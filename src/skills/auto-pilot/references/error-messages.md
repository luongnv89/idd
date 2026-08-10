# Error Messages — /auto-pilot

All errors follow the rich error format: what went wrong + fix command + docs link.

## Authentication & Setup

### Not authenticated
```
✗ Not authenticated with GitHub

  To fix:  gh auth login
  Docs:    https://cli.github.com/manual/gh_auth_login
```
**Trigger:** `gh` returns auth error (exit code 4 or "not logged in" in stderr).

### GitHub CLI not found
```
✗ GitHub CLI not found

  To fix:  brew install gh
  Docs:    https://cli.github.com
```
**Trigger:** `gh` command not found in PATH.

### No GitHub remote
```
✗ No GitHub remote configured

  To fix:  git remote add origin <url>
```
**Trigger:** `git remote -v` returns no output or no GitHub URL.

### Not a git repository
```
✗ Not a git repository

  To fix:  git init && git remote add origin <url>
```
**Trigger:** `git rev-parse --git-dir` fails.

## Pre-flight

### Dirty working tree (auto-resolved)
```
⚠ Working tree had uncommitted changes — auto-stashed
  Stash ref: {stash_ref}
```
**Trigger:** `git status --porcelain` returns non-empty output.
**Action:** Auto-stash with `git stash --include-untracked -m "auto-pilot: stash before run"`. Non-fatal — auto-pilot continues.

### Not on default branch (auto-resolved)
```
⚠ Was on branch {branch} — auto-switched to {default_branch}
```
**Trigger:** `git rev-parse --abbrev-ref HEAD` returns a branch that is not `main` or `master`.
**Action:** Auto-switch with `git checkout {default_branch} && git pull --rebase origin {default_branch}`. Non-fatal — auto-pilot continues.

### Rate budget exhausted — pausing until reset (non-fatal)
```
○ Rate budget exhausted — pausing until {resume_at}

  Remaining: {remaining} calls — below the safe threshold of 200.
  Waiting {wait_s}s for the budget to reset, then re-probing. The run
  lock is refreshed every 300s so no other run can reclaim it mid-pause.
```
**Trigger:** `gi-ratelimit.py --verdict` returns `action: "wait"` — `remaining` is below the threshold and `reset` falls inside `autopilot.max_runtime_minutes`. Non-fatal.
**Action:** Run the chunked pause in `references/preflight.md` (*Rate-limit pause*), refreshing the run-lock heartbeat between chunks, then re-probe and continue. Nobody is at the terminal, so a timestamp is the remedy, not an instruction to a reader.

### Insufficient API rate budget (fatal — the wait does not fit)
```
✗ Insufficient GitHub API rate budget for auto-pilot

  Remaining: {remaining} calls — below the safe threshold of 200.
  The budget resets at {resume_at}, which is past this run's budget
  of {max_runtime_minutes} min (or is unknown), so pausing for it
  would strand issues half-resolved.

  To fix:  re-run /auto-pilot after {resume_at}, or raise
           autopilot.max_runtime_minutes
  Check:   gh api rate_limit --jq '{remaining: .rate.remaining, reset: .rate.reset}'
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/platform-github.md
```
**Trigger:** `gi-ratelimit.py --verdict` returns `action: "stop"` — the pause would run past the runtime budget, or `reset` is unknown. Fatal.
**Action:** Persist the final summary with `gi-state.py --report`, release the run lock, and stop. Nothing is left half-resolved because nothing was started. **At Prerequisite 8 there is no lock yet** — it is taken further down the prerequisites — so the release is the mid-run half of this action and the preflight stop is the report and this block alone; the deadline the verdict was given comes from the clock rather than from a run state that does not exist. Both variants are in `references/preflight.md` (*Rate-limit pause*).

**Low-budget warning (non-fatal):** on `action: "warn"` — `remaining` between 200 and 500 — print the same block with a `⚠` symbol and the line `Proceeding — budget may run low; the loop will pause and resume if it hits the limit.` instead of stopping.

