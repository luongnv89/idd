# /issue-triage — Already-Fixed & Dependency Detection

Full spec for Step 1b (already-fixed detection via commit/PR history) and Step 2 (dependency analysis via file-overlap). SKILL.md keeps a summary; read this for the subagent prompts and confidence-scoring rules.

## Step 1b — Detect Already-Fixed Issues

Some open issues may have been incidentally fixed by commits or PRs that targeted a different issue. For example, a PR titled `fix(auth): resolve redirect loop (#42)` might also fix the bug described in issue #17 if they share the same root cause. This step scans recent git history and merged PRs to catch these cases, so the team doesn't waste time on issues that are already resolved.

### Subagent delegation

**When the Agent tool is available:** Spawn **one** issue-relationship-scanner subagent per batch for both Step 1b and Step 2. Read `shared/agents/issue-relationship-scanner.md` for the full prompt template. Pass the full input `{ issues: [{number, title, body}], repo_root, scan_timeout, scope: "both" }`, where `repo_root` is absolute and `scan_timeout` is the `scan_timeout_per_issue` config value. Consume its `history_scan` here: it contains `potentially_fixed`, `merged_prs` (PR number, referenced issue numbers, and changed-file paths), and `scanned_commits`/`scanned_prs` counts.

**Note:** The full-scope scanner implements the commit-level signal, fetches changed-file paths for merged PRs that explicitly reference an open issue, and returns the dependency data used by Step 2. The file-overlap signal combines both result sections in the main agent's **post-merge step** below.

### Post-merge (after Steps 1b and 2 subagents return)

1. Merge `history_scan.potentially_fixed`, `history_scan.merged_prs`, per-issue `affected_files`, and `dependency_edges` from all batches.
2. For each open issue, compare its `affected_files` with each `history_scan.merged_prs[].changed_files`. Promote file overlap only when all conditions hold: the PR has a known `target_issues` value different from the open issue; `references` contains that open issue with `source: "body"` (or a correlated commit reference has `reference_source: "commit"`); and the files overlap. Do **not** use `referenced_issues` alone: it is compatibility/traceability metadata and loses source information. Never promote a title or branch reference, and never promote an issue that is itself a PR target. If fetching one PR's files failed, warn and skip only that PR's file-overlap signal.
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

Retain the source for every reference as `body`, `title`, or `branch`. Derive `target_issues` from body closing references when available; otherwise title/branch references may identify the PR target, but are never incidental-fix evidence. For every merged PR that references an open issue, fetch its changed files:

```bash
gh pr view <N> --json files
```

Store the returned `files[].path` as that PR's `changed_files`. If this fetch fails, warn and skip only that PR's file-overlap signal.

**c) Identify potentially fixed issues:**

An open issue `#X` is flagged as **potentially fixed** when:

1. **Commit-level signal**: A commit references `#X` (via `Closes`, `Fixes`, `Resolves`, or bare `#N`) but that commit belongs to a PR that was created for a *different* issue. This means issue `#X` was mentioned in someone else's fix.

2. **File-overlap signal**: A merged PR modified files that overlap with issue `#X`'s affected files (from the keyword scan in Step 2), AND a PR-body or commit reference mentions `#X` by number, AND `#X` is distinct from the PR's known target issue. A title or branch reference is insufficient, even when it names `#X`.

Both signals require an eligible explicit mention of the issue number and a distinct known PR target — pure file overlap, title/branch references, or a reference to the PR's own target issue are not enough (that is dependency/traceability data, not incidental-fix evidence).

**d) Confidence levels:**

| Confidence | Criteria |
|-----------|----------|
| `high` | Commit uses a closing keyword (`Closes #X`, `Fixes #X`, `Resolves #X`) and is in a merged PR for a different issue |
| `medium` | Commit or PR body references `#X` (bare mention) in a merged PR targeting a different issue |
| `low` | Title or branch name contains `#X`'s number but no eligible commit/PR-body reference |

