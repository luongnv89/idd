---
name: issue-resolver
description: "Create an atomic PR closing a GitHub issue end-to-end via a 6-step pipeline. Use to resolve, fix, or implement issue #N. Don't use for analysis without fixing (/issue-analysis), reviewing a PR (/issue-pr-review), or bulk backlog work (/auto-pilot)."
license: MIT
compatibility: "Requires git and GitHub CLI (gh) with authentication and push access. Self-contained — uses shared agents from shared/agents/."
metadata:
  version: 0.20.1
  author: "Luong NGUYEN <luongnv89@gmail.com>"
  effort: max
---

# /issue-resolver N

Issue → atomic PR in 6 steps.

## Invocation

| Invocation (`N` = issue number) | What happens |
|------------|--------------|
| `/issue-resolver <N>` | Interactive; user picks the plan |
| `/issue-resolver <N> --auto` | No prompts; set by `/auto-pilot` |
| `/issue-resolver <N> --no-run-log` | Modifier, **orthogonal to `--auto`**: append nothing to `.idd/runs.jsonl`, return telemetry (*Run-log entry*) |

## Prerequisites

Run these checks in order before any operation. A non-zero exit or empty output stops the run: print that check's `references/error-messages.md` error and the *Closing Summary* `BLOCKED` block.

1. Git repository: `git rev-parse --git-dir`.
2. `gh` installed: `which gh`.
3. `gh` authenticated: `gh auth status`.
4. Remote present: `git remote -v` prints at least one line.

## Repo Sync Before Edits (mandatory)

In-place path only; worktree paths start from the fetched base, and an invalid `IDD_CALLER_WORKTREE=1` is a stop, never a sync bypass. Use the **stash-first pattern**: copy the snippet and recovery from `docs/sync-conventions.md` (*Quick Reference (Copy-Paste Snippet)*), never a bare rebase on a dirty tree. A missing `origin` or a conflict stops and asks (interactive), or aborts (auto).

## Configuration

Load config once; never re-read it. Run `python3 shared/scripts/gi-config.py` — **Working directory:** the repo root; **Script path:** absolute, as the *Bundled dependency precheck* resolves its list. It prints `{"config": …, "config_file": …, "first_run": …}` merged over the defaults below (rationale: `references/steps/step-0-preflight.md`, *Configuration load*).

- **Exit 0** — use `config`.
- **Exit 3** — invalid `.idd.yml`: print the `references/error-messages.md` error (*Invalid config*), stop.
- **Script file absent** — a broken install and not a degrade: stop, print `✗ Missing bundled dependency`.
- **Anything else** (no `python3`, non-zero exit, unparsable stdout) — print `⚠ gi-config unavailable — reading .idd.yml by hand` and read it yourself *instead of* the script (else legacy `.gitissue.yml`, printing `⚠ legacy .gitissue.yml found — rename to .idd.yml`), over the keys and defaults below.

Either path: no `.idd.yml` (`first_run`) prints `○ First run — using default config. Run /init-idd to customize.`

**Capture the run clock here:** chain that same `python3` invocation as `python3 …; ec=$?; date +%s >&2; exit "$ec"`; the stderr epoch is `run_started_epoch`, the *Run Stats Footer*'s `elapsed` anchor. Take `date +%s` again as each `[N/5]` step starts and at the terminal outcome: those boundaries are the run log's `phases` (`references/report-templates.md`).

Defaults and behavior per key: `docs/config-schema.md` — `issue.auto_normalize` · `resolve.approval_gate` · `resolve.branch_prefix` · `resolve.auto_test` · `resolve.test_timeout` · `resolve.max_commits` · `resolve.qa_max_cycles` · `resolve.adaptive_effort` · `resolve.ui_review.browser_review` · `resolve.borrow_skills: false`.

---

## Subagent Architecture

Heavy work goes to subagents (`shared/agents/`), keeping the main agent's **context window** lean: it owns Step 0, Step 4's loop and Step 5; Steps 1-3 each spawn one (*Subagent Architecture Diagram*). Prompts: `references/agents/<name>.md`; conventions: `docs/shared-agent-conventions.md`. Without the Agent tool (e.g. Claude.ai), run each step inline via its fallback instructions.

### Spawning a subagent (canonical pattern)

Role, description and prompt file change per step. **Do NOT set `subagent_type`**:

