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
# Issue #548 adds T5-T8: every fenced `reset --hard` must sit behind the
# empty-range guard (`git rev-list origin/<base>..HEAD` is empty), with fixture
# self-checks, and auto-pilot Step 2.1's recovery block is executed in scratch
# repos to prove it stops on local-only work and recovers when there is none.
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

echo "◆ Sync Safety Lint (issues #22, #548)"
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
  "src/skills/issue-pr-review/SKILL.source.md"
  "src/skills/issue-resolver/SKILL.source.md"
  "src/skills/auto-pilot/SKILL.source.md"
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
# T5: Every fenced `reset --hard` carries the empty-range guard (issue #548).
#     A `git rev-list` line over an `..HEAD` range must appear EARLIER in the
#     same fenced block. Scope: all Markdown under src/ plus top-level docs/
#     (runtime docs are bundled into skills).
# ───────────────────────────────────────────────────────────

scan_reset_file() {
  # Fences may be indented (e.g. inside a list item) or use ~~~.
  awk '
    /^[[:space:]]*(```|~~~)/ {
      if (in_block == 0) { in_block = 1; block_start = NR; guarded = 0 }
      else { in_block = 0 }
      next
    }
    in_block == 1 && /git rev-list/ && /\.\.HEAD/ { guarded = 1 }
    in_block == 1 && /reset --hard/ && guarded == 0 {
      printf("%s:%d: fenced `reset --hard` without the empty-range guard\n", FILENAME, NR)
    }
  ' "$1"
}

reset_violations="$(mktemp)"
fixture_dir="$(mktemp -d)"
trap 'rm -f "$violations" "$reset_violations"; rm -rf "$fixture_dir"' EXIT

while IFS= read -r -d '' file; do
  scan_reset_file "$file" >> "$reset_violations"
done < <(find "$REPO_ROOT/src" -type f -name "*.md" -print0; \
         find "$REPO_ROOT/docs" -maxdepth 1 -type f -name "*.md" -print0)

if [ -s "$reset_violations" ]; then
  fail "Unguarded \`reset --hard\` found in fenced code blocks:"
  while IFS= read -r line; do
    echo "      $line"
  done < "$reset_violations"
else
  pass "All fenced \`reset --hard\` blocks carry the empty-range guard"
fi

# T5a/T5b: fixture self-checks — the scanner must flag an unguarded reset
# (column-0 or indented fence, or a guard placed after the reset), and accept
# a guarded one.
printf '%s\n' '```bash' 'git rebase --abort' 'git reset --hard origin/main' '```' \
  > "$fixture_dir/unguarded.md"
printf '%s\n' '```bash' 'git reset --hard origin/main' \
  'n="$(git rev-list --count origin/main..HEAD)"' '```' > "$fixture_dir/late-guard.md"
printf '%s\n' '```bash' 'n="$(git rev-list --count origin/main..HEAD)"' \
  'if [ "$n" = "0" ]; then git reset --hard origin/main; fi' '```' \
  > "$fixture_dir/guarded.md"
printf '%s\n' '1. Recover:' '   ```bash' '   git reset --hard origin/main' '   ```' \
  > "$fixture_dir/indented.md"
if [ -n "$(scan_reset_file "$fixture_dir/unguarded.md")" ] &&
   [ -n "$(scan_reset_file "$fixture_dir/late-guard.md")" ] &&
   [ -n "$(scan_reset_file "$fixture_dir/indented.md")" ]; then
  pass "Scanner flags an unguarded \`reset --hard\` fixture"
else
  fail "Scanner missed an unguarded \`reset --hard\` fixture"
fi
if [ -z "$(scan_reset_file "$fixture_dir/guarded.md")" ]; then
  pass "Scanner accepts a guarded \`reset --hard\` fixture"
else
  fail "Scanner flagged a guarded \`reset --hard\` fixture"
fi

# ───────────────────────────────────────────────────────────
# T6-T8: Run auto-pilot Step 2.1's recovery block in scratch repos.
#   T6: a real sync conflict with a local-only commit stops the run and
#       discards nothing.
#   T7: with no local-only commits the block resets without a prompt.
#   T8: an uncommitted tracked change blocks the reset and is kept.
# ───────────────────────────────────────────────────────────

RESOLVE_MD="$REPO_ROOT/src/skills/auto-pilot/references/phases/phase-2-resolve.md"
recovery="$fixture_dir/recovery.sh"
awk '
  /^```/ {
    if (in_block == 0) { in_block = 1; buf = ""; next }
    in_block = 0
    if (buf ~ /reset --hard/) { printf "%s", buf; exit }
    next
  }
  in_block == 1 { buf = buf $0 "\n" }
' "$RESOLVE_MD" | sed 's/{default_branch}/main/g' > "$recovery"

if ! command -v git >/dev/null 2>&1 || [ ! -s "$recovery" ]; then
  fail "Step 2.1 recovery block not found, or git unavailable"
else
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
  export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
  g() { git -c init.defaultBranch=main -c advice.detachedHead=false "$@" >/dev/null 2>&1; }

  g init --bare "$fixture_dir/origin.git"
  g clone "$fixture_dir/origin.git" "$fixture_dir/seed"
  echo base > "$fixture_dir/seed/f.txt"
  g -C "$fixture_dir/seed" add f.txt
  g -C "$fixture_dir/seed" commit -m base
  g -C "$fixture_dir/seed" push origin HEAD:main
  g clone "$fixture_dir/origin.git" "$fixture_dir/work"
  g clone "$fixture_dir/origin.git" "$fixture_dir/clean"
  g clone "$fixture_dir/origin.git" "$fixture_dir/dirty"
  echo upstream > "$fixture_dir/seed/f.txt"
  g -C "$fixture_dir/seed" commit -am upstream
  g -C "$fixture_dir/seed" push origin HEAD:main

  # T6: local-only commit that conflicts with upstream.
  echo local > "$fixture_dir/work/f.txt"
  g -C "$fixture_dir/work" commit -am local
  local_sha="$(git -C "$fixture_dir/work" rev-parse HEAD)"
  g -C "$fixture_dir/work" fetch origin
  if g -C "$fixture_dir/work" pull --rebase origin main; then
    fail "T6 setup: expected a sync conflict"
  else
    rc=0
    out="$(cd "$fixture_dir/work" && bash "$recovery" </dev/null 2>&1)" || rc=$?
    if [ "$rc" -ne 0 ] &&
       [ "$(git -C "$fixture_dir/work" rev-parse HEAD)" = "$local_sha" ] &&
       [ "$(cat "$fixture_dir/work/f.txt")" = "local" ] &&
       printf '%s' "$out" | grep -q "cannot recover automatically"; then
      pass "Sync conflict with a local-only commit stops and discards nothing"
    else
      fail "Sync conflict with a local-only commit was not stopped safely (rc=$rc)"
    fi
  fi

  # T7: no local-only commits — the guarded reset recovers, no prompt.
  g -C "$fixture_dir/clean" fetch origin
  rc=0
  out="$(cd "$fixture_dir/clean" && bash "$recovery" </dev/null 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ] &&
     [ "$(git -C "$fixture_dir/clean" rev-parse HEAD)" = \
       "$(git -C "$fixture_dir/clean" rev-parse origin/main)" ] &&
     printf '%s' "$out" | grep -q "auto-reset to origin/main"; then
    pass "Sync conflict with no local-only commits recovers without a prompt"
  else
    fail "Guarded reset did not recover a clean checkout (rc=$rc)"
  fi

  # T8: no local-only commits but an uncommitted tracked change — stop, keep it.
  echo wip > "$fixture_dir/dirty/f.txt"
  g -C "$fixture_dir/dirty" fetch origin
  rc=0
  out="$(cd "$fixture_dir/dirty" && bash "$recovery" </dev/null 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ] && [ "$(cat "$fixture_dir/dirty/f.txt")" = "wip" ]; then
    pass "An uncommitted tracked change blocks the reset and is kept"
  else
    fail "Guarded reset discarded an uncommitted tracked change (rc=$rc)"
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
