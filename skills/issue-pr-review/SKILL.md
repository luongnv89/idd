---
name: issue-pr-review
description: Review a pull request end-to-end with up to 3 token-optimized fix cycles, CI monitoring, and auto-merge in auto-pilot mode. Use when asked to "review PR", "review and fix PR", "is this PR ready", "clean up this PR", or "polish this branch".
license: MIT
compatibility: Requires git and GitHub CLI (gh) with authentication. Self-contained — uses shared agents from shared/agents/.
effort: high
metadata:
  version: 0.3.0
  creator: Luong NGUYEN <luongnv89@gmail.com>
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
- `review.max_cycles: 3` — reduced from 5; script pre-pass handles mechanical issues, so 3 LLM cycles suffice for logic/architecture
- `review.auto_merge: false` (overridden to `true` in auto mode)
- `review.confidence_threshold: 80`
- `review.run_tests: true`
- `review.check_ci: true`
- `review.ci_poll_interval: 30` (seconds)
- `review.ci_timeout: 600` (seconds, 10 minutes)
- `review.test_timeout: 300` (seconds)
- `review.soft_pass: true` — pass when zero "fix" issues remain, even if "note" issues exist (≤ 2 medium allowed)

---

## Pipeline Overview

```
  ◆ PR Review Pipeline
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  [1/7] PR Info      ✓ PR #87: fix(auth): resolve redirect (#42)
  [2/7] Pre-pass     ✓ lint clean, format clean, 17 tests passed
  [3/7] Review       ● analyzing changes...
  [4/7] Test         ✓ 17 tests passed, build ok
  [5/7] CI Status    ✓ all checks passed
  [6/7] Fix          ○ no fixable issues
  [7/7] Report       ✓ PR is clean — ready to merge
```

Step 2 (Pre-pass) runs once before the review loop. Steps 3-6 repeat up to `review.max_cycles` times (default: 3). Step 7 runs once at the end.

### Token optimization strategy

The pipeline is designed to minimize LLM token usage:

1. **Script pre-pass (Step 2)** — Lint, format, and test tools run via shell scripts, not LLM agents. Auto-fixes mechanical issues for free (zero tokens). This handles the bulk of lint/format violations that previously consumed full review cycles.
2. **Agent reuse (Steps 3-6)** — The same reviewer and fixer agents are reused across fix cycles via `SendMessage`. Only the final confirmation pass spawns a fresh agent. This cuts agent spawn cost from 2 per cycle to ~1.3 average (reuse in cycles 2-3, fresh only for confirmation).
3. **Severity-based filtering** — The code reviewer classifies each issue with `action: "fix"` or `action: "note"`. Only "fix" issues trigger a fix cycle. "Note" issues are reported but don't consume tokens.
4. **Soft pass condition** — The review passes when zero "fix" issues remain, even if some medium "note" issues exist. This avoids burning cycles on diminishing-return fixes.
5. **Reduced cycles (3 max)** — With mechanical issues handled by scripts and only critical issues triggering fixes, 3 LLM cycles are sufficient.

---

## Step 1 — Get PR Info [1/7]

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
[1/7] PR Info      ✓ PR #{N}: {title}
                     {files_count} files changed, base: {base_branch}
```

---

## Step 2 — Script Pre-pass [2/7]

Before spawning any LLM reviewer, run deterministic tools to catch and auto-fix mechanical issues. This step uses zero LLM tokens — all work is done by scripts and CLI tools.

### Detect project tooling

Detect available lint/format/test tools from the project:

| Tool type | Detection | Auto-fix command |
|-----------|-----------|-----------------|
| ESLint | `.eslintrc*` or `eslint` in package.json | `npx eslint --fix .` |
| Prettier | `.prettierrc*` or `prettier` in package.json | `npx prettier --write .` |
| Black | `pyproject.toml` with `[tool.black]` | `python -m black .` |
| Ruff | `pyproject.toml` with `[tool.ruff]` or `ruff.toml` | `ruff check --fix . && ruff format .` |
| isort | `pyproject.toml` with `[tool.isort]` | `python -m isort .` |
| gofmt | `go.mod` | `gofmt -w .` |
| rustfmt | `Cargo.toml` | `cargo fmt` |
| clang-format | `.clang-format` | `find . -name '*.c' -o -name '*.h' \| xargs clang-format -i` |

### Run auto-fix

For each detected tool, run the auto-fix command. Capture output but don't block on warnings — only block on errors that prevent the fix from running.

```bash
# Example for a Node.js project:
npx eslint --fix . 2>&1
npx prettier --write . 2>&1
```

### Run tests

Run the project's test suite to catch test failures early (before the LLM review):

```bash
# Detected test runner
npm test          # or pytest, go test ./..., cargo test, etc.
```

### Commit auto-fixes

If any files were modified by the auto-fix tools:

```bash
git add -A
git commit -m "style: auto-fix lint and format issues"
git push origin {branch_name}
```

```
[2/7] Pre-pass     ✓ lint clean, format clean, {N} tests passed
                     Auto-fixed: {files_fixed} files (lint/format)
