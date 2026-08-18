#!/usr/bin/env python3
"""idd-lint — IDD Spec conformance checker. No LLM, no network, no dependencies.

Validates Issue-Driven Development artifacts against the IDD Spec
(https://github.com/luongnv89/idd/blob/main/SPEC.md) from plain data:

  idd-lint issue  [FILE|-]              lint an issue body           (L1, §1–§2)
  idd-lint branch NAME                  lint a branch name           (L2, §3.1)
  idd-lint commit MSG [MSG ...]         lint commit message(s)       (L2, §3.2)
  idd-lint commit --range A..B          lint a git commit range      (L2, §3.2)
  idd-lint pr     [FILE|-] [--title T] [--type bug|...]
                                        lint a PR body (+ title)     (L2 §5, L3 §4)
  idd-lint repo   [--base REF]          lint current branch + commits vs base
  idd-lint stats  [--branch REF] [--since DATE] [--no-github] [--json]
                                        evidence report: trace-completeness,
                                        Decision-Record coverage, run outcomes

FILE of `-` (or omitted) reads stdin. `--level L1|L2|L3` (default L3) selects
the conformance level to enforce; checks above the selected level are skipped.
Exit codes: 0 = conformant (warnings allowed), 1 = errors found, 2 = usage.
`stats` is a report, not a gate — it exits 0 unless the data is unreadable.
`--since` accepts any git approxidate. Prefer an unambiguous absolute form —
`--since '2026-08-15 00:00:00'`. A bare `YYYY-MM-DD` is normalized to midnight
before it reaches git, because git otherwise fills the time of day from the
current wall clock and the window silently shifts with the hour you run it.
git reads that date in the *local* zone while a PR's `mergedAt` is UTC, so a PR
merged at `2026-08-14T23:00Z` is inside a `2026-08-15` window in UTC+2.

CI example (GitHub Actions):

  gh pr view "$PR" --json body -q .body \\
    | python3 scripts/idd-lint.py pr - --title "$(gh pr view "$PR" --json title -q .title)"
  python3 scripts/idd-lint.py repo --base origin/main
"""

from __future__ import annotations

import argparse
import json
import os
import re
import statistics
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

SPEC_VERSION = "1.1"
SPEC_URL = "https://github.com/luongnv89/idd/blob/main/SPEC.md"

MARKER_RE = re.compile(r"<!--\s*gitissue:normalized\s+v(\d+)\s*-->")
SECTION_RE = re.compile(r"^## +(.+?)\s*$")
CONFIDENCE_RE = re.compile(r"\((?:high|medium) confidence\)|\(needs review\)")
CHECKBOX_RE = re.compile(r"^\s*[-*] \[[ xX]\] \S", re.MULTILINE)
DEP_MARKER_RE = re.compile(r"(?i)\b(?:depends on|blocked by)\b")
CROSS_REPO_TOKEN_RE = re.compile(r"\S+/\S+#\d+")
BARE_ISSUE_RE = re.compile(r"(?<![\w/])#(\d+)")
PART_MARKER_RE = re.compile(r"\bpart of:?\s*(#\d+)", re.IGNORECASE)

ISSUE_TYPES = ("bug", "feature", "improvement")
BRANCH_TYPES = ("fix", "feat", "refactor", "docs", "test", "chore")
COMMIT_TYPES = ("feat", "fix", "refactor", "docs", "test", "chore", "style", "perf")

BRANCH_RE = re.compile(r"^(fix|feat|refactor|docs|test|chore)/(\d+)((?:-[a-z0-9]+)+)$")
BRANCH_EXEMPT_RE = re.compile(r"^(hotfix|release)/[a-z0-9][a-z0-9.-]*$")
COMMIT_RE = re.compile(
    r"^(feat|fix|refactor|docs|test|chore|style|perf)"  # type
    r"(?:\(([a-z0-9._-]+)\))?"                          # optional scope
    r": (.+?) \(#(\d+)\)$"                              # description + issue ref
)

DR_HEADING = "## Decision Record"
BARE_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
# Approxidate spellings that legitimately resolve to *now*, so a resolved
# timestamp of ~now from one of these is an answer, not a parse failure.
NOW_TOKENS = {"now", "today", "@now"}
ADR_NO_BACKFILL = "docs/decisions/no-backfill-merged-decision-records.md"

DR_FIELDS = ("Root cause", "Options considered", "Options rejected", "Selected option", "Residual risk")
AC_STATUSES = ("pass", "fail", "unverified")
NO_AC_NOTE_RE = re.compile(r"no acceptance criteria defined", re.IGNORECASE)

LEVELS = ("L1", "L2", "L3")


class Finding:
    def __init__(self, severity: str, code: str, message: str) -> None:
        self.severity = severity  # "error" | "warn" | "info" | "ok"
        self.code = code
        self.message = message


def ok(code, msg):
    return Finding("ok", code, msg)


def err(code, msg):
    return Finding("error", code, msg)


def warn(code, msg):
    return Finding("warn", code, msg)


def info(code, msg):
    return Finding("info", code, msg)


# --- Parsing helpers ----------------------------------------------------------


def split_sections(text: str) -> dict[str, str]:
    """Split a markdown body into {heading: content} on `## ` headings.
    Content before the first heading is stored under ''. First heading wins
    on duplicates."""
    sections: dict[str, str] = {}
    current = ""
    buf: list[str] = []
    for line in text.splitlines():
        m = SECTION_RE.match(line)
        if m:
            if current not in sections:
                sections[current] = "\n".join(buf)
            current = m.group(1)
            buf = []
        else:
            buf.append(line)
    if current not in sections:
        sections[current] = "\n".join(buf)
    return sections


def strip_confidence(value: str) -> str:
    return CONFIDENCE_RE.sub("", value).strip()


def first_content_line(text: str) -> str:
    for line in text.splitlines():
        if line.strip():
            return line.strip()
    return ""


# --- Issue checks (L1, §1–§2) ---------------------------------------------------


