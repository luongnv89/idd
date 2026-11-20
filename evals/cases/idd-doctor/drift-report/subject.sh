#!/usr/bin/env bash
# idd-doctor stand-in (drift-report): the four gating checks on a fixture
# repository with drift, run read-only.
#
# Check 1 finds one positive "predicts affected files" claim in the creator's
# SKILL text and must not flag the README's negated "does not scan the
# codebase" line. Check 2 scans two clean templates. Check 3 must fail: the
# only `mode:` under `autopilot:` is commented out. Check 4 reads the two
# merge-strategy settings and warns, because the configured `merge` method is
# not one the repository allows. Expected: `Result: FAIL (4 checks, 2 failed,
# 1 warned)`, three read-only gh calls, and a working tree left exactly as found.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"

# The fixture is copied without history: make it the git repository the
# doctor's prerequisite requires, and record the tree it must leave unchanged.
git init -q -b main
git add -A
git -c user.name=idd-eval -c user.email=idd-eval@example.invalid -c commit.gpgsign=false \
  commit -q -m "fixture"
git remote add origin https://github.com/eval/idd-fixture.git
git rev-parse --git-dir >/dev/null
BEFORE="$(git ls-files -s; git status --porcelain=v1 --untracked-files=all)"

# Check 4's two reads, gated on gh being authenticated.
gh auth status >/dev/null
REMOTE="$(git remote get-url origin)"
SLUG="${REMOTE#https://github.com/}"
SLUG="${SLUG%.git}"
gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed > "$EVAL_OUT/strategy.json"
gh api "repos/$SLUG" --jq '{squash_merge_commit_message, merge_commit_message}' > "$EVAL_OUT/message-source.json"

OUT="$EVAL_OUT" python3 - <<'PY'
import glob
import json
import os
import re

out = os.environ["OUT"]
findings = []


def touch(name, text=""):
    with open(os.path.join(out, name), "w", encoding="utf-8") as fh:
        fh.write(text + "\n")


def record(check, path, number, pattern, line):
    findings.append({"check": check, "path": path, "line": number, "pattern": pattern, "snippet": line.strip()})
    touch(f"finding-{check}-{path.replace('/', '-')}-L{number}.txt", f"{path}:{number} {pattern}")


# Check 1 — stale skill claims, with the per-line negation guard.
CLAIMS = ["scans the codebase", "scan the codebase", "predicts affected files",
          "predict affected files", "predicted affected files", "generates implementation notes",
          "generate implementation notes", "generated implementation notes",
          "generates technical notes", "generated technical notes", "generates root cause",
          "provides root cause", "generates implementation hints", "provides implementation hints"]
NEGATION = re.compile(r"\b(no|not|never|does not|doesn't|without|cannot|won't)\b", re.I)
check1_files = ["src/skills/issue-creator/docs/README.md", "src/skills/issue-creator/SKILL.source.md"]
for path in check1_files:
    if not os.path.isfile(path):
        record(1, path, 0, "not found", "")
        continue
    for number, line in enumerate(open(path, encoding="utf-8"), 1):
        low = line.lower()
        for pattern in CLAIMS:
            if pattern in low and not NEGATION.search(line):
                record(1, path, number, pattern, line)

# Check 2 — issue-template fields, substring match, no negation guard.
LABELS = ["affected files", "predicted affected files", "technical notes", "root cause",
          "implementation hints", "implementation notes", "architecture constraints"]
templates = sorted(glob.glob("src/skills/issue-creator/templates/*.md"))
for ext in ("md", "yml", "yaml"):
    templates += sorted(glob.glob(f".github/ISSUE_TEMPLATE/*.{ext}"))
for path in templates:
    for number, line in enumerate(open(path, encoding="utf-8"), 1):
        for pattern in LABELS:
            if pattern in line.lower():
                record(2, path, number, pattern, line)

# Check 3 — autopilot.mode, read as text: a `mode:` line inside the block.
config = open(".idd.yml", encoding="utf-8").read() if os.path.isfile(".idd.yml") else None
block, in_block = [], False
for line in (config or "").splitlines():
    if line.startswith("autopilot:"):
        in_block = True
        continue
    if re.match(r"[^\s#]", line):
        in_block = False
    if in_block:
        block.append(line)
mode = next((m.group(1) for l in block if (m := re.match(r"\s+mode:\s*([^#\s]+)", l))), None)
check3 = "skip" if config is None else ("pass" if mode else "fail")

# Check 4 — merge method against the repository's allowed strategies.
method = "squash"
review = re.search(r"(?ms)^review:\n(.*?)(?=^\S|\Z)", config or "")
if review and (m := re.search(r"(?m)^\s+merge_method:\s*(\S+)", review.group(1))):
    method = m.group(1)
strategy = json.load(open(os.path.join(out, "strategy.json"), encoding="utf-8"))
allowed = {"squash": strategy["squashMergeAllowed"], "merge": strategy["mergeCommitAllowed"]}
check4 = "pass" if method != "rebase" and allowed.get(method) else "warn"

check1 = "fail" if any(f["check"] == 1 for f in findings) else "pass"
check2 = "fail" if any(f["check"] == 2 for f in findings) else "pass"
for number, status in ((1, check1), (2, check2), (3, check3), (4, check4)):
    touch(f"check{number}-{status}.txt")
outcomes = [check1, check2, check3, check4]
failed, warned = outcomes.count("fail"), outcomes.count("warn")
result = "FAIL" if failed else ("WARN" if warned else "PASS")
symbol = {"pass": "✓", "fail": "✗", "warn": "⚠", "skip": "○"}
names = ["Stale skill claims", "Issue-template fields", "Autopilot mode", "Merge method"]
lines = ["  ◆ /idd-doctor — health check", "  " + "┄" * 66, ""]
for number, (name, status) in enumerate(zip(names, outcomes), 1):
    lines.append(f"    {symbol[status]} [{number}/4] {name}")
    for f in findings:
        if f["check"] == number:
            lines += [f"        {f['path']}:{f['line']}", f"        pattern: {f['pattern']}",
                      f"        line:    {f['snippet']}"]
    if number == 4 and status == "warn":
        lines.append(f"        review.merge_method = {method}; the repository does not allow it")
lines += [
    "    " + "┄" * 66,
    f"    Result: {result}  (4 checks, {failed} failed, {warned} warned)",
    f"    Evidence:    ran 1 2 3 4 · scanned {len(check1_files)} skill files, {len(templates)} templates",
    "    Uncertainty: checks 1-3 are text heuristics",
    "    Decision:    No approval needed — report-only, nothing changed. Next: apply the fix hints, then re-run /idd-doctor",
]
with open(os.path.join(out, "report.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
with open(os.path.join(out, "findings.json"), "w", encoding="utf-8") as fh:
    json.dump(findings, fh, indent=2)
# A wrapper greps the Result: line; its first word after `Result:` is the status.
status_line = next(l for l in lines if l.strip().startswith("Result:"))
touch(f"result-{status_line.split()[1].lower()}.txt", status_line.strip())
PY

# Read-only guarantee: index and working tree exactly as found.
AFTER="$(git ls-files -s; git status --porcelain=v1 --untracked-files=all)"
if [ "$BEFORE" = "$AFTER" ]; then
  : > "$EVAL_OUT/tree-unchanged.txt"
fi
