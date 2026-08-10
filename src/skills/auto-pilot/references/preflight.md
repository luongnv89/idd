# Preflight: precheck errors and branch sync

Read this when a Prerequisites check fails or when syncing to the default branch.
SKILL.md carries the checklist and the bundled-file list; this file carries the
exact error outputs and the stash-first sync procedure.

## Skill dependency precheck

`/auto-pilot` delegates work to other gitissue skills. Before any triage,
resolution, review, merge, or repository mutation, verify those skills are
available in the current agent environment.

If one or more required skills are missing, stop immediately and print:

```text
✗ Missing required gitissue skill(s): {missing_skill_list}

  To fix:  asm install https://github.com/luongnv89/idd
           Select: {missing_skill_list}
  Or:      asm install https://github.com/luongnv89/idd --skill {first_missing_skill}

  Then restart the agent session and re-run /auto-pilot.
```

Do not continue with partial auto-pilot execution when required skills are
missing. `issue-creator` is optional; if it is missing, skip mid-loop issue
normalization and print a warning instead of stopping.

## Bundled dependency precheck

If any bundled reference file (listed in SKILL.md → *Bundled dependency
precheck*) is missing, stop immediately and print:

```text
✗ Missing bundled dependency: {missing_file}

  To fix:  asm install https://github.com/luongnv89/idd --skill auto-pilot
           (or reinstall the full distribution)

  Then restart the agent session and re-run /auto-pilot.
```

## Run lock

**The lock is taken before the first mutation.** The `git stash push -u` in
*Auto-stash and branch sync* below is that first mutation, so the lock precedes
it — two concurrent runs stashing, rebasing and branching in one working tree
corrupt each other's state long before either reaches a PR.

```bash
python3 shared/scripts/gi-state.py --lock --pid "$PPID"
```

**`--pid` names the process that owns the run, not the shell that ran the
command.** Each of these calls runs in its own throwaway shell that exits the
instant it finishes, so recording *that* pid would leave a lock whose owner is
already gone — the next run would read it as a dead-pid corpse and reclaim it,
and there would be no mutual exclusion at all. `"$PPID"` is the agent process
driving the whole run, which is why it is the owner to record. Where no durable
pid is available, drop the flag: the lock then records `pid 0`, meaning *owner
unknown*, and is retired by the TTL or `--force` only — slower to clear after a
crash, but never self-reclaiming.

**When this run was invoked with `--resume`, add `--resume` to that call.** A
plain `--lock` mints a fresh run id, so a state file left behind by a run that
already finished cannot lend its id to an unrelated one — two runs sharing an id
would file two reports and two `runs.jsonl` rows under the same name.
`--lock --resume` is the caller saying "I am continuing the recorded run", and
only then is the id read off disk. It is also the only call that can take a lock
that is still **live**, and only its own: when the lock records this run's id
*and* this run's owner pid *and* this host, `--resume` re-acquires it in place
(`reacquired`, exit 0, a heartbeat refresh and nothing else). That is the
ordinary interruption — the loop stopped, the agent process holding the lock did
not — and without it a resume would be refused by the lock it is resuming. Any
other id, any other pid, or any other machine is still a live holder: exit 3.
A pid means nothing off the host that recorded it, so dropping the host check
would let a pid collision hand one lock to two runs. Either way `--init` adopts
the id of the lock this run holds, so lock → init → unlock stays one run.

The lock is `.gitissue/run.lock`, created with `O_CREAT|O_EXCL` so two runs
racing for it cannot both win, and it records four fields:

| Field | Why it is there |
|-------|-----------------|
| `run_id` | identifies the holder; `--unlock` releases only a matching lock unless `--force` |
| `pid` | the process that owns the run (`--pid "$PPID"`), so a lock left by a run that is gone can be retired; `0` means owner unknown |
| `host` | liveness is only checkable on the machine that took the lock |
| `started_at` (+ `heartbeat`) | the age the TTL is measured against; each checkpoint refreshes `heartbeat`, so a long run never ages itself out |

