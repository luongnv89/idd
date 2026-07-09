#!/usr/bin/env bash
# test-issue-resolver-worktree.sh — Validate interactive worktree resolver contract
#
# This script verifies issue #123 and #129 acceptance criteria:
#   AC #1: interactive /issue-resolver offers a new git worktree or current tree.
#   AC #2: accepted worktree path creates/prepares a worktree with local setup.
#   AC #3: declined path keeps current in-place behavior.
#   AC #4: auto-pilot / IDD_AUTO_MODE=1 never shows the worktree prompt.
#   AC #5: prompt states copied/setup artifacts and branch/workspace naming.
#   #129: auto mode in-place default is explicit; auto-pilot resolver prompt matches.
#
# Usage: bash tests/test-issue-resolver-worktree.sh
# Returns: exit 0 if all checks pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

contains() {
  local file="$1"
  local pattern="$2"
  grep -qE "$pattern" "$file"
}

check_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if contains "$file" "$pattern"; then
    pass "$label"
  else
    fail "$label"
    echo "      missing pattern: $pattern"
    echo "      in file: $file"
  fi
}

echo "◆ Issue Resolver Worktree Contract Tests (issue #123)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

SRC_SKILL="$REPO_ROOT/src/skills/issue-resolver/SKILL.source.md"
SRC_STEPS="$REPO_ROOT/src/skills/issue-resolver/references/pipeline-steps.md"
SRC_ERRORS="$REPO_ROOT/src/skills/issue-resolver/references/error-messages.md"
SRC_AUTOPILOT_PROMPTS="$REPO_ROOT/src/skills/auto-pilot/references/subagent-prompts.md"
ROOT_SKILL="$REPO_ROOT/skills/issue-resolver/SKILL.md"
ROOT_STEPS="$REPO_ROOT/skills/issue-resolver/references/pipeline-steps.md"
ROOT_ERRORS="$REPO_ROOT/skills/issue-resolver/references/error-messages.md"

for file in "$SRC_SKILL" "$SRC_STEPS" "$SRC_ERRORS" "$SRC_AUTOPILOT_PROMPTS" "$ROOT_SKILL" "$ROOT_STEPS" "$ROOT_ERRORS"; do
  if [ -f "$file" ]; then
    pass "exists: ${file#$REPO_ROOT/}"
  else
    fail "missing: ${file#$REPO_ROOT/}"
  fi
done

# ───────────────────────────────────────────────────────────
# T1: Interactive prompt exists and gives the expected choice.
# ───────────────────────────────────────────────────────────
check_contains "$SRC_SKILL" '### 0e .*Workspace \(interactive only\)' \
  "T1.1: source skill defines interactive-only workspace step"
check_contains "$SRC_SKILL" 'Resolve in a new worktree\? \[Y/n\]' \
  "T1.2: prompt offers worktree with current-tree decline option"
check_contains "$SRC_SKILL" 'Accepting keeps your current working tree untouched' \
  "T1.3: prompt explains acceptance isolates current working tree"

# ───────────────────────────────────────────────────────────
# T2: Auto mode skips the prompt entirely.
# ───────────────────────────────────────────────────────────
check_contains "$SRC_SKILL" 'Auto mode .*IDD_AUTO_MODE=1.*skip this offer entirely|Auto mode .*--auto.*skip this offer entirely' \
  "T2.1: source skill says auto mode skips offer"
check_contains "$SRC_STEPS" 'Interactive mode only.*auto mode .*skipped|Interactive mode only.*IDD_AUTO_MODE=1.*skipped' \
  "T2.2: pipeline details say worktree step is skipped in auto mode"
check_contains "$SRC_STEPS" 'worktree prompt never appears in auto mode' \
  "T2.3: no-prompt auto-mode contract is explicit"
check_contains "$SRC_SKILL" 'Workspace:.*in-place.*Skip Step 0e' \
  "T2.4 (#129): Auto-Pilot Mode section states in-place default"
check_contains "$SRC_SKILL" 'no `git worktree add` on the default resolution path' \
  "T2.5 (#129): auto mode forbids default worktree creation"

# ───────────────────────────────────────────────────────────
# T3: Worktree branch/path naming and setup are stated before acceptance.
# ───────────────────────────────────────────────────────────
check_contains "$SRC_SKILL" 'Branch:[[:space:]]+\{branch_name\}' \
  "T3.1: prompt states the derived branch name"
