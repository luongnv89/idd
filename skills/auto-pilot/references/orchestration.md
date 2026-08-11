# Orchestration: why subagents, and the main agent's job

SKILL.md → *Context Window Management* states the principle (the main agent is a
lightweight orchestrator that delegates heavy work and never reads code, diffs,
or test output). This file expands the rationale, ownership boundary, and
main-agent task list.

## Why subagents matter

- **Fresh context per issue** — A resolver reads 10–20 files, traces dependencies,
  writes code and tests, then returns only structured telemetry.
- **Independent review** — The reviewer has no memory of how the code was written.
- **Isolation between issues** — Each resolver starts clean; when
  `autopilot.max_parallel > 1`, each one also gets its own git worktree and index.

## What the main agent does

The main agent handles lightweight orchestration only:

1. **Prerequisites** — environment checks, run lock, config validation
2. **Triage/Pick** — reuse or produce one triage graph and apply live eligibility
3. **Plan lanes** — with `max_parallel > 1`, choose up to the bound from one
   persisted `summary.parallel_groups` entry and checkpoint every lane as
   `planned`; never combine members from different groups in one fan-out
4. **Prepare worktrees** — derive each branch with `gi-branch.py --from-issue`,
   create a distinct sibling worktree from the same fetched base, copy detected
   local setup, and checkpoint it as `resolve`
5. **Spawn resolver subagents** — concurrently only for those prepared lanes;
   every worker runs `/issue-resolver --auto --no-run-log` with
   `IDD_CALLER_WORKTREE=1`
6. **Fan in** — wait for every started resolver and checkpoint each returned
   result without cancelling successful siblings when another lane fails
7. **Drain serially** — in original triage order, copy one returned lane into
   `current`, run `/issue-pr-review --auto --no-merge`, apply dependency/mode/CI
   gates, merge at most one PR at a time, append exactly one run-log line, update
   run state and triage cache, then remove that lane's worktree
8. **Loop** — clear the completed lane batch and pick again

The main agent never reads source files or PR diffs, runs tests, or writes code.
The only concurrent stage is resolver execution. Review, fixes, CI decisions,
merge, `.gitissue/runs.jsonl`, `.gitissue/run-state.json`,
`.gitissue/triage.json`, issue labels, and worktree cleanup have one writer: the
main agent's serialized drain.

## Compatibility branch (`max_parallel = 1`)

Value `1` is an explicit early branch, not a one-element use of the new
scheduler. It runs the legacy sequence byte-for-byte: pick one issue, sync the
original checkout, spawn the ordinary in-place resolver prompt, wait, review,
merge, log, checkpoint, update the cache, and loop. It creates no caller-managed
worktree, writes no `lanes[]` entries, and sets no `IDD_CALLER_WORKTREE`.

## Subagent architecture

In explicit-list mode the analyzer still runs once before the loop. The ordinary
path remains one resolver followed by one reviewer. The parallel path is bounded
fan-out/fan-in followed by a serialized drain:

```
Main Agent (single orchestrator / shared-state writer)
  │
  ├── Analyzer (explicit list mode only, once)
  │
  ├── max_parallel = 1
  │     Resolver (in-place) → Reviewer → Merge/log/cache/cleanup
  │
  └── max_parallel > 1, one independent triage group
        ├── Worktree A → Resolver A ─┐
        ├── Worktree B → Resolver B ─┼── fan-in
        └── Worktree N → Resolver N ─┘
                                     │
                                     └── serialized drain in triage order
                                           Reviewer A → Merge/log/cache A
                                           Reviewer B → Merge/log/cache B
                                           Reviewer N → Merge/log/cache N
```

Resolver workers return branch, PR, tests, QA, complexity, profile, and duration.
They never merge and never append a run-log line. Reviewer workers run only after
fan-in and one at a time; `--no-merge` preserves Phase 5 as the sole merge site.

## Failure and resume ownership

- A worktree setup failure fails that lane. It never falls back to the original
  checkout while siblings are active.
- A resolver failure does not cancel returned siblings. Its terminal telemetry is
  handled when that lane reaches the serialized drain.
- `run-state.json.lanes[]` persists the lane phases `planned`, `resolve`,
  `returned`, `review`, `fix`, `merge`, `cleanup`, `completed`, and `failed`.
  The existing singleton `current` remains the compatibility seam for the one
  lane currently draining.
- On `--resume`, reconcile every lane against GitHub and git before acting:
  validate its conventional branch, locate an open PR for it, and resume at the
  earliest safe phase. Any doubt re-runs or re-checks work; it never assumes a
  merge, a run-log append, or a completed cleanup.
