# Final Summary format

## Outcome meanings

| Outcome | Meaning |
|---------|---------|
| `merged` | PR passed review and was merged cleanly. |
| `left_open` | PR was created but not merged — either the mode forbids merge, the merge was blocked (CI/conflicts, merge floor unmet), or unresolved review issues prevented merge under the current mode. |
| `partial_followup` | PR was merged with unresolved review issues; a follow-up issue captures the remaining work. Only reachable in `aggressive` mode with `merge_partial: true`. |
| `blocked_by_dependency` | PR was created and reviewed but cannot merge until a `Depends on #N` / `Blocked by #N` reference is itself merged. PR is left open and unchanged, the issue is skipped for the rest of the session, and **the loop continues to the next eligible issue**. The user merges the dependency and a later `/auto-pilot` run picks the blocked PR back up. |
| `failed` | The resolver subagent failed before a PR could be created (or another fatal step failed). |
| `skipped` | Issue was skipped before resolution started — already resolved, blocked by labels/dependencies, in the `--skip` list, or assigned to another user. |

The one `skipped_reason` worth calling out separately is **`quarantined`**: the
issue failed `autopilot.quarantine_after` runs in a row and now carries
`autopilot.quarantine_label`, so it is skipped until a human removes that label.
It is recorded on the iteration that *applied* the label, which is a `failed`
iteration — the quarantine is the consequence of that failure, not a seventh
outcome. Later runs skip the issue as an ordinary label skip.


## Summary template

```
◆ Auto-Pilot Summary — {completed}/{max} iterations
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:                  {COMPLETED / PAUSED / LIMIT REACHED / BUDGET REACHED / RATE LIMITED} — {complete | partial}: {main finding}

  Iteration 1:       ✓ merged                — #{n1} {title1} → PR #{pr1} · AC {p}/{f}/{u} pass/fail/unverified{; partial: …}{; disabled: …}
  Iteration 2:       ⚠ left_open             — #{n2} {title2} → PR #{pr2}
  Iteration 3:       ⚠ partial_followup      — #{n5} {title5} → PR #{pr5}, follow-up #{f5} · AC {p}/{f}/{u} …
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
  Mode:                    {conservative / balanced / aggressive}
  Evidence:                {observed checks — see Review contract}
  Uncertainty:             {unverified or degraded items, or "none observed"}
  Rule candidates:         {review-fix:{scope} (PRs #{a}, #{b}); …}
  Decision:                {No approval needed. | the pending critical decision}

  Remaining:               {remaining_count} open issues
  Next action:             /auto-pilot to continue
  Report:                  .idd/last-run-report.md
```

A merged PR with no counts this session (merged before a resume) prints
`· AC n/a` and counts as `partial`.

The `Report:` line is the path the summary was **persisted** to, printed after
the write succeeds and omitted when it did not (or under `--dry-run`, which
writes nothing).

`Result:` takes exactly one of five values. `COMPLETED` — the backlog or the
explicit list is done. `PAUSED` — the loop stopped for a decision it may not make
alone (a critical issue with unresolved review problems, `pause_on_failure`).
`LIMIT REACHED` — `autopilot.max_iterations` or the `autopilot.max_open_prs` cap
was reached (`Next action:` names the open PRs to review first).
**`BUDGET REACHED`** and **`RATE LIMITED`** — the runtime budget or the API rate
budget stopped the run; their `Next action:` and report rules are in
`references/summary-variants.md` (*Budget and rate-limit stops*).

## Review contract

Apply these rules to the final summary at every terminal outcome that prints
one. A stop in *Prerequisites*, *Dependency Preflight*, the bundled precheck, the
run lock or config load prints no summary (the rate-budget stop excepted): its
rich error block carries the result (`✗` line), the evidence (the failed check)
and the next action (`To fix:` line), and nothing ran, so there is nothing else
to qualify.