### gi-ratelimit unavailable (degrade)
```
⚠ gi-ratelimit unavailable — computing the pause by hand
```
**Trigger:** No `python3`, exit 2 (the script path did not resolve), or exit 4 from any `gi-ratelimit.py` call. A **missing bundled file** is different — that is a broken install, and the `✗ Missing bundled dependency` block above is the answer. Exit 3 is invalid input: a stop for that one probe, never a degrade.
**Action:** Follow the prose fallback beside the call site in `references/preflight.md` (*Rate-limit pause*, *Transient-failure retry*) or `references/phases.md` (*Runtime budget check*). For the budget check the wording is `⚠ gi-ratelimit unavailable — the runtime budget is not enforced` and the run continues unbounded. Never read a degrade as an expiry or as a `stop` verdict.

### Runtime budget reached (clean stop)
```
○ Runtime budget reached ({max_runtime_minutes} min) — stopping cleanly

  Elapsed:   {elapsed_s}s since {started_at}
  Processed: {n} issue(s) this run
  Remaining work is untouched — re-run /auto-pilot to continue.
```
**Trigger:** `gi-ratelimit.py --budget` returns `expired: true` at the top of an iteration or around a rate-limit pause (`references/phases.md` → *Runtime budget check*). Not an error — the run did what it was told.
**Action:** Start nothing new, print the Final Summary, persist it with `gi-state.py --report`, release the run lock, and stop. An iteration already in flight is never abandoned: the budget gates when work may start, not how long it may run.

### Insufficient merge permission (auto-downgrade)
```
⚠ Insufficient merge permission — running in no-merge mode

  Your permission on this repo is {viewerPermission} (need WRITE or higher).
  Auto-pilot will triage, resolve, and review every issue, then leave each
  PR open for a maintainer to merge. No issues will be blocked.
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/platform-github.md
```
**Trigger:** Preflight step 9 finds `gh repo view --json viewerPermission` is `READ`, `TRIAGE`, or `NONE`.
**Action:** Downgrade to no-merge mode — run the full loop but skip Phase 5 (merge), leaving all PRs open. Non-fatal — auto-pilot continues.

## Run State & Lock

### Another run is in progress (fatal)
```
✗ Another /auto-pilot run is in progress

  Holder:  run {run_id} — pid {pid} on {host}, started {age} ago
  Nothing was mutated: the lock is taken before the first stash, branch,
  or push, so this run stopped before touching the working tree.

  To fix:  wait for that run to finish, or — if it is gone —
           /auto-pilot --force-unlock
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```
**Trigger:** `--lock` exits 3 — `.gitissue/run.lock` exists, is younger than the TTL (default 3600s), and its `pid` is alive on this host (or the lock was taken on another host, where liveness cannot be checked).
**Action:** Stop before any mutation. Exit 3 is a stop, never a degrade: starting anyway is the concurrent-mutation case the lock exists to prevent.

### Resuming an interrupted run
```
○ Resuming run {run_id} — interrupted at phase {phase}
  Issue:   #{issue_number} — {issue_title}
  Branch:  {branch_name} (confirmed on GitHub)
  PR:      #{pr_number} ({pr_state})
  Done:    {processed_count} issue(s) already processed this run
```
**Trigger:** `/auto-pilot --resume` and *Step 1.0*'s gate resolved to `resumable` — the recorded state parsed, and `gh pr list --head "{branch_name}"` confirms the recorded PR.
**Action:** Re-enter at the recorded phase on the recorded branch/PR; never re-resolve the issue and never open a second PR.

### Recorded run state is stale
```
⚠ Recorded run state is stale — starting fresh

  Reason: {corrupt state file | recorded branch has no PR | --fresh requested}
  The recorded state is a hint, never an authority: when GitHub disagrees
  with it, GitHub wins.
```
**Trigger:** *Step 1.0*'s gate resolved to `stale` — the read reported `corrupt`, the recorded phase is unknown, `--fresh` was passed, or the branch/PR reconciliation failed. Those four conditions are the whole list. A **reclaimed or re-acquired lock is not one of them**: a genuine `--resume` either finds its own lock still live and re-acquires it in place (`reacquired` — the agent process outlived the loop) or finds it dead-pid stale and reclaims it (`reclaimed` — the whole process is gone). Both are ordinary, both exit 0, and treating either as stale *state* would `--init` over the very state the resume is about to read. A reclaimed lock prints the script's own `⚠ gi-state: reclaimed a … lock` line; a re-acquired one prints nothing at all. Neither says anything about the recorded state.
**Action:** `--init` over the old state and run the full loop from Phase 1. Non-fatal.

