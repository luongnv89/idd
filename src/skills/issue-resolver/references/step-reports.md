# Step completion reports

## Step Completion Reports

Every step ends with a completion report — the checkable bar that separates *the
step ran* from *the step succeeded*. Emit it right after the step's `[N/5]`
tracker line:

```
  [3/5] Implement    ✓ 3 files changed, 8 unit tests
    √ Every AC addressed   √ Tests written   × Commits conventional
    Result: FAIL
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
- One clarification of that rule, because two paths reach Step 2 without spawning
  the synthesizer: *Step 2 — Plan*'s `Options produced` check is `√` whenever
  options are in hand at the end of the step — synthesized this run, lifted from
  a fresh analysis (`analysis_reuse = fresh`), or replaced by the `light`
  profile's direct minimal plan — and `×`/`PARTIAL` only when the step ends with
  no plan at all. The check asks whether the plan exists, not which machinery
  produced it.
- `Scope inside the issue` is `√` when the *Criteria coverage gate* returns
  `covered` or `no_criteria`; a `gap` is `×`.

`√` and `×` are the completion-report check glyphs defined in
`docs/terminal-style.md`; the run's own status symbols stay `✓ ✗ ⚠ ○`.

### Per-step checks

| Step | Checks |
|------|--------|
| 0 — Preflight | `Issue fetched` · `No PR already targets it` · `Guards clear` · `Criteria confirmed` · `Branch created` |
| 1 — Research | `Codebase scanned` · `Not already resolved` · `Complexity rated` |
| 2 — Plan | `Options produced` · `Option selected` · `Scope inside the issue` |
| 3 — Implement | `Every AC addressed` · `Tests written` · `Commits conventional` |
| 4 — QA | `Review clean` · `Tests pass` · `Build clean` · `AC verified` |
| 5 — Deliver | `Tests green` · `Branch pushed` · `PR opens with Closes #N` |

`PARTIAL` is legitimate in exactly three places: *Step 0 — Preflight* when only
`Criteria confirmed` is `×` (an issue not ready, resolved on a yes, or criteria 0d wrote); *Step 4 — QA* when the loop hits
`review_cycles` with residual non-blocking findings (delivered with known
issues), and *Step 5 — Deliver* when the PR is created but an optional extra
(project-board sync, run-log append) failed. Anywhere else a `×` is blocking.
