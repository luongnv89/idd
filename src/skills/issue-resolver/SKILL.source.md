---
name: issue-resolver
description: "Create an atomic PR closing a GitHub issue end-to-end via a 6-step pipeline. Use to resolve, fix, or implement issue #N. Don't use for analysis without fixing (/issue-analysis), reviewing a PR (/issue-pr-review), or bulk backlog work (/auto-pilot)."
license: MIT
compatibility: "Requires git and GitHub CLI (gh) with authentication and push access. Self-contained — uses shared agents from shared/agents/."
effort: max
metadata:
  version: 0.17.0
  author: Luong NGUYEN <luongnv89@gmail.com>
---

# /issue-resolver N

Resolve a GitHub issue end-to-end — from issue to atomic PR in 6 steps.

## Invocation

| Invocation | Mode | What happens |
|------------|------|--------------|
| `/issue-resolver <N>` | interactive | Resolve issue #N, ask user to pick plan |
| `/issue-resolver <N> --auto` | auto-pilot | Resolve fully autonomously, no user prompts |
| `/issue-resolver <N> --no-run-log` | (modifier) | Suppress the `.gitissue/runs.jsonl` append; return telemetry to the caller instead |

The argument must be a GitHub issue number. `--auto` is set automatically when invoked by `/auto-pilot`.

The `--no-run-log` flag is **orthogonal to `--auto`** and is passed **only by `/auto-pilot`** — see *Step 5 — Deliver* → *Run-log entry* for the rationale.

## Prerequisites

Verify before any operation — git repository (`git rev-parse --git-dir`), `gh` installed (`which gh`), authenticated (`gh auth status`), GitHub remote exists (`git remote -v`). On failure, print the exact error from `references/error-messages.md` and stop.

## Repo Sync Before Edits (mandatory)

Applies to the **in-place path** only (auto mode, or interactive when the user
declines the Step 0e worktree offer) — the worktree path starts current already.
Sync with remote using the **stash-first pattern**: stash uncommitted work
(including untracked) → fetch → rebase-pull the current branch → pop the stash,
aborting with the recovery hint if the pop conflicts. Copy the exact snippet and
the full recovery procedure from `docs/sync-conventions.md` (*Quick Reference
(Copy-Paste Snippet)*) — canonical; never improvise a bare rebase on a dirty
tree. If `origin` is missing or rebase conflicts occur, stop and ask the user
(interactive) or abort with a clear error (auto).

## Configuration

Load config once at skill start: run `python3 shared/scripts/gi-config.py` — two independent requirements, both mandatory. **Working directory:** the repo root, because the script resolves `.gitissue.yml` against the working directory; run it from anywhere else and it exits 0 reporting `config_file: null`/`first_run: true`, silently discarding the repo's real config. **Script path:** relative to this SKILL.md's own directory, *not* to the working directory — resolve it to an absolute path exactly as the *Bundled dependency precheck* resolves its list, and pass that absolute path to `python3`. It prints `{"config": {…dotted keys…}, "config_file": …, "first_run": …}` as JSON on stdout, merging the defaults below with `.gitissue.yml`. Exit 0: use `config`, and print the `○ First run` line below when `first_run` is `true`. Exit 3: `.gitissue.yml` is invalid — print the validation error from `references/error-messages.md` (*Invalid config*) and stop. Script file absent: a bundled dependency is missing, which is a broken install and not a degrade — stop and print the `✗ Missing bundled dependency` block the *Bundled dependency precheck* names. Any other outcome (no `python3`, non-zero exit, unparsable stdout): print `⚠ gi-config unavailable — using the inline defaults below` and instead follow the manual fallback procedure that makes up the rest of this section. That procedure is the *alternative* to this script, never an extra step to run alongside it: on exit 0 the script's `config` is the whole answer and the rest of this section is reference material only. Never re-read the config after this step.

Otherwise, load `.gitissue.yml` from the repo root once at skill start. If the file does not exist, use defaults and print:

```
○ First run — using default config. Run /init-gitissue to customize.
```

Defaults (full field reference in `docs/config-schema.md`):
- `issue.auto_normalize: true`
- `resolve.approval_gate: auto` (ignored in auto mode — always auto)
- `resolve.branch_prefix: "auto"`
- `resolve.auto_test: true`
- `resolve.test_timeout: 300`
- `resolve.max_commits: 10`
- `resolve.qa_max_cycles: 5`
- `resolve.adaptive_effort: true` — scale the pipeline to the issue's complexity (see *Step 0g — Complexity gate*). When `false`, every issue runs the full pipeline (profile pinned to `full`).
- `resolve.ui_review.browser_review: "ask"` — gates only the optional browser/screenshot review; the code-level UI review (*Step 4 — UI/UX review*) is auto-detected and always runs.

