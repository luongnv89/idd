# /issue-analysis — Output & Persistence Format

Full Step 8 terminal rendering spec and Step 9 JSON persistence schema. SKILL.md shows a condensed summary; read this when debugging output or JSON format.

## Step 8 — Output (Terminal Report)


Display the full analysis following `docs/terminal-style.md` conventions.

### Issue header

```
  ◆ Issue Analysis: #{N} {title}
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Type:        {bug|feature|improvement}
  Reporter:    @{author.login}
  Priority:    {from triage data if available, else "—"}
  Labels:      {label1}, {label2}
  Created:     {createdAt, YYYY-MM-DD}
```

When any explorer status flag is true, render it directly below the header so an
already-resolved, in-progress, or possibly-fixed result cannot look like an
ordinary analysis:

```
  ⚡ Research status: already resolved — {resolution_details}
  ⚠ Research status: PR in progress — {resolution_details}
  ⚠ Research status: possibly already fixed — verify before acting
```

Render each applicable line. If `scan_stats.scan_timed_out` is true, also render
the timeout warning from `subagent-steps.md` and label the summary result
`PARTIAL`.

### Keywords & targets

```
  ◆ Keywords & Targets
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    Error messages:  "{error_msg_1}", "{error_msg_2}"
    Functions:       handleAuth, validateToken
    Components:      AuthMiddleware, SessionManager
    File refs:       src/auth.py, config/routes.ts
```

Omit categories that have no entries.

### Affected files table

```
  ◆ Affected Files
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    File                        │ Relevance │ Role
    ────────────────────────────┼───────────┼──────────────
    src/auth/middleware.py       │ critical  │ entry point
    src/auth/session.py          │ high      │ session logic
    src/config/settings.py       │ medium    │ config values
    tests/test_auth.py           │ high      │ existing tests
```

Table rules (per `docs/terminal-style.md`): box-drawing characters `│ ─ ┼`, max 80 chars wide, truncate paths with `...` if needed.

### Git history

```
  ◆ Git History
  ┄┄┄┄┄┄┄┄┄┄┄┄
    Related commits:   {N} commits touching affected files
    Prior fix attempts: {M} (or "none")
    Regression candidate: {sha7} {date} — {message}
    Domain experts:    @{author1} (12 commits), @{author2} (5)
```

If a prior fix attempt or regression candidate is found, highlight it:
```
    ⚡ Prior fix attempt: {sha7} {message}
       Committed {date} by {author} — issue still open
    ⚡ Possible regression: {sha7} {message}
       Committed {date}, issue created {issue_date}
```

If the issue may already be addressed:
```
    ⚡ May already be addressed by {sha7}:
       {commit_message}
       Committed {date} by {author}
```

Omit sub-sections that have no entries. If no related commits at all:
```
  ◆ Git History
  ┄┄┄┄┄┄┄┄┄┄┄┄
    ○ No related commits found in git history.
```

### Cross-references

```
  ◆ Cross-references
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    Blocks:         #{a}, #{b}
    Blocked by:     #{c}
    Related issues: #{d} (shared affected files)
    ⚡ May be resolved by PR #88: Fix session handling
       Merged 2026-03-19, modified: src/auth/session.py
    ⚠ Possible duplicate: #51 — Auth redirect on mobile
       Shared keywords: redirect, auth, mobile
```

If triage data is unavailable, show what was found from issue/PR scanning only:
```
  ◆ Cross-references
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    ○ No triage data — run /issue-triage for dependency
      analysis. Showing issue/PR scan results only.
    Related issues: #{d} (shared keywords)
```

If nothing found:
```
  ◆ Cross-references
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    ○ No related issues or PRs found.
```

### Root cause / impact analysis

```
  ◆ Root Cause Analysis
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    {Multi-line description of root cause / architecture fit
     / current implementation, depending on issue type.
     Two-space indent under the header.}
```

The section title changes by type:
- Bug → `Root Cause Analysis`
- Feature → `Architecture Analysis`
- Improvement → `Implementation Analysis`

### Implementation options

```
  ◆ Implementation Options
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

    Option 1: {name} ({complexity})
    ┄┄┄┄┄┄┄┄┄┄┄┄
      {summary}
      Modify:  {file1}, {file2}
      Create:  {file3} (if any)
      + {pro_1}
      + {pro_2}
      - {con_1}
      Risk:    {Low|Medium|High} — {explanation}

    Option 2: {name} ({complexity})
    ┄┄┄┄┄┄┄┄┄┄┄┄
      {summary}
      Modify:  {file1}, {file2}, {file3}
      + {pro_1}
      - {con_1}
      - {con_2}
      Risk:    {Low|Medium|High} — {explanation}
```

