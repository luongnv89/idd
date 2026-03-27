---
name: issue-creator
description: Create structured GitHub issues from text, screenshots, or images, normalize existing unstructured issues into a standard template, and batch-create multiple issues from a single input. Use this skill whenever someone says "create issue", "file a bug", "report a feature request", "normalize issue", "enrich issue", "structure this issue", "/issue-creator", or describes a bug, feature, or improvement they want tracked. Also use when someone shares an issue number and wants it cleaned up or enriched, or when pasting a screenshot of a bug. Even if the user just describes a problem without saying "issue", this skill turns it into a structured GitHub issue with acceptance criteria and labels via gh CLI. For batch creation, trigger when the user provides a list of items, a planning document, multiple bugs, or says "create issues from this", "file these bugs", "batch create", or pastes text with multiple distinct problems to track.
effort: medium
license: MIT
metadata:
  version: 0.3.0
  creator: Luong NGUYEN <luongnv89@gmail.com>
compatibility: Requires git and GitHub CLI (gh) with authentication. Run `gh auth status` to verify.
---

# /issue-creator

Create structured GitHub issues — or normalize existing ones into a standard template. Supports single, batch, and normalization modes. Issues capture human intent only (no codebase analysis) — the resolver and triage skills scan the codebase themselves when needed.