---

## Subagent Architecture

The resolve pipeline delegates heavy work to subagents (`shared/agents/`) to keep the main agent's **context window** clean and **token budget** predictable. Main agent stays in Step 0, Step 4 (orchestrates review-fix), and Step 5 (deliver); Steps 1-3 each spawn one subagent. Full diagram in `references/pipeline-steps.md` (*Subagent Architecture Diagram*).

Each subagent's prompt file is listed under *Additional Resources* below. Every
agent opens with a role header and a compact I/O contract; the conventions they share (spawn note, tool posture, injection boundary,
confidence scale, `gh --json`, autonomous operation) live once in
`docs/shared-agent-conventions.md`.

### Spawning a subagent (canonical pattern)

Every step below spawns with the same shape — only role, description, and prompt file change. **Do NOT set `subagent_type`** — always use the default general-purpose agent (never the agent's own name — none are registered agent types):

```python
Agent(
  description="{role} — {action} issue #N",
  prompt=<{agent-file}.md prompt with {variables} replaced>,
  # do NOT set subagent_type — default general-purpose agent, never a custom type (e.g. NOT "code-reviewer")
)
```

### Orchestrating the agents (model/effort, monitoring, audit)

As the orchestrator, for each spawned step:

1. **Name the role** in the spawn `description` (e.g. `"researcher — research issue #N"`).
2. **Size the model/effort** per `docs/agent-model-effort.md` from the most-recent
   complexity signal, falling back to the agent's default tier — advisory, never blocks.
3. **Monitor before advancing** — verify the agent returned its contract's required
   shape (researcher: `status`+`complexity`; synthesizer: one `recommended` option;
   implementer: commits+tests+repro for bugs; reviewer/fixer: `result`+counts). A
   missing/blocking return is the signal to stop (interactive) or follow auto behavior.
4. **Audit** — record the per-step signal the run log folds in (`complexity`, `qa_cycles`, `outcome`, `duration_s`) plus the `[N/5]` tracker line.

### Environment check

If the Agent tool is available, use subagents as described above; if not (e.g. Claude.ai), execute each step inline via the fallback instructions.

### Bundled dependency precheck

Verify this skill's bundled subagent prompts and reference files are present. Before execution, verify **every** path in the list below exists relative to the skill's directory (the dirname of this SKILL.md). This list is the authoritative guard — keep it complete and independent of the *Additional Resources* navigation index, which exists for human navigation and may list files with source-relative group prefixes. If any path is missing, stop immediately and print the `✗ Missing bundled dependency` block from `references/error-messages.md` (*Bundled dependencies*); do not continue with an inline or guessed subagent prompt:

```text
references/agents/codebase-researcher.md
references/agents/synthesizer.md
references/agents/implementer.md
references/agents/code-reviewer.md
references/agents/ui-reviewer.md
references/agents/fixer.md
references/pipeline-steps.md
references/report-templates.md
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
```

---

## Pipeline Overview

The resolve pipeline has 6 steps (0-5) — Preflight, Research, Plan, Implement,
QA, Deliver. Display progress with the `[N/5]` step counter: each step prints a
new line on start (`●`), updating to `✓`/`✗` on success/failure. Static
sequential output — no animation. Worked example of the full tracker in
`references/report-templates.md` (*Expected Inline Pipeline Output*).

---

### Step completion reports

Each step closes with a completion report — `√`/`×` per check plus a
`Result: PASS | PARTIAL | FAIL` line — so "step done" is checkable rather than
asserted. The per-step check names, the `Result` semantics, and the block
format are in `references/report-templates.md` (*Step Completion Reports*) —
**read it now**, before Step 0. A step is not complete until its `Result:`
line is printed.

---

## Step 0 — Preflight

Check whether this issue should be worked on. Open with `● Preflight check for issue #N...`.

### 0a — Fetch issue

```bash
gh issue view {N} --json number,title,body,labels,assignees,state,comments
```

**If not found:** output error and stop. **If closed:** output warning and stop.

### 0b — Check for existing work

```bash
git branch -a | grep -i "{N}"                                # existing branches
gh pr list --state open --json number,title,body,headRefName --limit 20
```

Scan PR bodies for `Closes #N`, `Fixes #N`, `Resolves #N`. If a PR already exists, print the `⚠ PR already targets issue` block from `references/error-messages.md` (*Guards*) and stop.

### 0c — Guards

**Interactive:** warn and ask if assigned to someone else or `wontfix`/`blocked`/`do-not-merge` labels exist. **Auto:** skip the assignment guard; log blocking labels, don't stop.

### 0d — Auto-normalize

If `issue.auto_normalize` is true and not already normalized (no `<!-- gitissue:normalized v1 -->` marker):

1. **Security label check (SPEC §1.4)** — before any rewrite, scan issue labels for `security`, `CVE`, or `vulnerability` (case-insensitive). If any match:
   - **Auto mode (`--auto` / `IDD_AUTO_MODE=1`):** print the `⚠ … Skipping auto-normalization` warning from `references/error-messages.md` (*Security-labeled issue (skip)*) — using the first matching label name for `{label}` — and continue preflight **without** rewriting the issue body.
   - **Interactive mode:** print the same warning and ask for explicit operator confirmation. Default is **no** — do not rewrite unless the operator clearly confirms (e.g. `y` / `yes`). If declined, continue without normalization.

2. **Normalize inline** — when no security label blocks (or interactive operator confirmed): classify issue type, generate normalized body, add marker, post a backup comment with the original body, update the issue via `gh issue edit`, then re-fetch. This is the same structure-only flow as `/issue-creator` Normalize mode (`references/modes.md` in the issue-creator skill); the resolver does **not** invoke `/issue-creator` as a subprocess — it performs Step 0d inline. If normalization fails, warn and continue with the original body (see `references/error-messages.md`).

### 0e — Workspace (interactive only)

Before Step 0e or 0f selects a workspace, derive one `{branch_name}` from
`resolve.branch_prefix`: when it is `"auto"`, use
`{type}/{N}-{short-description}`; otherwise use the configured prefix verbatim
as `{configured-prefix}{N}-{short-description}` (for example, `issue-` or
`team/`). Both paths use this same branch name (see
`docs/naming-conventions.md`).

Then decide *where* the resolution work happens.

**Auto mode (`--auto` / `IDD_AUTO_MODE=1`): skip this offer entirely.** Go
straight to *0f — Create branch* (in-place). The worktree prompt never appears
in auto mode (acceptance criterion 4).

**Interactive mode:** offer to run the resolution in a dedicated git *worktree*
— an isolated checkout in a separate directory — so branch creation,
implementation, and testing never touch the user's current working tree. State
plainly what will be set up and the workspace/branch naming the user can expect:

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

Accept replaces *0f — Create branch* and the mandatory Repo Sync; decline runs the
mandatory Repo Sync then *0f — Create branch* as today. Creation commands,
setup-artifact propagation, cleanup guidance, and fallback-on-failure behavior are
in `references/pipeline-steps.md` (*Step 0e — Workspace*) — never leave the user
without a working resolution.

### 0f — Create branch

The **in-place path** — auto mode, or interactive after declining the worktree
offer. (Accepted-worktree path already created the branch via `git worktree add -b`
in 0e; skip this sub-step.)

Use the `{branch_name}` already derived from `resolve.branch_prefix` before Step
0e/0f (see *0e — Workspace* above, `docs/config-schema.md`, and
`docs/naming-conventions.md`) — never re-derive or replace it here.

**If branch already exists:**
- Interactive mode: ask `continue` or `fresh`
- Auto mode: `continue` (checkout existing branch)

### 0g — Complexity gate (select the pipeline profile)

Decide **before Step 1** how much pipeline this issue earns, so a trivial edit
does not pay the full orchestration cost. The mechanism, the shared `XS … XL`
scale it reuses, and the safety rules are defined once in
`docs/agent-model-effort.md` (*Complexity → pipeline profile*) — apply that
document here; this sub-step is only the resolver's entry point into it.

When `resolve.adaptive_effort` is `false`, skip the gate entirely: set
`profile = full` and continue exactly as before. Otherwise select the profile
from the issue's **pre-work `Effort` band** (the `XS … XL` value in the issue's
`## Metadata`, written by `/issue-creator`) — never from a later agent output, so
the saving is real:

- `Effort` `XS`/`S`, asserted (not `(needs review)`/low-confidence) → `profile = light`
- `Effort` `M`/`L`/`XL` → `profile = full`
- `Effort` `XS`/`S` but low-confidence, **or** absent/unparseable → `profile = full` (ambiguous → fuller)

**What `light` collapses — the single home for this rule.** `full` leaves every
step exactly as it is today. Each step below points back to this table; the full
per-step mechanics live in `references/pipeline-steps.md` (*Step N → `light`
profile*).

| Step | `light` behavior |
|------|------------------|
| 1 — Research | Lighter pass: the already-resolved safety check and a focused scan of the obviously-affected file(s) still run; skip the broad dependency trace and external solution research. |
| 2 — Plan | Skip the 3-option synthesis entirely — do **not** spawn the synthesizer. Derive a **direct minimal plan** inline and record it as the selected option, so the Decision Record still has a real `Selected option`; the design-confirm checkpoint does not apply. |
| 3 — Propose relevant skills | Skip the sub-step — set `selected_skills = []` and go straight to the implementer, mirroring auto-mode behavior. |
| 4 — QA | Cap the review-fix loop at **1** cycle (a single review pass; fix once if blocking issues are found, then deliver) instead of `resolve.qa_max_cycles`. One reviewer spawn still runs — the fast path reduces depth, it does not skip review. UI review remains auto-detected as usual. |
| 5 — Deliver | **Unchanged** — always emits the Decision Record and Acceptance Criteria Verification table. The profile never removes durable memory. |

