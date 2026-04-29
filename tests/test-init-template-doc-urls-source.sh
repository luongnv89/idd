#!/usr/bin/env bash
# test-init-template-doc-urls-source.sh — Verify init-gitissue source template
# does not reference moved runtime docs at the old path
# (issue #58, §9 of refactor-plan-v10.md, §3 init-gitissue special case;
# updated for issue #81 single-tree consolidation).
#
# Rule: comments inside src/skills/init-gitissue/templates/gitissue-template.yml
# may reference runtime docs as absolute GitHub URLs pinned to `main`. They
# MUST point at `docs/<file>.md` for any `<file>` that exists in `docs/`
# (top-level, post-#81 consolidation). A URL of the form
# `https://github.com/luongnv89/idd/.../src/docs/<file>.md` is stale post-#81
# and must be flagged.
#
# This test runs BEFORE the build in CI for fast failure.
#
# Usage: bash tests/test-init-template-doc-urls-source.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$REPO_ROOT/src/skills/init-gitissue/templates/gitissue-template.yml"
RUNTIME_DOCS="$REPO_ROOT/docs"

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
# Capture violations regardless of Python exit code. Without `|| true`, the
# Python `sys.exit(1)` on detected violations would propagate through
# `set -euo pipefail` and abort the script before T2's pass/fail check.
violation_output="$(python3 - "$TEMPLATE" "$RUNTIME_DOCS" <<'PY'
import re
import sys
from pathlib import Path

template = Path(sys.argv[1])
runtime_docs = Path(sys.argv[2])

if not runtime_docs.is_dir():
    print(f"FAIL: docs/ not found at {runtime_docs}")
    sys.exit(1)

# Names of runtime docs that exist at top-level docs/.
existing = {p.name for p in runtime_docs.glob("*.md")}

text = template.read_text(encoding="utf-8")

# Pattern: GitHub URLs to /src/docs/<file>.md in luongnv89/idd repo. Mirrors
# STALE_DOC_URL_RE in scripts/build.py — post-#81 the canonical path is
# /docs/<file>.md and any URL with /src/docs/ is stale.
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
)" || true

if [ -z "$violation_output" ]; then
  pass "T2: no stale '/src/docs/<file>.md' GitHub URLs in source template"
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
