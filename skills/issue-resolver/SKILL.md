---
name: issue-resolver
description: "Create an atomic PR that closes a GitHub issue end-to-end via a 6-step pipeline. Use for resolve, fix, implement, work on, or take issue #N. Don't use for analyzing an issue without implementing (use /issue-analysis), reviewing an existing PR (use /issue-pr-review), or bulk backlog processing (use /auto-pilot)."
license: MIT
compatibility: "Requires git and GitHub CLI (gh) with authentication and push access. Self-contained — uses shared agents from shared/agents/."
effort: max
metadata:
  version: 0.11.0
  author: Luong NGUYEN <luongnv89@gmail.com>
---

# /issue-resolver N

Resolve a GitHub issue end-to-end — from issue to atomic PR in 6 steps.

## Invocation

| Invocation | Mode | What happens |
|------------|------|--------------|
| `/issue-resolver <N>` | interactive | Resolve issue #N, ask user to pick plan |
| `/issue-resolver <N> --auto` | auto-pilot | Resolve fully autonomously, no user prompts |

The argument must be a GitHub issue number. The `--auto` flag is set automatically when invoked by `/auto-pilot`.

**`--no-run-log` flag:** suppresses this skill's own append to `.gitissue/runs.jsonl` (see *Run-Log* below). `/auto-pilot` passes it so that **one** enriched line is written per processed issue by the orchestrator instead of two. Standalone `/issue-resolver <N>` and `/issue-resolver <N> --auto` (run directly, not under auto-pilot) do **not** set it and write their own line. The flag is independent of `--auto` — `--auto` alone still logs.

## Prerequisites

Before any operation, verify the environment. On failure, output the exact error from `references/error-messages.md` and stop.

1. Confirm git repository: `git rev-parse --git-dir`
2. Confirm `gh` is installed: `which gh`
3. Confirm authentication: `gh auth status`
4. Confirm GitHub remote exists: `git remote -v`

## Repo Sync Before Edits (mandatory)

This applies to the **in-place path** (auto mode, or interactive when the user declines the worktree offer in Step 0e). On the **worktree path** the sync is unnecessary — `git worktree add` branches from a freshly fetched `origin/<base>`, so the new workspace already starts current (see Step 0e and `references/pipeline-steps.md`).

Before making file modifications, sync with remote using the stash-first pattern (see `references/docs/sync-conventions.md` for the full convention and recovery procedure):

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

Read `references/agents/codebase-researcher.md` for the researcher prompt.
Read `references/agents/synthesizer.md` for the synthesizer prompt.
Read `references/agents/implementer.md` for the implementer prompt.
Read `references/agents/code-reviewer.md` for the reviewer prompt.
Read `references/agents/fixer.md` for the fix-cycle prompt.

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
- `references/report-templates.md` — PR body template, final report templates, and expected inline output
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

Record the run start time so the final run-log line can report `duration_s` (env vars don't persist across Bash calls — see *Run-Log*):

```bash
mkdir -p .gitissue && date -u +%s > .gitissue/.run-start-{N}
```

### 0a — Fetch issue

```bash
gh issue view {N} --json number,title,body,labels,assignees,state,comments
```

**If not found:** output error and stop. (No issue number resolved → no run-log line.)
**If closed:** output warning, write a run-log line (`outcome: "skipped"`, `skipped_reason: "closed"` — see *Run-Log*; suppressed under `--no-run-log`), and stop.

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
Write a run-log line (`outcome: "skipped"`, `skipped_reason: "already_resolved"`, `pr: {pr_number}` — see *Run-Log*; suppressed under `--no-run-log`, in which case return the telemetry instead), then stop.

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
cases: `{type}/{N}-{short-description}` (see `references/docs/naming-conventions.md`).

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

Create working branch: `{type}/{N}-{short-description}` (see `references/docs/naming-conventions.md`).

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

Spawn the `codebase-researcher` subagent (see `references/agents/codebase-researcher.md`). Use this Agent invocation:

```python
Agent(
  description="Research issue #N",
  prompt=<codebase-researcher.md prompt with {variables} replaced>,
  subagent_type="general-purpose"  # NOT "codebase-researcher"
)
```

Full delegation payload, phases, early-exit behavior, and inline fallback are in `references/pipeline-steps.md` (*Step 1 — Research*).

If research determines the issue is **already fixed** (early-exit): close the issue with a comment (auto mode), record the run (`outcome: "skipped"`, `skipped_reason: "already_resolved"` — see *Run-Log*), and exit cleanly. This is a terminal path: write the run-log line, **unless `--no-run-log` was passed** (auto-pilot), in which case return the telemetry so the orchestrator writes the single line.

After research:
```
[1/5] Research     ✓ read {N} files, complexity: {level}
```

---

## Step 2 — Plan

Generate implementation options and select one. Spawn the `synthesizer` subagent (see `references/agents/synthesizer.md`). Use this Agent invocation:

```python
Agent(
  description="Plan for issue #N",
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

---

## Step 3 — Implement

Write code and tests based on the selected plan. Spawn the `implementer` subagent (see `references/agents/implementer.md`) with the plan, branch name, and naming conventions. Use this Agent invocation:

```python
Agent(
  description="Implement issue #N",
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

Automated review-fix loop: review → test → fix → repeat until clean or max cycles reached. Each cycle spawns a *fresh* `code-reviewer` subagent (see `references/agents/code-reviewer.md`) for unbiased review and delegates blocking fixes to the `fixer` subagent (see `references/agents/fixer.md`).

### Spawning the code reviewer

For each QA cycle, spawn a general-purpose agent with the code-reviewer prompt:

```python
Agent(
  description="Review cycle N",
  prompt=<code-reviewer.md prompt with {variables} replaced>,
  subagent_type="general-purpose"
)
```

**Do NOT use `subagent_type: "code-reviewer"`** — that is not a registered agent type. Always use `general-purpose` and pass the full code-reviewer prompt (see `references/agents/code-reviewer.md`).

When the reviewer or test/build run returns blocking issues, spawn or re-message the fixer subagent:

```python
Agent(
  description="Fix QA cycle N",
  prompt=<fixer.md prompt with {variables} replaced>,
  subagent_type="general-purpose"
)
```

Pass the issue context, branch/base branch, reviewer findings, failing test/build output, commit message `fix({scope}): address review feedback (#N)`, and `security_convention`: `references/docs/pre-commit-security.md` — the bundled pre-commit security scan the fixer MUST run before committing. The main agent collects the fixer's JSON result and decides whether to start another QA cycle; it should not apply fixes inline when the Agent tool is available.

### UI/UX review (auto-detected)

UI review is **auto-detected per issue** — no config flag enables it. Before the QA cycles, examine the issue body and the working diff to decide whether UI work is involved, then run only the review that *can* and *should* run:

- **Code UI review** is environment-independent — it reads the diff and changed files. It runs whenever UI work is detected, on any machine, **including a headless server with no display**. It is never gated on a GUI, a running app, or a browser.
- **Browser UI review** is optional and captures screenshots from a running app, so it only runs when there is a reachable running app *and* the user opted in. When it can't run, it **skips with a warning and the code UI review still runs** — fail-soft to code-only, never block.

#### Detection

1. Scan the issue title + body for UI keywords: `UI`, `frontend`, `component`, `style`, `css`, `html`, `design`, `layout`, `responsive`, `mobile`, `theme`, `dark mode`, `button`, `form`, `page`, `screen`, `visual`, `accessibility`, `a11y`, `icon`, `image`, `screenshot`, `dashboard`, `navigation`, `modal`, `dialog`, `card`, `table`, `chart`, `graph`.
2. Scan the working diff for UI files:
   ```bash
   git diff --name-only "origin/${base}"...HEAD | grep -E '\.(html|htm|css|scss|sass|less|styl|tsx|jsx|vue|svelte|astro)$|^(components|pages|views|layouts|app|src/app|screens|routes|templates)/|tailwind\.config\.|theme\.|tokens\.'
   ```
3. Classify: **`ui: detected`** (keywords OR UI files) → run the code UI review; **`ui: not detected`** → skip UI review entirely.

#### Code-based review

When `ui: detected`, spawn the `ui-reviewer` subagent in **code** mode (see `references/agents/ui-reviewer.md`):

```python
Agent(
  description="UI/UX code review (#N)",
  prompt=<ui-reviewer.md prompt with mode=code, {variables} replaced>,
  subagent_type="general-purpose"
)
```

Pass `{branch_name}`, `{base_branch}`, `{issue_context}` (the linked issue title/body + acceptance criteria), `{pr_context}` (empty — no PR exists yet at QA time), and `{diff_command}` (`git diff origin/${base}...HEAD`). Merge UI reviewer findings into the QA findings — both use the same `action: "fix" | "note"` semantics, so they flow into the fixer loop unchanged.

#### Browser-based review (optional, gated)

Browser review runs only when it both *can* and *should*. Check `resolve.ui_review.browser_review`:

- **`"false"`** — skip; code review already ran.
- **`"ask"`** — prompt interactive users; skip silently in auto mode.
- **`"true"`** — proceed to the capability check.

Then verify the runtime can actually capture screenshots — **all** must hold:
1. A target app is running and reachable (e.g. `curl -sf {app_url}` succeeds).
2. A headless browser is available (Playwright/Chromium installed). A headless server with no display is fine — headless Chromium needs no display, only the browser binary and a reachable app.
3. Capture is safe (not a production URL, no auth wall that would log real traffic).

If the gate or any check fails, print a warning and skip — **without** affecting the code UI review that already ran:
```
⚠ Browser review skipped — {reason}
  Code UI review still ran. Enable browser review with:
  resolve.ui_review.browser_review: "true"  (and ensure the app is running and reachable)
```

When all hold, capture screenshots at mobile/tablet/desktop viewports and spawn the UI reviewer in **browser** mode with the screenshot paths and `{app_url}`. UI `action: "fix"` findings join the QA fixable issues handled by the fixer.

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
Write a run-log line (`outcome: "failed"`, with `complexity`/`qa_cycles` if reached — see *Run-Log*; suppressed under `--no-run-log`, in which case return the telemetry instead), then stop (even in auto mode — a failing PR is worse than no PR).

### Update documentation

If the changes affect documented behavior:
- Update README if applicable
- Update inline documentation
- Update CHANGELOG if the project maintains one

### Push branch

The implementer ran the security scan per commit during Step 3, but before pushing you MUST run a final pre-push pass over the whole branch diff (`git diff --name-only "origin/${base}"...HEAD`) — it catches secrets that may have slipped in during QA fixes. Run the **Primary Pattern** in `references/docs/pre-commit-security.md` (authoritative; do not improvise a weaker check); export `IDD_AUTO_MODE=1` first in auto mode. It enforces, in order:

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

**PR title:** `{type}({scope}): {description} (#{issue_number})` (see `references/docs/naming-conventions.md`)

**PR body:** Fill the template in `references/report-templates.md` (section *PR Body Template*) — Summary, Approach, **Decision Record** (lifted from `.gitissue/analysis-<N>.json` if present, else synthesized from Steps 1-2 findings), Changes table, Test Results, **Acceptance Criteria Verification** table. The Decision Record and the verification table are the durable analysis signal that survives the squash-merge into git history; do not omit them. See *Analysis Artifacts and Durable Memory* in `references/docs/idd-methodology.md`.

### Project board sync

If `projects.sync_enabled` is true, update status to `status_map.done` (see `references/docs/github-projects-sync.md`).

### Record the run

After the PR is created, write the run-log line (`outcome: "left_open"`, with `pr`, `complexity`, `qa_cycles`, `duration_s`) per *Run-Log* below — unless `--no-run-log` was passed (then return the telemetry instead). This is the successful-delivery terminal path.

After delivery:
```
[5/5] Deliver      ✓ PR #{pr_number} created
```

---

## Run-Log

Append exactly **one** JSON line per run to `.gitissue/runs.jsonl` so resolve activity is observable across runs (QA cycle counts, complexity, failure modes, already-fixed detections). `/idd-doctor` summarizes this file. Schema, field list, and the `outcome` vocabulary are authoritative in `references/docs/config-schema.md` (*Run-log (`runs.jsonl`)*) — follow it; do not invent fields.

> **Suppression rule (applies to every append below).** When `--no-run-log` was passed (only `/auto-pilot` passes it), **do not append anywhere** — at any terminal path, instead of writing the line, **return** the same telemetry in the result payload (see *Suppression under `/auto-pilot`*) so the orchestrator writes the single line. Every "write a run-log line" instruction in the steps above (closed issue, PR-exists, already-fixed early-exit, failed pipeline, successful deliver) and below is governed by this rule — read each as "write the line **unless `--no-run-log`**, in which case return the telemetry." This is what guarantees exactly one line per processed issue under auto-pilot.

### When it fires

Absent `--no-run-log`, the append fires on **every terminal path** of the pipeline — not only on a successful PR. Whichever way the run ends, write its line with whatever fields are known at that point:

| Terminal path | `outcome` | Notable fields |
|---------------|-----------|----------------|
| Step 5 delivered a PR | `left_open` | `pr`, `complexity`, `qa_cycles`, `duration_s` |
| Already-fixed early-exit (Step 1) | `skipped` | `skipped_reason: "already_resolved"` |
| Preflight stop — closed issue, or a PR already targets #N | `skipped` | `skipped_reason: "already_resolved"` (PR exists) or `"closed"` |
| Preflight guard declined (interactive only — user answers *no* at a Step 0c assignment/blocking-label prompt) | `skipped` | `skipped_reason: "assigned_other"` or `"blocked_label"` |
| Pipeline aborted — final tests failed, or any step failed and stopped | `failed` | `complexity`/`qa_cycles` if reached |

(The interactive-guard-declined row never occurs in auto mode — Step 0c does not stop there — and `--no-run-log` is auto-pilot-only, so that path always logs.)

The resolver never emits `merged`, `partial_followup`, or `blocked_by_dependency` — it does not merge. A successful resolve records `left_open` (the PR is created and left for review/merge). The merge-stage outcomes are written by `/auto-pilot`.

### Start timestamp (for `duration_s`)

Environment variables do **not** persist across separate Bash tool calls. To measure `duration_s`, persist the start time once during Preflight (Step 0) and read it back when writing the line:

```bash
mkdir -p .gitissue
date -u +%s > .gitissue/.run-start-{N}    # Step 0 — record start (epoch seconds)
```

When writing the run line, compute the delta and remove the marker:

```bash
start=$(cat .gitissue/.run-start-{N} 2>/dev/null || echo "")
now=$(date -u +%s)
dur=null; [ -n "$start" ] && dur=$((now - start))   # literal `null` when unknown (jq --argjson rejects "")
rm -f .gitissue/.run-start-{N}
```

The marker file is scratch (dot-prefixed), is removed when the line is written, and is never staged. If it is missing (e.g. an early preflight stop before Step 0 recorded it), `dur` stays `null` and `duration_s` is omitted from the line.

### Writing the line

Build the object from known values and append it. Use `date -u +%Y-%m-%dT%H:%M:%SZ` for `ts`. Append only — never rewrite existing lines:

```bash
mkdir -p .gitissue
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# --argjson values MUST be valid JSON literals — a number or the literal `null`,
# never an empty string ("" makes jq error). --arg values are plain strings.
# Use `null` for any unknown numeric field (qa, pr, dur); empty "" for an absent reason.
qa=${qa:-null}; pr=${pr:-null}; dur=${dur:-null}    # default unknowns to the JSON literal null
jq -cn \
  --arg ts "$ts" --argjson issue {N} --arg mode "resolve" \
  --arg outcome "{outcome}" --arg complexity "{complexity}" \
  --argjson qa "$qa" --argjson pr "$pr" \
  --argjson dur "$dur" --arg reason "{skipped_reason_or_empty}" \
  '{ts:$ts, issue:$issue, mode:$mode, outcome:$outcome}
   + (if $complexity=="" then {} else {complexity:$complexity} end)
   + (if $qa==null then {} else {qa_cycles:$qa} end)
   + (if $pr==null then {} else {pr:$pr} end)
   + (if $dur==null then {} else {duration_s:$dur} end)
   + (if $reason=="" then {} else {skipped_reason:$reason} end)' \
  >> .gitissue/runs.jsonl
```

If `jq` is unavailable, fall back to appending a hand-built single-line JSON object with the same fields (escape any string values).

### Do not stage it

Append to the working-tree file but **never** `git add` `.gitissue/runs.jsonl` (and never the `.run-start-*` marker). The implementer already stages only explicit paths (never `git add .`/`-A`); the run line is written *after* PR creation, so it cannot be part of the resolution commits regardless. This keeps the run-log out of the PR diff. Absence or deletion of the file is non-fatal — the next run recreates it.

### Suppression under `/auto-pilot`

When invoked with `--no-run-log` (passed by `/auto-pilot`), **skip the append entirely**. Instead, **return** the telemetry in the result payload so the orchestrator writes the single enriched line:

```json
{ "outcome": "...", "pr": <number|null>, "complexity": "...", "qa_cycles": <number>, "duration_s": <number|null>, "skipped_reason": "<string|null>" }
```

This guarantees exactly one line per processed issue under auto-pilot. Standalone `/issue-resolver` (with or without `--auto`, run directly) does not receive `--no-run-log` and writes its own line.

---

## Final Report

After the pipeline completes, print a structured step-by-step summary so the user can scan the whole resolution at a glance. Use the templates in `references/report-templates.md`:

- *Final Report — Successful Resolution* — every step passed
- *Final Report — Resolution With Warnings* — QA left residual issues or another step warned
- *Final Report — Already Resolved* — Step 0 or Step 1 detected the issue was already closed

---

## Auto-Pilot Mode

When invoked with `--auto` (or by `/auto-pilot`), the entire pipeline runs without user interaction:

- **Environment:** Export `IDD_AUTO_MODE=1` before any shell snippet that consults it (the pre-commit security scan reads this to switch from prompt-on-warning to log-and-continue; see `references/docs/pre-commit-security.md`).
- **Workspace:** Always the **in-place** path. Skip Step 0e entirely — no worktree prompt, no `git worktree add` on the default resolution path. Run mandatory Repo Sync, then *0f — Create branch* in the current working tree. Isolated worktrees remain **interactive-only** (Step 0e).
- **Preflight:** Skip assignment guard. Log blocking labels as warnings, don't stop.
- **Research:** If already resolved, close the issue with a comment and exit cleanly.
- **Plan:** Auto-select the recommended option (best balance of quality/effort).
- **Implement:** Continue past max commits guard with a warning.
- **QA:** Run full cycle autonomously. If stagnation detected, continue to deliver with known issues.
- **Deliver:** Create PR. Do NOT merge — merging is handled by `/auto-pilot` or `/issue-pr-review`.
- **Run-Log:** `--auto` on its own still writes a `runs.jsonl` line. Only the separate `--no-run-log` flag — passed by the `/auto-pilot` orchestrator, not implied by `--auto` — suppresses the resolver's own append and makes it return telemetry instead (see *Run-Log*). A run started as `/issue-resolver N --auto` directly (not under auto-pilot) logs normally.

No `[y/N]` prompts, no `Choose:` prompts, no `Continue?` prompts. Every decision point has a defined auto behavior.

---

## Expected Output

A successful resolve prints the 6-step tracker and ends with the PR URL — see the *Expected Inline Pipeline Output* example in `references/report-templates.md`.

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

- **`references/agents/codebase-researcher.md`** — Research subagent (Step 1)
- **`references/agents/synthesizer.md`** — Plan subagent (Step 2)
- **`references/agents/implementer.md`** — Implement subagent (Step 3)
- **`references/agents/code-reviewer.md`** — QA review subagent (Step 4)
- **`references/agents/ui-reviewer.md`** — UI/UX review subagent (Step 4, auto-detected)
- **`references/agents/fixer.md`** — QA fix subagent (Step 4)
- **`references/pipeline-steps.md`** — Full delegation payloads, phases, and inline fallbacks for Steps 1–4
- **`references/report-templates.md`** — PR body template, final report templates, and expected inline output
- **`references/bug-verification.md`** — Red-capable reproduction checkpoint for bug issues (Step 3, before the fix)
- **`references/error-messages.md`** — Complete error catalog
- **`references/docs/naming-conventions.md`** — Branch, commit, PR naming conventions
- **`references/docs/github-projects-sync.md`** — GitHub Projects status sync
- **`DESIGN.md`** — Terminal output style guide
- **`references/docs/config-schema.md`** — Configuration schema
