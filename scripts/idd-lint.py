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
  idd-lint stats  [--branch REF] [--no-github] [--json]
                                        evidence report: trace-completeness,
                                        Decision-Record coverage, run outcomes

FILE of `-` (or omitted) reads stdin. `--level L1|L2|L3` (default L3) selects
the conformance level to enforce; checks above the selected level are skipped.
Exit codes: 0 = conformant (warnings allowed), 1 = errors found, 2 = usage.
`stats` is a report, not a gate — it exits 0 unless the data is unreadable.

CI example (GitHub Actions):

  gh pr view "$PR" --json body -q .body \\
    | python3 scripts/idd-lint.py pr - --title "$(gh pr view "$PR" --json title -q .title)"
  python3 scripts/idd-lint.py repo --base origin/main
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
import subprocess
import sys
from pathlib import Path

SPEC_VERSION = "1.0"
SPEC_URL = "https://github.com/luongnv89/idd/blob/main/SPEC.md"

MARKER_RE = re.compile(r"<!--\s*gitissue:normalized\s+v(\d+)\s*-->")
SECTION_RE = re.compile(r"^## +(.+?)\s*$")
CONFIDENCE_RE = re.compile(r"\((?:high|medium) confidence\)|\(needs review\)")
CHECKBOX_RE = re.compile(r"^\s*[-*] \[[ xX]\] \S", re.MULTILINE)
DEP_MARKER_RE = re.compile(r"\b(?:depends on|blocked by):?\s*(#\d+(?:\s*,\s*#\d+)*)", re.IGNORECASE)

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

    # I08 — dependency markers (informational, §2)
    deps: list[str] = []
    for m in DEP_MARKER_RE.finditer(body):
        deps.extend(re.findall(r"#\d+", m.group(1)))
    if deps:
        findings.append(info("I08", f"dependency markers found: {', '.join(deps)} (§2)"))

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


def _pct(n: int, d: int) -> int | None:
    return round(100 * n / d) if d else None


def _median(values: list) -> float | None:
    return statistics.median(values) if values else None


def detect_default_branch() -> str:
    out = _run_soft(["git", "rev-parse", "--abbrev-ref", "origin/HEAD"])
    if out and "/" in out.strip():
        return out.strip().split("/", 1)[1]
    for cand in ("main", "master"):
        if _run_soft(["git", "rev-parse", "--verify", "--quiet", cand]) is not None:
            return cand
    return "HEAD"


