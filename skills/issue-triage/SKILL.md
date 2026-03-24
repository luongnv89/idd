---
name: issue-triage
description: Triage open GitHub issues by analyzing dependencies, detecting circular references, computing execution order, identifying parallelizable work, flagging stale issues, detecting issues already fixed by other PRs, and suggesting priorities. By default, instantly shows cached triage from .gitissue/triage.json (auto-generates on first run if no cache exists). Suggests an update when local git history shows changes since the last triage, but never auto-updates. Full re-analysis only runs when the user explicitly says "/issue-triage update". Use this skill whenever someone says "triage issues", "prioritize issues", "what should I work on next", "issue dependencies", "which issues are blocked", "stale issues", "already fixed", "backlog review", "sprint planning", "dependency graph", "what's blocking", "/issue-triage", "/issue-triage update", or wants to understand the relationship between open issues in a repository. Also trigger when someone asks for a sprint plan, wants to know which issues can be worked on in parallel, needs to identify blocked or stale work, asks "which issue should I pick up", "what order should we resolve these", "show me the last triage", "triage report", "are any issues already fixed", or wants to plan their next sprint. This skill reads all open issues, builds a dependency graph from affected files, performs topological sorting, and outputs a structured triage table with priority suggestions, parallelization recommendations, stale warnings, already-fixed detection, and a suggested resolution order — all via gh CLI with structured JSON output, persisted to .gitissue/triage.json.
effort: medium
license: MIT
metadata:
  version: 0.3.0
  creator: Luong NGUYEN <luongnv89@gmail.com>
compatibility: Requires git and GitHub CLI (gh) with authentication. Default mode (cached view) needs only local file access — no gh required.
---

# /issue-triage

Analyze open GitHub issues to surface dependencies, suggest priorities, identify parallelizable work, flag stale issues, and detect issues that may have already been fixed by commits or PRs targeting other issues. Defaults to **view mode** — instantly renders cached results from `.gitissue/triage.json`. On first run (no cache), automatically performs a full analysis. After showing cached data, checks local git history and suggests an update if changes are detected. Full re-analysis only happens when the user explicitly requests `/issue-triage update`.

## Invocation

| Invocation | What happens |
|------------|--------------|
| `/issue-triage` | Show cached triage from `.gitissue/triage.json`. If no cache exists, automatically run a full analysis and persist. After rendering, suggest an update if repo changes are detected. |
| `/issue-triage update` | Force a full re-analysis: run Steps 1-9 and overwrite `.gitissue/triage.json` |
| `/issue-triage --limit N` | Force a full re-analysis with up to N issues |

The design principle: **viewing is cheap and instant, updating is deliberate.** Users see their triage report immediately without waiting for GitHub API calls. Updates only happen when the user explicitly requests one or approves a suggestion.

## Default Mode (View with Smart Suggestions)

When invoked as `/issue-triage` (without `update` or `--limit`):

### 1. Check for cached data

Look for `.gitissue/triage.json` at the repo root.

**If the file does not exist**, print a brief notice and automatically fall through to a full analysis (Steps 1-9):

```
○ No cached triage found — running first analysis...
```

Then execute the full pipeline (starting from Prerequisites) and stop after Step 9.

**If the file exists**, continue to step 2.

### 2. Parse the cached data

Read and parse the JSON file. If the JSON is malformed or unparseable, output the error from `references/error-messages.md` and stop:

```
✗ .gitissue/triage.json is corrupted

  To fix:  rm .gitissue/triage.json && /issue-triage update
  Check:   was the file edited manually?
```

### 3. Render the cached report

Compute report age from the `updated` timestamp relative to now. Render the triage table to terminal using the same DESIGN.md format as Step 8, with a cache header:

```
◆ Issue Triage (cached)
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Last updated:  {updated timestamp, formatted as YYYY-MM-DD HH:MM UTC}
  Report age:    {Nd Nh} (e.g., "3d 2h")
  Updated by:    {source field from JSON}
  Issues:        {analyzed_count} analyzed

  #  │ Issue              │ Pri │ Blocks │ Status
  ───┼────────────────────┼─────┼────────┼───────────
  1  │ #12 Fix auth       │ P1  │ #15    │ ready
  2  │ #8  Add pagination │ P3  │ —      │ ready

  ⚡ Parallelizable: #12 + #8 (independent)
  ⚠  Stale: 1 issue (>14 days inactive)
  ○  Suggested order: #12 → #8 → #3 → #15
```

