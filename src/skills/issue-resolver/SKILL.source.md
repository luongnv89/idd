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
| `/issue-resolver <N>` | interactive | Resolve issue #N; the user picks the plan |
| `/issue-resolver <N> --auto` | auto-pilot | Resolve autonomously, no prompts |
| `/issue-resolver <N> --no-run-log` | (modifier) | Append nothing to `.gitissue/runs.jsonl`; return telemetry to the caller |

`N` must be a GitHub issue number. `--auto` is set by `/auto-pilot`. `--no-run-log` is **orthogonal to `--auto`** and passed **only by `/auto-pilot`** — see *Step 5 — Deliver* → *Run-log entry*.

## Prerequisites

Verify before any operation — git repository (`git rev-parse --git-dir`), `gh` installed (`which gh`) and authenticated (`gh auth status`), remote present (`git remote -v`). On failure print the exact error from `references/error-messages.md` and stop.

## Repo Sync Before Edits (mandatory)

In-place path only (ordinary auto mode, or interactive after declining Step 0e); accepted and validated caller-managed worktrees already start from the fetched base, and an invalid `IDD_CALLER_WORKTREE=1` is a stop, never a sync bypass. Sync with the **stash-first pattern** — stash (including untracked) → fetch → rebase-pull → pop, aborting with the recovery hint if the pop conflicts. Copy the snippet and recovery procedure from `docs/sync-conventions.md` (*Quick Reference (Copy-Paste Snippet)*); never improvise a bare rebase on a dirty tree. A missing `origin` or a rebase conflict stops and asks (interactive), or aborts (auto).

## Configuration

Load config once at skill start; never re-read it. Run `python3 shared/scripts/gi-config.py` — two mandatory requirements. **Working directory:** the repo root. **Script path:** absolute, resolved as the *Bundled dependency precheck* resolves its list. It prints `{"config": {…dotted keys…}, "config_file": …, "first_run": …}`, merging the defaults below with `.gitissue.yml`. Why both requirements and the clock matter: `references/pipeline-steps.md` (*Configuration load*).

- **Exit 0** — use `config`; when `first_run` is `true` print `○ First run — using default config. Run /init-gitissue to customize.`
- **Exit 3** — invalid `.gitissue.yml`: print the error from `references/error-messages.md` (*Invalid config*) and stop.
- **Script file absent** — a missing bundled dependency is a broken install and not a degrade: stop, print `✗ Missing bundled dependency`.
- **Anything else** (no `python3`, another non-zero exit, unparsable stdout) — print `⚠ gi-config unavailable — using the inline defaults below`, then read `.gitissue.yml` by hand *instead of* the script.

**Capture the run clock here:** chain that same `python3` invocation as `python3 …; ec=$?; date +%s >&2; exit "$ec"` and keep the stderr epoch as `run_started_epoch` — what the *Run Stats Footer* (`references/run-stats.md`) measures `elapsed` from.

Defaults and per-key behavior in `docs/config-schema.md`: `issue.auto_normalize: true` · `resolve.approval_gate: auto` · `resolve.branch_prefix: "auto"` · `resolve.auto_test: true` · `resolve.test_timeout: 300` · `resolve.max_commits: 10` · `resolve.qa_max_cycles: 5` · `resolve.adaptive_effort: true` (*0g*) · `resolve.ui_review.browser_review: "ask"` · `resolve.borrow_skills: false`.

---

## Subagent Architecture

Heavy work goes to subagents (`shared/agents/`), keeping the main agent's **context window** clean and its **token budget** predictable: the main agent owns Step 0, Step 4's loop and Step 5; Steps 1-3 each spawn one. Diagram: `references/pipeline-steps.md` (*Subagent Architecture Diagram*). Prompts are bundled at `references/agents/<name>.md`; shared conventions live in `docs/shared-agent-conventions.md`.

### Spawning a subagent (canonical pattern)

Only role, description and prompt file change per step. **Do NOT set `subagent_type`**; use the default general-purpose agent:

```python
Agent(
  description="{role} — {action} issue #N",
  prompt=<{agent-file}.md prompt with {variables} replaced>,
  # do NOT set subagent_type — default general-purpose agent, never a custom type (e.g. NOT "code-reviewer")
)
```

