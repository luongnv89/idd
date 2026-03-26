---
name: review-fix-loop
description: "DEPRECATED: Use /issue-pr-review instead. This skill redirects to issue-pr-review which adds CI status monitoring and auto-merge capabilities on top of the original review-fix-loop functionality. Triggers on: \"review and fix\", \"review fix loop\", \"auto-review my PR\", \"fix review issues\", \"clean up this PR\", \"review until clean\", \"polish this branch\", \"make this PR ready\"."
effort: low
license: MIT
metadata:
  version: 0.2.0
  creator: Luong NGUYEN <luongnv89@gmail.com>
compatibility: Requires /issue-pr-review skill.
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
