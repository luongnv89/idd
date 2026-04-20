---
name: review-fix-loop
description: Redirect the user to /issue-pr-review — this skill is deprecated and replaced by issue-pr-review with CI monitoring and auto-merge. Use when asked to "review and fix", "review fix loop", "auto-review my PR", or "polish this branch".
license: MIT
compatibility: Requires /issue-pr-review skill.
effort: low
metadata:
  version: 0.3.0
  creator: Luong NGUYEN <luongnv89@gmail.com>
---

# /review-fix-loop — DEPRECATED

This skill has been replaced by `/issue-pr-review`, which provides the same review-fix cycle plus:
- CI status monitoring
- End-to-end test execution
- Auto-merge in auto-pilot mode
- Structured summary reports

## What to do

Run `/issue-pr-review` instead:

```
/issue-pr-review           # auto-detect PR for current branch
/issue-pr-review <N>       # review specific PR
/issue-pr-review --auto    # full autonomous mode with auto-merge
```

When this skill is triggered, immediately redirect to `/issue-pr-review` with the same arguments.
