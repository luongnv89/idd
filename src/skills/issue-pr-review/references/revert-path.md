# Revert path — `/issue-pr-review <M> --revert`

Undo merged PR `M` through a new PR `R` and reopen its issue `N`. This replaces Steps 1-7: no review, no progress record. It never merges or pushes to the base branch; with no linked issue, `R`'s merge floor is unmet, so a human or an interactive yes merges it. `--revert` combines with `--auto` only; the flag is the consent, so neither mode prompts.

1. **Read M.** `gh pr view {M} --json number,title,body,state,baseRefName,url,mergeCommit`. Stop unless `state` is `MERGED`. `N` is the `Closes|Fixes|Resolves #N` in its body (check 1's regex); with none, revert anyway, skip steps 5-6 and say so. Take `{owner}/{repo}` from `url`; `{base}` is `baseRefName`, `oid` is `mergeCommit.oid`.
2. **Revert on a branch.** Stop unless `git status --porcelain` is empty (commit or stash first): a revert commits whatever is staged. `git fetch origin {base}` and count parents with `git rev-list --parents -n 1 "$oid"`: one parent and a subject ending `(#M)` is a squash, two a merge commit, anything else (a rebase merge) stops. Bind `start="$(git symbolic-ref -q --short HEAD || git rev-parse HEAD)"`, then `git switch -c fix/{N}-revert-pr-{M} "origin/{base}"` (`{M}` for `{N}` with no issue) and `git revert --no-commit "$oid"`, adding `-m 1` for a merge commit. On a conflict, undo: `git revert --abort`, `git checkout -q "$start"`, `git branch -D fix/{N}-revert-pr-{M}`; push nothing, stop.
3. **Scan, commit, push.** As in SKILL.md *Commit auto-fixes*, bind `policy_base="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"` first, then scan the staged set with `python3 shared/scripts/gi-secscan.py --staged --policy-ref "origin/${policy_base}"` and the same four-part pass: a revert can restore a secret the PR removed.
   Exit 1 blocks: undo as in step 2, stop. Then `git commit --no-edit`, which keeps git's `Revert "…"` subject and `This reverts commit <sha40>.` line, and `git push -u origin fix/{N}-revert-pr-{M}`.
4. **Open R.** `gh pr create --base {base} --head fix/{N}-revert-pr-{M} --title 'Revert "{M title}"' --body-file "$body_file"` (a `mktemp` file). A `Revert "` subject is never read as a landing commit. Body, marker lines at line start, outside lists and quotes:

   ```text
   Reverts {owner}/{repo}#{M}

   This reverts commit {oid}.

   {one-line reason}. Reopens #{N}.

   > **Note:** No acceptance criteria defined — a revert restores the code before #{M}.
   ```

   With no issue, drop `Reopens #{N}`. No closing keyword may name an issue anywhere in the body, reason included: `R` must not re-close `N`. Two lines, because IDD's merge passes the body to the squash commit (`--body-file`), a hand squash under `COMMIT_MESSAGES` keeps git's line, and `Reverts …#M` holds for any method. A hand merge under `PR_TITLE` or `BLANK` drops both: warn. Re-read `gh pr view {R} --json number,url,state`.
5. **Reopen N.** `gh issue reopen {N}`, then `gh issue comment {N} --body-file "$comment_file"` with `Reopened: #{M} is being reverted in #{R} ({R url}).` Re-read `gh issue view {N} --json state`: it must be `OPEN`.
6. **Log.** Pipe `{"issue":N,"mode":"interactive|auto","skill":"issue-pr-review","outcome":"revert_opened","pr":M,"revert_pr":R}` to `python3 shared/scripts/gi-runlog.py --append`. `pr` is `M`, never `R`; omit `skill_version`. Exit 3: fix the record, never raw-append. Exit 4 or no `python3`: `mkdir -p .idd` and append the line, with `ts` (ISO-8601 UTC), to `.idd/runs.jsonl`.

If `R` is later closed unmerged, close `N` again by hand.

```text
◆ Revert of #{M}
  ✓ #{R} opened against {base}
    {R url}
  ✓ #{N} reopened, linked to #{R}
  ✓ run log: revert_opened
```

A stop prints its block, then the footer (`references/run-stats.md`):

```text
✗ PR #{M} is not merged ({state}) — nothing to revert
  To fix:  pass a merged PR number
✗ PR #{M} was rebase-merged — no single commit to revert
  To fix:  revert its commits by hand through a PR
✗ Reverting #{M} conflicts with {base} — aborted, nothing pushed
  To fix:  revert by hand, resolve, open a PR
✗ Secret scan blocked the revert of #{M}: {blocking[]}
  To fix:  drop that file from the revert; open the PR by hand
```
