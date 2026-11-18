# ADR — Practice packs in issue-resolver

**Status:** Accepted (2026-11-18).
**Issue:** [#649](https://github.com/luongnv89/idd/issues/649).
**Sources:** [luongnv89/skills](https://github.com/luongnv89/skills) at commit `d173ae3`, `skills/` and `extras/`.

## Context

`/issue-resolver` wrote code and tests with only the rules in the implementer and code-reviewer prompts. The engineering practices in luongnv89/skills (test-coverage, code-review, codebase-modernizer, security-setup, frontend-design, dont-make-me-think, ux-ax-review, design-optimizer, seo-ai-optimizer, devops-pipeline, github-pages-publish, cli-builder, install-script-generator, doc-manager, oss-ready, user-test) reached a run only through Step 3's optional propose sub-step: interactive, or auto with `resolve.borrow_skills: true`, and only when the skill was installed. Its catalog had drifted from the upstream repo.

## Decision

- Eight checklists are shared references, `src/shared/references/practice-{tests,code,performance,security,frontend,ci-cd,cli,docs}.md`, with one selection file, `practice-packs.md`. The build copies them unchanged into each citing skill: issue-resolver and issue-pr-review. Each rule is one line with an ID and a *Check* a reviewer can apply to a diff.
- They are references, not skills. A skill per checklist would break self-containment (a missing install degrades the run), add a skill wrapper around about 1.9 KB of rules without lowering per-run tokens, and add eight descriptions that can mis-trigger; subagents take file paths, not skill invocations.
- `/issue-pr-review` selects packs from `gh pr diff` and the linked issue, counting its `sensitive` risk tier as a sensitive classification, and binds the same set to the cycle-1 reviewer and the confirmation pass.
- Step 3 of `/issue-resolver` selects packs from the plan's files and the issue text (doubt includes a pack) and binds their absolute paths to the implementer as `practice_packs`, the same way as `secscan_script`: an emitted agent prompt cannot name a path inside the bundle.
- Step 4 re-selects from the actual diff and binds the packs to the fresh code reviewer. Violations use the reviewer's existing categories and action rules, so the packs widen what is noticed, not what blocks.
- The repo's established pattern and the selected plan win over a rule. The implementer records a rule it could not apply, or that needs unplanned work, under *Practices*; Step 4 passes that record to the reviewer, which lowers a recorded departure to a note only for a `code_quality` finding, so self-reported text cannot relax a security, correctness, edge-case or test finding, and PR-body text is never a departure record, and Deliver lists it under the Decision Record's *Residual risk*.
- The reviewer is read-only: it judges each *Check* by reading the diff, never by running the branch's code, and categorizes a violation by what it breaks.
- `practice-docs.md` also governs Step 5's *Update documentation*, which the main agent performs.
- The packs are self-contained: no run installs, invokes or depends on luongnv89/skills.

## Filter

A practice was kept only when it applies to code one issue's diff writes in an existing codebase, adds no dependency, tool, hook, service or CI job, is checkable from the diff or one focused command, is not already enforced by the implementer, code reviewer, UI reviewer, bug-verification checkpoint or pre-commit scan, and does not conflict with "follow existing patterns". Each checklist is capped at 1,900 bytes (`tests/test-practice-packs-649.sh`).

## Provenance

Paths are relative to the source repo's `skills/` or `extras/` directory.

### `practice-tests.md`

| Rule | Source |
|------|--------|
| T1 | test-coverage/SKILL.md; user-test/references/testing.md |
| T2 | code-review/references/tdd-checklist.md; test-coverage/SKILL.md |
| T3 | test-coverage/references/unit-test-quality.md; code-review/references/tdd-checklist.md |
| T4 | test-coverage/references/unit-test-quality.md; code-review/references/tdd-checklist.md |
| T5 | codebase-modernizer/references/dimension-map.md |
| T6 | codebase-modernizer/references/baseline.md |
| T7 | test-coverage/references/unit-test-quality.md, SKILL.md |
| T8 | test-coverage/references/unit-test-quality.md; code-review/references/tdd-checklist.md |
| T9 | user-test/references/testing.md |
| T10 | test-coverage/references/unit-test-quality.md; user-test/references/testing.md |

### `practice-code.md`

| Rule | Source |
|------|--------|
| C1 | code-review/agents/defensive-programming-remover.md; references/clean-code-checklist.md |
| C2 | code-review/references/clean-code-checklist.md; agents/defensive-programming-remover.md |
| C3 | code-review/agents/defensive-programming-remover.md, references/language-checks.md; codebase-modernizer/references/dimension-map.md |
| C4 | code-review/agents/legacy-code-remover.md, agents/weak-type-strengthener.md; codebase-modernizer/references/dependency-audit.md |
| C5 | code-review/agents/weak-type-strengthener.md; references/clean-code-checklist.md |
| C6 | code-review/agents/defensive-programming-remover.md; references/cleanup-mode.md |
| C7 | code-review/references/tdd-checklist.md |
| C8 | code-review/agents/legacy-code-remover.md; references/cleanup-mode.md |
| C9 | code-review/references/code-smells.md, review-mode.md; agents/deduplicator.md |
| C10 | code-review/agents/slop-comment-cleaner.md; references/code-smells.md, review-mode.md |
| C11 | code-review/references/clean-code-checklist.md, review-mode.md |

### `practice-performance.md`

| Rule | Source |
|------|--------|
| P1 | code-review/references/perf-mode.md, language-checks.md; codebase-modernizer/references/dimension-map.md |
| P2 | code-review/references/perf-mode.md, language-checks.md; codebase-modernizer/references/dimension-map.md |
| P3 | codebase-modernizer/references/dimension-map.md; code-review/references/language-checks.md |
| P4 | codebase-modernizer/references/dimension-map.md; code-review/references/language-checks.md |
| P5 | code-review/references/perf-mode.md, language-checks.md; codebase-modernizer/references/plan-template.md |
| P6 | codebase-modernizer/references/dimension-map.md; code-review/references/language-checks.md |
| P7 | codebase-modernizer/references/dimension-map.md; code-review/references/perf-mode.md |
| P8 | code-review/references/perf-mode.md, language-checks.md; codebase-modernizer/references/dimension-map.md |
| P9 | code-review/references/language-checks.md, perf-mode.md; agents/defensive-programming-remover.md |
| P10 | code-review/references/language-checks.md, perf-mode.md |

### `practice-security.md`

| Rule | Source |
|------|--------|
| S1 | codebase-modernizer/references/dimension-map.md |
| S2 | codebase-modernizer/references/dimension-map.md; code-review/references/review-mode.md |
| S3 | security-setup/references/templates.md |
| S4 | security-setup/references/templates.md; code-review/references/review-mode.md |
| S5 | code-review/references/review-mode.md; codebase-modernizer/references/dimension-map.md |
| S6 | code-review/references/review-mode.md; codebase-modernizer/references/dimension-map.md |
| S7 | codebase-modernizer/references/dimension-map.md |
| S8 | code-review/references/review-mode.md, agents/defensive-programming-remover.md; security-setup/references/templates.md |
| S9 | codebase-modernizer/references/dependency-audit.md |
| S10 | codebase-modernizer/references/dimension-map.md |
| S11 | security-setup/references/templates.md; codebase-modernizer/references/dimension-map.md; code-review/agents/defensive-programming-remover.md |

### `practice-frontend.md`

| Rule | Source |
|------|--------|
| F1 | dont-make-me-think/references/krug-principles.md; frontend-design/references/usability-guide.md |
| F2 | dont-make-me-think/references/redesign-mode.md, krug-principles.md |
| F3 | dont-make-me-think/references/krug-principles.md; frontend-design/references/usability-guide.md; ux-ax-review/references/final-report.md |
| F4 | frontend-design/SKILL.md, references/usability-guide.md |
| F5 | seo-ai-optimizer/references/technical-seo.md; frontend-design/SKILL.md |
| F6 | dont-make-me-think/references/krug-principles.md |
| F7 | ux-ax-review/references/human-ux.md |
| F8 | seo-ai-optimizer/references/technical-seo.md |
| F9 | seo-ai-optimizer/references/technical-seo.md, framework-configs.md; dont-make-me-think/references/krug-principles.md |
| F10 | frontend-design/SKILL.md; ux-ax-review/references/human-ux.md, ai-search-ax.md |

### `practice-ci-cd.md`

| Rule | Source |
|------|--------|
| D1 | security-setup/references/verification-scenarios.md, SKILL.md |
| D2 | devops-pipeline/SKILL.md, references/github-actions.md |
| D3 | security-setup/references/templates.md; devops-pipeline/references/github-actions.md; github-pages-publish/assets/pages-workflow.yml |
| D4 | codebase-modernizer/references/dimension-map.md, dependency-audit.md; devops-pipeline/references/github-actions.md |
| D5 | devops-pipeline/references/github-actions.md, precommit-configs.md; codebase-modernizer/references/baseline.md; security-setup/references/tool-selection.md |
| D6 | devops-pipeline/SKILL.md, references/github-actions.md |
| D7 | devops-pipeline/references/github-actions.md, ci-minutes.md |
| D8 | devops-pipeline/references/github-actions.md |
| D9 | devops-pipeline/references/github-actions.md; github-pages-publish/assets/pages-workflow.yml |
| D10 | devops-pipeline/references/github-actions.md; security-setup/references/templates.md |

### `practice-cli.md`

| Rule | Source |
|------|--------|
| L1 | cli-builder/references/testing-patterns.md |
| L2 | cli-builder/SKILL.md; references/btop-style.md |
| L3 | cli-builder/references/btop-style.md |
| L4 | cli-builder/SKILL.md |
| L5 | cli-builder/SKILL.md |
| L6 | cli-builder/references/btop-style.md |
| L7 | cli-builder/SKILL.md |
| L8 | install-script-generator/SKILL.md, references/install-template.md |

### `practice-docs.md`

| Rule | Source |
|------|--------|
| W1 | doc-manager/SKILL.md |
| W2 | doc-manager/SKILL.md; oss-ready/SKILL.md |
| W3 | oss-ready/SKILL.md; cli-builder/SKILL.md |
| W4 | oss-ready/SKILL.md; doc-manager/SKILL.md |
| W5 | doc-manager/SKILL.md |
| W6 | oss-ready/references/file-specs.md |
| W7 | doc-manager/SKILL.md |

## Dropped

- **tests:** coverage targets and tooling (repo-wide, adds tools); planted-bug checks, duplicate tests, layer choice (implementer's sensitivity, reuse and layer rules); generic edge cases (reviewer); AAA layout and naming (neighbor matching); speed and run-twice checks (need execution); suite baseline (Step 4 runs the suite); browser journeys (need a running app); fake credentials (security pack, secret scan); test hooks in production (code pack C7).
- **code, performance:** function length and nesting thresholds (reviewer complexity check, lint); import cycles (need a graph tool); duplicated types and helpers (reviewer duplication check); failure style per module and SOLID (design judgement); dependency upgrades and repo-wide sweeps (out of scope, tool installs); micro-optimizations (P5 allows only on a measured hot path); outbound timeouts (not in the sources); re-render avoidance (frontend, not in the sources).
- **security:** scanners, hooks and CI security workflows (setup); secret-file and key checks (pre-commit scan); generic injection categories (reviewer's security category; kept only as techniques); CI pipeline inputs (ci-cd pack D1–D3); SSRF, CSPRNG, constant-time compare, ReDoS, CSRF, cookie flags (no source support beyond a generic OWASP claim); package age, license and typosquat vetting (no one-command check); upgrade waves and history scans (whole-repo audits).
- **frontend:** distinctive aesthetics (conflicts with existing design; consistency covered by ui-reviewer); loading/error states, contrast, alt, focus, touch targets (ui-reviewer); site-level robots/sitemap/llms.txt/agent cards (setup); SEO copy lengths (not a defect); resource hints/AVIF (needs measurement); user tests and viewport renders (need a running app); copy/product choices (issue sets scope); server-HTML-first (cut for size).
- **ci-cd:** Docker non-root/multi-stage (no source prescribes); secrets in logs (covered by pre-commit scan); shift-left parity (pipeline design); speed/cost tuning (needs measured runs); Codecov/SARIF (third-party service); affected-test selection (setup); pre-push hook stage in CI (cut for size); CI-file linting (verification command, not a practice).
- **cli, docs:** flag deprecation and naming (covered by follow-existing-patterns); checksum downloads and non-TTY prompts (not in the sources); entry-point tests (tests pack); same-change doc updates (resolver Step 5); inline cites on every claim, runbook validators, new doc files (out of scope); btop styling, completions, packaging, parser choice (new-CLI setup).
