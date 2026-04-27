# Idea: GitIssue — Issue-Driven Development (IDD)

> **Historical document — superseded by [`docs/idd-methodology.md`](idd-methodology.md).**
> This file captures the original product concept (early 2026) when the design assumed `/issue-creator` would auto-enrich issues with codebase context. That direction was reversed: issues now capture **intent only**, and codebase analysis lives in `/issue-analysis`, `/issue-triage`, and `/issue-resolver` against current code. Phrases like "codebase-aware issues", "auto-enriched", or "affected files in the issue body" are historical and do **not** describe the shipped behavior. See `docs/idd-methodology.md` for the current intent-code boundary.

## Original Concept

Introduce a new software development methodology called **Issue-Driven Development (IDD)**, more adapted to brownfield projects than greenfield. The core workflow is two commands:

- `/issue-creator` — Create structured, codebase-aware issues (supports batch creation from screenshots, text, docs)
- `/issue-resolver [number]` — Pick up an issue and work through research → plan → code → PR

This workflow is tightly integrated with GitHub/GitLab issue management — no extra layer.

## Clarified Understanding

IDD treats GitHub issues as the **atomic unit of all development work**. Every change — bug fix, feature, improvement — starts as an issue and ends as a PR linked to that issue. The key innovation is **issue normalization**: any issue, whether filed by a human via the GitHub UI or created by an AI agent, gets auto-enriched with codebase context (affected files, architecture constraints, acceptance criteria) before work begins.

The system is **agent-agnostic** — the same structured issue can be resolved by Claude Code, Codex, Devin, a human developer, or any future agent. No vendor lock-in.

### Key Design Decisions
- **Templates**: Start minimal, but handle messy human-filed issues via auto-normalization (`/issue-creator 42` enriches existing issue #42)
- **Approval gates**: Configurable — auto-proceed by default, comment-and-wait for teams
- **Existing issues**: `/issue-resolver` works on any issue; auto-normalizes if needed
- **Platform**: GitHub first, GitLab second, core logic platform-agnostic
- **Batch creation**: Supports extraction from screenshots, emails, planning docs (like github-issue-creator skill)
- **Triage**: `/issue-triage` generates dependency tables, priority ordering, stale detection
- **Plan phase**: Stays local (not posted as issue comment)

## Target Audience

1. **Solo developers / small teams** using GitHub for brownfield projects who want structured, AI-ready issue workflows without adopting heavy project management tools
2. **Teams using AI coding agents** (Claude Code, Codex, Copilot) who want a standardized issue format any agent can consume
3. **Open-source maintainers** who receive messy bug reports and want auto-normalization into actionable issues
4. **Engineering leads** who want dependency-aware triage and execution ordering

## Goals & Objectives

- **Primary**: Establish IDD as a recognized methodology for brownfield development
- **MVP Goal**: Working `/issue-creator` and `/issue-resolver` skills that integrate with GitHub
- **6-month Goal**: Community adoption, GitLab support, triage capabilities
- **12-month Goal**: Recognized as a standard approach for AI-agent-compatible issue workflows

### Success Metrics
- Issues created via GitIssue have higher first-PR-merge rate than manually created issues
- Time from issue creation to PR is measurably shorter with `/issue-resolver`
- At least 3 different AI agents can consume GitIssue-formatted issues without modification

## Technical Context

- **Stack**: Python (CLI core), Claude Code skills (markdown), GitHub CLI (`gh`) integration
- **Timeline**: MVP in 2-4 weeks, iterative improvement over 3-6 months
- **Budget**: Side project / open-source
- **Existing Assets**:
  - `github-issue-creator` skill (batch issue creation from screenshots/text)
  - Claude Code skill system (for `/issue-creator` and `/issue-resolver`)
  - `gh` CLI for GitHub API interaction

## The Four Commands

```
/issue-creator          — Create new structured issue(s) from text, screenshot, or batch input
/issue-creator 42       — Normalize an existing issue (enrich with codebase context)
/issue-resolver 42      — Branch → research → plan → code → PR
/issue-triage         — Review open issues: prioritize, detect deps, suggest execution order
```

## Discussion Notes

### Issue Normalization Flow
```
Human files issue via GitHub UI     AI creates via /issue-creator
  │ (messy, unstructured)              │ (already structured)
  └──────────┬─────────────────────────┘
             │
     /issue-resolver 42
             │
       ┌─────▼──────┐
       │ Is this     │── Yes ──→ Proceed to resolve
       │ normalized? │
       └─────┬───────┘
             No
             │
     Auto-run /issue-creator 42
     (enrich with codebase context)
             │
       Update issue in-place
             │
       Proceed to resolve
```

### Resolve Pipeline
```
issue-resolver 42
  │
  ├── 1. Fetch issue from GitHub
  ├── 2. Create branch (fix/42-short-description)
  ├── 3. Research phase (read affected files, trace deps)
  ├── 4. Plan phase (propose approach, local only)
  ├── 5. Execute (write code, write tests, atomic commits)
  ├── 6. Verify (run tests, check acceptance criteria)
  └── 7. Ship (create PR linked to issue, auto-close on merge)
```

### Configuration — .gitissue.yml
```yaml
platform: github
issue:
  auto_normalize: true
  template: default
  labels_auto_suggest: true
resolve:
  approval_gate: auto
  branch_prefix: "auto"
  auto_test: true
  pr_auto_link: true
triage:
  stale_threshold_days: 14
  auto_priority: true
```

### The IDD Pitch
Issue-Driven Development treats GitHub issues as the single source of truth for all development work. Two commands — /issue-creator and /issue-resolver — form a complete workflow that works for humans and AI agents alike. Issues are automatically enriched with codebase context, structured with consistent templates, and resolved through a research-plan-execute pipeline that produces atomic PRs. No extra tools, no sync overhead, no translation layer. The issue is the spec. The code is the delivery. Git tracks everything in between.