```

If no tools detected:
```
[2/7] Pre-pass     ○ no lint/format tools detected, tests: {N} passed
```

If tests fail at this stage, continue to the review loop — test failures will be picked up in Step 4 and addressed in the fix cycle.

---

## Step 3 — Analyze & Review [3/7]

### Agent reuse strategy

To minimize token usage, the review loop **reuses the same reviewer agent** across fix cycles instead of spawning a fresh one each time. The reviewer already has the codebase context loaded, so subsequent reviews are cheaper.

- **Cycle 1:** Spawn a new reviewer agent (cold start — reads diff, files, context)
- **Cycles 2-3:** Send the reviewer a follow-up message via `SendMessage` asking it to re-review the diff after fixes were applied. The agent retains its context and only needs to re-read the updated diff, not re-discover the entire codebase.
- **Confirmation pass:** After the fixer reports all issues resolved, spawn a **fresh confirmation reviewer** (separate agent, no memory of prior cycles) for an unbiased final check. This is the only fresh spawn after cycle 1.

This trades perfect independence between cycles (which rarely matters in practice — the reviewer was already correct about what the issues were) for significant token savings. The fresh confirmation pass at the end catches anything the reused reviewer might have missed.

### Cycle 1 — Initial review

Read `shared/agents/code-reviewer.md` for the full prompt template.

Pass to the reviewer:
- `branch_name`: PR head branch
- `base_branch`: PR base branch
- `pr_context`: PR title and body
- `diff_command`: `gh pr diff {N}`

### Cycles 2+ — Re-review via SendMessage

Send a message to the existing reviewer agent:
```
The fixer applied changes. Re-review the PR diff to check if the issues were resolved and find any new issues.

Run: {diff_command}

Return the same JSON format as before.
```

### Confirmation pass

After the fix cycle reports zero fixable issues, spawn a **fresh** confirmation reviewer (new agent, no memory). If it finds new fixable issues, they go back to the existing fixer. If it confirms clean, the PR passes.

```
[3/7] Review       ✓ {result} — {fixable_count} fixable, {note_count} noted
```

Also fetch linked issues for acceptance criteria verification:
```bash
gh issue view {linked_issue} --json number,title,body,labels
```

Check each acceptance criterion against the PR changes.

---

## Step 4 — Run Tests & Build [4/7]

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
[4/7] Test         ✓ build ok, {N} tests passed
```

Or if failures:
```
[4/7] Test         ✗ {N} tests failed
                     {brief failure summary}
```

---

## Step 5 — Check CI Status [5/7]

Poll GitHub Actions / CI status for the PR:

```bash
gh pr checks {N} --json name,state,bucket
```

### Polling behavior

1. Check immediately after tests
2. If checks are still running, poll every `review.ci_poll_interval` seconds
3. Timeout after `review.ci_timeout` seconds

### CI results

**All checks passed:**
```
[5/7] CI Status    ✓ all checks passed
```

**Checks failed:**
```
[5/7] CI Status    ✗ {N} checks failed
                     {check_name}: {bucket}
```

Extract failure details from the CI log:
```bash
gh run view {run_id} --log-failed
```

**Checks still running after timeout:**
```
[5/7] CI Status    ⚠ checks still running after {timeout}s
```
In interactive mode: ask to wait more or proceed.
In auto mode: proceed — the next cycle will re-check.

**No CI configured:**
```
[5/7] CI Status    ○ no CI checks configured
```

