---
name: issue-resolver
description: "Create an atomic PR closing a GitHub issue end-to-end via a 6-step pipeline. Use to resolve, fix, or implement issue #N. Don't use for analysis without fixing (/issue-analysis), reviewing a PR (/issue-pr-review), or bulk backlog work (/auto-pilot)."
license: MIT
compatibility: "Requires git and GitHub CLI (gh) with authentication and push access. Self-contained — uses shared agents from shared/agents/."
effort: max
metadata:
  version: 0.14.0
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

The argument must be a GitHub issue number. The `--auto` flag is set automatically when invoked by `/auto-pilot`.

The `--no-run-log` flag is **orthogonal to `--auto`** and is passed **only by `/auto-pilot`** (which writes the single run-log line itself — see *Run-log entry*). It is **not** implied by `--auto`/`IDD_AUTO_MODE=1`: a standalone `/issue-resolver <N> --auto` still appends its own line. This keeps `/auto-pilot` the single writer per processed issue without silencing direct auto-mode resolves.

## Prerequisites

Before any operation, verify the environment. On failure, output the exact error from `references/error-messages.md` and stop.

1. Confirm git repository: `git rev-parse --git-dir`
2. Confirm `gh` is installed: `which gh`
3. Confirm authentication: `gh auth status`
4. Confirm GitHub remote exists: `git remote -v`

## Repo Sync Before Edits (mandatory)

This applies to the **in-place path** (auto mode, or interactive when the user declines the worktree offer in Step 0e). On the **worktree path** the sync is unnecessary — `git worktree add` branches from a freshly fetched `origin/<base>`, so the new workspace already starts current (see Step 0e and `references/pipeline-steps.md`).

Before making file modifications, sync with remote using the stash-first pattern (see `docs/sync-conventions.md` for the full convention and recovery procedure):

```bash
branch="$(git rev-parse --abbrev-ref HEAD)"
dirty=0
if [ -n "$(git status --porcelain)" ]; then
  git stash push -u -m "pre-sync: ${branch}"
  dirty=1
fi
git fetch origin
git pull --rebase origin "$branch"
if [ "$dirty" -eq 1 ]; then
  git stash pop || {
    echo "✗ Stash pop failed — recover with: git stash list && git stash show -p stash@{0}"
    exit 1
  }
fi
```

If `origin` is missing or rebase conflicts occur, stop and ask the user (interactive) or abort with a clear error (auto).

## Configuration

Load `.gitissue.yml` from the repo root once at skill start. If the file does not exist, use defaults and print:

```
○ First run — using default config. Run /init-gitissue to customize.
```

Defaults:
- `issue.auto_normalize: true`
- `resolve.approval_gate: auto` (ignored in auto mode — always auto)
- `resolve.branch_prefix: "auto"`
- `resolve.auto_test: true`
- `resolve.test_timeout: 300`
- `resolve.pr_auto_link: true`
- `resolve.max_commits: 10`
- `resolve.qa_max_cycles: 5`
- `resolve.ui_review.browser_review: "ask"` — browser (screenshot) review mode (`"false"` | `"ask"` | `"true"`); `"ask"` prompts interactive users, skips in auto mode. Does **not** gate the code-level UI review, which is auto-detected and always runs when UI work is present (see *Step 4 — UI/UX review*).

---

## Subagent Architecture

The resolve pipeline delegates heavy work to subagents to keep the main agent's **context window** clean and the **token budget** predictable. All agents are in `shared/agents/`.

```
Main Agent (orchestrator)
├── Step 0: Preflight (lightweight — stays in main)
│
├── Spawn: Codebase Researcher subagent (Step 1)
│   Verifies not already fixed, scans codebase, assesses complexity
│   Returns: structured findings (JSON or markdown)
│
├── Spawn: Synthesizer subagent (Step 2)
│   Proposes 3 implementation options from research
│   Returns: analysis + ranked options
│
├── Spawn: Implementer subagent (Step 3)
│   Writes code + all tests based on selected plan
│   Returns: files changed, tests written, commits
│
├── Step 4: QA (main agent orchestrates review-fix loop)
│   Spawns Code Reviewer subagent per cycle
│   Spawns/reuses Fixer subagent for blocking findings
│   Runs tests/build between cycles
│   Max 5 cycles
│
└── Step 5: Deliver (main agent — push + create PR + report)
```