### gi-state unavailable (degrade)
```
⚠ gi-state unavailable — running without the run lock
  This run is not resumable; checkpoints are skipped.
```
**Trigger:** No `python3`, exit 2 (the script path did not resolve), or exit 4 (the write failed) from any `gi-state.py` call. A **missing bundled file** is different — that is a broken install, and the `✗ Missing bundled dependency` block above is the answer.
**Action:** Follow the prose fallback beside the call site in `references/preflight.md` (*Run lock*) and continue. The loop's own work is unaffected; only resume is lost.

## Explicit List Mode

### Empty issue list
```
✗ No issues to process

  The issue list is empty after removing duplicates and skipped issues.
  To fix:  provide at least one issue number: /auto-pilot --issues 5,10
```
**Trigger:** `--issues` list is empty after deduplication and `--skip` removal.

### All issues invalid
```
✗ No valid issues to process

  All issues in the list are closed or not found.
```
**Trigger:** Every issue in the `--issues` list is either not found or closed after validation.

### Issue not found in list
```
✗ #{N} — not found (removing)
```
**Trigger:** `gh issue view N` returns 404 during upfront validation of `--issues` list. Non-fatal — the issue is removed from the list.

### Issue closed in list
```
⚠ #{N} — {title} (closed, removing)
```
**Trigger:** Issue state is `closed` during upfront validation. Non-fatal — the issue is removed from the list.

### Conflicting flags
```
✗ --issues and --limit cannot be combined

  The issue list defines its own limit.
  To fix:  use --issues alone, or --limit without --issues
```
**Trigger:** Both `--issues` and `--limit` flags are provided.

## Analysis (Explicit List Mode)

### Analysis failed
```
⚠ Issue analysis failed — falling back to user-defined order

  The analyzer could not complete analysis for all issues.
  Proceeding with original order without batching optimization.
```
**Trigger:** Analyzer subagent returns failure or times out. Non-fatal — the auto-pilot falls back to processing issues in the original user-defined order without batching.

### Analysis partial failure
```
⚠ Could not analyze #{N} — excluded from batching

  Issue #{N} will be resolved individually in its original position.
```
**Trigger:** Analyzer could not analyze a specific issue (e.g., issue body is empty or unparseable). Non-fatal — the issue is excluded from batching but still resolved individually.

## Triage

### No open issues
```
✓ All issues resolved — nothing left to triage!
```
**Trigger:** the backlog is empty, reached two ways. On a triage iteration,
*Step 1.1*'s scan returns an empty `issues[]`. On a **reuse** iteration — one
that skipped Step 1.1 because *Step 1.1a* read the cache as `fresh` — *Step 1.1b*'s
live `gh issue list --state open --json number,assignees` returns an empty array,
which is the same condition reached without a scan (equivalently, an empty
`summary.suggested_order` in a cache Step 1.1a reused or Step 1.6 updated). Both
entry points print the one block in `references/phases.md` (*Step 1.1*). The
second trigger is not optional: a reuse iteration never runs Step 1.1, so without
it a backlog that empties mid-run falls through to `⚠ No eligible issues to pick`
with all-zero counts. This is a success message, not an error.

### No eligible issues
```
⚠ No eligible issues to pick

  Blocked:      {blocked_count} issues (waiting on dependencies)
  Skipped:      {skipped_count} issues (skip labels, --skip, failed, or ineligible)
  Dep-blocked:  {dep_blocked_count} issues (PR open, waiting on a dependency merge)
  Assigned:     {assigned_count} issues (assigned to others)

  To unblock: merge the dependency PR(s), resolve dependency issues, or use
              --skip to bypass
```
**Trigger:** All open issues are blocked, skipped, assigned to other users, or
added to the session skip list — by the Phase 5.1b dependency gate
(`blocked_by_dependency`), by a Phase 2.3 resolution failure (`failed`), or by
Step 1.2b's post-pick re-check (`not_eligible` when the issue is closed or
assigned elsewhere; `quarantined` or `blocked_label` when its live labels are in
the effective `skip_labels` set). This is the
**only** place a run ends for dependency reasons — the gate itself never stops
the loop. Omit the `Dep-blocked` line when that count is zero. Keep this block
byte-identical to the one in `references/phases.md` (*Step 1.2*), and take which
bucket each reason counts under from that step's reason-to-bucket table — it is
the single home of that mapping, never restated here.

