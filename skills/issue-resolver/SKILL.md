---
name: issue-resolver
description: "Create an atomic PR that closes a GitHub issue end-to-end via a 6-step pipeline. Use when asked to resolve issue #N, fix #N, implement #N, work on #N, take issue #N, or /issue-resolver. Don't use for analyzing an issue without implementing (use /issue-analysis), reviewing an existing PR (use /issue-pr-review), or bulk backlog processing (use /auto-pilot)."
license: MIT
compatibility: Requires git and GitHub CLI (gh) with authentication and push access. Self-contained — uses shared agents from shared/agents/.
effort: max
metadata:
  version: 0.7.0
  creator: Luong NGUYEN <luongnv89@gmail.com>
---

# /issue-resolver N

Resolve a GitHub issue end-to-end — from issue to atomic PR in 6 steps.

## Invocation

| Invocation | Mode | What happens |
|------------|------|--------------|
| `/issue-resolver <N>` | interactive | Resolve issue #N, ask user to pick plan |
| `/issue-resolver <N> --auto` | auto-pilot | Resolve fully autonomously, no user prompts |

## Prerequisites

Before any operation, verify the environment. On failure, output the exact error from `references/error-messages.md` and stop.

1. Confirm git repository: `git rev-parse --git-dir`
2. Confirm `gh` is installed: `which gh`
3. Confirm authentication: `gh auth status`
4. Confirm GitHub remote exists: `git remote -v`

## Configuration

Load `.gitissue.yml` once at skill start. Defaults:
- `issue.auto_normalize: true`
- `resolve.approval_gate: auto`
- `resolve.branch_prefix: "auto"`
- `resolve.auto_test: true`
- `resolve.test_timeout: 300`
- `resolve.pr_auto_link: true`
- `resolve.max_commits: 10`
- `resolve.qa_max_cycles: 5`

## Workflow

- Preflight checks the issue, labels, and branch state.
- Research and planning happen in subagents.
- Implementation, QA, and delivery stay in the main loop with subagent help where needed.
- See `references/resolver-runbook.md` for the full step ordering and agent roles.

## When to Use

- Use this skill when the user wants one issue closed end-to-end as an atomic PR.
- Use it when implementation, tests, and delivery all belong to the same issue.

## Instructions

1. Preflight the issue and branch.
2. Research the codebase and choose a plan.
3. Implement the fix and write tests.
4. Run QA and deliver the PR once the issue is closed.

## Acceptance Criteria

- [ ] The issue is closed by a single atomic PR.
- [ ] Tests are written and executed for the change.
- [ ] The branch is synced and the result is reported clearly.

## Edge Cases

- A PR already exists targeting the issue.
- Blocking labels or assignments in interactive mode.
- Failing tests or merge restrictions.

## Example

```text
/issue-resolver 42 --auto
```

Expected output: an atomic PR plus the supporting issue analysis and implementation notes.
