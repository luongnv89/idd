# /auto-pilot — Examples & Edge-Case Scenarios

Detailed example runs and edge-case behaviors referenced from SKILL.md.

## Example: Full auto-pilot session

**User says:** `/auto-pilot --limit 3`

> Uses the default `autopilot.mode: balanced`, where clean PRs are merged automatically. Under `conservative` mode, each clean PR would end with `Outcome: left_open` instead.

```
● Checking environment...
✓ Environment ready

◆ Auto-Pilot Plan
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Issues to process:  5 (of 8 open)
  Limit:              3
  Review cycles:      3
  Merge mode:         {conservative | balanced | aggressive}
  First issue:        #12 — Fix auth redirect loop

  Execution order:
  ○  #12 — Fix auth redirect loop
  ○  #8  — Add pagination to API
  ○  #15 — Refactor middleware

  ⟶ Starting immediately...

○ Triage cache absent — running a full triage
● [Iteration 1/3] Triaging open issues...
✓ Triage updated — 8 open issues

● Picking next issue from triage order...
  Selected: #12 — Fix auth redirect loop

● [Iteration 1/3] Resolving #12...
  ⟶ Spawning resolver subagent...
  ✓ Resolved #12
    Branch:  fix/12-auth-redirect-loop
    PR:      #45
    Changed: 2 files
    Tests:   4 written, 12 passed

● Reviewing PR #45...
  ⟶ Spawning PR review subagent (/issue-pr-review --auto --no-merge)...

  ✓ PR #45 reviewed
    Review cycles: 1
    Issues found/fixed: 0/0
    CI: all checks passed

✓ PR #45 merged — #12 closed
  https://github.com/owner/repo/pull/45
✓ Triage cache updated — #12 resolved, 7 remain

✓ Iteration 1/3 complete
  Issue:    #12 — Fix auth redirect loop
  PR:       #45
  Outcome:  merged
  Duration: 4m 05s
  ────────────────────────────────────
  Remaining: 4 eligible issues

○ Live backlog: 7 open issues — 1 assigned to others
● [Iteration 2/3] Picking next issue from triage order...
  Selected: #8 — Add pagination to API
  ...

◆ Auto-Pilot Summary — 3/3 iterations
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Iteration 1:       ✓ merged                — #12 Fix auth redirect loop → PR #45
  Iteration 2:       ✓ merged                — #8 Add pagination to API → PR #46
  Iteration 3:       ✓ merged                — #15 Refactor middleware → PR #47
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  merged:                  3
  left_open:               0
  partial_followup:        0
  blocked_by_dependency:   0
  failed:                  0
  skipped:                 0
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:                  LIMIT REACHED
  Mode:                    balanced

  Remaining:               5 open issues
  Next action:             /auto-pilot to continue
```

---

## Example: Explicit issue list

**User says:** `/auto-pilot --issues #5, #12, #8`

