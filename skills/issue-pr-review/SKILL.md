---
name: issue-pr-review
description: "Review a PR end-to-end with CI checks, fix cycles, and optional auto-merge. Use for PR review, cleanup, or readiness checks. Don't use for creating PRs, raw issue analysis, or non-PR code review."
license: MIT
compatibility: "Requires git and GitHub CLI (gh) with authentication. Self-contained — uses shared agents from shared/agents/."
effort: high
metadata:
  version: 2.0.0
  author: Luong NGUYEN <luongnv89@gmail.com>
---

# /issue-pr-review [PR_NUMBER]

Review a pull request end-to-end — analyze, test, fix, check CI, repeat until clean.

## Invocation

| Invocation | Mode | What happens |
|------------|------|--------------|
| `/issue-pr-review <N>` | interactive | Review, fix, and repeat until clean; report findings (no auto-merge) |
| `/issue-pr-review <N> --auto` | auto-pilot | Review, fix, and auto-merge when clean |
| `/issue-pr-review` | detect | Auto-detect PR for current branch |
| `/issue-pr-review --review-only` | read-only | Review and report, never fix or merge |

The `--auto` flag is set automatically when invoked by `/auto-pilot`.

In auto mode, export `IDD_AUTO_MODE=1` before any shell snippet that consults it — the pre-commit security scan reads this to switch from prompt-on-warning to log-and-continue (see `references/docs/pre-commit-security.md`).

## Prerequisites

1. Confirm git repository: `git rev-parse --git-dir`
2. Confirm `gh` is installed and authenticated: `gh auth status`
3. Confirm the bundled reviewer agent exists at `references/agents/code-reviewer.md`
4. Confirm the bundled fixer agent exists at `references/agents/fixer.md`
5. Confirm the bundled UI reviewer agent exists at `references/agents/ui-reviewer.md`

### Bundled dependency precheck

`/issue-pr-review` is distributed as a self-contained skill — it does not require another gitissue skill to review a PR, but it does require its bundled agent prompts and reference files. Before execution, verify the files below are present relative to the skill's directory (the dirname of this SKILL.md). If any is missing, stop immediately and print the error, then do not continue with an inline or guessed reviewer/fixer prompt:

```text
✗ Missing bundled dependency: {missing_file}

  To fix:  asm install https://github.com/luongnv89/idd --skill issue-pr-review
           (or reinstall the full distribution)

  Then restart the agent session and re-run /issue-pr-review.
```

- `references/agents/code-reviewer.md` — Review subagent prompt
- `references/agents/fixer.md` — Fix subagent prompt
- `references/agents/ui-reviewer.md` — UI/UX review subagent prompt (auto-detected; see Step 3)
- `references/verification-checks.md` — AC + traceability check procedure (Step 3)
- `references/review-loop-mechanics.md` — reviewer/fixer spawn + reuse mechanics
- `references/report-templates.md` — Step 7 summary templates, auto-merge flow, expected inline output
- `references/docs/pre-commit-security.md` — pre-commit security conventions reference
- `references/docs/sync-conventions.md` — stash-first sync convention and recovery
- `references/docs/idd-methodology.md` — IDD methodology (durable analysis fields)
- `references/docs/naming-conventions.md` — naming conventions

## Repo Sync Before Edits (mandatory)

Before making any fixes, sync with remote using the stash-first pattern (see `references/docs/sync-conventions.md` for the full convention and recovery procedure):

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

If `origin` is missing or rebase conflicts occur, stop and ask (interactive) or abort with a clear error (auto).

## Configuration

