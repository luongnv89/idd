---
name: init-gitissue
description: "Generate a .gitissue.yml by auto-detecting a repo's stack, test runner, and size. Use to init, setup, or configure gitissue, or set up IDD. Don't use for editing an existing .gitissue.yml, creating issues (use /issue-creator), or plain git/npm init."
license: MIT
compatibility: "Requires git. No GitHub CLI or authentication needed — generates a local config file only."
metadata:
  version: 0.4.0
  author: "Luong NGUYEN <luongnv89@gmail.com>"
  effort: low
---

# /init-gitissue

Initialize gitissue for the current repository. Scans the codebase to detect language, framework, test runner, and repo size, then generates a `.gitissue.yml` config file with project-specific defaults.

**Invocation**: `/init-gitissue` — interactive. `/init-gitissue --auto` (or `IDD_AUTO_MODE=1`) — no prompts; an existing `.gitissue.yml` is kept.

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

```text
✗ Missing bundled dependency: {missing_file}

  To fix:  asm install https://github.com/luongnv89/idd --skill init-gitissue
           (or reinstall the full distribution)
  Plugin:  claude plugin marketplace add luongnv89/idd
           claude plugin install idd@idd
           (or: claude plugin update idd@idd)

  Then restart the agent session and re-run /init-gitissue.
```

Check these files relative to the skill's directory (the dirname of this SKILL.md):

- `templates/gitissue-template.yml` — canonical config template with all schema fields
- `references/error-messages.md` — complete error catalog with triggers and exact output
- `references/examples.md` — worked example runs
- `references/run-stats.md` — run-stats footer contract (shape, fields, unavailable marker)
- `references/review-contract.md` — report statuses, evidence, uncertainty, decision, format rule
- `references/merge-strategy-check.md` — optional post-write merge-settings check
- `references/docs/config-schema.md` — full configuration schema
- `references/docs/naming-conventions.md` — naming conventions (referenced by generated config)
- `references/docs/idd-methodology.md` — IDD methodology reference
- `references/docs/github-projects-sync.md` — GitHub Projects status sync reference
- `references/docs/platform-github.md` — GitHub platform driver reference
- `references/docs/terminal-style.md` — terminal output style contract (symbols, output structure, table/error formats)
- `references/scripts/gi-stack-detect.py` — language, framework, test-runner, and size detection

## Configuration Check

This skill GENERATES the config — it does not read one. Check if `.gitissue.yml` already exists in the repo root before proceeding. **Capture the run clock in that same check:** chain the first shell as `…; ec=$?; date +%s >&2; exit "$ec"` and keep the stderr epoch as `run_started_epoch` — the check's exit stays intact, it costs no extra round trip, and it is what the *Run Stats Footer* (`references/run-stats.md`) measures `elapsed` from.

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

- **overwrite** — run full generation. Keep the existing file until Step 3 replaces it in one write.
- **merge** — read the existing file. If it does not parse as YAML, print *Existing config does not parse* (`references/error-messages.md`), leave it untouched, and stop with `Result: BLOCKED`. Otherwise preserve every user-set value and add only the schema fields it lacks.
- **cancel** — make no change. Report `Result: CANCELLED`.
- **Auto mode** (`--auto` or `IDD_AUTO_MODE=1`) — do not prompt. Print `⚠ Auto mode: overwrite/merge/cancel prompt skipped — kept the existing .gitissue.yml (cancel).` and take **cancel**, the safe default.

---

## Step 1 — Scan Repository

Detect project characteristics by checking for specific files and directories.
That is file-existence and dependency-name lookup, not reasoning, so run
`shared/scripts/gi-stack-detect.py` from the repo root (resolve the script path
relative to this SKILL.md exactly as the *Bundled dependency precheck* resolves
its list):

```bash
python3 shared/scripts/gi-stack-detect.py --root .
```

Exit 0 prints one JSON object: `language`, `framework`, `test_runner` (each with
its `_source` file), `repo_size`, `file_count`, `file_count_source`,
`issue_templates`, a `derived` block carrying the Step 2 values
(`auto_test`, `test_timeout`, `stale_threshold_days`), and `unresolved`.