def lint_issue(body: str) -> list[Finding]:
    findings: list[Finding] = []
    sections = split_sections(body)

    # I01 — normalization marker (§1.1.1)
    m = MARKER_RE.search(body)
    if not m:
        findings.append(err("I01", "normalization marker '<!-- gitissue:normalized v1 -->' missing (§1.1)"))
    else:
        first_line = first_content_line(body)
        if not MARKER_RE.search(first_line):
            findings.append(warn("I01", "normalization marker present but not on the first line (§1.1)"))
        else:
            findings.append(ok("I01", f"normalization marker present (v{m.group(1)}) (§1.1)"))

    # I02 — ## Type with a known value (§1.1.2)
    issue_type = None
    if "Type" not in sections:
        findings.append(err("I02", "missing '## Type' section (§1.1)"))
    else:
        raw = strip_confidence(first_content_line(sections["Type"]))
        issue_type = raw.lower()
        if issue_type in ISSUE_TYPES:
            findings.append(ok("I02", f"type is '{raw}' (§1.1)"))
        elif raw:
            findings.append(warn("I02", f"type '{raw}' is not one of Bug/Feature/Improvement — allowed only as a documented implementation extension (§1.1)"))
        else:
            findings.append(err("I02", "'## Type' section is empty (§1.1)"))

    # I03 — ## Description (§1.1.3)
    if "Description" not in sections:
        findings.append(err("I03", "missing '## Description' section (§1.1)"))
    else:
        findings.append(ok("I03", "description section present (§1.1)"))

    # I04 — type-specific fields (§1.1.3)
    required_fields = {
        "bug": ("**Current behavior:**", "**Expected behavior:**"),
        "improvement": ("**Current state:**", "**Proposed change:**"),
    }.get(issue_type or "", ())
    for field in required_fields:
        if field in body:
            findings.append(ok("I04", f"{field} present (§1.1)"))
        else:
            findings.append(err("I04", f"{issue_type} issue missing required field {field} (§1.1)"))

    # I05 — Reporter Context blockquote (§1.1.4; SHOULD when authored directly)
    if "> **Reporter Context**" in body:
        findings.append(ok("I05", "Reporter Context blockquote present (§1.1)"))
    else:
        findings.append(warn("I05", "no '> **Reporter Context**' blockquote — required when normalizing, recommended always (§1.1)"))

    # I06 — ## Acceptance Criteria with >=1 checkbox (§1.1.6)
    if "Acceptance Criteria" not in sections:
        findings.append(err("I06", "missing '## Acceptance Criteria' section (§1.1)"))
    elif not CHECKBOX_RE.search(sections["Acceptance Criteria"]):
        findings.append(err("I06", "'## Acceptance Criteria' has no '- [ ]' checkbox items (§1.1)"))
    else:
        n = len(CHECKBOX_RE.findall(sections["Acceptance Criteria"]))
        findings.append(ok("I06", f"acceptance criteria present ({n} checkbox{'es' if n != 1 else ''}) (§1.1)"))

    # I07 — ## Metadata with Priority/Effort/Labels (§1.1.7)
    if "Metadata" not in sections:
        findings.append(err("I07", "missing '## Metadata' section (§1.1)"))
    else:
        for label in ("**Priority:**", "**Effort:**", "**Labels:**"):
            if label in sections["Metadata"]:
                findings.append(ok("I07", f"metadata field {label} present (§1.1)"))
            else:
                findings.append(err("I07", f"metadata missing {label} line (§1.1)"))

    # I08 — dependency markers (informational, §2; cross-repo ignored)
    deps: list[str] = []
    seen_dep: set[str] = set()
    for line in body.splitlines():
        if not DEP_MARKER_RE.search(line):
            continue
        local_segment = CROSS_REPO_TOKEN_RE.sub("", line)
        for m in BARE_ISSUE_RE.finditer(local_segment):
            ref = f"#{m.group(1)}"
            if ref not in seen_dep:
                seen_dep.add(ref)
                deps.append(ref)
    if deps:
        findings.append(info("I08", f"dependency markers found: {', '.join(deps)} (§2)"))

    # I09 — hierarchy marker (informational, §2.1)
    parents = [m.group(1) for m in PART_MARKER_RE.finditer(body)]
    if parents:
        findings.append(info("I09", f"hierarchy marker: Part of {', '.join(parents)} (§2.1)"))

    return findings


# --- Branch checks (L2, §3.1) ---------------------------------------------------


def lint_branch(name: str) -> list[Finding]:
    findings: list[Finding] = []
    if BRANCH_EXEMPT_RE.match(name):
        findings.append(ok("B01", f"'{name}' is a workflow-driven hotfix/release branch — issue number optional (§3.1)"))
    elif BRANCH_RE.match(name):
        findings.append(ok("B01", f"'{name}' matches <type>/<issue>-<description> (§3.1)"))
    else:
        findings.append(err("B01", f"'{name}' does not match <type>/<issue-number>-<short-description> with type in {'/'.join(BRANCH_TYPES)} — lowercase, hyphen-separated (§3.1)"))
    if len(name) > 50:
        findings.append(warn("B02", f"branch name is {len(name)} chars — should stay under 50 (§3.1)"))
    return findings


# --- Commit checks (L2, §3.2) ---------------------------------------------------


def lint_commit(subject: str) -> list[Finding]:
    findings: list[Finding] = []
    subject = subject.strip().splitlines()[0] if subject.strip() else ""
    label = subject if len(subject) <= 60 else subject[:57] + "..."

    if subject.startswith(("Merge ", "Revert ")):
        findings.append(info("C01", f"'{label}' — merge/revert commit, skipped (§3.2)"))
        return findings

    m = COMMIT_RE.match(subject)
    if not m:
        findings.append(err("C01", f"'{label}' does not match <type>(<scope>): <description> (#N) with type in {'/'.join(COMMIT_TYPES)} (§3.2)"))
        return findings

    ctype, scope, desc, issue = m.groups()
    findings.append(ok("C01", f"'{label}' matches the commit grammar (type={ctype}, issue=#{issue}) (§3.2)"))
    if desc and desc[0].isupper():
        findings.append(err("C02", f"'{label}' — description must be lowercase (§3.2)"))
    if desc.rstrip().endswith("."):
        findings.append(err("C03", f"'{label}' — description must not end with a period (§3.2)"))
    if len(subject) > 72:
        findings.append(warn("C04", f"'{label}' — first line is {len(subject)} chars, keep under 72 (§3.2)"))
    if not scope:
        findings.append(info("C05", f"'{label}' — no scope; scope is optional but recommended (§3.2)"))
    return findings


