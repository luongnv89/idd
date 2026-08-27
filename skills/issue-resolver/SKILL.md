---
name: issue-resolver
description: "Create an atomic PR closing a GitHub issue end-to-end via a 6-step pipeline. Use to resolve, fix, or implement issue #N. Don't use for analysis without fixing (/issue-analysis), reviewing a PR (/issue-pr-review), or bulk backlog work (/auto-pilot)."
license: MIT
compatibility: "Requires git and GitHub CLI (gh) with authentication and push access. Self-contained — uses shared agents from shared/agents/."
metadata:
  version: 0.18.0
  author: Luong NGUYEN <luongnv89@gmail.com>
  effort: max
---

# /issue-resolver N

Resolve a GitHub issue end-to-end — from issue to atomic PR in 6 steps.

## Invocation

| Invocation | Mode | What happens |
|------------|------|--------------|
| `/issue-resolver <N>` | interactive | Resolve issue #N; the user picks the plan |
| `/issue-resolver <N> --auto` | auto-pilot | Resolve autonomously, no prompts |
| `/issue-resolver <N> --no-run-log` | (modifier) | Append nothing to `.gitissue/runs.jsonl`; return telemetry to the caller |

`N` is a GitHub issue number; `--auto` is set by `/auto-pilot`; `--no-run-log` is **orthogonal to `--auto`** (*Step 5 — Deliver* → *Run-log entry*).

## Prerequisites

Required before any operation — git repository (`git rev-parse --git-dir`), `gh` installed (`which gh`) and authenticated (`gh auth status`), remote present (`git remote -v`). On failure print the error from `references/error-messages.md` and stop.

## Repo Sync Before Edits (mandatory)

In-place path only (auto mode, or interactive after declining Step 0e); worktree paths already start from the fetched base, and an invalid `IDD_CALLER_WORKTREE=1` is a stop, never a sync bypass. Use the **stash-first pattern**: copy the snippet and recovery procedure from `references/docs/sync-conventions.md` (*Quick Reference (Copy-Paste Snippet)*), never a bare rebase on a dirty tree. A missing `origin` or a conflict stops and asks (interactive), or aborts (auto).

## Configuration

Load config once; never re-read it. Run `python3 references/scripts/gi-config.py`, with two mandatory requirements — **Working directory:** the repo root; **Script path:** absolute, as the *Bundled dependency precheck* resolves its list. It prints `{"config": {…dotted keys…}, "config_file": …, "first_run": …}`, merging the defaults below with `.gitissue.yml`. Why each matters: `references/pipeline-steps.md` (*Configuration load*).

- **Exit 0** — use `config`; on `first_run` print `○ First run — using default config. Run /init-gitissue to customize.`
- **Exit 3** — invalid `.gitissue.yml`: print the error from `references/error-messages.md` (*Invalid config*), stop.
- **Script file absent** — a missing bundled dependency is a broken install and not a degrade: stop, print `✗ Missing bundled dependency`.
- **Anything else** (no `python3`, other non-zero exit, unparsable stdout) — print `⚠ gi-config unavailable — using the inline defaults below`, then read `.gitissue.yml` by hand, *instead of* the script.

**Capture the run clock here:** chain that same `python3` invocation as `python3 …; ec=$?; date +%s >&2; exit "$ec"`, keeping the stderr epoch as `run_started_epoch` — what the *Run Stats Footer* (`references/run-stats.md`) measures `elapsed` from.

Defaults and per-key behavior: `references/docs/config-schema.md` — `issue.auto_normalize` · `resolve.approval_gate` · `resolve.branch_prefix` · `resolve.auto_test` · `resolve.test_timeout` · `resolve.max_commits` · `resolve.qa_max_cycles` · `resolve.adaptive_effort` (*0g*) · `resolve.ui_review.browser_review` · `resolve.borrow_skills: false`.

---

## Subagent Architecture

Heavy work goes to subagents (`shared/agents/`), keeping the main agent's **context window** clean and its **token budget** predictable: it owns Step 0, Step 4's loop and Step 5; Steps 1-3 each spawn one. Diagram: *Subagent Architecture Diagram*. Prompts are bundled at `references/agents/<name>.md`; shared conventions in `references/docs/shared-agent-conventions.md`.

