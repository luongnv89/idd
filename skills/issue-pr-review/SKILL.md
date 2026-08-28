---
name: issue-pr-review
description: "Review a PR end-to-end with CI checks, fix cycles, and optional auto-merge. Use for PR review, cleanup, or readiness checks. Don't use for creating PRs, raw issue analysis, or non-PR code review."
license: MIT
compatibility: "Requires git and GitHub CLI (gh) with authentication. Self-contained — uses shared agents from shared/agents/."
metadata:
  version: 2.6.0
  author: Luong NGUYEN <luongnv89@gmail.com>
  effort: high
---

# /issue-pr-review [PR_NUMBER]

Review a PR end-to-end — analyze, test, fix, check CI, repeat until clean.

## Invocation

| Invocation | Mode | What happens |
|------------|------|--------------|
| `/issue-pr-review <N>` | interactive | Review, fix, repeat until clean; report (no auto-merge) |
| `/issue-pr-review <N> --auto` | auto-pilot | Review, fix, and auto-merge when clean |
| `/issue-pr-review <N> --auto --no-merge` | auto-pilot | Review and fix, but skip auto-merge |
| `/issue-pr-review` | detect | Auto-detect PR for current branch |
| `/issue-pr-review --review-only` | read-only | Review and report, never fix or merge |

`--auto` is set by `/auto-pilot`. In auto mode export `IDD_AUTO_MODE=1` before any shell snippet that consults it — the pre-commit security scan reads it to switch from prompt-on-warning to log-and-continue (`references/docs/pre-commit-security.md`). `--no-merge` suppresses auto-merge even under `--auto`.

## Prerequisites

Confirm before any operation: git repository (`git rev-parse --git-dir`), `gh` installed and authenticated (`gh auth status`), and the bundled prompts and reference files present — *Bundled dependency precheck*.

### Bundled dependency precheck

Verify **every** path below exists relative to the skill's directory (the dirname of this SKILL.md); this list is the authoritative guard. If any is missing, stop immediately, print the error, and never continue with an inline or guessed reviewer/fixer prompt:

```text
references/agents/code-reviewer.md
references/agents/ui-reviewer.md
references/agents/fixer.md
references/ui-review-mechanics.md
references/prepass-tests-ci-mechanics.md
references/verification-checks.md
references/review-loop-mechanics.md
references/report-templates.md
references/run-stats.md
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
references/scripts/gi-gh.py
references/scripts/gi-issue.py
```

```text
✗ Missing bundled dependency: {missing_file}

  To fix:  asm install https://github.com/luongnv89/idd --skill issue-pr-review
           (or reinstall the full distribution)

  Then restart the agent session and re-run /issue-pr-review.
```

## Repo Sync Before Edits (mandatory)

Before any fix, sync with the **stash-first pattern** — snippet and recovery in `references/docs/sync-conventions.md`: `git stash push -u` if the tree is dirty, `git fetch origin`, `git pull --rebase origin "$branch"`, `git stash pop`. On pop failure, stop and surface `git stash list` / `git stash show -p stash@{0}`. A missing `origin` or a conflicting rebase stops and asks (interactive), or aborts with a clear error (auto).

## Configuration

Load config once at skill start; never re-read it. Run `python3 references/scripts/gi-config.py` — **Working directory:** the repo root; **Script path:** resolved against this SKILL.md's own directory, as the *Bundled dependency precheck* resolves its list. Why both matter: `references/review-loop-mechanics.md` (*Config keys and what they gate*).

- **Exit 0** — use `config`.
- **Exit 3** — print `✗ Invalid config: .gitissue.yml` with the offending key and reason from stderr, and stop.
- **Script file absent** — a broken install and not a degrade: stop and print the `✗ Missing bundled dependency` block.
- **Anything else** (no `python3`, non-zero exit, unparsable stdout) — print `⚠ gi-config unavailable — reading .gitissue.yml by hand` and read it yourself, over the keys below, *instead of* the script.

**Capture the run clock here:** chain that same `python3` invocation as `python3 …; ec=$?; date +%s >&2; exit "$ec"`; the stderr epoch is `run_started_epoch`, from which the *Run Stats Footer* (`references/run-stats.md`) measures `elapsed`.

