# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!-- gitissue:normalized v1 -->

## [Unreleased]

### Features
- **skills:** ship `gi-secscan`, `gi-ci-wait`, `gi-issue`, and `gi-branch` (#252) — the second wave of deterministic scripts, replacing the four highest-frequency prose-executed procedures. `gi-secscan.py` is the pre-commit security gate as code: the same five rules as the canonical document (block on secret-bearing filenames and real API-key values, warn on large files, build artifacts, and protected branches), applied to `--staged` / `--working-tree` / `--range` / a stdin path list, printing one JSON verdict and **exiting 1 on a block**. That code is a verdict, not a runtime failure, and every call site says so explicitly — the default reading of a non-zero exit is "degrade", and degrading past a real secret is the one outcome the gate exists to prevent. Patterns extend per repository through a new `security.*` config section (`extra_secret_file_pattern`, `extra_secret_value_pattern`, `allow_pattern`, `max_file_size_mb`), which the script reads from `.gitissue.yml` itself. That is a security decision rather than a convenience: `.gitissue.yml` is repository-controlled and `/issue-pr-review` runs with a pull request's branch checked out, so any design where a caller interpolates a config *value* into the scan's command line would let a crafted value close its shell quoting and execute on the reviewer's machine at the moment the gate runs. No config value reaches a command line, and a test pins that. `gi-ci-wait.py` performs an entire CI wait inside one invocation and returns `pass`/`fail`/`pending`/`none`, replacing a poll loop that cost one agent tool call per poll; pending stays pending and an unmodeled check bucket counts as still-running, never as done. `gi-issue.py` serves repeat `gh issue view` reads from a short-lived `.gitissue/cache/` keyed by issue **and** field set, so a narrower cached read can never be served to a caller that asked for more; `--refresh`/`--invalidate` cover the read-after-write paths. `gi-branch.py` derives a branch name from an issue number, title, and type, and self-checks its output against the same grammar `idd-lint.py` enforces. Every replaced procedure survives as the documented fallback, and the pre-commit lint now accepts either the document or the script as the gate. The shared agents receive the scan path as a `{secscan_script}` spawn variable, since an emitted agent prompt cannot resolve a skill-relative path (issue #245). @luongnv89
- **build, skills:** add a scripts pipeline and ship `gi-config`, `gi-runlog`, `gi-deps` (#251) — `scripts/build.py` gains a third closure kind beside shared agents and runtime docs: a bare `shared/scripts/<name>.py` token in a skill's own files (or in a runtime doc reachable from them) resolves against the new `src/shared/scripts/` tree and is copied — byte-identical, `shutil.copy2` so the committed `0755` survives — into that skill's `references/scripts/`. Discovery is regex plus filesystem, so **adding a script needs no `build.py` change**; the token is directory-scoped because a bare `scripts/X.py` form collides with the prose mentions of this repo's own `scripts/` directory already inside the closure read set. Scripts are closure **leaves** (a `.py` comment can never drag a doc into a bundle), they render as absolute repo URLs inside agent prompts and are therefore not bundled when reachable only through an agent (issue #245), and a script may declare `# gi-requires: references/…` to make the build fail if a file it reads at run time is not bundled alongside it. Three scripts ship: `gi-config.py` *derives* the defaults from the bundled `config-schema.md` rather than restating them, validates `.gitissue.yml` against it, and prints the merged config as one JSON line — the six reader skills now load config with it instead of six prose copies of the same defaults; `gi-runlog.py` validates and normalizes one `runs.jsonl` record (5→3 `complexity` collapse, null-drop, `ts` fill, canonical key order) and either appends it or, with `--echo`, prints it and writes nothing — the machine form of the `--no-run-log` single-writer contract; `gi-deps.py` (the promoted `scripts/dependency_gate_parse.py`) parses local dependency issue numbers for the auto-pilot merge gate, which no longer cites a path that does not exist inside an installed skill. Every invocation keeps its prose fallback: a missing bundled file is fatal (the precheck list guarantees it shipped), while a runtime failure — no `python3`, a non-zero exit other than 3, unparsable stdout — prints a `⚠` line and follows the documented manual procedure. Shared exit codes are `0` ok, `2` usage, `3` invalid input (stop), `4` cannot complete (degrade). @luongnv89
- **resolver, review:** adapt effort to task complexity (#240) — `/issue-resolver` picks a pipeline **profile** (`light`/`full`) from the issue's pre-work `Effort` band before any subagent spawn, so trivial issues (XS/S) take a fast path (lighter Research, skipped 3-option Plan, skipped propose-skills, QA capped at 1 cycle) while complex or ambiguous work keeps the full pipeline; `/issue-pr-review` scales review depth from a diff-size/labels/linked-issue signal (fuller-of-disagreeing). The Decision Record + Acceptance Criteria table always emit, and the AC + traceability hard-blocks always run at full strength. The chosen profile is surfaced on the tracker line and in the `runs.jsonl` `profile` field. Opt out with `resolve.adaptive_effort: false` / `review.adaptive_depth: false` (both default `true`). Shared mechanism documented in `docs/agent-model-effort.md` (Complexity → pipeline profile). @luongnv89

### Fixes
- **skills:** fix disclosure gates and add checkable step completion criteria (#250) — five predictability gaps that let runs diverge or declare success with nothing to check. (1) `/issue-analysis` gated every-run-mandatory material behind "read that file when tuning/debugging", so the delegation payload and the Step 8-9 rendering/JSON spec could be skipped entirely; those pointers now read **read now**, and the 12.7KB no-Agent-tool procedure they shared a file with moved to its own `references/inline-fallback.md`, gated the other way — read **only** when the Agent tool is unavailable. `/issue-triage`'s `references/detection.md` pointer got the same inversion fix. (2) `/init-gitissue` reported `Config: ✓ generated` without ever reading the file back; it now re-parses the written `.gitissue.yml` as YAML, greps for surviving `{placeholder}` tokens, checks `platform` is present, and reports `DONE` only when all three hold (`PARTIAL` when no YAML parser exists, a rich error and stop on a real failure). (3) `/issue-resolver`, `/issue-pr-review`, `/auto-pilot` and `/issue-triage` now close every step with a **Step Completion Report** — `√`/`×` per check plus `Result: PASS | PARTIAL | FAIL` — with the format, the `PARTIAL`-vs-`FAIL` semantics and the per-step check names owned by each skill's own reference file (`report-templates.md` / `summary-format.md` / `output-and-persist.md`) so all seven built `SKILL.md` files stay under the 500-line cap. Checks are gates that could have failed, never restatements of a tracker metric, so the #165 de-duplication holds. `√`/`×` join `docs/terminal-style.md` as check glyphs distinct from the `✓`/`✗` status symbols. (4) `/issue-creator` no longer runs a mandatory stash-and-rebase before remote-only work: every write it performs goes out through `gh issue edit` or the GitHub contents API, so the sync protected nothing while being able to conflict-stop a pure create; the stash-first convention still applies, scoped to a run that actually writes the working tree. (5) The eight skill READMEs moved to the skill-creator standard `docs/README.md` and carry the AI-skip notice, with their doc references rewritten as absolute repo URLs so the relocated depth cannot dangle. @luongnv89
- **build, agents:** deliver the shared-agent conventions inside every injected subagent prompt (#245) — a spawned subagent's working directory is the **target repo**, not the skill directory, so the skill-relative `references/docs/shared-agent-conventions.md` that all eight shared agents cited resolved to nothing, and the rules it carries — prompt-injection boundary, read-only/full-access tool posture, the `gh --json` rule, the 0–100 confidence scale, autonomous operation, output discipline — silently never loaded into any of the 13 built agent prompts. `scripts/build.py` now splices six sections of `docs/shared-agent-conventions.md` **verbatim** into every emitted agent prompt (inside the `## Prompt` fence for the agents that have one, so the rules survive even when an orchestrator injects only the fence body), adding the confidence scale for `code-reviewer`/`ui-reviewer` only; the same preamble reaches the standalone `dist/agents/` and `.pi/agents/` outputs. The document stays the single source of truth — the six headings are matched exactly and a renamed, removed, or emptied section **aborts the build** rather than shipping a silently truncated preamble. Placement is guarded too, since a preamble emitted outside the injected fence would leave the rules unreachable while every heading-shaped assertion still passed: the build aborts when an agent declares `## Prompt` without a parsable opening fence, and when an inlined section body carries a ``` fence that would close the agent's prompt fence early. Logical references inside agent files now render as absolute repo URLs instead of skill-relative paths, so the `docs/agent-model-effort.md`, `docs/naming-conventions.md` and `docs/pre-commit-security.md` citations no longer dangle either, and the implementer's last skill-relative pointer resolves to the reproduction checklist its own prompt already spells out. Bundling is untouched: the transitive closure still scans the authored sources, so every skill ships exactly the docs it did before and every runtime *Bundled dependency precheck* list still resolves. @luongnv89
- **creator, triage:** add auto-mode carve-outs to the interactive gates (#244) — six confirmation gates had no defined non-interactive behavior, so autonomous runs could stall waiting for input that never arrives; the Normalize apply gate was a live deadlock for any orchestrator driving mid-loop normalization. The convention is now stated once in a new runtime doc `docs/auto-mode.md` — detection (`--auto` or `IDD_AUTO_MODE=1`, never caller provenance alone), the log-and-proceed gate rule, the `⚠` line format, and the safety stops auto mode must **not** weaken — and the gates cite it instead of restating detection per gate. In auto mode: the duplicate warning proceeds (naming the suspect), the create preview and batch approval auto-approve (batch logs the count and takes `[A]ll`, never `[e]dit`/`[c]ancel`), normalization auto-applies (never `dry-run`, and the mandatory backup still aborts on failure), issue-creator's mandatory pre-write repo sync aborts cleanly instead of asking, and issue-triage syncs without prompting. Interactive invocations are byte-for-byte unchanged — every gate still shows and still waits. Step summaries report `auto-approved` rather than claiming a human approved. The caller half is fixed too: `/auto-pilot` now states that every skill it delegates to — including the optional mid-loop `/issue-creator` normalization that made this a live deadlock — is invoked with `--auto` **and** `IDD_AUTO_MODE=1`, never relying on the callee detecting auto-pilot provenance, and it bundles `docs/auto-mode.md` so it can read the contract it is bound by. @luongnv89
- **auto-pilot:** continue the loop when a merge is dependency-blocked (#243) — the Phase 5.1b dependency gate (and the Phase 3-4 partial-merge path) still **never** merges out of `Depends on #N` / `Blocked by #N` order, but a blocked PR no longer ends the run: the iteration records `blocked_by_dependency`, the PR is left open and unchanged, the issue joins the session skip list (so the continuing loop cannot re-pick it and write a second run-log line), and the loop advances to the next eligible issue. A 30-issue backlog with one blocked PR now resolves the other 29 instead of halting at iteration 3. Dependency-blocking is no longer a stop-and-ask autonomy exception — critical-issue review failure is the only one left — and the loop stops on dependency grounds only through the existing `⚠ No eligible issues to pick` condition. SPEC §2 merge-order semantics are unchanged. @luongnv89

## [v0.18.0] — 2026-07-09

The Fable 5 review release: implement all seven recommendations (R1–R7) of the concept & methodology review — extract the spec, shrink the machinery, prove the methodology without an agent, and measure it.

### Features
- **lint:** add `scripts/idd-lint.py` — dependency-free IDD Spec conformance checker (issue/PR/commit/branch/repo modes, L1–L3 levels, no LLM) @luongnv89
- **lint:** add `stats` mode — evidence report with trace completeness, Decision-Record coverage, and resolution outcomes by issue quality, rendered with verdict meters @luongnv89

### Documentation
- **spec:** extract the tool-neutral IDD Spec (`SPEC.md`, v1.1) — issue contract, dependency + `Part of #N` hierarchy markers, naming grammar, Decision Record with three durable-memory bindings, L1–L3 conformance levels; gitissue repositioned as the reference implementation @luongnv89
- **methodology:** rewrite under the single name Issue-Driven Development; add Hierarchy of Intent (epics), the manual-IDD quickstart (`docs/manual-idd-quickstart.md`), and read-side retrieval recipes @luongnv89

### Refactoring
- **platform:** concentrate tracker access behind the GitHub driver doc (`docs/platform-github.md`); retire the unbuilt `gitlab` platform value @luongnv89
- **prose:** debloat the surface (−305 lines) — drop the stale README version table, dedupe README vs methodology, cut all eight agent personas, state boilerplate once, present a 10-field core config @luongnv89
- **skills:** skill-auto-improver sweep across issue-* skills (#176) @luongnv89

### Removed
- **install:** the shell installer (`install.sh`, `scripts/install.sh` — 855 lines, git side effects, npm upsell) and the Claude-only plugin layout (tarball release job, `dist/plugin/`, ~1/3 of build.py). Install via `asm install https://github.com/luongnv89/idd` or manual copy from `skills/`; the curl one-liner and plugin tarball paths no longer exist @luongnv89

**Full Changelog**: https://github.com/luongnv89/idd/compare/v0.17.0...v0.18.0

## [v0.17.0] — 2026-07-01

### Features
- **issue-resolver:** index luongnv89/skills and propose skills per task (#175) @luongnv89

### Refactoring
- **agents:** define severity high/medium boundary for reviewers (#173) @luongnv89
- **skills:** improve all skills to skill-creator standard via auto-improver (#171) @luongnv89

**Full Changelog**: https://github.com/luongnv89/idd/compare/v0.16.0...v0.17.0

## [v0.16.0] — 2026-06-28

### Features
- **monitoring:** add .gitissue/runs.jsonl run-log + idd-doctor summary (#154) @luongnv89
- **issue-resolver:** add complexity-gated design-confirm checkpoint (#164) @luongnv89
- **issue-pr-review:** group review findings under Spec and Standards axes (#163) @luongnv89
- **landing:** add frozen snow/ice/water effect to nav, buttons, terminal (#151) @luongnv89
- **agents:** add famous-persona profiles to all 8 shared sub-agents (#138) @luongnv89
- **landing:** add Ice Driven Development cooldown-launch skin (#136) @luongnv89
- **shared:** add auto-detecting UI/UX reviewer agent (#131) @luongnv89
- **resolver:** require red-capable verification before bug fixes (#146) @luongnv89
- **install:** refresh skills on re-run and offer asm first (#169) @luongnv89
- **resolver:** in-place workspace default in auto mode (#130) @luongnv89

### Bug Fixes
- **monitoring:** fan batch-resolver run-log out to one line per attempted issue (#161) @luongnv89
- **monitoring:** make /auto-pilot the single runs.jsonl writer per issue (#159) @luongnv89
- **landing:** repair hero/card layout, add screenshot slideshow, simplify install (#153) @luongnv89
- **landing:** vendor agent-team portraits locally so they always load (#144) @luongnv89
- **landing:** tune frost effect — shorter tapered icicles, softer snow (#149) @luongnv89
- **landing:** remove frost effects, keep only falling ice cubes (#148) @luongnv89

### Refactoring
- **review:** detect no-GUI environment and report headless capture mode (#168) @luongnv89
- **issue-resolver:** collapse duplicate end-of-run output into one closing summary (#167) @luongnv89
- **agents:** concise persona-labeled shared agents with I/O contracts (#162) @luongnv89
- **issue-creator:** make intent clarification active (#145) @luongnv89

### Documentation
- **landing:** shorten hero tagline and align meta copy (#157) @luongnv89

### Other Changes
- **build:** verify dist skills before promoting skills/ (#166) @luongnv89
- **skills:** bump versions for bug-verification feature (#152) @luongnv89

**Full Changelog:** https://github.com/luongnv89/idd/compare/v0.15.0...v0.16.0

## [v0.15.0] — 2026-06-20

### Features
- **issue-resolver:** offer interactive worktree resolution (#128) @luongnv89
- **issue-creator:** cache model data at skill level with dated filename (#127) @luongnv89
- **issue-creator:** always suggest one OpenAI + one Anthropic model (#122) @luongnv89

### Bug Fixes
- **issue-creator:** stream image base64 via stdin to avoid ARG_MAX (#126) @luongnv89

### Other Changes
- **landing:** highlight model and thinking level on issue create @luongnv89

**Full Changelog:** https://github.com/luongnv89/idd/compare/v0.14.0...v0.15.0

## [v0.14.0] — 2026-06-15

### Features
- **issue-creator:** add model suggestion with cache management (#119) @luongnv89

### Bug Fixes
- **nav:** repair broken landing-page nav links and deploy changelog (#120) @luongnv89
- **nav:** unify navigation bar across all pages (#115) @luongnv89

### Other Changes
- **issue-creator:** enable model_suggestion by default (#121) @luongnv89
- **config:** add .gitissue.yml with balanced merge default @luongnv89
- **docs:** format CSS, unify footer structure (#116) @luongnv89

**Full Changelog:** https://github.com/luongnv89/idd/compare/v0.13.0...v0.14.0