Load `.gitissue.yml` once. Defaults:
- `review.max_cycles: 3` — reduced from 5; script pre-pass handles mechanical issues, so 3 LLM cycles suffice for logic/architecture
- `review.auto_merge: false` (overridden to `true` in auto mode)
- `review.confidence_threshold: 80`
- `review.run_tests: true`
- `review.check_ci: true`
- `review.ci_poll_interval: 30` (seconds)
- `review.ci_timeout: 600` (seconds, 10 minutes)
- `review.test_timeout: 300` (seconds)
- `review.soft_pass: true` — pass when zero "fix" issues remain, even if "note" issues exist (≤ 2 medium allowed)
- `review.require_acceptance_criteria_check: true` — gate for per-criterion AC verification
- `review.require_traceability_check: true` — gate for the four traceability checks
- `review.traceability_exempt_labels: ["refactor", "chore"]` — labels that exempt a PR from the `Closes #N` hard-fail
- `review.traceability_exempt_pattern: "^\\s*Type:\\s*(refactor|chore)\\s*$"` — body-line regex exempting a PR from the `Closes #N` hard-fail
- `review.ui_review.browser_review: "ask"` — browser (screenshot) review mode (`"false"` | `"ask"` | `"true"`); `"ask"` prompts interactive users, skips in auto mode. Does **not** gate the code-level UI review, which is auto-detected and always runs when UI work is present.

UI/UX **code** review needs no config flag — it is auto-detected per PR (see *Step 3 — UI/UX Review*). Only the optional browser review reads `review.ui_review.browser_review`.

The traceability flags default to `true`/the values shown, which preserve the issue #36 contract. Their full semantics (what `false` does, exemption scope, disabling) are in `references/verification-checks.md`.

---

## Pipeline Overview

```
  ◆ PR Review Pipeline
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  [1/7] PR Info      ✓ PR #87: fix(auth): resolve redirect (#42)
  [2/7] Pre-pass     ✓ lint clean, format clean, 17 tests passed
  [3/7] Review       ● analyzing changes...
  [4/7] Test         ✓ 17 tests passed, build ok
  [5/7] CI Status    ✓ all checks passed
  [6/7] Fix          ○ no fixable issues
  [7/7] Report       ✓ PR is clean — ready to merge
```

Step 2 (Pre-pass) runs once before the review loop. Steps 3-6 repeat up to `review.max_cycles` times (default: 3). Step 7 runs once at the end. The pipeline minimizes LLM tokens via a zero-token script pre-pass (Step 2), reviewer/fixer reuse across cycles, severity-based `fix`/`note` filtering (Step 6), and the soft-pass condition (Review Loop).

---

## Step 1 — Get PR Info [1/7]

### Auto-detect PR

If no PR number provided, detect from current branch:

```bash
gh pr view --json number,title,body,baseRefName,headRefName,state,url,statusCheckRollup
```

If no PR exists for the current branch:
```
✗ No PR found for branch {branch_name}

  To fix:  gh pr create
  Or:      /issue-pr-review <PR_NUMBER>
```

### Fetch PR details

```bash
gh pr view {N} --json number,title,body,baseRefName,headRefName,state,url,labels,reviews,statusCheckRollup,files
```

Extract:
- PR number, title, URL
- Base and head branches
- Linked issue numbers (from `Closes #N` in body)
- Current CI status
- Files changed

**If PR is closed/merged:**
```
⚠ PR #{N} is already {state}
```
Stop.

```
[1/7] PR Info      ✓ PR #{N}: {title}
                     {files_count} files changed, base: {base_branch}
```

---

## Step 2 — Script Pre-pass [2/7]

Before spawning any LLM reviewer, run deterministic tools to catch and auto-fix mechanical issues. This step uses zero LLM tokens — all work is done by scripts and CLI tools.

### Detect project tooling

Detect available lint/format/test tools from the project:

| Tool type | Detection | Auto-fix command |
|-----------|-----------|-----------------|
| ESLint | `.eslintrc*` or `eslint` in package.json | `npx eslint --fix .` |
| Prettier | `.prettierrc*` or `prettier` in package.json | `npx prettier --write .` |
| Black | `pyproject.toml` with `[tool.black]` | `python -m black .` |
| Ruff | `pyproject.toml` with `[tool.ruff]` or `ruff.toml` | `ruff check --fix . && ruff format .` |
| isort | `pyproject.toml` with `[tool.isort]` | `python -m isort .` |
| gofmt | `go.mod` | `gofmt -w .` |
| rustfmt | `Cargo.toml` | `cargo fmt` |
| clang-format | `.clang-format` | `find . -name '*.c' -o -name '*.h' \| xargs clang-format -i` |

