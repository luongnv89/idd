# Error Messages — /issue-creator

All errors follow the rich error format: what went wrong + fix command + docs link.

**A block here that stops the run is followed by the run-stats footer** — see `references/run-stats.md`. A stop is a terminal outcome like any other, and printing the error block and exiting without the footer is the gap that contract exists to close. A stop that happens before the run clock was captured prints `elapsed n/a`, which is the contract working, not a hole in it. A `⚠` block that warns and continues is not a terminal outcome and prints no footer of its own.

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
  Check:   gh api rate_limit --jq '{remaining: .rate.remaining, reset: .rate.reset}'
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
**Trigger:** `gh issue create` returns HTTP 403 with rate limit headers during batch creation. Retries only when driver rule 5 in `references/docs/platform-github.md` classifies it as recoverable — a *secondary* limit carrying `Retry-After` — on the shared bounded schedule of 2s, 4s, 8s, 16s (four attempts), or the longer `Retry-After` when one is given. *Primary* exhaustion is not retryable and stops with the *Rate limited* block above.

### Batch item skipped after retries
```
✗ Skipped issue {N}/{total} after 4 retry attempts: {title}

  Reason:  rate limited
  Resume:  /issue-creator {title}
```
**Trigger:** A batch item is still rate limited after all four attempts (`references/modes.md` → Step 5, *Rate limiting*). The item is skipped and batch continues with remaining items.

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
**Trigger:** Config file exists but contains invalid values (wrong type, out of range, unknown field) — including `gi-model-cache.py` exiting 3 on an out-of-range `model_suggestion.*` value.

## Model Suggestion

All model-suggestion failures are **non-fatal** — they warn and continue creating the issue without a suggestion. None block creation.

### Model data refresh failed
```
⚠ Model data refresh failed — {reason}
  Using existing cached data (CursorBench {version}, fetched {age}).
  Tip: retry later, or set model_suggestion.enabled: false to disable.
```
**Trigger:** The WebFetch refresh of `data_url` fails (network error, empty/unparseable response) while a usable cache or seed is present.

### Model data unavailable
```
⚠ Model data unavailable — no cache and no bundled seed found
  Skipping model suggestion for this issue.
  To fix:  reinstall the skill, or set model_suggestion.enabled: false
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```
**Trigger:** `model_suggestion.enabled` is true but neither a skill-level `model-data-<date>.json` cache nor the bundled `templates/model-data.json` seed can be read. Suggestions are skipped; issue creation proceeds.

### Model data malformed
```
⚠ Model data is malformed — {detail}
  Skipping model suggestion for this issue.
  Tip: refresh with --refresh-model-data, or reinstall the skill to restore the bundled seed.
```
**Trigger:** The skill-level `model-data-<date>.json` cache exists but fails JSON parsing or is missing the `complexity_mapping` / `providers` keys.