Omit the `Create:` line if no files need to be created for that option.

### Summary

```
  ◆ Summary
  ┄┄┄┄┄┄┄┄┄
    Complexity:   {XS|S|M|L|XL} (based on recommended option)
    Risk:         {Low|Medium|High}
    Recommended:  Option {N} — {name}
```

### Decision Record

The Decision Record is the durable analysis signal that `/issue-resolver` lifts into the PR body and squash commit body. It uses the same five field labels as the JSON `decision_record` block — labels are stable across `/issue-analysis`, `/issue-resolver`, and `/issue-pr-review` because downstream presence checks are string-matched.

```
  ◆ Decision Record
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    Root cause:         {one-paragraph diagnosis from Step 6}
    Options considered: Option 1 — {name}; Option 2 — {name}; Option 3 — {name}
    Options rejected:   Option 1 — {one-line reason}; Option 3 — {reason}
    Selected option:    Option {N} — {name}
    Residual risk:      {what remains uncertain or accepted as known limitation}

    Analyzed at:        {branch} @ {commit_sha_short} ({YYYY-MM-DD})
```

If only one option was generated, render `Options rejected: none`. If `residual_risk` is empty, render `Residual risk: none identified`.

After output:
```
[8/8] Report         ✓ analysis complete
```

---

## Persist

After Step 8, save the analysis to `.gitissue/analysis-<N>.json`.

1. Create the directory if it doesn't exist: `mkdir -p .gitissue/`
2. Capture `git_state` so the analysis is pinned to a specific point in time. Run each command and write its output to the **exact JSON key named beside it** — the key names are a contract, not a suggestion, so never rename one on the way in:
   ```bash
   git rev-parse --abbrev-ref HEAD            # → git_state.branch
   git rev-parse HEAD                         # → git_state.commit_sha (full 40 chars — never write it as `sha`)
   git rev-parse --short=7 HEAD               # → git_state.commit_sha_short (display only)
   date -u +%Y-%m-%dT%H:%M:%SZ                # → git_state.captured_at AND the top-level `timestamp`
   ```
   Run the clock command **once** and write that one value to both timestamp keys. Both are **captured by running that command** — never invented, estimated, inferred from the conversation's idea of the date, or rounded to midnight; a `T00:00:00Z` value is the signature of a guessed clock.
   If the working tree is detached or the branch cannot be resolved, fall back to `branch: "(detached)"` and continue.
3. Build the `decision_record` block by lifting fields from Steps 6 and 7:
   - `root_cause` ← `analysis.summary` (one paragraph; use `analysis.details` first paragraph if `summary` is empty)
   - `options_considered` ← compact list of every entry in `options[]` (number + name only)
   - `options_rejected` ← every option whose number is not `recommended_option`, each with a one-line reason derived from `options[].cons[0]` or `options[].risk_details`
   - `selected_option` ← `options[recommended_option - 1]` reduced to number + name + summary
   - `residual_risk` ← the highest-severity con of the selected option, or `"none identified"` if none
4. Build the full JSON object from Steps 1-8 analysis results plus `git_state` and `decision_record` using the schema below. `issue.updatedAt` is **required**: copy it verbatim from the Step 1 issue fetch (whose field list already requests `updatedAt`) — never omit it, never re-derive it, and never substitute the capture time.
5. Write `.gitissue/analysis-<N>.json` with formatted JSON (readable diffs in git)
6. Print: `✓ Analysis saved to .gitissue/analysis-<N>.json`

**These key names are a consumer contract.** `/issue-resolver`'s *Step 0h — Analysis reuse gate* reads `git_state.commit_sha` and `issue.updatedAt` to decide whether this analysis is still true — the commit-SHA pin exists precisely so that check is possible, and `issue.updatedAt` is the GitHub-clock value the resolver compares its own fresh fetch against. The top-level `timestamp` and `git_state.captured_at` record when the analysis was taken; they are the *local* clock and the gate never compares them against GitHub's. Renaming a key (writing `git_state.sha` instead of `commit_sha`), omitting one, or inventing the clock does not fail loudly: it silently answers `stale` forever, so the resolver re-runs the very research this file was written to save.

If writing fails:
```
⚠ Could not save analysis to .gitissue/analysis-N.json

  To fix:  check file permissions in the .gitissue/ directory
```
This is a warning, not a fatal error — the terminal output from Step 6 was already displayed.

### JSON Schema (`.gitissue/analysis-<N>.json`)

