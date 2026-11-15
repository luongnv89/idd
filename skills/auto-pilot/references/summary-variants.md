# Final Summary variants — /auto-pilot

Read only on the path that needs a section: a `BUDGET REACHED` or
`RATE LIMITED` result, explicit list mode, or a requested format other than the
terminal one. The base layout and the *Review contract* are in
`references/summary-format.md`.

## Budget and rate-limit stops

**`BUDGET REACHED`** — the
wall-clock budget `autopilot.max_runtime_minutes` expired
(`references/phases/phase-0-lock-resume.md` → *Runtime budget check*); the run stopped cleanly at an
iteration boundary with nothing in flight, so `Next action:` is the ordinary
`/auto-pilot to continue`. **`RATE LIMITED`** — the `✗ Insufficient API rate
budget` stop fired: the API budget ran out and waiting for `reset` would not fit
the runtime budget, or `reset` is unknown (`references/preflight.md` →
*Rate-limit pause*, the `stop` row). Here `Next action:` is never the ordinary
`/auto-pilot to continue` — that would walk straight back into the same stop —
and it takes **one form per trigger**, because `resume_at` is `null` in exactly
one of the two: an unknown `reset` leaves the verdict's `wait_s` at `0`, and
`gi-ratelimit.py` derives `resume_at` from `wait_s`, so there is no instant to
name.

| Which trigger fired | `Next action:` |
|---------------------|----------------|
| the reset does not fit the runtime budget (`resume_at` is an instant) | `re-run /auto-pilot after {resume_at}` |
| `reset` is unknown (`resume_at` is `null`) | `re-run /auto-pilot once the API budget resets` |

Never substitute a null `resume_at` into the first form — `after null` names no
instant anyone could wait for. The `✗ Insufficient API rate budget` block in
`references/error-messages.md` splits on the same value for the same reason.

`RATE LIMITED` covers **both** call sites of that block, which is why it is its
own value rather than a reading of one of the other four. Mid-run the stop lands
between units of work and the counts are whatever completed. At **Prerequisite
8** nothing ever started, so the report is a `0/{max}` summary with every count
at zero and no iteration rows — and `COMPLETED` (nothing was done), `PAUSED` (no
decision is waiting), `LIMIT REACHED` (no iteration ran) and `BUDGET REACHED`
(the wall clock had time left; it was the API budget that did not) are each false
of it.

**A run that ends early still leaves a complete report.** A rate-limit *pause*
is not an early end: the lock is held across it and the summary describes the
whole run. A run stopped by the **runtime budget** composes the summary from
completed iterations only and persists it before the lock is released. A run
stopped by the rate-limit **`stop` verdict** ends early too and reports
`RATE LIMITED`; at Prerequisite 8 that report describes no iterations and is
written before any lock exists. There is no partial-report path.

## Batch mode

If batch analysis was used (explicit issue list), use the same layout with two
deltas: suffix the header with `(batch mode)` and add an
`Analysis: ✓ pass ({N} issues, {batches} batch groups)` line directly under the
header. Everything else — the per-iteration rows, the count block, and the
footer — is identical.

## Other formats

Default: the static terminal summary, one row per iteration, no
animation; `.idd/runs.jsonl` is the machine-readable form and
`.idd/last-run-report.md` the persisted copy. Another requested format renders
the same summary and keeps the `Result`, `Evidence`, `Uncertainty` and
`Decision` rows; if the host cannot render it, say so and print the terminal one.

## Evaluate report understanding

Grade actual summaries against these criteria as well as merge-gate correctness:

| Criterion | Observable check |
|---|---|
| Result is findable | The first row states the status, `complete`/`partial`, and the main finding without reading the iteration rows or logs. |
| Facts and assumptions are separate | Observed checks (merge, CI verdict, follow-up filed, persisted report) are distinct from degraded or reused verdicts listed under `Uncertainty`. |
| Claims are traceable | Each `merged` row names its PR and its AC pass/fail/unverified counts; each `left_open`/`blocked_by_dependency` row names its blocker; `partial` names what made it partial. |
| Next decision is clear | The summary says `No approval needed.` or names the one pending critical decision, and lists remaining user actions on `Next action:`. |

When running behavioral evaluations, include a clean run, a run with a
`left_open` PR, a critical-issue pause and a rate-limited stop, and grade each
summary against all four rows. Ask human reviewers the matching four questions
and record their answers in the eval case's `human_review` block. Missing, blank,
or nonresponsive feedback leaves human understanding unconfirmed; agent
inspection cannot confirm it.
