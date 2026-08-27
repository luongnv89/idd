---
name: issue-resolver
description: "Create an atomic PR closing a GitHub issue end-to-end via a 6-step pipeline. Use to resolve, fix, or implement issue #N. Don't use for analysis without fixing (/issue-analysis), reviewing a PR (/issue-pr-review), or bulk backlog work (/auto-pilot)."
license: MIT
compatibility: "Requires git and GitHub CLI (gh) with authentication and push access. Self-contained — uses shared agents from shared/agents/."
metadata:
  version: 0.17.0
  author: Luong NGUYEN <luongnv89@gmail.com>
  effort: max
---

# /issue-resolver N

Resolve a GitHub issue end-to-end — from issue to atomic PR in 6 steps.

## Invocation

| Invocation | Mode | What happens |
|------------|------|--------------|
| `/issue-resolver <N>` | interactive | Resolve issue #N, ask the user to pick a plan |
| `/issue-resolver <N> --auto` | auto-pilot | Resolve autonomously, no prompts |
| `/issue-resolver <N> --no-run-log` | (modifier) | Suppress the `.gitissue/runs.jsonl` append; return telemetry to the caller |

`N` must be a GitHub issue number. `--auto` is set automatically by `/auto-pilot`. `--no-run-log` is **orthogonal to `--auto`** and passed **only by `/auto-pilot`** — rationale in *Step 5 — Deliver* → *Run-log entry*.

## Prerequisites

Verify before any operation — git repository (`git rev-parse --git-dir`), `gh` installed (`which gh`), authenticated (`gh auth status`), GitHub remote present (`git remote -v`). On failure print the exact error from `references/error-messages.md` and stop.

## Repo Sync Before Edits (mandatory)

Applies to the **in-place path** only (ordinary auto mode, or interactive after declining Step 0e). Accepted interactive and validated caller-managed worktrees start from the fetched base; an invalid `IDD_CALLER_WORKTREE=1` is a stop, never a sync bypass or in-place fallback. Sync with the **stash-first pattern** — stash (including untracked) → fetch → rebase-pull → pop, aborting with the recovery hint if the pop conflicts. Copy the snippet and recovery procedure from `docs/sync-conventions.md` (*Quick Reference (Copy-Paste Snippet)*); never improvise a bare rebase on a dirty tree. A missing `origin` or a rebase conflict stops and asks (interactive), or aborts with a clear error (auto).

## Configuration

Load config once at skill start; never re-read it. Run `python3 shared/scripts/gi-config.py` — two mandatory requirements. **Working directory:** the repo root. **Script path:** absolute, resolved exactly as the *Bundled dependency precheck* resolves its list. It prints `{"config": {…dotted keys…}, "config_file": …, "first_run": …}`, merging the defaults below with `.gitissue.yml`. Why both requirements and the clock below are load-bearing: `references/pipeline-steps.md` (*Configuration load*).

- **Exit 0** — use `config`; when `first_run` is `true` print `○ First run — using default config. Run /init-gitissue to customize.`
- **Exit 3** — invalid `.gitissue.yml`: print the validation error from `references/error-messages.md` (*Invalid config*) and stop.
- **Script file absent** — a missing bundled dependency is a broken install and not a degrade: stop and print the `✗ Missing bundled dependency` block.
- **Anything else** (no `python3`, another non-zero exit, unparsable stdout) — print `⚠ gi-config unavailable — using the inline defaults below`, then read `.gitissue.yml` by hand *instead of* the script, never beside it.

**Capture the run clock here:** chain that same `python3` invocation as `python3 …; ec=$?; date +%s >&2; exit "$ec"` and keep the stderr epoch as `run_started_epoch` — what the *Run Stats Footer* (`references/run-stats.md`) measures `elapsed` from.

Defaults (field reference `docs/config-schema.md`): `issue.auto_normalize: true` · `resolve.approval_gate: auto` · `resolve.branch_prefix: "auto"` · `resolve.auto_test: true` · `resolve.test_timeout: 300` · `resolve.max_commits: 10` · `resolve.qa_max_cycles: 5` · `resolve.adaptive_effort: true` (*0g*; `false` pins `profile = full`) · `resolve.ui_review.browser_review: "ask"` (gates only the browser review) · `resolve.borrow_skills: false` (`true` may borrow catalogued skills).

