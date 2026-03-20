---
name: create-issue
description: This skill should be used when creating structured GitHub issues from text descriptions, normalizing existing unstructured issues with codebase context, or batch-creating issues from documents. Trigger phrases include "create issue", "create-issue", "file a bug", "normalize issue", "enrich issue", "structure this issue". Scans the codebase to identify affected files, classifies issue type, generates acceptance criteria, and produces GitHub-ready structured issues via gh CLI.
---

# /create-issue

Create structured, codebase-aware GitHub issues — or normalize existing ones with codebase context.

## Modes

| Invocation | Mode | Description |
|------------|------|-------------|
| `/create-issue <text>` | **Create** | Create a new structured issue from a text description |
| `/create-issue <N>` | **Normalize** | Enrich existing issue #N with codebase context |
| `/create-issue <N> --dry-run` | **Preview** | Preview normalization without applying |
| `/create-issue <N> --force` | **Force** | Normalize even if security-labeled |

Detect mode by checking whether the argument is a number (normalize) or text (create).

**Image/screenshot input**: If the user provides an image path or screenshot, read the image using the Read tool to extract visual context, then treat the extracted text as the input description. Combine visual observations with any text the user provides.

## Prerequisites Check

Before any operation, verify the environment. On failure, output the exact error from `references/error-messages.md` and stop.

1. Confirm this is a git repository: `git rev-parse --git-dir`
2. Confirm `gh` is installed: `which gh`
3. Confirm authentication: `gh auth status`
4. Confirm GitHub remote exists: `git remote -v`

## Configuration

Load `.gitissue.yml` from the repo root ONCE at the start. If the file does not exist, use all defaults and output:

```
○ First run — using default config. Run /init-gitissue to customize.
```

Default values:
- `issue.auto_normalize`: true
- `issue.template`: "default"
- `issue.labels_auto_suggest`: true
- `issue.normalize_comment`: true

Read the config file if it exists. Do not re-read it at each step.

---

## Mode: Create New Issue

### Step 1 — Parse Input

Extract from the user's text description:
- Keywords (error messages, component names, file paths, function names)
- Implied issue type (bug if describing broken behavior; feature if describing new capability; improvement if describing existing behavior to change)
- Any mentioned file paths or code references

### Step 2 — Scan Codebase

Use the keywords extracted in Step 1 to search the codebase:

1. Use Grep to search for error messages, function names, and component names mentioned in the description
2. Use Glob to find files matching mentioned paths or component names
3. Read the most relevant files (max 10) to understand context

For each matched file, assign a confidence level:
- **high** — file path or function name explicitly mentioned in the description, or file contains the exact error message
- **medium** — file matches a keyword or component name from the description
- **low** — file is in a related module but not directly mentioned (mark as `(needs review)`)

If no files are found:
```
⚠ Could not identify affected files. Issue created with manual-review flag.
  Tip: mention specific filenames or error messages for better results.
```

### Step 3 — Classify Type

Determine issue type based on the description content:
- **bug** — describes broken behavior, errors, crashes, regressions, unexpected results
- **feature** — describes new capability, new endpoint, new UI element, new workflow
- **improvement** — describes enhancement to existing behavior, refactoring, performance, UX polish

### Step 4 — Check for Duplicates

Search for similar open issues:

```bash
gh issue list --state open --json number,title,body --limit 50
```

Compare the new issue's title and key terms against existing issues. If a potential duplicate is found, warn:

```
⚠ Possible duplicate: #N "{title}"
  View: https://github.com/{owner}/{repo}/issues/N

  Continue creating? [Y/n]
```

### Step 5 — Generate Issue Content

Select the appropriate template from `templates/` based on the classified type (bug.md, feature.md, or improvement.md).

Populate each template section:

1. **Type** — the classified type
2. **Context** — affected files with confidence levels, current behavior (for bugs), related components, related issues
3. **Description** — synthesized from the user's input, enriched with codebase context
4. **Reporter Context** — the user's original text, verbatim, in a blockquote
5. **Acceptance Criteria** — generate 3-5 testable criteria based on the described problem and codebase context
6. **Technical Notes** — architecture constraints from reading affected files, test coverage status, breaking change risk assessment
7. **Metadata** — suggested priority, estimated effort (XS/S/M/L/XL), suggested labels

### Step 6 — Preview and Confirm

Output the issue preview following DESIGN.md format:

```
● Scanning codebase...
  Found {N} relevant files

◆ Issue Preview
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
Type:     {type}
Title:    {title}
Files:    {file1}, {file2}, {file3}
Labels:   {label1}, {label2}
Criteria: {N} acceptance criteria generated

Create issue? [Y/n]
```

Wait for user confirmation before proceeding. If the user declines, stop without creating the issue.

### Step 7 — Create Issue

Create the issue via GitHub CLI:

```bash
gh issue create --title "{title}" --body "{populated_template}" --label "{label1},{label2}"
```

IMPORTANT: Use `gh issue create` with explicit flags. The body must be the fully populated template content including the `<!-- gitissue:normalized v1 -->` marker at the top.

Output the result:

```
✓ Created issue #{number}
  https://github.com/{owner}/{repo}/issues/{number}
```

If creation fails, output the appropriate error from `references/error-messages.md`.

---

## Mode: Normalize Existing Issue

### Step 1 — Fetch Issue

```bash
gh issue view {N} --json number,title,body,labels,assignees,state,comments
```

If the issue is not found, output:
```
✗ Issue #{N} not found

  To fix:  gh issue list
  Check:   is this the right repository?
```