### API rate limit during a loop read
```
⚠ GitHub API rate limit reached while fetching issues

  Fetched {count}/{total} issues before the limit.
  Check:   gh api rate_limit --jq '{remaining: .rate.remaining, reset: .rate.reset}'
```
**Trigger:** HTTP 403 with rate-limit headers during an issue fetch, mid-run.
**Action:** Classify it by driver rule 5 in `docs/platform-github.md`. A *secondary* limit carrying `Retry-After` is recoverable: retry on the bounded backoff in `references/preflight.md` (*Transient-failure retry*). *Primary* exhaustion is not retryable — take the *Rate-limit pause* in that same file, which either pauses until `reset` and resumes or stops cleanly. Only when both are exhausted does the read fall through to its documented degrade (`live_backlog = unavailable`, `references/phases.md` → *Step 1.1b*). There is no remedy addressed to a reader here: an unattended run has none.

## Resolve

### Resolve failure (autonomous default)
```
⚠ Skipping #{issue_number} — will retry on next run.
  Continuing to next issue...
```
**Trigger:** Issue resolver fails at any step. Default behavior: log failure, skip issue, continue loop.

### Issue quarantined after repeated failures
```
⚠ #{issue_number} quarantined after {streak} consecutive failed runs

  Label:  {quarantine_label} — remove it to let /auto-pilot try again
  The streak comes from .gitissue/runs.jsonl; the label is the durable
  state, so deleting that file never clears a quarantine.
  Continuing to next issue...
```
**Trigger:** After a Phase 2.3 failure, `gi-runlog.py --failure-streak` reports `quarantine: true` — `autopilot.quarantine_after` consecutive `failed` records for this issue (`0` disables the check entirely).
**Action:** `gh issue edit {issue_number} --add-label "{quarantine_label}"` — only after the label passes the `^[A-Za-z0-9._:-]+$` check in `references/phases.md`, since a config string reaching a command line is not metacharacter-checked by `gi-config.py` — then record the skip-list reason `quarantined` and **continue to the next issue**: record-and-continue, never a stop. The label is in the effective `skip_labels` set, so later runs skip the issue with no extra gate. Missing or unreadable log (exit 4, `streak: 0`): print `⚠ gi-runlog unavailable — skipping the quarantine check` and never quarantine on evidence nobody read.

### Quarantine label could not be applied (degrade)
```
⚠ Quarantine label could not be applied to #{issue_number}

  Your permission on this repo is {viewerPermission} (need WRITE or higher).
  The issue is skipped for the rest of this run, but the quarantine will
  not persist — the next run will try it again.
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/platform-github.md
```
**Trigger:** `gh issue edit --add-label` is refused for lack of repository write permission (the `READ` / `TRIAGE` / `NONE` case Prerequisite 9 already downgrades for).
**Action:** Skip the write and continue — the same downgrade-rather-than-fail choice as no-merge mode. The issue stays in this run's session skip list, so the current run still stops re-picking it.

### Issue already resolved
```
○ #{issue_number} already resolved — skipping
```
**Trigger:** Resolver subagent returns `already_resolved` status — closing evidence, meaning a **merged** PR or a closing commit on the default branch.
**Action:** Skip review/fix/merge phases, continue to next iteration.