```python
Agent(
  description="{role} — {action} issue #N",
  prompt=<{agent-file}.md prompt with {variables} replaced>,
  # never subagent_type — the default general-purpose agent, not "code-reviewer"
)
```

**Per-role overrides:** at every spawn apply `docs/agent-overrides.md` — the resolved `agents.model.<role>` / `agents.effort.<role>` for the spawned role (`codebase-researcher`, `synthesizer`, `implementer`, `code-reviewer`, `ui-reviewer`, `fixer`); `null` (the default) passes nothing.

### Orchestrating the agents

Name the role in `description`, size model/effort per `docs/agent-model-effort.md`, and read each return before advancing: a missing or blocking return stops (interactive) or takes the auto behavior (*Orchestrating the agents*).

### Bundled dependency precheck

Check every path below exists relative to this SKILL.md's directory. A missing path stops the run: print the `✗ Missing bundled dependency` block from `references/error-messages.md` (*Bundled dependencies*); never guess a prompt.

```text
references/agents/codebase-researcher.md
references/agents/synthesizer.md
references/agents/implementer.md
references/agents/code-reviewer.md
references/agents/ui-reviewer.md
references/agents/fixer.md
references/pipeline-steps.md
references/steps/step-0-preflight.md
references/steps/step-0h-analysis-reuse.md
references/steps/step-0i-caller-payload.md
references/steps/step-1-research.md
references/steps/step-2-plan.md
references/steps/step-3-implement.md
references/steps/step-4-qa.md
references/steps/step-5-deliver.md
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
references/docs/agent-overrides.md
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
references/scripts/gi-receipt.py
references/scripts/gi-sensitive.py
references/scripts/gi-premise.py
references/scripts/gi-sketch.py
references/scripts/gi-recipe.py
```

---

## Pipeline Overview

6 steps (0-5) — Preflight, Research, Plan, Implement, QA, Deliver — each printing a `[N/5]` line (`●` → `✓`/`✗`); expected output example: `references/report-templates.md` (*Expected Inline Pipeline Output*).

### Step completion reports

Each step closes with `√`/`×` per check and a `Result: PASS | PARTIAL | FAIL` line (*Step Completion Reports* in `references/report-templates.md`, **read it now**). A step is incomplete until `Result:` prints.

---

## Step 0 — Preflight

Open with `● Preflight check for issue #N...`.

### 0a — Fetch issue

GitHub reads share the boundary in `shared/scripts/gi-gh.py`. Classify any framed caller payload first (`/auto-pilot` captured it in mode-neutral *Step 1.2b*); *Step 0i — Caller payload gate* in `references/steps/step-0i-caller-payload.md` is its single home — `issue_payload = supplied | partial | absent`, the mandatory live `gh issue view N --json state,comments,updatedAt` under `supplied`, the exact match between retained and live `updatedAt` before 0d, discard-and-refresh on mismatch (identical for individual, array, and keyed-map payloads), never a gate. Then run `python3 shared/scripts/gi-issue.py {N} --fields number,title,body,labels,assignees,state,comments,updatedAt`, reading `.issue` unless the gate substitutes a payload. **Capture `updatedAt` here** — 0d's `gh issue edit` bumps it, so *0h* uses this pre-normalization value. Exit 3 stops; anything else degrades to `gh issue view {N} --json number,title,body,labels,assignees,state,comments,updatedAt`. **0d rewrites the body, so it MUST end with `python3 shared/scripts/gi-issue.py {N} --invalidate`.** <!-- a:rs-0a-payload-concurrency -->

**Not found:** error, stop. **Closed:** warning, stop.

### 0b — Check for existing work

1. List branches: `git branch -a | grep -i "{N}"`.
2. List open PRs: `gh pr list --state open --json number,title,body,headRefName --limit 20`. A PR targets the issue when its body has `Closes #N`, `Fixes #N` or `Resolves #N`.
3. If an **open** PR targets it: print the `⚠ PR already targets issue` block from `references/error-messages.md` (*Guards*), stop, return `status: pr_in_progress` with its `pr_number` and `branch_name`, and **never close the issue** (*Early exit*).

Only a **merged** PR or a closing commit on the default branch is `already_resolved`.

### 0c — Guards

**Interactive:** warn and ask if assigned elsewhere, or on `wontfix`/`blocked`/`do-not-merge` labels. **Auto:** skip the assignment guard, log blocking labels, never stop.

### 0d — Auto-normalize