---

## Subagent Architecture

Heavy work goes to subagents (`shared/agents/`) to keep the main agent's **context window** clean and its **token budget** predictable: the main agent owns Step 0, Step 4's review-fix loop and Step 5; Steps 1-3 each spawn one. Diagram in `references/pipeline-steps.md` (*Subagent Architecture Diagram*). Each agent prompt is bundled at `references/agents/<name>.md`; the conventions they share live once in `docs/shared-agent-conventions.md`.

### Spawning a subagent (canonical pattern)

Every step spawns with the same shape — only role, description and prompt file change. **Do NOT set `subagent_type`**; always use the default general-purpose agent:

```python
Agent(
  description="{role} — {action} issue #N",
  prompt=<{agent-file}.md prompt with {variables} replaced>,
  # do NOT set subagent_type — default general-purpose agent, never a custom type (e.g. NOT "code-reviewer")
)
```

### Orchestrating the agents (model/effort, monitoring, audit)

For each spawned step: **name the role** in the spawn `description`; **size the model/effort** per `docs/agent-model-effort.md` from the most-recent complexity signal, falling back to the agent's default tier (advisory, never blocking); **monitor before advancing** — check the agent returned its contract's shape (researcher `status`+`complexity`; synthesizer one `recommended` option; implementer commits+tests+repro for bugs; reviewer/fixer `result`+counts), a missing or blocking return stopping the run (interactive) or following the auto behavior; and **audit** — record `complexity`, `qa_cycles`, `outcome`, `duration_s` plus the `[N/5]` tracker line.

### Environment check

If the Agent tool is available, use subagents as above; if not (e.g. Claude.ai), run each step inline via the fallback instructions.

### Bundled dependency precheck

Before execution, verify **every** path below exists relative to this SKILL.md's own directory. This list is the authoritative guard — keep it complete. If any path is missing, stop and print the `✗ Missing bundled dependency` block from `references/error-messages.md` (*Bundled dependencies*); never continue with an inline or guessed subagent prompt:

```text
references/agents/codebase-researcher.md
references/agents/synthesizer.md
references/agents/implementer.md
references/agents/code-reviewer.md
references/agents/ui-reviewer.md
references/agents/fixer.md
references/pipeline-steps.md
references/report-templates.md
references/run-stats.md
references/bug-verification.md
references/skill-index.md
references/error-messages.md
references/docs/sync-conventions.md
references/docs/naming-conventions.md
references/docs/pre-commit-security.md
references/docs/idd-methodology.md
references/docs/github-projects-sync.md
references/docs/run-log-schema.md
references/docs/config-schema.md
references/docs/agent-model-effort.md
references/docs/shared-agent-conventions.md
references/docs/platform-github.md
references/docs/terminal-style.md
references/docs/ui-review.md
references/scripts/gi-config.py
references/scripts/gi-runlog.py
references/scripts/gi-secscan.py
references/scripts/gi-branch.py
references/scripts/gi-gh.py
references/scripts/gi-issue.py
references/scripts/gi-state.py
```

---

## Pipeline Overview

6 steps (0-5) — Preflight, Research, Plan, Implement, QA, Deliver. Show progress with the `[N/5]` counter: each step prints a new line on start (`●`), updating to `✓`/`✗`. Static sequential output, no animation. Worked example in `references/report-templates.md` (*Expected Inline Pipeline Output*).

---

### Step completion reports

Each step closes with a completion report — `√`/`×` per check plus a `Result: PASS | PARTIAL | FAIL` line — so "step done" is checkable, not asserted. Check names, `Result` semantics and block format: `references/report-templates.md` (*Step Completion Reports*) — **read it now**, before Step 0. A step is not complete until its `Result:` line is printed.

---

## Step 0 — Preflight

Check whether this issue should be worked on. Open with `● Preflight check for issue #N...`.

### 0a — Fetch issue