# --- PR checks (L2 §3.3+§5, L3 §4) ------------------------------------------------


def lint_pr(body: str, title: str | None, issue_type: str | None, level: str) -> list[Finding]:
    findings: list[Finding] = []
    sections = split_sections(body)

    # P01 (L2) — title follows the commit grammar (§3.3)
    pr_is_fix = False
    if title is None:
        findings.append(info("P01", "no --title given — PR title check skipped (§3.3)"))
    else:
        m = COMMIT_RE.match(title.strip())
        if m:
            pr_is_fix = m.group(1) == "fix"
            findings.append(ok("P01", f"title matches <type>(<scope>): <description> (#N) (§3.3)"))
        else:
            findings.append(err("P01", f"title '{title}' does not match <type>(<scope>): <description> (#N) (§3.3)"))

    # P02 (L2) — first body line is `Closes #N` (§3.3, §5.1)
    first = first_content_line(body)
    if re.match(r"^Closes #\d+$", first):
        findings.append(ok("P02", f"body first line is '{first}' (§5.1)"))
    else:
        findings.append(err("P02", "body must start with 'Closes #N' on its first line (§3.3, §5.1)"))

    # P03 (L2) — Acceptance Criteria Verification table (§5.2)
    acv = sections.get("Acceptance Criteria Verification")
    if acv is None:
        if NO_AC_NOTE_RE.search(body):
            findings.append(ok("P03", "explicit no-acceptance-criteria note present (§5.2)"))
        else:
            findings.append(err("P03", "missing '## Acceptance Criteria Verification' table (or explicit no-criteria note) (§5.2)"))
    else:
        rows = [
            [c.strip() for c in line.strip().strip("|").split("|")]
            for line in acv.splitlines()
            if line.strip().startswith("|") and "---" not in line
        ]
        data_rows = [r for r in rows[1:] if len(r) >= 3] if rows else []
        if not data_rows:
            if NO_AC_NOTE_RE.search(acv):
                findings.append(ok("P03", "explicit no-acceptance-criteria note present (§5.2)"))
            else:
                findings.append(err("P03", "'## Acceptance Criteria Verification' has no data rows (§5.2)"))
        else:
            bad = [r for r in data_rows if r[1].lower() not in AC_STATUSES]
            no_evidence = [r for r in data_rows if len(r) < 3 or not r[2]]
            if bad:
                findings.append(err("P03", f"AC verification rows with status outside pass/fail/unverified: {len(bad)} (§5.2)"))
            elif no_evidence:
                findings.append(err("P03", f"AC verification rows without evidence: {len(no_evidence)} (§5.2)"))
            else:
                findings.append(ok("P03", f"AC verification table valid ({len(data_rows)} row{'s' if len(data_rows) != 1 else ''}) (§5.2)"))

    if level in ("L1", "L2"):
        return findings

    # P04 (L3) — Decision Record fields (§4.1)
    dr = sections.get("Decision Record")
    if dr is None:
        findings.append(err("P04", "missing '## Decision Record' section (§4.1)"))
    else:
        for field in DR_FIELDS:
            if f"**{field}:**" in dr:
                findings.append(ok("P04", f"Decision Record field **{field}:** present (§4.1)"))
            else:
                findings.append(err("P04", f"Decision Record missing **{field}:** (§4.1 — labels are string-matched, do not rename)"))

        # P05 (L3) — Reproduction required for bug issues (§4.1)
        is_bug = (issue_type or "").lower() == "bug" or (issue_type is None and pr_is_fix)
        if is_bug:
            if "**Reproduction:**" in dr:
                findings.append(ok("P05", "Reproduction evidence present for bug fix (§4.1)"))
            else:
                findings.append(err("P05", "bug fix without **Reproduction:** field in the Decision Record (§4.1)"))

        # P06 (L3) — Analyzed at line (§4.1, SHOULD)
        if re.search(r"^Analyzed at:", dr, re.MULTILINE):
            findings.append(ok("P06", "'Analyzed at:' line present (§4.1)"))
        else:
            findings.append(warn("P06", "no 'Analyzed at: `<branch> @ <sha>` (<date>)' line (§4.1, SHOULD)"))

    return findings


# --- Git helpers (repo / --range modes) -----------------------------------------


def git(*args: str) -> str:
    proc = subprocess.run(["git", *args], capture_output=True, text=True)
    if proc.returncode != 0:
        print(f"✗ git {' '.join(args)}: {proc.stderr.strip()}", file=sys.stderr)
        sys.exit(2)
    return proc.stdout


def commit_subjects(rev_range: str) -> list[str]:
    out = git("log", "--no-merges", "--format=%s", rev_range)
    return [line for line in out.splitlines() if line.strip()]


# --- Stats (evidence report) -----------------------------------------------------

SUCCESS_OUTCOMES = {"success", "merged"}
SKIP_OUTCOMES = {"skipped", "already_resolved"}


def _run_soft(cmd: list[str]) -> str | None:
    """Run a command, returning stdout or None on any failure (soft probe)."""
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        return None
    return proc.stdout if proc.returncode == 0 else None


def _gh_json(*args: str) -> object | None:
    out = _run_soft(["gh", *args])
    if out is None:
        return None
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        return None


def normalize_since(since: str | None) -> str | None:
    """Pin a bare `YYYY-MM-DD` to midnight.

    Git's approxidate parser fills an unstated time of day from the *current*
    wall clock, so `--since 2026-08-15` means "2026-08-15 at whatever o'clock it
    is now" and the same command returns different windows through the day.
    Anything else (an explicit time, `6 months ago`, a ref-ish date) is passed
    through untouched — git owns that grammar.
    """
    if since is None:
        return None
    stripped = since.strip()
    return f"{stripped} 00:00:00" if BARE_DATE_RE.match(stripped) else since


