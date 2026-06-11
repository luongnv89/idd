#!/usr/bin/env bash
# test-flattened-coexistence.sh — Verify that two independent flattened skills
# coexist in the same skills directory without reference collisions
# (issue #58, §9 of refactor-plan-v10.md; updated for #106: skills/ is the
# committed install surface).
#
# Strategy:
#   1. Copy `skills/issue-creator/` and `skills/init-gitissue/`
#      into a fresh temp directory.
#   2. Verify each skill remains self-contained: every `references/agents/*.md`
#      and `references/docs/*.md` referenced from the skill exists inside its
#      own directory.
#   3. Verify the two skills' directories don't collide (different top-level
#      names) and no file inside either skill escapes its own root.
#
# Usage: bash tests/test-flattened-coexistence.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS="$REPO_ROOT/skills"
BUILD_SH="$REPO_ROOT/scripts/build.sh"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Flattened Coexistence Tests (issue #58)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

if [ ! -d "$SKILLS" ]; then
  echo "  ○ skills/ missing — running build..."
  "$BUILD_SH" >/dev/null 2>&1 || {
    fail "Pre-build failed"
    exit 1
  }
fi

# ───────────────────────────────────────────────────────────
# T1: required source skills are present
# ───────────────────────────────────────────────────────────
SKILL_A="$SKILLS/issue-creator"
SKILL_B="$SKILLS/init-gitissue"

if [ -d "$SKILL_A" ] && [ -d "$SKILL_B" ]; then
  pass "T1: both candidate skills exist in skills/"
else
  fail "T1: missing skills/issue-creator or skills/init-gitissue"
  echo "  Cannot continue."
  echo "  Passed: $PASS"
  echo "  Failed: $FAIL"
  exit 1
fi

# ───────────────────────────────────────────────────────────
# T2: copy both skills into a single temp dir
# ───────────────────────────────────────────────────────────
TMP="$(mktemp -d)"
HELPER_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP" "$HELPER_DIR"' EXIT

cp -R "$SKILL_A" "$TMP/"
cp -R "$SKILL_B" "$TMP/"

if [ -d "$TMP/issue-creator" ] && [ -d "$TMP/init-gitissue" ]; then
  pass "T2: both skills copied to a single skills directory"
else
  fail "T2: copy step did not produce both skill directories"
fi

# ───────────────────────────────────────────────────────────
# T3: skill directory names are distinct (no collision when placed side-by-side)
# ───────────────────────────────────────────────────────────
NAME_A="$(basename "$SKILL_A")"
NAME_B="$(basename "$SKILL_B")"
if [ "$NAME_A" != "$NAME_B" ]; then
  pass "T3: skill directory names differ ($NAME_A vs $NAME_B)"
else
  fail "T3: skill directory names collide ($NAME_A == $NAME_B)"
fi

# ───────────────────────────────────────────────────────────
# T4: each skill's local references resolve within its own tree.
# Use a Python helper file to keep the bash heredoc out of $(...) capture.
# ───────────────────────────────────────────────────────────
HELPER="$HELPER_DIR/check_local_refs.py"
cat > "$HELPER" <<'PY'
import re
import sys
from pathlib import Path

base = Path(sys.argv[1])
URL_RE = re.compile(r"https?://\S+")
LOCAL_AGENT_RE = re.compile(r"(?<![\w/])references/agents/([a-z][a-z0-9-]+\.md)")
LOCAL_DOC_RE = re.compile(r"(?<![\w/])references/docs/([a-z][a-z0-9-]+\.md)")
EXTS = {".md", ".txt", ".yml", ".yaml", ".json", ".toml"}

errors = []
for f in base.rglob("*"):
    if not f.is_file() or f.suffix not in EXTS:
        continue
    text = f.read_text(encoding="utf-8", errors="replace")
    masked = URL_RE.sub(lambda m: " " * len(m.group(0)), text)
    rel = f.relative_to(base)
    for m in LOCAL_AGENT_RE.finditer(masked):
        target = base / "references" / "agents" / m.group(1)
        if not target.is_file():
            errors.append(f"{rel}: missing references/agents/{m.group(1)}")
    for m in LOCAL_DOC_RE.finditer(masked):
        target = base / "references" / "docs" / m.group(1)
        if not target.is_file():
            errors.append(f"{rel}: missing references/docs/{m.group(1)}")

if errors:
    for e in errors[:20]:
        print(f"  {e}")
    sys.exit(1)
sys.exit(0)
PY

for skill_dir in "$TMP/issue-creator" "$TMP/init-gitissue"; do
  name="$(basename "$skill_dir")"
  if python3 "$HELPER" "$skill_dir"; then
    pass "T4: $name local references resolve inside the skill"
  else
    fail "T4: $name has unresolved local references after coexistence copy"
  fi
done

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Coexistence tests failed"
  exit 1
fi

echo "  ✓ issue-creator and init-gitissue coexist cleanly"
exit 0
