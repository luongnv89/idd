#!/usr/bin/env bash
# test-behavior-test-contracts-521.sh — the behavior-test contract carries a
# sensitivity check and an equivalence check, and test removal needs a reason
# (#521).
#
# AC1: Targeted mutations fail tests.
# AC2: Refactors retain pinned observable outputs, without blanket deletion of
#      legitimate negative tests.
#
#   B1  the implementer's Write-tests task: a hand-made targeted mutation must
#       turn the focused test red for the stated reason, then be restored;
#       manual only (no mutation framework, nothing committed); `not_verified`
#       never blocks.
#   B2  the same task: a no-behavior-change plan runs its pinned tests
#       (negative and error-path included) green first and keeps them
#       unedited; removing or weakening a test needs an AC or plan item.
#   B3  the implementer returns Sensitivity and Test Integrity records.
#   B4  the code reviewer blocks (`action: fix`) an unjustified removal; the
#       fixer's old "without justification" escape is gone.
#   B5  the resolver routes the records: Step 3 summary, Step 4 reviewer
#       context, PR-body evidence.
#   B6  the built bundles carry the new contract.
#   B7  sensitivity of this test itself: each targeted mutation of the
#       contract text turns the matching check red.
#   B8  the flaky-test policy (#663): implementer, fixer and reviewer ban a
#       skip, xfail, retry or sleep on an existing test (pinned in the B2/B4
#       checks); Step 4 treats a test that fails in one cycle and passes in a
#       later one with no change on its code path as flaky, never as evidence,
#       sends it to the fixer, holds the clean exit until it ends (both
#       statements of that exit say so), and gives it three endings, the
#       follow-up one opened by the main agent with acceptance criteria;
#       the Decision Record says which, or `open`; a flaky record is the
#       one other reason to delete a
#       test, and justifies a deletion only. The reviewer's ban spares a skip
#       a criterion or plan item asks for. Source, built copies, and a
#       targeted mutation per pin.
#
# Usage: bash tests/test-behavior-test-contracts-521.sh
# Returns: exit 0 if all checks pass, exit 1 on failure.

# No `set -e`: assertions report and continue.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "0" ]; then pass "$1"; else fail "$1"; fi; }

# shellcheck source=lib/anchors.bash
. "$REPO_ROOT/tests/lib/anchors.bash"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

AGENTS="$REPO_ROOT/src/shared/agents"
IMPL="$AGENTS/implementer.md"
CR="$AGENTS/code-reviewer.md"
FIXER="$AGENTS/fixer.md"
RS="$REPO_ROOT/src/skills/issue-resolver"
STEP3="$RS/references/steps/step-3-implement.md"
STEP4="$RS/references/steps/step-4-qa.md"
TEMPLATES="$RS/references/report-templates.md"

# section FILE HEADING — the lines from the ### heading that starts with
# HEADING up to the next heading, joined into one line.
section() {
  awk -v h="$2" '
    index($0, h) == 1 { on = 1; print; next }
    on && /^#+ / { exit }
    on { print }
  ' "$1" | tr '\n' ' '
}

has() { printf '%s\n' "$1" | grep -qE -- "$2"; }

# Each check function returns 0 only when every stem holds, so B7 can run the
# same function against a mutated copy and expect it to fail.
sensitivity_ok() {
  local s
  s="$(section "$1" '### 2–4. Write tests')"
  has "$s" 'targeted mutation must fail the test' &&
    has "$s" 'revert or perturb the hunk' &&
    has "$s" 'run only that focused test' &&
    has "$s" 'fails for the stated reason' &&
    has "$s" 'restore the hunk' &&
    has "$s" 'Never commit a mutation' &&
    has "$s" 'never add a mutation framework' &&
    has "$s" '`not_verified`' &&
    has "$s" 'never block'
}

equivalence_ok() {
  local s
  s="$(section "$1" '### 2–4. Write tests')"
  has "$s" 'declares no behavior change' &&
    has "$s" 'negative and error-path tests' &&
    has "$s" 'run them green' &&
    has "$s" 'characterization test first' &&
    has "$s" 'pass \*\*unedited\*\*'
}

removal_ok() {
  local s
  s="$(section "$1" '### 2–4. Write tests')"
  has "$s" '\*\*only\*\* when an acceptance criterion or plan item removes the behavior' &&
    has "$s" 'Never remove a test, or add a skip, xfail, retry or sleep to an existing test, just to turn the suite green'
}

