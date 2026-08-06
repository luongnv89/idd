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

From `summary.suggested_order` in `.gitissue/triage.json` (the triage execution order), select the first issue that is:
- **Not blocked** — no unresolved dependencies in the triage graph
- **Not skipped** — not in the `--skip` list, the `skip_labels` set, or the **session skip list** (the in-memory list this run appends to: failed issues from Phase 2.3, and dependency-blocked issues from Step 5.1b / Phase 3-4 Step 2a). Consult all three every iteration — the session skip list is what stops a dependency-blocked issue from being re-picked after the loop continues past it.
- **Not assigned** — not assigned to another user (unless there are no unassigned issues)
- **Open** — state is `open`

```
● Picking next issue from triage order...
  Candidates: {N} issues in summary.suggested_order
  Selected:   #{issue_number} — {issue_title}
```

If no eligible issue is found (all blocked, skipped, or assigned):
```
⚠ No eligible issues to pick

  Blocked:   {blocked_count} issues (waiting on dependencies)
  Skipped:   {skipped_count} issues (skip labels or --skip)
  Dep-blocked: {dep_blocked_count} issues (PR open, waiting on a dependency merge)
  Assigned:  {assigned_count} issues (assigned to others)

  To unblock: merge the dependency PR(s), resolve dependency issues, or use
              --skip to bypass
```
Stop. Count the issues this run added to the session skip list from the
dependency gate on their **own** `Dep-blocked` line rather than folding them into
`Skipped` — their PRs are open and merge-ready as soon as the dependency lands,
which is a different next action from a `wontfix` label. Omit the line when the
count is zero. **This is the only place a run ends for dependency reasons** (see
*Step 5.1b — Dependency Gate*); the gate itself never stops the loop.

### Step 1.3 — Display Plan and Auto-Start

On the first iteration, display the execution plan and immediately begin — no confirmation prompt. The user's invocation of `/auto-pilot` is the confirmation.

```
◆ Auto-Pilot Plan
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Issues to process:  {eligible_count} (of {total_open} open)
  Limit:              {max_iterations}
  Review cycles:      {review_cycles}
  Merge mode:         {conservative | balanced | aggressive}
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

The main agent syncs to the default branch directly (this is lightweight — no code reading). Use the stash-first pattern to protect any uncommitted work that may have appeared since the pre-flight stash (see `references/docs/sync-conventions.md`):

```bash
git checkout {default_branch}
dirty=0
if [ -n "$(git status --porcelain)" ]; then
  git stash push -u -m "pre-sync: {default_branch}"
  dirty=1
fi
git fetch origin
git pull --rebase origin {default_branch}
if [ "$dirty" -eq 1 ]; then
  git stash pop || {
    echo "✗ Stash pop failed — recover with: git stash list && git stash show -p stash@{0}"
    exit 1
  }
fi
```

If the rebase itself fails (merge conflict from a prior iteration), attempt auto-resolution:

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

Launch a subagent using the Agent tool to perform the entire resolve pipeline. This keeps all codebase reading, code writing, and test execution out of the main agent's context. Pass only `description` and `prompt` — do NOT set `subagent_type`. The resolver is a **skill** invoked from inside the prompt (via `../issue-resolver/SKILL.md`), not an agent type; passing `subagent_type: "issue-resolver"` fails with `Agent type 'issue-resolver' not found`.

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
  Outcome: skipped
```

Record the iteration outcome as `skipped` and continue to the next iteration.

**On failure:**

```
✗ Resolution failed for #{issue_number} at step {failure_step}

  {failure_reason}
  Outcome: failed
```

**Autonomous behavior:** Log the failure as outcome `failed`, add the issue to the skip list, and continue to the next issue. Failed issues can always be retried later — stopping the entire loop wastes time on issues that might succeed.

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

See the `../issue-pr-review/SKILL.md` skill for the full pipeline.

### Step 3.1 — Spawn PR Review Subagent

```
● Reviewing PR #{pr_number}...
  ⟶ Spawning PR review subagent...
```

Use the **PR Reviewer Subagent** prompt from `references/subagent-prompts.md`, substituting `{pr_number}`. The subagent runs the full `/issue-pr-review --auto --no-merge` pipeline: review, test, CI check, fix, repeat. It does NOT merge — merging is the main agent's job in Phase 5. The `--no-merge` flag suppresses auto-merge in `--auto` mode so the reviewer never steals the merge step from Phase 5's mode gate and dependency gate.

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

