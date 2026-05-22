---
name: issue-pr-review
description: "Review a PR end-to-end with CI checks, fix cycles, and optional auto-merge. Use for PR review, cleanup, or readiness checks. Don't use for creating PRs, raw issue analysis, or non-PR code review."
license: MIT
compatibility: Requires git and GitHub CLI (gh) with authentication. Self-contained — uses shared agents from shared/agents/.
effort: high
metadata:
  version: 0.5.0
  creator: Luong NGUYEN <luongnv89@gmail.com>
---

# /issue-pr-review [PR_NUMBER]

Review a pull request end-to-end — analyze, test, fix, check CI, repeat until clean.

## Invocation

| Invocation | Mode | What happens |
|------------|------|--------------|
| `/issue-pr-review <N>` | interactive | Review PR #N, report findings |
| `/issue-pr-review <N> --auto` | auto-pilot | Review, fix, and auto-merge when clean |
| `/issue-pr-review` | detect | Auto-detect PR for current branch |
| `/issue-pr-review --review-only` | read-only | Review and report, never fix or merge |

The `--auto` flag is set automatically when invoked by `/auto-pilot`.

In auto mode, export `IDD_AUTO_MODE=1` before any shell snippet that consults it — the pre-commit security scan reads this to switch from prompt-on-warning to log-and-continue (see `docs/pre-commit-security.md`).

## Prerequisites

1. Confirm git repository: `git rev-parse --git-dir`
2. Confirm `gh` is installed and authenticated: `gh auth status`

## Repo Sync Before Edits (mandatory)

Before making any fixes, sync with remote using the stash-first pattern (see `docs/sync-conventions.md` for the full convention and recovery procedure):

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
- `review.require_acceptance_criteria_check: true` — when `false`, skip per-criterion AC verification; report acceptance_criteria as `pass` with a "verification disabled" note (never blocks soft-pass). Default `true` preserves the issue #36 contract.
- `review.require_traceability_check: true` — when `false`, skip the four traceability checks; report traceability as `pass` with a "verification disabled" note (never blocks soft-pass). Default `true` preserves the issue #36 contract.
- `review.traceability_exempt_labels: ["refactor", "chore"]` — PR labels that exempt a PR from the `Closes #N` hard-fail (check 1 only; the other three traceability checks still run). Set to `[]` to disable label-based exemption.
- `review.traceability_exempt_pattern: "^\\s*Type:\\s*(refactor|chore)\\s*$"` — case-insensitive multiline regex; if the PR body contains a matching line, the PR is exempt from the `Closes #N` hard-fail (check 1 only). Set to empty string `""` to disable pattern-based exemption.

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

Step 2 (Pre-pass) runs once before the review loop. Steps 3-6 repeat up to `review.max_cycles` times (default: 3). Step 7 runs once at the end.

### Token optimization strategy

The pipeline is designed to minimize LLM token usage:

1. **Script pre-pass (Step 2)** — Lint, format, and test tools run via shell scripts, not LLM agents. Auto-fixes mechanical issues for free (zero tokens). This handles the bulk of lint/format violations that previously consumed full review cycles.
2. **Agent reuse (Steps 3-6)** — The same reviewer and fixer agents are reused across fix cycles via `SendMessage`. Only the final confirmation pass spawns a fresh agent. This cuts agent spawn cost from 2 per cycle to ~1.3 average (reuse in cycles 2-3, fresh only for confirmation).
3. **Severity-based filtering** — The code reviewer classifies each issue with `action: "fix"` or `action: "note"`. Only "fix" issues trigger a fix cycle. "Note" issues are reported but don't consume tokens.
4. **Soft pass condition** — The review passes when zero "fix" issues remain, even if some medium "note" issues exist. This avoids burning cycles on diminishing-return fixes.
5. **Reduced cycles (3 max)** — With mechanical issues handled by scripts and only critical issues triggering fixes, 3 LLM cycles are sufficient.

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

If any files were modified by the auto-fix tools, run the pre-commit security
scan before staging (see the pre-commit security conventions reference at
`docs/pre-commit-security.md` — that document is authoritative; the snippet
below mirrors its Primary Pattern). Real secrets block; warnings prompt for
confirmation in interactive mode and log-and-continue in auto mode.

