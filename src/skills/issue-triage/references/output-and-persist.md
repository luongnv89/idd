# /issue-triage — Output & Persist Format

Full Step 8 rendering spec and Step 9 JSON schema. SKILL.md shows a summary; read this for exact format details.

## Step 8 — Output


Display the full triage results following `docs/terminal-style.md` conventions.

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

Table rules (per `docs/terminal-style.md`):
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

`shared/scripts/gi-triage-graph.py --out .gitissue/triage.json` does steps 1-4
below in one call — it emits exactly this schema, so the payload and the
document cannot drift. Do them by hand only when that script degraded (see
SKILL.md, *Steps 3-7*):

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
| `summary.circular_deps` | integer[][] | Detected circular dependency chains (each closes on its own first node) |
| `summary.co_dependent` | integer[][] | Pairs that shared files but where neither issue precedes the other — no edge was created |
| `history[]` | array | One entry per triage run |
| `history[].time` | ISO 8601 string | When this entry was created |
| `history[].source` | string | Skill that wrote this entry |
| `history[].changes` | string | Human-readable description |

### Overwrite behavior

A full re-triage **overwrites the entire file** — it does not append to previous data. The `history` array contains exactly one entry per triage run (the current run).

**Cross-skill incremental updates.** One other skill writes this file: `/auto-pilot`, in its *Step 1.6 — Update the triage cache after a merge*, which triages once per run and then keeps the payload current in place rather than re-triaging every iteration. That writer is bound by two invariants, and they are what let a second skill touch a file this one owns:

1. **Removal only, never a recomputation.** It deletes the merged issue's number from `issues[]`, from `summary.suggested_order`, from `summary.parallel_groups`, and from every remaining issue's `blocked_by` / `blocks` — plus the one derived consequence, flipping an issue whose `blocked_by` just emptied from `blocked` to `ready`. It never re-derives an order, because the persisted records carry `updated_at` and not `created_at`, and `created_at` is an input to the ordering. Removing one node from a valid topological order leaves a valid one; anything more goes through a full re-triage here.
2. **Exactly one appended `history[]` entry per update**, with `source: "/auto-pilot"`. So `history` still reads as one entry per write, and a reader can tell a full re-triage from an incremental update by that `source` and by the entry's `changes` text.

The schema is unchanged by this — no field is added, none is removed, and a payload an incremental update wrote is the same shape as one a full re-triage wrote.

### Error handling

If writing fails (e.g., permission denied):
```
⚠ Could not save triage report to .gitissue/triage.json

  To fix:  check file permissions in the .gitissue/ directory
```
This is a warning, not a fatal error — the terminal output from Step 8 was already displayed.

---

## Step Completion Reports

Every step ends with a completion report — the checkable bar that separates *the
step ran* from *the step succeeded*. Emit it right after the step's `[N/9]`
tracker line:

```
  [3-7/9] Ordering    ✓ 12 issues ordered, 4 stale
    √ Order computed   √ Threshold applied
    Result: PASS
```

Rules that make the report worth reading:

- `√` — the check passed. `×` — it did not. One entry per check the step actually
  validates. Checks are **gates that could have failed**, never restatements of a
  metric the tracker line already carries (files read, counts, option number) —
  restating those is the duplication issue #165 removed.
- `Result: PASS` — every check is `√`; continue.
- `Result: PARTIAL` — only non-blocking checks are `×`; continue, and carry the
  gap into the closing summary so it is never silently dropped.
- `Result: FAIL` — a blocking check is `×`; stop, or enter that step's defined
  failure path. In auto mode follow the step's documented auto behavior instead
  of prompting.
- A step may not be reported complete without a `Result:` line. If a check could
  not be evaluated (a tool was unavailable, a gate was skipped by config), mark
  it `×` and use `PARTIAL` — never assume `√`.

`√` and `×` are the completion-report check glyphs defined in
`docs/terminal-style.md`; the run's own status symbols stay `✓ ✗ ⚠ ○`.

### Per-step checks

| Step | Checks |
|------|--------|
| 1 — Fetch Issues | `Issues fetched` · `Config applied` |
| 1b & 2 — Already-Fixed & Dependencies | `Scanner returned` · `Dependencies mapped` |
| 3-7 — Order, Parallel Sets, Staleness, Priority | `Order computed` · `No cycle left unreported` · `Disjoint sets identified` · `Threshold applied` · `Every open issue scored` · `Every issue ranked` |
| 8-9 — Output & Persist | `Report rendered` · `.gitissue/triage.json written` |

When the scripted block degraded to the prose procedure, the step still reports —
mark the checks it could not evaluate `×` and use `PARTIAL`, never `√`.

A read-only default-mode run still emits the reports; `PARTIAL` is the right
result when a step ran with degraded input (for example the dependency scanner
was unavailable and detection fell back to inline heuristics).
