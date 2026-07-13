#!/usr/bin/env bash
# test-build-script.sh — Validate scripts/build.sh produces expected outputs
# (issue #58, §9 of refactor-plan-v10.md; updated for #106).
#
# Asserts:
#   - All public skills (src/skills/<name>/) appear in root skills/<name>/
#   - Every shared source agent is emitted as a standalone Claude Code agent
#   - Internal skills (src/internal-skills/) and deprecated skills
#     (src/deprecated-skills/) without a distribute flag are excluded.
#
# Usage: bash tests/test-build-script.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SH="$REPO_ROOT/scripts/build.sh"
SRC_SKILLS="$REPO_ROOT/src/skills"
SRC_AGENTS="$REPO_ROOT/src/shared/agents"
ROOT_SKILLS="$REPO_ROOT/skills"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Build Script Tests (issue #58)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T1: build.sh exists and is executable
# ───────────────────────────────────────────────────────────
if [ -x "$BUILD_SH" ]; then
  pass "T1: scripts/build.sh exists and is executable"
else
  fail "T1: scripts/build.sh missing or not executable"
  echo "  Build aborted — cannot continue."
  exit 1
fi

# ───────────────────────────────────────────────────────────
# T2: build runs cleanly into a temp out dir
# ───────────────────────────────────────────────────────────
TMP_OUT="$(mktemp -d)"
trap 'rm -rf "$TMP_OUT"' EXIT
if "$BUILD_SH" --out "$TMP_OUT" >/dev/null 2>&1; then
  pass "T2: build.sh --out <tmp> exits 0"
else
  fail "T2: build.sh --out <tmp> failed"
  echo "  Build aborted — cannot continue."
  exit 1
fi

# Also build into the canonical dist/ for the rest of the tests
if "$BUILD_SH" >/dev/null 2>&1; then
  pass "T2.1: build.sh (default out=dist/) exits 0"
else
  fail "T2.1: build.sh failed against default out"
fi

# ───────────────────────────────────────────────────────────
# T3: every public src skill is present in root skills/
# ───────────────────────────────────────────────────────────
for src_skill_dir in "$SRC_SKILLS"/*/; do
  name="$(basename "$src_skill_dir")"
  if [ -f "$ROOT_SKILLS/$name/SKILL.md" ]; then
    pass "T3: skills/$name/SKILL.md present"
  else
    fail "T3: skills/$name/SKILL.md missing"
  fi
done

# ───────────────────────────────────────────────────────────
# T5: every shared source agent is emitted as a standalone Claude Code agent
#      in the built dist/agents/ (agent outputs are gitignored, not committed)
# ───────────────────────────────────────────────────────────
TMP_AGENTS="$(mktemp -d)"
"$BUILD_SH" --out "$TMP_AGENTS" >/dev/null 2>&1
for src_agent in "$SRC_AGENTS"/*.md; do
  [ -f "$src_agent" ] || continue
  name="$(basename "$src_agent")"
  stem="${name%.md}"
  dist_agent="$TMP_AGENTS/agents/$name"
  if [ -f "$dist_agent" ] && \
     grep -q "^name: $stem$" "$dist_agent" && \
     grep -q '^description: ' "$dist_agent" && \
     grep -q 'Managed by IDD installer' "$dist_agent"; then
    pass "T5: dist/agents/$name generated with Claude Code frontmatter"
  else
    fail "T5: dist/agents/$name missing or malformed"
  fi
done
rm -rf "$TMP_AGENTS"

# ───────────────────────────────────────────────────────────
# T5b: every shared source agent is emitted for pi-subagents in .pi/agents/
# ───────────────────────────────────────────────────────────
PI_AGENTS="$REPO_ROOT/.pi/agents"
for src_agent in "$SRC_AGENTS"/*.md; do
  [ -f "$src_agent" ] || continue
  name="$(basename "$src_agent")"
  pi_agent="$PI_AGENTS/$name"
  if [ -f "$pi_agent" ] && \
     grep -q '^display_name: ' "$pi_agent" && \
     grep -q 'Managed by IDD installer (pi-subagents)' "$pi_agent" && \
     ! grep -q 'display_name:.*—' "$pi_agent" && \
     ! grep -q 'display_name:.*\\u2014' "$pi_agent"; then
    pass "T5b: .pi/agents/$name generated (role-only display_name)"
  else
    fail "T5b: .pi/agents/$name missing or still has persona display_name"
  fi
done

# ───────────────────────────────────────────────────────────
# T6: internal-skills excluded from generated outputs
# ───────────────────────────────────────────────────────────
if [ -d "$REPO_ROOT/src/internal-skills" ]; then
  for internal_dir in "$REPO_ROOT/src/internal-skills"/*/; do
    [ -d "$internal_dir" ] || continue
    name="$(basename "$internal_dir")"
    if [ ! -d "$ROOT_SKILLS/$name" ]; then
      pass "T6: internal skill '$name' correctly excluded from generated outputs"
    else
      fail "T6: internal skill '$name' leaked into generated outputs"
    fi
  done
fi

# ───────────────────────────────────────────────────────────
# T7: deprecated-skills without distribute flag excluded
# ───────────────────────────────────────────────────────────
if [ -d "$REPO_ROOT/src/deprecated-skills" ]; then
  for dep_dir in "$REPO_ROOT/src/deprecated-skills"/*/; do
    [ -d "$dep_dir" ] || continue
    name="$(basename "$dep_dir")"
    skill_md="$dep_dir/SKILL.md"
    distribute_flag=""
    if [ -f "$skill_md" ]; then
      # Look for "distribute:" in YAML frontmatter (first 30 lines).
      distribute_flag="$(head -30 "$skill_md" | grep -E '^distribute:' || true)"
    fi
    if [ -z "$distribute_flag" ]; then
      if [ ! -d "$ROOT_SKILLS/$name" ]; then
        pass "T7: deprecated skill '$name' (no distribute flag) excluded"
      else
        fail "T7: deprecated skill '$name' leaked into generated outputs without distribute flag"
      fi
    fi
  done
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Build script tests failed"
  exit 1
fi

echo "  ✓ Build script tests pass"
exit 0