Every `review.*` key, its default (`review.max_cycles: 3`, `review.soft_pass: true`, `review.auto_merge: false` — auto mode overrides to `true`) and what it gates: `references/review-loop-mechanics.md` (*Config keys and what they gate*); value syntax in `references/docs/config-schema.md`. UI/UX **code** review needs no config flag — auto-detected per PR (*Step 3*).

---

## Pipeline Overview

**Expected output** — example of a clean run, one line per step:

```
  ◆ PR Review Pipeline
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  [1/7] PR Info      ✓ PR #87: fix(auth): resolve redirect (#42), depth: full, qa: absent
  [2/7] Pre-pass     ✓ lint clean, format clean, 17 tests passed
  [3/7] Review       ● analyzing changes...
  [4/7] Test         ✓ 17 tests passed, build ok
  [5/7] CI Status    ✓ all checks passed
  [6/7] Fix          ○ no fixable issues
  [7/7] Report       ✓ PR is clean — ready to merge
```

Step 2 runs once; Steps 3-6 repeat up to `review.max_cycles` (default 3); Step 7 runs once. Tokens are minimized by the zero-token pre-pass, reviewer/fixer reuse, `fix`/`note` filtering, and soft-pass.

### Step completion reports

Each step closes with `√`/`×` per check plus a `Result: PASS | PARTIAL | FAIL` line; a step is not complete until its `Result:` line prints. Check names, semantics and format: `references/report-templates.md` (*Step Completion Reports*) — **read it now**.

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
gh pr view {N} --json number,title,body,baseRefName,headRefName,headRefOid,state,url,labels,reviews,statusCheckRollup,files
```

Extract the number/title/URL, base and head branches, the head SHA (`headRefOid` — the *QA handoff gate* binds against it), linked issue numbers (from `Closes #N`), CI status, and changed files.

**If PR is closed/merged:**
```
⚠ PR #{N} is already {state}
```
Stop.

### Checkout PR head branch

Check out the PR head before Step 2, so pre-pass commits and the fixer operate on `{headRefName}`:

```bash
gh pr checkout {N}
```

`{headRefName}` is `{branch_name}` for sync, commit and push (canonical command: `references/docs/platform-github.md`). **Bind it to a shell variable — never paste the literal name into a command:** assign once, `branch_name="$(gh pr view {N} --json headRefName --jq .headRefName)"`, then use `"$branch_name"` in every **shell command**; display templates and spawn-variable lists keep the plain name. Why it is a safety rule: `references/review-loop-mechanics.md` (*Binding the head-ref name*).

### Depth gate (select the review profile)

Decide **how deep** this review goes: `profile = light | full`. Signals and what <!-- a:rv-depth-gate-refresh -->
`light` changes: `references/docs/agent-model-effort.md` (*Complexity → pipeline profile*) and `references/review-loop-mechanics.md` (*Depth gate*) — **read and apply both**.
First, with `references/scripts/gi-gh.py` bundled beside its consumer, when the PR body links an issue, refresh it at the review boundary:
`python3 references/scripts/gi-issue.py {linked_issue} --fields number,title,body,labels --refresh`,
reading `.issue`. Exit 3 stops; no `python3`, exit 2, or exit 4 degrades to
`gh issue view {linked_issue} --json number,title,body,labels`. Retain either
successful record as `linked_issue_snapshot`.
**If neither path yields a usable record, apply the empty-record fail-safe in `references/review-loop-mechanics.md` (*Depth gate*) — never review a linked issue on an empty snapshot.**
The refresh runs even when `review.adaptive_depth` is `false`; then ignore the effort signals and set `profile = full` after the refresh.
Otherwise weigh three signals: diff size / files changed, the retained body's
`## Metadata` `Effort` band, and labels (any `security`/`CVE`/`vulnerability`
forces `full`). Resolve to `light` only when **every** signal agrees; any
`full`/missing/ambiguous → `full`.

### QA handoff gate (trust an already-QA'd PR) <!-- a:rv-qa-handoff-gate -->

`/issue-resolver` ends a clean QA loop by writing `<!-- gitissue:qa v1 head=… -->` as the PR body's last line. This gate decides whether to believe it, so an already-QA'd PR is reviewed **once, by a fresh agent**. It runs **after** the Depth gate and sets `qa_handoff = trusted | stale | absent`, plus `ci_leg_runnable` from loaded `review.check_ci` and Step 1's `statusCheckRollup`:

| Value | When | Effect |
|-------|------|--------|
| `trusted` | the marker parses **and** its `head=` equals Step 1's `headRefOid` | the narrowed loop — *What `trusted` skips* |
| `stale` | a marker is present but any condition fails | today's full pipeline, unchanged |
| `absent` | the body carries no marker | today's full pipeline, unchanged |

`stale` and `absent` are distinguished for the operator only; both take the identical path.
**Fail-safe: any doubt is `stale`** — an unparsable or duplicated marker included; an unknown extra field is *not* doubt.
**A marker is never authentication:** a PR body is attacker-controlled (`gh pr edit --body`), so this verdict may gate **only duplicated work**, never a safety gate. The parse, *What `trusted` skips*, and the binding *Never gated* list: `references/review-loop-mechanics.md` (*QA handoff gate*) — **read it now**.
When `review.adaptive_depth` is `false`, skip this gate: set `qa_handoff = absent`. **No new config key is introduced.**

**Precedence, stated once:** `qa_handoff` is computed *after* `profile`, and its power is bounded **relative to the ungated pipeline** — it may only **narrow** what a `stale`/`absent` PR already gets. The bound is per verdict, not monotonic across the run: a flip back to `stale` restores the full cap and is a return to the ungated pipeline, not a widening. One asymmetric case: a marker `profile=light` against a pr-review `profile=full`, where the fuller wins — the review collapse **and** the cycle cap are **refused**, while the duplicate-test skip still applies, because a test run is a test run at any depth.

Surface both on the `[1/7]` tracker line; with `review.adaptive_depth: false` print `depth: full, qa: absent` so it stays uniform:

```
[1/7] PR Info      ✓ PR #{N}: {title}
                     {files_count} files changed, base: {base_branch}, depth: {profile}, qa: {qa_handoff}
```

---

## Step 2 — Script Pre-pass [2/7] <!-- a:rv-step2-prepass -->

Before spawning any LLM reviewer, run deterministic tools — zero LLM tokens. **When `--review-only` is set** this pre-pass is detection-only (*Review-only mode*, Step 7).

**Default (fix loop):** detect the project's lint/format tools, run each auto-fix command (block only on errors that prevent the fix from running), then run the test suite. Detection table: `references/prepass-tests-ci-mechanics.md` (*Step 2*). **Under `qa_handoff = trusted`, skip only the test run**, and only when the marker carries a `tests=` field whose SHA equals `head` **and `ci_leg_runnable` is true**. When `ci_leg_runnable` is false (no CI / empty `statusCheckRollup` / `no_ci` / `review.check_ci: false`), ignore `tests=` and run the local suite as unmarked. The lint/format auto-fix still runs — it mutates the tree, so skipping it changes the PR, not just the review's cost — and the `gi-secscan` gate below is **never** gated on `qa_handoff`. That auto-fix moves the head off the marker: recompute the verdict then, before Step 3 (*Review Loop*).

### Commit auto-fixes <!-- a:rv-commit-autofix -->

**Skip entirely when `--review-only`.** Otherwise, if the auto-fix tools modified
any file, you MUST scan before staging — blocking on real secrets, warning on
large files / build artifacts / protected branches. In auto mode export
`IDD_AUTO_MODE=1` first, so warnings are logged rather than needing confirmation.
Run from the repo root:

```bash
base="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
python3 references/scripts/gi-secscan.py --working-tree --policy-ref "origin/${base}"
```

Bind `base` **first**, from the repository's default branch, never the PR's `baseRefName`; never interpolate a config value into this command — the script reads `security.*` itself.

**A pass is all four: exit 0, `policy_source` exactly the `ref:origin/…` asked for, `verdict` not `block`, and not (`scanned` 0 with `skipped` above 0).** **Exit 1 is the block verdict: stop, do not stage, do not push, report the path from `blocking[]`** — never the degrade path, and exit 1 without parsable JSON is a crash, so treat it as exit 2. Exit 3 is also a stop. A missing `python3`, **exit 2** (a scan that never ran), or exit 4 degrades: print `⚠ gi-secscan unavailable — running the documented scan` and run the **Primary Pattern** in `references/docs/pre-commit-security.md`. Never read a non-zero exit as a pass. Why each part holds, the `--policy-ref` trust boundary, and the commit/push commands gated behind the scan: `references/prepass-tests-ci-mechanics.md` (*Commit auto-fixes*) — **read it now**.

