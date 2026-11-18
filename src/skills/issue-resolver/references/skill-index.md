# Skill Index — Optional External Skills (luongnv89/skills)

A reference catalog of the skills published at
`https://github.com/luongnv89/skills`, grouped by the lifecycle phase each one
serves. The Step 3 propose-and-select sub-step (see `references/steps/step-3-implement.md`,
*Step 3 — Propose relevant skills*) reads this index to decide which skills to
offer for the analyzed task.

The index answers one question: **what skills exist, and what is each one for?**
It does **not** record which are installed — that is detected at runtime against
`~/.claude/skills/`. Keep the two concerns separate: this file is the *catalog*,
the filesystem is the *availability* signal.

Default (`resolve.borrow_skills: false`): the propose set is **installed-only**.
When `resolve.borrow_skills: true`, a catalogued-but-missing name is
**available to borrow** for one task (install, record origin, uninstall only
`origin: borrowed` — `references/steps/step-3-implement.md`).

Each name is the installable,
invocable skill name (directory and `name:` frontmatter), so detection
(`~/.claude/skills/<name>`) and invocation (`/<name>`) need no translation.

A run whose change matches a practice pack applies the checkable core of the
engineering skills below (*Step 3 — Practice packs*); a proposed skill adds its
full workflow on top.

## Lifecycle coverage

The catalog is grouped so a proposal can span the full task lifecycle —
**implementation, verification, testing, documentation** — naming a covering
subset for the analyzed task. Skills outside the core code-resolution lifecycle
(marketing, app-store, web search) are listed last under *Adjacent* and proposed
only when the task clearly calls for them.

### Implementation

| Skill | Purpose |
|-------|---------|
| `cli-builder` | Build a production-quality CLI for a module or app (detects the language, approval-gated steps). |
| `frontend-design` | Build production-grade frontend interfaces with working code (UI work). |
| `install-script-generator` | Generate a cross-platform `install.sh` runnable via a single curl/wget one-liner. |

### Verification (review / code quality / security / UX)

| Skill | Purpose |
|-------|---------|
| `code-review` | Review or improve code in four modes: bug/security review, performance, clean-code audit, slop cleanup. |
| `codebase-modernizer` | Audit a stale or inherited codebase (deps, bugs, security, tests, CI, docs, UI/UX) into a phased, tested plan. |
| `security-setup` | Install local-first security hardening: pre-commit secret detection, dependency scans, static analysis. |
| `dont-make-me-think` | Review UI usability against Steve Krug's principles from screenshots, URLs, or code. |
| `ux-ax-review` | Review UX for humans and AX for AI agents and search; evidence-backed audit and plan. |
| `design-optimizer` | Audit a site or app design in one run: usability, UX/AX, virality, agent readiness. |

### Testing

| Skill | Purpose |
|-------|---------|
| `test-coverage` | Generate unit tests for untested branches and edge cases. |
| `user-test` | Test an app, API or CLI like a real user: launch it, try features, log bugs, performance and UX issues. |

### Documentation

| Skill | Purpose |
|-------|---------|
| `doc-manager` | Generate or update docs to match the code, citing each claim to `path:line`. |
| `agent-config` | Create, update, or audit `AGENTS.md` / `CLAUDE.md` agent instructions. |
| `diagram-generator` | Generate a diagram as draw.io XML (flowcharts, architecture, C4, ER, sequence) or Excalidraw JSON. |
| `tad-generator` | Generate a Technical Architecture Document (TAD) from a PRD. |

### Planning / product (pre-implementation)

| Skill | Purpose |
|-------|---------|
| `prd-generator` | Generate a Product Requirements Document from `idea.md` / `validate.md`. |
| `tasks-generator` | Generate sprint-based development tasks from a PRD. |
| `idea-validator` | Validate an app/startup idea (market, feasibility, commercial, OSS competitors). |
| `product-planner` | Plan a product from idea to sprint tasks in one run. |

### Release / CI / open-source

| Skill | Purpose |
|-------|---------|
| `devops-pipeline` | Configure pre-commit hooks and lean GitHub Actions (shift-left QA). |
| `ship` | Run a release end to end: version bump, changelog, tag, push, GitHub release, publish. |
| `auto-push` | Generate a commit message, stage changes, and push after a secret/large-file/protected-branch scan. |
| `oss-ready` | Add `LICENSE`, `README`, `CONTRIBUTING`, `CODE_OF_CONDUCT`, `SECURITY`, issue/PR templates. |
| `github-pages-publish` | Publish or update a static site on GitHub Pages via GitHub Actions. |
| `cleanup-project` | Prepare a repo before new work: uncommitted changes, `.gitignore`, merged branches. |

### Adjacent (propose only when the task clearly calls for it)

| Skill | Purpose |
|-------|---------|
| `appstore-review-checker` | Audit iOS/macOS apps against Apple App Store Review Guidelines. |
| `appstore-assets` | Generate App Store screenshots, header images and preview videos. |
| `aso-marketing` | Optimize App Store / Google Play listings (ASO). |
| `brand-name-checker` | Check product/brand names for conflicts (trademark/domain/social/registry). |
| `landing-page-generator` | Write landing pages (PAS, AIDA, StoryBrand) as HTML. |
| `logo-designer` | Generate SVG logos (7 brand variants) + a showcase HTML page. |
| `seo-ai-optimizer` | Audit/optimize websites for technical SEO, content SEO and AI bot access. |
| `search-optimizer` | Optimize a site or app for SEO, AI-bot search and app-store search in one run. |
| `website-agent-readiness` | Scan a site for agent readiness and fix what it reports. |
| `ollama-optimizer` | Optimize Ollama configuration for the current machine's hardware. |
| `opencode-runner` | Run coding tasks via opencode using free cloud models. |
| `viral-product-evaluator` | Review a product against 32 viral principles → a Virality Score. |