**TTL and liveness.** A held lock is **stale** — and is reclaimed with a `⚠`
line — when its age reaches `--ttl` seconds (default 3600) **or** when it names
this host and a recorded `pid` that is no longer running. A lock with no
recorded owner (`pid 0`) has no liveness signal at all, so only the TTL or
`--force` retires it: unknown is never read as dead. Anything else is a live
holder: the call exits **3** and this run stops. Exit 3 is a stop, never a
degrade —
"another run is in progress" is an answer, not a failure to answer, and starting
anyway is exactly the concurrent-mutation case the lock exists to prevent.

**`--force-unlock`.** When a run really is dead but its lock still looks live
(a reused pid, a lock taken on another machine, a clock skew), reclaim it:

```bash
python3 shared/scripts/gi-state.py --lock --force --pid "$PPID"
```

That is what `/auto-pilot --force-unlock` runs. It is the only documented way
past a live-looking lock; deleting `.gitissue/run.lock` by hand is the same
thing without the audit line. **`--force` is a single-operator escape hatch, not
a concurrency-safe mode**: it says "reclaim regardless of who holds this", so
several `--lock --force` calls issued at once all succeed and the mutual
exclusion is gone for that instant. Run it once, deliberately, when you know the
other run is dead — never as a way to make a contended lock go away.

**Under `--dry-run`, add `--dry-run`** — the call reports who holds the lock and
creates nothing.

**Release on every exit path.** `python3 shared/scripts/gi-state.py --unlock` is
the run's last action, on success, on every stop condition, and after the
critical-issue pause. It releases only a lock whose id matches the run state's,
so in the one case where `--init` never wrote a state for this run (its exit-3
path in `references/phases.md` *Step 1.0*) the recorded id belongs to some other
run and the release needs `--unlock --force`.

**Fallback when the script cannot run.** A missing bundled file is a broken
install: stop with the `✗ Missing bundled dependency` block above. But no
`python3`, exit 2, or exit 4 is an environment problem — print
`⚠ gi-state unavailable — running without the run lock` and continue: check for
`.gitissue/run.lock` with `test -f`, treat a file younger than an hour as a live
holder and stop, otherwise proceed and skip every checkpoint. The run is then
correct but not resumable, which is exactly today's behavior.

## Rate-limit pause

Prerequisite 8 reads the budget with driver rule 4's single call; this section is
what to do with the answer, and it is where a mid-run 403 lands too
(`references/error-messages.md` → *API rate limit during a loop read*). Pipe the
payload straight in — the script never touches the network, it only decides what
the numbers mean:

```bash
gh api rate_limit --jq '{remaining: .rate.remaining, reset: .rate.reset}' \
  | python3 shared/scripts/gi-ratelimit.py --verdict \
      --threshold 200 --deadline "{budget_deadline_epoch}"
```

`{budget_deadline_epoch}` is the epoch at which `autopilot.max_runtime_minutes`
expires — `0` when it is unbounded — so a pause can never outlive the budget the
run was given. **It has two derivations, one per call site.** Mid-run it is
`run_state.started_at + autopilot.max_runtime_minutes × 60`, the same instant the
*Runtime budget check* measures against, so the pause and the budget cannot
disagree. At **Prerequisite 8** there is no run state to read it from — `--init`
writes `started_at` in `references/phases.md` (*Step 1.0*), which runs after the
prerequisites — so derive it from the clock: `now + autopilot.max_runtime_minutes
× 60`, with the minutes taken from the one config load. At the first probe that
is the *same* instant, because a run that has not started has spent none of its
budget — and the paragraph below is why the first probe is the only one. Either
way `0` means unbounded. Never substitute a `{run_state.started_at}` that does
not exist and never fabricate one: an unsatisfiable deadline degrades into an
unbounded pause, which is exactly the promise SKILL.md's Prerequisite 8 makes —
that the pause fits inside `autopilot.max_runtime_minutes` — broken silently.

