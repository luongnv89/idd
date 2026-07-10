# /issue-triage — Output & Persist Format

Full Step 8 rendering spec and Step 9 JSON schema. SKILL.md shows a summary; read this for exact format details.

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
  ○  Suggested order: #12 → #8 → #15 → #3
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
    "suggested_order": [12, 8, 15, 3],
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
| `issues[].status` | string | `"ready"`, `"blocked"`, `"stale"`, or `"maybe-fixed"` (potentially already fixed on a merged branch). Closed GitHub issues are not written into `issues[]` on a full re-triage. |
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

