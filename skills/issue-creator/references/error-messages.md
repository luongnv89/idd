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

## Batch Creation

### Partial batch failure
```
⚠ {created}/{total} created, {failed} failed

  ✓ #{n}  {succeeded_title}
         https://github.com/owner/repo/issues/{n}
  ✗      {failed_title} — {reason}

  To retry: /issue-creator {failed_title_1}
  To retry: /issue-creator {failed_title_2}
```
**Trigger:** One or more items in a batch fail to create while others succeed. One `To retry:` line per failed item.

### Batch rate limited (retry in progress)
```
● Rate limited (issue {N}/{total}: {title}) — retrying in {wait}s...
```
**Trigger:** `gh issue create` returns HTTP 403 with rate limit headers during batch creation. Auto-retries up to 3 times with exponential backoff (5s, 10s, 20s).

### Batch item skipped after retries
```
✗ Skipped issue {N}/{total} after 3 retries: {title}

  Reason:  rate limited
  Resume:  /issue-creator {title}
```
**Trigger:** A batch item fails all 3 retry attempts. The item is skipped and batch continues with remaining items.

### No items detected
```
○ Only 1 item detected — using single create mode.
```
**Trigger:** Batch detection finds only one distinct item in the input. Falls through to single Create mode.
**Note:** This is an informational message, not an error.

## Image Upload

### Image file not found
```
⚠ Image upload failed: {filename} — file not found
  Issue created without embedded image.
  Tip: upload the image manually via GitHub's web UI.
```
**Trigger:** The provided image path does not exist on disk.

### Unsupported image format
```
⚠ Image upload failed: {filename} — unsupported format
  Issue created without embedded image.
  Supported: PNG, JPG, JPEG, GIF, WEBP, SVG
  Tip: convert the image and retry, or upload manually via GitHub's web UI.
```
**Trigger:** The file extension is not in the supported list (png, jpg, jpeg, gif, webp, svg).

### Image too large
```
⚠ Image upload failed: {filename} — file too large ({size} MB, max 10 MB)
  Issue created without embedded image.
  Tip: resize or compress the image, or upload manually via GitHub's web UI.
```
**Trigger:** The file size exceeds 10 MB (GitHub API limit for contents API).

### Image upload API error
```
⚠ Image upload failed: {filename} — GitHub API error
  Issue created without embedded image.
  To fix:  check your permissions: gh api repos/{owner}/{repo}/contents
  Tip: upload the image manually via GitHub's web UI.
```
**Trigger:** The `gh api` call to upload the image returns a non-success status (403, 404, 422, 500).

### Partial image upload failure
```
⚠ {uploaded}/{total} images uploaded, {failed} failed

  ✓ {success_filename} — embedded in issue
  ✗ {failed_filename} — {reason}

  Tip: upload failed images manually via GitHub's web UI.
```
**Trigger:** In a multi-image upload, some succeed and some fail. Issue is created with successfully uploaded images embedded.

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

## Configuration

### Invalid config
```
✗ Invalid config: .gitissue.yml

  Line {N}: {field} {validation_message}

  To fix:  edit .gitissue.yml and correct the values above
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```
**Trigger:** Config file exists but contains invalid values (wrong type, out of range, unknown field).
