#!/usr/bin/env bash
# test-pr-body-closing-keywords-312.sh — guards the merge-effective closing-
# keyword surface from issue #312. Check 1 must evaluate keywords against the
# raw PR body when the commit carries it (review.merge_method squash or merge,
# issue #564), keep markdown-aware PR-body rules under rebase, and report
# divergence.
#
# Assertions run against authored src/ files and the generated skills/ output.
# A change that lands only in one tree is not a fix.
#
# Usage: bash tests/test-pr-body-closing-keywords-312.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_VERIFICATION="$REPO_ROOT/src/skills/issue-pr-review/references/verification-checks.md"
SRC_TEMPLATES="$REPO_ROOT/src/skills/issue-pr-review/references/report-templates.md"
BUILT_VERIFICATION="$REPO_ROOT/skills/issue-pr-review/references/verification-checks.md"
BUILT_TEMPLATES="$REPO_ROOT/skills/issue-pr-review/references/report-templates.md"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

expect_grep() {
  local label="$1" pattern="$2" file="$3"
  if grep -qiE -- "$pattern" "$file"; then pass "$label"; else fail "$label"; fi
}

forbid_grep() {
  local label="$1" pattern="$2" file="$3"
  if grep -qiE -- "$pattern" "$file"; then fail "$label"; else pass "$label"; fi
}

echo "◆ B1 PR-body closing-keyword tests (issue #312)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

echo "T0: Files exist"
for f in "$SRC_VERIFICATION" "$SRC_TEMPLATES" "$BUILT_VERIFICATION" "$BUILT_TEMPLATES"; do
  if [ -f "$f" ]; then
    pass "T0: exists ${f#"$REPO_ROOT"/}"
  else
    fail "T0: missing ${f#"$REPO_ROOT"/}"
  fi
done

# Issue #564: IDD's merge passes the PR body as the commit body, so the surface
# is chosen by `review.merge_method` (squash/merge → raw body, rebase →
# markdown-aware), no longer by the repo's squash message source.
echo "T1: authored check 1 splits the raw-body and markdown-aware surfaces by merge method"
expect_grep "T1: src chooses the surface from review.merge_method, with no API call" \
  'Use the loaded `review\.merge_method` — no API call — to choose which body surface is merge-effective' "$SRC_VERIFICATION"
expect_grep "T1: src squash/merge evaluates raw body without markdown strip" \
  '`squash` or `merge`: evaluate the regex against the \*\*raw\*\* PR body\. Do \*\*not\*\* strip markdown' "$SRC_VERIFICATION"
expect_grep "T1: src squash/merge treats code span/blockquote keywords as merge-effective" \
  'fenced code, inline code spans, or blockquotes \*\*are\*\* merge-effective' "$SRC_VERIFICATION"
expect_grep "T1: src rebase keeps markdown-aware PR-body rules" \
  '`rebase`: evaluate the regex with \*\*markdown-aware\*\* PR-body rules' "$SRC_VERIFICATION"
expect_grep "T1: src still hard-fails missing Closes #N (issue #36)" \
  'issue #36 hard-fail' "$SRC_VERIFICATION"

echo "T2: authored templates report the divergence, not under rebase"
expect_grep "T2: src templates name issues that will close at merge" \
  'will close at merge:' "$SRC_TEMPLATES"
expect_grep "T2: src templates bind divergence to the squash and merge methods" \
  'When `review\.merge_method` is `squash` or `merge` and the merge-effective keyword set' "$SRC_TEMPLATES"
expect_grep "T2: src templates omit merge-effective code-span closers under rebase" \
  'Under `rebase` do not treat code-span or blockquote keywords as merge-effective' "$SRC_TEMPLATES"

echo "T3: built skills ship the authored contract"
expect_grep "T3: built verification ships raw-body evaluation for squash and merge" \
  '`squash` or `merge`: evaluate the regex against the \*\*raw\*\* PR body\. Do \*\*not\*\* strip markdown' "$BUILT_VERIFICATION"
expect_grep "T3: built verification ships markdown-aware rules for rebase" \
  '`rebase`: evaluate the regex with \*\*markdown-aware\*\* PR-body rules' "$BUILT_VERIFICATION"
expect_grep "T3: built templates ship the divergence line" \
  'will close at merge:' "$BUILT_TEMPLATES"
expect_grep "T3: built templates keep rebase non-merge-effective for code spans" \
  'Under `rebase` do not treat code-span or blockquote keywords as merge-effective' "$BUILT_TEMPLATES"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ B1 PR-body closing-keyword tests failed"
  exit 1
fi
echo "  ✓ All B1 PR-body closing-keyword checks passed"
