# /issue-analysis — Examples

Full example runs (happy path, view mode, closed issue), extracted from SKILL.md.

## Example: Full analysis flow

**User says:** `/issue-analysis 42`

```
  ● Fetching issue #42...

  ◆ Analysis Pipeline
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  [1/8] Fetch          ✓ issue #42 loaded (bug)
  [2/8] Extract        ✓ 8 keywords, 2 file refs
  [3/8] Research       ✓ read 18 files, traced 12 deps
  [4/8] History        ✓ 5 related commits, 1 prior fix attempt
  [5/8] Cross-refs     ✓ 2 related issues, 1 may resolve this
  [6/8] Analysis       ✓ root cause identified
  [7/8] Options        ✓ 3 approaches proposed
  [8/8] Report         ✓ analysis complete

  ◆ Issue Analysis: #42 Fix mobile auth redirect loop
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Type:        bug
  Reporter:    @janedoe
  Priority:    P1 (from triage)
  Labels:      bug, auth, mobile
  Created:     2026-03-15

  ◆ Keywords & Targets
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    Error messages:  "ERR_TOO_MANY_REDIRECTS"
    Functions:       handleRedirect, validateSession
    Components:      AuthMiddleware
    File refs:       src/auth/middleware.py

  ◆ Affected Files
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    File                        │ Relevance │ Role
    ────────────────────────────┼───────────┼──────────────
    src/auth/middleware.py       │ critical  │ redirect logic
    src/auth/session.py          │ high      │ session check
    src/config/routes.py         │ medium    │ route config

  ◆ Git History
  ┄┄┄┄┄┄┄┄┄┄┄┄
    Related commits:    5 touching affected files
    Domain experts:     @jdoe (12 commits), @asmith (5)
    ⚡ Prior fix attempt: a1b2c3d fix: resolve auth re...
       Committed 2026-03-18 by @jdoe — issue still open
    ⚡ Possible regression: e4f5g6h refactor: simplify...
       Committed 2026-03-10, issue created 2026-03-15

  ◆ Cross-references
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    Blocks:         #55, #60
    Blocked by:     —
    Related issues: #38 (shared auth middleware)
    ⚡ May be resolved by PR #88: Fix session handling
       Merged 2026-03-19, modified: src/auth/session.py
    ⚠ Possible duplicate: #51 — Auth redirect on mobile
       Shared keywords: redirect, auth, mobile

  ◆ Root Cause Analysis
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    The redirect loop occurs because handleRedirect() in
    middleware.py checks session validity but does not
    exclude the login route itself from the check. On
    mobile browsers, the session cookie is not sent on
    the initial redirect, causing an infinite loop.

    This is likely a regression introduced by commit
    e4f5g6h (2026-03-10) which simplified the session
    check and removed the login route exclusion.

  ◆ Implementation Options
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

    Option 1: Minimal fix (S)
    ┄┄┄┄┄┄┄┄┄┄┄┄
      Add login route to redirect exclusion list
      Modify:  src/auth/middleware.py
      + Smallest change, lowest risk
      + Easy to test
      - Hardcoded exclusion list grows over time
      Risk:    Low — single file, clear behavior change

    Option 2: Route-based auth config (M)
    ┄┄┄┄┄┄┄┄┄┄┄┄
      Move auth requirements to route configuration
      Modify:  src/auth/middleware.py, src/config/routes.py
      + Declarative auth per route
      + Solves the class of problems, not just this one
      - Moderate refactor, touches config
      Risk:    Medium — two files, config migration needed

    Option 3: Session-aware redirect (M)
    ┄┄┄┄┄┄┄┄┄┄┄┄
      Add redirect-count tracking to session
      Modify:  src/auth/middleware.py, src/auth/session.py
      Create:  tests/test_redirect_loop.py
      + Catches all redirect loops, not just auth
      - More complex, adds state to session
      Risk:    Medium — behavior change in session handling

  ◆ Summary
  ┄┄┄┄┄┄┄┄┄
    Complexity:   S (based on Option 1)
    Risk:         Low
    Recommended:  Option 1 — Minimal fix

  ✓ Analysis saved to .gitissue/analysis-42.json

◆ Issue Analysis: #42 — Fix mobile auth redirect loop
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Fetch:             ✓ pass (issue loaded)
  Extract targets:   ✓ pass (6 keywords, 2 file refs)
  Research:          ✓ pass (14 files scanned)
  Git history:       ✓ pass (3 related commits)
  Cross-references:  ✓ pass (1 related issue)
  Root cause:        ✓ pass
  Options:           ✓ pass (3 approaches proposed)
  Report:            ✓ pass
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            DONE

  Complexity: S │ Risk: Low
  Recommended: Option 1 — Minimal fix
  Saved: .gitissue/analysis-42.json
```

---

## Example: View mode

**User says:** `/issue-analysis 42 view`

```
  ◆ Issue Analysis (cached)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    Issue:       #42 Fix mobile auth redirect loop
    Last run:    2026-03-21 14:30 UTC
    Report age:  1d 3h

    ... (same analysis sections as above) ...

  ○ Cached report. Run /issue-analysis 42 for fresh analysis.
```

---

## Example: Closed issue

**User says:** `/issue-analysis 15`

```
  ● Fetching issue #15...

  ⚠ Issue #15 is closed. Analyzing anyway for reference.

  ◆ Analysis Pipeline
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  [1/8] Fetch          ✓ issue #15 loaded (feature)
  ...
```
