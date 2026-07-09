# Report and PR Body Templates

Templates for the PR body, the single closing summary, and the expected pipeline output. SKILL.md references this file at the relevant steps — do not inline these templates back into SKILL.md.

## PR Body Template (Step 5 — Deliver)

This template is the load-bearing artifact for durable project memory. Under squash-merge, GitHub copies the PR body verbatim into the commit message that lands on the default branch, so every section here is preserved in `git log -p` after merge. Repos using merge-commit or rebase-merge keep this content only on GitHub. See *Analysis Artifacts and Durable Memory* in `references/docs/idd-methodology.md`.

```markdown
Closes #{issue_number}

## Summary

{One-paragraph summary}

## Approach

{Selected option name and description}

## Decision Record

- **Root cause:** {one-paragraph diagnosis from analysis Step 6}
- **Options considered:** Option 1 — {name}; Option 2 — {name}; Option 3 — {name}
- **Options rejected:** Option 1 — {one-line reason}; Option 3 — {reason}
- **Selected option:** Option {N} — {name}
- **Residual risk:** {what remains uncertain or accepted as known limitation, or "none identified"}
- **Design-confirm:** {high-complexity issues only — "confirmed Option {N} at design-confirm checkpoint (complexity: {level})" in interactive mode, or "auto-selected Option {N} (complexity: {level})" in auto mode; omit this line for trivial/low/medium complexity}
- **Reproduction:** {bug issues only — success: `<command>` confirmed red for the stated reason → regression test `<path>` (or "manual — no seam"); degraded: `not reproduced — <one-line reason> (fix applied without confirmed red; criterion marked unverified)`; omit for non-bug issues}

Analyzed at: `{branch} @ {commit_sha_short}` ({YYYY-MM-DD})

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

## Acceptance Criteria Verification

| Criterion | Status | Evidence |
|-----------|--------|----------|
| {criterion text from issue body} | pass | {short pointer — file/line, test name, manual check} |
| {criterion text from issue body} | unverified | {explanation — out of scope, manual review needed} |

Use `pass`, `fail`, or `unverified` per criterion. Always cite evidence (a file path, a test name, or a one-line explanation). If the issue has no acceptance criteria, replace the table with `> **Note:** No acceptance criteria defined — manual review recommended.`

**Bug issues — reproduction evidence.** When the issue `type` is `bug`, the Evidence column must cite the reproduction command from the Step 3 bug-verification checkpoint (`references/bug-verification.md`), not just a checkmark. Format the cell as `Verified red: <command> → fixed → <regression test path>` (or `… → manual repro, no seam` when no test seam exists). If the symptom could not be reproduced, mark that criterion `unverified` and note `not reproduced: <reason>`.
```

The PR title follows `{type}({scope}): {description} (#{issue_number})` — see `references/docs/naming-conventions.md`.

### Lifting the Decision Record

Treat analysis JSON as **fresh** only when `git_state.commit_sha` equals the synced base SHA for this run. When fresh, you may lift `root_cause`, `options_considered`, and `git_state` from the cache; **`selected_option` and `options_rejected` MUST always reflect this run's Step 2 synthesizer outcome** (never a stale cache pick). Field labels are stable across skills — do not rename them.

If no analysis JSON exists (e.g., resolver was invoked without prior analysis), synthesize the same five core fields from the resolver's own Step 1 (Research) and Step 2 (Plan) findings, and use the synced base SHA as `commit_sha_short`. (For bug issues the sixth `Reproduction` line is added separately from the implementer's returned reproduction block — see the bug-verification checkpoint, not the analysis JSON.) Either source produces the same template — what matters is that the durable analysis signal lands in the PR body, where squash-merge will carry it into git history.

## Closing Summary

The closing summary is the **single** end-of-run block. It does **not** repeat
anything the live `[N/5]` tracker already showed — neither per-step pass/fail nor
the per-step metrics (files read, complexity, option, files changed, test counts,
QA cycles all appear on the tracker lines, see *Expected Inline Pipeline Output*).
The closing block carries **only facts the tracker never printed**: the overall
outcome line, the `risk_rating` (Plan never surfaces it on its tracker line), and
the single PR reference (number, title, URL, `Closes #N`). Print it **once**,
immediately after the tracker's `[5/5]` line — do not also print a separate
step-by-step report. Pick the variant that matches the run's outcome.

> Why so spare: the tracker is the recap. Restating its metrics here is the
> duplication #165 removed — keep this block to the outcome, the one un-shown
> metric (risk), and the PR reference.

### Successful Resolution

Every step passed:

```
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  ✓ Issue #{issue_number} resolved ({risk_rating} risk)

  PR #{pr_number}: {pr_title}
  https://github.com/owner/repo/pull/{pr_number}
  Closes #{issue_number}
```

### Resolution With Warnings

When any step had problems (e.g., QA could not fully clean up, tests still flaky).
The outcome line names the residual issue — the remaining-count and cycle total
are genuinely new (the tracker's `[4/5] QA` line would have shown the in-progress
state, not the final unresolved count):

```
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  ⚠ Issue #{issue_number} resolved — manual review recommended ({risk_rating} risk)
    ⚠ QA: {remaining} issues remain after {cycles} cycles

  PR #{pr_number}: {pr_title}
  https://github.com/owner/repo/pull/{pr_number}
  Closes #{issue_number}
```

### Already Resolved

Step 0 or Step 1 detected the issue was already closed — no PR is created, so the
PR reference is omitted entirely. The fixing SHA is the one new fact:

```
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  ○ Issue #{issue_number} already resolved — closed, no PR needed
    already fixed by {sha7}
```

## Expected Inline Pipeline Output

A successful resolve prints the full 6-step tracker, then the single Closing
Summary block — per-step status appears only in the tracker, the PR reference only
in the closing block:

```
  ◆ Resolve Pipeline
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  [0/5] Preflight    ✓ issue #42 open, not yet resolved
  [1/5] Research     ✓ read 12 files, complexity: medium
  [2/5] Plan         ✓ option 2 selected: balanced refactor
  [3/5] Implement    ✓ 3 files changed, 8 unit tests, 2 e2e tests
  [4/5] QA           ✓ clean after 2 cycles
  [5/5] Deliver      ✓ PR #87 created
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  ✓ Issue #42 resolved (low risk)

  PR #87: fix(auth): resolve mobile auth redirect (#42)
  https://github.com/user/repo/pull/87
  Closes #42
```

Every metric the old closing block restated — files read, complexity, option,
files changed, test counts, QA cycles — is already on a `[N/5]` tracker line
above. Only the outcome, the `risk_rating`, and the PR reference are new, so only
those appear below the separator.