The profile may only be **revised upward** later (e.g. Step 1 research reports
`high`/`complex` on what the band called `S` → switch to `full` for the remaining
steps); never downgrade a `full` run to `light` mid-pipeline.

After preflight, surface the chosen profile so the effort decision is
transparent. `{workspace_note}` is ` (worktree)` in a worktree, empty otherwise;
`{profile}` is `light` or `full` — when `resolve.adaptive_effort` is `false`,
still print `effort: full` (the pinned profile) so the line is uniform:
```
[0/5] Preflight    ✓ issue #N open, branch: {branch_name}{workspace_note}, effort: {profile}
```

---

## Step 1 — Research

Deeply understand the issue, affected codebase, and possible solutions; also verifies the issue hasn't already been fixed (early-exit path closes it in auto mode). Spawn the researcher (`shared/agents/codebase-researcher.md`) with the canonical pattern — full delegation payload, phases, early-exit behavior, and inline fallback are in `references/pipeline-steps.md` (*Step 1 — Research*).

**`light` profile:** run a **lighter** research pass — see the profile table in
*Step 0g* for what it collapses, and `references/pipeline-steps.md` (*Step 1 —
Research → `light` profile*) for the mechanics. On a `high`/`complex` signal,
revise the profile **upward** to `full` (never downward).

After research:
```
[1/5] Research     ✓ read {N} files, complexity: {level}
```

---

## Step 2 — Plan

Generate implementation options and select one. Spawn the synthesizer (`shared/agents/synthesizer.md`) with the canonical pattern. It returns 3 options — minimal / balanced / comprehensive — with the balanced option usually recommended.

Selection behavior (interactive auto, interactive comment-and-wait, auto-pilot) and inline fallback are in `references/pipeline-steps.md` (*Step 2 — Plan*).

**`light` profile:** skip the 3-option synthesis — see the profile table in
*Step 0g*; full procedure in `references/pipeline-steps.md` (*Step 2 — Plan →
`light` profile*).

After plan selection:
```
[2/5] Plan         ✓ approach: {selected option name}
```

### Design-confirm checkpoint (high-complexity, interactive only)

High-risk work earns **exactly one** extra agreement point before code is written —
no new phase, artifact, or config key. Fires only when **both** hold: synthesizer
reports `overall_complexity: L`/`XL` or `overall_risk: High` (trivial/low/medium
skip it), **and** interactive mode (`--auto`/`IDD_AUTO_MODE=1` never pauses).
Accept (default) → Step 3 unchanged; decline → stop before implementing and
suggest re-running or picking a different option. Record the decision in the PR
Decision Record. Full procedure in `references/pipeline-steps.md` (*Step 2 —
Plan → Design-confirm checkpoint*).

---

## Step 3 — Implement

### Propose relevant skills (interactive only)

Before spawning the implementer, optionally augment it with external skills from
the index in `references/skill-index.md` (`https://github.com/luongnv89/skills`).
Detect installed skills against the catalog, propose the relevant subset, let the
user accept all/some/none into `selected_skills` — the implementer always falls
back to internal agents, so selecting none is unchanged behavior. Detection,
proposal, the `◆`/`○` block (no own `[N/5]` tracker line), and auto-mode behavior
are in `references/pipeline-steps.md` (*Step 3 — Propose relevant skills*).

