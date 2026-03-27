# Error Messages — /issue-pr-review-fix-loop

All errors follow the rich format: symbol + description + fix action.

---

## Prerequisite Errors

### Not a git repository

**Trigger:** `git rev-parse --git-dir` fails.

```
✗ Not inside a git repository

  To fix:  cd into your project directory
  Check:   ls -la .git
```

### GitHub CLI not installed

**Trigger:** `which gh` fails.

```
✗ GitHub CLI (gh) not found

  To fix:  brew install gh   (macOS)
           https://cli.github.com (other)
```

### Not authenticated

**Trigger:** `gh auth status` fails.

```
✗ Not authenticated with GitHub

  To fix:  gh auth login
```

---

## PR Errors

### PR not found

**Trigger:** `gh pr view {N}` fails.

```
✗ PR #{N} not found

  To fix:  gh pr list
  Check:   is this the right repository?
```

### No PR for current branch

**Trigger:** No PR number provided and `gh pr view` fails for current branch.

```
✗ No PR found for branch {branch_name}

  To fix:  gh pr create
  Or:      /issue-pr-review-fix-loop <PR_NUMBER>
```

### PR already closed/merged

**Trigger:** PR state is `CLOSED` or `MERGED`.

```
⚠ PR #{N} is already {state}

  Nothing to review.
```

---

## Fix Errors

### Push failed

**Trigger:** `git push` fails after committing fixes.

```
✗ Failed to push fixes to {branch_name}

  To fix:  check remote access: git remote -v
  Check:   do you have push permission? gh repo view --json viewerPermission
```

### Merge failed

**Trigger:** `gh pr merge` fails (auto mode only).

```
⚠ Auto-merge failed: {reason}

  Manual merge required.
  PR:   {pr_url}
  Docs: https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/merging-a-pull-request
```

---

## Loop Errors

### Stagnation detected

**Trigger:** Identical issues found in 2 consecutive review cycles.

```
⚠ Stagnation detected — same {N} issues found in cycles {A} and {B}

  The automated fixer cannot resolve these issues.
  Manual attention required:
    ● [{category}] {description} ({file}:{line})
```

### Max cycles exhausted

**Trigger:** Loop reached `review.max_cycles` with issues remaining.

```
⚠ {N} issues remain after {max_cycles} review-fix cycles

  Remaining issues:
    ● [{category}] {description} ({file}:{line})

  These may need manual attention.
  PR: {pr_url}
```

---

## Sync Errors

### Rebase conflict

**Trigger:** `git pull --rebase` encounters conflicts.

```
✗ Rebase conflict on {branch_name}

  To fix:  git rebase --abort && git pull origin {branch_name}
  Check:   git status
```

### Remote not found

**Trigger:** `git fetch origin` fails because no remote named `origin` exists.

```
✗ Remote 'origin' not found

  To fix:  git remote add origin <url>
  Check:   git remote -v
```