The GitHub-backed helpers share the bundled subprocess boundary in `shared/scripts/gi-gh.py`. Classify any framed caller payload first (`/auto-pilot` captured it in mode-neutral *Step 1.2b*) — *Step 0i — Caller payload gate* in `references/pipeline-steps.md` is its single home: the framing, `issue_payload = supplied | partial | absent`, the mandatory live read `gh issue view N --json state,comments,updatedAt` under `supplied`, the exact match between retained and live `updatedAt` required before 0d, the discard-and-refresh fallback on any mismatch (applied identically to individual, array, and keyed-map payloads), and the rule that no safety check — 0a's two stops included — is ever decided from a payload. Then run `python3 shared/scripts/gi-issue.py {N} --fields number,title,body,labels,assignees,state,comments,updatedAt` and read `.issue`, except where that gate lets the payload stand in. **Capture `updatedAt` here** — 0d's `gh issue edit` bumps it, so *0h* must compare against this pre-normalization value. Resolve the script path as the *Bundled dependency precheck* resolves its list. Exit 3 stops; no `python3`, exit 2 or exit 4 degrades to `gh issue view {N} --json number,title,body,labels,assignees,state,comments,updatedAt` — the cache is an optimization, never a dependency. **0d rewrites the body, so it MUST end with `python3 shared/scripts/gi-issue.py {N} --invalidate`**, or Step 1 and Step 5 read the pre-normalization body. <!-- a:rs-0a-payload-concurrency -->

**If not found:** output error and stop. **If closed:** output warning and stop.

### 0b — Check for existing work

```bash
git branch -a | grep -i "{N}"                                # existing branches
gh pr list --state open --json number,title,body,headRefName --limit 20
```

Scan PR bodies for `Closes #N`, `Fixes #N`, `Resolves #N`. An **open** PR already targeting the issue prints the `⚠ PR already targets issue` block from `references/error-messages.md` (*Guards*) and stops — return `status: pr_in_progress` with its `pr_number` and `branch_name`, and **never close the issue**: an unreviewed, unmerged PR is not a resolution (`references/pipeline-steps.md` → *Early exit*). Only a **merged** PR or a closing commit on the default branch is `already_resolved`.

### 0c — Guards

**Interactive:** warn and ask if assigned to someone else or `wontfix`/`blocked`/`do-not-merge` labels exist. **Auto:** skip the assignment guard; log blocking labels, don't stop.

### 0d — Auto-normalize

If `issue.auto_normalize` is true and not already normalized (no `<!-- gitissue:normalized v1 -->` marker):

1. **Security label check (SPEC §1.4)** — before any rewrite, scan issue labels for `security`, `CVE`, or `vulnerability` (case-insensitive). If any match:
   - **Auto mode (`--auto` / `IDD_AUTO_MODE=1`):** print the `⚠ … Skipping auto-normalization` warning from `references/error-messages.md` (*Security-labeled issue (skip)*) — using the first matching label name for `{label}` — and continue preflight **without** rewriting the issue body.
   - **Interactive mode:** print the same warning and ask for explicit operator confirmation. Default is **no** — do not rewrite unless the operator clearly confirms (e.g. `y` / `yes`). If declined, continue without normalization.

2. **Normalize inline** — when no security label blocks (or the operator confirmed): classify the issue type, generate the normalized body, add the marker, post a backup comment carrying the original, `gh issue edit` the issue, invalidate the cache (`python3 shared/scripts/gi-issue.py {N} --invalidate`), then re-fetch. Same structure-only flow as `/issue-creator` Normalize mode, but the resolver does **not** invoke `/issue-creator` as a subprocess — Step 0d runs inline. On failure, warn and continue with the original body (`references/error-messages.md`).

### 0e — Workspace (interactive only)

Derive one `{branch_name}` before 0e or 0f picks a workspace: `python3 shared/scripts/gi-branch.py {N} --from-issue --type {type}`, reading `.branch`. **`--from-issue` is mandatory** — never put the issue title or the configured prefix on the command line; a title is attacker-controlled, and the flag makes the script read both values itself (`references/pipeline-steps.md` → *Step 0e — Workspace*). `{type}` is one of the six literals this skill classified, never free text. Exit 3 stops; no `python3`, exit 2 or exit 4 degrades to deriving the name by hand per `docs/naming-conventions.md`. Both workspace paths use this one name. Then decide *where* the work happens.

