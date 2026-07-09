---
name: issue-resolver
description: "Create an atomic PR closing a GitHub issue end-to-end via a 6-step pipeline. Use to resolve, fix, or implement issue #N. Don't use for analysis without fixing (/issue-analysis), reviewing a PR (/issue-pr-review), or bulk backlog work (/auto-pilot)."
license: MIT
compatibility: "Requires git and GitHub CLI (gh) with authentication and push access. Self-contained — uses shared agents from shared/agents/."
effort: max
metadata:
  version: 0.16.1
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

The `--no-run-log` flag is **orthogonal to `--auto`** and is passed **only by `/auto-pilot`** — see *Run-log entry* → *Suppression rule* for the full single-writer rationale.

## Prerequisites

Verify the environment before any operation; on failure, print the exact error from `references/error-messages.md` and stop.

Git repository (`git rev-parse --git-dir`), `gh` installed (`which gh`), authenticated (`gh auth status`), GitHub remote exists (`git remote -v`).

## Repo Sync Before Edits (mandatory)

Applies to the **in-place path** only (auto mode, or interactive when the user
declines the Step 0e worktree offer) — the worktree path starts current already.
Sync with remote using the stash-first pattern (full convention and recovery in
`references/docs/sync-conventions.md`):

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

Defaults (full field reference in `references/docs/config-schema.md`):
- `issue.auto_normalize: true`
- `resolve.approval_gate: auto` (ignored in auto mode — always auto)
- `resolve.branch_prefix: "auto"`
- `resolve.auto_test: true`
- `resolve.test_timeout: 300`
- `resolve.max_commits: 10`
- `resolve.qa_max_cycles: 5`
- `resolve.ui_review.browser_review: "ask"` — gates only the optional browser/screenshot review; the code-level UI review (*Step 4 — UI/UX review*) is auto-detected and always runs.

---

## Subagent Architecture

The resolve pipeline delegates heavy work to subagents (`shared/agents/`) to keep the main agent's **context window** clean and **token budget** predictable. Main agent stays in Step 0, Step 4 (orchestrates review-fix), and Step 5 (deliver); Steps 1-3 each spawn one subagent. Full diagram in `references/pipeline-steps.md` (*Subagent Architecture Diagram*).

Each subagent's prompt file is listed under *Additional Resources* below. Every
agent opens with a role header and a compact I/O contract; the conventions they share (spawn note, tool posture, injection boundary,
confidence scale, `gh --json`, autonomous operation) live once in
`references/docs/shared-agent-conventions.md`.

### Spawning a subagent (canonical pattern)

Every step below spawns with the same shape — only role, description, and prompt file change. `subagent_type` is **always** `"general-purpose"` (never the agent's own name — none are registered agent types):

```python
Agent(
  description="{role} — {action} issue #N",
  prompt=<{agent-file}.md prompt with {variables} replaced>,
  subagent_type="general-purpose"  # NEVER the agent's own name (e.g. NOT "code-reviewer")
)
```

### Orchestrating the agents (model/effort, monitoring, audit)

As the orchestrator, for each spawned step:

1. **Name the role** in the spawn `description` (e.g. `"researcher — research issue #N"`).
2. **Size the model/effort** per `references/docs/agent-model-effort.md` from the most-recent
   complexity signal, falling back to the agent's default tier — advisory, never blocks.
3. **Monitor before advancing** — verify the agent returned its contract's required
   shape (researcher: `status`+`complexity`; synthesizer: one `recommended` option;
   implementer: commits+tests+repro for bugs; reviewer/fixer: `result`+counts). A
   missing/blocking return is the signal to stop (interactive) or follow auto behavior.
4. **Audit** — record the per-step signal the run log already folds in (`complexity`,
   `qa_cycles`, `outcome`, `duration_s`) plus the `[N/5]` tracker line.

### Environment check

If the Agent tool is available, use subagents as described above; if not (e.g. Claude.ai), execute each step inline via the fallback instructions.

### Bundled dependency precheck

Verify this skill's bundled subagent prompts and reference files are present. Before execution, verify **every** path in the list below exists relative to the skill's directory (the dirname of this SKILL.md). This list is the authoritative guard — keep it complete and independent of the *Additional Resources* navigation index, which exists for human navigation and may list files with source-relative group prefixes. If any path is missing, stop immediately and print the error below; do not continue with an inline or guessed subagent prompt:

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
references/docs/config-schema.md
references/docs/agent-model-effort.md
references/docs/shared-agent-conventions.md
```

```
✗ Missing bundled dependency: {missing_file}

  To fix:  asm install https://github.com/luongnv89/idd --skill issue-resolver
           (or reinstall the full distribution)

  Then restart the agent session and re-run /issue-resolver.
```

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

Each step prints a new line on start (`●`), updating to `✓`/`✗` on success/failure. Static sequential output — no animation.

---

## Step 0 — Preflight

Check whether this issue should be worked on.

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

**Interactive:** warn and ask if assigned to someone else or `wontfix`/`blocked`/`do-not-merge` labels exist.

**Auto:** skip the assignment guard; log blocking labels, don't stop.

### 0d — Auto-normalize

If `issue.auto_normalize` is true and not already normalized (no `<!-- gitissue:normalized v1 -->` marker):

1. **Security label check (SPEC §1.4)** — before any rewrite, scan issue labels for `security`, `CVE`, or `vulnerability` (case-insensitive). If any match:
   - **Auto mode (`--auto` / `IDD_AUTO_MODE=1`):** print the skip warning below and continue preflight **without** rewriting the issue body.
   - **Interactive mode:** print the warning and ask for explicit operator confirmation. Default is **no** — do not rewrite unless the operator clearly confirms (e.g. `y` / `yes`). If declined, continue without normalization.

   ```
   ⚠ Issue #N has a security label ({label}). Skipping auto-normalization.
     Rewriting security-sensitive issues requires explicit operator confirmation (SPEC §1.4).

     To normalize first: /issue-creator N   (or /issue-creator N --force after review)
   ```

   Use the first matching label name for `{label}` in the warning line.

2. **Normalize inline** — when no security label blocks (or interactive operator confirmed): classify issue type, generate normalized body, add marker, post a backup comment with the original body, update the issue via `gh issue edit`, then re-fetch. This is the same structure-only flow as `/issue-creator` Normalize mode (`references/modes.md` in the issue-creator skill); the resolver does **not** invoke `/issue-creator` as a subprocess — it performs Step 0d inline. If normalization fails, warn and continue with the original body (see `references/error-messages.md`).

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

Create working branch from `resolve.branch_prefix` (see `references/docs/config-schema.md` and `references/docs/naming-conventions.md`): when `"auto"`, use `{type}/{N}-{short-description}`; when a custom string (e.g. `issue-`), use `{prefix}{N}-{short-description}`.

**If branch already exists:**
- Interactive mode: ask `continue` or `fresh`
- Auto mode: `continue` (checkout existing branch)

After preflight:
```
[0/5] Preflight    ✓ issue #N open, branch: {branch_name}{workspace_note}
```

`{workspace_note}` is ` (worktree)` in a worktree, empty otherwise.

---

## Step 1 — Research

Deeply understand the issue, affected codebase, and possible solutions; also verifies the issue hasn't already been fixed (early-exit path closes it in auto mode). Spawn the researcher (`references/agents/codebase-researcher.md`) with the canonical pattern — full delegation payload, phases, early-exit behavior, and inline fallback are in `references/pipeline-steps.md` (*Step 1 — Research*).

After research:
```
[1/5] Research     ✓ read {N} files, complexity: {level}
```

---

## Step 2 — Plan

Generate implementation options and select one. Spawn the synthesizer (`references/agents/synthesizer.md`) with the canonical pattern.

It returns 3 options — minimal / balanced / comprehensive — with the balanced option usually recommended.

Selection behavior (interactive auto, interactive comment-and-wait, auto-pilot) and inline fallback are in `references/pipeline-steps.md` (*Step 2 — Plan*).

After plan selection:
```
[2/5] Plan         ✓ approach: {selected option name}
```

### Design-confirm checkpoint (high-complexity, interactive only)

High-risk work earns **exactly one** extra agreement point before code is written —
no new phase, artifact, or config key. Fires only when **both** hold: synthesizer
reports `overall_complexity: L`/`XL` or `overall_risk: High` (trivial/low/medium
skip it), **and** interactive mode (`--auto`/`IDD_AUTO_MODE=1` never pauses).

Accept (default) → Step 3 unchanged. Decline → stop before implementing, suggest
re-running or picking a different option. Record the decision in the PR Decision
Record. Full procedure in `references/pipeline-steps.md`
(*Step 2 — Plan → Design-confirm checkpoint*).

---

## Step 3 — Implement

### Propose relevant skills (interactive only)

Before spawning the implementer, optionally augment it with external skills from
the index in `references/skill-index.md` (`https://github.com/luongnv89/skills`).
This sub-step emits a `◆`/`○` block, no own `[N/5]` tracker line.

Detect installed skills (`~/.claude/skills/<name>`) against the catalog, propose the
relevant subset, let the user accept all/some/none into `selected_skills` — the
implementer always falls back to internal agents, so selecting none is unchanged
behavior. Full procedure in `references/pipeline-steps.md` (*Step 3 — Propose relevant skills*).

Write code and tests based on the selected plan. Spawn the implementer (`references/agents/implementer.md`) with the canonical pattern, passing the plan, branch name, naming conventions, and `selected_skills`.

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

For each QA cycle, spawn a **fresh** reviewer (`references/agents/code-reviewer.md`) with the canonical pattern — fresh each cycle for unbiased review.

When the reviewer or test/build run returns blocking issues, spawn or re-message the fixer (`references/agents/fixer.md`) the same way. Pass issue context, branch/base branch, reviewer findings, failing test/build output, commit message `fix({scope}): address review feedback (#N)`, and the pre-commit security convention it MUST run before committing (`references/docs/pre-commit-security.md`). Collect the fixer's JSON result and decide whether to start another cycle — never apply fixes inline when the Agent tool is available.

### UI/UX review (auto-detected)

UI review is **auto-detected per issue** — no config flag enables it. Scan the issue body/diff for UI work before the QA cycles, then run only what *can* and *should* run:

- **Code UI review** — reads the diff, environment-independent, runs anywhere including headless, never gated on a GUI/browser.
- **Browser UI review** — optional screenshots from a running app; runs only when reachable *and* opted in, else **skips with a warning, code UI review still runs** — fail-soft.

Detection rules, `ui-reviewer` spawns, the `resolve.ui_review.browser_review` gate, and skip/success messages are in `references/pipeline-steps.md` (*Step 4 — UI/UX review*). Cycle mechanics and loop controls (`resolve.qa_max_cycles`, exit-on-clean, exit-on-stagnation) are in the same file (*Step 4 — QA*).

---

## Step 5 — Deliver

Push, create PR, and report.

### Verify all tests pass

When `resolve.auto_test` is true (default), run the full test suite one final time to confirm everything is clean after QA fixes. When false, skip this suite (QA Step 4 may still have run tests during the loop).

If tests fail at this point:
```
✗ Final test run failed — PR not created
  {failure details}
```
Stop (even in auto mode — a failing PR is worse than no PR).

### Update documentation

If the changes affect documented behavior, update README, inline docs, and CHANGELOG as applicable.

### Push branch

Before pushing, run a final pre-push pass over the whole branch diff (`git diff --name-only "origin/${base}"...HEAD`) — catches secrets that slipped in during QA fixes. Run the **Primary Pattern** in `references/docs/pre-commit-security.md` (authoritative — do not improvise a weaker check); export `IDD_AUTO_MODE=1` first in auto mode.

Only after the scan passes (or warnings are accepted):

```bash
git push -u origin {branch_name}
```

### Create PR

```bash
gh pr create --title "{pr_title}" --body "{pr_body}"
```

**PR title:** `{type}({scope}): {description} (#{issue_number})` (see `references/docs/naming-conventions.md`)

**PR body:** Fill the template in `references/report-templates.md` (*PR Body Template*) — Summary, Approach, **Decision Record** (from `.gitissue/analysis-<N>.json` if present, else synthesized), Changes table, Test Results, **Acceptance Criteria Verification** table. The last two are the durable analysis signal surviving squash-merge; never omit them (see `references/docs/idd-methodology.md`).

### Project board sync

If `projects.sync_enabled` is true, update status to `status_map.done` (see `references/docs/github-projects-sync.md`).

After delivery:
```
[5/5] Deliver      ✓ PR #{pr_number} created
```

### Run-log entry (monitoring)

At **every terminal outcome** — delivered PR (`success`), early exit because
already fixed (`already_resolved`), or a failed step (`failed`) — append exactly
**one JSON line** to `.gitissue/runs.jsonl`, **unless invoked with `--no-run-log`**
(see *Suppression rule*), in which case append **nothing** and return the
telemetry to the caller instead. Build the object from values already known
(`ts`, `issue`, `mode`, `skill`, `outcome`, `pr`, plus optional `complexity`,
`qa_cycles`, `duration_s`, `skipped_reason`) per the schema in
`references/docs/config-schema.md` (*`.gitissue/runs.jsonl` — run log*). Collapse researcher
complexity to the 3-value run-log scale before writing (`trivial`/`low`→`low`,
`medium`→`medium`, `high`/`complex`→`high`).

> **Suppression rule (single writer under `/auto-pilot`).** `--no-run-log` is
> passed only by `/auto-pilot`, which runs this resolver as a subagent and writes
> the **single** run-log line per issue itself — appending here too would
> double-write and skew `/idd-doctor`'s metrics. Instead **return** the telemetry
> (`outcome`, `qa_cycles`, `complexity`, `duration_s`) in the subagent result so
> the orchestrator folds it into its own line. Independent of `--auto`: a
> standalone `/issue-resolver <N> --auto` is *not* suppressed and still writes.

```bash
# Only when --no-run-log is NOT set:
mkdir -p .gitissue
printf '%s\n' "$run_json" >> .gitissue/runs.jsonl
```

Best-effort and non-fatal — a failed write never blocks the reported run result.
Only append; never rewrite or reorder existing lines.

---

## Closing Summary

After the pipeline completes, print **one** closing block that repeats **nothing**
the live `[N/5]` tracker already showed (per-step pass/fail, files read, complexity,
option, files changed, test counts, QA cycles — repeating any is the duplication
issue #165 removed). It carries only what the tracker never printed: the outcome
line, the `risk_rating`, and the single PR reference (number, title, URL,
`Closes #N`). Use the matching variant in `references/report-templates.md`
(*Closing Summary*):

*Successful Resolution* (every step passed), *Resolution With Warnings* (QA left
residual issues or another step warned), or *Already Resolved* (Step 0/1 found the
issue already closed — no PR reference). Per-step status appears only in the
tracker, the full PR reference only in the closing block, never both — see the
*Expected Inline Pipeline Output* example in `references/report-templates.md`.

---

## Auto-Pilot Mode

When invoked with `--auto` (or by `/auto-pilot`), the entire pipeline runs without user interaction:

- **Environment:** Export `IDD_AUTO_MODE=1` before any shell snippet that consults it (`references/docs/pre-commit-security.md`).
- **Workspace:** Always in-place. Skip Step 0e entirely — no `git worktree add` on the default resolution path. Run mandatory Repo Sync, then *0f — Create branch*.
- **Preflight:** Skip assignment guard. Log blocking labels as warnings, don't stop.
- **Research:** If already resolved, close the issue with a comment and exit cleanly.
- **Plan:** Auto-select the recommended option; design-confirm never appears — log the selection and proceed.
- **Implement:** Continue past max commits guard with a warning; propose-relevant-skills never prompts (internal agents only).
- **QA:** Run full cycle autonomously; continue to deliver with known issues if stagnation is detected.
- **Deliver:** Create PR. Do NOT merge — merging is `/auto-pilot` or `/issue-pr-review`'s job.

No `[y/N]` prompts, no `Choose:` prompts, no `Continue?` prompts. Every decision point has a defined auto behavior.

---

## Edge Cases

No acceptance criteria, empty issue body, large issues (20+ files), test failure/timeout,
and branch-already-exists are all handled — full behavior for each is in
`references/pipeline-steps.md` (*Edge Cases*).

---

## Platform Driver

All tracker access follows the GitHub driver — `--json` with explicit field selection, never parsed text output. The full operation catalog and driver rules live in references/docs/platform-github.md.

## Output Conventions

Terminal output follows the DESIGN.md contract — symbols `● ✓ ✗ ◆ ⚡ ⚠ ○`, two-space indent, `┄` separators, URLs on their own line, ≤80 chars, one blank line between sections, static sequential output (no animation), plus the `[N/5]` pipeline step counter. Errors use the rich format from `references/error-messages.md`: `✗ what failed`, then `To fix:  <command>`, then a docs link when applicable.

## Additional Resources

Authoritative file list for the *Bundled dependency precheck* above:

**Agents** (`shared/agents/`): `codebase-researcher.md` (Step 1) · `synthesizer.md` (Step 2) · `implementer.md` (Step 3) · `code-reviewer.md` (Step 4) · `ui-reviewer.md` (Step 4) · `fixer.md` (Step 4)

**References** (`references/`): `pipeline-steps.md` (payloads/phases/fallbacks, Steps 1–4) · `report-templates.md` (PR body, closing summary, expected output) · `bug-verification.md` (reproduction checkpoint, Step 3) · `skill-index.md` (external-skill catalog, Step 3) · `error-messages.md` (error catalog)

**Docs** (`docs/`): `sync-conventions.md` · `naming-conventions.md` · `pre-commit-security.md` · `idd-methodology.md` · `github-projects-sync.md` · `config-schema.md` · `agent-model-effort.md` · `shared-agent-conventions.md` · `platform-github.md`

**`DESIGN.md`** — terminal output style guide.
