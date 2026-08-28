# skill-auto-improver run — `/issue-pr-review`

**Issue:** [#417](https://github.com/luongnv89/idd/issues/417) · part of epic #413
**Target:** `src/skills/issue-pr-review/` (measured against built `skills/issue-pr-review/`)
**Measuring standard:** `skill-auto-improver` v2.1.0
**Date:** 2026-08-28

> **STATUS: IN PROGRESS.** Gate 1's word threshold and Gate 2's
> `context-efficiency` floor are both unresolved at the time of writing.
> Numbers below are updated as the compression pass lands.

Measurement convention: `src/skills/<name>/` holds `SKILL.source.md`, not
`SKILL.md`, so `quick_validate.py` and `asm eval` cannot read the authored
source. Every measurement was taken read-only against the built tree; every edit
was landed in `src/skills/issue-pr-review/` and the tree regenerated with
`./scripts/build.sh`. `asm eval --fix` was never run against `skills/`.

## 1. Gate status — baseline → current

| Gate | Check | Baseline | Current |
|------|-------|----------|---------|
| Gate 1 | body under 500 lines | 500 (at cap) | 441 |
| Gate 1 | body under 3000 words | **6148 (FAIL)** | **5384 (FAIL)** |
| Gate 1 | `metadata.version` bump | 2.5.0 | 2.6.0 |
| Gate 2 | overall > 85 | 87 (B) | pending |
| Gate 2 | every category >= 8 | **min 6 (FAIL)** | pending |

Per-category baseline (`asm eval --json`, built tree): structure 10 ·
description 10 · prompt-engineering 9 · context-efficiency **6** ·
safety **9** · testability **7** · naming 10 → overall **87**, grade B.

Baseline evaluator findings, verbatim:

- context-efficiency: *"Body is over 3000 words — split long content into
  referenced files or templates."*
- prompt-engineering: *"Body is very long (6148 words)."*
- testability: *"Include an \"Expected output\" example so reviewers and the
  agent can verify correctness."*
- safety: only two findings — the destructive-action/confirmation pair was
  absent because the body named no destructive action at all.

## 2. Work landed so far

- Testability and safety findings closed first (they add words, so they had to
  precede compression): the Pipeline Overview fence is now labelled **Expected
  output**, and Step 7 states that auto-merge squash merges and **deletes** the
  head branch, with the three gates that confirm it.
- `metadata.version` 2.5.0 → 2.6.0.
- Relocations, each with its destination section written in the same commit:
  `references/review-loop-mechanics.md` gained *Config keys and what they gate*
  and *Binding the head-ref name*.
- The *Additional Resources* index was deleted (the *Bundled dependency
  precheck* is the authoritative guard; the build's zero-mention scan strips
  both blocks before it runs, and it reports 0 warnings).

## 3. Remaining

Body is 5384 asm words against a 3000 cap. Sections still carrying the most
compressible prose: Review Loop, QA handoff gate, Step 7, Step 5, Commit
auto-fixes, Configuration, UI/UX Review.