```json
{
  "version": 1,
  "timestamp": "2026-03-21T14:30:00Z",
  "source": "/issue-analysis",
  "issue": {
    "number": 42,
    "title": "Fix mobile auth redirect loop",
    "type": "bug",
    "reporter": {
      "login": "janedoe",
      "name": "Jane Doe"
    },
    "labels": ["bug", "auth", "mobile"],
    "state": "open",
    "createdAt": "2026-03-15T10:00:00Z",
    "updatedAt": "2026-03-20T08:00:00Z"
  },
  "research_status": {
    "already_resolved": false,
    "pr_in_progress": false,
    "possibly_already_fixed": false,
    "resolution_details": null
  },
  "extraction": {
    "error_messages": ["ERR_TOO_MANY_REDIRECTS"],
    "functions": ["handleRedirect", "validateSession"],
    "classes": ["AuthMiddleware"],
    "file_refs": ["src/auth/middleware.py"],
    "modules": ["auth", "config"],
    "keywords": ["redirect", "loop", "mobile", "auth", "session"]
  },
  "affected_files": [
    {
      "path": "src/auth/middleware.py",
      "relevance": "critical",
      "role": "redirect logic",
      "match_reasons": ["direct file reference", "function match: handleRedirect"]
    }
  ],
  "analysis": {
    "type_specific": "root_cause",
    "summary": "One-paragraph analysis summary.",
    "details": "Full multi-paragraph analysis text."
  },
  "options": [
    {
      "number": 1,
      "name": "Minimal fix",
      "summary": "Add login route to redirect exclusion list",
      "files_to_modify": [
        {
          "path": "src/auth/middleware.py",
          "changes": "Add login route to EXCLUDED_ROUTES constant"
        }
      ],
      "files_to_create": [],
      "pros": ["Smallest change, lowest risk", "Easy to test"],
      "cons": ["Hardcoded exclusion list grows over time"],
      "complexity": "S",
      "risk": "Low",
      "risk_details": "Single file, clear behavior change"
    }
  ],
  "recommended_option": 1,
  "overall_complexity": "S",
  "overall_risk": "Low",
  "history": {
    "related_commits": [
      {
        "sha": "a1b2c3d",
        "message": "fix: resolve auth redirect (#42)",
        "author": "jdoe",
        "date": "2026-03-18T10:00:00Z",
        "files": ["src/auth/middleware.py"],
        "type": "prior_fix_attempt"
      }
    ],
    "regression_candidate": {
      "sha": "e4f5g6h",
      "message": "refactor: simplify session check",
      "author": "asmith",
      "date": "2026-03-10T14:00:00Z",
      "files": ["src/auth/middleware.py"]
    },
    "already_addressed": null,
    "domain_experts": [
      {"author": "jdoe", "commit_count": 12},
      {"author": "asmith", "commit_count": 5}
    ]
  },
  "cross_references": {
    "blocks": [],
    "blocked_by": [],
    "related_issues": [
      {
        "number": 51,
        "title": "Auth redirect on mobile",
        "relationship": "possible_duplicate",
        "shared_keywords": ["redirect", "auth", "mobile"],
        "confidence": "medium"
      }
    ],
    "resolved_by": [
      {
        "type": "pr",
        "number": 88,
        "title": "Fix session handling",
        "merged_at": "2026-03-19T10:00:00Z",
        "shared_files": ["src/auth/session.py"],
        "confidence": "low"
      }
    ],
    "triage_data_available": false,
    "triage_timestamp": null
  },
  "scan_stats": {
    "files_read": 18,
    "deps_traced": 12,
    "keywords_extracted": 8,
    "file_refs_extracted": 2,
    "scan_duration_seconds": 45,
    "scan_timed_out": false
  },
  "git_state": {
    "branch": "main",
    "commit_sha": "01afdc5ba2a1f856f116d46168f870d35b549789",
    "commit_sha_short": "01afdc5",
    "captured_at": "2026-03-21T14:30:00Z"
  },
  "decision_record": {
    "root_cause": "One-paragraph diagnosis lifted from analysis.summary or analysis.details.",
    "options_considered": [
      {"number": 1, "name": "Minimal fix"},
      {"number": 2, "name": "Balanced refactor"},
      {"number": 3, "name": "Comprehensive overhaul"}
    ],
    "options_rejected": [
      {"number": 1, "reason": "Hardcoded list grows over time."},
      {"number": 3, "reason": "Out of scope for this issue."}
    ],
    "selected_option": {
      "number": 2,
      "name": "Balanced refactor",
      "summary": "One-sentence description of the chosen approach."
    },
    "residual_risk": "What remains uncertain after the fix lands, or 'none identified'.",
    "reproduction": {
      "command": "Exact command/test that reproduces the symptom (bug issues only).",
      "status": "red",
      "stated_reason_match": "The failing line/message that matches the issue symptom.",
      "regression_test": "Path of the regression test, or 'manual — no seam'."
    }
  }
}
```