If `issue.auto_normalize` is true and the body lacks a `<!-- idd:normalized v1 -->` marker (a legacy `gitissue:normalized` one counts):

1. **Security label check (SPEC §1.4)** — before any rewrite scan labels for `security`, `CVE`, `vulnerability` (case-insensitive). On a match:
   - **Auto mode (`--auto` / `IDD_AUTO_MODE=1`):** print the `⚠ … Skipping auto-normalization` warning (`references/error-messages.md` → *Security-labeled issue (skip)*), first matching label as `{label}`, continue **without** rewriting.
   - **Interactive mode:** same warning, then ask for explicit operator confirmation; default **no**, a decline continuing without normalization.

2. **Normalize inline** — otherwise, structure-only as `/issue-creator` Normalize mode (the resolver does **not** invoke `/issue-creator` as a subprocess):
   1. Classify the type and generate the body with the marker.
   2. Back up the original body in a comment.
   3. Run `gh issue edit`, then `python3 shared/scripts/gi-issue.py {N} --invalidate`, then re-fetch.
   4. On any failure, **warn** and continue with the original body (`references/error-messages.md` → *Auto-normalization failed*).

### 0e — Workspace (interactive only)

Derive one `{branch_name}` first: `python3 shared/scripts/gi-branch.py {N} --from-issue --type {type}`, reading `.branch`. **`--from-issue` is mandatory** — never put the issue title or configured prefix on the command line (`references/steps/step-0-preflight.md` → *Step 0e — Workspace*). `{type}` is one of six classified literals. Exit 3 stops; anything else degrades to `docs/naming-conventions.md`.

**Auto mode (`--auto` / `IDD_AUTO_MODE=1`): skip this offer entirely.** A set `IDD_CALLER_WORKTREE=1` uses the validated caller-managed path; otherwise go to *0f*.

**Interactive mode:** offer a git *worktree*, so work never touches the user's tree:

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

Accept replaces *0f — Create branch* and the mandatory Repo Sync; decline runs mandatory Repo Sync then *0f*. Creation, setup, cleanup: *Step 0e — Workspace*.

### 0f — Create branch

The **in-place path**; worktree paths already checked out the branch. Reuse the derived `{branch_name}` (*0e — Workspace*, `docs/naming-conventions.md`). **If it exists:** interactive asks `continue` or `fresh`, auto takes `continue`.

### 0g — Complexity gate (select the pipeline profile)

Decide **before Step 1** how much pipeline this issue earns; the `XS … XL` scale and safety rules: `docs/agent-model-effort.md` (*Complexity → pipeline profile*). `resolve.adaptive_effort: false` pins `full`; else read the **pre-work `Effort` band** in `## Metadata`, never later agent output:

- `XS`/`S` asserted (not `(needs review)`) → `light`; `M`/`L`/`XL` → `full`
- `XS`/`S` low-confidence, **or** absent/unparseable → `full` (ambiguous → fuller)

**What `light` collapses — the single home for this rule.** Mechanics: the *`light` profile* subsection of `references/steps/step-1-research.md` and `references/steps/step-2-plan.md`.

| Step | `light` behavior |
|------|------------------|
| 1 — Research | Lighter pass; the already-resolved check still runs. |
| 2 — Plan | Do **not** spawn the synthesizer; derive a minimal plan inline, no design-confirm checkpoint; the sensitive-change gate **still runs**. **Unless *0h* set `analysis_reuse = fresh`**: *Step 2 — Plan → `reuse`* governs, options are **lifted**, and the design-confirm checkpoint **does** apply. |
| 3 — Propose relevant skills | Skip propose/install; `selected_skills = []`. **Leftover teardown still runs** (*Step 3*), except in a parallel lane (`IDD_CALLER_WORKTREE=1`). |
| 4 — QA | Cap the loop at **1** cycle; one reviewer spawn still runs. |
| 5 — Deliver | **Unchanged**. |

Revise **upward** only. `{workspace_note}` is ` (worktree)` in a worktree, else empty; `effort: full` prints even under `resolve.adaptive_effort: false`:
```
[0/5] Preflight    ✓ issue #N open, branch: {branch_name}{workspace_note}, effort: {profile}
```

### 0h — Analysis reuse gate <!-- a:rs-0h-skill -->

