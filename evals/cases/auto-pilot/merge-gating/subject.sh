#!/usr/bin/env bash
# auto-pilot stand-in: decide the merge gate for a PR under every documented
# mode / merge_partial / dependency combination.
#
# Encodes three rule sets that /auto-pilot states normatively:
#   1. Merge Modes matrix — conservative / balanced / aggressive x clean /
#      partial / critical (SKILL.source.md "Merge Modes").
#   2. Effective-mode resolution — `autopilot.mode` wins; absent mode with an
#      explicit legacy `autopilot.auto_merge` maps true -> aggressive +
#      merge_partial, false -> conservative; nothing set -> balanced.
#   3. Dependency gate — `Depends on` / `Blocked by` markers, cross-repo refs
#      stripped, gate satisfied only when the referenced issue is CLOSED and
#      every closing PR is MERGED.
#
# Each decision is emitted as `gate-<scenario>-<decision>.txt`, so case.json
# asserts the whole table with `file-exists`: a gate that decides differently
# does not create the file the case expects. The four distinct run-log outcomes
# are emitted as records and validated by gi-runlog.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"
: "${EVAL_CASSETTES:?EVAL_CASSETTES is required}"

gh auth status >/dev/null

# The blocked issue (#50 depends on the still-open #12), the cleared one (#51
# depends on the merged #40, plus a cross-repo ref that must be ignored), and
# the half-cleared one (#52 depends on #41, which is CLOSED but whose only
# closing PR was CLOSED unmerged — closing an issue by hand does not ship it).
gh issue view 50 --json number,title,body,labels,state > "$EVAL_OUT/issue-50.json"
gh issue view 51 --json number,title,body,labels,state > "$EVAL_OUT/issue-51.json"
gh issue view 52 --json number,title,body,labels,state > "$EVAL_OUT/issue-52.json"
gh issue view 12 --json number,state,closedByPullRequestsReferences > "$EVAL_OUT/issue-12.json"
gh issue view 40 --json number,state,closedByPullRequestsReferences > "$EVAL_OUT/issue-40.json"
gh issue view 41 --json number,state,closedByPullRequestsReferences > "$EVAL_OUT/issue-41.json"
gh pr view 101 --json number,title,body,state,mergeable > "$EVAL_OUT/pr-101.json"

EVAL_OUT="$EVAL_OUT" python3 - <<'PY'
import json
import os
import re

out = os.environ["EVAL_OUT"]

DEP_MARKER = re.compile(r"(?im)\b(?:depends\s+on|blocked\s+by)\b")
CROSS_REPO = re.compile(r"\S+/\S+#\d+")
LOCAL_REF = re.compile(r"(?<![\w/])#(\d+)")


def load(name):
    with open(os.path.join(out, name), encoding="utf-8") as fh:
        return json.load(fh)


def dep_numbers(body, self_number):
    """Local issue numbers the dependency markers name, in first-appearance order.

    Cross-repo tokens are stripped before local refs are captured. A body that
    references its own number carries no ordering information and is dropped —
    the documented cycle guard.
    """
    found = []
    for line in body.splitlines():
        if not DEP_MARKER.search(line):
            continue
        for ref in LOCAL_REF.findall(CROSS_REPO.sub("", line)):
            number = int(ref)
            if number != self_number and number not in found:
                found.append(number)
    return found


def dependency_satisfied(issue, blockers):
    """A blocker clears only when it is CLOSED and every closing PR is MERGED."""
    for number in blockers:
        blocker = issue.get(number)
        if blocker is None:  # a 404 reference is a typo, not a blocker
            continue
        if blocker["state"] != "CLOSED":
            return False
        refs = blocker.get("closedByPullRequestsReferences") or []
        if any(pr["state"] != "MERGED" for pr in refs):
            return False
    return True


def effective_mode(mode, merge_partial, auto_merge):
    """`autopilot.mode` is the source of truth; legacy auto_merge only fills in.

    `merge_partial` is honored solely under `aggressive`; under any other mode
    the field is ignored, which is what keeps a default install from ever
    merging a PR with unresolved fixable review issues.
    """
    if mode is not None:
        return mode, bool(merge_partial) and mode == "aggressive"
    if auto_merge is not None:
        return ("aggressive", True) if auto_merge else ("conservative", False)
    return "balanced", False