### Step 2 — Check Already Normalized

Search the issue body for the normalization marker: `<!-- gitissue:normalized v1 -->`

If found:
```
✓ Issue #{N} is already normalized (v1, {date}). No changes needed.
```
Where `{date}` is today's date in YYYY-MM-DD format. Stop here.

IMPORTANT: Only check for the marker as a standalone HTML comment. If the text `<!-- gitissue:normalized v1 -->` appears inside a code block or as quoted text, it is NOT a normalization marker — proceed with normalization.

### Step 3 — Check Issue State

Check if the issue is locked or in a state that prevents editing:

If the issue state indicates it is locked:
```
✗ Issue #{N} is locked

  To fix:  unlock the issue in GitHub's web UI, then retry
```
Stop here.

If the issue body exceeds 60,000 characters, note this for Step 5 — technical notes and low-priority sections will be truncated to keep the normalized body under GitHub's 65KB limit.

### Step 4 — Security Label Check

Check issue labels against security keywords: `security`, `CVE`, `vulnerability` (case-insensitive).

If a security label is found and `--force` was NOT used:
```
⚠ Issue #{N} has a security label ({label_name}). Skipping normalization.
  Codebase context could reveal exploit details.

  To override: /create-issue {N} --force
```
Stop here.

### Step 5 — Scan Codebase for Context

Extract keywords from the existing issue title and body:
- Error messages, stack traces, file paths, function names, component names
- Use the same scanning approach as Create mode (Grep + Glob + Read)

Assign confidence levels to each discovered file.

### Step 6 — Generate Normalization Content

Using the appropriate template (classify type from existing issue content):

1. Preserve the ENTIRE original issue body in the `> **Reporter Context**` blockquote
2. Fill in all template sections with codebase-enriched data
3. Add the `<!-- gitissue:normalized v1 -->` marker at the top
4. If the original body exceeds 60,000 characters (noted in Step 3), truncate Technical Notes and Metadata sections to keep total body under 65KB

### Step 7 — Preview with Confidence Scores

Output the normalization preview:

```
● Fetching issue #{N}...
● Scanning codebase for context...

◆ Normalization Preview
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
+ Type:        {type} (high confidence)
+ Files:       {file1} (high), {file2} (medium)
+ Criteria:    {N} acceptance criteria (medium)
+ Labels:      +{label1}, +{label2}
= Original:    preserved in Reporter Context block

Apply normalization? [Y/n/dry-run]
```

The `+` prefix indicates added fields. The `=` prefix indicates preserved fields.

Confidence format: use `(high confidence)` for the Type field, use abbreviated `(high)`, `(medium)`, `(low)` for files and criteria. Mark low-confidence fields with `(needs review)` in the issue body.

Wait for user confirmation. If the user selects `n`, stop. If the user selects `dry-run`, proceed as dry-run.

### Step 8 — Dry Run Check

If `--dry-run` was specified or user selected dry-run at the prompt, stop after the preview:
```
○ Dry run complete. No changes applied.
```

### Step 9 — Backup Original Body

CRITICAL: Before editing the issue body, post a backup comment containing the original body. This is a data safety requirement — if the backup fails, abort normalization entirely.

```bash
gh issue comment {N} --body "<details><summary>Original issue body (backup by gitissue)</summary>

{original_body}

</details>"
```

Verify the comment was posted by checking the command exit code.

If backup fails:
```
✗ Failed to post backup comment for issue #{N}

  Normalization aborted — original issue body is unchanged.
  To fix:  check your permissions: gh issue comment {N} --body "test"
```
Stop here. Do NOT proceed to edit the issue body.

### Step 10 — Update Issue Body

Only after backup is verified:

```bash
gh issue edit {N} --body "{normalized_body}"
```

### Step 11 — Post Normalization Comment

If `issue.normalize_comment` is true in config:

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
✓ Backup posted (comment #{comment_id})
✓ Issue #{N} normalized
  https://github.com/{owner}/{repo}/issues/{N}
```

---

## Terminal Output Rules

Follow these rules from DESIGN.md for ALL output:

1. **Symbols**: `● ` in progress, `✓ ` success, `✗ ` failure, `◆ ` section header, `⚡` action/recommendation, `⚠ ` warning, `○ ` info
2. **Indentation**: two-space indent for content under headers
3. **Section separator**: `┄` (light dash, not heavy box)
4. **URLs**: always on their own line
5. **Tables**: box-drawing characters `│ ─ ┼`, right-align numbers, left-align text
6. **Max width**: 80 characters (truncate with `...` if needed)
7. **Empty cells**: use `—` (not blank)
8. **One blank line** between sections
9. **No trailing blank lines**
10. **Static sequential output** — each step prints a new line, no terminal animation

## Error Handling

For ALL errors, use the rich error format. Reference `references/error-messages.md` for the exact messages. The format is always:

```
✗ Short error description

  To fix:  <actionable command>
  Docs:    <url> (when applicable)
```

## GitHub CLI Convention

CRITICAL: Every `gh` command MUST use `--json` with explicit field selection for data retrieval. Never parse text output.

Examples:
- `gh issue view 42 --json number,title,body,labels,assignees,state,comments`
- `gh issue list --state open --json number,title,body --limit 50`
- `gh issue create --title "..." --body "..." --label "..."`

## Additional Resources

### Reference Files
- **`references/error-messages.md`** — Complete error message catalog with triggers and exact output format

### Templates
- **`templates/bug.md`** — Bug report template
- **`templates/feature.md`** — Feature request template
- **`templates/improvement.md`** — Improvement template
