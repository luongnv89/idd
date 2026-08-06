#!/usr/bin/env bash
# test-autopilot-dependency-gate.sh — Validate the Phase 5.1b dependency gate
#
# This script verifies issue #93 acceptance criteria, as amended by issue #243:
#  - /auto-pilot identifies "Depends on #N" / "Blocked by #N" markers
#  - When a PR is blocked, the gate refuses the merge with a structured alert
#  - The alert names the blocking PR, dependency, and how to unblock it
#  - A later run waits for the dep PR before retrying (stateless re-evaluation)
#  - The blocked issue is tracked via the blocked_by_dependency outcome
#  - #243: the loop does NOT stop — it records the outcome, leaves the PR open,
#    skips the issue for the session, and advances to the next eligible issue
#
# Usage: bash tests/test-autopilot-dependency-gate.sh
# Returns: exit 0 if all tests pass, exit 1 on first failure

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() {
  echo "  ✓ $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  ✗ $1"
  FAIL=$((FAIL + 1))
}

echo "◆ Auto-Pilot Dependency Gate Tests (issue #93)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

SKILL="$REPO_ROOT/src/skills/auto-pilot/SKILL.source.md"
PHASES="$REPO_ROOT/src/skills/auto-pilot/references/phases.md"
ERRORS="$REPO_ROOT/src/skills/auto-pilot/references/error-messages.md"
EXAMPLES="$REPO_ROOT/src/skills/auto-pilot/references/examples.md"
SCHEMA="$REPO_ROOT/docs/config-schema.md"
METHODOLOGY="$REPO_ROOT/docs/idd-methodology.md"
TEMPLATE="$REPO_ROOT/src/skills/init-gitissue/templates/gitissue-template.yml"

# ───────────────────────────────────────────────────────────
# T1: AC #1 — markers are identified before merge
# ───────────────────────────────────────────────────────────
if grep -qE '^### Step 5\.1b — Dependency Gate' "$PHASES"; then
  pass "T1.1: phases.md defines Step 5.1b before Step 5.2"
else
  fail "T1.1: phases.md missing 'Step 5.1b — Dependency Gate' heading"
fi

if grep -qE 'Depends\s+on\s+#N|Blocked\s+by\s+#N' "$PHASES"; then
  pass "T1.2: phases.md documents both 'Depends on #N' and 'Blocked by #N' markers"
else
  fail "T1.2: phases.md missing dependency marker syntax"
fi

if grep -qE 'closedByPullRequestsReferences' "$PHASES"; then
  pass "T1.3: phases.md uses closedByPullRequestsReferences for dependency resolution"
else
  fail "T1.3: phases.md missing GraphQL closedByPullRequestsReferences lookup"
fi

if awk '/^### Step 5\.1b/{found=1} found && /^### Step 5\.2/{exit} END{exit !found}' "$PHASES"; then
  pass "T1.4: Step 5.1b appears before Step 5.2 in phases.md"
else
  fail "T1.4: Step 5.1b ordering is wrong (must come before Step 5.2)"
fi

# ───────────────────────────────────────────────────────────
# T2: AC #2 — structured blocked-merge alert exists
# ───────────────────────────────────────────────────────────
if grep -qE '^### PR blocked by unmerged dependency' "$ERRORS"; then
  pass "T2.1: error-messages.md has 'PR blocked by unmerged dependency' alert"
else
  fail "T2.1: error-messages.md missing the dependency-blocked alert"
fi

if grep -qE 'BLOCKED — PR #\{pr_number\}' "$ERRORS"; then
  pass "T2.2: alert headline names the blocked PR"
else
  fail "T2.2: alert headline does not name {pr_number}"
fi

# ───────────────────────────────────────────────────────────
# T3: AC #3 — alert contains issue, deps, resume steps
# ───────────────────────────────────────────────────────────
if awk '/^### PR blocked by unmerged dependency/{f=1; next} f && /^### /{exit} f' "$ERRORS" | grep -qE 'Blocked by:'; then
  pass "T3.1: alert lists 'Blocked by:' dependencies"
else
  fail "T3.1: alert is missing the 'Blocked by:' enumeration"
fi