def gate(mode, merge_partial, auto_merge, review, deps_ok, critical, mergeable=True):
    """The merge decision, in the order the loop actually reaches each check.

    Review exhaustion on a critical issue stops the loop while reviewing, so it
    precedes every merge-time check and is identical across all three modes.
    Then the mode decides whether a merge is attempted at all; only if it is do
    the pre-merge conditions run — mergeability first, then the dependency gate.
    """
    resolved, partial_ok = effective_mode(mode, merge_partial, auto_merge)
    if review != "clean" and critical:
        return "stop"
    # `partial_ok` is the single place the "aggressive + merge_partial" rule
    # lives — re-testing the mode here would make that rule unobservable, so a
    # scenario that opts a non-aggressive mode into merge_partial could never
    # detect the rule being dropped.
    would_merge = (review == "clean" and resolved in ("balanced", "aggressive")) or (
        review != "clean" and partial_ok
    )
    if not would_merge:
        # The mode forbids this merge, so the merge step never runs.
        return "left_open"
    if not mergeable:
        # Conflicts or red CI: leave the PR open and continue the loop.
        return "left_open"
    if not deps_ok:
        # Never merge out of order — but never stop the run for it either.
        return "blocked_by_dependency"
    return "merged" if review == "clean" else "partial_followup"


blockers_index = {
    12: load("issue-12.json"),
    40: load("issue-40.json"),
    41: load("issue-41.json"),
}

issue_50 = load("issue-50.json")
issue_51 = load("issue-51.json")
issue_52 = load("issue-52.json")
deps_50 = dep_numbers(issue_50["body"], 50)
deps_51 = dep_numbers(issue_51["body"], 51)
deps_52 = dep_numbers(issue_52["body"], 52)
blocked_ok = dependency_satisfied(blockers_index, deps_50)
cleared_ok = dependency_satisfied(blockers_index, deps_51)
unmerged_ok = dependency_satisfied(blockers_index, deps_52)

assert deps_50 == [12], f"expected #50 to gate on #12, got {deps_50}"
assert deps_51 == [40], f"expected #51 to gate on #40 only, got {deps_51}"
assert deps_52 == [41], f"expected #52 to gate on #41, got {deps_52}"
assert blocked_ok is False, "#12 is still OPEN — the gate must not clear"
assert cleared_ok is True, "#40 is CLOSED with a MERGED PR — the gate must clear"
# Assert the fixture shape, not the verdict: #41 is CLOSED, so only the
# every-closing-PR-is-MERGED half of the rule can still hold this gate shut.
# The verdict itself is left to the graded artifact, so dropping that half of
# the rule fails the case rather than tripping an assertion here.
_blocker_41 = blockers_index[41]
assert _blocker_41["state"] == "CLOSED" and all(
    pr["state"] != "MERGED" for pr in _blocker_41["closedByPullRequestsReferences"]
), "fixture #41 must be CLOSED with no MERGED closing PR"

with open(os.path.join(out, "dependency-gate.json"), "w", encoding="utf-8") as fh:
    json.dump(
        {
            "issue_50": {"blockers": deps_50, "satisfied": blocked_ok},
            "issue_51": {"blockers": deps_51, "satisfied": cleared_ok},
            "issue_52": {"blockers": deps_52, "satisfied": unmerged_ok},
        },
        fh,
        indent=2,
    )
    fh.write("\n")

pr = load("pr-101.json")
# The PR under review is open and conflict-free; a scenario below flips this to
# prove that an unmergeable PR is left open rather than merged.
pr_mergeable = pr["state"] == "OPEN" and pr["mergeable"] == "MERGEABLE"
assert pr_mergeable is True, "fixture PR #101 must be mergeable"

# scenario, mode, merge_partial, auto_merge, review, deps_ok, critical, mergeable
SCENARIOS = [
    ("default-unset-clean", None, None, None, "clean", True, False, pr_mergeable),
    ("balanced-clean", "balanced", False, None, "clean", True, False, pr_mergeable),
    ("conservative-clean", "conservative", False, None, "clean", True, False, pr_mergeable),
    ("aggressive-clean", "aggressive", False, None, "clean", True, False, pr_mergeable),
    ("balanced-partial", "balanced", False, None, "partial", True, False, pr_mergeable),
    ("conservative-partial", "conservative", False, None, "partial", True, False, pr_mergeable),
    ("aggressive-partial-optout", "aggressive", False, None, "partial", True, False, pr_mergeable),
    ("aggressive-partial-optin", "aggressive", True, None, "partial", True, False, pr_mergeable),
    # `merge_partial` is honored solely under `aggressive`: opting a lesser mode
    # into it changes nothing, which is what keeps a default or conservative
    # install from ever merging a PR with unresolved fixable review issues.
    ("balanced-partial-optin", "balanced", True, None, "partial", True, False, pr_mergeable),
    ("conservative-partial-optin", "conservative", True, None, "partial", True, False, pr_mergeable),
    ("legacy-automerge-true-partial", None, None, True, "partial", True, False, pr_mergeable),
    ("legacy-automerge-false-clean", None, None, False, "clean", True, False, pr_mergeable),
    # `autopilot.mode` is the source of truth; a legacy auto_merge beside it is ignored.
    ("mode-wins-over-legacy", "conservative", False, True, "clean", True, False, pr_mergeable),
    ("dependency-open-blocks", "balanced", False, None, "clean", blocked_ok, False, pr_mergeable),
    ("dependency-merged-clears", "balanced", False, None, "clean", cleared_ok, False, pr_mergeable),
    # A blocker closed by hand — CLOSED, but its only closing PR was CLOSED
    # unmerged — has not shipped, so the gate stays shut.
    ("dependency-closed-unmerged-pr", "balanced", False, None, "clean", unmerged_ok, False, pr_mergeable),
    # Conflicts or red CI outrank a clean review and a cleared dependency gate.
    ("unmergeable-pr-stays-open", "balanced", False, None, "clean", True, False, False),
    # The critical stop is scoped to an exhausted review: a critical issue whose
    # PR reviews clean merges like any other.
    ("critical-clean-merges", "balanced", False, None, "clean", True, True, pr_mergeable),
    # Critical handling is unchanged across all three modes.
    ("critical-partial-stops", "balanced", False, None, "partial", True, True, pr_mergeable),
    ("critical-partial-conservative-stops", "conservative", False, None, "partial", True, True, pr_mergeable),
    ("critical-partial-aggressive-stops", "aggressive", True, None, "partial", True, True, pr_mergeable),
    ("critical-partial-blocked-stops", "balanced", False, None, "partial", blocked_ok, True, pr_mergeable),
]

