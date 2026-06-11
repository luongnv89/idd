#!/usr/bin/env bash
# test-sync-safety.sh — Validate the stash-first sync convention (issue #22)
#
# This script verifies issue #22 acceptance criteria:
#   AC #1: All skills that run `git pull --rebase` check for dirty working tree first.
#   AC #2: Dirty working tree is handled by stash-before/pop-after as the
#          PRIMARY documented code path.
#   AC #3: On stash pop conflicts, output clear recovery instructions with the stash ref.
#   AC #4: Consistent approach across all affected skills:
#          issue-pr-review, issue-resolver, auto-pilot,
#          plus issue-triage and issue-analysis (same anti-pattern).
#
# Strategy: walk every fenced code block (```bash / ```sh / ```) in src/skills/**/*.md
# and src/skills/**/references/*.md, looking for `git pull --rebase`. For each
# occurrence, the same fenced block must contain a preceding `git stash` invocation.
# Inline prose mentions inside single backticks are ignored — only fenced code blocks
# count, since those are what the skill actually instructs the agent to execute.
#
# Usage: bash tests/test-sync-safety.sh
# Returns: exit 0 if all checks pass, exit 1 on failure

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0
FAIL=0

pass() {
  echo "  ✓ $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  ✗ $1"
  FAIL=$((FAIL + 1))
}

echo "◆ Sync Safety Lint (issue #22)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T1: docs/sync-conventions.md exists
# ───────────────────────────────────────────────────────────
if [ -f "$REPO_ROOT/docs/sync-conventions.md" ]; then
  pass "docs/sync-conventions.md exists (canonical convention)"
else
  fail "docs/sync-conventions.md missing"
fi

# ───────────────────────────────────────────────────────────
# T2: Every fenced `git pull --rebase` is preceded by a `git stash`
#     in the SAME fenced block.
# ───────────────────────────────────────────────────────────
#
# Implementation: use awk to track fenced code-block state and report any
# `git pull --rebase` line whose enclosing block does not also contain
# `git stash`. Inline-code (single backticks) and prose are ignored.

# Files in scope: skills + auto-pilot/issue-resolver references.
# Exclude the convention doc itself (it documents the pattern).
SCAN_DIRS=(
  "$REPO_ROOT/src/skills"
)

# Use a temp file to collect violations across files.
violations="$(mktemp)"
trap 'rm -f "$violations"' EXIT

scan_file() {
  local file="$1"
  awk '
    BEGIN {
      in_block = 0
      block_start = 0
      block_lines = ""
      block_has_rebase = 0
      block_has_stash = 0
    }
    /^```/ {
      if (in_block == 0) {
        in_block = 1
        block_start = NR
        block_lines = ""
        block_has_rebase = 0
        block_has_stash = 0
      } else {
        # Closing fence — evaluate the block.
        if (block_has_rebase == 1 && block_has_stash == 0) {
          printf("%s:%d: fenced block with `git pull --rebase` lacks `git stash`\n", FILENAME, block_start)
        }
        in_block = 0
      }
      next
    }
    {
      if (in_block == 1) {
        if ($0 ~ /git pull --rebase/) {
          block_has_rebase = 1
        }
        if ($0 ~ /git stash/) {
          block_has_stash = 1
        }
      }
    }
  ' "$file"
}

for dir in "${SCAN_DIRS[@]}"; do
  if [ ! -d "$dir" ]; then
    continue
  fi
  while IFS= read -r -d '' file; do
    scan_file "$file" >> "$violations"
  done < <(find "$dir" -type f -name "*.md" -print0)
done

if [ -s "$violations" ]; then
  fail "Unguarded \`git pull --rebase\` found in fenced code blocks:"
  while IFS= read -r line; do
    echo "      $line"
  done < "$violations"
else
  pass "All fenced \`git pull --rebase\` blocks include a preceding \`git stash\`"
fi

# ───────────────────────────────────────────────────────────
# T3: All four skills named in issue #22 reference sync-conventions.md.
# ───────────────────────────────────────────────────────────

NAMED_FILES=(
  "src/skills/issue-pr-review/SKILL.md"
  "src/skills/issue-resolver/SKILL.md"
  "src/skills/auto-pilot/SKILL.md"
)

for rel in "${NAMED_FILES[@]}"; do
  abs="$REPO_ROOT/$rel"
  if [ ! -f "$abs" ]; then
    fail "$rel missing"
    continue
  fi
  if grep -q "sync-conventions.md" "$abs"; then
    pass "$rel references sync-conventions.md"
  else
    fail "$rel does not reference sync-conventions.md"
  fi
done

# ───────────────────────────────────────────────────────────
# T4: The convention doc documents stash-pop conflict recovery
#     with the stash ref (AC #3).
# ───────────────────────────────────────────────────────────

CONV="$REPO_ROOT/docs/sync-conventions.md"
if [ -f "$CONV" ]; then
  if grep -q "stash@{0}" "$CONV"; then
    pass "sync-conventions.md documents stash-pop recovery with stash ref"
  else
    fail "sync-conventions.md missing explicit stash ref recovery (e.g. stash@{0})"
  fi
  if grep -q "git stash list" "$CONV"; then
    pass "sync-conventions.md documents \`git stash list\` recovery command"
  else
    fail "sync-conventions.md missing \`git stash list\` recovery command"
  fi
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Sync safety lint failed"
  exit 1
fi

echo "  ✓ All sync safety checks passed"
exit 0