Set `analysis_reuse` to `fresh`, `stale` or `absent` by the five-condition predicate in `references/steps/step-0h-analysis-reuse.md` (*Step 0h — Analysis reuse gate*) — its **single home**. `fresh` seeds Step 1 and skips Step 2's synthesizer; `stale`/`absent` run the full pipeline. Any doubt is `stale` (fail-safe). Skipped when `resolve.adaptive_effort: false`.

---

## Step 1 — Research

Understand the issue, the affected code and candidate solutions; the same pass verifies it is not already fixed (auto then closes it). Spawn the researcher (`shared/agents/codebase-researcher.md`). Payload, phases, early exit, fallback: *Step 1 — Research*.

**Profiles.** `light` — see the profile table in *Step 0g*; a `high`/`complex` signal revises **upward** to `full`. `analysis_reuse = fresh` (*0h*) — pass `prior_analysis` for the seeded **verify-first** pass: confirm or refute, never trust; the already-resolved check still runs. `triage_context` has no commit pin, so it may only **reorder** a scan (*→ `reuse`*, *→ `triage_context`*).

---

## Step 2 — Plan

Generate options and select one. Spawn the synthesizer (`shared/agents/synthesizer.md`); it returns minimal / balanced / comprehensive options and recommends one (*Step 2 — Plan*). **Design sketches:** when the change adds or reshapes a domain type, state or transition and the repo has a static checker, options differ in structure instead, each carrying caller code the repo's checker type-checks, never runs; `shared/scripts/gi-sketch.py` rejects designs that accept an invalid transition and may switch the selection (*Step 2 — Plan → Design sketches*).

**Profiles.** `light` — see the profile table in *Step 0g*. `analysis_reuse = fresh` (*0h*) skips the same spawn but **wins Step 2 when both apply** — a replacement, not an addition: lift `options[]`, `recommended_option`, `overall_complexity`, `overall_risk` from the analysis, each `rejection_reason` from `decision_record.options_rejected[]` (*→ `reuse`*).

### Sensitive-change gate (every profile, every mode)

Size never exempts a change. Once an option is selected, `shared/scripts/gi-sensitive.py --classify` checks the labels and planned paths; when sensitive, run falsifiable load-bearing probes, a **fresh** code-reviewer challenge, and adjudication where one unrebutted blocker at any confidence holds the plan. `--adjudicate` decides; `stop` is a safety stop in auto mode (*Step 2 — Plan → Sensitive-change gate*).

### Design-confirm checkpoint (high-complexity, interactive only)

**Exactly one** extra agreement point before code is written, when **both** hold: `overall_complexity: L`/`XL` or `overall_risk: High`, **and** interactive mode (`--auto`/`IDD_AUTO_MODE=1` never pauses). Accept (default) → Step 3; decline → stop, recorded in the PR Decision Record (*Step 2 — Plan → Design-confirm checkpoint*).

---

## Step 3 — Implement

### Propose relevant skills

Optionally augment the implementer with external skills from `references/skill-index.md`: detect, propose, accept into `selected_skills`; internal agents remain the fallback. Borrow/install, `{name, origin}` records via `shared/scripts/gi-state.py`, teardown of `origin: borrowed` only, auto-mode: `references/steps/step-3-implement.md` (*Step 3 — Propose relevant skills*).

Then spawn the implementer (`shared/agents/implementer.md`) with the plan, branch name, naming conventions and `selected_skills`. **Bug** issues first run the red-capable reproduction checkpoint — reproduce, confirm red, fix, convert to a regression test — surfaced in the Decision Record and acceptance table; others skip it, auto never blocks (`references/bug-verification.md`). Payload, guardrails, fallback: *Step 3*; `light`: profile table in *Step 0g*.

---

## Step 4 — QA

Loop: review → test → fix until clean or the cycle cap — light=1 (profile table in *Step 0g*); full+low/medium=2; full+high=`resolve.qa_max_cycles`. Record `ceiling`/`breach_reason`. **Premise reset:** two failed fixes sharing a premise block the next fix — cap and interactive continue included — until rerunnable diagnostics support a revised premise; `shared/scripts/gi-premise.py` decides (*Step 4 — QA → Premise reset*).

### Spawning the code reviewer

Spawn a **fresh** reviewer (`shared/agents/code-reviewer.md`) each cycle. On blocking issues, spawn or re-message the fixer (`shared/agents/fixer.md`) with issue context, branch/base branch, findings, failing output, the commit message `fix({scope}): address review feedback (#N)`, and the pre-commit security gate it MUST run before committing — `security_convention` (`references/docs/pre-commit-security.md`), `secscan_script` (`references/scripts/gi-secscan.py`), `secscan_policy_ref` (`origin/${base}`) as spawn variables; paths and a ref only. Read the fixer's JSON result and decide on another cycle — never fix inline when the Agent tool exists.