Read `shared/agents/codebase-researcher.md` for the researcher prompt (Ada Lovelace).
Read `shared/agents/synthesizer.md` for the synthesizer prompt (Nikola Tesla).
Read `shared/agents/implementer.md` for the implementer prompt (Linus Torvalds).
Read `shared/agents/code-reviewer.md` for the reviewer prompt (Marie Curie).
Read `shared/agents/ui-reviewer.md` for the UI/UX reviewer prompt (Dieter Rams).
Read `shared/agents/fixer.md` for the fix-cycle prompt (Thomas Edison).

Every agent opens with a persona + role header and a compact I/O contract; the
conventions they share (spawn note, tool posture, injection boundary, confidence
scale, `gh --json`, autonomous operation) live once in
`docs/shared-agent-conventions.md`.

### Orchestrating the agents (model/effort, monitoring, audit)

As the orchestrator, for each spawned step:

1. **Name the persona** — pass the agent's persona + role in the spawn
   `description` (e.g. `"Ada Lovelace — research issue #N"`), so terminal output
   and the run log identify a recognizable agent.
2. **Size the model/effort** — select the tier per `docs/agent-model-effort.md`
   from the most-recent complexity signal (researcher `complexity` → synthesizer
   `overall_complexity`), falling back to each agent's default tier. The
   orchestrator is the decision point; selection is advisory and never blocks.
3. **Monitor before advancing** — verify the agent returned its contract's
   required shape (researcher: `status` + `complexity`; synthesizer: exactly one
   `recommended` option; implementer: commits + test stats + repro for bugs;
   reviewer/fixer: `result` + counts). A missing/blocking return is itself the
   signal: stop (interactive) or follow the step's auto behavior.
4. **Audit** — record the per-step signal the pipeline already folds into the run
   log line (`complexity`, `qa_cycles`, `outcome`, `duration_s` — see the
   *run-log* note in Step 5) plus the printed `[N/5]` tracker line.

### Environment check

If the Agent tool is available, use subagents as described above.
If not (e.g., Claude.ai), execute each step inline using the fallback instructions.

### Bundled dependency precheck

Verify that this skill's bundled subagent prompts and reference files are present.
If any are missing, stop immediately and print:

```
text
✗ Missing bundled dependency: {missing_file}

  To fix:  asm install https://github.com/luongnv89/idd --skill issue-resolver
           (or reinstall the full distribution)

  Then restart the agent session and re-run /issue-resolver.
```

Check these files relative to the skill's directory (the dirname of this SKILL.md):

- `references/agents/codebase-researcher.md` — Research subagent (Step 1)
- `references/agents/synthesizer.md` — Plan subagent (Step 2)
- `references/agents/implementer.md` — Implement subagent (Step 3)
- `references/agents/code-reviewer.md` — QA review subagent (Step 4)
- `references/agents/ui-reviewer.md` — UI/UX review subagent (Step 4, auto-detected)
- `references/agents/fixer.md` — QA fix subagent (Step 4)
- `references/pipeline-steps.md` — Full delegation payloads, phases, and inline fallbacks for Steps 1–4
- `references/report-templates.md` — PR body template, closing summary templates, and expected inline output
- `references/bug-verification.md` — Red-capable reproduction checkpoint for bug issues (Step 3, before the fix)
- `references/docs/sync-conventions.md` — stash-first sync convention and recovery
- `references/docs/naming-conventions.md` — branch, commit, PR naming conventions
- `references/docs/pre-commit-security.md` — pre-commit security conventions reference
- `references/docs/idd-methodology.md` — IDD methodology (durable analysis fields)
- `references/docs/github-projects-sync.md` — GitHub Projects status sync
- `references/docs/config-schema.md` — configuration schema reference

---

## Pipeline Overview

