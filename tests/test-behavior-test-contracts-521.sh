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
    has "$s" 'Never remove a test just to turn the suite green'
}

reviewer_ok() {
  grep -qE '^   - \*\*Test integrity\*\* \(category `test_coverage`\):.*no acceptance criterion or plan item' "$1" &&
    grep -qE 'behavior-preserving edits an existing test.s expected output' "$1" &&
    grep -qE '^   - \*\*"fix"\*\*:.*a test-integrity break at any severity' "$1"
}

fixer_ok() {
  ! grep -q 'without justification' "$1" &&
    grep -qE '^- Never hide a failing test by deleting it, dropping or loosening an assertion, retiring a negative test' "$1" &&
    grep -qE 'only when an acceptance criterion or plan item removes the behavior it pins, and name that criterion' "$1"
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
fixer_ok "$FIXER"; check "B4: the fixer removes a test only with a named AC or plan item" "$?"
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
anchor_check_flat "$STEP4" rs-step4-qa 'bind `\{pr_context\}` to the issue.s acceptance criteria, the selected plan and the implementer.s \*Test Integrity\* record' \
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

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
