# /issue-triage — Examples

Full example runs for each mode (first run, cached view, explicit update, empty repo, circular dependency).

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

