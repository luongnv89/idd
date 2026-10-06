# UI/UX Review Mechanics

Operational detail for the auto-detected UI/UX review in SKILL.md Step 3 (*UI review*).

The mechanics themselves are **shared with `/issue-resolver` and live in exactly
one home: `references/docs/ui-review.md`** — the contract (auto-detect → always run code
review; browser review is an additive bonus), the UI keyword list, the
classification rule, the code-review spawn, the display-environment label, the
browser gate + capability checks, and the skip/success output. Read that file
before running this step. This file carries only `/issue-pr-review`'s deltas.

## The two legs, and why only one of them can be blocked

- **Code UI review** reads the diff and the changed files, so it is
  environment-independent. It runs whenever UI work is detected, on any machine
  **including a no-GUI/server host**, and is never gated on a GUI, a running
  app, or a browser. Nothing about the host may switch it off.
- **Browser UI review** is an optional bonus that needs a reachable app *and*
  user opt-in. When it cannot run it **skips with a warning and the code UI
  review still runs** — fail-soft to code-only, never a blocked step.

That asymmetry is the contract SKILL.md's Step 3 *UI review* paragraph states in one
line; it is why `light` may skip the browser leg while `qa_handoff = trusted`
reaches only the code leg.

## Deltas for `/issue-pr-review`

- **When:** detection runs once, after Step 2, before the review cycles.
- **Context source:** the PR title + body —
  ```bash
  pr_body=$(gh pr view {N} --json body --jq .body)
  ```
- **Diff command:** `gh pr diff {N}`, so detection step 2 scans
  ```bash
  ui_files=$(gh pr diff {N} --name-only | grep -E '\.(html|htm|css|scss|sass|less|styl|tsx|jsx|vue|svelte|astro)$|^(components|pages|views|layouts|app|src/app|screens|routes|templates)/|tailwind\.config\.|theme\.|tokens\.')
  ```
- **Agent description:** `"ui-reviewer — UI/UX code review for PR #{N}"`.
- **Variables passed:** `{branch_name}`, `{base_branch}`, `{pr_context}` (PR
  title + body), `{issue_context}` (the linked issue title/body + acceptance
  criteria, or empty if none), and `{diff_command}`.
- **Browser gate config key:** `review.ui_review.browser_review`.
- **Findings flow:** merged into the code reviewer findings; `action: "fix"`
  findings join the fixable issues handled in Step 6.

## Propose review mix (interactive mode only)

After classification returns `ui: detected`:

```
◆ UI Review Detected
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  PR mentions:    responsive, mobile, button
  Files changed:  src/components/Button.tsx, src/styles/main.css

  Proposed review:
    ✓ Code review (a11y, responsive, interaction patterns) — runs now
    ○ Browser review (screenshot capture) — needs a running app

  Enable browser review? [Y/n] (requires a reachable app + Playwright)
```

In auto mode (`IDD_AUTO_MODE=1`): log the detection result and proceed with
**code review only** — browser review requires user confirmation per
`review.ui_review.browser_review`.

## Verification recipe <!-- a:rv-verification-recipe -->

The contract, opt-in, lifecycle and verdict handling live in `references/docs/ui-review.md`
(*Verification recipe*). These are `/issue-pr-review`'s deltas:

- **Call:** Step 4 runs it on the checked-out PR head, after the suite or in its place when the suite is skipped. In auto
  mode export `IDD_AUTO_MODE=1` first. Bind `base` from the repository's default
  branch, never the PR's `baseRefName`, because the PR author chooses that:
  ```bash
  base="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
  gh pr diff {N} --name-only | python3 references/scripts/gi-recipe.py --ref "origin/${base}" --consumer review --changed -
  ```
  In interactive mode, add `--plan` to the same call first and ask.
- **Never skipped by the QA handoff.** `qa_handoff = trusted` skips the suite
  but not the recipe, which follows the same rule as the browser leg.
- **Findings:** each capability in a `result: fail` becomes a Step 6 fixable
  issue (`category: correctness`) that cites its `drive.log`. It blocks
  soft-pass the way a failing test does.
- **Report:** Step 7 lists the verdict and its `evidence_dir`.
- **Exit 3** stops the review before Step 5.

## Cycle reuse

Cycles 2+ re-message the existing UI reviewer via `SendMessage` instead of
spawning a new one:

```
The fixer applied changes. Re-review the PR diff for UI/UX issues.

Run: gh pr diff {N}

Return the same JSON format as before.
```

For the confirmation pass, spawn one **fresh** UI reviewer for an unbiased final
check.

Every UI reviewer spawn is role `ui-reviewer`: apply `references/docs/agent-overrides.md`
with the resolved `agents.model.ui-reviewer` / `agents.effort.ui-reviewer`;
`null` (the default) passes nothing, leaving the call unchanged.
