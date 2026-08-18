# Skill Index — Optional External Skills (luongnv89/skills)

A reference catalog of the skills published at
`https://github.com/luongnv89/skills`, grouped by the lifecycle phase each one
serves. The Step 3 propose-and-select sub-step (see `references/pipeline-steps.md`,
*Step 3 — Propose relevant skills*) reads this index to decide which skills to
offer for the analyzed task. SKILL.md references this file at Step 3 — do not
inline the catalog back into SKILL.md.

The index answers one question: **what skills exist, and what is each one for?**
It does **not** record which are installed — that is detected at runtime against
`~/.claude/skills/` (the propose sub-step intersects this catalog with the
installed set). Keep the two concerns separate: this file is the *catalog*, the
filesystem is the *availability* signal.

## Source-agnostic by design

The detection and proposal logic must never hardcode `luongnv89/skills`
assumptions. It treats this file as the **swappable candidate list**: it reads
the skill names + lifecycle phases below, intersects them with what is
installed, and proposes the relevant subset. Re-pointing the catalog at a
different upstream is then a *contents swap of this file*, not a rewrite of the
step logic. Each entry's **name == the installable / invocable skill name** (the
`luongnv89/skills` directory name and `name:` frontmatter), so runtime detection
(`~/.claude/skills/<name>`) and invocation (`/<name>`) match without
translation.

## Lifecycle coverage

The catalog is grouped so a proposal can span the full task lifecycle —
**implementation, verification, testing, documentation** — naming a covering
subset for the analyzed task. Skills outside the core code-resolution lifecycle
(marketing, app-store, infra) are listed last under *Adjacent* and proposed only
when the task clearly calls for them.

### Implementation

| Skill | Purpose |
|-------|---------|
| `cli-builder` | Build a production-quality CLI tool for a module/app (auto-detects language, recommends CLI libraries). |
| `frontend-design` | Build production-grade frontend interfaces with distinctive aesthetics and working code (UI work). |
| `install-script-generator` | Generate a cross-platform `install.sh` runnable via a single curl/wget one-liner. |
| `website-cloner` | Build an improved website clone from a URL (6-phase Vite/React/shadcn/Tailwind). |

### Verification (review / code quality / security)

| Skill | Purpose |
|-------|---------|
| `code-review` | Review code changes for bugs, security vulnerabilities, and quality issues; prioritized findings + fixes. |
| `clean-code` | Audit code against the bbv Clean Code Cheat Sheet → `CLEAN_CODE_AUDIT.md` + a phased plan. |
| `code-optimizer` | Analyze code for performance bottlenecks, memory leaks, and algorithmic inefficiencies. |
| `slop-cleanup` | Refactor a codebase to remove AI slop, dead code, weak types, and duplication. |
| `dont-make-me-think` | Review UI for usability issues (Steve Krug's principles) from screenshots, URLs, or code. |
| `security-setup` | Install local-first security hardening: pre-commit secret detection, dep scans, static analysis. |

### Testing

| Skill | Purpose |
|-------|---------|
| `test-coverage` | Generate unit tests for untested branches and edge cases. |

### Documentation

| Skill | Purpose |
|-------|---------|
| `docs-generator` | Generate and restructure project documentation into a clear hierarchy. |
| `readme-to-landing-page` | Transform a `README.md` into a conversion-optimized landing page (markdown). |
| `agent-config` | Create or update `CLAUDE.md` / `AGENTS.md` following best practices. |
| `subagent-creator` | Create, evaluate, or improve Claude Code subagent files (`.claude/agents/*.md`). |
| `drawio-generator` | Generate diagrams as valid draw.io XML (flowcharts, architecture, C4, ER, sequence). |
| `excalidraw-generator` | Generate diagrams as valid Excalidraw JSON. |
| `tad-generator` | Generate a Technical Architecture Document (TAD) from a PRD. |

### Planning / product (pre-implementation)

| Skill | Purpose |
|-------|---------|
| `prd-generator` | Generate a Product Requirements Document from `idea.md` / `validate.md`. |
| `tasks-generator` | Generate development tasks from a PRD with sprint planning. |
| `idea-validator` | Validate an app/startup idea (market, feasibility, commercial, OSS competitor analysis). |

### Release / CI / open-source

| Skill | Purpose |
|-------|---------|
| `devops-pipeline` | Configure pre-commit hooks + lean GitHub Actions (shift-left QA). |
| `release-manager` | Manage releases end-to-end: bump version, changelog, tag, push, GitHub release, publish. |
| `auto-push` | Generate a commit message, stage changes, and push after a secret/large-file/protected-branch scan. |
| `oss-ready` | Add `LICENSE`, `README`, `CONTRIBUTING`, `CODE_OF_CONDUCT`, `SECURITY`, issue/PR templates. |

### Adjacent (propose only when the task clearly calls for it)

| Skill | Purpose |
|-------|---------|
| `appstore-review-checker` | Audit iOS/macOS projects against Apple App Store Review Guidelines. |
| `aso-marketing` | Optimize App Store / Google Play listings (ASO). |
| `brand-name-checker` | Check product/brand names for conflicts (trademark/domain/social/registry). |
| `landing-page-generator` | Conversion-focused landing page copy (PAS / AIDA / StoryBrand). |
| `logo-designer` | Generate SVG logos (7 brand variants) + a showcase HTML page. |
| `ollama-optimizer` | Optimize Ollama configuration for the current machine's hardware. |
| `opencode-runner` | Run coding tasks via opencode using free cloud models. |
| `seo-ai-optimizer` | Audit/optimize websites for SEO + AI bot accessibility. |
| `tmux-agent-comms` | Manage AI agents in tmux (spawn/kill/message CLI agents). |
| `viral-product-evaluator` | Review a product against 32 viral principles → a Virality Score. |

## Maintenance

This catalog is hand-maintained. To refresh it against the upstream repo, list
the published skills and their one-line purposes:

```bash
gh api 'repos/luongnv89/skills/git/trees/HEAD?recursive=1' \
  --jq '.tree[] | select(.path | test("/SKILL\\.md$")) | .path'
```

Then read each `skills/<name>/SKILL.md` frontmatter `name:` + `description:` and
re-group by lifecycle phase. The skill names here are the contract for runtime
detection — keep them exactly matching the upstream directory names.