**Auto mode (`--auto` / `IDD_AUTO_MODE=1`): skip this offer entirely.** A set
`IDD_CALLER_WORKTREE=1` uses the validated caller-managed path in `references/pipeline-steps.md`; otherwise go to *0f* (legacy in-place). Neither auto path shows the prompt.

**Interactive mode:** offer a dedicated git *worktree* — an isolated checkout in a separate directory — so branch creation, implementation and testing never touch the user's current working tree. State what will be set up and the naming to expect:

```
◆ Workspace for issue #N
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  This resolution can run in an isolated git worktree instead of your
  current working tree.

    Branch:    {branch_name}
    Worktree:  ../{repo}-worktrees/{branch_name with / → -}
    Setup:     copies your gitignored local config (.env*, and similar),
               then runs this project's detected install/bootstrap so the
               workspace is ready to run without manual reconfiguration.

  Accepting keeps your current working tree untouched. Declining uses the current working tree with the existing sync and branch behavior.

  Resolve in a new worktree? [Y/n]
```

Accept replaces *0f — Create branch* and the mandatory Repo Sync; decline runs the mandatory Repo Sync then *0f — Create branch*. Creation commands, setup-artifact propagation, cleanup and fallback-on-failure are in `references/pipeline-steps.md` (*Step 0e — Workspace*) — never leave the user without a working resolution.

### 0f — Create branch

The **in-place path** — ordinary auto mode, or interactive after declining the offer. Accepted interactive and validated caller-managed paths already checked out the branch and skip this sub-step. Use the `{branch_name}` already derived (*0e — Workspace*, `docs/naming-conventions.md`); never re-derive it here.

**If the branch already exists:** interactive asks `continue` or `fresh`; auto takes `continue` (checkout the existing branch).

### 0g — Complexity gate (select the pipeline profile)

Decide **before Step 1** how much pipeline this issue earns. Mechanism, the shared `XS … XL` scale and the safety rules live once in `docs/agent-model-effort.md` (*Complexity → pipeline profile*); this sub-step is only the entry point.

`resolve.adaptive_effort: false` skips the gate: `profile = full`. Otherwise select from the issue's **pre-work `Effort` band** (the `XS … XL` value in `## Metadata`, written by `/issue-creator`) — never from a later agent output, so the saving is real:

- `Effort` `XS`/`S`, asserted (not `(needs review)`/low-confidence) → `profile = light`
- `Effort` `M`/`L`/`XL` → `profile = full`
- `Effort` `XS`/`S` but low-confidence, **or** absent/unparseable → `profile = full` (ambiguous → fuller)

**What `light` collapses — the single home for this rule.** `full` changes nothing.
Per-step mechanics: `references/pipeline-steps.md` (*Step N → `light` profile*).

| Step | `light` behavior |
|------|------------------|
| 1 — Research | Lighter pass: the already-resolved check and a focused scan of the obviously-affected file(s) still run; skip the broad dependency trace and external solution research. |
| 2 — Plan | Skip the 3-option synthesis — do **not** spawn the synthesizer; derive a **direct minimal plan** inline and record it as the selected option so the Decision Record keeps a real `Selected option`, and the design-confirm checkpoint does not apply. **Unless *0h* set `analysis_reuse = fresh`**: then *Step 2 — Plan → `reuse`* governs, options are **lifted** from the analysis rather than derived, and the design-confirm checkpoint **does** apply. |
| 3 — Propose relevant skills | Skip the **propose/install** — set `selected_skills = []` and go straight to the implementer, as auto mode does. **Leftover teardown still runs** (`references/pipeline-steps.md` → *Step 3 — Propose relevant skills*): a `light` run still releases skills a crashed run borrowed. The one path without teardown is a parallel lane (`IDD_CALLER_WORKTREE=1`), which disables borrowing outright. |
| 4 — QA | Cap the review-fix loop at **1** cycle instead of `resolve.qa_max_cycles`: one review pass, fix once if blocking, deliver. One reviewer spawn still runs — less depth, never no review. UI review stays auto-detected. |
| 5 — Deliver | **Unchanged** — always emits the Decision Record and Acceptance Criteria Verification table. The profile never removes durable memory. |