def collect_commit_stats(branch: str, since: str | None) -> dict | None:
    """Trace-completeness and Decision-Record coverage from local git history."""
    cmd = ["git", "log", "--no-merges", "--format=%s%x1f%b%x1e", branch]
    if since:
        cmd.insert(2, f"--since={since}")
    out = _run_soft(cmd)
    if out is None:
        return None
    records = [r for r in out.split("\x1e") if r.strip()]
    total, grammar, issue_ref, squash, dr = len(records), 0, 0, 0, 0
    for rec in records:
        subject, _, body = rec.partition("\x1f")
        subject = subject.strip()
        if COMMIT_RE.match(subject):
            grammar += 1
        if re.search(r"\(#\d+\)", subject):
            issue_ref += 1
        if re.search(r"^Closes #\d+", body, re.MULTILINE):
            squash += 1
            if "## Decision Record" in body:
                dr += 1
    return {
        "branch": branch,
        "commits": total,
        "grammar_ok": grammar,
        "grammar_pct": _pct(grammar, total),
        "issue_linked": issue_ref,
        "trace_pct": _pct(issue_ref, total),
        "squash_pr_commits": squash,
        "decision_records": dr,
        "dr_pct": _pct(dr, squash),
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


def collect_github_stats(limit: int, run_rows_path: Path) -> dict | None:
    """Optional gh-backed metrics: %% issues normalized, merged-PR linkage,
    and run outcomes tiered by issue quality (normalized vs not)."""
    open_issues = _gh_json("issue", "list", "--state", "open", "--limit", str(limit), "--json", "number,body")
    if open_issues is None:
        return None  # gh missing, unauthenticated, or offline — skip the whole section
    normalized_open = sum(1 for i in open_issues if MARKER_RE.search(i.get("body") or ""))

    result: dict = {
        "open_issues": len(open_issues),
        "open_normalized": normalized_open,
        "open_normalized_pct": _pct(normalized_open, len(open_issues)),
    }

    merged = _gh_json("pr", "list", "--state", "merged", "--limit", str(limit), "--json", "number,body")
    if merged is not None:
        closes = sum(1 for p in merged if re.search(r"^Closes #\d+", p.get("body") or "", re.MULTILINE))
        dr = sum(1 for p in merged if "## Decision Record" in (p.get("body") or ""))
        result.update({
            "merged_prs": len(merged),
            "merged_with_closes": closes,
            "merged_closes_pct": _pct(closes, len(merged)),
            "merged_with_dr": dr,
            "merged_dr_pct": _pct(dr, len(merged)),
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


def _fmt_ratio(pct: int | None, n: int, d: int) -> str:
    return f"{pct}% ({n}/{d})" if pct is not None else f"n/a (0 of {d})"


def render_stats(commit_s: dict | None, run_s: dict | None, gh_s: dict | None, gh_skipped: str | None) -> None:
    print(f"◆ idd-lint stats — evidence report (IDD Spec v{SPEC_VERSION})")
    print("┄" * 59)

    if commit_s is None:
        print("  ○ git history: not a git repository — skipped")
    else:
        print(f"  Git history — {commit_s['branch']}, {commit_s['commits']} non-merge commits")
        print(f"    conventional grammar:    {_fmt_ratio(commit_s['grammar_pct'], commit_s['grammar_ok'], commit_s['commits'])} (§3.2)")
        print(f"    issue-linked commits:    {_fmt_ratio(commit_s['trace_pct'], commit_s['issue_linked'], commit_s['commits'])} — trace completeness (§5.1)")
        if commit_s["squash_pr_commits"]:
            print(f"    Decision-Record coverage: {_fmt_ratio(commit_s['dr_pct'], commit_s['decision_records'], commit_s['squash_pr_commits'])} of squash-merged PR commits (§4)")
        else:
            print("    ○ no squash-merged PR commits found (no 'Closes #N' bodies) — Decision-Record coverage n/a (§4)")

    if run_s is None:
        print("  ○ run log: .gitissue/runs.jsonl not found or empty — skipped")
    else:
        print(f"  Run log — .gitissue/runs.jsonl, {run_s['runs']} run{'s' if run_s['runs'] != 1 else ''}")
        print(f"    outcomes: {' · '.join(f'{k} {v}' for k, v in run_s['outcomes'].items())}")
        if run_s["attempted"]:
            print(f"    success rate (attempted): {_fmt_ratio(run_s['success_pct'], run_s['succeeded'], run_s['attempted'])}")
        if run_s["median_qa_cycles"] is not None:
            dur = f" · median duration: {round(run_s['median_duration_s'])}s" if run_s["median_duration_s"] is not None else ""
            print(f"    median QA cycles: {run_s['median_qa_cycles']:g}{dur}")
        if run_s["by_complexity"]:
            parts = [
                f"{lvl} {v['runs']}" + (f" (median QA {v['median_qa']:g})" if v["median_qa"] is not None else "")
                for lvl, v in run_s["by_complexity"].items()
            ]
            print(f"    by complexity: {' · '.join(parts)}")

    if gh_s is None:
        print(f"  ○ GitHub: {gh_skipped or 'gh unavailable'} — skipped (local metrics above are unaffected)")
    else:
        print("  GitHub — via gh")
        print(f"    open issues normalized:  {_fmt_ratio(gh_s['open_normalized_pct'], gh_s['open_normalized'], gh_s['open_issues'])} (§1.1)")
        if "merged_prs" in gh_s:
            print(f"    merged PRs w/ Closes #N: {_fmt_ratio(gh_s['merged_closes_pct'], gh_s['merged_with_closes'], gh_s['merged_prs'])} (§5.1)")
            print(f"    merged PRs w/ Decision Record: {_fmt_ratio(gh_s['merged_dr_pct'], gh_s['merged_with_dr'], gh_s['merged_prs'])} (§4.1)")
        tiers = gh_s.get("tiers")
        if tiers:
            print("  Issue quality → resolution outcome")
            for name, t in tiers.items():
                qa = f", median QA {t['median_qa']:g}" if t["median_qa"] is not None else ""
                print(f"    {name:<13} n={t['runs']}, success {t['success_pct']}%{qa}")
            saved = gh_s.get("qa_cycles_saved")
            if saved is not None and saved > 0:
                print(f"    ⚡ normalized issues resolve in {saved:g} fewer QA cycle{'s' if saved != 1 else ''} (median)")

    print("┄" * 59)


def cmd_stats(args: argparse.Namespace) -> int:
    root_out = _run_soft(["git", "rev-parse", "--show-toplevel"])
    root = Path(root_out.strip()) if root_out else Path.cwd()
    runs_path = root / ".gitissue" / "runs.jsonl"

    branch = args.branch or detect_default_branch()
    commit_s = collect_commit_stats(branch, args.since)
    run_s = collect_run_stats(runs_path)
    gh_s, gh_skipped = None, None
    if args.no_github:
        gh_skipped = "--no-github"
    else:
        gh_s = collect_github_stats(args.limit, runs_path)
        if gh_s is None:
            gh_skipped = "gh unavailable, unauthenticated, or offline"

    if args.json:
        print(json.dumps(
            {"spec_version": SPEC_VERSION, "git": commit_s, "runs": run_s, "github": gh_s},
            indent=2, sort_keys=True,
        ))
        return 0

    render_stats(commit_s, run_s, gh_s, gh_skipped)
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
    p_stats.add_argument("--since", help="limit git history, e.g. '6 months ago'")
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