def _since_epoch(since: str | None) -> tuple[int | None, str | None]:
    """Resolve a git approxidate to a Unix timestamp via `git rev-parse --since=`.

    Using git itself keeps the PR-side `mergedAt` filter and the git-side
    `--since` window on exactly one date grammar.

    Returns `(epoch, error)`. `error` is None when no window was asked for or
    the window resolved; otherwise it is the reason the window could not be
    applied. The two must stay distinguishable: a window that was requested and
    failed to resolve is not the same report as one that was never requested,
    and rendering them alike advises the reader to do what they just did.

    git's approxidate never rejects input — `--since=garbage-typo` silently
    resolves to *now*, which yields an empty window and a green report built
    from nothing. Anything landing within a couple of seconds of now, from a
    string that is not itself a now-token, is read as a parse failure.
    """
    if not since:
        return None, None
    out = _run_soft(["git", "rev-parse", f"--since={since}"])
    m = re.search(r"--max-age=(\d+)", out) if out else None
    if not m:
        return None, "could not be resolved (not a git repository?)"
    epoch = int(m.group(1))
    now = int(datetime.now(timezone.utc).timestamp())
    if since.strip().lower() not in NOW_TOKENS and abs(now - epoch) <= 2:
        return None, "did not parse as a date"
    return epoch, None


def _merged_at_epoch(value: object) -> int | None:
    """`2026-08-14T19:33:53Z` → Unix timestamp; None when unparsable."""
    if not isinstance(value, str):
        return None
    try:
        dt = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        return None
    return int(dt.replace(tzinfo=timezone.utc).timestamp())


def _pct(n: int, d: int) -> int | None:
    return round(100 * n / d) if d else None


def _median(values: list) -> float | None:
    return statistics.median(values) if values else None


def _repo_name_from_remote() -> str | None:
    """Derive owner/repo from the git origin URL (works offline, no gh)."""
    url = _run_soft(["git", "config", "--get", "remote.origin.url"])
    if not url:
        return None
    url = url.strip().removesuffix(".git")
    # git@host:owner/repo  or  https://host/owner/repo  or  ssh://host/owner/repo
    m = re.search(r"[:/]([^/:]+/[^/:]+)$", url)
    return m.group(1) if m else None


def collect_project_info(root: Path, use_github: bool = True) -> dict:
    """Identify the project being analyzed: filesystem location and a name.

    Name preference: GitHub nameWithOwner (via gh, only when use_github) → origin
    remote owner/repo → the checkout's directory basename. Never fails — a name
    is always produced, and offline mode makes no network call.
    """
    name = None
    if use_github:
        gh = _gh_json("repo", "view", "--json", "nameWithOwner")
        if isinstance(gh, dict):
            name = gh.get("nameWithOwner") or None
    if not name:
        name = _repo_name_from_remote()
    if not name:
        name = root.name
    return {"name": name, "location": str(root)}


def detect_default_branch() -> str:
    out = _run_soft(["git", "rev-parse", "--abbrev-ref", "origin/HEAD"])
    if out and "/" in out.strip():
        return out.strip().split("/", 1)[1]
    for cand in ("main", "master"):
        if _run_soft(["git", "rev-parse", "--verify", "--quiet", cand]) is not None:
            return cand
    return "HEAD"


def collect_commit_stats(branch: str, since: str | None) -> dict | None:
    """Trace-completeness and Decision-Record coverage from local git history.

    The Decision-Record denominator is every **PR-derived** commit: one whose
    subject carries a `(#N)` reference *or* whose body opens with `Closes #N`.
    Keying it on `Closes #N` alone — as this did before #180 — silently drops
    the failures out of the sample: a squash landed under GitHub's default
    `squash_merge_commit_message=COMMIT_MESSAGES` carries a bullet list of
    commit subjects and no `Closes #N`, so exactly the commits that *lost* their
    Decision Record at the merge boundary left the denominator instead of
    counting as misses, and the ratio measured the survivors against themselves.

    This is a local proxy, not the verdict: a `(#N)` subject with no `Closes`
    body may be a direct-to-main commit rather than a defeated merge. The
    authoritative measurement is the per-PR join in `collect_dr_binding`.

    `--no-merges` is deliberate. `grammar_pct` and `trace_pct` are claims about
    *authored* commits; folding merge commits in would corrupt both.
    """
    cmd = ["git", "log", "--no-merges", "--format=%s%x1f%b%x1e", branch]
    if since:
        cmd.insert(2, f"--since={since}")
    out = _run_soft(cmd)
    if out is None:
        return None
    records = [r for r in out.split("\x1e") if r.strip()]
    total, grammar = len(records), 0
    subject_ref = closes_body = both = pr_derived = dr = 0
    for rec in records:
        subject, _, body = rec.partition("\x1f")
        subject = subject.strip()
        if COMMIT_RE.match(subject):
            grammar += 1
        has_subject_ref = bool(re.search(r"\(#\d+\)", subject))
        has_closes = bool(re.search(r"^Closes #\d+", body, re.MULTILINE))
        subject_ref += has_subject_ref
        closes_body += has_closes
        both += has_subject_ref and has_closes
        if has_subject_ref or has_closes:
            pr_derived += 1
            if DR_HEADING in body:
                dr += 1
    return {
        "branch": branch,
        "commits": total,
        "grammar_ok": grammar,
        "grammar_pct": _pct(grammar, total),
        "issue_linked": subject_ref,
        "trace_pct": _pct(subject_ref, total),
        "subject_ref_commits": subject_ref,
        "closes_body_commits": closes_body,
        "subject_and_closes_commits": both,
        "pr_derived_commits": pr_derived,
        "decision_records": dr,
        "dr_pct": _pct(dr, pr_derived),
    }


