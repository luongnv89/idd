# Report and PR Body Templates

Templates for the PR body, the step-by-step final report, and the expected pipeline output. SKILL.md references this file at the relevant steps — do not inline these templates back into SKILL.md.

## PR Body Template (Step 5 — Deliver)

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

The PR title follows `{type}({scope}): {description} (#{issue_number})` — see `docs/naming-conventions.md`.

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