### Spawning a subagent (canonical pattern)

Only role, description and prompt file change. **Do NOT set `subagent_type`**:

```python
Agent(
  description="{role} — {action} issue #N",
  prompt=<{agent-file}.md prompt with {variables} replaced>,
  # do NOT set subagent_type — default general-purpose agent, never a custom type (e.g. NOT "code-reviewer")
)
```

### Orchestrating the agents (model/effort, monitoring, audit)

Per step: **name the role** in the spawn `description`; **size the model/effort** per `references/docs/agent-model-effort.md`; **monitor before advancing** — a missing or blocking return stops the run (interactive) or follows the auto behavior; **audit** the per-step signal. Return shapes and audited fields: *Orchestrating the agents*.

### Environment check

With the Agent tool, use subagents; without it (e.g. Claude.ai), run each step inline via its fallback.

### Bundled dependency precheck

Every path below must exist relative to this SKILL.md's own directory. A missing path stops the run: print the `✗ Missing bundled dependency` block from `references/error-messages.md` (*Bundled dependencies*), never a guessed prompt.

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

6 steps (0-5) — Preflight, Research, Plan, Implement, QA, Deliver — each printing a `[N/5]` line on start (`●`) that updates to `✓`/`✗`. Example: `references/report-templates.md` (*Expected Inline Pipeline Output*).

### Step completion reports

Each step closes with `√`/`×` per check plus a `Result: PASS | PARTIAL | FAIL` line — format in `references/report-templates.md` (*Step Completion Reports*), **read it now**. A step is not complete until its `Result:` line prints.

---

## Step 0 — Preflight

Open with `● Preflight check for issue #N...`.

### 0a — Fetch issue

GitHub reads share the boundary in `references/scripts/gi-gh.py`. Classify any framed caller payload first (`/auto-pilot` captured it in mode-neutral *Step 1.2b*); *Step 0i — Caller payload gate* in `references/pipeline-steps.md` is its single home — framing, `issue_payload = supplied | partial | absent`, the mandatory live `gh issue view N --json state,comments,updatedAt` under `supplied`, the exact match between retained and live `updatedAt` before 0d, discard-and-refresh on mismatch (identical for individual, array, and keyed-map payloads), no safety check decided from a payload. Then run `python3 references/scripts/gi-issue.py {N} --fields number,title,body,labels,assignees,state,comments,updatedAt`, reading `.issue` unless that gate substitutes the payload. **Capture `updatedAt` here** — 0d's `gh issue edit` bumps it, so *0h* compares against this pre-normalization value. Exit 3 stops; no `python3`, exit 2 or exit 4 degrades to `gh issue view {N} --json number,title,body,labels,assignees,state,comments,updatedAt`. **0d rewrites the body, so it MUST end with `python3 references/scripts/gi-issue.py {N} --invalidate`.** <!-- a:rs-0a-payload-concurrency -->

**Not found:** error, stop. **Closed:** warning, stop.

### 0b — Check for existing work

```bash
git branch -a | grep -i "{N}"                                # existing branches
gh pr list --state open --json number,title,body,headRefName --limit 20
```

Scan PR bodies for `Closes #N`, `Fixes #N`, `Resolves #N`. An **open** PR targeting the issue prints the `⚠ PR already targets issue` block from `references/error-messages.md` (*Guards*), stops, returns `status: pr_in_progress` with its `pr_number` and `branch_name`, and must **never close the issue** (*Early exit*). Only a **merged** PR, or a closing commit on the default branch, is `already_resolved`.

### 0c — Guards

**Interactive:** warn and ask if assigned to someone else, or on `wontfix`/`blocked`/`do-not-merge` labels. **Auto:** skip the assignment guard; log blocking labels, do not stop.

### 0d — Auto-normalize

If `issue.auto_normalize` is true and the body has no `<!-- gitissue:normalized v1 -->` marker:

