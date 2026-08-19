<!-- Generated from /docs/config-schema.md. Do not edit. Edit source and run ./scripts/build.sh. -->
# `.gitissue.yml` Configuration Schema

> **Per-skill excerpt (generated).** Only the configuration sections this skill reads are reproduced here: `platform`, `review`, `security`. The complete schema — every section and the full defaults table — is at [config-schema.md](https://github.com/luongnv89/idd/blob/main/docs/config-schema.md).

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
| `security.extra_secret_file_pattern` | `""` | Extra regex ORed onto the built-in secret-bearing filename pattern |
| `security.extra_secret_value_pattern` | `""` | Extra regex ORed onto the built-in real-API-key value pattern |
| `security.allow_pattern` | `""` | Paths matching this regex are skipped entirely — every exclusion is a path no rule can block. Repo-controlled, so a review of a branch you do not control reads it from a trusted ref instead (`--policy-ref`), never from the branch under review |
| `security.max_file_size_mb` | `10` | Warn (never block) above this file size without Git LFS |