**`light` profile:** skip this sub-step — see the profile table in *Step 0g*.

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

When the reviewer or test/build run returns blocking issues, spawn or re-message the fixer (`shared/agents/fixer.md`) the same way. Pass issue context, branch/base branch, reviewer findings, failing test/build output, commit message `fix({scope}): address review feedback (#N)`, and the pre-commit security convention it MUST run before committing (`docs/pre-commit-security.md`). Collect the fixer's JSON result and decide whether to start another cycle — never apply fixes inline when the Agent tool is available.

### UI/UX review (auto-detected)

UI review is **auto-detected per issue** — no config flag enables it. Scan the issue body/diff for UI work before the QA cycles, then run only what *can* and *should* run: the **code UI review** reads the diff, is environment-independent, and runs anywhere including headless (never gated on a GUI/browser); the **browser UI review** takes optional screenshots from a running app and runs only when reachable *and* opted in, else **skips with a warning while the code UI review still runs** — fail-soft.

Detection rules, the `ui-reviewer` spawn, the `ui_review.browser_review` gate, and skip/success messages are in `docs/ui-review.md`; the resolver's own deltas (diff command, variables, `resolve.ui_review.browser_review` as the gate key, findings flow) are in `references/pipeline-steps.md` (*Step 4 — UI/UX review*). Cycle mechanics and loop controls (`resolve.qa_max_cycles`, exit-on-clean, exit-on-stagnation) are in the same file (*Step 4 — QA*).

**`light` profile:** cap the review-fix loop at **1** cycle instead of
`resolve.qa_max_cycles` — see the profile table in *Step 0g*.

---

## Step 5 — Deliver

Push, create PR, and report.

### Verify all tests pass

When `resolve.auto_test` is true (default), run the full test suite one final time to confirm everything is clean after QA fixes. When false, skip this suite (QA Step 4 may still have run tests during the loop).

If tests fail at this point, print `✗ Final test run failed — PR not created` with the failure details and stop — even in auto mode, a failing PR is worse than no PR.

### Update documentation

If the changes affect documented behavior, update README, inline docs, and CHANGELOG as applicable.

### Push branch and create PR

Before pushing, run a final pre-push pass over the whole branch diff (`git diff --name-only "origin/${base}"...HEAD`) — catches secrets that slipped in during QA fixes. Run the **Primary Pattern** in `docs/pre-commit-security.md` (authoritative — do not improvise a weaker check); export `IDD_AUTO_MODE=1` first in auto mode. Only after the scan passes (or warnings are accepted):

```bash
git push -u origin {branch_name}
gh pr create --title "{pr_title}" --body "{pr_body}"
```

**PR title:** `{type}({scope}): {description} (#{issue_number})` (see `docs/naming-conventions.md`)

**PR body:** Fill the template in `references/report-templates.md` (*PR Body Template*) — Summary, Approach, **Decision Record** (from `.gitissue/analysis-<N>.json` if present, else synthesized), Changes table, Test Results, **Acceptance Criteria Verification** table. The last two are the durable analysis signal surviving squash-merge; never omit them (see `docs/idd-methodology.md`).

### Project board sync

If `projects.sync_enabled` is true, update status to `status_map.done` (see `docs/github-projects-sync.md`). After delivery:
```
[5/5] Deliver      ✓ PR #{pr_number} created
```

### Run-log entry (monitoring)

At **every terminal outcome** — delivered PR (`success`), early exit because
already fixed (`already_resolved`), or a failed step (`failed`) — append exactly
**one JSON line** to `.gitissue/runs.jsonl`, **unless invoked with `--no-run-log`**,
in which case append **nothing** and return the telemetry to the caller instead.
`--no-run-log` enforces the **single writer** rule under `/auto-pilot` and is
independent of `--auto` — a standalone `/issue-resolver <N> --auto` is *not*
suppressed and still writes. Field derivation (the object's keys, the researcher
`complexity` collapse, when to omit `profile`) and the full suppression rationale
are in `references/report-templates.md` (*Run-log entry — field derivation and
suppression*), which follows the schema in `docs/config-schema.md`
(*`.gitissue/runs.jsonl` — run log*).

```bash
# Only when --no-run-log is NOT set:
printf '%s' "$run_json" | python3 shared/scripts/gi-runlog.py --append
# Under --no-run-log, validate the telemetry you return without writing:
printf '%s' "$run_json" | python3 shared/scripts/gi-runlog.py --echo
# Fallback when the script cannot run: mkdir -p .gitissue && printf '%s\n' "$run_json" >> .gitissue/runs.jsonl
```

