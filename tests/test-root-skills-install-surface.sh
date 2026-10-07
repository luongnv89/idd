#!/usr/bin/env bash
# test-root-skills-install-surface.sh — Verify repo-root skills/ supports ASM installs.
# Post #106: skills/ is the committed install surface (dist/ no longer tracked).

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

if find "$REPO_ROOT/src" -name 'SKILL.md' -type f | grep -q .; then
  fail "T6: src/ leaks SKILL.md files that asm would discover"
else
  pass "T6: src/ uses SKILL.source.md and is hidden from asm discovery"
fi

# T7: supported local installs target public skills/, not a recursive repo scan.
# Exercise the default ASM method when available; no CI dependency is installed.
TMP_INSTALL="$(mktemp -d)"
trap 'rm -rf "$TMP_INSTALL"' EXIT
if command -v asm >/dev/null 2>&1; then
  if HOME="$TMP_INSTALL/home" XDG_CONFIG_HOME="$TMP_INSTALL/config" \
     XDG_CACHE_HOME="$TMP_INSTALL/cache" asm install "$ROOT_SKILLS" \
       --library --all --yes >"$TMP_INSTALL/install.log" 2>&1; then
    if python3 - "$ROOT_SKILLS" "$TMP_INSTALL" <<'PY'
import sys
from pathlib import Path
public, installed = map(Path, sys.argv[1:])
expected = {p.parent.name for p in public.glob("*/SKILL.md")}
got = {p.parent.name for p in installed.rglob("SKILL.md")}
assert expected and got == expected, (expected, got)
assert "idd-doctor" not in got, "internal doctor leaked through default installer"
PY
    then pass "T7: default ASM local skills/ install discovers exactly public packages"
    else fail "T7: ASM installed unexpected or incomplete skill inventory"; fi
  else
    fail "T7: default ASM local skills/ install failed"
    tail -12 "$TMP_INSTALL/install.log"
  fi
else
  echo "  ○ T7: real ASM install skipped — asm unavailable; manual public surface checked above"
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
