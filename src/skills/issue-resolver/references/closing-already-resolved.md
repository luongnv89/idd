# Closing Summary — Already Resolved

Read when Step 0 or Step 1 found the fix already on the default branch. The
*Review contract* in `references/closing-summary.md` applies. `Evidence:` cites
the fixing commit or PR. No PR is created, so the PR reference is omitted:

```
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:       DONE — issue #{issue_number} already resolved, no PR needed
  Evidence:     fixed by {sha7} ({merged PR #M | closing commit})
  Uncertainty:  matched by commit and PR text; the suite was not re-run
  Decision:     No approval needed.
  Next action:  close #{issue_number} — the resolver never closes it
```

If the user asks for another format, follow *Format rule* in
`references/report-examples.md`.
