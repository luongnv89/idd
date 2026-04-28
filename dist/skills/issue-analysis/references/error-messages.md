# Error Messages — /issue-analysis

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
**Trigger:** Issue body is empty or null. Default is No — if declined, stop.

## Research

### Scan timeout
```
⚠ Scan timeout after {N}s — analysis based on {M} files read

  To fix:  increase analysis.scan_timeout in .gitissue.yml
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
**Trigger:** `/issue-analysis N view` invoked but `.gitissue/analysis-N.json` does not exist.
**Note:** This is an informational message, not an error.

### Corrupted analysis file
```
✗ .gitissue/analysis-N.json is corrupted

  To fix:  rm .gitissue/analysis-N.json && /issue-analysis N
  Check:   was the file edited manually?
```
**Trigger:** `/issue-analysis N view` finds the file but JSON parsing fails.

### Could not save analysis
```
⚠ Could not save analysis to .gitissue/analysis-N.json

  To fix:  check file permissions in the .gitissue/ directory
```
**Trigger:** File write to `.gitissue/analysis-N.json` fails (permission denied, disk full, etc.).

## Configuration

### Invalid config
```
✗ Invalid config: .gitissue.yml

  Line {N}: {field} {validation_message}

  To fix:  edit .gitissue.yml and correct the values above
  Docs:    https://github.com/luongnv89/idd/blob/main/src/docs/config-schema.md
```
**Trigger:** Config file exists but contains invalid values (wrong type, out of range, unknown field).
