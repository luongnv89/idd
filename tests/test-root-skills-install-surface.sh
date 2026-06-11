#!/usr/bin/env bash
# test-root-skills-install-surface.sh — Verify repo-root skills/ supports ASM installs.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SH="$REPO_ROOT/scripts/build.sh"
SRC_SKILLS="$REPO_ROOT/src/skills"
ROOT_SKILLS="$REPO_ROOT/skills"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Root Skills Install Surface Tests (issue #104)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

if "$BUILD_SH" >/dev/null 2>&1; then
  pass "T1: build regenerates root skills/"
else
  fail "T1: build failed"
  exit 1
fi

for src_skill_dir in "$SRC_SKILLS"/*/; do
  name="$(basename "$src_skill_dir")"
  root_skill="$ROOT_SKILLS/$name"
  dist_skill="$REPO_ROOT/dist/skills/$name"

  if [ -f "$root_skill/SKILL.md" ]; then
    pass "T2: skills/$name/SKILL.md present"
  else
    fail "T2: skills/$name/SKILL.md missing"
    continue
  fi

  if diff -qr "$root_skill" "$dist_skill" >/dev/null; then
    pass "T3: skills/$name mirrors dist/skills/$name"
  else
    fail "T3: skills/$name differs from dist/skills/$name"
  fi

  if find "$root_skill" -path '*/references/agents/*.md' -type f | grep -q .; then
    pass "T4: skills/$name bundles referenced agents or has no agent deps"
  elif grep -R "references/agents/" "$root_skill" >/dev/null 2>&1; then
    fail "T4: skills/$name references agents but bundles none"
  else
    pass "T4: skills/$name has no agent deps"
  fi
done

if [ -d "$ROOT_SKILLS/idd-doctor" ]; then
  fail "T5: internal idd-doctor leaked into root skills/"
else
  pass "T5: internal idd-doctor excluded from root skills/"
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Root skills install surface tests failed"
  exit 1
fi

echo "  ✓ Root skills install surface is ready"
exit 0
