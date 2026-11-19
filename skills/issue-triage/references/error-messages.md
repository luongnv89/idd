# Error Messages — /issue-triage

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

## Triage

### Insufficient API rate budget (preflight)
```
✗ Insufficient GitHub API rate budget for triage

  Remaining: {remaining} calls — below the safe threshold of 100.
  The update-mode batch loop fetches every open issue and fans out
  scanner subagents; running now would exhaust the budget mid-scan.

  To fix:  wait for the budget to reset, then retry
  Check:   gh api rate_limit --jq '{remaining: .rate.remaining, reset: .rate.reset}'
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/platform-github.md
```
**Trigger:** Preflight step 5 finds `gh api rate_limit --jq '{remaining: .rate.remaining, reset: .rate.reset}'` below 100 before the update-mode batch loop. Fatal — triage stops.

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
⚠ More than {limit} open issues found. Analyzing first {limit}.

  To analyze more: /issue-triage --limit {N}
```
**Trigger:** `gi-backlog.py` reports `truncated: true` (fallback: `gh issue list` returns exactly the limit, default 100) and no `--limit` override was specified.

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
  To fix:  increase triage.scan_timeout_per_issue in .idd.yml
```
**Trigger:** Keyword scan for a single issue exceeds `triage.scan_timeout_per_issue` seconds.

### No merged PRs found for fix-scan
```
○ No merged PRs found — skipping already-fixed detection.
```
**Trigger:** `gh pr list --state merged` returns an empty array. This is expected for new repos.
**Note:** This is an informational message, not an error. The triage continues without fix-scanning.

### API rate limit during fix-scan
```
⚠ GitHub API rate limit reached during fix-scan

  Skipping already-fixed detection. Triage continues without it.
  Check:   gh api rate_limit --jq '{remaining: .rate.remaining, reset: .rate.reset}'
```
**Trigger:** HTTP 403 with rate limit headers during the merged PR fetch in Step 1b.

### API rate limit during fetch
```
✗ GitHub API rate limit reached while fetching issues

  Fetched {count}/{total} issues before limit.
  To fix:  wait a few minutes, then retry
  Check:   gh api rate_limit --jq '{remaining: .rate.remaining, reset: .rate.reset}'
```
**Trigger:** HTTP 403 with rate limit headers during issue fetch.

## Persistence

### No triage report found
```
○ No cached triage found — running first analysis...
```
**Trigger:** `/issue-triage` invoked but `.idd/triage.json` does not exist. The skill automatically falls through to a full analysis.
**Note:** This is an informational message, not an error.

### Corrupted triage report
```
✗ .idd/triage.json is corrupted

  To fix:  rm .idd/triage.json && /issue-triage update
  Check:   was the file edited manually?
```
**Trigger:** `/issue-triage` finds the file but JSON parsing fails.

### Could not save triage report
```
⚠ Could not save triage report to .idd/triage.json

  To fix:  check file permissions in the .idd/ directory
```
**Trigger:** File write to `.idd/triage.json` fails (permission denied, disk full, etc.) — including `gi-triage-graph.py` exiting 4, which still printed the payload on stdout.

### Invalid triage scan
```
✗ Invalid triage scan — the ordering step cannot run

  {reason from gi-triage-graph on stderr}

  To fix:  re-run /issue-triage update so the scanner rebuilds the scan
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```
**Trigger:** `gi-triage-graph.py` exits 3 — an issue without a number, an edge naming an unknown issue, an unparsable timestamp, or an out-of-range `triage.*` value. This is a **stop**, never a degrade: the scan is wrong, and computing the same order by hand would compute it from the same wrong input.

## Route mode

### Invalid route config
```
✗ Invalid route config: {key}

  {reason: gi-route's stderr, or the failed check}

  To fix:  {fix for that key}
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```
**Trigger:** `{key}` = `triage.route.questions` — an id fails `^[a-z]+$`, or `gi-route.py --questions --enabled` exits 3; fix: keep injection, clarity and criteria in the list. `{key}` = `triage.route.label_prefix` — the prefix fails the check in `references/route-mode.md` (§1); fix: match that check. A **stop**.

### Route answers rejected
```
⚠ #{N} answers rejected — routed needs-human: {reason}
```
**Trigger:** a judge call exits 3. No comment, never `{prefix}agent-ready`; the run continues.

### gi-route unavailable
```
⚠ gi-route unavailable — routing needs-human
```
**Trigger:** no `python3`, an exit other than 0 or 3, or unparsable stdout. No comment (only the script renders one), never `{prefix}agent-ready`.

### Route write failed
```
⚠ Could not write the route for #{N}: {label | comment}

  To fix:  check write access: gh repo view --json viewerPermission
```
**Trigger:** the add still fails after its one create-and-retry, the `{prefix}agent-ready` removal fails, `gh issue comment` fails, or the re-read lacks the route label (or still carries `{prefix}agent-ready` after its removal). A failed first add or a failed `gh label create` alone is not a write failure. The run continues.

## Configuration

### Invalid config
```
✗ Invalid config: .idd.yml

  Line {N}: {field} {validation_message}

  To fix:  edit .idd.yml and correct the values above
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```
**Trigger:** Config file exists but contains invalid values (wrong type, out of range, unknown field).
