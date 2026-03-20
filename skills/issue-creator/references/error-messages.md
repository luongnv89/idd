# Error Messages — /issue-creator

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

## Issue Creation

### Rate limited
```
✗ GitHub API rate limit reached

  To fix:  wait a few minutes, then retry
  Check:   gh api rate_limit --jq '.rate.remaining'
```
**Trigger:** HTTP 403 with rate limit headers.

### Repository not found
```
✗ Repository not found or no access

  To fix:  check your remote: git remote -v
  Check:   do you have push access to this repo?
```
**Trigger:** HTTP 404 from `gh issue create`.

## Normalization

### Issue not found
```
✗ Issue #N not found

  To fix:  gh issue list
  Check:   is this the right repository?
```
**Trigger:** `gh issue view N` returns 404.

### Already normalized
```
✓ Issue #N is already normalized (v1, {date}). No changes needed.
```
**Trigger:** Issue body contains `<!-- gitissue:normalized v1 -->`.
**Note:** This is an informational message, not an error.

### Security label detected
```
⚠ Issue #N has a security label ({label_name}). Skipping normalization.
  Codebase context could reveal exploit details.

  To override: /issue-creator N --force
```
**Trigger:** Issue has label matching: 'security', 'CVE', 'vulnerability'.

### Backup comment failed
```
✗ Failed to post backup comment for issue #N

  Normalization aborted — original issue body is unchanged.
  To fix:  check your permissions: gh issue comment N --body "test"
```
**Trigger:** `gh issue comment` fails during normalization backup step.

### Issue locked
```
✗ Issue #N is locked

  To fix:  unlock the issue in GitHub's web UI, then retry
```
**Trigger:** API returns 403 with "locked" reason.

## Empty States

### No files identified
```
⚠ Could not identify affected files. Issue created with manual-review flag.
  Tip: mention specific filenames or error messages for better results.
```
**Trigger:** Codebase scan returns no file matches.

### No labels suggested
```
○ No labels suggested — add labels manually if needed.
```
**Trigger:** Auto-label logic returns empty suggestions.
