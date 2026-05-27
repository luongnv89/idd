#!/usr/bin/env bash
# test-install-script-tools.sh — Verify multi-tool standalone install support.
#
# install.sh installs self-contained skills to any SKILL.md-compatible tool.
# This suite asserts the per-tool destination paths, the skills-only behavior
# for tools without a shared-agents layout, and the guard rails that reject
# Claude-only options (--plugin / --agents-only / --target) for those tools.
#
# Each non-Claude tool uses a fixed $HOME-relative path, so the tests run the
# installer under an isolated HOME (a temp dir) to avoid touching real config.
#
# Usage: bash tests/test-install-script-tools.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SH="$REPO_ROOT/scripts/build.sh"
INSTALL_SH="$REPO_ROOT/scripts/install.sh"
DIST_SKILLS="$REPO_ROOT/dist/skills"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Install Script Multi-Tool Tests"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

if "$BUILD_SH" >/dev/null 2>&1; then
  pass "T0: build.sh generates current dist outputs"
else
  fail "T0: build.sh failed"
  exit 1
fi

skill_count="$(find "$DIST_SKILLS" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')"

# run install.sh under an isolated HOME
inst() { HOME="$TMP_HOME" "$INSTALL_SH" "$@"; }

# ───────────────────────────────────────────────────────────
# T1: each non-Claude tool installs all skills to its fixed path
# ───────────────────────────────────────────────────────────
# tool|skills dir relative to HOME
declare -a TOOL_PATHS=(
  "codex|.codex/skills"
  "opencode|.config/opencode/skills"
  "pi|.pi/skills"
  "openclaw|.openclaw/skills"
  "hermes|.hermes/skills"
  "antigravity|.antigravity/skills"
  "windsurf|.windsurf/rules"
)

for entry in "${TOOL_PATHS[@]}"; do
  tool="${entry%%|*}"
  rel="${entry#*|}"
  dest="$TMP_HOME/$rel"
  if inst --tool "$tool" >/dev/null 2>&1; then
    installed="$(find "$dest" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$installed" = "$skill_count" ]; then
      pass "T1[$tool]: $skill_count skills installed to $rel"
    else
      fail "T1[$tool]: expected $skill_count skills at $rel, found $installed"
    fi
  else
    fail "T1[$tool]: install failed"
  fi
done

# ───────────────────────────────────────────────────────────
# T2: non-Claude tools get NO shared-agents directory
# ───────────────────────────────────────────────────────────
if [ ! -d "$TMP_HOME/.codex/agents" ] && [ ! -d "$TMP_HOME/.hermes/agents" ]; then
  pass "T2: non-Claude tools receive skills only (no agents dir)"
else
  fail "T2: unexpected agents dir created for a non-Claude tool"
fi

# ───────────────────────────────────────────────────────────
# T3: skills are self-contained (bundled agents present)
# ───────────────────────────────────────────────────────────
if [ -f "$TMP_HOME/.codex/skills/issue-resolver/references/agents/codebase-researcher.md" ]; then
  pass "T3: skills ship bundled shared agents (self-contained)"
else
  fail "T3: bundled agents missing from installed skill"
fi

# ───────────────────────────────────────────────────────────
# T4: 'agents' tool installs skills AND shared agents
# ───────────────────────────────────────────────────────────
if inst --tool agents >/dev/null 2>&1; then
  if [ -d "$TMP_HOME/.agents/skills" ] && \
     [ -f "$TMP_HOME/.agents/agents/codebase-researcher.md" ]; then
    pass "T4: 'agents' tool installs skills + shared agents (~/.agents/agents)"
  else
    fail "T4: 'agents' tool missing skills or shared agents"
  fi
else
  fail "T4: 'agents' tool install failed"
fi

# ───────────────────────────────────────────────────────────
# T5: --tools list and 'all' fan out
# ───────────────────────────────────────────────────────────
TMP_HOME2="$(mktemp -d)"
if HOME="$TMP_HOME2" "$INSTALL_SH" --tools codex,pi >/dev/null 2>&1; then
  if [ -d "$TMP_HOME2/.codex/skills" ] && [ -d "$TMP_HOME2/.pi/skills" ] && \
     [ ! -d "$TMP_HOME2/.hermes/skills" ]; then
    pass "T5: --tools codex,pi installs exactly those two"
  else
    fail "T5: --tools comma-list did not fan out correctly"
  fi
else
  fail "T5: --tools comma-list install failed"
fi
rm -rf "$TMP_HOME2"

# ───────────────────────────────────────────────────────────
# T6: guard rails reject Claude-only options for other tools
# ───────────────────────────────────────────────────────────
if ! inst --plugin --tool codex --dry-run >/dev/null 2>&1; then
  pass "T6.1: --plugin rejected for non-Claude tool"
else
  fail "T6.1: --plugin should be rejected for non-Claude tool"
fi

if ! inst --agents-only --tool codex --dry-run >/dev/null 2>&1; then
  pass "T6.2: --agents-only rejected for tool without agents layout"
