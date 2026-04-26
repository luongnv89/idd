# Issue Resolver Runbook

This reference holds the longer pipeline and subagent details that do not need to live in the main body.

## Pipeline

1. Preflight and environment checks.
2. Research the issue and confirm it is not already fixed.
3. Synthesize implementation options and choose one.
4. Implement the fix and write tests.
5. Run QA and fix/retest until clean.
6. Deliver the PR and report results.

## Subagents

- Researcher: codebase scan and complexity assessment.
- Synthesizer: candidate implementations and tradeoffs.
- Implementer: code and tests.
- Reviewer: repeated QA cycles.

## Output

Produce a single atomic PR that closes the issue and summarize the files changed, tests run, and any remaining risks.
