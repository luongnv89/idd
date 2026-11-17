#!/usr/bin/env bash
# test-eval-grading-out-of-bundle-630.sh — eval-grading criteria are maintainer
# material: they live in evals/, never in a file a skill reads at run time
# (issue #630).
#
#   T1  no authored skill file and no built skill carries an eval-grading
#       section ("Evaluate report understanding", "Report-understanding
#       criteria", "## Understanding criteria");
#   T2  the SKILL pointers to those sections are gone (init-idd, idd-doctor),
#       and the read-only doctor no longer says to record answers on a PR;
#   T3  evals/report-understanding.md holds the four criteria, the feedback
#       rule, and one section per skill that had a grading section;
#   T4  evals/README.md links it, and the CI step exists.
#
# Usage: bash tests/test-eval-grading-out-of-bundle-630.sh
# Returns: exit 0 if all checks pass, exit 1 on failure
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RU="$ROOT/evals/report-understanding.md"
WORKFLOW="$ROOT/.github/workflows/dist-check.yml"

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
has() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3 (missing in ${1#"$ROOT"/})"; }
lacks() { grep -qF -- "$2" "$1" && fail "$3 (found in ${1#"$ROOT"/})" || pass "$3"; }

echo "◆ Eval grading lives outside the skill bundles (#630)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ── T1 — no runtime file carries a grading section ──────────────────────────
RUNTIME=("$ROOT/src/skills" "$ROOT/src/internal-skills" "$ROOT/src/shared" "$ROOT/skills")
for phrase in 'Evaluate report understanding' 'Report-understanding criteria' '## Understanding criteria'; do
  hits="$(grep -rlF -- "$phrase" "${RUNTIME[@]}" 2>/dev/null || true)"
  if [ -z "$hits" ]; then
    pass "T1: no skill file carries '$phrase'"
  else
    fail "T1: '$phrase' still in: $(echo "$hits" | sed "s|$ROOT/||" | tr '\n' ' ')"
  fi
done

# ── T2 — pointers to the moved sections ─────────────────────────────────────
lacks "$ROOT/src/skills/init-idd/SKILL.source.md" 'Grade report' \
  "T2.1: init-idd SKILL no longer points at grading criteria"
lacks "$ROOT/skills/init-idd/SKILL.md" 'Grade report' \
  "T2.2: the built init-idd SKILL no longer points at grading criteria"
DOC="$ROOT/src/internal-skills/idd-doctor"
lacks "$DOC/SKILL.source.md" 'Understanding criteria' \
  "T2.3: idd-doctor SKILL no longer points at understanding criteria"
lacks "$DOC/references/review-contract.md" 'criteria a reviewer grades' \
  "T2.4: the doctor's review contract no longer promises grading criteria"
# Join lines first: the sentence can wrap anywhere.
if find "$DOC" -type f -name '*.md' -exec cat {} + | tr -s ' \n' '  ' \
   | grep -qiF -- 'record the answers on the PR'; then
  fail "T2.5: idd-doctor still says to record answers on a PR or issue"
else
  pass "T2.5: idd-doctor never says to record answers on a PR or issue"
fi

# ── T3 — the maintainer guide ───────────────────────────────────────────────
if [ -f "$RU" ]; then
  pass "T3.1: evals/report-understanding.md exists"
  for criterion in 'Result is findable' 'Facts and assumptions are separate' \
                   'Claims are traceable' 'Next decision is clear'; do
    has "$RU" "| $criterion |" "T3.2: the guide defines '$criterion'"
  done
  has "$RU" 'leaves human understanding' "T3.3: missing feedback leaves understanding..."
  has "$RU" '**unconfirmed**' "T3.3: ...unconfirmed"
  has "$RU" '**Never record them on a PR' "T3.4: answers are never recorded on a PR or issue"
  has "$RU" '`human_review`' "T3.5: answers go in the case's human_review block"
  for skill in auto-pilot issue-resolver issue-analysis issue-triage issue-creator \
               issue-pr-review init-idd idd-doctor; do
    has "$RU" "## $skill" "T3.6: the guide has a $skill section"
  done
else
  fail "T3.1: evals/report-understanding.md is missing"
fi

# ── T4 — discoverability and CI ─────────────────────────────────────────────
has "$ROOT/evals/README.md" '(report-understanding.md)' "T4.1: evals/README.md links the guide"
grep -qF 'run: bash tests/test-eval-grading-out-of-bundle-630.sh' "$WORKFLOW" \
  && pass "T4.2: the CI step exists" || fail "T4.2: dist-check.yml lacks this test"

echo ""
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || { echo "  ✗ Eval-grading placement tests failed"; exit 1; }
echo "  ✓ Eval-grading placement tests passed"
