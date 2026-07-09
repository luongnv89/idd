# Error Messages — /issue-resolver

All errors follow the rich error format: what went wrong + fix command + docs link.

## Authentication & Setup

### Not authenticated
```
✗ Not authenticated with GitHub

  To fix:  gh auth login
  Docs:    https://cli.github.com/manual/gh_auth_login
```
**Trigger:** `gh` returns auth error (exit code 4 or "not logged in" in stderr).

### GitHub CLI not found
```
✗ GitHub CLI not found

  To fix:  brew install gh
  Docs:    https://cli.github.com
```
**Trigger:** `gh` command not found in PATH.

### No GitHub remote
```
✗ No GitHub remote configured

  To fix:  git remote add origin <url>
```
**Trigger:** `git remote -v` returns no output or no GitHub URL.

### Not a git repository
```
✗ Not a git repository

  To fix:  git init && git remote add origin <url>
```
**Trigger:** `git rev-parse --git-dir` fails.

## Issue Fetch

### Issue not found
```
✗ Issue #N not found

  To fix:  gh issue list
  Check:   is this the right repository?
```
**Trigger:** `gh issue view N` returns 404.

### Issue closed
```
⚠ Issue #N is already closed

  To fix:  gh issue reopen N
  Check:   was this resolved by another PR?
```
**Trigger:** Issue `state` is `closed` in the fetched JSON.

## Guards

### Assigned to another user
```
⚠ Issue #N is assigned to @username

  Proceeding may duplicate work.
  Continue anyway? [y/N]
```
**Trigger:** Issue `assignees` list contains a user other than the current authenticated user.

### Blocking label
```
⚠ Issue #N has blocking label: {label_name}

  This issue may not be ready for resolution.
  Continue anyway? [y/N]
```
**Trigger:** Issue labels include `wontfix`, `blocked`, or `do-not-merge` (case-insensitive).

## Branch

### Branch already exists (worktree path — Step 0e)
```
⚠ Branch {branch} already exists

  You were creating a worktree for issue #{N}.

  Options:
    continue  — attach a new worktree to the existing branch
              (git worktree add "{wt_dir}" "{branch}")
    fresh     — delete the branch, then retry git worktree add -b

  Choose: [continue/fresh]
```
**Trigger:** `git worktree add -b {branch} {wt_dir}` fails because the branch already exists (Step 0e). On `continue`, set `created_branch_in_step_0e=0` and run `git worktree add "$wt_dir" "$branch"`. On `fresh`, delete the branch, keep `created_branch_in_step_0e=1`, and retry creation.

### Branch already exists (in-place path — Step 0f)
```
⚠ Branch {branch} already exists

  Options:
    continue  — check out the existing branch in this working tree
    fresh     — delete the branch and create it again from {base_branch}

  Choose: [continue/fresh]
```
**Trigger:** `git checkout -b {branch}` fails because the branch already exists (Step 0f, in-place path). On `continue`, run `git checkout {branch}`. On `fresh`, run `git branch -D {branch}` then `git checkout -b {branch}`.

### Worktree creation failed
```
⚠ Could not create the worktree at {wt_dir}

  Falling back to resolving in the current working tree.
  To clean up stale worktrees:  git worktree prune
```
**Trigger:** `git worktree add` fails for a reason other than an existing branch (path already occupied, locked worktree, disk error). Non-fatal — the resolver continues on the in-place path (Repo Sync + branch creation). Interactive only; the worktree offer never runs in auto mode.

### Worktree setup failed
```
⚠ Worktree setup failed at {wt_dir}

  Cleaning up the partial worktree, then falling back to resolving in the
  current working tree.
  Recover manually:  git worktree list && git worktree remove {wt_dir}
                    git worktree prune
```
**Trigger:** local setup preparation fails after the worktree was created (copy error, dependency install failure, bootstrap failure). The resolver removes the partial worktree, deletes only a branch created by this Step 0e, then continues on the in-place path. If cleanup fails, stop and ask the user to run the recovery commands.

## Verify

### Tests failed
```
✗ Tests failed — PR not created

  {test_output_summary}

  To fix:  review failures above and update the code
  Run:     {test_command}
```
**Trigger:** Test runner exits with non-zero status.

### Tests timed out
```
✗ Tests timed out after {timeout}s — PR not created

  The test suite did not complete within the configured timeout.
  To fix:  increase resolve.test_timeout in .gitissue.yml
  Check:   are tests hanging? Run manually: {test_command}
```
**Trigger:** Test runner does not complete within `resolve.test_timeout` seconds.

### Max commits exceeded
```
⚠ Resolve produced {count} commits (max_commits: {max})

  This may indicate the change is too large for a single issue.
  Continue creating PR? [y/N]
```
**Trigger:** Number of commits created during Execute exceeds `resolve.max_commits`.

## Ship

### PR creation failed
```
✗ Failed to create PR

  To fix:  check your permissions and try: gh pr create --title "..." --body "..."
  Check:   is the branch pushed? git push -u origin {branch}
```
**Trigger:** `gh pr create` returns a non-zero exit code.

### Merge conflicts
```
✗ Branch has merge conflicts with {base_branch}

  To fix:  git rebase {base_branch} and resolve conflicts
  Then:    /issue-resolver N (to resume from verify phase)
```
**Trigger:** `git push` or `gh pr create` reports merge conflicts with the base branch.

### Push failed
```
✗ Failed to push branch {branch_name}

  To fix:  check remote access: git remote -v
  Check:   do you have push permission? gh repo view --json viewerPermission
```
**Trigger:** `git push -u origin {branch_name}` exits with non-zero status.

### Rate limited during PR creation
```
✗ GitHub API rate limit reached

  To fix:  wait a few minutes, then retry
  Check:   gh api rate_limit --jq '.rate.remaining'
```
**Trigger:** HTTP 403 with rate limit headers during `gh pr create`.

## Research

### Issue body empty
```
⚠ Issue #N has no description. Resolution may be incomplete.

  Continue anyway? [y/N]
```
**Trigger:** Issue body is empty or null after fetch.

### Large scope warning
```
⚠ This issue may require changes to {N} files.

  Consider breaking it into smaller issues.
  Continue anyway? [y/N]
```
**Trigger:** Research phase identifies more than 20 potentially affected files.

## Auto-normalize

### Security-labeled issue (skip)
```
⚠ Issue #N has a security label ({label}). Skipping auto-normalization.
  Rewriting security-sensitive issues requires explicit operator confirmation (SPEC §1.4).

  To normalize first: /issue-creator N   (or /issue-creator N --force after review)
```
**Trigger:** Step 0d finds a `security`, `CVE`, or `vulnerability` label (case-insensitive) and the operator has not confirmed a rewrite (auto mode always skips; interactive defaults to skip). Non-fatal — the pipeline continues with the original issue body.

### Auto-normalization failed
```
⚠ Auto-normalization failed for issue #N — proceeding without normalization.

  To fix:  run /issue-creator N manually to normalize
```
**Trigger:** Any failure during the auto-normalize step (backup comment fails, API error, etc.). Non-fatal — the pipeline continues with the original issue body.

## Configuration

### Invalid config
```
✗ Invalid config: .gitissue.yml

  Line {N}: {field} {validation_message}

  To fix:  edit .gitissue.yml and correct the values above
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
```
**Trigger:** Config file exists but contains invalid values (wrong type, out of range, unknown field).
