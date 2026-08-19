<!-- Generated from /docs/config-schema.md. Do not edit. Edit source and run ./scripts/build.sh. -->
# `.gitissue.yml` Configuration Schema

> **Per-skill excerpt (generated).** Only the configuration sections this skill reads are reproduced here: `duplicate_detection`, `issue`, `model_suggestion`, `platform`, `projects`, `triage`. The complete schema — every section and the full defaults table — is at [config-schema.md](https://github.com/luongnv89/idd/blob/main/docs/config-schema.md).

gitissue works with zero configuration — all settings have sensible defaults. When no `.gitissue.yml` file exists, the first-run hint is shown:

```
○ First run — using default config. Run /init-gitissue to customize.
```

Place `.gitissue.yml` in the repository root to customize behavior.

### Config Loading Flow

Loaded **once** at skill start. Valid file → use it. Invalid → stop with the
line-numbered *Validation* errors. Absent → defaults + first-run hint above.
`.gitissue.yml` is config; `.gitissue/` is runtime state; built-ins are fallback.

## Core Fields

Everyday knobs: `platform`, `issue.auto_normalize`, `resolve.branch_prefix`, `resolve.auto_test`, `resolve.test_timeout`, `triage.stale_threshold_days`, `autopilot.mode`, `autopilot.review_cycles`, `autopilot.skip_labels`, `review.require_acceptance_criteria_check`. Everything below is the advanced reference.

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

# GitHub Projects board sync
# See https://github.com/luongnv89/idd/blob/main/docs/github-projects-sync.md
projects:
  # Type: boolean. Default: false. When false, sync is silently skipped.
  sync_enabled: false
  # Type: integer or null. Default: null (first linked project).
  project_number: null
  # Type: string. Default: "Status". Must match the board field (case-sensitive).
  status_field: "Status"
  # Internal key → board option name (must match an option in status_field).
  status_map:
    # Defaults: Todo / In Progress / Done (new issue / work started / PR created)
    todo: "Todo"
    in_progress: "In Progress"
    done: "Done"

# Deterministic dup scoring (/issue-creator). One NFKC/case-folded tokenizer;
# a signal pays per newly consumed item token. extra_stop_words extends the
# built-in list (never replaces it) and cannot raise a score.
duplicate_detection:
  # Integers >= 0. phrase must be >= `weights.title_overlap` so a stop word
  # cannot promote evidence onto a higher-paying lower-precedence signal.
  weights:
    phrase: 2
    title_overlap: 2
    keyword: 1
    # Paid once, not per token
    same_type: 1
  # Integers. High is deterministic; medium alone is sent to the LLM.
  high_threshold: 5
  medium_threshold: 3
  # Tokenizer and detection bounds — all integers >= 1
  min_token_length: 1
  phrase_min_tokens: 3
  backlog_limit: 100
  max_items: 100
  # Additive comma-separated terms; folded after NFKC. Never raises a score.
  extra_stop_words: ""

# Model suggestion (/issue-creator). Procedure: references/model-suggestion.md
model_suggestion:
  # Type: boolean. Default: true. false skips suggestion; body/preview unchanged.
  # Cache is skill-level model-data-<date>.json (all repos); --refresh-model-data.
  enabled: true
  # Type: string. Default: "https://cursor.com/cursorbench"
  data_url: "https://cursor.com/cursorbench"
  # Type: integer. Default: 7. Days before the cache is stale.
  cache_ttl_days: 7
```

## `.gitissue/` Directory

Repo-root state beside `.gitissue.yml`, created on first use.

| File | Written by | Description |
|------|-----------|-------------|
| `.gitissue/triage.json` | `/issue-triage`, `/auto-pilot` | Cached triage: priorities, deps, order, history |
| `.gitissue/analysis-<N>.json` | `/issue-analysis` | Deep analysis of issue #N |
| `.gitissue/runs.jsonl` | `/issue-resolver`, `/auto-pilot` | Append-only run log (one line per issue) |
| `.gitissue/run-state.json`, `run.lock`, `last-run-report.md` | `/auto-pilot` | Resume state, lock, report. Machine-local |

> **Not in `.gitissue/`:** the model-suggestion cache is **skill-level** (`model-data-<date>.json` in the installed skill, all repos).

**Conventions:**
- Create via `mkdir -p`
- Re-triage overwrites `triage.json`; `/auto-pilot` updates after a merge
- `runs.jsonl` is **append-only**; absence non-fatal
- **Carve-out — `run-state.json`, `run.lock`, `last-run-report.md` are machine-local and gitignored**; only `src/shared/scripts/gi-state.py` writes them, and `--dry-run` mutates nothing.

### `.gitissue/runs.jsonl` — run log

Field set, append rules, and the single-writer / `--no-run-log` convention in [run-log-schema.md](https://github.com/luongnv89/idd/blob/main/docs/run-log-schema.md).

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
| `projects.sync_enabled` | `false` | Enable project board sync |
| `projects.project_number` | `null` | Explicit project number (null = auto-detect) |
| `projects.status_field` | `"Status"` | Name of the Status field on the board |
| `projects.status_map.todo` | `"Todo"` | Status for new issues |
| `projects.status_map.in_progress` | `"In Progress"` | Status when work starts |
| `projects.status_map.done` | `"Done"` | Status when PR is created |
| `duplicate_detection.weights.phrase` | `2` | Per newly consumed phrase token; must be >= `weights.title_overlap` |
| `duplicate_detection.weights.title_overlap` | `2` | Per newly consumed shared-title token; ≤ `weights.phrase` |
| `duplicate_detection.weights.keyword` | `1` | Per newly consumed keyword token |
| `duplicate_detection.weights.same_type` | `1` | One-time same-type payment |
| `duplicate_detection.high_threshold` | `5` | Deterministic high-band |
| `duplicate_detection.medium_threshold` | `3` | Only band sent to the LLM |
| `duplicate_detection.min_token_length` | `1` | Tokenizer minimum |
| `duplicate_detection.phrase_min_tokens` | `3` | Minimum phrase length |
| `duplicate_detection.backlog_limit` | `100` | Max open issues scored |
| `duplicate_detection.max_items` | `100` | Max proposed items per request |
| `duplicate_detection.extra_stop_words` | `""` | Additive stop words; never raises a score |
| `model_suggestion.enabled` | `true` | Suggest a model + thinking level per issue |
| `model_suggestion.data_url` | `"https://cursor.com/cursorbench"` | CursorBench source refreshed into the cache |
| `model_suggestion.cache_ttl_days` | `7` | Days before cached model data is stale |