### Run auto-fix

For each detected tool, run the auto-fix command. Capture output but don't block on warnings — only block on errors that prevent the fix from running.

```bash
# Example for a Node.js project:
npx eslint --fix . 2>&1
npx prettier --write . 2>&1
```

### Run tests

Run the project's test suite to catch test failures early (before the LLM review):

```bash
# Detected test runner
npm test          # or pytest, go test ./..., cargo test, etc.
```

### Commit auto-fixes

If any files were modified by the auto-fix tools, you MUST run the pre-commit
security scan before staging. The authoritative scan is the **Primary Pattern**
in `references/docs/pre-commit-security.md` — run that exact pattern against the working
tree; do not improvise a weaker check. In auto mode, export `IDD_AUTO_MODE=1`
first so the scan logs-and-continues on warnings instead of prompting.

The scan enforces, in order:

1. **Block on real secrets** — secret-bearing filenames (`.env`, `*.key`, `*.pem`, `credentials.json`, `id_rsa`, …) or real API-key patterns (OpenAI, AWS, GitHub, Slack, GitLab, Google) in any staged text file → print the offending file and `exit 1`. Never commit.
2. **Warn (non-blocking) on** large files (>10 MB without LFS), staged build artifacts (`node_modules`, `dist`, `__pycache__`, `*.pyc`, …), and being on a protected branch (`main`/`master`/`production`/`release`). In interactive mode prompt `Proceed anyway? [y/N]`; in auto mode (`IDD_AUTO_MODE=1`) log and continue.

Only after the scan passes (or warnings are accepted), commit and push:

```bash
git add -A
git commit -m "style: auto-fix lint and format issues"
git push origin {branch_name}
```

```
[2/7] Pre-pass     ✓ lint clean, format clean, {N} tests passed
                     Auto-fixed: {files_fixed} files (lint/format)
```

If no tools detected:
```
[2/7] Pre-pass     ○ no lint/format tools detected, tests: {N} passed
```

If tests fail at this stage, continue to the review loop — test failures will be picked up in Step 4 and addressed in the fix cycle.

---

## Step 3 — Analyze & Review [3/7]

### Reviewer agents and cycle reuse

Read `references/agents/code-reviewer.md` for the reviewer prompt template and `references/agents/fixer.md` for the fix-cycle prompt. Both are spawned with `subagent_type="general-purpose"` (NOT a custom `code-reviewer`/`fixer` type). Pass the reviewer `branch_name`, `base_branch`, `pr_context` (PR title + body), and `diff_command` (`gh pr diff {N}`).

To minimize tokens, the loop **reuses the same reviewer across cycles**: cycle 1 is a cold-start spawn; cycles 2+ re-message that agent via `SendMessage` to re-review the updated diff; after the fixer reports zero fixable issues, one **fresh** confirmation reviewer does an unbiased final check. The full mechanics (exact spawn calls, the SendMessage re-review prompt, and the token-trade rationale) live in `references/review-loop-mechanics.md`.

### UI/UX Review (Step 3 — auto-detected)

UI review is **auto-detected per PR** — no config flag enables it. The skill examines the PR title/body and changed files to decide whether UI work is involved, then runs only the review that *can* and *should* run for this PR:

- **Code UI review** is environment-independent — it reads the diff and changed files. It runs whenever UI work is detected, on any machine, **including a headless server with no display**. It is never gated on a GUI, a running app, or a browser.
- **Browser UI review** is optional. It captures screenshots from a running app, so it only runs when there is a reachable running app *and* the user opted in. When it can't run (no app, no display capable of headless capture, capture unsafe, or auto mode without opt-in), it **skips with a warning and the code UI review still runs** — fail-soft to code-only, never block.

This separation is the contract: detecting UI work always gives you a code UI review; the browser review is an additive bonus when the runtime allows it.

#### Detection phase (runs once, after Step 2, before the review cycles)