### UI/UX review (auto-detected)

UI review is **auto-detected per issue** (no config flag): scan the issue body and diff for UI work before cycling. The **code UI review** always runs; the **browser UI review** runs only when a running app is reachable *and* opted in, else **skips with a warning**. Detection, the `ui-reviewer` spawn and the `ui_review.browser_review` gate: `docs/ui-review.md`; mechanics: *Step 4 — UI/UX review*.

**Verification recipe:** when the base branch commits `.idd-recipe.json` (or legacy `.gitissue-recipe.json`), each cycle also runs it through `shared/scripts/gi-recipe.py`: launch, drive the capabilities the diff maps, keep evidence, tear down the owned instance. Auto mode runs it only when the recipe opts in `resolve` (*Step 4 — QA → Verification recipe*).

---

## Step 5 — Deliver

### Verify all tests pass

With `resolve.auto_test` true (default), run the full suite once more after QA; false skips. **Under `auto_test`, not over it:** when `tests_state`'s SHA equals `git rev-parse HEAD` **and `git status --porcelain=v1 --untracked-files=all` is empty**, a clean QA cycle already ran this suite on this tree — skip it, print `○ Test suite: skipped (last green {count}@{sha_short} == HEAD)`. Nothing recorded, or any doubt, runs it (*Step 4 — QA → Last-green test state*, the variable's single home). <!-- a:rs-deliver-clean-tree -->

A failure prints `✗ Final test run failed — PR not created` and stops, even in auto.

### Update documentation

1. List the user-visible names the diff changes (commands, flags, config keys, public functions, output strings).
2. Search `README*`, `docs/`, `CHANGELOG*` and the changed files' docstrings for each name.
3. Update each match describing the old behavior; add a `CHANGELOG` entry if that file exists.
4. No match: record `docs: none found` in the Evidence row.

### Push branch and create PR

Run the branch-diff scan first: export `IDD_AUTO_MODE=1` in auto mode, then from the repo root run `python3 shared/scripts/gi-secscan.py --range "origin/${base}" --policy-ref "origin/${base}"`. It reads `security.*` from `.idd.yml` (else legacy `.gitissue.yml`) **at the base ref**: never pass a config *value* on the command line, never let the scanned branch supply its policy (*Pre-push secret scan*).

- **Pass** needs all four: exit 0, `policy_source` equal to the requested `ref:origin/…`, `verdict` not `block`, `scanned` not 0 while `skipped` is above 0.
- **Exit 1 is the block verdict** — stop, do not push, report `blocking[]`. **Exit 3** (uncompilable `security.*`) also stops.
- **No `python3`, exit 2, exit 4** — degrade: print `⚠ gi-secscan unavailable — running the documented scan` and run the **Primary Pattern** in `docs/pre-commit-security.md` over `git diff --name-only "origin/${base}"...HEAD`. Exit 1 without JSON is a crash — treat as exit 2.

Never read a non-zero exit as a pass. Only after it passes:

```bash
# gated by the gi-secscan.py pass above — see docs/pre-commit-security.md
git push -u origin {branch_name}
gh pr create --title "{pr_title}" --body "{pr_body}"
```

**PR title:** `{type}({scope}): {description} (#{issue_number})` (`docs/naming-conventions.md`)

**PR body:** fill *PR Body Template* in `references/report-templates.md`; never omit its **Decision Record**, Test Results or **Acceptance Criteria Verification** (`docs/idd-methodology.md`). Its **last line** is the QA handoff marker: fill it **only when QA exited clean**, else drop it — never append a second copy (*QA handoff marker* owns the per-field omit rules). `head=` is `git rev-parse HEAD` after the last commit.

Copy that line out of the template **character-for-character** and substitute **only** the `{braced}` tokens; never re-word or recall a field name:

```
<!-- idd:qa v1 head={head_sha} profile={profile} cycles={qa_cycles} review=clean tests={test_count}@{tests_sha} ui={ui_legs}:{ui_result}@{ui_sha} -->
```

`review=clean` has **no synonym**: `verdict=`, `status=` or `result=` make the marker `stale` (*QA handoff marker* explains why).