decisions = {}
for name, mode, partial, auto_merge, review, deps_ok, critical, mergeable in SCENARIOS:
    decision = gate(mode, partial, auto_merge, review, deps_ok, critical, mergeable)
    decisions[name] = decision
    path = os.path.join(out, f"gate-{name}-{decision}.txt")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(
            f"mode={mode} merge_partial={partial} auto_merge={auto_merge} "
            f"review={review} deps_ok={deps_ok} critical={critical} "
            f"mergeable={mergeable} -> {decision}\n"
        )

with open(os.path.join(out, "gate-decisions.json"), "w", encoding="utf-8") as fh:
    json.dump(decisions, fh, indent=2, sort_keys=True)
    fh.write("\n")

# One run-log record per distinct terminal outcome the gate can reach. The
# mode field carries the merge mode that produced it, per the run-log schema.
RECORDS = {
    "merged": {
        "ts": "2026-08-24T12:00:00Z",
        "issue": 51,
        "mode": "balanced",
        "skill": "auto-pilot",
        "complexity": "low",
        "profile": "light",
        "qa_cycles": 1,
        "outcome": "merged",
        "pr": 101,
        "duration_s": 42,
    },
    "left_open": {
        "ts": "2026-08-24T12:05:00Z",
        "issue": 51,
        "mode": "conservative",
        "skill": "auto-pilot",
        "complexity": "medium",
        "profile": "full",
        "qa_cycles": 2,
        "outcome": "left_open",
        "pr": 101,
        "duration_s": 51,
    },
    "partial_followup": {
        "ts": "2026-08-24T12:10:00Z",
        "issue": 51,
        "mode": "aggressive",
        "skill": "auto-pilot",
        "complexity": "medium",
        "profile": "full",
        "qa_cycles": 2,
        "outcome": "partial_followup",
        "pr": 101,
        "duration_s": 63,
    },
    "blocked_by_dependency": {
        "ts": "2026-08-24T12:15:00Z",
        "issue": 50,
        "mode": "balanced",
        "skill": "auto-pilot",
        "complexity": "low",
        "profile": "light",
        "qa_cycles": 0,
        "outcome": "blocked_by_dependency",
        "pr": None,
        "duration_s": 4,
    },
}
for outcome, record in RECORDS.items():
    assert outcome in decisions.values(), f"no scenario produced {outcome}"
    with open(os.path.join(out, f"run-{outcome}.json"), "w", encoding="utf-8") as fh:
        json.dump(record, fh, indent=2)
        fh.write("\n")

# Negative 1: a resolver outcome on an auto-pilot row. The per-skill outcome
# vocabulary is what keeps /idd-doctor's merge-rate metric honest.
with open(os.path.join(out, "run-wrong-vocabulary.json"), "w", encoding="utf-8") as fh:
    json.dump({**RECORDS["merged"], "outcome": "success"}, fh, indent=2)
    fh.write("\n")

# Negative 2: a gated run that blew past its QA-cycle ceiling without saying why.
with open(os.path.join(out, "run-uncapped-cycles.json"), "w", encoding="utf-8") as fh:
    json.dump({**RECORDS["merged"], "qa_cycles": 9}, fh, indent=2)
    fh.write("\n")

print("  ○ gate decisions: " + ", ".join(f"{k}={v}" for k, v in sorted(decisions.items())))
PY

echo "  ○ auto-pilot gating artifacts written to $EVAL_OUT"
