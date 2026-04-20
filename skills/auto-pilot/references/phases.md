# /auto-pilot — Phase Details

Full step-by-step specification of each loop phase. SKILL.md contains the overview; this reference file contains the full per-step guidance. Read this when implementing a specific phase.

## Phase 1 — Triage and Pick

> **Note:** This entire phase is skipped in explicit list mode (`--issues`). The next issue is simply taken from the user-provided list in order. Jump directly to Phase 2.

### Step 1.1 — Triage

Run a fresh triage to get current priorities:

```
● [Iteration {i}/{max}] Triaging open issues...
```

Execute the equivalent of `/issue-triage update`:

```bash
gh issue list --state open --json number,title,body,labels,assignees --limit 100
```

Build the dependency graph and compute execution order (same algorithm as issue-triage). Persist to `.gitissue/triage.json`.

If no open issues remain:
```
✓ All issues resolved — nothing left to triage!

◆ Auto-Pilot Summary
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Iterations:  {completed}
  Resolved:    {resolved_count} issues
  Failed:      {failed_count} issues
  Skipped:     {skipped_count} issues
```
Stop — the loop is complete.

### Step 1.2 — Pick Next Issue

From the triage execution order, select the first issue that is:
- **Not blocked** — no unresolved dependencies in the triage graph
- **Not skipped** — not in the `--skip` list or `skip_labels` set
- **Not assigned** — not assigned to another user (unless there are no unassigned issues)
- **Open** — state is `open`

```
● Picking next issue from triage order...
  Candidates: {N} issues in execution order
  Selected:   #{issue_number} — {issue_title}
```

If no eligible issue is found (all blocked, skipped, or assigned):
```
⚠ No eligible issues to pick

  Blocked:   {blocked_count} issues (waiting on dependencies)
  Skipped:   {skipped_count} issues (skip labels or --skip)
  Assigned:  {assigned_count} issues (assigned to others)

  To unblock: resolve dependency issues first, or use --skip to bypass
```
Stop.

### Step 1.3 — Display Plan and Auto-Start

On the first iteration, display the execution plan and immediately begin — no confirmation prompt. The user's invocation of `/auto-pilot` is the confirmation.

```
◆ Auto-Pilot Plan
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Issues to process:  {eligible_count} (of {total_open} open)
  Limit:              {max_iterations}
  Review cycles:      {review_cycles}
  Auto-merge:         {yes/no}
  First issue:        #{number} — {title}

  Execution order:
  ○  #{n1} — {title1}
  ○  #{n2} — {title2}
  ○  #{n3} — {title3}
  ...

  ⟶ Starting immediately...
```

If `--dry-run` was specified:
```
○ Dry run complete. No issues resolved.
```
Stop.

---

## Phase 2 — Resolve (Subagent)

### Step 2.1 — Sync to Default Branch

The main agent syncs to the default branch directly (this is lightweight — no code reading):

```bash
git checkout {default_branch}
git pull --rebase origin {default_branch}
```

If this fails (merge conflict from a prior iteration), attempt auto-resolution:

```bash
git rebase --abort
git reset --hard origin/{default_branch}
```

```
⚠ Sync conflict — auto-reset to origin/{default_branch}
  Any local-only changes were discarded (all work is already pushed to PRs).
```