### 4. Detect changes and suggest update

After rendering the cached report, check whether the triage data might be outdated. Run these lightweight checks (no GitHub API calls):

**a) Git history check** — count commits since the last triage:

```bash
git log --oneline --since="{updated timestamp from cache}" | wc -l
```

**b) Report age check** — compute how old the cached report is.

**c) Issue activity check** — compare the cached issue `updated_at` timestamps against the cache's `updated` timestamp to see if any issues were already showing signs of change at triage time.

Based on these signals, print one of these endings:

**No changes detected:**
```
○ Cached report is up to date. No changes detected since last triage.
```

**Changes detected (commits since last triage):**
```
○ {N} commit(s) since last triage ({report age} ago).
  Issues may have changed. Run /issue-triage update for fresh analysis.
```

**Report is old (>24 hours):**
```
○ Report is {Nd Nh} old.
  Run /issue-triage update for fresh analysis.
```

These suggestions are informational only — the skill never auto-updates. The user decides whether to act on them.

After the suggestion (or the "up to date" message), **stop**. View mode never writes to the file or makes API calls beyond the local git log check.

---

## Prerequisites

Before any operation, verify the environment. On failure, output the exact error from `references/error-messages.md` and stop.

1. Confirm git repository: `git rev-parse --git-dir`
2. Confirm `gh` is installed: `which gh`
3. Confirm authentication: `gh auth status`
4. Confirm GitHub remote exists: `git remote -v`

## Repo Sync (recommended)

Before analyzing issues, recommend syncing with the remote so dependency analysis based on local files is accurate:

```
⚡ Your branch may be behind the remote. Sync before triaging?

  This ensures file-based dependency detection uses the latest code.
  Sync now? [Y/n]
```

If the user agrees, run:

```bash
branch="$(git rev-parse --abbrev-ref HEAD)"
git fetch origin
git pull --rebase origin "$branch"
```

If the working tree is dirty, stash first, sync, then pop. If `origin` is missing or conflicts occur, inform the user and continue without syncing. If the user declines, proceed without syncing.

## Configuration

Load `.gitissue.yml` from the repo root once at skill start. If the file does not exist, use defaults and print:

```
○ First run — using default config. Run /init-gitissue to customize.
```

Triage settings and defaults:

| Setting | Default | Description |
|---------|---------|-------------|
| `triage.stale_threshold_days` | `14` | Flag issues with no activity beyond this many days |
| `triage.auto_priority` | `true` | Suggest P1/P2/P3 based on type, age, and dependency position |
| `triage.include_closed` | `false` | Include recently closed issues in triage analysis |
| `triage.scan_timeout_per_issue` | `30` | Max seconds to scan per issue for file dependencies |

If the config file exists but contains invalid values, output the validation error from `references/error-messages.md` and stop.

Do not re-read the config at each step.

---

## Step 1 — Fetch Issues

```bash
gh issue list --state open --json number,title,body,labels,assignees,state,updatedAt --limit 100
```

If `triage.include_closed` is true, also fetch closed issues and merge the results:

```bash
gh issue list --state closed --json number,title,body,labels,assignees,state,updatedAt --limit 100
```

If the repository has more than 100 open issues and no `--limit` was specified, warn using the message from `references/error-messages.md`:

```
⚠ {count} open issues found. Analyzing first 100.

  To analyze all: /issue-triage --limit {count}
```

If `--limit N` was provided, use that value instead of the default 100.

**Empty state**: If no open issues are found, output the message from `references/error-messages.md` and stop:

```
○ No open issues found. Nothing to triage!
  Create issues with /issue-creator to get started.
```

Progress output:

```
● Fetching {N} open issues...
```

## Step 1b — Detect Already-Fixed Issues

