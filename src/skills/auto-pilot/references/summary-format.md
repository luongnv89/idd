# Final Summary format

When the loop ends (for any reason), print a structured step-by-step summary
showing each iteration's outcome. Each iteration is tagged with one of six
categorical outcomes.

## Outcome meanings

| Outcome | Meaning |
|---------|---------|
| `merged` | PR passed review and was merged cleanly. |
| `left_open` | PR was created but not merged — either the mode forbids merge, the merge was blocked (CI/conflicts), or unresolved review issues prevented merge under the current mode. |
| `partial_followup` | PR was merged with unresolved review issues; a follow-up issue captures the remaining work. Only reachable in `aggressive` mode with `merge_partial: true`. |
| `blocked_by_dependency` | PR was created and reviewed but cannot merge until a `Depends on #N` / `Blocked by #N` reference is itself merged. PR is left open and unchanged, the issue is skipped for the rest of the session, and **the loop continues to the next eligible issue**. The user merges the dependency and a later `/auto-pilot` run picks the blocked PR back up. |
| `failed` | The resolver subagent failed before a PR could be created (or another fatal step failed). |
| `skipped` | Issue was skipped before resolution started — already resolved, blocked by labels/dependencies, in the `--skip` list, or assigned to another user. |

## Summary template

```
◆ Auto-Pilot Summary — {completed}/{max} iterations
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Iteration 1:       ✓ merged                — #{n1} {title1} → PR #{pr1}
  Iteration 2:       ⚠ left_open             — #{n2} {title2} → PR #{pr2}
  Iteration 3:       ⚠ partial_followup      — #{n5} {title5} → PR #{pr5}, follow-up #{f5}
  Iteration 4:       ⚠ blocked_by_dependency — #{n6} {title6} → PR #{pr6} (dep: #{dep})
  Iteration 5:       ○ skipped               — #{n3} {title3} (blocked)
  Iteration 6:       ✗ failed                — #{n4} {title4} (resolver step {step})
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  merged:                  {merged_count}
  left_open:               {left_open_count}
  partial_followup:        {partial_followup_count}
  blocked_by_dependency:   {blocked_by_dependency_count}
  failed:                  {failed_count}
  skipped:                 {skipped_count}
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:                  {COMPLETED / PAUSED / LIMIT REACHED}
  Mode:                    {conservative / balanced / aggressive}

  Remaining:               {remaining_count} open issues
  Next action:             /auto-pilot to continue
```

If batch analysis was used (explicit issue list), use the same layout with two
deltas: suffix the header with `(batch mode)` and add an
`Analysis: ✓ pass ({N} issues, {batches} batch groups)` line directly under the
header. Everything else — the per-iteration rows, the count block, and the
footer — is identical.

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
  restating those is the duplication issue #165 removed.
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
this iteration ran, a cache *Step 1.0* read as `fresh`, or a cache *Step 1.6*
updated after the last merge. It is not "a triage ran this iteration": under
issue #258 a run triages once and updates incrementally, so a name that asserted
a refresh would mark every reuse iteration `×` and turn a working loop into a
wall of `PARTIAL`. It is `×` only when the gate degraded and the pick ran against
an order nothing could vouch for.

`√` and `×` are the completion-report check glyphs defined in
`docs/terminal-style.md`; the run's own status symbols stay `✓ ✗ ⚠ ○`.

### Per-step checks

| Phase | Checks |
|-------|--------|
| 1 — Triage and Pick | `Triage current` · `Issue picked` · `Dependencies clear` |
| 2 — Resolve | `Resolver returned` · `PR created` · `Telemetry returned` |
| 3-4 — PR Review | `Review ran` · `Fix cycles converged` · `CI green` |
| 5 — Merge | `Mergeable` · `Squash-merged` · `Issue closed` · `Follow-up filed when partial` |

The report is per phase, printed above the *Iteration Report* block. It never
stops the loop by itself: a `FAIL` phase resolves to the iteration's own
categorical outcome (`failed`, `left_open`, `blocked_by_dependency`, `skipped`),
which the loop records before advancing to the next issue.
