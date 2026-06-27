# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- `feat(install)` `scripts/install.sh` and root `install.sh` now refresh skills from the latest `main` on every run (clone/fetch for `curl | bash`, fast-forward for clean checkouts). Re-install always replaces each skill directory and overwrites IDD-managed agents from source — no skip when `cmp` matches and no reliance on skill `metadata.version`. Set `IDD_SKIP_SOURCE_SYNC=1` to install from the current tree without fetching. (#TBD)
- `feat(install)` Interactive installs now ask whether to use **asm** first; Yes installs `agent-skill-manager` when missing and runs `asm install` for this repo (honors `--skill`). No continues with the bundled copy installer. Flags: `--use-asm`, `--no-asm-prompt`; tests use `IDD_SKIP_ASM_PROMPT=1`. (#TBD)

### Fixed
- `fix(monitoring)` The **Batch Resolver** path (`/auto-pilot --issues`, where the analyzer bundles several issues into one PR) now records **one `.gitissue/runs.jsonl` line per attempted issue** instead of ~2 lines per batch regardless of N — completing the single-writer work from #156 on the batch fan-out. The Batch Resolver subagent now runs with `--no-run-log` (like the single-issue resolver) and **returns** its telemetry (`complexity`, `duration_s`, plus `issues_resolved` for per-issue outcomes); `/auto-pilot` fans that one result out so that — **across the run** — every issue in the **attempted set** ends with exactly one line (not the success-only `issues_resolved`, so a failed batch doesn't drop fully-attempted issues). At batch time `/auto-pilot` writes a line only for the issues **in** `issues_resolved` (their `outcome` is the success outcome); each unresolved attempted issue is re-queued and logged at its individual retry (which sets its own `outcome`), never a `failed` line at batch time. The shared `pr`/`complexity` go on every line while `qa_cycles`/`duration_s` are attributed to the primary issue's line only (so a batch isn't weighted N-fold in `/idd-doctor`'s medians). On a partial/failed batch, a line is written only for the resolved issues now, and every unresolved issue — **including the batch's primary (spawn-position) issue** — is re-queued for individual resolution, which logs *its* single line (re-queuing the primary is mandatory: its `optimized_order` slot is already consumed, so without an explicit re-append it would drop to zero lines — the inverse under-count). No batch `failed` line is written for an unresolved issue, so a batch-failed-then-individually-resolved issue is never double-counted; and the later `already resolved in batch` skip for a batch-resolved member is display-only and writes no line. Net: exactly one line per attempted issue across the run, with no re-resolve double-count and no inverse under-count. Authoritative contract in `references/explicit-list-mode.md` (*Run-log fan-out for the batch*), mirrored in `docs/config-schema.md`; `tests/test-runs-jsonl.sh` gains T7 (and flips the #156 `--no-run-log`-count tripwire from 1 to 2). Skills bumped: `/auto-pilot` 2.3.3 → 2.3.4. (#158)
- `fix(monitoring)` `/auto-pilot` is now the **single writer** of `.gitissue/runs.jsonl` per processed issue, fixing a double-write regression from #154 where both the resolver subagent and `/auto-pilot` appended a line per issue — double-counting every metric `/idd-doctor` computes (resolve rate, outcome breakdown, median QA cycles, which aggregate over every line with no dedup). `/issue-resolver` gains a `--no-run-log` flag: when set it does **not** append and instead **returns** its telemetry (`outcome`, `qa_cycles`, `complexity`, `duration_s`) to the caller; `/auto-pilot` passes the flag to its resolver subagent and folds the returned telemetry into its one enriched line. The flag is **orthogonal to `--auto`/`IDD_AUTO_MODE`** — a standalone `/issue-resolver N --auto` is not suppressed and remains the single writer for that run. Scoped to the single-issue path; the Batch Resolver miscount is deferred to #158. Skills bumped: `/issue-resolver` 0.10.0 → 0.11.0, `/auto-pilot` 2.3.2 → 2.3.3. (#156)

### Added
- `feat(review)` Browser-based UI/UX review now **explicitly detects the no-GUI / server environment and reports its capture mode**, so UI changes are verified reliably on a headless CI host. Both review skills already noted that headless Chromium needs no display, but neither named the no-GUI case as a distinct step nor stated which mode ran. The browser-review section of `/issue-pr-review` (Step 3) and `/issue-resolver` (Step 4) now classifies the runtime as *no-GUI/server* (no `$DISPLAY`/`$WAYLAND_DISPLAY` on a non-macOS host) or *graphical* — **for reporting only**. Capture always runs Playwright **headless** (the only mode this review has ever used), so a no-GUI host proceeds headless rather than being skipped, and graphical-display behavior is unchanged. The environment label never selects the launch mode and is never a fourth gate (the existing opt-in + reachable-app + capture-safe gates and fail-soft-to-code-only are untouched). The success path now prints `✓ Browser review — captured 3 viewports (Playwright: headless; environment: {no-GUI server | graphical})` and the skip warning names the environment so a no-GUI host is never mistaken for a silent skip. Code UI review still always runs regardless. Documentation-only change to the two skill sources; no headed code path is introduced — the design stays headless-only and `headed` is named only as the contrast term satisfying the issue's mode-reporting criterion. The environment-detection block is placed **before** the `browser_review` gate and capability checks so `ui_env` is defined on every path — including the early config-level skips — leaving no skip warning that references an unset label. Skills bumped: `/issue-pr-review` 2.1.0 → 2.2.1, `/issue-resolver` 0.12.1 → 0.13.1. (#166)
- `feat(issue-resolver)` High-complexity work now passes through a single **design-confirm checkpoint** before implementation, closing weakness **W4** (every issue previously ran the identical 6-step pipeline with no risk-gated agreement point). The minimum-viable version per plan reference P5: when the synthesizer reports a high-complexity tier (`overall_complexity: L`/`XL`, or `overall_risk: High` — equivalently the researcher's `complexity: high|complex`) **and** mode is interactive, the resolver presents the already-selected recommended option for a one-shot `Proceed? [Y/n]` confirmation between Step 2 (Plan) and Step 3 (Implement), reusing that option's change summary and residual risk. Declining stops before any code is written; accepting continues unchanged. Trivial/low/medium complexity is the unchanged fast path, and auto mode (`--auto`/`IDD_AUTO_MODE=1`) never pauses — it selects the recommended option and logs the decision. The decision (option + complexity) is recorded on a conditional **Design-confirm** line in the PR Decision Record so it survives squash-merge into git history. No new phase, artifact, or config key is introduced — the checkpoint is gated entirely on data Step 2 already produces and is not suppressed by `approval_gate: auto`. Full procedure in `references/pipeline-steps.md` (*Step 2 — Plan → Design-confirm checkpoint*). Skill bumped: `/issue-resolver` 0.11.0 → 0.12.0. (#143)
- `feat(issue-pr-review)` PR review findings are now reported under **two named axes** — a **Spec axis** (does the PR satisfy the issue's acceptance criteria?: `acceptance_criteria`, `correctness`, `safety`) and a **Standards axis** (does the PR follow documented project conventions?: `traceability`, `maintainability`) — so "clean-but-wrong" and "correct-but-ugly" are no longer conflated (Matt Pocock's two-axis review framing; plan reference P4). This is a presentation reframe of the existing five-dimension output: the same findings, the same `action: "fix" | "note"` semantics, the same per-dimension `pass`/`partial`/`fail` status rules, and the same soft-pass gating (`acceptance_criteria: fail` and a missing `Closes #N` remain the only hard-blocks) are unchanged — there is no per-axis verdict and auto mode's merge gating is untouched. The Step 7 summary templates (clean, remaining-issues, human-authored, refactor/chore-exempt) and the compact `[3/7] Review` line group the five dimensions under the two axis headers; the full mapping and rationale live in `references/verification-checks.md` (*Two-axis grouping — Spec vs Standards*). `tests/test-issue-pr-review-traceability.sh` gains T10 (axis grouping). Skills bumped: `/issue-pr-review` 2.0.0 → 2.1.0. (#142)
- `feat(monitoring)` Added `.gitissue/runs.jsonl` — an append-only, newline-delimited JSON **run log** that gives the `monitoring` value its first persistent home (closes weakness W3). `/issue-resolver` appends one line per run (`success` / `already_resolved` / `failed`) and `/auto-pilot` appends one line per processed issue including skips (with a `skipped_reason`). Each line carries at minimum `ts`, `issue`, `mode`, `outcome`, and `pr`, plus optional `complexity`, `qa_cycles`, `duration_s`, and `skipped_reason`. `/idd-doctor` gains an informational, non-gating **run-log summary** (resolve rate, median QA cycles, common skip reasons over the last N runs) that degrades gracefully when the file is absent. The file is append-only, schema-light, grep-friendly, deletable, and writing it is best-effort/non-fatal. Schema documented in `docs/config-schema.md`. (#141)
- `feat(issue-resolver)` Bug fixes now require a **red-capable verification checkpoint** before the fix. For `type: bug` issues the resolver names a command/test that reproduces the symptom and confirms it fails red **for the stated reason** before any fix is applied (implementer Task 1.5), then converts the minimized reproduction into a regression test when a clean seam exists. The reproduction becomes durable **evidence** in the PR Decision Record and acceptance table — not just a checkmark — and degrades gracefully when there is no test seam or runner (records the manual command, adds no framework). Non-bug issues are unaffected and auto mode never blocks. Adds `references/bug-verification.md`. `/issue-analysis` gains a matching optional `decision_record.reproduction` schema field for the analysis-JSON mirror (defined, not self-populated). Skills bumped: `/issue-resolver` 0.9.0 → 0.10.0, `/issue-analysis` 0.4.2 → 0.5.0. (#140)
- `feat(issue-resolver)` Interactive runs now offer to resolve the issue in an isolated git **worktree** instead of the current working tree. On accept, the resolver creates the branch + worktree in one `git worktree add -b` off a freshly fetched base (replacing the in-place stash-first sync and branch creation), copies the repo's gitignored local config (`.env*` and similar), and runs the project's detected install/bootstrap so the workspace is ready to run without manual reconfiguration. Declining keeps today's in-place behavior unchanged, and auto-pilot / `IDD_AUTO_MODE=1` never shows the prompt. Worktree creation failures fall back to the in-place path. Skill bumped 0.8.0 → 0.9.0. (#123)

### Changed
- `refactor(issue-resolver)` End-of-run output no longer repeats itself. Previously a resolve printed the same status three times: the live `[N/5]` tracker, then **two** end-of-run blocks (a `✓ Done` block and a step-by-step *Final Report*) that both re-listed every step's pass/fail **and** its metrics (files read, complexity, option, files changed, test counts, QA cycles) plus the PR number / URL / `Closes #N`. The three *Final Report* templates and the separate `✓ Done` block are replaced by a **single Closing Summary** printed once after the tracker's `[5/5]` line, carrying only facts the tracker never showed: the outcome line, the `risk_rating` (which no tracker line surfaces), and the single PR reference. Every metric the tracker already displayed is dropped from the closing block rather than restated, and the full PR reference (number, title, URL, `Closes #N`) appears **only** in that block. The with-warnings variant additionally states the residual QA count/cycle total (genuinely new — the tracker showed the in-progress state, not the final unresolved count); already-resolved keeps the fixing SHA and omits the PR reference (none is created). Each surviving fact now appears in exactly one place — the tracker or the closing block — with one intentional trim: the success path's per-cycle `issues_found` count (old `QA: ✓ pass (… N issues fixed)`) is folded into the tracker's `[4/5] QA ✓ clean after N cycles` line, since "clean" already implies every found issue was fixed. No fact a reader needs is lost. Pure output-format change — no pipeline, agent, or config behavior is affected. `references/report-templates.md` (*Closing Summary*) and the SKILL source's *Closing Summary* / *Expected Output* framing updated together. Skill bumped: `/issue-resolver` 0.12.0 → 0.12.1. (#165)
- `feat(issue-creator)` Model-suggestion cache moved from per-repo `.gitissue/model-data.json` to a **skill-level** dated cache (`model-data-<date>.json` in the installed skill folder), so one cache serves every repo on the machine — no more re-seeding per project. The filename carries the last-update date for at-a-glance staleness, and `--refresh-model-data` forces a refresh on demand regardless of the staleness threshold. A legacy per-repo `.gitissue/model-data.json` is ignored and may be deleted. (#124)

## [0.13.0] - 2026-06-12

### Added
- `feat(site)` Separate changelog page — extracted the changelog from `landing.html` into a standalone `changelog.html` with a matching dark terminal theme, a stats bar (total releases + date range), an interactive expandable timeline, and live GitHub API integration with an offline fallback dataset. Nav links added between the landing and changelog pages. (#112)

### Changed
- `chore(skills)` Brought all 7 IDD skills under `src/skills/` up to the skill-creator standard — normalized frontmatter (`metadata.author`), YAML-safe quoting, trimmed over-long descriptions while preserving every negative-trigger clause, and split the 4 skills that exceeded 500 lines into `references/` files (`issue-pr-review` 733→479, `issue-resolver` 525→484, `auto-pilot` 503→476, `issue-creator` kept under 500). Per-skill version bumps reflect the largest change. (#113)

## [0.12.0] - 2026-06-11

### Added
- `feat(skills)` Added a shared `fixer` agent (`src/shared/agents/fixer.md`) used by both `/issue-pr-review` (Step 6) and `/issue-resolver` (Step 4) to own commits. The fixer now runs a mandatory pre-commit security scan unconditionally: a `security_convention` variable points at the bundled `pre-commit-security.md`, and both skills pass it, so real secrets block the commit — restoring the deterministic secret-blocking gate that had been dropped. (#111)

### Changed
- `breaking(issue-pr-review)` default behavior changed to automatic review-fix loop. `/issue-pr-review <N>` now loops to fix issues until clean (up to `review.max_cycles`), matching the former `--auto` loop behavior minus auto-merge. `--auto` flag adds auto-merge on top of the loop. `--review-only` remains the opt-out for a single-pass report without fixing or looping. Version bumped 0.5.1 → 1.0.0.

### Removed
- `issue-pr-review-fix-loop` skill removed entirely — its source, installed skill, and project directory deleted. Its functionality was already folded into `/issue-pr-review` since v0.3.0. All references in AGENTS.md, CLAUDE.md, and README.md updated.

### Documentation
- `docs(landing)` Landing page SEO and AI-crawler discovery improvements — added `llms.txt`, `robots.txt`, `docs.html`, `docs/skills.md`, and sitemap updates. (#110)
- `docs(landing)` Landing page now shows the latest release and GitHub star count dynamically.

## [0.11.1] - 2026-06-11

### Fixed
- `fix(install)` Hide source skills from asm discovery so only the intended flat install surface is detected (#109)

### Documentation
- `docs(landing)` Update landing page install commands for the flat install surface

## [0.11.0] - 2026-06-11

### Added
- `feat(site)` Landing page with GitHub Pages deploy workflow (#103)
- `feat(site)` Hero terminal mock now shows `/auto-pilot` run in progress
- `feat(config)` Default merge strategy updated to `balanced` with `always-create` config (#103)

### Changed
- `feat(site)` Hero terminal mock reverted back to `/issue-resolver` from `/auto-pilot`

### Documentation
- `docs(readme)` Added live website link (luongnv.com/idd) (#103)

### Refactors
- `refactor(skills)` Added flat install surface for all IDD skills (#104, #105)

### Internal
- `chore(repo)` Removed tracked `dist/` folder from version control (#106, #107)
- `chore(seo)` Optimized landing page metadata and crawlability (#103)
- `chore(skills)` Added bundled dependency precheck to all 8 IDD skills (#108)

## [0.10.1] - 2026-06-03

### Changed
- Skill versions corrected for the behavior fixes that shipped in 0.10.0 without their own version ticks: `/issue-resolver` 0.7.1 → 0.7.2 and `/issue-pr-review` 0.5.0 → 0.5.1 (correct subagent invocation, #95); `/auto-pilot` 2.3.0 → 2.3.1 (never pass a skill name as `subagent_type`, #98, #99). No behavior change beyond what 0.10.0 already shipped — this release only aligns each skill's `metadata.version` and the README table with the fixes already in `main`.

## [0.10.0] - 2026-06-03

### Added
- `feat(auto-pilot)` Phase 5 dependency-aware merge gate. Before merging PR-A, the loop parses `Depends on #N` / `Blocked by #N` markers from the originating issue's body and verifies every referenced issue is closed and its PR merged. If any dependency is unsatisfied, the auto-pilot pauses with a structured alert (mirroring the critical-issue alert shape) and leaves PR-A open — the user merges the dependency, then re-runs `/auto-pilot` to resume. New iteration outcome label: `blocked_by_dependency`. New config: `autopilot.respect_dependencies: true` (default on). The convention is documented in `docs/idd-methodology.md` (Issue Dependencies). Self-reference cycle detection skips the gate to avoid infinite pauses (multi-hop cycles surface as repeated `blocked_by_dependency` outcomes); cross-repo references are out of scope. (#93)
- `feat(install)` `scripts/install.sh` now installs self-contained skills into agent tools beyond Claude Code: `agents`, `codex`, `opencode`, `pi`, `openclaw`, `hermes`, `antigravity`, and `windsurf`. New repeatable `--tool <name>` and `--tools <list|all>` flags, plus an interactive numbered picker when no tool is specified on a TTY (falls back to Claude Code in CI / `curl | bash` / piped contexts). Per-tool destination paths mirror `asm config show`; `--plugin`/`--all`/`--agents-only`/`--target` reject tools that lack the Claude-only layout, and unknown tool names are rejected. Adds `tests/test-install-script-tools.sh`. (#96, #97)

### Changed
- Skill versions: `/auto-pilot` 2.2.0 → 2.3.0 (new Phase 5 gate, `blocked_by_dependency` outcome, `autopilot.respect_dependencies` config key).

### Fixed
- `fix(skills)` `/issue-resolver` and `/issue-pr-review` SKILL.md now document the correct subagent invocation. Shared agents must be spawned with the Agent tool passing only `description` and `prompt` (the shared agent prompt) — never a `subagent_type` of a shared-agent or skill name (e.g. `code-reviewer`, `synthesizer`, `issue-resolver`), which are not registered agent types. Explicit `Agent()` invocation examples were added for every spawn point across the resolve and PR-review pipelines, fixing the "Agent type not found" error during QA cycles. (#95)
- `fix(auto-pilot)` the orchestrator no longer passes a skill name as `subagent_type` when spawning the resolver, PR reviewer, analyzer, or batch resolver. The convention — pass only `description` and `prompt`, invoke the skill from inside the prompt — is now explicit in the subagent prompts and the Phase spawn step, fixing the "Agent type 'issue-resolver' not found" error. (#98, #99)

### Internal
- `test(issue-pr-review)` decoupled stale test assertions from exact version pins: `test-config-schema-38` and `test-issue-pr-review-traceability` now use a `sort -V` semver floor for the `/issue-pr-review` version (surviving two-digit minors like `0.10.0`) instead of an exact `0.4.x` match, and `test-issue-pr-review-fix-loop-deprecation` scans the `### Deprecated`/`### Removed` subsections wherever they live rather than only `[Unreleased]`. No change to shipped skill behavior or CHANGELOG content. (#100, #101)
- `refactor(tests)` hardened the CHANGELOG subsection scan in `test-issue-pr-review-fix-loop-deprecation.sh` to avoid awk interval expressions that older one-true-awk builds treat as literals (which could silently let a stale entry pass). (#102)

## [0.9.0] - 2026-04-30

### Added
- `feat(issue-pr-review)` exempt refactor/chore PRs from the `Closes #N` traceability hard-fail. A PR is now exempt when either it carries a label in `review.traceability_exempt_labels` (default `["refactor", "chore"]`) or its body matches `review.traceability_exempt_pattern` (default recognizes `Type: refactor` / `Type: chore`, case-insensitive). The exemption applies only to check 1; checks 2–4 (commit reference, Decision Record, Acceptance Criteria Verification block) still run and report `partial` if absent. Strict issue #36 behavior is preserved when both keys are set to their empty values. (#91)
- `dist/agents/` generated Claude Code subagent definitions for every shared IDD agent, including `code-reviewer`, so standalone installs can register the agent types skills may invoke on fresh environments. (#89)

### Changed
- `scripts/install.sh` now installs shared agents to `~/.claude/agents/` alongside standalone skills, supports `--agents-only`, `--no-agents`, `--force-agents`, and `--uninstall`, and avoids overwriting unmanaged same-name agents unless explicitly forced. Plugin builds now also include a top-level `agents/` directory for Claude Code plugin subagent discovery. (#89)
- Skill versions: `/issue-pr-review` 0.4.2 → 0.5.0 (new exempt-PR config keys).

## [0.8.0] - 2026-04-30

### Added
- `feat(security)` shared pre-commit security scan — `docs/pre-commit-security.md` codifies the secret/credential/large-file gate adopted from `/auto-push`. Every skill that runs `git commit` or `git push` now invokes the scan before staging or pushing; real secrets block, warnings log and continue. Wired into `src/shared/agents/implementer.md`, `src/skills/issue-pr-review/SKILL.source.md` (auto-fix and fix-cycle steps), and `src/skills/issue-resolver/SKILL.source.md` (Step 5 push). `tests/test-pre-commit-security.sh` greps shell-fenced `git commit`/`git push` invocations and asserts each is gated by a reference to the canonical doc. (#87)
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
- `/issue-pr-review-fix-loop` (v0.4.0) — its outer review-fix loop, agent reuse, and fresh confirmation pass are all part of `/issue-pr-review` now (since v0.3.0), and Phase 2 acceptance-criteria + traceability checks landed there in v0.4.0. Migration: replace any `/issue-pr-review-fix-loop` invocation with `/issue-pr-review` (same PR number, same `--auto` flag). Source removed in [Unreleased]. Tracking issue: #37.

### Removed
- `/issue-pr-review-fix-loop` is removed from the public README command index and standalone install table. Its source was under `src/deprecated-skills/issue-pr-review-fix-loop/` and has been removed in [Unreleased]. Tracking issue: #54.
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