reviewer_ok() {
  grep -qE '^   - \*\*Test integrity\*\* \(category `test_coverage`\):.*no acceptance criterion or plan item' "$1" &&
    grep -qE 'behavior-preserving edits an existing test.s expected output' "$1" &&
    grep -qE '^   - \*\*Test integrity\*\*.*removes the behavior it pinned, and, for a deleted test, neither records it as flaky; or it adds' "$1" &&
    grep -qE '^   - \*\*Test integrity\*\*.*; or it adds a skip, xfail, retry or sleep to an existing test' "$1" &&
    grep -qE '^   - \*\*Test integrity\*\*.*to an existing test that no criterion or plan item asks for; or a change' "$1" &&
    grep -qE '^   - \*\*"fix"\*\*:.*a test-integrity break at any severity' "$1"
}

fixer_ok() {
  ! grep -q 'without justification' "$1" &&
    grep -qE '^- Never hide a failing test by deleting it, dropping or loosening an assertion, retiring a negative test' "$1" &&
    grep -qE 'only when an acceptance criterion or plan item removes the behavior it pins, and name that criterion' "$1" &&
    grep -qE '^- Never hide a failing test.*Delete a test a finding records as flaky only when no root cause is found, and name that reason' "$1" &&
    grep -qE '^- Never hide a failing test.*Never add a skip, xfail, retry or sleep to an existing test' "$1"
}

# flaky_rule_ok STEP4 — the Evaluate block carries the one full statement of
# the flaky rule, and its clean-exit bullet waits for an open flaky test.
flaky_rule_ok() {
  local r
  r="$(anchor_region "$1" rs-qa-evaluate)" || return 1
  r="$(printf '%s\n' "$r" | tr '\n' ' ')"
  has "$r" 'AND no static check failed AND no flaky test is open → exit loop, QA passed\.' &&
    has "$r" 'failed in an earlier cycle and passes now with no change on its code path is \*\*flaky\*\*: never evidence for a criterion' &&
    has "$r" 'and a finding for the fixer' &&
    has "$r" 'that keeps the cycle from clean until it ends root-caused' &&
    has "$r" 'root-caused, deleted with the reason written down, or — only when it covers no criterion — tracked in a follow-up issue the main agent opens with acceptance criteria\.' &&
    has "$r" 'The Decision Record.s \*Flaky tests\* line says which'
}

# flaky_exit_ok STEP4 — Loop controls' statement of the clean exit waits for
# an open flaky test too.
flaky_exit_ok() {
  grep -qE '^- \*\*Exit on clean:\*\* stop as soon as review passes AND tests pass AND no static check failed AND no flaky test is open$' "$1"
}

# flaky_record_ok TEMPLATES — the Decision Record line sits directly after
# Premise reset and names the three endings and the open state.
flaky_record_ok() {
  awk '
    prev ~ /^- \*\*Premise reset:\*\* / && /^- \*\*Flaky tests:\*\* / { found = 1 }
    { prev = $0 }
    END { exit found ? 0 : 1 }
  ' "$1" &&
    grep -qE '^- \*\*Flaky tests:\*\* \{only when Step 4 found one — .*: root-caused \| deleted: <reason> \| follow-up #<n> \| open; omit otherwise\}$' "$1"
}

# flaky_pointer_ok STEP4 TEMPLATES — the Decision Record line Step 4 names
# exists under that label in the template.
flaky_pointer_ok() {
  local label
  label="$(grep -oE "Decision Record.s \*[^*]+\* line says which" "$1" | sed -E 's/^[^*]*\*([^*]+)\*.*$/\1/')"
  [ -n "$label" ] && grep -qF -- "- **${label}:** " "$2"
}