def collect_run_stats(path: Path) -> dict | None:
    """Outcome/QA/duration aggregates from the append-only run log."""
    if not path.is_file():
        return None
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(row, dict):
            rows.append(row)
    if not rows:
        return None
    outcomes: dict[str, int] = {}
    for r in rows:
        o = str(r.get("outcome", "unknown"))
        outcomes[o] = outcomes.get(o, 0) + 1
    attempted = [r for r in rows if r.get("outcome") not in SKIP_OUTCOMES]
    succeeded = [r for r in attempted if r.get("outcome") in SUCCESS_OUTCOMES]
    qa = [r["qa_cycles"] for r in rows if isinstance(r.get("qa_cycles"), int)]
    dur = [r["duration_s"] for r in rows if isinstance(r.get("duration_s"), (int, float))]
    by_complexity: dict[str, dict] = {}
    for level in ("low", "medium", "high"):
        sub = [r for r in rows if r.get("complexity") == level]
        if sub:
            sub_qa = [r["qa_cycles"] for r in sub if isinstance(r.get("qa_cycles"), int)]
            by_complexity[level] = {"runs": len(sub), "median_qa": _median(sub_qa)}
    return {
        "runs": len(rows),
        "outcomes": dict(sorted(outcomes.items())),
        "attempted": len(attempted),
        "succeeded": len(succeeded),
        "success_pct": _pct(len(succeeded), len(attempted)),
        "median_qa_cycles": _median(qa),
        "median_duration_s": _median(dur),
        "by_complexity": by_complexity,
        "issues": sorted({r["issue"] for r in rows if isinstance(r.get("issue"), int)}),
    }


def classify_merge_commit(oid: str | None) -> str:
    """Did the Decision Record survive the merge? — one PR, one landing commit.

    Returns exactly one of:
      `no_sha`        the PR reports no merge commit (unmerged, or squashed away
                      by a platform that did not report an oid)
      `not_in_clone`  the oid is real to GitHub but absent from this checkout
                      (shallow clone, unfetched branch) — unknown, not a miss
      `landed`        the landing commit's message carries the Decision Record
      `lost`          it does not — SPEC §4.3 binding B1 was defeated at merge

    Never raises and never exits: `_run_soft` swallows the non-zero `git log`
    that an unknown oid produces, which is why this must not use `git()`.
    """
    if not oid:
        return "no_sha"
    body = _run_soft(["git", "log", "-1", "--format=%B", oid])
    if body is None:
        return "not_in_clone"
    return "landed" if DR_HEADING in body else "lost"


def collect_dr_binding(merged: list, limit: int, since: str | None) -> dict:
    """Join each merged PR to its own landing commit to measure SPEC §4.3 B1.

    The local git-side ratio can only guess which commits came from a PR. This
    joins the two sides directly — PR body → `mergeCommit.oid` → commit message
    — so `dr_lost` is a count of Decision Records demonstrably dropped at the
    merge boundary rather than an inference from message shape.

    Lifetime numbers are informational by design: this repo's B1 binding was
    only repaired on 2026-08-15 and
    `docs/decisions/no-backfill-merged-decision-records.md` accepts the
    historical gap. A `--since` window is what makes a loss actionable.
    """
    with_dr = [p for p in merged if DR_HEADING in ((p or {}).get("body") or "")]
    counts = {"no_sha": 0, "not_in_clone": 0, "landed": 0, "lost": 0}
    verdict_by_pr: dict = {}
    for pr in with_dr:
        mc = pr.get("mergeCommit")
        oid = mc.get("oid") if isinstance(mc, dict) else None
        verdict = classify_merge_commit(oid)
        counts[verdict] += 1
        # Keyed on the PR number, not `id(pr)`: identity is only stable while
        # this exact list of dicts is alive, and a future refactor that copies
        # or re-parses a PR would silently miss every lookup.
        verdict_by_pr[pr["number"]] = verdict

    resolved = counts["landed"] + counts["lost"]
    binding = {
        "prs_with_dr": len(with_dr),
        "merge_commit_resolved": resolved,
        "unresolved_no_sha": counts["no_sha"],
        "unresolved_not_in_clone": counts["not_in_clone"],
        "dr_landed": counts["landed"],
        "dr_lost": counts["lost"],
        "landed_pct": _pct(counts["landed"], resolved),
        # `gh pr list --limit N` returns the newest N. A client-side window over
        # a capped page under-reports without saying so, so say so.
        "truncated": len(merged) == limit,
        "window": None,
        "adr": ADR_NO_BACKFILL,
    }

    if since:
        # `gh pr list` has no merged-date flag, so the window is applied here.
        cutoff, error = _since_epoch(since)
        if cutoff is None:
            # Say so in the document, not only on the terminal: the caller most
            # likely to be misled is a JSON consumer gating on `dr_lost > 0`,
            # and an absent window is indistinguishable from a clean one.
            binding["window_error"] = {"since": since, "reason": error}
        else:
            in_window = [
                p for p in with_dr
                if (_merged_at_epoch(p.get("mergedAt")) or -1) >= cutoff
            ]
            # Same buckets and the same key names as the lifetime numbers above,
            # so the denominator is `landed + lost` on both sides. Counting the
            # unresolved PRs as misses would render `✗ 0%` from unknown data —
            # in a shallow clone every oid is `not_in_clone`.
            w = {v: [p for p in in_window if verdict_by_pr[p["number"]] == v] for v in counts}
            binding["window"] = {
                "since": since,
                "prs_with_dr": len(in_window),
                "merge_commit_resolved": len(w["landed"]) + len(w["lost"]),
                "unresolved_no_sha": len(w["no_sha"]),
                "unresolved_not_in_clone": len(w["not_in_clone"]),
                "dr_landed": len(w["landed"]),
                "dr_lost": len(w["lost"]),
            }
    return binding


