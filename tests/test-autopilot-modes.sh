#!/usr/bin/env bash
# test-autopilot-modes.sh — Validate balanced-by-default merge modes
#
# This script verifies issue #33 acceptance criteria:
#  - .gitissue.yml supports `autopilot.mode` with values conservative|balanced|aggressive
#  - Default install never merges a PR with unresolved fixable review issues
#  - Aggressive behavior is unreachable without explicit config (no casual flag)
#  - /init-gitissue emits balanced defaults
#  - /auto-pilot final report uses the six categories: merged, left_open,
#    partial_followup, blocked_by_dependency, failed, skipped
#
# Usage: bash tests/test-autopilot-modes.sh
# Returns: exit 0 if all tests pass, exit 1 on first failure

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

echo "◆ Auto-Pilot Balanced Merge Modes Tests (issue #33)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T1: init-gitissue template ships balanced defaults
# ───────────────────────────────────────────────────────────
TEMPLATE="$REPO_ROOT/src/skills/init-gitissue/templates/gitissue-template.yml"

if [ -f "$TEMPLATE" ]; then
  pass "T1.0: template file exists"
else
  fail "T1.0: $TEMPLATE not found"
fi

if grep -qE '^\s*mode:\s*balanced\b' "$TEMPLATE"; then
  pass "T1.1: template ships 'mode: balanced' as the default"
else
  fail "T1.1: template does not ship 'mode: balanced' as default"
fi

if grep -qE '^\s*merge_partial:\s*false\b' "$TEMPLATE"; then
  pass "T1.2: template ships 'merge_partial: false' as the default"
else
  fail "T1.2: template does not ship 'merge_partial: false' as default"
fi

if grep -qE '^autopilot:' "$TEMPLATE"; then
  pass "T1.3: template has autopilot: section"
else
  fail "T1.3: template missing autopilot: section"
fi

# ───────────────────────────────────────────────────────────
# T2: docs/config-schema.md documents both new keys
# ───────────────────────────────────────────────────────────
SCHEMA="$REPO_ROOT/docs/config-schema.md"

if grep -qE 'autopilot\.mode' "$SCHEMA"; then
  pass "T2.1: config-schema.md documents autopilot.mode"
else
  fail "T2.1: config-schema.md missing autopilot.mode"
fi

if grep -qE 'autopilot\.merge_partial' "$SCHEMA"; then
  pass "T2.2: config-schema.md documents autopilot.merge_partial"
else
  fail "T2.2: config-schema.md missing autopilot.merge_partial"
fi

# All three mode values are documented
for mode_value in conservative balanced aggressive; do
  if grep -qE "\"?${mode_value}\"?" "$SCHEMA"; then
    pass "T2.3.${mode_value}: schema documents mode value '${mode_value}'"
  else
    fail "T2.3.${mode_value}: schema missing mode value '${mode_value}'"
  fi
done

# Default in defaults table is balanced
if grep -qE '\| \`autopilot\.mode\` \| \`balanced\`' "$SCHEMA"; then
  pass "T2.4: defaults table lists balanced as the default mode"
else
  fail "T2.4: defaults table does not list balanced as the default mode"
fi

# Default merge_partial is false
if grep -qE '\| \`autopilot\.merge_partial\` \| \`false\`' "$SCHEMA"; then
  pass "T2.5: defaults table lists merge_partial: false as default"
else
  fail "T2.5: defaults table does not list merge_partial: false as default"
fi

# Legacy auto_merge field is documented as legacy
if grep -qE 'LEGACY' "$SCHEMA"; then
  pass "T2.6: schema marks legacy auto_merge field"
else
  fail "T2.6: schema does not mark auto_merge as legacy"
fi

# ───────────────────────────────────────────────────────────
# T3: auto-pilot SKILL.md documents merge modes
# ───────────────────────────────────────────────────────────
SKILL="$REPO_ROOT/src/skills/auto-pilot/SKILL.md"

if grep -qiE 'Merge Modes' "$SKILL"; then
  pass "T3.1: SKILL.md has a Merge Modes section"
else
  fail "T3.1: SKILL.md missing Merge Modes section"
fi