check_contains "$SRC_SKILL" 'resolve\.branch_prefix' \
  "T3.2: prompt derives branch name from resolve.branch_prefix"
check_contains "$SRC_SKILL" 'Worktree:[[:space:]]+\.\./\{repo\}-worktrees/\{branch_name with / → -\}' \
  "T3.3: prompt derives worktree naming from the branch name"
check_contains "$SRC_SKILL" 'copies your gitignored local config \(\.env\*, and similar\)' \
  "T3.4: prompt states local config/env copy"
check_contains "$SRC_SKILL" 'detected install/bootstrap' \
  "T3.5: prompt states detected install/bootstrap setup"

# ───────────────────────────────────────────────────────────
# T4: Accepted path creates/prepares the worktree generically.
# ───────────────────────────────────────────────────────────
check_contains "$SRC_STEPS" 'git worktree add -b "\$branch_name" "\$wt_dir" "origin/\$\{base\}"' \
  "T4.1: accepted path uses the derived branch and fetched base"
check_contains "$SRC_STEPS" 'cd "\$wt_dir"' \
  "T4.2: subsequent resolver steps run inside worktree"
check_contains "$SRC_STEPS" 'for f in \.env \.env\.local \.env\.development \.env\.test' \
  "T4.3: setup copies common env files when present"
check_contains "$SRC_STEPS" 'gitignored local config|\.gitignore.*local-only' \
  "T4.4: setup uses gitignored local config as the guide"
check_contains "$SRC_STEPS" 'detected package manager|npm ci|pnpm install|pip install|uv sync|bundle install|go mod download|cargo fetch' \
  "T4.5: setup uses detected dependency manager"
check_contains "$SRC_STEPS" 'Makefile.*setup|scripts/setup\.sh|bootstrap' \
  "T4.6: setup runs detected project bootstrap when present"

# ───────────────────────────────────────────────────────────
# T5: Decline/failure paths keep current behavior.
# ───────────────────────────────────────────────────────────
check_contains "$SRC_SKILL" 'Declining uses the[[:space:]]+current working tree with the existing sync and branch behavior|Decline.*current working tree exactly as today|declined the worktree offer' \
  "T5.1: decline path keeps current working-tree behavior"
check_contains "$SRC_SKILL" 'mandatory Repo Sync.*0f|Repo Sync.*Create branch' \
  "T5.2: decline path retains stash-first sync plus branch creation"
check_contains "$SRC_ERRORS" 'Worktree creation failed' \
  "T5.3: worktree creation fallback error is documented"
check_contains "$SRC_ERRORS" 'Worktree setup failed' \
  "T5.4: worktree setup fallback error is documented"
check_contains "$SRC_STEPS" 'git worktree remove "\$wt_dir" --force' \
  "T5.5: setup failure cleans up partial worktree before fallback"
check_contains "$SRC_STEPS" 'created_branch_in_step_0e' \
  "T5.6: setup failure only deletes branches created by Step 0e"
check_contains "$SRC_STEPS" 'git branch -D "\$branch_name"' \
  "T5.7: setup failure deletes the derived prefix-aware worktree branch"
check_contains "$SRC_ERRORS" 'Falling back to resolving in the current working tree|falling back to resolving in the[[:space:]]+current working tree' \
  "T5.8: worktree failures fall back in-place"

# ───────────────────────────────────────────────────────────
# T6: Root install surface mirrors the contract.
# ───────────────────────────────────────────────────────────
for file in "$ROOT_SKILL" "$ROOT_STEPS" "$ROOT_ERRORS"; do
  rel="${file#$REPO_ROOT/}"
  check_contains "$file" 'worktree|Worktree' "T6: generated $rel contains worktree contract text"
done

# ───────────────────────────────────────────────────────────
# T7 (#129): Auto-pilot resolver subagent uses in-place auto contract.
# ───────────────────────────────────────────────────────────
check_contains "$SRC_AUTOPILOT_PROMPTS" 'Workspace is in-place only: skip Step 0e' \
  "T7.1 (#129): auto-pilot resolver prompt skips worktree"
check_contains "$SRC_AUTOPILOT_PROMPTS" 'no `git worktree add`' \
  "T7.2 (#129): auto-pilot forbids worktree add on resolve path"

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

exit 0
