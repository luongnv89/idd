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
  Report:                  .gitissue/last-run-report.md
```

The `Report:` line is the path the summary was **persisted** to, printed after
the write succeeds and omitted when it did not (or under `--dry-run`, which
writes nothing).

## Persisted run report

The summary above is printed to the terminal and written to
`.gitissue/last-run-report.md`, so a run that scrolled past — or that nobody was
watching — leaves a readable artifact. It is machine-local and gitignored, like
the run state and the lock.

Compose the payload and pipe it in; the markdown carries issue titles, so it
reaches the script on **stdin**, never on a command line:

| Field | Type | Meaning |
|-------|------|---------|
| `run_id` | string | the run this report belongs to (defaults to the run state's) |
| `markdown` | string | the rendered summary — the same text just printed |
| `generated_at` | string | optional UTC instant, exactly `YYYY-MM-DDTHH:MM:SSZ`; defaults to now. Pattern-checked like `run_id`, because both are interpolated into the marker below and a value carrying `-->` would end it early |

Both header values are pattern-checked on **every** path that can produce one —
the value submitted here, and the `run_id` the script falls back to reading out
of `.gitissue/run-state.json`. A state file is machine-local but it is still
input: a recorded `run_id` that does not conform is dropped from the marker
rather than passed through, so the marker cannot be broken by editing the state
file.

The file it writes opens with a `<!-- gitissue:run-report v1 {…} -->` marker
carrying `run_id` and `generated_at`, so a later reader can tell which run it
describes. Each run overwrites it — there is one *last* run report, not a
history; `.gitissue/runs.jsonl` is where cross-run history lives.

Exit 0 prints the path. Exit 3 is a stop — the payload is invalid (an empty
`markdown`, an unknown key); fix the payload rather than writing the file by
hand. No `python3`, exit 2, or exit 4: print `⚠ gi-state unavailable` and write
the same markdown to `.gitissue/last-run-report.md` with the **Write** tool
instead. Either way the run is over, so neither path changes an outcome.

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

`√` and `×` are the completion-report check glyphs defined in
`docs/terminal-style.md`; the run's own status symbols stay `✓ ✗ ⚠ ○`.

### Per-step checks

| Phase | Checks |
|-------|--------|
| 1 — Triage and Pick | `Triage refreshed` · `Issue picked` · `Dependencies clear` |
| 2 — Resolve | `Resolver returned` · `PR created` · `Telemetry returned` |
| 3-4 — PR Review | `Review ran` · `Fix cycles converged` · `CI green` |
| 5 — Merge | `Mergeable` · `Squash-merged` · `Issue closed` · `Follow-up filed when partial` |

The report is per phase, printed above the *Iteration Report* block. It never
stops the loop by itself: a `FAIL` phase resolves to the iteration's own
categorical outcome (`failed`, `left_open`, `blocked_by_dependency`, `skipped`),
which the loop records before advancing to the next issue.
