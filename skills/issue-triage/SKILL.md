---
name: issue-triage
description: Triage open GitHub issues by analyzing dependencies, detecting circular references, computing execution order, identifying parallelizable work, flagging stale issues, and suggesting priorities. Use this skill whenever someone says "triage issues", "prioritize issues", "what should I work on next", "issue dependencies", "which issues are blocked", "stale issues", "backlog review", "sprint planning", "dependency graph", "what's blocking", "/issue-triage", or wants to understand the relationship between open issues in a repository. Also trigger when someone asks for a sprint plan, wants to know which issues can be worked on in parallel, needs to identify blocked or stale work, asks "which issue should I pick up", "what order should we resolve these", or wants to plan their next sprint. This skill reads all open issues, builds a dependency graph from affected files, performs topological sorting, and outputs a structured triage table with priority suggestions, parallelization recommendations, stale warnings, and a suggested resolution order — all via gh CLI with structured JSON output.
---

# /issue-triage

Analyze open GitHub issues to surface dependencies, suggest priorities, identify parallelizable work, and flag stale issues. Outputs a structured triage table with a recommended execution order.

## Invocation

| Invocation | What happens |
|------------|--------------|
| `/issue-triage` | Triage all open issues (default limit 100) |
| `/issue-triage --limit N` | Triage up to N open issues |

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

## Step 2 — Analyze Dependencies

For each issue, extract affected files from the normalized body. Look for the `**Affected files:**` section (or variations: `## Context` with file paths, inline code blocks containing file paths, `**Files:**` field). Issues sharing affected files or modules (same parent directory) are considered dependent.

Build a dependency graph:
- Each issue is a node.
- An edge from issue A to issue B means they share one or more affected files, and A should be resolved before B (determined by: earlier creation date, more blocking relationships, or bug type takes precedence).
- If two issues share the same file and neither clearly precedes the other, mark them as co-dependent at the same level.

Progress output:

```
● Analyzing dependencies...
```

## Step 3 — Detect Circular Dependencies

Walk the dependency graph and check for cycles using a depth-first traversal.

If a cycle is found, warn using the format from `references/error-messages.md`:

```
⚠ Circular dependency detected: #12 → #15 → #12

  These issues reference each other's affected files.
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
- **stale (Nd)** — flagged in Step 6 (added later, but the status column reflects it)

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
  ○  Suggested order: #12 → #15 → #8 → #3
```

- **Parallelizable**: List groups of issues that can be worked on simultaneously. If multiple groups exist, show each on its own line. If no parallelizable issues, omit this line.
- **Stale**: Count of stale issues with the threshold. If none are stale, omit this line.
- **Suggested order**: The full execution order from Step 4, shown as issue numbers connected by `→`. If more than 10 issues, show the first 10 and append `... (+N more)`.

---

## Example: Triage with dependencies and stale issues

**Repository has 4 open issues:**
- #12 "Fix auth redirect" (bug, updated 2 days ago, affects `auth.py`, `middleware.py`)
- #8 "Add pagination" (feature, updated 5 days ago, affects `api/views.py`)
- #15 "Refactor DB layer" (improvement, updated 3 days ago, affects `auth.py`, `db.py`)
- #3 "Old UI alignment bug" (bug, updated 28 days ago, affects `styles.css`)

**Execution:**

1. Fetch → 4 open issues
2. Dependencies → #12 and #15 share `auth.py`, so #12 blocks #15
3. Cycles → none
4. Topological sort → #12 first (bug, blocks #15), then #8 and #3 (independent), then #15
5. Parallelizable → #12 + #8 + #3 are all at the first level, but #12 blocks #15 so #8 and #3 can run in parallel with #12
6. Stale → #3 is 28 days old (>14 day threshold)
7. Priorities → #12 = P1 (bug, blocks #15), #8 = P3 (feature, blocks nothing), #15 = P2 (improvement, blocked), #3 = P3 (stale bug, blocks nothing)

**Output:**

```
  ● Fetching 4 open issues...
  ● Analyzing dependencies...

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
```

---

## Example: Empty repository

```
  ● Fetching open issues...

  ○ No open issues found. Nothing to triage!
    Create issues with /issue-creator to get started.
```

---

## Example: Circular dependency

**Repository has 2 open issues that reference each other's files:**
- #5 "Fix login flow" (bug, affects `auth.py`, `session.py`)
- #9 "Refactor session management" (improvement, affects `session.py`, `auth.py`)

**Output:**

```
  ● Fetching 2 open issues...
  ● Analyzing dependencies...

  ⚠ Circular dependency detected: #5 → #9 → #5

    These issues reference each other's affected files.
    Suggestion: resolve #5 first (fewer dependencies).

  ◆ Issue Triage
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  #  │ Issue                       │ Pri │ Blocks │ Status
  ───┼─────────────────────────────┼─────┼────────┼───────────
  1  │ #5  Fix login flow          │ P1  │ #9     │ ready
  2  │ #9  Refactor session mgmt   │ P2  │ —      │ ready

  ○  Suggested order: #5 → #9
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
