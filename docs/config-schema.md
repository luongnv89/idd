# `.gitissue.yml` Configuration Schema

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
# Values: "github" — the only implemented driver (see docs/platform-github.md);
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

# PR review settings (used by /issue-pr-review and /auto-pilot)
review:
  # Max review-fix cycles before stopping
  # Type: integer
  # Default: 3
  # Minimum: 1
  # Maximum: 10
  max_cycles: 3

  # Scale review depth to each PR's complexity (adaptive depth).
  # Type: boolean
  # Default: true
  # When true, /issue-pr-review derives a pre-work complexity signal from the PR
  # (diff size, files-changed, labels, and the linked issue's Effort band — the
  # fuller of any that disagree) and, for a trivial PR, caps the review-fix loop
  # at 1 cycle and skips optional passes. The acceptance-criteria and
  # traceability hard-blocks always run at full strength. Complex or ambiguous
  # PRs keep the full max_cycles depth. When false, every PR gets full review
  # depth as before — the profile is pinned to "full", and the QA handoff gate
  # is disabled too, so a resolver-marked PR also gets the full pipeline. The
  # chosen depth is surfaced on the [1/7] tracker line. See
  # https://github.com/luongnv89/idd/blob/main/docs/agent-model-effort.md
  # (Complexity → pipeline profile).
  adaptive_depth: true

  # Auto-merge PR when clean (overridden to true in --auto mode)
  # Type: boolean
  # Default: false
  auto_merge: false

  # Only report issues at or above this confidence level (0-100)
  # Type: integer
  # Default: 80
  # Minimum: 50
  # Maximum: 100
  confidence_threshold: 80

  # Run tests as part of the review pipeline
  # Type: boolean
  # Default: true
  run_tests: true

  # Check CI status as part of the review pipeline
  # Type: boolean
  # Default: true
  check_ci: true

  # Seconds between CI status polls
  # Type: integer
  # Default: 30
  # Minimum: 10
  # Maximum: 120
  ci_poll_interval: 30

  # Abort CI polling after N seconds
  # Type: integer
  # Default: 600 (10 minutes)
  # Minimum: 60
  # Maximum: 3600
  ci_timeout: 600

  # Abort test suite after N seconds
  # Type: integer
  # Default: 300 (5 minutes)
  # Minimum: 30
  # Maximum: 3600
  test_timeout: 300

  # Allow note findings and partial dimensions after all fixables are resolved.
  # Type: boolean
  # Default: true
  # When false, require every enabled review dimension to pass with no notes;
  # partial/note findings remain blockers for a clean result and auto-merge.
  soft_pass: true

  # Run per-criterion acceptance-criteria verification against the linked issue.
  # Type: boolean
  # Default: true
  # When true, /issue-pr-review parses the linked issue's `## Acceptance Criteria`
  # and reports each criterion as pass/fail/unverified; any `fail` blocks soft-pass.
  # When false, the acceptance_criteria dimension is reported as `pass` with a
  # "verification disabled" note and never blocks. Default true preserves the
  # contract from issue #36.
  require_acceptance_criteria_check: true

  # Run the four traceability checks against the PR body and commit history.
  # Type: boolean
  # Default: true
  # When true, /issue-pr-review verifies `Closes #N`, commit references,
  # Decision Record presence, and Acceptance Criteria Verification block; the
  # missing-`Closes #N` case blocks soft-pass even on green tests/CI.
  # When false, the traceability dimension is reported as `pass` with a
  # "verification disabled" note and never blocks. Default true preserves the
  # contract from issue #36.
  require_traceability_check: true

  # PR labels that exempt a PR from the `Closes #N` hard-fail (check 1 only).
  # Type: list of strings (label names — exact, case-sensitive match)
  # Default: ["refactor", "chore"]
  # When the PR carries any label in this list, /issue-pr-review skips the
  # `Closes #N` check and reports `traceability: pass — exempt`. The other
  # three traceability checks (commit reference, Decision Record, Acceptance
  # Criteria Verification block) still run and report `partial` if absent.
  # Set to [] to disable label-based exemption (see also traceability_exempt_pattern).
  traceability_exempt_labels:
    - refactor
    - chore

  # PR-body pattern that exempts a PR from the `Closes #N` hard-fail (check 1 only).
  # Type: string (regex, multiline-anchored, case-insensitive)
  # Default: "^\\s*Type:\\s*(refactor|chore)\\s*$"
  # When the PR body contains a line matching this pattern, /issue-pr-review
  # skips the `Closes #N` check and reports `traceability: pass — exempt`. The
  # other three traceability checks still run.
  # Set to "" to disable pattern-based exemption. Setting both this and
  # traceability_exempt_labels to empty restores strict issue #36 behavior.
  traceability_exempt_pattern: "^\\s*Type:\\s*(refactor|chore)\\s*$"

  # UI/UX review settings (Step 3 — Review)
  # Code-level UI review is auto-detected per PR and always runs when UI work is
  # present; it needs no flag and runs in any environment (including headless
  # servers with no display). Only the optional browser (screenshot) review is
  # gated here.
  ui_review:
    # Browser (screenshot) review mode
    # Type: string enum
    # Values: "false" (never) | "ask" (prompt interactive, skip in auto) | "true" (always attempt)
    # Default: "ask"
    # Note: when enabled it still skips (fail-soft to code-only) if no app is
    #       running/reachable or capture is unsafe — it never blocks code review.
    browser_review: "ask"

