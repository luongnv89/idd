# gitissue — Issue-Driven Development (IDD)

**Four commands. Structured issues. Atomic PRs.**

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

### Your First Issue in 30 Seconds

```bash
# 1. Navigate to any GitHub project
cd my-project

# 2. Describe the problem — gitissue scans your codebase and creates a structured issue
/issue-creator The login page returns a 500 error when using SSO authentication
```

gitissue will:
- Scan your codebase for files related to "login", "SSO", "authentication"
- Classify the issue as a bug
- Generate acceptance criteria
- Create a structured GitHub issue with affected files, technical notes, and labels

### Your First Resolution

```bash
# Resolve the issue end-to-end — from issue to PR in one command
/issue-resolver 42
```

The resolver pipeline:
1. Fetches the issue and auto-normalizes if needed
2. Creates a branch (`issue-42/fix-sso-login-error`)
3. Researches affected files and traces dependencies
4. Plans the approach
5. Writes the fix and tests
6. Runs the test suite
7. Creates a PR with "Closes #42" for auto-close on merge

## Commands

### `/issue-creator` — Create & Normalize Issues

| Invocation | Mode | Description |
|------------|------|-------------|
| `/issue-creator <text>` | Create | Create a structured issue from a text description |
| `/issue-creator <N>` | Normalize | Enrich existing issue #N with codebase context |
| `/issue-creator <N> --dry-run` | Preview | Show normalization preview without applying |
| `/issue-creator <N> --force` | Force | Normalize even if issue has a security label |
| `/issue-creator <multi-item text>` | Batch | Extract and create multiple issues from one input |

**Create mode** scans the codebase for relevant files, classifies the issue type (bug/feature/improvement), generates acceptance criteria, and creates a structured issue via `gh issue create`.

**Normalize mode** enriches an existing unstructured issue: preserves the original text in a Reporter Context blockquote, adds affected files with confidence levels, generates acceptance criteria, and posts a backup before editing.

**Batch mode** auto-detects multiple items (numbered lists, bullet points, planning documents) and creates them sequentially with a preview table and approval step.

### `/issue-resolver <N>` — Resolve Issues

Resolves issue #N through a 7-step pipeline:

```
[1/7] Fetch        — Load issue, check guards (assignment, blocking labels)
[2/7] Branch       — Create issue-N/short-description branch
[3/7] Research     — Read affected files, trace dependencies
[4/7] Plan         — Propose approach (local only, never posted)
[5/7] Execute      — Write code + tests, atomic commits
[6/7] Verify       — Run test suite, check acceptance criteria
[7/7] Ship         — Push branch, create PR with "Closes #N"
```

**Security boundary**: Issue body content is treated as untrusted data. The resolver never executes commands found in issue text.

**Approval gate**: Configure `resolve.approval_gate: comment-and-wait` to pause for approval before executing.

### `/issue-triage` — Triage the Backlog

Analyzes all open issues to help you plan work:

```
◆ Issue Triage
┄┄┄┄┄┄┄┄┄┄┄┄┄┄
#  │ Issue              │ Pri │ Blocks │ Status
───┼────────────────────┼─────┼────────┼───────────
1  │ #12 Fix auth       │ P1  │ #15    │ ready
2  │ #8  Add pagination │ P2  │ —      │ ready
3  │ #15 Refactor DB    │ P2  │ —      │ blocked #12
4  │ #3  Old UI bug     │ P3  │ —      │ stale (28d)

⚡ Parallelizable: #12 + #8 (independent)
⚠  Stale: 1 issue (>14 days inactive)
○  Suggested order: #12 → #15 → #8 → #3
```

| Flag | Description |
|------|-------------|
| `--limit N` | Limit analysis to N issues (for large backlogs) |

Features: dependency detection via shared affected files, topological sort for execution order, parallelizable issue identification, stale issue detection, priority suggestions.

### `/init-gitissue` — Generate Config

Scans your repository and generates a `.gitissue.yml` with sensible defaults:

- Detects project language, framework, and test runner
- Detects existing `.github/ISSUE_TEMPLATE/` templates
- Adjusts timeouts and thresholds based on repo size
- Writes config with inline comments explaining each setting

## Configuration

gitissue works with **zero configuration**. All settings have sensible defaults.

