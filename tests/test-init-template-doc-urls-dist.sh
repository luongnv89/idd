#!/usr/bin/env bash
# test-init-template-doc-urls-dist.sh — Verify both dist copies of the
# init-gitissue template hold the URL policy after build (issue #58, §9 of
# refactor-plan-v10.md).
#
# Same rule as the source variant, applied to:
#   dist/skills/init-gitissue/templates/gitissue-template.yml
#   dist/plugin/skills/init-gitissue/templates/gitissue-template.yml
#
# Stale pattern: any GitHub URL to docs/<file>.md (without src/ prefix) where
# <file> exists in src/docs/.
#
# Usage: bash tests/test-init-template-doc-urls-dist.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DOCS="$REPO_ROOT/src/docs"
BUILD_SH="$REPO_ROOT/scripts/build.sh"
DIST_FLAT_TEMPLATE="$REPO_ROOT/dist/skills/init-gitissue/templates/gitissue-template.yml"
DIST_PLUGIN_TEMPLATE="$REPO_ROOT/dist/plugin/skills/init-gitissue/templates/gitissue-template.yml"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Init Template Doc URL Dist Tests (issue #58)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

if [ ! -f "$DIST_FLAT_TEMPLATE" ] || [ ! -f "$DIST_PLUGIN_TEMPLATE" ]; then
  echo "  ○ dist copies missing — running build..."
  "$BUILD_SH" >/dev/null 2>&1 || {
    fail "Pre-build failed"
    exit 1
  }
fi

scan() {
  local file="$1"
  python3 - "$file" "$SRC_DOCS" <<'PY'
import re
import sys
from pathlib import Path

target = Path(sys.argv[1])
src_docs = Path(sys.argv[2])

if not target.is_file():
    print(f"FAIL: missing {target}")
    sys.exit(1)
if not src_docs.is_dir():
    print(f"FAIL: src/docs/ not found at {src_docs}")
    sys.exit(1)

existing = {p.name for p in src_docs.glob("*.md")}
text = target.read_text(encoding="utf-8")

PATTERN = re.compile(
    r"https://github\.com/luongnv89/idd/[^/\s]+/[^/\s]+/docs/([a-z][a-z0-9-]+\.md)"
)

violations = []
for line_no, line in enumerate(text.splitlines(), start=1):
    for m in PATTERN.finditer(line):
        if m.group(1) in existing:
            violations.append(
                f"line {line_no}: stale URL '{m.group(0)}' — should reference 'src/docs/{m.group(1)}'"
            )

if violations:
    for v in violations:
        print(v)
    sys.exit(1)
sys.exit(0)
PY
}

# ───────────────────────────────────────────────────────────
# T1: dist/skills/init-gitissue copy
# ───────────────────────────────────────────────────────────
if [ -f "$DIST_FLAT_TEMPLATE" ]; then
  flat_violations="$(scan "$DIST_FLAT_TEMPLATE" || true)"
  if [ -z "$flat_violations" ]; then
    pass "T1: dist/skills/init-gitissue/.../gitissue-template.yml passes URL policy"
  else
    fail "T1: stale URLs in flattened template copy"
    printf '%s\n' "$flat_violations" | sed 's/^/    /'
  fi
else
  fail "T1: dist/skills/init-gitissue/.../gitissue-template.yml missing"
fi

# ───────────────────────────────────────────────────────────
# T2: dist/plugin/skills/init-gitissue copy
# ───────────────────────────────────────────────────────────
if [ -f "$DIST_PLUGIN_TEMPLATE" ]; then
  plug_violations="$(scan "$DIST_PLUGIN_TEMPLATE" || true)"
  if [ -z "$plug_violations" ]; then
    pass "T2: dist/plugin/skills/init-gitissue/.../gitissue-template.yml passes URL policy"
  else
    fail "T2: stale URLs in plugin template copy"
    printf '%s\n' "$plug_violations" | sed 's/^/    /'
  fi
else
  fail "T2: dist/plugin/skills/init-gitissue/.../gitissue-template.yml missing"
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Dist template URL check failed"
  exit 1
fi

echo "  ✓ Both dist template copies hold URL policy"
exit 0