for mode_value in conservative balanced aggressive; do
  if grep -qE "\b${mode_value}\b" "$SKILL"; then
    pass "T3.2.${mode_value}: SKILL.md mentions mode '${mode_value}'"
  else
    fail "T3.2.${mode_value}: SKILL.md does not mention mode '${mode_value}'"
  fi
done

if grep -qE 'autopilot\.mode' "$SKILL"; then
  pass "T3.3: SKILL.md references autopilot.mode key"
else
  fail "T3.3: SKILL.md does not reference autopilot.mode"
fi

if grep -qE 'autopilot\.merge_partial|merge_partial' "$SKILL"; then
  pass "T3.4: SKILL.md references autopilot.merge_partial key"
else
  fail "T3.4: SKILL.md does not reference autopilot.merge_partial"
fi

# Final-report uses the six categorical labels
for category in merged left_open partial_followup blocked_by_dependency failed skipped; do
  if grep -qE "\b${category}\b" "$SKILL"; then
    pass "T3.5.${category}: SKILL.md final report mentions outcome '${category}'"
  else
    fail "T3.5.${category}: SKILL.md final report does not mention outcome '${category}'"
  fi
done

# ───────────────────────────────────────────────────────────
# T4: phases.md gates merge behavior on mode
# ───────────────────────────────────────────────────────────
PHASES="$REPO_ROOT/src/skills/auto-pilot/references/phases.md"

if grep -qE 'autopilot\.mode|effective mode' "$PHASES"; then
  pass "T4.1: phases.md describes mode gating"
else
  fail "T4.1: phases.md does not describe mode gating"
fi

if grep -qiE 'mode:\s*balanced.*manual\s+merge|conservative.*leave PR open|leave PR open.*conservative' "$PHASES"; then
  pass "T4.2: phases.md describes conservative-mode leave-open behavior"
else
  fail "T4.2: phases.md does not describe conservative-mode leave-open behavior"
fi

if grep -qE 'merge_partial' "$PHASES"; then
  pass "T4.3: phases.md references merge_partial gate"
else
  fail "T4.3: phases.md does not reference merge_partial gate"
fi

if grep -qE 'aggressive' "$PHASES"; then
  pass "T4.4: phases.md describes aggressive-mode behavior"
else
  fail "T4.4: phases.md does not describe aggressive-mode behavior"
fi

# Outcome labels appear in phases.md
for category in merged left_open partial_followup; do
  if grep -qE "\b${category}\b" "$PHASES"; then
    pass "T4.5.${category}: phases.md uses outcome label '${category}'"
  else
    fail "T4.5.${category}: phases.md does not use outcome label '${category}'"
  fi
done

# ───────────────────────────────────────────────────────────
# T5: README highlights merge modes
# ───────────────────────────────────────────────────────────
README="$REPO_ROOT/src/skills/auto-pilot/README.md"

if grep -qiE 'conservative' "$README"; then
  pass "T5.1: README mentions conservative mode"
else
  fail "T5.1: README does not mention conservative mode"
fi

if grep -qE 'autopilot\.mode' "$README"; then
  pass "T5.2: README references autopilot.mode key"
else
  fail "T5.2: README does not reference autopilot.mode key"
fi

# ───────────────────────────────────────────────────────────
# T6: Acceptance — aggressive partial-merge requires BOTH keys
# (Static check: phases.md must require both mode=aggressive AND merge_partial=true)
# ───────────────────────────────────────────────────────────
if grep -qE 'aggressive.*merge_partial|merge_partial.*aggressive' "$PHASES"; then
  pass "T6.1: aggressive partial-merge gated on both mode AND merge_partial"
else
  fail "T6.1: phases.md does not gate aggressive partial-merge on both keys"
fi

# AC #2: default install never merges a PR with unresolved fixable review issues
# This is enforced by the balanced default + merge_partial: false default.
# Verify the SKILL.md merge-modes table makes this explicit.
if grep -qiE 'Default install never merges|never auto-merge' "$SKILL"; then
  pass "T6.2: SKILL.md states default never merges unresolved PRs (AC #2)"
else
  fail "T6.2: SKILL.md does not explicitly state default never merges unresolved PRs"
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
else
  exit 0
fi
