---
name: init-gitissue
description: Generate a project-specific .gitissue.yml by auto-detecting language, framework, test runner, and repo size. Use when asked to "init gitissue", "setup gitissue", "configure gitissue", "first time setup", "/init-gitissue", or to set up IDD on a new repo.
license: MIT
compatibility: Requires git. No GitHub CLI or authentication needed — generates a local config file only.
effort: low
metadata:
  version: 0.3.0
  creator: Luong NGUYEN <luongnv89@gmail.com>
---

# /init-gitissue

Initialize gitissue for the current repository. Scans the codebase to detect language, framework, test runner, and repo size, then generates a `.gitissue.yml` config file with project-specific defaults.

**Invocation**: `/init-gitissue` — no arguments.

## Prerequisites

Before any operation, verify the environment. On failure, output the exact error from `references/error-messages.md` and stop.

1. Confirm git repository: `git rev-parse --git-dir`

That is the only prerequisite. This skill does not need `gh` or GitHub authentication — it generates a local config file.

## Configuration Check

This skill GENERATES the config — it does not read one. However, check if `.gitissue.yml` already exists in the repo root before proceeding.

If the file exists, show the prompt from `references/error-messages.md`:

```
⚠ .gitissue.yml already exists

  Options:
    overwrite  — replace with new auto-detected config
    merge      — keep existing values, add new fields
    cancel     — do nothing

  Choose: [overwrite/merge/cancel]
```

- **overwrite** — delete existing file, proceed with full generation
- **merge** — read the existing file, preserve all user-set values, only add fields that are missing from the schema
- **cancel** — stop immediately, no changes

---

## Step 1 — Scan Repository

Detect project characteristics by checking for specific files and directories.

### Language Detection

Check for these files in the repo root (or nearby):

| File | Language |
|------|----------|
| `package.json` | JavaScript / TypeScript (check for `"typescript"` in devDependencies to distinguish) |
| `requirements.txt`, `pyproject.toml`, `setup.py`, `Pipfile` | Python |
| `go.mod` | Go |
| `Cargo.toml` | Rust |
| `pom.xml`, `build.gradle`, `build.gradle.kts` | Java |
| `Gemfile` | Ruby |
| `*.csproj`, `*.sln` | C# |

If multiple language markers exist, pick the primary one (the one with the most source files or the one at the repo root). If none detected, use empty state.

### Framework Detection

Parse dependency files to identify frameworks:

| Dependency name | Framework |
|-----------------|-----------|
| `react`, `react-dom` | React |
| `next` | Next.js |
| `vue` | Vue.js |
| `nuxt` | Nuxt.js |
| `angular`, `@angular/core` | Angular |
| `express` | Express |
| `fastify` | Fastify |
| `django` | Django |
| `flask` | Flask |
| `fastapi` | FastAPI |
| `rails`, `railties` | Rails |
| `spring-boot`, `spring-core` | Spring |
| `gin-gonic/gin` | Gin |
| `actix-web` | Actix |
| `ASP.NET`, `Microsoft.AspNetCore` | ASP.NET |

Check `package.json` dependencies/devDependencies, `requirements.txt` lines, `pyproject.toml` dependencies, `Gemfile` gems, `go.mod` require blocks, `Cargo.toml` dependencies, `pom.xml`/`build.gradle` dependencies.

If no framework detected, omit the framework line from the report (not an error).

### Test Runner Detection

Look for these files and patterns:

| Marker | Test runner |
|--------|-------------|
| `jest.config.js`, `jest.config.ts`, `jest.config.mjs`, `"jest"` in `package.json` | Jest |
| `vitest.config.js`, `vitest.config.ts`, `"vitest"` in `package.json` | Vitest |
| `.mocharc.yml`, `.mocharc.js`, `"mocha"` in `package.json` | Mocha |
| `karma.conf.js` | Karma |
| `pytest.ini`, `pyproject.toml` with `[tool.pytest]`, `setup.cfg` with `[tool:pytest]`, `conftest.py` | pytest |
| `unittest` imports in test files | unittest |
| `_test.go` files | Go test |
| `#[cfg(test)]` in `.rs` files | Cargo test |
| `src/test/` directory (Java) | JUnit |
| `spec/` directory with `Gemfile` containing `rspec` | RSpec |
| `*.test.js`, `*.spec.js`, `*.test.ts`, `*.spec.ts` files | (infer from config) |

If no test runner detected, use empty state.

### Existing Issue Templates

Check for `.github/ISSUE_TEMPLATE/` directory. If it exists, count the number of template files inside.

### Repo Size

Count files in the repository (excluding `.git/`, `node_modules/`, `vendor/`, `__pycache__/`, `.venv/`, `venv/`, `dist/`, `build/`, `.next/`, `target/`):