The review-fix loop tried `review_cycles` times (default: 3) but could not resolve all issues. The behavior depends on (a) whether the original issue is critical and (b) the configured `autopilot.mode` (and `autopilot.merge_partial` for `aggressive`).

#### Non-critical issues: mode-gated partial-merge decision

For non-critical issues (no `critical` or `priority:critical` label), the auto-pilot always captures the unresolved problems as a follow-up issue. Whether the original PR is then merged depends on the mode:

| Mode (effective) | `merge_partial` | Behavior | Outcome label |
|------------------|-----------------|----------|----------------|
| `conservative` | n/a (ignored) | follow-up created, PR left open | `left_open` |
| `balanced` (default) | n/a (ignored) | follow-up created, PR left open | `left_open` |
| `aggressive` | `false` (default) | follow-up created, PR left open | `left_open` |
| `aggressive` | `true` | follow-up created, PR merged anyway | `partial_followup` |

The default install (`mode: balanced`) **never** auto-merges a PR with unresolved fixable review issues; only clean PRs are merged. Aggressive partial-merge is unreachable without setting both `mode: aggressive` and `merge_partial: true` in `.gitissue.yml`.

**Step 1 — Create follow-up issue (always, regardless of mode):**

```bash
gh issue create \
  --title "Follow-up: unresolved review issues from #{issue_number}" \
  --label "auto-pilot-followup" \
  --body "$(cat <<'EOF'
<!-- gitissue:normalized v1 -->

## Type
Improvement

## Description
Auto-pilot resolved #{issue_number} ({issue_title}) but the review-fix loop could not resolve all issues within {review_cycles} cycles.

The following review issues were not resolved:

{remaining_issues_bulleted}

Original issue #{issue_number}; partial fix PR #{pr_number} ({branch_name}); {review_cycles} review cycles; mode {mode} (merge_partial={merge_partial}).

## Acceptance Criteria
- [ ] All listed review issues are addressed
- [ ] Tests pass

## Metadata
**Priority:** P2 (high confidence)
**Effort:** S (medium confidence)
**Labels:** auto-pilot-followup
EOF
)"
```

**Step 2 — Mode-gated merge decision:**

Compute the **effective mode** by reading `autopilot.mode` if set; if unset and `autopilot.auto_merge` is not explicitly present in the file, use `balanced`; if unset but `autopilot.auto_merge` is explicitly present, apply the legacy mapping (`auto_merge: true` → aggressive+merge_partial; `auto_merge: false` → conservative). If the effective mode is `aggressive` AND `autopilot.merge_partial` is `true`, the PR may be merged to preserve partial progress after the dependency gate passes; otherwise leave the PR open.

**Step 2a — Dependency gate (before any merge):**

Whenever Step 2 would merge a PR (aggressive + `merge_partial: true`), run **Step 5.1b — Dependency Gate** first using the originating issue `#{issue_number}`. SPEC §2 requires this check before **any** automated merge, including partial merges. If the gate finds unsatisfied dependencies, do **not** merge: print the structured alert from `references/error-messages.md` (*PR blocked by unmerged dependency*), record the iteration outcome as `blocked_by_dependency`, leave the PR open, add the issue to the session skip list, and **continue to the next eligible issue** (same record-and-continue semantics as Phase 5 — see *Record and continue when any dependency is unsatisfied*). If all dependencies are satisfied, proceed to Step 2b.

**Step 2b — Merge (only when aggressive + merge_partial: true and Step 2a passed):**

```bash
gh pr merge {pr_number} --squash --delete-branch
```

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

If the merge command itself fails (branch protection, etc.):
```
  ⚠ Merge failed for PR #{pr_number} — PR left open
    Unresolved issues tracked in #{followup_number}
    Outcome: left_open
  Continuing to next issue...
```

If NOT merging (`conservative`, `balanced`, or `aggressive` + `merge_partial: false`):

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

Record the iteration outcome (`partial_followup` or `left_open`) for the final summary.

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

### Step 5.1b — Dependency Gate

If `autopilot.respect_dependencies` is `true` (default), check whether the originating issue declares any dependencies that are not yet merged. The convention is documented in `references/docs/idd-methodology.md` (Issue Dependencies). If the config is `false`, skip this step and proceed to Step 5.2.

