# CLAUDE.md — gitissue / IDD

## Project Overview

gitissue implements Issue-Driven Development (IDD) — a methodology where GitHub issues are the single source of truth for all development work. The product is a set of Claude Code skills that create, normalize, resolve, and triage GitHub issues.

## Architecture

This is a **prompt-first** project. Almost all of it is prose: each skill is a self-contained Claude Code skill (SKILL.md + references/ + templates/) that instructs the agent how to perform a task, and there is no application runtime. The one exception is `src/shared/scripts/` — small, stdlib-only Python helpers that skills shell out to for the few jobs where determinism beats prose (resolving config, validating a run-log record, parsing dependency markers). Every one of them is optional at run time: the skill prose that invokes a script also documents the manual procedure, so a skill still works where the script cannot run. Shared agents live in `src/shared/agents/` and are referenced by multiple skills. All authored skill sources live under `src/`. Per issue #81, all documentation — both runtime docs consumed by skills and human-only project docs — lives in a single top-level `docs/` tree.

```
src/
├── shared/
│   ├── agents/                    # Shared agent definitions (used by multiple skills)
│   │   ├── codebase-researcher.md # Deep codebase scan + solution research
│   │   ├── synthesizer.md         # Analysis + implementation options
│   │   ├── implementer.md         # Code + tests implementation
│   │   ├── code-reviewer.md       # Confidence-based code review
│   │   ├── fixer.md               # Targeted fixes for review/test/CI/AC failures
│   │   ├── duplicate-detector.md  # Issue dedup scoring
│   │   ├── issue-relationship-scanner.md  # File deps + already-fixed detection
│   │   └── ui-reviewer.md         # UI/UX + screenshot accessibility review
│   └── scripts/                   # Shared executable helpers (stdlib-only, mode 0755)
│       ├── gi-config.py           # Defaults + .gitissue.yml → one JSON line
│       ├── gi-runlog.py           # Validate/normalize/append a runs.jsonl record
│       ├── gi-deps.py             # Parse local dependency issue numbers
│       ├── gi-secscan.py          # Pre-commit secret/artifact scan → JSON verdict
│       ├── gi-ci-wait.py          # Poll a PR's CI checks to one JSON verdict
│       ├── gi-issue.py            # TTL-cached `gh issue view` by field set
│       ├── gi-branch.py           # Derive a convention-conformant branch name
│       └── gi-ratelimit.py        # Rate-limit verdict, chunked pause, backoff, runtime budget
│
├── skills/
│   ├── auto-pilot/         # /auto-pilot — triage, resolve, review, merge loop
│   │   ├── SKILL.source.md
│   │   └── references/     # → bundled: references/{agents,docs,scripts}/ at build time
│   ├── issue-analysis/     # /issue-analysis N — deep issue investigation
│   │   ├── SKILL.source.md
│   │   └── references/
│   ├── issue-creator/      # /issue-creator — create/normalize/batch issues
│   │   ├── SKILL.source.md
│   │   ├── templates/      # Issue templates (bug, feature, improvement)
│   │   └── references/
│   ├── issue-resolver/     # /issue-resolver N — 6-step resolve pipeline
│   │   ├── SKILL.source.md
│   │   └── references/
│   ├── issue-triage/       # /issue-triage — prioritize and order issues
│   │   ├── SKILL.source.md
│   │   └── references/
│   ├── issue-pr-review/    # /issue-pr-review — review, test, CI check, fix, merge
│   │   ├── SKILL.source.md
│   │   └── references/
│   └── init-gitissue/      # /init-gitissue — generate .gitissue.yml
│       ├── SKILL.source.md
│       └── references/
│
├── internal-skills/
│   └── idd-doctor/         # /idd-doctor — read-only repo health check
│       ├── SKILL.source.md
│       └── references/
│
CHANGELOG.md                       # Project changelog (repo root, not under docs/)

docs/                              # All documentation — single tree (issue #81)
├── config-schema.md               # ↓ Runtime docs (skills reference these via
├── idd-methodology.md             #   bare `docs/X.md` tokens; build.py
├── naming-conventions.md          #   bundles them into each skill's
├── sync-conventions.md            #   references/docs/ at build time)
├── github-projects-sync.md        #
├── platform-github.md             #
├── shared-agent-conventions.md    #
├── agent-model-effort.md          #
├── pre-commit-security.md         #
├── terminal-style.md              #
├── auto-mode.md                   # ↑
├── ARCHITECTURE.md                # ↓ Human-only project docs (not bundled
├── DEVELOPMENT.md                 #   into skills; readable on the
├── decisions/                     #   repo's main branch only)
├── experiments/                   #
└── release-notes/                 # ↑
```