Only after the scan passes (or warnings are accepted), commit and push: `git add -A`, then `git commit -m "style: auto-fix lint and format issues"`, then `git push origin "$branch_name"` (the variable bound in Step 1).

```
[2/7] Pre-pass     ✓ lint clean, format clean, {N} tests passed
                     Auto-fixed: {files_fixed} files (lint/format)
[2/7] Pre-pass     ○ no lint/format tools detected, tests: {N} passed
```

If tests fail here, continue to the review loop — Step 4 picks them up.

---

## Step 3 — Analyze & Review [3/7] <!-- a:rv-step3-analyze -->

### Reviewer agents and cycle reuse

Read `references/agents/code-reviewer.md` and `references/agents/fixer.md` for the two prompts; both spawn with the default general-purpose agent (do NOT set `subagent_type`). Pass `branch_name`, `base_branch`, `pr_context` (title + body), `diff_command` (`gh pr diff {N}`), and `review.confidence_threshold` (default 80) as the minimum finding confidence; ui-reviewer keeps its 75 floor.

To minimize tokens the loop **reuses the same reviewer across cycles**: cycle 1 cold-starts, cycles 2+ re-message it via `SendMessage`, and after the fixer reports zero fixable issues one **fresh** confirmation reviewer does an unbiased final check. Under `qa_handoff = trusted` the cycle-1 reviewer is **collapsed into** that fresh confirmation pass rather than skipped, so the PR still receives exactly one independent, full-strength review, and the loop cap drops to `min(1, configured_cap)`. The collapse **saves no reviewer spawn** — the confirmation pass is itself fix-conditional — and *Precedence* refuses both collapse and cap when the marker says `profile=light` against `profile=full`. Spawn calls and what the collapse buys: `references/review-loop-mechanics.md` (*Why reuse the reviewer*).

### UI/UX Review (Step 3 — auto-detected)

UI review is **auto-detected per PR** — no config flag enables it. Two legs: the **code** UI review reads the diff, so it runs on any host, **including a no-GUI/server host**, never gated on a GUI or browser; the **browser** UI review is an optional bonus that **skips with a warning while the code UI review still runs** (*The two legs* in `references/ui-review-mechanics.md`).

Detection commands, the code-review spawn, the report-only `ui_env` label, the browser gate and its three-part capability check, and headless capture are in `references/docs/ui-review.md`; this skill's deltas in `references/ui-review-mechanics.md`. **Read both and apply them** when `ui: detected`; they preserve the contract above and route `action: "fix"` UI findings into Step 6 under `category: ui_ux`. Under `qa_handoff = trusted` the **code** UI review is skipped only when the marker's `ui=` leg says it already ran (`ui=code…` or `ui=code+browser…`) **and** carries an `@<sha40>` equal to `head` — never on `ui=none`, never on an unsuffixed `ui=`, and never for the browser leg.

For acceptance-criteria verification, consume `linked_issue_snapshot` directly; do not call `gi-issue.py` or `gh` again. If a linked issue exists but its snapshot holds no usable record, the *Depth gate*'s empty-record fail-safe applies. A PR with **no** linked issue is a different state, not a fail-safe case: it proceeds normally — `acceptance_criteria` reports `○ pass — none defined; manual review recommended`, and traceability check 1 handles the missing `Closes #N`. <!-- a:rv-step3-ac-snapshot -->

```
[3/7] Review       ✓ spec[ac:pass correctness:pass safety:pass]
                     standards[trace:pass maint:partial]
                     {fixable_count} fixable, {note_count} noted
```

### Order within Step 3

Reviewer subagent → UI reviewer in **code** mode (skip when `ui: not detected`) → per-criterion AC verification → the four traceability checks → aggregate into the five dimensions.

### Dimensional review output

