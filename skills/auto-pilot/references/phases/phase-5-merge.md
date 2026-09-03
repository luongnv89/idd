# /auto-pilot — Phase 5: Merge

One part of `references/phases.md` — the index that maps every step to its file. Read only the part for the step you are on; a pointer to another step (*Step N.n*, *Phase N*) resolves through that index.

## Phase 5 — Merge <!-- a:ap-phase5-merge -->

### Step 5.1 — Pre-merge Checks <!-- a:ap-premerge-checks -->

Before merging, verify:

1. **PR is mergeable** — no conflicts, CI passing (if configured)
2. **No blocking reviews** — no "request changes" reviews from other humans

```bash
gh pr view {pr_number} --json mergeable,reviewDecision,statusCheckRollup,headRefOid
```

`headRefOid` rides along on this one read because *Step 5.1a* needs it and a second `gh pr view` three lines later would be the duplicated work this whole phase exists to remove. `statusCheckRollup` is likewise already in hand at that instant, so the gate can corroborate a `trusted` verdict for free.

**Consult *Step 5.1a — CI verdict gate* first.** Under `ci_verdict = trusted` the whole wait below is already answered and is skipped; on `stale` or `absent` it runs exactly as written.

When checks are still pending, do not read `statusCheckRollup` in a loop — run `python3 references/scripts/gi-ci-wait.py {pr_number} --interval {review.ci_poll_interval} --timeout {review.ci_timeout}` once and read its JSON verdict. A non-empty `pass` is mergeable only when `settled: true`; an unsettled terminal snapshot is `pending` for merge purposes. **`none` merges only when `none_confirmed` is `true`** — that field is the difference between "this repository configures no checks" (step 1 above reads "CI passing (*if configured*)", and a repo without CI must not deadlock the loop) and "the checks have not registered yet", which is what a repository *with* CI reports for the first seconds after a push. A `none` with `none_confirmed: false` is a pending answer wearing a `none` label: leave the PR open, exactly as for `pending`. `fail`, `pending`, invalid or unavailable results, and any failed manual fallback all leave the PR open. Exit 3 (invalid input — a non-numeric PR number, or a non-positive interval or timeout) is a stop, not a degrade. A missing `python3`, exit 2 (the script path did not resolve), or exit 4 degrades to the concrete merge-safe manual procedure in `references/examples.md` (*Merge requires CI checks*); manually verified green results must satisfy the same current-head, complete-rollup, check-set stability, and none-grace requirements. Only a settled `pass`, confirmed `none`, or equivalent verified manual result may proceed to merge.

If not mergeable:
```
⚠ PR #{pr_number} is not mergeable

  Reason: {conflict / failing checks / review requested}
  PR left open — continuing to next issue.
```

**Autonomous behavior:** Leave the PR open and move on. The PR is already created with all changes — it can be merged manually later or picked up on the next auto-pilot run. Only pause if `autopilot.pause_on_failure` is explicitly `true`.

### Step 5.1a — CI verdict gate <!-- a:ap-ci-verdict-gate -->

