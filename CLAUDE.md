# CLAUDE.md — gitissue / IDD

## Project Overview

gitissue implements Issue-Driven Development (IDD) — a methodology where GitHub issues are the single source of truth for all development work. The product is a set of Claude Code skills that create, normalize, resolve, and triage GitHub issues.

## Architecture

This is a **skills-only** project. There is no runtime code — each skill is a self-contained Claude Code skill (SKILL.md + references/ + templates/) that instructs the agent how to perform a task. Shared agents live in `src/shared/agents/` and are referenced by multiple skills. All authored skill sources live under `src/`. Per issue #81, all documentation — both runtime docs consumed by skills and human-only project docs — lives in a single top-level `docs/` tree.

```
src/
├── shared/
│   └── agents/                    # Shared agent definitions (used by multiple skills)
│       ├── codebase-researcher.md # Deep codebase scan + solution research
│       ├── synthesizer.md         # Analysis + implementation options
│       ├── implementer.md         # Code + tests implementation
│       ├── code-reviewer.md       # Confidence-based code review
│       ├── duplicate-detector.md  # Issue dedup scoring
│       └── issue-relationship-scanner.md  # File deps + already-fixed detection
│
├── skills/
│   ├── auto-pilot/         # /auto-pilot — triage, resolve, review, merge loop
│   │   ├── SKILL.md
│   │   └── references/
│   ├── issue-analysis/     # /issue-analysis N — deep issue investigation
│   │   ├── SKILL.md
│   │   └── references/
│   ├── issue-creator/      # /issue-creator — create/normalize/batch issues
│   │   ├── SKILL.md
│   │   ├── templates/      # Issue templates (bug, feature, improvement)
│   │   └── references/
│   ├── issue-resolver/     # /issue-resolver N — 6-step resolve pipeline
│   │   ├── SKILL.md
│   │   └── references/
│   ├── issue-triage/       # /issue-triage — prioritize and order issues
│   │   ├── SKILL.md
│   │   └── references/
│   ├── issue-pr-review/    # /issue-pr-review — review, test, CI check, fix, merge
│   │   ├── SKILL.md
│   │   └── references/
│   └── init-gitissue/      # /init-gitissue — generate .gitissue.yml
│       ├── SKILL.md
│       └── references/
│
├── internal-skills/
│   └── idd-doctor/         # /idd-doctor — read-only repo health check
│       ├── SKILL.md
│       └── references/
│
docs/                              # All documentation — single tree (issue #81)
├── config-schema.md               # ↓ Runtime docs (skills reference these via
├── idd-methodology.md             #   bare `docs/X.md` tokens; build.py
├── naming-conventions.md          #   bundles them into each skill's
├── sync-conventions.md            #   references/docs/ at build time)
├── github-projects-sync.md        # ↑
├── ARCHITECTURE.md                # ↓ Human-only project docs (not bundled
├── CHANGELOG.md                   #   into skills; readable on the
├── DEVELOPMENT.md                 #   repo's main branch only)
├── decisions/                     # ↑
├── experiments/
└── release-notes/
```

### Docs placement rule

All documentation lives in top-level `docs/`. Two kinds coexist there:

1. **Runtime docs** — read by skills at execution time. A skill source file references them as bare `docs/X.md` tokens. `scripts/build.py` discovers these references via transitive-closure scan and copies the matching files into each skill's `references/docs/` (standalone) and the plugin tree's top-level `docs/` (plugin layout). To add a runtime doc: drop the new `.md` file at `docs/<name>.md` and reference it from a skill or shared agent — the build picks it up automatically. Today's runtime docs: `config-schema.md`, `idd-methodology.md`, `naming-conventions.md`, `sync-conventions.md`, `github-projects-sync.md`.
2. **Project docs** — read by humans only. Architecture, changelog, dev guide, decision records, experiments, release notes. They are not referenced by any skill, so the build does not bundle them. Place new project docs at `docs/<name>.md` (top-level) or under a topical subdirectory (`docs/decisions/`, `docs/experiments/`, `docs/release-notes/`).

When in doubt: if a skill source needs to read it at runtime, it is a runtime doc and goes at the top level of `docs/`. Otherwise it is a project doc.

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
- Shared agents live in `src/shared/agents/` — skills reference them by path, not by external agent types
- All subagents use the default general-purpose agent (no `subagent_type` parameter)
- In auto-pilot mode, all agents/skills run autonomously without user prompts
- Static sequential output — each step prints a new line, no terminal animation

### Testing
- Integration tests in `tests/` directory
- Shell scripts that verify skill behavior against real or mock GitHub repos