Only `high` and `medium` confidence matches are flagged. `low` is too noisy — title/branch references are target/traceability metadata, not incidental-fix evidence.

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

**When the Agent tool is available:** Do **not** spawn another scanner for Step 2. Consume `dependency_scan` from the same full-scope (`scope: "both"`) result spawned for Step 1b. It contains the per-issue `affected_files` and `dependency_edges`; the input and output contract is defined in `shared/agents/issue-relationship-scanner.md`.

**For 10+ issues:** Split the issues into batches of ~5 and spawn one full-scope issue-relationship-scanner subagent per batch (all in the same turn). After all subagents return, merge their results:
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

## Steps 3-7 — the prose procedure

`shared/scripts/gi-triage-graph.py` implements everything in this section, and
SKILL.md runs it. What follows is the authoritative statement of the rules it
applies — read it to understand or audit an ordering, and **run** it by hand
only on the documented degrade path (no `python3`, exit 2, or unparsable
stdout). Exit 3 is not a degrade: it means the scan handed to the script was
invalid, and the fix is the scan, not this procedure.

### Step 3 — Detect Circular Dependencies

Walk the dependency graph and check for cycles using a depth-first traversal.
Visit nodes, and each node's successors, in ascending issue order, so the same
graph always yields the same cycle list and the same broken edges.

If a cycle is found, warn using the format from `references/error-messages.md`:

```
⚠ Circular dependency detected: #12 → #15 → #12

  These issues share affected files detected by codebase scan.
  Suggestion: resolve #12 first (fewer dependencies).
```

The suggestion should recommend resolving the issue in the cycle that has the fewest outgoing dependencies. If tied, prefer the older issue.

Do not abort on circular dependencies — break the cycle by removing the back-edge, note the cycle in the output, and continue with the remaining graph.

### Step 4 — Compute Execution Order

Perform a topological sort on the dependency graph (after breaking any cycles from Step 3).

- Issues with no incoming dependencies come first — they are "ready" to work on.
- Issues blocked by other issues are ordered after their blockers.
- Within the same topological level, sort by: bugs before features before improvements, then by age (oldest first), then by issue number.

Assign a status to each issue, in this precedence order:
- **maybe-fixed** — flagged in Step 1b as potentially already resolved (high or medium confidence)
- **blocked #N** — depends on issue #N being resolved first
- **stale (Nd)** — no activity beyond the threshold (Step 6)
- **ready** — none of the above

Issues flagged as `maybe-fixed` are sorted to the bottom of the execution order — there's no point working on them until someone verifies whether the fix actually landed. They still appear in the triage table so the team can review and close them.

### Step 5 — Identify Parallelizable Issues

Find sets of issues at the same topological level that are independent of each other (no shared affected files, no dependency edges between them). Report only sets of two or more.

These issues can be worked on simultaneously by different developers. Group them for the recommendation output in Step 8.

### Step 6 — Stale Detection

For each issue, compare `updatedAt` to today's date. If the difference exceeds `triage.stale_threshold_days` (default: 14 days), flag the issue as stale.

The stale flag is reflected in both:
- The Status column of the triage table (e.g., `stale (28d)`)
- The summary warning line

### Step 7 — Priority Suggestions

If `triage.auto_priority` is true, assign a suggested priority to each issue based on these heuristics:

**P1 (Critical)**:
- Issues with the `critical` or `urgent` label
- Bugs that block other issues
- Bugs created more than 2x the stale threshold ago

**P2 (Standard)**:
- Bugs that do not block other issues
- Features that block other issues
- Improvements that block multiple (2+) issues

**P3 (Low)**:
- Features and improvements that do not block other issues
- Stale issues with no dependencies (may be obsolete)

Within each priority level, sort by: number of issues blocked (descending), then age (oldest first).

If `triage.auto_priority` is false, set every priority to null, omit the Pri column from the table, and skip priority suggestions.

