# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `/issue-pr-review` per-criterion acceptance-criteria verification — each criterion in the linked issue reports `pass` / `fail` / `unverified` with required evidence
- `/issue-pr-review` four-check traceability dimension — verifies `Closes #N` in PR body, at least one commit referencing the issue (via `git log --grep`), durable analysis fields (Decision Record + Acceptance Criteria Verification block), and the squash-merge assumption
- Five-dimension review output — `correctness`, `acceptance_criteria`, `traceability`, `maintainability`, `safety` — replacing the prior single-line review verdict in cycle reports and the Step 7 summary
- `tests/test-issue-pr-review-traceability.sh` — 50 spec assertions verifying every Phase 2 acceptance criterion from issue #36
- `.gitissue.yml` configuration keys `review.require_acceptance_criteria_check` (default `true`) and `review.require_traceability_check` (default `true`) — gate the Phase 2 acceptance-criteria and traceability dimensions in `/issue-pr-review`. When `false`, the corresponding dimension is reported as `pass — verification disabled` and never blocks soft-pass.
- `/init-gitissue` template emits `review.require_acceptance_criteria_check: true` and `review.require_traceability_check: true` on a fresh install, alongside the existing `autopilot.mode: conservative` and `autopilot.merge_partial: false` defaults
- `tests/test-config-schema-38.sh` — spec assertions verifying every issue #38 acceptance criterion (schema documents the four keys with defaults; init template emits them; no speculative keys; consuming skills wire the gates)

