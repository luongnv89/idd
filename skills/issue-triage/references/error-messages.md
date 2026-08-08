# Error Messages — /issue-triage

All errors follow the rich error format: what went wrong + fix command + docs link.

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

## Triage

### Insufficient API rate budget (preflight)
```
✗ Insufficient GitHub API rate budget for triage

  Remaining: {remaining} calls — below the safe threshold of 100.
  The update-mode batch loop fetches every open issue and fans out
  scanner subagents; running now would exhaust the budget mid-scan.

  To fix:  wait for the budget to reset, then retry
  Check:   gh api rate_limit --jq '.rate.remaining'
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/platform-github.md
```
**Trigger:** Preflight step 5 finds `gh api rate_limit --jq '.rate.remaining'` below 100 before the update-mode batch loop. Fatal — triage stops.

**Low-budget warning (non-fatal):** when `remaining` is between 100 and 200, print the same block with a `⚠` symbol and the line `Proceeding — budget may run low during the scan.` instead of stopping.

### No open issues
```
○ No open issues found. Nothing to triage!
  Create issues with /issue-creator to get started.
```
**Trigger:** `gh issue list --state open` returns an empty array.
**Note:** This is an informational message, not an error.

### Too many issues
```
⚠ {count} open issues found. Analyzing first {limit}.

  To analyze all: /issue-triage --limit {count}
```
**Trigger:** `gh issue list` returns more than the limit (default 100) and no `--limit` override was specified.

### Circular dependencies
```
⚠ Circular dependency detected: #{a} → #{b} → #{a}

  These issues share affected files detected by codebase scan.
  Suggestion: resolve #{a} first (fewer dependencies).
```
**Trigger:** Depth-first traversal of the dependency graph detects a cycle.

### Scan timeout
```
⚠ Scan timeout for #{N} — skipping file analysis

  Issue will appear as no-deps (timeout) in the dependency graph.
  To fix:  increase triage.scan_timeout_per_issue in .gitissue.yml
```
**Trigger:** Keyword scan for a single issue exceeds `triage.scan_timeout_per_issue` seconds.

### No merged PRs found for fix-scan
```
○ No merged PRs found in the last 3 months — skipping already-fixed detection.
```
**Trigger:** `gh pr list --state merged` returns an empty array. This is expected for new repos.
**Note:** This is an informational message, not an error. The triage continues without fix-scanning.

### API rate limit during fix-scan
```
⚠ GitHub API rate limit reached during fix-scan

  Skipping already-fixed detection. Triage continues without it.
  Check:   gh api rate_limit --jq '.rate.remaining'
```
**Trigger:** HTTP 403 with rate limit headers during the merged PR fetch in Step 1b.

### API rate limit during fetch
```
✗ GitHub API rate limit reached while fetching issues

  Fetched {count}/{total} issues before limit.
  To fix:  wait a few minutes, then retry
  Check:   gh api rate_limit --jq '.rate.remaining'
```
**Trigger:** HTTP 403 with rate limit headers during issue fetch.

## Persistence

### No triage report found
```
○ No cached triage found — running first analysis...
```
**Trigger:** `/issue-triage` or `/issue-triage view` invoked but `.gitissue/triage.json` does not exist. The skill automatically falls through to a full analysis.
**Note:** This is an informational message, not an error.

### Corrupted triage report
```
✗ .gitissue/triage.json is corrupted

  To fix:  rm .gitissue/triage.json && /issue-triage update
  Check:   was the file edited manually?
```
**Trigger:** `/issue-triage` or `/issue-triage view` finds the file but JSON parsing fails.

### Could not save triage report
```
⚠ Could not save triage report to .gitissue/triage.json

  To fix:  check file permissions in the .gitissue/ directory
```
**Trigger:** File write to `.gitissue/triage.json` fails (permission denied, disk full, etc.) — including `gi-triage-graph.py` exiting 4, which still printed the payload on stdout.

### Invalid triage scan
```
✗ Invalid triage scan — the ordering step cannot run

  {reason from gi-triage-graph on stderr}

  To fix:  re-run /issue-triage update so the scanner rebuilds the scan
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```
**Trigger:** `gi-triage-graph.py` exits 3 — an issue without a number, an edge naming an unknown issue, an unparsable timestamp, or an out-of-range `triage.*` value. This is a **stop**, never a degrade: the scan is wrong, and computing the same order by hand would compute it from the same wrong input.

## Configuration

### Invalid config
```
✗ Invalid config: .gitissue.yml

  Line {N}: {field} {validation_message}

  To fix:  edit .gitissue.yml and correct the values above
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```
**Trigger:** Config file exists but contains invalid values (wrong type, out of range, unknown field).