**At Prerequisite 8 that clock is read once.** Compute `{budget_deadline_epoch}`
at the **first** probe of this section and reuse that one epoch verbatim — in
every re-probe the `wait` row loops back to, and in every `--wait` chunk of every
pause that follows, for the whole of the prerequisites. Re-deriving it from `now`
on each pass would push the deadline forward by exactly as long as the pause that
just ended, so each pause would fit the budget on its own while the sequence of
them had no bound at all: the `wait` → pause → re-probe loop could idle
indefinitely and never once see `action: stop`. The pinned epoch is the fixed
anchor `run_state.started_at` gives the mid-run site, and it is what makes the
`stop` branch reachable — once it is past, the next verdict is `stop` and the
prerequisites end cleanly. Mid-run nothing needs pinning: `run_state.started_at`
is already written down, so re-reading it yields the same instant every time.

The one JSON line carries `action`, `remaining`, `reset`, `wait_s` and
`resume_at`:

| `action` | What the loop does |
|----------|--------------------|
| `proceed` | continue silently |
| `warn` | print the `⚠` low-budget variant from `references/error-messages.md` and continue |
| `wait` | print the `○ Rate budget exhausted — pausing until {resume_at}` block, run the chunked pause below, then **re-probe from the top of this section** — carrying the `{budget_deadline_epoch}` this section already computed, never a freshly derived one |
| `stop` | print the `✗ Insufficient API rate budget` block, persist the report, release the lock (mid-run only — at Prerequisite 8 none is held yet), and stop cleanly |

**The pause is chunked, and that is not cosmetic.** The run lock's TTL is 3600s
(*Run lock* above) and its `heartbeat` is refreshed only at checkpoints, so one
uninterrupted sleep past the TTL would let a second run read this live run's lock
as stale and reclaim it mid-pause — the exact concurrent-mutation case the lock
exists to prevent. Sleeping one chunk at a time gives the loop somewhere to
refresh from:

```bash
python3 shared/scripts/gi-ratelimit.py --wait \
    --until "{reset_epoch}" --deadline "{budget_deadline_epoch}" --chunk-s 300
```

After **every** chunk, refresh the heartbeat with the ordinary checkpoint of
`references/phases.md` (*Step 1.0b*) — `gi-state.py` stays the single writer of
`.gitissue/run.lock`, and nothing here may touch that file directly. Repeat until
the line reports `done: true`, then re-probe. A line with `done: false` and
`waited_s: 0` means a further chunk would run past the deadline: stop cleanly,
exactly as `action: stop` does. Check the runtime budget before and after the
pause (`references/phases.md` → *Runtime budget check*). The heartbeat refresh
and that bracketing budget check describe the **mid-run** site; the paragraph
below says how each of them reads at Prerequisite 8.

**The preflight site holds no lock and has no run state, and must not act as if
it did.** The run lock is taken further down these Prerequisites (*Run lock*
above), after the budget probe, and the run state is written later still. So at
Prerequisite 8:

- the between-chunk heartbeat refresh **does not apply** — there is no lock to
  age out and nothing to refresh. Skip it, and in particular do **not** run
  *Step 1.0b*'s checkpoint here: that would create `.gitissue/run-state.json`
  ahead of the `--init` that owns creating it, and the next run would read a
  state no run ever started. The chunked `--wait` call itself is unchanged; only
  the refresh between chunks drops away.
- the bracketing *Runtime budget check* does not apply either — it measures from
  a `started_at` that does not exist yet. The `--deadline` above **is** the
  enforcement at this site, and the once-computed epoch is what keeps it exact
  rather than approximate: it is measured from the instant this section first
  ran, so time already spent in an earlier preflight pause is time the deadline
  has already counted.
- the `stop` branch's *release the lock* is the mid-run half of that row. Here
  there is nothing to release, so the clean stop is the `✗ Insufficient API rate
  budget` block plus the persisted report and nothing else — and the report is
  written with no recorded `run_id`, which `gi-state.py --report` already handles.
  That report is a zero-iteration summary reporting `Result: RATE LIMITED`
  (`references/summary-format.md`), the same value the mid-run stop reports.