### Changed
- `/issue-pr-review` soft-pass condition now hard-blocks on `traceability: fail` (e.g., missing `Closes #N`) and any `acceptance_criteria: fail`, even when tests and CI are green — this matches the explicit issue #36 contract that a PR can pass tests and fail traceability
- `/issue-pr-review` v0.4.1 — Phase 2 hard-block conditions now gated on `review.require_*_check` flags (#38)
- `/init-gitissue` v0.3.2 — emits the unified Phase 1b + Phase 2 configuration schema
- Step 3 of `/issue-pr-review` now runs in a documented order per cycle: reviewer subagent → per-criterion AC verification → traceability checks → dimensional aggregation
- Human-authored PRs without a Decision Record are reported as `traceability: partial`, not `fail`, while `Closes #N` and acceptance-criteria checks still apply at full strength

### Deprecated
- `/issue-pr-review-fix-loop` (v0.4.0) — its outer review-fix loop, agent reuse, and fresh confirmation pass are all part of `/issue-pr-review` now (since v0.3.0), and Phase 2 acceptance-criteria + traceability checks landed there in v0.4.0. The skill file is retained for one release cycle so existing references resolve; after that release cycle it will be removed from the public skill index. Migration: replace any `/issue-pr-review-fix-loop` invocation with `/issue-pr-review` (same PR number, same `--auto` flag). Tracking issue: #37.

## [0.7.0] - 2026-03-27

### Added
- Shared agents architecture — consolidated 9 per-skill agent definitions into 6 reusable shared agents in `shared/agents/`:
  - `codebase-researcher.md` — deep codebase scan and solution research
  - `synthesizer.md` — analysis and implementation options
  - `implementer.md` — code and tests implementation
  - `code-reviewer.md` — confidence-based code review
  - `duplicate-detector.md` — issue dedup scoring
  - `issue-relationship-scanner.md` — file deps and already-fixed detection
- `/issue-pr-review` skill — review, test, CI check, fix, and merge PRs (replaces `/review-fix-loop`)
- `/issue-pr-review-fix-loop` skill — outer review-fix loop with fresh context per cycle for genuinely independent reviews
- Structured step-by-step final reports for all skills

### Changed
- `/issue-resolver` rewritten from 8-step pipeline (Fetch → Branch → Research → Plan → Execute → Test → Verify → Ship) to 6-step pipeline (Preflight → Research → Plan → Implement → QA → Deliver)
  - Step 0 (Preflight) consolidates fetch, branch creation, guards, and auto-normalize
  - Step 4 (QA) integrates code review and test running in a single review-fix loop
  - Step 5 (Deliver) consolidates push, PR creation, and project board sync
- All skills now reference shared agents from `shared/agents/` instead of per-skill agent definitions
- Removed all external agent type dependencies (`subagent_type` parameter no longer used)
- `/review-fix-loop` deprecated — redirects to `/issue-pr-review`
- Updated `docs/github-projects-sync.md` step references to match new 6-step pipeline

### Removed
- Per-skill agent definitions (replaced by shared agents)
- Old 8-step pipeline structure and associated step-specific agent files

## [0.6.0] - 2026-03-24

### Added
- Dedicated Test step (Step 6) in `/issue-resolver` pipeline — expands the pipeline from 7 steps to 8 (Fetch → Branch → Research → Plan → Execute → Test → Verify → Ship)
  - Test writer subagent (`agents/test-writer.md`) writes unit tests and e2e tests (when an e2e framework exists) for all new/changed functionality
  - Inline fallback for environments without the Agent tool
- Build verification in `/issue-resolver` Step 7 (Verify) — compiles/builds the project before running tests to catch errors early
- `/auto-pilot` resolver and batch resolver subagent prompts updated to enforce the Test step and report `tests_written` count

### Changed
- `/issue-resolver` v0.4.0, `/auto-pilot` v0.6.0
- `/issue-resolver` implementer subagent now defers comprehensive test writing to the dedicated Test Writer subagent (Step 6)
- `/auto-pilot` pipeline references updated from 7-step to 8-step across SKILL.md and subagent-prompts.md
- README command table updated with current skill versions

## [0.5.0] - 2026-03-24

### Added
- Subagent architecture for `/issue-analysis`, `/issue-resolver`, and `/issue-triage` — delegates context-heavy phases to dedicated subagents, keeping the main agent's context clean
  - `/issue-analysis`: explorer subagent (Steps 2-5: keyword extraction, deep codebase scan, git history, cross-references) and synthesizer subagent (Steps 6-7: root cause analysis, implementation options)
  - `/issue-resolver`: researcher subagent (Step 3: codebase scanning) and implementer subagent (Step 5: code writing and commits)
  - `/issue-triage`: history-scanner subagent (Step 1b: already-fixed detection) and dependency-scanner subagent (Step 2: affected files and dependency graph) with parallel execution and batch splitting for 10+ issues
- All subagent prompts include prompt injection boundary warnings and read-only constraints
- Inline fallback for environments without the Agent tool (e.g., Claude.ai)
- `/auto-pilot` smart analysis phase — runs `/issue-analysis` before resolution when given explicit issue lists, identifying dependencies and optimal resolution order

### Changed
- `/issue-analysis` v0.3.0, `/issue-resolver` v0.3.0, `/issue-triage` v0.4.0
- `/auto-pilot` review cycles increased from 2 to 5

## [0.4.0] - 2026-03-24

### Added
- `/review-fix-loop` skill — automated review-fix cycle that spawns fresh reviewer agents, fixes detected issues, and repeats until clean
  - Each review cycle uses an independent `shared/agents/code-reviewer.md` subagent for unbiased assessment
  - Fixes accumulate without committing — one clean commit at the end
  - Stagnation detection stops the loop if the same issues recur across 2 consecutive cycles
  - Max 5 cycles safety cap, high-confidence-only filtering to avoid nitpicking
  - Auto-detects PR branches (uses `gh pr diff`) or regular branches (uses `git diff base...HEAD`)

### Changed
- `/review-fix-loop` v0.1.0
- README updated with review-fix-loop skill in command table and project structure

## [0.3.0] - 2026-03-24

### Added
- `/auto-pilot` skill — fully automated triage → resolve → review → merge loop with subagent architecture and 2-pass code review
  - Supports explicit issue lists to process specific issues in user-defined order
  - Two fix-review cycles before merge, with stop conditions for safety
- `/issue-triage` already-fixed detection — scans commit history and merged PRs to find open issues incidentally resolved by other PRs
  - Confidence levels (high/medium) based on closing keywords vs bare references
  - Detail block with suggested `gh issue close` commands
- `/issue-analysis` now includes issue reporter information in analysis output

### Fixed
- `/issue-resolver` — removed invalid `--json` flag from `gh pr create` command (#17)

### Changed
- README updated with Intention-Driven Development concept and commit message guidance
- `/issue-triage` v0.3.0, `/auto-pilot` v0.3.0, `/issue-analysis` v0.2.0

## [0.2.1] - 2026-03-23

### Added
- `docs/naming-conventions.md` — standalone, tool-agnostic naming conventions for branches, commits, PRs, and issues
- Naming conventions section in CLAUDE.md referencing the standalone doc

### Changed
- `/issue-resolver` v0.2.0 — branch naming switched from `issue-N/description` to type-based `fix/N-description`, commit messages use Conventional Commits with optional scope, PR titles follow same format
- `/issue-creator` v0.2.0 — issue title conventions added (imperative mood, good/bad examples table)
- `/init-gitissue` v0.2.0 — generated config uses `branch_prefix: "auto"` with type-based prefix documentation
- `resolve.branch_prefix` default changed from `"issue-"` to `"auto"` across all docs and config schema
- All terminal mockups and examples updated to reflect new naming conventions (DESIGN.md, README.md, prd.md, idea.md)

## [0.2.0] - 2026-03-22

### Added
- `/issue-analysis` skill — deep single-issue analysis with root cause, implementation options, and risk assessment
  - 8-step pipeline: Fetch → Extract → Research → History → Cross-refs → Analysis → Options → Report
  - Git history analysis: prior fix attempts, regression detection, domain expert identification
  - Cross-references: triage data, related issues/PRs, duplicate detection, "already resolved" detection
  - Persists to `.gitissue/analysis-<N>.json` for cross-session access and future use by `/issue-resolver`
  - View mode renders cached analysis without GitHub API calls
  - Configurable scan depth (`analysis.max_files`, `analysis.trace_depth`, `analysis.scan_timeout`)
  - Analyzes closed issues for reference (does not stop on closed state)
- `effort` attribute in all skill frontmatter (low/medium/high/max)
- README rewritten as landing page with "Works With Any Tool" section

### Changed
- `/issue-triage` — view is now the default mode; removed `/view` subcommand
- README command table includes Version and Effort columns
- Documentation updated with `/issue-analysis` references (ARCHITECTURE.md, DESIGN.md, config-schema.md)

## [0.1.0] - 2026-03-21

### Added
- `/issue-creator` skill — create and normalize GitHub issues
  - Single issue creation from text descriptions
  - Issue normalization (restructure existing issues into standard template)
  - Batch creation from multi-item input
  - Image upload and embedding in issue descriptions
  - Security issue detection (skip normalization for CVE/vulnerability labels)
  - Confidence scoring for type classification and acceptance criteria
- `/issue-resolver` skill — resolve issues through a 7-step pipeline (Fetch → Branch → Research → Plan → Execute → Verify → Ship)
  - Structure-only auto-normalize before resolution
  - Single authoritative codebase scan in Research step
- `/issue-triage` skill — backlog analysis with keyword-based codebase scanning for dependency detection, priority suggestions, stale issue flagging
  - Triage results persisted to `.gitissue/triage.json` for cross-session access
  - View mode renders cached report without GitHub API calls
  - Per-issue scan timeout (`triage.scan_timeout_per_issue`, default 30s)
- `/init-gitissue` skill — auto-detect project language/framework and generate `.gitissue.yml`
- Lean issues architecture — issues contain only human intent (type, description, acceptance criteria); codebase analysis performed by consumer skills at execution time
- IDD methodology documentation
- Terminal output style guide (DESIGN.md)
- Configuration schema documentation with Mermaid diagrams
- Integration test framework (Sprint 1-3 test suites)
- SVG terminal screenshots in README
- CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md
- GitHub issue and PR templates
- `.gitissue/` directory convention for persistent skill state
