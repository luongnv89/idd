# Orchestration: why subagents, and the main agent's job

SKILL.md → *Context Window Management* states the principle (the main agent is a
lightweight orchestrator that delegates heavy work and never reads code, diffs,
or test output). This file expands the rationale and the main-agent task list.

## Why subagents matter

- **Fresh context per issue** — The resolver subagent reads 10-20 files, traces dependencies, writes code and tests. That's thousands of lines that would permanently consume the main agent's context. As a subagent, it all gets discarded after returning the result.
- **Independent review** — The reviewer subagent has no memory of how the code was written. It reads the diff with fresh eyes, which produces better reviews than self-reviewing.
- **Isolation between iterations** — Issue #1's codebase details don't interfere with issue #3's research. Each subagent starts clean.

## What the main agent does

The main agent handles only orchestration tasks that are lightweight and sequential:

1. **Prerequisites** — environment checks (git, gh, auth)
2. **Triage/Pick** — fetch issue list, compute order (or walk explicit list)
3. **Spawn resolver subagent** — pass issue number, wait for result
4. **Spawn PR review subagent** — delegates to `/issue-pr-review --auto --no-merge` which handles review, test, CI, and fix (never merge — merge is Phase 5's job)
5. **Merge** — apply the mode gate and dependency gate (SPEC §2), then squash-merge via `gh pr merge`
6. **Track results** — append to the iteration log
7. **Loop** — advance to next issue

The main agent should never: read source files, read PR diffs, run tests, or
write code. All of that happens inside subagents.

## Subagent architecture

Each iteration spawns up to 2 subagents. The main agent only tracks: issue
number, title, branch name, PR number, and pass/fail status. In explicit list
mode, an additional analyzer subagent runs once upfront before the loop begins.

```
Main Agent (orchestrator)
  │
  ├── Subagent: Analyzer (explicit list mode only, runs once)
  │     Analyzes all issues, finds dependencies and batch opportunities
  │     Returns: optimized_order, batches, dependencies
  │
  ├── Subagent: Resolver (or Batch Resolver for batched issues)
  │     Runs the full /issue-resolver 6-step pipeline (Preflight → Research → Plan → Implement → QA → Deliver)
  │     Returns: branch_name, pr_number, files_changed, tests_written, tests_passed
  │
  └── Subagent: PR Reviewer (via /issue-pr-review --auto --no-merge)
        Script pre-pass (lint/format auto-fix), then LLM review cycles (max 3)
        Returns: PASS/NEEDS_FIX, review_cycles, issues_found, issues_fixed
        Note: --no-merge suppresses auto-merge; merge is Phase 5's job
```
