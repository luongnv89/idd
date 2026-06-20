# Pipeline Step Details

Detailed procedures for each subagent delegation in the resolve pipeline. SKILL.md keeps the contract short; this file holds the full input/output spec and inline fallback instructions.

## Step 0e — Workspace (interactive only)

Full procedure for the worktree offer described in SKILL.md *Step 0e — Workspace*. **Interactive mode only** — in auto mode (`--auto` / `IDD_AUTO_MODE=1`) this entire step is skipped and the pipeline uses the in-place path (Repo Sync + *0f — Create branch*), byte-for-byte as before. The worktree prompt never appears in auto mode (acceptance criterion 4).

### Why a worktree

`git worktree` checks out a branch into a *separate directory* that shares the same `.git` object store. The user's current working tree — including any uncommitted changes — is never modified. Branch creation, implementation, and the QA test runs all happen in the isolated directory.

### The offer

Present the prompt from SKILL.md (*Step 0e — Workspace*). It must state, before the user answers:

- the **branch** name (`{type}/{N}-{short-description}`),
- the **worktree path** (the naming convention below), and
- what **setup** will be copied/run (gitignored local config + the project's detected install/bootstrap).

Default is **accept** (`[Y/n]`). This satisfies acceptance criterion 5 (the proposal states what is copied and the workspace/branch naming).

### Naming convention

- **Branch:** `{type}/{N}-{short-description}` — identical to the in-place path (`docs/naming-conventions.md`). Unchanged so traceability and the `feat/`, `fix/`, … prefixes stay consistent.
- **Worktree directory:** a *sibling* of the repo root, derived from the branch with `/` → `-` so it is a single path segment:

  ```
  ../{repo}-worktrees/{type}-{N}-{short-description}
  ```

  Example: repo `idd`, branch `feat/123-resolver-worktree-prompt` → `../idd-worktrees/feat-123-resolver-worktree-prompt`.

  A sibling directory (outside the repo) keeps the worktree out of the repo's own status and ignore rules. If you instead place it *inside* the repo, the path **must** already be covered by `.gitignore` — otherwise the worktree's own files surface as untracked changes in the parent. Prefer the sibling location.

### Create the worktree

`git worktree add -b` creates the branch **and** the workspace in one command, off a freshly fetched base — so this replaces both the mandatory Repo Sync and *0f — Create branch* on the accepted path. No `git pull --rebase` / stash dance is needed (the new branch starts at `origin/<base>` directly).

```bash
repo_root="$(git rev-parse --show-toplevel)"        # absolute path to the repo
base="$(git rev-parse --abbrev-ref HEAD)"           # base branch to fork from
repo="$(basename "$repo_root")"
branch="{type}/{N}-{short-description}"
# Absolute worktree path (sibling of the repo) — independent of the current
# directory, so later steps that `cd` into it stay correct.
wt_dir="$(dirname "$repo_root")/${repo}-worktrees/$(printf '%s' "$branch" | tr '/' '-')"

git fetch origin
created_branch_in_step_0e=1
git worktree add -b "$branch" "$wt_dir" "origin/${base}"
```

Keep `repo_root` and `wt_dir` available for the setup step below (both are
absolute, so the copy works regardless of the current directory).

**If the branch already exists** (`git worktree add -b` fails): in interactive mode ask `continue` (set `created_branch_in_step_0e=0`, then add a worktree for the existing branch with `git worktree add "$wt_dir" "$branch"`) or `fresh` (delete the branch, keep `created_branch_in_step_0e=1`, then retry). See `references/error-messages.md` → *Branch already exists*.

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
git worktree remove "$wt_dir" --force 2>/dev/null || git worktree prune
# Delete the branch only if this Step 0e created it with `git worktree add -b`.
# If the user chose to continue an existing branch, keep the branch and let 0f's
# existing branch flow handle it.
if [ "${created_branch_in_step_0e:-0}" = "1" ]; then
  git branch -D "$branch" 2>/dev/null || true
fi
```

After cleanup, run the mandatory Repo Sync and *0f — Create branch* in the original working tree. If cleanup itself fails, stop and tell the user how to recover with `git worktree list`, `git worktree remove {wt_dir}`, and `git worktree prune` rather than attempting to use two checked-out copies of the same branch.

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

### Inline fallback

If no Agent tool, analyze the research findings and generate the plan inline.

## Step 3 — Implement (implementer subagent)

### Delegation payload

- Issue data
- Research findings (from Step 1)
- Selected plan (the chosen option from Step 2)
- Branch name
- Naming conventions: `docs/naming-conventions.md`
- Max commits: `resolve.max_commits`

### What the implementer writes

1. Implementation code with atomic commits
2. Unit tests for all new/changed functions
3. Integration tests (if framework exists)
4. E2e tests (if framework exists)
5. All committed following conventional commit format

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
