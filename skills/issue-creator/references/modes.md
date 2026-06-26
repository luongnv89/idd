# /issue-creator — Normalize and Batch Modes

Full specs for the Normalize and Batch Create modes. SKILL.md keeps a summary; this reference holds the full step-by-step flows, templates, and error handling.

## Mode: Normalize Existing Issue


### Step 1 — Fetch Issue

```bash
gh issue view {N} --json number,title,body,labels,assignees,state,comments
```

If not found:
```
✗ Issue #42 not found

  To fix:  gh issue list
  Check:   is this the right repository?
```

### Step 2 — Check Already Normalized

Look for `<!-- gitissue:normalized v1 -->` as a standalone HTML comment in the issue body.

If found:
```
✓ Issue #42 is already normalized (v1, 2026-03-20). No changes needed.
```
Stop. The date is today's date in YYYY-MM-DD format.

Important: if the marker text appears inside a code block or blockquote, it is not a real marker — proceed with normalization.

### Step 3 — Check Issue State

If the issue is locked:
```
✗ Issue #42 is locked

  To fix:  unlock the issue in GitHub's web UI, then retry
```
Stop.

If the issue body exceeds 60,000 characters, note this — Metadata will be truncated in Step 5 to stay under GitHub's 65KB limit.

### Step 4 — Security Label Check

Check labels for: `security`, `CVE`, `vulnerability` (case-insensitive).

If found and `--force` not used:
```
⚠ Issue #42 has a security label (security). Skipping normalization.
  Codebase context could reveal exploit details.

  To override: /issue-creator 42 --force
```
Stop.

### Step 5 — Generate Normalization Content

Classify type from the existing issue content, then use the matching template:

1. Preserve the entire original issue body in `> **Reporter Context**` blockquote
2. Fill all template sections from the issue text (type, description, acceptance criteria, metadata)
3. Place `<!-- gitissue:normalized v1 -->` at the top
4. If original body > 60K chars, truncate Metadata to fit under 65KB

**Note:** Normalization is structure-only — it restructures the issue into the standard template without scanning the codebase. No affected files, technical notes, or architecture constraints are added.

### Step 6 — Preview with Confidence Scores

```
● Fetching issue #42...

◆ Normalization Preview
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  + Type:        bug (high confidence)
  + Criteria:    3 acceptance criteria (medium)
  + Labels:      +bug, +auth
  = Original:    preserved in Reporter Context block

Apply normalization? [Y/n/dry-run]
```

`+` = added field, `=` = preserved field. Use `(high confidence)` for Type, abbreviated `(high)`, `(medium)`, `(low)` for criteria. Low-confidence fields get `(needs review)` in the issue body.

Wait for confirmation. `n` → stop. `dry-run` → proceed to Step 7.

### Step 7 — Dry Run Check

If `--dry-run` was specified or selected at the prompt:
```
○ Dry run complete. No changes applied.
```
Stop.

### Step 8 — Backup Original Body

Post a backup comment with the original body before making any edits. This is a data safety requirement — if the backup fails, abort entirely. Never edit the issue body without a verified backup.

```bash
gh issue comment {N} --body "<details><summary>Original issue body (backup by gitissue)</summary>

{original_body}

</details>"
```

Verify success via the command exit code. If it fails:
```
✗ Failed to post backup comment for issue #42

  Normalization aborted — original issue body is unchanged.
  To fix:  check your permissions: gh issue comment 42 --body "test"
```
Stop. Do not edit the issue body.

### Step 9 — Update Issue Body

```bash
gh issue edit {N} --body "{normalized_body}"
```

### Step 10 — Post Normalization Comment

If `issue.normalize_comment` is true:

```bash
gh issue comment {N} --body "🔧 **Normalized by gitissue**

Added: type classification, acceptance criteria, structured description.
Original body preserved in Reporter Context block and backup comment above."
```

### Step 11 — Apply Labels

If `issue.labels_auto_suggest` is true and new labels were suggested:

```bash
gh issue edit {N} --add-label "{label1},{label2}"
```

### Step 12 — Report

Print a structured step-by-step summary:

```
◆ Issue Normalized: #{N}
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Fetch:             ✓ pass
  Already normal:    ✓ pass (not yet normalized)
  State check:       ✓ pass (unlocked)
  Security check:    ✓ pass (no security labels)
  Generate:          ✓ pass ({type} template applied)
  Dry-run:           ✓ approved
  Backup:            ✓ pass (comment #{comment_id})
  Update:            ✓ pass
  Labels:            ✓ pass ({N} labels applied)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            DONE

  #{N}  {title}
  https://github.com/owner/repo/issues/{N}
```

---

## Mode: Batch Create

Create multiple issues from a single input — a planning document, a list of bugs, a screenshot with multiple items, or any text containing several distinct problems or features.

### Step 1 — Detect Items

Parse the input and identify distinct items. Boundary detection heuristics:

- **Numbered lists** — `1.`, `2.`, etc. are separate items
- **Bullet points** — each `- ` or `* ` at the top level is an item
- **Paragraph breaks** — distinct paragraphs describing different problems
- **Headings** — each heading starts a new item
- **Screenshot items** — for images, each visually distinct element (separate error, UI element, or annotation)