The resolve pipeline has 6 steps (0-5). Display progress using the `[N/5]` step counter:

```
  ◆ Resolve Pipeline
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  [0/5] Preflight    ✓ issue #42 open, not yet resolved
  [1/5] Research     ✓ read 12 files, complexity: medium
  [2/5] Plan         ✓ option 2 selected: balanced refactor
  [3/5] Implement    ✓ 3 files changed, 8 unit tests, 2 e2e tests
  [4/5] QA           ✓ clean after 2 cycles
  [5/5] Deliver      ✓ PR #87 created
```

Each step prints a new line when it starts (with `●`) and updates to `✓` on success or `✗` on failure. Static sequential output — no animation.

---

## Step 0 — Preflight

Check whether this issue should be worked on at all.

```
● Preflight check for issue #N...
```

### 0a — Fetch issue

```bash
gh issue view {N} --json number,title,body,labels,assignees,state,comments
```

**If not found:** output error and stop.
**If closed:** output warning and stop.

### 0b — Check for existing work

```bash
# Check for existing branches
git branch -a | grep -i "{N}"

# Check for existing PRs targeting this issue
gh pr list --state open --json number,title,body,headRefName --limit 20
```

Scan PR bodies for `Closes #N`, `Fixes #N`, `Resolves #N`. If a PR already exists:

```
⚠ PR #{pr_number} already targets issue #N
  https://github.com/owner/repo/pull/{pr_number}

  Use /issue-pr-review {pr_number} to review it instead.
```
Stop.

### 0c — Guards

**In interactive mode**, check guards and prompt:

- **Assignment guard:** If assigned to someone else, warn and ask to continue.
- **Blocking label guard:** If `wontfix`, `blocked`, `do-not-merge` labels exist, warn and ask.

**In auto mode**, skip assignment guard (auto-pilot resolves regardless). For blocking labels, skip and log a warning — do not stop.

### 0d — Auto-normalize

If `issue.auto_normalize` is true and the issue is not already normalized (no `<!-- gitissue:normalized v1 -->` marker):

1. Classify issue type, generate normalized body, add marker
2. Post backup comment with original body
3. Update issue body via `gh issue edit`
4. Re-fetch issue

If normalization fails, warn and continue with original body.

### 0e — Workspace (interactive only)

Decide *where* the resolution work happens. The branch name is the same in both
cases: `{type}/{N}-{short-description}` (see `docs/naming-conventions.md`).

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

    Branch:    {type}/{N}-{short-description}
    Worktree:  ../{repo}-worktrees/{type}-{N}-{short-description}
    Setup:     copies your gitignored local config (.env*, and similar),
               then runs this project's detected install/bootstrap so the
               workspace is ready to run without manual reconfiguration.

  Accepting keeps your current working tree untouched. Declining uses the
  current working tree with the existing sync and branch behavior.

  Resolve in a new worktree? [Y/n]