1. **Security label check (SPEC §1.4)** — before any rewrite, scan labels for `security`, `CVE`, `vulnerability` (case-insensitive). On a match:
   - **Auto mode (`--auto` / `IDD_AUTO_MODE=1`):** print the `⚠ … Skipping auto-normalization` warning (`references/error-messages.md` → *Security-labeled issue (skip)*) with the first matching label as `{label}`, and continue **without** rewriting.
   - **Interactive mode:** same warning, then ask for explicit operator confirmation; default **no**, and a decline continues without normalization.

2. **Normalize inline** — when nothing blocks: classify the type, generate the body, add the marker, back up the original in a comment, `gh issue edit`, invalidate the cache (`python3 references/scripts/gi-issue.py {N} --invalidate`), re-fetch. Structure-only, as `/issue-creator` Normalize mode, but the resolver does **not** invoke `/issue-creator` as a subprocess. On failure, warn and keep the original body.

### 0e — Workspace (interactive only)

Derive one `{branch_name}` first: `python3 references/scripts/gi-branch.py {N} --from-issue --type {type}`, reading `.branch`. **`--from-issue` is mandatory** — never put the issue title or configured prefix on the command line (`references/pipeline-steps.md` → *Step 0e — Workspace*). `{type}` is one of six classified literals. Exit 3 stops; no `python3`, exit 2 or exit 4 degrades to `references/docs/naming-conventions.md`. Both paths use this name.

**Auto mode (`--auto` / `IDD_AUTO_MODE=1`): skip this offer entirely.** A set `IDD_CALLER_WORKTREE=1` uses the validated caller-managed path in `references/pipeline-steps.md`; otherwise go to *0f*.

**Interactive mode:** offer a git *worktree*, so the work never touches the user's tree:

```
◆ Workspace for issue #N
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

    Branch:    {branch_name}
    Worktree:  ../{repo}-worktrees/{branch_name with / → -}
    Setup:     copies your gitignored local config (.env*, and similar),
               then runs this project's detected install/bootstrap.

  Accepting keeps your current working tree untouched. Declining uses the current working tree with the existing sync and branch behavior.

  Resolve in a new worktree? [Y/n]
```

Accept replaces *0f — Create branch* and the mandatory Repo Sync; decline runs the mandatory Repo Sync then *0f — Create branch*. Creation, setup, cleanup: *Step 0e — Workspace*.

### 0f — Create branch

The **in-place path** — ordinary auto mode, or interactive after declining; worktree paths already checked out the branch. Reuse the derived `{branch_name}` (*0e — Workspace*, `references/docs/naming-conventions.md`). **If it exists:** interactive asks `continue` or `fresh`; auto takes `continue`.

### 0g — Complexity gate (select the pipeline profile)

Decide **before Step 1** how much pipeline this issue earns; the `XS … XL` scale and safety rules live in `references/docs/agent-model-effort.md` (*Complexity → pipeline profile*). `resolve.adaptive_effort: false` pins `profile = full`; otherwise read the **pre-work `Effort` band** in `## Metadata`, never a later agent output:

- `XS`/`S`, asserted (not `(needs review)`) → `light`
- `M`/`L`/`XL` → `full`
- `XS`/`S` low-confidence, **or** absent/unparseable → `full` (ambiguous → fuller)

**What `light` collapses — the single home for this rule.** `full` changes nothing. Mechanics: `references/pipeline-steps.md` (*Step N → `light` profile*).

| Step | `light` behavior |
|------|------------------|
| 1 — Research | Lighter pass; the already-resolved check still runs. |
| 2 — Plan | Do **not** spawn the synthesizer; derive a minimal plan inline, and the design-confirm checkpoint does not apply. **Unless *0h* set `analysis_reuse = fresh`**: *Step 2 — Plan → `reuse`* governs, options are **lifted**, and the design-confirm checkpoint **does** apply. |
| 3 — Propose relevant skills | Skip propose/install; `selected_skills = []`. **Leftover teardown still runs** (*Step 3 — Propose relevant skills*), except in a parallel lane (`IDD_CALLER_WORKTREE=1`). |
| 4 — QA | Cap the loop at **1** cycle; one reviewer spawn still runs. |
| 5 — Deliver | **Unchanged**. |

