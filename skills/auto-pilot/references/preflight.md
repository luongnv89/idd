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
(see `references/docs/sync-conventions.md` for the full sync convention and recovery
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
