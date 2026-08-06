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

### Insufficient API rate budget (preflight)
```
✗ Insufficient GitHub API rate budget for auto-pilot

  Remaining: {remaining} calls — below the safe threshold of 200.
  The loop resolves many issues, each fanning out subagents that make
  their own API calls; running now would strand issues half-resolved.

  To fix:  wait for the budget to reset, then re-run /auto-pilot
  Check:   gh api rate_limit --jq '.rate.remaining'
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/platform-github.md
```
**Trigger:** Preflight step 8 finds `gh api rate_limit --jq '.rate.remaining'` below 200 before the loop starts. Fatal — auto-pilot stops.

**Low-budget warning (non-fatal):** when `remaining` is between 200 and 500, print the same block with a `⚠` symbol and the line `Proceeding — budget may run low; the loop will skip merges if it hits the limit.` instead of stopping.

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
**Trigger:** `gh issue list --state open` returns an empty array. This is a success message, not an error.

### No eligible issues
```
⚠ No eligible issues to pick

  Blocked:   {blocked_count} issues (waiting on dependencies)
  Skipped:   {skipped_count} issues (skip labels or --skip)
  Assigned:  {assigned_count} issues (assigned to others)

  To unblock: resolve dependency issues first, or use --skip to bypass
```
**Trigger:** All open issues are blocked, skipped, or assigned to other users.

### API rate limit during triage
```
✗ GitHub API rate limit reached while fetching issues

  Fetched {count}/{total} issues before limit.
  To fix:  wait a few minutes, then retry
  Check:   gh api rate_limit --jq '.rate.remaining'
```
**Trigger:** HTTP 403 with rate limit headers during issue fetch.

## Resolve

### Resolve failure (autonomous default)
```
⚠ Skipping #{issue_number} — will retry on next run.
  Continuing to next issue...
```
**Trigger:** Issue resolver fails at any step. Default behavior: log failure, skip issue, continue loop.

### Issue already resolved
```
○ #{issue_number} already resolved — skipping
```
**Trigger:** Resolver subagent returns `already_resolved` status.
**Action:** Skip review/fix/merge phases, continue to next iteration.

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
**Trigger:** Phase 5.1b finds the issue's body references its own number (direct self-reference). Multi-hop cycles (A → B → A) are not detected at this gate; they would require traversing each dependency's body. The gate is skipped to avoid an infinite pause on the self-reference case.
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
