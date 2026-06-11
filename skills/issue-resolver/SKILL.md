---
name: issue-resolver
description: "Create an atomic PR that closes a GitHub issue end-to-end via a 6-step pipeline. Use when asked to resolve issue #N, fix #N, implement #N, work on #N, take issue #N, or /issue-resolver. Don't use for analyzing an issue without implementing (use /issue-analysis), reviewing an existing PR (use /issue-pr-review), or bulk backlog processing (use /auto-pilot)."
license: MIT
compatibility: Requires git and GitHub CLI (gh) with authentication and push access. Self-contained — uses shared agents from shared/agents/.
effort: max
metadata:
  version: 0.7.2
  creator: Luong NGUYEN <luongnv89@gmail.com>
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
│   Runs tests/build between cycles
│   Max 5 cycles
│
└── Step 5: Deliver (main agent — push + create PR + report)
```

Read `references/agents/codebase-researcher.md` for the researcher prompt.
Read `references/agents/synthesizer.md` for the synthesizer prompt.
Read `references/agents/implementer.md` for the implementer prompt.
Read `references/agents/code-reviewer.md` for the reviewer prompt.

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
- `references/pipeline-steps.md` — Full delegation payloads, phases, and inline fallbacks for Steps 1–4
- `references/report-templates.md` — PR body template, final report templates, and expected inline output
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

### 0e — Create branch

Create working branch: `{type}/{N}-{short-description}` (see `references/docs/naming-conventions.md`).

**If branch already exists:**
- Interactive mode: ask `continue` or `fresh`
- Auto mode: `continue` (checkout existing branch)

After preflight:
```
[0/5] Preflight    ✓ issue #N open, branch: {branch_name}
```

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

Full payload, commit guardrails, and inline fallback are in `references/pipeline-steps.md` (*Step 3 — Implement*).

After implementation:
```
[3/5] Implement    ✓ {N} files changed, {U} unit tests, {E} e2e tests
```

---

## Step 4 — QA

Automated review-fix loop: review → test → fix → repeat until clean or max cycles reached. Each cycle spawns a *fresh* `code-reviewer` subagent (see `references/agents/code-reviewer.md`) for unbiased review.

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

Before pushing, run the pre-commit security scan against every file touched by
commits on this branch. The implementer ran the scan per commit during Step 3,
but a final pre-push pass catches secrets that may have slipped in during QA
fixes (see the pre-commit security conventions reference at
`references/docs/pre-commit-security.md` — that document is authoritative; the snippet
below mirrors its Primary Pattern). Real secrets block the push; warnings
prompt for confirmation in interactive mode and log-and-continue in auto mode.

```bash
# Pre-push security scan — mirrors the Primary Pattern in the
# pre-commit-security conventions reference. Set IDD_AUTO_MODE=1 in auto mode.
base="$(gh pr view --json baseRefName --jq .baseRefName 2>/dev/null || echo main)"
files="$(git diff --name-only "origin/${base}"...HEAD)"
secrets_found=0
warnings=()
if printf '%s\n' "$files" | grep -E -q '(^|/)\.env($|\.)|\.key$|\.pem$|credentials\.json$|secrets\.ya?ml$|id_rsa($|\.pub$)|\.p12$|\.pfx$|\.cer$'; then
  echo "✗ Secret-bearing file in branch diff."
  secrets_found=1
fi
realkey='(sk-(proj-)?[A-Za-z0-9_-]{20,}|sk_live_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|gho_[A-Za-z0-9]{30,}|ghs_[A-Za-z0-9]{30,}|ghu_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|xox[abprs]-[A-Za-z0-9-]{10,}|glpat-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{30,})'
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  file --mime "$f" 2>/dev/null | grep -q 'charset=binary' && continue
  if grep -E -q "$realkey" "$f" 2>/dev/null; then
    echo "✗ Real API key detected in: $f"
    secrets_found=1
  fi
  size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)
  [ "$size" -gt 10485760 ] && warnings+=("⚠ Large file (>10 MB) without LFS: $f")
done <<< "$files"
junk='(^|/)(node_modules|dist|build|__pycache__|\.venv)(/|$)|\.pyc$|(^|/)(\.DS_Store|thumbs\.db)$|\.swp$|\.tmp$'
while IFS= read -r f; do
  [ -z "$f" ] && continue
  printf '%s\n' "$f" | grep -E -q "$junk" && warnings+=("⚠ Build artifact in diff: $f")
done <<< "$files"
case "$(git rev-parse --abbrev-ref HEAD)" in
  main|master|production|release) warnings+=("⚠ On protected branch — confirm intentional") ;;
esac
[ "$secrets_found" = 1 ] && { echo "✗ Pre-push security scan blocked. See pre-commit-security conventions reference."; exit 1; }
if [ "${#warnings[@]}" -gt 0 ]; then
  printf '%s\n' "${warnings[@]}"
  if [ "${IDD_AUTO_MODE:-0}" = "1" ]; then
    echo "○ Warnings logged — proceeding (auto mode)."
  else
    printf "Proceed anyway? [y/N] "; read -r reply
    case "$reply" in y|Y|yes|YES) echo "○ Continuing despite warnings." ;; *) echo "✗ Stopped."; exit 1 ;; esac
  fi
fi
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

After delivery:
```
[5/5] Deliver      ✓ PR #{pr_number} created
```

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
- **Preflight:** Skip assignment guard. Log blocking labels as warnings, don't stop.
- **Research:** If already resolved, close the issue with a comment and exit cleanly.
- **Plan:** Auto-select the recommended option (best balance of quality/effort).
- **Implement:** Continue past max commits guard with a warning.
- **QA:** Run full cycle autonomously. If stagnation detected, continue to deliver with known issues.
- **Deliver:** Create PR. Do NOT merge — merging is handled by `/auto-pilot` or `/issue-pr-review`.

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
- **`references/pipeline-steps.md`** — Full delegation payloads, phases, and inline fallbacks for Steps 1–4
- **`references/report-templates.md`** — PR body template, final report templates, and expected inline output
- **`references/error-messages.md`** — Complete error catalog
- **`references/docs/naming-conventions.md`** — Branch, commit, PR naming conventions
- **`references/docs/github-projects-sync.md`** — GitHub Projects status sync
- **`DESIGN.md`** — Terminal output style guide
- **`references/docs/config-schema.md`** — Configuration schema