```
● Checking environment...
✓ Environment ready

● Validating issue list...
  ✓ #5  — Fix login crash on mobile (open)
  ✓ #12 — Refactor auth middleware (open)
  ✓ #8  — Add dark mode toggle (open)

● Analyzing 3 issues for optimal resolution strategy...
  ⟶ Spawning analyzer subagent...

◆ Analysis Results
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Issues analyzed:  3

  Dependencies detected:
  ● #12 must come before #8 — #8 touches UI theme which depends on auth context refactored by #12

  Batch opportunities:
  ⚡ #5, #8 share 2 files (styles.css, theme.ts) — can batch-resolve together

  Optimized resolution order:
  1. #12 — Refactor auth middleware (high, dependency of #8)
  2. #5  — Fix login crash on mobile (medium, batched with #8)
  3. #8  — Add dark mode toggle (low, batched with #5)

◆ Auto-Pilot Plan (explicit list)
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Issues to process:  3 (of 3 provided)
  Review cycles:      3
  Merge mode:         {conservative | balanced | aggressive}
  Mode:               explicit list (analyzed + optimized)
  Batches:            1 (saving ~1 iterations)

  Optimized execution order:
  1. #12 — Refactor auth middleware
  2. #5  — Fix login crash on mobile (batched with #8)
  3. #8  — Add dark mode toggle (batched with #5)

  ⟶ Starting immediately...

● [Issue 1/3] Next from optimized order: #12 — Refactor auth middleware

● Resolving #12...
  ⟶ Spawning resolver subagent...
  ✓ Resolved #12
    Branch:  refactor/12-refactor-auth-middleware
    PR:      #50
    Changed: 2 files
    Tests:   3 written, 9 passed

● Reviewing PR #50...
  ⟶ Spawning PR review subagent (/issue-pr-review --auto --no-merge)...
  ✓ PR #50 reviewed (1 cycle, 0 issues)

✓ PR #50 merged — #12 closed
  https://github.com/owner/repo/pull/50

✓ Issue 1/3 complete
  Issue:    #12 — Refactor auth middleware
  PR:       #50
  Outcome:  merged
  Duration: 3m 20s
  ────────────────────────────────────
  Remaining: 2 issues in list

● [Issue 2/3] Resolving #5 (+ batched: #8)...
  ⟶ Spawning batch resolver subagent...
  ✓ Resolved #5 and #8
    Branch:  fix/5-login-crash-mobile
    PR:      #51
    Changed: 3 files
    Tests:   5 written, 13 passed

● Reviewing PR #51...
  ⟶ Spawning PR review subagent (/issue-pr-review --auto --no-merge)...
  ✓ PR #51 reviewed (1 cycle, 0 issues)

✓ PR #51 merged — #5 closed, #8 closed (batched)
  https://github.com/owner/repo/pull/51

✓ Issue 2/3 complete (2 issues resolved via batch)
  Issues:   #5 — Fix login crash on mobile, #8 — Add dark mode toggle
  PR:       #51
  Outcome:  merged
  Duration: 2m 50s
  ────────────────────────────────────
  Remaining: 0 issues in list

○ [Issue 3/3] #8 — already resolved in batch with #5

◆ Auto-Pilot Summary — 2/3 iterations (batch mode)
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Analysis: ✓ pass (3 issues, 1 batch groups)

  Iteration 1:       ✓ merged                — #12 Refactor auth middleware → PR #50
  Iteration 2:       ✓ merged                — #5 Fix login crash on mobile → PR #51 (batch: +#8)
  Iteration 3:       ○ skipped               — #8 Add dark mode toggle (already resolved in batch)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  merged:                  2
  left_open:               0
  partial_followup:        0
  blocked_by_dependency:   0
  failed:                  0
  skipped:                 1
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:                  COMPLETED
  Mode:                    balanced

  Remaining:               0 open issues
  Next action:             /auto-pilot to continue
```

---

## Example: Explicit list with invalid issues

**User says:** `/auto-pilot --issues 5, 99, 12 --skip 12`

```
● Validating issue list...
  ✓ #5  — Fix login crash on mobile (open)
  ✗ #99 — not found (removing)
  ○ #12 — skipped (--skip)

◆ Auto-Pilot Plan (explicit list)
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Issues to process:  1 (of 3 provided)
  Review cycles:      3
  Merge mode:         {conservative | balanced | aggressive}
  Mode:               explicit list (analyzed + optimized)

  Optimized execution order:
  1. #5  — Fix login crash on mobile

  Removed:
  ✗ #99 — not found
  ○ #12 — skipped by --skip flag

  ⟶ Starting immediately...
```

---

## Edge Cases

### Review finds issues, fix cycle succeeds

```
● Reviewing PR #45...
  ⟶ Spawning PR review subagent (/issue-pr-review --auto --no-merge)...

  ✓ PR #45 reviewed
    Review cycles: 2
    Issues found/fixed: 2/2
    CI: all checks passed

✓ PR #45 merged — #12 closed
```

Note: the `/issue-pr-review --auto --no-merge` subagent handled the full review-fix cycle internally (review, fix, re-review). It found 2 issues in cycle 1, fixed them, then cycle 2 passed clean. Merge was handled by auto-pilot's Phase 5 after the review returned PASS.

### All eligible issues are blocked

```
● Picking next issue from triage order...

⚠ No eligible issues to pick

  Blocked:   3 issues (waiting on dependencies)
  Skipped:   2 issues (skip labels)
  Assigned:  1 issue (assigned to @alice)

  To unblock: resolve dependency issues first
```

### Merge requires CI checks

First consult *Step 5.1a — CI verdict gate*. The reviewer subagent already
waited on this PR's CI and returned `ci_status` bound to the commit it waited
on. That verdict is `trusted` only on **both** of the gate's conditions: the SHA
still equals the live head, **and** `statusCheckRollup` from the same read is
non-empty with every check in it green. Both are already requested by Step 5.1's
single
`gh pr view {pr_number} --json mergeable,reviewDecision,statusCheckRollup,headRefOid`,
so no second read is issued. A rollup that shows nothing — empty, absent or
unreadable — is `absent`, not `trusted`, and the full wait below runs.
`mergeable` from the same call catches a base that moved **into conflict** and
nothing else; it does not cover a clean base advance, so the moved-base residual
*Step 5.1a* names is unchanged here. With both conditions met there is nothing
left to wait for *on this head*, and the merge proceeds:

