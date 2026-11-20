# Closing Summary — Blocked

Read when the run stopped before a PR was created: a failed prerequisite, an
invalid config, a missing bundled dependency, `not found`, `closed`,
`pr_in_progress`, a foreign claim, a plan awaiting approval, a declined design confirm, a step that printed
`Result: FAIL`, a blocked secret scan, or a failed final test run. The
*Review contract* in `references/closing-summary.md` applies.

- **Evidence:** the failed check and its observed output.
- **Next action:**
  - `large_scope`, `max_commits_exceeded`: split #{issue_number} into smaller issues;
  - `pr_in_progress`: `/issue-pr-review {pr_number}` for the existing PR;
  - `plan_awaiting_approval`: add the `plan-approved` label to the plan comment's issue, then `/issue-resolver {issue_number}`;
  - any other stop: the `To fix:` command of the error block.

The error block from `references/error-messages.md` prints first; this block
follows it:

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