For each detected item, extract: a short title, keywords, and implied type (bug/feature/improvement).

If only one item is detected, fall through to single Create mode silently.

### Step 2 — Preview Table

Display all extracted items in a table for review before creating anything:

```
● Parsing input...
  Found {N} items in input

◆ Batch Preview
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  #  │ Type        │ Title                              │ Effort
  ───┼─────────────┼────────────────────────────────────┼───────
  1  │ bug         │ Fix Safari checkout redirect        │ S
  2  │ feature     │ Add dark mode toggle                │ M
  3  │ improvement │ Refactor auth middleware             │ L
```

Use DESIGN.md table format: box-drawing characters `│ ─ ┼`, right-align numbers, left-align text, max 80 chars wide (truncate titles with `...`).

### Step 3 — Duplicate Check

#### Subagent delegation

Spawn the duplicate-detector subagent with all batch items:

```json
{
  "mode": "batch",
  "items": [
    { "index": 1, "title": "...", "keywords": [...], "type": "bug" },
    { "index": 2, "title": "...", "keywords": [...], "type": "feature" }
  ],
  "repo_root": "{repo_root}"
}
```

Read `references/agents/duplicate-detector.md` for the full prompt. The subagent checks each item against existing open issues AND cross-checks items against each other in a single pass.

**Parallel execution:** In batch mode, spawn the duplicate-detector at the same time as pre-generating template content — both results are ready by Step 4 (Approval) and consumed at Step 5 (Create Issues).

#### Fallback (no Agent tool)

If the Agent tool is not available, run inline:

```bash
gh issue list --state open --json number,title,body,labels --limit 100
```

Check each batch item against existing issues AND against other items in the batch.

#### Present results

Flag duplicates found by the subagent (or fallback). Both `existing_issue` and `batch_internal` matches are shown:

```
⚠ Item 2 may duplicate: #15 "Dark mode support"
  View: https://github.com/owner/repo/issues/15

⚠ Item 3 overlaps with Item 1 — both address auth session handling
```

Duplicates are flagged but not removed — the user decides in the approval step.

### Step 4 — Approval

Prompt the user with three options:

```
Create 3 issues? [A]ll / [e]dit / [c]ancel
```

- **All** (default) — create all items as-is
- **Edit** — let the user specify items to modify or remove (e.g., "remove 2, change 3 title to...")
- **Cancel** — stop without creating any issues

If the user chooses Edit, apply the requested changes, re-display the updated table, and show the approval prompt again:
```
Create {N} issues? [A]ll / [e]dit / [c]ancel
```

### Step 5 — Create Issues

Create each approved issue sequentially using the same pipeline as single Create mode (generate content from template, `gh issue create`). Each issue gets the full template treatment — `<!-- gitissue:normalized v1 -->` marker, all sections populated.

> **Batch never blocks for clarification.** The single Create pipeline includes an interactive *Step 3.5 — Clarify Ambiguous Intent* that asks one targeted question when type/criteria confidence is low. Batch mode **skips that step entirely** — it never pauses to ask the user about an individual item. Low-confidence fields are drafted with their defaulted assumptions and marked `(needs review)` in the body, exactly as before. Batch's only interactive gate remains the Step 4 approval prompt over the whole set.

**Rate limiting:** If `gh issue create` returns a rate limit error, wait and retry with exponential backoff (5s, 10s, 20s). After 3 retries for a single item, skip it and continue with remaining items.

**Progress output:** Show per-item progress:

```
● Creating issue 1/3...
✓ Created issue #42: Fix Safari checkout redirect
  https://github.com/owner/repo/issues/42

● Creating issue 2/3...
✓ Created issue #43: Add dark mode toggle
  https://github.com/owner/repo/issues/43

● Creating issue 3/3...
✗ Failed to create: Refactor auth middleware (rate limited)
```

### Step 6 — Report

Print a structured step-by-step summary:

**All succeeded:**
```
◆ Batch Create — {N}/{N} issues
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Detect items:      ✓ pass ({N} items found)
  Preview:           ✓ approved
  Duplicates:        ✓ pass (no duplicates)
  Create:            ✓ pass ({N}/{N} created)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            DONE

  ✓ #42  Fix Safari checkout redirect
         https://github.com/owner/repo/issues/42
  ✓ #43  Add dark mode toggle
         https://github.com/owner/repo/issues/43
  ✓ #44  Refactor auth middleware
         https://github.com/owner/repo/issues/44
```

**Partial failure:**
```
◆ Batch Create — {succeeded}/{total} issues
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Detect items:      ✓ pass ({total} items found)
  Preview:           ✓ approved
  Duplicates:        ✓ pass
  Create:            ⚠ warn ({succeeded}/{total} created, {failed} failed)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            PARTIAL

  ✓ #42  Fix Safari checkout redirect
         https://github.com/owner/repo/issues/42
  ✓ #43  Add dark mode toggle
         https://github.com/owner/repo/issues/43
  ✗      Refactor auth middleware — rate limited

  To retry failed: /issue-creator Refactor auth middleware
```

The retry hint shows the single-create invocation for each failed item, so the user can easily pick up where the batch left off.

---
