---
name: issue-pr-review-fix-loop
description: "Run a review-fix loop over a PR until clean, then confirm the result. Use when asked to keep fixing a PR or run a review loop; don't use for a single review, creating a PR, or backlog-wide automation."
license: MIT
compatibility: Requires git and GitHub CLI (gh) with authentication. Depends on /issue-pr-review skill (skills/issue-pr-review/SKILL.md). Uses shared agents from shared/agents/.
effort: high
metadata:
  version: 0.3.1
  creator: Luong NGUYEN <luongnv89@gmail.com>
---

# /issue-pr-review-fix-loop [PR_NUMBER]

Outer loop that reviews a PR, fixes issues, commits, and repeats — with a fresh confirmation pass at the end.

## Invocation

| Invocation | Mode | What happens |
|------------|------|--------------|
| `/issue-pr-review-fix-loop <N>` | interactive | Review-fix loop for PR #N |
| `/issue-pr-review-fix-loop <N> --auto` | auto-pilot | Review-fix loop + auto-merge when clean |
| `/issue-pr-review-fix-loop` | detect | Auto-detect PR for current branch |

## Prerequisites

Before any operation, verify the environment. On failure, output the exact error from `references/error-messages.md` and stop.

1. Confirm git repository: `git rev-parse --git-dir`
2. Confirm `gh` is installed and authenticated: `gh auth status`
3. Confirm the branch points at a PR or can detect one cleanly

## Workflow

- Delegate the review to `/issue-pr-review --review-only`.
- Apply fixes, commit, and push after each cycle.
- Reuse the same reviewer/fixer loop until the PR is clean.
- Finish with a fresh confirmation pass.
- See `references/fix-loop-runbook.md` for the outer-loop rules and example cycle structure.

## When to Use

- Use this skill when the user wants the agent to keep fixing a PR until it is clean.
- Use it when a review-only pass is not enough and the loop should continue automatically.

## Instructions

1. Run the review-only pass.
2. Fix the reported issues.
3. Commit and push each iteration.
4. Repeat until the PR is clean, then confirm the result.

## Acceptance Criteria

- [ ] The PR reaches a clean state or stops for a real blocker.
- [ ] Fix cycles are tracked and repeated intentionally.
- [ ] A final confirmation pass runs after the last fix.

## Edge Cases

- Auto mode with a clean PR should still confirm before merge.
- A blocker remains after the loop.
- The review-only pass finds nothing to fix.

## Example

```text
/issue-pr-review-fix-loop 87 --auto
```

Expected output: the PR is updated, committed, and pushed, or a clear blocker is reported.
