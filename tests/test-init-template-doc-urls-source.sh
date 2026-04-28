#!/usr/bin/env bash
# test-init-template-doc-urls-source.sh — Verify init-gitissue source template
# does not reference moved runtime docs at the old path
# (issue #58, §9 of refactor-plan-v10.md, §3 init-gitissue special case).
#
# Rule: comments inside src/skills/init-gitissue/templates/gitissue-template.yml
# may reference runtime docs as absolute GitHub URLs pinned to `main`. They
# MUST point at `src/docs/<file>.md` for any `<file>` that exists in
# `src/docs/`. A URL of the form
# `https://github.com/luongnv89/idd/.../docs/<file>.md` (without the `src/`
# prefix) is stale post-move and must be flagged.
#
# This test runs BEFORE the build in CI for fast failure.
#
# Usage: bash tests/test-init-template-doc-urls-source.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$REPO_ROOT/src/skills/init-gitissue/templates/gitissue-template.yml"
SRC_DOCS="$REPO_ROOT/src/docs"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Init Template Doc URL Source Tests (issue #58)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T1: template file exists
# ───────────────────────────────────────────────────────────
if [ -f "$TEMPLATE" ]; then
  pass "T1: source template exists at expected path"
else
  fail "T1: source template missing: $TEMPLATE"
  exit 1
fi

# ───────────────────────────────────────────────────────────
# T2: scan template for stale doc URLs
# ───────────────────────────────────────────────────────────
violation_output="$(python3 - "$TEMPLATE" "$SRC_DOCS" <<'PY'
import re
import sys
from pathlib import Path

template = Path(sys.argv[1])
src_docs = Path(sys.argv[2])

if not src_docs.is_dir():
    print(f"FAIL: src/docs/ not found at {src_docs}")
    sys.exit(1)

# Names of docs that exist in src/docs/
existing = {p.name for p in src_docs.glob("*.md")}

text = template.read_text(encoding="utf-8")

# Pattern: GitHub URLs to docs/<file>.md in luongnv89/idd repo where <file>
# matches a doc in src/docs/. The URL must reference src/docs/<file>.md
# instead. We allow any branch/tag in the path because the rule applies
# regardless.
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
)"

if [ -z "$violation_output" ]; then
  pass "T2: no stale 'docs/<file>.md' GitHub URLs in source template"
else
  fail "T2: stale GitHub URLs detected in source template"
  printf '%s\n' "$violation_output" | sed 's/^/    /'
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Source template URL check failed"
  exit 1
fi

echo "  ✓ Source template URL policy holds"
exit 0