1. **Check PR context** for UI indicators:
   ```bash
   pr_body=$(gh pr view {N} --json body --jq .body)
   ```
   Scan title + body for UI keywords: `UI`, `frontend`, `component`, `style`, `css`, `html`, `design`, `layout`, `responsive`, `mobile`, `theme`, `dark mode`, `button`, `form`, `page`, `screen`, `visual`, `accessibility`, `a11y`, `icon`, `image`, `screenshot`, `dashboard`, `navigation`, `modal`, `dialog`, `card`, `table`, `chart`, `graph`.

2. **Check PR diff** for UI file changes:
   ```bash
   ui_files=$(gh pr diff {N} --name-only | grep -E '\.(html|htm|css|scss|sass|less|styl|tsx|jsx|vue|svelte|astro)$|^(components|pages|views|layouts|app|src/app|screens|routes|templates)/|tailwind\.config\.|theme\.|tokens\.')
   ```

3. **Classify**:
   - **`ui: detected`** — UI keywords in PR context OR UI files in diff → run the code UI review.
   - **`ui: not detected`** — no UI indicators → skip UI review entirely (no agent spawned).

4. **Propose review mix** (interactive mode only):
   ```
   ◆ UI Review Detected
   ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
   
     PR mentions:    responsive, mobile, button
     Files changed:  src/components/Button.tsx, src/styles/main.css
   
     Proposed review:
       ✓ Code review (a11y, responsive, interaction patterns) — runs now
       ○ Browser review (screenshot capture) — needs a running app
   
     Enable browser review? [Y/n] (requires a reachable app + Playwright)
   ```
   In auto mode (`IDD_AUTO_MODE=1`): log the detection result and proceed with **code review only** — browser review requires user confirmation per `review.ui_review.browser_review`.

#### Code-based review

When detection returns `ui: detected`, spawn the `ui-reviewer` subagent in **code** mode (see `references/agents/ui-reviewer.md`):

```python
Agent(
  description="UI/UX code review for PR #{N}",
  prompt=<ui-reviewer.md prompt with mode=code, {variables} replaced>,
  subagent_type="general-purpose"
)
```

Pass `{branch_name}`, `{base_branch}`, `{pr_context}` (PR title + body), `{issue_context}` (the linked issue title/body + acceptance criteria, or empty if none), and `{diff_command}` (`gh pr diff {N}`). Merge UI reviewer findings into the code reviewer findings — both use the same `action: "fix" | "note"` semantics, so they flow into Step 6 unchanged.

For cycle reuse, cycles 2+ re-message the existing UI reviewer via `SendMessage`:
```
The fixer applied changes. Re-review the PR diff for UI/UX issues.

Run: gh pr diff {N}

Return the same JSON format as before.
```
For the confirmation pass, spawn one **fresh** UI reviewer for an unbiased final check.

#### Browser-based review (optional, gated)

Browser review runs only when it both *can* and *should*. Check `review.ui_review.browser_review`:

- **`"false"`** — skip; code review already ran.
- **`"ask"`** — prompt interactive users; skip silently in auto mode.
- **`"true"`** — proceed to the capability check below.

Then verify the runtime can actually capture screenshots — **all** must hold:
1. A target app is running and reachable (e.g. `curl -sf {app_url}` succeeds).
2. A headless browser is available (Playwright/Chromium installed). A headless server with no physical display is fine — headless Chromium needs no display; what it needs is the browser binary and a reachable app.
3. Capture is safe (not a production URL, no auth wall that would log real traffic).

If the gate or any capability check fails, print a warning and skip — **without** affecting the code UI review that already ran:
```
⚠ Browser review skipped — {reason}
  Code UI review still ran. Enable browser review with:
  review.ui_review.browser_review: "true"  (and ensure the app is running and reachable)
```

When all hold, capture screenshots at mobile/tablet/desktop viewports and spawn the UI reviewer in **browser** mode with the screenshot paths and `{app_url}`.

#### Integration with the fixer

`action: "fix"` findings from the UI reviewer join the fixable issues in Step 6. The fixer handles file/line findings normally; browser-only findings without file/line are resolved by identifying the responsible files from the PR diff and issue context.

