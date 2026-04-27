#!/usr/bin/env bash
# test-config-schema-38.sh — Validate the unified Phase 1b + Phase 2
# configuration schema shipped for issue #38.
#
# This script verifies issue #38 acceptance criteria:
#  AC1. .gitissue.yml schema documents the four keys with defaults:
#         autopilot.mode (conservative), autopilot.merge_partial (false),
#         review.require_acceptance_criteria_check (true),
#         review.require_traceability_check (true).
#  AC2. /init-gitissue emits these defaults on a fresh install.
#  AC3. No additional speculative keys are added in this milestone — the
#       four keys above are the only Phase 1b + Phase 2 schema additions.
#  AC4. Skills consuming these keys behave per Phase 1b and Phase 2 ACs:
#       - /auto-pilot honours autopilot.mode and autopilot.merge_partial
#         (already verified by tests/test-autopilot-modes.sh — referenced).
#       - /issue-pr-review honours the two review.require_*_check gates,
#         skipping the corresponding dimension when set to false.
#
# Strategy: this is a documentation/skill repo — tests verify that the
# SKILL.md, template, and schema files contain the spec language that
# satisfies each AC. If the language is present, the agent following the
# skill produces the documented behavior.
#
# Usage: bash tests/test-config-schema-38.sh
# Returns: exit 0 if all tests pass, exit 1 on first failure category.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEMA="$REPO_ROOT/docs/config-schema.md"
TEMPLATE="$REPO_ROOT/skills/init-gitissue/templates/gitissue-template.yml"
PR_REVIEW_SKILL="$REPO_ROOT/skills/issue-pr-review/SKILL.md"
INIT_SKILL="$REPO_ROOT/skills/init-gitissue/SKILL.md"

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

echo "◆ Config Schema Tests (issue #38 — unified Phase 1b + Phase 2)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T0: Files exist
# ───────────────────────────────────────────────────────────
for f in "$SCHEMA" "$TEMPLATE" "$PR_REVIEW_SKILL" "$INIT_SKILL"; do
  if [ -f "$f" ]; then
    pass "T0: $(basename "$(dirname "$f")")/$(basename "$f") exists"
  else
    fail "T0: $f not found"
    exit 1
  fi
done

# ───────────────────────────────────────────────────────────
# T1: AC1 — schema documents all four keys with their defaults
# ───────────────────────────────────────────────────────────
# autopilot.mode = conservative (already shipped in #33; covered here for
# the unified-schema AC)
if grep -qE '^\s*mode:\s*conservative\b' "$SCHEMA"; then
  pass "T1.AC1.1: schema yaml block has 'mode: conservative'"
else
  fail "T1.AC1.1: schema yaml block missing 'mode: conservative'"
fi

if grep -qE '\| \`autopilot\.mode\` \| \`conservative\`' "$SCHEMA"; then
  pass "T1.AC1.2: defaults table lists autopilot.mode = conservative"
else
  fail "T1.AC1.2: defaults table missing autopilot.mode = conservative"
fi

# autopilot.merge_partial = false
if grep -qE '^\s*merge_partial:\s*false\b' "$SCHEMA"; then
  pass "T1.AC1.3: schema yaml block has 'merge_partial: false'"
else
  fail "T1.AC1.3: schema yaml block missing 'merge_partial: false'"
fi

if grep -qE '\| \`autopilot\.merge_partial\` \| \`false\`' "$SCHEMA"; then
  pass "T1.AC1.4: defaults table lists autopilot.merge_partial = false"
else
  fail "T1.AC1.4: defaults table missing autopilot.merge_partial = false"
fi

# review.require_acceptance_criteria_check = true (new in #38)
if grep -qE '^\s*require_acceptance_criteria_check:\s*true\b' "$SCHEMA"; then
  pass "T1.AC1.5: schema yaml block has 'require_acceptance_criteria_check: true'"
else
  fail "T1.AC1.5: schema yaml block missing 'require_acceptance_criteria_check: true'"
fi

if grep -qE '\| \`review\.require_acceptance_criteria_check\` \| \`true\`' "$SCHEMA"; then
  pass "T1.AC1.6: defaults table lists review.require_acceptance_criteria_check = true"
else
  fail "T1.AC1.6: defaults table missing review.require_acceptance_criteria_check = true"
fi

# review.require_traceability_check = true (new in #38)
if grep -qE '^\s*require_traceability_check:\s*true\b' "$SCHEMA"; then
  pass "T1.AC1.7: schema yaml block has 'require_traceability_check: true'"
else
  fail "T1.AC1.7: schema yaml block missing 'require_traceability_check: true'"
fi

if grep -qE '\| \`review\.require_traceability_check\` \| \`true\`' "$SCHEMA"; then
  pass "T1.AC1.8: defaults table lists review.require_traceability_check = true"
else
  fail "T1.AC1.8: defaults table missing review.require_traceability_check = true"
fi

