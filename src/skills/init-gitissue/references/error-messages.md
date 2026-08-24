# Error Messages — /init-gitissue

All errors follow the rich error format: what went wrong + fix command + docs link.

**A block here that stops the run is followed by the run-stats footer** — see `references/run-stats.md`. A stop is a terminal outcome like any other, and printing the error block and exiting without the footer is the gap that contract exists to close. A stop that happens before the run clock was captured prints `elapsed n/a`, which is the contract working, not a hole in it. A `⚠` block that warns and continues is not a terminal outcome and prints no footer of its own.

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

### Stack detection failed
```
✗ Stack detection cannot run

  {reason from gi-stack-detect on stderr}

  To fix:  run /init-gitissue from the repository root
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```
**Trigger:** `gi-stack-detect.py` exits 3 — `--root` is not a directory, or a `--rules` file is not the documented shape. This is a **stop**, not a degrade: the caller pointed the scan at something it cannot scan, and detecting inline would scan the same wrong place. Exit 4 (the repository could not be read at all) *is* a degrade — warn and run the detection tables by hand.

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

### Generated config failed validation
```
✗ Generated .gitissue.yml failed validation: {yaml_parse_error_or_placeholder_list}

  To fix:  inspect the file, then re-run /init-gitissue to regenerate it
  Check:   python3 -c "import yaml; yaml.safe_load(open('.gitissue.yml'))"
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```
**Trigger:** After writing `.gitissue.yml`, the file does not parse as YAML, still contains an unsubstituted `{placeholder}` token, or is missing the `platform` key. The file is left in place for inspection and setup does not report success.
