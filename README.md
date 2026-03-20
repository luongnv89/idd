# gitissue — Issue-Driven Development (IDD)

**Two commands. Structured issues. Atomic PRs.**

gitissue introduces Issue-Driven Development — a methodology where GitHub issues are the single source of truth for all development work. Issues are automatically enriched with codebase context, structured with consistent templates, and resolved through a research-plan-execute pipeline that produces atomic PRs.

Works for humans and AI agents alike. No extra tools, no sync overhead.

## Quick Start

### Prerequisites

- [GitHub CLI](https://cli.github.com) (`gh`) 2.0+ — authenticated via `gh auth login`
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) or any agent supporting the SKILL.md standard
- Git 2.30+

### Installation

Clone the repo and add the skills to your Claude Code project:

```bash
git clone https://github.com/luongnv89/idd.git
cd idd
```

Add to your project's `.claude/settings.json`:

```json
{
  "skills": [
    "./skills/issue-creator",
    "./skills/issue-resolver",
    "./skills/issue-triage",
    "./skills/init-gitissue"
  ]
}
```

### Usage

```bash
# Create a new structured issue from a description
/issue-creator The login page shows a 500 error when using SSO

# Normalize an existing messy issue
/issue-creator 42

# Resolve an issue end-to-end (branch → research → code → PR)
/issue-resolver 42

# Triage open issues — dependencies, priorities, execution order
/issue-triage

# Generate project config
/init-gitissue
```

## Commands

| Command | Description |
|---------|-------------|
| `/issue-creator <text>` | Create a structured, codebase-aware issue from a description |
| `/issue-creator <N>` | Normalize existing issue #N with codebase context |
| `/issue-resolver <N>` | Full resolution pipeline: fetch → branch → research → plan → code → test → PR |
| `/issue-triage` | Dependency graph, priority suggestions, stale detection, execution order |
| `/init-gitissue` | Scan repo and generate `.gitissue.yml` with sensible defaults |

## Configuration

gitissue works with zero configuration. All settings have sensible defaults.

To customize, create `.gitissue.yml` in your repo root:

```yaml
platform: github                # github | gitlab (future)

issue:
  auto_normalize: true          # auto-normalize in /issue-resolver
  template: default             # default | path to custom template dir
  labels_auto_suggest: true     # auto-suggest labels based on content
  normalize_comment: true       # add comment when normalizing

resolve:
  approval_gate: auto           # auto | comment-and-wait
  branch_prefix: "issue-"       # branch naming: issue-42/short-description
  auto_test: true               # run tests before creating PR
  test_timeout: 300             # abort verify phase after N seconds
  pr_auto_link: true            # include "Closes #N" in PR body
  max_commits: 10               # warn if resolve produces >N commits

triage:
  stale_threshold_days: 14      # flag issues with no activity
  auto_priority: true           # suggest priorities based on type + age + deps
  include_closed: false         # include recently closed issues in triage
```

Or run `/init-gitissue` to auto-generate one based on your repo.

## What is IDD?

Issue-Driven Development treats GitHub issues as the atomic unit of all development work. Every change — bug fix, feature, improvement — starts as an issue and ends as a PR linked to that issue.

The key innovation is **issue normalization**: any issue, whether filed by a human via the GitHub UI or created by an AI agent, gets auto-enriched with codebase context (affected files, architecture constraints, acceptance criteria) before work begins.

The system is **agent-agnostic** — the same structured issue can be resolved by Claude Code, Codex, Copilot, a human developer, or any future agent. No vendor lock-in.

### The Workflow

```
Developer describes a problem
        │
   /issue-creator
        │
   Structured issue with codebase context
        │
   /issue-resolver N
        │
   ┌────┴────────────────────────────┐
   │ Fetch → Branch → Research →     │
   │ Plan → Execute → Verify → Ship  │
   └────┬────────────────────────────┘
        │
   Atomic PR linked to issue
        │
   Review → Merge → Issue auto-closes
```

## Issue Templates

gitissue ships with three default templates:

- **Bug** — reproduction context, affected files, current vs expected behavior
- **Feature** — user story, acceptance criteria, technical constraints
- **Improvement** — current state, proposed change, migration notes

Each normalized issue includes:
- `<!-- gitissue:normalized v1 -->` marker for detection
- Reporter's original text preserved in a blockquote
- Confidence markers on auto-enriched fields: `(high confidence)`, `(needs review)`

## License

MIT
