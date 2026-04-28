#!/usr/bin/env bash
# test-flattened-self-contained.sh — Verify dist/skills/* is fully self-contained
# (issue #58, §9 of refactor-plan-v10.md).
#
# URL-aware scan of every text file in each flattened skill. Fails on:
#   - Unresolved local `shared/agents/X.md` references (must be rewritten to
#     `references/agents/X.md`).
#   - Unresolved runtime `docs/X.md` references (must be rewritten to
#     `references/docs/X.md`).
#   - Bare `skills/<name>/SKILL.md` references (must be rewritten per ADR
#     row to `../<name>/SKILL.md`).
#   - Unresolved `{{skill:...}}` tokens.
#   - References to local files that do not exist within the flattened skill.
#
# URL-aware: matches inside http:// / https:// URLs are NOT treated as local
# references (mirrors scripts/build.py URL_RE behavior).
#
# Usage: bash tests/test-flattened-self-contained.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_SKILLS="$REPO_ROOT/dist/skills"
BUILD_SH="$REPO_ROOT/scripts/build.sh"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Flattened Self-Contained Tests (issue #58)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# Build if dist/skills/ is missing
if [ ! -d "$DIST_SKILLS" ]; then
  echo "  ○ dist/skills/ missing — running build..."
  "$BUILD_SH" >/dev/null 2>&1 || {
    fail "Pre-build failed — cannot run scan"
    exit 1
  }
fi

# Helper: scan a single file for unresolved local references using a
# URL-aware Python pass that mirrors scripts/build.py semantics.
scan_file() {
  python3 - "$1" "$2" <<'PY'
import re
import sys
from pathlib import Path

filepath = Path(sys.argv[1])
skill_dir = Path(sys.argv[2])
text = filepath.read_text(encoding="utf-8", errors="replace")

URL_RE = re.compile(r"https?://[^\s<>'\"\)]+")
SHARED_AGENT_RE = re.compile(r"(?<![\w/])shared/agents/([a-z][a-z0-9-]+\.md)")
RUNTIME_DOC_RE = re.compile(r"(?<![\w/])docs/([a-z][a-z0-9-]+\.md)")
BARE_SKILL_PATH_RE = re.compile(r"(?<![\w/])skills/([a-z][a-z0-9-]+)/SKILL\.md")
SKILL_TOKEN_RE = re.compile(r"\{\{skill:([a-z][a-z0-9-]*)\}\}")

# Mask all URLs — replace with same-length spaces so character offsets are
# preserved if they ever matter; we only care about presence.
masked = URL_RE.sub(lambda m: " " * len(m.group(0)), text)

# Mask "../docs/..." sibling-relative references (legitimate plugin form),
# but for flattened skills no such form is allowed. We still mask URL
# fragments only; relative-form filtering happens by pattern below.

errors = []

for m in SHARED_AGENT_RE.finditer(masked):
    # Reject any bare shared/agents/*.md — should be references/agents/...
    line_no = masked[: m.start()].count("\n") + 1
    errors.append(f"unresolved 'shared/agents/{m.group(1)}' at line {line_no}")

for m in RUNTIME_DOC_RE.finditer(masked):
    line_no = masked[: m.start()].count("\n") + 1
    errors.append(f"unresolved 'docs/{m.group(1)}' at line {line_no}")

for m in BARE_SKILL_PATH_RE.finditer(masked):
    line_no = masked[: m.start()].count("\n") + 1
    errors.append(f"bare 'skills/{m.group(1)}/SKILL.md' at line {line_no}")

for m in SKILL_TOKEN_RE.finditer(masked):
    line_no = masked[: m.start()].count("\n") + 1
    errors.append(f"unresolved '{{{{skill:{m.group(1)}}}}}' token at line {line_no}")

# Verify referenced local files exist:
# - 'references/agents/X.md' must exist
# - 'references/docs/Y.md' must exist
# - '../<name>/SKILL.md' is intentional cross-skill sibling reference
#   (cannot verify without full dist context — skip here)
LOCAL_AGENT_RE = re.compile(r"(?<![\w/])references/agents/([a-z][a-z0-9-]+\.md)")
LOCAL_DOC_RE = re.compile(r"(?<![\w/])references/docs/([a-z][a-z0-9-]+\.md)")

for m in LOCAL_AGENT_RE.finditer(masked):
    target = skill_dir / "references" / "agents" / m.group(1)
    if not target.is_file():
        line_no = masked[: m.start()].count("\n") + 1
        errors.append(
            f"missing referenced agent file '{target.name}' at line {line_no}"
        )

for m in LOCAL_DOC_RE.finditer(masked):
    target = skill_dir / "references" / "docs" / m.group(1)
    if not target.is_file():
        line_no = masked[: m.start()].count("\n") + 1
        errors.append(
            f"missing referenced doc file '{target.name}' at line {line_no}"
        )

if errors:
    print(f"FAIL: {filepath}")
    for e in errors:
        print(f"  {e}")
    sys.exit(1)
sys.exit(0)
PY
}

TEXT_EXTS_REGEX='\.(md|txt|yml|yaml|json|toml)$'

for skill_dir in "$DIST_SKILLS"/*/; do
  name="$(basename "$skill_dir")"
  errors_in_skill=0
  while IFS= read -r f; do
    if ! scan_file "$f" "$skill_dir"; then
      errors_in_skill=$((errors_in_skill + 1))
    fi
  done < <(find "$skill_dir" -type f -regex ".*$TEXT_EXTS_REGEX")
  if [ "$errors_in_skill" -eq 0 ]; then
    pass "T1: dist/skills/$name is self-contained"
  else
    fail "T1: dist/skills/$name has $errors_in_skill file(s) with unresolved references"
  fi
done

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Flattened skills are not all self-contained"
  exit 1
fi

echo "  ✓ All flattened skills are self-contained"
exit 0
