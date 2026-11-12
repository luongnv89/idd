#!/usr/bin/env bash
# test-plan-criteria-coverage-554.sh — map the plan to the acceptance criteria
# (issue #554).
#
# Every plan option lists `criteria_covered`, the `AC<k>` IDs gi-ready.py
# numbers from the issue body. Once an option is selected, the resolver's
# *Criteria coverage gate* checks it; a `gap` stops planning with each
# uncovered criterion named, in auto mode too.
#
#   T1  gi-ready.py --criteria numbers the criteria (behavioural), skipping the
#       quoted Reporter Context that repeats them in an issue shaped like #554;
#   T2  gi-ready.py --coverage: a plan that omits one criterion is a `gap`
#       naming it; full coverage, unknown IDs, no criteria, malformed plans;
#   T3  the readiness verdict is unchanged by the refactor;
#   T4  the synthesizer contract and the gate's one home (prose pins);
#   T5  the built bundles carry the script and the agent field;
#   T6  the CI step exists.
#
# Usage: bash tests/test-plan-criteria-coverage-554.sh
# Returns: exit 0 if all checks pass, exit 1 on failure
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
READY="$ROOT/src/shared/scripts/gi-ready.py"
SYN="$ROOT/src/shared/agents/synthesizer.md"
RS="$ROOT/src/skills/issue-resolver"
PLAN="$RS/references/steps/step-2-plan.md"
WORKFLOW="$ROOT/.github/workflows/dist-check.yml"

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
has() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3 (missing in ${1#"$ROOT"/})"; }
js() { python3 -c "import json,sys; d=json.load(sys.stdin); print(($1))"; }

echo "Plan-to-criteria coverage tests (issue #554)"

# An issue shaped like #554: the Reporter Context quote repeats both criteria.
BODY='## Type\n\nimprovement (high confidence)\n\n## Description\n\n> Acceptance criteria:\n> - [ ] quoted one\n> - [ ] quoted two\n\n## Acceptance Criteria\n\n- [ ] Every plan option lists the criteria it covers (high confidence)\n- [ ] Selecting an option that leaves a criterion uncovered stops planning (high confidence)\n\n## Metadata\n\n- not a criterion\n'
ISSUE="{\"number\":554,\"body\":\"$BODY\"}"

# coverage <options-json> <selected> — runs --coverage, prints stdout, sets $ec.
coverage() {
  set +e
  out="$(printf '%s' "{\"issue\":$ISSUE,\"options\":$1,\"selected\":$2}" \
    | python3 "$READY" --coverage 2>/dev/null)"
  ec=$?
  set -e
}

# ── T1: criteria are numbered IDs ────────────────────────────────────────
out="$(printf '%s' "{\"issue\":$ISSUE}" | python3 "$READY" --criteria)"
[ "$(printf '%s' "$out" | js '[c["id"] for c in d["criteria"]]')" = "['AC1', 'AC2']" ] \
  && [ "$(printf '%s' "$out" | js 'd["criteria"][1]["text"]')" = 'Selecting an option that leaves a criterion uncovered stops planning (high confidence)' ] \
  && pass "T1.1 --criteria numbers the two real criteria, never the quoted ones" \
  || fail "T1.1 --criteria: $out"
out="$(printf '%s' "$ISSUE" | python3 "$READY" --criteria)"
[ "$(printf '%s' "$out" | js 'd["number"], len(d["criteria"])')" = "(554, 2)" ] \
  && pass "T1.2 --criteria also takes a bare issue object" \
  || fail "T1.2 --criteria on a bare issue: $out"

# ── T2: the coverage verdict ─────────────────────────────────────────────
coverage '[{"number":1,"criteria_covered":["AC1"]},{"number":2,"criteria_covered":["AC1","AC2"]}]' 1
[ "$ec" -eq 0 ] && [ "$(printf '%s' "$out" | js 'd["verdict"], [m["id"] for m in d["missing"]]')" = "('gap', ['AC2'])" ] \
  && printf '%s' "$out" | grep -qF 'stops planning (high confidence)' \
  && pass "T2.1 a selected plan that omits one criterion is a gap naming it (exit 0)" \
  || fail "T2.1 omitted criterion: exit $ec, $out"
coverage '[{"number":1,"criteria_covered":["AC1"]},{"number":2,"criteria_covered":["ac1"," AC2 "]}]' 2
[ "$ec" -eq 0 ] && [ "$(printf '%s' "$out" | js 'd["verdict"], d["selected"], d["missing"]')" = "('covered', 2, [])" ] \
  && pass "T2.2 full coverage is covered; IDs are case- and space-insensitive" \
  || fail "T2.2 full coverage: exit $ec, $out"
coverage '[{"number":1,"criteria_covered":["AC1","AC9"]}]' 1
[ "$(printf '%s' "$out" | js 'd["verdict"], d["unknown"]')" = "('gap', ['AC9'])" ] \
  && pass "T2.3 an unknown ID is listed and never counts as covered" \
  || fail "T2.3 unknown ID: $out"
out="$(printf '%s' '{"issue":{"body":"## Description\n\nno criteria"},"options":[{"number":1,"criteria_covered":[]}],"selected":1}' \
  | python3 "$READY" --coverage)"
[ "$(printf '%s' "$out" | js 'd["verdict"]')" = "no_criteria" ] \
  && pass "T2.4 a body with no criteria is no_criteria, never covered" \
  || fail "T2.4 no criteria: $out"
for bad in \
  '[{"number":1,"criteria_covered":["AC1"]},{"number":2}]|1|an option without criteria_covered' \
  '[{"number":1,"criteria_covered":"AC1"}]|1|a criteria_covered string' \
  '[{"number":1,"criteria_covered":[1]}]|1|a non-string ID' \
  '[{"number":1,"criteria_covered":[]},{"number":1,"criteria_covered":[]}]|1|duplicate option numbers' \
  '[{"number":1,"criteria_covered":[]}]|2|a selected number no option has' \
  '[{"number":1,"criteria_covered":[]}]|true|a boolean selected' \
  '[{"number":1,"criteria_covered":[]}]|[1]|an unhashable selected' \
  '[{"number":1,"criteria_covered":[]}]|1.0|a float selected' \
  '[]|1|no options'; do
  IFS='|' read -r opts sel why <<<"$bad"
  coverage "$opts" "$sel"
  [ "$ec" -eq 3 ] && pass "T2.5 exit 3 on $why" || fail "T2.5 $why: exit $ec, $out"
done
set +e
printf '' | python3 "$READY" --coverage >/dev/null 2>&1; ec=$?
set -e
[ "$ec" -eq 4 ] && pass "T2.6 empty stdin is exit 4 (degrade)" || fail "T2.6 empty stdin: exit $ec"

# The basis: the list the IDs were numbered against.
basis() {
  printf '%s' "{\"issue\":$ISSUE,\"options\":[{\"number\":1,\"criteria_covered\":[\"AC1\",\"AC2\"]}],\"selected\":1,\"criteria\":$1}" \
    | python3 "$READY" --coverage | js 'd["verdict"]'
}
[ "$(basis '[{"id":"ac1","text":"every plan option  lists the criteria it covers"},{"id":"AC2","text":"Selecting an option that leaves a criterion uncovered stops planning (high confidence)"}]')" = covered ] \
  && pass "T2.7 a matching basis (case, spacing, confidence marker aside) stays covered" \
  || fail "T2.7 matching basis was not covered"
[ "$(basis '[{"id":"AC1","text":"Selecting an option that leaves a criterion uncovered stops planning"},{"id":"AC2","text":"Every plan option lists the criteria it covers"}]')" = renumbered ] \
  && pass "T2.8 IDs numbered against a reordered list are renumbered, never covered" \
  || fail "T2.8 reordered basis was not renumbered"
[ "$(basis '[{"id":"AC1","text":"Every plan option lists the criteria it covers"}]')" = renumbered ] \
  && pass "T2.9 a basis with a different criterion count is renumbered" \
  || fail "T2.9 short basis was not renumbered"
[ "$(basis '"AC1"')" = renumbered ] && pass "T2.10 a malformed basis is renumbered" \
  || fail "T2.10 malformed basis was not renumbered"
NESTED='{"body":"## Acceptance Criteria\n\n- [ ] parent\n  - detail a\n  - detail b\n- [ ] second\n"}'
[ "$(printf '%s' "$NESTED" | python3 "$READY" --criteria | js '[c["text"] for c in d["criteria"]]')" = "['parent', 'second']" ] \
  && pass "T2.11 nested sub-bullets are detail, never their own criterion" \
  || fail "T2.11 nested sub-bullets were numbered"
SIBLINGS='{"body":"## Acceptance Criteria\n\n - [ ] one\n- [ ] two\n 9. three\n10. four\n    - detail\n"}'
[ "$(printf '%s' "$SIBLINGS" | python3 "$READY" --criteria | js '[c["text"] for c in d["criteria"]]')" = "['one', 'two', 'three', 'four']" ] \
  && pass "T2.12 a 1-3-space sibling and a right-aligned number stay criteria" \
  || fail "T2.12 indented siblings were dropped"

# ── T3: readiness is unchanged ───────────────────────────────────────────
out="$(printf '%s' "$ISSUE" | python3 "$READY")"
[ "$(printf '%s' "$out" | js 'd["ready"]')" = "True" ] \
  && pass "T3.1 the #554-shaped body is still ready" || fail "T3.1 readiness: $out"
out="$(printf '%s' '{"number":1,"body":"## Acceptance Criteria\n\n- `only code`\n"}' | python3 "$READY")"
[ "$(printf '%s' "$out" | js 'd["reasons"]')" = "['no_criteria']" ] \
  && pass "T3.2 a code-span-only item is still not a criterion" || fail "T3.2 code-span item: $out"
for b in '`x` - foo' '-`x` foo'; do
  out="$(printf '%s' "{\"number\":1,\"body\":\"## Acceptance Criteria\\n\\n$b\\n\"}" | python3 "$READY")"
  [ "$(printf '%s' "$out" | js 'd["ready"]')" = "True" ] \
    && pass "T3.3 '$b' is still a criterion (marker found once code spans drop)" \
    || fail "T3.3 '$b': $out"
done
out="$(printf '%s' '{"number":1,"body":"## Acceptance Criteria\n\n- [ ] a\n  - b (needs review)\n"}' | python3 "$READY")"
[ "$(printf '%s' "$out" | js 'd["reasons"]')" = "['criteria_need_review']" ] \
  && pass "T3.4 a nested item's marker still fails readiness" || fail "T3.4 nested marker: $out"

# ── T4: the contract and the gate's one home ─────────────────────────────
has "$SYN" '`criteria_covered` (IDs of the criteria this option fully satisfies)' \
  "T4.1 the synthesizer's option fields include criteria_covered"
n="$(grep -c '"criteria_covered": \[' "$SYN")"
[ "$n" -ge 2 ] && pass "T4.2 every example option carries criteria_covered" \
  || fail "T4.2 expected criteria_covered on both example options, found $n"
has "$SYN" 'never one that leaves a criterion uncovered while another option covers them all' \
  "T4.3 the recommendation prefers full coverage"
has "$SYN" 'never a quoted Reporter Context' "T4.4 the synthesizer numbers only the real criteria"
n="$(grep -c 'a:rs-criteria-coverage' "$PLAN")"
[ "$n" -eq 1 ] && pass "T4.5 step-2-plan.md has one Criteria coverage gate section" \
  || fail "T4.5 expected one a:rs-criteria-coverage anchor, found $n"
has "$PLAN" '`gap` — **stop planning**, auto mode too' "T4.6 a gap stops planning in auto mode"
has "$PLAN" 'gi-ready.py --coverage' "T4.7 the gate runs the deterministic check"
has "$PLAN" 'or a *Criteria coverage gate* verdict other than `covered` — set `analysis_reuse = stale`' \
  "T4.8 a reused analysis that does not cover is stale"
has "$PLAN" '`analysis_reuse = stale` and spawns the synthesizer with the binding' \
  "T4.13 on reuse a non-covered verdict re-synthesizes instead of stopping"
has "$SYN" 'Return the list your IDs refer to as `criteria`' "T4.14 the synthesizer returns its numbering"
has "$ROOT/src/skills/issue-analysis/references/output-and-persist.md" '| `criteria` | array |' \
  "T4.15 the analysis persists the numbering its IDs refer to"
has "$RS/SKILL.source.md" '*Step 2 — Plan → Criteria coverage gate*' "T4.9 SKILL.md points to the one home"
has "$RS/references/error-messages.md" '### Plan leaves a criterion uncovered' "T4.10 the stop has an error block"
has "$RS/references/report-templates.md" '`Scope inside the issue` is `√` when the *Criteria coverage gate* returns' \
  "T4.11 Scope inside the issue has a procedure"
has "$ROOT/src/skills/issue-analysis/references/output-and-persist.md" '`options[].criteria_covered`' \
  "T4.12 the analysis schema lists the field"

# ── T5: built bundles ────────────────────────────────────────────────────
cmp -s "$READY" "$ROOT/skills/issue-resolver/references/scripts/gi-ready.py" \
  && pass "T5.1 issue-resolver bundles the current gi-ready.py" \
  || fail "T5.1 issue-resolver: gi-ready.py missing or differs"
for skill in issue-resolver issue-analysis; do
  grep -qF 'criteria_covered' "$ROOT/skills/$skill/references/agents/synthesizer.md" \
    && pass "T5.2 $skill's bundled synthesizer carries criteria_covered" \
    || fail "T5.2 $skill's bundled synthesizer lacks criteria_covered"
done
grep -qF 'a:rs-criteria-coverage' "$ROOT/skills/issue-resolver/references/steps/step-2-plan.md" \
  && pass "T5.3 the built Step 2 carries the gate" || fail "T5.3 the built Step 2 lacks the gate"

# ── T6: CI ───────────────────────────────────────────────────────────────
has "$WORKFLOW" 'run: bash tests/test-plan-criteria-coverage-554.sh' "T6.1 dist-check runs this test"

echo ""
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
if [ "$FAIL" -ne 0 ]; then
  echo "  ✗ Plan-to-criteria coverage tests failed"
  exit 1
fi
echo "  ✓ Plan-to-criteria coverage tests passed"