### Orchestrating the agents (model/effort, monitoring, audit)

Per spawned step: **name the role** in the spawn `description`; **size the model/effort** per `docs/agent-model-effort.md`; **monitor before advancing** — a missing or blocking return stops the run (interactive) or follows the auto behavior; **audit** the per-step signal. Required return shapes and audited fields: `references/pipeline-steps.md` (*Orchestrating the agents*).

### Environment check

With the Agent tool available, use subagents as above; without it (e.g. Claude.ai), run each step inline via the fallback instructions.

### Bundled dependency precheck

Verify **every** path below exists relative to this SKILL.md's own directory — the authoritative guard. Any missing path stops the run: print the `✗ Missing bundled dependency` block from `references/error-messages.md` (*Bundled dependencies*), never an inline or guessed subagent prompt.

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

6 steps (0-5) — Preflight, Research, Plan, Implement, QA, Deliver. Each prints a new `[N/5]` line on start (`●`), updating to `✓`/`✗`; static sequential output, no animation. Worked example in `references/report-templates.md` (*Expected Inline Pipeline Output*).

---

### Step completion reports

Each step closes with `√`/`×` per check plus a `Result: PASS | PARTIAL | FAIL` line. Check names, semantics and format: `references/report-templates.md` (*Step Completion Reports*) — **read it now**, before Step 0. A step is not complete until its `Result:` line is printed.

---

## Step 0 — Preflight

Decide whether this issue should be worked on. Open with `● Preflight check for issue #N...`.

### 0a — Fetch issue

GitHub reads share the subprocess boundary in `shared/scripts/gi-gh.py`. Classify any framed caller payload first (`/auto-pilot` captured it in mode-neutral *Step 1.2b*) — *Step 0i — Caller payload gate* in `references/pipeline-steps.md` is its single home: the framing, `issue_payload = supplied | partial | absent`, the mandatory live read `gh issue view N --json state,comments,updatedAt` under `supplied`, the exact match between retained and live `updatedAt` required before 0d, the discard-and-refresh fallback on any mismatch (identical for individual, array, and keyed-map payloads), and the rule that no safety check — 0a's two stops included — is ever decided from a payload. Then run `python3 shared/scripts/gi-issue.py {N} --fields number,title,body,labels,assignees,state,comments,updatedAt` and read `.issue`, except where that gate lets the payload stand in. **Capture `updatedAt` here** — 0d's `gh issue edit` bumps it, so *0h* must compare against this pre-normalization value. Resolve the script path as the *Bundled dependency precheck* does. Exit 3 stops; no `python3`, exit 2 or exit 4 degrades to `gh issue view {N} --json number,title,body,labels,assignees,state,comments,updatedAt`. **0d rewrites the body, so it MUST end with `python3 shared/scripts/gi-issue.py {N} --invalidate`.** <!-- a:rs-0a-payload-concurrency -->

**If not found:** output error and stop. **If closed:** output warning and stop.

### 0b — Check for existing work

```bash
git branch -a | grep -i "{N}"                                # existing branches
gh pr list --state open --json number,title,body,headRefName --limit 20
```

Scan PR bodies for `Closes #N`, `Fixes #N`, `Resolves #N`. An **open** PR already targeting the issue prints the `⚠ PR already targets issue` block from `references/error-messages.md` (*Guards*) and stops — return `status: pr_in_progress` with its `pr_number` and `branch_name`, and **never close the issue** (`references/pipeline-steps.md` → *Early exit*). Only a **merged** PR or a closing commit on the default branch is `already_resolved`.

### 0c — Guards

**Interactive:** warn and ask if assigned to someone else, or if `wontfix`/`blocked`/`do-not-merge` labels exist. **Auto:** skip the assignment guard; log blocking labels, do not stop.

### 0d — Auto-normalize

If `issue.auto_normalize` is true and the body carries no `<!-- gitissue:normalized v1 -->` marker:

1. **Security label check (SPEC §1.4)** — before any rewrite, scan labels for `security`, `CVE`, or `vulnerability` (case-insensitive). On a match:
   - **Auto mode (`--auto` / `IDD_AUTO_MODE=1`):** print the `⚠ … Skipping auto-normalization` warning from `references/error-messages.md` (*Security-labeled issue (skip)*), using the first matching label for `{label}`, and continue **without** rewriting.
   - **Interactive mode:** print the same warning and ask for explicit operator confirmation. Default **no**; if declined, continue without normalization.

2. **Normalize inline** — when nothing blocks: classify the type, generate the normalized body, add the marker, post a backup comment carrying the original, `gh issue edit` the issue, invalidate the cache (`python3 shared/scripts/gi-issue.py {N} --invalidate`), re-fetch. Same structure-only flow as `/issue-creator` Normalize mode, but the resolver does **not** invoke `/issue-creator` as a subprocess — Step 0d runs inline. On failure, warn and continue with the original body (`references/error-messages.md`).

### 0e — Workspace (interactive only)

Derive one `{branch_name}` before 0e or 0f picks a workspace: `python3 shared/scripts/gi-branch.py {N} --from-issue --type {type}`, reading `.branch`. **`--from-issue` is mandatory** — never put the issue title or the configured prefix on the command line (`references/pipeline-steps.md` → *Step 0e — Workspace*). `{type}` is one of the six literals this skill classified, never free text. Exit 3 stops; no `python3`, exit 2 or exit 4 degrades to deriving the name by hand per `docs/naming-conventions.md`. Both workspace paths use this one name.

**Auto mode (`--auto` / `IDD_AUTO_MODE=1`): skip this offer entirely.** A set `IDD_CALLER_WORKTREE=1` uses the validated caller-managed path in `references/pipeline-steps.md`; otherwise go to *0f*.

**Interactive mode:** offer a dedicated git *worktree* so branch creation, implementation and testing never touch the user's current working tree:

```
◆ Workspace for issue #N
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

    Branch:    {branch_name}
    Worktree:  ../{repo}-worktrees/{branch_name with / → -}
    Setup:     copies your gitignored local config (.env*, and similar),
               then runs this project's detected install/bootstrap so the
               workspace is ready to run without manual reconfiguration.

  Accepting keeps your current working tree untouched. Declining uses the current working tree with the existing sync and branch behavior.

  Resolve in a new worktree? [Y/n]
```

Accept replaces *0f — Create branch* and the mandatory Repo Sync; decline runs the mandatory Repo Sync then *0f — Create branch*. Creation, setup-artifact propagation, cleanup and fallback-on-failure: `references/pipeline-steps.md` (*Step 0e — Workspace*).

### 0f — Create branch

The **in-place path** — ordinary auto mode, or interactive after declining. Accepted and validated caller-managed paths already checked out the branch and skip this sub-step. Use the `{branch_name}` already derived (*0e — Workspace*, `docs/naming-conventions.md`); never re-derive it. **If the branch exists:** interactive asks `continue` or `fresh`; auto takes `continue`.

### 0g — Complexity gate (select the pipeline profile)

Decide **before Step 1** how much pipeline this issue earns. Mechanism, the `XS … XL` scale and the safety rules live in `docs/agent-model-effort.md` (*Complexity → pipeline profile*).

`resolve.adaptive_effort: false` skips the gate (`profile = full`). Otherwise read the issue's **pre-work `Effort` band** in `## Metadata`, never a later agent output:

- `XS`/`S`, asserted (not `(needs review)`/low-confidence) → `profile = light`
- `M`/`L`/`XL` → `profile = full`
- `XS`/`S` but low-confidence, **or** absent/unparseable → `profile = full` (ambiguous → fuller)

**What `light` collapses — the single home for this rule.** `full` changes nothing. Per-step mechanics: `references/pipeline-steps.md` (*Step N → `light` profile*).

