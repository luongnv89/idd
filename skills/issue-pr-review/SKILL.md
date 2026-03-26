---
name: issue-pr-review
description: Review a pull request end-to-end with automated fix cycles and CI monitoring. Analyzes code changes, runs all tests (unit, integration, e2e), checks CI status, fixes detected issues, and repeats up to 5 times until clean — then provides a summary report and auto-merges in auto-pilot mode. Replaces review-fix-loop with CI awareness. Use when asked to "review PR", "review and fix PR", "check this PR", "is this PR ready", "review-fix-loop", "review fix loop", "auto-review my PR", "fix review issues", "clean up this PR", "review until clean", "polish this branch", "make this PR ready", or "keep reviewing until it passes". Also trigger when auto-pilot needs to review a PR after issue resolution.
effort: high
license: MIT
metadata:
  version: 0.1.0
  creator: Luong NGUYEN <luongnv89@gmail.com>
compatibility: Requires git and GitHub CLI (gh) with authentication. Self-contained — uses shared agents from shared/agents/.
---

# /issue-pr-review [PR_NUMBER]

Review a pull request end-to-end — analyze, test, fix, check CI, repeat until clean.

## Invocation

| Invocation | Mode | What happens |
|------------|------|--------------|
| `/issue-pr-review <N>` | interactive | Review PR #N, report findings |
| `/issue-pr-review <N> --auto` | auto-pilot | Review, fix, and auto-merge when clean |
| `/issue-pr-review` | detect | Auto-detect PR for current branch |
| `/issue-pr-review --review-only` | read-only | Review and report, never fix or merge |

The `--auto` flag is set automatically when invoked by `/auto-pilot`.

## Prerequisites

1. Confirm git repository: `git rev-parse --git-dir`
2. Confirm `gh` is installed and authenticated: `gh auth status`

## Repo Sync Before Edits (mandatory)

Before making any fixes:

```bash
branch="$(git rev-parse --abbrev-ref HEAD)"
git fetch origin
git pull --rebase origin "$branch"
```

If dirty: stash, sync, pop. If `origin` missing or conflicts: stop and ask (interactive) or abort (auto).

## Configuration

Load `.gitissue.yml` once. Defaults:
- `review.max_cycles: 5`
- `review.auto_merge: false` (overridden to `true` in auto mode)
- `review.confidence_threshold: 80`
- `review.run_tests: true`
- `review.check_ci: true`
- `review.ci_poll_interval: 30` (seconds)
- `review.ci_timeout: 600` (seconds, 10 minutes)
- `review.test_timeout: 300` (seconds)

---

## Pipeline Overview

```
  ◆ PR Review Pipeline
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  [1/6] PR Info      ✓ PR #87: fix(auth): resolve redirect (#42)
  [2/6] Review       ● analyzing changes...
  [3/6] Test         ✓ 17 tests passed, build ok
  [4/6] CI Status    ✓ all checks passed
  [5/6] Fix          ○ no issues to fix
  [6/6] Report       ✓ PR is clean — ready to merge
```

Steps 2-5 repeat up to `review.max_cycles` times. Step 6 runs once at the end.

---

## Step 1 — Get PR Info

### Auto-detect PR

If no PR number provided, detect from current branch:

```bash
gh pr view --json number,title,body,baseRefName,headRefName,state,url,statusCheckRollup
```

If no PR exists for the current branch:
```
✗ No PR found for branch {branch_name}

  To fix:  gh pr create
  Or:      /issue-pr-review <PR_NUMBER>
```

### Fetch PR details

```bash
gh pr view {N} --json number,title,body,baseRefName,headRefName,state,url,labels,reviews,statusCheckRollup,files
```

Extract:
- PR number, title, URL
- Base and head branches
- Linked issue numbers (from `Closes #N` in body)
- Current CI status
- Files changed

**If PR is closed/merged:**
```
⚠ PR #{N} is already {state}
```
Stop.

```
[1/6] PR Info      ✓ PR #{N}: {title}
                     {files_count} files changed, base: {base_branch}
```

---

## Step 2 — Analyze & Review

Spawn a **fresh** code-reviewer agent each cycle. Fresh context ensures no bias from prior review passes.

Read `shared/agents/code-reviewer.md` for the full prompt template.

Pass to the reviewer:
- `branch_name`: PR head branch
- `base_branch`: PR base branch
- `pr_context`: PR title and body
- `diff_command`: `gh pr diff {N}`

The reviewer returns structured JSON:
```json
{
  "result": "PASS" or "NEEDS_FIX",
  "issues_found": N,
  "issues": [ ... ],
  "summary": "..."
}
```

Also fetch linked issues for acceptance criteria verification:
```bash
gh issue view {linked_issue} --json number,title,body,labels
```

Check each acceptance criterion against the PR changes.

```
[2/6] Review       ✓ {result} — {issues_found} issues found
```

---

## Step 3 — Run Tests & Build

### Build check

Detect and run the project's build system:

| Build system | Detection | Command |
|-------------|-----------|---------|
| Node.js (TS) | `tsconfig.json` | `npx tsc --noEmit` |
| Node.js (JS) | `package.json` build script | `npm run build` |
| Python | `pyproject.toml` | `python -m compileall` |
| Go | `go.mod` | `go build ./...` |
| Rust | `Cargo.toml` | `cargo build` |