The `reproduction` object is **optional** and present only for `type: bug` issues — omit it for feature/improvement issues. This schema defines its shape so both skills agree on it, but `/issue-analysis` does not itself populate it: it is read-only and runs *before* the fix, so it cannot produce the post-fix `regression_test` proof. The evidence is produced by `/issue-resolver` at its Step 3 bug-verification checkpoint; this field is the optional cache mirror it lifts into the PR Decision Record and acceptance table when present (the PR body is the always-present durable home). `status` is `red` (reproduced and failing for the stated reason) or `not_reproduced` (could not be made red).

### Schema field reference

| Field | Type | Description |
|-------|------|-------------|
| `version` | integer | Schema version, always `1` |
| `timestamp` | ISO 8601 string | When this analysis was generated — captured with `date -u +%Y-%m-%dT%H:%M:%SZ`, never invented |
| `source` | string | Always `"/issue-analysis"` |
| `issue.number` | integer | GitHub issue number |
| `issue.title` | string | Issue title |
| `issue.type` | string | `"bug"`, `"feature"`, or `"improvement"` |
| `issue.reporter` | object | Issue author from GitHub |
| `issue.reporter.login` | string | GitHub username |
| `issue.reporter.name` | string or null | Display name (may be null if not set) |
| `issue.labels` | string[] | GitHub labels |
| `issue.state` | string | `"open"` or `"closed"` |
| `issue.createdAt` | ISO 8601 string | Issue creation date |
| `issue.updatedAt` | ISO 8601 string | Last update date, copied verbatim from the issue fetch — **required**, never omitted |
| `research_status` | object | Explorer status copied unchanged; always persisted so status findings remain visible |
| `research_status.already_resolved` | boolean | Research found resolution evidence on the default branch |
| `research_status.pr_in_progress` | boolean | Research found an open PR targeting this issue |
| `research_status.possibly_already_fixed` | boolean | Code evidence suggests the reported condition may no longer exist |
| `research_status.resolution_details` | string or null | Evidence/PR details supplied by the researcher |
| `extraction.error_messages` | string[] | Error strings found in issue body |
| `extraction.functions` | string[] | Function/method names extracted |
| `extraction.classes` | string[] | Class/component names extracted |
| `extraction.file_refs` | string[] | Explicit file paths mentioned |
| `extraction.modules` | string[] | Module/package names inferred |
| `extraction.keywords` | string[] | Significant keywords from title/body |
| `affected_files[]` | array | Files identified during research |
| `affected_files[].path` | string | Relative file path |
| `affected_files[].relevance` | string | `"critical"`, `"high"`, `"medium"`, or `"low"` |
| `affected_files[].role` | string | What role this file plays in the issue |
| `affected_files[].match_reasons` | string[] | Why this file was identified |
| `analysis.type_specific` | string | `"root_cause"` (bug), `"architecture_fit"` (feature), `"current_impl"` (improvement) |
| `analysis.summary` | string | One-paragraph analysis summary |
| `analysis.details` | string | Full multi-paragraph analysis |
| `options[]` | array | 2-3 implementation approaches |
| `options[].number` | integer | Option number (1-indexed) |
| `options[].name` | string | Short label |
| `options[].summary` | string | One-sentence description |
| `options[].files_to_modify` | array | Files to change with descriptions |
| `options[].files_to_create` | array | New files with descriptions |
| `options[].pros` | string[] | Advantages |
| `options[].cons` | string[] | Disadvantages |
| `options[].complexity` | string | `"XS"`, `"S"`, `"M"`, `"L"`, or `"XL"` |
| `options[].risk` | string | `"Low"`, `"Medium"`, or `"High"` |
| `options[].risk_details` | string | Brief risk explanation |
| `recommended_option` | integer | Option number recommended |
| `overall_complexity` | string | Overall complexity estimate |
| `overall_risk` | string | Overall risk level |
| `scan_stats.scan_timed_out` | boolean | `true` when the bounded scan returned partial findings; final result is `PARTIAL` |
| `history.related_commits[]` | array | Commits related to this issue |
| `history.related_commits[].sha` | string | Short SHA (7 chars) |
| `history.related_commits[].message` | string | Commit message (first line) |
| `history.related_commits[].author` | string | Commit author |
| `history.related_commits[].date` | ISO 8601 string | Commit date |
| `history.related_commits[].files` | string[] | Files modified by this commit |
| `history.related_commits[].type` | string | `"prior_fix_attempt"`, `"related_change"`, `"keyword_match"` |
| `history.regression_candidate` | object or null | Commit that may have introduced the issue |
| `history.already_addressed` | object or null | Commit that appears to fix this issue |
| `history.domain_experts[]` | array | Top contributors to affected files |
| `history.domain_experts[].author` | string | Git author name |
| `history.domain_experts[].commit_count` | integer | Number of commits to affected files |
| `cross_references.blocks` | integer[] | Issues this one blocks (from triage) |
| `cross_references.blocked_by` | integer[] | Issues blocking this one (from triage) |
| `cross_references.related_issues[]` | array | Issues with overlapping scope |
| `cross_references.related_issues[].number` | integer | Issue number |
| `cross_references.related_issues[].title` | string | Issue title |
| `cross_references.related_issues[].relationship` | string | `"possible_duplicate"`, `"shared_files"`, `"shared_keywords"`, `"explicit_reference"` |
| `cross_references.related_issues[].shared_keywords` | string[] | Keywords in common |
| `cross_references.related_issues[].confidence` | string | `"high"`, `"medium"`, `"low"` |
| `cross_references.resolved_by[]` | array | PRs/issues that may already address this |
| `cross_references.resolved_by[].type` | string | `"pr"` or `"issue"` |
| `cross_references.resolved_by[].number` | integer | PR or issue number |
| `cross_references.resolved_by[].title` | string | Title |
| `cross_references.resolved_by[].merged_at` | ISO 8601 or null | When merged (PRs only) |
| `cross_references.resolved_by[].shared_files` | string[] | Overlapping affected files |
| `cross_references.resolved_by[].confidence` | string | `"high"`, `"medium"`, `"low"` |
| `cross_references.triage_data_available` | boolean | Whether triage.json was found |
| `cross_references.triage_timestamp` | ISO 8601 or null | When triage was last run |
| `scan_stats.files_read` | integer | Total files read during research |
| `scan_stats.deps_traced` | integer | Import dependencies traced |
| `scan_stats.keywords_extracted` | integer | Keywords found in issue body |
| `scan_stats.file_refs_extracted` | integer | Explicit file paths found |
| `scan_stats.scan_duration_seconds` | integer | Time spent on research |
| `git_state.branch` | string | Branch name HEAD pointed at when analysis ran |
| `git_state.commit_sha` | string | Full 40-character commit SHA at analysis time |
| `git_state.commit_sha_short` | string | First 7 characters of `commit_sha` for display |
| `git_state.captured_at` | ISO 8601 string | Timestamp when `git_state` was captured (matches top-level `timestamp`) |
| `decision_record.root_cause` | string | One-paragraph diagnosis lifted from `analysis.summary` or `analysis.details` |
| `decision_record.options_considered[]` | array | Compact list of all options proposed in Step 7 |
| `decision_record.options_considered[].number` | integer | Option number (matches `options[].number`) |
| `decision_record.options_considered[].name` | string | Option name (matches `options[].name`) |
| `decision_record.options_rejected[]` | array | Options not chosen, with one-line reason; empty array if only one option was generated |
| `decision_record.options_rejected[].number` | integer | Option number |
| `decision_record.options_rejected[].reason` | string | One-line reason this option was not selected |
| `decision_record.selected_option` | object | The chosen option, lifted from `options[recommended_option - 1]` |
| `decision_record.selected_option.number` | integer | Option number |
| `decision_record.selected_option.name` | string | Option name |
| `decision_record.selected_option.summary` | string | One-sentence description of the chosen approach |
| `decision_record.residual_risk` | string | What remains uncertain or accepted as a known limitation; `"none identified"` if empty |
| `decision_record.reproduction` | object | **Bug issues only** (omit otherwise). Red-capable verification evidence mirrored from the resolver's bug-verification checkpoint |
| `decision_record.reproduction.command` | string | Exact command/test that reproduces the symptom |
| `decision_record.reproduction.status` | string | `"red"` (reproduced, failing for the stated reason) or `"not_reproduced"` |
| `decision_record.reproduction.stated_reason_match` | string | The failing line/message matching the issue symptom |
| `decision_record.reproduction.regression_test` | string | Path of the regression test, or `"manual — no seam"` |

