# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!-- gitissue:normalized v1 -->

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