echo "◆ Behavior-test sensitivity and equivalence (issue #521)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ── B1–B3: the implementer contract ──────────────────────────
sensitivity_ok "$IMPL"; check "B1: a targeted, manual, restored mutation must turn the focused test red" "$?"
s="$(section "$IMPL" '### 2–4. Write tests')"
has "$s" 'Write one focused test per behavior stated in the plan or an acceptance criterion'
check "B1: the one-focused-test-per-behavior rule is kept" "$?"
has "$s" 'confirmed red in Task 1.5 already meets this'
check "B1: a bug regression test confirmed red already counts as sensitive" "$?"
equivalence_ok "$IMPL"; check "B2: a no-behavior-change plan keeps its pinned outputs, negative tests included, unedited" "$?"
removal_ok "$IMPL"; check "B2: a test is removed or weakened only when an AC or plan item removes its behavior" "$?"
grep -qE '^- \*\*Sensitivity\*\* — one row per acceptance-criterion test' "$IMPL"
check "B3: the implementer returns a Sensitivity record" "$?"
grep -qE '^- \*\*Test Integrity\*\* — \*\*Pinned outputs\*\*.*\*\*Removed or weakened\*\*' "$IMPL"
check "B3: the implementer returns a Test Integrity record" "$?"
grep -qE '^- \*\*Returns:\*\*.*Sensitivity, Test Integrity' "$IMPL"
check "B3: the contract's Returns line names both records" "$?"

# ── B4: reviewer and fixer ───────────────────────────────────
reviewer_ok "$CR"; check "B4: the code reviewer blocks an unjustified deleted or weakened test" "$?"
fixer_ok "$FIXER"; check "B4: the fixer removes a test only with a named AC or plan item, or a recorded flaky finding" "$?"
grep -qE 'when it must not change, keep the tests pinning it unedited' "$FIXER"
check "B4: a behavior-preserving fix keeps its pinned tests unedited" "$?"

# ── B5: the resolver routes the records ──────────────────────
anchor_check_flat "$STEP3" rs-test-sensitivity 'never a mutation framework, never the full suite, never a committed mutation' \
  "B5: Step 3 keeps the mutation check manual and focused"
anchor_check_flat "$STEP3" rs-test-sensitivity 'passing \*\*unedited\*\*' \
  "B5: Step 3 keeps pinned tests unedited"
anchor_check_flat "$STEP3" rs-test-sensitivity 'no blanket ban' \
  "B5: Step 3 states removal is justified, not banned"
anchor_check_flat "$STEP3" rs-test-sensitivity '\*\*Auto mode never blocks:\*\*.*`not_verified`' \
  "B5: Step 3 never blocks auto mode"
anchor_check_flat "$STEP4" rs-step4-qa 'bind `\{pr_context\}` to the issue.s acceptance criteria, the selected plan and the implementer.s \*Test Integrity\* and \*Practices\* records' \
  "B5: Step 4 gives the reviewer the criteria and the Test Integrity record"
grep -qF 'Sensitive: <test> fails with <mutation> → restored green' "$TEMPLATES"
check "B5: the PR body cites sensitivity evidence per criterion" "$?"
grep -qF 'sensitivity not verified: <reason>' "$TEMPLATES"
check "B5: an unverified sensitivity check marks its criterion unverified" "$?"
grep -qE '^- Test integrity: ' "$TEMPLATES"
check "B5: the PR body's Test Results carries the Test Integrity line" "$?"

# ── B6: the built bundles ────────────────────────────────────
BUILT_IMPL="$REPO_ROOT/skills/issue-resolver/references/agents/implementer.md"
sensitivity_ok "$BUILT_IMPL" && equivalence_ok "$BUILT_IMPL" && removal_ok "$BUILT_IMPL"
check "B6: skills/issue-resolver ships the implementer contract" "$?"
for skill in issue-resolver issue-pr-review; do
  reviewer_ok "$REPO_ROOT/skills/$skill/references/agents/code-reviewer.md"
  check "B6: skills/$skill ships the code-reviewer rule" "$?"
  fixer_ok "$REPO_ROOT/skills/$skill/references/agents/fixer.md"
  check "B6: skills/$skill ships the fixer rule" "$?"
done

# ── B7: targeted mutations of the contract fail these checks ─
mutate() { # mutate SRC NAME PYTHON-REPLACEMENT-ARGS...
  local src="$1" out="$TMP/$2"
  python3 - "$src" "$out" "$3" "$4" <<'PY'
import sys
src, out, old, new = sys.argv[1:5]
text = open(src, encoding="utf-8").read()
if old not in text:
    sys.exit(1)
open(out, "w", encoding="utf-8").write(text.replace(old, new, 1))
PY
}

