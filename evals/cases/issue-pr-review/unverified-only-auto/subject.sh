#!/usr/bin/env bash
# pr-review stand-in: the merge floor under auto mode (issue #552).
#
# PR #9 passed review with `review.auto_merge: true`, but every acceptance
# criterion in its table is `unverified`. Under auto mode (`--auto`,
# IDD_AUTO_MODE=1) the *Merge floor* in SKILL.md Step 7 holds the PR open: the
# floor is `met` only when the criteria check is enabled, at least one
# criterion is `pass` and none is `unverified`, deferred rows on a `Refs #N`
# PR excluded. An interactive run asks instead of deciding.
#
# Each decision is emitted as `floor-<scenario>-<decision>.txt`, so case.json
# asserts the whole table with `file-exists`: a floor that decides differently
# does not create the file the case expects. The gh call log proves the fixture
# PR was never merged.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"

export IDD_AUTO_MODE=1
gh auth status >/dev/null
gh pr view 9 --json number,title,body,state > "$EVAL_OUT/pr-view.json"

EVAL_OUT="$EVAL_OUT" python3 - <<'PY'
import json
import os
import re

out = os.environ["EVAL_OUT"]
with open(os.path.join(out, "pr-view.json"), encoding="utf-8") as fh:
    pr = json.load(fh)
assert pr["state"] == "OPEN", pr["state"]
with open(os.path.join(out, "pr-body.md"), "w", encoding="utf-8") as fh:
    fh.write(pr["body"])

ROW = re.compile(r"^\|\s*(?P<crit>[^|]+?)\s*\|\s*(?P<status>pass|fail|unverified)\s*\|\s*(?P<evidence>[^|]*?)\s*\|\s*$")


def criteria(body):
    """pass/fail/unverified counts from the AC table, deferred rows excluded.

    A deferred row (Status `unverified`, Evidence containing `deferred`) is
    excluded only on a PR whose first line is `Refs #N` (verification-checks.md,
    *Intentional reference*); anywhere else it is an ordinary `unverified`.
    """
    refs = body.splitlines()[0].startswith("Refs #")
    counts = {"pass": 0, "fail": 0, "unverified": 0}
    for line in body.splitlines():
        m = ROW.match(line)
        if not m:
            continue
        if refs and m["status"] == "unverified" and "deferred" in m["evidence"].lower():
            continue
        counts[m["status"]] += 1
    return counts


def merge_floor(counts, ac_check_enabled):
    """SKILL.md Step 7 *Merge floor*: `met`, or `unmet: {reason}`."""
    if not ac_check_enabled:
        return "unmet: acceptance-criteria check disabled"
    if counts["unverified"]:
        return f"unmet: {counts['unverified']} criteria unverified"
    if not counts["pass"]:
        return "unmet: no criterion passed"
    return "met"


def decide(floor, auto):
    """Auto never merges below the floor; interactive asks the maintainer."""
    if floor == "met":
        return "merged"
    return "left_open" if auto else "ask"


def table(*rows, first="Closes #42"):
    head = "| Criterion | Status | Evidence |\n|-----------|--------|----------|\n"
    return first + "\n\n## Acceptance Criteria Verification\n\n" + head + "".join(
        f"| {c} | {s} | {e} |\n" for c, s, e in rows
    )


fixture = criteria(pr["body"])
assert fixture == {"pass": 0, "fail": 0, "unverified": 2}, fixture

# scenario, body counts, ac_check_enabled, auto
SCENARIOS = [
    # The fixture PR read from GitHub: every criterion unverified.
    ("auto-all-unverified", fixture, True, True),
    ("auto-no-criteria", criteria(table()), True, True),
    ("auto-pass-and-unverified",
     criteria(table(("A", "pass", "t.sh"), ("B", "unverified", "manual"))), True, True),
    # `review.require_acceptance_criteria_check: false` refuses the merge even
    # with every criterion passing.
    ("auto-check-disabled", criteria(table(("A", "pass", "t.sh"))), False, True),
    ("auto-all-pass",
     criteria(table(("A", "pass", "t.sh"), ("B", "pass", "u.sh"))), True, True),
    # A `Refs #N` PR: the deferred row is excluded, the delivered one passes.
    ("auto-refs-deferred",
     criteria(table(("A", "pass", "t.sh"), ("B", "unverified", "deferred to #43"),
                    first="Refs #42")), True, True),
    # The same deferred-looking row on a `Closes` PR is an ordinary unverified.
    ("auto-closes-deferred-text",
     criteria(table(("A", "pass", "t.sh"), ("B", "unverified", "deferred to #43"))), True, True),
    # An interactive run shows the result and lets the maintainer decide.
    ("interactive-all-unverified", fixture, True, False),
]

decisions = {}
for name, counts, enabled, auto in SCENARIOS:
    floor = merge_floor(counts, enabled)
    decision = decide(floor, auto)
    decisions[name] = {"criteria": counts, "merge_floor": floor, "decision": decision}
    with open(os.path.join(out, f"floor-{name}-{decision}.txt"), "w", encoding="utf-8") as fh:
        fh.write(f"criteria={counts} ac_check_enabled={enabled} auto={auto} "
                 f"merge_floor={floor} -> {decision}\n")

with open(os.path.join(out, "floor-decisions.json"), "w", encoding="utf-8") as fh:
    json.dump(decisions, fh, indent=2, sort_keys=True)
    fh.write("\n")

# Review contract (references/report-templates.md, *Auto-Merge*): the fixture
# PR passed review, the floor is unmet, so the merge block reports it left open.
floor = decisions["auto-all-unverified"]["merge_floor"]
reason = floor.split(": ", 1)[1]
report = (
    f"Result: PASS — PR #{pr['number']} left open; merge floor unmet ({reason})\n"
    f"Evidence: PR #{pr['number']} read (state {pr['state']}); merge floor: {floor}\n"
    f"Merge: ○ not attempted (merge floor unmet: {reason})\n"
    f"Uncertainty: {fixture['unverified']} acceptance criteria unverified; "
    "tests and CI not run by this stand-in\n"
    "Decision: No approval needed.\n"
    f"Next action: verify the criteria, then merge PR #{pr['number']} yourself\n"
)
lines = report.splitlines()
assert lines[0].startswith("Result: PASS") and "left open" in lines[0], lines[0]
assert "ready to merge" not in report and "MERGED" not in report
for label in ("Evidence: ", "Uncertainty: ", "Decision: ", "Next action: "):
    assert sum(line.startswith(label) for line in lines) == 1, label
with open(os.path.join(out, "report.txt"), "w", encoding="utf-8") as fh:
    fh.write(report)

print("  ○ floor decisions: " + ", ".join(f"{k}={v['decision']}" for k, v in sorted(decisions.items())))
PY
