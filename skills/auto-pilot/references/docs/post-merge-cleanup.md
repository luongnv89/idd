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
| a worktree kept for `untracked_files`/`ignored_files` | show its `files` (`file_count` total) and any `nested_repos` (a removal deletes their history); only an interactive yes (default No) re-runs with `--remove-worktree "$wt=$digest"`, `digest` from the answer shown. Auto mode never passes it |
| exit 3 | invalid `--pr`; fix the call |
| exit 4, or no `python3` | run the manual procedure (a mid-run git failure may have done a step already) |

`--dry-run` reports the plan and changes nothing. `--delete-remote` also deletes a remote head branch gh left behind at the merged head; pass it only after this skill's own `gh pr merge --delete-branch` exited non-zero on a PR that reads `MERGED`. `--remove-worktree PATH=DIGEST` re-probes that worktree and refuses a changed file list, tracked changes, a lock or an operation in progress. When `cwd_removed` is `true`, `cd` to `main_worktree` before the next command.

## Guarantees (both paths)

- **No silent removal.** A worktree with tracked changes, untracked or ignored files (probed with `--untracked-files=all`, so `status.showUntrackedFiles=no` hides nothing), an in-progress merge/rebase/cherry-pick/bisect, or a lock is kept and reported. Untracked or ignored files are deleted only after the user confirms, never in auto mode.
- **Switch only off the merged branch.** The main worktree moves to the base only from the merged branch or the base itself, and never mid-operation. On any other branch it stays; only the local base ref is fast-forwarded.
- **Stash-first.** A dirty tree is stashed before the switch, and only that stash is popped after (`references/docs/sync-conventions.md`). A failed pop keeps the stash; a conflicting one names the unmerged paths and `git reset --merge`.
- **Fast-forward only.** A diverged base is reported, never reset.
- **Delete only what merged.** `git branch -D` runs only when the local tip equals the PR's `headRefOid` (the script also accepts an ancestor of it or of `origin/{base}`). For a fork PR the name can be an unrelated branch, so only an exact `headRefOid` match counts. A head named like the base is never deleted.

## Manual procedure

Stop unless `gh pr view {N} --json state --jq .state` is `MERGED`. Run from the main worktree (the first `worktree` line of `git worktree list --porcelain`). Unless the head is named like the base, for each linked worktree `$wt` on the branch:

- skip it when `git worktree list --porcelain` marks it `locked`, or when any of `MERGE_HEAD`, `CHERRY_PICK_HEAD`, `REVERT_HEAD`, `BISECT_LOG`, `rebase-merge`, `rebase-apply` exists under `git -C "$wt" rev-parse --absolute-git-dir`;
- read `git -C "$wt" status --porcelain --untracked-files=all --ignored`. Empty: `git worktree remove "$wt"`. Only `??`/`!!` lines: list them, naming any listed directory holding a `.git` as a nested repository with its history; only after the user confirms (never in auto mode), re-list right before removing and only if the list is unchanged run `git worktree remove --force "$wt"`. Anything else: keep it.

Then:

```bash
branch="$(gh pr view {N} --json headRefName --jq .headRefName)"
merged_head="$(gh pr view {N} --json headRefOid --jq .headRefOid)"
base="$(gh pr view {N} --json baseRefName --jq .baseRefName)"
git fetch --prune origin
cur="$(git rev-parse --abbrev-ref HEAD)"
if [ "$cur" = "$branch" ] || [ "$cur" = "$base" ]; then
  before="$(git rev-parse -q --verify refs/stash)"
  [ -z "$(git status --porcelain --untracked-files=all)" ] || git stash push -u -m "post-merge: ${branch} $(date +%Y-%m-%dT%H:%M:%S)" || exit 1
  after="$(git rev-parse -q --verify refs/stash)"
  git checkout "$base" && git merge --ff-only "origin/${base}"
  [ "$after" = "$before" ] || git stash pop || echo "✗ Stash pop failed: $(git diff --name-only --diff-filter=U | xargs) — stash ${after:0:7} kept; git reset --merge, then git stash list"
else
  git fetch . "origin/${base}:${base}"
fi
[ "$branch" != "$base" ] && [ "$(git rev-parse -q --verify "refs/heads/${branch}")" = "$merged_head" ] && git branch -D "$branch"
```

Skip the switch while `git status` reports a merge, rebase, cherry-pick or bisect in progress.
