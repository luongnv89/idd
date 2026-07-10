# Issue PR Review

> Review a pull request end-to-end — analyze, test, fix, check CI, and auto-merge when clean — with up to 3 token-optimized fix cycles.

## Intent-Code Boundary

`/issue-pr-review` respects the intent-code boundary. The reviewer reads the **PR diff** and the **current codebase** for findings — it never relies on a predicted file list embedded in the linked issue body. When the linked issue exists, its **acceptance criteria** are the contract the PR is evaluated against; everything else (root cause, affected files, implementation choices) is verified against the code as it is right now. Findings stay in the PR review thread and per-cycle reports — they are not written back into the issue body. See `references/docs/idd-methodology.md` for the full boundary contract.

## Highlights

- Mechanical pre-pass (lint, format, tests) before any LLM cycles to save tokens
- Up to 3 LLM-driven review-fix cycles, ending early when clean
- Runs the project's real test suite, not mocks
- Monitors CI status and waits for green before merging
- Auto-merge in `--auto` mode (used by `/auto-pilot`); read-only mode available
- Five-dimension review output — correctness, acceptance_criteria, traceability, maintainability, safety — grouped under two axes (**Spec**: does it satisfy the acceptance criteria? · **Standards**: does it follow project conventions?) so clean-but-wrong and correct-but-ugly stay separate, and a PR can pass tests yet still be flagged for missing issue links or unmet acceptance criteria
- Per-criterion acceptance-criteria verification (`pass` / `fail` / `unverified` with evidence) against the linked issue
- Soft-pass when zero "fix" issues remain, with **hard blocks** on `traceability: fail` (missing `Closes #N`) and any `acceptance_criteria: fail` — green tests do not override these
- Refactor/chore PRs (matching `review.traceability_exempt_labels` or `review.traceability_exempt_pattern`) are exempt from the `Closes #N` hard-fail; the other three traceability checks still run

## When to Use

| Say this... | Skill will... |
|---|---|
| `/issue-pr-review 42` | Review PR #42, fix issues, and repeat until clean; report findings (no auto-merge) |
| `/issue-pr-review 42 --auto` | Review, fix, wait for CI, and auto-merge when green |
| `/issue-pr-review --review-only` | Review and report only — never fix or merge |
| "is this PR ready?" | Run the pipeline against the current branch's PR |
| "clean up this PR" | Iterate fix cycles until the review is clean |

## How It Works

```mermaid
graph TD
    A["PR info + repo sync"] --> B["Mechanical pre-pass"]
    B --> C["LLM review cycle"]
    C --> D{"Clean?"}
    D -- No --> E["Apply fixes"]
    E --> C
    D -- Yes --> F["Run tests"]
    F --> G["Wait for CI"]
    G --> H["Auto-merge (if --auto)"]
    style A fill:#4CAF50,color:#fff
    style H fill:#2196F3,color:#fff
```

## Installation

Install via [npx (Vercel)](https://www.npmjs.com/package/skills):

```bash
npx skills add https://github.com/luongnv89/idd --skill issue-pr-review
```

Or via [agent-skill-manager (asm)](https://www.npmjs.com/package/agent-skill-manager):

```bash
asm install https://github.com/luongnv89/idd --skill issue-pr-review
```

## Usage

```
/issue-pr-review
/issue-pr-review <PR_NUMBER>
/issue-pr-review <PR_NUMBER> --auto
/issue-pr-review --review-only
```

## Resources

| Path | Description |
|---|---|
| `references/review-loop-mechanics.md` | Review-fix cycle mechanics and the up-to-3-cycle loop |
| `references/prepass-tests-ci-mechanics.md` | Pre-pass lint/format/test and CI check mechanics |
| `references/verification-checks.md` | Verification checks the reviewer runs against the diff |
| `references/ui-review-mechanics.md` | UI-review mechanics for front-end changes |
| `references/report-templates.md` | Per-cycle and final report templates |
| `references/error-messages.md` | Error catalog for prerequisite (git, gh CLI, auth), PR, CI, and fix (push, merge) failures, each with a Docs link |

## Output

A structured 7-step pipeline report in the terminal with:
- PR title, number, and base/head branch
- Pre-pass results (lint, format, test counts)
- Per-cycle findings with confidence and severity
- Test and CI status
- Final verdict: pass, fix-and-retry, or hard-fail
