# Closing Summary — /issue-resolver

The **single** end-of-run block, printed **once**: after the tracker's last
line, or after a stop's error block. It never repeats a per-step pass/fail or a
metric the `[N/5]` tracker printed (files read, complexity, option, files
changed, test counts, QA cycles). Pick the variant that matches the outcome.

## Review contract

Apply these rules to every variant. The resolver opens a PR and never merges it,
so no row asks for approval. The rows are human-facing only: the report-back
fields a caller reads and the run-log record keep their shape.

1. **Result first.** The first row is `Result:` with one status and the main
   finding or stop reason:
   - `DONE` — a PR was created and every step's completion report printed
     `Result: PASS`; or the issue was `already_resolved`.
   - `PARTIAL` — a PR was created, but at least one step printed
     `Result: PARTIAL` (an issue not ready, residual QA findings, a failed
     board sync or run-log append, a check that could not be evaluated).
   - `BLOCKED` — the run stopped before a PR was created: a failed
     prerequisite, an invalid config, a missing bundled dependency, `not found`,
     `closed`, `pr_in_progress`, a declined design confirm, a step that printed
     `Result: FAIL`, a blocked secret scan, or a failed final test run.

   These run statuses are separate from the per-step `PASS | PARTIAL | FAIL`
   vocabulary (`references/step-reports.md`).
2. **Evidence.** Name only checks that ran, each with its observed result: the
   final suite (`{count} passed@{sha7}`, or its skip reason), the secret-scan
   verdict and `policy_source`, the QA verdict, the PR URL that `gh pr create`
   returned, the docs search (*Update documentation*), and the run-log write
   (`appended`, `echoed`, or `fallback`). For `already_resolved`, cite the fixing
   commit or PR. For `BLOCKED`, cite the failed check and its observed output.
   A resumed run adds `resumed from step {k}/5 (record {age} old)`.
3. **Uncertainty.** List what this run did not verify: PR-body AC rows not marked
   `pass`, a skipped browser UI review, `resolve.auto_test: false`, a script that
   degraded to its prose procedure, the inline fallback without the Agent tool,
   a reused analysis (`analysis_reuse = fresh` — verified first, not re-derived),
   the `light` profile's single QA cycle, and a resumed run's restored plan and
   findings (verified, not re-derived). Label `risk_rating` as a judgment,
   not a measurement. Write `none identified` only when no item applies.
4. **Decision.** Print `Decision: No approval needed.` in interactive and auto
   mode alike. Name the remaining user action on `Next action:`:
   - a created PR: `/issue-pr-review {pr_number}` (review, then merge);
   - `large_scope`, `max_commits_exceeded`: split #{issue_number} into smaller issues;
   - under `/auto-pilot`: `none — auto-pilot reviews and merges`;
   - `pr_in_progress`: `/issue-pr-review {pr_number}` for the existing PR;
   - any other `BLOCKED`: the `To fix:` command of the error block.

A wrapped row continues on the next line, aligned under its value, so every line
stays within 80 characters.

## PR created

`DONE` when every step printed `Result: PASS`:

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

`PARTIAL` when a step printed `Result: PARTIAL`. The same block, with the
residual gap named; the final count is new, the tracker's `[4/5] QA` line only
showed the in-progress state:

```
  Result:       PARTIAL — issue #{issue_number} PR created ({risk_rating} risk)
                QA: {remaining} issues remain after {cycles} cycles
  Evidence:     final tests {count} passed@{sha7}
                secret scan pass ({policy_source}) · run log {run_log_state}
  Uncertainty:  {remaining} unresolved QA findings listed in the PR body
```

## Already Resolved

Step 0 or Step 1 found the fix already on the default branch. No PR is created,
so the PR reference is omitted:

```
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:       DONE — issue #{issue_number} already resolved, no PR needed
  Evidence:     fixed by {sha7} ({merged PR #M | closing commit})
  Uncertainty:  matched by commit and PR text; the suite was not re-run
  Decision:     No approval needed.
  Next action:  close #{issue_number} — the resolver never closes it
```

## Blocked

The run stopped before a PR was created. The error block from
`references/error-messages.md` prints first; this block follows it:

```
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:       BLOCKED — {stop reason}
  Evidence:     {failed check}: {observed output}
  Uncertainty:  {steps not run, e.g. "Steps 1-5 not run; no code changed"}
  Decision:     No approval needed.
  Next action:  {To fix command, or /issue-pr-review {pr_number}}
```

If the user asks for another format, follow *Format rule* in
`references/report-examples.md`.