def collect_github_stats(limit: int, run_rows_path: Path, since: str | None = None) -> dict | None:
    """Optional gh-backed metrics: %% issues normalized, merged-PR linkage,
    the SPEC §4.3 B1 durable-memory join, and run outcomes tiered by issue
    quality (normalized vs not)."""
    open_issues = _gh_json("issue", "list", "--state", "open", "--limit", str(limit), "--json", "number,body")
    if open_issues is None:
        return None  # gh missing, unauthenticated, or offline — skip the whole section
    normalized_open = sum(1 for i in open_issues if MARKER_RE.search(i.get("body") or ""))

    result: dict = {
        "open_issues": len(open_issues),
        "open_normalized": normalized_open,
        "open_normalized_pct": _pct(normalized_open, len(open_issues)),
    }

    # One page, three metrics: `truncated` below is only meaningful because
    # merged_prs, merged_with_dr and dr_binding all read the same fetch.
    merged = _gh_json(
        "pr", "list", "--state", "merged", "--limit", str(limit),
        "--json", "number,body,mergedAt,mergeCommit",
    )
    if merged is not None:
        closes = sum(1 for p in merged if re.search(r"^Closes #\d+", p.get("body") or "", re.MULTILINE))
        dr = sum(1 for p in merged if DR_HEADING in (p.get("body") or ""))
        result.update({
            "merged_prs": len(merged),
            "merged_with_closes": closes,
            "merged_closes_pct": _pct(closes, len(merged)),
            "merged_with_dr": dr,
            "merged_dr_pct": _pct(dr, len(merged)),
            "dr_binding": collect_dr_binding(merged, limit, since),
        })

    # Tier run outcomes by issue quality (normalized vs unnormalized issue body).
    runs = collect_run_stats(run_rows_path)
    if runs and runs["issues"]:
        all_issues = _gh_json(
            "issue", "list", "--state", "all",
            "--limit", str(max(limit, 500)), "--json", "number,body",
        )
        if all_issues is not None:
            marker_by_issue = {i["number"]: bool(MARKER_RE.search(i.get("body") or "")) for i in all_issues}
            rows = []
            for line in run_rows_path.read_text(encoding="utf-8").splitlines():
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(row, dict) and row.get("outcome") not in SKIP_OUTCOMES:
                    rows.append(row)
            tiers: dict[str, dict] = {}
            for name, wanted in (("normalized", True), ("unnormalized", False)):
                sub = [r for r in rows if marker_by_issue.get(r.get("issue")) is wanted]
                if sub:
                    sub_qa = [r["qa_cycles"] for r in sub if isinstance(r.get("qa_cycles"), int)]
                    won = sum(1 for r in sub if r.get("outcome") in SUCCESS_OUTCOMES)
                    tiers[name] = {
                        "runs": len(sub),
                        "success_pct": _pct(won, len(sub)),
                        "median_qa": _median(sub_qa),
                    }
            if tiers:
                result["tiers"] = tiers
                norm, unnorm = tiers.get("normalized"), tiers.get("unnormalized")
                if norm and unnorm and norm["median_qa"] is not None and unnorm["median_qa"] is not None:
                    result["qa_cycles_saved"] = unnorm["median_qa"] - norm["median_qa"]
    return result


# Report layout (DESIGN.md: symbols carry meaning without color; dim = secondary;
# max width 80). Ratio rows share one rail: verdict symbol, label, 10-cell meter,
# right-aligned percentage, counts, dim spec citation.

_LABEL_W = 28
_METER_W = 10

_ANSI = {"bold": "1", "dim": "2", "red": "31", "green": "32", "yellow": "33", "cyan": "36"}
_COLOR = sys.stdout.isatty() and not os.environ.get("NO_COLOR") and os.environ.get("TERM") != "dumb"


def _c(text: str, *styles: str) -> str:
    if not _COLOR or not styles:
        return text
    codes = ";".join(_ANSI[s] for s in styles)
    return f"\x1b[{codes}m{text}\x1b[0m"


def _verdict(pct: int) -> tuple[str, str]:
    if pct >= 80:
        return "✓", "green"
    if pct >= 40:
        return "⚠", "yellow"
    return "✗", "red"


def _meter(pct: int) -> str:
    filled = min(_METER_W, round(pct / 100 * _METER_W))
    return "█" * filled + "░" * (_METER_W - filled)


def _ratio_row(label: str, n: int, d: int, cite: str = "") -> str:
    """`  ✓ label……………………  ██████████  100%    1/1   §4` — pad before coloring."""
    pct = _pct(n, d)
    counts = f"{n}/{d}" if d else "—"
    tail = f"  {_c(cite, 'dim')}" if cite else ""
    if pct is None:
        return (f"    {_c('○', 'dim')} {label:<{_LABEL_W}}"
                f" {_c('░' * _METER_W, 'dim')}     {_c('—', 'dim')}  {counts:>7}{tail}")
    sym, tone = _verdict(pct)
    return (f"    {_c(sym, tone)} {label:<{_LABEL_W}}"
            f" {_c(_meter(pct), tone)}  {_c(f'{pct:>3}%', tone, 'bold')}  {counts:>7}{tail}")


def _info_row(label: str, value: str) -> str:
    return f"      {label:<{_LABEL_W}} {value}"


def _section(title: str, context: str = "") -> str:
    head = f"  {_c(title, 'bold')}"
    return f"{head} {_c('— ' + context, 'dim')}" if context else head


def _render_dr_binding(b: dict | None) -> list[str]:
    """The §4.3 B1 headline: did each merged PR's Decision Record reach git?

    A *lifetime* shortfall renders `○` informational, never `⚠`. This repo's
    binding was defeated by a repo setting until 2026-08-15 and
    `docs/decisions/no-backfill-merged-decision-records.md` accepts that history
    as final; a permanent warning over a decided-and-closed gap is noise that
    trains readers to ignore the row. Only an explicit `--since` window — where
    a loss means the binding is being defeated *now* — escalates to `⚠`.
    """
    if not b:
        return []
    lines: list[str] = []
    resolved, landed, lost = b["merge_commit_resolved"], b["dr_landed"], b["dr_lost"]
    win = b.get("window")

    if win:
        # Denominator is `landed + lost`, exactly as the lifetime row computes
        # it. `prs_with_dr` would fold the unresolved PRs in as misses and paint
        # a red `✗ 0%` directly above the caveat line saying they are excluded.
        # At a zero denominator `_ratio_row` falls to its `○ … —` branch, which
        # is the intended reading: unknown, not a miss.
        lines.append(_ratio_row("DR landed in git (window)", win["dr_landed"],
                                win["merge_commit_resolved"], "§4.3"))
        lines.append(_c(f"      window — merged since {win['since']}", "dim"))
        if win["dr_lost"]:
            n = win["dr_lost"]
            lines.append(
                f"    {_c('⚠', 'yellow')} {n} merged PR{'s' if n != 1 else ''} "
                f"in this window lost the Decision Record at merge"
            )
            lines.append(_c("      binding B1 is being defeated (§4.3)", "yellow"))
    else:
        counts = f"{landed}/{resolved}" if resolved else "—"
        lines.append(
            f"    {_c('○', 'dim')} {'DR landed in git (lifetime)':<{_LABEL_W}}"
            f" {_c('░' * _METER_W, 'dim')}     {_c('—', 'dim')}  {counts:>7}  {_c('§4.3', 'dim')}"
        )
        lines.append(_c("      lifetime shortfall is a recorded decision, not a regression", "dim"))
        # The ADR path gets its own line: it is a URL-shaped token, and the
        # joined form ran to 121 columns against this report's 80-column rail.
        lines.append(_c(f"      {b['adr']}", "dim"))
        we = b.get("window_error")
        if we:
            # A window was asked for and could not be applied. Saying nothing
            # here would print the "run with --since" hint below, advising the
            # reader to do the thing they just did.
            lines.append(f"    {_c('⚠', 'yellow')} --since {we['since']!r} {we['reason']}")
            lines.append(_c("      window not applied — this is the lifetime row", "dim"))
        else:
            lines.append(_c("      run with --since to judge the binding as it stands today", "dim"))

    if lost and not win:
        lines.append(_c(f"      {lost} of {b['prs_with_dr']} PRs with a Decision Record lost it at merge", "dim"))
    # Read the caveat from whichever population the row above counted, or the
    # printed numbers describe a different set of PRs than the ratio does.
    src = win or b
    unresolved = src["unresolved_no_sha"] + src["unresolved_not_in_clone"]
    if unresolved:
        lines.append(_c(
            f"      {unresolved} unresolved ({src['unresolved_no_sha']} no merge sha, "
            f"{src['unresolved_not_in_clone']} not in this clone)", "dim"))
        lines.append(_c("      excluded from the ratio, not counted as misses", "dim"))
    if b["truncated"]:
        # No symbol: in this report ⚠ is a verdict glyph carrying a tone, and
        # this is a scope caveat on a continuation line, not a verdict.
        lines.append(_c("      PR page hit --limit — older merges are not in this sample", "dim"))
    return lines


