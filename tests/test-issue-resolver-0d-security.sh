#!/usr/bin/env bash
# test-issue-resolver-0d-security.sh — Validate resolver Step 0d security guard (issue #186)
#
# Acceptance criteria:
#  - Step 0d checks security/CVE/vulnerability labels before rewrite
#  - Auto mode skips with ⚠; interactive asks for explicit confirmation
#  - README no longer claims resolver runs /issue-creator first
#
# Usage: bash tests/test-issue-resolver-0d-security.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Issue-Resolver Step 0d Security Guard Tests (issue #186)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

SKILL="$REPO_ROOT/src/skills/issue-resolver/SKILL.source.md"
README="$REPO_ROOT/src/skills/issue-resolver/docs/README.md"
ERRORS="$REPO_ROOT/src/skills/issue-resolver/references/error-messages.md"

if [ ! -f "$SKILL" ]; then
  fail "SKILL.source.md missing"
  exit 1
fi

if grep -qE 'Security label check \(SPEC §1\.4\)' "$SKILL"; then
  pass "T1.1: Step 0d documents SPEC §1.4 security label check"
else
  fail "T1.1: Step 0d missing SPEC §1.4 security label check"
fi

if grep -qE 'security.*CVE.*vulnerability|CVE.*vulnerability' "$SKILL"; then
  pass "T1.2: Step 0d lists security/CVE/vulnerability labels"
else
  fail "T1.2: Step 0d missing security/CVE/vulnerability label list"
fi

if grep -qE 'case-insensitive' "$SKILL"; then
  pass "T1.3: Step 0d documents case-insensitive label match"
else
  fail "T1.3: Step 0d missing case-insensitive note"
fi

if grep -qE 'Auto mode.*--auto.*IDD_AUTO_MODE' "$SKILL" && grep -q 'Skipping auto-normalization' "$SKILL"; then
  pass "T1.4: Step 0d auto mode skips normalization with warning"
else
  fail "T1.4: Step 0d auto-mode skip behavior incomplete"
fi

if grep -qE 'Interactive mode.*explicit operator confirmation' "$SKILL"; then
  pass "T1.5: Step 0d interactive mode requires explicit confirmation"
else
  fail "T1.5: Step 0d interactive confirmation missing"
fi

if grep -qE 'does \*\*not\*\* invoke `/issue-creator`' "$SKILL"; then
  pass "T1.6: Step 0d clarifies inline normalize vs /issue-creator subprocess"
else
  fail "T1.6: Step 0d missing inline vs /issue-creator clarification"
fi

if grep -qE '^### Security-labeled issue \(skip\)' "$ERRORS"; then
  pass "T2.1: error-messages.md defines security skip warning"
else
  fail "T2.1: error-messages.md missing security skip section"
fi

if grep -q 'runs `/issue-creator` first' "$README"; then
  fail "T3.1: README still claims resolver runs /issue-creator first"
else
  pass "T3.1: README corrected — no false /issue-creator-first claim"
fi

if grep -q 'Step 0d normalizes it inline' "$README"; then
  pass "T3.2: README documents Step 0d inline normalization"
else
  fail "T3.2: README missing Step 0d inline normalization text"
fi

echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Step 0d security guard tests failed ($PASS passed, $FAIL failed)"
  exit 1
fi
echo "  ✓ All Step 0d security guard checks passed ($PASS)"