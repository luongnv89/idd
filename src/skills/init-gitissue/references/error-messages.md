# Error Messages — /init-gitissue

All errors follow the rich error format: what went wrong + fix command + docs link.

## Setup

### Not a git repository
```
✗ Not a git repository

  To fix:  git init && git remote add origin <url>
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/platform-github.md
```
**Trigger:** `git rev-parse --git-dir` fails.

### Config already exists
```
⚠ .gitissue.yml already exists

  Options:
    overwrite  — replace with new auto-detected config
    merge      — keep existing values, add new fields
    cancel     — do nothing

  Choose: [overwrite/merge/cancel]
```
**Trigger:** `.gitissue.yml` already exists in the repo root.

## Detection

### No language detected
```
○ Could not detect project language. Using generic defaults.
  Tip: add a package.json, requirements.txt, or go.mod to help detection.
```
**Trigger:** No recognized language marker files found in the repository.
**Note:** This is an informational message, not an error.

### No test runner detected
```
○ Could not detect test runner. Setting resolve.auto_test: false.
  Tip: configure your test command in .gitissue.yml after setup.
```
**Trigger:** No recognized test runner configuration files found in the repository.
**Note:** This is an informational message, not an error.

## File Write

### Write failed
```
✗ Could not write .gitissue.yml

  To fix:  check file permissions in the repo root
  Check:   do you have write access? ls -la .
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```
**Trigger:** File write to `.gitissue.yml` fails (permission denied, disk full, read-only filesystem).

### Directory not writable
```
✗ Repository root is not writable

  To fix:  check permissions: ls -la .
  Check:   is this a read-only mount?
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```
**Trigger:** The repo root directory does not allow file creation.