---

## Step 6 — Fix Issues [6/7]

Collect issues from Steps 3-5, but **only fix issues with `action: "fix"`**. Issues with `action: "note"` are reported in the summary but do not trigger a fix cycle. This is the key token optimization — note-only issues (medium code_quality, test_coverage suggestions) are skipped.

- Code review issues with `action: "fix"` (from the reviewer agent)
- Test failures (from Step 4)
- CI failures (from Step 5)

### If no fixable issues

```
[6/7] Fix          ○ no fixable issues (noted: {note_count})
```
Exit the loop — PR passes the soft-pass condition.

### If fixable issues found

For each issue where `action: "fix"`:
1. Read the affected file
2. Apply the fix
3. Stage: `git add <specific-file>`

After all fixes:
4. Commit: `fix({scope}): address review feedback` (append `(#{linked_issue})` only if a linked issue exists)
5. Push: `git push origin {branch_name}`

```
[6/7] Fix          ✓ fixed {N} issues (noted: {note_count} — not fixed)
```

Track what was fixed and what was noted:
```
Cycle {N}:
  ✗ {fixable_count} fixable issues found
  ✓ Fixed: [category] description (file:line)
  ✓ Fixed: [category] description (file:line)
  ○ Noted: [category] description (file:line) — medium, not blocking
```

---

## Review Loop

After Step 6, go back to Step 3 — but reuse the same reviewer agent via `SendMessage` (not a fresh spawn). Only spawn fresh for the confirmation pass.

**Loop controls:**
- **Max cycles:** `review.max_cycles` (default: 3)
- **Agent reuse:** Cycles 2+ reuse the existing reviewer and fixer agents. Fresh spawn only for the confirmation pass after fixer reports zero issues.
- **Soft pass (default):** Stop when zero `action: "fix"` issues remain AND tests pass AND CI passes. Medium "note" issues (≤ 2) are allowed — they don't block the pass.
- **Confirmation pass:** When the fixer reports all fixed, spawn one fresh reviewer for unbiased verification. If clean → PASS. If new issues → back to existing fixer (counts as a cycle).
- **Exit on stagnation:** If the same issues appear in 2 consecutive cycles, stop and report
- **Review-only mode:** Run one cycle of Steps 3-5 only, never fix or loop

---

## Step 7 — Summary Report [7/7]

Print a structured step-by-step summary showing the review pipeline results.

### Clean PR

```
◆ PR Review: #{pr_number} (pass {N} — clean)
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Script pre-pass:   ✓ lint/format auto-fixed ({auto_fixed} files)
  Code review:       ✓ pass
  Tests:             ✓ pass ({count} passed)
  CI status:         ✓ pass ({checks_count} checks passed)
  Issues fixed:      ✓ {total_fixed} total across {cycles} cycles
  Issues noted:      ○ {note_count} (medium, not blocking)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            PASS

  {pr_url}
```

### PR with remaining issues

```
◆ PR Review: #{pr_number} (pass {max} — issues remain)
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Code review:       ⚠ warn ({N} issues remain)
  Tests:             ✓ pass
  CI status:         ✓ pass
  Issues fixed:      ✓ {total_fixed} total across {max} cycles
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            WARN (manual review recommended)

  Remaining:
    ● [category] description (file:line)

  {pr_url}
```

### Auto-merge (auto mode only)

If the PR is clean AND `--auto` flag is set:

```bash
gh pr merge {N} --squash --delete-branch
```

Append to the report:
```
  Merge:             ✓ pass (squash merged)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            MERGED

  ✓ PR #{N} merged — branch {branch_name} deleted
```

If merge fails:
```
  Merge:             ✗ fail ({reason})
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            BLOCKED (manual merge required)
```

In interactive mode: never auto-merge. Just report status.

---

## Review-Only Mode

When invoked with `--review-only`:

1. Run Steps 1-5 once (PR info, pre-pass, review, test, CI check)
2. Skip Step 6 (no fixes)
3. Report findings in Step 7
4. Never loop, never fix, never merge

---

## GitHub CLI Convention

Every `gh` command uses `--json` with explicit field selection. Never parse text output.

## Terminal Output

Follow DESIGN.md symbol vocabulary:
- Step counter: `[N/7]`
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
