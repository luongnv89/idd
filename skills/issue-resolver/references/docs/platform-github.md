<!-- Generated from /docs/platform-github.md. Do not edit. Edit source and run ./scripts/build.sh. -->
# Platform Driver: GitHub

IDD skills reach the issue tracker through a **platform driver** — the workflow's operations mapped to one tool's commands. This is the **GitHub driver**, implemented with the [GitHub CLI](https://cli.github.com) (`gh`) and the only one implemented; `.gitissue.yml` selects it with `platform: github`. Skills inline these commands at the step where they run; this catalog is the contract they must match — when a command here changes, the skills follow.

> **Runtime digest (generated).** This is the normative subset of [platform-github.md](https://github.com/luongnv89/idd/blob/main/docs/platform-github.md) that skills read at run time. The sections a skill run never acts on live in the full document.

## Driver rules

1. **Data retrieval always uses `--json` with explicit field selection.** Never parse `gh` text output — it is unstable across versions and locales. The field lists below are supersets; a skill selects only what it needs.
2. **Mutations are verified by re-reading.** After an edit/create, confirm with the corresponding read rather than trusting the exit code.
3. **Auth failures produce rich errors.** When `gh` is missing or unauthenticated: state what failed, then `To fix:  gh auth login`, then the docs link.
4. **Check the rate budget before batch loops** (triage, auto-pilot): `gh api rate_limit --jq '{remaining: .rate.remaining, reset: .rate.reset}'` — one call, both fields; `reset` is what an unattended loop pauses until.
5. **Retry only transient failures, on bounded exponential backoff.** Recoverable: 5xx, connection reset or timeout, a *secondary* rate-limit 403 (honour `Retry-After`). Not recoverable: 401, 404, *primary* rate-limit exhaustion — rule 4's pause path, never backoff. `gi-ratelimit.py --backoff` computes the schedule; the loop lives with the caller.

## Operation catalog

### Preflight

| Operation | Canonical command |
|-----------|-------------------|
| Verify authentication | `gh auth status` |
| Remaining API budget | `gh api rate_limit --jq '{remaining: .rate.remaining, reset: .rate.reset}'` |
| Repo merge strategy | `gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed` |
| Squash-commit message source | `gh api repos/{owner}/{repo} --jq '{squash_merge_commit_title, squash_merge_commit_message}'` |
| Caller's permission | `gh repo view --json viewerPermission` |

REST, not `--json`: `gh repo view --json squashMergeCommitMessage` answers `Unknown JSON field`. It is **not** interchangeable with the strategy row above — that answers *is squash allowed*, this whether the squash commit carries the PR body (`PR_BODY`) or the commit subjects (`COMMIT_MESSAGES`, the default); only this one decides whether B1 lands (#295). Writing `PR_BODY` requires title source `PR_TITLE`.

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
| Merge readiness | `gh pr view {N} --json mergeable,reviewDecision,statusCheckRollup,headRefOid` |
| List merged PRs | `gh pr list --state merged --json number,title,body,mergeCommit,headRefName --limit 50` |
| List open PRs | `gh pr list --state open --json number,title,body,headRefName --limit 20` |
| Diff / changed files | `gh pr diff {N}` · `gh pr diff {N} --name-only` |
| Checkout PR head branch | `gh pr checkout {N}` |
| CI check status | `gh pr checks {N}` |
| Read PR body (before edit) | `gh pr view {N} --json body` |
| Update PR body | `gh pr edit {N} --body "{body}"` — read-modify-write only: fetch the body, apply the minimal change (e.g. prepend `Closes #N`), write back, verify per rule 2 |
| Squash-merge + clean up | `gh pr merge {N} --squash --delete-branch` |
| Find PR for an issue | `gh search prs "is:open" "Closes #{N}" --json number,state,url --limit 5` |

### Raw API (escape hatch)

For operations with no first-class `gh` subcommand — uploading issue assets, say — use `gh api` directly and note the endpoint inline (`gh api repos/{owner}/{repo}/contents/.github/issue-assets/{filename} ...`). Prefer a catalog operation when one exists.
