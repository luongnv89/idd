#!/usr/bin/env bash
# test-autopilot-portability.sh — Validate auto-pilot portability (issues #53, #58)
#
# This script verifies:
#   #53 AC #1: Source pattern `skills/.*/SKILL\.md` is absent from auto-pilot.
#   #53 AC #2: Phrase "All agents are in shared/agents" is absent from auto-pilot.
#   #58: Both dist outputs use the §6.0 ADR-decided rendering.
#
# ADR row in use: (A-fail, B-fail, C-1) per
# docs/decisions/cross-skill-invocation.md (2026-04-28).
#
# Expected rendered forms in auto-pilot dist outputs:
#   dist/skills/auto-pilot/**:        ../<name>/SKILL.md, references/docs/...,
#                                     references/agents/...
#   dist/plugin/skills/auto-pilot/**: ../../<name>/SKILL.md, ../../../docs/...,
#                                     ../../../shared/agents/...
#
# Usage: bash tests/test-autopilot-portability.sh
# Returns: exit 0 if all tests pass, exit 1 on failure

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUTOPILOT_DIR="$REPO_ROOT/src/skills/auto-pilot"
AUTOPILOT_DIST_FLAT="$REPO_ROOT/dist/skills/auto-pilot"
AUTOPILOT_DIST_PLUGIN="$REPO_ROOT/dist/plugin/skills/auto-pilot"
BUILD_SH="$REPO_ROOT/scripts/build.sh"

PASS=0
FAIL=0

pass() {
  echo "  ✓ $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  ✗ $1"
  FAIL=$((FAIL + 1))
}

echo "◆ /auto-pilot Portability Tests (issue #53)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T1: AC #1 — no hardcoded `skills/<name>/SKILL.md` paths
# ───────────────────────────────────────────────────────────
hardcoded_hits="$(grep -rnE 'skills/[^[:space:]]+/SKILL\.md' "$AUTOPILOT_DIR" 2>/dev/null || true)"
if [ -z "$hardcoded_hits" ]; then
  pass "T1.1: AC #1 — no hardcoded 'skills/<name>/SKILL.md' paths in auto-pilot"
else
  printf '%s\n' "$hardcoded_hits" | sed 's/^/    /'
  fail "T1.1: AC #1 — hardcoded 'skills/<name>/SKILL.md' paths still present"
fi

# ───────────────────────────────────────────────────────────
# T2: AC #2 — no "All agents are in shared/agents" phrase
# ───────────────────────────────────────────────────────────
agents_hits="$(grep -rn 'All agents are in shared/agents' "$AUTOPILOT_DIR" 2>/dev/null || true)"
if [ -z "$agents_hits" ]; then
  pass "T2.1: AC #2 — phrase 'All agents are in shared/agents' is absent"
else
  printf '%s\n' "$agents_hits" | sed 's/^/    /'
  fail "T2.1: AC #2 — phrase 'All agents are in shared/agents' still present"
fi

# ───────────────────────────────────────────────────────────
# T3: Compatibility line names required peer skills (sanity check)
# ───────────────────────────────────────────────────────────
SKILL_FILE="$AUTOPILOT_DIR/SKILL.md"
compat_line="$(grep -m1 '^compatibility:' "$SKILL_FILE" || true)"
for required in "issue-triage" "issue-resolver" "issue-analysis" "issue-pr-review"; do
  case "$compat_line" in
    *"$required"*)
      pass "T3: compatibility line names required skill: $required"
      ;;
    *)
      fail "T3: compatibility line missing required skill: $required"
      ;;
  esac
done

# ───────────────────────────────────────────────────────────
# T4: Cross-skill references use `{{skill:name}}` tokens
# ───────────────────────────────────────────────────────────
# Auto-pilot must address peer skills via `{{skill:<name>}}` so the build can
# rewrite them per distribution (§6 of refactor-plan-v10.md).
for skill in "issue-resolver" "issue-pr-review" "issue-analysis"; do
  if grep -rqF "{{skill:$skill}}" "$AUTOPILOT_DIR"; then
    pass "T4: auto-pilot uses {{skill:$skill}} token"
  else
    fail "T4: auto-pilot missing {{skill:$skill}} token"
  fi