| Count | Size |
|-------|------|
| < 100 | small |
| 100 - 1000 | medium |
| > 1000 | large |

Use `git ls-files` for an efficient count (only tracked files), or fall back to a find command excluding common vendor directories.

---

## Step 2 — Suggest Defaults

Based on detections, customize defaults from the base schema (see `docs/config-schema.md`):

### Test Timeout (`resolve.test_timeout`)

| Repo size | Timeout |
|-----------|---------|
| small | 60 |
| medium | 300 |
| large | 600 |

### Auto Test (`resolve.auto_test`)

- If a test runner was detected: `true`
- If no test runner detected: `false`

### Stale Threshold (`triage.stale_threshold_days`)

| Repo size | Threshold |
|-----------|-----------|
| small | 7 |
| medium | 14 |
| large | 30 |

### Framework-Specific Suggestions

Add inline `#` comments in the generated YAML when a framework is detected:

- **Next.js / Nuxt.js**: comment suggesting `resolve.test_timeout` may need increase for E2E tests
- **Django / Rails / Spring**: comment noting integration test suites may be slow
- **React / Vue / Angular**: comment about component test patterns

These are comments only — they do not change default values.

---

## Step 3 — Write Config

Write `.gitissue.yml` to the repo root. The file must include:

1. A header comment with detection results
2. Every field from the full schema (`docs/config-schema.md`)
3. Inline `#` comments explaining each setting
4. Framework-specific comments where applicable
5. Values customized per Step 2 logic

### Template

Generate the file following this structure (values and comments adjusted based on detections):

```yaml
# gitissue configuration
# Generated by /init-gitissue
# Detected: {language} | {framework} | {test_runner} | {repo_size} repo ({file_count} files)

# Platform for issue management
# Values: "github" | "gitlab"
platform: github

# Issue creation and normalization settings
issue:
  # Auto-normalize issues in /issue-resolver before resolution
  auto_normalize: true

  # Issue template source
  # Values: "default" | path to custom template directory
  template: default

  # Auto-suggest labels based on issue content and type
  labels_auto_suggest: true

  # Post a comment when normalizing an issue
  normalize_comment: true

# Resolution pipeline settings
resolve:
  # Approval gate for the plan phase
  # Values: "auto" | "comment-and-wait"
  approval_gate: auto

  # Branch naming prefix
  # "auto" uses type-based prefixes: fix/, feat/, refactor/, docs/, test/, chore/
  # Branch format: {type}/{issue_number}-{short-description}
  # Examples: fix/42-mobile-auth-redirect, feat/15-add-dark-mode
  # Set a custom string (e.g., "issue-") to override type-based naming
  branch_prefix: "auto"

  # Run tests before creating PR
  auto_test: {true_or_false}

  # Abort verify phase after N seconds
  # Range: 30-3600
  test_timeout: {timeout_value}

  # Include "Closes #N" in PR body for auto-close on merge
  pr_auto_link: true

  # Warn if resolve produces more than N commits
  max_commits: 10

# Triage settings
triage:
  # Flag issues with no activity beyond this threshold (days)
  stale_threshold_days: {stale_value}

  # Suggest priorities based on type, age, and dependency position
  auto_priority: true

  # Include recently closed issues in triage analysis
  include_closed: false

  # Max seconds to scan codebase per issue for file dependencies
  scan_timeout_per_issue: 30

# Issue analysis settings
analysis:
  # Max files to read during deep analysis (5-100)
  max_files: 30

  # How many levels of import dependencies to trace (1-5)
  trace_depth: 3

  # Max seconds for the full codebase scan phase (30-600)
  scan_timeout: 120
```

If **merge** mode was chosen, read the existing file first, preserve all user-set values, and only add fields that are missing.

If the file write fails, output the error from `references/error-messages.md` and stop:
```
✗ Could not write .gitissue.yml

  To fix:  check file permissions in the repo root
  Check:   do you have write access? ls -la .
```

If existing issue templates were detected in `.github/ISSUE_TEMPLATE/`, add a comment:

```yaml
  # Note: .github/ISSUE_TEMPLATE/ found ({N} templates)
  # Set template to ".github/ISSUE_TEMPLATE" to use your existing templates
  template: default
```

---

## Step 4 — Report

Print a structured step-by-step summary showing what was detected and configured:

```
◆ Init Gitissue — setup complete
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Git repo:          ✓ pass
  Language:          ✓ {language} (from {file})
  Framework:         ✓ {framework}
  Test runner:       ✓ {test_runner}
  Templates:         ✓ {template_status}
  Repo size:         ✓ {size} ({count} files)
  Config:            ✓ generated .gitissue.yml
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            DONE

  Config: .gitissue.yml
  Next action: /issue-creator to create your first issue
```

### Variations

**No framework detected** — show:
```
  Framework:         ○ skip (not detected)
```

