# Issue PR Review Fix Loop Runbook

This reference keeps the outer-loop rules and cycle notes out of `SKILL.md`.

## Core Loop

1. Run `/issue-pr-review --review-only`.
2. Apply the highest-priority fixes.
3. Commit and push the changes.
4. Repeat until no blocking issues remain.
5. Run a final confirmation pass.

## Output

Report the cycles completed, issues fixed, and whether the PR is ready to merge.
