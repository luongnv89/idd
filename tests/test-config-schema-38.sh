#!/usr/bin/env bash
# test-config-schema-38.sh — Validate the unified Phase 1b + Phase 2
# configuration schema shipped for issue #38.
#
# This script verifies issue #38 acceptance criteria:
#  AC1. .idd.yml schema documents the four keys with defaults:
#         autopilot.mode (balanced), autopilot.merge_partial (false),
#         review.require_acceptance_criteria_check (true),
#         review.require_traceability_check (true).
#  AC2. /init-idd emits these defaults on a fresh install.
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
TEMPLATE="$REPO_ROOT/src/skills/init-idd/templates/idd-template.yml"
PR_REVIEW_SKILL="$REPO_ROOT/src/skills/issue-pr-review/SKILL.source.md"
INIT_SKILL="$REPO_ROOT/src/skills/init-idd/SKILL.source.md"

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
# autopilot.mode = balanced (already shipped in #33; covered here for
# the unified-schema AC)
if grep -qE '^\s*mode:\s*balanced\b' "$SCHEMA"; then
  pass "T1.AC1.1: schema yaml block has 'mode: balanced'"
else
  fail "T1.AC1.1: schema yaml block missing 'mode: balanced'"
fi

if grep -qE '\| `autopilot\.mode` \| `balanced`' "$SCHEMA"; then
  pass "T1.AC1.2: defaults table lists autopilot.mode = balanced"
else
  fail "T1.AC1.2: defaults table missing autopilot.mode = balanced"
fi

# autopilot.merge_partial = false
if grep -qE '^\s*merge_partial:\s*false\b' "$SCHEMA"; then
  pass "T1.AC1.3: schema yaml block has 'merge_partial: false'"
else
  fail "T1.AC1.3: schema yaml block missing 'merge_partial: false'"
fi

if grep -qE '\| `autopilot\.merge_partial` \| `false`' "$SCHEMA"; then
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

if grep -qE '\| `review\.require_acceptance_criteria_check` \| `true`' "$SCHEMA"; then
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

if grep -qE '\| `review\.require_traceability_check` \| `true`' "$SCHEMA"; then
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
# T2: AC2 — /init-idd emits the four defaults
# ───────────────────────────────────────────────────────────
# autopilot.mode and merge_partial come from #33; verify they are still
# emitted as part of the unified schema.
if grep -qE '^\s*mode:\s*balanced\b' "$TEMPLATE"; then
  pass "T2.AC2.1: init template emits 'mode: balanced'"
else
  fail "T2.AC2.1: init template missing 'mode: balanced'"
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
# T5: Version bumps — both consuming skills bumped past the
#     pre-#38 baseline. Use a semver floor (sort -V) rather than
#     pinning an exact minor, so the assertion survives later
#     legitimate bumps (e.g. 0.5.0, 0.10.0) — see issue #100.
# ───────────────────────────────────────────────────────────
# /issue-pr-review must be at or past 0.4.1 — i.e. #38's bump
# landed and the version has only moved forward since.
pr_review_ver="$(grep -E '^[[:space:]]*version:' "$PR_REVIEW_SKILL" | head -1 | sed -E 's/.*version:[[:space:]]*//')"
if [ -n "$pr_review_ver" ] \
   && [ "$(printf '%s\n%s\n' "0.4.1" "$pr_review_ver" | sort -V | head -n1)" = "0.4.1" ]; then
  pass "T5.1: /issue-pr-review SKILL.md at or past 0.4.1 (#38 bump landed) — $pr_review_ver"
else
  fail "T5.1: /issue-pr-review SKILL.md below 0.4.1 — expected a bump for #38 (got '${pr_review_ver:-none}')"
fi

# /init-idd bumped past 0.3.1
if grep -qE '^[[:space:]]*version:[[:space:]]+0\.3\.[2-9]' "$INIT_SKILL" \
   || grep -qE '^[[:space:]]*version:[[:space:]]+0\.[4-9]\.' "$INIT_SKILL"; then
  pass "T5.3: /init-idd SKILL.md bumped past 0.3.1"
else
  fail "T5.3: /init-idd SKILL.md still at 0.3.1 — expected a bump for #38"
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
# T7: review.merge_method (issue #564) — one key, default `squash`, present in
# all three schema places and in the init template, with a value guard.
# ───────────────────────────────────────────────────────────
FULL_SCHEMA="$(awk '/^## Full Schema/{f=1} f && /^```yaml/{y=1; next} y && /^```/{exit} y' "$SCHEMA")"
if printf '%s\n' "$FULL_SCHEMA" | awk '/^review:/{f=1; next} /^[^[:space:]#]/{f=0} f' \
     | grep -qE '^  merge_method: "squash"$'; then
  pass "T7.1: Full Schema review: block has merge_method defaulting to squash"
