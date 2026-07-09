# Pipeline Step Details

Detailed procedures for each subagent delegation in the resolve pipeline. SKILL.md keeps the contract short; this file holds the full input/output spec and inline fallback instructions.

## Subagent Architecture Diagram

Full shape of the orchestrator → subagent delegation described in SKILL.md
(*Subagent Architecture*):

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

## Step 0e — Workspace (interactive only)

Full procedure for the worktree offer described in SKILL.md *Step 0e — Workspace*. **Interactive mode only** — in auto mode (`--auto` / `IDD_AUTO_MODE=1`) this entire step is skipped and the pipeline uses the in-place path (Repo Sync + *0f — Create branch*), byte-for-byte as before. The worktree prompt never appears in auto mode (acceptance criterion 4).

### Why a worktree

`git worktree` checks out a branch into a *separate directory* that shares the same `.git` object store. The user's current working tree — including any uncommitted changes — is never modified. Branch creation, implementation, and the QA test runs all happen in the isolated directory.

### The offer

Before Step 0e or 0f selects a workspace, derive `branch_name` from
`resolve.branch_prefix` exactly once: when it is `"auto"`, use
`{type}/{N}-{short-description}`; otherwise use the configured prefix verbatim
as `{configured-prefix}{N}-{short-description}`. Do not re-derive or replace
this value on either path.

Present the prompt from SKILL.md (*Step 0e — Workspace*). It must state, before the user answers:

- the derived **branch** name (`{branch_name}`),
- the **worktree path** (the naming convention below), and
- what **setup** will be copied/run (gitignored local config + the project's detected install/bootstrap).

Default is **accept** (`[Y/n]`). This satisfies acceptance criterion 5 (the proposal states what is copied and the workspace/branch naming).

### Naming convention

- **Branch:** `{branch_name}` — the same prefix-derived name used by the in-place path (`docs/naming-conventions.md`).
- **Worktree directory:** a *sibling* of the repo root, derived from the branch with `/` → `-` so it is a single path segment:

  ```
  ../{repo}-worktrees/{branch_name with / → -}
  ```

  Example: repo `idd`, branch `feat/123-resolver-worktree-prompt` → `../idd-worktrees/feat-123-resolver-worktree-prompt`.

  A sibling directory (outside the repo) keeps the worktree out of the repo's own status and ignore rules. If you instead place it *inside* the repo, the path **must** already be covered by `.gitignore` — otherwise the worktree's own files surface as untracked changes in the parent. Prefer the sibling location.

### Create the worktree

`git worktree add -b` creates the branch **and** the workspace in one command, off a freshly fetched base — so this replaces both the mandatory Repo Sync and *0f — Create branch* on the accepted path. No `git pull --rebase` / stash dance is needed (the new branch starts at `origin/<base>` directly).

```bash
repo_root="$(git rev-parse --show-toplevel)"        # absolute path to the repo
base="$(git rev-parse --abbrev-ref HEAD)"           # base branch to fork from
repo="$(basename "$repo_root")"
# branch_name was derived once before this step: "auto" →
# {type}/{N}-{short-description}; custom resolve.branch_prefix →
# {configured-prefix}{N}-{short-description}.
# Absolute worktree path (sibling of the repo) — independent of the current
# directory, so later steps that `cd` into it stay correct.
wt_dir="$(dirname "$repo_root")/${repo}-worktrees/$(printf '%s' "$branch_name" | tr '/' '-')"

git fetch origin
created_branch_in_step_0e=1
git worktree add -b "$branch_name" "$wt_dir" "origin/${base}"
```

Keep `repo_root` and `wt_dir` available for the setup step below (both are
absolute, so the copy works regardless of the current directory).

**If the branch already exists** (`git worktree add -b` fails): in interactive mode ask `continue` (set `created_branch_in_step_0e=0`, then add a worktree for the existing branch with `git worktree add "$wt_dir" "$branch_name"`) or `fresh` (delete the branch, keep `created_branch_in_step_0e=1`, then retry). See `references/error-messages.md` → *Branch already exists (worktree path — Step 0e)*.

**If worktree creation fails for any other reason** (e.g. path exists, disk, locked worktree): warn, print the message from `references/error-messages.md` → *Worktree creation failed*, and **fall back to the in-place path** (Repo Sync + *0f — Create branch*). Never abort the resolution just because the worktree could not be made.

After creation, **change into the worktree** so every subsequent step (research, implement, QA, deliver) operates there:

```bash
cd "$wt_dir"
```

### Prepare the workspace (generic — discovered, not hardcoded)

The goal: the worktree can build and run immediately, without the user reconfiguring it. A fresh worktree shares git history but **not** gitignored files (local config) or installed dependencies. Reconstruct them **by detecting what this repo uses** — do not assume any specific stack:

1. **Copy gitignored local config** from the original working tree into the worktree. These are the files git does not track but the app needs at runtime — typically environment files. Copy what exists; skip silently what does not:

   ```bash
   # Absolute paths from the creation block — works from any directory, so this
   # does not depend on a prior `cd` or on shell state carrying across steps.
   for f in .env .env.local .env.development .env.test; do
     [ -f "$repo_root/$f" ] && cp "$repo_root/$f" "$wt_dir/$f"
   done
   ```

   If the repo keeps other gitignored local config (service-account JSON, local certs, a `config.local.*`), copy those too. Use the repo's `.gitignore` as the guide for what is local-only. **Never copy secrets anywhere outside the worktree, and never commit them** — the pre-commit security scan (`docs/pre-commit-security.md`) still blocks secret-bearing files on push.

2. **Install dependencies** using the project's **detected** package manager — the same detection the researcher/implementer rely on. Examples (pick the one matching the repo, do not run all): `npm ci` / `pnpm install` / `yarn` (Node), `pip install -r requirements.txt` or `uv sync` inside the project venv (Python), `bundle install` (Ruby), `go mod download` (Go), `cargo fetch` (Rust). If the repo has no dependency manifest, skip this step.

3. **Run project bootstrap** if the repo defines one — e.g. a `Makefile` `setup`/`bootstrap` target, a `scripts/setup.sh`, a documented "getting started" command, or generated files (`prisma generate`, etc.). Skip if none exists.

Report what was prepared, e.g. `✓ Worktree ready — copied .env, ran npm ci`. Keep it factual: list only what actually ran.

**If setup fails after the worktree was created** (copy error, dependency install failure, bootstrap failure): warn, print the message from `references/error-messages.md` → *Worktree setup failed*, then clean up the partial workspace before falling back to the in-place path. This avoids stranding the resolver on a branch that is already checked out in the failed worktree.

```bash
cd "$repo_root"
cleanup_ok=1
git worktree remove "$wt_dir" --force 2>/dev/null || cleanup_ok=0
if [ "$cleanup_ok" -eq 1 ] && git worktree list --porcelain | grep -q "worktree $wt_dir$"; then
  cleanup_ok=0
fi
if [ "$cleanup_ok" -eq 0 ]; then
  git worktree prune 2>/dev/null || true
  if git worktree list --porcelain | grep -q "worktree $wt_dir$"; then
    cleanup_ok=0
  else
    cleanup_ok=1
  fi
fi
if [ "$cleanup_ok" -eq 0 ]; then
  # Do not fall back in-place while the branch is still checked out in the failed worktree.
  stop with *Worktree setup failed* recovery commands and exit the resolution attempt.
fi
# Delete the branch only if this Step 0e created it with `git worktree add -b`.
# If the user chose to continue an existing branch, keep the branch and let 0f's
# existing branch flow handle it.
if [ "${created_branch_in_step_0e:-0}" = "1" ]; then
  git branch -D "$branch_name" 2>/dev/null || true
fi
```

After **verified** cleanup (`cleanup_ok=1`), run the mandatory Repo Sync and *0f — Create branch* in the original working tree. If cleanup cannot remove the worktree entry, **stop** — print `references/error-messages.md` → *Worktree setup failed* and do not attempt the in-place path while the same branch may still be checked out in `{wt_dir}`.

### Cleanup (after delivery, interactive only)

The worktree is intentionally left in place after the PR is created so the user can inspect it. Tell them how to remove it when done:

```
○ Worktree left at {wt_dir} for inspection.
  Remove with:  git worktree remove {wt_dir}
```

Do not auto-remove it — the user may still want the local artifacts.

## Step 1 — Research (codebase-researcher subagent)

### Delegation payload

```json
{
  "issue": { <issue data from Step 0> },
  "config": {
    "max_files": 30,
    "trace_depth": 3,
    "scan_timeout": 120,
    "output_format": "json"
  },
  "repo_root": "<absolute path>"
}
```

### What the researcher does

1. **Verify not already resolved** — check git history for closing commits and scan the codebase for evidence the bug is fixed.
2. **Scan codebase** — extract targets, grep/glob, read files, trace dependencies.
3. **Assess complexity** — trivial / low / medium / high / complex.
4. **Research solutions** (for high/complex) — algorithms, optimizations, design patterns, web search if needed.
5. **Analyze git history** — prior attempts, regressions, domain experts (via `git blame`).
6. **Cross-reference issues** — duplicates, blockers, related work.

### Early exit: already resolved

If the researcher returns `already_resolved: true` or `pr_in_progress: true`:

```
✓ Issue #N appears to already be resolved
  {resolution_details}

  Recommend closing the issue.
```

- Auto mode: close the issue with a comment and move on.
- Interactive mode: inform the user and stop.

### Inline fallback

If no Agent tool, execute research inline following the same phases described in `shared/agents/codebase-researcher.md`.

### GitHub Projects status transition

If `projects.sync_enabled` is true, set the issue status to `status_map.in_progress` (see `docs/github-projects-sync.md`).

## Step 2 — Plan (synthesizer subagent)

### Delegation payload

- Issue data
- Research findings (JSON from Step 1)
- Mode: `"auto"` if auto-pilot, `"interactive"` otherwise

### Options returned

The synthesizer returns 3 options differing in scope:

1. **Minimal fix** — smallest change
2. **Balanced approach** — proper fix, reasonable scope (usually recommended)
3. **Comprehensive refactor** — addresses root cause and technical debt

### Plan selection

**Interactive, `resolve.approval_gate: auto`:** display the recommended option and proceed.

**Interactive, `resolve.approval_gate: comment-and-wait`:** present all 3:

```
◆ Implementation Options
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  [1] Minimal fix (S, Low risk)
      {summary}

  [2] Balanced refactor (M, Medium risk) ← recommended
      {summary}

  [3] Comprehensive overhaul (L, High risk)
      {summary}

Select option [1/2/3]:
```

**Auto mode:** auto-select the recommended option, no prompt.

### Design-confirm checkpoint (high-complexity, interactive only)

The minimum-viable risk gate from SKILL.md (*Step 2 — Plan → Design-confirm checkpoint*).
The pipeline shape is unchanged for most work; only high-complexity work in interactive
mode earns one extra confirmation before Step 3. It reuses the synthesizer's already-
returned recommended option — no new phase, artifact, or config key.

#### When it fires

Both conditions must hold:

1. **High-complexity tier.** Use the most-recent complexity signal the orchestrator
   already tracks (researcher `complexity` → synthesizer `overall_complexity`). Fire when
   the synthesizer reports `overall_complexity: L` or `XL`, **or** `overall_risk: High`
   (equivalently the researcher's `complexity` is `high` or `complex`). For
   `trivial`/`low`/`medium` (`overall_complexity` `XS`/`S`/`M` with non-`High` risk) the
   checkpoint is skipped and the pipeline runs the fast path exactly as before.
2. **Interactive mode.** In auto mode (`--auto` / `IDD_AUTO_MODE=1`) the checkpoint is
   never presented — see *Auto mode* below.

#### The prompt (interactive, high-complexity)

Present the **recommended** option the synthesizer already produced — do not re-plan or
generate anything new. Pull `name`, `summary`, `files_to_modify` (count), and
`risk_details` straight from that option:

```
◆ Design confirm — issue #N (high complexity)
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Proceed with Option {recommended.number} — {recommended.name}?
    Changes:        {recommended.summary} ({len(files_to_modify)} files)
    Residual risk:  {recommended.risk_details}
  Proceed? [Y/n]
```

- **Y / accept (default):** continue to Step 3 with the recommended option, unchanged.
- **n / decline:** stop the pipeline **before** implementing. Leave the branch in place
  (no commits were made yet) and tell the user how to resume:

  ```
  ○ Stopped at design-confirm — no changes made.
    Re-run /issue-resolver {N} to try again, or refine the issue scope first.
  ```

This is the **only** new interactive pause. It is **not suppressed by `approval_gate: auto`**:
even with `approval_gate: auto` (which otherwise proceeds silently with the recommended
option), the high-complexity checkpoint still asks — that is the entire point of the gate.
With `approval_gate: comment-and-wait` the user has **already made an explicit option choice
above**, so that selection itself served as the agreement point — the design-confirm prompt
is redundant and is skipped regardless of whether the chosen option was the recommended one.
The checkpoint therefore only ever fires on the auto-gate/default path, where the recommended
option is exactly what proceeds to Step 3 — which is why the prompt box above keys off
`recommended.*`.

#### Auto mode

Never pauses. Select the recommended option and emit a single log line so the decision is
auditable, then proceed to Step 3:

```
○ Design-confirm (auto): selected Option {N} — {name} (complexity: {overall_complexity}, risk: {overall_risk})
```

#### Recording the decision (durable memory)

Whether confirmed interactively or auto-selected, record the decision — selected option
and complexity — in the PR **Decision Record** via the conditional *Design-confirm* line
(`references/report-templates.md`). No separate artifact or config key is introduced; the
decision rides the existing durable-memory channel into git history on squash-merge.

### Inline fallback

If no Agent tool, analyze the research findings and generate the plan inline. The
design-confirm checkpoint still applies: in interactive mode, if the inline analysis lands
in the high-complexity tier, present the same `[Y/n]` prompt before implementing; in auto
mode, log the auto-selection and proceed.

## Step 3 — Implement (implementer subagent)

### Step 3 — Propose relevant skills (sub-step, before the implementer spawn)

Optionally augment the implementer with **optional external skills** from
`references/skill-index.md` (the skills published at
`https://github.com/luongnv89/skills`). This is a sub-step of Step 3 — it emits a
`◆`/`○` block and prints **no** `[N/5]` tracker line (the `[3/5]` Implement line is
unchanged), exactly like the design-confirm checkpoint. It runs for **every** issue
type in interactive mode (it is interactive-gated, not complexity-gated).

The skill index is treated as a **swappable candidate list**: the detection logic
reads the skill names + lifecycle phases from `references/skill-index.md` and never
hardcodes the source repo, so a future issue (#170) can swap the index contents to
a different source without changing this step's logic.

#### Detect — which catalogued skills are installed

Intersect the catalog with the skills available on this system. A skill named `X`
in the index is **available** when `~/.claude/skills/X/` exists and is invocable as
`/X`:

```bash
# For each `name` listed in references/skill-index.md:
[ -d "$HOME/.claude/skills/$name" ] && echo "available: $name"
```

Only **installed** skills are eligible to be proposed — a catalogued-but-not-installed
skill is never offered (and the implementer would have no way to invoke it).

#### Propose — the relevant subset for this task

From the installed skills, pick the subset relevant to the analyzed task. Use the
Step 1 research signal (issue type, complexity, affected files, UI detection) and the
index's lifecycle grouping so the proposal can span **implementation, verification,
testing, and documentation**. Present them grouped by lifecycle phase. The block
below is an **illustrative example** — the one-skill-per-phase layout is not a
required shape; propose however many (or few) installed skills actually fit the task:

```
◆ Optional skills for issue #N (example)
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  These installed skills from luongnv89/skills look relevant to this task.
  The implementer will use the ones you select; internal agents always remain
  the reliable fallback.

    [1] frontend-design     (implementation) — build the UI component
    [2] test-coverage       (testing)        — unit tests for new branches
    [3] code-review         (verification)   — extra review pass
    [4] docs-generator      (documentation)  — update affected docs

  Select skills to use — all, a subset (e.g. 1,2), or none [default: none]:
```

#### Accept all / some / none

- **All** → `selected_skills` = every proposed skill.
- **Subset** (e.g. `1,3`) → `selected_skills` = the chosen entries.
- **None** (default) → `selected_skills` = `[]`; the implementer uses internal
  agents only — today's behavior, byte-for-byte.

If no installed skills are relevant, skip the prompt entirely and proceed with
`selected_skills = []` (print one `○` line noting none were applicable). The chosen
set is passed to the implementer via the delegation payload below.

#### Auto mode

In auto mode (`--auto` / `IDD_AUTO_MODE=1`) the prompt **never appears**: set
`selected_skills = []` and proceed, so the implementer falls back to the internal
agents and today's behavior is unchanged. Optionally emit one audit line
(`○ Skill proposal (auto): skipped — using internal agents`). No new config key is
introduced — the sub-step is gated entirely on interactive mode plus what is
installed, following the design-confirm precedent.

### Delegation payload

- Issue data
- Research findings (from Step 1)
- Selected plan (the chosen option from Step 2)
- Branch name
- Naming conventions: `docs/naming-conventions.md`
- Max commits: `resolve.max_commits`
- `selected_skills` — the external skills chosen in the propose sub-step above (`[]` in auto mode or when the user declines); the implementer uses them where applicable and always falls back to the internal approach

### What the implementer writes

1. Implementation code with atomic commits
2. Unit tests for all new/changed functions
3. Integration tests (if framework exists)
4. E2e tests (if framework exists)
5. All committed following conventional commit format

### Bug verification checkpoint (bug issues only)

Before the implementer applies any fix, run the red-capable reproduction checkpoint —
see `references/bug-verification.md` for the full procedure. It applies **only** when the
issue `type` is `bug`; non-bug issues skip it entirely (acceptance criterion 5).

For a bug issue, the implementer (per `shared/agents/implementer.md` Task 1.5):

1. **Names the reproduction command/test** that surfaces the symptom (an existing focused
   test, a newly written failing test, or — when there is no test seam — the smallest
   manual runtime command).
2. **Confirms it is red for the stated reason** — the failure matches the symptom the
   issue describes, not an unrelated non-zero exit.
3. **After the fix, converts the repro into a regression test when a clean seam exists**;
   with no seam (or no test runner — e.g. a docs/skills repo), records the manual
   reproduction command as the evidence instead and adds no framework.

The implementer **returns** a `reproduction` block (command, red status, stated-reason
match, regression-test path or "manual — no seam"). The main agent folds it into the PR
body's Decision Record and Acceptance Criteria Verification table (durable home — see
`references/report-templates.md`); if a fresh `.gitissue/analysis-<N>.json` exists, the
same data also lives in its `decision_record.reproduction` field (optional cache mirror,
written by `/issue-analysis`, never created by the resolver).

**Auto mode never blocks** (`--auto` / `IDD_AUTO_MODE=1`): a missing or failed
reproduction is logged, recorded as `not_reproduced`, and the pipeline continues to
deliver with the affected criterion marked `unverified` (acceptance criterion 6).
Interactive mode behaves the same — surface the evidence (or its absence); do not halt.

### Max commits guard

If commits exceed `resolve.max_commits`:
- Interactive: warn and ask to continue
- Auto: warn in log, continue anyway

### Inline fallback

If no Agent tool, implement inline following `shared/agents/implementer.md`.

## Step 4 — QA (code-reviewer + fixer subagents)

Each cycle:

1. **Code review** — spawn a *fresh* code-reviewer subagent per cycle (see `shared/agents/code-reviewer.md`) so each pass is unbiased.
2. **Run tests** — unit, integration, e2e (if present), build/compile.
3. **Evaluate results:**
   - Reviewer returns `PASS` AND all tests pass AND build succeeds → exit loop, QA passed.
   - Issues found → delegate fixes, then start next cycle.
4. **Fix issues** — spawn or re-message the fixer subagent (see `shared/agents/fixer.md`) with reviewer findings and failing test/build output, passing `security_convention`: `references/docs/pre-commit-security.md`. The fixer reads affected files, applies targeted fixes, verifies them, runs the mandatory pre-commit security scan before committing (real secrets block), and commits as `fix(scope): address review feedback (#N)`. The main agent does not apply code fixes inline when the Agent tool is available.

### Loop controls

- **Max cycles:** `resolve.qa_max_cycles` (default: 5)
- **Exit on clean:** stop as soon as review passes AND tests pass
- **Exit on stagnation:** if the same issues appear in 2 consecutive cycles, stop and report

### After QA

If clean:
```
[4/5] QA           ✓ clean after {N} cycles
```

If max cycles with remaining issues:
```
[4/5] QA           ⚠ {N} issues remain after {max} cycles
```

- Interactive: show remaining issues, ask to continue.
- Auto: continue to Deliver — PR can be created with known issues noted.

### Step 4 — UI/UX review (auto-detected)

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

When `ui: detected`, spawn the `ui-reviewer` subagent in **code** mode (see `shared/agents/ui-reviewer.md`):

```python
Agent(
  description="ui-reviewer — UI/UX code review (#N)",
  prompt=<ui-reviewer.md prompt with mode=code, {variables} replaced>,
  # do NOT set subagent_type — default general-purpose agent, not a custom "ui-reviewer" type
)
```

Pass `{branch_name}`, `{base_branch}`, `{issue_context}` (the linked issue title/body + acceptance criteria), `{pr_context}` (empty — no PR exists yet at QA time), and `{diff_command}` (`git diff origin/${base}...HEAD`). Merge UI reviewer findings into the QA findings — both use the same `action: "fix" | "note"` semantics, so they flow into the fixer loop unchanged.

#### Browser-based review (optional, gated)

Browser review runs only when it both *can* and *should*.

**First, detect the display environment (for the report only — capture is always headless).** Classify the runtime as *no-GUI/server* or *graphical* up front, before the gate and capability checks, so `ui_env` is always defined for every code path below — including the early skip paths. This label never selects the launch mode and never gates the review — Playwright always runs **headless** (the only capture mode this review has ever used), so behavior on a graphical display is unchanged:

```bash
# Label the environment for reporting. Capture stays headless either way —
# headless Chromium needs no display, so a no-GUI/server host is fully supported.
if [ "$(uname)" = "Darwin" ] || [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
  ui_env="graphical"        # a display is present (macOS, or Linux with X11/Wayland)
else
  ui_env="no-GUI server"    # no display ($DISPLAY/$WAYLAND_DISPLAY unset on a non-macOS host)
fi
```

This detection is **report-only**: it is never a fourth gate, and it never switches Playwright to a headed launch. A no-GUI result does **not** skip the browser review — headless Chromium needs no display, so capture proceeds headless exactly as it does on a graphical host.

Then check `resolve.ui_review.browser_review`:

- **`"false"`** — skip; code review already ran.
- **`"ask"`** — prompt interactive users; skip silently in auto mode.
- **`"true"`** — proceed to the capability check.

Then verify the runtime can actually capture screenshots — **all** must hold:
1. A target app is running and reachable (e.g. `curl -sf {app_url}` succeeds).
2. A headless browser is available (Playwright/Chromium installed). A headless server with no display is fine — headless Chromium needs no display, only the browser binary and a reachable app.
3. Capture is safe (not a production URL, no auth wall that would log real traffic).

If the gate or any check fails, print a warning and skip — **without** affecting the code UI review that already ran. Name the environment so a no-GUI host is never mistaken for a silent skip:
```
⚠ Browser review skipped — {reason} (environment: {ui_env})
  Code UI review still ran. Enable browser review with:
  resolve.ui_review.browser_review: "true"  (and ensure the app is running and reachable)
```

When all hold, capture screenshots at mobile/tablet/desktop viewports with Playwright launched **headless**, then spawn the UI reviewer in **browser** mode with the screenshot paths and `{app_url}`. **Report the mode and environment** on success so the review output always states that the headless path ran and where:
```
✓ Browser review — captured 3 viewports (Playwright: headless; environment: {ui_env})
```
UI `action: "fix"` findings join the QA fixable issues handled by the fixer.

## Edge Cases

Full behavior for the edge cases named in SKILL.md.

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
