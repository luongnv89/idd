---
name: create-issue
description: Create structured GitHub issues from text, screenshots, or images, and normalize existing unstructured issues with codebase context. Use this skill whenever someone says "create issue", "file a bug", "report a feature request", "normalize issue", "enrich issue", "structure this issue", "/create-issue", or describes a bug, feature, or improvement they want tracked. Also use when someone shares an issue number and wants it cleaned up or enriched, or when pasting a screenshot of a bug. Even if the user just describes a problem without saying "issue", this skill turns it into a structured, codebase-aware GitHub issue with affected files, acceptance criteria, and labels via gh CLI.
---

# /create-issue

Create structured, codebase-aware GitHub issues — or normalize existing ones with codebase context.

Two modes: **Create** (new issue from text/image) and **Normalize** (enrich existing issue #N).

## Modes

| Invocation | Mode | What happens |
|------------|------|--------------|
| `/create-issue <text>` | Create | New structured issue from a text description |
| `/create-issue <N>` | Normalize | Enrich existing issue #N with codebase context |
| `/create-issue <N> --dry-run` | Preview | Show normalization preview without applying |
| `/create-issue <N> --force` | Force | Normalize even if security-labeled |

Detect mode: if the argument is a number → Normalize. If text → Create.

**Image/screenshot input**: When the user provides an image path or screenshot, read the image with the Read tool to extract visual context, then treat extracted information as the input description. Combine visual observations with any accompanying text.

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

Do not re-read the config at each step.

---

## Mode: Create New Issue

### Step 1 — Parse Input

Extract from the description:
- Keywords: error messages, component names, file paths, function names
- Implied type: bug (broken behavior, errors, crashes), feature (new capability), improvement (enhancement to existing behavior)
- Any explicitly mentioned file paths or code references

### Step 2 — Scan Codebase

Search the codebase using extracted keywords:

1. Grep for error messages, function names, and component names
2. Glob for files matching mentioned paths or component names
3. Read the most relevant files (max 10) to understand context

Assign confidence to each matched file:
- **high** — file path or function explicitly mentioned, or file contains the exact error message
- **medium** — matches a keyword or component name from the description
- **low** — related module but not directly mentioned → mark `(needs review)` in the issue body

If no files found:
```
⚠ Could not identify affected files. Issue created with manual-review flag.
  Tip: mention specific filenames or error messages for better results.
```

### Step 3 — Classify Type

- **bug** — broken behavior, errors, crashes, regressions
- **feature** — new capability, endpoint, UI element, workflow
- **improvement** — enhancement, refactoring, performance, UX polish

### Step 4 — Check for Duplicates

```bash
gh issue list --state open --json number,title,body --limit 50
```

Compare the new issue's title and key terms against existing issues. If a potential duplicate exists:

```
⚠ Possible duplicate: #42 "Fix auth redirect loop"
  View: https://github.com/owner/repo/issues/42

  Continue creating? [Y/n]
```

### Step 5 — Generate Issue Content

Read the appropriate template from `templates/` (bug.md, feature.md, or improvement.md) and populate every section:

1. **Type** — classified type
2. **Context** — affected files with confidence levels, current behavior (bugs), related components, related issues
3. **Description** — synthesized from user input, enriched with codebase context
4. **Reporter Context** — user's original text, verbatim, in a blockquote
5. **Acceptance Criteria** — 3-5 testable criteria based on the problem and codebase context
6. **Technical Notes** — architecture constraints from reading affected files, test coverage status, breaking change risk
7. **Metadata** — suggested priority, estimated effort (XS/S/M/L/XL), suggested labels

### Step 6 — Preview and Confirm

```
● Scanning codebase...
  Found 3 relevant files

◆ Issue Preview
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Type:     bug
  Title:    Fix mobile auth redirect loop
  Files:    auth.py (high), middleware.py (high), config.py (medium)
  Labels:   bug, auth, mobile
  Criteria: 3 acceptance criteria generated

Create issue? [Y/n]
```

Wait for confirmation. If declined, stop without creating.

### Step 7 — Create Issue

```bash
gh issue create --title "{title}" --body "{populated_template}" --label "{labels}"
```

The body is the fully populated template including `<!-- gitissue:normalized v1 -->` at the top.

```
✓ Created issue #42
  https://github.com/owner/repo/issues/42
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

If the issue body exceeds 60,000 characters, note this — Technical Notes and Metadata will be truncated in Step 6 to stay under GitHub's 65KB limit.

### Step 4 — Security Label Check

Check labels for: `security`, `CVE`, `vulnerability` (case-insensitive).

If found and `--force` not used:
```
⚠ Issue #42 has a security label (security). Skipping normalization.
  Codebase context could reveal exploit details.

  To override: /create-issue 42 --force
```
Stop.

### Step 5 — Scan Codebase for Context

Extract keywords from the existing issue title and body — error messages, stack traces, file paths, function names, component names. Use the same Grep + Glob + Read approach as Create mode. Assign confidence levels.

### Step 6 — Generate Normalization Content

Classify type from the existing issue content, then use the matching template:

1. Preserve the entire original issue body in `> **Reporter Context**` blockquote
2. Fill all template sections with codebase-enriched data
3. Place `<!-- gitissue:normalized v1 -->` at the top
4. If original body > 60K chars, truncate Technical Notes and Metadata to fit under 65KB

### Step 7 — Preview with Confidence Scores

```
● Fetching issue #42...
● Scanning codebase for context...

◆ Normalization Preview
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  + Type:        bug (high confidence)
  + Files:       auth.py (high), config.py (medium)
  + Criteria:    3 acceptance criteria (medium)
  + Labels:      +bug, +auth
  = Original:    preserved in Reporter Context block

Apply normalization? [Y/n/dry-run]
```

`+` = added field, `=` = preserved field. Use `(high confidence)` for Type, abbreviated `(high)`, `(medium)`, `(low)` for files/criteria. Low-confidence fields get `(needs review)` in the issue body.

Wait for confirmation. `n` → stop. `dry-run` → proceed to Step 8.

### Step 8 — Dry Run Check

If `--dry-run` was specified or selected at the prompt:
```
○ Dry run complete. No changes applied.
```
Stop.

### Step 9 — Backup Original Body

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

### Step 10 — Update Issue Body

```bash
gh issue edit {N} --body "{normalized_body}"
```

### Step 11 — Post Normalization Comment

If `issue.normalize_comment` is true:

```bash
gh issue comment {N} --body "🔧 **Normalized by gitissue**

Added: type classification, affected files, acceptance criteria, technical notes.
Original body preserved in Reporter Context block and backup comment above."
```

### Step 12 — Apply Labels

If `issue.labels_auto_suggest` is true and new labels were suggested:

```bash
gh issue edit {N} --add-label "{label1},{label2}"
```

### Step 13 — Report

```
✓ Backup posted (comment #5)
✓ Issue #42 normalized
  https://github.com/owner/repo/issues/42
```

---

## Example: Create from a vague description

**User says:** `/create-issue the checkout page is broken on Safari`

1. Parse → keywords: "checkout", "broken", "Safari"; type: bug
2. Scan → Grep finds `src/checkout/payment.js` mentions "Safari", Glob finds `src/checkout/` directory
3. Classify → bug
4. Duplicates → none found
5. Generate → populates bug.md template with affected files, Safari-specific acceptance criteria
6. Preview:
   ```
   ● Scanning codebase...
     Found 2 relevant files

   ◆ Issue Preview
   ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
     Type:     bug
     Title:    Fix checkout page broken on Safari
     Files:    src/checkout/payment.js (high), src/checkout/cart.js (medium)
     Labels:   bug, checkout
     Criteria: 3 acceptance criteria generated

   Create issue? [Y/n]
   ```
7. On confirmation → `gh issue create` → `✓ Created issue #15`

## GitHub CLI Convention

Every `gh` command for data retrieval uses `--json` with explicit field selection. Never parse text output.

- `gh issue view 42 --json number,title,body,labels,assignees,state,comments`
- `gh issue list --state open --json number,title,body --limit 50`
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

## Additional Resources

- **`references/error-messages.md`** — Complete error catalog with triggers and exact output
- **`templates/bug.md`** — Bug report template
- **`templates/feature.md`** — Feature request template
- **`templates/improvement.md`** — Improvement template