Five dimensions — `correctness`, `acceptance_criteria`, `traceability`, `maintainability`, `safety` — each `pass`, `partial`, or `fail`. UI `ui_ux` findings fold into `maintainability`, and a UI `action: "fix"` finding makes it at least `partial` and adds a fixable issue (`category: ui_ux`) — the verdict never shows all-pass while UI fixables remain. The report groups them under a **Spec axis** (`acceptance_criteria`, `correctness`, `safety`) and a **Standards axis** (`traceability`, `maintainability`) — presentation-only, no per-axis verdict. Mapping and rationale: `references/verification-checks.md`. **Read that file and apply it now.** A PR can pass tests and still fail `traceability` or `acceptance_criteria`.

### Verification gates and the AC + traceability checks <!-- a:rv-verify-gates -->

`acceptance_criteria` and `traceability` are produced by this skill, not the reviewer; their procedure — per-criterion AC verification, the four traceability checks, the refactor/chore exemption — is in `references/verification-checks.md`. **Read that file and apply it now**, before aggregating the cycle report. Enforce these gating rules here and in the Review Loop: <!-- a:rv-traceability-outcomes -->

- `review.require_acceptance_criteria_check` (default `true`) gates the AC check; `review.require_traceability_check` (default `true`) gates traceability. When either is `false`, that dimension reports `pass — verification disabled` and never blocks soft-pass.
- **Any `acceptance_criteria: fail`** → fixable issue in Step 6, `category: acceptance_criteria`. **Hard-blocks** soft-pass.
- **`Closes #{linked_issue}` absent** (traceability check 1, unless refactor/chore-exempt) → fixable issue in Step 6, `category: traceability`, suggested fix "Add `Closes #{linked_issue}` to the PR body." **Hard-blocks** soft-pass.
- All other traceability outcomes (missing commit ref, missing Decision Record on a human-authored PR) report `partial` and do **not** block.

These two hard-blocks are the issue #36 contract: a PR can pass tests and still be blocked on `acceptance_criteria: fail` or a missing `Closes #N`.

---

## Step 4 — Run Tests & Build [4/7] <!-- a:rv-step4-tests -->

When `review.run_tests` is false, skip this step, report `○ tests skipped (review.run_tests: false)`; the soft-pass conjunction treats the test leg as satisfied.

When true, detect and run the build system, then all test types (unit, integration, e2e where present) with a `review.test_timeout`-second timeout (default 300). Detection table: `references/prepass-tests-ci-mechanics.md` (*Step 4*).

**Under `qa_handoff = trusted`, skip this step** and report `○ tests skipped (qa handoff @ {commit_sha_short})` — the first 7 characters of Step 1's `headRefOid` — but only when the marker carries a `tests=` field whose SHA equals `head` **and `ci_leg_runnable` is true**; with no `tests=` field, or a SHA that differs, run the step in full. When `ci_leg_runnable` is false (no CI / empty `statusCheckRollup` / `no_ci` / `review.check_ci: false`), ignore `tests=` and run the local suite as unmarked. The verdict is `trusted` only against the **live** head — recomputed after any push this skill makes — so the suite it stands in for did run on this exact commit; the soft-pass conjunction therefore treats the test leg as satisfied.

A skipped step evaluated neither check, so its report is `× Suite passed` / `× Build clean` with `Result: PARTIAL` and the closing summary carries the gap — never a silent `√`/`✓ pass`. Step 5's CI is a separate leg, never skipped: it runs on the remote against the merge result, and nothing in a PR body is evidence about it.

```
[4/7] Test         ✓ build ok, {N} tests passed
[4/7] Test         ✗ {N} tests failed — {brief failure summary}
```

---

## Step 5 — Check CI Status [5/7] <!-- a:rv-step5-ci -->

When `review.check_ci` is false, skip polling, report `○ CI skipped (review.check_ci: false)`; the soft-pass conjunction treats the CI leg as satisfied.

When true, run the whole wait in one call — `python3 references/scripts/gi-ci-wait.py {N} --interval {review.ci_poll_interval} --timeout {review.ci_timeout}` — and read `verdict` (`pass` / `fail` / `pending` / `none`). A terminal snapshot is trusted only after its check-name set settles; `none` is clean only when `none_confirmed` is `true`; otherwise both are `pending`. Exit 3 is a stop. Exit 4, or no `python3`, degrades to the **merge-safe manual fallback** — never to a filtered `gh pr checks` list, which makes an empty result look successful. On `fail`, extract details with `gh run view {run_id} --log-failed`.

