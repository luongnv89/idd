<!-- Generated from /docs/config-schema.md. Do not edit. Edit source and run ./scripts/build.sh. -->
# `.gitissue.yml` Configuration Schema

> **Per-skill excerpt (generated).** Only the configuration sections this skill reads are reproduced here: `analysis`, `issue`, `platform`, `triage`. The complete schema — every section and the full defaults table — is at [config-schema.md](https://github.com/luongnv89/idd/blob/main/docs/config-schema.md).

gitissue works with zero configuration — all settings have sensible defaults. When no `.gitissue.yml` file exists, the first-run hint is shown:

```
○ First run — using default config. Run /init-gitissue to customize.
```

Place `.gitissue.yml` in the repository root to customize behavior.

### Config Loading Flow

A skill loads the file once at start. Present and valid → use it. Present and
invalid → stop with the line-numbered errors under *Validation* below. Absent →
use the defaults and print the first-run hint above.

### Config Hierarchy

Three inputs, each with its own lifetime: `.gitissue.yml` is configuration, read
**once** at skill start; `.gitissue/` is state, read and written **during**
execution; the built-in skill defaults are the **fallback** when no config file
exists.

## Core Fields

Ten fields cover almost every customization in practice — `platform`, `issue.auto_normalize`, `resolve.branch_prefix`, `resolve.auto_test`, `resolve.test_timeout`, `triage.stale_threshold_days`, `autopilot.mode`, `autopilot.review_cycles`, `autopilot.skip_labels`, and `review.require_acceptance_criteria_check`. Start with those (the README shows a ready-to-copy sample); treat everything below as the **advanced reference** — useful when a specific behavior needs tuning, never required.

## Full Schema (advanced reference)

```yaml
# Tracker platform driver
# Type: string
# Values: "github" — the only implemented driver (see references/docs/platform-github.md);
#         a new driver becomes valid here once its docs/platform-<name>.md exists
# Default: "github"
platform: github

# Issue creation and normalization settings
issue:
  # Auto-normalize issues (structure-only, no codebase scan) in /issue-resolver before resolution
  # Type: boolean
  # Default: true
  auto_normalize: true

  # Issue template source
  # Type: string
  # Values: "default" | path to custom template directory
  # Default: "default"
  # When "default", uses built-in templates (bug.md, feature.md, improvement.md)
  # When a path, looks for bug.md, feature.md, improvement.md in that directory
  template: default

  # Auto-suggest labels based on issue content and type
  # Type: boolean
  # Default: true
  labels_auto_suggest: true

  # Post a comment when normalizing an issue
  # Type: boolean
  # Default: true
  normalize_comment: true

# Triage settings
triage:
  # Flag issues with no activity beyond this threshold (days)
  # Type: integer
  # Default: 14
  # Minimum: 1
  stale_threshold_days: 14

  # Suggest priorities based on type, age, and dependency position
  # Type: boolean
  # Default: true
  auto_priority: true

  # Include recently closed issues in triage analysis
  # Type: boolean
  # Default: false
  include_closed: false

  # Max seconds to scan codebase per issue for file dependencies
  # Type: integer
  # Default: 30
  # Minimum: 5
  # Maximum: 300
  scan_timeout_per_issue: 30

# Issue analysis settings
analysis:
  # Max files to read during deep analysis (more thorough than resolver's 20)
  # Type: integer
  # Default: 30
  # Minimum: 5
  # Maximum: 100
  max_files: 30

  # How many levels of import dependencies to trace
  # Type: integer
  # Default: 3
  # Minimum: 1
  # Maximum: 5
  trace_depth: 3

  # Max seconds for the full codebase scan phase
  # Type: integer
  # Default: 120
  # Minimum: 30
  # Maximum: 600
  scan_timeout: 120
```

## `.gitissue/` Directory

State written by gitissue skills, at the repo root beside `.gitissue.yml`, created on first use.

| File | Written by | Description |
|------|-----------|-------------|
| `.gitissue/triage.json` | `/issue-triage`, `/auto-pilot` | Cached triage analysis (JSON schema v1) — priorities, dependencies, execution order, history |
| `.gitissue/analysis-<N>.json` | `/issue-analysis` | Deep analysis of issue #N — affected files, root cause, implementation options, complexity, and risk |
| `.gitissue/runs.jsonl` | `/issue-resolver`, `/auto-pilot` | Append-only run log — one JSON line per processed issue. Schema and single-writer rule: the subsection below |
| `.gitissue/run-state.json`, `run.lock`, `last-run-report.md` | `/auto-pilot` | Mutable resume state (current/lane phases and PRs, processed/skips), run lock, and final report. Machine-local; mechanics: auto-pilot preflight/phases |

> **Not in `.gitissue/`:** the model-suggestion cache is **skill-level** —
> `/issue-creator` caches CursorBench data in the installed skill folder as
> `model-data-<date>.json` (one per machine, all repos); a legacy
> `.gitissue/model-data.json` is ignored. See
> `src/skills/issue-creator/references/model-suggestion.md`.

**Conventions:**
- Skills create `.gitissue/` via `mkdir -p`
- JSON files are formatted for readable git diffs
- A full re-triage overwrites `triage.json`; `/auto-pilot` instead updates it in place after a merge, removing the resolved issue and appending one history entry
- `runs.jsonl` is **append-only** — one line per run, never edited; its absence or deletion is non-fatal
- Commit the directory (project state, not secrets)
- **Carve-out — `run-state.json`, `run.lock` and `last-run-report.md` are
  machine-local and gitignored.** They describe one machine's in-flight run: a
  committed lock makes every clone look busy, a committed state offers a resume
  onto branches another machine lacks, and both carry titles of work in flight.
  Only `src/shared/scripts/gi-state.py` writes them — the single writer that
  makes `--dry-run` leave no mutation.

### `.gitissue/runs.jsonl` — run log (monitoring)

Field set, append rules, and the single-writer / `--no-run-log` convention live
in
[run-log-schema.md](https://github.com/luongnv89/idd/blob/main/docs/run-log-schema.md).
Skills that only append a telemetry line read that document, not this one.

## Validation

Config is validated on load at the start of every skill invocation. Errors include line numbers:

```
✗ Invalid config: .gitissue.yml

  Line 8: issue.template must be "default" or a valid directory path
  Line 15: resolve.test_timeout must be between 30 and 3600

  To fix:  edit .gitissue.yml and correct the values above
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```

## Defaults Table

| Setting | Default | Description |
|---------|---------|-------------|
| `platform` | `github` | Tracker platform driver — `github` is the only implemented driver (references/docs/platform-github.md) |
| `issue.auto_normalize` | `true` | Auto-normalize in /issue-resolver |
| `issue.template` | `default` | Built-in templates |
| `issue.labels_auto_suggest` | `true` | Suggest labels from content |
| `issue.normalize_comment` | `true` | Comment on normalization |
| `triage.stale_threshold_days` | `14` | Stale issue threshold |
| `triage.auto_priority` | `true` | Auto-suggest priorities |
| `triage.include_closed` | `false` | Exclude closed from triage |
| `triage.scan_timeout_per_issue` | `30` | Max seconds per issue scan |
| `analysis.max_files` | `30` | Max files to read during analysis |
| `analysis.trace_depth` | `3` | Import trace depth levels |
| `analysis.scan_timeout` | `120` | Max seconds for codebase scan |
