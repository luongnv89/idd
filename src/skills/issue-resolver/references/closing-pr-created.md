# Closing Summary — PR created

Read when Step 5 created a PR. The *Review contract* in
`references/closing-summary.md` applies. The tracker metrics (files read,
complexity, option, files changed, test counts, QA cycles) stay on the `[N/5]`
lines and are not repeated here.

- **Evidence:** the final suite (`{count} passed@{sha7}`, or its skip reason),
  the secret-scan verdict and `policy_source`, the QA verdict, the PR URL that
  `gh pr create` returned, the docs search (*Update documentation*), and the
  run-log write (`appended`, `echoed`, or `fallback`).
- **Uncertainty:** PR-body AC rows not marked `pass`, a skipped browser UI
  review, `resolve.auto_test: false`, a script that degraded to its prose
  procedure, the inline fallback without the Agent tool, a reused analysis
  (`analysis_reuse = fresh` — verified first, not re-derived), the `light`
  profile's single QA cycle, and a resumed run's restored plan and findings.
- **Next action:** `/issue-pr-review {pr_number}` (review, then merge).

## DONE

Every step printed `Result: PASS`:

```
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:       DONE — issue #{issue_number} resolved ({risk_rating} risk)
  Evidence:     final tests {count} passed@{sha7}
                secret scan pass ({policy_source}) · QA review clean
                run log {run_log_state}
  Uncertainty:  {items, or "none identified"}
  Decision:     No approval needed.
  Next action:  /issue-pr-review {pr_number}

  PR #{pr_number}: {pr_title}
  https://github.com/owner/repo/pull/{pr_number}
  Closes #{issue_number}
```

## PARTIAL

A step printed `Result: PARTIAL`: an issue not ready, residual QA findings, a
failed board sync or run-log append, or a check that could not be evaluated.
Name the residual gap; the final count is new, since the `[4/5] QA` line only
showed the in-progress state:

```
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:       PARTIAL — issue #{issue_number} PR created ({risk_rating} risk)
                QA: {remaining} issues remain after {cycles} cycles
  Evidence:     final tests {count} passed@{sha7}
                secret scan pass ({policy_source}) · run log {run_log_state}
  Uncertainty:  {remaining} unresolved QA findings listed in the PR body
  Decision:     No approval needed.
  Next action:  /issue-pr-review {pr_number}

  PR #{pr_number}: {pr_title}
  https://github.com/owner/repo/pull/{pr_number}
  Closes #{issue_number}
```

If the user asks for another format, follow *Format rule* in
`references/report-examples.md`.
