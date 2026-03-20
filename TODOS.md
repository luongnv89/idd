# TODOS — gitissue / IDD

Generated from /plan-ceo-review on 2026-03-20.
Updated from /plan-eng-review on 2026-03-20.
Updated from /plan-design-review on 2026-03-20.
Updated: 2026-03-20 — Sprint 1-4 complete.

## Completed

All P1 items from the original review are implemented in Sprints 1-3:

- [x] Resolve test timeout config (`resolve.test_timeout: 300`)
- [x] Use `gh --json` everywhere (convention)
- [x] Scripted test suite (`tests/`)
- [x] Security issue detection — skip normalization
- [x] GitHub-rendered issue template mockup (`docs/sample-normalized-issue.md`)

## P2 — Future

### Predicted-vs-actual file tracking
- **What:** Record predicted affected files in an HTML comment marker during normalization (`<!-- gitissue:predicted_files: a.py, b.py -->`). After resolution, compare against PR's actual changed files.
- **Why:** F13 (issue intelligence / feedback loop) depends on this data. Without it, the feedback loop has nothing to learn from.
- **Effort:** S (human: ~1 day / CC: ~15 min)
- **Depends on:** F2 implemented (done)
- **Context:** Plant the data seed early so it accumulates passively. Comparison logic can be built in Phase 5.

### Cross-skill triage updates
- **What:** `/issue-creator` and `/issue-resolver` update `.gitissue/triage.json` after creating/resolving issues — append to `issues[]` and `history[]`.
- **Why:** Keeps triage report fresh between full re-triage runs. Currently `triage.json` goes stale after any issue lifecycle event (create, resolve).
- **Pros:** Users see up-to-date triage without re-running. Reduces GitHub API calls.
- **Cons:** Breaks pure skill isolation (though file-based IPC is already the pattern with `.gitissue.yml`). Each skill needs JSON read/write instructions added to its SKILL.md.
- **Effort:** S (human: ~2 days / CC: ~20 min)
- **Depends on:** #11 (triage persistence) shipped
- **Context:** Decided during eng review of #11. JSON schema already includes `history[]` array to support this — no schema version bump needed when implemented. `/issue-creator` would append new issues with `priority: "needs-review"`. `/issue-resolver` would set `status: "resolved"` on the matching issue entry.