```bash
# Pre-commit security scan — mirrors the Primary Pattern in the
# pre-commit-security conventions reference. Set IDD_AUTO_MODE=1 in auto mode.
files="$(git status --porcelain | awk '{print $2}')"
secrets_found=0
warnings=()
if printf '%s\n' "$files" | grep -E -q '(^|/)\.env($|\.)|\.key$|\.pem$|credentials\.json$|secrets\.ya?ml$|id_rsa($|\.pub$)|\.p12$|\.pfx$|\.cer$'; then
  echo "✗ Secret-bearing file in working tree."
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
  printf '%s\n' "$f" | grep -E -q "$junk" && warnings+=("⚠ Build artifact staged: $f")
done <<< "$files"
case "$(git rev-parse --abbrev-ref HEAD)" in
  main|master|production|release) warnings+=("⚠ On protected branch — confirm intentional") ;;
esac
[ "$secrets_found" = 1 ] && { echo "✗ Pre-commit security scan blocked. See pre-commit-security conventions reference."; exit 1; }
if [ "${#warnings[@]}" -gt 0 ]; then
  printf '%s\n' "${warnings[@]}"
  if [ "${IDD_AUTO_MODE:-0}" = "1" ]; then
    echo "○ Warnings logged — proceeding (auto mode)."
  else
    printf "Proceed anyway? [y/N] "; read -r reply
    case "$reply" in y|Y|yes|YES) echo "○ Continuing despite warnings." ;; *) echo "✗ Stopped."; exit 1 ;; esac
  fi
fi
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

### Agent reuse strategy

To minimize token usage, the review loop **reuses the same reviewer agent** across fix cycles instead of spawning a fresh one each time. The reviewer already has the codebase context loaded, so subsequent reviews are cheaper.

- **Cycle 1:** Spawn a new reviewer agent (cold start — reads diff, files, context)
- **Cycles 2-3:** Send the reviewer a follow-up message via `SendMessage` asking it to re-review the diff after fixes were applied. The agent retains its context and only needs to re-read the updated diff, not re-discover the entire codebase.
- **Confirmation pass:** After the fixer reports all issues resolved, spawn a **fresh confirmation reviewer** (separate agent, no memory of prior cycles) for an unbiased final check. This is the only fresh spawn after cycle 1.

This trades perfect independence between cycles (which rarely matters in practice — the reviewer was already correct about what the issues were) for significant token savings. The fresh confirmation pass at the end catches anything the reused reviewer might have missed.

### Cycle 1 — Initial review

Read `shared/agents/code-reviewer.md` for the full prompt template.

Spawn a new reviewer agent (cold start):

```python
Agent(
  description="Review PR #N",
  prompt=<code-reviewer.md prompt with {variables} replaced>,
  subagent_type="general-purpose"  # NOT "code-reviewer"
)
```

Pass to the reviewer:
- `branch_name`: PR head branch
- `base_branch`: PR base branch
- `pr_context`: PR title and body
- `diff_command`: `gh pr diff {N}`

### Cycles 2+ — Re-review via SendMessage

Send a message to the existing reviewer agent:
```
The fixer applied changes. Re-review the PR diff to check if the issues were resolved and find any new issues.

Run: {diff_command}

Return the same JSON format as before.
```

### Confirmation pass

After the fix cycle reports zero fixable issues, spawn a **fresh** confirmation reviewer (new agent, no memory of prior cycles):

```python
Agent(
  description="Confirmation review for PR #N",
  prompt=<code-reviewer.md prompt with {variables} replaced>,
  subagent_type="general-purpose"  # NOT "code-reviewer"
)
```

If it finds new fixable issues, they go back to the existing fixer. If it confirms clean, the PR passes.

```
[3/7] Review       ✓ correctness:pass  ac:pass  trace:pass  maint:partial  safety:pass
                     {fixable_count} fixable, {note_count} noted
```

Also fetch linked issues for acceptance criteria verification:
```bash
gh issue view {linked_issue} --json number,title,body,labels
```

Parse the `## Acceptance Criteria` section into one entry per checklist item and check each criterion against the PR changes — see *Acceptance-criteria verification (per criterion)* below.

### Order within Step 3

Within a single review cycle, the work runs in this order:
1. Spawn (or re-message) the reviewer subagent and collect its findings.
2. Run per-criterion acceptance-criteria verification against the linked issue.
3. Run the four traceability checks against the PR body and commit history.
4. Aggregate reviewer findings + AC results + traceability results into the five user-facing dimensions for the cycle report.

### Dimensional review output

