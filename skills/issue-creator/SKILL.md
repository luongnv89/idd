---
name: issue-creator
description: "Create structured GitHub issues from text, screenshots, or lists, or normalize existing ones. Use when asked to file, batch-create, or standardize issues; don't use for resolving, triaging, or analyzing an issue."
license: MIT
compatibility: Requires git and GitHub CLI (gh) with authentication. Run `gh auth status` to verify.
effort: medium
metadata:
  version: 0.4.1
  creator: Luong NGUYEN <luongnv89@gmail.com>
---

# /issue-creator

Create structured GitHub issues or normalize existing ones into a standard template.

## Modes

| Invocation | Mode | What happens |
|------------|------|--------------|
| `/issue-creator <text>` | Create | New structured issue from a text description |
| `/issue-creator <N>` | Normalize | Restructure existing issue #N into standard template |
| `/issue-creator <N> --dry-run` | Preview | Show normalization preview without applying |
| `/issue-creator <N> --force` | Force | Normalize even if security-labeled |
| `/issue-creator <multi-item text>` | Batch | Extract multiple issues from one input and create sequentially |

## Prerequisites

Before any operation, verify the environment. On failure, output the exact error from `references/error-messages.md` and stop.

1. Confirm git repository: `git rev-parse --git-dir`
2. Confirm `gh` is installed: `gh --version`
3. Confirm authentication: `gh auth status`
4. Confirm GitHub remote exists: `git remote -v`
5. If normalizing, confirm the target issue exists before editing it.

## Workflow

- Detect whether the user provided a new issue, a normalization target, or a batch of items.
- Preserve the user’s intent, but convert it into a consistent issue shape with clear summary, context, acceptance criteria, and next steps.
- For image or screenshot inputs, extract the visible content and incorporate it into the issue body.
- See `references/creator-runbook.md` for the mode-detection rules, image handling, and upload steps.

## When to Use

- Use this skill when the user wants a new issue, a normalized issue, or a batch of related issues captured consistently.

## Instructions

1. Detect create, normalize, or batch mode.
2. Preserve the user’s meaning while restructuring the issue.
3. Handle image or screenshot inputs by extracting the visible context.
4. Keep the output focused on tracking work, not implementing it.

## Acceptance Criteria

- [ ] The issue body is structured and readable.
- [ ] Normalization preserves the original intent.
- [ ] Batch mode separates distinct items into separate issues.

## Edge Cases

- Multiple distinct tasks in one prompt.
- Screenshot input that needs visual extraction.
- Already-normalized issues that should be left mostly intact.

## Example

```text
/issue-creator Fix login redirect after OAuth on mobile
```

Expected output: a normalized GitHub issue draft with the chosen template and metadata.