The profile may only be **revised upward** later (Step 1 reports `high`/`complex` on an `S` band → `full` for the rest); never downgrade mid-pipeline. Then surface it — `{workspace_note}` is ` (worktree)` in a worktree, empty otherwise; print `effort: full` even when `resolve.adaptive_effort` is `false`:
```
[0/5] Preflight    ✓ issue #N open, branch: {branch_name}{workspace_note}, effort: {profile}
```

### 0h — Analysis reuse gate <!-- a:rs-0h-skill -->

Set `analysis_reuse` to `fresh`, `stale` or `absent` by the five-condition predicate in `references/pipeline-steps.md` (*Step 0h — Analysis reuse gate*) — its **single home**. `fresh` seeds Step 1's research and skips Step 2's synthesizer; `stale`/`absent` run the full pipeline. Any doubt — missing key, short SHA, unparsable timestamp, failed `git` call — is `stale` (fail-safe). Skipped, like *0g*, when `resolve.adaptive_effort` is `false`; no new config key.

---

## Step 1 — Research

Understand the issue, the affected code and the candidate solutions; the same pass verifies the issue is not already fixed (the early-exit path closes it in auto mode). Spawn the researcher (`shared/agents/codebase-researcher.md`) with the canonical pattern. Payload, phases, early exit and inline fallback: `references/pipeline-steps.md` (*Step 1 — Research*).

**Profiles.** `light` — a lighter pass; see the profile table in *Step 0g*, mechanics in *Step 1 — Research → `light` profile*. A `high`/`complex` signal revises the profile **upward** to `full`, never downward. `analysis_reuse = fresh` (*0h*) — pass `prior_analysis` and run the seeded **verify-first** pass: hints to confirm or refute, never to trust; the already-resolved check still runs in full (*→ `reuse`*). Pass the optional sibling key `triage_context` too: it carries **no commit pin**, so it may only **reorder** a scan, never skip a phase (*→ `triage_context`*).

After research:
```
[1/5] Research     ✓ read {N} files, complexity: {level}
```

---

## Step 2 — Plan

Generate implementation options and select one. Spawn the synthesizer (`shared/agents/synthesizer.md`) with the canonical pattern; it returns 3 options — minimal / balanced / comprehensive — with balanced usually recommended. Selection behavior and inline fallback: `references/pipeline-steps.md` (*Step 2 — Plan*).

**Profiles.** `light` — skip the 3-option synthesis; see the profile table in *Step 0g*, procedure in *Step 2 — Plan → `light` profile*. `analysis_reuse = fresh` (*0h*) skips the same spawn but **wins Step 2 when both apply** — a replacement, not an addition: lift `options[]`, `recommended_option`, `overall_complexity` and `overall_risk` from the analysis instead of deriving a minimal plan, and each `rejection_reason` from `decision_record.options_rejected[]` (*→ `reuse`*).

After plan selection:
```
[2/5] Plan         ✓ approach: {selected option name}
```

### Design-confirm checkpoint (high-complexity, interactive only)

High-risk work earns **exactly one** extra agreement point before code is written. Fires only when **both** hold: the synthesizer reports `overall_complexity: L`/`XL` or `overall_risk: High`, **and** interactive mode (`--auto`/`IDD_AUTO_MODE=1` never pauses). Accept (default) → Step 3 unchanged; decline → stop before implementing and suggest re-running or a different option. Record it in the PR Decision Record. Procedure: `references/pipeline-steps.md` (*Step 2 — Plan → Design-confirm checkpoint*).

---

## Step 3 — Implement

### Propose relevant skills

