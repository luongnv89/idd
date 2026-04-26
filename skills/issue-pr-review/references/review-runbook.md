# Issue PR Review Runbook

This reference keeps the longer review-fix cycle rules and CI notes out of `SKILL.md`.

## Core Loop

1. Review the PR in read-only mode.
2. Run tests or lint when needed.
3. Fix the highest-signal issues first.
4. Repeat for up to three cycles.
5. Run a confirmation pass before merging.

## Output

Report findings, the files changed, the tests run, and whether the PR is ready to merge.
