# Development Guide

## Prerequisites

- [GitHub CLI](https://cli.github.com) (`gh`) 2.0+ — authenticated via `gh auth login`
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) or any SKILL.md-compatible agent
- Git 2.30+

## Local Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/luongnv89/idd.git
   cd idd
   ```

2. Install skills locally. Standalone is the recommended default — pick one of these:
   ```bash
   # Standalone (recommended) — bundled install script, all skills, idempotent:
   ./scripts/install.sh

   # Standalone — single skill from this checkout (manual variant):
   cp -r dist/skills/issue-resolver ~/.claude/skills/

   # Standalone — via asm (no clone needed; targets Claude Code):
   asm install github:luongnv89/idd#main:dist/skills/issue-resolver

   # Plugin (Claude Code only) — build then install the plugin tree:
   ./scripts/build.sh && ./scripts/install.sh --plugin
   ```
   The Plugin path lands under `~/.claude/plugins/idd/`; the Standalone paths drop individual skills directly into `~/.claude/skills/`. See [README → Install](../README.md#install) for the full hierarchy.

3. Verify setup:
   ```bash
   gh auth status        # Must be authenticated
   gh --version          # Must be 2.0+
   ```

## Build Flow

`src/` is the single source of truth. `dist/` is generated and must not be hand-edited.

```mermaid
graph LR
    SRC["src/<br/>(authored)"] -->|"./scripts/build.sh"| DSK["dist/skills/<br/>(committed)"]
    SRC -->|"./scripts/build.sh"| DPL["dist/plugin/<br/>(gitignored)"]
    DPL -->|"release tag"| TAR["idd-plugin-&lt;tag&gt;.tar.gz<br/>(release asset)"]

    style SRC fill:#4CAF50,color:#fff
    style TAR fill:#2196F3,color:#fff
```

After editing anything under `src/`, rebuild before committing:

```bash
./scripts/build.sh
```

CI's drift check fails any PR where the committed `dist/skills/` does not match a fresh build.

## Making Changes

```mermaid
graph TD
    A["Clone repo & install skills"] --> B["Edit SKILL.md"]
    B --> C["Update error-messages.md<br/>(if new errors)"]
    C --> D["Test against real<br/>GitHub repo"]
    D --> E["Verify terminal output<br/>matches DESIGN.md"]
    E --> F["Submit PR"]

    style A fill:#4CAF50,color:#fff
    style F fill:#2196F3,color:#fff
```

### Editing a Skill

Skills live in `src/skills/<name>/SKILL.md` (internal-only skills under `src/internal-skills/<name>/`, deprecated skills under `src/deprecated-skills/<name>/`). Hand edits go in `src/` only — never edit `dist/skills/` directly. When editing:

1. Read the existing SKILL.md fully before making changes
2. Follow the terminal output patterns in `DESIGN.md`
3. Use `--json` with explicit field selection for all `gh` commands
4. Update `references/error-messages.md` if adding new error cases
5. Run `./scripts/build.sh` to regenerate `dist/skills/`
6. Test against a real GitHub repository

### Adding Error Messages

Each skill has `references/error-messages.md`. Follow the three-part format:

```
✗ Short error description

  To fix:  <actionable command>
  Docs:    <url to relevant documentation>
```

### Modifying Templates

Issue templates are in `src/skills/issue-creator/templates/`. Each template must:
- Include the `<!-- gitissue:normalized v1 -->` marker
- Use intent-only sections: Type, Context, Description, Acceptance Criteria, Metadata
- Preserve the Reporter Context blockquote
- **Never** include sections that imply codebase analysis (no Affected Files, no Technical Notes, no Architecture Constraints, no Implementation Hints) — `/issue-creator` is intent-only; consumer skills (resolver, triage, analysis) scan the codebase fresh at execution time

## Testing

Integration tests are in `tests/`. They verify skill behavior against GitHub repositories.

```bash
# See tests/README.md for setup and execution instructions
```

When testing manually:
1. Create a test repository (or use an existing one)
2. Run the skill you modified
3. Verify terminal output matches `DESIGN.md` patterns
4. Check that GitHub issues/PRs are created correctly

## Key Conventions

- **`gh` CLI** — every call must use `--json` with explicit field selection
- **Terminal symbols** — `✓ ✗ ● ◆ ⚡ ⚠ ○` per `DESIGN.md`
- **No cross-skill state** — skills are fully isolated
- **Config loaded once** — `.gitissue.yml` is read at skill start, not per-step
- **Backup before edit** — always post a backup comment before modifying an issue

## File Reference

```mermaid
graph TD
    CM["CLAUDE.md<br/>Agent conventions"] --> DM["DESIGN.md<br/>Output style guide"]
    CM --> CS["src/docs/config-schema.md<br/>Config schema"]
    CM --> AR["docs/ARCHITECTURE.md<br/>System design"]
    AR --> SK["src/skills/*/SKILL.md<br/>Skill definitions"]
    SK --> EM["src/skills/*/references/<br/>Error messages"]
    SK --> TM["src/skills/*/templates/<br/>Issue templates"]
    CS --> GY[".gitissue.yml<br/>Project config"]

    style CM fill:#4CAF50,color:#fff
    style SK fill:#2196F3,color:#fff
```

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Project conventions for AI agents |
| `DESIGN.md` | Terminal output style guide |
| `src/docs/config-schema.md` | Full `.gitissue.yml` schema (autopilot + review sections) |
| `src/docs/idd-methodology.md` | IDD methodology overview + analysis-artifact dual-write rule |
| `src/docs/naming-conventions.md` | Branch / commit / PR / issue naming |
| `docs/sample-normalized-issue.md` | Example normalized issue (intent-only) |
| `docs/ARCHITECTURE.md` | System design, data flow, durable-memory model |
| `docs/CHANGELOG.md` | Per-release notes |
| `src/internal-skills/idd-doctor/SKILL.md` | Read-only health check — run before submitting a PR |