Revise **upward** only. `{workspace_note}` is ` (worktree)` in a worktree, empty otherwise; `effort: full` prints even when `resolve.adaptive_effort` is `false`:
```
[0/5] Preflight    ✓ issue #N open, branch: {branch_name}{workspace_note}, effort: {profile}
```

### 0h — Analysis reuse gate <!-- a:rs-0h-skill -->

Set `analysis_reuse` to `fresh`, `stale` or `absent` by the five-condition predicate in `references/pipeline-steps.md` (*Step 0h — Analysis reuse gate*) — its **single home**. `fresh` seeds Step 1 and skips Step 2's synthesizer; `stale`/`absent` run the full pipeline. Any doubt is `stale` (fail-safe). Skipped, like *0g*, when `resolve.adaptive_effort` is `false`.

---

## Step 1 — Research

Understand the issue, the affected code and candidate solutions; the same pass verifies it is not already fixed (auto mode then closes it and exits). Spawn the researcher (`references/agents/codebase-researcher.md`). Payload, phases, early exit, fallback: `references/pipeline-steps.md` (*Step 1 — Research*).

**Profiles.** `light` — see the profile table in *Step 0g*; a `high`/`complex` signal revises **upward** to `full`, never downward. `analysis_reuse = fresh` (*0h*) — pass `prior_analysis` for the seeded **verify-first** pass: confirm or refute, never trust, with the already-resolved check still run in full. `triage_context` has no commit pin, so it may only **reorder** a scan (*→ `reuse`*, *→ `triage_context`*).

```
[1/5] Research     ✓ read {N} files, complexity: {level}
```

---

## Step 2 — Plan

Generate options and select one. Spawn the synthesizer (`references/agents/synthesizer.md`); it returns minimal / balanced / comprehensive, balanced usually recommended. Selection and fallback: *Step 2 — Plan*.

**Profiles.** `light` — skip the synthesis; see the profile table in *Step 0g*. `analysis_reuse = fresh` (*0h*) skips the same spawn but **wins Step 2 when both apply** — a replacement, not an addition: lift `options[]`, `recommended_option`, `overall_complexity` and `overall_risk` from the analysis, each `rejection_reason` from `decision_record.options_rejected[]` (*→ `reuse`*).

```
[2/5] Plan         ✓ approach: {selected option name}
```

### Design-confirm checkpoint (high-complexity, interactive only)

**Exactly one** extra agreement point before code is written, only when **both** hold: `overall_complexity: L`/`XL` or `overall_risk: High`, **and** interactive mode (`--auto`/`IDD_AUTO_MODE=1` never pauses). Accept (default) → Step 3; decline → stop before implementing, recording it in the PR Decision Record. Procedure: *Step 2 — Plan → Design-confirm checkpoint*.

---

## Step 3 — Implement

### Propose relevant skills

Optionally augment the implementer with external skills from `references/skill-index.md`: detect, propose, accept into `selected_skills`; internal agents stay the fallback. Borrow/install, `{name, origin}` records via `references/scripts/gi-state.py`, teardown of `origin: borrowed` only, the `◆`/`○` block and auto-mode: `references/pipeline-steps.md` (*Step 3 — Propose relevant skills*).

**`light` profile:** skip the propose/install — see the profile table in *Step 0g* — but **still run the leftover teardown** there.

Then spawn the implementer (`references/agents/implementer.md`) with the plan, branch name, naming conventions and `selected_skills`. **Bug** issues first run the red-capable reproduction checkpoint — reproduce, confirm red, fix, convert to a regression test — surfaced in the Decision Record and acceptance table; other issues skip it, and auto mode never blocks (`references/bug-verification.md`). Payload, commit guardrails, fallback: *Step 3 — Implement*.

```
[3/5] Implement    ✓ {N} files changed, {U} unit tests, {E} e2e tests
```

---

## Step 4 — QA

Automated loop: review → test → fix → repeat until clean or the cap is hit.

### Spawning the code reviewer

