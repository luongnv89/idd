<!-- Generated from /docs/config-schema.md. Do not edit. Edit source and run ./scripts/build.sh. -->
# `.gitissue.yml` Configuration Schema

> **Per-skill excerpt (generated).** Only the configuration sections this skill reads are reproduced here: `platform`, `triage`. The complete schema — every section and the full defaults table — is at [config-schema.md](https://github.com/luongnv89/idd/blob/main/docs/config-schema.md).

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
| `triage.stale_threshold_days` | `14` | Stale issue threshold |
| `triage.auto_priority` | `true` | Auto-suggest priorities |
| `triage.include_closed` | `false` | Exclude closed from triage |
| `triage.scan_timeout_per_issue` | `30` | Max seconds per issue scan |