if awk '/^### PR blocked by unmerged dependency/{f=1; next} f && /^### /{exit} f' "$ERRORS" | grep -qE 'To unblock PR'; then
  pass "T3.2: alert includes 'To unblock PR' instructions"
else
  fail "T3.2: alert is missing 'To unblock PR' instructions"
fi

if awk '/^### PR blocked by unmerged dependency/{f=1; next} f && /^### /{exit} f' "$ERRORS" | grep -qE 'autopilot\.respect_dependencies:\s*false'; then
  pass "T3.3: alert documents the bypass via autopilot.respect_dependencies: false"
else
  fail "T3.3: alert does not document the respect_dependencies bypass"
fi

# ───────────────────────────────────────────────────────────
# T4: AC #4 — stateless re-evaluation resumes correctly
# ───────────────────────────────────────────────────────────
if grep -qE 're-read|re-evaluat|stateless' "$PHASES"; then
  pass "T4.1: phases.md describes stateless re-evaluation on resume"
else
  fail "T4.1: phases.md does not describe stateless resume behaviour"
fi

if grep -qE 're-invoke|Re-run /auto-pilot|re-run /auto-pilot|Re-run `/auto-pilot`' "$ERRORS"; then
  pass "T4.2: alert tells the user to re-run /auto-pilot"
else
  fail "T4.2: alert does not instruct to re-run /auto-pilot"
fi

# ───────────────────────────────────────────────────────────
# T5: AC #5 — blocked issue tracked via outcome label
# ───────────────────────────────────────────────────────────
if grep -qE '\bblocked_by_dependency\b' "$SKILL"; then
  pass "T5.1: SKILL.md uses outcome label 'blocked_by_dependency'"
else
  fail "T5.1: SKILL.md missing outcome label 'blocked_by_dependency'"
fi

# Final summary table must list six outcomes including blocked_by_dependency.
if grep -qE 'six categorical (labels|outcomes)' "$SKILL"; then
  pass "T5.2: SKILL.md states there are six outcome labels"
else
  fail "T5.2: SKILL.md does not state 'six categorical' outcomes"
fi

# Iteration template includes the new label as one of the choices.
if grep -qE 'merged \| left_open \| partial_followup \| blocked_by_dependency \| failed \| skipped' "$SKILL"; then
  pass "T5.3: iteration Outcome line lists blocked_by_dependency"
else
  fail "T5.3: iteration Outcome line missing blocked_by_dependency"
fi

# ───────────────────────────────────────────────────────────
# T6: Configuration — autopilot.respect_dependencies
# ───────────────────────────────────────────────────────────
if grep -qE 'autopilot\.respect_dependencies' "$SCHEMA"; then
  pass "T6.1: docs/config-schema.md documents autopilot.respect_dependencies"
else
  fail "T6.1: docs/config-schema.md missing autopilot.respect_dependencies"
fi

if grep -qE 'respect_dependencies:\s*true' "$SCHEMA"; then
  pass "T6.2: schema documents the default value (true)"
else
  fail "T6.2: schema does not document respect_dependencies: true default"
fi

if grep -qE 'respect_dependencies' "$SKILL"; then
  pass "T6.3: SKILL.md references autopilot.respect_dependencies"
else
  fail "T6.3: SKILL.md does not reference autopilot.respect_dependencies"
fi

# ───────────────────────────────────────────────────────────
# T7: Cycle and 404 sub-alerts (fail-safe behaviour)
# ───────────────────────────────────────────────────────────
if grep -qE 'Dependency cycle detected' "$ERRORS"; then
  pass "T7.1: error-messages.md has cycle-detection sub-alert"
else
  fail "T7.1: error-messages.md missing 'Dependency cycle detected' alert"
fi

if grep -qE 'Dependency #\{N\} not found' "$ERRORS"; then
  pass "T7.2: error-messages.md has 404 sub-alert"
else
  fail "T7.2: error-messages.md missing dependency-404 alert"
fi

if grep -qE 'self-reference' "$ERRORS" "$PHASES"; then
  pass "T7.3: cycle guard wording mentions self-reference (post-review tightening)"
else
  fail "T7.3: cycle guard wording missing self-reference clarification"
fi

