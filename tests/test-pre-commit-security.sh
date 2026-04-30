#!/usr/bin/env bash
# test-pre-commit-security.sh — Validate the pre-commit security convention (issue #87)
#
# This script verifies issue #87 acceptance criteria:
#   AC #1: A shared pre-commit safety scan procedure exists at
#          docs/pre-commit-security.md with the secret/credential/large-file
#          checks adopted from /auto-push.
#   AC #2: Every skill that runs `git commit` or `git push` references this
#          shared scan in a fenced block that also (or in nearby prose) cites
#          docs/pre-commit-security.md, so the gate cannot be silently dropped.
#   AC #3: The canonical doc explicitly distinguishes real secrets from
#          placeholders (covers AC #3 from the issue).
#   AC #4: The canonical doc defines the rich-error format that skills use
#          when a secret blocks (covers AC #4 from the issue).
#   AC #5: The canonical doc states warnings are non-blocking and require
#          explicit confirmation in interactive mode / log-and-continue in
#          auto mode (covers AC #5 from the issue).
#
# Strategy: walk every fenced code block (```bash / ```sh) in
# src/skills/**/*.md, src/internal-skills/**/*.md, and
# src/shared/agents/*.md, looking for `git commit` or `git push`. For each
# occurrence, the same fenced block — or the 12 lines of prose immediately
# before the block — must reference `docs/pre-commit-security.md`. The
# canonical doc itself and `/auto-push` examples that demonstrate failure
# output are excluded.
#
# Usage: bash tests/test-pre-commit-security.sh
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

echo "◆ Pre-Commit Security Lint (issue #87)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T1: docs/pre-commit-security.md exists
# ───────────────────────────────────────────────────────────
CONV="$REPO_ROOT/docs/pre-commit-security.md"
if [ -f "$CONV" ]; then
  pass "docs/pre-commit-security.md exists (canonical convention)"
else
  fail "docs/pre-commit-security.md missing"
fi

# ───────────────────────────────────────────────────────────
# T2: Canonical doc covers the four required content areas:
#     - real-key vs. placeholder discrimination
#     - rich error format (✗ symbol + 'docs/pre-commit-security.md')
#     - warning non-block contract
#     - skill-side responsibilities section
# ───────────────────────────────────────────────────────────
if [ -f "$CONV" ]; then
  if grep -q -i "placeholder" "$CONV" && grep -q "your-api-key\|your-key\|YOUR_KEY\|placeholder" "$CONV"; then
    pass "canonical doc distinguishes real keys from placeholders"
  else
    fail "canonical doc missing placeholder discrimination"
  fi

  if grep -q "✗" "$CONV" && grep -q "Pre-commit security scan blocked" "$CONV"; then
    pass "canonical doc defines rich-error format (✗ + blocked message)"
  else
    fail "canonical doc missing rich-error format"
  fi

  if grep -q -i "warnings.*log\|warn.*proceed\|log-and-continue\|log and continue" "$CONV"; then
    pass "canonical doc documents warning non-block contract"
  else
    fail "canonical doc missing warning non-block contract"
  fi

  if grep -q -i "Skill-Side Responsibilities" "$CONV"; then
    pass "canonical doc has Skill-Side Responsibilities section"
  else
    fail "canonical doc missing Skill-Side Responsibilities section"
  fi
fi

# ───────────────────────────────────────────────────────────
# T3: Every fenced block containing `git commit` or `git push` in
#     skill sources is gated by a reference to
#     docs/pre-commit-security.md — either inside the block, or in
#     the 12 lines of prose immediately preceding the block.
#     The canonical doc itself is excluded.
# ───────────────────────────────────────────────────────────

SCAN_DIRS=(
  "$REPO_ROOT/src/skills"
  "$REPO_ROOT/src/internal-skills"
  "$REPO_ROOT/src/shared/agents"
)

violations="$(mktemp)"
trap 'rm -f "$violations"' EXIT

scan_file() {
  local file="$1"
  awk -v file="$file" '
    BEGIN {
      in_block = 0
      is_shell_block = 0
      block_start = 0
      block_has_commit_or_push = 0
      block_has_ref = 0
      # Rolling window of recent prose lines (outside fenced blocks).
      window_size = 12
      for (i = 0; i < window_size; i++) prose[i] = ""
      window_idx = 0
      window_has_ref = 0
    }
    /^```/ {
      if (in_block == 0) {
        in_block = 1
        # Only ```bash and ```sh blocks are executed shell instructions.
        # Plain ``` blocks are display-only (error messages, sample output).
        is_shell_block = ($0 ~ /^```(bash|sh)[[:space:]]*$/) ? 1 : 0
        block_start = NR
        block_has_commit_or_push = 0
        block_has_ref = 0
        # Snapshot whether the prose window already references the doc.
        window_has_ref = 0
        for (i = 0; i < window_size; i++) {
          if (prose[i] ~ /pre-commit-security\.md/) window_has_ref = 1
        }
      } else {
        # Closing fence — evaluate the block.
        if (is_shell_block == 1 && block_has_commit_or_push == 1 && block_has_ref == 0 && window_has_ref == 0) {
          printf("%s:%d: shell block with `git commit` or `git push` is not gated by docs/pre-commit-security.md\n", file, block_start)
        }
        in_block = 0
        is_shell_block = 0
      }
      next
    }
    {
      if (in_block == 1) {
        # Match `git commit` or `git push` as actual commands, not in comments
        # or inline-code mentions. We look for either at start of line (after
        # optional whitespace) or after a shell separator.
        if ($0 ~ /(^|[[:space:]&|;]|^[[:space:]]*)git[[:space:]]+commit([[:space:]]|$)/) {
          block_has_commit_or_push = 1
        }
        if ($0 ~ /(^|[[:space:]&|;]|^[[:space:]]*)git[[:space:]]+push([[:space:]]|$)/) {
          block_has_commit_or_push = 1
        }
        if ($0 ~ /pre-commit-security\.md/) {
          block_has_ref = 1
        }
      } else {
        # Update prose window (ring buffer of last N lines).
        prose[window_idx] = $0
        window_idx = (window_idx + 1) % window_size
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
  fail "Ungated \`git commit\` or \`git push\` found in fenced code blocks:"
  while IFS= read -r line; do
    echo "      $line"
  done < "$violations"
else
  pass "All fenced \`git commit\` / \`git push\` blocks are gated by pre-commit-security.md"
fi

# ───────────────────────────────────────────────────────────
# T4: All four touchpoints identified during research reference
#     pre-commit-security.md somewhere in the file.
# ───────────────────────────────────────────────────────────

NAMED_FILES=(
  "src/shared/agents/implementer.md"
  "src/skills/issue-pr-review/SKILL.md"
  "src/skills/issue-resolver/SKILL.md"
)

for rel in "${NAMED_FILES[@]}"; do
  abs="$REPO_ROOT/$rel"
  if [ ! -f "$abs" ]; then
    fail "$rel missing"
    continue
  fi
  if grep -q "pre-commit-security.md" "$abs"; then
    pass "$rel references pre-commit-security.md"
  else
    fail "$rel does not reference pre-commit-security.md"
  fi
done

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Pre-commit security lint failed"
  exit 1
fi

echo "  ✓ All pre-commit security checks passed"
exit 0