# Auto-pilot settings (used by /auto-pilot)
autopilot:
  # Merge mode — controls when /auto-pilot is allowed to merge PRs.
  # Type: string
  # Values: "conservative" | "balanced" | "aggressive"
  # Default: "balanced"
  # "balanced":     auto-merge clean PRs only. Unresolved issues create a follow-up
  #                 and leave the PR open. Recommended default for most projects.
  # "conservative": create PR, run review-fix cycles, leave PR open. Never auto-merges.
  # "aggressive":   auto-merge clean PRs AND, when merge_partial=true, merge partial
  #                 PRs with a follow-up issue. Documented as risky; opt-in only.
  # When set, this field is authoritative — autopilot.auto_merge is ignored.
  mode: balanced

  # Allow merging PRs that still have unresolved fixable review issues.
  # Type: boolean
  # Default: false
  # Only honored when mode is "aggressive"; ignored otherwise. Both keys must be
  # set explicitly to reach partial-merge behavior — there is no casual opt-in.
  merge_partial: false

  # Max iterations (issues to process) before stopping
  # Type: integer
  # Default: 10
  # Minimum: 1
  # Maximum: 50
  max_iterations: 10

  # Resolver concurrency, integer 1..8 (default 1). Only independent resolves
  # overlap; review, merge and shared writes remain serialized.
  max_parallel: 1

  # Max review-fix cycles per PR (overrides review.max_cycles in subagent prompt)
  # Type: integer
  # Default: 3
  # Minimum: 1
  # Maximum: 10
  review_cycles: 3

  # Auto-merge PRs after review passes
  # Type: boolean
  # Default: true
  # LEGACY: kept for backwards compatibility. Ignored when autopilot.mode is set.
  # When mode is unset and auto_merge is not explicitly present in the file, effective mode is balanced.
  # When mode is unset but auto_merge is explicitly present, legacy interpretation applies:
  #   auto_merge: true  ≈ mode: aggressive + merge_partial: true (preserves prior 2.1.x behavior)
  #   auto_merge: false ≈ mode: conservative
  auto_merge: true

  # Pause loop on failure instead of skipping to next issue
  # Type: boolean
  # Default: false (skip failed issues and continue; set true to halt the loop on failure)
  pause_on_failure: false

  # Labels that cause an issue to be skipped
  # Type: array of strings
  # Default: ["wontfix", "blocked", "do-not-merge"]
  skip_labels:
    - wontfix
    - blocked
    - do-not-merge

  # Labels that mark an issue as critical (processed first)
  # Type: array of strings
  # Default: ["critical", "priority:critical"]
  critical_labels:
    - critical
    - priority:critical

  # Respect "Depends on #N" / "Blocked by #N" markers in issue bodies (see
  # https://github.com/luongnv89/idd/blob/main/docs/idd-methodology.md,
  # Issue Dependencies, for the syntax): never merge a PR whose dependencies
  # are unmerged. The run is not paused; disabling skips the merge gate.
  # Type: boolean
  # Default: true
  respect_dependencies: true

  # Reuse .gitissue/triage.json when it is younger than this many minutes AND
  # no commit landed since. Type: integer. Default: 60. 0 disables reuse.
  triage_cache_max_age_minutes: 60
  # Force a full re-triage every Nth iteration (1-based i % N == 0); a pick
  # miss forces one regardless. Type: integer. Default: 0 (never).
  retriage_every: 0

  # Quarantine an issue after this many consecutive failed runs by applying
  # quarantine_label, which the effective skip_labels set then skips until a
  # human removes it. Type: integer. Default: 3. 0 disables.
  quarantine_after: 3
  quarantine_label: "auto-pilot-quarantined"
  # Wall-clock budget for one run, from the run state's started_at; it also
  # caps a rate-limit pause. Type: integer minutes. Default: 0 (unbounded).
  max_runtime_minutes: 0

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