Some open issues may have been incidentally fixed by commits or PRs that targeted a different issue. For example, a PR titled `fix(auth): resolve redirect loop (#42)` might also fix the bug described in issue #17 if they share the same root cause. This step scans recent git history and merged PRs to catch these cases, so the team doesn't waste time on issues that are already resolved.

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

## Step 4 — Compute Execution Order

Perform a topological sort on the dependency graph (after breaking any cycles from Step 3).

- Issues with no incoming dependencies come first — they are "ready" to work on.
- Issues blocked by other issues are ordered after their blockers.
- Within the same topological level, sort by: bugs before features before improvements, then by age (oldest first).

Assign a status to each issue:
- **ready** — no unresolved dependencies
- **blocked #N** — depends on issue #N being resolved first
- **maybe-fixed** — flagged in Step 1b as potentially already resolved (high or medium confidence)
- **stale (Nd)** — flagged in Step 6 (added later, but the status column reflects it)

Issues flagged as `maybe-fixed` are sorted to the bottom of the execution order — there's no point working on them until someone verifies whether the fix actually landed. They still appear in the triage table so the team can review and close them.

## Step 5 — Identify Parallelizable Issues

Find sets of issues at the same topological level that are independent of each other (no shared affected files, no dependency edges between them).

These issues can be worked on simultaneously by different developers.

Group them for the recommendation output in Step 8.

## Step 6 — Stale Detection

For each issue, compare `updatedAt` to today's date. If the difference exceeds `triage.stale_threshold_days` (default: 14 days), flag the issue as stale.

The stale flag is reflected in both:
- The Status column of the triage table (e.g., `stale (28d)`)
- The summary warning line

## Step 7 — Priority Suggestions

If `triage.auto_priority` is true, assign a suggested priority to each issue based on these heuristics:

**P1 (Critical)**:
- Bugs that block other issues
- Issues with the `critical` or `urgent` label
- Bugs older than 2x the stale threshold

**P2 (Standard)**:
- Bugs that do not block other issues
- Features that block other issues
- Improvements that block multiple (2+) issues

**P3 (Low)**:
- Features and improvements that do not block other issues
- Stale issues with no dependencies (may be obsolete)

Within each priority level, sort by: number of issues blocked (descending), then age (oldest first).

If `triage.auto_priority` is false, omit the Pri column from the table and skip priority suggestions.

## Step 8 — Output

Display the full triage results following DESIGN.md conventions.

### Triage Table

```
  ◆ Issue Triage
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  #  │ Issue              │ Pri │ Blocks │ Status
  ───┼────────────────────┼─────┼────────┼───────────
  1  │ #12 Fix auth       │ P1  │ #15    │ ready
  2  │ #8  Add pagination │ P2  │ —      │ ready
  3  │ #15 Refactor DB    │ P2  │ —      │ blocked #12
  4  │ #3  Old UI bug     │ P3  │ —      │ stale (28d)
```

Table rules (per DESIGN.md):
- Box-drawing characters: `│ ─ ┼`
- Right-align numbers, left-align text
- Max width: 80 characters (truncate issue titles with `...` if needed)
- Use `—` for empty cells (not blank)
- Issues ordered by suggested execution order (from Step 4)

### Summary Lines

After the table, output summary recommendations:

```
  ⚡ Parallelizable: #12 + #8 (independent)
  ⚠  Stale: 1 issue (>14 days inactive)
  ◆  Maybe fixed: 1 issue may already be resolved
  ○  Suggested order: #12 → #15 → #8 → #3
```

- **Parallelizable**: List groups of issues that can be worked on simultaneously. If multiple groups exist, show each on its own line. If no parallelizable issues, omit this line.
- **Stale**: Count of stale issues with the threshold. If none are stale, omit this line.
- **Maybe fixed**: Count of issues flagged as potentially already fixed. If none, omit this line.
- **Suggested order**: The full execution order from Step 4, shown as issue numbers connected by `→`. If more than 10 issues, show the first 10 and append `... (+N more)`.

### Already-Fixed Detail Block

If any issues were flagged as potentially fixed in Step 1b, output a detail block after the summary lines:

```
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  ◆ Potentially Already Fixed
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  #17 Fix session timeout on mobile
    ● Likely fixed by PR #43 (fix/42-mobile-auth-redirect)
      Commit: abc1234 "fix(auth): resolve redirect loop (#42)"
      Confidence: high — commit uses "Fixes #17"
      Target issue: #42
    → Verify and close: gh issue close 17 -c "Fixed by #43"

  #9 Duplicate error in logs
    ● Likely fixed by PR #31 (refactor/8-cleanup-auth-module)
      Commit: def5678 "refactor(auth): deduplicate error handlers (#8)"
      Confidence: medium — commit references #9
      Target issue: #8
    → Verify and close: gh issue close 9 -c "Fixed by #31"
```

For each flagged issue, show:
- The issue number and title
- Which PR likely fixed it and its branch name
- The specific commit with its message
- Confidence level with the reason
- Which issue that PR was originally targeting
- A suggested `gh issue close` command to make it easy to act on

---

## Step 9 — Persist

After Step 8 (terminal output is always shown regardless of persistence success), save the triage results to `.gitissue/triage.json`.

### Write process

1. Create the directory if it doesn't exist: `mkdir -p .gitissue/`
2. Build the JSON object from Steps 1-8 analysis results using the schema below
3. Append one entry to the `history` array
4. Write `.gitissue/triage.json` with formatted JSON (readable diffs in git)
5. Print: `✓ Triage saved to .gitissue/triage.json`

### JSON Schema (`.gitissue/triage.json`)

```json
{
  "version": 1,
  "updated": "2026-03-20T14:30:00Z",
  "source": "/issue-triage",
  "analyzed_count": 4,
  "issues": [
    {
      "number": 12,
      "title": "Fix auth redirect",
      "type": "bug",
      "priority": "P1",
      "blocks": [15],
      "blocked_by": [],
      "status": "ready",
      "stale_days": null,
      "labels": ["bug", "auth"],
      "affected_files": ["auth.py", "middleware.py"],
      "updated_at": "2026-03-18T10:00:00Z",
      "potentially_fixed_by": null
    }
  ],
  "summary": {
    "parallel_groups": [[12, 8]],
    "stale_count": 1,
    "stale_threshold_days": 14,
    "potentially_fixed_count": 0,
    "suggested_order": [12, 8, 3, 15],
    "circular_deps": []
  },
  "history": [
    {
      "time": "2026-03-20T14:30:00Z",
      "source": "/issue-triage",
      "changes": "Full re-triage (4 issues)"
    }
  ]
}
```

### Schema field reference

| Field | Type | Description |
|-------|------|-------------|
| `version` | integer | Schema version, always `1` |
| `updated` | ISO 8601 string | Timestamp of this triage run |
| `source` | string | Always `"/issue-triage"` for this skill |
| `analyzed_count` | integer | Number of issues analyzed |
| `issues[]` | array | One entry per analyzed issue |
| `issues[].number` | integer | GitHub issue number |
| `issues[].title` | string | Issue title |
| `issues[].type` | string | `"bug"`, `"feature"`, or `"improvement"` |
| `issues[].priority` | string | `"P1"`, `"P2"`, or `"P3"` (null if auto_priority is off) |
| `issues[].blocks` | integer[] | Issue numbers this issue blocks |
| `issues[].blocked_by` | integer[] | Issue numbers blocking this issue |
| `issues[].status` | string | `"ready"`, `"blocked"`, or `"stale"` |
| `issues[].stale_days` | integer or null | Days since last update, null if not stale |
| `issues[].labels` | string[] | GitHub labels |
| `issues[].affected_files` | string[] | Files identified by keyword-based codebase scan at triage time |
| `issues[].updated_at` | ISO 8601 string | GitHub `updatedAt` value |
| `issues[].potentially_fixed_by` | object or null | If flagged as maybe-fixed: `{ "pr": 43, "branch": "fix/42-auth", "commit": "abc1234", "commit_message": "fix(auth): ...", "confidence": "high", "target_issue": 42 }`. Null if not flagged. |
| `summary.parallel_groups` | integer[][] | Groups of parallelizable issue numbers |
| `summary.stale_count` | integer | Number of stale issues |
| `summary.stale_threshold_days` | integer | Threshold used for stale detection |
| `summary.potentially_fixed_count` | integer | Number of issues flagged as potentially already fixed |
| `summary.suggested_order` | integer[] | Execution order by issue number |
| `summary.circular_deps` | integer[][] | Detected circular dependency chains |
| `history[]` | array | One entry per triage run |
| `history[].time` | ISO 8601 string | When this entry was created |
| `history[].source` | string | Skill that wrote this entry |
| `history[].changes` | string | Human-readable description |

