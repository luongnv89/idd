# CLAUDE.md — gitissue / IDD

## Project Overview

gitissue implements Issue-Driven Development (IDD) — a methodology where GitHub issues are the single source of truth for all development work. The product is a set of Claude Code skills that create, normalize, resolve, and triage GitHub issues.

## Architecture

This is a **skills-only** project. There is no runtime code — each skill is a self-contained Claude Code skill (SKILL.md + references/ + templates/) that instructs the agent how to perform a task.

```
skills/
├── create-issue/       # /create-issue and /create-issue N (normalization)
│   ├── SKILL.md
│   ├── templates/      # Issue templates (bug, feature, improvement)
│   └── references/     # Error messages, detailed patterns
├── resolve-issue/      # /resolve-issue N
│   ├── SKILL.md
│   └── references/
├── triage-issues/      # /triage-issues
│   ├── SKILL.md
│   └── references/
└── init-gitissue/      # /init-gitissue
    ├── SKILL.md
    └── references/
```

## Conventions

### GitHub CLI
- Every `gh` call MUST use `--json` with explicit field selection
- Example: `gh issue view 42 --json number,title,body,labels,assignees,state`
- Never parse text output from `gh`

### Terminal Output
- Follow DESIGN.md symbol vocabulary: `✓ ✗ ● ◆ ⚡ ⚠ ○`
- Section separators: `┄` (light dash)
- Table characters: `│ ─ ┼`
- Two-space indent for content under headers
- URLs always on their own line
- Rich error format: what went wrong + fix command + docs link

### Issue Templates
- Normalization marker: `<!-- gitissue:normalized v1 -->`
- Standard sections: Type, Context, Description, Acceptance Criteria, Technical Notes, Metadata
- Reporter's original text preserved in `> Reporter Context` blockquote
- Confidence markers: `(high confidence)`, `(needs review)`

### Configuration
- `.gitissue.yml` loaded ONCE at skill start, not re-read at each step
- Zero-config: all defaults applied when no config file exists
- First-run hint: `○ First run — using default config. Run /init-gitissue to customize.`

### Skills
- Each skill follows the skill-creator standard (frontmatter with name/description, progressive disclosure)
- Each skill has its own `references/error-messages.md`
- Skills are isolated — no cross-skill imports or shared state
- Static sequential output — each step prints a new line, no terminal animation

### Testing
- Integration tests in `tests/` directory
- Shell scripts that verify skill behavior against real or mock GitHub repos
