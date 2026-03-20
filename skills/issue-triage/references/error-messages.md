# Error Messages — /issue-triage

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

## Triage

### No open issues
```
○ No open issues found. Nothing to triage!
  Create issues with /issue-creator to get started.
```

### Too many issues
```
⚠ {count} open issues found. Analyzing first {limit}.

  To analyze all: /issue-triage --limit {count}
```

### Circular dependencies
```
⚠ Circular dependency detected: #{a} → #{b} → #{a}

  These issues reference each other's affected files.
  Suggestion: resolve #{a} first (fewer dependencies).
```

### API rate limit during fetch
```
✗ GitHub API rate limit reached while fetching issues

  Fetched {count}/{total} issues before limit.
  To fix:  wait a few minutes, then retry
  Check:   gh api rate_limit --jq '.rate.remaining'
```
