---
name: issue-triage
description: Analyze and triage open GitHub issues for dependencies, priorities, parallelizable work, staleness, and already-fixed detection, caching results to .gitissue/triage.json. Use when asked to "triage issues", "prioritize issues", "what should I work on next", or "/issue-triage".
license: MIT
compatibility: Requires git and GitHub CLI (gh) with authentication. Default mode (cached view) needs only local file access — no gh required.
effort: medium
metadata:
  version: 0.5.1
  creator: Luong NGUYEN <luongnv89@gmail.com>
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

## Subagent Architecture (Update Mode)

During a full triage update, the skill delegates the two heaviest phases to subagents. This keeps the main agent's **context window** clean and the **token budget** predictable — the main agent never reads source files or parses git history directly.

```
Main Agent (orchestrator)
├── Step 1: Fetch Issues (lightweight — stays in main agent)
│
├── Spawn: Issue Relationship Scanner subagent(s) (Steps 1b + 2)
│   Combined agent: scans git log + merged PRs for already-fixed issues,
│   AND scans codebase for keywords, builds dependency map
│   For 10+ issues, split into parallel batches
│   Returns: potentially-fixed issues, affected files per issue, dependency edges
│
├── Steps 3-7: Main agent (lightweight computation)
│   Circular dep detection, topological sort, parallelization,
│   stale detection, priority assignment — all operate on the
│   structured data returned by subagents
│
├── Step 8: Output (main agent — render terminal report)
└── Step 9: Persist (main agent — write triage.json)
```

Read `shared/agents/issue-relationship-scanner.md` for the combined scanner prompt (handles both dependency scanning and history scanning in a single agent).

### Parallel execution

After fetching issues in Step 1, spawn issue-relationship-scanner subagent(s). Each scanner instance performs both dependency scanning (file-level overlap) and history scanning (already-fixed detection) for its batch.

```
Step 1 completes
    └── Spawn issue-relationship-scanner    ─┐
                                             │
    Collect results ◄────────────────────────┘
Step 3 continues with merged data
```

### Batch splitting

When there are 10+ issues, split into batches of ~5 and spawn multiple scanner subagents in parallel:

```
Step 1 completes (18 issues)
    ├── Spawn scanner batch 1 (issues 1-5)
    ├── Spawn scanner batch 2 (issues 6-10)
    ├── Spawn scanner batch 3 (issues 11-15)
    └── Spawn scanner batch 4 (issues 16-18)

    Collect all results, merge dependency maps + history results
    Main agent adds cross-batch dependency edges
Step 3 continues
```

### Environment check

If the Agent tool is available, use subagents as described above.
If not (e.g., Claude.ai), execute history scanning and dependency analysis inline — the steps below include the full procedure for both modes.
When the Agent tool is available and there are 10+ issues, split dependency scanning into parallel batches of ~5 issues each for faster execution.

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

## Steps 1b & 2 — Already-Fixed & Dependency Detection

Two subagents run in parallel: the **history scanner** finds issues already fixed by commits/PRs, and the **dependency scanner** builds a file-overlap dependency map. Full subagent prompts, confidence-scoring rules, and merge logic live in `references/detection.md` — read that file when tuning either scanner.

Summary:
- **Step 1b** — flags open issues whose titles/bodies match recent commit messages or merged PR descriptions. Marks them `potentially_fixed` with evidence links.
- **Step 2** — for each issue, derives affected files from the body, then computes pairwise overlap to produce a `dependencies[]` graph.
- **Step 3** — detects circular dependency cycles in the graph and breaks them before the topological sort.

---
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

## Step 8-9 — Output & Persist

Step 8 renders the full triage table (rank, issue, priority, blockers, status, parallelizable flag, stale flag) and a suggested execution order. Step 9 persists the structured data to `.gitissue/triage.json` with keys: `updated`, `source`, `analyzed_count`, `issues[]`, `dependencies[]`, `parallelizable_groups[]`, `execution_order[]`, `stale[]`, `already_fixed[]`.

Full rendering spec (column widths, sort order, color rules) and JSON schema live in `references/output-and-persist.md`.

---
## Final Report

After the triage table (Step 8) and persist (Step 9) are both complete, print a structured step-by-step summary at the end:

```
◆ Issue Triage — {N} issues analyzed
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Fetch issues:      ✓ pass ({N} open issues)
  Already-fixed:     ✓ pass ({fixed_count} potentially fixed)
  Dependencies:      ✓ pass ({dep_count} dependencies found)
  Circular deps:     ✓ pass (none detected)
  Execution order:   ✓ pass (topological sort)
  Parallelizable:    ✓ pass ({group_count} parallel groups)
  Stale detection:   ✓ pass ({stale_count} stale issues)
  Priority:          ✓ pass ({p1} P1, {p2} P2, {p3} P3)
  Persist:           ✓ pass (saved to .gitissue/triage.json)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            DONE

  Suggested start:   #{first} — {title}
  Next action:       /issue-resolver {first}
```

For cached view mode (no update run):

```
◆ Issue Triage — cached
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Cache load:        ✓ pass (age: {Nd Nh})
  Issues:            {N} analyzed
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            CACHED

  Suggested start:   #{first} — {title}
  Next action:       /issue-resolver {first}
```

Omit lines where a step found nothing (e.g., omit `Already-fixed` if count is 0, omit `Circular deps` if none checked).

---

## Example Runs

Full example runs (first run, cached view with/without changes, explicit update, empty repo, circular dependency scenario) live in `references/examples.md` to keep SKILL.md focused on mechanics.

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

## GitHub Projects Sync

The triage skill is **read-only** with respect to the GitHub Project board. It does not change issue status. Future versions may reorder project board items based on triage priority.

See `docs/github-projects-sync.md` for the shared reference on how other skills (issue-creator, issue-resolver) update project board status.

## Expected Output

A cached view renders instantly from `.gitissue/triage.json`:

```
  ◆ Triage Snapshot — 12 open issues
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  │ Rank │ Issue │ Title                           │ Status       │
  ├──────┼───────┼─────────────────────────────────┼──────────────┤
  │  1   │ #42   │ Fix mobile auth redirect loop   │ ready        │
  │  2   │ #15   │ Add dark mode toggle            │ ready        │
  │  3   │ #31   │ Cover auth in unit tests        │ blocked-by #8│
  ...

  ● Suggestion: git history shows 3 new commits since last triage.
    Run /issue-triage update to refresh.
```

An update (`/issue-triage update`) runs Steps 1–9 and overwrites the cache, ending with the same snapshot view.

## Edge Cases

- **No cache and no issues** — prints a friendly `○ No open issues` and exits without creating a cache file.
- **Circular dependency detected** — flagged in the report with the offending cycle; execution order still computed via topological pruning.
- **Stale issues (>90 days)** — grouped at the bottom of the report with a `⚠ stale` marker.
- **Rate-limited by GitHub API** — partial results are kept, the report notes incompleteness, and the user is shown the exact retry command.
- **Already-fixed detection false positive** — the report lists supporting commits/PRs so the user can verify before closing.

## Additional Resources

- **`references/error-messages.md`** — Complete error catalog with triggers and exact output
- **`docs/github-projects-sync.md`** — Shared GitHub Projects status sync reference
- **`DESIGN.md`** — Terminal output style guide (repo root)
- **`docs/config-schema.md`** — Full configuration schema
