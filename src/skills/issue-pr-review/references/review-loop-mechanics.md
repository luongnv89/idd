# Review Loop Mechanics — Agent Reuse

Exact spawn calls and the token-trade rationale for the reviewer/fixer agents used in Step 3 and the Review Loop of `/issue-pr-review`. SKILL.md keeps the summary (cold start → SendMessage re-review → fresh confirmation); this file holds the detail.

## Why reuse the reviewer

To minimize token usage, the review loop **reuses the same reviewer agent** across fix cycles instead of spawning a fresh one each time. The reviewer already has the codebase context loaded, so subsequent reviews are cheaper.

- **Cycle 1:** Spawn a new reviewer agent (cold start — reads diff, files, context).
- **Cycles 2-3:** Send the reviewer a follow-up message via `SendMessage` asking it to re-review the diff after fixes were applied. The agent retains its context and only needs to re-read the updated diff, not re-discover the entire codebase.
- **Confirmation pass:** After the fixer reports all issues resolved, spawn a **fresh confirmation reviewer** (separate agent, no memory of prior cycles) for an unbiased final check. This is the only fresh spawn after cycle 1.

This trades perfect independence between cycles (which rarely matters in practice — the reviewer was already correct about what the issues were) for significant token savings. The fresh confirmation pass at the end catches anything the reused reviewer might have missed.

## Cycle 1 — Initial review

Read `shared/agents/code-reviewer.md` for the full prompt template. Read `shared/agents/fixer.md` for the fix-cycle prompt template.

Spawn a new reviewer agent (cold start):

```python
Agent(
  description="Review PR #N",
  prompt=<code-reviewer.md prompt with {variables} replaced>,
  subagent_type="general-purpose"  # NOT "code-reviewer"
)
```

Pass to the reviewer:
- `branch_name`: PR head branch
- `base_branch`: PR base branch
- `pr_context`: PR title and body
- `diff_command`: `gh pr diff {N}`

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
  description="Confirmation review for PR #N",
  prompt=<code-reviewer.md prompt with {variables} replaced>,
  subagent_type="general-purpose"  # NOT "code-reviewer"
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
  description="Fix PR #N review issues",
  prompt=<fixer.md prompt with {variables} replaced>,
  subagent_type="general-purpose"  # NOT "fixer"
)
```

The fixer subagent reads affected files, applies targeted changes, stages specific files, runs relevant verification, and — before committing — runs the mandatory pre-commit security scan from `references/docs/pre-commit-security.md` against the staged set (real secrets block the commit). It then commits any changes. The main agent only collects the fixer's JSON result and pushes if changes were committed. If the fixer cannot resolve all blocking findings, keep the remaining items for the next loop/report. After the fixer returns with one or more commits, push: `git push origin {branch_name}`.
