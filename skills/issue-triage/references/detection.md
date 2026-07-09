# /issue-triage — Already-Fixed & Dependency Detection

Full spec for Step 1b (already-fixed detection via commit/PR history) and Step 2 (dependency analysis via file-overlap). SKILL.md keeps a summary; read this for the subagent prompts and confidence-scoring rules.

## Step 1b — Detect Already-Fixed Issues

Some open issues may have been incidentally fixed by commits or PRs that targeted a different issue. For example, a PR titled `fix(auth): resolve redirect loop (#42)` might also fix the bug described in issue #17 if they share the same root cause. This step scans recent git history and merged PRs to catch these cases, so the team doesn't waste time on issues that are already resolved.

### Subagent delegation

**When the Agent tool is available:** Delegate this step to the issue-relationship-scanner subagent (history scan). Read `references/agents/issue-relationship-scanner.md` for the full prompt template. Pass open issues as `{number, title, body}` from Step 1, along with the repo root path (absolute). The subagent returns a JSON object with a `potentially_fixed` array and `scanned_commits`/`scanned_prs` counts. Spawn this subagent **in the same turn** as the dependency scanner (Step 2) — they are independent and run in parallel.

**Note:** The issue-relationship-scanner's history scan only implements the commit-level signal (explicit issue references in commit messages and PR bodies). The file-overlap signal (detecting fixes via shared affected files) requires data from the dependency scan and is handled by the main agent in the **post-merge step** below.

### Post-merge (after Steps 1b and 2 subagents return)

1. Merge `potentially_fixed`, per-issue `affected_files`, and `dependency_edges` from all batches.
2. For each open issue, if a merged PR's changed files overlap its `affected_files` **and** the PR references that issue number, upgrade `potentially_fixed` confidence per table (c).
3. Convert undirected scanner edges to **directed** `blocks` / `blocked_by` using creation date (`createdAt`), blocking count, and type precedence (bug before feature/improvement) — same heuristics as the inline Step 2 procedure.

**When the Agent tool is NOT available:** Execute the procedure below inline.

### How it works

**a) Scan commit messages for issue references:**

```bash
git log --all --oneline --since="3 months ago"
```

Parse each commit message for references to open issue numbers. Look for patterns like:
- `#N` (bare reference)
- `Closes #N`, `Fixes #N`, `Resolves #N` (GitHub closing keywords, case-insensitive)
- Branch names containing issue numbers (e.g., `fix/42-mobile-auth`)

For each open issue, collect all commits that reference it.

**b) Cross-reference with merged PRs:**

```bash
gh pr list --state merged --json number,title,body,mergeCommit,headRefName --limit 50
```

For each merged PR, extract:
- Issue numbers from the PR title (e.g., `(#42)`)
- Issue numbers from the PR body (`Closes #N`, `Fixes #N`, `Resolves #N`)
- Issue numbers from the branch name (`fix/42-...`)

This gives you a map: **PR → set of issue numbers it explicitly targets**.

**c) Identify potentially fixed issues:**

An open issue `#X` is flagged as **potentially fixed** when:

1. **Commit-level signal**: A commit references `#X` (via `Closes`, `Fixes`, `Resolves`, or bare `#N`) but that commit belongs to a PR that was created for a *different* issue. This means issue `#X` was mentioned in someone else's fix.

2. **File-overlap signal**: A merged PR modified files that overlap with issue `#X`'s affected files (from the keyword scan in Step 2), AND the PR's commit messages or body mention issue `#X` by number.

Both signals require an explicit mention of the issue number — pure file overlap without a reference is not enough (that's what dependency analysis in Step 2 handles).

**d) Confidence levels:**

| Confidence | Criteria |
|-----------|----------|
| `high` | Commit uses a closing keyword (`Closes #X`, `Fixes #X`, `Resolves #X`) and is in a merged PR for a different issue |
| `medium` | Commit references `#X` (bare mention) in a merged PR for a different issue, or the PR body mentions `#X` alongside another issue |
| `low` | Branch name contains `#X`'s number but no explicit commit/PR body reference |

