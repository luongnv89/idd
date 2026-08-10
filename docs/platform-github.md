# Platform Driver: GitHub

IDD skills talk to the issue tracker through a **platform driver** — a documented mapping from the abstract operations the workflow needs to one tool's concrete commands. This document is the **GitHub driver**, implemented with the [GitHub CLI](https://cli.github.com) (`gh`). It is the only implemented driver; `.gitissue.yml` selects it with `platform: github`.

Skills inline these commands at the step where they run, for execution speed. This catalog is the contract those inlined commands must match — when a command here changes, the skills follow.

## Driver rules

1. **Data retrieval always uses `--json` with explicit field selection.** Never parse `gh` text output — it is unstable across versions and locales. The field lists below are supersets; a skill selects only the fields it needs.
2. **Mutations are verified by re-reading.** After an edit/create, confirm with the corresponding read operation rather than trusting the exit code alone.
3. **Auth failures produce rich errors.** When `gh` is missing or unauthenticated: state what failed, then `To fix:  gh auth login`, then the docs link.
4. **Check the rate budget before batch loops** (triage, auto-pilot): `gh api rate_limit --jq '.rate.remaining'`.

## Operation catalog

### Preflight

| Operation | Canonical command |
|-----------|-------------------|
| Verify authentication | `gh auth status` |
| Remaining API budget | `gh api rate_limit --jq '.rate.remaining'` |
| Repo merge strategy | `gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed` |
| Caller's permission | `gh repo view --json viewerPermission` |

### Issues

| Operation | Canonical command |
|-----------|-------------------|
| Read one issue | `gh issue view {N} --json number,title,body,labels,assignees,state,comments,createdAt,updatedAt,author` |
| Resolution links | `gh issue view {N} --json number,state,closedByPullRequestsReferences` |
| List open issues | `gh issue list --state open --json number,title,body,labels,assignees,state,updatedAt --limit 100` |
| List closed issues | `gh issue list --state closed --json number,title,labels,closedAt --limit 50` |
| Create issue | `gh issue create --title "{title}" --body "{body}" --label "{labels}"` |
| Rewrite body (normalize) | `gh issue edit {N} --body "{normalized_body}"` |
| Add labels | `gh issue edit {N} --add-label "{label1},{label2}"` |
| Comment (backup, notice) | `gh issue comment {N} --body "{text}"` |
| Close with comment | `gh issue close {N} -c "{reason}"` |
| Reopen | `gh issue reopen {N}` |

### Pull requests

| Operation | Canonical command |
|-----------|-------------------|
| Create PR | `gh pr create --title "{pr_title}" --body "{pr_body}"` |
| Read one PR | `gh pr view {N} --json number,title,body,baseRefName,headRefName,headRefOid,state,url,labels,reviews,statusCheckRollup,files` |
| Merge readiness | `gh pr view {N} --json mergeable,reviewDecision,statusCheckRollup` |
| List merged PRs | `gh pr list --state merged --json number,title,body,mergeCommit,headRefName --limit 50` |
| List open PRs | `gh pr list --state open --json number,title,body,headRefName --limit 20` |
| Diff / changed files | `gh pr diff {N}` · `gh pr diff {N} --name-only` |
| Checkout PR head branch | `gh pr checkout {N}` |
| CI check status | `gh pr checks {N}` |
| Read PR body (before edit) | `gh pr view {N} --json body` |
| Update PR body | `gh pr edit {N} --body "{body}"` — use only after read-modify-write: fetch current body, apply the minimal change (e.g. prepend `Closes #N`), write back, then re-read to verify preserved sections |
| Squash-merge + clean up | `gh pr merge {N} --squash --delete-branch` |
| Find PR for an issue | `gh search prs "is:open" "Closes #{N}" --json number,state,url --limit 5` |

### Raw API (escape hatch)

For operations without a first-class `gh` subcommand — e.g. uploading issue assets — use `gh api` directly and note the endpoint inline:

```
gh api repos/{owner}/{repo}/contents/.github/issue-assets/{filename} ...
```

Prefer a catalog operation whenever one exists.

## Adding a driver

Porting IDD to another tracker (GitLab, Gitea, …) is deliberately scoped: write the equivalent driver document — `docs/platform-<name>.md` mapping every operation in this catalog to the new tool (e.g. `glab issue view`), then update the inlined commands in the skills to match it. The catalog above defines exactly which operations must exist; anything the new tool cannot express is a documented gap, not a silent one.

Until a second driver document exists, `github` is the only valid `platform` value — the config schema does not advertise drivers that have not been written.
