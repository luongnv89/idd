---
name: issue-analysis
description: "Analyze a single GitHub issue for root cause, affected files, implementation options, complexity, and risk; persists to .gitissue/analysis-N.json. Use when asked to analyze issue #N, investigate issue, impact analysis, how hard is #N, or /issue-analysis. Don't use for creating/filing issues (use /issue-creator), bulk triaging (use /issue-triage), or actually resolving the issue (use /issue-resolver)."
license: MIT
compatibility: Requires git and GitHub CLI (gh) with authentication. View mode (`/issue-analysis N view`) needs only local file access — no gh required.
effort: high
metadata:
  version: 0.4.1
  creator: Luong NGUYEN <luongnv89@gmail.com>
---

# /issue-analysis N

Deep analysis of a single GitHub issue. Produces a report and persists it to `.gitissue/analysis-<N>.json`.

## Invocation

| Invocation | What happens |
|------------|--------------|
| `/issue-analysis <N>` | Full analysis of issue #N, persist to `.gitissue/analysis-<N>.json` |
| `/issue-analysis <N> view` | Render cached analysis from `.gitissue/analysis-<N>.json` without re-scanning |

## Prerequisites

Before any operation, verify the environment. On failure, output the exact error from `references/error-messages.md` and stop.

1. Confirm git repository: `git rev-parse --git-dir`
2. Confirm `gh` is installed: `which gh`
3. Confirm authentication: `gh auth status`
4. Confirm GitHub remote exists: `git remote -v`

## Configuration

Load `.gitissue.yml` once at skill start. Defaults:
- `analysis.max_files: 30`
- `analysis.trace_depth: 3`
- `analysis.scan_timeout: 120`

## Workflow

- View mode renders the cached JSON without re-scanning or writing.
- Fresh mode fetches the issue, scans the repo, traces dependencies, and synthesizes implementation options.
- Use subagents for file exploration and synthesis when available.
- See `references/analysis-runbook.md` for the cached-report format, config details, and subagent notes.

## When to Use

- Use this skill for a single issue when the user wants root cause, risk, and implementation options.
- Use cached view when they want to inspect a previous analysis without re-scanning.

## Instructions

1. Fetch the issue and classify it.
2. Scan the repo and trace relevant dependencies.
3. Synthesize options, risks, and likely affected files.
4. Persist the analysis unless the user asked for view mode.

## Acceptance Criteria

- [ ] Fresh mode writes `.gitissue/analysis-<N>.json`.
- [ ] View mode renders cached data without writing.
- [ ] The report includes root cause, affected files, options, and risk.

## Edge Cases

- Missing or malformed cached JSON.
- Closed issues that are still valid to analyze for reference.

## Example

```text
/issue-analysis 42 view
```

Expected output: a saved issue analysis report with root cause, affected files, options, and risk.
