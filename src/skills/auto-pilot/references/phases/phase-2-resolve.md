# /auto-pilot — Phase 2: Resolve

One part of `references/phases.md` — the index that maps every step to its file. Read only the part for the step you are on; a pointer to another step (*Step N.n*, *Phase N*) resolves through that index.

## Phase 2 — Resolve (Subagent)

### Step 2.1 — Sync to Default Branch

The main agent syncs the original checkout to the default branch directly (this
is lightweight — no code reading). Run this **once per sequential issue or once
before a parallel fan-out**, never concurrently inside resolver workers. Use the
stash-first pattern to protect any uncommitted work that may have appeared since
the pre-flight stash (see `docs/sync-conventions.md`):

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

### Step 2.2 — Spawn Resolver Subagent(s)

Launch default general-purpose subagents to perform the resolve pipeline. Pass
only `description` and `prompt` — do NOT set `subagent_type`. The resolver is a
**skill** invoked from inside the prompt (via `{{skill:issue-resolver}}`), not an
agent type; passing `subagent_type: "issue-resolver"` fails.

#### Legacy sequential path (`max_parallel = 1`)

Run the original path exactly:

```
● [Iteration {i}/{max}] Resolving #{issue_number}...
  ⟶ Spawning resolver subagent...
```

Use the **Resolver Subagent** prompt from `references/subagent-prompts.md`,
substituting `{issue_number}` and the optional payload/context. Omit the
`parallel_lane` block, launch from the original checkout, and wait for this one
result before Step 2.3. No caller-managed worktree or `lanes[]` checkpoint is
created.

#### Parallel path (`max_parallel > 1` and at least two lanes)

Prepare every worktree **sequentially before any resolver starts**, from the same
fetched base. For each planned lane, derive the branch without putting issue text
on a command line, then create the deterministic sibling worktree:

```bash
repo_root="$(git rev-parse --show-toplevel)"
base="$(git symbolic-ref --short refs/remotes/origin/HEAD)"
base="${base#origin/}"
repo="$(basename "$repo_root")"
base_sha="$(git rev-parse "origin/${base}")"
branch_json="$(python3 shared/scripts/gi-branch.py {issue_number} --from-issue --type {type})"
branch_name="$(printf '%s' "$branch_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["branch"])')"
wt_dir="$(cd "$(dirname "$repo_root")" && pwd)/${repo}-worktrees/$(printf '%s' "$branch_name" | tr '/' '-')"
git worktree add -b "$branch_name" "$wt_dir" "$base_sha"
```

`issue_number` is an integer and `issue_type` must first be reduced to one of the
six resolver literals. Treat script exit 3, an unparsable result, or `valid:
false` under the standard `auto` prefix as a lane failure. On resume, an existing
conventional branch may be attached with
`git worktree add "$wt_dir" "$branch_name"` only after
`git worktree list --porcelain` proves it is not
already attached elsewhere. A path collision or ambiguous branch is a lane
failure, never permission to delete an unknown directory.

Prepare the workspace with the same detected procedure as resolver Step 0e:
copy existing gitignored local config from `repo_root`, install dependencies with
the detected package manager, and run a documented setup/bootstrap target when
present. Record only commands actually run. If creation or setup fails, remove
only the partial worktree/branch this lane created, checkpoint the lane as
`failed`, and continue preparing siblings. **Never fall back in-place** while a
parallel batch exists.

After each setup succeeds, checkpoint its phase from `planned` to `resolve`.
Then launch **all** prepared resolver calls before waiting for any one of them:

```
● [Iterations {first}-{last}/{max}] Resolving independent lanes...
  ⟶ #42  feat/42-a  (worktree)
  ⟶ #45  fix/45-b   (worktree)
```

Launch each lane with the canonical supported shape only:
`Agent(description="resolver — resolve issue #N", prompt=<lane prompt>)`. Do not
invent `cwd`, environment, or `subagent_type` fields. The validated lane record
is structured prompt data and is the worker's complete workspace authority.

Before fan-out, capability-gate the host: parallel mode requires workers whose
Read/Edit/Write tools accept absolute paths and whose Bash tool can execute one
quoted command at a time. If either capability is unavailable, print
`⚠ Parallel resolver absolute-path isolation unavailable — using the legacy
sequential path`, remove only the unstarted worktrees this batch created, clear
the planned batch, and execute the byte-for-byte legacy path. This fallback is
permitted only before any worker starts.

A parallel worker may not use its ambient root for any repository operation.
Every file tool call names an absolute path under the canonical
`parallel_lane.worktree_path`. Every shell call is one quoted command that first
binds the validated path as data and then uses
`cd -- "$lane_root" && ...`; git-only calls may instead use
`git -C "$lane_root" ...`. Quote/bind values as arguments — never paste a path,
branch, or SHA into executable shell syntax. The first command re-verifies
`--show-toplevel`, branch, registered worktree ownership, lane/event identity,
and base ancestry. On any mismatch the lane stops before resolver logic. These
rules give the ordinary Agent primitive worktree isolation without claiming a
spawn parameter it does not support.

Substitute its own payload/context plus the persisted structural record:

```json
{"issue":42,"lane_id":"run-1:42","event_id":"run-1:42",
 "branch":"feat/42-a","worktree_path":"/abs/repo-worktrees/feat-42-a",
 "base_sha":"0123456789abcdef0123456789abcdef01234567","base":"main"}
```

Within every quoted shell command, export from that already-validated record:
`IDD_AUTO_MODE=1`, `IDD_CALLER_WORKTREE=1`, `IDD_LANE_ID`,
`IDD_EVENT_ID`, `IDD_WORKTREE_PATH`, `IDD_LANE_BRANCH`, and `IDD_BASE_SHA`; a resumed resolver
also exports `IDD_RESUME_LANE=1`. Exports are repeated per command because Agent
shell calls do not share process state. Before invoking resolver logic the
worker runs Step 0e's caller-managed validation in full rather than skipping it.
Every lane still uses `--auto --no-run-log`; the caller
worktree changes only workspace setup, never issue-state checks, QA, tests,
secret scans, push, or PR delivery. Wait for **all started lanes** to return. Do
not cancel successful siblings when one fails, and do not start PR review until
fan-in is complete.

Checkpoint every returned result immediately, including the resolver telemetry
needed by the single writer:

```json
{"lanes":[{"issue":42,"branch":"feat/42-a","pr":87,"phase":"returned",
  "telemetry":{"status":"success","qa_cycles":3,"ceiling":2,
               "breach_reason":"extra re-review cycle after reviewer collapse",
               "complexity":"medium","profile":"full","duration_s":420}}]}
```

A failed return uses `phase: failed` and stores its failure fields in telemetry.
After all returns are durable, order lanes by `summary.suggested_order` and begin
the serialized drain. No reviewer, merge, run-log append, triage-cache update,
or worktree cleanup overlaps another lane's.

### Step 2.3 — Process Resolver Result

On the sequential path, process the sole result as before. On the parallel path,
choose the next `returned`/`failed` lane in original triage order and copy it
into singleton `current`. A returned lane advances to `review`. A failed lane
advances to `cleanup` only when its deterministic path is still registered by
`git worktree list --porcelain`; otherwise log/checkpoint the terminal failure
without a cleanup attempt. Only then apply the existing result handling below.
Finish this lane before choosing the next one.

Parse the subagent's response. Extract: `status`, `branch_name`, `pr_number`, `pr_url`, `tests_written`, `failure_step`, `failure_reason`. For a parallel lane, require the returned `branch_name` to equal its validated planned branch and verify `gh pr view {pr_number} --json headRefName,state` reports that same head and `OPEN` before queuing review. Bind both returned values to shell variables rather than pasting them. A mismatch is a failed lane and never reaches review or merge.

**Checkpoint (post-resolve).** As soon as `branch_name` and `pr_number` are
known — before Phase 3 spawns anything — record them with the *Step 1.0b*
checkpoint procedure:

```json
{"phase": "review", "current": {"issue": 42, "title": "…", "branch": "fix/42-…", "pr": 87, "phase": "review"}}
```

For a parallel drain, the same atomic patch also advances that issue's lane:
`"lanes": [{"issue": 42, "phase": "review"}]`. At `max_parallel=1` omit it.

This is the checkpoint that makes AC1 work: a run interrupted anywhere in Phase
3-5 resumes onto **this** branch and **this** PR instead of re-resolving the
issue and opening a second one.

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

The resolver subagent may report that the issue is already fixed (status: `already_resolved`). That status means **closing evidence** — a merged PR, or a closing commit on the default branch. In this case, skip the review/fix/merge phases entirely and move on.

```
○ #{issue_number} already resolved — skipping
  Outcome: skipped
```

Record the iteration outcome as `skipped` and continue to the next iteration.

**On pr_in_progress — review the existing PR, never skip and never close:**

`pr_in_progress` is a **different** answer from `already_resolved`: someone (or
an earlier, interrupted run of this loop) already has an open PR targeting this
issue. The resolver returns `status: pr_in_progress` with `pr_number` and
`branch_name` and **does not close the issue** — an unreviewed, unmerged PR is
not a resolution, and closing the issue behind one loses the work and the
tracking at once.

Route it into **Phase 3 review of that existing PR**, exactly as if this
iteration's resolver had just created it: take `pr_number` / `branch_name` from
the report-back, run the *Checkpoint (post-resolve)* above with them, and
continue to Step 3.1. The iteration then reaches its ordinary outcome —
`merged`, `left_open`, `blocked_by_dependency` — through the same gates as any
other PR.

```
○ #{issue_number} already has PR #{pr_number} — reviewing the existing PR
```

If the report-back carries no `pr_number` (an older resolver, or a PR it could
not identify), there is nothing to review: record `skipped` with
`skipped_reason: pr_in_progress`, leave the issue **open**, and continue.

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

#### Quarantine after repeated failures

"Retry on next run" is only true while retrying is still worth the tokens. The
streak is counted **from** this failure's own run-log line, so counting before
that line is appended is off by one. Ensure the failed line is durable **before**
`--failure-streak`:

- **Sequential path (`max_parallel = 1`):** the failed line is already appended
  by SKILL.md → *Run-log entry* (`gi-runlog.py --append`) before this subsection
  runs. Leave that path unchanged.
- **Parallel path (`max_parallel > 1`):** failed lanes do **not** wait for Step
  5.3's success-path drain. **Before** the streak check below, run the same
  exactly-once log transition Step 5.3 documents (*Parallel lane — exactly-once
  log transition*): construct the normalized `failed` record with the lane's
  persisted `event_id` and resolver telemetry, checkpoint it as
  `telemetry.run_log` with phase `log_pending`, then append with
  `--append-once`. Exit 0 (new line or identical event already present) →
  checkpoint `logged`, then continue into the streak check. Exit 3
  (conflicting/invalid event) stops that lane without quarantining. No
  `python3`, exit 2, or exit 4 leaves `log_pending` for resume and **skips**
  the streak check this pass — never raw-append, never quarantine on missing
  evidence. A later resume retries `--append-once` from `log_pending`
  (*Step 1.0*), then re-enters this subsection only after `logged`. This
  write must complete before `--failure-streak` so the current failure is
  included in the consecutive count.

```bash
python3 shared/scripts/gi-runlog.py --failure-streak {issue_number} \
    --threshold {autopilot.quarantine_after}
```

The one JSON line reports `{"streak": N, "threshold": F, "quarantine": bool}` —
the most recent consecutive `failed` records for this issue, stopping at its
first record with any other outcome, so one success anywhere in between resets
the count. `autopilot.quarantine_after: 0` disables quarantine entirely: skip
this whole subsection, never invoke the script.

On `quarantine: true`, apply the label and record it:

```bash
gh issue edit {issue_number} --add-label "{autopilot.quarantine_label}"
```

**Check the label before you substitute it**, exactly as *Step 1.0* checks a
recorded branch and the *Runtime budget check* checks a recorded `started_at`:
it must match `^[A-Za-z0-9._:-]+$`. `gi-config.py` validates that
`autopilot.quarantine_label` is a *string*, never that it is free of shell
metacharacters, and it is the only config **string** in the distribution that
reaches a command line — every other substituted config value is an integer. The
double quotes above stop word-splitting and globbing but do **not** neutralize
`$(…)` or a backtick, so the check is what makes the substitution safe. Anything
else is the first degrade path below: skip the write and continue.

```
⚠ #{issue_number} quarantined after {streak} consecutive failed runs
  Label:  {autopilot.quarantine_label} — remove it to let /auto-pilot try again
  Continuing to next issue...
```

Then record the skip-list entry with reason `quarantined`, write
`skipped_reason: quarantined` on **no** additional run-log line — this iteration
already wrote its `failed` line — and **continue to the next issue**. Quarantine
is record-and-continue, exactly like the dependency-blocked merge: it never stops
the run. The reason exists so *Step 1.2*'s no-eligible-issues block can attribute
the skip; see the reason-to-bucket table there.

**Why the label is the state.** `.gitissue/runs.jsonl` is deletable, gitignored
telemetry, so the streak it yields is *progress toward* a quarantine and never
the quarantine itself. The label lives on the issue: it survives a clone, a new
machine, and a deleted `.gitissue/`, a human can see it and remove it, and
"until the label is removed" is then literally true. From the next run's
perspective there is no new gate to consult — the label is in the effective
`skip_labels` set (SKILL.md → *Configuration*), so *Step 1.2* already skips it.

**Three degrade paths, all non-fatal.**

- **The label is unusable.** `autopilot.quarantine_label` failed the format
  check above. Print `⚠ Quarantine label is not a usable label name — skipping
  the label write`, never substitute the value, and continue. The streak stays
  in the run log, so a run started with a corrected `.gitissue.yml` quarantines
  on this issue's very next failure.
- **The count is unavailable.** No `python3`, or exit 4 (the log is missing or
  unreadable — note the script still prints its line, with `streak: 0`): print
  `⚠ gi-runlog unavailable — skipping the quarantine check` and continue without
  quarantining. Counting by hand is the documented fallback if the log is
  readable at all: read `.gitissue/runs.jsonl` bottom-up, skip other issues, and
  stop at this issue's first non-`failed` record. **Never quarantine on missing
  evidence** — the failure direction is deliberate, because an unquarantined
  issue costs tokens while a wrongly quarantined one costs a fix nobody is
  watching for.
- **The label write is refused.** A repo the caller only has `READ`/`TRIAGE` on
  cannot be labelled. Print the `⚠ Quarantine label could not be applied` block
  from `references/error-messages.md`, skip the write, and continue — the same
  downgrade-rather-than-fail choice Prerequisite 9 makes for merge permission
  (SKILL.md → *Prerequisites*). The issue stays in this run's session skip list,
  so the current run still stops re-picking it.

If `autopilot.pause_on_failure` is explicitly set to `true` in config, stop the loop instead:
```
⚠ Auto-pilot paused due to failure (pause_on_failure: true).

  Failed on:  #{issue_number} — {title}
  Step:       {failure_step}
  To resume:  fix the issue, then /auto-pilot
  To skip:    /auto-pilot --skip {issue_number}
```

---