Three modes: **Create** (new issue from text/image), **Normalize** (restructure existing issue #N into standard template), and **Batch** (extract multiple issues from one input).

## Modes

| Invocation | Mode | What happens |
|------------|------|--------------|
| `/issue-creator <text>` | Create | New structured issue from a text description |
| `/issue-creator <N>` | Normalize | Restructure existing issue #N into standard template |
| `/issue-creator <N> --dry-run` | Preview | Show normalization preview without applying |
| `/issue-creator <N> --force` | Force | Normalize even if security-labeled |
| `/issue-creator <multi-item text>` | Batch | Extract multiple issues from one input and create sequentially |

Detect mode: if the argument is a number → Normalize. If the input contains multiple distinct items (numbered list, bullet points, multiple paragraphs describing different problems, or a planning document with several work items) → Batch. Otherwise → Create.

**Image/screenshot input**: When the user provides an image path or screenshot, read the image with the Read tool to extract visual context, then treat extracted information as the input description. Combine visual observations with any accompanying text. Additionally, upload the image to GitHub and embed it in the issue body — see the **Image Upload** section below.

## Prerequisites

Before any operation, verify the environment. On failure, output the exact error from `references/error-messages.md` and stop.

1. Confirm git repository: `git rev-parse --git-dir`
2. Confirm `gh` is installed: `which gh`
3. Confirm authentication: `gh auth status`
4. Confirm GitHub remote exists: `git remote -v`

## Configuration

Load `.gitissue.yml` from the repo root once at skill start. If the file does not exist, use defaults and print:

```
○ First run — using default config. Run /init-gitissue to customize.
```

Defaults: `issue.auto_normalize: true`, `issue.template: "default"`, `issue.labels_auto_suggest: true`, `issue.normalize_comment: true`

If the config file exists but contains invalid values, output the validation error from `references/error-messages.md` and stop.

Do not re-read the config at each step.

## Subagent Architecture

The issue-creator skill delegates duplicate detection to a subagent so the main agent's context stays clean and, in batch mode, duplicate checking runs in parallel with template generation.

```
Main Agent (orchestrator) — Create mode
├── Step 1: Parse Input (lightweight — stays in main agent)
├── Step 2: Classify Type and Title (lightweight — stays in main agent)
│
├── Spawn: Duplicate Detector subagent (Step 3)
│   Fetches open issues, scores proposed item(s) against them
│   In batch mode, also cross-checks items against each other
│   Returns: structured duplicate matches with confidence levels
│
├── Step 4: Generate Issue Content (main agent — uses template)
├── Step 5: Preview and Confirm (main agent — user interaction)
└── Step 6: Create Issue (main agent — gh issue create)
```

In **batch mode**, the duplicate detector checks all batch items in a single pass (including internal cross-checks), so only one subagent spawn is needed regardless of batch size.

Read `shared/agents/duplicate-detector.md` for the full duplicate detector prompt.

### Environment check

If the Agent tool is available, use the duplicate-detector subagent as described above for Step 3.
If not (e.g., Claude.ai or environments without the Agent tool), execute duplicate checking inline using the fallback instructions included in Step 3.

### Parallel execution — Batch mode

In batch mode, the duplicate detector and template generation can run in parallel since they are independent:

```
Batch mode — Step 2 completes (items classified)
    ├── Spawn duplicate-detector (Step 3)       ─┐
    └── Pre-generate template content (for S5)   ─┤  parallel
                                                  │
    Collect both results ◄────────────────────────┘
Step 4 (Approval) continues with merged data
Step 5 (Create Issues) uses pre-generated templates
```

---

## Image Upload

When the user provides one or more image paths (e.g., screenshots, photos, diagrams), upload each image to GitHub and embed it in the issue body. This happens **in addition to** reading the image for visual context extraction.

### Supported formats

PNG, JPG/JPEG, GIF, WEBP, SVG. Maximum file size: 10 MB per image (GitHub's limit).

### Upload procedure

For each image path provided:

1. **Validate the file** — confirm it exists, is a supported format, and is under 10 MB:
   ```bash
   test -f "{image_path}" && stat -f%z "{image_path}" 2>/dev/null || stat -c%s "{image_path}" 2>/dev/null
   ```

2. **Upload via GitHub API** — use the repository contents API to commit the image to `.github/issue-assets/`:
   ```bash
   # Base64-encode the image (cross-platform: try Linux -w0 flag first, fall back to macOS)
   base64_content=$(base64 -w0 < "{image_path}" 2>/dev/null || base64 < "{image_path}")

   # Generate a unique filename: timestamp + original name
   filename="$(date +%Y%m%d%H%M%S)-{original_filename}"

   # Upload via gh api and capture the download URL
   download_url=$(gh api repos/{owner}/{repo}/contents/.github/issue-assets/{filename} \
     --method PUT \
     --field message="Upload image for issue: {filename}" \
     --field content="$base64_content" \
     --jq '.content.download_url')
   ```

3. **Extract the URL** — the upload command in Step 2 already captures `download_url` via `--jq`. Verify it is non-empty before proceeding. If empty, treat as an upload failure.

4. **Build the markdown** — create an image embed for each uploaded file:
   ```markdown
   ![{original_filename}]({download_url})
   ```

### Placement in issue body

Embed uploaded images in a **Screenshots** section placed between the Description and Acceptance Criteria sections:

```markdown
## Screenshots

![screenshot-1.png](https://raw.githubusercontent.com/owner/repo/main/.github/issue-assets/20260320120000-screenshot-1.png)

![error-log.png](https://raw.githubusercontent.com/owner/repo/main/.github/issue-assets/20260320120001-error-log.png)
```

If no images are provided, omit the Screenshots section entirely.

### Multiple images

When multiple images are provided, upload each sequentially and embed all of them in the Screenshots section. Number them if the user did not provide descriptive filenames:

```markdown
## Screenshots

![Screenshot 1](url1)

![Screenshot 2](url2)
```

### Failure handling

If an image upload fails, do **not** block issue creation. Create the issue with text context only and warn:

```
⚠ Image upload failed: {filename} — {reason}
  Issue created without embedded image.
  Tip: upload the image manually via GitHub's web UI.
```

Reasons include: file not found, unsupported format, file too large (>10 MB), API error, permission denied.

If some images in a batch succeed and others fail, embed the successful ones and warn about the failures.

### Normalization mode

When normalizing an existing issue that mentions image paths or contains image URLs, preserve existing images. Do not re-upload images that are already embedded with `![...]()` syntax.

---

## Confidence Scoring System

Auto-enriched fields include a confidence level. Confidence is displayed in previews and written into the issue body.

### Levels

| Level | Criteria | Preview display | Issue body display |
|-------|----------|-----------------|-------------------|
| **high** | Explicit keywords match clearly (e.g., crash/error → bug, "add new" → feature) or requirements stated directly | `(high)` | `(high confidence)` |
| **medium** | Inferred from description context or tone | `(medium)` | `(medium confidence)` |
| **low** | Ambiguous, defaulted based on common patterns | `(needs review)` | `(needs review)` |

### Fields with Confidence

| Field | How confidence is determined |
|-------|------------------------------|
| **Type classification** | high = explicit error/crash keywords (bug) or "add"/"new" (feature); medium = inferred from description tone; low = ambiguous, defaulted |
| **Acceptance criteria** | high = directly derived from explicit requirements in description; medium = inferred from problem description; low = generic criteria from template |

---

## Mode: Create New Issue

### Step 1 — Parse Input

Extract from the description:
- Keywords: error messages, component names, file paths, function names
- Implied type: bug (broken behavior, errors, crashes), feature (new capability), improvement (enhancement to existing behavior)

### Step 2 — Classify Type and Title

**Type classification:**
- **bug** — broken behavior, errors, crashes, regressions
- **feature** — new capability, endpoint, UI element, workflow
- **improvement** — enhancement, refactoring, performance, UX polish

**Issue title conventions** (see `docs/naming-conventions.md` for the full reference):
- Use **imperative mood** (like a command): "Fix login crash on mobile" not "Login is crashing"
- Keep titles **concise, descriptive, and actionable** — under 70 characters
- Include **context** when helpful: "Fix checkout page redirect on Safari"
- The title should read as what needs to happen, not what is broken
- Optional **type prefix** for extra clarity: "Bug: App crashes on iOS login"

| Good | Bad |
|------|-----|
| Fix mobile auth redirect loop | Login is broken |
| Add dark mode toggle to settings | Dark mode |
| Refactor auth middleware for OAuth2 | Auth stuff needs updating |
| Bug: App crashes on iOS when tapping login | It doesn't work on my phone |

Assign confidence to the type classification:
- **high** — explicit crash/error/500 keywords (bug), "add new"/"create" (feature), "refactor"/"improve"/"optimize" (improvement)
- **medium** — inferred from description context (e.g., "doesn't work" → bug, "would be nice" → feature)
- **low** — ambiguous description, type defaulted based on most common pattern

### Step 3 — Check for Duplicates

#### Subagent delegation

Spawn the duplicate-detector subagent with:

```json
{
  "mode": "create",
  "items": [
    {
      "index": 1,
      "title": "{classified_title}",
      "keywords": ["{keyword1}", "{keyword2}"],
      "type": "{bug|feature|improvement}"
    }
  ],
  "repo_root": "{repo_root}"
}
```

Read `shared/agents/duplicate-detector.md` for the full prompt. The subagent returns a `duplicates` array with scored matches.

#### Fallback (no Agent tool)

If the Agent tool is not available, run inline:

```bash
gh issue list --state open --json number,title,body,labels --limit 100
```

Compare the new issue's title and key terms against existing issues.

#### Present results

If the subagent (or fallback) found potential duplicates (confidence `medium` or `high`):

```
⚠ Possible duplicate: #42 "Fix auth redirect loop"
  View: https://github.com/owner/repo/issues/42

  Continue creating? [Y/n]
```

If no duplicates found, proceed silently.

### Step 4 — Generate Issue Content

If the user provided image paths, upload them now using the **Image Upload** procedure. Collect the resulting markdown embeds for inclusion in the issue body.

Read the appropriate template from `templates/` (bug.md, feature.md, or improvement.md) and populate every section:

1. **Type** — classified type with confidence
2. **Description** — synthesized from user input, including current/expected behavior (bugs), related components, related issues
3. **Reporter Context** — user's original text, verbatim, in a blockquote
4. **Screenshots** — embedded images (only if images were provided and uploaded successfully)
5. **Acceptance Criteria** — 3-5 testable criteria derived from the problem description, with confidence levels
6. **Metadata** — suggested priority, estimated effort (XS/S/M/L/XL), suggested labels

**Note:** Issues intentionally do NOT include codebase analysis (affected files, technical notes, architecture constraints). The resolver and triage skills scan the codebase themselves when needed, against current code.

### Step 5 — Preview and Confirm

```
◆ Issue Preview
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Type:     bug (high)
  Title:    Fix mobile auth redirect loop
  Images:   2 uploaded ✓
  Labels:   bug, auth, mobile
  Criteria: 3 acceptance criteria generated (medium)

Create issue? [Y/n]
```

The `Images:` line appears only when images were provided. Show count and upload status. If some failed: `Images: 1/2 uploaded (1 failed)`.

Wait for confirmation. If declined, stop without creating.

### Step 6 — Create Issue

```bash
gh issue create --title "{title}" --body "{populated_template}" --label "{labels}"
```

The body is the fully populated template including `<!-- gitissue:normalized v1 -->` at the top.

Print a structured step-by-step summary:

```
◆ Issue Created
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Parse input:       ✓ pass
  Classify:          ✓ pass ({type})
  Duplicates:        ✓ pass (no duplicates found)
  Template:          ✓ pass
  Preview:           ✓ approved
  Create:            ✓ pass
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            DONE

  #42  {title}
  https://github.com/owner/repo/issues/42
```

If duplicates were found but user proceeded:
```
  Duplicates:        ⚠ warn ({N} potential duplicates, user overrode)
```

On failure, output the matching error from `references/error-messages.md`.

---

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

Read `shared/agents/duplicate-detector.md` for the full prompt. The subagent checks each item against existing open issues AND cross-checks items against each other in a single pass.

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

## Example: Batch from a planning document

**User says:** `/issue-creator` followed by:
```
Here are the items from our sprint planning:
1. Fix the Safari checkout redirect bug — payments fail on iOS Safari
2. Add dark mode toggle to the settings page
3. Refactor auth middleware to support OAuth2
```

1. Detect → 3 items from numbered list
2. Preview table → 3 rows with types and effort estimates
3. Duplicates → none found
4. Approval:
   ```
   ● Scanning codebase...
     Found 3 items in input

   ◆ Batch Preview
   ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
     #  │ Type        │ Title                              │ Effort
     ───┼─────────────┼────────────────────────────────────┼───────
     1  │ bug         │ Fix Safari checkout redirect        │ S
     2  │ feature     │ Add dark mode toggle                │ M
     3  │ improvement │ Refactor auth middleware for OAuth2  │ L

   Create 3 issues? [A]ll / [e]dit / [c]ancel
   ```
5. On "All" → create each → `✓ 3/3 issues created`

---

## Example: Create from a vague description

**User says:** `/issue-creator the checkout page is broken on Safari`

1. Parse → keywords: "checkout", "broken", "Safari"; type: bug
2. Classify → bug (high confidence)
3. Duplicates → none found
4. Generate → populates bug.md template with Safari-specific acceptance criteria
5. Preview:
   ```
   ◆ Issue Preview
   ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
     Type:     bug (high)
     Title:    Fix checkout page broken on Safari
     Labels:   bug, checkout
     Criteria: 3 acceptance criteria generated (medium)

   Create issue? [Y/n]
   ```
6. On confirmation → `gh issue create` → `✓ Created issue #15`

## GitHub CLI Convention

Every `gh` command for data retrieval uses `--json` with explicit field selection. Never parse text output.

- `gh issue view 42 --json number,title,body,labels,assignees,state,comments`
- `gh issue list --state open --json number,title,body,labels --limit 100`
- `gh issue create --title "..." --body "..." --label "..."`

## Terminal Output

Follow DESIGN.md symbol vocabulary and output structure for all output. Key rules:

- Symbols: `●` progress, `✓` success, `✗` failure, `◆` section header, `⚡` recommendation, `⚠` warning, `○` info, `+` added, `=` preserved
- Two-space indent for content under section headers
- Section separators: `┄` (light dash)
- URLs on their own line
- Max 80 chars wide (truncate with `...`)
- One blank line between sections
- Static sequential output — each step prints a new line, no animation

## Error Handling

All errors use the rich format from `references/error-messages.md`:

```
✗ Short error description

  To fix:  <actionable command>
  Docs:    <url> (when applicable)
```

## GitHub Projects Sync

After creating an issue (single or batch mode), sync the issue to the repo's GitHub Project board if `projects.sync_enabled` is `true` in `.gitissue.yml`. Follow the procedures in `docs/github-projects-sync.md`:

1. Discover the linked project (or use cached project ID)
2. Add the newly created issue to the project board
3. Set the Status field to `projects.status_map.todo` (default: "Todo")

```
● Syncing project board...
✓ Added to project "{project_title}" — Status: Todo
```

In batch mode, sync each issue after it is created.

If `projects.sync_enabled` is `false` (default), skip silently. If any sync step fails, print a `⚠` warning and continue — never block issue creation on project sync failure. See `docs/github-projects-sync.md` for error messages and graceful degradation details.

## Additional Resources

- **`references/error-messages.md`** — Complete error catalog with triggers and exact output
- **`docs/naming-conventions.md`** — Issue title and labeling conventions
- **`docs/github-projects-sync.md`** — Shared GitHub Projects status sync reference
- **`templates/bug.md`** — Bug report template
- **`templates/feature.md`** — Feature request template
- **`templates/improvement.md`** — Improvement template