Step 3 produces a single review verdict organized into **five dimensions**. The reviewer subagent reports findings against its own internal categories (correctness, test_coverage, code_quality, security, edge_cases); this skill maps those findings into the user-facing dimensions and adds two dimensions the reviewer does not produce (acceptance criteria, traceability). Mapping is fixed:

| User-facing dimension | Source | Failure means |
|----------------------|--------|---------------|
| `correctness` | reviewer category `correctness` | logic, off-by-one, race conditions |
| `acceptance_criteria` | per-criterion verification (this skill) | one or more criteria report `fail` |
| `traceability` | PR-body and commit-history scan (this skill) | issue-to-code link is broken |
| `maintainability` | reviewer categories `code_quality` + `test_coverage` | dead code, untested paths, complex logic |
| `safety` | reviewer categories `security` + `edge_cases` | injection, auth bypass, unsafe nulls, crash paths |

Each dimension reports `pass`, `partial`, or `fail`. A PR can pass tests and still fail on `traceability` or `acceptance_criteria` — those dimensions are not gated by test results.

### Verification gates

Two `.gitissue.yml` flags decide whether the acceptance-criteria and traceability checks run at all:

| Flag | Default | When `true` (default) | When `false` |
|------|---------|----------------------|--------------|
| `review.require_acceptance_criteria_check` | `true` | Run per-criterion verification described below; any `fail` blocks soft-pass. | Skip the check entirely. Report `○ acceptance_criteria: pass` with the explicit note `verification disabled (review.require_acceptance_criteria_check: false)`. Never blocks soft-pass; emit no fixable issues for this dimension. |
| `review.require_traceability_check` | `true` | Run the four traceability checks below; missing `Closes #N` blocks soft-pass. | Skip the check entirely. Report `○ traceability: pass` with the explicit note `verification disabled (review.require_traceability_check: false)`. Never blocks soft-pass; emit no fixable issues for this dimension. |

Both default to `true`, which preserves the issue #36 contract verbatim. Setting either flag to `false` is an explicit opt-out — the corresponding hard-block conditions in *Loop controls* below no longer apply for that dimension.

A separate, narrower opt-out exists for refactor/chore PRs (see *Refactor/chore exemption* below). It relaxes only check 1 (`Closes #N`) for the matching PR; the other three traceability checks still run.

### Acceptance-criteria verification (per criterion)

> Run only when `review.require_acceptance_criteria_check` is `true`. When `false`, skip this entire subsection and emit `○ acceptance_criteria: pass — verification disabled (review.require_acceptance_criteria_check: false)`.

Fetch the linked issue and parse its `## Acceptance Criteria` section into individual checklist items. For each criterion, evaluate against the PR diff and produce one of three statuses:

| Status | When |
|--------|------|
| `pass` | The PR demonstrably satisfies the criterion. Evidence is required: a file path with line range, a test name, or a one-line description of how the change fulfills the criterion. |
| `fail` | The PR does not satisfy the criterion. Evidence is required: what's missing or what contradicts the criterion. |
| `unverified` | The criterion cannot be verified from the diff alone (e.g., needs production validation, manual user testing, or behavior outside the change set). Explanation is required. |

Output a structured block:

```
○ Acceptance Criteria
  | # | Criterion | Status | Evidence |
  |---|-----------|--------|----------|
  | 1 | "{criterion text}" | pass | tests/foo.test.ts: case 'rejects empty' |
  | 2 | "{criterion text}" | fail | exclusion list still hard-codes /login |
  | 3 | "{criterion text}" | unverified | needs manual mobile-device test |
```

If the issue has no acceptance criteria:

```
○ Acceptance Criteria — none defined; manual review recommended
```

**Pass/partial/fail rule for the dimension:**
- All criteria `pass` → ✓ acceptance_criteria: pass
- Any criterion `fail` → ✗ acceptance_criteria: fail (blocks soft-pass; treat as fixable)
- No fails, but at least one `unverified` → ⚠ acceptance_criteria: partial (does not block soft-pass; surfaced in report)
- No criteria defined → ○ acceptance_criteria: pass (with the "manual review recommended" note)

Each `fail` criterion becomes a fixable issue in Step 6 with `category: acceptance_criteria`, `action: fix`, evidence as the description, and the criterion text as the suggested fix target.

### Traceability checks

> Run only when `review.require_traceability_check` is `true`. When `false`, skip this entire subsection and emit `○ traceability: pass — verification disabled (review.require_traceability_check: false)`.

