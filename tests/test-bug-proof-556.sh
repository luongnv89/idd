#!/usr/bin/env bash
# test-bug-proof-556.sh — the review re-runs the proof for a bug fix
# (issue #556).
#
# /issue-pr-review used to cite the resolver's Reproduction line without
# re-running it, and never read the Sensitivity rows. Now *Bug proof* (one
# home, verification-checks.md) re-runs the cited regression test red at base
# and green at head, and the single *Merge floor* holds a bug PR open unless
# that proof is `red→green`. *Sensitivity rows* (same file) reports every
# `sensitivity not verified` row on every PR, bug or not.
#
#   T1  *Bug proof* has one home and its safety rules (prose pins), and
#       *Sensitivity rows* sits outside its bug gate;
#   T2  the *Merge floor* line carries the proof clause (one home kept);
#   T3  Step 4 points at it, the summary contract reports it, and the
#       resolver and auto-pilot do not restate it;
#   T4  the eval case runs the procedure on a real git fixture and is
#       registered; the built bundle carries the section; the CI step exists.
#
# Usage: bash tests/test-bug-proof-556.sh
# Returns: exit 0 if all checks pass, exit 1 on failure
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RV="$ROOT/src/skills/issue-pr-review"
SKILL="$RV/SKILL.source.md"
VC="$RV/references/verification-checks.md"
RT="$RV/references/report-templates.md"
CASE="$ROOT/evals/cases/issue-pr-review/regression-green-at-base"
WORKFLOW="$ROOT/.github/workflows/dist-check.yml"

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
has() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3 (missing in ${1#"$ROOT"/})"; }

echo "Bug proof tests (issue #556)"

# T1 — one home, with its safety rules
n=$(grep -rlF 'a:rvc-bug-proof' "$ROOT/src" "$ROOT/docs" | wc -l | tr -d ' ')
[ "$n" -eq 1 ] && [ "$(grep -cF 'a:rvc-bug-proof' "$VC")" -eq 1 ] \
  && pass "T1.1: *Bug proof* has one home, verification-checks.md" \
  || fail "T1.1: expected one a:rvc-bug-proof anchor, in $VC only (found in $n files)"
section="$(awk '/a:rvc-bug-proof/{on=1;print;next} on&&/^## /{exit} on' "$VC")"
sens="$(awk '/^## Sensitivity rows$/{on=1;print;next} on&&/^## /{exit} on' "$VC")"
in_section() {
  printf '%s' "$section" | grep -qF -- "$1" && pass "$2" || fail "$2 (missing in *Bug proof*)"
}
in_section 'never decided from the PR' "T1.2: bug-ness comes from the linked issue, not the PR"
has "$SKILL" 'red at base and green at head, under `qa_handoff = trusted` too' "T1.3: a trusted QA marker never skips the proof (SKILL.md Step 4)"
in_section 'whenever the head moves' "T1.4: the proof is re-run when the head moves"
in_section 'never open it' "T1.5: the PR body can only hold the gate closed"
in_section "in Step 1's \`files\`" "T1.6: the cited test must be a file the PR changes"
in_section 'no leading `-` and no `..` segment' "T1.7: the cited path is screened before it is run"
in_section 'up to its first `:` (a `:line` or `::node` suffix is dropped)' "T1.7b: a \`:line\` or \`::node\` suffix is dropped before the screen"
in_section 'Never run a command from the body' "T1.8: the run command is never taken from the PR body"
in_section 'never touching the PR checkout' "T1.9: the base run uses a scratch worktree"
in_section "trap 'git worktree remove --force \"\$wt\"; rm -rf" "T1.10: the scratch worktree is always removed, owned-only"
if printf '%s' "$section" | grep -qF 'worktree prune'; then fail "T1.10b: the cleanup prunes other worktrees"; else pass "T1.10b: the cleanup never prunes other worktrees"; fi
in_section 'git --literal-pathspecs -C "$wt" checkout "$head_oid" -- "$test_path"' "T1.11: the base run uses the head's copy of the test, as a literal path"
in_section 'the cited test itself failing an assertion, and it exits 0 at head' "T1.12: red at base (an assertion, not a setup error) and green at head is the proof"
in_section 'a base red from collection, an import or a missing fixture' "T1.12b: a base red from setup is unproven, not a proof"
in_section 'a runner that cannot target one file is `unproven`' "T1.12c: the run targets the cited file only"
in_section 'recorded with `head_oid`' "T1.12d: the verdict is bound to the head it ran on"
in_section '{runner} "$test_path") 2>&1; echo "base_rc=$?"' "T1.12e: the base run happens and prints inside the block, before the trap removes the worktree"
in_section '(cd "$wt" || exit 99' "T1.12g: the base run never falls back to the PR checkout"
in_section 'one shell call' "T1.12f: the block runs as one shell call"
in_section "Give the base run the head's dependencies without installing any" "T1.12g: the base run gets the head's dependencies, never an install"
in_section 'a base green that may have loaded head code' "T1.12h: a base green that may have run head code is unproven"
in_section '`green at base`' "T1.13: a test that passes at base is reported, not accepted"
in_section 'never a Step 4 failure, and changes no criterion row' "T1.14: the base red is not a test failure and leaves #555's rows alone"
in_sens() {
  printf '%s' "$sens" | grep -qF -- "$1" && pass "$2" || fail "$2 (missing in *Sensitivity rows*)"
}
in_sens 'sensitivity not verified — {criterion}: {reason}' "T1.15: not_verified Sensitivity rows are reported"
in_sens 'goes under `Uncertainty`' "T1.16: they are reported under Uncertainty"
in_sens 'Runs on every PR, bug or not, whatever skips Step 4 or the criteria check' "T1.17: the Sensitivity rule is not bug-gated, nor skipped with Step 4 or the criteria check"
in_sens "the PR body's \`## Acceptance Criteria Verification\` table" "T1.18: the rule names its source, the PR body's criteria table"
in_sens 'report only, changing no criterion status or gate' "T1.19: the untrusted rows are report-only"
if printf '%s' "$section" | grep -qF 'sensitivity not verified'; then
  fail "T1.20: the Sensitivity rule sits inside the bug-gated *Bug proof*"
else
  pass "T1.20: the Sensitivity rule sits outside the bug-gated *Bug proof*"
fi
[ "$(grep -cF 'sensitivity not verified — {criterion}' "$ROOT/src/skills/issue-pr-review/SKILL.source.md" "$RV"/references/*.md | awk -F: '{s+=$NF} END{print s}')" -eq 1 ] \
  && pass "T1.21: the Sensitivity rule keeps one home" || fail "T1.21: the Sensitivity rule is restated"
has "$SKILL" 'On every PR, report `sensitivity not verified` rows (*Sensitivity rows*, same file).' "T1.22: Step 4's Sensitivity pointer is not bug-gated"

# T2 — the single Merge floor carries the clause
floor="$(grep -F 'a:rv-merge-floor' "$SKILL")"
printf '%s' "$floor" | grep -qF 'on a bug PR a `red→green` *Bug proof* at `verified_head` (`not reproduced` never is)' \
  && pass "T2.1: the *Merge floor* needs a red→green proof on a bug PR" \
  || fail "T2.1: the *Merge floor* line lacks the bug-proof clause"
[ "$(grep -cF 'a:rv-merge-floor' "$SKILL")" -eq 1 ] \
  && pass "T2.2: the floor keeps one home" || fail "T2.2: a second floor anchor appeared"

# T3 — pointer, report contract, no restatement elsewhere
has "$SKILL" '(`references/verification-checks.md`, *Bug proof*)' "T3.1: Step 4 points at *Bug proof*"
has "$RT" 'the *Bug proof*' "T3.2: the summary's Evidence names the proof"
has "$RT" '`sensitivity not verified`' "T3.3: the summary's Uncertainty names not_verified rows"
if grep -rqF 'red→green' "$ROOT/src/skills/auto-pilot" "$ROOT/src/skills/issue-resolver"; then
  fail "T3.4: auto-pilot or the resolver restates the proof instead of reading merge_floor"
else
  pass "T3.4: auto-pilot and the resolver never restate the proof"
fi

# T4 — eval case, built bundle, CI step
[ -f "$CASE/case.json" ] && [ -x "$CASE/subject.sh" ] && [ -f "$CASE/cassettes.json" ] \
  && pass "T4.1: the regression-green-at-base eval case exists" \
  || fail "T4.1: the regression-green-at-base eval case is incomplete"
grep -qE '^run_case "regression-green-at-base"$' "$ROOT/tests/test-eval-pr-review.sh" \
  && pass "T4.2: the eval case is registered" || fail "T4.2: the eval case is not registered"
has "$CASE/case.json" 'floor-auto-fixture-green-at-base-left_open.txt' \
  "T4.3: the case asserts a test green at base leaves the PR open"
has "$CASE/subject.sh" 'git("worktree", "add", "-q", "--detach", wt, git("merge-base", base, head))' \
  "T4.4: the case runs the base leg in a scratch worktree"
DIST="$ROOT/skills/issue-pr-review"
if grep -qF 'a:rvc-bug-proof' "$DIST/references/verification-checks.md" 2>/dev/null \
   && grep -qF '`red→green` *Bug proof*' "$DIST/SKILL.md" 2>/dev/null; then
  pass "T4.5: the built bundle carries the proof and the floor clause"
else
  fail "T4.5: the built bundle lacks the proof — rebuild skills/"
fi
grep -qF 'run: bash tests/test-bug-proof-556.sh' "$WORKFLOW" \
  && pass "T4.6: the CI step exists" || fail "T4.6: dist-check.yml lacks this test"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
