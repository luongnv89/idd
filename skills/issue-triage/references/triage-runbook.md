# Issue Triage Runbook

This reference keeps the cache and refresh heuristics out of `SKILL.md`.

## Default Mode

When invoked as `/issue-triage`:
- show cached triage instantly when `.gitissue/triage.json` exists
- run a first analysis automatically when no cache exists
- after rendering, check git history and suggest `update` only if the repo changed

## Update Mode

When invoked as `/issue-triage update` or `/issue-triage --limit N`:
- run a full re-analysis
- overwrite `.gitissue/triage.json`
- keep the report deterministic and easy to scan

## Output

Render the cached table with priority, blockers, and parallelizable work. End with a short status line telling the user whether the report looks current.
