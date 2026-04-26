# Issue Analysis Runbook

This reference holds the longer cached-view and orchestration details that are not needed in the main skill body.

## View Mode

When invoked as `/issue-analysis <N> view`:
- read `.gitissue/analysis-<N>.json`
- if missing, print the empty-state message and stop
- if malformed, print the corruption error and stop
- render the cached report without re-scanning
- never write to disk in view mode

## Subagents

- Use a codebase-researcher subagent for structural exploration.
- Use a synthesizer subagent for implementation options and risk tradeoffs.
- Keep the main agent focused on orchestration and final reporting.

## Output

The rendered report should include the issue title, cache age, and the same analysis sections produced in fresh mode.
