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

✓ Iteration 1/3 complete
  Issue:    #12 — Fix auth redirect loop
  PR:       #45
  Outcome:  merged
  Duration: 4m 05s
  ────────────────────────────────────
  Remaining: 4 eligible issues

● [Iteration 2/3] Triaging open issues...
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

  Next action:             all requested issues resolved!
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

```
⚠ PR #45 is not mergeable

  Reason: 2 status checks pending (CI / lint)
  Waiting for checks to complete... (timeout: 600s)
```

Wait up to `review.ci_timeout` seconds for CI checks. Poll every 30 seconds:

```bash
gh pr view {pr_number} --json statusCheckRollup --jq '.statusCheckRollup[] | select(.status != "COMPLETED")'
```

If all checks pass within the timeout, proceed with merge. If timeout:
```
⚠ CI checks did not complete within {timeout}s — PR left open
  Continuing to next issue...
```
Leave PR open, continue to next issue. Non-fatal.

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

  ⚠ Auto-pilot paused — merging out of dependency order is irreversible.

  To resume:
    1. Review and merge the dependency PR(s) above
    2. Re-run /auto-pilot — the loop will pick up where it left off and
       re-evaluate the gate for PR #87
    3. To bypass entirely: set autopilot.respect_dependencies: false in
       .gitissue.yml (not recommended unless the marker is wrong)

  Iteration 2/10:    ⚠ blocked_by_dependency — #42 → PR #87 (dep: #38, PR #84)
```

The user reviews and merges PR #84 manually. They re-invoke `/auto-pilot`. The loop re-triages, picks #42 again (since it's still open and PR #87 is still open and waiting), re-evaluates the gate (now satisfied — #38 is CLOSED and PR #84 is MERGED), and merges PR #87. The next iteration continues with the rest of the backlog.

This is the second and only other place the loop pauses (alongside the critical-issue review-failure case). Both pauses share the same shape: structured alert with concrete next steps, no state file, resume-by-re-invocation.

