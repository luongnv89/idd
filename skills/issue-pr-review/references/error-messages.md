# Error Messages — /issue-pr-review

All errors follow the rich format: symbol + description + fix action.

---

## Prerequisite Errors

### Not a git repository

**Trigger:** `git rev-parse --git-dir` fails.

```
✗ Not inside a git repository

  To fix:  cd into your project directory
  Check:   ls -la .git
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/platform-github.md
```

### GitHub CLI not installed

**Trigger:** `which gh` fails.

```
✗ GitHub CLI (gh) not found

  To fix:  brew install gh   (macOS)
           https://cli.github.com (other)
  Docs:    https://cli.github.com
```

### Not authenticated

**Trigger:** `gh auth status` fails.

```
✗ Not authenticated with GitHub

  To fix:  gh auth login
  Docs:    https://cli.github.com/manual/gh_auth_login
```

---

## PR Errors

### PR not found

**Trigger:** `gh pr view {N}` fails.

```
✗ PR #{N} not found

  To fix:  gh pr list
  Check:   is this the right repository?
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/platform-github.md
```

### No PR for current branch

**Trigger:** No PR number provided and `gh pr view` fails for current branch.

```
✗ No PR found for branch {branch_name}

  To fix:  gh pr create
  Or:      /issue-pr-review <PR_NUMBER>
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/platform-github.md
```

### PR already closed/merged

**Trigger:** PR state is `CLOSED` or `MERGED`.

```
⚠ PR #{N} is already {state}

  Nothing to review.
```

---

## Linked Issue Errors

### Linked issue unreadable at the review boundary

**Trigger:** the PR body links an issue (`Closes #{N}`), but neither the Step 1
*Depth gate* refresh nor its direct-`gh` degrade returns a usable record — on the
first attempt or on the single re-run. This is a **stop**, not a degrade: Step 3
would otherwise verify acceptance criteria against an empty snapshot and report
the `acceptance_criteria` hard-block as `pass`. A PR with **no** linked issue is
not this error and is never stopped by it — see *The empty-record fail-safe* in
`references/review-loop-mechanics.md`.

**Placeholders:** this is the one entry in this file where `{N}` is **not** the
PR number. Here `{N}` is the **linked issue** being read — the number `Closes #N`
names — and `{PR}` is the pull request under review. The resume command takes
`{PR}`; re-running the review against the issue number reviews the wrong PR, or
none.

```
✗ Cannot read linked issue #{N} — review stopped

  To fix:  gh issue view {N} --json number,title,body,labels
  Then:    /issue-pr-review {PR}
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/platform-github.md
```

---

## CI Errors

### CI check timeout

**Trigger:** CI checks still running after `review.ci_timeout` seconds.

```
⚠ CI checks still running after {timeout}s

  To fix:  wait and re-run /issue-pr-review {N}
  Check:   gh pr checks {N}
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/platform-github.md
```

### CI log fetch failed

**Trigger:** `gh run view {run_id} --log-failed` fails.

```
⚠ Could not fetch CI failure logs

  To fix:  gh run view {run_id} --log-failed
  Check:   gh run list
  Docs:    https://cli.github.com/manual/gh_run_view
```

---

## Fix Errors

### Push failed

**Trigger:** `git push` fails after applying fixes.

```
✗ Failed to push fixes to {branch_name}

  To fix:  check remote access: git remote -v
  Check:   do you have push permission? gh repo view --json viewerPermission
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/platform-github.md
```

### Merge failed

**Trigger:** `gh pr merge` fails (auto mode only).

```
⚠ Auto-merge failed: {reason}

  Manual merge required.
  PR:  {pr_url}
```

---

## Stagnation

### Same issues across cycles

**Trigger:** Identical issues found in 2 consecutive review cycles.

```
⚠ Stagnation detected — same {N} issues found in cycles {A} and {B}

  The automated fixer cannot resolve these issues.
  Manual attention required:
    ● [category] description (file:line)
```