```
○ CI verdict: trusted (passed @ 9f2c1ab) — head unchanged, checks green, no re-poll
```

On `stale` or `absent` — a moved head, a bare or missing value, a `failed@…`, or
`review.adaptive_depth: false` — the full wait below runs, unchanged:

```
⚠ PR #45 is not mergeable

  Reason: 2 status checks pending (CI / lint)
  Waiting for checks to complete... (timeout: 600s)
```

Wait for CI checks in one call, at `review.ci_poll_interval` up to `review.ci_timeout`:

```bash
python3 references/scripts/gi-ci-wait.py {pr_number} \
  --interval {review.ci_poll_interval} --timeout {review.ci_timeout}
```

Read `verdict`: `pass` proceeds with the merge; `fail` and `pending` both leave the PR open. Exit 3 is a stop; a missing `python3`, exit 2 (an unresolved script path), or exit 4 degrades to polling by hand every `review.ci_poll_interval` seconds with `gh pr view {pr_number} --json statusCheckRollup --jq '.statusCheckRollup[] | select(.status != "COMPLETED" or (.conclusion | IN("SUCCESS","NEUTRAL","SKIPPED") | not))'`.

The `.conclusion` half of that filter is not optional. A check that finished and
**failed** still has `status: "COMPLETED"`, so filtering on status alone prints
nothing for a red build — and empty output must never be treated as "all clear".

**The degraded path reaches the same three outcomes, not fewer.** Empty output
means no checks have registered yet, so keep polling until the configured settle
window confirms that no CI is configured; do not merge on the first empty poll.
Any line naming a failed check leaves the PR open, as `verdict: fail` would. If timeout:
```
⚠ CI checks did not complete within {timeout}s — PR left open
  Continuing to next issue...
```
Leave PR open, continue to next issue. Non-fatal.

### Interrupted run, resumed

A run is killed (terminal closed, machine rebooted) during Phase 3 of its second
issue. Re-invoking `/auto-pilot` alone would re-triage, re-pick #42, and the
resolver would find its own PR — the case that used to end as `skipped`, and,
worse, as a closed issue behind an unreviewed PR. `--resume` re-enters the run
instead. Nothing about this depends on the loop *remembering* anything: the
memory is `.gitissue/run-state.json`, written at each phase boundary.

```
$ /auto-pilot --resume

● Preflight...
  ⚠ gi-state: reclaimed a dead-pid lock from run 20260810T0914Z-4471
  ✓ Run lock acquired (run 20260810T0914Z-4471)
● Reading recorded run state...

○ Resuming run 20260810T0914Z-4471 — interrupted at phase review
  Issue:   #42 — Apply new auth middleware to checkout
  Branch:  fix/42-auth-middleware-checkout (confirmed on GitHub)
  PR:      #87 (OPEN)
  Done:    1 issue(s) already processed this run

● Reviewing PR #87...
  ✓ PR #87 review passed (clean in 1 cycle)
● Pre-merge: dependency gate... ○ Dependency gate passed
  ✓ PR #87 merged — #42 closed
  Outcome: merged

● [Iteration 3/10] Triaging open issues...
  Selected:   #45 — Add rate-limit headers to the API client
```

Three things in that transcript are the whole mechanism:

1. **The lock was reclaimed, not refused.** The dead run's `pid` is gone, so the
   lock is stale and this run takes it with a `⚠`. Had the original run still
   been alive, the same call would have exited 3 with
   `✗ Another /auto-pilot run is in progress` and mutated nothing.
2. **The checkpoint supplied the branch and PR.** Phase 2.3 wrote
   `{"phase": "review", "current": {"issue": 42, "branch": "fix/42-…", "pr": 87}}`
   the moment the resolver returned, so the resume knows what exists.
3. **GitHub, not the file, confirmed it.** The resume ran
   `gh pr list --head fix/42-auth-middleware-checkout --json number,state` and
   got `[{"number": 87, "state": "OPEN"}]`. Had that come back empty — branch
   deleted, PR closed by someone — the gate would have fallen to `absent` and
   started a fresh run. The state file is a hint; GitHub is the authority. Had
   it come back `MERGED`, #42 would have gone straight to `processed[]` and the
   loop to the next issue.

The first issue is not re-processed: it is in `processed[]`, so the resumed run
skips it and writes no second `runs.jsonl` line for it. The invariant of exactly
one run-log line per processed issue survives the interruption.

### PR blocked by an unmerged dependency

Issue #42 declares `Depends on #38` in its body. Auto-pilot resolves both #38 and #42 in the same session, but #38's PR is still open when #42's PR reaches Phase 5:

```
● Reviewing PR #87...
  ✓ PR #87 review passed (clean in 1 cycle)
● Pre-merge: dependency gate...
  Found markers: Depends on #38

⚠ BLOCKED — PR #87 cannot merge until PR #84 (closing #38) is merged

  Issue:        #42 — Apply new auth middleware to checkout
  PR:           #87 (https://github.com/owner/repo/pull/87)
  Blocked by:
    ● #38 — Add auth middleware base class (OPEN; PR #84 is OPEN)

  ⚠ Not merged — merging out of dependency order is irreversible.
  ○ PR #87 left open — continuing to next issue.

  To unblock PR #87:
    1. Review and merge the dependency PR(s) above
    2. Re-run /auto-pilot — a later run re-evaluates the gate for
       PR #87 and merges it once the dependency is in
    3. To bypass entirely: set autopilot.respect_dependencies: false in
       .gitissue.yml (not recommended unless the marker is wrong)

  Iteration 2/10:    ⚠ blocked_by_dependency — #42 → PR #87 (dep: #38, PR #84)

● [Iteration 3/10] Picking next issue from triage order...
  Selected:   #45 — Add rate-limit headers to the API client
```

The run does **not** end here. #42 is recorded as `blocked_by_dependency`, PR #87 stays open and unchanged, #42 is added to the session skip list (so the pick cannot select it again in this run — the skip list is consulted on every pick, cached or freshly triaged), and iteration 3 starts on the next eligible issue. A 30-issue backlog with one dependency-blocked PR still resolves the other 29. Nothing was merged here, so *Step 1.6* does not run and the cached order is untouched; #42 stays in `summary.suggested_order` and the skip list is what keeps it from being re-picked.

Later, the user reviews and merges PR #84 manually and re-invokes `/auto-pilot`. That new run starts with an empty **session** skip list and its own *Step 1.1a* gate — a commit landed since the cached triage, so the cache reads `stale` and the run triages afresh — picks #42 again (still open, PR #87 still waiting), re-evaluates the gate (now satisfied — #38 is CLOSED and PR #84 is MERGED), and merges PR #87.

The gate never merges out of dependency order, but it also never halts the run: the only dependency-related stop is the ordinary `⚠ No eligible issues to pick` condition, once nothing eligible is left. The one remaining stop-and-ask case is the critical-issue review failure.

**"Empty skip list" is about the session list only.** A quarantined issue is not
in that list on a new run either — it is filtered *earlier*, by its
`autopilot.quarantine_label` in the effective `skip_labels` set, before the
session skip list is ever consulted. So an issue skipped for a dependency comes
back on the next run, while one skipped for a quarantine does not, and neither
fact contradicts the other.

---

## Unattended hardening: quarantine, rate-limit pause, runtime budget

One run showing all three of issue #259's behaviors, with
`autopilot.max_runtime_minutes: 90` and the default `quarantine_after: 3`.

A resolve fails for the third run in a row, so the issue is labelled and the loop
carries on — record-and-continue, never a stop:

```
✗ Resolution failed for #61 at step 4

  Test suite fails on an unrelated fixture the resolver cannot repair
  Outcome: failed

⚠ #61 quarantined after 3 consecutive failed runs
  Label:  auto-pilot-quarantined — remove it to let /auto-pilot try again
  Continuing to next issue...

● [Iteration 4/10] Picking next issue from triage order...
  Selected:   #66 — Cache the model catalogue between runs
```

Two iterations later the API budget runs out. The reset is 22 minutes away and
the run still has 51 minutes of its 90, so the wait fits: the loop pauses,
refreshes the run lock every 300s so no other run can reclaim it, and resumes
where it stopped. Nobody was asked anything.

```
○ Rate budget exhausted — pausing until 2026-08-10T14:52:00Z

  Remaining: 143 calls — below the safe threshold of 200.
  Waiting 1320s for the budget to reset, then re-probing. The run
  lock is refreshed every 300s so no other run can reclaim it mid-pause.

○ Rate budget restored — 4998 calls; resuming at iteration 6/10
```

At the top of iteration 8 the wall clock is spent. The check runs *before* the
pick, so nothing is started and no PR is left half-reviewed; the report is
persisted and the lock released on the way out:

```
○ Runtime budget reached (90 min) — stopping cleanly
  Elapsed:   5412s since 2026-08-10T13:22:00Z
  Processed: 7 issue(s) this run
  Remaining work is untouched — re-run /auto-pilot to continue.

◆ Auto-Pilot Summary — 7/10 iterations
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:                  BUDGET REACHED
  Mode:                    balanced

  Remaining:               12 open issues
  Next action:             /auto-pilot to continue
  Report:                  .gitissue/last-run-report.md
```

The next run picks up from exactly there — #61 is skipped by its label without
costing a resolve, and the other 12 are untouched.