### Run test suite

Detect and run all test types:

1. **Unit tests** — `pytest`, `npm test`, `go test ./...`, etc.
2. **Integration tests** — if integration test directory/config exists
3. **E2e tests** — if e2e framework exists (playwright, cypress, etc.)

Timeout: `review.test_timeout` seconds (default: 300).

```
[3/6] Test         ✓ build ok, {N} tests passed
```

Or if failures:
```
[3/6] Test         ✗ {N} tests failed
                     {brief failure summary}
```

---

## Step 4 — Check CI Status

Poll GitHub Actions / CI status for the PR:

```bash
gh pr checks {N} --json name,state,conclusion
```

### Polling behavior

1. Check immediately after tests
2. If checks are still running, poll every `review.ci_poll_interval` seconds
3. Timeout after `review.ci_timeout` seconds

### CI results

**All checks passed:**
```
[4/6] CI Status    ✓ all checks passed
```

**Checks failed:**
```
[4/6] CI Status    ✗ {N} checks failed
                     {check_name}: {conclusion}
```

Extract failure details from the CI log:
```bash
gh run view {run_id} --log-failed
```

**Checks still running after timeout:**
```
[4/6] CI Status    ⚠ checks still running after {timeout}s
```
In interactive mode: ask to wait more or proceed.
In auto mode: proceed — the next cycle will re-check.

**No CI configured:**
```
[4/6] CI Status    ○ no CI checks configured
```

---

## Step 5 — Fix Issues

Collect all issues from Steps 2-4:
- Code review issues (from the reviewer agent)
- Test failures (from Step 3)
- CI failures (from Step 4)

### If no issues

```
[5/6] Fix          ○ no issues to fix
```
Exit the loop — PR is clean.

### If issues found

For each issue:
1. Read the affected file
2. Apply the fix
3. Stage: `git add <specific-file>`

After all fixes:
4. Commit: `fix({scope}): address review feedback (#{linked_issue})`
5. Push: `git push origin {branch_name}`

```
[5/6] Fix          ✓ fixed {N} issues
```

Track what was fixed:
```
Cycle {N}:
  ✗ {issues_found} issues found
  ✓ Fixed: [category] description (file:line)
  ✓ Fixed: [category] description (file:line)
```

---

## Review Loop

After Step 5, go back to Step 2 with a fresh reviewer agent.

**Loop controls:**
- **Max cycles:** `review.max_cycles` (default: 5)
- **Exit on clean:** Stop when reviewer returns `PASS` AND tests pass AND CI passes
- **Exit on stagnation:** If the same issues appear in 2 consecutive cycles, stop and report
- **Review-only mode:** Run one cycle of Steps 2-4 only, never fix or loop

---

## Step 6 — Summary Report

### Clean PR

```
◆ PR Review Complete
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  PR:          #{pr_number}: {title}
  URL:         {pr_url}
  Status:      ✓ Clean
  Cycles:      {N}
  Issues fixed: {total_fixed}

  Review:      PASS
  Tests:       {count} passed
  CI:          all checks passed

  Cycle history:
    Cycle 1: {N} issues (categories)
    Cycle 2: {N} issues (categories)
    Cycle 3: ✓ PASS
```

### PR with remaining issues

```
◆ PR Review Complete
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  PR:          #{pr_number}: {title}
  URL:         {pr_url}
  Status:      ⚠ {N} issues remain after {max} cycles
  Cycles:      {max}
  Issues fixed: {total_fixed}

  Remaining issues:
    ● [category] description (file:line)
    ● [category] description (file:line)

  These may need manual attention.
```

### Auto-merge (auto mode only)

If the PR is clean AND `--auto` flag is set:

```bash
gh pr merge {N} --squash --delete-branch
```

```
✓ PR #{N} merged via squash
  Branch {branch_name} deleted
```

If merge fails (conflicts, branch protection):
```
⚠ Auto-merge failed: {reason}

  Manual merge required.
```

In interactive mode: never auto-merge. Just report status.

---

## Review-Only Mode

When invoked with `--review-only`:

1. Run Steps 1-4 once (PR info, review, test, CI check)
2. Skip Step 5 (no fixes)
3. Report findings in Step 6
4. Never loop, never fix, never merge

---

## GitHub CLI Convention

Every `gh` command uses `--json` with explicit field selection. Never parse text output.

## Terminal Output

Follow DESIGN.md symbol vocabulary:
- Step counter: `[N/6]`
- Symbols: `●` progress, `✓` success, `✗` failure, `◆` header, `⚠` warning, `○` info
- Two-space indent, `┄` separators, URLs on own line, max 80 chars

## Error Handling

All errors use rich format from `references/error-messages.md`:
```
✗ Short error description

  To fix:  <actionable command>
```

## Additional Resources

- **`shared/agents/code-reviewer.md`** — Review subagent prompt
- **`references/error-messages.md`** — Error catalog
- **`docs/naming-conventions.md`** — Naming conventions
- **`DESIGN.md`** — Terminal output style guide
