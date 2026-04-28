<!-- Generated from src/docs/naming-conventions.md. Do not edit. Edit source and run ./scripts/build.sh. -->
# Naming Conventions

Standard conventions for naming branches, commits, pull requests, and issues across all gitissue skills. These conventions follow industry-standard practices (Conventional Commits, Gitflow-inspired prefixes) to ensure readability, automation compatibility, and clean git history.

## Why These Conventions Matter

- **Readability**: Anyone can glance at a branch/PR/commit and understand its purpose
- **Automation**: Changelog generators, release scripts, and CI/CD pipelines parse these patterns
- **Traceability**: Issue numbers link every artifact back to the work item that motivated it
- **Collaboration**: Reduces confusion in teams and open-source projects

---

## Branch Names

**Format:** `<type>/<issue-number>-<short-description>`

### Rules

- **Lowercase only** — never uppercase letters
- **Hyphens between words** — never spaces or underscores
- **Always include the issue number** — for traceability back to the work item (exception: `release/` and `hotfix/` branches may omit the issue number when they're workflow-driven, not issue-driven)
- **Keep total length under 50 characters** — short, readable, greppable
- **Type prefix** — instantly communicates the branch's purpose

### Type Prefixes

| Prefix | When to use | Example |
|--------|-------------|---------|
| `fix/` | Bug fixes | `fix/42-mobile-auth-redirect` |
| `feat/` | New features or functionality | `feat/15-dark-mode-toggle` |
| `refactor/` | Code improvements (no behavior change) | `refactor/8-cleanup-auth-module` |
| `docs/` | Documentation changes | `docs/23-update-api-reference` |
| `test/` | Adding or fixing tests | `test/31-add-auth-unit-tests` |
| `chore/` | Maintenance, builds, dependencies | `chore/50-update-dependencies` |
| `hotfix/` | Urgent production/critical fixes | `hotfix/99-security-patch` |
| `release/` | Preparing a new version | `release/v1.2.0` |

### Deriving the Short Description

1. Take the issue title
2. Convert to lowercase
3. Replace spaces with hyphens
4. Remove non-alphanumeric characters (except hyphens)
5. Truncate to keep total branch name under 50 characters

### Issue Type → Branch Prefix Mapping

| Issue type | Branch prefix |
|------------|---------------|
| bug | `fix/` |
| feature | `feat/` |
| improvement | `refactor/` |
| documentation | `docs/` |
| test | `test/` |
| maintenance | `chore/` |

### Examples

| Issue | Type | Branch name |
|-------|------|-------------|
| #42 "Fix mobile auth redirect loop" | bug | `fix/42-mobile-auth-redirect-loop` |
| #15 "Add dark mode toggle" | feature | `feat/15-add-dark-mode-toggle` |
| #8 "Clean up auth middleware" | improvement | `refactor/8-cleanup-auth-middleware` |
| #23 "Update API reference docs" | documentation | `docs/23-update-api-reference` |

### Custom Prefix Override

If the user has configured `resolve.branch_prefix` in `.gitissue.yml` to a string other than `"auto"`, use that fixed prefix instead of type-based prefixes:

- `branch_prefix: "auto"` (default) → type-based: `fix/42-description`
- `branch_prefix: "issue-"` → fixed: `issue-42/description`

---

## Commit Messages

**Format:** `<type>(<scope>): <description> (#<issue-number>)`

Follows the **Conventional Commits** specification (https://www.conventionalcommits.org/).

### Structure

```
<type>(<scope>): <description> (#<issue-number>)
```

- **type** (required) — categorizes the change
- **scope** (optional, recommended) — module, component, or area affected
- **description** (required) — imperative mood, lowercase, no trailing period
- **issue reference** (required) — `(#N)` at the end for traceability

### Types

| Type | Purpose | Example |
|------|---------|---------|
| `feat` | New feature | `feat(auth): implement OAuth login (#42)` |
| `fix` | Bug fix | `fix(checkout): resolve redirect loop (#15)` |
| `refactor` | Code change, no behavior change | `refactor(auth): extract middleware helper (#8)` |
| `docs` | Documentation only | `docs(readme): update installation steps (#23)` |
| `test` | Adding or fixing tests | `test(auth): add login flow unit tests (#31)` |
| `chore` | Maintenance, deps, tooling | `chore(deps): update express to v5 (#50)` |
| `style` | Formatting, whitespace (no logic change) | `style(lint): apply prettier formatting (#60)` |
| `perf` | Performance improvement | `perf(query): add index for user lookup (#70)` |

### Rules

- Use **imperative mood**: "add feature" not "added feature" or "adding feature"
- Keep the first line **under 72 characters**
- Scope should name the module or component, not the file: `auth` not `auth.py`
- One logical change per commit — atomic commits

### Multi-line Commit Messages

For complex changes, add a body after a blank line:

```
fix(auth): resolve mobile redirect loop (#42)

The redirect middleware was checking the session cookie before
it was set, causing an infinite loop on mobile browsers that
clear cookies between redirects.
```

---

## Pull Request Titles

**Format:** `<type>(<scope>): <description> (#<issue-number>)`

Same convention as commit messages. The PR title should summarize what the entire PR accomplishes.

### Rules

- Same `type(scope): description` format as commits
- Use the **dominant type** if the PR spans multiple types (e.g., a PR with fix + test commits uses `fix`)
- Keep under **72 characters**
- Issue reference goes in the title: `(#N)`
- `Closes #N` goes on the **first line of the PR body** (not in the title) — this auto-closes the issue on merge

### Examples

| PR title | Body first line |
|----------|----------------|
| `fix(auth): resolve mobile redirect loop (#42)` | `Closes #42` |
| `feat(settings): add dark mode toggle (#15)` | `Closes #15` |
| `refactor(db): extract connection pool logic (#8)` | `Closes #8` |

### PR Body Structure

```markdown
Closes #<issue-number>

## Summary
{One-paragraph summary of what was done and why}

## Approach
{Brief description of the implementation approach}

## Changes
| File | Change |
|------|--------|
| `file1` | {what changed} |
| `file2` | {what changed} |

## Test Results
{Test output summary}

## Acceptance Criteria
- [x] {criterion 1}
- [x] {criterion 2}
- [ ] {criterion 3 — if not addressed}
```

---

## Issue Titles

### Rules

- Use **imperative mood** (like a command): "Fix login crash on mobile" not "Login is crashing"
- Keep titles **concise and actionable** — under 70 characters
- Include **context** when helpful: "Fix checkout page redirect on Safari"
- Optional **type prefix** for extra clarity: "Bug: ...", "Feature: ...", "Enhancement: ..."

### Examples

| Good | Bad |
|------|-----|
| Fix mobile auth redirect loop | Login is broken |
| Add dark mode toggle to settings page | Dark mode |
| Refactor auth middleware for OAuth2 | Auth stuff needs updating |
| Bug: App crashes on iOS when tapping login | It doesn't work on my phone |

### Labels

Use labels for machine-readable categorization — the title stays human-readable:

- `bug`, `feature`, `improvement` — issue type
- `priority:high`, `priority:low` — urgency
- `good first issue` — contributor onboarding
- `blocked`, `wontfix`, `do-not-merge` — workflow state

---

## Quick Reference

| Artifact | Format | Example |
|----------|--------|---------|
| Branch | `<type>/<N>-<desc>` | `fix/42-mobile-auth-redirect` |
| Commit | `<type>(<scope>): <desc> (#N)` | `fix(auth): resolve redirect loop (#42)` |
| PR title | `<type>(<scope>): <desc> (#N)` | `fix(auth): resolve redirect loop (#42)` |
| Issue title | Imperative, actionable | Fix mobile auth redirect loop |
