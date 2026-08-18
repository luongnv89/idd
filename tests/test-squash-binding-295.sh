#!/usr/bin/env bash
# test-squash-binding-295.sh — guards the B1 squash-binding contract from issue
# #295 and its issue #311 follow-up. The traceability pass must be qualified by
# both independent repository reads: squash-only merge strategy and
# squash_merge_commit_message=PR_BODY.
#
# Assertions run against authored src/ files and the generated skills/ output.
# A change that lands only in one tree is not a fix.
#
# Usage: bash tests/test-squash-binding-295.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_VERIFICATION="$REPO_ROOT/src/skills/issue-pr-review/references/verification-checks.md"
SRC_TEMPLATES="$REPO_ROOT/src/skills/issue-pr-review/references/report-templates.md"
BUILT_VERIFICATION="$REPO_ROOT/skills/issue-pr-review/references/verification-checks.md"
BUILT_TEMPLATES="$REPO_ROOT/skills/issue-pr-review/references/report-templates.md"

SETTING_READ="gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed"
MESSAGE_READ="gh api repos/{owner}/{repo} --jq '{squash_merge_commit_title, squash_merge_commit_message}'"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

expect_fixed() {
  local label="$1" needle="$2" file="$3"
  if grep -qF -- "$needle" "$file"; then pass "$label"; else fail "$label"; fi
}

expect_grep() {
  local label="$1" pattern="$2" file="$3"
  if grep -qiE -- "$pattern" "$file"; then pass "$label"; else fail "$label"; fi
}

forbid_grep() {
  local label="$1" pattern="$2" file="$3"
  if grep -qiE -- "$pattern" "$file"; then fail "$label"; else pass "$label"; fi
}

echo "◆ B1 squash-binding tests (issues #295 + #311)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

echo "T0: Files exist"
for f in "$SRC_VERIFICATION" "$SRC_TEMPLATES" "$BUILT_VERIFICATION" "$BUILT_TEMPLATES"; do
  if [ -f "$f" ]; then
    pass "T0: exists ${f#"$REPO_ROOT"/}"
  else
    fail "T0: missing ${f#"$REPO_ROOT"/}"
  fi
done

echo "T1: authored contract reads both repository settings"
expect_fixed "T1: src verification-checks reads merge strategy" "$SETTING_READ" "$SRC_VERIFICATION"
expect_fixed "T1: src verification-checks reads squash message source" "$MESSAGE_READ" "$SRC_VERIFICATION"
expect_grep "T1: src pass requires squash-only \+ PR_BODY" \
  '✓ traceability: pass — B1/squash holds \(squash-only \+ PR_BODY\)' "$SRC_VERIFICATION"
expect_grep "T1: src pass row names the full squash-only predicate" \
  'squashMergeAllowed: true.*mergeCommitAllowed: false.*rebaseMergeAllowed: false.*squash_merge_commit_message: PR_BODY' "$SRC_VERIFICATION"

echo "T2: authored contract reports partial, not pass, when B1 is not guaranteed"
expect_grep "T2: src has a PR_BODY-but-not-squash-only partial row" \
  '⚠ traceability: partial — .B1/squash qualified only.*merge-commit and/or rebase can bypass the durable record' "$SRC_VERIFICATION"
forbid_grep "T2: src never treats PR_BODY alone as an unqualified pass" \
  'All four checks pass .*squash_merge_commit_message: PR_BODY[^|]*\| ✓ traceability: pass \|' "$SRC_VERIFICATION"
expect_grep "T2: src unreadable strategy or message source is non-pass" \
  'either the strategy read or the message-source read did not answer|strategy or squash-merge binding unverified' "$SRC_VERIFICATION"
expect_grep "T2: src repo-setting outcomes are note-only" \
  'All three non-.?pass repository-setting outcomes are properties of the .repository., not of the PR|never emit them as .action: fix. findings' "$SRC_VERIFICATION"
expect_grep "T2: src strict mode still blocks on qualified-only repo state" \
  'qualified-only, defeated, or unverified binding blocks' "$SRC_VERIFICATION"
expect_grep "T2: src exemption cannot swallow the new partial outcome" \
  'qualified-only.*defeated.*unverified' "$SRC_VERIFICATION"

echo "T3: report templates surface the same user-facing outcome"
expect_grep "T3: src clean summary names the B1/squash pass" \
  'traceability:.*B1/squash: squash-only \+ PR_BODY' "$SRC_TEMPLATES"
expect_grep "T3: src templates render the qualified-only partial" \
  'B1/squash qualified only' "$SRC_TEMPLATES"
expect_grep "T3: src templates keep unreadable config non-pass" \
  'binding unverified \(\{reason\}\)' "$SRC_TEMPLATES"
expect_grep "T3: src templates keep repo-setting findings note-only" \
  'All three lines are `note` findings|never handed to the fixer' "$SRC_TEMPLATES"
expect_grep "T3: src templates keep exempt PRs partial when check 4 is non-pass" \
  'qualified-only, defeated, or unverified binding is a repository finding' "$SRC_TEMPLATES"

echo "T4: built skills ship the authored contract"
expect_fixed "T4: built verification ships merge-strategy read" "$SETTING_READ" "$BUILT_VERIFICATION"
expect_fixed "T4: built verification ships squash-message read" "$MESSAGE_READ" "$BUILT_VERIFICATION"
expect_grep "T4: built verification ships the qualified B1/squash pass" \
  '✓ traceability: pass — B1/squash holds \(squash-only \+ PR_BODY\)' "$BUILT_VERIFICATION"
expect_grep "T4: built templates ship the clean B1/squash summary" \
  'traceability:.*B1/squash: squash-only \+ PR_BODY' "$BUILT_TEMPLATES"
expect_grep "T4: built templates ship the qualified-only partial" \
  'B1/squash qualified only' "$BUILT_TEMPLATES"
expect_grep "T4: built templates keep repo-setting findings note-only" \
  'All three lines are `note` findings|never handed to the fixer' "$BUILT_TEMPLATES"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ B1 squash-binding tests failed"
  exit 1
fi
echo "  ✓ All B1 squash-binding checks passed"