### Config Section Map

```mermaid
graph TD
    R[".gitissue.yml"] --> P["platform<br/>(driver: github)"]
    R --> I["issue"]
    R --> RS["resolve"]
    R --> RV["review"]
    R --> AP["autopilot"]
    R --> T["triage"]
    R --> A["analysis"]
    R --> PR["projects"]
    R --> DD["duplicate_detection"]
    R --> MS["model_suggestion"]
    R --> SEC["security"]

    I --> I1["auto_normalize"]
    I --> I2["template"]
    I --> I3["labels_auto_suggest"]
    I --> I4["normalize_comment"]

    RS --> R1["approval_gate"]
    RS --> R2["branch_prefix"]
    RS --> R3["auto_test"]
    RS --> R4["test_timeout"]
    RS --> R5["pr_auto_link"]
    RS --> R6["max_commits"]
    RS --> R7["qa_max_cycles"]
    RS --> R8["adaptive_effort"]
    RS --> R9["borrow_skills"]

    RV --> RV1["max_cycles"]
    RV --> RV14["adaptive_depth"]
    RV --> RV2["auto_merge"]
    RV --> RV3["confidence_threshold"]
    RV --> RV4["run_tests"]
    RV --> RV5["check_ci"]
    RV --> RV6["ci_poll_interval"]
    RV --> RV7["ci_timeout"]
    RV --> RV8["test_timeout"]
    RV --> RV9["soft_pass"]
    RV --> RV10["require_acceptance_criteria_check"]
    RV --> RV11["require_traceability_check"]
    RV --> RV12["traceability_exempt_labels"]
    RV --> RV13["traceability_exempt_pattern"]

    AP --> AP0["mode"]
    AP --> AP00["merge_partial"]
    AP --> AP1["max_iterations"]
    AP --> AP01["max_parallel"]
    AP --> AP2["review_cycles"]
    AP --> AP3["auto_merge<br/>(legacy)"]
    AP --> AP4["pause_on_failure"]
    AP --> AP5["skip_labels"]
    AP --> AP6["critical_labels"]

    T --> T1["stale_threshold_days"]
    T --> T2["auto_priority"]
    T --> T3["include_closed"]
    T --> T4["scan_timeout_per_issue"]

    A --> A1["max_files"]
    A --> A2["trace_depth"]
    A --> A3["scan_timeout"]

    PR --> PR1["sync_enabled"]
    PR --> PR2["project_number"]
    PR --> PR3["status_field"]
    PR --> PR4["status_map"]

    DD --> DD1["weights"]
    DD --> DD2["high_threshold / medium_threshold"]
    DD --> DD3["token + detection limits"]
    DD --> DD4["extra_stop_words"]

    MS --> MS1["enabled"]
    MS --> MS2["data_url"]
    MS --> MS3["cache_ttl_days"]

    SEC --> SEC1["extra_secret_file_pattern"]
    SEC --> SEC2["extra_secret_value_pattern"]
    SEC --> SEC3["allow_pattern"]
    SEC --> SEC4["max_file_size_mb"]

    style R fill:#4CAF50,color:#fff
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
| `platform` | `github` | Tracker platform driver — `github` is the only implemented driver (docs/platform-github.md) |
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
| `review.max_cycles` | `3` | Max review-fix cycles |
| `review.adaptive_depth` | `true` | Scale review depth to PR complexity — a trivial PR caps the review-fix loop at 1 cycle and skips optional passes (AC + traceability hard-blocks still run); `false` pins every PR to full depth and disables the QA handoff gate and #256's CI verdict gate too ([agent-model-effort.md](https://github.com/luongnv89/idd/blob/main/docs/agent-model-effort.md)) |
| `review.auto_merge` | `false` | Auto-merge PR when clean |
| `review.confidence_threshold` | `80` | Min confidence level for issues |
| `review.run_tests` | `true` | Run tests during review |
| `review.check_ci` | `true` | Check CI status during review |
| `review.ci_poll_interval` | `30` | Seconds between CI polls |
| `review.ci_timeout` | `600` | CI polling timeout |
| `review.test_timeout` | `300` | Review test timeout |
| `review.soft_pass` | `true` | Allow note findings and partial dimensions after fixables resolve; `false` requires no notes and all enabled dimensions pass |
| `review.require_acceptance_criteria_check` | `true` | Run per-criterion acceptance-criteria verification; `fail` blocks soft-pass |
| `review.require_traceability_check` | `true` | Run the four traceability checks; missing `Closes #N` blocks soft-pass |
| `review.traceability_exempt_labels` | `["refactor", "chore"]` | PR labels that exempt a PR from the `Closes #N` hard-fail (check 1 only; other three checks still run) |
| `review.traceability_exempt_pattern` | `"^\\s*Type:\\s*(refactor\|chore)\\s*$"` | Regex (multiline, case-insensitive) matched against PR body for exemption from check 1 |
| `review.ui_review.browser_review` | `"ask"` | Browser (screenshot) UI review mode; code UI review is auto-detected and always runs |
| `autopilot.mode` | `balanced` | Merge mode: `balanced` (auto-merge clean PRs), `conservative` (never merge), `aggressive` (merge clean + partial w/ `merge_partial: true`) |
| `autopilot.merge_partial` | `false` | Allow merging PRs with unresolved review issues. Only honored when `mode: aggressive` |
| `autopilot.max_iterations` | `10` | Max issues to process |
| `autopilot.max_parallel` | `1` | Resolver concurrency `1..8`; only independent resolves overlap, and `1` preserves the sequential path |
| `autopilot.review_cycles` | `3` | Max review-fix cycles per PR |
| `autopilot.auto_merge` | `true` | LEGACY — auto-merge PRs after review. Ignored when `autopilot.mode` is set |
| `autopilot.pause_on_failure` | `false` | Skip failed issues and continue (`true` pauses the loop) |
| `autopilot.skip_labels` | `["wontfix", "blocked", "do-not-merge"]` | Labels that skip issues |
| `autopilot.critical_labels` | `["critical", "priority:critical"]` | Labels that prioritize issues |
| `autopilot.respect_dependencies` | `true` | Honor `Depends on #N` / `Blocked by #N` markers — never merge a PR whose dependencies are unmerged; the PR is left open (`blocked_by_dependency`) and the loop continues |
| `autopilot.triage_cache_max_age_minutes` | `60` | Max age of a reusable `triage.json` (also requires no commit since); `0` disables reuse |
| `autopilot.retriage_every` | `0` | Force a full re-triage every Nth iteration (`0` = never) |
| `autopilot.quarantine_after` | `3` | Consecutive failed runs before an issue is labelled and skipped until a human removes the label (`0` disables) |
| `autopilot.quarantine_label` | `"auto-pilot-quarantined"` | The quarantine label; honored through the effective `skip_labels` set |
| `autopilot.max_runtime_minutes` | `0` | Wall-clock budget for one run in minutes, from the run state's `started_at`; at the budget the loop stops cleanly (`0` = unbounded) |
| `triage.stale_threshold_days` | `14` | Stale issue threshold |
| `triage.auto_priority` | `true` | Auto-suggest priorities |
| `triage.include_closed` | `false` | Exclude closed from triage |
| `triage.scan_timeout_per_issue` | `30` | Max seconds per issue scan |
| `analysis.max_files` | `30` | Max files to read during analysis |
| `analysis.trace_depth` | `3` | Import trace depth levels |
| `analysis.scan_timeout` | `120` | Max seconds for codebase scan |
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
| `security.extra_secret_file_pattern` | `""` | Extra regex ORed onto the built-in secret-bearing filename pattern |
| `security.extra_secret_value_pattern` | `""` | Extra regex ORed onto the built-in real-API-key value pattern |
| `security.allow_pattern` | `""` | Paths matching this regex are skipped entirely — every exclusion is a path no rule can block. Repo-controlled, so a review of a branch you do not control reads it from a trusted ref instead (`--policy-ref`), never from the branch under review |
| `security.max_file_size_mb` | `10` | Warn (never block) above this file size without Git LFS |
