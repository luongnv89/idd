#!/usr/bin/env bash
# test-plugin-tarball-layout.sh — Verify plugin release tarball has the correct
# archive root layout (issue #58, §9 of refactor-plan-v10.md).
#
# Strategy:
#   Build the plugin tree, then create a release-shaped tarball using
#   `tar -czf <name> -C dist/plugin .`. Inspect the archive listing and
#   verify the archive root contains:
#       .claude-plugin/  skills/  shared/  docs/
#   and DOES NOT contain a top-level `plugin/` directory (which would mean
#   someone used `-C dist plugin` instead — wrong root).
#
# Usage: bash tests/test-plugin-tarball-layout.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_PLUGIN="$REPO_ROOT/dist/plugin"
BUILD_SH="$REPO_ROOT/scripts/build.sh"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Plugin Tarball Layout Tests (issue #58)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# Ensure plugin tree is built (it's git-ignored)
if [ ! -d "$DIST_PLUGIN" ]; then
  echo "  ○ dist/plugin/ missing — running build..."
  "$BUILD_SH" >/dev/null 2>&1 || {
    fail "Pre-build failed"
    exit 1
  }
fi

# ───────────────────────────────────────────────────────────
# T1: produce tarball using the documented command
# ───────────────────────────────────────────────────────────
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
TARBALL="$TMP_DIR/idd-plugin-test.tar.gz"

if tar -czf "$TARBALL" -C "$DIST_PLUGIN" . 2>/dev/null; then
  pass "T1: tar -czf <name> -C dist/plugin . succeeds"
else
  fail "T1: tar command failed"
  exit 1
fi

# ───────────────────────────────────────────────────────────
# T2: archive root contains the four expected entries
# ───────────────────────────────────────────────────────────
listing="$(tar -tzf "$TARBALL")"

# Top-level entries (strip ./ prefix from tar output, take first path
# component). Use python for robust parsing.
top_levels="$(printf '%s\n' "$listing" | python3 - <<'PY'
import sys

tops = set()
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    # Strip leading ./ and take the first path component
    if line.startswith("./"):
        line = line[2:]
    if not line or line.startswith("/"):
        continue
    first = line.split("/", 1)[0]
    if first:
        tops.add(first)

for t in sorted(tops):
    print(t)
PY
)"

for expected in ".claude-plugin" "skills" "shared" "docs"; do
  if printf '%s\n' "$top_levels" | grep -qxF "$expected"; then
    pass "T2: archive root contains '$expected/'"
  else
    fail "T2: archive root missing '$expected/'"
  fi
done

# ───────────────────────────────────────────────────────────
# T3: archive root MUST NOT contain a top-level 'plugin/' directory
# (would indicate `tar -C dist plugin` was used by mistake)
# ───────────────────────────────────────────────────────────
if printf '%s\n' "$top_levels" | grep -qxF "plugin"; then
  fail "T3: archive contains forbidden top-level 'plugin/' directory"
  printf '%s\n' "$top_levels" | head -10 | sed 's/^/    /'
else
  pass "T3: archive root has no top-level 'plugin/' directory"
fi

# ───────────────────────────────────────────────────────────
# T4: .claude-plugin/plugin.json present in archive
# ───────────────────────────────────────────────────────────
if printf '%s\n' "$listing" | grep -qE '^\.?/?\.claude-plugin/plugin\.json$'; then
  pass "T4: .claude-plugin/plugin.json present in archive"
else
  fail "T4: .claude-plugin/plugin.json missing from archive"
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Plugin tarball layout tests failed"
  exit 1
fi

echo "  ✓ Plugin tarball layout matches release spec"
exit 0