Per the dual-write rule (see *Analysis Artifacts and Durable Memory* in `docs/idd-methodology.md`), the durable analysis signal must survive the squash-merge into git history. Run the following four checks against the PR body and the commits in the PR:

1. **Issue link** — PR body contains `Closes #{N}`, `Fixes #{N}`, or `Resolves #{N}` for the linked issue. Detected with the same regex used by GitHub itself: `(?i)(close[sd]?|fix(e[sd])?|resolve[sd]?)\s+#\d+`. See *Refactor/chore exemption* below — the `Closes #N` requirement is relaxed for refactor/chore PRs (the other three checks still run).
2. **Commit references issue** — at least one commit between base and head references the issue number:
   ```bash
   git log "{base_branch}..{head_branch}" --grep="#{N}" --oneline
   ```
   The reference may live in the subject or body. A reference inside a `Co-authored-by:` trailer does not count.
3. **Durable analysis fields in PR body** — the PR body contains a `## Decision Record` section with the five stable labels (`Root cause`, `Options considered`, `Options rejected`, `Selected option`, `Residual risk`) and a `## Acceptance Criteria Verification` section (table or the explicit `No acceptance criteria defined` note). The labels are the contract — match them as exact strings, do not rewrite.
4. **Squash-commit-body assumption** — under squash-merge (the project default per `docs/idd-methodology.md`), GitHub copies the PR body verbatim into the commit message. Treat passing check 3 as evidence the squash commit will carry the durable summary; no separate check is needed pre-merge. Note this assumption explicitly in the report so reviewers know what is and is not verified.

**Pass/partial/fail rule for the dimension:**