def render_stats(commit_s: dict | None, run_s: dict | None, gh_s: dict | None, gh_skipped: str | None, project: dict | None = None) -> None:
    out: list[str] = []
    out.append(f"◆ idd-lint stats {_c('— evidence report · IDD Spec v' + SPEC_VERSION, 'dim')}")
    if project:
        out.append(f"  {_c('project', 'bold')}  {project['name']}")
        out.append(_c(f"  location {project['location']}", "dim"))
    out.append(_c("┄" * 59, "dim"))
    out.append("")

    if commit_s is None:
        out.append(_c("  ○ git history — skipped: not a git repository", "dim"))
    else:
        n = commit_s["commits"]
        out.append(_section("Git history", f"{commit_s['branch']} · {n} non-merge commit{'s' if n != 1 else ''}"))
        out.append(_ratio_row("conventional grammar", commit_s["grammar_ok"], n, "§3.2"))
        out.append(_ratio_row("trace completeness", commit_s["issue_linked"], n, "§5.1"))
        if commit_s["pr_derived_commits"]:
            out.append(_ratio_row("DR coverage (local proxy)", commit_s["decision_records"], commit_s["pr_derived_commits"], "§4"))
            out.append(_c("      proxy — subject (#N) or `Closes #N` body; the GitHub join is authoritative", "dim"))
        else:
            out.append(_c("      DR coverage (local proxy) — no PR-derived commits on this branch (§4)", "dim"))

    out.append("")
    if run_s is None:
        out.append(_c("  ○ run log — skipped: .gitissue/runs.jsonl not found or empty", "dim"))
    else:
        out.append(_section("Run log", f".gitissue/runs.jsonl · {run_s['runs']} run{'s' if run_s['runs'] != 1 else ''}"))
        out.append(_info_row("outcomes", " · ".join(f"{k} {v}" for k, v in run_s["outcomes"].items())))
        if run_s["attempted"]:
            out.append(_ratio_row("success rate", run_s["succeeded"], run_s["attempted"]))
        if run_s["median_qa_cycles"] is not None:
            out.append(_info_row("median QA cycles", f"{run_s['median_qa_cycles']:g}"))
        if run_s["median_duration_s"] is not None:
            out.append(_info_row("median duration", f"{round(run_s['median_duration_s'])}s"))
        if run_s["by_complexity"]:
            parts = [
                f"{lvl} {v['runs']}" + (f" (median QA {v['median_qa']:g})" if v["median_qa"] is not None else "")
                for lvl, v in run_s["by_complexity"].items()
            ]
            out.append(_info_row("complexity mix", " · ".join(parts)))

    out.append("")
    if gh_s is None:
        out.append(_c(f"  ○ GitHub — skipped: {gh_skipped or 'gh unavailable'} (local metrics unaffected)", "dim"))
    else:
        out.append(_section("GitHub", "via gh"))
        out.append(_ratio_row("open issues normalized", gh_s["open_normalized"], gh_s["open_issues"], "§1.1"))
        if "merged_prs" in gh_s:
            out.append(_ratio_row("merged PRs · Closes #N", gh_s["merged_with_closes"], gh_s["merged_prs"], "§5.1"))
            out.append(_ratio_row("merged PRs · Decision Record", gh_s["merged_with_dr"], gh_s["merged_prs"], "§4.1"))
        out.extend(_render_dr_binding(gh_s.get("dr_binding")))
        tiers = gh_s.get("tiers")
        if tiers:
            out.append("")
            out.append(_section("Issue quality → outcome", "runs joined with issue bodies"))
            for name, t in tiers.items():
                qa = f" · median QA {t['median_qa']:g}" if t["median_qa"] is not None else ""
                out.append(_info_row(name, f"n={t['runs']} · success {t['success_pct']}%{qa}"))
            saved = gh_s.get("qa_cycles_saved")
            if saved is not None and saved > 0:
                cycles = f"{saved:g} fewer QA cycle{'s' if saved != 1 else ''}"
                out.append(f"    ⚡ normalized issues resolve in {_c(cycles, 'bold')} (median)")

    out.append("")
    out.append(_c("┄" * 59, "dim"))
    print("\n".join(out))