mutate "$IMPL" impl-no-restore.md 'Then restore the hunk, re-run it green, and' 'Then' \
  && ! sensitivity_ok "$TMP/impl-no-restore.md"
check "B7: dropping the restore step turns the sensitivity check red" "$?"
mutate "$IMPL" impl-framework.md 'never add a mutation framework' 'add a mutation framework when useful' \
  && ! sensitivity_ok "$TMP/impl-framework.md"
check "B7: allowing a mutation framework turns the sensitivity check red" "$?"
mutate "$IMPL" impl-no-negatives.md 'and the negative and error-path tests that pin each rejection' '' \
  && ! equivalence_ok "$TMP/impl-no-negatives.md"
check "B7: dropping negative tests from the pinned set turns the equivalence check red" "$?"
mutate "$IMPL" impl-edited.md 'pass **unedited**' 'pass' \
  && ! equivalence_ok "$TMP/impl-edited.md"
check "B7: allowing edited pinned tests turns the equivalence check red" "$?"
mutate "$IMPL" impl-ban.md '**only** when an acceptance criterion or plan item removes the behavior it pins' 'never' \
  && ! removal_ok "$TMP/impl-ban.md"
check "B7: a blanket ban on removal turns the removal check red" "$?"
mutate "$CR" cr-note.md '; a test-integrity break at any severity' '' \
  && ! reviewer_ok "$TMP/cr-note.md"
check "B7: demoting a test-integrity break to a note turns the reviewer check red" "$?"
mutate "$FIXER" fixer-escape.md 'retiring a negative test, or suppressing an error.' 'or suppressing errors without justification.' \
  && ! fixer_ok "$TMP/fixer-escape.md"
check "B7: restoring the 'without justification' escape turns the fixer check red" "$?"

# ── B8: the flaky-test policy ────────────────────────────────
flaky_rule_ok "$STEP4"; check "B8: Step 4 treats a fail-then-pass test with no change on its code path as flaky, never as evidence" "$?"
flaky_exit_ok "$STEP4"; check "B8: Loop controls' Exit on clean waits for an open flaky test" "$?"
flaky_record_ok "$TEMPLATES"; check "B8: the Decision Record's Flaky tests line names the three endings and the open state" "$?"
flaky_pointer_ok "$STEP4" "$TEMPLATES"; check "B8: the line Step 4 points to exists in the PR body template" "$?"
BUILT_RS="$REPO_ROOT/skills/issue-resolver/references"
flaky_rule_ok "$BUILT_RS/steps/step-4-qa.md" && flaky_exit_ok "$BUILT_RS/steps/step-4-qa.md" && flaky_record_ok "$BUILT_RS/report-templates.md" &&
  flaky_pointer_ok "$BUILT_RS/steps/step-4-qa.md" "$BUILT_RS/report-templates.md"
check "B8: skills/issue-resolver ships the flaky rule and its Decision Record line" "$?"

mutate "$IMPL" impl-skip.md ', or add a skip, xfail, retry or sleep to an existing test,' '' \
  && ! removal_ok "$TMP/impl-skip.md"
check "B8: dropping the implementer's skip/xfail/retry/sleep ban turns the removal check red" "$?"
mutate "$FIXER" fixer-sleep.md 'Never add a skip, xfail, retry or sleep to an existing test.' 'Never add a skip, xfail or retry to an existing test.' \
  && ! fixer_ok "$TMP/fixer-sleep.md"
check "B8: dropping 'sleep' from the fixer's ban turns the fixer check red" "$?"
mutate "$FIXER" fixer-no-cause.md ' only when no root cause is found' '' \
  && ! fixer_ok "$TMP/fixer-no-cause.md"
check "B8: deleting a flaky test without seeking its root cause turns the fixer check red" "$?"
mutate "$CR" cr-no-flaky.md ', and, for a deleted test, neither records it as flaky' '' \
  && ! reviewer_ok "$TMP/cr-no-flaky.md"
check "B8: dropping the flaky record from the reviewer's deletion reasons turns the reviewer check red" "$?"
mutate "$CR" cr-flaky-wide.md ', and, for a deleted test, neither records it as flaky' ', and neither records it as flaky' \
  && ! reviewer_ok "$TMP/cr-flaky-wide.md"