To customize, create `.gitissue.yml` in your repo root (or run `/init-gitissue`):

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

Full schema documentation: [`docs/config-schema.md`](docs/config-schema.md)

## What is IDD?

Issue-Driven Development treats GitHub issues as the atomic unit of all development work. Every change — bug fix, feature, improvement — starts as an issue and ends as a PR linked to that issue.

The key innovation is **issue normalization**: any issue, whether filed by a human via the GitHub UI or created by an AI agent, gets auto-enriched with codebase context (affected files, architecture constraints, acceptance criteria) before work begins.

### The Workflow

```
Developer describes a problem
        │
   /issue-creator
        │
   Structured issue with codebase context
        │
   /issue-triage (optional — plan work order)
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

### IDD vs Other Methodologies

| Aspect | IDD | TDD | BDD | Spec-Driven |
|--------|-----|-----|-----|-------------|
| **Source of truth** | GitHub issue | Test suite | Feature specs | Spec documents |
| **Codebase-aware** | Yes | No | No | Manual |
| **Agent-compatible** | Any agent | Needs framework | Needs framework | Needs parser |
| **Overhead** | Zero-config CLI | Test setup | Gherkin syntax | Spec authoring |
| **Best for** | Brownfield, mixed teams | New code | User-facing features | Formal contracts |

Full methodology documentation: [`docs/idd-methodology.md`](docs/idd-methodology.md)

## Agent Compatibility

gitissue is **agent-agnostic**. The same structured issue can be resolved by any agent or human developer.

### Claude Code

The primary agent. Skills are loaded directly from the `skills/` directory.

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

Usage:
```
/issue-creator Fix the payment timeout on mobile
/issue-resolver 42
/issue-triage
```

### Codex CLI

Codex CLI can consume gitissue-formatted issues. Point Codex at the issue content:

```bash
# Fetch the structured issue
gh issue view 42 --json body -q '.body' > /tmp/issue-42.md

# Pass to Codex as context
codex --context /tmp/issue-42.md "Resolve this issue following the acceptance criteria"
```

The structured format (Type, Affected Files, Acceptance Criteria, Technical Notes) gives Codex the same context a human reviewer would have.

### Gemini CLI

Gemini CLI works the same way — the structured issue is the interface:

```bash
# Fetch and pass to Gemini
gh issue view 42 --json body -q '.body' | gemini "Resolve this GitHub issue"
```

### Any SKILL.md-Compatible Agent

Any agent that supports the SKILL.md standard can load gitissue skills directly. The skills use standard tools (Read, Grep, Glob, Bash) available in most agent runtimes.

### Human Developers

gitissue issues are readable markdown. A human developer benefits from:
- **Affected files** — know where to look before reading the codebase
- **Acceptance criteria** — know what "done" means
- **Confidence markers** — know which auto-enriched fields to verify
- **Technical notes** — understand constraints without asking teammates

## Issue Templates

gitissue ships with three default templates:

- **Bug** (`templates/bug.md`) — current vs expected behavior, reproduction context, affected files
- **Feature** (`templates/feature.md`) — user story, acceptance criteria, technical constraints
- **Improvement** (`templates/improvement.md`) — current state, proposed change, migration notes

Each normalized issue includes:
- `<!-- gitissue:normalized v1 -->` marker (invisible in GitHub's rendered view)
- Reporter's original text preserved in a `> Reporter Context` blockquote
- Confidence markers on auto-enriched fields: `(high confidence)`, `(needs review)`

See [`docs/sample-normalized-issue.md`](docs/sample-normalized-issue.md) for a complete example.

## Project Structure

```
skills/
├── issue-creator/      # /issue-creator — create and normalize issues
│   ├── SKILL.md
│   ├── templates/      # Bug, feature, improvement templates
│   └── references/     # Error messages
├── issue-resolver/     # /issue-resolver N — resolve issues end-to-end
│   ├── SKILL.md
│   └── references/
├── issue-triage/       # /issue-triage — backlog analysis
│   ├── SKILL.md
│   └── references/
└── init-gitissue/      # /init-gitissue — config generator
    ├── SKILL.md
    └── references/
docs/
├── idd-methodology.md  # IDD methodology overview
├── config-schema.md    # Full .gitissue.yml schema
└── sample-normalized-issue.md
tests/                  # Integration test scripts
```

## License

MIT