#### Parse dependency markers

Fetch the issue body (already cached from Phase 1's triage call to `gh issue list ... --json body`, or re-fetch with `gh issue view N --json body` if running in explicit-list mode) and extract every `Depends on #N` and `Blocked by #N` reference. The match is case-insensitive and tolerates list/sentence/colon shapes:

```
- Depends on #12
Blocked by: #15, #20
This depends on #8
```

For each line that matches `(?im)\b(?:depends\s+on|blocked\s+by)\b`, collect **local** issue numbers only (SPEC §2 MUST-ignore for cross-repo):

1. **Strip cross-repo tokens** on that line — remove every `\S+/\S+#\d+` match (e.g. `acme/lib#15`) so its trailing digits are never captured.
2. **Capture bare refs** on the remainder with a negative lookbehind guard: `(?<![\w/])#(\d+)` — this matches `#12` and comma lists (`#12, #15`) but not the `#15` inside `acme/lib#15` if a token was missed.

Example: `Blocked by: acme/lib#15, #12` → gate on **#12 only**. `Depends on #12, #15` → gate on **#12** and **#15**. The reference implementation is `scripts/dependency_gate_parse.py` (`extract_dependency_issue_numbers`). If no local markers remain, the gate is satisfied; proceed to Step 5.2.

**Cycle guard:** If issue A's body references its own number (`#A`), log a warning and skip the gate (treat as satisfied). The auto-pilot must never block a PR on its own issue number. Multi-hop cycles (A → B → A) are not detected here — they would require traversing each dependency's body, which is out of scope for the per-merge gate; the fail-safe is that any genuinely-cyclic issue set surfaces as `blocked_by_dependency` on each affected issue and requires user intervention before those PRs can merge — the loop still advances past them. The check is:

```
⚠ Dependency cycle detected for #{issue_number} — skipping gate
  Resume manually after fixing the issue body.
```

#### Resolve each dependency

For each captured `#N`, ask GitHub: "is this issue closed by a merged PR?" GitHub's GraphQL exposes the linked-PR set directly via `closedByPullRequestsReferences` on the Issue type, which `gh issue view` surfaces:

```bash
gh issue view N --json number,state,title,closedByPullRequestsReferences
```

The `closedByPullRequestsReferences.nodes[]` array contains every PR that closes (or would close) issue #N, each with `number`, `state` (`OPEN` / `CLOSED` / `MERGED`), and `url`. This is the authoritative answer — no need to grep PR bodies for `Closes #N`.

A dependency is **satisfied** when both:
- The issue's `state` is `CLOSED`, AND
- Either `closedByPullRequestsReferences` is empty (issue was closed manually with no PR — treat as resolved), OR every PR in `closedByPullRequestsReferences` has `state: MERGED`.

A dependency is **unsatisfied** when any of:
- The issue's `state` is `OPEN` (regardless of PR state — the issue itself isn't done), OR
- The issue is `CLOSED` but at least one referenced PR has `state: OPEN` (rare race window — treat as unsatisfied to be safe).

For each unsatisfied dependency, record `{issue_number, issue_title, issue_state, pr_number, pr_state}` for the alert. If `closedByPullRequestsReferences` is unavailable on older `gh` versions (pre-2.45), fall back to:

```bash
gh search prs "is:open" "Closes #N" --json number,state,url --limit 5
```

— which finds the open PRs that would close issue `#N` once merged. The fallback is scoped to `is:open` because it only needs to surface *blocking* PRs (the merged-issue path is already short-circuited by the `state == CLOSED` check above — a CLOSED issue with no in-flight PRs satisfies the gate without consulting the fallback). Treat the result as the unmerged-PR set for the open-issue case.

Collect the unsatisfied set.

#### Record and continue when any dependency is unsatisfied

If the unsatisfied set is non-empty, do **not** merge. Print the structured alert from `references/error-messages.md` (*PR blocked by unmerged dependency*), record the iteration outcome as `blocked_by_dependency`, and **continue to the next eligible issue**. The headline names the dependency's PR directly (when known) so the user's next action is one step:

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

