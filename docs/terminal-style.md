# Terminal Output Style Contract

The single source of truth for what gitissue skills emit: symbol vocabulary,
output structure, progress patterns, table and error formats, and the rules for
confirmations, confidence, first-run, and empty states. `DESIGN.md` (repo root)
is the human-facing guide layered on top — colors and per-command mockups; where
the two overlap, this document wins.

## Principles

1. **Show, don't dump.** Structured output > raw text. Tables > JSON. Sections > walls of text.
2. **Transparency builds trust.** Show confidence scores, step progress, and what's happening at each phase. No black boxes.
3. **Errors are help.** When something fails, show what went wrong + how to fix + where to learn more.
4. **Warmth in empty states.** "No items found" is not a design. Every empty state has context and a next action.
5. **Distinctive, not decorative.** Step counters, confidence markers, and semantic symbols give gitissue its own feel — not generic AI slop.

## Symbol Vocabulary

| Symbol | Meaning | Color | Example |
|--------|---------|-------|---------|
| `●` | In progress | — | `● Scanning codebase...` |
| `✓` | Success / complete | Green | `✓ Created issue #42` |
| `✗` | Failure / error | Red | `✗ Not authenticated` |
| `◆` | Section header | Bold | `◆ Issue Preview` |
| `⚡` | Action / recommendation | — | `⚡ Parallelizable: #12 + #8` |
| `⚠` | Warning | Yellow | `⚠ Stale: 1 issue (>14d)` |
| `○` | Info / neutral | — | `○ First run — using defaults` |
| `⟶` | Next action / leads to | — | `⟶ Spawning resolver subagent...` |
| `+` | Added field | — | `+ Files: auth.py (high)` |
| `=` | Preserved field | — | `= Original: preserved` |
| `√` | Completion-report check passed | — | `√ Tests written` |
| `×` | Completion-report check failed | — | `× Build clean` |

All symbols carry meaning without color. Never rely on color alone.

`√` and `×` are reserved for **step completion reports** — the `Result: PASS | PARTIAL | FAIL` blocks a skill prints to close each step. They are deliberately distinct from `✓`/`✗`, which report the run's own status, so a check row is never mistaken for a status line. Each skill defines its own per-step check names in its `references/` report file.

`⟶` marks the transition to the next autonomous action in a loop (auto-pilot):
what the orchestrator is about to do — spawn a subagent, start immediately,
merge a partial PR. It reads as "leads to".

## Output Structure

Every command follows this hierarchy:

```
  ● Progress (what's happening now)

  ◆ Section Header
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    Content (indented 2 spaces)
    More content

  ✓ Result (what happened)
    https://url (always on its own line)
```

Rules:
- One blank line between sections
- Two-space indent for content under headers
- No trailing blank lines
- URLs always on their own line, in cyan
- Section separators: `┄` (light dash, not heavy box)

## Progress Patterns

**Multi-step pipeline** (issue-resolver):
```
  [0/5] Preflight    ✓ issue #42 open, not yet resolved
  [1/5] Research     ✓ read 5 files, complexity: medium
  [2/5] Plan         ● selecting approach...
```

**Single operation** (issue-creator):
```
  ● Scanning codebase...
```

## Table Format

```
  #  │ Issue              │ Pri │ Blocks │ Status
  ───┼────────────────────┼─────┼────────┼───────────
  1  │ #12 Fix auth       │ P1  │ #15    │ ready
  2  │ #8  Add pagination │ P2  │ —      │ ready
```

- Box-drawing characters: `│ ─ ┼`
- Right-align numbers, left-align text
- Max width: 80 characters (truncate with `...` if needed)
- Use `—` for empty cells (not blank)

## Error Format

Errors are the moment users need the most help.

```
  ✗ Short error description

    To fix:  <actionable command>
    Docs:    <url to relevant documentation>
```

Always include: what went wrong, how to fix it, where to learn more.

## Confirmation Prompts

```
  Apply normalization? [Y/n]
```

Default option in uppercase. Alternatives in lowercase.

## Confidence Markers

Unique to gitissue. Show honesty about what's inferred:

```
  + Files:    auth.py (high), config.py (medium)
  + Criteria: 3 acceptance criteria (medium)
```

Levels: `high` (direct match), `medium` (keyword inference), `low` (best guess, marked `(needs review)` in the issue).

## First-Run Experience

When no `.gitissue.yml` exists:

```
  ○ First run — using default config. Run /init-gitissue to customize.
```

One line, then proceed normally. Non-intrusive.

## Empty States

Every empty state has warmth and a next action:

| Scenario | Output |
|----------|--------|
| No files identified | `⚠ Could not identify affected files. Issue created with manual-review flag. Tip: mention specific filenames for better results.` |
| No open issues (triage) | `○ No open issues found. Nothing to triage! Create issues with /issue-creator to get started.` |
| Already normalized | `✓ Issue #42 is already normalized (v1, 2026-03-15). No changes needed.` |
| Issue not found | `✗ Issue #42 not found\n\n  To fix: gh issue list\n  Check: is this the right repository?` |

## GitHub Markdown Rendering

Normalized issues must render cleanly in GitHub's web UI:

- Use standard markdown (no HTML except the invisible marker)
- Section headers: `## Type`, `## Description`, `## Acceptance Criteria`
- Code blocks for file paths and technical details
- Normalization marker: `<!-- gitissue:normalized v1 -->` (invisible in rendered view)
- QA handoff marker: `<!-- gitissue:qa v1 head=<sha40> … -->` — same invisible shape, written by `/issue-resolver` as a PR body's last line and read by `/issue-pr-review`; it gates duplicated work only, never a safety check
- Reporter's original text: in a `> Reporter Context` blockquote
- Confidence markers in parentheses: `(high confidence)`, `(needs review)`
