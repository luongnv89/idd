#!/usr/bin/env bash
# test-install-script-agents.sh — Verify standalone install provisions IDD
# Claude Code agents alongside skills (issue #89).
#
# Asserts:
#   - ./scripts/install.sh installs all dist/agents/*.md to <target>/agents/
#   - single-skill installs still provision shared agents
#   - re-running the installer is idempotent
#   - unmanaged agent conflicts are skipped unless --force-agents is used
#   - uninstall removes IDD-managed agents without touching unmanaged files
#
# Usage: bash tests/test-install-script-agents.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SH="$REPO_ROOT/scripts/build.sh"
INSTALL_SH="$REPO_ROOT/scripts/install.sh"
SRC_AGENTS="$REPO_ROOT/src/shared/agents"
DIST_AGENTS="$REPO_ROOT/dist/agents"
DIST_SKILLS="$REPO_ROOT/dist/skills"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Install Script Agent Tests (issue #89)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

if "$BUILD_SH" >/dev/null 2>&1; then
  pass "T1: build.sh generates current dist outputs"
else
  fail "T1: build.sh failed"
  exit 1
fi

expected_agent_count="$(find "$SRC_AGENTS" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"

# ───────────────────────────────────────────────────────────
# T2: default install provisions skills and agents
# ───────────────────────────────────────────────────────────
TARGET_ALL="$TMP_ROOT/default-target"
if "$INSTALL_SH" --target "$TARGET_ALL" >/dev/null 2>&1; then
  pass "T2.1: default install exits 0"
else
  fail "T2.1: default install failed"
fi

missing_agents=0
for src_agent in "$SRC_AGENTS"/*.md; do
  [ -f "$src_agent" ] || continue
  name="$(basename "$src_agent")"
  stem="${name%.md}"
  installed="$TARGET_ALL/agents/$name"
  if [ -f "$installed" ] && \
     grep -q "^name: $stem$" "$installed" && \
     grep -q '^description: ' "$installed" && \
     grep -q 'Managed by IDD installer' "$installed"; then
    :
  else
    echo "    missing or malformed: $installed"
    missing_agents=$((missing_agents + 1))
  fi
done
if [ "$missing_agents" -eq 0 ]; then
  pass "T2.2: all shared agents installed with Claude Code frontmatter"
else
  fail "T2.2: $missing_agents agent(s) missing or malformed"
fi

missing_skills=0
for src_skill in "$DIST_SKILLS"/*/; do
  [ -d "$src_skill" ] || continue
  name="$(basename "$src_skill")"
  if [ ! -f "$TARGET_ALL/skills/$name/SKILL.md" ]; then
    echo "    missing skill: $name"
    missing_skills=$((missing_skills + 1))
  fi
done
if [ "$missing_skills" -eq 0 ]; then
  pass "T2.3: default install still installs standalone skills"
else
  fail "T2.3: $missing_skills skill(s) missing"
fi

# ───────────────────────────────────────────────────────────
# T3: single-skill install still provisions all shared agents
# ───────────────────────────────────────────────────────────
TARGET_ONE="$TMP_ROOT/single-target"
if "$INSTALL_SH" --target "$TARGET_ONE" --skill issue-resolver >/dev/null 2>&1; then
  pass "T3.1: single-skill install exits 0"
else
  fail "T3.1: single-skill install failed"
fi

installed_agent_count="$(find "$TARGET_ONE/agents" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
if [ "$installed_agent_count" = "$expected_agent_count" ]; then
  pass "T3.2: single-skill install provisions shared agents"
else
  fail "T3.2: expected $expected_agent_count agents, found $installed_agent_count"
fi

# ───────────────────────────────────────────────────────────
# T4: re-running is idempotent
# ───────────────────────────────────────────────────────────
before_count="$(find "$TARGET_ALL/agents" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
if "$INSTALL_SH" --target "$TARGET_ALL" >/dev/null 2>&1; then
  after_count="$(find "$TARGET_ALL/agents" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
  if [ "$before_count" = "$after_count" ]; then
    pass "T4: repeat install leaves one file per managed agent"
  else
    fail "T4: repeat install changed agent count ($before_count -> $after_count)"
  fi
else
  fail "T4: repeat install failed"
fi

# ───────────────────────────────────────────────────────────
# T5: unmanaged conflicts are skipped unless explicitly forced
# ───────────────────────────────────────────────────────────
TARGET_CONFLICT="$TMP_ROOT/conflict-target"
mkdir -p "$TARGET_CONFLICT/agents"
printf '%s\n' 'custom reviewer' > "$TARGET_CONFLICT/agents/code-reviewer.md"
if "$INSTALL_SH" --target "$TARGET_CONFLICT" --agents-only >"$TMP_ROOT/conflict.log" 2>&1; then
  if grep -q 'custom reviewer' "$TARGET_CONFLICT/agents/code-reviewer.md" && \
     grep -q 'not IDD-managed; skipped' "$TMP_ROOT/conflict.log"; then
    pass "T5.1: unmanaged code-reviewer agent skipped with warning"
  else
    fail "T5.1: unmanaged code-reviewer was overwritten or warning missing"
  fi
else
  fail "T5.1: conflict install should warn and continue"
fi

if "$INSTALL_SH" --target "$TARGET_CONFLICT" --agents-only --force-agents >/dev/null 2>&1; then
  if grep -q 'Managed by IDD installer' "$TARGET_CONFLICT/agents/code-reviewer.md" && \
     ls "$TARGET_CONFLICT/agents"/code-reviewer.md.bak.* >/dev/null 2>&1; then
    pass "T5.2: --force-agents backs up and replaces unmanaged conflicts"
  else
    fail "T5.2: forced replacement missing managed file or backup"
  fi
else
  fail "T5.2: forced agent install failed"
fi

# ───────────────────────────────────────────────────────────
# T6: uninstall removes managed agents
# ───────────────────────────────────────────────────────────
if "$INSTALL_SH" --target "$TARGET_ALL" --uninstall >/dev/null 2>&1; then
  remaining_managed=0
  for f in "$TARGET_ALL/agents"/*.md; do
    [ -f "$f" ] || continue
    if grep -q 'Managed by IDD installer' "$f"; then
      remaining_managed=$((remaining_managed + 1))
    fi
  done
  if [ "$remaining_managed" -eq 0 ] && [ ! -d "$TARGET_ALL/skills/issue-resolver" ]; then
    pass "T6: uninstall removes skills and managed agents"
  else
    fail "T6: uninstall left $remaining_managed managed agent(s) or skills behind"
  fi
else
  fail "T6: uninstall failed"
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Install script agent tests failed"
  exit 1
fi

echo "  ✓ Install script agent tests pass"
exit 0
