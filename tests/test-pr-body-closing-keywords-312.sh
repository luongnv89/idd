#!/usr/bin/env bash
# test-pr-body-closing-keywords-312.sh — guards the B1 merge-effective closing-
# keyword surface from issue #312. Check 1 must evaluate keywords against the
# raw PR body when squash_merge_commit_message is PR_BODY, keep markdown-aware
# PR-body rules under COMMIT_MESSAGES, and report divergence.
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

echo "T1: authored check 1 splits PR_BODY vs COMMIT_MESSAGES surfaces"
expect_grep "T1: src reuses check 4 squash_merge_commit_message" \
  'Reuse check 4.s already-read `squash_merge_commit_message`' "$SRC_VERIFICATION"
expect_grep "T1: src PR_BODY evaluates raw body without markdown strip" \
  'PR_BODY.*raw.*PR body|Do \*\*not\*\* strip markdown' "$SRC_VERIFICATION"
expect_grep "T1: src PR_BODY treats code span/blockquote keywords as merge-effective" \
  'fenced code, inline code spans, or blockquotes \*\*are\*\* merge-effective' "$SRC_VERIFICATION"
expect_grep "T1: src COMMIT_MESSAGES keeps markdown-aware PR-body rules" \
  'COMMIT_MESSAGES.*markdown-aware|markdown-aware.*PR-body rules' "$SRC_VERIFICATION"
expect_grep "T1: src still hard-fails missing Closes #N (issue #36)" \
  'issue #36 hard-fail' "$SRC_VERIFICATION"

echo "T2: authored templates report B1 divergence, not under COMMIT_MESSAGES"
expect_grep "T2: src templates name issues that will close at squash-merge" \
  'will close at\s+squash-merge|will close at squash-merge' "$SRC_TEMPLATES"
expect_grep "T2: src templates bind divergence to PR_BODY" \
  'squash_merge_commit_message: PR_BODY' "$SRC_TEMPLATES"
expect_grep "T2: src templates omit merge-effective code-span closers under COMMIT_MESSAGES" \
  'Under `COMMIT_MESSAGES`.*do not treat code-span or blockquote keywords as merge-effective' "$SRC_TEMPLATES"

echo "T3: built skills ship the authored contract"
expect_grep "T3: built verification ships raw-body PR_BODY evaluation" \
  'PR_BODY.*raw.*PR body|Do \*\*not\*\* strip markdown' "$BUILT_VERIFICATION"
expect_grep "T3: built verification ships markdown-aware COMMIT_MESSAGES rules" \
  'COMMIT_MESSAGES.*markdown-aware|markdown-aware.*PR-body rules' "$BUILT_VERIFICATION"
expect_grep "T3: built templates ship the B1 divergence line" \
  'will close at\s+squash-merge|will close at squash-merge' "$BUILT_TEMPLATES"
expect_grep "T3: built templates keep COMMIT_MESSAGES non-merge-effective for code spans" \
  'Under `COMMIT_MESSAGES`.*do not treat code-span or blockquote keywords as merge-effective' "$BUILT_TEMPLATES"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ B1 PR-body closing-keyword tests failed"
  exit 1
fi
echo "  ✓ All B1 PR-body closing-keyword checks passed"