- a pause that finishes resumes nothing: it re-probes, and on `proceed` or `warn`
  the prerequisites simply carry on to the run lock.

Mid-run every one of those reads normally — the lock is held, the heartbeat is
refreshed between chunks, the budget check brackets the pause, and `--unlock`
releases the lock on the stop path.

**Prose fallback**, per the rule that every script call site documents one. No
`python3`, exit 2, or exit 4: print
`⚠ gi-ratelimit unavailable — computing the pause by hand` and do the same
arithmetic — `wait_s = reset - now`; if `max_runtime_minutes` is set and
`now + wait_s` falls past the deadline — at Prerequisite 8 the one epoch pinned
at the first probe, never a fresh one — stop cleanly instead; otherwise sleep in
slices no longer than 300s, refreshing the heartbeat between them (mid-run only,
per the paragraph above), then re-read `gh api rate_limit` and decide again. Exit 3 is invalid input (an unparsable
payload) — a stop for this probe, not a degrade. Exit 0 carrying
`action: "stop"` is an **answer**, never a degrade: do not retry past it.

## Transient-failure retry

Driver rule 5 in `docs/platform-github.md` is the single home of *which* failures
are recoverable — 5xx, a connection reset or timeout, and a *secondary*
rate-limit 403 carrying `Retry-After`; never 401, 404, or primary rate-limit
exhaustion, which takes *Rate-limit pause* above instead. This section is the
loop that acts on that classification, and it wraps any single `gh` call the
orchestrator makes directly:

```bash
python3 shared/scripts/gi-ratelimit.py --backoff --attempt {n}
```

Start at attempt 1, sleep the returned `delay_s`, retry the call, increment.
The schedule is 2s, 4s, 8s, 16s — four attempts, 30s of added latency at worst.
When the line reports `exhausted: true` (attempt 5 and beyond, `delay_s: 0`, and
exit **0**, because exhaustion is an answer and not a failure to answer),
**fall through to the degrade the call site already documents** — never to a new
stop. The contract adds attempts *before* an existing fallback and never replaces
it: for *Step 1.1b*'s live eligibility read that fallback is
`live_backlog = unavailable` (`references/phases.md`), and for a `gh issue edit`
it is that call's own no-write path. Honour a `Retry-After` header when it asks
for longer than the computed delay.

**Prose fallback:** without the script, apply the same 2s/4s/8s/16s schedule by
hand and give up after the fourth attempt, into the same documented degrade.

## Auto-stash and branch sync

If the working tree is dirty, auto-stash and continue:

```bash
git stash --include-untracked -m "auto-pilot: stash before run"
```
```
⚠ Working tree had uncommitted changes — auto-stashed
  Stash ref: {stash_ref}
```

If not on the default branch (main/master), auto-switch and sync. The stash above
already protects any uncommitted work, so the rebase here runs on a clean tree
(see `docs/sync-conventions.md` for the full sync convention and recovery
procedure):

```bash
git checkout {default_branch}
# Defensive stash — the pre-flight stash above should have caught this,
# but the convention is to stash-first whenever a rebase follows.
dirty=0
if [ -n "$(git status --porcelain)" ]; then
  git stash push -u -m "pre-sync: {default_branch}"
  dirty=1
fi
git fetch origin
git pull --rebase origin {default_branch} || {
  echo "✗ Rebase failed — aborting and resetting to remote"
  git rebase --abort 2>/dev/null
  exit 1
}
if [ "$dirty" -eq 1 ]; then
  git stash pop || {
    echo "✗ Stash pop failed — recover with: git stash list && git stash show -p stash@{0}"
    exit 1
  }
fi
```
```
⚠ Was on branch {branch} — auto-switched to {default_branch}
```

These are safe, local, reversible operations — no user confirmation needed. The
stash is preserved and can be restored with `git stash pop` after the auto-pilot
finishes.
