<!-- Generated from /docs/config-schema.md. Do not edit. Edit source and run ./scripts/build.sh. -->
# `.gitissue.yml` Configuration Schema

> **Per-skill excerpt (generated).** Only the configuration sections this skill reads are reproduced here: `issue`, `platform`, `projects`, `resolve`, `security`. The complete schema — every section and the full defaults table — is at [config-schema.md](https://github.com/luongnv89/idd/blob/main/docs/config-schema.md).

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

# Resolution pipeline settings
resolve:
  # Approval gate for the plan phase
  # Type: string
  # Values: "auto" | "comment-and-wait"
  # Default: "auto"
  # "auto": proceed immediately after planning
  # "comment-and-wait": show plan and wait for user approval
  # Note: with resolve.adaptive_effort: true (default), a light-profile (trivial
  #   XS/S) issue proceeds on a direct minimal plan without the option prompt —
  #   it produces no 3-option comparison to wait on. Set adaptive_effort: false
  #   to force the approval wait on every issue regardless of complexity.
  approval_gate: auto

  # Branch naming prefix
  # Type: string
  # Default: "auto"
  # "auto" uses type-based prefixes: fix/, feat/, refactor/, docs/, test/, chore/
  # Branch format: {type}/{issue_number}-{short-description}
  # Examples: fix/42-mobile-auth-redirect, feat/15-add-dark-mode
  # Set a custom string (e.g., "issue-") to override type-based naming
  branch_prefix: "auto"

  # Run tests before creating PR
  # Type: boolean
  # Default: true
  auto_test: true

  # Abort verify phase after N seconds
  # Type: integer
  # Default: 300 (5 minutes)
  # Minimum: 30
  # Maximum: 3600
  test_timeout: 300

  # (Removed) pr_auto_link — deprecated. SPEC §5.1 requires the PR body to open with
  # `Closes #N`; issue-resolver always includes that line unconditionally.

  # Warn if resolve produces more than N commits
  # Type: integer
  # Default: 10
  # Minimum: 1
  max_commits: 10

  # Max QA review-fix cycles during resolve Step 4
  # Type: integer
  # Default: 5
  # Minimum: 1
  # Maximum: 10
  qa_max_cycles: 5

  # Scale the resolve pipeline to each issue's complexity (adaptive effort).
  # Type: boolean
  # Default: true
  # When true, trivial issues (pre-work Effort band XS/S, asserted) take a
  # lighter, faster, lower-token path: a lighter Research step (the
  # already-resolved safety check still runs), the 3-option synthesis in Plan is
  # skipped for a direct minimal plan, the propose-relevant-skills sub-step is
  # skipped, and QA is capped at 1 cycle. The Decision Record and Acceptance
  # Criteria Verification table are always emitted regardless. Complex or
  # ambiguous issues (M/L/XL, low-confidence, or no band) keep the full pipeline.
  # When false, every issue gets the full pipeline as before — the profile is
  # pinned to "full". The chosen profile is surfaced on the [0/5] tracker line
  # and in the run log's `profile` field. See
  # https://github.com/luongnv89/idd/blob/main/docs/agent-model-effort.md
  # (Complexity → pipeline profile).
  adaptive_effort: true

  # Borrow catalogued-but-not-installed skills for one task (issue #309).
  # Type: boolean. Default: false (installed-only). true installs selected
  # missing skills, records {name, origin} in run-state, uninstalls only
  # origin: borrowed; auto never installs unless this key is true.
  borrow_skills: false

  # UI/UX review settings (Step 4 — QA)
  # Code-level UI review is auto-detected per issue and always runs when UI
  # work is present; it needs no flag and runs in any environment (including
  # headless servers with no display). Only the optional browser (screenshot)
  # review is gated here.
  ui_review:
    # Browser (screenshot) review mode
    # Type: string enum
    # Values: "false" (never) | "ask" (prompt interactive, skip in auto) | "true" (always attempt)
    # Default: "ask"
    # Note: when enabled it still skips (fail-soft to code-only) if no app is
    #       running/reachable or capture is unsafe — it never blocks code review.
    browser_review: "ask"

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

# Pre-commit scan extensions (built-ins always apply; no key disables a rule).
# Rules live in the pre-commit security conventions reference.
security:
  # Type: string (Python regex; "" = built-ins only). Default: ""
  # Example: "(^|/)service-account\\.json$"
  extra_secret_file_pattern: ""
  # Type: string (Python regex; "" = built-ins only). Default: ""
  # Prefer prefix+length. Example: "acme_live_[A-Za-z0-9]{24,}"
  extra_secret_value_pattern: ""
  # Type: string (Python regex; "" = scan all). Default: "". Keep narrow.
  # Example: "^tests/fixtures/"
  # Suppresses SCANNING, not findings: a matching path reaches no rule at all.
  # This file is repo-controlled, so a skill reviewing a branch it does not
  # control passes --policy-ref to read security.* from a trusted ref, and then
  # ignores this value. That protection is opt-in and travels with the call
  # site: a review that asserts policy_source cannot be weakened by editing
  # this key, while any caller that omits --policy-ref still honours it.
  allow_pattern: ""
  # Type: integer. Default: 10. Minimum: 1. Warn (never block) above this MB.
  max_file_size_mb: 10
```

## `.gitissue/` Directory

Repo-root state beside `.gitissue.yml`, created on first use.

| File | Written by | Description |
|------|-----------|-------------|
| `.gitissue/triage.json` | `/issue-triage`, `/auto-pilot` | Cached triage: priorities, deps, order, history |
| `.gitissue/analysis-<N>.json` | `/issue-analysis` | Deep analysis of issue #N |
| `.gitissue/runs.jsonl` | `/issue-resolver`, `/auto-pilot` | Append-only run log (one line per issue) |
| `.gitissue/run-state.json`, `run.lock`, `last-run-report.md` | `/auto-pilot`; `/issue-resolver` (`borrowed_skills` only) | Resume state, lock, report |

> **Not in `.gitissue/`:** the model-suggestion cache is **skill-level** (`model-data-<date>.json` in the installed skill, all repos).

**Conventions:**
- Create via `mkdir -p`
- Re-triage overwrites `triage.json`; `/auto-pilot` updates after a merge
- `runs.jsonl` is **append-only**; absence non-fatal
- **Carve-out** — commit the directory (project state, not secrets), never the three machine-local files: gitignored, `gi-state.py` the only writer, `--dry-run` mutates nothing

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
| `resolve.approval_gate` | `auto` | No approval wait |
| `resolve.branch_prefix` | `auto` | Type-based branch prefix (fix/, feat/, etc.) |
| `resolve.auto_test` | `true` | Run tests before PR |
| `resolve.test_timeout` | `300` | 5 minute test timeout |
| *(removed)* `resolve.pr_auto_link` | — | Deprecated; `Closes #N` is unconditional per SPEC §5.1 |
| `resolve.max_commits` | `10` | Max commits warning |
| `resolve.qa_max_cycles` | `5` | Max QA review-fix cycles during resolve Step 4 |
| `resolve.adaptive_effort` | `true` | Scale the resolve pipeline to issue complexity — trivial issues (Effort XS/S) take a lighter path (lighter Research, skip 3-option Plan, skip propose-skills, QA capped at 1 cycle); `false` pins every issue to the full pipeline, and turns off #256's caller context: the payload gate, `triage_context`, last-green test reuse ([agent-model-effort.md](https://github.com/luongnv89/idd/blob/main/docs/agent-model-effort.md)) |
| `resolve.borrow_skills` | `false` | Off by default. true: full catalog; install selected missing, record {name, origin} in run-state, uninstall only `origin: borrowed`; auto never installs unless true |
| `resolve.ui_review.browser_review` | `"ask"` | Browser (screenshot) UI review mode; code UI review is auto-detected and always runs |
| `projects.sync_enabled` | `false` | Enable project board sync |
| `projects.project_number` | `null` | Explicit project number (null = auto-detect) |
| `projects.status_field` | `"Status"` | Name of the Status field on the board |
| `projects.status_map.todo` | `"Todo"` | Status for new issues |
| `projects.status_map.in_progress` | `"In Progress"` | Status when work starts |
| `projects.status_map.done` | `"Done"` | Status when PR is created |
| `security.extra_secret_file_pattern` | `""` | Extra regex ORed onto the built-in secret-bearing filename pattern |
| `security.extra_secret_value_pattern` | `""` | Extra regex ORed onto the built-in real-API-key value pattern |
| `security.allow_pattern` | `""` | Paths matching this regex are skipped entirely — every exclusion is a path no rule can block. Repo-controlled, so a review of a branch you do not control reads it from a trusted ref instead (`--policy-ref`), never from the branch under review |
| `security.max_file_size_mb` | `10` | Warn (never block) above this file size without Git LFS |