**No language detected** — show:
```
  Language:          ⚠ warn (unknown — using generic defaults)
```
And earlier in the flow, print:
```
○ Could not detect project language. Using generic defaults.
  Tip: add a package.json, requirements.txt, or go.mod to help detection.
```

**No test runner detected** — show:
```
  Test runner:       ⚠ warn (none — auto_test disabled)
```
And earlier in the flow, print:
```
○ Could not detect test runner. Setting resolve.auto_test: false.
  Tip: configure your test command in .gitissue.yml after setup.
```

**No issue templates** — show:
```
  Templates:         ○ skip (none found)
```

**Existing issue templates** — show:
```
  Templates:         ✓ .github/ISSUE_TEMPLATE/ ({N} templates)
```

**Merge mode** — change Config line and result:
```
  Config:            ✓ merged into existing .gitissue.yml ({N} new, {M} preserved)
```

**Overwrite mode** — change Config line:
```
  Config:            ✓ replaced .gitissue.yml with new config
```

---

## Example: TypeScript + Next.js project

**User says:** `/init-gitissue`

1. Prerequisites pass — git repo confirmed
2. No existing `.gitissue.yml` found
3. Scan:
   - `package.json` found → TypeScript (typescript in devDependencies)
   - `next` in dependencies → Next.js
   - `jest.config.ts` found → Jest
   - `.github/ISSUE_TEMPLATE/` found with 3 files
   - `git ls-files` returns 342 files → medium
4. Defaults: `test_timeout: 300`, `auto_test: true`, `stale_threshold_days: 14`, `scan_timeout_per_issue: 30`
5. Write `.gitissue.yml` with Next.js-specific comments
6. Report:

```
  ● Scanning repository...
    Language:    TypeScript (detected from package.json)
    Framework:   Next.js
    Test runner: Jest
    Templates:   .github/ISSUE_TEMPLATE/ found (3 templates)
    Repo size:   medium (342 files)

  ◆ Configuration
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    Generated .gitissue.yml with project-specific defaults

  ✓ Setup complete
    Config: .gitissue.yml
    Run /issue-creator to create your first issue
```

## Example: Minimal Python project

**User says:** `/init-gitissue`

1. Prerequisites pass
2. No existing `.gitissue.yml`
3. Scan:
   - `requirements.txt` found → Python
   - No known framework in requirements
   - No test runner markers found
   - No `.github/ISSUE_TEMPLATE/` directory
   - 47 tracked files → small
4. Print: `○ Could not detect test runner. Setting resolve.auto_test: false.`
5. Defaults: `test_timeout: 60`, `auto_test: false`, `stale_threshold_days: 7`, `scan_timeout_per_issue: 30`
6. Write `.gitissue.yml`
7. Report:

```
  ○ Could not detect test runner. Setting resolve.auto_test: false.
    Tip: configure your test command in .gitissue.yml after setup.

  ● Scanning repository...
    Language:    Python (detected from requirements.txt)
    Test runner: none
    Templates:   none found
    Repo size:   small (47 files)

  ◆ Configuration
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    Generated .gitissue.yml with project-specific defaults

  ✓ Setup complete
    Config: .gitissue.yml
    Run /issue-creator to create your first issue
```

## Example: Config already exists (merge)

**User says:** `/init-gitissue`

1. Prerequisites pass
2. `.gitissue.yml` already exists — show overwrite/merge/cancel prompt
3. User chooses **merge**
4. Read existing file, scan repo, add missing fields
5. Report:

```
  ● Scanning repository...
    Language:    Go (detected from go.mod)
    Framework:   Gin
    Test runner: Go test
    Templates:   none found
    Repo size:   large (1847 files)

  ◆ Configuration
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    Merged new fields into existing .gitissue.yml
    3 new fields added, 8 existing values preserved

  ✓ Setup complete
    Config: .gitissue.yml
    Run /issue-creator to create your first issue
```

---

## Terminal Output

Follow DESIGN.md symbol vocabulary and output structure for all output. Key rules:

- Symbols: `●` progress, `✓` success, `✗` failure, `◆` section header, `⚠` warning, `○` info
- Two-space indent for content under section headers
- Section separators: `┄` (light dash)
- Max 80 chars wide (truncate with `...`)
- One blank line between sections
- Static sequential output — each step prints a new line, no animation

## Error Handling

All errors use the rich format from `references/error-messages.md`:

```
✗ Short error description

  To fix:  <actionable command>
```

## Additional Resources

- **`references/error-messages.md`** — Complete error catalog with triggers and exact output
- **`docs/naming-conventions.md`** — Branch, commit, PR, and issue naming conventions (referenced by generated config)
- **`docs/config-schema.md`** — Full configuration schema that this skill generates
- **`DESIGN.md`** — Terminal output style guide (repo root)