### Docs placement rule

All documentation lives in top-level `docs/`. Two kinds coexist there:

1. **Runtime docs** — read by skills at execution time. A skill source file references them as bare `docs/X.md` tokens. `scripts/build.py` discovers these references via transitive-closure scan and copies the matching files into each skill's `references/docs/`. To add a runtime doc: drop the new `.md` file at `docs/<name>.md` and reference it from a **skill** — the build picks it up automatically. Today's runtime docs — all 13 bundled by the closure — are: `config-schema.md`, `run-log-schema.md`, `idd-methodology.md`, `naming-conventions.md`, `sync-conventions.md`, `github-projects-sync.md`, `platform-github.md`, `shared-agent-conventions.md`, `agent-model-effort.md`, `pre-commit-security.md`, `terminal-style.md`, `auto-mode.md`, `ui-review.md`.

   Three build-time rules shape what actually lands in a skill (issue #249). **(a) Skill-reachable only** — a doc reachable only through a shared agent is validated but not bundled: emitted agent prompts render their references as absolute repo URLs (issue #245), so a bundled copy would be unreferenceable. **(b) Per-skill config excerpt** — `config-schema.md` is emitted carrying only the top-level sections a skill's own text names (plus `platform`); `/init-gitissue`, which renders `.gitissue.yml`, keeps it whole. **(c) Runtime digest** — docs in `DOC_SECTION_DIGESTS` (today: `idd-methodology.md`) are emitted as their normative sections only, plus any optional section the skill names. Both (b) and (c) are verified in `build.py` and fail the build on a hole; a doc bundled with no runtime mention outside the index/precheck blocks prints a `⚠` warning.
2. **Project docs** — read by humans only. Architecture, changelog, dev guide, decision records, experiments, release notes. They are not referenced by any skill, so the build does not bundle them. Place new project docs at `docs/<name>.md` (top-level) or under a topical subdirectory (`docs/decisions/`, `docs/experiments/`, `docs/release-notes/`).

When in doubt: if a skill source needs to read it at runtime, it is a runtime doc and goes at the top level of `docs/`. Otherwise it is a project doc.

One deliberate exception: each skill package carries its own human-facing `README.md` at `src/skills/<name>/docs/README.md` (and `src/internal-skills/idd-doctor/docs/README.md`). That is the skill-creator standard location — a README under the skill's `docs/` is never auto-loaded into agent context, so it costs zero runtime tokens — and it carries the `DO NOT READ THIS FILE` AI-skip notice. These are skill-package files, not entries in the top-level `docs/` tree.

### Scripts placement rule

Shared executable helpers are a third closure kind alongside agents and runtime docs (issue #251). They follow the same author-once / bundle-per-skill shape:

- **Source** lives at `src/shared/scripts/<name>.py`. Lowercase-hyphen names, `.py` only, committed mode `0755`, stdlib-only, and `--help` must exit 0.
- **Reference** it from skill prose as the bare token `shared/scripts/<name>.py` — never as a path that already exists on disk. `scripts/build.py` discovers the token by regex (`SHARED_SCRIPT_RE`, directory-scoped exactly like `SHARED_AGENT_RE`, because a bare `scripts/X.py` token would collide with the prose mentions of this repo's own `scripts/` directory).
- **Emitted** to `references/scripts/<name>.py`, byte-identical to the source and with its mode preserved. The build rewrites the source token to that path in the skill's own files, so the runtime prose reads `references/scripts/<name>.py`.
- **Invoke** it as `python3 references/scripts/<name>.py`, **never** `./references/scripts/<name>.py`. Zip and tar installs (and some npx-style copies) drop the exec bit; the committed `0755` is a human convenience, not a runtime guarantee.
- **Scripts are closure leaves.** Their contents are never scanned for further references — a deterministic tool is not a document, and scanning `.py` bodies would let a comment silently pull a doc into a bundle.
- **Agent reachability.** A script reached only through a shared agent is validated but *not* bundled, for the same reason as docs: since issue #245 an emitted agent prompt renders every reference as an absolute repo URL, so a bundled copy would be unreferenceable. An agent that needs a script must receive its path as a **spawn variable** bound by the orchestrating skill, mirroring today's `{security_convention}`.
- **Declared inputs.** A script may declare a bundled file it reads at run time with a `# gi-requires: references/…` header line; the build fails if that file is not bundled alongside it in the same skill.
- **Adding a new script requires no `build.py` change.** Discovery is regex plus filesystem: drop the file in `src/shared/scripts/`, cite it from a skill, add it to that skill's *Bundled dependency precheck* list, and rebuild.

**Fatal vs. degrade.** These are two different failures and the skills treat them differently:

- **File absent from the bundle → fatal.** The precheck list guarantees the script shipped (the build fails both ways if the list and the bundle disagree), so a missing file means a broken or partial install. Stop and print the `✗ Missing bundled dependency` block.
- **Runtime failure → degrade.** No `python3` on PATH, a non-zero exit other than 3, or unparsable stdout is an environment problem, not a broken install. Print a `⚠` line and follow the documented prose procedure the skill keeps beside every invocation. Exit 3 is the exception: it means the *user's input* is invalid (e.g. a malformed `.gitissue.yml`), which is a real stop, not a degrade.

The shared exit-code vocabulary is `0` ok · `2` usage error · `3` invalid input (stop) · `4` cannot complete (degrade to prose).

Code `1` is reserved for a **script-specific verdict** — an answer the script was asked for, not a failure to answer. Only `gi-secscan.py` uses it today (`1` = a real secret was found, the commit must stop). A script that claims `1` must document it in its own docstring **and** at every call site, because the default reading of a non-zero exit is "degrade", and degrading past a verdict inverts it.

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
- Standard sections (SPEC §1.1): Type, Description, Screenshots, Acceptance Criteria, Metadata
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
- Shared scripts live in `src/shared/scripts/` — skills reference them by the bare `shared/scripts/<name>.py` token and run the bundled copy as `python3 references/scripts/<name>.py`, always with a documented prose fallback (see *Scripts placement rule*)
- All subagents use the default general-purpose agent (no `subagent_type` parameter)
- In auto-pilot mode, all agents/skills run autonomously without user prompts
- Static sequential output — each step prints a new line, no terminal animation

### Testing
- The automated suite is `tests/*.sh` — shell scripts that assert on `src/`, `docs/`, and the built `skills/`. They need no GitHub repo, no token, and no setup. Run one with `bash tests/<name>.sh`; run them all with `git ls-files 'tests/*.sh' | xargs -n1 bash`
- `.github/workflows/dist-check.yml` is the authoritative list of the suite: one named step per script, in the order CI runs them. `tests/test-build-script.sh` (T9) fails if a tracked `tests/*.sh` is missing from it, so the list cannot silently fall behind
- `tests/README.md`, `README-sprint2.md`, and `README-sprint3.md` are something else: manual, human-driven test cases that do need a scratch GitHub repo