```

- **Accept (default):** create the worktree and prepare it, then continue the
  pipeline from inside it. This **replaces** *0f — Create branch* and the
  mandatory Repo Sync (the worktree branches from a freshly fetched
  `origin/<base>`, so it starts current). Full procedure — creation commands,
  generic setup-artifact propagation, and cleanup guidance — is in
  `references/pipeline-steps.md` (*Step 0e — Workspace*).
- **Decline:** proceed in the current working tree exactly as today — run the
  mandatory Repo Sync, then *0f — Create branch*. No behavior change.

If worktree creation fails, warn and fall back to the in-place path (see
`references/error-messages.md` → *Worktree creation failed*). If setup fails
after the worktree was created, first remove that partial worktree (and delete
only a branch created by this step), then fall back to the in-place path (see
`references/error-messages.md` → *Worktree setup failed*). Never leave the user
without a working resolution.

### 0f — Create branch

This is the **in-place path** — used in auto mode, and in interactive mode when
the user declined the worktree offer. (On the accepted-worktree path the branch
was already created by `git worktree add -b` in 0e; skip this sub-step.)

Create working branch: `{type}/{N}-{short-description}` (see `docs/naming-conventions.md`).

**If branch already exists:**
- Interactive mode: ask `continue` or `fresh`
- Auto mode: `continue` (checkout existing branch)

After preflight:
```
[0/5] Preflight    ✓ issue #N open, branch: {branch_name}{workspace_note}
```

where `{workspace_note}` is ` (worktree)` when the resolution is running in a
worktree, and empty otherwise.

---

## Step 1 — Research

Deeply understand the issue, affected codebase, and possible solutions. Also verifies the issue hasn't already been fixed (early-exit path closes the issue in auto mode).

Spawn the `codebase-researcher` subagent (see `shared/agents/codebase-researcher.md`). Use this Agent invocation:

```python
Agent(
  description="Ada Lovelace — research issue #N",
  prompt=<codebase-researcher.md prompt with {variables} replaced>,
  subagent_type="general-purpose"  # NOT "codebase-researcher"
)
```

Full delegation payload, phases, early-exit behavior, and inline fallback are in `references/pipeline-steps.md` (*Step 1 — Research*).

After research:
```
[1/5] Research     ✓ read {N} files, complexity: {level}
```

---

## Step 2 — Plan

Generate implementation options and select one. Spawn the `synthesizer` subagent (see `shared/agents/synthesizer.md`). Use this Agent invocation:

```python
Agent(
  description="Nikola Tesla — plan issue #N",
  prompt=<synthesizer.md prompt with {variables} replaced>,
  subagent_type="general-purpose"  # NOT "synthesizer"
)
```

It returns 3 options — minimal / balanced / comprehensive — with the balanced option usually recommended.

Selection behavior (interactive auto, interactive comment-and-wait, auto-pilot) and inline fallback are in `references/pipeline-steps.md` (*Step 2 — Plan*).

After plan selection:
```
[2/5] Plan         ✓ approach: {selected option name}
```

### Design-confirm checkpoint (high-complexity, interactive only)

High-risk work earns **exactly one** extra agreement point before code is written —
no new phase, artifact, or config key. The checkpoint is gated entirely on data Step 2
already produced (the synthesizer's recommended option, its change summary, and its
residual risk).

Trigger it only when **both** hold:

1. **High-complexity tier** — the synthesizer reports `overall_complexity: L` or `XL`,
   or `overall_risk: High` (equivalently the most-recent complexity signal is the
   researcher's `complexity: high|complex`). Trivial / low / medium → no checkpoint.
2. **Interactive mode** — `--auto` / `IDD_AUTO_MODE=1` never pauses (see *Auto-Pilot Mode*).

When triggered, present the already-selected recommended option for confirmation:

```
◆ Design confirm — issue #N (high complexity)
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Proceed with Option {recommended.number} — {recommended.name}?
    Changes:        {recommended.summary} ({len(files_to_modify)} files)
    Residual risk:  {recommended.risk_details}
  Proceed? [Y/n]
