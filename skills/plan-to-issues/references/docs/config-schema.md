<!-- Generated from /docs/config-schema.md. Do not edit. Edit source and run ./scripts/build.sh. -->
# `.idd.yml` Configuration Schema

> **Per-skill excerpt (generated).** Only the configuration sections this skill reads are reproduced here: `compaction`, `platform`. The complete schema — every section and the full defaults table — is at [config-schema.md](https://github.com/luongnv89/idd/blob/main/docs/config-schema.md).

IDD Stack works with zero configuration — every setting has a default. With no `.idd.yml`, the first-run hint is shown:

```
○ First run — using default config. Run /init-idd to customize.
```

Place `.idd.yml` at the repo root to customize behavior.

### Config Loading Flow

Loaded **once** at skill start. Valid file → use it. Invalid → stop with the
line-numbered *Validation* errors. Absent → defaults + first-run hint above.
`.idd.yml` is config; `.idd/` is runtime state; built-ins are fallback.

## Core Fields

Everyday knobs: `platform`, `issue.auto_normalize`, `resolve.branch_prefix`, `resolve.auto_test`, `resolve.test_timeout`, `triage.stale_threshold_days`, `autopilot.mode`, `autopilot.review_cycles`, `autopilot.skip_labels`, `review.require_acceptance_criteria_check`. Below is the advanced reference.

## Full Schema (advanced reference)

```yaml
# Tracker platform driver
# Type: string
# Values: "github" — the only implemented driver (see references/docs/platform-github.md);
#         a new driver becomes valid here once its docs/platform-<name>.md exists
# Default: "github"
platform: github

# Context-threshold check + re-entry rules. Contract:
# https://github.com/luongnv89/idd/blob/main/docs/context-threshold.md
compaction:
  # Type: boolean. Default: true. false = behave as before.
  enabled: true
  # Type: integer 1-99 per skill, % of context remaining (else exit 3).
  # Default: as listed (auto-pilot 15, every other skill 40).
  threshold:
    auto-pilot: 15
    issue-resolver: 40
    issue-pr-review: 40
    issue-analysis: 40
    issue-creator: 40
    issue-triage: 40
    plan-to-issues: 40
    init-idd: 40
```

## `.idd/` Directory

Repo-root state beside `.idd.yml`, created on first use.

| File | Written by | Description |
|------|-----------|-------------|
| `.idd/triage.json` | `/issue-triage`, `/auto-pilot` | Cached triage: priorities, deps, order, history |
| `.idd/analysis-<N>.json` | `/issue-analysis` | Deep analysis of issue #N |
| `.idd/runs.jsonl` | `/issue-resolver`, `/auto-pilot` | Append-only run log (one line per issue) |
| `.idd/run-state.json`, `run.lock`, `last-run-report.md` | `/auto-pilot`; `/issue-resolver` (`borrowed_skills` only) | Resume state, lock, report |

> **Not in `.idd/`:** the model-suggestion cache is **user-level** (`~/.cache/idd/`, all repos).

**Conventions:**
- Create via `mkdir -p`
- Re-triage overwrites `triage.json`; `/auto-pilot` updates after a merge
- `runs.jsonl` is **append-only**; absence non-fatal
- **Carve-out** — commit the directory (project state, not secrets), never the three machine-local files: gitignored, `gi-state.py` the only writer, `--dry-run` mutates nothing

### `.idd/runs.jsonl` — run log

Field set, append rules, and the single-writer / `--no-run-log` convention in [run-log-schema.md](https://github.com/luongnv89/idd/blob/main/docs/run-log-schema.md).

## Validation

Config is validated at every skill start; errors include line numbers:

```
✗ Invalid config: .idd.yml

  Line 8: issue.template must be "default" or a valid directory path
  Line 15: resolve.test_timeout must be between 30 and 3600

  To fix:  edit .idd.yml and correct the values above
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```

Each `compaction.threshold.<skill>` must be an integer from 1 to 99 and `compaction.enabled` a boolean.

## Defaults Table

| Setting | Default | Description |
|---------|---------|-------------|
| `platform` | `github` | Tracker platform driver — `github` is the only implemented driver (references/docs/platform-github.md) |
| `compaction.enabled` | `true` | Context-threshold check and re-entry rules; `false` = behave as before |
| `compaction.threshold` · `auto-pilot` | `15` | % of context remaining (1-99) at or below which the skill prompts compaction |
| `compaction.threshold` · every other skill | `40` | Same, one key per skill |
