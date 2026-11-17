# /issue-triage — Examples

One full run per mode.

## Example: First run (no cache exists)

**User says:** `/issue-triage` (no cache)

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

  ✓ Triage saved to .idd/triage.json

◆ Issue Triage — 4 issues analyzed
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            DONE — start with #12 (P1)

  Fetch issues:      ✓ pass (4 open issues)
  Dependencies:      ✓ pass (1 dependency found)
  Circular deps:     ✓ pass (none detected)
  Execution order:   ✓ pass (topological sort)
  Parallelizable:    ✓ pass (1 parallel group)
  Stale detection:   ✓ pass (1 stale issue)
  Priority:          ✓ pass (1 P1, 1 P2, 2 P3)
  Persist:           ✓ pass (saved to .idd/triage.json)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Evidence:          4 fetched; 1 scan batch; script exit 0
  Uncertainty:       #12 → #15 edge inferred; priorities are rule buckets
  Decision:          No approval needed.
  Suggested start:   #12 — Fix auth redirect
  Next action:       /issue-resolver 12

  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Run stats   elapsed 1m 08s · agents 1
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

    ... (table and summary lines as in the first run) ...

  ○ 7 commit(s) since last triage (3d 2h ago).
  ○ Report is 3d 2h old (>24 hours).
    Run /issue-triage update for fresh analysis.

◆ Issue Triage — cached
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            CACHED — start with #12 (P1)
  Cache load:        ✓ pass (age: 3d 2h)
  Issues:            4 analyzed
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Evidence:          .idd/triage.json, updated 2026-03-17 14:30 UTC
  Uncertainty:       backlog and code not re-checked since 2026-03-17 14:30 UTC
  Decision:          No approval needed.
  Suggested start:   #12 — Fix auth redirect
  Next action:       /issue-triage update

  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Run stats   elapsed n/a · agents 0
```

---

## Example: Default view (cached, up to date)

**User says:** `/issue-triage` (cache exists, no commits since last triage)

```
  ... (cache header, age 2h, table and summary lines) ...

  ○ Cached report is up to date. No changes detected since last triage.

  ... (cached Final Report, next /issue-resolver 12, footer) ...
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
  ... (header, rows 1-2 as in the first run) ...
  3  │ #15 Refactor DB layer  │ P2  │ —      │ blocked #12
  4  │ #3  Old UI alignment   │ P3  │ —      │ maybe-fixed

  ⚡ Parallelizable: #12 + #8 (independent)
  ⚠  Stale: 1 issue (>14 days inactive)
  ◆  Maybe fixed: 1 issue may already be resolved
  ○  Suggested order: #12 → #8 → #15 → #3

  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  ◆ Potentially Already Fixed
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  #3 Old UI alignment
    ● Likely fixed by PR #14 (fix/12-fix-auth-redirect)
      Commit: abc1234 "fix(ui): align header, refs #3 (#12)"
      Confidence: medium — commit references #3
      Target issue: #12
    → Verify and close: gh issue close 3 -c "Fixed by #14"

  ✓ Triage saved to .idd/triage.json

  ... (Final Report, Already-fixed: ✓ pass (1 potentially fixed), footer) ...
```

---

## Example: Empty repository

```
  ○ No cached triage found — running first analysis...

  ● Fetching open issues...

  ○ No open issues found. Nothing to triage!
    Create issues with /issue-creator to get started.

  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Run stats   elapsed 4s · agents 0
```

---

## Example: Circular dependency (during update)

**User says:** `/issue-triage update`

**2 open issues whose keyword scans overlap:**
- #5 "Fix login flow" (bug; login auth session)
- #9 "Refactor session management" (improvement; session auth refactor)

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
  2  │ #9  Refactor session mgmt   │ P3  │ —      │ blocked #5

  ○  Suggested order: #5 → #9

  ✓ Triage saved to .idd/triage.json

  ... (Final Report for these 2 issues, start #5, footer) ...
```

---