### Issue already has an open PR (review it)
```
○ #{issue_number} already has PR #{pr_number} — reviewing the existing PR
  Branch: {branch_name}
```
**Trigger:** Resolver subagent returns `pr_in_progress` with a `pr_number` — an open, unmerged PR already targets this issue (often one an interrupted run created).
**Action:** Route into Phase 3 review of that PR, reusing the reported branch and PR; the iteration then reaches its ordinary outcome. **Never close the issue** — an unreviewed, unmerged PR is not a resolution. With no `pr_number` in the report-back, record `skipped` with `skipped_reason: pr_in_progress` and leave the issue open.

### Resolve failure (pause mode — opt-in)
```
⚠ Auto-pilot paused due to failure (pause_on_failure: true).

  Failed on:  #{issue_number} — {title}
  Step:       {failure_step}
  To resume:  fix the issue, then /auto-pilot
  To skip:    /auto-pilot --skip {issue_number}
```
**Trigger:** Issue resolver fails and `autopilot.pause_on_failure` is explicitly set to `true` in config.

### Sync conflict (auto-resolved)
```
⚠ Sync conflict — auto-reset to origin/{default_branch}
  Any local-only changes were discarded (all work is already pushed to PRs).
```
**Trigger:** `git pull --rebase origin {default_branch}` fails with merge conflicts.
**Action:** Auto-recover with `git rebase --abort && git reset --hard origin/{default_branch}`. Non-fatal — auto-pilot continues.

### Sync failure (unrecoverable)
```
✗ Failed to sync with {default_branch} — cannot recover automatically

  To fix:  resolve conflicts manually: git rebase --continue
  Then:    /auto-pilot to resume
```
**Trigger:** Both rebase and hard reset fail. Fatal — auto-pilot stops.

## Review

### Review cycles exhausted (non-critical issue, aggressive + merge_partial)
```
⚠ PR #{pr_number} has unresolved issues after {review_cycles} cycles

  Remaining issues:
    ● {issue_description_1}
    ● {issue_description_2}

  ✓ Created follow-up issue #{followup_number}
    "Follow-up: unresolved review issues from #{issue_number}"
  ⟶ mode: aggressive + merge_partial: true — merging partial PR...
  ✓ PR #{pr_number} merged (partial fix) — #{issue_number} closed
    Unresolved issues tracked in #{followup_number}
    Outcome: partial_followup
  Continuing to next issue...
```
**Trigger:** All review-fix cycles exhausted, the original issue does NOT have a `critical_labels` label, and the effective mode is `aggressive` with `autopilot.merge_partial: true`. Step 2a (Step 5.1b dependency gate) must pass before this output is shown.
**Action:** Create follow-up issue, merge PR only after dependency gate passes. If the gate blocks, use *PR blocked by unmerged dependency* instead (PR left open, outcome `blocked_by_dependency`, loop still continues). Otherwise continue to next issue. Non-fatal either way.

### Review cycles exhausted (non-critical issue, PR left open)
```
⚠ PR #{pr_number} has unresolved issues after {review_cycles} cycles

  Remaining issues:
    ● {issue_description_1}
    ● {issue_description_2}

  ✓ Created follow-up issue #{followup_number}
    "Follow-up: unresolved review issues from #{issue_number}"
  ○ mode: {mode} — PR left open for manual merge
    Outcome: left_open
  Continuing to next issue...
```
**Trigger:** All review-fix cycles exhausted, the original issue does NOT have a `critical_labels` label, and the effective mode is `conservative`, `balanced`, or `aggressive` with `merge_partial: false`.
**Action:** Create follow-up issue; leave PR open. Continue to next issue. Non-fatal.

### Review cycles exhausted (critical issue)
```
⚠ CRITICAL issue #{issue_number} has unresolved review issues after {review_cycles} cycles

  Issue:  #{issue_number} — {issue_title}
  PR:     #{pr_number} ({pr_url})
  Labels: {labels}

  Remaining issues:
    ● {issue_description_1}
    ● {issue_description_2}

  ⚠ This issue is marked critical — auto-pilot requires your decision.

  Options:
    1. Merge PR as-is (partial fix) and create follow-up issue
    2. Leave PR open for manual review — do not merge
    3. Skip this issue and continue the loop

  What would you like to do?
```
**Trigger:** All review-fix cycles exhausted and the original issue HAS a `critical_labels` label.
**Action:** Stop the loop and ask the user for a decision. Fatal (pauses loop).

