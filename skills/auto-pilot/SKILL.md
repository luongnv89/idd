---
name: auto-pilot
description: "Run a fully autonomous triage-resolve-review-merge loop over the GitHub issue backlog with zero user prompts. Use when asked to auto-pilot, autopilot, resolve everything, work through the backlog, run the loop, or keep going until done. Don't use for single-issue work (use /issue-resolver), one-shot triage (use /issue-triage), or interactive PR review (use /issue-pr-review)."
license: MIT
compatibility: Requires git and GitHub CLI (gh) with authentication and push access. Requires merge permission for auto-merge. Uses /issue-triage, /issue-resolver, /issue-analysis, and /issue-pr-review skills internally. All agents are in shared/agents/.
effort: max
metadata:
  version: 2.1.2
  creator: Luong NGUYEN <luongnv89@gmail.com>
---

# /auto-pilot

Fully autonomous development loop: triage, pick, resolve, review, fix, merge, repeat — zero user prompts.

## Invocation

| Invocation | What happens |
|------------|--------------|
| `/auto-pilot` | Start the loop — triage, pick first, resolve, review, merge, repeat |
| `/auto-pilot --issues 5,10,12` | Process issues #5, #10, #12 in that exact order (skip triage) |
| `/auto-pilot --limit N` | Process at most N issues, then stop |
| `/auto-pilot --dry-run` | Run triage/show execution plan without resolving anything |
| `/auto-pilot --skip N` | Skip issue #N (add to skip list for this session) |

## Prerequisites

Before starting the loop, verify the environment. On failure, output the exact error from `references/error-messages.md` and stop.

1. Confirm git repository: `git rev-parse --git-dir`
2. Confirm `gh` is installed: `which gh`
3. Confirm authentication: `gh auth status`
4. Confirm GitHub remote exists: `git remote -v`
5. Confirm clean working tree: `git status --porcelain`
6. Confirm on default branch: `git rev-parse --abbrev-ref HEAD`

## Configuration

Load `.gitissue.yml` once at start. Defaults:
- `autopilot.max_iterations: 10`
- `autopilot.review_cycles: 3`
- `autopilot.auto_merge: true`
- `autopilot.pause_on_failure: false`
- `autopilot.skip_labels: ["wontfix", "blocked", "do-not-merge"]`
- `autopilot.critical_labels: ["critical", "priority:critical"]`

## Workflow

- Triage the backlog or the explicit issue list.
- Resolve each issue with `/issue-resolver`.
- Review the resulting PR with `/issue-pr-review --auto`.
- Merge or create a follow-up issue, then continue.
- See `references/auto-pilot-details.md` for the release notes, autonomy rules, and context-window notes.

## When to Use

- Use this skill when the user wants unattended backlog processing from triage through merge.
- Use the `--dry-run` path when they want an execution plan without making changes.

## Instructions

1. Pick or validate the issue list.
2. Run the resolver, then the PR review loop.
3. Merge when clean, or create a follow-up issue when a blocker remains.
4. Stop only for genuinely critical or irreversible situations.

## Acceptance Criteria

- [ ] Issues are processed in the requested order or by triage priority.
- [ ] Routine decisions happen without user prompts.
- [ ] Critical unresolved cases stop for a decision instead of guessing.

## Edge Cases

- Dirty working tree or branch mismatch at startup.
- Critical issue with unresolved review problems after the loop.

## Example

```text
/auto-pilot --dry-run
```

Expected output: a backlog run log or a clear stop reason when human input is required.