Spawn a **fresh** reviewer (`references/agents/code-reviewer.md`) each cycle. On blocking issues from the reviewer or a test/build run, spawn or re-message the fixer (`references/agents/fixer.md`) with issue context, branch/base branch, findings, failing output, the commit message `fix({scope}): address review feedback (#N)`, and the pre-commit security gate it MUST run before committing — `security_convention` (`references/docs/pre-commit-security.md`), `secscan_script` (`references/scripts/gi-secscan.py`) and `secscan_policy_ref` (`origin/${base}`) as spawn variables; paths and a ref name only. Read the fixer's JSON result and decide on another cycle — never fix inline when the Agent tool is available.

### UI/UX review (auto-detected)

UI review is **auto-detected per issue** — no config flag enables it. Scan the issue body and diff for UI work before the cycles. The **code UI review** is environment-independent and always runs; the **browser UI review** runs only when a running app is reachable *and* opted in, else **skips with a warning while the code UI review still runs**. Detection, the `ui-reviewer` spawn and the `ui_review.browser_review` gate: `references/docs/ui-review.md`. Resolver deltas and cycle mechanics (`resolve.qa_max_cycles`, exit-on-clean, exit-on-stagnation): `references/pipeline-steps.md` (*Step 4 — UI/UX review*, *Step 4 — QA*).

**`light` profile:** cap the loop at **1** cycle instead of `resolve.qa_max_cycles` — see the profile table in *Step 0g*. Class policy: light=1; full+low/medium=2; full+high=`qa_max_cycles`. Record `ceiling`/`breach_reason`.

---

## Step 5 — Deliver

Push, create the PR, report.

### Verify all tests pass

With `resolve.auto_test` true (default), run the full suite once more after the QA fixes; false skips it. **Under `auto_test`, not over it:** when `tests_state`'s SHA equals `git rev-parse HEAD` **and `git status --porcelain=v1 --untracked-files=all` is empty**, a clean QA cycle already ran this suite on this tree — skip it, print `○ Test suite: skipped (last green {count}@{sha_short} == HEAD)`. Nothing recorded, or any doubt, runs it (*Step 4 — QA → Last-green test state*, the single home of the variable and both consumers). <!-- a:rs-deliver-clean-tree -->

A failure prints `✗ Final test run failed — PR not created` and stops, even in auto mode.

### Update documentation

If the change affects documented behavior, update README, inline docs and CHANGELOG.

### Push branch and create PR

Scan the branch diff first. Export `IDD_AUTO_MODE=1` in auto mode, then from the repo root run `python3 references/scripts/gi-secscan.py --range "origin/${base}" --policy-ref "origin/${base}"`. It reads `security.*` from `.gitissue.yml` **at the base ref**: never pass a config *value* on the command line, never let the scanned branch supply its own policy (*Pre-push secret scan*).

- **Pass** needs all four: exit 0, `policy_source` equal to the `ref:origin/…` requested, `verdict` not `block`, `scanned` not 0 while `skipped` is above 0.
- **Exit 1 is the block verdict** — stop, do not push, report `blocking[]`. **Exit 3** (uncompilable `security.*` regex) also stops.
- **No `python3`, exit 2, exit 4** — degrade: print `⚠ gi-secscan unavailable — running the documented scan` and run the **Primary Pattern** in `references/docs/pre-commit-security.md` over `git diff --name-only "origin/${base}"...HEAD`. Exit 1 without parsable JSON is a crash — treat it as exit 2.

Never read a non-zero exit as a pass. Only after the scan passes:

```bash
# gated by the gi-secscan.py pass above — see references/docs/pre-commit-security.md
git push -u origin {branch_name}
gh pr create --title "{pr_title}" --body "{pr_body}"
```

**PR title:** `{type}({scope}): {description} (#{issue_number})` (`references/docs/naming-conventions.md`)

**PR body:** fill *PR Body Template* in `references/report-templates.md` — Summary, Approach, **Decision Record**, Changes, Test Results, **Acceptance Criteria Verification**; never omit the last two (`references/docs/idd-methodology.md`). Its **last line** is the `<!-- gitissue:qa v1 … -->` marker: fill it **only when QA exited clean**, else drop the line — never append a second copy (*QA handoff marker*). `head=` is `git rev-parse HEAD` after the last commit.

