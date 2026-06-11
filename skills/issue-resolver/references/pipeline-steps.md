# Pipeline Step Details

Detailed procedures for each subagent delegation in the resolve pipeline. SKILL.md keeps the contract short; this file holds the full input/output spec and inline fallback instructions.

## Step 1 — Research (codebase-researcher subagent)

### Delegation payload

```json
{
  "issue": { <issue data from Step 0> },
  "config": {
    "max_files": 30,
    "trace_depth": 3,
    "scan_timeout": 120,
    "output_format": "json"
  },
  "repo_root": "<absolute path>"
}
```

### What the researcher does

1. **Verify not already resolved** — check git history for closing commits and scan the codebase for evidence the bug is fixed.
2. **Scan codebase** — extract targets, grep/glob, read files, trace dependencies.
3. **Assess complexity** — trivial / low / medium / high / complex.
4. **Research solutions** (for high/complex) — algorithms, optimizations, design patterns, web search if needed.
5. **Analyze git history** — prior attempts, regressions, domain experts (via `git blame`).
6. **Cross-reference issues** — duplicates, blockers, related work.

### Early exit: already resolved

If the researcher returns `already_resolved: true` or `pr_in_progress: true`:

```
✓ Issue #N appears to already be resolved
  {resolution_details}

  Recommend closing the issue.
```

- Auto mode: close the issue with a comment and move on.
- Interactive mode: inform the user and stop.

### Inline fallback

If no Agent tool, execute research inline following the same phases described in `references/agents/codebase-researcher.md`.

### GitHub Projects status transition

If `projects.sync_enabled` is true, set the issue status to `status_map.in_progress` (see `references/docs/github-projects-sync.md`).

## Step 2 — Plan (synthesizer subagent)

### Delegation payload

- Issue data
- Research findings (JSON from Step 1)
- Mode: `"auto"` if auto-pilot, `"interactive"` otherwise

### Options returned

The synthesizer returns 3 options differing in scope:

1. **Minimal fix** — smallest change
2. **Balanced approach** — proper fix, reasonable scope (usually recommended)
3. **Comprehensive refactor** — addresses root cause and technical debt

### Plan selection

**Interactive, `resolve.approval_gate: auto`:** display the recommended option and proceed.

**Interactive, `resolve.approval_gate: comment-and-wait`:** present all 3:

```
◆ Implementation Options
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  [1] Minimal fix (S, Low risk)
      {summary}

  [2] Balanced refactor (M, Medium risk) ← recommended
      {summary}

  [3] Comprehensive overhaul (L, High risk)
      {summary}

Select option [1/2/3]:
```

**Auto mode:** auto-select the recommended option, no prompt.

### Inline fallback

If no Agent tool, analyze the research findings and generate the plan inline.

## Step 3 — Implement (implementer subagent)

### Delegation payload

- Issue data
- Research findings (from Step 1)
- Selected plan (the chosen option from Step 2)
- Branch name
- Naming conventions: `references/docs/naming-conventions.md`
- Max commits: `resolve.max_commits`

### What the implementer writes

1. Implementation code with atomic commits
2. Unit tests for all new/changed functions
3. Integration tests (if framework exists)
4. E2e tests (if framework exists)
5. All committed following conventional commit format

### Max commits guard

If commits exceed `resolve.max_commits`:
- Interactive: warn and ask to continue
- Auto: warn in log, continue anyway

### Inline fallback

If no Agent tool, implement inline following `references/agents/implementer.md`.

## Step 4 — QA (code-reviewer + fixer subagents)

Each cycle:

1. **Code review** — spawn a *fresh* code-reviewer subagent per cycle (see `references/agents/code-reviewer.md`) so each pass is unbiased.
2. **Run tests** — unit, integration, e2e (if present), build/compile.
3. **Evaluate results:**
   - Reviewer returns `PASS` AND all tests pass AND build succeeds → exit loop, QA passed.
   - Issues found → delegate fixes, then start next cycle.
4. **Fix issues** — spawn or re-message the fixer subagent (see `references/agents/fixer.md`) with reviewer findings and failing test/build output, passing `security_convention`: `references/docs/pre-commit-security.md`. The fixer reads affected files, applies targeted fixes, verifies them, runs the mandatory pre-commit security scan before committing (real secrets block), and commits as `fix(scope): address review feedback (#N)`. The main agent does not apply code fixes inline when the Agent tool is available.

### Loop controls

- **Max cycles:** `resolve.qa_max_cycles` (default: 5)
- **Exit on clean:** stop as soon as review passes AND tests pass
- **Exit on stagnation:** if the same issues appear in 2 consecutive cycles, stop and report

### After QA

If clean:
```
[4/5] QA           ✓ clean after {N} cycles
```

If max cycles with remaining issues:
```
[4/5] QA           ⚠ {N} issues remain after {max} cycles
```

- Interactive: show remaining issues, ask to continue.
- Auto: continue to Deliver — PR can be created with known issues noted.