| Outcome | Conditions | Status |
|---------|-----------|--------|
| All four checks pass | Closes #N + commit ref + Decision Record + AC Verification block all present | ✓ traceability: pass |
| `Closes #{N}` absent on a refactor/chore-exempt PR | check 1 skipped via the *Refactor/chore exemption* below; checks 2-4 still run | ○ traceability: pass — exempt (refactor/chore PR; no Closes #N required), with any check 2-4 partial findings appended |
| `Closes #{N}` absent | check 1 fails (regardless of other checks) | ✗ traceability: fail (blocking — see below) |
| Decision Record absent on a human-authored PR | check 3 partially fails: PR was not produced by `/issue-resolver` and has no Decision Record | ⚠ traceability: partial — "PR not produced by `/issue-resolver`; Decision Record absent" |
| Commit reference absent | check 2 fails but check 1 passes (PR body has Closes #N but no commit references the issue) | ⚠ traceability: partial — "no commit references #{N}" |
| Acceptance Criteria Verification block absent on a `/issue-resolver` PR | check 3 fails on a PR that does include a Decision Record | ⚠ traceability: partial — "Acceptance Criteria Verification block missing" |

The `Closes #{N}` failure is the only traceability outcome that **blocks** the soft-pass. All other partial outcomes are reported but do not block. This matches issue #36's contract: a PR missing `Closes #N` reports a traceability failure even if tests pass; a human-authored PR without a Decision Record reports `partial`, not `fail`.

When traceability fails on `Closes #{N}`, emit a fixable issue in Step 6 with `category: traceability`, `action: fix`, suggested fix: "Add `Closes #{N}` to the PR body."

### Refactor/chore exemption

Some PRs aren't tied to a single tracked issue — skill quality passes, dependency bumps, doc-only updates. Forcing each one to open a tracking issue purely to satisfy the `Closes #N` gate is workflow ceremony with no information gain. To accommodate this, check 1 (`Closes #N`) is **skipped** when either of the following holds:

1. The PR has any label whose name appears in `review.traceability_exempt_labels` (default: `["refactor", "chore"]`). Match is exact and case-sensitive against GitHub label names.
2. The PR body contains a line matching `review.traceability_exempt_pattern` (default: `"^\\s*Type:\\s*(refactor|chore)\\s*$"`, case-insensitive, evaluated multiline-anchored against the body). The line may appear anywhere in the body. The default is shown in YAML double-quoted form, so `\\s` is the correct value to copy into `.gitissue.yml`.

The exemption applies **only to check 1**. Checks 2-4 (commit reference, Decision Record, Acceptance Criteria Verification block) still run; their absence is reported as `partial`, never `fail`. Note that check 2 (`git log --grep="#{N}"`) is well-defined only when there is a tracked issue number; an exempt refactor/chore PR with no linked issue has no `#{N}` to grep for, so check 2 is reported as `n/a — no linked issue`, not `partial`. When an exempt PR _does_ have a linked issue (e.g., a refactor scoped under a tracking ticket) but no commit references it, the report is `○ pass — exempt; no commit references #{N} (note)`, not `fail`.

Report wording:

```
traceability:        ○ pass — exempt (refactor/chore PR; no Closes #N required)
```

If checks 2-4 produce partial findings on an exempt PR, append them as in the human-authored case:

```
traceability:        ○ pass — exempt (refactor/chore PR; no Closes #N required);
                       no commit references #{N}
```

To **disable** the exemption entirely (restore the strict issue #36 behavior), set `traceability_exempt_labels: []` and `traceability_exempt_pattern: ""` in `.gitissue.yml`.

The exemption check runs before the four traceability checks; if a PR matches, log which mechanism matched (label name or pattern) so reviewers can audit the decision in the report.

### Reviewer call-out for the other three dimensions

Pass the reviewer the issue body alongside the diff (the existing `pr_context` field is fine). The reviewer's JSON output already partitions findings by category — at the end of Step 3, this skill aggregates:

- `correctness` findings → `correctness` dimension
- `code_quality` + `test_coverage` findings → `maintainability` dimension
- `security` + `edge_cases` findings → `safety` dimension

Each dimension's status is computed from its findings:
- Any `action: fix` finding in the dimension → ✗ `fail`
- Only `action: note` findings → ⚠ `partial`
- No findings → ✓ `pass`

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

For each issue where `action: "fix"`:
1. Read the affected file
2. Apply the fix
3. Stage: `git add <specific-file>`

After all fixes, run the pre-commit security scan against the staged set before
committing (see the pre-commit security conventions reference at
`docs/pre-commit-security.md` — that document is authoritative; the snippet
below mirrors its Primary Pattern). Real secrets block; warnings prompt for
confirmation in interactive mode and log-and-continue in auto mode.

```bash
# Pre-commit security scan — mirrors the Primary Pattern in the
# pre-commit-security conventions reference. Set IDD_AUTO_MODE=1 in auto mode.
files="$(git diff --cached --name-only)"
secrets_found=0
warnings=()
if printf '%s\n' "$files" | grep -E -q '(^|/)\.env($|\.)|\.key$|\.pem$|credentials\.json$|secrets\.ya?ml$|id_rsa($|\.pub$)|\.p12$|\.pfx$|\.cer$'; then
  echo "✗ Secret-bearing file staged."
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
  printf '%s\n' "$f" | grep -E -q "$junk" && warnings+=("⚠ Build artifact staged: $f")
done <<< "$files"
case "$(git rev-parse --abbrev-ref HEAD)" in
  main|master|production|release) warnings+=("⚠ On protected branch — confirm intentional") ;;
esac
[ "$secrets_found" = 1 ] && { echo "✗ Pre-commit security scan blocked. See pre-commit-security conventions reference."; exit 1; }
if [ "${#warnings[@]}" -gt 0 ]; then
  printf '%s\n' "${warnings[@]}"
  if [ "${IDD_AUTO_MODE:-0}" = "1" ]; then
    echo "○ Warnings logged — proceeding (auto mode)."
  else
    printf "Proceed anyway? [y/N] "; read -r reply
    case "$reply" in y|Y|yes|YES) echo "○ Continuing despite warnings." ;; *) echo "✗ Stopped."; exit 1 ;; esac
  fi
fi
```

4. Commit: `fix({scope}): address review feedback` (append `(#{linked_issue})` only if a linked issue exists)
5. Push: `git push origin {branch_name}`

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

---

## Review-Only Mode

When invoked with `--review-only`:

1. Run Steps 1-5 once (PR info, pre-pass, review, test, CI check)
2. Skip Step 6 (no fixes)
3. Report findings in Step 7
4. Never loop, never fix, never merge

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
- **Review-only mode (`--review-only`)** — never fixes or merges, always reports.

## Additional Resources

- **`shared/agents/code-reviewer.md`** — Review subagent prompt
- **`references/report-templates.md`** — Step 7 summary templates, auto-merge flow, expected inline output
- **`references/error-messages.md`** — Error catalog
- **`docs/naming-conventions.md`** — Naming conventions
- **`DESIGN.md`** — Terminal output style guide