```

Accept (default) → continue to Step 3 unchanged. Decline → stop before implementing,
leave the branch in place, and suggest re-running `/issue-resolver {N}` or picking a
different option. **Record the decision** (selected option + complexity) in the PR
Decision Record so it survives into durable memory — see `references/report-templates.md`
(*Design-confirm* line). Full procedure, including the auto-mode log line, is in
`references/pipeline-steps.md` (*Step 2 — Plan → Design-confirm checkpoint*).

---

## Step 3 — Implement

Write code and tests based on the selected plan. Spawn the `implementer` subagent (see `shared/agents/implementer.md`) with the plan, branch name, and naming conventions. Use this Agent invocation:

```python
Agent(
  description="Linus Torvalds — implement issue #N",
  prompt=<implementer.md prompt with {variables} replaced>,
  subagent_type="general-purpose"  # NOT "implementer"
)
```

For **bug** issues, the implementer first runs the red-capable reproduction checkpoint — name a command/test that reproduces the symptom and confirm it fails red for the stated reason **before** the fix, then convert it to a regression test when a clean seam exists. The reproduction is returned and surfaced as evidence in the PR Decision Record and acceptance table. Non-bug issues skip it; auto mode never blocks. See `references/bug-verification.md`.

Full payload, commit guardrails, and inline fallback are in `references/pipeline-steps.md` (*Step 3 — Implement*).

After implementation:
```
[3/5] Implement    ✓ {N} files changed, {U} unit tests, {E} e2e tests
```

---

## Step 4 — QA

Automated review-fix loop: review → test → fix → repeat until clean or max cycles reached. Each cycle spawns a *fresh* `code-reviewer` subagent (see `shared/agents/code-reviewer.md`) for unbiased review and delegates blocking fixes to the `fixer` subagent (see `shared/agents/fixer.md`).

### Spawning the code reviewer

For each QA cycle, spawn a general-purpose agent with the code-reviewer prompt:

```python
Agent(
  description="Marie Curie — review cycle N",
  prompt=<code-reviewer.md prompt with {variables} replaced>,
  subagent_type="general-purpose"
)
```

**Do NOT use `subagent_type: "code-reviewer"`** — that is not a registered agent type. Always use `general-purpose` and pass the full code-reviewer prompt (see `shared/agents/code-reviewer.md`).

When the reviewer or test/build run returns blocking issues, spawn or re-message the fixer subagent:

```python
Agent(
  description="Thomas Edison — fix QA cycle N",
  prompt=<fixer.md prompt with {variables} replaced>,
  subagent_type="general-purpose"
)
```

Pass the issue context, branch/base branch, reviewer findings, failing test/build output, commit message `fix({scope}): address review feedback (#N)`, and `security_convention`: `references/docs/pre-commit-security.md` — the bundled pre-commit security scan the fixer MUST run before committing. The main agent collects the fixer's JSON result and decides whether to start another QA cycle; it should not apply fixes inline when the Agent tool is available.

### UI/UX review (auto-detected)

UI review is **auto-detected per issue** — no config flag enables it. Before the QA cycles, scan the issue body and working diff for UI work, then run only the review that *can* and *should* run:

- **Code UI review** reads the diff and changed files — environment-independent. It runs whenever UI work is detected, on any machine **including a headless server**, and is never gated on a GUI, running app, or browser.
- **Browser UI review** is optional: it captures screenshots from a running app, so it runs only when a reachable app is up *and* the user opted in. When it can't, it **skips with a warning and the code UI review still runs** — fail-soft, never block.

Detection (UI keywords in title/body, or UI files in the diff), the code-mode and browser-mode `ui-reviewer` spawns, the report-only `ui_env` display-environment label, the `resolve.ui_review.browser_review` gate, the headless capability check, and the skip/success messages are all in `references/pipeline-steps.md` (*Step 4 — UI/UX review*). UI `action: "fix"` findings join the QA fixable issues handled by the fixer.

Cycle mechanics, loop controls (`resolve.qa_max_cycles`, exit-on-clean, exit-on-stagnation), and the remaining-issues flow are in `references/pipeline-steps.md` (*Step 4 — QA*).

---

## Step 5 — Deliver

Push, create PR, and report.

### Verify all tests pass

Run the full test suite one final time to confirm everything is clean after QA fixes.

If tests fail at this point:
```
✗ Final test run failed — PR not created
  {failure details}
```
Stop (even in auto mode — a failing PR is worse than no PR).

### Update documentation

If the changes affect documented behavior:
- Update README if applicable
- Update inline documentation
- Update CHANGELOG if the project maintains one

### Push branch

The implementer ran the security scan per commit during Step 3, but before pushing you MUST run a final pre-push pass over the whole branch diff (`git diff --name-only "origin/${base}"...HEAD`) — it catches secrets that may have slipped in during QA fixes. Run the **Primary Pattern** in `docs/pre-commit-security.md` (authoritative; do not improvise a weaker check); export `IDD_AUTO_MODE=1` first in auto mode. It enforces, in order:

1. **Block on real secrets** — secret-bearing filenames (`.env`, `*.key`, `*.pem`, `credentials.json`, `id_rsa`, …) or real API-key patterns (OpenAI, AWS, GitHub, Slack, GitLab, Google) in any text file in the diff → print the offending file and `exit 1`. Never push.
2. **Warn (non-blocking) on** large files (>10 MB without LFS), build artifacts in the diff (`node_modules`, `dist`, `__pycache__`, `*.pyc`, …), and being on a protected branch. Interactive: prompt `Proceed anyway? [y/N]`; auto (`IDD_AUTO_MODE=1`): log and continue.

Only after the scan passes (or warnings are accepted):

```bash
git push -u origin {branch_name}
```

### Create PR

```bash
gh pr create --title "{pr_title}" --body "{pr_body}"
```

**PR title:** `{type}({scope}): {description} (#{issue_number})` (see `docs/naming-conventions.md`)

**PR body:** Fill the template in `references/report-templates.md` (section *PR Body Template*) — Summary, Approach, **Decision Record** (lifted from `.gitissue/analysis-<N>.json` if present, else synthesized from Steps 1-2 findings), Changes table, Test Results, **Acceptance Criteria Verification** table. The Decision Record and the verification table are the durable analysis signal that survives the squash-merge into git history; do not omit them. See *Analysis Artifacts and Durable Memory* in `docs/idd-methodology.md`.

### Project board sync

If `projects.sync_enabled` is true, update status to `status_map.done` (see `docs/github-projects-sync.md`).

After delivery:
```
[5/5] Deliver      ✓ PR #{pr_number} created
```

### Run-log entry (monitoring)

At **every terminal outcome** of the pipeline — a delivered PR (`success`), an
early exit because the issue was already fixed (`already_resolved`), or a failed
step (`failed`) — append exactly **one JSON line** to `.gitissue/runs.jsonl` for a
persistent, cross-run telemetry signal — **unless invoked with `--no-run-log`**
(see *Suppression rule* below), in which case append **nothing** and return the
telemetry to the caller instead. Build the object from values already known at
this point (`ts`, `issue`, `mode`, `skill`, `outcome`, `pr`, plus optional
`complexity`, `qa_cycles`, `duration_s`, `skipped_reason`); the schema and field
list are defined once in `docs/config-schema.md` (*`.gitissue/runs.jsonl` — run
log*) — follow it rather than re-deriving fields here.

> **Suppression rule (single writer under `/auto-pilot`).** When invoked with
> `--no-run-log`, **do not append** to `.gitissue/runs.jsonl` at all. This flag
> is passed only by `/auto-pilot`, which runs this resolver as a subagent and
> writes the **single** run-log line for the issue itself — appending here too
> would double-write one line per processed issue and skew `/idd-doctor`'s
> resolve-rate and median-QA metrics (they count over every line). Instead,
> **return** the telemetry the resolver alone knows — `outcome`, `qa_cycles`,
> `complexity`, `duration_s` — in the subagent result payload so the orchestrator
> can fold it into its enriched line. The flag is **independent of `--auto`**: a
> standalone `/issue-resolver <N> --auto` is *not* suppressed and still appends
> its own line (it is the single writer in that case).

```bash
# Only when --no-run-log is NOT set:
mkdir -p .gitissue
printf '%s\n' "$run_json" >> .gitissue/runs.jsonl
```

This write is **best-effort and non-fatal**: if it fails, report the run result
normally — never fail or block a run because the run log could not be written.
Do not rewrite or reorder existing lines; only append.

---

## Closing Summary

After the pipeline completes, print **one** closing block that repeats **nothing**
the live `[N/5]` tracker already showed — not the per-step pass/fail, and not the
per-step metrics (files read, complexity, option, files changed, test counts, QA
cycles are all on the tracker lines). Repeating any of them is the duplication
issue #165 removed. The closing block carries only the facts the tracker never
printed: the outcome line, the `risk_rating`, and the single PR reference (number,
title, URL, `Closes #N`). Use the matching variant in
`references/report-templates.md` (*Closing Summary*):

- *Successful Resolution* — every step passed
- *Resolution With Warnings* — QA left residual issues or another step warned
- *Already Resolved* — Step 0 or Step 1 detected the issue was already closed (no PR reference, since none was created)

---

## Auto-Pilot Mode

When invoked with `--auto` (or by `/auto-pilot`), the entire pipeline runs without user interaction:

- **Environment:** Export `IDD_AUTO_MODE=1` before any shell snippet that consults it (the pre-commit security scan reads this to switch from prompt-on-warning to log-and-continue; see `docs/pre-commit-security.md`).
- **Workspace:** Always the **in-place** path. Skip Step 0e entirely — no worktree prompt, no `git worktree add` on the default resolution path. Run mandatory Repo Sync, then *0f — Create branch* in the current working tree. Isolated worktrees remain **interactive-only** (Step 0e).
- **Preflight:** Skip assignment guard. Log blocking labels as warnings, don't stop.
- **Research:** If already resolved, close the issue with a comment and exit cleanly.
- **Plan:** Auto-select the recommended option (best balance of quality/effort). The high-complexity design-confirm checkpoint never appears in auto mode — log the selected option + complexity for the Decision Record and proceed without pausing.
- **Implement:** Continue past max commits guard with a warning.
- **QA:** Run full cycle autonomously. If stagnation detected, continue to deliver with known issues.
- **Deliver:** Create PR. Do NOT merge — merging is handled by `/auto-pilot` or `/issue-pr-review`.

No `[y/N]` prompts, no `Choose:` prompts, no `Continue?` prompts. Every decision point has a defined auto behavior.

---

## Expected Output

A successful resolve prints the 6-step tracker, then the single Closing Summary
block — per-step status appears only in the tracker, the full PR reference only in
the closing block, never both. See the *Expected Inline Pipeline Output* example in
`references/report-templates.md`.

## Edge Cases

### No acceptance criteria
PR body notes: `> **Note:** No acceptance criteria defined — manual review recommended.`

### Issue body is empty
- Interactive: warn and ask to continue
- Auto: warn in log, continue with title-only context

### Large issues (20+ files estimated)
- Interactive: warn and ask
- Auto: warn in log, continue

### Tests fail or timeout
- PR is not created. The Verify step stops with the failing test output and a resume hint.

### Branch already exists
- Interactive: `continue` or `fresh` prompt.
- Auto: resume from the existing branch.

---

## GitHub CLI Convention

Every `gh` command uses `--json` with explicit field selection. Never parse text output.

## Terminal Output

Follow DESIGN.md symbol vocabulary:
- Step counter: `[N/5]` for pipeline steps
- Symbols: `●` progress, `✓` success, `✗` failure, `◆` header, `⚡` recommendation, `⚠` warning, `○` info
- Two-space indent, `┄` separators, URLs on own line, max 80 chars

## Error Handling

All errors use rich format from `references/error-messages.md`:
```
✗ Short error description

  To fix:  <actionable command>
  Docs:    <url>
```

## Additional Resources

- **`shared/agents/codebase-researcher.md`** — Research subagent (Step 1)
- **`shared/agents/synthesizer.md`** — Plan subagent (Step 2)
- **`shared/agents/implementer.md`** — Implement subagent (Step 3)
- **`shared/agents/code-reviewer.md`** — QA review subagent (Step 4)
- **`shared/agents/ui-reviewer.md`** — UI/UX review subagent (Step 4, auto-detected)
- **`shared/agents/fixer.md`** — QA fix subagent (Step 4)
- **`references/pipeline-steps.md`** — Full delegation payloads, phases, and inline fallbacks for Steps 1–4
- **`references/report-templates.md`** — PR body template, closing summary templates, and expected inline output
- **`references/bug-verification.md`** — Red-capable reproduction checkpoint for bug issues (Step 3, before the fix)
- **`references/error-messages.md`** — Complete error catalog
- **`docs/naming-conventions.md`** — Branch, commit, PR naming conventions
- **`docs/github-projects-sync.md`** — GitHub Projects status sync
- **`DESIGN.md`** — Terminal output style guide
- **`docs/config-schema.md`** — Configuration schema
