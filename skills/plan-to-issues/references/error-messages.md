# Error Messages — /plan-to-issues

All errors follow the rich error format: what went wrong + fix command + docs link.

**A block here that stops the run is followed by the run-stats footer** — see `references/run-stats.md`. A stop is a terminal outcome like any other, and printing the error block and exiting without the footer is the gap that contract exists to close. A stop that happens before the run clock was captured prints `elapsed n/a`, which is the contract working, not a hole in it. A `⚠` block that warns and continues is not a terminal outcome and prints no footer of its own.

Phase 0's per-probe failure blocks — `gh` too old, token scope, permission, ambiguous remote, API budget, input resolution — live beside the probes in `references/preflight.md`. This file holds the install-level and configuration errors every idd skill shares.

## Installation

### Missing required skill — `issue-creator`
```
✗ Missing required skill: issue-creator

  /plan-to-issues delegates every issue body to /issue-creator. Filing
  issues without it would produce a backlog that /issue-triage and
  /issue-resolver cannot read.

  To fix:  asm install https://github.com/luongnv89/idd --skill issue-creator
           (no asm yet: npm install -g agent-skill-manager)
  Plugin:  claude plugin marketplace add luongnv89/idd
           claude plugin install idd@idd

  Then restart the agent session and re-run /plan-to-issues.
```
**Trigger:** the *Dependency Preflight* finds no sibling `issue-creator/SKILL.md` and `asm list` does not list it. Stop — there is no fallback (`references/issue-creator-bridge.md` → *Fallback*).

### Missing bundled dependency
```
✗ Missing bundled dependency: {missing_file}

  To fix:  asm install https://github.com/luongnv89/idd --skill plan-to-issues
           (or reinstall the full distribution)
  Plugin:  claude plugin marketplace add luongnv89/idd
           claude plugin install idd@idd
           (or: claude plugin update idd@idd)

  Then restart the agent session and re-run /plan-to-issues.
```
**Trigger:** a path in SKILL.md → *Bundled dependency precheck* is absent. A truncated install that passes preflight and then fails mid-run is the failure this gate prevents.

## Configuration

### Invalid config
```
✗ Invalid config: .gitissue.yml

  Line {N}: {field} {validation_message}

  To fix:  edit .gitissue.yml and correct the values above
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```
**Trigger:** `gi-config.py` exits 3 — the file exists but holds an invalid value. Stop before Phase 0's first probe.

### gi-config unavailable (warn, continue)
```
⚠ gi-config unavailable — reading .gitissue.yml by hand
```
**Trigger:** no `python3`, a non-zero exit other than 3, or unparsable stdout. Not a terminal outcome.

## Plan map

### Invalid render input
```
✗ gi-plan-map: {message}

  To fix:  {hint from stderr}
  Docs:    references/epic-dashboard.md → Render input schema
```
**Trigger:** `gi-plan-map.py` exits 3. The render input this run built is wrong — fix the input and re-render; never hand-render past it, and never write a partial map into the epic.

### gi-plan-map unavailable (warn, continue)
```
⚠ gi-plan-map unavailable — rendering the plan map by hand
```
**Trigger:** no `python3`, any non-zero exit other than 3, or empty/unparsable stdout. Render by hand per `references/epic-dashboard.md` (*Layout*, *Rules the layout must hold*) and record the degrade under *Uncertainty*.