Best-effort and non-fatal — a failed write never blocks the reported run result. Only append; never rewrite or reorder existing lines.

---

## Closing Summary

After the pipeline completes, print **one** closing block carrying only what the
live `[N/5]` tracker never printed: the outcome line, the `risk_rating`, and the
single PR reference (number, title, URL, `Closes #N`). Repeating any tracker
metric — per-step pass/fail, files read, complexity, option, files changed, test
counts, QA cycles — is the duplication issue #165 removed. Use the matching
variant in `references/report-templates.md` (*Closing Summary*): *Successful
Resolution* (every step passed), *Resolution With Warnings* (QA left residual
issues or another step warned), or *Already Resolved* (Step 0/1 found the issue
already closed — no PR reference). The *Expected Inline Pipeline Output* example
in the same file shows the tracker and closing block together.

---

## Auto-Pilot Mode

When invoked with `--auto` (or by `/auto-pilot`), the entire pipeline runs without user interaction. Each step above already states its own auto behavior; these are the cross-cutting invariants:

- **Environment:** Export `IDD_AUTO_MODE=1` before any shell snippet that consults it (`docs/pre-commit-security.md`).
- **Workspace:** Always in-place. Skip Step 0e entirely — no `git worktree add` on the default resolution path. Run mandatory Repo Sync, then *0f — Create branch*.
- **Never blocks:** *0c* skips the assignment guard and logs blocking labels as warnings; *0g* still runs (reads the pre-work `Effort` band, no prompt); *Step 1* closes an already-resolved issue with a comment and exits cleanly; *Step 2* auto-selects the recommended option and design-confirm never appears; *Step 3* continues past the max-commits guard with a warning and never prompts for skills (internal agents only); *Step 4* runs its cycles autonomously and delivers with known issues on stagnation.
- **Deliver:** Create PR. Do NOT merge — merging is `/auto-pilot` or `/issue-pr-review`'s job. Under `/auto-pilot` the selected `profile` is **returned** in the telemetry (with `--no-run-log`) and folded into auto-pilot's single run-log line; a standalone `--auto` run writes `profile` itself.

No `[y/N]` prompts, no `Choose:` prompts, no `Continue?` prompts. Every decision point has a defined auto behavior.

---

## Edge Cases

No acceptance criteria, empty issue body, large issues (20+ files), test failure/timeout, and branch-already-exists are all handled — full behavior for each is in `references/pipeline-steps.md` (*Edge Cases*).

---

## Platform Driver and Output Conventions

All tracker access follows the GitHub driver — `--json` with explicit field selection, never parsed text output. The full operation catalog and driver rules live in docs/platform-github.md.

Terminal output follows the `docs/terminal-style.md` contract — symbols `● ✓ ✗ ◆ ⚡ ⚠ ○`, two-space indent, `┄` separators, URLs on their own line, ≤80 chars, one blank line between sections, static sequential output (no animation), plus the `[N/5]` pipeline step counter. Errors use the rich format from `references/error-messages.md`: `✗ what failed`, then `To fix:  <command>`, then a docs link when applicable.

## Additional Resources

Navigation index for the *Bundled dependency precheck* list above (that list, not this one, is the authoritative guard).

**Agents** (`shared/agents/`): `codebase-researcher.md` (Step 1) · `synthesizer.md` (Step 2) · `implementer.md` (Step 3) · `code-reviewer.md` (Step 4) · `ui-reviewer.md` (Step 4) · `fixer.md` (Step 4)

**References** (`references/`): `pipeline-steps.md` (payloads/phases/fallbacks, Steps 0e–4, edge cases) · `report-templates.md` (PR body, closing summary, run-log fields, expected output) · `bug-verification.md` (reproduction checkpoint, Step 3) · `skill-index.md` (external-skill catalog, Step 3) · `error-messages.md` (error catalog)

**Docs** (`docs/`): `sync-conventions.md` · `naming-conventions.md` · `pre-commit-security.md` · `idd-methodology.md` · `github-projects-sync.md` · `config-schema.md` · `run-log-schema.md` · `agent-model-effort.md` · `shared-agent-conventions.md` · `platform-github.md` · `terminal-style.md` · `ui-review.md` — the repo-root `DESIGN.md` is the human-facing companion to the last of these (color palette, per-command mockups) and is **not** bundled.