Before spawning the implementer, optionally augment it with external skills from `references/skill-index.md`. Detect (installed vs available-to-borrow when `resolve.borrow_skills` is true), propose, accept into `selected_skills`; internal agents remain the fallback. Borrow/install, `{name, origin}` records via `shared/scripts/gi-state.py`, teardown of `origin: borrowed` only, the `◆`/`○` block, leftover cleanup, and auto-mode are in `references/pipeline-steps.md` (*Step 3 — Propose relevant skills*).

**`light` profile:** skip the propose/install — see the profile table in *Step 0g* — but **still run the leftover teardown** in `references/pipeline-steps.md`.

Write code and tests based on the selected plan. Spawn the implementer (`shared/agents/implementer.md`) with the canonical pattern, passing the plan, branch name, naming conventions, and `selected_skills`.

For **bug** issues, the implementer first runs the red-capable reproduction checkpoint — reproduce the symptom, confirm it fails red, fix, then convert to a regression test. Surfaced as evidence in the PR Decision Record and acceptance table. Non-bug issues skip it; auto mode never blocks. See `references/bug-verification.md`.

Full payload, commit guardrails, and inline fallback are in `references/pipeline-steps.md` (*Step 3 — Implement*).

After implementation:
```
[3/5] Implement    ✓ {N} files changed, {U} unit tests, {E} e2e tests
```

---

## Step 4 — QA

Automated review-fix loop: review → test → fix → repeat until clean or max cycles reached.

### Spawning the code reviewer

For each QA cycle, spawn a **fresh** reviewer (`shared/agents/code-reviewer.md`) with the canonical pattern — fresh each cycle for unbiased review.

When the reviewer or test/build run returns blocking issues, spawn or re-message the fixer (`shared/agents/fixer.md`) the same way. Pass issue context, branch/base branch, reviewer findings, failing test/build output, commit message `fix({scope}): address review feedback (#N)`, and the pre-commit security gate it MUST run before committing — `security_convention` (`references/docs/pre-commit-security.md`), `secscan_script` (`references/scripts/gi-secscan.py`) and `secscan_policy_ref` (`origin/${base}`) as spawn variables, because an emitted agent prompt cannot resolve a skill-relative path on its own. Paths and a ref name only — the script reads `security.*` from that ref itself, so the branch being fixed never supplies the policy that scans it. Collect the fixer's JSON result and decide whether to start another cycle — never apply fixes inline when the Agent tool is available.

### UI/UX review (auto-detected)

UI review is **auto-detected per issue** — no config flag enables it. Scan the issue body/diff for UI work before the QA cycles, then run only what *can* and *should* run: the **code UI review** reads the diff, is environment-independent, and runs anywhere including headless (never gated on a GUI/browser); the **browser UI review** takes optional screenshots from a running app and runs only when reachable *and* opted in, else **skips with a warning while the code UI review still runs** — fail-soft.

Detection rules, the `ui-reviewer` spawn, the `ui_review.browser_review` gate, and skip/success messages are in `docs/ui-review.md`; the resolver's own deltas (diff command, variables, `resolve.ui_review.browser_review` as the gate key, findings flow) are in `references/pipeline-steps.md` (*Step 4 — UI/UX review*). Cycle mechanics and loop controls (`resolve.qa_max_cycles`, exit-on-clean, exit-on-stagnation) are in the same file (*Step 4 — QA*).

**`light` profile:** cap the review-fix loop at **1** cycle instead of
`resolve.qa_max_cycles` — see the profile table in *Step 0g*. Class policy: light=1; full+low/medium=2; full+high=`qa_max_cycles`. Record `ceiling`/`breach_reason`.

---

## Step 5 — Deliver

Push, create PR, and report.

### Verify all tests pass

When `resolve.auto_test` is true (default), run the full test suite one final time to confirm everything is clean after QA fixes. When false, skip this suite (QA Step 4 may still have run tests during the loop). **Under `auto_test`, not over it:** when `tests_state`'s SHA equals `git rev-parse HEAD` **and `git status --porcelain=v1 --untracked-files=all` is empty** at this moment, a clean QA cycle already ran this exact suite on this exact tree — skip it and print `○ Test suite: skipped (last green {count}@{sha_short} == HEAD)`. Nothing recorded, or any doubt, runs it (`references/pipeline-steps.md`, *Step 4 — QA → Last-green test state*, the single home of the variable and both consumers). <!-- a:rs-deliver-clean-tree -->

