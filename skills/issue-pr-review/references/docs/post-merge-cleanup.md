<!-- Generated from /docs/post-merge-cleanup.md. Do not edit. Edit source and run ./scripts/build.sh. -->
# Post-Merge Cleanup

After a PR merges, the checkout may still hold the head branch, a worktree on it, or sit on that branch. A squash merge makes `git branch -d` refuse the branch (its tip is never an ancestor of the base). Every skill that merges a PR, or finds one already merged, runs this cleanup. It is idempotent, so it is safe after `gh pr merge --delete-branch` did part of it.

## Primary path

Run the bundled `gi-postmerge` helper with `--pr {N}` from anywhere in the repository. It reads `gh pr view {N} --json state,headRefName,headRefOid,baseRefName,isCrossRepository`, touches nothing unless `state` is `MERGED`, and prints one JSON object. Read `merged`, `ok` and the step fields, not just the exit status:

| Answer | Caller does |
|--------|-------------|
| exit 0, `merged: false` | nothing was touched (`ok` is false); never report it as cleaned |
| exit 0, `ok: true` | `✓ Cleaned up: removed {branch}`, plus `on {base} @ {sha7}` when `checkout.action` is `switched` or `already` |
| exit 0, `ok: false` | `⚠ Cleanup incomplete` plus each `problems[]` line (each says how to finish by hand); never retry with force |
| exit 3 | invalid `--pr`; fix the call |
| exit 4, or no `python3` | run the manual procedure (a mid-run git failure may have done a step already) |

`--dry-run` reports the plan and changes nothing. `--delete-remote` also deletes a remote head branch gh left behind at the merged head; pass it only after this skill's own `gh pr merge --delete-branch` merged. When `cwd_removed` is `true`, `cd` to `main_worktree` before the next command.

## Guarantees (both paths)

- **No forced removal.** A worktree with changes, ignored files (a plain remove deletes them), an in-progress merge/rebase/cherry-pick/bisect, or a lock is kept and reported.
- **Switch only off the merged branch.** The main worktree moves to the base only from the merged branch or the base itself, and never mid-operation. On any other branch it stays; only the local base ref is fast-forwarded.
- **Stash-first.** A dirty tree is stashed before the switch, and only that stash is popped after (`references/docs/sync-conventions.md`). A failed pop keeps the stash.
- **Fast-forward only.** A diverged base is reported, never reset.
- **Delete only what merged.** `git branch -D` runs only when the local tip equals the PR's `headRefOid` (the script also accepts an ancestor of it or of `origin/{base}`). For a fork PR the name can be an unrelated branch, so only an exact `headRefOid` match counts. A head named like the base is never deleted.

## Manual procedure

Stop unless `gh pr view {N} --json state --jq .state` is `MERGED`. Run from the main worktree (the first `worktree` line of `git worktree list --porcelain`). Unless the head is named like the base, remove each linked worktree on the branch whose `git -C "$wt" status --porcelain --ignored` is empty with a plain `git worktree remove "$wt"`. Then:

```bash
branch="$(gh pr view {N} --json headRefName --jq .headRefName)"
merged_head="$(gh pr view {N} --json headRefOid --jq .headRefOid)"
base="$(gh pr view {N} --json baseRefName --jq .baseRefName)"
git fetch --prune origin
cur="$(git rev-parse --abbrev-ref HEAD)"
if [ "$cur" = "$branch" ] || [ "$cur" = "$base" ]; then
  before="$(git rev-parse -q --verify refs/stash)"
  [ -z "$(git status --porcelain)" ] || git stash push -u -m "post-merge: ${branch} $(date +%Y-%m-%dT%H:%M:%S)" || exit 1
  after="$(git rev-parse -q --verify refs/stash)"
  git checkout "$base" && git merge --ff-only "origin/${base}"
  [ "$after" = "$before" ] || git stash pop || echo "✗ Stash pop failed — recover with: git stash list && git stash show -p stash@{0}"
else
  git fetch . "origin/${base}:${base}"
fi
[ "$branch" != "$base" ] && [ "$(git rev-parse -q --verify "refs/heads/${branch}")" = "$merged_head" ] && git branch -D "$branch"
```

Skip the switch while `git status` reports a merge, rebase, cherry-pick or bisect in progress.
