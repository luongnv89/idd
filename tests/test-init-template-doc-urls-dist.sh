#!/usr/bin/env bash
# test-init-template-doc-urls-dist.sh — Verify the built copy of the
# init-gitissue template holds the URL policy after build (issue #58, §9 of
# refactor-plan-v10.md; updated for issue #81 and #106).
#
# Same rule as the source variant, applied to:
#   skills/init-gitissue/templates/gitissue-template.yml (committed)
#
# Stale pattern: any GitHub URL to /src/docs/<file>.md where <file> exists
# at top-level docs/. Post-#81 the canonical path is /docs/<file>.md.
#
# Usage: bash tests/test-init-template-doc-urls-dist.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_DOCS="$REPO_ROOT/docs"
BUILD_SH="$REPO_ROOT/scripts/build.sh"
SKILL_TEMPLATE="$REPO_ROOT/skills/init-gitissue/templates/gitissue-template.yml"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Init Template Doc URL Dist Tests (issue #58)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

if [ ! -f "$SKILL_TEMPLATE" ]; then
  echo "  ○ template copies missing — running build..."
  "$BUILD_SH" >/dev/null 2>&1 || {
    fail "Pre-build failed"
    exit 1
  }
fi

scan() {
  local file="$1"
  python3 - "$file" "$RUNTIME_DOCS" <<'PY'
import re
import sys
from pathlib import Path

target = Path(sys.argv[1])
runtime_docs = Path(sys.argv[2])

if not target.is_file():
    print(f"FAIL: missing {target}")
    sys.exit(1)
if not runtime_docs.is_dir():
    print(f"FAIL: docs/ not found at {runtime_docs}")
    sys.exit(1)

existing = {p.name for p in runtime_docs.glob("*.md")}
text = target.read_text(encoding="utf-8")

# Mirrors STALE_DOC_URL_RE in scripts/build.py post-#81: any URL with
# /src/docs/<file>.md is stale — the canonical path is /docs/<file>.md.
PATTERN = re.compile(
    r"https://github\.com/luongnv89/idd/[^\s<>'\"\)]*?/src/docs/([a-z][a-z0-9-]+\.md)"
)

violations = []
for line_no, line in enumerate(text.splitlines(), start=1):
    for m in PATTERN.finditer(line):
        if m.group(1) in existing:
            violations.append(
                f"line {line_no}: stale URL '{m.group(0)}' — should reference 'docs/{m.group(1)}'"
            )

if violations:
    for v in violations:
        print(v)
    sys.exit(1)
sys.exit(0)
PY
}

# ───────────────────────────────────────────────────────────
# T1: skills/init-gitissue copy (committed)
# ───────────────────────────────────────────────────────────
if [ -f "$SKILL_TEMPLATE" ]; then
  flat_violations="$(scan "$SKILL_TEMPLATE" || true)"
  if [ -z "$flat_violations" ]; then
    pass "T1: skills/init-gitissue/.../gitissue-template.yml passes URL policy"
  else
    fail "T1: stale URLs in skills template copy"
    printf '%s\n' "$flat_violations" | sed 's/^/    /'
  fi
else
  fail "T1: skills/init-gitissue/.../gitissue-template.yml missing"
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

echo "  ✓ Built template copy holds URL policy"
exit 0
