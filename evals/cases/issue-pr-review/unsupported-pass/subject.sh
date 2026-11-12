#!/usr/bin/env bash
# pr-review stand-in: a PR body claims a pass the diff does not support (#555).
#
# PR #9's Acceptance Criteria Verification table claims `pass` for both of
# issue #42's criteria. The diff fixes the redirect loop and tests it, but adds
# nothing for rate limiting. /issue-pr-review must not take the table's word:
#
#   1. the criteria judge is bound from the issue and the diff only — nothing
#      from the PR title or body reaches it (verification-checks.md,
#      *Acceptance-criteria verification*);
#   2. its verdicts go through the real gi-criteria.py, which keeps the test
#      that ran green at head and downgrades the pass resting on a description;
#   3. the downgraded criterion is `unverified`, so the *Merge floor* is unmet
#      and an auto run leaves the PR open.
#
# The judge's verdicts are a committed fixture (judge-verdicts.json): this case
# tests the isolation of its inputs and the deterministic rule, not the model.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"
: "${EVAL_SCRIPTS_DIR:?EVAL_SCRIPTS_DIR is required}"
: "${EVAL_CASE_DIR:?EVAL_CASE_DIR is required}"

export IDD_AUTO_MODE=1
gh auth status >/dev/null
gh pr view 9 --json number,title,body,state,headRefOid > "$EVAL_OUT/pr-view.json"
gh issue view 42 --json number,title,body,labels > "$EVAL_OUT/issue.json"
gh pr diff 9 > "$EVAL_OUT/pr.diff"

EVAL_OUT="$EVAL_OUT" EVAL_SCRIPTS_DIR="$EVAL_SCRIPTS_DIR" EVAL_CASE_DIR="$EVAL_CASE_DIR" python3 - <<'PY'
import json
import os
import re
import subprocess

out = os.environ["EVAL_OUT"]
script = os.path.join(os.environ["EVAL_SCRIPTS_DIR"], "gi-criteria.py")


def load(name):
    with open(os.path.join(out, name), encoding="utf-8") as fh:
        return json.load(fh)


def write(name, text):
    with open(os.path.join(out, name), "w", encoding="utf-8") as fh:
        fh.write(text)


pr = load("pr-view.json")
issue = load("issue.json")
assert pr["state"] == "OPEN", pr["state"]
write("pr-body.md", pr["body"])

# The PR body claims every criterion passed.
claimed = re.findall(r"^\|[^|]+\|\s*(pass|fail|unverified)\s*\|", pr["body"], re.M)
assert claimed == ["pass", "pass"], claimed

# 1. Bind the judge from the issue and the diff only.
section = issue["body"].split("## Acceptance Criteria", 1)[1].split("\n## ", 1)[0]
criteria = [m.strip() for m in re.findall(r"^- \[[ x]\] (.+)$", section, re.M)]
assert len(criteria) == 2, criteria
numbered = "\n".join(f"{n}. {c}" for n, c in enumerate(criteria, start=1))
bindings = {
    "issue_context": f"Issue #{issue['number']}: {issue['title']}\n\n{issue['body']}\n\n"
                     f"Acceptance criteria:\n{numbered}",
    "diff_command": "gh pr diff 9",
    "head_sha": pr["headRefOid"],
    "branch_name": "fix/42-mobile-auth",
    "base_branch": "main",
}
write("judge-bindings.json", json.dumps(bindings, indent=2) + "\n")
blob = json.dumps(bindings)
leaks = [s for s in ("Decision Record", "Acceptance Criteria Verification",
                     "cookie now SameSite=None", pr["title"]) if s in blob]
assert not leaks, f"PR text reached the judge: {leaks}"
write("judge-isolated.txt", "judge bindings carry the issue, the diff command and the head only\n")

# 2. Hold each pass to its evidence with the real script.
with open(os.path.join(os.environ["EVAL_CASE_DIR"], "judge-verdicts.json"), encoding="utf-8") as fh:
    verdicts = json.load(fh)
record = {"head": pr["headRefOid"], "criteria": criteria, "deferred": [], "verdicts": verdicts}
run = subprocess.run(["python3", script], input=json.dumps(record), capture_output=True,
                     text=True, check=True)
result = json.loads(run.stdout)
write("criteria.json", json.dumps(result, indent=2) + "\n")
rows = result["rows"]
assert [r["status"] for r in rows] == ["pass", "unverified"], rows
assert rows[1]["downgraded"] and result["downgraded"] == 1, result
write("criterion-1-pass.txt", rows[0]["evidence"] + "\n")
write("criterion-2-downgraded.txt", rows[1]["evidence"] + "\n")

# 3. The *Merge floor* (SKILL.md Step 7) reads the downgraded table.
counts = result["counts"]
if counts["unverified"]:
    floor = f"unmet: {counts['unverified']} criteria unverified"
elif not counts["pass"]:
    floor = "unmet: no criterion passed"
else:
    floor = "met"
decision = "merged" if floor == "met" else "left_open"
write(f"floor-{decision}.txt", f"counts={counts} merge_floor={floor} -> {decision}\n")

reason = floor.split(": ", 1)[1]
report = (
    f"Result: PASS — PR #{pr['number']} left open; merge floor unmet ({reason})\n"
    f"Evidence: criteria judged in isolation at {pr['headRefOid'][:7]}; "
    f"1 pass downgraded ({rows[1]['evidence']}); merge floor: {floor}\n"
    f"Merge: ○ not attempted (merge floor unmet: {reason})\n"
    "Uncertainty: the PR body claimed both criteria passed; criterion 2 has no "
    "re-runnable evidence\n"
    "Decision: No approval needed.\n"
    f"Next action: show criterion 2 at head, then merge PR #{pr['number']} yourself\n"
)
assert "ready to merge" not in report and "MERGED" not in report
write("report.txt", report)
print(f"  ○ criteria: {[r['status'] for r in rows]}; merge floor {floor} -> {decision}")
PY
