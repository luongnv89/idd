# Error Messages — /issue-resolver

All errors follow the rich error format: what went wrong + fix command + docs link.

## Authentication & Setup

### Not authenticated
```
✗ Not authenticated with GitHub

  To fix:  gh auth login
  Docs:    https://cli.github.com/manual/gh_auth_login
```

### GitHub CLI not found
```
✗ GitHub CLI not found

  To fix:  brew install gh
  Docs:    https://cli.github.com
```

### No GitHub remote
```
✗ No GitHub remote configured

  To fix:  git remote add origin <url>
```

## Issue Fetch

### Issue not found
```
✗ Issue #N not found

  To fix:  gh issue list
  Check:   is this the right repository?
```

### Issue closed
```
⚠ Issue #N is already closed

  To fix:  gh issue reopen N
  Check:   was this resolved by another PR?
```

## Guards

### Assigned to another user
```
⚠ Issue #N is assigned to @username

  Proceeding may duplicate work.
  Continue anyway? [y/N]
```

### Blocking label
```
⚠ Issue #N has blocking label: {label_name}

  This issue may not be ready for resolution.
  Continue anyway? [y/N]
```

## Branch

### Branch already exists
```
⚠ Branch issue-N/{description} already exists

  Options:
    continue  — resume from existing branch
    fresh     — delete and start fresh

  Choose: [continue/fresh]
```

## Verify

### Tests failed
```
✗ Tests failed — PR not created

  {test_output_summary}

  To fix:  review failures above and update the code
  Run:     {test_command}
```

### Tests timed out
```
✗ Tests timed out after {timeout}s — PR not created

  The test suite did not complete within the configured timeout.
  To fix:  increase resolve.test_timeout in .gitissue.yml
  Check:   are tests hanging? Run manually: {test_command}
```

### Max commits exceeded
```
⚠ Resolve produced {count} commits (max_commits: {max})

  This may indicate the change is too large for a single issue.
  Continue creating PR? [y/N]
```

## Ship

### PR creation failed
```
✗ Failed to create PR

  To fix:  check your permissions and try: gh pr create --title "..." --body "..."
  Check:   is the branch pushed? git push -u origin {branch}
```

### Merge conflicts
```
✗ Branch has merge conflicts with {base_branch}

  To fix:  git rebase {base_branch} and resolve conflicts
  Then:    /issue-resolver N (to resume from verify phase)
```