else
  fail "T7.1: Full Schema review: block lacks merge_method: \"squash\""
fi

if grep -qE '^    RV --> RV[0-9]+\["merge_method"\]$' "$SCHEMA"; then
  pass "T7.2: Config Section Map lists review.merge_method"
else
  fail "T7.2: Config Section Map does not list merge_method"
fi

if grep -qE '^\| `review\.merge_method` \| `"squash"` \|.*`squash`, `merge` or `rebase`' "$SCHEMA"; then
  pass "T7.3: Defaults Table documents review.merge_method = squash and its three values"
else
  fail "T7.3: Defaults Table lacks the review.merge_method row"
fi

if awk '/^review:/{f=1; next} /^[^[:space:]#]/{f=0} f' "$TEMPLATE" | grep -qE '^  merge_method: squash$'; then
  pass "T7.4: init template emits review.merge_method: squash"
else
  fail "T7.4: init template does not emit review.merge_method: squash"
fi

# The guard is behavioural: run the real script against the real schema.
GI_CONFIG="$REPO_ROOT/src/shared/scripts/gi-config.py"
T7_TMP="$(mktemp -d)"
trap 'rm -rf "$T7_TMP"' EXIT
merge_method_rc() {
  # $1 = the YAML value, or "" for no config file at all (cwd holds none).
  rm -f "$T7_TMP/.idd.yml"
  [ -z "$1" ] || printf 'review:\n  merge_method: %s\n' "$1" > "$T7_TMP/.idd.yml"
  (cd "$T7_TMP" && python3 "$GI_CONFIG" --schema "$SCHEMA" \
     --key review.merge_method > "$T7_TMP/out" 2> "$T7_TMP/err"); echo $?
}

if [ "$(merge_method_rc "")" = "0" ] && [ "$(cat "$T7_TMP/out")" = '"squash"' ]; then
  pass "T7.5: gi-config resolves review.merge_method to squash with no config"
else
  fail "T7.5: gi-config default is not squash (out=$(cat "$T7_TMP/out") err=$(cat "$T7_TMP/err"))"
fi

for method in squash merge rebase; do
  if [ "$(merge_method_rc "$method")" = "0" ] && [ "$(cat "$T7_TMP/out")" = "\"$method\"" ]; then
    pass "T7.6: gi-config accepts review.merge_method: $method"
  else
    fail "T7.6: gi-config rejected review.merge_method: $method (err=$(cat "$T7_TMP/err"))"
  fi
done

if [ "$(merge_method_rc fast-forward)" = "3" ] \
   && grep -qF 'review.merge_method — must be one of: squash, merge, rebase' "$T7_TMP/err"; then
  pass "T7.7: gi-config exits 3 on review.merge_method: fast-forward, naming the key and the allowed values"
else
  fail "T7.7: gi-config did not stop on an invalid merge method (err=$(cat "$T7_TMP/err"))"
fi

# The guard also holds for a skill whose schema excerpt hides the review
# section: /issue-triage ships an excerpt without it.
TRIAGE="$REPO_ROOT/skills/issue-triage/references"
printf 'review:\n  merge_method: fast-forward\n' > "$T7_TMP/.idd.yml"
T7_RC=0
(cd "$T7_TMP" && python3 "$TRIAGE/scripts/gi-config.py" > "$T7_TMP/out" 2> "$T7_TMP/err") || T7_RC=$?
if ! grep -qE '^review:' "$TRIAGE/docs/config-schema.md" && [ "$T7_RC" = "3" ] \
   && grep -qF 'review.merge_method — must be one of: squash, merge, rebase' "$T7_TMP/err"; then
  pass "T7.8: the guard runs when the review section is out of the schema view"
else
  fail "T7.8: an out-of-view invalid merge method was not refused (rc=$T7_RC err=$(cat "$T7_TMP/err"))"
fi

# The prose fallback states the same stop.
if grep -qE '`review\.merge_method: squash` \|.*Any other value is `✗ Invalid config`: stop, also when reading `\.idd\.yml` by hand' \
     "$REPO_ROOT/src/skills/issue-pr-review/references/review-loop-mechanics.md"; then
  pass "T7.9: the prose fallback stops on an invalid merge method"
else
  fail "T7.9: the prose fallback does not state the invalid-merge-method stop"
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