| Step | `light` behavior |
|------|------------------|
| 1 — Research | Lighter pass; the already-resolved check still runs. Skip the broad dependency trace and external solution research. |
| 2 — Plan | Skip the synthesis — do **not** spawn the synthesizer; derive a minimal plan inline, and the design-confirm checkpoint does not apply. **Unless *0h* set `analysis_reuse = fresh`**: then *Step 2 — Plan → `reuse`* governs, options are **lifted** from the analysis, and the design-confirm checkpoint **does** apply. |
| 3 — Propose relevant skills | Skip propose/install; `selected_skills = []`. **Leftover teardown still runs** (*Step 3 — Propose relevant skills*), except in a parallel lane (`IDD_CALLER_WORKTREE=1`), which disables borrowing outright. |
| 4 — QA | Cap the loop at **1** cycle instead of `resolve.qa_max_cycles`; one reviewer spawn still runs. |
| 5 — Deliver | **Unchanged** — the Decision Record and Acceptance Criteria Verification table always ship. |

Revise **upward** only (Step 1 reports `high`/`complex` on an `S` band → `full`); never downgrade. Then print — `{workspace_note}` is ` (worktree)` in a worktree, empty otherwise, and `effort: full` prints even when `resolve.adaptive_effort` is `false`:
```
[0/5] Preflight    ✓ issue #N open, branch: {branch_name}{workspace_note}, effort: {profile}
```

### 0h — Analysis reuse gate <!-- a:rs-0h-skill -->

Set `analysis_reuse` to `fresh`, `stale` or `absent` by the five-condition predicate in `references/pipeline-steps.md` (*Step 0h — Analysis reuse gate*) — its **single home**. `fresh` seeds Step 1 and skips Step 2's synthesizer; `stale`/`absent` run the full pipeline. Any doubt — missing key, short SHA, unparsable timestamp, failed `git` call — is `stale` (fail-safe). Skipped, like *0g*, when `resolve.adaptive_effort` is `false`.

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

Optionally augment the implementer with external skills from `references/skill-index.md`: detect, propose, accept into `selected_skills`; internal agents stay the fallback. Borrow/install, `{name, origin}` records via `shared/scripts/gi-state.py`, teardown of `origin: borrowed` only, the `◆`/`○` block, leftover cleanup and auto-mode: `references/pipeline-steps.md` (*Step 3 — Propose relevant skills*).

**`light` profile:** skip the propose/install — see the profile table in *Step 0g* — but **still run the leftover teardown** there.

Then spawn the implementer (`shared/agents/implementer.md`) with the canonical pattern, passing the plan, branch name, naming conventions and `selected_skills`. **Bug** issues first run the red-capable reproduction checkpoint — reproduce, confirm red, fix, convert to a regression test — surfaced in the PR Decision Record and acceptance table; non-bug issues skip it and auto mode never blocks (`references/bug-verification.md`). Payload, commit guardrails and inline fallback: *Step 3 — Implement* in the same file.

After implementation:
```
[3/5] Implement    ✓ {N} files changed, {U} unit tests, {E} e2e tests
```

---

## Step 4 — QA

Automated review-fix loop: review → test → fix → repeat until clean or the cap is hit.

### Spawning the code reviewer

Spawn a **fresh** reviewer (`shared/agents/code-reviewer.md`) each cycle, canonical pattern, for unbiased review. On blocking issues from the reviewer or a test/build run, spawn or re-message the fixer (`shared/agents/fixer.md`) the same way with issue context, branch/base branch, findings, failing output, the commit message `fix({scope}): address review feedback (#N)`, and the pre-commit security gate it MUST run before committing — `security_convention` (`references/docs/pre-commit-security.md`), `secscan_script` (`references/scripts/gi-secscan.py`) and `secscan_policy_ref` (`origin/${base}`) as spawn variables. Paths and a ref name only. Collect the fixer's JSON result and decide whether to run another cycle — never fix inline when the Agent tool is available.

### UI/UX review (auto-detected)

UI review is **auto-detected per issue** — no config flag enables it. Scan the issue body and diff for UI work before the QA cycles. The **code UI review** is environment-independent and always runs; the **browser UI review** runs only when a running app is reachable *and* opted in, else **skips with a warning while the code UI review still runs** — fail-soft. Detection rules, the `ui-reviewer` spawn, the `ui_review.browser_review` gate and its messages: `docs/ui-review.md`. Resolver deltas and cycle mechanics (`resolve.qa_max_cycles`, exit-on-clean, exit-on-stagnation): `references/pipeline-steps.md` (*Step 4 — UI/UX review*, *Step 4 — QA*).

