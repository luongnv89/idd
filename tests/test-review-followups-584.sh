#!/usr/bin/env bash
# test-review-followups-584.sh — the non-blocking review notes from the epic
# #547 P0/P1 PRs are fixed in place (issue #584).
#
# The behavioural fixes are tested beside the scripts they change
# (test-progress-records-542.sh p584*, test-criteria-evidence-555.sh T3.8-9,
# test-issue-readiness-553.sh T1.12-15, test-bug-proof-556.sh T1.12i-m). This
# file pins the prose that has no script behind it:
#
#   T1  the deferred-row exclusion is scoped to `Refs #N` PRs everywhere;
#   T2  a resumed auto-pilot run never merges on a missing merge_floor;
#   T3  a resolver resumed after the plan re-runs the Criteria coverage gate;
#   T4  every statement of the code-reviewer threshold exempts constraints;
#   T5  the explicit-list readiness check reuses the retained record;
#   T6  issue-analysis hands its synthesizer the numbered criteria;
#   T7  the built skills carry the changes, and the CI step exists.
#
# Usage: bash tests/test-review-followups-584.sh
# Returns: exit 0 if all checks pass, exit 1 on failure
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/src/skills"
AP="$SRC/auto-pilot/references"
WORKFLOW="$ROOT/.github/workflows/dist-check.yml"

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
has() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3 (missing in ${1#"$ROOT"/})"; }
lacks() { grep -qF -- "$2" "$1" && fail "$3 (found in ${1#"$ROOT"/})" || pass "$3"; }

echo "◆ Review follow-ups (#584)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# T1 — every statement that excludes deferred rows names the Refs #N scope.
# A `Closes #N` PR's deferred row is `unverified`, so an unscoped statement
# would log it `verification: full` (#551).
unscoped=""
while IFS= read -r line; do
  printf '%s' "$line" | grep -qF 'Refs #N' || unscoped="$unscoped
    $line"
done < <(cd "$ROOT" && grep -rniE 'deferred rows? excluded|non-deferred' src docs \
           --include='*.md' | grep -v -e '^docs/release-notes/' -e '^docs/decisions/' -e '^docs/experiments/' || true)
[ -z "$unscoped" ] && pass "T1.1: every deferred-row exclusion is scoped to a \`Refs #N\` PR" \
  || fail "T1.1: unscoped deferred-row exclusion:$unscoped"
has "$SRC/issue-resolver/references/report-templates.md" 'excluded only on a `Refs #N` PR' "T1.2: the resolver's verification bullet carries the scope"
has "$ROOT/docs/run-log-schema.md" 'a deferred row excluded only on a `Refs #N` PR' "T1.3: the run-log schema's verification row carries the scope"
has "$SRC/issue-pr-review/SKILL.source.md" 'deferred rows excluded only on a `Refs #N` PR' "T1.4: the *Merge floor* carries the scope"
has "$AP/subagent-prompts.md" '(deferred rows excluded only on a `Refs #N` PR)' "T1.5: the auto-pilot reviewer's criteria counts carry the scope"
has "$SRC/issue-resolver/references/report-templates.md" '(`gi-runlog.py` exits 3 without it); omit otherwise.' "T1.6: breach_reason says when exit 3 happens, and to omit it otherwise"

# T2 — a run resumed at merge re-derives merge_floor; never a bare "unmet".
has "$AP/phases/phase-0-lock-resume.md" '**A recorded `merge` phase re-enters at review.**' "T2.1: a resumed singleton at merge re-enters at review"
has "$AP/phases/phase-0-lock-resume.md" 're-derives `merge_floor` from the live PR' "T2.2: the review re-derives merge_floor from the live PR"
has "$AP/phases/phase-0-lock-resume.md" '(a `merge` lane re-enters at review, as above)' "T2.3: a parallel lane at merge re-enters at review"
has "$AP/phases/phase-3-4-review.md" '`merge` included, since `merge_floor` is not recorded' "T2.4: the post-review checkpoint says why merge re-enters at review"
fallback="$(grep -F 'merge floor not derived (resumed run)' "$AP/phases/phase-5-merge.md" | sed 's/.*A missing `merge_floor`//' || true)"
if [ -n "$fallback" ] && ! printf '%s' "$fallback" | grep -qF 'merge floor unmet'; then
  pass "T2.5: a missing merge_floor is left open with its own reason, not \"merge floor unmet\""
else
  fail "T2.5: Phase 5.1 lacks a distinct reason for a missing merge_floor"
fi
lacks "$ROOT/src/shared/scripts/gi-state.py" 'merge_floor' "T2.6: run state never records merge_floor (state is a hint, never a gate fact)"
has "$AP/phases/phase-3-4-review.md" 'all four gates pass — merge floor, dependency, CI and merge identity' "T2.7: Step 2a counts the merge floor among its gates"
lacks "$AP/phases/phase-3-4-review.md" 'all three gates' "T2.8: Step 2a/2b no longer say all three gates"
has "$AP/phases/phase-5-merge.md" 'use the same Step 5.1 merge floor, the Step 5.1b dependency gate' "T2.9: Step 5.2's partial-merge gates include the merge floor"
has "$AP/phases/phase-3-4-review.md" 'run as `--auto --no-merge`; the merge itself is Phase 5'"'"'s' "T2.10: Phase 3-4 no longer says it delegates merging"

# T3 — the restored plan re-runs the coverage gate against the live body.
RS0J="$SRC/issue-resolver/references/steps/step-0j-resume.md"
has "$RS0J" 'a:rs-0j-coverage' "T3.1: step-0j has a *Restored plan gates* section"
has "$RS0J" "Step 2's *Criteria" "T3.2: it points at Step 2's gate rather than restating it"
grep -qF '`covered` — or `no_criteria` with an empty recorded `criteria` — keeps the' "$RS0J" \
  && pass "T3.3: only covered (or no criteria then and now) keeps the restored plan" \
  || fail "T3.3: the keep condition is missing"
has "$RS0J" '`renumbered`, a record without those' "T3.4: a renumbered verdict or an old record discards the plan"
has "$RS0J" 'the *Criteria coverage gate* and the *Sensitive-change gate* re-run' "T3.5: the k=3 row re-runs both gates"
tr '\n' ' ' < "$SRC/issue-resolver/references/steps/step-0j-progress-record.md" | grep -qF '`criteria_covered` and the `criteria` list those IDs were numbered against' \
  && pass "T3.6: the plan summary records the criteria fields" || fail "T3.6: the plan summary lacks the criteria fields"
has "$SRC/issue-resolver/references/steps/step-2-plan.md" 'The `[3/5]` progress write' "T3.7: Step 2 says the progress write records the mapping"

# T4 — the confidence threshold is never stated without the constraint exemption.
has "$ROOT/src/shared/agents/code-reviewer.md" '(default 80 if unset) — except a stated-constraint finding' "T4.1: the code-reviewer prompt line exempts constraints"
awk '/^## Confidence scale \(review agents\)/{on=1;next} on&&/^## /{exit} on' "$ROOT/docs/shared-agent-conventions.md" \
  | tr '\n' ' ' | grep -qF 'stated-constraint finding and a challenge-mode blocker at any confidence' \
  && pass "T4.2: *Confidence scale (review agents)* exempts constraints and blockers" \
  || fail "T4.2: *Confidence scale (review agents)* drops findings below threshold without exception"
has "$SRC/issue-pr-review/references/review-loop-mechanics.md" 'except a `constraints` finding, reported at any confidence' "T4.3: the reviewer spawn's threshold bullet exempts constraints"
has "$SRC/issue-pr-review/references/review-loop-mechanics.md" 'a `constraints` finding is reported at any confidence. The ui-reviewer' "T4.4: the config table row exempts constraints"
# Any other line in the reviewer prompt that states the floor must carry an exception.
bare="$(grep -nE 'confidence >= \{confidence_threshold\}|Report only >= \{confidence_threshold\}' "$ROOT/src/shared/agents/code-reviewer.md" \
  | grep -viE 'constraint' || true)"
[ -z "$bare" ] && pass "T4.5: every threshold line in code-reviewer.md names the constraint exemption" \
  || fail "T4.5: a threshold line lacks the exemption: $bare"

# T5 — one body snapshot in explicit-list mode.
has "$AP/explicit-list-mode.md" 'pipe the retained `explicit_issue_records[N]`' "T5.1: the readiness check pipes the retained record"
lacks "$AP/explicit-list-mode.md" 'gi-issue.py {N} --fields number,body' "T5.2: it no longer re-reads the body with gi-issue.py"

# T5b — the *Issue Readiness* fallback matches gi-ready.py: a marker ending any line of a criterion.
has "$ROOT/docs/idd-methodology.md" 'ends with `(needs review)` — on any of its lines' "T5.3: the readiness fallback reads a marker on any wrapped line"
lacks "$ROOT/docs/idd-methodology.md" 'on its last wrapped line' "T5.4: the fallback no longer limits the marker to the last line"

# T6 — issue-analysis numbers the criteria for its synthesizer.
has "$SRC/issue-analysis/references/subagent-steps.md" '"criteria": <numbered criteria>' "T6.1: the synthesizer payload carries criteria"
has "$SRC/issue-analysis/references/subagent-steps.md" 'shared/scripts/gi-ready.py --criteria' "T6.2: the criteria come from gi-ready.py --criteria"
has "$SRC/issue-analysis/references/inline-fallback.md" '**Criteria covered**' "T6.3: the inline fallback maps options to criteria"
has "$SRC/issue-analysis/references/output-and-persist.md" '"criteria_covered": ["AC1"]' "T6.4: the example JSON carries options[].criteria_covered"
has "$SRC/issue-analysis/references/output-and-persist.md" '"criteria": [{ "id": "AC1"' "T6.5: the example JSON carries criteria"
has "$SRC/issue-analysis/references/output-and-persist.md" 'require both when present' "T6.6: *Validate analysis data* checks the criteria fields"
has "$SRC/issue-analysis/SKILL.source.md" '`references/scripts/gi-ready.py`' "T6.7: the precheck lists the bundled gi-ready.py"

# T7 — built skills and CI.
DIST="$ROOT/skills"
has "$DIST/issue-pr-review/SKILL.md" 'deferred rows excluded only on a `Refs #N` PR' "T7.1: the built *Merge floor* carries the scope"
has "$DIST/auto-pilot/references/phases/phase-0-lock-resume.md" 'a:ap-step10-merge-reentry' "T7.2: the built auto-pilot re-enters merge at review"
has "$DIST/issue-pr-review/references/agents/code-reviewer.md" '(default 80 if unset) — except a stated-constraint finding' "T7.3: the built code-reviewer carries the exemption"
[ -f "$DIST/issue-analysis/references/scripts/gi-ready.py" ] \
  && cmp -s "$DIST/issue-analysis/references/scripts/gi-ready.py" "$ROOT/src/shared/scripts/gi-ready.py" \
  && pass "T7.4: issue-analysis bundles gi-ready.py byte-identical" || fail "T7.4: issue-analysis lacks gi-ready.py — rebuild skills/"
grep -qF 'run: bash tests/test-review-followups-584.sh' "$WORKFLOW" \
  && pass "T7.5: the CI step exists" || fail "T7.5: dist-check.yml lacks this test"

echo ""
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || { echo "  ✗ Review follow-up tests failed"; exit 1; }
echo "  ✓ Review follow-up tests passed"