**Bind the verdict to the commit it was reached on** — record `ci_sha` = the `headRefOid` this wait ran against, and report `ci_status` as `passed@` or `failed@` plus that full 40-character SHA; `no_ci`, a skipped wait, and any degraded wait that never read a head stay bare. Settle window, manual polling loop and its head re-read, and the bare-vs-bound cases: `references/prepass-tests-ci-mechanics.md` (*Step 5*, *Binding the verdict to a commit*). **Read that file and apply it now.**

```
[5/7] CI Status    ✓ all checks passed
[5/7] CI Status    ✗ {N} checks failed — {check_name}: {bucket}
[5/7] CI Status    ⚠ checks still running after {timeout}s
[5/7] CI Status    ○ no CI checks configured
```

Pending CI is **not clean**: it never satisfies soft-pass, and auto mode must not merge while CI is pending — including when Step 6 finds zero fixables and would otherwise exit the fix loop. Interactive: ask to wait more or proceed without merging. Auto: do not merge; extend polling or stop with remaining issues — do not assume a later cycle will re-check once the fix loop has ended.

---

## Step 6 — Fix Issues [6/7] <!-- a:rv-step6-fix -->

Collect issues from Steps 3-5, but **only fix those with `action: "fix"`** — `action: "note"` issues are reported, never fixed. This is the key token optimization. Fixable sources: the five dimensions (each `fail`/UI `action:"fix"` is one fixable issue) plus Step 4 test failures and Step 5 CI failures.

The traceability `Closes #{linked_issue}` fix is a **read-modify-write** PR-body edit (driver rule 2 in `references/docs/platform-github.md`): `gh pr view {N} --json body`, prepend `Closes #{linked_issue}` as the **first line** when absent (SPEC §3.3 / `references/docs/naming-conventions.md`) preserving the rest unchanged, `gh pr edit {N} --body "{merged_body}"`, then re-read and confirm `## Decision Record`, the Acceptance Criteria Verification table, and any trailing `<!-- gitissue:qa v1 … -->` marker are still present. Never replace the body from scratch. Apply code fixes, then commit and push as usual. <!-- a:rv-closes-body-edit -->

### If no fixable issues

```
[6/7] Fix          ○ no fixable issues (noted: {note_count})
```
Exit the **fix loop** only. Soft-pass is **not** implied — evaluate it next per *Review Loop* controls. Pending CI ⇒ not clean.

### If fixable issues found

Delegate to the fixer subagent (`references/agents/fixer.md`) — never apply code changes in the main skill context — reusing the same fixer across cycles. It applies targeted changes, runs the mandatory pre-commit security scan against the staged set (`references/scripts/gi-secscan.py`, same `--policy-ref` base ref as Step 2, Primary Pattern in `references/docs/pre-commit-security.md` as fallback, real secrets blocking either way), then commits. The main agent collects its JSON result and pushes (`git push origin "$branch_name"` — never the literal ref name); unresolved blocking findings carry to the next cycle. Spawn variables and the `Agent(...)` call: `references/review-loop-mechanics.md`.

```
[6/7] Fix          ✓ fixed {N} issues (noted: {note_count} — not fixed)

Cycle {N}:
  ✗ {fixable_count} fixable issues found
  ✓ Fixed: [category] description (file:line)
  ○ Noted: [category] description (file:line) — medium, not blocking
```

---

## Review Loop

After Step 6, go back to Step 3 — reuse the same reviewer via `SendMessage`, spawning fresh only for the confirmation pass. Mechanics for every control below: `references/review-loop-mechanics.md` (*Depth gate*, *What `light` changes in the loop*, *QA handoff gate*, *Re-evaluation after a push*, *Config keys and what they gate*) — **read that file and apply it now.**

