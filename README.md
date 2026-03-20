<p align="center">
  <strong>issue-dev</strong>
</p>

<p align="center">
  <a href="https://github.com/luongnv89/idd/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="MIT License"></a>
  <a href="https://github.com/luongnv89/idd"><img src="https://img.shields.io/badge/skills-4-blue.svg" alt="4 skills"></a>
</p>

# Turn GitHub Issues Into Your Entire Dev Workflow

**Four commands. Structured issues. Atomic PRs.** issue-dev brings Issue-Driven Development (IDD) to your terminal — describe a problem, get a codebase-aware issue. Point at that issue, get a tested PR. No extra tools, no sync overhead.

Works for humans and AI agents alike.

[**Get Started in 30 Seconds →**](#installation)

---

## The Problem

You already know this drill:

- **Vague issues waste hours.** Someone files "the thing is broken" and you spend 30 minutes just figuring out *which files to open* before writing a single line of code.
- **AI agents produce off-target PRs.** You point Copilot or Claude at an issue and get back changes to the wrong files — because the issue didn't have enough context to begin with.
- **No one triages the backlog.** 47 open issues, no dependency awareness, no execution order. You pick whichever looks easiest and accidentally block three other issues.

The gap isn't your team or your tools. It's that GitHub issues were designed for humans to *read*, not for agents to *execute*.

## What issue-dev Does

issue-dev makes every GitHub issue a self-contained work order — enriched with affected files, acceptance criteria, and technical context pulled from your actual codebase.

| Command | What It Does |
|---------|-------------|
| `/issue-creator` | Scans your codebase, classifies the type, generates acceptance criteria, uploads screenshots, creates a structured issue |
| `/issue-resolver N` | Fetches the issue, creates a branch, researches files, writes code + tests, opens a PR with "Closes #N" |
| `/issue-triage` | Builds a dependency graph, detects stale issues, suggests priority and execution order |
| `/init-gitissue` | Detects your language/framework/test runner and generates a `.gitissue.yml` config |

Every issue created or normalized by issue-dev includes:
- **Affected files** with confidence levels (high/medium/low)
- **Acceptance criteria** derived from the problem description and codebase
- **Technical notes** — architecture constraints, test coverage, breaking change risk
- **Reporter's original text** preserved verbatim
- **Embedded screenshots** — images uploaded to GitHub and embedded inline in the issue body

## How It Works

### 1. Describe a problem

```bash
/issue-creator The login page returns a 500 error when using SSO
```

issue-dev scans your codebase for files related to "login", "SSO", "authentication" — classifies it as a bug — and creates a structured GitHub issue with affected files, acceptance criteria, and labels.

### 2. Resolve it in one command

```bash
/issue-resolver 42
```

The 7-step pipeline runs automatically:

```
[1/7] Fetch        ✓ issue #42 loaded
[2/7] Branch       ✓ issue-42/fix-sso-login-error
[3/7] Research     ✓ read 5 files, traced 3 deps
[4/7] Plan         ✓ approach: fix redirect logic
[5/7] Execute      ✓ 2 files changed, 45 lines
[6/7] Verify       ✓ 12 tests passed
[7/7] Ship         ✓ PR #87 created — Closes #42
```

### 3. Triage the backlog

```bash
/issue-triage
```

```
#  │ Issue              │ Pri │ Blocks │ Status
───┼────────────────────┼─────┼────────┼───────────
1  │ #12 Fix auth       │ P1  │ #15    │ ready
2  │ #8  Add pagination │ P2  │ —      │ ready
3  │ #15 Refactor DB    │ P2  │ —      │ blocked #12
4  │ #3  Old UI bug     │ P3  │ —      │ stale (28d)

⚡ Parallelizable: #12 + #8 (independent)
○  Suggested order: #12 → #15 → #8 → #3
```

[**Install Now →**](#installation)

---

## Installation

Three ways to install. Pick your favorite.

### Prerequisites

- [GitHub CLI](https://cli.github.com) (`gh`) 2.0+ — authenticated via `gh auth login`
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) or any SKILL.md-compatible agent
- Git 2.30+

### Option 1: Vercel Skills (npx)

```bash
npx skills add https://github.com/luongnv89/idd
```

### Option 2: Agent Skill Manager (asm)

```bash
asm install https://github.com/luongnv89/idd
```

### Option 3: Manual

Clone the repo and add skills to your project's `.claude/settings.json`:

```bash
git clone https://github.com/luongnv89/idd.git ~/.issue-dev
```

```json
{
  "skills": [
    "~/.issue-dev/skills/issue-creator",
    "~/.issue-dev/skills/issue-resolver",
    "~/.issue-dev/skills/issue-triage",
    "~/.issue-dev/skills/init-gitissue"
  ]
}
```

### Installing Individual Skills

You can install skills individually instead of the full suite. See the README in each skill folder for per-skill installation commands:

| Skill | Folder |
|-------|--------|
| `/issue-creator` | [`skills/issue-creator/`](skills/issue-creator/) |
| `/issue-resolver` | [`skills/issue-resolver/`](skills/issue-resolver/) |
| `/issue-triage` | [`skills/issue-triage/`](skills/issue-triage/) |
| `/init-gitissue` | [`skills/init-gitissue/`](skills/init-gitissue/) |

---

## Agent Compatibility

issue-dev is **agent-agnostic**. The structured issue format works with any resolver — human or AI.

| Agent | How It Works |
|-------|-------------|
| **Claude Code** | Load skills directly — `/issue-creator`, `/issue-resolver` |
| **Codex CLI** | `gh issue view 42 --json body -q '.body' > /tmp/issue.md && codex --context /tmp/issue.md "Resolve this issue"` |
| **Gemini CLI** | `gh issue view 42 --json body -q '.body' \| gemini "Resolve this GitHub issue"` |
| **Any SKILL.md agent** | Load skills from `skills/` directory |
| **Human developers** | Read the issue — affected files, acceptance criteria, and technical notes are all there |

---

## What is IDD?

Issue-Driven Development treats GitHub issues as the atomic unit of all development work. Every change — bug fix, feature, improvement — starts as an issue and ends as a PR linked to that issue.

The key innovation is **issue normalization**: any issue, whether filed by a human or created by an AI, gets auto-enriched with codebase context before work begins.

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

[**Start Using IDD →**](#installation)

---

## FAQ

**Is it free?**
Yes. MIT licensed, free forever. No telemetry, no accounts, no cloud dependency.

**Does it work without Claude Code?**
The skills are designed for Claude Code but the structured issue format works with any AI agent (Codex, Gemini, Copilot) or human developers. The issue *is* the interface.

**Will it modify my existing issues?**
Only when you explicitly run `/issue-creator N` to normalize an issue. It always posts a backup comment with the original body before making any changes. If the backup fails, it aborts.

**How does it handle security issues?**
Issues labeled `security`, `CVE`, or `vulnerability` are automatically skipped during normalization — codebase context in a public issue could reveal exploit details. Use `--force` to override.

**Can I customize the issue templates?**
Yes. Run `/init-gitissue` to generate a `.gitissue.yml` config, then point `issue.template` to your custom template directory.

**Does it work with private repos?**
Yes. It uses `gh` CLI's authentication — whatever repos you have access to via `gh auth login` will work.

**How does `/issue-resolver` avoid prompt injection?**
Issue body content is treated as untrusted data. The resolver never executes commands found in issue text — it only follows its own pipeline steps.

---

## Get Started

Paste a bug report. Get a structured, codebase-aware issue. Resolve it into a tested PR. All from your terminal.

MIT licensed. Zero config. Works today.

```bash
npx skills add https://github.com/luongnv89/idd
```

[**View on GitHub →**](https://github.com/luongnv89/idd)

---

<details>
<summary><strong>Commands Reference</strong></summary>

### `/issue-creator` — Create & Normalize Issues

| Invocation | Mode | Description |
|------------|------|-------------|
| `/issue-creator <text>` | Create | Create a structured issue from a text description |
| `/issue-creator <N>` | Normalize | Enrich existing issue #N with codebase context |
| `/issue-creator <N> --dry-run` | Preview | Show normalization preview without applying |
| `/issue-creator <N> --force` | Force | Normalize even if issue has a security label |
| `/issue-creator <multi-item text>` | Batch | Extract and create multiple issues from one input |

**Create mode** scans the codebase for relevant files, classifies the issue type (bug/feature/improvement), generates acceptance criteria, uploads any provided screenshots to GitHub (embedded inline in the issue body), and creates a structured issue via `gh issue create`.

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

### `/issue-triage` — Triage the Backlog

Analyzes all open issues: dependency detection via shared affected files, topological sort for execution order, parallelizable issue identification, stale issue detection (>14 days), priority suggestions.

### `/init-gitissue` — Generate Config

Scans your repository and generates a `.gitissue.yml` with sensible defaults: detects project language, framework, test runner, existing issue templates, and adjusts timeouts based on repo size.

</details>

<details>
<summary><strong>Configuration</strong></summary>

issue-dev works with **zero configuration**. All settings have sensible defaults.

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

</details>

<details>
<summary><strong>Issue Templates</strong></summary>

issue-dev ships with three default templates:

- **Bug** (`templates/bug.md`) — current vs expected behavior, reproduction context, affected files
- **Feature** (`templates/feature.md`) — user story, acceptance criteria, technical constraints
- **Improvement** (`templates/improvement.md`) — current state, proposed change, migration notes

Each normalized issue includes:
- `<!-- gitissue:normalized v1 -->` marker (invisible in GitHub's rendered view)
- Reporter's original text preserved in a `> Reporter Context` blockquote
- Confidence markers on auto-enriched fields: `(high confidence)`, `(needs review)`

See [`docs/sample-normalized-issue.md`](docs/sample-normalized-issue.md) for a complete example.

</details>

<details>
<summary><strong>IDD Methodology</strong></summary>

Full methodology documentation: [`docs/idd-methodology.md`](docs/idd-methodology.md)

</details>

<details>
<summary><strong>Project Structure</strong></summary>

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

</details>

---

## License

MIT
