---
name: issue-triage
description: "Analyze and triage open GitHub issues for dependencies, priorities, parallelizable work, staleness, and already-fixed detection, caching results to .gitissue/triage.json. Use when asked to triage issues, prioritize issues, what should I work on next, or /issue-triage. Don't use for analyzing one specific issue (use /issue-analysis), resolving an issue (use /issue-resolver), or creating new issues (use /issue-creator)."
license: MIT
compatibility: Requires git and GitHub CLI (gh) with authentication. Default mode (cached view) needs only local file access — no gh required.
effort: medium
metadata:
  version: 0.5.2
  creator: Luong NGUYEN <luongnv89@gmail.com>
---

# /issue-triage

Analyze open GitHub issues to surface dependencies, suggest priorities, identify parallelizable work, flag stale issues, and detect issues that may have already been fixed.

## Invocation

| Invocation | What happens |
|------------|--------------|
| `/issue-triage` | Show cached triage from `.gitissue/triage.json` or run a first analysis if no cache exists |
| `/issue-triage update` | Force a full re-analysis and overwrite `.gitissue/triage.json` |
| `/issue-triage --limit N` | Force a full re-analysis with up to N issues |

## Prerequisites

Before any operation, verify the environment. On failure, output the exact error from `references/error-messages.md` and stop.

1. Confirm git repository: `git rev-parse --git-dir`
2. Confirm `gh` is installed: `which gh`
3. Confirm authentication: `gh auth status`
4. Confirm GitHub remote exists: `git remote -v`

## Configuration

Load `.gitissue.yml` once at skill start. Defaults:
- `triage.stale_threshold_days: 14`
- `triage.auto_priority: true`
- `triage.include_closed: false`
- `triage.scan_timeout_per_issue: 30`

## Workflow

- Default mode shows cached triage instantly and suggests an update only when the repo changed.
- Update mode reruns the full issue scan and refreshes `.gitissue/triage.json`.
- The detailed cache heuristics, smart refresh behavior, and update-mode architecture live in `references/triage-runbook.md`.

## When to Use

- Use this skill when the user wants to know what to work on next across the backlog.
- Use cached mode for a fast read and update mode when the repo changed or priorities shifted.

## Instructions

1. Render cached triage or run the first analysis.
2. Rank issues by priority, stale state, and dependency position.
3. Highlight parallelizable work and anything that may already be fixed.
4. Suggest an update only when the cache looks stale.

## Acceptance Criteria

- [ ] Cached triage renders instantly when available.
- [ ] Update mode refreshes the JSON cache.
- [ ] The report surfaces priority, blockers, and parallelizable work.

## Edge Cases

- No cache exists yet.
- Cached JSON is malformed.
- The report is old but the repo has not changed.

## Example

```text
/issue-triage update
```

Expected output: a triage report and cache file showing ranked issues and blockers.
