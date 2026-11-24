# Test practices

- **T1 Both sides of new branches.** Test the nearest input on each side of every branch the diff adds; assert the exact error type or message. *Check:* each new branch has a case per side.
- **T2 Assertions always run.** Assert errors with the framework's raises construct, await async calls, and let no try, if or loop skip an assertion. *Check:* no assertion sits behind a branch.
- **T3 Spec-derived expectations.** Take expected values from the issue or spec, never from the code's own formula or output (characterization tests excepted). *Check:* every expected literal traces to the spec.
- **T4 Boundary fakes.** Fake network, database and external services at the repo's wrapper with real shapes and errors; mock in-process code only where neighbors do. *Check:* no new test reaches an external service.
- **T5 No focus, skip or retry markers.** Commit no `.only`, `fit`, unconditional skip, xfail or retry on any test. *Check:* grep added lines for these markers.
- **T6 Snapshots are expectations.** Change a snapshot only for output the plan changes; never regenerate wholesale. *Check:* each snapshot hunk maps to a planned change.
- **T7 Deterministic.** Control clock, timezone, locale and randomness; await events or advance fake timers instead of sleeping. *Check:* no added test line sleeps.
- **T8 Isolated state.** Change env vars, globals and cwd only through auto-restoring fixtures, and write files only under a per-test temp dir. *Check:* no new test mutates shared state or writes to a repo path.
- **T9 Unusual text.** Where the diff parses, stores or renders text, test markup, quotes and non-ASCII; assert the exact value back. *Check:* such a case exists.
- **T10 Observable behavior.** Assert what callers observe, not private fields or call order; locate UI by role, label or text, never position. *Check:* no new test reads private fields.
