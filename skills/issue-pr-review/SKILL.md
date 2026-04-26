---
name: issue-pr-review
description: "Review a pull request end-to-end with fix cycles, CI monitoring, and auto-merge. Use when asked to review, fix, or polish a PR; don't use for creating PRs, raw issues, or code not yet in a PR."
license: MIT
compatibility: Requires git and GitHub CLI (gh) with authentication. Self-contained — uses shared agents from shared/agents/.
effort: high
metadata:
  version: 0.3.2
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

## Prerequisites

Before any operation, verify the environment. On failure, output the exact error from `references/error-messages.md` and stop.

1. Confirm git repository: `git rev-parse --git-dir`
2. Confirm `gh` is installed and authenticated: `gh auth status`
3. Confirm the branch points at a PR or can detect one cleanly

## Workflow

- Review the PR with fresh eyes and score the current state.
- Run any required tests or CI checks before fixing.
- Apply up to three fix cycles, then run a confirmation pass.
- Auto-merge only when the review is clean and the mode allows it.
- See `references/review-runbook.md` for the exact cycle rules and review-fix flow.

## When to Use

- Use this skill when the user wants a full PR review, fix pass, or merge readiness check.
- Use `--review-only` when they want findings without edits.

## Instructions

1. Review the diff with a fresh pass.
2. Run tests or CI checks before modifying code.
3. Fix the highest-signal issues first.
4. Re-review until the PR is clean or the cycle limit is reached.

## Acceptance Criteria

- [ ] Findings are reported clearly.
- [ ] Required tests or checks are run.
- [ ] The PR is only merged when the review is clean.

## Edge Cases

- Review-only mode must not modify the branch.
- No PR detected for the current branch.
- Protected branch or merge restriction.

## Example

```text
/issue-pr-review 87 --review-only
```

Expected output: a review report with findings, fix cycles, and a final recommendation.
