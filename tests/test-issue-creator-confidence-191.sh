#!/usr/bin/env bash
# test-issue-creator-confidence-191.sh — Issue #191 acceptance checks
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_DIR="$REPO_ROOT/src/skills/issue-creator"
CONF="$SKILL_DIR/references/confidence-scoring.md"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Issue-creator confidence markers (issue #191)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

for t in bug feature improvement; do
  f="$SKILL_DIR/templates/${t}.md"
  for ph in type_confidence criterion_1_confidence priority_confidence effort_confidence labels_confidence; do
    if grep -q "{$ph}" "$f"; then
      pass "${t}.md has {$ph}"
    else
      fail "${t}.md missing {$ph}"
    fi
  done
done

for row in "Metadata — Priority" "Metadata — Effort" "Metadata — Labels"; do
  if grep -qF "$row" "$CONF"; then
    pass "confidence-scoring.md lists $row"
  else
    fail "confidence-scoring.md missing $row"
  fi
done

if grep -q '_confidence' "$SKILL_DIR/SKILL.source.md" && grep -q 'priority_confidence' "$SKILL_DIR/SKILL.source.md"; then
  pass "SKILL.source.md documents metadata confidence placeholders"
else
  fail "SKILL.source.md missing metadata confidence guidance"
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
[ "$FAIL" -eq 0 ]