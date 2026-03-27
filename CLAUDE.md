# CLAUDE.md — gitissue / IDD

## Project Overview

gitissue implements Issue-Driven Development (IDD) — a methodology where GitHub issues are the single source of truth for all development work. The product is a set of Claude Code skills that create, normalize, resolve, and triage GitHub issues.

## Architecture

This is a **skills-only** project. There is no runtime code — each skill is a self-contained Claude Code skill (SKILL.md + references/ + templates/) that instructs the agent how to perform a task. Shared agents live in `shared/agents/` and are referenced by multiple skills.

```
shared/
└── agents/                    # Shared agent definitions (used by multiple skills)
    ├── codebase-researcher.md # Deep codebase scan + solution research
    ├── synthesizer.md         # Analysis + implementation options
    ├── implementer.md         # Code + tests implementation
    ├── code-reviewer.md       # Confidence-based code review
    ├── duplicate-detector.md  # Issue dedup scoring
    └── issue-relationship-scanner.md  # File deps + already-fixed detection

skills/
├── auto-pilot/         # /auto-pilot — triage, resolve, review, merge loop
│   ├── SKILL.md
│   └── references/
├── issue-analysis/     # /issue-analysis N — deep issue investigation
│   ├── SKILL.md
│   └── references/
├── issue-creator/      # /issue-creator — create/normalize/batch issues
│   ├── SKILL.md
│   ├── templates/      # Issue templates (bug, feature, improvement)
│   └── references/
├── issue-resolver/     # /issue-resolver N — 6-step resolve pipeline
│   ├── SKILL.md
│   └── references/
├── issue-triage/       # /issue-triage — prioritize and order issues
│   ├── SKILL.md
│   └── references/
├── issue-pr-review/    # /issue-pr-review — review, test, CI check, fix, merge
│   ├── SKILL.md
│   └── references/
├── issue-pr-review-fix-loop/  # /issue-pr-review-fix-loop — outer review-fix loop with fresh context per cycle
│   ├── SKILL.md
│   └── references/
├── review-fix-loop/    # DEPRECATED — redirects to /issue-pr-review
│   ├── SKILL.md
│   └── references/
└── init-gitissue/      # /init-gitissue — generate .gitissue.yml
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

### Naming Conventions

All skills that create branches, commits, PRs, or issues follow these conventions. The full standalone reference is at `docs/naming-conventions.md` — skills reference that document directly so the conventions work with any tool, not just Claude.

#### Branch Names

Format: `<type>/<issue-number>-<short-description>`

- **Lowercase only**, words separated by **hyphens** (never spaces or underscores)
- Always include the **issue number** for traceability
- Keep the description **short and readable** (under 50 characters total)
- Type prefix matches the issue type:

| Type prefix | When to use | Example |
|-------------|-------------|---------|
| `fix/` | Bug fixes | `fix/42-mobile-auth-redirect` |
| `feat/` | New features | `feat/15-dark-mode-toggle` |
| `refactor/` | Improvements, tech debt | `refactor/8-cleanup-auth-module` |
| `docs/` | Documentation changes | `docs/23-update-api-reference` |
| `test/` | Test additions/fixes | `test/31-add-auth-unit-tests` |
| `chore/` | Maintenance, deps | `chore/50-update-dependencies` |

The `short-description` is derived from the issue title: lowercase, spaces → hyphens, non-alphanumeric removed, truncated to keep total branch name under 50 chars.

#### Commit Messages

Format: `<type>(<scope>): <description> (#<issue-number>)`

Follow **Conventional Commits**:

| Type | Purpose | Example |
|------|---------|---------|
| `feat` | New feature | `feat(auth): implement OAuth login (#42)` |
| `fix` | Bug fix | `fix(checkout): resolve redirect loop (#15)` |
| `refactor` | No behavior change | `refactor(auth): extract middleware helper (#8)` |
| `docs` | Documentation | `docs(readme): update installation steps (#23)` |
| `test` | Tests only | `test(auth): add login flow unit tests (#31)` |
| `chore` | Maintenance | `chore(deps): update express to v5 (#50)` |

- Scope is optional but recommended (module or component name)
- Description in **imperative mood**, lowercase, no period
- Always reference the issue number in parentheses at the end

#### Pull Request Titles

Format: `<type>(<scope>): <description> (#<issue-number>)`

Same convention as commit messages. PR titles should read as a summary of what the PR accomplishes. Include `Closes #N` on the first line of the PR body (not in the title).

Examples:
- `fix(auth): resolve mobile redirect loop (#42)`
- `feat(settings): add dark mode toggle (#15)`
- `refactor(db): extract connection pool logic (#8)`

#### Issue Titles

- Use **imperative mood** (like a command): "Fix login crash on mobile" not "Login is crashing"
- Keep titles **concise, descriptive, and actionable**
- Optional type prefix for clarity: "Bug: ...", "Feature: ...", "Enhancement: ..."
- Include context when helpful: "Bug: App crashes when clicking login on iOS"

### Configuration
- `.gitissue.yml` loaded ONCE at skill start, not re-read at each step
- Zero-config: all defaults applied when no config file exists
- First-run hint: `○ First run — using default config. Run /init-gitissue to customize.`

### Skills
- Each skill follows the skill-creator standard (frontmatter with name/description, progressive disclosure)
- Each skill has its own `references/error-messages.md`
- Shared agents live in `shared/agents/` — skills reference them by path, not by external agent types
- All subagents use the default general-purpose agent (no `subagent_type` parameter)
- In auto-pilot mode, all agents/skills run autonomously without user prompts
- Static sequential output — each step prints a new line, no terminal animation

### Testing
- Integration tests in `tests/` directory
- Shell scripts that verify skill behavior against real or mock GitHub repos