### Overwrite behavior

A full re-triage **overwrites the entire file** — it does not append to previous data. The `history` array contains exactly one entry per triage run (the current run). Future cross-skill updates (deferred) may append additional history entries.

### Error handling

If writing fails (e.g., permission denied):
```
⚠ Could not save triage report to .gitissue/triage.json

  To fix:  check file permissions in the .gitissue/ directory
```
This is a warning, not a fatal error — the terminal output from Step 8 was already displayed.

---

## Example: First run (no cache exists)

**User says:** `/issue-triage` (no previous triage run)

```
  ○ No cached triage found — running first analysis...

  ● Fetching 4 open issues...
  ● Scanning commit history for already-fixed issues...
  ● Scanning codebase for issue dependencies...

  ◆ Issue Triage
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  #  │ Issue                  │ Pri │ Blocks │ Status
  ───┼────────────────────────┼─────┼────────┼───────────
  1  │ #12 Fix auth redirect  │ P1  │ #15    │ ready
  2  │ #8  Add pagination     │ P3  │ —      │ ready
  3  │ #3  Old UI alignment   │ P3  │ —      │ stale (28d)
  4  │ #15 Refactor DB layer  │ P2  │ —      │ blocked #12

  ⚡ Parallelizable: #12 + #8 + #3 (independent)
  ⚠  Stale: 1 issue (>14 days inactive)
  ○  Suggested order: #12 → #8 → #3 → #15

  ✓ Triage saved to .gitissue/triage.json
```

---

## Example: Default view (cached, changes detected)

**User says:** `/issue-triage` (cache exists, 7 commits since last triage)

```
  ◆ Issue Triage (cached)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    Last updated:  2026-03-17 14:30 UTC
    Report age:    3d 2h
    Updated by:    /issue-triage
    Issues:        4 analyzed

    #  │ Issue                  │ Pri │ Blocks │ Status
    ───┼────────────────────────┼─────┼────────┼───────────
    1  │ #12 Fix auth redirect  │ P1  │ #15    │ ready
    2  │ #8  Add pagination     │ P3  │ —      │ ready
    3  │ #3  Old UI alignment   │ P3  │ —      │ stale (28d)
    4  │ #15 Refactor DB layer  │ P2  │ —      │ blocked #12

    ⚡ Parallelizable: #12 + #8 + #3 (independent)
    ⚠  Stale: 1 issue (>14 days inactive)
    ○  Suggested order: #12 → #8 → #3 → #15

  ○ 7 commit(s) since last triage (3d 2h ago).
    Issues may have changed. Run /issue-triage update for fresh analysis.
```

---

## Example: Default view (cached, up to date)

**User says:** `/issue-triage` (cache exists, no commits since last triage)

```
  ◆ Issue Triage (cached)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    Last updated:  2026-03-21 09:15 UTC
    Report age:    2h
    Updated by:    /issue-triage
    Issues:        4 analyzed

    #  │ Issue                  │ Pri │ Blocks │ Status
    ───┼────────────────────────┼─────┼────────┼───────────
    1  │ #12 Fix auth redirect  │ P1  │ #15    │ ready
    2  │ #8  Add pagination     │ P3  │ —      │ ready
    3  │ #3  Old UI alignment   │ P3  │ —      │ stale (28d)
    4  │ #15 Refactor DB layer  │ P2  │ —      │ blocked #12

    ⚡ Parallelizable: #12 + #8 + #3 (independent)
    ⚠  Stale: 1 issue (>14 days inactive)
    ○  Suggested order: #12 → #8 → #3 → #15

  ○ Cached report is up to date. No changes detected since last triage.
```