- **Max cycles:** `review.max_cycles` (default 3). `light` and `qa_handoff = trusted` each cap it at `min(1, configured_cap)`, the `trusted` cap subject to the *Precedence* carve-out. The `light` profile also skips the optional browser UI review; `trusted` never does — it reaches only the **code** leg (Step 3). Neither skips the reviewer; neither relaxes the two #36 hard-blocks.
- **Re-evaluate `qa_handoff` after any push this skill makes** — Step 2's auto-fix commit as much as every fixer push — re-read `headRefOid` and recompute before the next step that reads it. The loop re-enters at Step 3, never Step 1.
- **Agent reuse:** cycles 2+ reuse the existing reviewer and fixer. **Confirmation pass:** when the fixer reports all fixed, spawn one fresh reviewer — clean → PASS; new issues → back to the existing fixer (counts as a cycle).
- **Soft pass (`review.soft_pass: true`, default):** stop when ALL hold — zero `action: "fix"` issues remain, tests pass or `review.run_tests: false`, CI passes or no CI configured or `review.check_ci: false`, and traceability is not `fail`. Notes and `partial` dimensions are report-only.
- **Strict pass (`review.soft_pass: false`):** strict mode keeps those tests/CI gates and adds zero `action: "fix"` findings, zero remaining `action: "note"` findings, and `pass` for every enabled dimension; any note or `partial` dimension is a strict blocker — exit the fix loop, report it under Remaining, and do not report clean or merge.
- **Hard-block conditions:** `traceability: fail` (e.g. missing `Closes #{N}`) and any `acceptance_criteria: fail` block even when every other dimension is clean and tests pass.
- **`review.auto_merge`:** honored only in `--auto` mode; interactive `/issue-pr-review` never merges.
- **Exit on stagnation:** same issues in 2 consecutive cycles → stop and report.
- **Review-only mode:** Step 1 (including PR head checkout), Step 2 detection-only, Steps 3-5 once — skip Step 6, never fix, loop, or merge (*Step 7*).

---

## Step 7 — Summary Report [7/7]

Print a structured summary from `references/report-templates.md` — *Summary — Clean PR* (all checks pass, may include soft-pass notes), *Summary — PR With Remaining Issues* (not cleared within `review.max_cycles`), *Auto-Merge (auto mode only)* (post-report squash merge, block-on-failure handling).

**Auto-merge is the one destructive action this skill takes:** it squash merges the PR and deletes the head branch, neither reversible from here. It is confirmed by gate, not by prompt, and every gate must hold: interactive `/issue-pr-review` never merges whatever `review.auto_merge` says; `--auto` merges only when `review.auto_merge` is true **and** the PR is clean (pending CI is never clean); `--no-merge` suppresses the merge outright, so auto-pilot's reviewer can run the full cycle without stealing Phase 5's merge step. No dry-run — if a gate is unmet, report and stop, and never remove a branch by hand to "finish" a merge the gates refused.

**Then the run-stats footer.** Close with the *Run Stats Footer* — `references/run-stats.md` — `elapsed`, `tokens` only where the host reported a count (otherwise left out), `agents`, run cost only, `n/a` for anything else undetermined. It is the last thing printed at **every** terminal outcome, including a run that stopped before Step 7: a failed prerequisite, an invalid config, an un-checkoutable PR, a CI wait that gave up, or a loop that exhausted `review.max_cycles`.

**Review-only mode (`--review-only`) — authoritative definition.** The single home for the flag's behavior; every other mention points here.

- **Step flow:** Step 1 (PR info + `gh pr checkout`), Step 2 detection-only, Steps 3-5 **once**, skip Step 6, report in Step 7 — never loop, fix, or merge.
- **Step 2 is detection-only:** lint/format in check mode (`npx eslint .`, `npx prettier --check .`, `ruff check .`) — no `--fix`, `--write`, or other mutating flags.
- **No writes at all:** skip *Commit auto-fixes* entirely — no file edits, commits, or pushes.

---

## Conventions

Terminal output uses the `references/docs/terminal-style.md` vocabulary — `[N/7]` counter; `●` `✓` `✗` `◆` `⚠` `○`; two-space indent, `┄` separators, URLs on their own line, max 80 chars. Tracker access follows the GitHub driver (`--json`, explicit fields, never parsed text). Errors use the rich format in `references/error-messages.md`.

## Edge Cases

No PR for the current branch (ask for an explicit `<N>` or stop cleanly), CI still running (wait up to `review.ci_timeout`, print state, stop without merging), a critical issue still unresolved at the cycle cap (stop, print remaining, do not merge), and a merge conflict with base (print the exact rebase command and stop) each have a rich error block in `references/error-messages.md`.
