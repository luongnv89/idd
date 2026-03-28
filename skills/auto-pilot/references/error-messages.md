# Error Messages — /auto-pilot

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

## Pre-flight

### Dirty working tree (auto-resolved)
```
⚠ Working tree had uncommitted changes — auto-stashed
  Stash ref: {stash_ref}
```
**Trigger:** `git status --porcelain` returns non-empty output.
**Action:** Auto-stash with `git stash --include-untracked -m "auto-pilot: stash before run"`. Non-fatal — auto-pilot continues.

### Not on default branch (auto-resolved)
```
⚠ Was on branch {branch} — auto-switched to {default_branch}
```
**Trigger:** `git rev-parse --abbrev-ref HEAD` returns a branch that is not `main` or `master`.
**Action:** Auto-switch with `git checkout {default_branch} && git pull --rebase origin {default_branch}`. Non-fatal — auto-pilot continues.

## Explicit List Mode

### Empty issue list
```
✗ No issues to process

  The issue list is empty after removing duplicates and skipped issues.
  To fix:  provide at least one issue number: /auto-pilot --issues 5,10
```
**Trigger:** `--issues` list is empty after deduplication and `--skip` removal.

### All issues invalid
```
✗ No valid issues to process

  All issues in the list are closed or not found.
```
**Trigger:** Every issue in the `--issues` list is either not found or closed after validation.

### Issue not found in list
```
✗ #{N} — not found (removing)
```
**Trigger:** `gh issue view N` returns 404 during upfront validation of `--issues` list. Non-fatal — the issue is removed from the list.

### Issue closed in list
```
⚠ #{N} — {title} (closed, removing)
```
**Trigger:** Issue state is `closed` during upfront validation. Non-fatal — the issue is removed from the list.

### Conflicting flags
```
✗ --issues and --limit cannot be combined

  The issue list defines its own limit.
  To fix:  use --issues alone, or --limit without --issues
```
**Trigger:** Both `--issues` and `--limit` flags are provided.

## Analysis (Explicit List Mode)

### Analysis failed
```
⚠ Issue analysis failed — falling back to user-defined order

  The analyzer could not complete analysis for all issues.
  Proceeding with original order without batching optimization.
```
**Trigger:** Analyzer subagent returns failure or times out. Non-fatal — the auto-pilot falls back to processing issues in the original user-defined order without batching.

### Analysis partial failure
```
⚠ Could not analyze #{N} — excluded from batching

  Issue #{N} will be resolved individually in its original position.
```
**Trigger:** Analyzer could not analyze a specific issue (e.g., issue body is empty or unparseable). Non-fatal — the issue is excluded from batching but still resolved individually.

## Triage

### No open issues
```
✓ All issues resolved — nothing left to triage!
```
**Trigger:** `gh issue list --state open` returns an empty array. This is a success message, not an error.

### No eligible issues
```
⚠ No eligible issues to pick

  Blocked:   {blocked_count} issues (waiting on dependencies)
  Skipped:   {skipped_count} issues (skip labels or --skip)
  Assigned:  {assigned_count} issues (assigned to others)

  To unblock: resolve dependency issues first, or use --skip to bypass
```
**Trigger:** All open issues are blocked, skipped, or assigned to other users.

### API rate limit during triage
```
✗ GitHub API rate limit reached while fetching issues

  Fetched {count}/{total} issues before limit.
  To fix:  wait a few minutes, then retry
  Check:   gh api rate_limit --jq '.rate.remaining'
```
**Trigger:** HTTP 403 with rate limit headers during issue fetch.

## Resolve

### Resolve failure (autonomous default)
```
⚠ Skipping #{issue_number} — will retry on next run.
  Continuing to next issue...
```
**Trigger:** Issue resolver fails at any step. Default behavior: log failure, skip issue, continue loop.

### Resolve failure (pause mode — opt-in)
```
⚠ Auto-pilot paused due to failure (pause_on_failure: true).

  Failed on:  #{issue_number} — {title}
  Step:       {step_name}
  To resume:  fix the issue, then /auto-pilot
  To skip:    /auto-pilot --skip {issue_number}
```
**Trigger:** Issue resolver fails and `autopilot.pause_on_failure` is explicitly set to `true` in config.

### Sync conflict (auto-resolved)
```
⚠ Sync conflict — auto-reset to origin/{default_branch}
  Any local-only changes were discarded (all work is already pushed to PRs).
```
**Trigger:** `git pull --rebase origin {default_branch}` fails with merge conflicts.
**Action:** Auto-recover with `git rebase --abort && git reset --hard origin/{default_branch}`. Non-fatal — auto-pilot continues.

### Sync failure (unrecoverable)
```
✗ Failed to sync with {default_branch} — cannot recover automatically

  To fix:  resolve conflicts manually: git rebase --continue
  Then:    /auto-pilot to resume
```
**Trigger:** Both rebase and hard reset fail. Fatal — auto-pilot stops.

## Review

### Review cycles exhausted
```
⚠ Review issues remain after {review_cycles} review-fix cycles

  Remaining issues:
    1. {issue_description_1}
    2. {issue_description_2}

  Auto-merge skipped — PR needs manual review.
  PR: https://github.com/owner/repo/pull/{pr_number}
```
**Trigger:** All review-fix cycles are exhausted and the review still finds issues.

## Merge

### PR not mergeable (auto-skip)
```
⚠ PR #{pr_number} is not mergeable

  Reason: {conflict / failing checks / review requested}
  PR left open — continuing to next issue.
```
**Trigger:** `gh pr view` shows `mergeable` is false or `reviewDecision` is `CHANGES_REQUESTED`.
**Action:** Leave PR open, continue to next issue. Non-fatal.

### Merge failed (auto-skip)
```
⚠ Merge failed for PR #{pr_number} — PR left open
  Continuing to next issue...
```
**Trigger:** `gh pr merge` returns non-zero exit code.
**Action:** Leave PR open, continue to next issue. Non-fatal.

### CI checks timeout
```
✗ CI checks did not complete within {timeout}s

  PR: https://github.com/owner/repo/pull/{pr_number}
  To fix:  wait for CI to finish, then /auto-pilot to resume
```
**Trigger:** Status checks remain pending after `review.ci_timeout` seconds of polling.

### CI checks failed
```
✗ CI checks failed for PR #{pr_number}

  Failed checks:
    ✗ {check_name_1}: {conclusion}
    ✗ {check_name_2}: {conclusion}

  PR: https://github.com/owner/repo/pull/{pr_number}
  To fix:  review check logs and fix: gh pr checks {pr_number}
```
**Trigger:** One or more status checks complete with `failure` or `error` conclusion.

## Configuration

### Invalid config
```
✗ Invalid config: .gitissue.yml

  Line {N}: {field} {validation_message}

  To fix:  edit .gitissue.yml and correct the values above
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```
**Trigger:** Config file exists but contains invalid values (wrong type, out of range, unknown field).
