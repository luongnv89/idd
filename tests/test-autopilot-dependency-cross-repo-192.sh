#!/usr/bin/env bash
# test-autopilot-dependency-cross-repo-192.sh — Issue #192 acceptance checks
#
# Usage: bash tests/test-autopilot-dependency-cross-repo-192.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Auto-Pilot dependency gate cross-repo exclusion (issue #192)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

PHASES="$REPO_ROOT/src/skills/auto-pilot/references/phases.md"
PARSE="$REPO_ROOT/scripts/dependency_gate_parse.py"

if grep -qE 'Strip cross-repo tokens' "$PHASES" \
   && grep -qF '(?<![\w/])#(\d+)' "$PHASES"; then
  pass "T1: phases.md documents strip + bare-ref guard (not capture-all #digits)"
else
  fail "T1: phases.md missing cross-repo exclusion mechanism"
fi

if grep -qE 'acme/lib#15' "$PHASES" && grep -qE '#12 only' "$PHASES"; then
  pass "T1.1: phases.md includes cross-repo vs local example"
else
  fail "T1.1: phases.md missing worked example for acme/lib#15"
fi

if [ ! -f "$PARSE" ]; then
  fail "T2: scripts/dependency_gate_parse.py missing"
else
  pass "T2: reference parser script present"
fi

run_parse() {
  printf '%s' "$1" | python3 "$PARSE" | tr '\n' ' ' | sed 's/ $//'
}

out="$(run_parse 'Blocked by: acme/lib#15')"
if [ -z "$out" ]; then
  pass "T3: cross-repo-only line yields no local deps"
else
  fail "T3: expected empty deps, got: $out"
fi

out="$(run_parse 'Depends on #12, #15')"
if [ "$out" = "12 15" ]; then
  pass "T3.1: multi bare-ref line gates #12 and #15"
else
  fail "T3.1: expected '12 15', got '$out'"
fi

out="$(run_parse $'Blocked by: acme/lib#15, #12')"
if [ "$out" = "12" ]; then
  pass "T3.2: mixed line ignores cross-repo, keeps #12"
else
  fail "T3.2: expected '12', got '$out'"
fi

echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi