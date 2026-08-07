---
name: issue-pr-review
description: "Review a PR end-to-end with CI checks, fix cycles, and optional auto-merge. Use for PR review, cleanup, or readiness checks. Don't use for creating PRs, raw issue analysis, or non-PR code review."
license: MIT
compatibility: "Requires git and GitHub CLI (gh) with authentication. Self-contained — uses shared agents from shared/agents/."
effort: high
metadata:
  version: 2.5.0
  author: Luong NGUYEN <luongnv89@gmail.com>
---

# /issue-pr-review [PR_NUMBER]

Review a PR end-to-end — analyze, test, fix, check CI, repeat until clean.

## Invocation

| Invocation | Mode | What happens |
|------------|------|--------------|
| `/issue-pr-review <N>` | interactive | Review, fix, and repeat until clean; report findings (no auto-merge) |
| `/issue-pr-review <N> --auto` | auto-pilot | Review, fix, and auto-merge when clean |
| `/issue-pr-review <N> --auto --no-merge` | auto-pilot | Review, fix, and report — skip auto-merge (use when another agent owns the merge step) |
| `/issue-pr-review` | detect | Auto-detect PR for current branch |
| `/issue-pr-review --review-only` | read-only | Review and report, never fix or merge (see *Review-only mode*) |

The `--auto` flag is set automatically when invoked by `/auto-pilot`. In auto mode, export `IDD_AUTO_MODE=1` before any shell snippet that consults it — the pre-commit security scan reads this to switch from prompt-on-warning to log-and-continue (see `docs/pre-commit-security.md`).

The `--no-merge` flag suppresses auto-merge even when `--auto` is set. Use it when another agent (e.g. auto-pilot's Phase 5) owns the merge step — it runs the full review-fix cycle but stops at the summary report without calling `gh pr merge`.

## Prerequisites

1. Confirm git repository: `git rev-parse --git-dir`
2. Confirm `gh` is installed and authenticated: `gh auth status`
3. Confirm the bundled agent prompts and reference files exist (see *Bundled dependency precheck* below)

### Bundled dependency precheck

`/issue-pr-review` is distributed as a self-contained skill — it does not require another gitissue skill to review a PR, but it does require its bundled agent prompts and reference files. Before execution, verify **every** path in the list below exists relative to the skill's directory (the dirname of this SKILL.md). This list is the authoritative guard — keep it complete and independent of the *Additional Resources* navigation index, which exists for human navigation and may list more or fewer files than the runtime requires. If any path is missing, stop immediately, print the error, and do not continue with an inline or guessed reviewer/fixer prompt:

```text
references/agents/code-reviewer.md
references/agents/ui-reviewer.md
references/agents/fixer.md
references/ui-review-mechanics.md
references/prepass-tests-ci-mechanics.md
references/verification-checks.md
references/review-loop-mechanics.md
references/report-templates.md
references/error-messages.md
references/docs/pre-commit-security.md
references/docs/sync-conventions.md
references/docs/idd-methodology.md
references/docs/config-schema.md
references/docs/naming-conventions.md
references/docs/platform-github.md
references/docs/agent-model-effort.md
references/docs/terminal-style.md
references/docs/ui-review.md
references/scripts/gi-config.py
references/scripts/gi-secscan.py
references/scripts/gi-ci-wait.py
references/scripts/gi-issue.py
```


```text
✗ Missing bundled dependency: {missing_file}

  To fix:  asm install https://github.com/luongnv89/idd --skill issue-pr-review
           (or reinstall the full distribution)

  Then restart the agent session and re-run /issue-pr-review.
```

## Repo Sync Before Edits (mandatory)

Before making any fixes, sync with remote using the **stash-first pattern**: if the working tree is dirty, `git stash push -u` first; then `git fetch origin` and `git pull --rebase origin "$branch"`; then `git stash pop` (on pop failure, stop and surface `git stash list` / `git stash show -p stash@{0}` for recovery). The exact script and recovery procedure are in `docs/sync-conventions.md`.

If `origin` is missing or rebase conflicts occur, stop and ask (interactive) or abort with a clear error (auto).

## Configuration

Load config once at skill start: run `python3 shared/scripts/gi-config.py` — two independent requirements, both mandatory. **Working directory:** the repo root, because the script resolves `.gitissue.yml` against the working directory; run it from anywhere else and it exits 0 reporting `config_file: null`/`first_run: true`, silently discarding the repo's real config. **Script path:** relative to this SKILL.md's own directory, *not* to the working directory — resolve it to an absolute path exactly as the *Bundled dependency precheck* resolves its list, and pass that absolute path to `python3`. It prints `{"config": {…dotted keys…}, "config_file": …, "first_run": …}` as JSON on stdout, merging the defaults below with `.gitissue.yml`. Exit 0: use `config`; `first_run: true` means no `.gitissue.yml` was found and every value came from the defaults below. Exit 3: `.gitissue.yml` is invalid — print `✗ Invalid config: .gitissue.yml` followed by the offending key and reason the script reported on stderr, and stop. Script file absent: a bundled dependency is missing, which is a broken install and not a degrade — stop and print the `✗ Missing bundled dependency` block the *Bundled dependency precheck* names. Any other outcome (no `python3`, non-zero exit, unparsable stdout): print `⚠ gi-config unavailable — using the inline defaults below` and instead follow the manual fallback procedure that makes up the rest of this section. That procedure is the *alternative* to this script, never an extra step to run alongside it: on exit 0 the script's `config` is the whole answer and the rest of this section is reference material only. Never re-read the config after this step.

Otherwise, load `.gitissue.yml` once. Defaults (full semantics in `docs/config-schema.md`):
- `review.max_cycles: 3` — 3 LLM cycles suffice once the script pre-pass handles mechanical issues
- `review.adaptive_depth: true` — scale review depth to the PR's complexity (see *Step 1 — Depth gate*). When `false`, every PR gets full-depth review (profile pinned to `full`).
- `review.auto_merge: false` (overridden to `true` in auto mode)
- `review.confidence_threshold: 80`
- `review.run_tests: true`, `review.check_ci: true`
- `review.ci_poll_interval: 30`, `review.ci_timeout: 600`, `review.test_timeout: 300` (seconds)
- `review.soft_pass: true` — when zero `action: fix` issues remain and tests/CI/traceability legs pass, treat remaining `note` findings and `partial` dimensions as report-only. When `false`, strict mode requires no `note` findings and every enabled dimension to be `pass`; remaining notes or partials block a clean result and merge.
- `review.require_acceptance_criteria_check: true` — gate for per-criterion AC verification
- `review.require_traceability_check: true` — gate for the four traceability checks
- `review.traceability_exempt_labels: ["refactor", "chore"]` — labels exempting a PR from the `Closes #N` hard-fail
- `review.traceability_exempt_pattern: "^\\s*Type:\\s*(refactor|chore)\\s*$"` — body-line regex for the same exemption
- `review.ui_review.browser_review: "ask"` — browser (screenshot) review mode (`"false"` | `"ask"` | `"true"`); `"ask"` prompts interactive users, skips in auto mode. Does **not** gate the auto-detected code-level UI review.

UI/UX **code** review needs no config flag — it is auto-detected per PR (*Step 3 — UI/UX Review*); only the optional browser review reads `review.ui_review.browser_review`. The traceability flags default to the values shown, preserving the issue #36 contract; their full semantics (what `false` does, exemption scope) are in `references/verification-checks.md`.

---

## Pipeline Overview

```
  ◆ PR Review Pipeline
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  [1/7] PR Info      ✓ PR #87: fix(auth): resolve redirect (#42), depth: full
  [2/7] Pre-pass     ✓ lint clean, format clean, 17 tests passed
  [3/7] Review       ● analyzing changes...
  [4/7] Test         ✓ 17 tests passed, build ok
  [5/7] CI Status    ✓ all checks passed
  [6/7] Fix          ○ no fixable issues
  [7/7] Report       ✓ PR is clean — ready to merge
```

Step 2 (Pre-pass) runs once before the loop; Steps 3-6 repeat up to `review.max_cycles` times (default: 3); Step 7 runs once at the end. The pipeline minimizes LLM tokens via the zero-token script pre-pass, reviewer/fixer reuse across cycles, `fix`/`note` severity filtering (Step 6), and the soft-pass condition.

---

### Step completion reports

Each step closes with a completion report — `√`/`×` per check plus a
`Result: PASS | PARTIAL | FAIL` line — so "step done" is checkable rather than
asserted. The per-step check names, the `Result` semantics, and the block
format are in `references/report-templates.md` (*Step Completion Reports*) —
**read it now**, before Step 1. A step is not complete until its `Result:`
line is printed.

---

## Step 1 — Get PR Info [1/7]

### Auto-detect PR

If no PR number is given, detect from the current branch:

```bash
gh pr view --json number,title,body,baseRefName,headRefName,state,url,statusCheckRollup
```

If no PR exists for the current branch:
```
✗ No PR found for branch {branch_name}

  To fix:  gh pr create
  Or:      /issue-pr-review <PR_NUMBER>
```

### Fetch PR details

```bash
gh pr view {N} --json number,title,body,baseRefName,headRefName,state,url,labels,reviews,statusCheckRollup,files
```

Extract the PR number/title/URL, base and head branches, linked issue numbers (from `Closes #N` in the body), current CI status, and changed files.

**If PR is closed/merged:**
```
⚠ PR #{N} is already {state}
```
Stop.

```
[1/7] PR Info      ✓ PR #{N}: {title}
                     {files_count} files changed, base: {base_branch}
```

### Checkout PR head branch

Before Step 2 or any other step that runs git against the working tree, check out the PR head branch so pre-pass commits and the fixer operate on `{headRefName}`, not whatever branch was active when the skill was invoked (e.g. `main`):

```bash
gh pr checkout {N}
```

Use `{headRefName}` from Step 1 as `{branch_name}` for sync, commit, and push. Canonical command: `docs/platform-github.md` (*Pull requests* → Checkout PR head branch).

**Bind it to a shell variable — never paste the literal name into a command.** A
head-ref name is chosen by whoever opened the PR, and git permits `` ` ``, `$`,
`(`, `;` and `&` in a ref, so ``fix/1-`id` `` in a shell word runs on the
reviewer's machine; double quotes do not stop `$(…)` or a backtick. Assign once —
`branch_name="$(gh pr view {N} --json headRefName --jq .headRefName)"` — and use
`"$branch_name"` everywhere this skill writes `{branch_name}`. Command-substitution
output is never re-evaluated, so it is inert whatever the name holds. Same rule as
the `gi-secscan` and `gi-branch` call sites, for the one untrusted value this skill
cannot hand to a script.

### Depth gate (select the review profile)

Decide **how deep** this review goes, so a one-line copy fix is not put through
the same full-weight review as a multi-subsystem PR. The mechanism and the shared
`XS … XL` scale it reuses are defined once in `docs/agent-model-effort.md`
(*Complexity → pipeline profile*); this skill has no researcher, so it derives its
own **pre-work** complexity signal from data already fetched in Step 1.

When `review.adaptive_depth` is `false`, skip the gate: set `profile = full` and
review at full depth as before. Otherwise compute the signal from the PR itself
and take the **fuller** of any inputs that disagree (a "trivial" issue whose diff
ballooned still earns full review):

- **Diff size / files-changed** — from `statusCheckRollup`/`files` in Step 1
  (`gh pr view {N} --json files`). Small (e.g. ≤ ~15 changed lines across 1 file)
  leans `light`; larger leans `full`.
- **Linked-issue `Effort` band** — when the PR links an issue (`Closes #N`), fetch
  its `## Metadata` `Effort` (`python3 shared/scripts/gi-issue.py {N} --fields
  number,title,body,labels`, reading `.issue.body`; on exit 4 or no `python3`,
  `gh issue view {N} --json body`). Request that exact field list, not just
  `body`: the cache is keyed by issue **and** field set, so asking narrowly here
  would make Step 3's read a guaranteed miss. `XS`/`S` asserted
  leans `light`; `M`/`L`/`XL`, or low-confidence, leans `full`.
- **Labels** — a `security`/`CVE`/`vulnerability` label (case-insensitive) forces
  `full` regardless of size (security-sensitive changes always get full review).

Resolve to `profile = light` only when **every** available signal agrees on
trivial; if any signal says `full`, or a signal is missing/ambiguous, use `full`
(ambiguous → fuller). Surface the decision on the `[1/7]` tracker line:

```
[1/7] PR Info      ✓ PR #{N}: {title}
                     {files_count} files changed, base: {base_branch}, depth: {profile}
```

`{profile}` is `light` or `full`. When `review.adaptive_depth` is `false`, still
print `depth: full` so the line is uniform. The `light` profile scales the Review
Loop only — see *Review Loop* (`light` caps cycles at 1 and skips optional passes;
the acceptance-criteria and traceability hard-blocks always run at full strength).
Full mechanics in `references/review-loop-mechanics.md` (*Depth gate*).

---

## Step 2 — Script Pre-pass [2/7]

Before spawning any LLM reviewer, run deterministic tools to catch mechanical issues — zero LLM tokens, all scripts and CLI tools.

**When `--review-only` is set:** this pre-pass is detection-only — see *Review-only mode* under Step 7.

**Default (fix loop):** detect the project's lint/format tools, run each auto-fix command (don't block on warnings — only on errors that prevent the fix from running), then run the test suite to catch failures early. The per-tool detection table and example commands are in `references/prepass-tests-ci-mechanics.md` (*Step 2*).

### Commit auto-fixes

**Skip entirely when `--review-only`.** Otherwise, if any files were modified by
the auto-fix tools, you MUST scan before staging — blocking on real secrets and
warning on large files / build artifacts / protected branches. In auto mode,
export `IDD_AUTO_MODE=1` first so warnings are logged rather than needing
confirmation. Run:

```bash
python3 shared/scripts/gi-secscan.py --working-tree
```

Run it from the repo root: it finds `.gitissue.yml` there and applies this
repo's `security.allow_pattern`, `security.extra_secret_file_pattern`,
`security.extra_secret_value_pattern`, and `security.max_file_size_mb` by
reading them itself. **Never interpolate a config value into this command.**
This skill runs with a pull request's branch checked out, so `.gitissue.yml` is
attacker-controlled; a value pasted into a shell word can close its quote and
append a command that runs on the reviewer's machine.

**Exit 1 is the block verdict — stop, do not stage, do not push, and report the
path from `blocking[]`.** It is not the degrade path: falling through to another
scan after a real secret is the one outcome this gate exists to prevent. Exit 3
(an uncompilable `security.*` regex) is also a stop. A missing `python3`, **exit
2** (the script path did not resolve, or the invocation was malformed — a scan
that never ran, never a pass), or exit 4 degrades — print `⚠ gi-secscan
unavailable — running the documented scan` and run the authoritative **Primary
Pattern** in `docs/pre-commit-security.md` against the working tree instead. Exit
1 with no parsable JSON on stdout is a crash, not a verdict: treat it as exit 2
and degrade. Do not improvise a weaker check, and never treat any non-zero exit
as a pass.

Only after the scan passes (or warnings are accepted), commit and push (`git add
-A` → `git commit -m "style: auto-fix lint and format issues"` → `git push
origin "$branch_name"`, using the variable bound in Step 1).

```
[2/7] Pre-pass     ✓ lint clean, format clean, {N} tests passed
                     Auto-fixed: {files_fixed} files (lint/format)
```

If no tools detected:
```
[2/7] Pre-pass     ○ no lint/format tools detected, tests: {N} passed
```

If tests fail here, continue to the review loop — failures are picked up in Step 4 and addressed in the fix cycle.

---

## Step 3 — Analyze & Review [3/7]

### Reviewer agents and cycle reuse

Read `shared/agents/code-reviewer.md` for the reviewer prompt and `shared/agents/fixer.md` for the fix-cycle prompt. Both spawn with the default general-purpose agent (do NOT set `subagent_type`; not a custom `code-reviewer`/`fixer` type). Pass the reviewer `branch_name`, `base_branch`, `pr_context` (PR title + body), and `diff_command` (`gh pr diff {N}`). Pass `review.confidence_threshold` (default 80) as the minimum confidence for code-reviewer findings; ui-reviewer keeps its 75 floor.

To minimize tokens, the loop **reuses the same reviewer across cycles**: cycle 1 cold-starts; cycles 2+ re-message it via `SendMessage` to re-review the updated diff; after the fixer reports zero fixable issues, one **fresh** confirmation reviewer does an unbiased final check. The exact spawn calls, the `SendMessage` re-review prompt, and the token-trade rationale live in `references/review-loop-mechanics.md`.

### UI/UX Review (Step 3 — auto-detected)

UI review is **auto-detected per PR** — no config flag enables it. The skill scans the PR title/body and changed files for UI work, then runs only what *can* and *should* run. The contract:

- **Code UI review** is environment-independent (reads the diff/changed files). It runs whenever UI work is detected, on any machine **including a no-GUI/server host** — never gated on a GUI, running app, or browser.
- **Browser UI review** is an optional, additive bonus: it captures screenshots from a running app, so it runs only with a reachable app *and* user opt-in. When it can't run (no app, capture unsafe, or auto mode without opt-in), it **skips with a warning and the code UI review still runs** — fail-soft to code-only, never block.

The shared mechanics — detection commands, the code-review spawn, the report-only display-environment label (`ui_env`), the browser-review gate + three-part capability check, and the headless capture call — live in `docs/ui-review.md`. This skill's own deltas — the PR diff command, the variables it passes, the interactive proposal prompt, and cycle-reuse `SendMessage` — are in `references/ui-review-mechanics.md`. **Read both and apply them** when `ui: detected`; together they preserve the contract above and route `action: "fix"` UI findings into Step 6 under `category: ui_ux`.

Also fetch the linked issue for acceptance-criteria verification: `python3 shared/scripts/gi-issue.py {linked_issue} --fields number,title,body,labels`, reading `.issue`. Step 1's depth gate requested this same field list, so the cache answers without a second network call — the field sets must stay identical for that to hold. Exit 3 is a stop; exit 4 or no `python3` degrades to `gh issue view {linked_issue} --json number,title,body,labels`.

```
[3/7] Review       ✓ spec[ac:pass correctness:pass safety:pass]
                     standards[trace:pass maint:partial]
                     {fixable_count} fixable, {note_count} noted
```

### Order within Step 3

Within a cycle, in order: reviewer subagent → UI reviewer in **code** mode (skip when `ui: not detected`) → per-criterion AC verification → the four traceability checks → aggregate all four into the five dimensions below for the cycle report.

### Dimensional review output

Step 3 produces a single verdict in **five dimensions** — `correctness`, `acceptance_criteria`, `traceability`, `maintainability`, `safety` — each reporting `pass`, `partial`, or `fail`. The reviewer's internal categories map onto them; when UI work is detected, the UI reviewer's `ui_ux` findings fold into `maintainability`, and a UI `action: "fix"` finding makes `maintainability` at least `partial` and adds a fixable issue to Step 6 (`category: ui_ux`) — the verdict never shows all-pass while UI fixables remain. The report groups the five under a **Spec axis** (`acceptance_criteria`, `correctness`, `safety`) and a **Standards axis** (`traceability`, `maintainability`) — presentation-only, no per-axis verdict. Full reviewer-category mapping and the two-axis rationale live in `references/verification-checks.md`. **Read that file and apply it now.**

A PR can pass tests and still fail `traceability` or `acceptance_criteria` — those are not gated by test results.

### Verification gates and the AC + traceability checks

Two dimensions — `acceptance_criteria` and `traceability` — are produced by this skill, not the reviewer. Their full procedure (per-criterion AC verification, the four traceability checks, and the refactor/chore exemption) lives in `references/verification-checks.md`. **Read that file and apply it now**, before aggregating the cycle report. The gating rules the rest of this skill depends on — enforce them here and in the Review Loop:

- `review.require_acceptance_criteria_check` (default `true`) gates the AC check; `review.require_traceability_check` (default `true`) gates traceability. When either is `false`, that dimension reports `pass — verification disabled` and never blocks soft-pass.
- **Any `acceptance_criteria: fail`** (a criterion the PR does not satisfy) → fixable issue in Step 6, `category: acceptance_criteria`. **Hard-blocks** soft-pass.
- **`Closes #{N}` absent** (traceability check 1, unless the PR is refactor/chore-exempt) → fixable issue in Step 6, `category: traceability`, suggested fix "Add `Closes #{N}` to the PR body." **Hard-blocks** soft-pass.
- All other traceability outcomes (missing commit ref, missing Decision Record on a human-authored PR, etc.) report `partial` and do **not** block.

These two hard-blocks are the issue #36 contract: a PR can pass tests and still be blocked on `acceptance_criteria: fail` or a missing `Closes #N`.

---

## Step 4 — Run Tests & Build [4/7]

When `review.run_tests` is false, skip this step and report `○ tests skipped (review.run_tests: false)`; the soft-pass conjunction treats the test leg as satisfied.

When true, detect and run the project's build system, then run all test types (unit, integration, e2e where present), with a `review.test_timeout`-second timeout (default: 300). The build-system detection table and the test-type breakdown are in `references/prepass-tests-ci-mechanics.md` (*Step 4*).

```
[4/7] Test         ✓ build ok, {N} tests passed
```

Or if failures:
```
[4/7] Test         ✗ {N} tests failed
                     {brief failure summary}
```

---

## Step 5 — Check CI Status [5/7]

When `review.check_ci` is false, skip polling and report `○ CI skipped (review.check_ci: false)`; the soft-pass conjunction treats the CI leg as satisfied (same pattern as disabled AC/traceability checks).

When true, run the whole wait in one call — `python3 shared/scripts/gi-ci-wait.py {N} --interval {review.ci_poll_interval} --timeout {review.ci_timeout}` — and read `verdict` from its JSON (`pass` / `fail` / `pending` / `none`). One invocation replaces the poll loop, so a ten-minute wait costs one tool call instead of one per poll. Exit 3 (a malformed argument) is a stop. Exit 4, or no `python3`, degrades to polling by hand: `gh pr checks {N} --json name,state,bucket` immediately after tests, then every `review.ci_poll_interval` seconds until `review.ci_timeout`. Either way, on `fail` extract details with `gh run view {run_id} --log-failed`. The manual polling and failure-extraction detail is in `references/prepass-tests-ci-mechanics.md` (*Step 5*).

**All checks passed:**
```
[5/7] CI Status    ✓ all checks passed
```

**Checks failed:**
```
[5/7] CI Status    ✗ {N} checks failed
                     {check_name}: {bucket}
```

**Checks still running after timeout:**
```
[5/7] CI Status    ⚠ checks still running after {timeout}s
```
Pending CI is **not clean** — it never satisfies soft-pass and auto mode must not merge while CI is pending (including when Step 6 finds zero fixables and would otherwise exit the fix loop). In interactive mode: ask to wait more or proceed without merging. In auto mode: do not merge; extend polling or stop with remaining issues — do not assume a later cycle will re-check if the fix loop has already ended.

**No CI configured:**
```
[5/7] CI Status    ○ no CI checks configured
```

---

## Step 6 — Fix Issues [6/7]

Collect issues from Steps 3-5, but **only fix those with `action: "fix"`** — `action: "note"` issues (medium code_quality/test_coverage suggestions) are reported in the summary but never trigger a fix cycle. This is the key token optimization. Fixable sources are the same five dimensions from Step 3's *Dimensional review output* (each `fail`/UI `action:"fix"` becomes one fixable issue) plus Step 4 test failures and Step 5 CI failures.

Acceptance-criteria fixes typically need code changes. The traceability `Closes #{N}` fix is a **read-modify-write** PR-body edit (driver rule 2 in `docs/platform-github.md`): (1) `gh pr view {N} --json body` to fetch the current body; (2) prepend `Closes #{N}` as the **first line** when absent (SPEC §3.3 / `docs/naming-conventions.md`), preserving the rest of the body unchanged — never replace the body from scratch; (3) `gh pr edit {N} --body "{merged_body}"`; (4) re-read with `gh pr view {N} --json body` and confirm `## Decision Record` and the Acceptance Criteria Verification table are still present. Apply code fixes, then commit and push as usual.

### If no fixable issues

```
[6/7] Fix          ○ no fixable issues (noted: {note_count})
```
Exit the **fix loop** only. Soft-pass is **not** implied — evaluate it next per *Review Loop* controls (tests pass, CI passes or no CI is configured, traceability not `fail`, zero `action: "fix"` issues). Pending CI ⇒ not clean.

### If fixable issues found

Delegate fixes to the fixer subagent (`shared/agents/fixer.md`) — never apply code changes in the main skill context — reusing the same fixer across cycles when possible. The fixer reads affected files, applies targeted changes, runs the mandatory pre-commit security scan against the staged set — `references/scripts/gi-secscan.py`, with the Primary Pattern in `docs/pre-commit-security.md` as its fallback, real secrets blocking the commit either way — then commits. The main agent collects the fixer's JSON result and pushes (`git push origin "$branch_name"`, the variable bound in Step 1 — never the literal ref name); unresolved blocking findings carry to the next cycle. The spawn variables and `Agent(...)` call are in `references/review-loop-mechanics.md`.

```
[6/7] Fix          ✓ fixed {N} issues (noted: {note_count} — not fixed)
```

Track what was fixed and what was noted:
```
Cycle {N}:
  ✗ {fixable_count} fixable issues found
  ✓ Fixed: [category] description (file:line)
  ✓ Fixed: [category] description (file:line)
  ○ Noted: [category] description (file:line) — medium, not blocking
```

---

## Review Loop

After Step 6, go back to Step 3 — but reuse the same reviewer agent via `SendMessage` (not a fresh spawn). Only spawn fresh for the confirmation pass.

**Loop controls:**
- **Max cycles:** `review.max_cycles` (default: 3). **`light` profile (Step 1
  Depth gate) caps this at 1** — one review pass, one fix cycle if `action: "fix"`
  issues are found, then the confirmation pass and exit. The reviewer still runs
  on the `light` path (depth reduced, review never skipped); only the number of
  review-fix iterations is capped. `full` uses `review.max_cycles` as before.
- **`light` profile — optional passes:** the `light` depth skips the optional
  browser UI review (the code UI review still auto-detects and runs when UI work
  is present) and does not spin extra confirmation cycles. The two #36
  hard-blocks — `acceptance_criteria: fail` and missing `Closes #N` — **still run
  at full strength** on every profile; the fast path never relaxes them.
- **Agent reuse:** Cycles 2+ reuse the existing reviewer and fixer agents. Fresh spawn only for the confirmation pass after fixer reports zero issues.
- **Soft pass (when `review.soft_pass: true`, default):** Stop when ALL hold: zero `action: "fix"` issues remain AND (tests pass or `review.run_tests: false`) AND (CI passes, no CI configured, or `review.check_ci: false`) AND traceability is not `fail`. Medium `note` issues and `partial` dimensions are report-only — they do not block.
- **Strict pass (when `review.soft_pass: false`):** Apply the same tests/CI gates, then require zero `action: "fix"` findings, zero remaining `action: "note"` findings, and `pass` for every enabled dimension. A `partial` dimension or any note is a strict blocker: exit the fix loop, report it under Remaining, and do not report clean or merge. Notes never become fixer inputs — Step 6 still fixes only `action: "fix"` — so strict mode surfaces these for manual remediation rather than looping without a fixable action.
- **`review.auto_merge`:** honored only in `--auto` mode (auto-pilot forces merge when mode permits). Interactive `/issue-pr-review` never merges regardless of this flag.
- **Hard-block conditions:** enforce the two #36 hard-blocks from Step 3's *Verification gates* — `traceability: fail` (e.g. missing `Closes #{N}`) and any `acceptance_criteria: fail` block even when every other dimension is clean and tests pass. They are gated on `review.require_traceability_check` / `review.require_acceptance_criteria_check` (both default `true`; `false` → `pass — verification disabled`), with the refactor/chore exemption reporting `traceability: pass — exempt`.
- **Confirmation pass:** When the fixer reports all fixed, spawn one fresh reviewer for unbiased verification. If clean → PASS. If new issues → back to existing fixer (counts as a cycle).
- **Exit on stagnation:** If the same issues appear in 2 consecutive cycles, stop and report
- **Review-only mode:** After Step 1 (including PR head checkout), run Step 2 detection-only (no auto-fix commits), then Steps 3-5 once — skip Step 6, never fix, loop, or merge

---

## Step 7 — Summary Report [7/7]

Print a structured step-by-step summary of the pipeline results, using the templates in `references/report-templates.md`:

- *Summary — Clean PR* — all checks pass, may include soft-pass notes
- *Summary — PR With Remaining Issues* — review couldn't clear everything within `review.max_cycles`
- *Auto-Merge (auto mode only)* — post-report squash merge and block-on-failure handling

In interactive mode: never auto-merge — just report status.

When `--no-merge` is set (even in auto mode): skip the merge step and report status only — equivalent to interactive mode's merge behavior. This flag exists so auto-pilot's reviewer subagent can run the full review-fix cycle without stealing the merge step from Phase 5.

**Review-only mode (`--review-only`) — authoritative definition.** This is the single home for the flag's behavior; every other mention is a pointer here.

- **Step flow:** Step 1 (PR info + `gh pr checkout`), Step 2 detection-only, Steps 3-5 **once**, skip Step 6, report in Step 7 — never loop, fix, or merge.
- **Step 2 is detection-only:** run lint/format in check mode (e.g. `npx eslint .` without `--fix`, `npx prettier --check .`, `ruff check .` without `--fix`) — no `--fix`, `--write`, or other mutating flags.
- **No writes at all:** skip *Commit auto-fixes* entirely. No file edits, commits, or pushes in this mode.

---

## Conventions

- **Platform driver:** all tracker access follows the GitHub driver — `--json` with explicit field selection, never parsed text output; full catalog in docs/platform-github.md.
- **Terminal output:** follow the `docs/terminal-style.md` vocabulary — `[N/7]` step counter; symbols `●` progress, `✓` success, `✗` failure, `◆` header, `⚠` warning, `○` info; two-space indent, `┄` separators, URLs on their own line, max 80 chars.
- **Errors:** rich format from `references/error-messages.md` — `✗ Short description` then `  To fix:  <command>`.
- **Expected output:** a clean review prints the 7-step tracker and a summary — see *Expected Inline Output* in `references/report-templates.md`.

## Edge Cases

- **No PR for current branch** — asks for an explicit `<N>` or stops cleanly.
- **CI still running** — waits up to `review.ci_timeout`, then prints state and stops without merging.
- **Critical issue unresolvable after 3 cycles** — stops, prints remaining issues, does not merge, hands back to the user.
- **Merge conflict with base** — prints the exact rebase command and stops.

## Additional Resources

- **`shared/agents/code-reviewer.md`** — Review subagent prompt
- **`shared/agents/ui-reviewer.md`** — UI/UX review subagent prompt (Step 3, auto-detected)
- **`shared/agents/fixer.md`** — Fix subagent prompt
- **`references/ui-review-mechanics.md`** — `/issue-pr-review`'s UI-review deltas: PR diff command, variables, review-mix prompt, cycle reuse (Step 3)
- **`references/prepass-tests-ci-mechanics.md`** — tool/build/CI detection tables (Steps 2, 4, 5)
- **`references/verification-checks.md`** — AC + traceability check procedure (Step 3)
- **`references/review-loop-mechanics.md`** — reviewer/fixer spawn + reuse mechanics
- **`references/report-templates.md`** — Step 7 summary templates, auto-merge flow, expected inline output
- **`references/error-messages.md`** — Error catalog
- **`docs/pre-commit-security.md`** — Pre-commit security scan contract (Steps 2, 6)
- **`docs/sync-conventions.md`** — Stash-first sync convention and recovery
- **`docs/idd-methodology.md`** — IDD durable-analysis fields (traceability check 3)
- **`docs/naming-conventions.md`** — Naming conventions
- **`docs/ui-review.md`** — Shared UI/UX review mechanics: detection, code/browser review, headless capture (Step 3)
- **`docs/terminal-style.md`** — Terminal output style contract (bundled at build time; the repo-root `DESIGN.md` is the human-facing companion and is not bundled)