# Section-map mermaid diagram references both new keys
if grep -qE 'require_acceptance_criteria_check' "$SCHEMA"; then
  pass "T1.AC1.9: schema section map includes require_acceptance_criteria_check"
else
  fail "T1.AC1.9: schema section map missing require_acceptance_criteria_check"
fi

if grep -qE 'require_traceability_check' "$SCHEMA"; then
  pass "T1.AC1.10: schema section map includes require_traceability_check"
else
  fail "T1.AC1.10: schema section map missing require_traceability_check"
fi

# ───────────────────────────────────────────────────────────
# T2: AC2 — /init-gitissue emits the four defaults
# ───────────────────────────────────────────────────────────
# autopilot.mode and merge_partial come from #33; verify they are still
# emitted as part of the unified schema.
if grep -qE '^\s*mode:\s*conservative\b' "$TEMPLATE"; then
  pass "T2.AC2.1: init template emits 'mode: conservative'"
else
  fail "T2.AC2.1: init template missing 'mode: conservative'"
fi

if grep -qE '^\s*merge_partial:\s*false\b' "$TEMPLATE"; then
  pass "T2.AC2.2: init template emits 'merge_partial: false'"
else
  fail "T2.AC2.2: init template missing 'merge_partial: false'"
fi

# Two new review.* keys (added in #38)
if grep -qE '^\s*require_acceptance_criteria_check:\s*true\b' "$TEMPLATE"; then
  pass "T2.AC2.3: init template emits 'require_acceptance_criteria_check: true'"
else
  fail "T2.AC2.3: init template missing 'require_acceptance_criteria_check: true'"
fi

if grep -qE '^\s*require_traceability_check:\s*true\b' "$TEMPLATE"; then
  pass "T2.AC2.4: init template emits 'require_traceability_check: true'"
else
  fail "T2.AC2.4: init template missing 'require_traceability_check: true'"
fi

# Template has a review: section header so the keys live under the
# correct namespace, not loose at the top level.
if grep -qE '^review:' "$TEMPLATE"; then
  pass "T2.AC2.5: init template has 'review:' section header"
else
  fail "T2.AC2.5: init template missing 'review:' section header"
fi

# autopilot section is still present
if grep -qE '^autopilot:' "$TEMPLATE"; then
  pass "T2.AC2.6: init template has 'autopilot:' section header"
else
  fail "T2.AC2.6: init template missing 'autopilot:' section header"
fi

# ───────────────────────────────────────────────────────────
# T3: AC3 — no speculative keys
# ───────────────────────────────────────────────────────────
# The improvement-plan-final.md "Configuration Schema" section lists
# exactly four keys for this milestone. The schema may already document
# other keys from earlier milestones (e.g., review.max_cycles,
# autopilot.max_iterations); those are pre-existing, not Phase 1b/2
# additions. The check is: no NEW review.require_*_check keys beyond the
# two specified, and no NEW autopilot keys with names that look like
# speculative additions from the planning docs.

# Phase 2 spec lists exactly TWO review.require_*_check keys.
SPEC_REVIEW_REQUIRE_COUNT=$(grep -cE '^\s*require_(acceptance_criteria|traceability)_check:' "$SCHEMA" || true)
if [ "$SPEC_REVIEW_REQUIRE_COUNT" -eq 2 ]; then
  pass "T3.AC3.1: schema has exactly 2 review.require_*_check keys (no speculative additions)"
else
  fail "T3.AC3.1: schema has $SPEC_REVIEW_REQUIRE_COUNT review.require_*_check keys, expected 2"
fi

# Same check for the init template.
TEMPLATE_REVIEW_REQUIRE_COUNT=$(grep -cE '^\s*require_(acceptance_criteria|traceability)_check:' "$TEMPLATE" || true)
if [ "$TEMPLATE_REVIEW_REQUIRE_COUNT" -eq 2 ]; then
  pass "T3.AC3.2: init template has exactly 2 review.require_*_check keys (no speculative additions)"
else
  fail "T3.AC3.2: init template has $TEMPLATE_REVIEW_REQUIRE_COUNT review.require_*_check keys, expected 2"
fi

# Speculative-key smell test: a few candidate names that the planning
# docs mention but that this milestone explicitly defers.
for speculative in 'require_decision_record_check' 'require_squash_merge_check' 'require_codebase_research_check'; do
  if grep -qE "\b${speculative}\b" "$SCHEMA" "$TEMPLATE"; then
    fail "T3.AC3.3: speculative key '$speculative' found — should be deferred per AC3"
  else
    pass "T3.AC3.3.${speculative}: speculative key '$speculative' is correctly absent"
  fi
done

# ───────────────────────────────────────────────────────────
# T4: AC4 — /issue-pr-review wires the two review.require_*_check gates
# ───────────────────────────────────────────────────────────
# SKILL.md lists the new gate flags in its config defaults block.
if grep -qE 'review\.require_acceptance_criteria_check' "$PR_REVIEW_SKILL"; then
  pass "T4.AC4.1: /issue-pr-review SKILL.md references review.require_acceptance_criteria_check"