else
  fail "T6.2: --agents-only should be rejected for codex"
fi

if ! inst --tool codex --target /tmp/x --dry-run >/dev/null 2>&1; then
  pass "T6.3: --target rejected for non-Claude tool"
else
  fail "T6.3: --target should be rejected for non-Claude tool"
fi

if ! inst --tool bogus --dry-run >/dev/null 2>&1; then
  pass "T6.4: unknown tool name rejected"
else
  fail "T6.4: unknown tool name should be rejected"
fi

# Empty --tools value is rejected cleanly (not an unbound-variable crash).
if ! inst --tools "" --dry-run >/dev/null 2>&1; then
  pass "T6.5: empty --tools value rejected"
else
  fail "T6.5: empty --tools value should be rejected"
fi

# 'all' keyword tolerates case and surrounding whitespace, like the picker.
count="$(inst --tools 'All ' --dry-run 2>&1 | grep -c 'installing standalone skills' || true)"
if [ "$count" = "9" ]; then
  pass "T6.6: --tools 'All ' normalizes to all 9 tools"
else
  fail "T6.6: --tools 'All ' selected $count tools (expected 9)"
fi

# ───────────────────────────────────────────────────────────
# T7: uninstall removes a tool's skills
# ───────────────────────────────────────────────────────────
if inst --tool hermes --uninstall >/dev/null 2>&1; then
  remaining="$(find "$TMP_HOME/.hermes/skills" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$remaining" = "0" ]; then
    pass "T7: uninstall removes all skills for a tool"
  else
    fail "T7: uninstall left $remaining skills for hermes"
  fi
else
  fail "T7: uninstall failed"
fi

# ───────────────────────────────────────────────────────────
# T8: interactive tool selection (IDD_FORCE_PROMPT reads from stdin)
# ───────────────────────────────────────────────────────────
# prompt + reply, capture which tools the installer reported targeting
prompt_inst() { IDD_FORCE_PROMPT=1 HOME="$TMP_HOME" "$INSTALL_SH" --dry-run "$@"; }

# Enter (empty) -> Claude default
out="$(prompt_inst <<< "" 2>&1 || true)"
if grep -q '\[claude\] installing' <<< "$out" && ! grep -q '\[codex\] installing' <<< "$out"; then
  pass "T8.1: empty reply defaults to Claude"
else
  fail "T8.1: empty reply did not default to Claude"
fi

# numeric multi-select "3 5" -> codex + pi
out="$(prompt_inst <<< "3 5" 2>&1 || true)"
if grep -q '\[codex\] installing' <<< "$out" && grep -q '\[pi\] installing' <<< "$out" && \
   ! grep -q '\[claude\] installing' <<< "$out"; then
  pass "T8.2: '3 5' selects codex + pi"
else
  fail "T8.2: '3 5' did not select codex + pi"
fi

# comma list "1,3" -> claude + codex
out="$(prompt_inst <<< "1,3" 2>&1 || true)"
if grep -q '\[claude\] installing' <<< "$out" && grep -q '\[codex\] installing' <<< "$out"; then
  pass "T8.3: '1,3' selects claude + codex"
else
  fail "T8.3: '1,3' did not select claude + codex"
fi

# 'a' -> all 9 tools
count="$(prompt_inst <<< "a" 2>&1 | grep -c 'installing standalone skills' || true)"
if [ "$count" = "9" ]; then
  pass "T8.4: 'a' selects all 9 tools"
else
  fail "T8.4: 'a' selected $count tools (expected 9)"
fi

# out-of-range / invalid input exits non-zero
if prompt_inst <<< "99" >/dev/null 2>&1; then
  fail "T8.5: out-of-range selection should fail"
else
  pass "T8.5: out-of-range selection rejected"
fi
if prompt_inst <<< "xyz" >/dev/null 2>&1; then
  fail "T8.6: non-numeric selection should fail"
else
  pass "T8.6: non-numeric selection rejected"
fi

# explicit --tool bypasses the prompt entirely
out="$(prompt_inst --tool windsurf <<< "3 5" 2>&1 || true)"
if grep -q '\[windsurf\] installing' <<< "$out" && ! grep -q '\[codex\] installing' <<< "$out"; then
  pass "T8.7: explicit --tool bypasses the interactive prompt"
else
  fail "T8.7: explicit --tool did not bypass the prompt"
fi

# non-interactive (no force, piped stdin) falls back to Claude without prompting
out="$(printf '' | HOME="$TMP_HOME" "$INSTALL_SH" --dry-run 2>&1 || true)"
if ! grep -q 'Select the tool' <<< "$out" && grep -q '\[claude\] installing' <<< "$out"; then
  pass "T8.8: non-interactive run skips prompt, defaults to Claude"
else
  fail "T8.8: non-interactive run did not behave correctly"
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "  ✓ Install script multi-tool tests pass"
  exit 0
else
  echo "  ✗ Install script multi-tool tests failed"
  exit 1
fi