# ───────────────────────────────────────────────────────────
# T8: Convention is documented in idd-methodology
# ───────────────────────────────────────────────────────────
if grep -qE '^## Issue Dependencies' "$METHODOLOGY"; then
  pass "T8.1: idd-methodology.md has 'Issue Dependencies' section"
else
  fail "T8.1: idd-methodology.md missing 'Issue Dependencies' section"
fi

if grep -qE 'Depends on #N|Blocked by #N' "$METHODOLOGY"; then
  pass "T8.2: methodology documents both marker phrasings"
else
  fail "T8.2: methodology missing marker phrasings"
fi

# ───────────────────────────────────────────────────────────
# T9: Worked example is provided
# ───────────────────────────────────────────────────────────
if grep -qE 'PR blocked by an unmerged dependency' "$EXAMPLES"; then
  pass "T9.1: examples.md walks through the dependency-blocked scenario"
else
  fail "T9.1: examples.md missing the dependency-blocked walk-through"
fi

# ───────────────────────────────────────────────────────────
# T10: Autonomy philosophy — dependency-blocking is auto-decided (#243)
# ───────────────────────────────────────────────────────────
if grep -qE 'PR blocked by an unmerged dependency' "$SKILL"; then
  pass "T10.1: SKILL.md autonomy section covers the dependency case"
else
  fail "T10.1: SKILL.md autonomy section missing the dependency case"
fi

# #243: dependency-blocking is no longer a stop-and-ask exception. The bullet
# must live in the auto-decide list (category 1), above the "Confirm with user"
# heading, not below it.
if awk '/^1\. \*\*Auto-decide\*\*/{f=1} /^2\. \*\*Confirm with user\*\*/{f=0} f && /PR blocked by an unmerged dependency/{found=1} END{exit !found}' "$SKILL"; then
  pass "T10.2: dependency case is listed under Auto-decide, not Confirm with user"
else
  fail "T10.2: dependency case is not in the Auto-decide list (#243 regression)"
fi

if grep -qE 'second documented exception' "$SKILL"; then
  fail "T10.3: SKILL.md still calls the dependency gate the second stop-and-ask exception"
else
  pass "T10.3: 'second documented exception' framing removed (#243)"
fi

# Critical-issue review failure is the remaining stop-and-ask case.
if grep -qE 'only\*\* documented stop-and-ask exception' "$SKILL"; then
  pass "T10.4: SKILL.md names critical-issue review failure as the only stop-and-ask case"
else
  fail "T10.4: SKILL.md does not name a single remaining stop-and-ask exception"
fi

# ───────────────────────────────────────────────────────────
# T11: Skill version — at or past the 2.3.0 baseline the dependency
# gate shipped under. Use a semver floor (sort -V), not an exact pin,
# so the check survives later legitimate bumps (2.3.1, …) — issue #100.
# ───────────────────────────────────────────────────────────
skill_ver="$(grep -E '^[[:space:]]*version:' "$SKILL" | head -1 | sed -E 's/.*version:[[:space:]]*//')"
if [ -n "$skill_ver" ] \
   && [ "$(printf '%s\n%s\n' "2.3.0" "$skill_ver" | sort -V | head -n1)" = "2.3.0" ]; then
  pass "T11.1: SKILL.md version at or past 2.3.0 — $skill_ver"
else
  fail "T11.1: SKILL.md version below 2.3.0 (got '${skill_ver:-none}')"
fi

# ───────────────────────────────────────────────────────────
# T12: dist/ tree mirrors src/ for the new content (drift guard)
# ───────────────────────────────────────────────────────────
DIST_PHASES="$REPO_ROOT/dist/skills/auto-pilot/references/phases.md"
DIST_SKILL="$REPO_ROOT/dist/skills/auto-pilot/SKILL.md"

if [ -f "$DIST_PHASES" ] && grep -qE '^### Step 5\.1b — Dependency Gate' "$DIST_PHASES"; then
  pass "T12.1: dist/ phases.md contains Step 5.1b"
else
  fail "T12.1: dist/ phases.md missing Step 5.1b — run scripts/build.sh"
fi

if [ -f "$DIST_SKILL" ] && grep -qE '\bblocked_by_dependency\b' "$DIST_SKILL"; then
  pass "T12.2: dist/ SKILL.md contains blocked_by_dependency outcome"