**`unresolved` is the LLM fallback trigger, and the only one.** It names the
fields nothing in the table matched. A `null` there is a real answer ("no marker
file is present"), not a failure — the script never guesses. For each field it
names, and *only* those, work it out yourself from the tables below; leave every
resolved field exactly as the script reported it. `file_count_source` says
whether the count came from `git ls-files` or a filesystem walk; report the
count as given rather than re-deriving it.

Classify **every** outcome:

| Outcome | Meaning | Do |
|---------|---------|----|
| exit 0 | detected | use the output; resolve `unresolved` fields from the tables below |
| exit 3 | invalid input — a bad `--root` or `--rules` file | **stop**; print the error from `references/error-messages.md` (*Stack detection failed*). Never degrade past exit 3 |
| script file absent | broken install, not a runtime problem | stop with the `✗ Missing bundled dependency` block above |
| no `python3`, exit 2, exit 4, unparsable stdout | environment problem | print `⚠ gi-stack-detect unavailable — detecting inline` and run the whole of the tables below by hand |

Pass `--rules FILE` to replace a built-in table for a repository the defaults do
not describe — a JSON object of `{"language": [[glob, name]], "framework":
[[dependency, name]], "test_runner": [[kind, pattern, name]]}`, where each key
replaces the matching table outright.

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

If several language markers exist, use the one at the repo root. If several are at the root, use the language with the most source files. If none is detected, use empty state.

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

If no framework is detected, print the `○ skip` Framework row (not an error).

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

The script's `derived` block already carries these three values; the tables
below are what it computed them from, and what to apply by hand when Step 1
degraded. Everything else is customized from the base schema (see
`docs/config-schema.md`):

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
6. When Step 1 found `.github/ISSUE_TEMPLATE/`, this comment above `template:`:

```yaml
  # Note: .github/ISSUE_TEMPLATE/ found ({N} templates)
  # Set template to ".github/ISSUE_TEMPLATE" to use your existing templates
  template: default
```

### Template

Use the canonical template at `templates/gitissue-template.yml` — it contains every field from `docs/config-schema.md` with inline comments. At write time, substitute the placeholder tokens (`{language}`, `{framework}`, `{test_runner}`, `{repo_size}`, `{file_count}`, `{true_or_false}`, `{timeout_value}`, `{stale_value}`) with the values computed in Step 2. Read `templates/gitissue-template.yml` to see the exact field layout.

In **merge** mode, write the existing file's values plus the missing fields, per the *File exists* rules.

If the file write fails, output the error from `references/error-messages.md` and stop:
```
✗ Could not write .gitissue.yml

  To fix:  check file permissions in the repo root
  Check:   do you have write access? ls -la .
```

### Validate the written config (mandatory)

A write that succeeded is not a config that works. Before reporting success,
re-read the file just written and verify three things:

1. **It parses as YAML.** `python3 -c "import yaml,sys; yaml.safe_load(open('.gitissue.yml'))"` — or, when PyYAML is unavailable, `ruby -ryaml -e "YAML.load_file('.gitissue.yml')"`. If neither parser is available, print `○ Config validation skipped — no YAML parser available` and treat the validation check as `PARTIAL`, never `PASS`.
2. **No placeholder token survived substitution.** `grep -nE '\{(language|framework|test_runner|repo_size|file_count|true_or_false|timeout_value|stale_value)\}' .gitissue.yml` must return nothing. Any hit means Step 3 substitution missed a token.
3. **The `platform` key is present** — it is the driver selector every skill resolves on load, so a config without it is unusable.

On a parse error, a surviving placeholder, or a missing `platform` key, do **not**
report success. Print the matching error from `references/error-messages.md` (*Generated config failed
validation*), leave the file in place for inspection, and stop with `Result: BLOCKED`.

### Merge strategy check (optional)

After a validated write, run the two read-only repository-settings reads in
`references/merge-strategy-check.md`. That file defines when the check is
skipped, the two independent warnings, and the `Merge settings:` report row. The
check never changes a setting and never changes `Result`.

---

## Step 4 — Report

Print the report below. `references/review-contract.md` defines each `Result`
status (`DONE`, `PARTIAL`, `BLOCKED`, `CANCELLED`) and what the `Evidence`,
`Uncertainty`, `Decision`, and `Next action` rows must carry. Print `✓` only for
a check that ran and passed.

**Then the run-stats footer.** Close with the *Run Stats Footer* — `references/run-stats.md` — `elapsed`, `tokens` only where the host reported a count (otherwise left out), `agents`, run cost only, `n/a` for anything else undetermined. It is the last thing printed at **every** terminal outcome, including a run that wrote no config — a failed prerequisite, a declined overwrite, or a scan that could not complete. This skill spawns no subagents, so `agents 0` is the determined value here, not `n/a`.

```
◆ Init Gitissue — setup complete
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Result:            DONE — .gitissue.yml generated and validated
  Git repo:          ✓ pass
  Language:          ✓ {language} (from {file})
  Framework:         ✓ {framework} (from {file})
  Test runner:       ✓ {test_runner} (from {file})
  Templates:         ✓ {template_status}
  Repo size:         ✓ {size} ({count} files, via {file_count_source})
  Config:            ✓ generated .gitissue.yml
  Validation:        ✓ parses as YAML, no placeholders left, platform set
  Merge settings:    ✓ squash-only, PR_BODY
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Evidence:          gi-stack-detect exit 0; re-read with {parser}
  Uncertainty:       values from marker files; no test command run
  Decision:          No approval needed.

  Config: .gitissue.yml
  Next action: review and commit .gitissue.yml, then /issue-creator
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

**Validation could not run** — no YAML parser available; show:
```
  Validation:        ⚠ warn (skipped — no YAML parser available)
```
and set `Result: PARTIAL — config written; parse check skipped`.

**No issue templates** — show:
```
  Templates:         ○ skip (none found)
```

**Existing issue templates** — show:
```
  Templates:         ✓ .github/ISSUE_TEMPLATE/ ({N} templates)
```

**Merge mode** — change Config line:
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

## Output Conventions

Terminal output follows the `docs/terminal-style.md` contract — symbols `● ✓ ✗ ◆ ⚡ ⚠ ○`, two-space indent, `┄` separators, URLs on their own line, ≤80 chars, one blank line between sections, static sequential output (no animation). Errors use the rich format from `references/error-messages.md`: `✗ what failed`, then `To fix:  <command>`, then a docs link when applicable.

## Expected Output

After a successful run the repo root contains a validated `.gitissue.yml` and the
terminal prints the *Step 4 — Report* block above — the `Validation:` row is the
checkable bar: the run only reports `DONE` after the written file parsed as YAML
with no placeholder tokens left and a `platform` key. Variations (merge mode,
missing framework, missing test runner) are listed under that step. Grade report
understanding — findable result, separated facts, traceable claims, clear next
decision — with the criteria in `references/review-contract.md`.

## Edge Cases

- **Config already exists** — interactive runs show an overwrite / merge / cancel prompt; auto mode skips it, takes cancel, and prints the `⚠ Auto mode:` line. Neither prints a diff of detected vs current values.
- **Unrecognized language** — falls back to a minimal generic config with inline comments guiding manual edits.
- **Not a git repository** — prints the exact error from `references/error-messages.md` and stops; no file is written.
- **Empty repo (no source files)** — writes a minimal default config; the Language and Test runner rows print their `⚠ warn` variants.

## Additional Resources

- **`references/error-messages.md`** — Complete error catalog with triggers and exact output
- **`docs/naming-conventions.md`** — Branch, commit, PR, and issue naming conventions (referenced by generated config)
- **`docs/config-schema.md`** — Full configuration schema that this skill generates
- **`docs/terminal-style.md`** — Terminal output style contract (bundled at build time; the repo-root `DESIGN.md` is the human-facing companion and is not bundled)