check "B8: letting a flaky record excuse a loosened assertion turns the reviewer check red" "$?"
mutate "$CR" cr-no-ban.md '; or it adds a skip, xfail, retry or sleep to an existing test' '' \
  && ! reviewer_ok "$TMP/cr-no-ban.md"
check "B8: dropping the reviewer's skip/xfail/retry/sleep ban turns the reviewer check red" "$?"
mutate "$CR" cr-no-exception.md ' that no criterion or plan item asks for' '' \
  && ! reviewer_ok "$TMP/cr-no-exception.md"
check "B8: flagging a skip that a criterion or plan item asks for turns the reviewer check red" "$?"
mutate "$STEP4" step4-evidence.md '**flaky**: never evidence for a criterion' '**flaky**: evidence for a criterion' \
  && ! flaky_rule_ok "$TMP/step4-evidence.md"
check "B8: letting a flaky test count as evidence turns the Step 4 check red" "$?"
mutate "$STEP4" step4-not-flaky.md 'with no change on its code path is **flaky**' 'is green' \
  && ! flaky_rule_ok "$TMP/step4-not-flaky.md"
check "B8: accepting a fail-then-pass test as green turns the Step 4 check red" "$?"
mutate "$STEP4" step4-follow-up.md ' — only when it covers no criterion —' '' \
  && ! flaky_rule_ok "$TMP/step4-follow-up.md"
check "B8: a follow-up for a test that covers a criterion turns the Step 4 check red" "$?"
mutate "$STEP4" step4-no-fixer.md 'a finding for the fixer that keeps' 'a finding that keeps' \
  && ! flaky_rule_ok "$TMP/step4-no-fixer.md"
check "B8: a flaky finding that never reaches the fixer turns the Step 4 check red" "$?"
mutate "$STEP4" step4-clean.md ' that keeps the cycle from clean until it ends root-caused' '. It ends root-caused' \
  && ! flaky_rule_ok "$TMP/step4-clean.md"
check "B8: a flaky test that lets the cycle exit clean turns the Step 4 check red" "$?"
mutate "$STEP4" step4-exit.md 'AND no static check failed AND no flaky test is open → exit loop' 'AND no static check failed → exit loop' \
  && ! flaky_rule_ok "$TMP/step4-exit.md"
check "B8: a clean-exit bullet that ignores an open flaky test turns the Step 4 check red" "$?"
mutate "$STEP4" step4-loop-exit.md 'tests pass AND no static check failed AND no flaky test is open' 'tests pass AND no static check failed' \
  && ! flaky_exit_ok "$TMP/step4-loop-exit.md"
check "B8: an Exit on clean that ignores an open flaky test turns the Loop controls check red" "$?"
mutate "$STEP4" step4-no-actor.md 'tracked in a follow-up issue the main agent opens with' 'tracked in a follow-up issue with' \
  && ! flaky_rule_ok "$TMP/step4-no-actor.md"
check "B8: a follow-up issue with no one to open it turns the Step 4 check red" "$?"
mutate "$STEP4" step4-no-criteria.md ' the main agent opens with acceptance criteria.' ' the main agent opens.' \
  && ! flaky_rule_ok "$TMP/step4-no-criteria.md"
check "B8: a follow-up issue opened without acceptance criteria turns the Step 4 check red" "$?"
mutate "$STEP4" step4-no-record.md " The Decision Record's *Flaky tests* line says which." '' \
  && ! flaky_rule_ok "$TMP/step4-no-record.md"
check "B8: dropping the Decision Record pointer turns the Step 4 check red" "$?"
mutate "$TEMPLATES" tpl-no-reason.md 'deleted: <reason>' 'deleted' \
  && ! flaky_record_ok "$TMP/tpl-no-reason.md"
check "B8: a deletion with no written reason turns the Decision Record check red" "$?"
mutate "$TEMPLATES" tpl-no-open.md ' | follow-up #<n> | open; omit otherwise}' ' | follow-up #<n>; omit otherwise}' \
  && ! flaky_record_ok "$TMP/tpl-no-open.md"
check "B8: no spelling for a flaky test still open at Deliver turns the Decision Record check red" "$?"
mutate "$TEMPLATES" tpl-renamed.md '- **Flaky tests:** ' '- **Unstable tests:** ' \
  && ! flaky_pointer_ok "$STEP4" "$TMP/tpl-renamed.md"
check "B8: renaming the template line turns the pointer check red" "$?"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