### Project board sync

With `projects.sync_enabled` true, set status to `status_map.done` (`references/docs/github-projects-sync.md`).
```
[5/5] Deliver      ✓ PR #{pr_number} created
```

### Run-log entry (monitoring)

At **every terminal outcome** — `success`, `already_resolved`, or `failed` — append exactly **one JSON line** to `.gitissue/runs.jsonl`, **unless invoked with `--no-run-log`**, which appends **nothing** and returns the telemetry instead. That enforces the **single writer** rule under `/auto-pilot`, independently of `--auto`: a standalone `/issue-resolver <N> --auto` still writes. Derivation and suppression: `references/report-templates.md` (*Run-log entry — field derivation and suppression*), following `references/docs/run-log-schema.md`.

```bash
# Exactly one of these runs. --echo validates the telemetry you return and writes nothing.
if [ -n "$no_run_log" ]; then printf '%s' "$run_json" | python3 references/scripts/gi-runlog.py --echo; else printf '%s' "$run_json" | python3 references/scripts/gi-runlog.py --append; fi
# Fallback when `python3` is unavailable or the script exits 4: mkdir -p .gitissue && printf '%s\n' "$run_json" >> .gitissue/runs.jsonl
```

**Exit 3:** the record is invalid and nothing was written. A stop, not a degrade: never append `$run_json` raw. Correct the record and re-run, or drop the line. Every other write failure (no `python3`, exit 2, exit 4) is **non-fatal** — use the fallback append, never block the reported result. Only append; never rewrite or reorder lines.

---

## Closing Summary

Print **one** closing block carrying only what the `[N/5]` tracker never printed: the outcome line, `risk_rating`, and the PR reference (number, title, URL, `Closes #N`). Never repeat a tracker metric. Use the matching variant in `references/report-templates.md` (*Closing Summary*). **Then the run-stats footer** — `references/run-stats.md`: elapsed, tokens only where the host reported a count (otherwise left out), agents, run cost only, `n/a` for anything undetermined. It is the last thing printed at **every** terminal outcome, including those that never reach this block — a preflight stop (`not found`, `closed`, `pr_in_progress`), an invalid-config stop, `already_resolved`, a blocked secret scan, a failed final test run, or any failed step.

---

## Auto-Pilot Mode

With `--auto` (or under `/auto-pilot`) the pipeline runs without user interaction. Each step states its own auto behavior; the cross-cutting invariants:

- **Environment:** export `IDD_AUTO_MODE=1` before any shell snippet that consults it (`references/docs/pre-commit-security.md`).
- **Workspace:** in-place is the default resolution path. Skip Step 0e and allow no `git worktree add` on the default resolution path; run mandatory Repo Sync, then *0f*. With `max_parallel > 1` a resolver may receive `IDD_CALLER_WORKTREE=1` and use that already-current workspace, without creating or cleaning it up.
- **Never blocks:** every decision point has a defined auto behavior (*Auto-mode behavior by step*). Every terminal outcome still runs borrow teardown.
- **Deliver:** create the PR; never merge — `/auto-pilot`'s or `/issue-pr-review`'s job. Under `/auto-pilot` the `profile` is **returned** in the telemetry; a standalone `--auto` run writes it.

No `[y/N]`, `Choose:` or `Continue?` prompts.

## Edge Cases

Missing acceptance criteria, an empty issue body, large issues (20+ files), test failure or timeout, and branch-already-exists are handled — behavior per edge case in *Edge Cases*.

## Platform Driver and Output Conventions

Tracker access follows the GitHub driver — `--json` with explicit field selection, never parsed text; catalog in references/docs/platform-github.md. Output follows `references/docs/terminal-style.md` — `● ✓ ✗ ◆ ⚡ ⚠ ○`, two-space indent, `┄` separators, URLs on their own line, ≤80 chars, plus the `[N/5]` counter. Errors use `references/error-messages.md`'s rich format: `✗ what failed`, `To fix:  <command>`, a docs link.
