---
name: review-fix-loop
description: Automated review-fix cycle for PRs and branches. Spawns a fresh reviewer agent, fixes detected issues, re-reviews with another fresh agent, and repeats until clean — then creates one clean commit. Use when asked to "review and fix", "review fix loop", "auto-review my PR", "fix review issues", "clean up this PR", "review until clean", or when the user wants to iterate on code quality without manually cycling between review and fix. Also trigger when someone says "polish this branch", "make this PR ready", or "keep reviewing until it passes".
effort: high
license: MIT
metadata:
  version: 0.1.0
  creator: Luong NGUYEN <luongnv89@gmail.com>
compatibility: Requires git and GitHub CLI (gh) with authentication. Uses feature-dev:code-reviewer subagent for independent review passes.
---

# /review-fix-loop

Automate the tedious review-fix-review-fix cycle. Each review uses a fresh agent with no memory of prior passes, so every cycle is an independent assessment. Fixes are applied without committing, and only after all issues are resolved does the skill create a single clean commit.

This matters because reviewers with memory of what they already flagged tend to rubber-stamp fixes. Fresh eyes catch things that incremental reviewers miss.

## Repo Sync Before Edits (mandatory)

Before starting, sync the current branch with remote:

```bash
branch="$(git rev-parse --abbrev-ref HEAD)"
git fetch origin
git pull --rebase origin "$branch"
```

If the working tree is dirty, stash first, sync, then pop:

```bash
git stash push -u -m "pre-sync"
branch="$(git rev-parse --abbrev-ref HEAD)"
git fetch origin && git pull --rebase origin "$branch"
git stash pop
```

If `origin` is missing or conflicts occur, stop and ask the user.

## Workflow

### Step 0 — Detect Context

Determine what to review:

1. Check if there's a PR for the current branch:
   ```bash
   gh pr view --json number,title,baseRefName,headRefName 2>/dev/null
   ```
2. If a PR exists, use the PR diff against its base branch.
3. If no PR, use the diff of the current branch against the default branch (`main` or `master`):
   ```bash
   default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
   git diff "$default_branch"...HEAD
   ```
4. If there are also uncommitted changes, include those in the review scope.

Print the detected context:

```
◆ Review-Fix Loop
  Branch: feature/42-add-auth
  PR: #47 (if applicable)
  Base: main
  Changed files: 5
  Uncommitted changes: yes/no
```

### Step 1 — Review (fresh agent)

Spawn a reviewer subagent. The reviewer must be a **separate agent** (via the Agent tool) so it has fresh context and no bias from prior passes.

**Agent parameters:**
- `description`: "Review cycle N"
- `subagent_type`: "feature-dev:code-reviewer"

**Prompt for the reviewer agent:**

Read `references/reviewer-prompt.md` for the full prompt template. Key points:
- The reviewer examines the diff between the current state and the base branch
- It checks: correctness, test coverage, code quality, security, edge cases
- It returns a structured JSON result with `"PASS"` or `"NEEDS_FIX"`
- Only report issues with **high confidence** — things that are clearly wrong, not style preferences
- Each issue must include: category, severity, description, file, line number

### Step 2 — Fix (if needed)

If the reviewer returned `NEEDS_FIX`:

1. Parse the issues list from the reviewer's response
2. For each issue, read the affected file, apply the fix, but **do not commit**
3. After all fixes, run the project's test suite if one exists (detect via `package.json`, `Makefile`, `pytest.ini`, etc.)
4. If tests fail, fix the test failures too

Track what was fixed in an internal log:

```
Cycle 1:
  ✗ 3 issues found
  ✓ Fixed: [security] SQL injection in user query (src/db.ts:42)
  ✓ Fixed: [code_quality] Unused import (src/auth.ts:3)
  ✓ Fixed: [edge_cases] Missing null check (src/api.ts:87)
```

### Step 3 — Loop

Go back to Step 1 with a **new** reviewer agent (fresh context).

**Loop controls:**
- **Max cycles**: 5 (safety cap to prevent infinite loops)
- **Exit on PASS**: Stop as soon as a reviewer returns `PASS`
- **Exit on stagnation**: If the same issues keep appearing across 2 consecutive cycles (the fixer isn't resolving them), stop and report the stuck issues to the user

### Step 4 — Summarize and Commit

Once a reviewer returns `PASS` (or max cycles reached):

1. Print the full summary:

```
◆ Review-Fix Loop Complete
  Cycles: 3
  Total issues found: 7
  Total issues fixed: 7
  Status: ✓ Clean

  Cycle 1: 3 issues (security: 1, code_quality: 1, edge_cases: 1)
  Cycle 2: 3 issues (test_coverage: 2, code_quality: 1)
  Cycle 3: 1 issue (edge_cases: 1)
  Cycle 4: ✓ PASS

  Files modified:
    src/db.ts
    src/auth.ts
    src/api.ts
    tests/api.test.ts
```

2. Stage all modified files and create **one clean commit**:
   - Commit message format: `refactor(<scope>): address review feedback`
   - Include a body listing what was fixed, grouped by category
   - If this is a PR branch, push the commit

3. If max cycles reached with remaining issues, print the unresolved issues clearly:

```
⚠ Max cycles (5) reached — 2 issues remain unresolved:
  ● [code_quality] Complex conditional in src/parser.ts:142
  ● [edge_cases] Missing timeout handling in src/api.ts:203

  These may need manual attention.
```

## When NOT to Commit

If the user said "just review" or "review only" or "don't fix", run only one review cycle and report findings without fixing or committing anything.

## Configuration

The skill respects `.gitissue.yml` if present, but works with zero config. Defaults:

| Setting | Default | Description |
|---------|---------|-------------|
| `review_fix_loop.max_cycles` | 5 | Maximum review-fix iterations |
| `review_fix_loop.auto_push` | true | Push after committing (on PR branches) |
| `review_fix_loop.review_categories` | all | Categories to check (correctness, test_coverage, code_quality, security, edge_cases) |
| `review_fix_loop.confidence_threshold` | high | Only report high-confidence issues (avoids nitpicking) |
