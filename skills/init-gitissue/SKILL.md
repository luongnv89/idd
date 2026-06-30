---
name: init-gitissue
description: "Generate a .gitissue.yml by auto-detecting a repo's stack, test runner, and size. Use to init, setup, or configure gitissue, or set up IDD. Don't use for editing an existing .gitissue.yml, creating issues (use /issue-creator), or plain git/npm init."
license: MIT
compatibility: "Requires git. No GitHub CLI or authentication needed — generates a local config file only."
effort: low
metadata:
  version: 0.3.5
  author: Luong NGUYEN <luongnv89@gmail.com>
---

# /init-gitissue

Initialize gitissue for the current repository. Scans the codebase to detect language, framework, test runner, and repo size, then generates a `.gitissue.yml` config file with project-specific defaults.

**Invocation**: `/init-gitissue` — no arguments.

## When to Use

- **Do** run this skill the first time a repository starts using gitissue, or when the existing `.gitissue.yml` is outdated after a stack migration.
- **Do** treat it as idempotent for the "already exists" path — merge or overwrite based on user confirmation.
- **Avoid** running it every session — it is a one-time setup skill.
- **Never** modify or delete files outside the repo root, and never commit the generated config (leave that to the user).

**Context and token budget:** this skill stays small — it reads only a handful of files (`package.json`, `requirements.txt`, etc.) to keep the main agent's context window compact.

## Instructions

1. Verify prerequisites (git repo present).
2. Check for an existing `.gitissue.yml` and follow the merge path if found.
3. Scan the repository to detect language, framework, test runner, and size.
4. Suggest defaults based on detection.
5. Write `.gitissue.yml` to the repo root.
6. Print a report of detected values and next-step suggestions.

## Prerequisites

Before any operation, verify the environment. On failure, output the exact error from `references/error-messages.md` and stop.

1. Confirm git repository: `git rev-parse --git-dir`

That is the only prerequisite. This skill does not need `gh` or GitHub authentication — it generates a local config file.

### Bundled dependency precheck

Verify that this skill's bundled template and reference files are present. If any are missing,
stop immediately and print:

```
text
✗ Missing bundled dependency: {missing_file}

  To fix:  asm install https://github.com/luongnv89/idd --skill init-gitissue
           (or reinstall the full distribution)

  Then restart the agent session and re-run /init-gitissue.
```

Check these files relative to the skill's directory (the dirname of this SKILL.md):

- `templates/gitissue-template.yml` — canonical config template with all schema fields
- `references/docs/config-schema.md` — full configuration schema
- `references/docs/naming-conventions.md` — naming conventions (referenced by generated config)

## Configuration Check

This skill GENERATES the config — it does not read one. Check if `.gitissue.yml` already exists in the repo root before proceeding.

### File does NOT exist — always create

When the file is missing, **always create it** without prompting. This happens regardless of context — even when the skill is invoked non-interactively from another skill. No early exit, no conditions, no cancel option.

```
○ No .gitissue.yml found — generating config...
```

Proceed directly to **Step 1 — Scan Repository**.

### File exists — ask user

If the file already exists, show the prompt from `references/error-messages.md`:

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

Based on detections, customize defaults from the base schema (see `references/docs/config-schema.md`):

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
2. Every field from the full schema (`references/docs/config-schema.md`)
3. Inline `#` comments explaining each setting
4. Framework-specific comments where applicable
5. Values customized per Step 2 logic

### Template

Use the canonical template at `templates/gitissue-template.yml` — it contains every field from `references/docs/config-schema.md` with inline comments. At write time, substitute the placeholder tokens (`{language}`, `{framework}`, `{test_runner}`, `{repo_size}`, `{file_count}`, `{true_or_false}`, `{timeout_value}`, `{stale_value}`) with the values computed in Step 2. Read `templates/gitissue-template.yml` to see the exact field layout.

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

## Example Runs

Full example outputs for three scenarios (TypeScript + Next.js project, minimal Python project, config-already-exists merge) live in `references/examples.md` — read that file when debugging detection or merge behavior.

---
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

## Expected Output

After a successful run, the repo root contains a `.gitissue.yml` file and the terminal prints:

```
  ✓ Wrote .gitissue.yml (24 lines)

  Detected:
    language:    TypeScript
    framework:   Next.js
    test_runner: vitest
    repo_size:   medium (42 files)

  Run /auto-pilot to start the loop, or /issue-creator to file a first issue.
```

## Edge Cases

- **Config already exists** — the skill prints a diff of detected vs current values and asks before overwriting.
- **Unrecognized language** — falls back to a minimal generic config with inline comments guiding manual edits.
- **Not a git repository** — prints the exact error from `references/error-messages.md` and stops; no file is written.
- **Empty repo (no source files)** — writes a minimal default config and notes that detection was skipped.

## Additional Resources

- **`references/error-messages.md`** — Complete error catalog with triggers and exact output
- **`references/docs/naming-conventions.md`** — Branch, commit, PR, and issue naming conventions (referenced by generated config)
- **`references/docs/config-schema.md`** — Full configuration schema that this skill generates
- **`DESIGN.md`** — Terminal output style guide (repo root)
