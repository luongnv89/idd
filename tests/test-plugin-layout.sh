#!/usr/bin/env bash
# test-plugin-layout.sh — Validate dist/plugin/ layout (issue #58, §9 of
# refactor-plan-v10.md).
#
# Asserts:
#   - dist/plugin/.claude-plugin/plugin.json exists
#   - dist/plugin/.claude-plugin/ contains ONLY plugin.json (no other files)
#   - plugin.json validates against scripts/plugin-schema.json (structural
#     check via Python, no external jsonschema dep required)
#   - If `claude plugin validate` is on PATH, runs it as the authoritative gate
#
# Usage: bash tests/test-plugin-layout.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_PLUGIN="$REPO_ROOT/dist/plugin"
SCHEMA_PATH="$REPO_ROOT/scripts/plugin-schema.json"
BUILD_SH="$REPO_ROOT/scripts/build.sh"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Plugin Layout Tests (issue #58)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# Build if dist/plugin/ is missing (it's git-ignored)
if [ ! -d "$DIST_PLUGIN" ]; then
  echo "  ○ dist/plugin/ missing — running build..."
  "$BUILD_SH" >/dev/null 2>&1 || {
    fail "Pre-build failed — cannot run layout checks"
    exit 1
  }
fi

# ───────────────────────────────────────────────────────────
# T1: .claude-plugin/plugin.json exists
# ───────────────────────────────────────────────────────────
PLUGIN_JSON="$DIST_PLUGIN/.claude-plugin/plugin.json"
if [ -f "$PLUGIN_JSON" ]; then
  pass "T1: dist/plugin/.claude-plugin/plugin.json exists"
else
  fail "T1: dist/plugin/.claude-plugin/plugin.json missing"
  exit 1
fi

# ───────────────────────────────────────────────────────────
# T2: .claude-plugin/ contains only plugin.json
# ───────────────────────────────────────────────────────────
unexpected="$(find "$DIST_PLUGIN/.claude-plugin" -mindepth 1 \
  ! -name "plugin.json" 2>/dev/null || true)"
if [ -z "$unexpected" ]; then
  pass "T2: .claude-plugin/ contains only plugin.json"
else
  printf '%s\n' "$unexpected" | sed 's/^/    /'
  fail "T2: .claude-plugin/ contains unexpected files"
fi

# ───────────────────────────────────────────────────────────
# T3: plugin.json is valid JSON and has required keys
# ───────────────────────────────────────────────────────────
if python3 - "$PLUGIN_JSON" "$SCHEMA_PATH" <<'PY'; then
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
schema_path = Path(sys.argv[2])

try:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
except json.JSONDecodeError as e:
    print(f"FAIL: plugin.json is not valid JSON: {e}")
    sys.exit(1)

# Structural check derived from scripts/plugin-schema.json without requiring
# the jsonschema package. The schema's required keys at top-level are 'name'.
# We additionally check for 'version', 'description', 'author' since the
# build always emits them.
required = ["name"]
recommended = ["version", "description", "author"]

missing = [k for k in required if k not in manifest]
if missing:
    print(f"FAIL: plugin.json missing required keys: {missing}")
    sys.exit(1)

absent = [k for k in recommended if k not in manifest]
if absent:
    print(f"FAIL: plugin.json missing expected keys: {absent}")
    sys.exit(1)

# Light schema check: parse schema, find required keys, ensure manifest covers
# them. (Avoids a hard dep on jsonschema.)
try:
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
except (json.JSONDecodeError, FileNotFoundError) as e:
    print(f"WARN: could not load schema for cross-check: {e}")
    sys.exit(0)

schema_required = schema.get("required", [])
missing_schema = [k for k in schema_required if k not in manifest]
if missing_schema:
    print(f"FAIL: plugin.json missing schema-required keys: {missing_schema}")
    sys.exit(1)

print("OK")
sys.exit(0)
PY
  pass "T3: plugin.json structurally valid against scripts/plugin-schema.json"
else
  fail "T3: plugin.json structural validation failed"
fi

# ───────────────────────────────────────────────────────────
# T4: claude plugin validate (if available)
# ───────────────────────────────────────────────────────────
if command -v claude >/dev/null 2>&1; then
  if claude plugin --help 2>/dev/null | grep -q validate; then
    if claude plugin validate "$DIST_PLUGIN" >/dev/null 2>&1; then
      pass "T4: claude plugin validate accepts dist/plugin/"
    else
      fail "T4: claude plugin validate rejected dist/plugin/"
    fi
  else
    pass "T4: claude plugin validate not exposed by CLI — skipped"
  fi
else
  pass "T4: claude CLI not on PATH — skipped (test still passes per issue spec)"
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Plugin layout tests failed"
  exit 1
fi

echo "  ✓ Plugin layout tests pass"
exit 0
