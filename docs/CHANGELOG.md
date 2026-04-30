# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `dist/agents/` generated Claude Code subagent definitions for every shared IDD agent, including `code-reviewer`, so standalone installs can register the agent types skills may invoke on fresh environments. (#89)

### Changed
- `scripts/install.sh` now installs shared agents to `~/.claude/agents/` alongside standalone skills, supports `--agents-only`, `--no-agents`, `--force-agents`, and `--uninstall`, and avoids overwriting unmanaged same-name agents unless explicitly forced. Plugin builds now also include a top-level `agents/` directory for Claude Code plugin subagent discovery. (#89)

## [0.8.0] - 2026-04-30

### Added
- `feat(security)` shared pre-commit security scan — `docs/pre-commit-security.md` codifies the secret/credential/large-file gate adopted from `/auto-push`. Every skill that runs `git commit` or `git push` now invokes the scan before staging or pushing; real secrets block, warnings log and continue. Wired into `src/shared/agents/implementer.md`, `src/skills/issue-pr-review/SKILL.md` (auto-fix and fix-cycle steps), and `src/skills/issue-resolver/SKILL.md` (Step 5 push). `tests/test-pre-commit-security.sh` greps shell-fenced `git commit`/`git push` invocations and asserts each is gated by a reference to the canonical doc. (#87)
- `feat(install)` `scripts/install.sh` — single idempotent install command for users without `asm`. Installs all standalone skills by default; supports `--skill <name>` for a single skill, `--plugin` for the Claude Code plugin layout, `--all` for both, plus `--target <dir>`, `--dry-run`, and `--help`. Pure POSIX bash, shellcheck clean. (#76, #80)

### Changed
- `refactor(docs)` `src/docs/` and top-level `docs/` merged into a single top-level `docs/` tree containing both runtime (skill-consumed) docs and human-only project docs. The build script copies the same five runtime docs as before — `config-schema.md`, `idd-methodology.md`, `naming-conventions.md`, `sync-conventions.md`, `github-projects-sync.md` — into each skill's `references/docs/`. Internal references and runtime-doc URLs rewritten to match. (#81)
- `docs(install)` README install hierarchy reorganized so standalone installation via `asm install` is the recommended default; the plugin path is preserved as an advanced option below standalone. `docs/DEVELOPMENT.md` updated to point at the new install script alongside the existing manual paths. (#76, #80)
- Skill versions: `/issue-resolver` 0.7.1 (Step 5 pre-push security scan), `/issue-pr-review` 0.4.2 (Step 2 auto-fix and Step 6 fix-cycle pre-commit security scans).

### Fixed
- `docs(install)` README's "every public skill in one call" example previously used `asm install ...:dist/skills --all -p claude`, which fails on asm v2.5.0 because `--all` is ignored when the source includes a subpath ([asm#251](https://github.com/luongnv89/asm/issues/251)). Replaced with a per-skill loop that exercises the working single-skill path, plus a "Why a loop?" callout linking to the upstream asm issue. Single-skill and from-source instructions unchanged. (#85)
- `docs(install)` README "Heads up" callout now explicitly states that `claude plugin install <tarball-url>` is unsupported — Claude Code's `claude plugin install` only accepts `plugin@marketplace` references, not tarball URLs or paths. Replaces the stale "tarballs ship with the first tagged release" note (v0.7.0 already ships `idd-plugin-v0.7.0.tar.gz`) and points users to the working manual `tar -xzf` extract path. (#79)

## [0.7.0] - 2026-04-29

### Added
- `scripts/build.py` and `scripts/build.sh` — byte-deterministic build that flattens authored sources under `src/` into `dist/skills/` (harness-agnostic) and `dist/plugin/` (Claude Code plugin layout). Sibling-relative path rewriting; no `${CLAUDE_PLUGIN_ROOT}` placeholders. (#56)
- `/idd-doctor` internal skill — read-only repository health check that validates IDD invariants against the local `src/` checkout. Not distributed in `dist/`. (#34)
- `feat(plugin)` `src/plugin.json.in` metadata input template — single source of truth for plugin name, slug, author, description, and default version, consumed by the build. (#55)
- `feat(ci)` `dist-check` workflow and `.gitattributes` — CI verifies that `dist/` matches a fresh build of `src/`, and `.gitattributes` keeps generated files out of language stats. (#59)
- `feat(config)` unified `autopilot.*` and `review.*` schema in `.gitissue.yml`, including `review.require_acceptance_criteria_check` (default `true`) and `review.require_traceability_check` (default `true`). When `false`, the corresponding dimension is reported as `pass — verification disabled` and never blocks soft-pass. `/init-gitissue` emits the new keys on a fresh install alongside `autopilot.mode: conservative` and `autopilot.merge_partial: false`. (#38)
- `feat(auto-pilot)` conservative-by-default merge modes — `conservative`/`balanced`/`aggressive` selectable via `autopilot.mode`, and explicit issue lists for targeted runs. (#33)
- `feat(auto-pilot)` fully autonomous workflow — zero-confirmation triage → resolve → review → merge loop with documented stop conditions.
- `feat(issue-pr-review)` per-criterion acceptance-criteria verification — each criterion in the linked issue reports `pass` / `fail` / `unverified` with required evidence; four-check traceability dimension (`Closes #N` in PR body, ≥1 commit referencing the issue via `git log --grep`, durable analysis fields, squash-merge assumption); five-dimension review output (`correctness`, `acceptance_criteria`, `traceability`, `maintainability`, `safety`) replacing the prior single-line verdict. (#36)
- `feat(issue-creator)` duplicate-detector subagent — scores potential duplicates against the open issue list before creation. (#19)
- `feat(projects)` shared GitHub Projects status sync utility — keeps Project boards aligned with issue/PR state. (#16)
- Shared agents architecture — consolidated 9 per-skill agent definitions into 6 reusable shared agents in `shared/agents/`:
  - `codebase-researcher.md` — deep codebase scan and solution research
  - `synthesizer.md` — analysis and implementation options
  - `implementer.md` — code and tests implementation
  - `code-reviewer.md` — confidence-based code review
  - `duplicate-detector.md` — issue dedup scoring
  - `issue-relationship-scanner.md` — file deps and already-fixed detection
- `/issue-pr-review` skill — review, test, CI check, fix, and merge PRs (replaces `/review-fix-loop`).
- Structured step-by-step final reports for all skills.
- `tests/test-autopilot-portability.sh` — source-level portability checks for `/auto-pilot`: forbids hardcoded `skills/<name>/SKILL.md` paths, forbids the "All agents are in shared/agents" phrase, and verifies the compatibility line names every required peer skill. (#53)
- `tests/test-issue-pr-review-traceability.sh` — 50 spec assertions verifying every Phase 2 acceptance criterion from issue #36.
- `tests/test-config-schema-38.sh` — spec assertions verifying every issue #38 acceptance criterion.
- `tests/` — additional build, layout, and determinism tests. (#58)
- `tests/test-projects.sh` — validation tests for the projects sync utility. (#16)
- `docs/release-notes/v0.7.0-smoke-tests.md` — executed results for the four manual release-checklist smoke tests from `refactor-plan-v10.md` §14 against the locally built `0.7.0` artifact: single skill, independent coexistence, `auto-pilot` dependency bundle, plugin tarball + `claude plugin validate`. All four pass. (#61)
- `docs/install` — plugin and standalone distribution install paths documented. (#60)

### Changed
- `refactor(repo)` authored sources moved into a `src/` tree — `src/skills/`, `src/internal-skills/`, `src/deprecated-skills/`, `src/shared/agents/`, `src/docs/`. Top-level `docs/` now retains human-only project docs. Internal references and runtime-doc URLs rewritten to match. (#48, #49, #50, #51)
- `refactor(auto-pilot)` cross-skill prompts now use `{{skill:<name>}}` tokens instead of hardcoded `skills/<name>/SKILL.md` paths; the `compatibility:` frontmatter spells out the required peer skills (issue-triage, issue-resolver, issue-analysis, issue-pr-review) and the optional issue-creator. Source no longer carries the boilerplate "All agents are in shared/agents/" sentence — invoked skills carry their own agent guidance. (#53)
- `/issue-pr-review` soft-pass condition now hard-blocks on `traceability: fail` (e.g., missing `Closes #N`) and any `acceptance_criteria: fail`, even when tests and CI are green — matches the explicit issue #36 contract that a PR can pass tests and fail traceability. Phase 2 hard-blocks are gated on `review.require_*_check` flags. Step 3 runs in a documented order per cycle: reviewer subagent → per-criterion AC verification → traceability checks → dimensional aggregation. Human-authored PRs without a Decision Record are reported as `traceability: partial`, not `fail`. (#36, #38)
- `/issue-resolver` rewritten from 8-step pipeline (Fetch → Branch → Research → Plan → Execute → Test → Verify → Ship) to 6-step pipeline (Preflight → Research → Plan → Implement → QA → Deliver):
  - Step 0 (Preflight) consolidates fetch, branch creation, guards, and auto-normalize
  - Step 4 (QA) integrates code review and test running in a single review-fix loop
  - Step 5 (Deliver) consolidates push, PR creation, and project board sync
- `refactor(review)` review-fix loop optimized for token usage — fewer redundant context loads across cycles. (#24)
- `refactor(shared/agents)` consolidated agents into `shared/agents/` and restructured pipelines accordingly. (#21)
- All skills now reference shared agents from `shared/agents/` instead of per-skill agent definitions; external agent type dependencies removed (`subagent_type` parameter no longer used).
- Skill descriptions trimmed to the asm-eval pass threshold across all 9 skills. (#26, #28, #29)
- `docs(skills)` skill READMEs audited for codebase-enriched claims and rewritten in intent-only language. (#31, #32, #35)
- Updated `docs/github-projects-sync.md` step references to match the 6-step pipeline.
- README and runtime docs adapted to post-#38 methodology. (#47)
- Skill versions: `/auto-pilot` 2.2.0, `/issue-resolver` 0.7.0, `/issue-pr-review` 0.4.1, `/issue-analysis` 0.4.1, `/issue-creator` 0.4.1, `/issue-triage` 0.5.2, `/init-gitissue` 0.3.2, `/idd-doctor` 0.1.0.

### Fixed
- `fix(skills)` `/issue-resolver` Step 0 (Preflight) now stashes uncommitted changes before rebasing the working branch on the latest base, then restores them — protects in-progress work from sync side effects. (#22)
- `fix(auto-pilot)` `auto_merge` guard ordering and `MERGED` status handling reworked; `already_resolved` status handled and consistency gaps closed; CI errors, stop conditions, and docs aligned with the autonomous model; reviewer prompt no longer triggers a merge directly. (#23)
- `fix(skills)` truncated long descriptions and bumped patch versions for `/auto-pilot` and `/issue-triage`.

### Deprecated
- `/issue-pr-review-fix-loop` (v0.4.0) — its outer review-fix loop, agent reuse, and fresh confirmation pass are all part of `/issue-pr-review` now (since v0.3.0), and Phase 2 acceptance-criteria + traceability checks landed there in v0.4.0. Migration: replace any `/issue-pr-review-fix-loop` invocation with `/issue-pr-review` (same PR number, same `--auto` flag). Source remains under `src/deprecated-skills/issue-pr-review-fix-loop/` for repository history and migration references. Tracking issue: #37.

### Removed
- `/issue-pr-review-fix-loop` is removed from the public README command index and standalone install table. Its source remains under `src/deprecated-skills/issue-pr-review-fix-loop/` for repository history and migration references, but it is no longer publicly distributed unless a future compatibility release explicitly opts it in with a `distribute:` flag. Tracking issue: #54.
- `/review-fix-loop` (legacy redirect skill) — replaced entirely by `/issue-pr-review`.
- Per-skill agent definitions (replaced by shared agents).
- Old 8-step pipeline structure and associated step-specific agent files.

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