Also fetch the linked issue for acceptance-criteria verification: `gh issue view {linked_issue} --json number,title,body,labels`.

```
[3/7] Review       ✓ correctness:pass  ac:pass  trace:pass  maint:partial  safety:pass
                     {fixable_count} fixable, {note_count} noted
```

### Order within Step 3

Within a single review cycle, the work runs in this order:
1. Spawn (or re-message) the reviewer subagent and collect its findings.
2. If UI work was detected (see *UI/UX Review* above), spawn (or re-message) the UI reviewer in **code** mode and collect its findings. Skip when `ui: not detected`.
3. Run per-criterion acceptance-criteria verification against the linked issue.
4. Run the four traceability checks against the PR body and commit history.
5. Aggregate reviewer findings + UI reviewer findings + AC results + traceability results into the five user-facing dimensions for the cycle report.

### Dimensional review output

Step 3 produces a single review verdict organized into **five dimensions**. The reviewer subagent reports findings against its own internal categories (correctness, test_coverage, code_quality, security, edge_cases); this skill maps those findings into the user-facing dimensions and adds two dimensions the reviewer does not produce (acceptance criteria, traceability). When UI work is detected, the UI reviewer's `ui_ux` findings fold into `maintainability` (a11y, responsive, interaction, and consistency are quality concerns). Mapping is fixed:

| User-facing dimension | Source | Failure means |
|----------------------|--------|---------------|
| `correctness` | reviewer category `correctness` | logic, off-by-one, race conditions |
| `acceptance_criteria` | per-criterion verification (this skill) | one or more criteria report `fail` |
| `traceability` | PR-body and commit-history scan (this skill) | issue-to-code link is broken |
| `maintainability` | reviewer categories `code_quality` + `test_coverage`; UI reviewer `ui_ux` findings (when detected) | dead code, untested paths, complex logic, a11y/responsive/interaction defects |
| `safety` | reviewer categories `security` + `edge_cases` | injection, auth bypass, unsafe nulls, crash paths |

A UI `action: "fix"` finding makes `maintainability` report at least `partial` and contributes a fixable issue to Step 6 (`category: ui_ux`), so the dimensional verdict never shows all-pass while UI fixables remain.

Each dimension reports `pass`, `partial`, or `fail`. A PR can pass tests and still fail on `traceability` or `acceptance_criteria` — those dimensions are not gated by test results.

### Verification gates and the AC + traceability checks

Two of the five dimensions — `acceptance_criteria` and `traceability` — are produced by this skill, not the reviewer subagent. Their full procedure (per-criterion AC verification, the four traceability checks, the refactor/chore exemption, and the reviewer-category → dimension mapping) lives in `references/verification-checks.md`. **Read that file and apply it now**, before aggregating the cycle report.

The gating rules that the rest of this skill depends on — keep these in mind here and enforce them in the Review Loop below:

- `review.require_acceptance_criteria_check` (default `true`) gates the AC check; `review.require_traceability_check` (default `true`) gates traceability. When either is `false`, that dimension reports `pass — verification disabled` and never blocks soft-pass.
- **Any `acceptance_criteria: fail`** (a criterion the PR does not satisfy) → fixable issue in Step 6, `category: acceptance_criteria`. **Hard-blocks** soft-pass.
- **`Closes #{N}` absent** (traceability check 1, unless the PR is refactor/chore-exempt) → fixable issue in Step 6, `category: traceability`, suggested fix "Add `Closes #{N}` to the PR body." **Hard-blocks** soft-pass.
- All other traceability outcomes (missing commit ref, missing Decision Record on a human-authored PR, etc.) report `partial` and do **not** block.

These two hard-blocks are the issue #36 contract: a PR can pass tests and still be blocked on `acceptance_criteria: fail` or a missing `Closes #N`.

---

## Step 4 — Run Tests & Build [4/7]

### Build check

Detect and run the project's build system:

| Build system | Detection | Command |
|-------------|-----------|---------|
| Node.js (TS) | `tsconfig.json` | `npx tsc --noEmit` |
| Node.js (JS) | `package.json` build script | `npm run build` |
| Python | `pyproject.toml` | `python -m compileall` |
| Go | `go.mod` | `go build ./...` |
| Rust | `Cargo.toml` | `cargo build` |

### Run test suite

Detect and run all test types:

1. **Unit tests** — `pytest`, `npm test`, `go test ./...`, etc.
2. **Integration tests** — if integration test directory/config exists
3. **E2e tests** — if e2e framework exists (playwright, cypress, etc.)

Timeout: `review.test_timeout` seconds (default: 300).

```
[4/7] Test         ✓ build ok, {N} tests passed
```

Or if failures:
```
[4/7] Test         ✗ {N} tests failed
                     {brief failure summary}
```

---

## Step 5 — Check CI Status [5/7]

Poll GitHub Actions / CI status for the PR:

```bash
gh pr checks {N} --json name,state,bucket
```

### Polling behavior

1. Check immediately after tests
2. If checks are still running, poll every `review.ci_poll_interval` seconds
3. Timeout after `review.ci_timeout` seconds

### CI results

**All checks passed:**
```
[5/7] CI Status    ✓ all checks passed
```

**Checks failed:**
```
[5/7] CI Status    ✗ {N} checks failed
                     {check_name}: {bucket}
```

Extract failure details from the CI log:
```bash
gh run view {run_id} --log-failed
```

**Checks still running after timeout:**
```
[5/7] CI Status    ⚠ checks still running after {timeout}s
```
In interactive mode: ask to wait more or proceed.
In auto mode: proceed — the next cycle will re-check.

**No CI configured:**
```
[5/7] CI Status    ○ no CI checks configured
```

---

## Step 6 — Fix Issues [6/7]

Collect issues from Steps 3-5, but **only fix issues with `action: "fix"`**. Issues with `action: "note"` are reported in the summary but do not trigger a fix cycle. This is the key token optimization — note-only issues (medium code_quality, test_coverage suggestions) are skipped.

- Code review issues with `action: "fix"` (from the reviewer agent — `correctness`, `maintainability`, `safety` dimensions)
- UI/UX issues with `action: "fix"` (from the UI reviewer when UI work was detected — `category: ui_ux`, folded under `maintainability`)
- Acceptance-criteria failures (from Step 3 per-criterion verification — one fixable issue per `fail` criterion, `category: acceptance_criteria`)
- Traceability failures on `Closes #{N}` (from Step 3 traceability checks — `category: traceability`, suggested fix: edit the PR body to add the link)
- Test failures (from Step 4)
- CI failures (from Step 5)

Acceptance-criteria fixes typically require code changes (the criterion is unmet); traceability `Closes #{N}` fixes require a PR-body edit via `gh pr edit {N} --body`. Apply both kinds of fixes, then commit and push as usual.

### If no fixable issues

```
[6/7] Fix          ○ no fixable issues (noted: {note_count})
```
Exit the loop — PR passes the soft-pass condition.

### If fixable issues found

Delegate fixes to the fixer subagent (`references/agents/fixer.md`) — never apply code changes in the main skill context — and reuse the same fixer across cycles when possible. The fixer reads affected files, applies targeted changes, runs the mandatory pre-commit security scan from `references/docs/pre-commit-security.md` against the staged set (real secrets block the commit), then commits. The main agent collects the fixer's JSON result and pushes any commits (`git push origin {branch_name}`); unresolved blocking findings carry to the next cycle. The exact spawn variables and `Agent(...)` call are in `references/review-loop-mechanics.md`.

```
[6/7] Fix          ✓ fixed {N} issues (noted: {note_count} — not fixed)
```

Track what was fixed and what was noted:
```
Cycle {N}:
  ✗ {fixable_count} fixable issues found
  ✓ Fixed: [category] description (file:line)
  ✓ Fixed: [category] description (file:line)
  ○ Noted: [category] description (file:line) — medium, not blocking
```

---

## Review Loop

