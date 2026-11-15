# Report examples — /issue-resolver

## Expected Inline Pipeline Output

A successful resolve prints the full 6-step tracker, then the single Closing
Summary block — per-step status appears only in the tracker, the PR reference only
in the closing block:

```
  ◆ Resolve Pipeline
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  [0/5] Preflight    ✓ issue #42 open, not yet resolved, effort: full
  [1/5] Research     ✓ read 12 files, complexity: medium
  [2/5] Plan         ✓ option 2 selected: balanced refactor
  [3/5] Implement    ✓ 3 files changed, 8 unit tests, 2 e2e tests
  [4/5] QA           ✓ clean after 2 cycles
  [5/5] Deliver      ✓ PR #87 created
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:       DONE — issue #42 resolved (low risk)
  Evidence:     final tests 14 passed@3f9c2a1
                secret scan pass (ref:origin/main) · QA review clean
                run log appended
  Uncertainty:  browser UI review skipped (no running app)
  Decision:     No approval needed.
  Next action:  /issue-pr-review 87

  PR #87: fix(auth): resolve mobile auth redirect (#42)
  https://github.com/user/repo/pull/87
  Closes #42
```

The tracker metrics — files read, complexity, option, files changed, test counts,
QA cycles — stay on the `[N/5]` lines above. Below the separator are only the
*Review contract* rows, the `risk_rating`, and the PR reference.

## Format rule

The default format is the terminal closing block, after the `[N/5]` tracker. The
PR body is the durable Markdown record. If the user asks for another format (for
example a Markdown summary or JSON), render it from the same facts and keep the
`Result`, `Evidence`, `Uncertainty`, `Decision` and `Next action` rows. If the
host cannot render the requested format, say so and print the terminal block.

## Evaluate report understanding

Grade actual outputs against these criteria as well as correctness:

| Criterion | Observable check |
|---|---|
| Result is findable | The first row states `DONE`, `PARTIAL` or `BLOCKED` and the PR or stop reason, without reading the tracker or logs. |
| Facts and assumptions are separate | Observed checks (suite run, secret scan, `gh pr create` URL) are distinct from unverified ACs, skipped legs and `risk_rating`. |
| Claims are traceable | Each test claim names its count and SHA; `already_resolved` names the fixing commit; `BLOCKED` names the failed check; `PARTIAL` names the residual gap. A created PR is not reported as merged. |
| Next decision is clear | The output says `No approval needed.` and names the next action. |

When running behavioral evaluations, include a delivered PR, a PR with residual
QA findings, a blocked secret scan, and an `already_resolved` issue, and grade
each closing block against all four rows. Ask human reviewers the matching four
questions and record their answers in the eval case's `human_review` block.
Missing, blank, or nonresponsive feedback leaves human understanding
unconfirmed; agent inspection cannot confirm it.