else
  fail "T12.2: dist/ SKILL.md missing blocked_by_dependency — run scripts/build.sh"
fi

# ───────────────────────────────────────────────────────────
# T13: issue #243 — the gate refuses the merge but the loop continues
# ───────────────────────────────────────────────────────────
SUMMARY_FMT="$REPO_ROOT/src/skills/auto-pilot/references/summary-format.md"
CONFIG_REF="$REPO_ROOT/src/skills/auto-pilot/references/configuration.md"
RUNLOG_REF="$REPO_ROOT/src/skills/auto-pilot/references/run-log.md"

# Isolate the Step 5.1b unsatisfied-dependency block (ends at the next h4).
gate_block() {
  awk '/^#### Record and continue when any dependency is unsatisfied/{f=1; next} f && /^#### /{exit} f' "$PHASES"
}

if grep -qE '^#### Record and continue when any dependency is unsatisfied' "$PHASES"; then
  pass "T13.1: phases.md heading states record-and-continue, not pause"
else
  fail "T13.1: phases.md still uses the pause heading for the unsatisfied set"
fi

# T13.3-T13.7 all read through gate_block. If the heading is ever reworded the
# block comes back empty and those five would fail for the wrong reason — so
# report the real cause once instead of five misleading failures.
if [ -n "$(gate_block)" ]; then
  pass "T13.2a: Step 5.1b unsatisfied-dependency block is non-empty"
else
  fail "T13.2a: Step 5.1b block not found — heading changed? (T13.3-T13.7 unreliable)"
fi

# The old stop-the-loop rationale must be gone everywhere in the source tree.
if grep -rqE 'do not advance to the next issue' "$REPO_ROOT/src"; then
  fail "T13.2: 'do not advance to the next issue' still present in src/"
else
  pass "T13.2: stop-the-loop rationale removed from src/"
fi

if gate_block | grep -qE 'advance to the next eligible issue'; then
  pass "T13.3: Step 5.1b advances to the next eligible issue"
else
  fail "T13.3: Step 5.1b does not advance to the next eligible issue"
fi

# The gate itself is unchanged — it must still refuse the merge.
if gate_block | grep -qE 'do \*\*not\*\* merge'; then
  pass "T13.4: Step 5.1b still refuses to merge out of dependency order"
else
  fail "T13.4: Step 5.1b lost the do-not-merge guarantee"
fi

if gate_block | grep -qE 'open and unchanged'; then
  pass "T13.5: blocked PR is left open and unchanged"
else
  fail "T13.5: Step 5.1b does not state the PR is left open and unchanged"
fi

# Re-pick guard: the blocked issue joins the session skip list so the
# continuing loop cannot resolve/log it twice.
if gate_block | grep -qE 'session skip list'; then
  pass "T13.6: blocked issue is added to the session skip list"
else
  fail "T13.6: no session skip-list guard against re-picking the blocked issue"
fi

# Dependency-grounded termination happens only via 'no eligible issue left'.
if gate_block | grep -qE 'only when no eligible issue remains'; then
  pass "T13.7: loop stops on dependency grounds only when nothing is eligible"
else
  fail "T13.7: Step 5.1b does not scope the dependency stop to an empty queue"
fi

# Exactly one run-log line, keyed on the outcome (not a skipped_reason).
if grep -qE 'outcome: blocked_by_dependency' "$RUNLOG_REF" \
  && grep -qE 'exactly one' "$RUNLOG_REF"; then
  pass "T13.8: run-log.md pins one line with outcome blocked_by_dependency"
else
  fail "T13.8: run-log.md does not pin the single blocked_by_dependency line"
fi

# config-schema.md legitimately lists blocked_by_dependency under BOTH `outcome`
# and `skipped_reason`. The two only agree because run-log.md carries the
# discriminator; without it a future reader could write both lines for one issue.
if grep -qE 'reserved for' "$RUNLOG_REF" && grep -qE 'never both' "$RUNLOG_REF"; then
  pass "T13.8a: run-log.md reserves skipped_reason for pre-resolution skips"
else
  fail "T13.8a: run-log.md lost the outcome-vs-skipped_reason discriminator"
fi