After Step 6, go back to Step 3 — but reuse the same reviewer agent via `SendMessage` (not a fresh spawn). Only spawn fresh for the confirmation pass.

**Loop controls:**
- **Max cycles:** `review.max_cycles` (default: 3)
- **Agent reuse:** Cycles 2+ reuse the existing reviewer and fixer agents. Fresh spawn only for the confirmation pass after fixer reports zero issues.
- **Soft pass (default):** Stop when ALL of the following hold: zero `action: "fix"` issues remain (across all five dimensions, including `acceptance_criteria` and `traceability` failures) AND tests pass AND CI passes AND traceability is not `fail`. Medium "note" issues (≤ 2) and `partial` dimensions are allowed — they don't block the pass.
- **Hard-block conditions:** `traceability: fail` (e.g., `Closes #{N}` missing) and any `acceptance_criteria: fail` always block, even if every other dimension is clean. Tests passing does not override these — that is the explicit contract from issue #36. The block is gated on `review.require_traceability_check` and `review.require_acceptance_criteria_check`: when either flag is `false`, the corresponding dimension is reported as `pass — verification disabled` and never blocks soft-pass. Both flags default to `true`. A narrower opt-out applies to refactor/chore PRs (see *Refactor/chore exemption* in Step 3): a matching PR reports `traceability: pass — exempt` and is not blocked, even though the four checks (minus check 1) still run.
- **Confirmation pass:** When the fixer reports all fixed, spawn one fresh reviewer for unbiased verification. If clean → PASS. If new issues → back to existing fixer (counts as a cycle).
- **Exit on stagnation:** If the same issues appear in 2 consecutive cycles, stop and report
- **Review-only mode:** Run one cycle of Steps 3-5 only, never fix or loop

---

## Step 7 — Summary Report [7/7]

Print a structured step-by-step summary showing the review pipeline results. Use the templates in `references/report-templates.md`:

- *Summary — Clean PR* — all checks pass, may include soft-pass notes
- *Summary — PR With Remaining Issues* — review couldn't clear everything within `review.max_cycles`
- *Auto-Merge (auto mode only)* — post-report squash merge and block-on-failure handling

In interactive mode: never auto-merge — just report status.

**Review-only mode (`--review-only`):** run Steps 1-5 once, skip Step 6, report in Step 7 — never loop, fix, or merge.

---

## GitHub CLI Convention

Every `gh` command uses `--json` with explicit field selection. Never parse text output.

## Terminal Output

Follow DESIGN.md symbol vocabulary:
- Step counter: `[N/7]`
- Symbols: `●` progress, `✓` success, `✗` failure, `◆` header, `⚠` warning, `○` info
- Two-space indent, `┄` separators, URLs on own line, max 80 chars

## Error Handling

All errors use rich format from `references/error-messages.md`:
```
✗ Short error description

  To fix:  <actionable command>
```

## Expected Output

A clean review prints the 7-step tracker and a summary — see the *Expected Inline Output* example in `references/report-templates.md`.

## Edge Cases

- **No PR for current branch** — the skill asks for an explicit `<N>` or stops cleanly.
- **CI still running** — waits up to `review.ci_timeout`, then prints the current state and stops without merging.
- **Critical issue unresolvable after 3 cycles** — stops, prints remaining issues, does not merge, asks the user to take over.
- **Merge conflict with base** — prints the exact rebase command and stops.

## Additional Resources

- **`references/agents/code-reviewer.md`** — Review subagent prompt
- **`references/agents/ui-reviewer.md`** — UI/UX review subagent prompt (Step 3, auto-detected)
- **`references/agents/fixer.md`** — Fix subagent prompt
- **`references/verification-checks.md`** — AC + traceability check procedure (Step 3)
- **`references/review-loop-mechanics.md`** — reviewer/fixer spawn + reuse mechanics
- **`references/report-templates.md`** — Step 7 summary templates, auto-merge flow, expected inline output
- **`references/error-messages.md`** — Error catalog
- **`references/docs/naming-conventions.md`** — Naming conventions
- **`DESIGN.md`** — Terminal output style guide