---

## Example: Explicit update

**User says:** `/issue-triage update`

```
  ● Fetching 4 open issues...
  ● Scanning commit history for already-fixed issues...
    ◆ 1 issue(s) may already be fixed
  ● Scanning codebase for issue dependencies...

  ◆ Issue Triage
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  #  │ Issue                  │ Pri │ Blocks │ Status
  ───┼────────────────────────┼─────┼────────┼───────────
  1  │ #12 Fix auth redirect  │ P1  │ #15    │ ready
  2  │ #8  Add pagination     │ P3  │ —      │ ready
  3  │ #15 Refactor DB layer  │ P2  │ —      │ blocked #12
  4  │ #3  Old UI alignment   │ P3  │ —      │ maybe-fixed

  ⚡ Parallelizable: #12 + #8 (independent)
  ◆  Maybe fixed: 1 issue may already be resolved
  ○  Suggested order: #12 → #8 → #15 → #3

  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  ◆ Potentially Already Fixed
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  #3 Old UI alignment
    ● Likely fixed by PR #14 (fix/12-fix-auth-redirect)
      Commit: abc1234 "fix(ui): align header elements (#12)"
      Confidence: medium — commit references #3
      Target issue: #12
    → Verify and close: gh issue close 3 -c "Fixed by #14"

  ✓ Triage saved to .gitissue/triage.json
```

---

## Example: Empty repository

```
  ○ No cached triage found — running first analysis...

  ● Fetching open issues...

  ○ No open issues found. Nothing to triage!
    Create issues with /issue-creator to get started.
```

---

## Example: Circular dependency (during update)

**User says:** `/issue-triage update`

**Repository has 2 open issues whose keyword scans overlap:**
- #5 "Fix login flow" (bug, keywords: 'login auth session')
- #9 "Refactor session management" (improvement, keywords: 'session auth refactor')

**Output:**

```
  ● Fetching 2 open issues...
  ● Scanning commit history for already-fixed issues...
  ● Scanning codebase for issue dependencies...

  ⚠ Circular dependency detected: #5 → #9 → #5

    These issues share affected files detected by codebase scan.
    Suggestion: resolve #5 first (fewer dependencies).

  ◆ Issue Triage
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  #  │ Issue                       │ Pri │ Blocks │ Status
  ───┼─────────────────────────────┼─────┼────────┼───────────
  1  │ #5  Fix login flow          │ P1  │ #9     │ ready
  2  │ #9  Refactor session mgmt   │ P2  │ —      │ ready

  ○  Suggested order: #5 → #9

  ✓ Triage saved to .gitissue/triage.json
```

---

## GitHub CLI Convention

Every `gh` command for data retrieval uses `--json` with explicit field selection. Never parse text output.

- `gh issue list --state open --json number,title,body,labels,assignees,state,updatedAt --limit 100`
- `gh issue list --state closed --json number,title,body,labels,assignees,state,updatedAt --limit 100`

## Terminal Output

Follow DESIGN.md symbol vocabulary and output structure for all output. Key rules:

- Symbols: `●` progress, `✓` success, `✗` failure, `◆` section header, `⚡` recommendation, `⚠` warning, `○` info
- Two-space indent for content under section headers
- Section separators: `┄` (light dash)
- URLs on their own line
- Max 80 chars wide (truncate with `...`)
- One blank line between sections
- Static sequential output — each step prints a new line, no animation
- Table characters: `│ ─ ┼`
- Right-align numbers, left-align text in tables
- Use `—` for empty cells

## Error Handling

All errors use the rich format from `references/error-messages.md`:

```
✗ Short error description

  To fix:  <actionable command>
  Docs:    <url> (when applicable)
```

See `references/error-messages.md` for the complete error catalog including: authentication failures, CLI not found, no remote, no issues, too many issues, circular dependencies, and API rate limits.

## Additional Resources

- **`references/error-messages.md`** — Complete error catalog with triggers and exact output
- **`DESIGN.md`** — Terminal output style guide (repo root)
- **`docs/config-schema.md`** — Full configuration schema
