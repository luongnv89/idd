# Review Loop Mechanics — Agent Reuse

Exact spawn calls and the token-trade rationale for the reviewer/fixer agents used in Step 3 and the Review Loop of `/issue-pr-review`. SKILL.md keeps the summary (cold start → SendMessage re-review → fresh confirmation); this file holds the detail.

## Depth gate (adaptive review depth)

The Step 1 *Depth gate* selects a review `profile` — `light` or `full` — from a
pre-work complexity signal, so a trivial PR is not reviewed as deeply as a
multi-subsystem one. The mechanism and the shared `XS … XL` scale live in
`references/docs/agent-model-effort.md` (*Complexity → pipeline profile*); this section is
only how the review loop consumes the result.

**Selecting the signal (no researcher here).** Unlike `/issue-resolver`,
`/issue-pr-review` has no research subagent, so it derives the signal from data
already fetched in Step 1 and takes the **fuller** of any inputs that disagree:

- **Diff size / files-changed** (`gh pr view {N} --json files`) — small change
  (≈ ≤ 15 changed lines in 1 file) leans `light`.
- **Linked-issue `Effort` band** — when the PR body has `Closes #N`, read that
  issue's `## Metadata` `Effort` (`gh issue view {N} --json body`); `XS`/`S`
  asserted leans `light`, `M`/`L`/`XL` or low-confidence leans `full`.
- **Security label** — any `security`/`CVE`/`vulnerability` label forces `full`.

Resolve to `light` **only when every available signal agrees on trivial**; any
`full` vote, or a missing/ambiguous signal, wins → `full`. When
`review.adaptive_depth` is `false`, the gate is skipped and `profile = full`.

**What `light` changes in the loop:**

| Aspect | `full` (default) | `light` |
|--------|------------------|---------|
| Review-fix cycle cap | `review.max_cycles` (3) | **1** |
| Optional browser UI review | runs when opted in + reachable | skipped |
| Code UI review (auto-detected) | runs when UI work present | runs when UI work present (unchanged) |
| AC + traceability hard-blocks | full strength | **full strength (unchanged)** |
| Reviewer spawn | yes | yes (depth reduced, never skipped) |

The `light` cap of 1 is a **ceiling that wins** — it is the effective cycle limit
regardless of the configured value, i.e. `min(1, configured_cap)`. This matters
under `/auto-pilot`, which overrides `review.max_cycles` with its `review_cycles`
value (default 3): on the `light` path the effective cap is still **1**, never the
overridden 3. The cap governs **only** the loop iteration count; the cold-start
reviewer, the fixer, and the fresh confirmation pass below all still apply — a
`light` review is one review pass + at most one fix + confirmation, not a skipped
review. The two #36 hard-blocks (`acceptance_criteria: fail`, missing
`Closes #N`) are never relaxed by the profile — a trivial PR that fails them still
blocks soft-pass and does not merge.

## Why reuse the reviewer

To minimize token usage, the review loop **reuses the same reviewer agent** across fix cycles instead of spawning a fresh one each time. The reviewer already has the codebase context loaded, so subsequent reviews are cheaper.

- **Cycle 1:** Spawn a new reviewer agent (cold start — reads diff, files, context).
- **Cycles 2-3:** Send the reviewer a follow-up message via `SendMessage` asking it to re-review the diff after fixes were applied. The agent retains its context and only needs to re-read the updated diff, not re-discover the entire codebase.
- **Confirmation pass:** After the fixer reports all issues resolved, spawn a **fresh confirmation reviewer** (separate agent, no memory of prior cycles) for an unbiased final check. This is the only fresh spawn after cycle 1.

This trades perfect independence between cycles (which rarely matters in practice — the reviewer was already correct about what the issues were) for significant token savings. The fresh confirmation pass at the end catches anything the reused reviewer might have missed.

## Cycle 1 — Initial review

Read `references/agents/code-reviewer.md` for the full prompt template. Read `references/agents/fixer.md` for the fix-cycle prompt template.

Spawn a new reviewer agent (cold start):

```python
Agent(
  description="reviewer — review PR #N",
  prompt=<code-reviewer.md prompt with {variables} replaced>,
  # do NOT set subagent_type — default general-purpose agent, not a custom "code-reviewer" type
)
```

Pass to the reviewer:
- `branch_name`: PR head branch
- `base_branch`: PR base branch
- `pr_context`: PR title and body
- `diff_command`: `gh pr diff {N}`
- `confidence_threshold`: `review.confidence_threshold` (default 80) — the reviewer reports only findings scored at or above this floor; ui-reviewer keeps its own 75 floor

## Cycles 2+ — Re-review via SendMessage

Send a message to the existing reviewer agent:

```
The fixer applied changes. Re-review the PR diff to check if the issues were resolved and find any new issues.

Run: {diff_command}

Return the same JSON format as before.
```

## Confirmation pass

After the fix cycle reports zero fixable issues, spawn a **fresh** confirmation reviewer (new agent, no memory of prior cycles):

```python
Agent(
  description="reviewer — confirmation review for PR #N",
  prompt=<code-reviewer.md prompt with {variables} replaced>,
  # do NOT set subagent_type — default general-purpose agent, not a custom "code-reviewer" type
)
```

If it finds new fixable issues, they go back to the existing fixer. If it confirms clean, the PR passes.

## Fixer spawn (Step 6)

Delegate fixes to the fixer subagent instead of applying code changes in the main skill context. Reuse the same fixer agent across cycles when possible. Spawn or re-message the fixer with:

- `branch_name`: PR head branch
- `base_branch`: PR base branch
- `issue_context`: linked issue details and acceptance criteria, if any
- `pr_context`: PR number, title, body, and URL
- `findings_json`: all blocking findings from reviewer, acceptance-criteria checks, traceability checks, tests, and CI
- `test_output`: trimmed relevant failure output from Steps 4-5
- `commit_message`: `fix({scope}): address review feedback` (append `(#{linked_issue})` only if a linked issue exists)
- `security_convention`: `references/docs/pre-commit-security.md` — the bundled pre-commit security scan the fixer MUST run before committing

```python
Agent(
  description="fixer — fix PR #N review issues",
  prompt=<fixer.md prompt with {variables} replaced>,
  # do NOT set subagent_type — default general-purpose agent, not a custom "fixer" type
)
```

The fixer subagent reads affected files, applies targeted changes, stages specific files, runs relevant verification, and — before committing — runs the mandatory pre-commit security scan from `references/docs/pre-commit-security.md` against the staged set (real secrets block the commit). It then commits any changes. The main agent only collects the fixer's JSON result and pushes if changes were committed. If the fixer cannot resolve all blocking findings, keep the remaining items for the next loop/report. After the fixer returns with one or more commits, push: `git push origin {branch_name}`.
