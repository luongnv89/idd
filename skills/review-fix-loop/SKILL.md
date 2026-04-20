---
name: review-fix-loop
description: "Review a PR by delegating to /issue-pr-review — this skill is deprecated and forwards all invocations to the replacement, which adds CI monitoring and auto-merge. Use when asked to review and fix, review fix loop, or auto-review my PR. Don't use for new projects — prefer /issue-pr-review directly, or /issue-pr-review-fix-loop for outer-loop iteration."
license: MIT
compatibility: Requires /issue-pr-review skill.
effort: low
metadata:
  version: 0.3.1
  creator: Luong NGUYEN <luongnv89@gmail.com>
---

# /review-fix-loop — DEPRECATED

This skill is replaced by `/issue-pr-review`, which provides the same review-fix cycle plus CI status monitoring, end-to-end test execution, auto-merge in auto-pilot mode, and structured summary reports.

## When to Use

- **Do** forward to `/issue-pr-review` whenever this skill is invoked.
- **Do** preserve the user's exact arguments when forwarding.
- **Avoid** implementing any review logic here — it all lives in `/issue-pr-review`.
- **Never** edit repository files, create commits, or call `gh` from this skill directly.

## Instructions

1. Read the arguments passed to `/review-fix-loop`.
2. Print the deprecation notice (see Example).
3. Invoke `/issue-pr-review` with the same arguments verbatim. Hand off control.

## Prerequisites

- `/issue-pr-review` installed at `skills/issue-pr-review/SKILL.md`.
- `gh` authenticated — the target skill requires GitHub CLI access.

## Example

**User types:** `/review-fix-loop 42`

**Output:**

```
  ○ /review-fix-loop is deprecated — forwarding to /issue-pr-review 42
```

The forwarded skill then runs the normal review cycle.

## Expected Output

One line of output from this skill:

```
  ○ /review-fix-loop is deprecated — forwarding to /issue-pr-review{args}
```

After that, all further output comes from `/issue-pr-review`.

## Edge Cases

- **No arguments** — forward with no arguments so `/issue-pr-review` can auto-detect the current branch's PR.
- **`--auto` flag** — forward verbatim; auto-pilot mode is handled by `/issue-pr-review`.
- **`/issue-pr-review` missing** — print `✗ /issue-pr-review not installed — install it from skills/issue-pr-review/SKILL.md`, then stop.

## Error Handling

- If `/issue-pr-review` fails to start (missing skill, not a git repo, `gh` not authenticated), print the exact error from the target skill and stop — do not attempt to retry or fall back to an inline loop.
- If the user's arguments are malformed (e.g., `/review-fix-loop banana`), pass them through anyway; `/issue-pr-review` will surface a validation error in its own format.
- Ask the user to confirm before running the forwarded skill **only** if the command includes destructive flags the user may not intend — otherwise forward immediately.

## Additional Resources

- See `skills/issue-pr-review/SKILL.md` — the replacement skill; all review-fix logic lives there.
- See `skills/issue-pr-review/references/error-messages.md` — error catalog the forwarded skill uses.
