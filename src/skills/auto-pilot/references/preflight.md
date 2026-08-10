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
only then is the id read off disk. Either way `--init` adopts the id of the lock
this run holds, so lock → init → unlock stays one run.

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