If tests fail at this point, print `✗ Final test run failed — PR not created` with the failure details and stop — even in auto mode, a failing PR is worse than no PR.

### Update documentation

If the changes affect documented behavior, update README, inline docs, and CHANGELOG as applicable.

### Push branch and create PR

Before pushing, scan the whole branch diff — it catches secrets that slipped in during QA fixes. Export `IDD_AUTO_MODE=1` first in auto mode, then from the repo root run `python3 shared/scripts/gi-secscan.py --range "origin/${base}" --policy-ref "origin/${base}"`. It reads `security.*` from `.gitissue.yml` **at the base ref**: never pass a config
*value* on the command line, and never let the branch under scan supply the policy that
scans it. Why each rule below exists — `references/pipeline-steps.md` (*Step 5 — Deliver → Pre-push secret scan*).

- **Pass** needs all four: exit 0, `policy_source` equal to the `ref:origin/…` requested, `verdict` not `block`, and `scanned` not 0 while `skipped` is above 0.
- **Exit 1 is the block verdict** — stop, do not push, report the path from `blocking[]`. Never fall through to the prose scan hoping for a pass.
- **Exit 3** (uncompilable `security.*` regex) — also a stop.
- **No `python3`, exit 2, or exit 4** — degrade: print `⚠ gi-secscan unavailable — running the documented scan`, then run the **Primary Pattern** in `docs/pre-commit-security.md` over `git diff --name-only "origin/${base}"...HEAD`. Exit 1 with no parsable JSON on stdout is a crash, not a verdict — treat it as exit 2.

Never improvise a weaker check; never read a non-zero exit as a pass. Only after the scan passes (or warnings are accepted):

```bash
# gated by the gi-secscan.py pass above — see docs/pre-commit-security.md
git push -u origin {branch_name}
gh pr create --title "{pr_title}" --body "{pr_body}"
```

**PR title:** `{type}({scope}): {description} (#{issue_number})` (`docs/naming-conventions.md`)

**PR body:** fill *PR Body Template* in `references/report-templates.md` — Summary, Approach, **Decision Record** (from `.gitissue/analysis-<N>.json` if present, else synthesized), Changes, Test Results, **Acceptance Criteria Verification**. The last two are the durable analysis signal surviving squash-merge; never omit them (`docs/idd-methodology.md`). The template's **last line** is the `<!-- gitissue:qa v1 … -->` handoff marker: fill it in **only when QA exited clean**, otherwise drop the line — never append a second copy, because two markers make the consumer fall back to the full pipeline. Field derivation and the omit rules are in the same file (*QA handoff marker*); `head=` is `git rev-parse HEAD` taken after the last commit and immediately before `git push`.

### Project board sync

If `projects.sync_enabled` is true, update status to `status_map.done` (see `docs/github-projects-sync.md`). After delivery:
```
[5/5] Deliver      ✓ PR #{pr_number} created
```

### Run-log entry (monitoring)

At **every terminal outcome** — delivered PR (`success`), early exit because already fixed (`already_resolved`), or a failed step (`failed`) — append exactly **one JSON line** to `.gitissue/runs.jsonl`, **unless invoked with `--no-run-log`**, in which case append **nothing** and return the telemetry to the caller instead. `--no-run-log` enforces the **single writer** rule under `/auto-pilot` and is independent of `--auto`: a standalone `/issue-resolver <N> --auto` still writes. Field derivation and the full suppression rationale are in `references/report-templates.md` (*Run-log entry — field derivation and suppression*), which follows the schema in `docs/run-log-schema.md`.

```bash
# Exactly one of these runs. --echo validates the telemetry you return and writes nothing.
if [ -n "$no_run_log" ]; then printf '%s' "$run_json" | python3 shared/scripts/gi-runlog.py --echo; else printf '%s' "$run_json" | python3 shared/scripts/gi-runlog.py --append; fi
# Fallback when `python3` is unavailable or the script exits 4: mkdir -p .gitissue && printf '%s\n' "$run_json" >> .gitissue/runs.jsonl
```