## Merge

### PR not mergeable (auto-skip)
```
⚠ PR #{pr_number} is not mergeable

  Reason: {conflict / failing checks / review requested}
  PR left open — continuing to next issue.
```
**Trigger:** `gh pr view` shows `mergeable` is false or `reviewDecision` is `CHANGES_REQUESTED`.
**Action:** Leave PR open, continue to next issue. Non-fatal.

### Merge failed (auto-skip)
```
⚠ Merge failed for PR #{pr_number} — PR left open
  Continuing to next issue...
```
**Trigger:** `gh pr merge` returns non-zero exit code.
**Action:** Leave PR open, continue to next issue. Non-fatal.

### CI checks timeout
```
⚠ CI checks did not complete within {timeout}s — PR left open
  Continuing to next issue...
```
**Trigger:** Status checks remain pending after `review.ci_timeout` seconds of polling.
**Action:** Leave PR open, continue to next issue. Non-fatal.

### CI checks failed
```
⚠ CI checks failed for PR #{pr_number} — PR left open
  Continuing to next issue...
```
**Trigger:** One or more status checks complete with `failure` or `error` conclusion.
**Action:** Leave PR open, continue to next issue. Non-fatal.

### PR blocked by unmerged dependency
```
⚠ BLOCKED — PR #{pr_number} cannot merge until PR #{dep_pr_1} (closing #{dep_n1}) is merged

  Issue:        #{issue_number} — {issue_title}
  PR:           #{pr_number} ({pr_url})
  Blocked by:
    ● #{dep_n1} — {dep_title_1} ({dep_issue_state}; PR #{dep_pr_1} is {dep_pr_state})
    ● #{dep_n2} — {dep_title_2} ({dep_issue_state}; no linked PR)

  ⚠ Not merged — merging out of dependency order is irreversible.
  ○ PR #{pr_number} left open — continuing to next issue.

  To unblock PR #{pr_number}:
    1. Review and merge the dependency PR(s) above
    2. Re-run /auto-pilot — a later run re-evaluates the gate for
       PR #{pr_number} and merges it once the dependency is in
    3. To bypass entirely: set autopilot.respect_dependencies: false in
       .gitissue.yml (not recommended unless the marker is wrong)
```
**Trigger:** Phase 5.1b (Dependency Gate) finds at least one `Depends on #N` / `Blocked by #N` reference whose target issue is still open, or whose target issue is closed but has an unmerged linked PR. Only fires when `autopilot.respect_dependencies: true`.
**Action:** Do **not** merge. Leave the PR open and unchanged, record iteration outcome as `blocked_by_dependency`, add the issue to the session skip list, and continue to the next eligible issue. **Non-fatal — the run is not paused.** The gate never merges out of order, but it never strands the rest of the backlog either; the loop ends on dependency grounds only when no eligible issue is left (`⚠ No eligible issues to pick`). The audit trail is the iteration line in the final summary table plus the alert above, and exactly one `.gitissue/runs.jsonl` line with `outcome: blocked_by_dependency`.

### Dependency cycle detected (auto-skip)
```
⚠ Dependency cycle detected for #{issue_number} — skipping gate
  Resume manually after fixing the issue body.
```
**Trigger:** Phase 5.1b finds the issue's body references its own number (direct self-reference). Multi-hop cycles (A → B → A) are not detected at this gate; they would require traversing each dependency's body. The gate is skipped so a PR is never blocked on its own issue number.
**Action:** Skip the gate, log the warning, proceed to Step 5.2. Non-fatal.

### Dependency reference not found (auto-skip)
```
⚠ Dependency #{N} not found — ignoring
```
**Trigger:** A `Depends on #N` reference points at an issue that returns 404 from `gh issue view`. Likely a typo in the issue body.
**Action:** Skip that reference, continue evaluating the gate. Non-fatal.

## Configuration

### Invalid config
```
✗ Invalid config: .gitissue.yml

  Line {N}: {field} {validation_message}

  To fix:  edit .gitissue.yml and correct the values above
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```
**Trigger:** Config file exists but contains invalid values (wrong type, out of range, unknown field).
