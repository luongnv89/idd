#!/usr/bin/env bash
# test-autopilot-partial-merge-dependency-gate.sh — Issue #184 acceptance checks
#
# Usage: bash tests/test-autopilot-partial-merge-dependency-gate.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Auto-Pilot Partial-Merge Dependency Gate (issue #184)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

PHASES="$REPO_ROOT/src/skills/auto-pilot/references/phases.md"
ERRORS="$REPO_ROOT/src/skills/auto-pilot/references/error-messages.md"

# AC1: Phase 3-4 partial path runs dependency and CI gates before merge
if grep -qE 'Step 2a — Dependency and CI gates' "$PHASES" \
  && awk '/Step 2a — Dependency and CI gates/{f=1} f && /Step 5\.1b — Dependency Gate/{found=1; exit} END{exit !found}' "$PHASES"; then
  pass "T1: Phase 3-4 Step 2a runs Step 5.1b before partial merge"
else
  fail "T1: Phase 3-4 missing Step 2a dependency gate before merge"
fi

# AC2: blocked_by_dependency on partial path when deps open
if awk '/Step 2a — Dependency and CI gates/{f=1} f && /blocked_by_dependency/{found=1; exit} END{exit !found}' "$PHASES"; then
  pass "T2: partial-merge path records blocked_by_dependency when gate fails"
else
  fail "T2: partial-merge path missing blocked_by_dependency outcome"
fi

# AC2b (#243): the partial path still refuses the merge, but continues the loop.
STEP2A="$(awk '/Step 2a — Dependency and CI gates/{f=1; next} f && /^\*\*Step 2b/{exit} f' "$PHASES")"

if printf '%s' "$STEP2A" | grep -qE 'do \*\*not\*\* merge'; then
  pass "T2.1: Step 2a still refuses to merge out of dependency order"
else
  fail "T2.1: Step 2a lost the do-not-merge guarantee"
fi

if printf '%s' "$STEP2A" | grep -qE 'continue to the next eligible issue'; then
  pass "T2.2: Step 2a continues to the next eligible issue (#243)"
else
  fail "T2.2: Step 2a does not continue the loop after a blocked partial merge"
fi

if printf '%s' "$STEP2A" | grep -qE 'stop the loop'; then
  fail "T2.3: Step 2a still stops the loop on a blocked partial merge"
else
  pass "T2.3: Step 2a no longer stops the loop (#243)"
fi

# AC3: error catalog has mode-gated variants, no unconditional partial merge
if grep -qE '^### Review cycles exhausted \(non-critical issue, aggressive \+ merge_partial\)' "$ERRORS" \
  && grep -qE '^### Review cycles exhausted \(non-critical issue, PR left open\)' "$ERRORS"; then
  pass "T3.1: error-messages.md has two mode-gated non-critical variants"
else
  fail "T3.1: error-messages.md missing mode-gated non-critical variants"
fi

if grep -qE 'Merging PR with partial fix\.\.\.' "$ERRORS"; then
  fail "T3.2: unconditional 'Merging PR with partial fix' still in error catalog"
else
  pass "T3.2: no unconditional 'Merging PR with partial fix' in error catalog"
fi

# AC4: Step 5.2 no longer scopes dependency gate to PASS-only
if grep -qE 'only runs after the PR review returned PASS' "$PHASES"; then
  fail "T4: phases.md still scopes merge/dependency gate to PASS-reviewed PRs only"
else
  pass "T4: PASS-only scoping text removed from Step 5.2"
fi

if grep -qE 'Partial merges \(Phase 3-4 Step 2\) use the same Step 5\.1b' "$PHASES" \
  && grep -qE 'Step 5\.1a — CI verdict gate' "$PHASES"; then
  pass "T4.1: Step 5.2 documents partial path uses dependency and CI gates"
else
  fail "T4.1: Step 5.2 does not document partial path dependency gate"
fi

echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0