This is safe because the auto-pilot always pushes work to remote PRs before cleanup. Note: `git stash` entries created during pre-flight (with the user's uncommitted work) are stored under their own ref (`refs/stash`) and survive `git reset --hard` — the user's stashed work is preserved (`git stash list` will still show them). If the hard reset also fails (unlikely), then stop:
```
✗ Failed to sync with {default_branch} — cannot recover automatically

  To fix:  resolve conflicts manually: git rebase --continue
  Then:    /auto-pilot to resume
```

### Step 2.2 — Spawn Resolver Subagent

Launch a subagent using the Agent tool to perform the entire resolve pipeline. This keeps all codebase reading, code writing, and test execution out of the main agent's context.

```
● [Iteration {i}/{max}] Resolving #{issue_number}...
  ⟶ Spawning resolver subagent...
```

Use the **Resolver Subagent** prompt from `references/subagent-prompts.md`, substituting `{issue_number}`. The subagent runs the full /issue-resolver pipeline and returns only: status, branch_name, pr_number, pr_url, files_changed, tests_written, tests_passed (and failure_step/failure_reason on failure).

### Step 2.3 — Process Resolver Result

Parse the subagent's response. Extract: `status`, `branch_name`, `pr_number`, `pr_url`, `tests_written`, `failure_step`, `failure_reason`.

**On success:**
```
  ✓ Resolved #{issue_number}
    Branch:  {branch_name}
    PR:      #{pr_number}
    Changed: {files_changed} files
    Tests:   {tests_written} written, {tests_passed} passed
```

Proceed to Phase 3 (Review).

**On already_resolved:**

The resolver subagent may report that the issue is already fixed (status: `already_resolved`). In this case, skip the review/fix/merge phases entirely and move on.

```
○ #{issue_number} already resolved — skipping
```

Continue to the next iteration.

**On failure:**

```
✗ Resolution failed for #{issue_number} at step {failure_step}

  {failure_reason}
```

**Autonomous behavior:** Log the failure, add the issue to the skip list, and continue to the next issue. Failed issues can always be retried later — stopping the entire loop wastes time on issues that might succeed.

```
⚠ Skipping #{issue_number} — will retry on next run.
  Continuing to next issue...
```

If `autopilot.pause_on_failure` is explicitly set to `true` in config, stop the loop instead:
```
⚠ Auto-pilot paused due to failure (pause_on_failure: true).

  Failed on:  #{issue_number} — {title}
  Step:       {failure_step}
  To resume:  fix the issue, then /auto-pilot
  To skip:    /auto-pilot --skip {issue_number}
```

---

## Phase 3 & 4 — PR Review (via /issue-pr-review)

After the PR is created, the auto-pilot delegates review, testing, CI checking, fixing, and merging to the `/issue-pr-review` skill in auto mode. This replaces the former inline review-fix loop with a more comprehensive pipeline that includes CI status monitoring.

### What issue-pr-review does in auto mode

1. **Script pre-pass** — runs lint/format auto-fix tools, then tests (zero LLM tokens)
2. Analyzes PR changes (cycle 1: fresh reviewer; cycles 2+: reuses same reviewer via SendMessage)
3. Runs all tests (unit, integration, e2e) and build/compile
4. Checks CI status (polls GitHub Actions until complete)
5. Fixes only `action: "fix"` issues — reuses the same fixer agent across cycles
6. Repeats steps 2-5 up to `review_cycles` cycles (default: 3)
7. **Confirmation pass** — spawns one fresh reviewer for unbiased final check

See `skills/issue-pr-review/SKILL.md` for the full pipeline.

### Step 3.1 — Spawn PR Review Subagent

```
● Reviewing PR #{pr_number}...
  ⟶ Spawning PR review subagent...
```

Use the **PR Reviewer Subagent** prompt from `references/subagent-prompts.md`, substituting `{pr_number}`. The subagent runs the full `/issue-pr-review --auto` pipeline: review, test, CI check, fix, repeat. It does NOT merge — merging is the main agent's job in Phase 5.

### Step 3.2 — Process Review Result

Parse the subagent's response:

**On PASS:**
```
  ✓ PR #{pr_number} review passed
    Review cycles: {review_cycles}
    Issues found/fixed: {issues_found}/{issues_fixed}
```
Proceed to Phase 5 (Merge).

**On NEEDS_FIX (review cycles exhausted with remaining issues):**

The review-fix loop tried `review_cycles` times (default: 3) but could not resolve all issues. The behavior depends on whether the original issue is critical.

#### Non-critical issues: create follow-up issue, merge PR, continue

For non-critical issues (no `critical` or `priority:critical` label), the auto-pilot captures the unresolved problems as a new GitHub issue, then merges the PR to preserve the progress that was made, and continues to the next issue.

**Step 1 — Create follow-up issue:**

```bash
gh issue create \
  --title "Follow-up: unresolved review issues from #{issue_number}" \
  --label "auto-pilot-followup" \
  --body "$(cat <<'EOF'
<!-- gitissue:normalized v1 -->

## Type
Enhancement

## Context
Auto-pilot resolved #{issue_number} ({issue_title}) but the review-fix loop could not resolve all issues within {review_cycles} cycles. The PR #{pr_number} was merged with the following issues remaining.

## Description
The following review issues were not resolved:

{remaining_issues_bulleted}

## Acceptance Criteria
- [ ] All listed review issues are addressed
- [ ] Tests pass

## Technical Notes
- Original issue: #{issue_number}
- PR with partial fix: #{pr_number}
- Branch: {branch_name}
- Review cycles attempted: {review_cycles}

## Metadata
- **Priority:** medium
- **Effort:** small
EOF
)"
```

```
⚠ PR #{pr_number} has unresolved issues after {review_cycles} cycles

  Remaining issues:
    ● {issue_description_1}
    ● {issue_description_2}

  ✓ Created follow-up issue #{followup_number}
    "Follow-up: unresolved review issues from #{issue_number}"
  ⟶ Merging PR with partial fix...
```

**Step 2 — Merge the PR anyway:**

The PR contains valid progress (the resolver completed, and some or all review issues may have been fixed). Merge it to avoid losing that work:

```bash
gh pr merge {pr_number} --squash --delete-branch
```

```
  ✓ PR #{pr_number} merged (partial fix) — #{issue_number} closed
    Unresolved issues tracked in #{followup_number}
  Continuing to next issue...
```

If merge fails (branch protection, etc.), leave the PR open and note it:
```
  ⚠ Merge failed for PR #{pr_number} — PR left open
    Unresolved issues tracked in #{followup_number}
  Continuing to next issue...
```

#### Critical issues: stop and ask the user

If the original issue has any label in `autopilot.critical_labels` (default: `["critical", "priority:critical"]`), the auto-pilot does **not** create a follow-up or auto-merge. Instead, it stops the loop and presents the situation to the user for a decision. Critical issues deserve human judgment — an incomplete fix could make things worse.

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

The loop pauses and waits for the user's response. Based on the user's choice:
- **Option 1:** Create follow-up issue (same as non-critical flow), merge PR, continue loop
- **Option 2:** Leave PR open, do not merge, continue loop to the next issue
- **Option 3:** Skip issue, leave PR open, continue loop

---

## Phase 5 — Merge

### Step 5.1 — Pre-merge Checks

Before merging, verify:

1. **PR is mergeable** — no conflicts, CI passing (if configured)
2. **No blocking reviews** — no "request changes" reviews from other humans

```bash
gh pr view {pr_number} --json mergeable,reviewDecision,statusCheckRollup
```

If not mergeable:
```
⚠ PR #{pr_number} is not mergeable

  Reason: {conflict / failing checks / review requested}
  PR left open — continuing to next issue.
```

**Autonomous behavior:** Leave the PR open and move on. The PR is already created with all changes — it can be merged manually later or picked up on the next auto-pilot run. Only pause if `autopilot.pause_on_failure` is explicitly `true`.

### Step 5.2 — Merge

First, check `autopilot.auto_merge`. If it is explicitly set to `false`, skip the merge entirely and continue to the next issue:
```
○ PR #{pr_number} ready for manual merge (auto_merge: false)
  https://github.com/owner/repo/pull/{pr_number}
  Continuing to next issue...
```

If `autopilot.auto_merge` is `true` (the default), merge the PR:

```bash
gh pr merge {pr_number} --squash --delete-branch
```

```
✓ PR #{pr_number} merged — #{issue_number} closed
  https://github.com/owner/repo/pull/{pr_number}
```

If merge fails (branch protection, required approvals, etc.), leave the PR open and continue:
```
⚠ Merge failed for PR #{pr_number} — PR left open
  Continuing to next issue...
```

### Step 5.3 — Cleanup

```bash
git checkout {default_branch}
git pull --rebase origin {default_branch}
git branch -d {branch_name} 2>/dev/null
```

---