**Single home of the CI-trust rule.** Phase 3-4's reviewer subagent already ran
`/issue-pr-review` Step 5 on this PR and returned `ci_status` **bound to the
commit it waited on** — `passed@<sha40>` / `failed@<sha40>`, or a bare `no_ci`
(*Binding the verdict to a commit* in that skill's
`references/prepass-tests-ci-mechanics.md`). Re-running the whole wait here is
duplicated work whenever the head has not moved since **and** the live rollup
already reports every check green — both conditions, never the first alone
(issue #256).

Set exactly one variable:

```
ci_verdict = trusted | stale | absent
```

| State | When | Effect |
|-------|------|--------|
| `trusted` | `ci_status` is `passed@<sha40>`, that SHA equals the PR's live head, **and** the same read's `statusCheckRollup` is non-empty with every check in it green | Step 5.1's wait is skipped; treat CI as green |
| `stale` | the returned SHA differs from the live head | run the full wait below, unchanged |
| `absent` | no `ci_status` field, a bare or unparsable value, `no_ci`, `failed@…`, or `review.check_ci: false` | run the full wait below, unchanged |

The one verification, which replaces the poll: read `headRefOid` from **Step
5.1's own `gh pr view {pr_number} --json mergeable,reviewDecision,statusCheckRollup,headRefOid`** — the
field is requested there precisely so this gate costs nothing. Issue no second
`gh pr view`. One `--json` read against one PR, shared with the pre-merge checks
— not a poll loop, not a second `gi-ci-wait.py`
run. If that read fails, or the field is absent, the answer is `absent`.
`statusCheckRollup` from the same read is the corroboration, and it is
**positive, not negative**: a verdict is `trusted` only when that rollup is
non-empty and every check in it has concluded green. A rollup that shows any
failed or pending check is `absent` — and so is one that shows **nothing**:
empty, absent from the reply, or unreadable. That last case is the one an
"is anything red?" reading would wave through, and it is exactly the case the
full wait treats as not-clean: `gi-ci-wait.py`'s `none` counts as clean only when
`none_confirmed` is true, and an unconfirmed `none` leaves the PR open (Step 5.1).
Corroborating positively keeps this gate's answer on the same side of that line.

**Head-SHA equality does not cover a moved base.** `pull_request` checks run
against the merge result, so a base branch that advanced under this PR since the
reviewer's wait can change the answer with `headRefOid` unchanged. This is
today's exposure, not something this gate introduces — but read "nothing left to
wait for" as "nothing left to wait for *on this head*", and do **not** read Step
5.1's `mergeable` as covering it. `mergeable` answers MERGEABLE / CONFLICTING /
UNKNOWN: GitHub does recompute it against the current base, so it catches a base
that moved **into conflict**, and nothing else — a clean, fast-forwardable
advance leaves it MERGEABLE. The full wait this gate skips would not catch it
either, since GitHub does not re-run a PR's checks merely because its base
advanced, so the poll would read the same rollup this gate already read. The
residual is unchanged from today; this gate neither widens nor closes it.

**`failed@<sha40>` is never `trusted`.** A failing verdict already leaves the PR
open under Step 5.1's own rules; routing it through this gate would only let a
`trusted` label attach to a red build. Read it as `absent` and let the wait
below reach the same "not mergeable" outcome it reaches today.

**Fail-safe: any doubt is `absent`.** A missing field, a SHA that is not 40 hex
characters, a `headRefOid` that cannot be read, a `pending` or `none` that
somehow arrived here — every one of them runs today's wait, byte-for-byte. The
gate can only ever *remove* a duplicate wait; it can never merge something the
wait would have blocked.

**This is a subagent return value, not a PR-body marker — the distinction is
load-bearing.** The QA handoff marker is written into a PR body by whoever
authored the PR, which is why `/issue-pr-review` states that its Step 5 CI wait
is **never skipped by the marker**, and nothing here changes that. `ci_status` is
returned in-process by a subagent *this run spawned*, reporting a wait it just
performed. That makes it **harder to forge than a PR-body marker — not
attacker-free.** That subagent read the live issue body, the PR body and the diff,
so attacker-authored text is in its context and can reach the value it returns;
naming the head SHA it just read is within reach of the same text, so head-SHA
equality *binds* the verdict to a commit, it does not authenticate it. What the
gate actually leans on is the live `statusCheckRollup` above, read by this agent
from GitHub in the same call as `headRefOid`: the fast path is taken only when
GitHub itself, read here, already reports every check green. Trusting a verdict
on those two conditions is not a loosening of the marker rule; a marker still
buys nothing at this step.

**No new config key.** `review.adaptive_depth: false` disables this gate — it
already disables the QA handoff gate — and forces `absent`.

One `○` line, per `references/docs/terminal-style.md`:

```
○ CI verdict: trusted (passed @ 9f2c1ab) — head unchanged, checks green, no re-poll
○ CI verdict: stale (head moved) — waiting on CI
○ CI verdict: absent — waiting on CI
```

### Step 5.1b — Dependency Gate <!-- a:ap-dependency-gate -->

If `autopilot.respect_dependencies` is `true` (default), check whether the originating issue declares any dependencies that are not yet merged. The convention is documented in `references/docs/idd-methodology.md` (Issue Dependencies). If the config is `false`, skip this step and proceed to Step 5.2.

#### Parse dependency markers

Read the issue body from Step 1.2b's held `{issue_payload}` resolution snapshot. Only when that issue has no complete held snapshot, fetch with `python3 references/scripts/gi-issue.py N --fields body` — reading `.issue.body`; exit 3 is a stop, while no `python3`, exit 2, or exit 4 degrades to `gh issue view N --json body`. Extract every `Depends on #N` and `Blocked by #N` reference. The match is case-insensitive and tolerates list/sentence/colon shapes: <!-- a:ap-deps-reuse-snapshot -->

```
- Depends on #12
Blocked by: #15, #20
This depends on #8
```

For each line that matches `(?im)\b(?:depends\s+on|blocked\s+by)\b`, collect **local** issue numbers only (SPEC §2 MUST-ignore for cross-repo):

1. **Strip cross-repo tokens** on that line — remove every `\S+/\S+#\d+` match (e.g. `acme/lib#15`) so its trailing digits are never captured.
2. **Capture bare refs** on the remainder with a negative lookbehind guard: `(?<![\w/])#(\d+)` — this matches `#12` and comma lists (`#12, #15`) but not the `#15` inside `acme/lib#15` if a token was missed.

Feed the body in on **stdin**, never on a command line and never pasted into a
shell word: an issue body is written by whoever filed the issue, and `/auto-pilot`
runs unattended, so a body containing `` ` `` or `$(` would execute. A fetched body must reach `$issue_body` through a command substitution — whose
output is never re-evaluated. A held compact-JSON snapshot is parsed as data with
`python3`; never paste its body into shell syntax:

```bash
issue_body="$(python3 references/scripts/gi-issue.py N --fields body --jq .issue.body)"
# Degrade form, when that exits 2 or 4 or there is no python3 — replace the
# assignment above, do not add a second one:
#   issue_body="$(gh issue view N --json body --jq .body)"
printf '%s' "$issue_body" | python3 references/scripts/gi-deps.py
```

When Step 1.2b's snapshot is the source, parse `.body` from that compact JSON on
stdin and make **no** extra GitHub read. Passing JSON on stdin keeps attacker-
authored text out of executable syntax while reusing the one resolution-boundary
snapshot.

`gi-deps.py` prints one local issue number per line; no markers prints nothing.
**Empty output is only "no dependencies" when the exit status is 0.** A non-zero
exit — 2 for an unresolved script path or a malformed invocation — is a parse
that never ran, and reading its silence as "no blockers" merges a PR whose
dependency is still open. On any non-zero exit, or no `python3`,
apply steps 1–2 above by hand. Example: `Blocked by: acme/lib#15, #12` → gate on **#12 only**. `Depends on #12, #15` → gate on **#12** and **#15**. If no local markers remain, the gate is satisfied; proceed to Step 5.2.

**Cycle guard:** If issue A's body references its own number (`#A`), log a warning and skip the gate (treat as satisfied). The auto-pilot must never block a PR on its own issue number. Multi-hop cycles (A → B → A) are not detected here — they would require traversing each dependency's body, which is out of scope for the per-merge gate; the fail-safe is that any genuinely-cyclic issue set surfaces as `blocked_by_dependency` on each affected issue and requires user intervention before those PRs can merge — the loop still advances past them. The check is:

```
⚠ Dependency cycle detected for #{issue_number} — skipping gate
  Resume manually after fixing the issue body.
```

#### Resolve each dependency

For each captured `#N`, ask GitHub: "is this issue closed by a merged PR?" GitHub's GraphQL exposes the linked-PR set directly via `closedByPullRequestsReferences` on the Issue type, which `gh issue view` surfaces:

```bash
python3 references/scripts/gi-issue.py N \
  --fields number,state,title,closedByPullRequestsReferences
```

Read `.issue` from the envelope. Each dependency is checked once per merge gate and often again on a later iteration, so the cache absorbs the repeats. Exit 3 is a stop; no `python3`, exit 2 (an unresolved script path), or exit 4 degrades to `gh issue view N --json number,state,title,closedByPullRequestsReferences`. **A dependency PR merged during this session invalidates the entry** — pass `--refresh` after any merge in this run.

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

Before advancing, add `#{issue_number}` to the **session skip list** — the same in-memory list Phase 2.3 uses for failed issues. This is required, not cosmetic: when the dependency issue is `CLOSED` but its PR is still `OPEN` (the race case the gate treats as unsatisfied), Phase 1's triage graph sees the dependency as done and would re-pick `#{issue_number}` on the next iteration; the resolver would then abort on its "PR already targets this issue" guard and the run log would gain a second, bogus `failed` line for an issue that was already recorded. Skipping it for the rest of the session keeps the invariant of **exactly one run-log line per processed issue** (`outcome: blocked_by_dependency`, see `references/run-log.md`). In explicit-list mode Phase 1 does not run and the user-provided list is consumed in order, so re-picking is impossible there — the skip-list append is harmless and the same continue-to-the-next-entry behavior applies.

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

**Compute the effective mode** by applying the *Resolution rules* under *Merge Modes* in SKILL.md — the single home for this logic, including the legacy `autopilot.auto_merge` mapping. Zero-config shorthand: when neither `autopilot.mode` nor `autopilot.auto_merge` appears in the file, effective mode = `balanced`.

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

**Checkpoint (post-merge).** The merge is the one irreversible step in the
iteration, so record it immediately after `gh pr merge` returns — or after the
mode gate declines to merge — with the *Step 1.0b* procedure:

```json
{"phase": "cleanup", "current": {"phase": "cleanup", "outcome": "merged"}}
```

During a parallel drain, include `"lanes": [{"issue": 42, "phase":
"cleanup", "outcome": "merged"}]` in the same patch. A resume that reads `outcome: merged` never re-merges and never re-opens: the PR
is gone and the issue is closed, so the iteration is finished and the loop moves
to Step 5.3. **AC2 holds here too** — nothing in this phase closes an issue whose
PR is still open and unreviewed; the issue is closed by GitHub, as the
consequence of merging the `Closes #N` PR, and by nothing else.

### Step 5.3 — Cleanup <!-- a:ap-step53-cleanup -->

**Parallel lane — exactly-once log transition.** Before cleanup, construct the
normalized run-log object with the lane's persisted `event_id` and checkpoint
both that object in `telemetry.run_log` and phase `log_pending`. Then pipe that
exact persisted object to `gi-runlog.py --append-once`. Exit 0 means either the
line was appended and fsynced or the identical event already existed; checkpoint
`logged` immediately. Exit 3 is a conflicting/invalid event and stops that lane.
No Python, exit 2, or exit 4 leaves `log_pending` for resume — **never raw append
on this path**. Only `logged` lanes advance to processed/cache cleanup.

The main agent is already in the original checkout. After `logged`, remove only
its validated caller-managed worktree, then delete the local branch if it is no
longer checked out:

```bash
repo_root="$(git rev-parse --show-toplevel)"
repo="$(basename "$repo_root")"
wt_dir="$(dirname "$repo_root")/${repo}-worktrees/$(printf '%s' "$branch_name" | tr '/' '-')"
git worktree remove "$wt_dir"
git branch -d "$branch_name" 2>/dev/null || true
```

Bind `branch_name` and `wt_dir` from the validated lane record; never re-derive
or paste a literal read-back into a command. First require `git worktree list
--porcelain` to map that exact path to this lane's branch and lane identity.
Never use `--force`. A clean terminal worktree may be removed normally. A dirty
worktree or active merge/rebase/cherry-pick/bisect state becomes `blocked_dirty`,
is retained with explicit `git status` / path recovery guidance, and does not
block the next returned sibling. A path mapped to another branch is ambiguous
and also blocks only that lane. Mark `completed` only after `logged`, cache
update, and non-forced cleanup; retain `failed`/`blocked_dirty` lanes for resume.
Then clear `current` and select the next returned lane. Clear `lanes` only when
every lane completed cleanly; otherwise retain terminal blocked records in the
final report/state.

**Sequential path (`max_parallel=1`):** use the original stash-first sync below
byte-for-byte to protect any uncommitted changes that may have accumulated
between iterations (see `references/docs/sync-conventions.md`):

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
git branch -d "{branch_name}" 2>/dev/null
```

**End-of-iteration checkpoint.** Close the iteration in the run state with the
*Step 1.0b* procedure: append this issue to `processed[]` with its final
outcome, append it to `skip_list[]` when this iteration added it there (failed
in Phase 2.3, or `blocked_by_dependency` from the gate), and **clear `current`**
by patching it to `null`:

```json
{"phase": "triage", "current": null, "processed": [{"issue": 42, "outcome": "merged", "pr": 87}]}
```

During a parallel drain, retain the batch by also patching the matching lane to
`completed`/`failed`/`blocked_dirty`; set top-level `phase` to `resolve` while
siblings remain. Clear lanes only after every lane completed cleanly. The stable
`event_id` plus `--append-once` is the append-before-checkpoint crash guard;
`processed[]` remains a scheduling guard but is never treated as log idempotency.

Clearing `current` is what tells a later resume that no issue is half-done: a
state whose `current` is `null` resumes at the top of the loop, and `processed[]`
plus `skip_list[]` keep the resumed run from re-picking anything this run already
finished or already gave up on. These are the same two lists the run holds in
memory — the state file is where they survive a crash, not a second source of
truth.

### Step 1.6 — Update the triage cache after a merge <!-- a:ap-step16-cache-update -->

Numbered in Phase 1 because it maintains Phase 1's payload; executed here
because a merge is what makes it necessary.

It runs alongside *Step 5.3*'s **End-of-iteration checkpoint**, and the two own
**different files**: this step owns the triage payload
(`.gitissue/triage.json`), that checkpoint owns the run state
(`.gitissue/run-state.json`). Neither reads or writes the other's file, so their
order relative to each other does not matter.

**Two lists, two facts — never sync them.** `summary.suggested_order` in
`.gitissue/triage.json` is the **live pick order**: this step maintains it after
every merge, and it is the only thing *Step 1.2* reads when choosing an issue.
`queue` in `.gitissue/run-state.json` is the run's **recorded intent at
`--init`** (*Step 1.0*), kept for the resume gate and the final report; it is
deliberately **not** re-derived here, and this step never patches the run state.
After the first merge the two therefore differ — by exactly the issue just
closed — and that difference is correct, not drift. They answer two different
questions: "what is left to pick *now*" and "what did this run set out to do".
A resumed run learns what is already done from `processed[]` and `skip_list[]`,
never from `queue`, so re-deriving `queue` per merge would buy nothing and would
destroy the only record of the run's original scope. **Do not "fix" the
divergence by writing one into the other** — that would collapse two facts into
one and is exactly the duplicated-home failure issue #248 forbids.

> **Note:** Skipped in explicit list mode (`--issues`), with the rest of Phase 1
> (the note at the top of `references/phases/phase-1-triage-pick.md`). That mode never triages, so there is no
> payload to maintain: a `.gitissue/triage.json` this run neither wrote nor read
> is not a cache that went stale, and a missing one there is not a degrade. Skip
> the step silently — no `⚠`, no `retriage_required`, which that mode has no
> *Step 1.1* to clear. The fail-safe below governs triage mode alone.

Run it after **any step that merged a PR and closed its issue** —
*Step 5.2*'s clean merge, *Phase 3-4 Step 2b*'s `partial_followup` merge,
which closes the issue exactly as finally, and *Phase 3-4 Option 1*'s
user-chosen merge of a critical issue's partial PR, which is that same merge
reached through a human decision. Three sites, one rule; each of the other two
carries a pointer back here, because this step sits at the far end of the file.
A PR left open, a failed resolve, a
dependency-blocked gate: none of those closed an issue, so none of them changes
the backlog and none of them runs this step — the session skip list is already
what keeps the loop from re-picking them.

**Fail-safe: any doubt is "run it."** The update is removal-only and keyed to
the one number this run just closed, so applying it to an issue the payload no
longer carries is a no-op; skipping it leaves a closed issue in
`summary.suggested_order`, on no skip list, for *Step 1.2* to pick again. The
explicit-list skip above is the one thing this does not cover, and it is not an
exception to it: the mode is known at invocation, so it is never a doubt.

**Under `--dry-run`, compute the removal and print it, but write nothing.** This
step is the one place in #258's work that persists anything, so it takes the same
rule *Step 1.1*'s `--out` and every `gi-state.py` call take: a dry run mutates no
file on disk. Apply the nine rules below in memory, print the `✓ Triage cache
updated` line with the counts the update *would* have produced, and skip the
write-back — never write `.gitissue/triage.json`. Nothing downstream is harmed:
`--dry-run` stops at *Step 1.3* before any merge, so in practice this step is
unreachable under it, and the rule is stated here so that it stays unreachable
by design rather than by accident. *Step 1.1a*, the read side of this cache, is
read-only and needs no such rule.

Read `.gitissue/triage.json`, apply **removal only**, and write it back with the
Write tool:

1. Drop the resolved number from `issues[]`.
2. Drop it from `summary.suggested_order`.
3. Drop it from every `summary.parallel_groups` entry, and drop any group that
   empties as a result — a group of zero is not a parallel set, and issue #260's
   consumer reads these directly.
4. Drop it from every remaining issue's `blocked_by` and from every remaining
   issue's `blocks`.
5. Discard the entire `summary.circular_deps` chain when it contains the
   resolved number; preserve unrelated valid closed cycles unchanged. Do not
   remove the resolved number from a chain and then accept the result: resolving
   middle node 2 from `[1,2,3,1]` must discard the whole chain, because the
   resulting `[1,3,1]` is not a recorded cycle. For every
   `summary.co_dependent` pair, drop the resolved member and retain only pairs
   with at least two distinct members — a one-issue pair is not a report.
6. If a remaining issue's `potentially_fixed_by.target_issue` is the resolved
   number, set that `potentially_fixed_by` to `null`. Reporting data only;
   nothing here feeds the pick.
7. Flip any issue whose `blocked_by` just became empty from `blocked` to
   `ready`. **This is the one derived change permitted** — it is the direct
   consequence of step 4, not a recomputation.
8. Recompute `analyzed_count`, `summary.stale_count` and
   `summary.potentially_fixed_count` by **counting the records that remain**,
   never by subtracting one from the old number. A count reached by arithmetic
   drifts the first time an assumption behind it is wrong; a count reached by
   counting cannot.
9. Append exactly **one** `history[]` entry naming the removed issue —
   `time` now, `source` `/auto-pilot`, `changes` `Incremental update (#N
   resolved)` — and set the file's `updated` to that same timestamp.

No field is added and none is removed: the schema stays the one `/issue-triage`
owns in its `references/output-and-persist.md`.

**Why removal only, and never a recomputation.** The graph script reads `createdAt`
and uses it as the primary tie-break when directing an undirected
edge and as the secondary sort key inside a topological level, but the payload
it persists carries only `updated_at`. A cached payload therefore cannot
reproduce its own order — recomputing from it would silently order on a
different input and answer a different question. Deletion needs no
recomputation: removing one node from a valid topological order leaves a valid
topological order over what remains, and removing a *completed* node cannot
un-satisfy a constraint on any node that remains. Anything beyond deletion — a
newly filed issue, a new dependency marker, a changed label — is outside what
this step can honestly do and goes through a full re-triage instead.

**When a full re-triage runs instead.** The `autopilot.retriage_every` trigger
does **not** live here — it is evaluated at the top of every iteration from the
1-based `{i}` counter, so it fires on non-merging iterations too. This step's
only remaining `retriage_required` write is the degrade path below.

**A pick miss is not a trigger here.** *Step 1.2* owns it, and handles it
**in the same iteration** — re-enter Step 1.1 once, re-run the pick. A pick miss
cannot reach this step in any case, because this step runs only after a merge.
Stating it in both places with two different timings is how the two steps drift
apart; *Step 1.2* is the single home of that retry.

**Degrade.** If the file cannot be parsed, or the write-back fails, print

```
⚠ Could not update the triage cache — re-triaging next iteration
```

set `retriage_required`, and carry on. This step never stops the loop: a cache
that could not be updated costs **one** full triage — *Step 1.1* clears the flag
as it runs, so the cost is the next iteration's scan and not every iteration's
from here on — which is what every iteration paid before this gate existed.

```
✓ Triage cache updated — #{issue_number} resolved, {n} remain
```

---