1. **Result first.** The first row is `Result:` with one of the five values, then
   `complete` or `partial`, then the main finding:
   - `complete` — every processed iteration ended `merged` with `verification:
     full` (zero `unverified` criteria, no `partial` or `disabled` dimension),
     or `skipped` for a reason the user chose (`--skip`, a skip label, already
     resolved), and no completion-report check was `×`.
   - `partial` — at least one iteration ended `left_open`, `partial_followup`,
     `blocked_by_dependency` or `failed`, a merged PR's `verification` was not
     `full`, or a check was `×` (a degraded script, an unread quarantine
     streak, a run-log line left `log_pending`).
   - The main finding is one clause: for example `3 merged, 1 left open (CI red)`
     or `paused on critical #42`.
2. **Evidence.** Name only checks the loop observed: the merged PR numbers, the
   CI verdict each merge relied on (`ci_status` or the CI wait), the follow-up
   issue numbers filed, the run-log append result, and the persisted report path.
   A PR the reviewer reported clean is evidence of a review verdict, not of a
   merge; only `gh pr merge` success (or a non-zero exit that Step 5.2's merge
   reconciliation read back as `MERGED`) plus the closed issue establishes `merged`.
3. **Uncertainty.** List what the loop did not verify: any `⚠` degrade (gi-config,
   gi-state, gi-runlog, gi-ratelimit), a CI verdict reused from the reviewer
   rather than re-polled, each merged PR whose `verification` is not `full`
   (its unverified count and its `partial` or `disabled` dimensions), a
   follow-up issue that could not be filed, an iteration
   that never reached review, a lane left `log_pending`, an unsynced tree, and
   any post-merge cleanup that kept a worktree or branch (`ok: false`; name
   each worktree kept for untracked or ignored files, and each `blocked_dirty`
   lane worktree). If
   nothing applies, print `none observed`. Label inferences (triage priority,
   dependency edges) as inferences, never as verified facts.
4. **Decision.** An autonomous run makes its own decisions, so print
   `Decision: No approval needed.` The one exception is `PAUSED` on a critical
   issue with unresolved review problems: name that decision (merge, fix by hand,
   or close the PR) and the PR it concerns. Name remaining user actions
   separately on `Next action:` — open PRs a maintainer must merge (`left_open`,
   no-merge mode, `conservative`), quarantined issues to inspect, issues to
   split (`large_scope`, `max_commits_exceeded`), and the
   dependency to merge for a `blocked_by_dependency` PR. Never add an approval
   gate the loop does not already have.
5. **Rule candidates.** Print `Rule candidates:` only when a scope (compared
   lowercase) is in the `fix_scopes` of at least two distinct PRs this run; list
   each such scope with its PRs. The row only informs: never on `Decision:` or
   `Next action:`, it adds no approval gate, and nothing in the loop writes a
   rule, test, recipe or proposal from it. A maintainer approves any rule through
   `docs/shared-agent-conventions.md` (*Correction-to-enforcement*).


## Persisted run report

The summary is also written to `.idd/last-run-report.md` (machine-local,
gitignored), so an unwatched run leaves a readable artifact. The markdown
carries issue titles, so the payload reaches the script on **stdin**, never on
a command line:

| Field | Type | Meaning |
|-------|------|---------|
| `run_id` | string | the run this report belongs to (defaults to the run state's) |
| `markdown` | string | the rendered summary — the same text just printed |
| `generated_at` | string | optional UTC instant, exactly `YYYY-MM-DDTHH:MM:SSZ`; defaults to now |

The file opens with a `<!-- idd:run-report v1 {…} -->` marker carrying
`run_id` and `generated_at`; the script pattern-checks both on every path
(a `run_id` read back from `.idd/run-state.json` included) and drops a
malformed one, since a value carrying `-->` would end the marker early. Each
run overwrites the file; `.idd/runs.jsonl` holds cross-run history.

Exit 0 prints the path. Exit 3 is a stop — the payload is invalid (an empty
`markdown`, an unknown key); fix the payload rather than writing the file by
hand. No `python3`, exit 2, or exit 4: print `⚠ gi-state unavailable` and write
the same markdown to `.idd/last-run-report.md` with the **Write** tool
instead. Either way the run is over, so neither path changes an outcome.