**`light` profile:** cap the loop at **1** cycle instead of `resolve.qa_max_cycles` — see the profile table in *Step 0g*. Class policy: light=1; full+low/medium=2; full+high=`qa_max_cycles`. Record `ceiling`/`breach_reason`.

---

## Step 5 — Deliver

Push, create the PR, report.

### Verify all tests pass

When `resolve.auto_test` is true (default), run the full suite one final time after the QA fixes; when false, skip it. **Under `auto_test`, not over it:** when `tests_state`'s SHA equals `git rev-parse HEAD` **and `git status --porcelain=v1 --untracked-files=all` is empty**, a clean QA cycle already ran this suite on this tree — skip it and print `○ Test suite: skipped (last green {count}@{sha_short} == HEAD)`. Nothing recorded, or any doubt, runs it (`references/pipeline-steps.md`, *Step 4 — QA → Last-green test state*, the single home of the variable and both consumers). <!-- a:rs-deliver-clean-tree -->

A failure here prints `✗ Final test run failed — PR not created` with the details and stops, even in auto mode.

### Update documentation

If the change affects documented behavior, update README, inline docs and CHANGELOG.

### Push branch and create PR

Scan the whole branch diff first — it catches secrets that slipped in during QA fixes. Export `IDD_AUTO_MODE=1` in auto mode, then from the repo root run `python3 shared/scripts/gi-secscan.py --range "origin/${base}" --policy-ref "origin/${base}"`. It reads `security.*` from `.gitissue.yml` **at the base ref**: never pass a config *value* on the command line, and never let the branch under scan supply the policy that scans it. Why each rule below holds: `references/pipeline-steps.md` (*Step 5 — Deliver → Pre-push secret scan*).

- **Pass** needs all four: exit 0, `policy_source` equal to the `ref:origin/…` requested, `verdict` not `block`, and `scanned` not 0 while `skipped` is above 0.
- **Exit 1 is the block verdict** — stop, do not push, report the path from `blocking[]`. Never fall through to the prose scan.
- **Exit 3** (uncompilable `security.*` regex) — also a stop.
- **No `python3`, exit 2, or exit 4** — degrade: print `⚠ gi-secscan unavailable — running the documented scan`, then run the **Primary Pattern** in `docs/pre-commit-security.md` over `git diff --name-only "origin/${base}"...HEAD`. Exit 1 with no parsable JSON on stdout is a crash, not a verdict — treat it as exit 2.

Never improvise a weaker check; never read a non-zero exit as a pass. Only after the scan passes (or warnings are accepted):

```bash
# gated by the gi-secscan.py pass above — see docs/pre-commit-security.md
git push -u origin {branch_name}
gh pr create --title "{pr_title}" --body "{pr_body}"
```

**PR title:** `{type}({scope}): {description} (#{issue_number})` (`docs/naming-conventions.md`)

**PR body:** fill *PR Body Template* in `references/report-templates.md` — Summary, Approach, **Decision Record** (from `.gitissue/analysis-<N>.json` if present, else synthesized), Changes, Test Results, **Acceptance Criteria Verification**. Never omit the last two (`docs/idd-methodology.md`). The template's **last line** is the `<!-- gitissue:qa v1 … -->` handoff marker: fill it in **only when QA exited clean**, otherwise drop the line — never append a second copy. Field derivation and the omit rules: same file, *QA handoff marker*. `head=` is `git rev-parse HEAD` taken after the last commit and immediately before `git push`.

### Project board sync

If `projects.sync_enabled` is true, set status to `status_map.done` (`docs/github-projects-sync.md`). After delivery:
```
[5/5] Deliver      ✓ PR #{pr_number} created
```

### Run-log entry (monitoring)

