# Error Messages — /init-idd

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
⚠ .idd.yml already exists

  Options:
    overwrite  — replace with new auto-detected config
    merge      — keep existing values, add new fields
    cancel     — do nothing

  Choose: [overwrite/merge/cancel]
```
**Trigger:** `.idd.yml` (or, with no `.idd.yml`, the legacy `.gitissue.yml` — the prompt then names it) already exists in the repo root and the run is interactive. In auto mode (`--auto` or `IDD_AUTO_MODE=1`) this prompt is not shown: print `⚠ Auto mode: overwrite/merge/cancel prompt skipped — kept the existing .idd.yml (cancel).` and take **cancel**.

### Legacy config found
```
⚠ legacy .gitissue.yml found — rename to .idd.yml (git mv .gitissue.yml .idd.yml)
```
**Trigger:** only the legacy `.gitissue.yml` exists and the run is in auto mode. It is kept untouched and no `.idd.yml` is written (`Result: CANCELLED`). Interactive runs show the *Config already exists* prompt instead and, after merge or overwrite, tell the user to `git rm .gitissue.yml`. Steps: https://github.com/luongnv89/idd/blob/main/docs/migrating-from-gitissue.md

### Existing config does not parse
```
✗ Existing .idd.yml does not parse as YAML — cannot merge

  {yaml_parse_error}

  To fix:  fix the file by hand, or re-run /init-idd and choose overwrite
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```
**Trigger:** The user chose **merge** and the existing file fails the YAML parse. The file is left untouched and the run reports `Result: BLOCKED`.

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
  Tip: configure your test command in .idd.yml after setup.
```
**Trigger:** No recognized test runner configuration files found in the repository.
**Note:** This is an informational message, not an error.

### Stack detection failed
```
✗ Stack detection cannot run

  {reason from gi-stack-detect on stderr}

  To fix:  run /init-idd from the repository root
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```
**Trigger:** `gi-stack-detect.py` exits 3 — `--root` is not a directory, or a `--rules` file is not the documented shape. This is a **stop**, not a degrade: the caller pointed the scan at something it cannot scan, and detecting inline would scan the same wrong place. Exit 4 (the repository could not be read at all) *is* a degrade — warn and run the detection tables by hand.

## File Write

### Write failed
```
✗ Could not write .idd.yml

  To fix:  check file permissions in the repo root
  Check:   do you have write access? ls -la .
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```
**Trigger:** File write to `.idd.yml` fails (permission denied, disk full, read-only filesystem).

### Could not update .gitignore
```
⚠ Could not update .gitignore — .idd/cache/ may not be ignored

  {error output from the Ignore Rule}

  To fix:  printf '.idd/cache/\n' >> .gitignore
  Check:   ls -la .gitignore
```
**Trigger:** the *Ignore Rule* snippet printed an error (permission denied, read-only file). A warning, not a stop: the config result stands, and the `.gitignore:` row shows `⚠ warn (write failed)`.

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
✗ Generated .idd.yml failed validation: {yaml_parse_error_or_placeholder_list}

  To fix:  inspect the file, then re-run /init-idd to regenerate it
  Check:   python3 -c "import yaml; yaml.safe_load(open('.idd.yml'))"
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```
**Trigger:** After writing `.idd.yml`, the file does not parse as YAML, still contains an unsubstituted `{placeholder}` token, or is missing the `platform` key. The file is left in place for inspection and setup does not report success.