def cmd_stats(args: argparse.Namespace) -> int:
    root_out = _run_soft(["git", "rev-parse", "--show-toplevel"])
    root = Path(root_out.strip()) if root_out else Path.cwd()
    runs_path = root / ".gitissue" / "runs.jsonl"

    project = collect_project_info(root, use_github=not args.no_github)

    branch = args.branch or detect_default_branch()
    since = normalize_since(args.since)
    commit_s = collect_commit_stats(branch, since)
    run_s = collect_run_stats(runs_path)
    gh_s, gh_skipped = None, None
    if args.no_github:
        gh_skipped = "--no-github"
    else:
        gh_s = collect_github_stats(args.limit, runs_path, since)
        if gh_s is None:
            gh_skipped = "gh unavailable, unauthenticated, or offline"

    if args.json:
        print(json.dumps(
            {"spec_version": SPEC_VERSION, "project": project, "git": commit_s, "runs": run_s, "github": gh_s},
            indent=2, sort_keys=True,
        ))
        return 0

    render_stats(commit_s, run_s, gh_s, gh_skipped, project)
    return 0


# --- Rendering -----------------------------------------------------------------


SYMBOLS = {"ok": "✓", "error": "✗", "warn": "⚠", "info": "○"}


def render(findings: list[Finding], label: str, level: str, quiet: bool) -> int:
    errors = sum(1 for f in findings if f.severity == "error")
    warns = sum(1 for f in findings if f.severity == "warn")
    passed = sum(1 for f in findings if f.severity == "ok")

    print(f"◆ idd-lint — {label} (IDD Spec v{SPEC_VERSION}, level {level})")
    print("┄" * 59)
    for f in findings:
        if quiet and f.severity in ("ok", "info"):
            continue
        print(f"  {SYMBOLS[f.severity]} [{f.code}] {f.message}")
    print("┄" * 59)
    print(f"  Passed: {passed}   Warnings: {warns}   Errors: {errors}")
    if errors:
        print(f"  ✗ not conformant — see {SPEC_URL}")
        return 1
    print(f"  ✓ conformant at {level} (spec v{SPEC_VERSION})")
    return 0


def read_input(path: str | None) -> str:
    if path is None or path == "-":
        return sys.stdin.read()
    with open(path, encoding="utf-8") as fh:
        return fh.read()


# --- CLI -----------------------------------------------------------------------


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="idd-lint",
        description=f"IDD Spec v{SPEC_VERSION} conformance checker — plain data, no LLM. Spec: {SPEC_URL}",
    )
    parser.add_argument("--level", choices=LEVELS, default="L3", help="conformance level to enforce (default: L3)")
    parser.add_argument("--quiet", "-q", action="store_true", help="print only warnings and errors")
    sub = parser.add_subparsers(dest="kind", required=True)

    p_issue = sub.add_parser("issue", help="lint an issue body (L1)")
    p_issue.add_argument("file", nargs="?", help="markdown file, or - for stdin")

    p_branch = sub.add_parser("branch", help="lint a branch name (L2)")
    p_branch.add_argument("name")

    p_commit = sub.add_parser("commit", help="lint commit message(s) (L2)")
    p_commit.add_argument("messages", nargs="*", help="commit subject line(s)")
    p_commit.add_argument("--range", dest="rev_range", help="git rev range, e.g. origin/main..HEAD")

    p_pr = sub.add_parser("pr", help="lint a PR body and optional title (L2+L3)")
    p_pr.add_argument("file", nargs="?", help="markdown file, or - for stdin")
    p_pr.add_argument("--title", help="PR title to check against the naming grammar")
    p_pr.add_argument("--type", dest="issue_type", help="linked issue type (bug/feature/improvement); inferred from a fix() title when omitted")

    p_repo = sub.add_parser("repo", help="lint current branch name + commits vs --base (L2)")
    p_repo.add_argument("--base", default="main", help="base ref to diff commits against (default: main)")

    p_stats = sub.add_parser("stats", help="evidence report: trace-completeness, DR coverage, run outcomes")
    p_stats.add_argument("--branch", help="branch to analyze (default: detected default branch)")
    p_stats.add_argument(
        "--since",
        help="limit the window to commits/merges after DATE, e.g. '2026-08-15 00:00:00' "
             "or '6 months ago'; a bare YYYY-MM-DD is normalized to midnight so the "
             "window does not drift with the wall clock. DATE is read in the local "
             "timezone while a PR's mergedAt is UTC, so a PR merged 2026-08-14T23:00Z "
             "falls inside a 2026-08-15 window in UTC+2",
    )
    p_stats.add_argument("--limit", type=int, default=200, help="max issues/PRs fetched via gh (default: 200)")
    p_stats.add_argument("--no-github", action="store_true", help="skip gh-backed metrics (offline mode)")
    p_stats.add_argument("--json", action="store_true", help="emit machine-readable JSON instead of text")

    args = parser.parse_args(argv)

    if args.kind == "issue":
        findings = lint_issue(read_input(args.file))
        return render(findings, "issue body", "L1", args.quiet)

    if args.kind == "branch":
        return render(lint_branch(args.name), f"branch {args.name}", args.level if args.level != "L1" else "L2", args.quiet)

    if args.kind == "commit":
        subjects = list(args.messages)
        if args.rev_range:
            subjects.extend(commit_subjects(args.rev_range))
        if not subjects:
            print("✗ no commit messages given (pass MSG arguments or --range)", file=sys.stderr)
            return 2
        findings = [f for s in subjects for f in lint_commit(s)]
        return render(findings, f"{len(subjects)} commit(s)", "L2", args.quiet)

    if args.kind == "pr":
        findings = lint_pr(read_input(args.file), args.title, args.issue_type, args.level)
        return render(findings, "pull request", args.level, args.quiet)

    if args.kind == "stats":
        return cmd_stats(args)

    if args.kind == "repo":
        branch = git("rev-parse", "--abbrev-ref", "HEAD").strip()
        findings: list[Finding] = []
        if branch in ("main", "master", args.base.split("/")[-1]):
            findings.append(info("B01", f"on '{branch}' — branch name check skipped (§3.1)"))
        else:
            findings.extend(lint_branch(branch))
        subjects = commit_subjects(f"{args.base}..HEAD")
        if subjects:
            findings.extend(f for s in subjects for f in lint_commit(s))
        else:
            findings.append(info("C01", f"no commits in {args.base}..HEAD"))
        return render(findings, f"repo @ {branch}", "L2", args.quiet)

    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