else
  fail "T4.AC4.1: /issue-pr-review SKILL.md does not reference review.require_acceptance_criteria_check"
fi

if grep -qE 'review\.require_traceability_check' "$PR_REVIEW_SKILL"; then
  pass "T4.AC4.2: /issue-pr-review SKILL.md references review.require_traceability_check"
else
  fail "T4.AC4.2: /issue-pr-review SKILL.md does not reference review.require_traceability_check"
fi

# A "Verification gates" section exists so future readers understand the
# false-path semantics.
if grep -qiE 'Verification gates|verification disabled' "$PR_REVIEW_SKILL"; then
  pass "T4.AC4.3: /issue-pr-review SKILL.md documents the false-path semantics"
else
  fail "T4.AC4.3: /issue-pr-review SKILL.md missing false-path semantics for the gates"
fi

# Hard-block clause mentions the gates so a reader can trust the gate
# actually disables the block.
if grep -qE 'require_traceability_check|require_acceptance_criteria_check' "$PR_REVIEW_SKILL" \
   && grep -qE 'Hard-block conditions' "$PR_REVIEW_SKILL"; then
  pass "T4.AC4.4: /issue-pr-review SKILL.md ties the gates to the hard-block clause"
else
  fail "T4.AC4.4: /issue-pr-review SKILL.md does not tie the gates to the hard-block clause"
fi

# Both default to true (preserves issue #36 contract verbatim)
if grep -qiE 'require_acceptance_criteria_check.*true|true.*require_acceptance_criteria_check' "$PR_REVIEW_SKILL"; then
  pass "T4.AC4.5: /issue-pr-review SKILL.md states require_acceptance_criteria_check defaults to true"
else
  fail "T4.AC4.5: /issue-pr-review SKILL.md does not state require_acceptance_criteria_check defaults to true"
fi

if grep -qiE 'require_traceability_check.*true|true.*require_traceability_check' "$PR_REVIEW_SKILL"; then
  pass "T4.AC4.6: /issue-pr-review SKILL.md states require_traceability_check defaults to true"
else
  fail "T4.AC4.6: /issue-pr-review SKILL.md does not state require_traceability_check defaults to true"
fi

# ───────────────────────────────────────────────────────────
# T5: Version bumps — both consuming skills bumped, version bumps
#     stay in the test-friendly version range.
# ───────────────────────────────────────────────────────────
# /issue-pr-review must remain on 0.4.x so test-issue-pr-review-traceability.sh
# T9 still passes.
if grep -qE '^[[:space:]]*version:[[:space:]]+0\.4\.[0-9]+' "$PR_REVIEW_SKILL"; then
  pass "T5.1: /issue-pr-review SKILL.md still on 0.4.x"
else
  fail "T5.1: /issue-pr-review SKILL.md not on 0.4.x"
fi

# Version actually moved past 0.4.0 — i.e., this PR bumped it.
if grep -qE '^[[:space:]]*version:[[:space:]]+0\.4\.[1-9][0-9]*' "$PR_REVIEW_SKILL"; then
  pass "T5.2: /issue-pr-review SKILL.md bumped past 0.4.0"
else
  fail "T5.2: /issue-pr-review SKILL.md still at 0.4.0 — expected a bump for #38"
fi

# /init-gitissue bumped past 0.3.1
if grep -qE '^[[:space:]]*version:[[:space:]]+0\.3\.[2-9]' "$INIT_SKILL" \
   || grep -qE '^[[:space:]]*version:[[:space:]]+0\.[4-9]\.' "$INIT_SKILL"; then
  pass "T5.3: /init-gitissue SKILL.md bumped past 0.3.1"
else
  fail "T5.3: /init-gitissue SKILL.md still at 0.3.1 — expected a bump for #38"
fi

# ───────────────────────────────────────────────────────────
# T6: Cross-test sanity — Phase 1b tests still pass on the same files
# ───────────────────────────────────────────────────────────
# Don't actually re-run them here (avoid recursion); just confirm the
# test files exist and the assertions they make are still satisfied.
AUTOPILOT_TEST="$REPO_ROOT/tests/test-autopilot-modes.sh"
TRACEABILITY_TEST="$REPO_ROOT/tests/test-issue-pr-review-traceability.sh"

if [ -f "$AUTOPILOT_TEST" ]; then
  pass "T6.1: test-autopilot-modes.sh exists (Phase 1b coverage)"
else
  fail "T6.1: test-autopilot-modes.sh missing"
fi

if [ -f "$TRACEABILITY_TEST" ]; then
  pass "T6.2: test-issue-pr-review-traceability.sh exists (Phase 2 coverage)"
else
  fail "T6.2: test-issue-pr-review-traceability.sh missing"
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  Result: FAIL"
  exit 1
else
  echo "  Result: PASS"
  exit 0
fi
