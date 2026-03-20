# Error Messages — /init-gitissue

All errors follow the rich error format: what went wrong + fix command + docs link.

## Setup

### Not a git repository
```
✗ Not a git repository

  To fix:  git init && git remote add origin <url>
```

### Config already exists
```
⚠ .gitissue.yml already exists

  Options:
    overwrite  — replace with new auto-detected config
    merge      — keep existing values, add new fields
    cancel     — do nothing

  Choose: [overwrite/merge/cancel]
```

## Detection

### No language detected
```
○ Could not detect project language. Using generic defaults.
  Tip: add a package.json, requirements.txt, or go.mod to help detection.
```

### No test runner detected
```
○ Could not detect test runner. Setting resolve.auto_test: false.
  Tip: configure your test command in .gitissue.yml after setup.
```