**Exit 3:** the record itself is invalid — the script printed the reason on stderr and
wrote nothing. A stop, not a degrade: never append `$run_json` raw, because that writes the malformed line the script exists to reject. Correct the record and re-run, or drop the line.

Every other write failure (no `python3`, exit 2 for an unresolved script path or a malformed invocation, exit 4) is **non-fatal** — use the fallback append above and never block the reported run result. Only append; never rewrite or reorder existing lines.

---

## Closing Summary

After the pipeline completes, print **one** closing block carrying only what the live `[N/5]` tracker never printed: the outcome line, the `risk_rating`, and the single PR reference (number, title, URL, `Closes #N`). Repeating any tracker metric — per-step pass/fail, files read, complexity, option, files changed, test counts, QA cycles — is the duplication issue #165 removed. Use the matching variant in `references/report-templates.md` (*Closing Summary*): *Successful Resolution* (every step passed), *Resolution With Warnings* (QA left residual issues or another step warned), or *Already Resolved* (Step 0/1 found the issue already closed — no PR reference). The *Expected Inline Pipeline Output* example in the same file shows the tracker and closing block together. **Then the run-stats footer.** Close with the *Run Stats Footer* — `references/run-stats.md` — `elapsed`, `tokens` only where the host reported a count (otherwise left out), `agents`, run cost only, `n/a` for anything else undetermined. It is the last thing printed at **every** terminal outcome, including the ones that never reach this block: a preflight stop (`not found`, `closed`, `pr_in_progress`), an invalid-config stop, `already_resolved`, a blocked secret scan, a failed final test run, or any failed step.

---

## Auto-Pilot Mode

With `--auto` (or under `/auto-pilot`) the whole pipeline runs without user interaction. Each step above states its own auto behavior; these are the cross-cutting invariants:

- **Environment:** Export `IDD_AUTO_MODE=1` before any shell snippet that consults it (`docs/pre-commit-security.md`).
- **Workspace:** The default resolution path is in-place. Skip Step 0e and allow no `git worktree add` on the default resolution path; ordinary standalone auto mode and auto-pilot's default single-lane path run mandatory Repo Sync, then *0f*, exactly as before. A resolver launched by auto-pilot with `max_parallel > 1` may receive `IDD_CALLER_WORKTREE=1`; after the linked-worktree/branch validation in `references/pipeline-steps.md`, it uses that already-current workspace without creating, falling back from, or cleaning it up. The prompt never appears on either path.
- **Never blocks:** every decision point has a defined auto behavior — the per-step list is in `references/pipeline-steps.md` (*Auto-mode behavior by step*). Every terminal outcome still runs borrow teardown.
- **Deliver:** Create PR. Do NOT merge — merging is `/auto-pilot`'s or `/issue-pr-review`'s job. Under `/auto-pilot` the selected `profile` is **returned** in the telemetry (with `--no-run-log`) and folded into auto-pilot's single run-log line; a standalone `--auto` run writes `profile` itself.

No `[y/N]` prompts, no `Choose:` prompts, no `Continue?` prompts.

## Edge Cases

No acceptance criteria, empty issue body, large issues (20+ files), test failure/timeout, and branch-already-exists are all handled — full behavior for each is in `references/pipeline-steps.md` (*Edge Cases*).

## Platform Driver and Output Conventions

All tracker access follows the GitHub driver — `--json` with explicit field selection, never parsed text output. The full operation catalog and driver rules live in docs/platform-github.md.

Terminal output follows the `docs/terminal-style.md` contract — symbols `● ✓ ✗ ◆ ⚡ ⚠ ○`, two-space indent, `┄` separators, URLs on their own line, ≤80 chars, one blank line between sections, static sequential output (no animation), plus the `[N/5]` pipeline step counter. Errors use the rich format from `references/error-messages.md`: `✗ what failed`, then `To fix:  <command>`, then a docs link when applicable.
