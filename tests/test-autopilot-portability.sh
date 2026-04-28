#!/usr/bin/env bash
# test-autopilot-portability.sh — Validate auto-pilot portability (issue #53)
#
# This script verifies issue #53 acceptance criteria:
#   AC #1: Source pattern `skills/.*/SKILL\.md` is absent from auto-pilot.
#   AC #2: Phrase "All agents are in shared/agents" is absent from auto-pilot.
#
# Per the issue body, the post-build dist verification (flattened and plugin
# outputs use the §6.0 ADR rendering) lights up in PR 3 once the build exists,
# so it is intentionally out of scope for this test.
#
# Usage: bash tests/test-autopilot-portability.sh
# Returns: exit 0 if all tests pass, exit 1 on failure

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUTOPILOT_DIR="$REPO_ROOT/src/skills/auto-pilot"

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
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Auto-pilot portability spec is incomplete"
  exit 1
fi

echo "  ✓ Auto-pilot portability satisfies issue #53 source-level ACs"
exit 0
