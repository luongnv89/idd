<!-- Generated from /docs/config-schema.md. Do not edit. Edit source and run ./scripts/build.sh. -->
# `.gitissue.yml` Configuration Schema

> **Per-skill excerpt (generated).** Only the configuration sections this skill reads are reproduced here: `issue`, `platform`, `projects`, `resolve`, `security`. The complete schema — every section and the full defaults table — is at [config-schema.md](https://github.com/luongnv89/idd/blob/main/docs/config-schema.md).

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

# GitHub Projects board sync settings
# See https://github.com/luongnv89/idd/blob/main/docs/github-projects-sync.md
# for the full integration reference
projects:
  # Enable automatic project board status sync
  # Type: boolean
  # Default: false
  # When false, all project sync operations are silently skipped
  sync_enabled: false

  # Explicit project number (from the project URL)
  # Type: integer or null
  # Default: null (auto-detect first linked project)
  # Set this if the repo has multiple linked projects
  project_number: null

  # Name of the Status field on the project board
  # Type: string
  # Default: "Status"
  # Must match the exact field name on the project (case-sensitive)
  status_field: "Status"

  # Map of internal status keys to project board option values
  # Type: object
  # Each value must match an option name in the Status field
  status_map:
    # Status for newly created issues
    # Type: string
    # Default: "Todo"
    todo: "Todo"

    # Status when work starts (branch created)
    # Type: string
    # Default: "In Progress"
    in_progress: "In Progress"

    # Status when PR is created
    # Type: string
    # Default: "Done"
    done: "Done"

# Pre-commit security scan settings (used by every skill that commits or pushes)
# The built-in rules always apply; these keys only *extend* them. There is no
# key that disables a rule — a scan a repository can switch off is not a gate.
# The rules themselves live in the pre-commit security conventions reference.
security:
  # Extra regex ORed onto the built-in secret-bearing *filename* pattern
  # Type: string (a Python regex; empty means built-ins only)
  # Default: ""
  # Example: "(^|/)service-account\\.json$"
  extra_secret_file_pattern: ""

  # Extra regex ORed onto the built-in real-API-key *value* pattern
  # Type: string (a Python regex; empty means built-ins only)
  # Default: ""
  # Prefer prefix + length over identifier + value — the latter false-positives
  # on docstrings and tests, which is how a scan gets disabled in practice
  # Example: "acme_live_[A-Za-z0-9]{24,}"
  extra_secret_value_pattern: ""

  # Paths matching this regex are skipped entirely (fixtures, golden files)
  # Type: string (a Python regex; empty means scan everything)
  # Default: ""
  # Every path it excludes is a path no rule can block — keep it narrow
  # Example: "^tests/fixtures/"
  allow_pattern: ""

  # Warn (never block) when a scanned file exceeds this size, in megabytes
  # Type: integer
  # Default: 10
  # Minimum: 1
  max_file_size_mb: 10
```

## `.gitissue/` Directory

The `.gitissue/` directory at the repo root stores persistent state generated by gitissue skills. It sits alongside `.gitissue.yml` (configuration) and is created automatically on first use.

| File | Written by | Description |
|------|-----------|-------------|
| `.gitissue/triage.json` | `/issue-triage`, `/auto-pilot` | Cached triage analysis (JSON schema v1) — issue priorities, dependencies, execution order, and history |
| `.gitissue/analysis-<N>.json` | `/issue-analysis` | Deep analysis of issue #N — affected files, root cause, implementation options, complexity, and risk |
| `.gitissue/runs.jsonl` | `/issue-resolver`, `/auto-pilot` | Append-only run log — exactly one JSON line per processed issue; cross-run telemetry for monitoring. Single-writer rules: the run-log section below. |

> **Not in `.gitissue/`:** `/issue-creator`'s model-suggestion cache is
> **skill-level**, not per-repo — `model-data-<date>.json` in the installed skill
> folder, one per machine, seeded from the bundle and refreshed via
> `--refresh-model-data`. A legacy `.gitissue/model-data.json` is ignored and may
> be deleted. See `src/skills/issue-creator/references/model-suggestion.md`.

**Conventions:**
- Skills create `.gitissue/` via `mkdir -p` if it doesn't exist
- JSON files are formatted for readable git diffs
- A full re-triage overwrites `triage.json` entirely (not append); `/auto-pilot` may instead update it in place after a merge, removing the resolved issue and appending one history entry
- `runs.jsonl` is **append-only** — skills add one line per run and never edit prior lines; its absence or deletion is non-fatal
- The directory should be committed to the repo (it contains project state, not secrets)

### `.gitissue/runs.jsonl` — run log (monitoring)

Field set, append rules, and the single-writer / `--no-run-log` suppression
convention live in
[run-log-schema.md](https://github.com/luongnv89/idd/blob/main/docs/run-log-schema.md)
— read that document instead of this one.

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
| `resolve.ui_review.browser_review` | `"ask"` | Browser (screenshot) UI review mode; code UI review is auto-detected and always runs |
| `projects.sync_enabled` | `false` | Enable project board sync |
| `projects.project_number` | `null` | Explicit project number (null = auto-detect) |
| `projects.status_field` | `"Status"` | Name of the Status field on the board |
| `projects.status_map.todo` | `"Todo"` | Status for new issues |
| `projects.status_map.in_progress` | `"In Progress"` | Status when work starts |
| `projects.status_map.done` | `"Done"` | Status when PR is created |
| `security.extra_secret_file_pattern` | `""` | Extra regex ORed onto the built-in secret-bearing filename pattern |
| `security.extra_secret_value_pattern` | `""` | Extra regex ORed onto the built-in real-API-key value pattern |
| `security.allow_pattern` | `""` | Paths matching this regex are skipped entirely — every exclusion is a path no rule can block |
| `security.max_file_size_mb` | `10` | Warn (never block) above this file size without Git LFS |
