# Report and PR Body Templates

Templates for the PR body, the step-by-step final report, and the expected pipeline output. SKILL.md references this file at the relevant steps — do not inline these templates back into SKILL.md.

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
- **Reproduction:** {bug issues only — `<command>` confirmed red for the stated reason → regression test `<path>` (or "manual — no seam"); omit this line for non-bug issues}

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

If a fresh `.gitissue/analysis-<N>.json` exists for this issue, lift its `decision_record` and `git_state` blocks directly into the *Decision Record* section above. Field labels are stable across `/issue-analysis`, `/issue-resolver`, and `/issue-pr-review` because downstream presence checks are string-matched — do not rename them.

If no analysis JSON exists (e.g., resolver was invoked without prior analysis), synthesize the same five fields from the resolver's own Step 1 (Research) and Step 2 (Plan) findings, and use the synced base SHA as `commit_sha_short`. Either source produces the same template — what matters is that the durable analysis signal lands in the PR body, where squash-merge will carry it into git history.

## Final Report — Successful Resolution

```
◆ Issue #{issue_number} — resolved
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Preflight:       ✓ pass
  Research:        ✓ pass ({files_read} files analyzed, {complexity})
  Plan:            ✓ pass ({option_name}, {risk_rating} risk)
  Implement:       ✓ pass ({files_changed} files, {tests_written} tests)
  QA:              ✓ pass ({cycles} cycles, {issues_found} issues fixed)
  Deliver:         ✓ pass (PR #{pr_number} created)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:          DONE

  PR #{pr_number}: {pr_title}
  https://github.com/owner/repo/pull/{pr_number}
  Closes #{issue_number}
```

## Final Report — Resolution With Warnings

When any step had problems (e.g., QA could not fully clean up, tests still flaky):

```
◆ Issue #{issue_number} — resolved with warnings
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Preflight:       ✓ pass
  Research:        ✓ pass ({files_read} files analyzed)
  Plan:            ✓ pass ({option_name})
  Implement:       ✓ pass ({files_changed} files)
  QA:              ⚠ warn ({remaining} issues remain after {cycles} cycles)
  Deliver:         ✓ pass (PR #{pr_number} created)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:          DONE (manual review recommended)

  PR #{pr_number}: {pr_title}
  https://github.com/owner/repo/pull/{pr_number}
  Closes #{issue_number}
```

## Final Report — Already Resolved

```
◆ Issue #{issue_number} — already resolved
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Preflight:       ✓ pass
  Research:        ○ skipped (already fixed by {sha7})
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:          SKIPPED — issue closed
```

## Expected Inline Pipeline Output

A successful resolve prints the full 6-step tracker and ends with the PR URL:

```
  ◆ Resolve Pipeline
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  [0/5] Preflight    ✓ issue #42 open, not yet resolved
  [1/5] Research     ✓ read 12 files, complexity: medium
  [2/5] Plan         ✓ option 2 selected: balanced refactor
  [3/5] Implement    ✓ 3 files changed, 8 unit tests, 2 e2e tests
  [4/5] QA           ✓ clean after 2 cycles
  [5/5] Deliver      ✓ PR #87 created

  ✓ Done — PR #87: fix(auth): resolve mobile auth redirect (#42)
    https://github.com/user/repo/pull/87
    Closes #42
```
