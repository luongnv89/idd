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

FILE of `-` (or omitted) reads stdin. `--level L1|L2|L3` (default L3) selects
the conformance level to enforce; checks above the selected level are skipped.
Exit codes: 0 = conformant (warnings allowed), 1 = errors found, 2 = usage.

CI example (GitHub Actions):

  gh pr view "$PR" --json body -q .body \\
    | python3 scripts/idd-lint.py pr - --title "$(gh pr view "$PR" --json title -q .title)"
  python3 scripts/idd-lint.py repo --base origin/main
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys

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
