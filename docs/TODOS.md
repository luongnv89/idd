# TODOS — gitissue / IDD

Generated from /plan-ceo-review on 2026-03-20.
Updated from /plan-eng-review on 2026-03-20.
Updated from /plan-design-review on 2026-03-20.
Updated: 2026-03-20 — Sprint 1-4 complete.
Updated: 2026-03-21 — Lean Issues Architecture (P1) implemented.

## Completed

All P1 items from the original review are implemented in Sprints 1-3:

- [x] Resolve test timeout config (`resolve.test_timeout: 300`)
- [x] Use `gh --json` everywhere (convention)
- [x] Scripted test suite (`tests/`)
- [x] Security issue detection — skip normalization
- [x] GitHub-rendered issue template mockup (`docs/sample-normalized-issue.md`)

## P1 — Lean Issues Architecture (from /plan-eng-review 2026-03-21)

Rethink: issue-creator was embedding codebase analysis into issues, then issue-resolver re-scanned the same code. Three scans per issue lifecycle. The fix: issues contain only human intent (no affected files, no technical notes), and each consumer (resolver, triage) scans the codebase itself when needed — against current code.

### ~~TODO-1: Update issue templates~~ ✓
- **What:** Remove Affected Files, Technical Notes, and Architecture Constraints sections from `templates/bug.md`, `templates/feature.md`, `templates/improvement.md`. Keep: Type, Description, Reporter Context, Acceptance Criteria, Metadata.
- **Why:** Templates must match the lean issue format before skill logic changes.
- **Effort:** XS (human: ~1 hour / CC: ~5 min)
- **Depends on:** Nothing
- **Blocked by:** Nothing
- **Blocking:** TODO-2, TODO-3

### ~~TODO-2: Rewrite issue-creator SKILL.md for lean issues~~ ✓
- **What:** Remove codebase scan steps (Step 2 in Create mode, Step 5 in Normalize mode). Normalize becomes structure-only (restructure messy text into template, no scan). Simplify confidence scoring to type + acceptance criteria only (remove affected files, labels, technical notes confidence). Update preview format to exclude files/tech-notes lines. Update batch mode to skip per-item codebase scan.
- **Why:** Eliminates the first redundant scan. Issues become durable human-intent specs instead of fragile codebase snapshots.
- **Effort:** M (human: ~2 days / CC: ~30 min)
- **Depends on:** TODO-1
- **Blocking:** TODO-3

### ~~TODO-3: Update issue-resolver SKILL.md for structure-only auto-normalize~~ ✓
- **What:** Simplify auto-normalize in Step 1 to structure-only (remove inline scan logic — no Grep+Glob+Read, just text restructuring into template). Keep Research (Step 3) as the single authoritative codebase scan. Remove references to reading affected files from the issue body in Research — instead, Research extracts keywords from the structured issue and scans the codebase fresh.
- **Why:** Eliminates the second redundant scan. Resolver always works against current code.
- **Effort:** S (human: ~1 day / CC: ~15 min)
- **Depends on:** TODO-2
- **Blocking:** Nothing

### ~~TODO-4: Rewrite issue-triage dependency analysis~~ ✓
- **What:** Replace Step 2 (read affected files from issue body) with: extract keywords from issue title/description, grep codebase per issue, build file-overlap dependency graph from scan results. Add `triage.scan_timeout_per_issue` config (default 30s) — skip file analysis for issues that exceed timeout, mark as `no-deps (timeout)`. Add timeout error message to `references/error-messages.md`.
- **Why:** Triage can no longer rely on issue bodies having affected files. Scanning at triage time is more reliable (always current code) and eliminates the hidden dependency on normalization.
- **Effort:** M (human: ~2 days / CC: ~30 min)
- **Depends on:** Nothing (can be done in parallel with TODO-1/2/3)
- **Blocking:** Nothing

### ~~TODO-5: Add integration tests for lean issue architecture~~ ✓
- **What:** Add test cases to `tests/`: lean issue creation (verify no affected files in body), structure-only normalize (verify no scan, structure applied), triage keyword scan (verify dependency detection), triage with no-affected-files issues (verify no errors), triage scan timeout (verify graceful degradation).
- **Why:** The test diagram from this review identified 5 changed codepaths that need coverage.
- **Effort:** S (human: ~4 hours / CC: ~15 min)
- **Depends on:** TODO-1 through TODO-4
- **Blocking:** Nothing

### ~~TODO-6: Update docs for lean issue format~~ ✓
- **What:** Update `docs/config-schema.md` (new triage.scan_timeout_per_issue, note removed fields), update DESIGN.md examples (issue preview without files line), update `docs/sample-normalized-issue.md` to show lean format. Remove references to affected-files-in-issues throughout all docs.
- **Why:** Docs must match the new architecture to avoid confusing contributors.
- **Effort:** S (human: ~2 hours / CC: ~10 min)
- **Depends on:** TODO-1 through TODO-4
- **Blocking:** Nothing

---

## P2 — Future

### ~~Predicted-vs-actual file tracking~~ (OBSOLETE)
- **Status:** Superseded by Lean Issues Architecture (P1 above). Issues no longer contain predicted affected files, so there's nothing to compare. If a feedback loop is needed in the future, it should compare triage's keyword-scan predictions against PR changed files — but that's a different design.
- **Original context:** Record predicted affected files in an HTML comment marker during normalization. After resolution, compare against PR's actual changed files.

### Cross-skill triage updates
- **What:** `/issue-creator` and `/issue-resolver` update `.gitissue/triage.json` after creating/resolving issues — append to `issues[]` and `history[]`.
- **Why:** Keeps triage report fresh between full re-triage runs. Currently `triage.json` goes stale after any issue lifecycle event (create, resolve).
- **Pros:** Users see up-to-date triage without re-running. Reduces GitHub API calls.
- **Cons:** Breaks pure skill isolation (though file-based IPC is already the pattern with `.gitissue.yml`). Each skill needs JSON read/write instructions added to its SKILL.md.
- **Effort:** S (human: ~2 days / CC: ~20 min)
- **Depends on:** #11 (triage persistence) shipped
- **Context:** Decided during eng review of #11. JSON schema already includes `history[]` array to support this — no schema version bump needed when implemented. `/issue-creator` would append new issues with `priority: "needs-review"`. `/issue-resolver` would set `status: "resolved"` on the matching issue entry.