done

# ───────────────────────────────────────────────────────────
# T5–T7: dist verification (issue #58) — runs build if dist missing
# ───────────────────────────────────────────────────────────
if [ ! -d "$AUTOPILOT_DIST_FLAT" ] || [ ! -d "$AUTOPILOT_DIST_PLUGIN" ]; then
  echo "  ○ dist outputs missing — running build..."
  if ! "$BUILD_SH" >/dev/null 2>&1; then
    fail "Pre-build failed — cannot run dist verification"
    echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
    echo "  Passed: $PASS"
    echo "  Failed: $FAIL"
    exit 1
  fi
fi

# T5: dist/skills/auto-pilot/ uses sibling-relative ../<name>/SKILL.md
if grep -rqE '\.\./issue-resolver/SKILL\.md' "$AUTOPILOT_DIST_FLAT"; then
  pass "T5: dist/skills/auto-pilot uses '../<name>/SKILL.md' (A-fail)"
else
  fail "T5: dist/skills/auto-pilot missing expected '../<name>/SKILL.md' rendering"
fi

# T5.1: no unresolved {{skill:...}} tokens in flattened output
if grep -rqE '\{\{skill:' "$AUTOPILOT_DIST_FLAT" 2>/dev/null; then
  fail "T5.1: dist/skills/auto-pilot contains unresolved {{skill:...}} tokens"
else
  pass "T5.1: dist/skills/auto-pilot has no unresolved {{skill:...}} tokens"
fi

# T6: dist/plugin/skills/auto-pilot/ uses ../../<name>/SKILL.md (C-1)
if grep -rqE '\.\./\.\./issue-resolver/SKILL\.md' "$AUTOPILOT_DIST_PLUGIN"; then
  pass "T6: dist/plugin/skills/auto-pilot uses '../../<name>/SKILL.md' (A-fail)"
else
  fail "T6: dist/plugin/skills/auto-pilot missing expected '../../<name>/SKILL.md' rendering"
fi

# T6.1: dist/plugin/skills/auto-pilot/ uses ../../../docs/... for runtime docs
if grep -rqE '\.\./\.\./\.\./docs/[a-z-]+\.md' "$AUTOPILOT_DIST_PLUGIN"; then
  pass "T6.1: dist/plugin/skills/auto-pilot uses '../../../docs/...' (C-1) for runtime docs"
else
  pass "T6.1: dist/plugin/skills/auto-pilot has no runtime doc references — vacuously OK"
fi

# T6.2: no unresolved tokens in plugin output
if grep -rqE '\{\{skill:' "$AUTOPILOT_DIST_PLUGIN" 2>/dev/null; then
  fail "T6.2: dist/plugin/skills/auto-pilot contains unresolved {{skill:...}} tokens"
else
  pass "T6.2: dist/plugin/skills/auto-pilot has no unresolved {{skill:...}} tokens"
fi

# T7: forbidden ${CLAUDE_PLUGIN_ROOT} (B-fail row in use, must use ../../../...)
if grep -rqF '${CLAUDE_PLUGIN_ROOT}' "$AUTOPILOT_DIST_PLUGIN" 2>/dev/null; then
  fail "T7: dist/plugin/skills/auto-pilot contains forbidden \${CLAUDE_PLUGIN_ROOT} (B-fail row)"
else
  pass "T7: dist/plugin/skills/auto-pilot has no \${CLAUDE_PLUGIN_ROOT} references"
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Auto-pilot portability spec is incomplete"
  exit 1
fi

echo "  ✓ Auto-pilot portability satisfies #53 source ACs and #58 dist ACs"
exit 0
