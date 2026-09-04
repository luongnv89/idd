# /auto-pilot — Phases 3 & 4: PR Review

One part of `references/phases.md` — the index that maps every step to its file. Read only the part for the step you are on; a pointer to another step (*Step N.n*, *Phase N*) resolves through that index.

## Phase 3 & 4 — PR Review (via /issue-pr-review)

After the PR is created, the auto-pilot delegates review, testing, CI checking, fixing, and merging to the `/issue-pr-review` skill in auto mode. This replaces the former inline review-fix loop with a more comprehensive pipeline that includes CI status monitoring.

### What issue-pr-review does in auto mode

1. **Script pre-pass** — runs lint/format auto-fix tools (always), then tests (zero LLM tokens) — that test run is skipped when the PR carries a valid QA handoff marker recording the suite already passing on the current head SHA
2. Analyzes PR changes (cycle 1: fresh reviewer; cycles 2+: reuses same reviewer via SendMessage). On a resolver-authored PR still carrying a valid QA handoff marker bound to the current head SHA, cycle 1 collapses into the fresh confirmation pass, so the one independent full-strength review the PR gets is the unbiased one — no reviewer spawn is saved (the confirmation pass is fix-conditional, so a clean PR gets one pass either way); the saving is the skipped local test runs in step 3
3. Runs all tests (unit, integration, e2e) and build/compile — skipped only when that same marker records the suite already passing on this exact commit
4. Checks CI status (polls GitHub Actions until complete) — always, never skipped by the marker
5. Fixes only `action: "fix"` issues — reuses the same fixer agent across cycles
6. Repeats steps 2-5 up to `review_cycles` cycles (default: 3)
7. **Confirmation pass** — spawns one fresh reviewer for unbiased final check

See the `../issue-pr-review/SKILL.md` skill for the full pipeline.

### Step 3.1 — Spawn PR Review Subagent

```
● Reviewing PR #{pr_number}...
  ⟶ Spawning PR review subagent...
```

Use the **PR Reviewer Subagent** prompt from `references/subagent-prompts.md`, substituting `{pr_number}` and, when Step 1.2b captured it, `{issue_payload_ids}` for the issue this PR closes. **The reviewer reads identifying fields from that payload only** — and gets only those, because Step 1.2b trimmed the block to `number`, `title` and `labels`, so the scope is structural rather than instruction-only. This spawn happens strictly *after* Phase 2's resolver ran its Step 0d normalization (`gh issue edit` + re-read), so a Phase-1 body would be superseded by construction — on an unnormalized backlog issue, 0d is what *creates* the structured Acceptance Criteria section. That is why the body is dropped from this block rather than fenced off in prose. The reviewer's acceptance-criteria verification therefore always re-fetches the live body, and the #36 `acceptance_criteria` hard-block is never evaluated against the payload. The subagent runs the full `/issue-pr-review --auto --no-merge` pipeline: review, test, CI check, fix, repeat. It does NOT merge — merging is the main agent's job in Phase 5. The `--no-merge` flag suppresses auto-merge in `--auto` mode so the reviewer never steals the merge step from Phase 5's mode gate and dependency gate.

### Step 3.2 — Process Review Result <!-- a:ap-step32-review-result -->

Parse the subagent's response. Extract: `result`, `review_cycles`, `issues_found`,
`issues_fixed`, `issues_noted`, `remaining_issues`, `pre_pass_fixes`,
`tests_passed`, `ci_status`.

**Retain `ci_status` verbatim** — the string exactly as returned (`passed@<sha40>`,
`failed@<sha40>`, `no_ci`, or a bare value), never re-derived and never summarised
to a boolean. It is the only input to *Step 5.1a — CI verdict gate* that **this
step** supplies — the gate's other inputs, `headRefOid` and `statusCheckRollup`,
it reads live in Phase 5, and it decides on its own conditions; never restate
them here. It is also the one returned field nothing in this step prints, so it is
the one an executing agent is likeliest to drop. Dropping it is not unsafe — the gate
reads a missing field as `absent` and runs today's full wait — but the run then
re-polls CI the reviewer already waited on, and the gate does nothing on every
iteration while appearing to be in force.

**Checkpoint (post-review).** Before acting on the result, record it with the
*Step 1.0b* procedure — `{"phase": "merge", "current": {"phase": "merge"}}` on a
PASS, `{"phase": "fix", "current": {"phase": "fix"}}` when the fix cycles are
still running. During a parallel drain, include the same phase update for the
matching `lanes[]` entry. A resume that lands here re-enters at review or merge
on the recorded PR rather than re-running the resolve.

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

Compute the **effective mode** per the *Resolution rules* under *Merge Modes* in SKILL.md. If the effective mode is `aggressive` AND `autopilot.merge_partial` is `true`, the PR may be merged to preserve partial progress after the dependency gate passes; otherwise leave the PR open.

**Step 2a — Dependency and CI gates (before any merge):**

Whenever Step 2 would merge a PR (aggressive + `merge_partial: true`), run **Step 5.1b — Dependency Gate** first using the originating issue `#{issue_number}`, then run the shared **Step 5.1a — CI verdict gate** against the current PR head. SPEC §2 requires these checks before **any** automated merge, including partial merges. The CI gate may accept `ci_verdict = trusted` only when the live head still equals the `passed@<sha40>` `ci_status` SHA and the same live rollup is non-empty and entirely green. Otherwise run the documented waiter/fallback for this head; accept only a settled `pass`, `none` with `none_confirmed: true`, or a successfully verified equivalent manual fallback. A stale or absent status, failed or pending checks, an unsettled terminal snapshot, an unconfirmed empty result, an unavailable or failed fallback, or any head change leaves the PR open. If either gate finds an unsatisfied dependency or non-mergeable CI, do **not** merge: print the structured alert from `references/error-messages.md`, record the iteration outcome as `blocked_by_dependency` or `left_open`, leave the PR open, add the issue to the session skip list, and **continue to the next eligible issue** (same record-and-continue semantics as Phase 5). Only when both gates pass may the flow proceed to Step 2b.

**Step 2b — Merge (only when aggressive + merge_partial: true and both gates passed):** <!-- a:ap-step2b-merge -->

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

**Before continuing, run *Step 1.6 — Update the triage cache after a merge*.**
This merge closed `#{issue_number}` exactly as finally as Step 5.2's does, and
Step 1.6 is the only thing that takes a closed issue back out of
`summary.suggested_order` — a partial merge that skips it leaves the issue in
the cached order, on no skip list, for *Step 1.2* to pick again next iteration.
The failed-merge path below closed nothing, so it runs nothing.

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

**Checkpoint (post-fix-cycle).** Record the outcome the fix cycles reached with
the *Step 1.0b* procedure before advancing —
`{"phase": "cleanup", "current": {"phase": "cleanup", "outcome": "left_open"}}` —
so a run interrupted between "the cycles are spent" and "the next issue starts"
resumes knowing the review is finished. Without it a resume re-enters review and
burns another `review_cycles` on a PR that already exhausted them.

#### Critical issues: stop and ask the user <!-- a:ap-critical-issues -->

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

**After Option 1's merge,
run *Step 1.6 — Update the triage cache after a merge*.**
That merge closed `#{issue_number}` exactly as finally as Step 5.2's
does, and Step 1.6 is the only thing that takes a closed issue back out of
`summary.suggested_order` — a user-chosen merge that skips it leaves the issue in
the cached order, on no skip list, for *Step 1.2* to pick again next iteration.
Options 2 and 3 merged nothing, so they run nothing.

---
