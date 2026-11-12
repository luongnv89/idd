# Step completion reports

## Step Completion Reports

Every step ends with a completion report — the checkable bar that separates *the
step ran* from *the step succeeded*. Emit it right after the step's `Phase`
tracker line:

```
  Phase 5 — Merge
    √ Mergeable   √ Squash-merged   × Issue closed
    Result: PARTIAL
```

Rules that make the report worth reading:

- `√` — the check passed. `×` — it did not. One entry per check the step actually
  validates. Checks are **gates that could have failed**, never restatements of a
  metric the tracker line already carries (files read, counts, option number) —
  restating those would report the same fact twice.
- `Result: PASS` — every check is `√`; continue.
- `Result: PARTIAL` — only non-blocking checks are `×`; continue, and carry the
  gap into the closing summary so it is never silently dropped.
- `Result: FAIL` — a blocking check is `×`; stop, or enter that step's defined
  failure path. In auto mode follow the step's documented auto behavior instead
  of prompting.
- A step may not be reported complete without a `Result:` line. If a check could
  not be evaluated (a tool was unavailable, a gate was skipped by config), mark
  it `×` and use `PARTIAL` — never assume `√`.

`Triage current` is `√` when the order the pick used is current — a full triage
this iteration ran, a cache *Step 1.1a* read as `fresh`, or a cache *Step 1.6*
(`references/phases/phase-5-merge.md`) updated after the last merge. A run triages
once, reuses a `fresh` cache, and updates it incrementally after each merge;
cache reuse satisfies this check. It is `×` only when the gate degraded and the
pick ran against an order nothing could vouch for.

`Runtime budget` is `√` when the check ran and the budget had time left, and
`×` when it could not be evaluated (`gi-ratelimit` degraded) — an expired budget
is not a `×`, it ends the run before the phase reports at all. With
`max_runtime_minutes: 0` the check is inapplicable, not skipped-and-failed: omit
the entry rather than marking it `×`.

`Quarantine checked` is `√` on any iteration that did not fail (nothing to
check), and on a failing one when `gi-runlog.py --failure-streak` answered. It is
`×` when the streak could not be read or the label write was refused — both
non-blocking, so the phase is `PARTIAL` and the loop continues. With
`quarantine_after: 0` the check is inapplicable: omit the entry.

`√` and `×` are the completion-report check glyphs defined in
`docs/terminal-style.md`; the run's own status symbols stay `✓ ✗ ⚠ ○`.

### Per-step checks

| Phase | Checks |
|-------|--------|
| 1 — Triage and Pick | `Runtime budget` · `Triage current` · `Issue picked` · `Dependencies clear` |
| 2 — Resolve | `Resolver returned` · `PR created` · `Telemetry returned` · `Quarantine checked` |
| 3-4 — PR Review | `Review ran` · `Fix cycles converged` · `CI green` |
| 5 — Merge | `Mergeable` · `Squash-merged` · `Issue closed` · `Follow-up filed when partial` |

The report is per phase, printed above the *Iteration Report* block. It never
stops the loop by itself: a `FAIL` phase resolves to the iteration's own
categorical outcome (`failed`, `left_open`, `blocked_by_dependency`, `skipped`),
which the loop records before advancing to the next issue.