At **every terminal outcome** — delivered PR (`success`), early exit because already fixed (`already_resolved`), or a failed step (`failed`) — append exactly **one JSON line** to `.gitissue/runs.jsonl`, **unless invoked with `--no-run-log`**, in which case append **nothing** and return the telemetry to the caller. `--no-run-log` enforces the **single writer** rule under `/auto-pilot` and is independent of `--auto`: a standalone `/issue-resolver <N> --auto` still writes. Field derivation and the suppression rationale: `references/report-templates.md` (*Run-log entry — field derivation and suppression*), following `docs/run-log-schema.md`.

```bash
# Exactly one of these runs. --echo validates the telemetry you return and writes nothing.
if [ -n "$no_run_log" ]; then printf '%s' "$run_json" | python3 shared/scripts/gi-runlog.py --echo; else printf '%s' "$run_json" | python3 shared/scripts/gi-runlog.py --append; fi
# Fallback when `python3` is unavailable or the script exits 4: mkdir -p .gitissue && printf '%s\n' "$run_json" >> .gitissue/runs.jsonl
```

**Exit 3:** the record is invalid — the script printed the reason on stderr and wrote nothing. A stop, not a degrade: never append `$run_json` raw. Correct the record and re-run, or drop the line.

Every other write failure (no `python3`, exit 2, exit 4) is **non-fatal** — use the fallback append above and never block the reported run result. Only append; never rewrite or reorder existing lines.

---

## Closing Summary

Print **one** closing block carrying only what the live `[N/5]` tracker never printed: the outcome line, the `risk_rating`, and the single PR reference (number, title, URL, `Closes #N`). Never repeat a tracker metric. Use the matching variant in `references/report-templates.md` (*Closing Summary*): *Successful Resolution*, *Resolution With Warnings*, or *Already Resolved* (no PR reference). **Then the run-stats footer.** Close with the *Run Stats Footer* — `references/run-stats.md` — elapsed, tokens only where the host reported a count (otherwise left out), agents, run cost only, `n/a` for anything else undetermined. It is the last thing printed at **every** terminal outcome, including those that never reach this block: a preflight stop (`not found`, `closed`, `pr_in_progress`), an invalid-config stop, `already_resolved`, a blocked secret scan, a failed final test run, or any failed step.

---

## Auto-Pilot Mode

With `--auto` (or under `/auto-pilot`) the pipeline runs without user interaction. Each step states its own auto behavior; these are the cross-cutting invariants:

- **Environment:** Export `IDD_AUTO_MODE=1` before any shell snippet that consults it (`docs/pre-commit-security.md`).
- **Workspace:** in-place is the default resolution path. Skip Step 0e and allow no `git worktree add` on the default resolution path; standalone auto mode and auto-pilot's single-lane path run mandatory Repo Sync, then *0f*. With `max_parallel > 1` a resolver may receive `IDD_CALLER_WORKTREE=1` and, after the validation in `references/pipeline-steps.md`, use that already-current workspace without creating, falling back from, or cleaning it up. The prompt never appears.
- **Never blocks:** every decision point has a defined auto behavior — per-step list in `references/pipeline-steps.md` (*Auto-mode behavior by step*). Every terminal outcome still runs borrow teardown.
- **Deliver:** create the PR; never merge — that is `/auto-pilot`'s or `/issue-pr-review`'s job. Under `/auto-pilot` the selected `profile` is **returned** in the telemetry (with `--no-run-log`); a standalone `--auto` run writes `profile` itself.

No `[y/N]`, `Choose:` or `Continue?` prompts.

## Edge Cases

Missing acceptance criteria, an empty issue body, large issues (20+ files), test failure or timeout, and branch-already-exists are all handled — behavior for each edge case is in `references/pipeline-steps.md` (*Edge Cases*).

## Platform Driver and Output Conventions

Tracker access follows the GitHub driver — `--json` with explicit field selection, never parsed text; catalog in docs/platform-github.md. Terminal output follows `docs/terminal-style.md` — symbols `● ✓ ✗ ◆ ⚡ ⚠ ○`, two-space indent, `┄` separators, URLs on their own line, ≤80 chars, static sequential output, plus the `[N/5]` counter. Errors use the rich format from `references/error-messages.md`: `✗ what failed`, then `To fix:  <command>`, then a docs link when applicable.