Only `high` and `medium` confidence matches are flagged. `low` is too noisy — branch names like `fix/12-auth` could match issue #1 or #12 accidentally.

### Output

For each potentially fixed issue, collect:
- The issue number
- The PR(s) and/or commit(s) that likely fixed it
- The confidence level
- Which other issue the PR was targeting

This data feeds into Step 8 (Output) and Step 9 (Persist).

Progress output:

```
● Scanning commit history for already-fixed issues...
```

If any are found:

```
● Scanning commit history for already-fixed issues...
  ◆ {N} issue(s) may already be fixed
```

## Step 2 — Analyze Dependencies

### Subagent delegation

**When the Agent tool is available:** Delegate this step to the issue-relationship-scanner subagent (dependency scan). Read `references/agents/issue-relationship-scanner.md` for the full prompt template. Pass the list of issues (number, title, body) from Step 1 along with the repo root path and the `scan_timeout_per_issue` config value (passed as `scan_timeout` in the subagent input). Spawn this subagent **in the same turn** as the history scanner (Step 1b) — they are independent and run in parallel.

**For 10+ issues:** Split the issues into batches of ~5 and spawn one issue-relationship-scanner subagent (dependency scan) per batch (all in the same turn). After all subagents return, merge their results:
1. Concatenate the `issues` maps from each batch into a single map
2. Concatenate the `dependency_edges` arrays from each batch
3. Run a cross-batch pass: for any two issues from different batches, check if their `affected_files` overlap. If they do, add a dependency edge. Determine directionality using the same heuristics as the inline procedure: earlier creation date takes precedence, more blocking relationships take precedence, and bug type takes precedence over feature/improvement. If neither issue clearly precedes the other, mark them as co-dependent at the same level. This is a lightweight comparison the main agent does on the merged data.

**When the Agent tool is NOT available:** Execute the procedure below inline.

### Inline procedure

For each issue, extract keywords from the issue title and body — look for error messages, component names, file paths, function names, class names, and module references. Then grep the codebase for each issue's keywords to find affected files. Issues sharing affected files or modules (same parent directory) are considered dependent.

**Keyword extraction:** Parse the title and body for meaningful search terms. Ignore common stop-words, markdown syntax, and generic phrases. Prefer specific identifiers: function names (`handleAuth`), file paths (`src/auth.py`), error strings (`"ECONNREFUSED"`), component names (`SessionManager`).

**Codebase scan:** For each extracted keyword, search the local codebase (respecting `.gitignore`). Collect the set of files that match. This is the issue's affected files list.

**Scan timeout:** Each issue's scan is bounded by `triage.scan_timeout_per_issue` (default: 30 seconds). If the scan exceeds this limit, stop scanning for that issue, mark it as `no-deps (timeout)` in the dependency graph, and emit the timeout warning from `references/error-messages.md`.

Build a dependency graph:
- Each issue is a node.
- An edge from issue A to issue B means they share one or more affected files (found by keyword scan), and A should be resolved before B (determined by: earlier creation date, more blocking relationships, or bug type takes precedence).
- If two issues share the same file and neither clearly precedes the other, mark them as co-dependent at the same level.
- Issues marked `no-deps (timeout)` have no edges — they appear as isolated nodes.

Progress output:

```
● Scanning codebase for issue dependencies...
```

## Step 3 — Detect Circular Dependencies

Walk the dependency graph and check for cycles using a depth-first traversal.

If a cycle is found, warn using the format from `references/error-messages.md`:

```
⚠ Circular dependency detected: #12 → #15 → #12

  These issues share affected files detected by codebase scan.
  Suggestion: resolve #12 first (fewer dependencies).
```

The suggestion should recommend resolving the issue in the cycle that has the fewest outgoing dependencies. If tied, prefer the older issue.

Do not abort on circular dependencies — break the cycle by removing the back-edge, note the cycle in the output, and continue with the remaining graph.