### Revision receipt <!-- a:rs-revision-receipt -->

The marker alone is not evidence, because whoever opened the PR can write it. **Whenever the marker is filled**, record its receipt while `HEAD` is still the marker's `head=` and `git status --porcelain=v1 --untracked-files=all` is empty. Without a receipt, `/issue-pr-review` reads the marker as `stale`. The JSON record carries `profile`, `cycles`, `review: "clean"`, `ui` (the marker's `ui=` value), and `tests`: the `tests=` count and SHA plus the command that ran, or `null` when the marker omits `tests=`, plus `artifacts`: the `recipe_state` evidence paths when a recipe ran (*Revision receipt* in `references/report-templates.md`). The script prints the `sha` it recorded, which must equal the marker's `head=`.

```bash
printf '%s' "$receipt_json" | python3 shared/scripts/gi-receipt.py --write
```

- **Exit 0**: written.
- **Exit 3**: invalid record, nothing written. Fix it and retry once, or ship without a receipt.
- **Exit 4, or no `python3`**: print `⚠ No revision receipt — the reviewer will run its full pipeline`. Ship without a receipt and **never hand-write one**, because the script's clean-tree and `HEAD` checks are what a receipt attests.

### Project board sync

With `projects.sync_enabled` true, set `status_map.done` (`docs/github-projects-sync.md`), then print `[5/5] Deliver`.

### Run-log entry (monitoring)

At **every terminal outcome** — `success`, `already_resolved`, `failed` — append exactly **one JSON line** to `.idd/runs.jsonl`, **unless invoked with `--no-run-log`**, which appends **nothing** and returns telemetry. That is the **single writer** rule under `/auto-pilot`, independent of `--auto`: a standalone `/issue-resolver <N> --auto` still writes. Derivation: `references/report-templates.md` (*Run-log entry — field derivation and suppression*), per `docs/run-log-schema.md`.

```bash
# Exactly one runs. --echo validates the telemetry you return and writes nothing.
if [ -n "$no_run_log" ]; then printf '%s' "$run_json" | python3 shared/scripts/gi-runlog.py --echo; else printf '%s' "$run_json" | python3 shared/scripts/gi-runlog.py --append; fi
# Fallback when `python3` is unavailable or the script exits 4: mkdir -p .idd && printf '%s\n' "$run_json" >> .idd/runs.jsonl
```

**Exit 3:** the record is invalid and nothing was written — a stop, not a degrade: never append `$run_json` raw. Correct the record and re-run, or drop the line. Every other write failure is **non-fatal** — use the fallback append, never block the result. Only append; never rewrite or reorder lines.

---

## Closing Summary

Emit **one** closing block at **every** terminal outcome, stops included. Read the *Review contract* in `references/report-templates.md` (*Closing Summary*), then print its matching variant: `Result:` first (`DONE`, `PARTIAL` or `BLOCKED`), then `Evidence:`, `Uncertainty:`, `Decision:` and `Next action:`. **Then the run-stats footer** (`references/run-stats.md`) prints last, with tokens only where the host reported a count.

---

## Auto-Pilot Mode

With `--auto` (or under `/auto-pilot`) no step prompts. Invariants:

- **Environment:** export `IDD_AUTO_MODE=1` before any shell snippet consulting it (`docs/pre-commit-security.md`).
- **Workspace:** in-place is the default resolution path. Skip Step 0e and allow no `git worktree add` on the default resolution path; run mandatory Repo Sync, then *0f*. With `max_parallel > 1` a resolver may receive `IDD_CALLER_WORKTREE=1` and use that workspace, never creating or cleaning it up.
- **Never blocks:** every decision point has an auto behavior (*Auto-mode behavior by step*); every terminal outcome runs borrow teardown. No `[y/N]`, `Choose:` or `Continue?` prompts.
- **Deliver:** create the PR; never merge (`/auto-pilot`'s or `/issue-pr-review`'s job). Under `/auto-pilot` the `profile` is **returned** in telemetry; a standalone `--auto` run writes it.

## Edge Cases

No ACs, empty body, 20+ files, test failure or timeout, existing branch: *Edge Cases*.

## Platform Driver and Output Conventions

Tracker access uses the GitHub driver: `--json` with explicit fields, never parsed text (docs/platform-github.md). Output follows `docs/terminal-style.md` (symbols, indent, URLs on their own line, ≤80 chars, no animation). Errors use `references/error-messages.md`'s format.