# Partial-merge path (Phase 3-4 Step 2a) continues too.
if awk '/Step 2a — Dependency gate/{f=1} f && /continue to the next eligible issue/{found=1; exit} END{exit !found}' "$PHASES"; then
  pass "T13.9: partial-merge path also continues to the next eligible issue"
else
  fail "T13.9: partial-merge path still stops the loop"
fi

# No surface may still claim the run is paused by the dependency gate.
if grep -qE 'the loop pauses' "$SUMMARY_FMT"; then
  fail "T13.10: summary-format.md still says the loop pauses"
else
  pass "T13.10: summary-format.md no longer claims the loop pauses"
fi

if grep -qE 'Auto-pilot paused — merging out of dependency order' "$ERRORS" "$EXAMPLES" "$PHASES"; then
  fail "T13.11: 'Auto-pilot paused' dependency alert still present"
else
  pass "T13.11: dependency alert no longer claims auto-pilot is paused"
fi

if grep -qE 'pause the loop' "$CONFIG_REF"; then
  fail "T13.12: configuration.md still says respect_dependencies pauses the loop"
else
  pass "T13.12: configuration.md describes the non-pausing gate"
fi

if grep -qE 'pause the loop before merging|pause loop before merging' "$SCHEMA"; then
  fail "T13.13: config-schema.md still documents a pausing dependency gate"
else
  pass "T13.13: config-schema.md documents the non-pausing dependency gate"
fi

if grep -qE 'the auto-pilot pauses with a structured alert' "$METHODOLOGY"; then
  fail "T13.14: idd-methodology.md still says auto-pilot pauses on the gate"
else
  pass "T13.14: idd-methodology.md describes the continue-the-loop gate"
fi

# The re-pick guard only works if Step 1.2 eligibility consults the session
# skip list the gate appends to.
if awk '/^### Step 1\.2 — Pick Next Issue/{f=1; next} f && /^### /{exit} f' "$PHASES" \
  | grep -qE 'session skip list'; then
  pass "T13.15: Step 1.2 eligibility consults the session skip list"
else
  fail "T13.15: Step 1.2 never consults the session skip list (re-pick hazard)"
fi

# The 'no eligible issues' terminal surface distinguishes dep-blocked issues.
if awk '/^### Step 1\.2 — Pick Next Issue/{f=1; next} f && /^### /{exit} f' "$PHASES" \
  | grep -qE 'Dep-blocked'; then
  pass "T13.16: terminal 'no eligible issues' block reports dep-blocked issues"
else
  fail "T13.16: terminal block folds dep-blocked issues into plain Skipped"
fi

# Public skills doc must not still claim the loop pauses on the gate.
SKILLS_DOC="$REPO_ROOT/docs/skills.md"
if grep -qE 'loop pauses for critical unresolved review failures and dependency-blocked' "$SKILLS_DOC"; then
  fail "T13.17: docs/skills.md still says the loop pauses on dependency-blocked PRs"
else
  pass "T13.17: docs/skills.md describes the continue-the-loop gate"
fi

# Stop Conditions table: its preamble says "except the rows marked *loop
# continues*", so every row that actually continues must carry the marker.
# Assert per known-continuing row rather than an exact total, so the check
# survives future rows and still catches an unmarked continuing row.
STOP_TABLE="$(awk '/^\| Condition \| Output \|/{f=1} f && /^\| User cancellation/{exit} f' "$SKILL")"

if printf '%s' "$STOP_TABLE" | grep -qE '\*loop continues\*'; then
  pass "T13.18: Stop Conditions table uses the *loop continues* marker"
else
  fail "T13.18: Stop Conditions table has no *loop continues* marker"
fi

while IFS='|' read -r label pattern; do
  [ -z "$label" ] && continue
  if printf '%s' "$STOP_TABLE" | grep -qE "${pattern}.*\*loop continues\*"; then
    pass "T13.19.${label}: continuing row '${label}' carries the marker"
  else
    fail "T13.19.${label}: continuing row '${label}' is not marked *loop continues*"
  fi
done <<'ROWS'
merge-blocked|^\| Merge blocked \(CI/conflicts\)
conservative|^\| Mode forbids merge
review-exhausted|^\| Review exhausted \(non-critical
dependency|^\| PR blocked by an unmerged dependency
ROWS

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
else
  exit 0
fi
