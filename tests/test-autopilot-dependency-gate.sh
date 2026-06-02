#!/usr/bin/env bash
# test-autopilot-dependency-gate.sh — Validate the Phase 5.1b dependency gate
#
# This script verifies issue #93 acceptance criteria:
#  - /auto-pilot identifies "Depends on #N" / "Blocked by #N" markers
#  - When a PR is blocked, the loop pauses with a structured alert
#  - The alert names the blocking PR, dependency, and how to resume
#  - Resume waits for the dep PR before retrying (stateless re-evaluation)
#  - The pause/resume cycle is tracked via the blocked_by_dependency outcome
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

SKILL="$REPO_ROOT/src/skills/auto-pilot/SKILL.md"
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
# T2: AC #2 — structured pause alert exists
# ───────────────────────────────────────────────────────────
if grep -qE '^### PR blocked by unmerged dependency' "$ERRORS"; then
  pass "T2.1: error-messages.md has 'PR blocked by unmerged dependency' alert"
else
  fail "T2.1: error-messages.md missing the dependency-pause alert"
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

if awk '/^### PR blocked by unmerged dependency/{f=1; next} f && /^### /{exit} f' "$ERRORS" | grep -qE 'To resume:'; then
  pass "T3.2: alert includes 'To resume:' instructions"
else
  fail "T3.2: alert is missing 'To resume:' instructions"
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
# T5: AC #5 — pause/resume tracked via outcome label
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
# T10: Autonomy-philosophy exception is recorded
# ───────────────────────────────────────────────────────────
if grep -qE 'PR blocked by an unmerged dependency' "$SKILL"; then
  pass "T10.1: SKILL.md autonomy-exception list includes the dependency case"
else
  fail "T10.1: SKILL.md autonomy-exception list missing the dependency case"
fi

if grep -qE 'second documented exception' "$SKILL"; then
  pass "T10.2: SKILL.md notes this is the second autonomy exception"
else
  fail "T10.2: SKILL.md does not flag the new exception"
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