When a dependency issue has no linked PR (`closedByPullRequestsReferences` is empty and the issue is still open), the bullet shows `no linked PR` in place of the PR state — the user knows they need to drive that issue forward, not wait on a PR. When the dependency is open with multiple linked PRs, list each one. The headline picks the first unsatisfied dependency to keep the one-line summary actionable; the bullets enumerate the rest.

Set the iteration outcome to `blocked_by_dependency`, leave the PR for the current issue **open and unchanged**, and **advance to the next eligible issue**. Not merging is already the safe outcome; the rest of the backlog rarely shares this dependency, and halting a 30-issue run at iteration 3 strands every remaining eligible issue.

Before advancing, add `#{issue_number}` to the **session skip list** — the same in-memory list Phase 2.3 uses for failed issues. This is required, not cosmetic: when the dependency issue is `CLOSED` but its PR is still `OPEN` (the race case the gate treats as unsatisfied), Phase 1's triage graph sees the dependency as done and would re-pick `#{issue_number}` on the next iteration; the resolver would then abort on its "PR already targets this issue" guard and the run log would gain a second, bogus `failed` line for an issue that was already recorded. Skipping it for the rest of the session keeps the invariant of **exactly one run-log line per processed issue** (`outcome: blocked_by_dependency`, see `references/run-log.md`).

The loop therefore stops on dependency grounds **only when no eligible issue remains** — through the existing `⚠ No eligible issues to pick` stop condition in Phase 1, never from the gate itself.

If a referenced `#N` does not exist (404 from `gh issue view`), log a warning and treat that single reference as satisfied (skip it). Do not block on a typo.

```
⚠ Dependency #{N} not found — ignoring
```

If all dependencies are satisfied, log and proceed:

```
○ Dependency gate passed — {n} dependency(ies) merged
```

Continue to Step 5.2.

### Step 5.2 — Merge (mode-gated)

Merge behavior is controlled by `autopilot.mode`. This step runs for clean PRs after review PASS. Partial merges (Phase 3-4 Step 2) use the same Step 5.1b dependency gate before `gh pr merge`.

**Compute the effective mode:**

1. If `autopilot.mode` is set in `.gitissue.yml`, use it directly (`conservative` | `balanced` | `aggressive`).
2. If `autopilot.mode` is unset and neither `autopilot.mode` nor `autopilot.auto_merge` appears in the file → effective mode = `balanced` (zero-config default).
3. If `autopilot.mode` is unset but `autopilot.auto_merge` is **explicitly present** in the file, fall back to legacy interpretation:
   - `autopilot.auto_merge: false` → effective mode = `conservative`
   - `autopilot.auto_merge: true` → effective mode = `aggressive` (with `merge_partial: true`, preserving prior 2.1.x behavior)

**Decision table for clean PRs:**

| Effective mode | Action | Outcome label |
|----------------|--------|----------------|
| `conservative` | leave PR open for manual merge | `left_open` |
| `balanced` | merge | `merged` |
| `aggressive` | merge | `merged` |

If the mode forbids merge (`conservative`):
```
○ PR #{pr_number} ready for manual merge (mode: conservative)
  https://github.com/owner/repo/pull/{pr_number}
  Outcome: left_open
  Continuing to next issue...
```

If the mode allows merge (`balanced` or `aggressive`):

```bash
gh pr merge {pr_number} --squash --delete-branch
```

```
✓ PR #{pr_number} merged — #{issue_number} closed
  https://github.com/owner/repo/pull/{pr_number}
  Outcome: merged
```

If the merge command fails (branch protection, required approvals, conflicts, etc.), leave the PR open and continue:
```
⚠ Merge failed for PR #{pr_number} — PR left open
  Outcome: left_open
  Continuing to next issue...
```

Record the iteration outcome (`merged` or `left_open`) for the final summary.

### Step 5.3 — Cleanup

Use the stash-first sync to protect any uncommitted changes that may have accumulated between iterations (see `references/docs/sync-conventions.md`):

```bash
git checkout {default_branch}
dirty=0
if [ -n "$(git status --porcelain)" ]; then
  git stash push -u -m "pre-cleanup: {default_branch}"
  dirty=1
fi
git fetch origin
git pull --rebase origin {default_branch}
if [ "$dirty" -eq 1 ]; then
  git stash pop || {
    echo "✗ Stash pop failed — recover with: git stash list && git stash show -p stash@{0}"
    exit 1
  }
fi
git branch -d {branch_name} 2>/dev/null
```

---

