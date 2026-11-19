# Error Messages — /issue-analysis

All errors follow the rich error format: what went wrong + fix command + docs link.

**A block here that stops the run is followed by the run-stats footer** — see `references/run-stats.md`. A stop is a terminal outcome like any other, so the error block never ends the run without the footer. A stop that happens before the run clock was captured prints `elapsed n/a`. A `⚠` block that warns and continues is not a terminal outcome and prints no footer of its own.

## Authentication & Setup

### Not authenticated
```
✗ Not authenticated with GitHub

  To fix:  gh auth login
  Docs:    https://cli.github.com/manual/gh_auth_login
```
**Trigger:** `gh` returns auth error (exit code 4 or "not logged in" in stderr).

### GitHub CLI not found
```
✗ GitHub CLI not found

  To fix:  brew install gh
  Docs:    https://cli.github.com
```
**Trigger:** `gh` command not found in PATH.

### No GitHub remote
```
✗ No GitHub remote configured

  To fix:  git remote add origin <url>
```
**Trigger:** `git remote -v` returns no output or no GitHub URL.

### Not a git repository
```
✗ Not a git repository

  To fix:  git init && git remote add origin <url>
```
**Trigger:** `git rev-parse --git-dir` fails.

## Issue Fetch

### Issue not found
```
✗ Issue #N not found

  To fix:  gh issue list
  Check:   is this the right repository?
```
**Trigger:** `gh issue view N` returns a 404 error.

### Issue closed (informational)
```
⚠ Issue #N is closed. Analyzing anyway for reference.
```
**Trigger:** Issue state is `closed`. Analysis continues — this is a warning, not a stop condition.
**Note:** This is an informational message, not an error.

### Issue body empty
```
⚠ Issue #N has no description. Analysis may be limited.

  Continue anyway? [y/N]
```
**Trigger:** Issue body is empty or null. In interactive mode, default is No — if declined, stop. In `IDD_AUTO_MODE=1` or when invoked/delegated by `/auto-pilot`, do not prompt; warn that confidence is limited and continue with title-only analysis (a listed auto-mode exception). <!-- auto:exception=analysis-empty-body -->

## Research

### Scan timeout
```
⚠ Scan timeout after {N}s — analysis based on {M} files read

  To fix:  increase analysis.scan_timeout in .idd.yml
```
**Trigger:** The research phase exceeds `analysis.scan_timeout` seconds (default 120). Analysis continues with partial results.

### No relevant files found
```
⚠ Could not find files relevant to issue #N

  The issue may reference components not in this codebase.
  Check:   are the keywords in the issue specific enough?
  Tip:     normalize the issue with /issue-creator N first
```
**Trigger:** Codebase scan finds no files matching any extracted keywords or file references. Analysis stops.

## Persistence

### No analysis found (view mode)
```
○ No analysis found for issue #N. Run /issue-analysis N to generate one.
```
**Trigger:** `/issue-analysis N view` invoked but `.idd/analysis-N.json` does not exist.
**Note:** This is an informational message, not an error.

### Corrupted analysis file
```
✗ .idd/analysis-N.json is corrupted

  To fix:  rm .idd/analysis-N.json && /issue-analysis N
  Check:   was the file edited manually?
```
**Trigger:** `/issue-analysis N view` finds the file but it does not parse or fails *Validate analysis data* (`references/output-and-persist.md`).

### Could not save analysis
```
⚠ Could not save analysis to .idd/analysis-N.json

  To fix:  check file permissions in the .idd/ directory
```
**Trigger:** File write to `.idd/analysis-N.json` fails (permission denied, disk full, etc.).

## Plan Comment (`--plan`)

### Plan refused — issue not normalized
```
✗ Plan refused — issue #N is not normalized

  A plan is bound to the body it was made for, and /issue-resolver
  normalizes an un-normalized body before reading its plan.
  To fix:  /issue-creator N   (normalize it), then /issue-analysis N --plan
```
**Trigger:** `--plan` on a body without `<!-- idd:normalized v1 -->` (or a legacy `gitissue:normalized` marker). Nothing is posted; the saved analysis stands.

### Plan approval label not removed
```
✗ Plan not posted — plan-approved is still on issue #N

  An approval must never carry over to a new plan.
  To fix:  gh issue edit N --remove-label plan-approved
           then /issue-analysis N --plan
```
**Trigger:** the `plan-approved` removal could not be confirmed by a live label read (`references/docs/plan-and-claim.md`, *Posting a plan*). Nothing is posted.

### Plan comment not posted
```
⚠ Plan comment not posted on issue #N: {reason}

  The analysis is saved; post it later with /issue-analysis N --plan.
```
**Trigger:** `gi-plan.py render-plan` exits non-zero, or `gh issue comment` or the `planned` label write fails.

## Configuration

### Invalid config
```
✗ Invalid config: .idd.yml

  Line {N}: {field} {validation_message}

  To fix:  edit .idd.yml and correct the values above
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```
**Trigger:** Config file exists but contains invalid values (wrong type, out of range, unknown field).
