# Pipeline Step Details

Detailed procedures for each subagent delegation in the resolve pipeline. SKILL.md keeps the contract short; this file is the index — the orchestration shapes, the *Step files* table, the auto-mode table and the edge cases — and each step's full input/output spec and inline fallback lives in its own file under `references/steps/`.

## Subagent Architecture Diagram

Full shape of the orchestrator → subagent delegation described in SKILL.md
(*Subagent Architecture*):

```
Main Agent (orchestrator)
├── Step 0: Preflight (lightweight — stays in main)
│
├── Spawn: Codebase Researcher subagent (Step 1)
│   Verifies not already fixed, scans codebase, assesses complexity
│   Returns: structured findings (JSON or markdown)
│
├── Spawn: Synthesizer subagent (Step 2)
│   Proposes 3 implementation options from research
│   Returns: analysis + ranked options
│
├── Spawn: Implementer subagent (Step 3)
│   Writes code + all tests based on selected plan
│   Returns: files changed, tests written, commits
│
├── Step 4: QA (main agent orchestrates review-fix loop)
│   Spawns Code Reviewer subagent per cycle
│   Spawns/reuses Fixer subagent for blocking findings
│   Runs tests/build between cycles
│   Policy ceiling by class (≤ resolve.qa_max_cycles)
│
└── Step 5: Deliver (main agent — push + create PR + report)
```

## Orchestrating the agents

Full detail for SKILL.md *Subagent Architecture → Orchestrating the agents*, which owns
the four duties. This section carries the per-agent shapes and the audited fields.

**Required return shape, checked before the next step starts.** A step that advances on
a malformed return carries the damage forward silently, so treat the shape as the
step's completion criterion:

| Agent | Must return |
|-------|-------------|
| `codebase-researcher` | `status` and `complexity` |
| `synthesizer` | exactly one `recommended` option |
| `implementer` | commits, tests, and a reproduction for bug issues |
| `code-reviewer` / `fixer` | `result` plus the finding counts |

A missing or blocking return is the signal to stop (interactive) or to follow the step's
documented auto behavior — never to guess the missing field.

**Model/effort sizing** comes from `references/docs/agent-model-effort.md`, read from the
most-recent complexity signal and falling back to the agent's default tier. It is
advisory: a tier that cannot be honoured never blocks the step.

**Audited per step:** `complexity`, `qa_cycles`, `outcome` and `duration_s` — the four
signals the run log folds into its single line — plus the `[N/5]` tracker line the user
sees.

## Step files

Each step's full procedure lives in its own file so a run reads only the step it
is on — never the whole pipeline (issue #323). Every `(*Step N — …*)` pointer in
SKILL.md or another reference resolves here:

| Step | File | Read when |
|------|------|-----------|
| Configuration load · 0e — Workspace | `references/steps/step-0-preflight.md` | Every run, at Step 0 |
| 0h — Analysis reuse gate | `references/steps/step-0h-analysis-reuse.md` | Step 0h, unless `resolve.adaptive_effort: false` |
| 0i — Caller payload gate | `references/steps/step-0i-caller-payload.md` | Step 0i, when a caller payload is present |
| 1 — Research | `references/steps/step-1-research.md` | Before spawning the researcher |
| 2 — Plan | `references/steps/step-2-plan.md` | Before spawning the synthesizer |
| 3 — Implement | `references/steps/step-3-implement.md` | Before spawning the implementer |
| 4 — QA | `references/steps/step-4-qa.md` | Before the first review cycle |
| 5 — Deliver | `references/steps/step-5-deliver.md` | Before creating the PR |

The cross-step material — the orchestration shapes above, the auto-mode table
and the edge cases below — stays in this file.

## Auto-mode behavior by step

The per-step half of SKILL.md *Auto-Pilot Mode*, which owns the cross-cutting
invariants (environment, workspace, deliver, no prompts). Under `--auto` /
`IDD_AUTO_MODE=1` no step ever waits for a person:

| Step | Auto behavior |
|------|---------------|
| *0c* — Guards | Skip the assignment guard; log blocking labels as warnings and continue. |
| *0d* — Auto-normalize | A security-labelled issue prints the skip warning and continues **without** rewriting the body — no operator confirmation is sought. |
| *0e* — Workspace | The offer never appears. |
| *0g* — Complexity gate | Still runs: it reads the pre-work `Effort` band, which needs no prompt. |
| *Step 1* — Research | An already-resolved issue is closed with a comment and the run exits cleanly. |
| *Step 2* — Plan | Auto-select the recommended option; the design-confirm checkpoint never fires. |
| *Step 3* — Implement | Continue past the max-commits guard with a warning. Never prompt for skills: internal agents only, unless `resolve.borrow_skills` is `true`, in which case the auto-selected set is borrowed without asking. |
| *Step 4* — QA | Run the cycles autonomously; on stagnation, deliver with the known issues recorded rather than stopping. |
| *Step 5* — Deliver | Create the PR; never merge. |

Every terminal outcome — success, `already_resolved`, or `failed` — still runs the
borrow teardown in *Step 3 — Propose relevant skills*.

## Edge Cases <!-- a:rs-edge-cases -->

Full behavior for the edge cases named in SKILL.md.

### No acceptance criteria
PR body notes: `> **Note:** No acceptance criteria defined — manual review recommended.`

### Issue body is empty
- Interactive: warn and ask to continue
- Auto: warn in log, continue with title-only context

### Large issues (20+ files estimated)
- Interactive: warn and ask
- Auto: warn in log, continue

### Tests fail or timeout
- PR is not created. The Verify step stops with the failing test output and a resume hint.

### Branch already exists
- Interactive: `continue` or `fresh` prompt.
- Auto: resume from the existing branch.
