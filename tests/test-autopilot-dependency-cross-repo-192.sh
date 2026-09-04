#!/usr/bin/env bash
# test-autopilot-dependency-cross-repo-192.sh — Issue #192 acceptance checks
#
# The parser moved to src/shared/scripts/gi-deps.py and now ships inside
# auto-pilot as references/scripts/gi-deps.py (issue #251), so T4 re-runs every
# behavior case against the installed copy: the dev-tree file is what we edit,
# the shipped copy is what actually gates a merge.
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

. "$(cd "$(dirname "$0")" && pwd)/lib/spec.bash"  # spec_concat — split reference specs read as one file (#323)
PHASES="$(spec_concat "$REPO_ROOT/src/skills/auto-pilot/references/phases.md")"
PARSE="$REPO_ROOT/src/shared/scripts/gi-deps.py"
SHIPPED_PARSE="$REPO_ROOT/skills/auto-pilot/references/scripts/gi-deps.py"

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
  fail "T2: src/shared/scripts/gi-deps.py missing"
else
  pass "T2: parser source present at src/shared/scripts/gi-deps.py"
fi

run_parse() {
  # $1 = parser path, $2 = issue body
  printf '%s' "$2" | python3 "$1" | tr '\n' ' ' | sed 's/ $//'
}

out="$(run_parse "$PARSE" 'Blocked by: acme/lib#15')"
if [ -z "$out" ]; then
  pass "T3: cross-repo-only line yields no local deps"
else
  fail "T3: expected empty deps, got: $out"
fi

out="$(run_parse "$PARSE" 'Depends on #12, #15')"
if [ "$out" = "12 15" ]; then
  pass "T3.1: multi bare-ref line gates #12 and #15"
else
  fail "T3.1: expected '12 15', got '$out'"
fi

out="$(run_parse "$PARSE" $'Blocked by: acme/lib#15, #12')"
if [ "$out" = "12" ]; then
  pass "T3.2: mixed line ignores cross-repo, keeps #12"
else
  fail "T3.2: expected '12', got '$out'"
fi

# ───────────────────────────────────────────────────────────
# T4 (issue #251): the same three cases against the SHIPPED copy — the file the
# installed auto-pilot actually runs. A build that dropped, truncated, or failed
# to re-copy the parser would leave T3 green and the gate broken.
# ───────────────────────────────────────────────────────────
if [ ! -f "$SHIPPED_PARSE" ]; then
  fail "T4: skills/auto-pilot/references/scripts/gi-deps.py missing — run ./scripts/build.sh"
else
  pass "T4: shipped parser present at skills/auto-pilot/references/scripts/gi-deps.py"

  out="$(run_parse "$SHIPPED_PARSE" 'Blocked by: acme/lib#15')"
  if [ -z "$out" ]; then
    pass "T4.1: shipped parser — cross-repo-only line yields no local deps"
  else
    fail "T4.1: shipped parser expected empty deps, got: $out"
  fi

  out="$(run_parse "$SHIPPED_PARSE" 'Depends on #12, #15')"
  if [ "$out" = "12 15" ]; then
    pass "T4.2: shipped parser — multi bare-ref line gates #12 and #15"
  else
    fail "T4.2: shipped parser expected '12 15', got '$out'"
  fi

  out="$(run_parse "$SHIPPED_PARSE" $'Blocked by: acme/lib#15, #12')"
  if [ "$out" = "12" ]; then
    pass "T4.3: shipped parser — mixed line ignores cross-repo, keeps #12"
  else
    fail "T4.3: shipped parser expected '12', got '$out'"
  fi

  if cmp -s "$PARSE" "$SHIPPED_PARSE"; then
    pass "T4.4: shipped parser is byte-identical to its source"
  else
    fail "T4.4: shipped parser differs from src/shared/scripts/gi-deps.py"
  fi
fi

echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi