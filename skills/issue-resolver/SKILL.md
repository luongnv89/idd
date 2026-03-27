---
name: issue-resolver
description: Resolve a GitHub issue end-to-end through a 6-step pipeline (Preflight, Research, Plan, Implement, QA, Deliver) producing an atomic PR with "Closes #N". Checks issue status and verifies the issue hasn't already been resolved before starting work. In auto-pilot mode, all steps run autonomously without user prompts. Use this skill whenever someone says "resolve issue", "fix issue", "work on issue", "implement issue", "/issue-resolver", or provides an issue number they want resolved. Also trigger when asked to "close this issue with a PR", "implement #N", "fix #N", "take issue #N", "start working on #N", "pick up issue #N", or even just "#N" with the intent to work on it. If the user mentions a GitHub issue number and wants code written to address it, this is the right skill — even if they don't say "resolve" explicitly.
effort: max
license: MIT
metadata:
  version: 0.5.0
  creator: Luong NGUYEN <luongnv89@gmail.com>
compatibility: Requires git and GitHub CLI (gh) with authentication and push access. Self-contained — uses shared agents from shared/agents/.
---

# /issue-resolver N

Resolve a GitHub issue end-to-end — from issue to atomic PR in 6 steps.

## Invocation

| Invocation | Mode | What happens |
|------------|------|--------------|
| `/issue-resolver <N>` | interactive | Resolve issue #N, ask user to pick plan |
| `/issue-resolver <N> --auto` | auto-pilot | Resolve fully autonomously, no user prompts |

The argument must be a GitHub issue number. The `--auto` flag is set automatically when invoked by `/auto-pilot`.

## Prerequisites

Before any operation, verify the environment. On failure, output the exact error from `references/error-messages.md` and stop.

1. Confirm git repository: `git rev-parse --git-dir`
2. Confirm `gh` is installed: `which gh`
3. Confirm authentication: `gh auth status`
4. Confirm GitHub remote exists: `git remote -v`

## Repo Sync Before Edits (mandatory)

Before making file modifications, sync with remote:

```bash
branch="$(git rev-parse --abbrev-ref HEAD)"
git fetch origin
git pull --rebase origin "$branch"
```

If the working tree is dirty, stash first, sync, then pop:

```bash
git stash push -u -m "pre-sync"
branch="$(git rev-parse --abbrev-ref HEAD)"
git fetch origin && git pull --rebase origin "$branch"
git stash pop
```

If `origin` is missing or conflicts occur, stop and ask the user (in interactive mode) or abort with error (in auto mode).

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

---

## Subagent Architecture

The resolve pipeline delegates heavy work to subagents to keep the main agent's context clean. All agents are in `shared/agents/`.

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
│   Runs tests/build between cycles
│   Max 5 cycles
│
└── Step 5: Deliver (main agent — push + create PR + report)
```

Read `shared/agents/codebase-researcher.md` for the researcher prompt.
Read `shared/agents/synthesizer.md` for the synthesizer prompt.
Read `shared/agents/implementer.md` for the implementer prompt.
Read `shared/agents/code-reviewer.md` for the reviewer prompt.

### Environment check

If the Agent tool is available, use subagents as described above.
If not (e.g., Claude.ai), execute each step inline using the fallback instructions.

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

### 0e — Create branch

Create working branch: `{type}/{N}-{short-description}` (see `docs/naming-conventions.md`).

**If branch already exists:**
- Interactive mode: ask `continue` or `fresh`
- Auto mode: `continue` (checkout existing branch)

After preflight:
```
[0/5] Preflight    ✓ issue #N open, branch: {branch_name}
```

---

## Step 1 — Research

Deeply understand the issue, the affected codebase, and possible solutions. This step also verifies the issue hasn't already been fixed.

### GitHub Projects status transition

If `projects.sync_enabled` is true, set the issue status to `status_map.in_progress` (see `docs/github-projects-sync.md`).

### Subagent delegation (preferred)

Spawn the codebase-researcher agent with:

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

The researcher will:
1. **Verify not already resolved** — check git history for closing commits, check codebase for evidence the bug is fixed
2. **Scan codebase** — extract targets, grep/glob, read files, trace deps
3. **Assess complexity** — trivial / low / medium / high / complex
4. **Research solutions** (for high/complex) — algorithms, optimizations, design patterns, web search if needed
5. **Analyze git history** — prior attempts, regressions, domain experts
6. **Cross-reference issues** — duplicates, blockers, related work

### Early exit: already resolved

If the researcher returns `already_resolved: true` or `pr_in_progress: true`:

```
✓ Issue #N appears to already be resolved
  {resolution_details}

  Recommend closing the issue.
```

In auto mode: close the issue with a comment and move to the next issue.
In interactive mode: inform the user and stop.

### Inline fallback

If no Agent tool, execute research inline following the same phases described in `shared/agents/codebase-researcher.md`.

After research:
```
[1/5] Research     ✓ read {N} files, complexity: {level}
```

---

## Step 2 — Plan

Generate implementation options and select one.

### Subagent delegation (preferred)

Spawn the synthesizer agent with:
- Issue data
- Research findings (JSON from Step 1)
- Mode: `"auto"` if auto-pilot, `"interactive"` otherwise

The synthesizer returns 3 options differing in scope:
1. **Minimal fix** — smallest change
2. **Balanced approach** — proper fix, reasonable scope (usually recommended)
3. **Comprehensive refactor** — addresses root cause and technical debt

### Plan selection

**Interactive mode (`resolve.approval_gate: auto`):**
Display the plan summary and proceed with the recommended option:
```
[2/5] Plan         ✓ approach: {selected option name}
```

**Interactive mode (`resolve.approval_gate: comment-and-wait`):**
Present all 3 options to the user:

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

**Auto mode:**
Auto-select the recommended option (best balance of quality and effort). No user prompt.

```
[2/5] Plan         ✓ auto-selected option {N}: {name}
```

### Inline fallback

If no Agent tool, analyze the research findings and generate the plan inline.

---

## Step 3 — Implement

Write code and all tests based on the selected plan.

### Subagent delegation (preferred)

Spawn the implementer agent with:
- Issue data
- Research findings (from Step 1)
- Selected plan (the chosen option from Step 2)
- Branch name
- Naming conventions: `docs/naming-conventions.md`
- Max commits: `resolve.max_commits`

The implementer writes:
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

After implementation:
```
[3/5] Implement    ✓ {N} files changed, {U} unit tests, {E} e2e tests
```

---

## Step 4 — QA

Automated quality assurance loop: review code, run tests, build, fix issues. Repeats until clean or max cycles reached.

### QA cycle

Each cycle:

1. **Code review** — spawn a fresh code-reviewer agent (see `shared/agents/code-reviewer.md`). Fresh agent each cycle ensures unbiased review.

2. **Run tests** — detect and run the project's test suite:
   - Unit tests
   - Integration tests
   - E2e tests (if framework exists)
   - Build/compile check

3. **Evaluate results:**
   - If reviewer returns `PASS` AND all tests pass AND build succeeds → exit loop, QA passed
   - If issues found → fix them, then start next cycle

4. **Fix issues** — for each issue from the reviewer or test failures:
   - Read affected file
   - Apply fix
   - Stage and commit: `fix(scope): address review feedback (#N)`

### Loop controls

- **Max cycles:** `resolve.qa_max_cycles` (default: 5)
- **Exit on clean:** Stop as soon as review passes AND tests pass
- **Exit on stagnation:** If the same issues appear in 2 consecutive cycles, stop and report

### After QA

If clean:
```
[4/5] QA           ✓ clean after {N} cycles
```

If max cycles with remaining issues:
```
[4/5] QA           ⚠ {N} issues remain after {max} cycles
```
In interactive mode: show remaining issues and ask to continue.
In auto mode: continue to Deliver — the PR can be created with known issues noted.

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

```bash
git push -u origin {branch_name}
```

### Create PR

```bash
gh pr create --title "{pr_title}" --body "{pr_body}"
```

**PR title:** `{type}({scope}): {description} (#{issue_number})` (see `docs/naming-conventions.md`)

**PR body:**

```markdown
Closes #{issue_number}

## Summary

{One-paragraph summary}

## Approach

{Selected option name and description}

## Changes

| File | Change |
|------|--------|
| `{file}` | {description} |

## Test Results

- Unit tests: {count} passed
- Integration tests: {count} passed (or skipped)
- E2e tests: {count} passed (or skipped)
- Build: passed
- QA cycles: {count}

## Acceptance Criteria

- [x] {criterion — checked if addressed}
- [ ] {criterion — unchecked with note}
```

### Project board sync

If `projects.sync_enabled` is true, update status to `status_map.done` (see `docs/github-projects-sync.md`).

After delivery:
```
[5/5] Deliver      ✓ PR #{pr_number} created
```

---

## Final Report

```
✓ Done — PR #{pr_number}: {pr_title}
  https://github.com/owner/repo/pull/{pr_number}
  Closes #{issue_number}

  Research:    {complexity}, {files_read} files analyzed
  Plan:        {option_name} ({complexity_rating}, {risk_rating} risk)
  Implement:   {files_changed} files, {tests_written} tests
  QA:          {cycles} cycles, {issues_found} issues fixed
```

---

## Auto-Pilot Mode

When invoked with `--auto` (or by `/auto-pilot`), the entire pipeline runs without user interaction:

- **Preflight:** Skip assignment guard. Log blocking labels as warnings, don't stop.
- **Research:** If already resolved, close the issue with a comment and exit cleanly.
- **Plan:** Auto-select the recommended option (best balance of quality/effort).
- **Implement:** Continue past max commits guard with a warning.
- **QA:** Run full cycle autonomously. If stagnation detected, continue to deliver with known issues.
- **Deliver:** Create PR. Do NOT merge — merging is handled by `/auto-pilot` or `/issue-pr-review`.

No `[y/N]` prompts, no `Choose:` prompts, no `Continue?` prompts. Every decision point has a defined auto behavior.

---

## Edge Cases

### No acceptance criteria
PR body notes: `> **Note:** No acceptance criteria defined — manual review recommended.`

### Issue body is empty
- Interactive: warn and ask to continue
- Auto: warn in log, continue with title-only context

### Large issues (20+ files estimated)
- Interactive: warn and ask
- Auto: warn in log, continue

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
- **`references/error-messages.md`** — Complete error catalog
- **`docs/naming-conventions.md`** — Branch, commit, PR naming conventions
- **`docs/github-projects-sync.md`** — GitHub Projects status sync
- **`DESIGN.md`** — Terminal output style guide
- **`docs/config-schema.md`** — Configuration schema
