---
name: issue-creator
description: "Create structured GitHub issues from text, screenshots, or lists, with acceptance criteria and preserved reporter context. Use for filing bugs/features, batch creation, or template cleanup. Don't use for resolving, triaging, or deep issue analysis."
license: MIT
compatibility: "Requires git and GitHub CLI (gh) with authentication. Run `gh auth status` to verify."
effort: medium
metadata:
  version: 0.8.0
  author: Luong NGUYEN <luongnv89@gmail.com>
---

# /issue-creator

Creates structured, intent-focused GitHub issues from text, screenshots, or lists. Preserves reporter context and generates acceptance criteria without guessing implementation details.

This skill is an **intent-capture tool only**. It does not analyze the codebase, predict affected files, or generate technical notes. The resolver and triage skills perform their own current-code analysis when needed — see the Output Contract below.

Three modes: **Create** (new issue from text/image), **Normalize** (restructure existing issue #N into standard template), and **Batch** (extract multiple issues from one input).

## Output Contract

Issues produced by `/issue-creator` capture **durable human intent only**. The skill MUST NOT include any of the following in the issue body:

- **No predicted affected files** — file paths, modules, or directories that the skill guessed by inspecting the codebase
- **No generated technical notes** — implementation approach, architecture constraints, or design notes derived from code
- **No root cause** — diagnostic reasoning about *why* a bug occurs in the current code
- **No implementation hints** — code snippets, function signatures, or step-by-step "how to fix" instructions

These four artifacts are the responsibility of `/issue-analysis`, `/issue-triage`, and `/issue-resolver`, which produce them fresh against the current codebase at the moment work begins. Encoding them in the issue body would freeze stale understanding into durable memory.

What the issue body **does** contain: type classification, problem description, reporter context (verbatim), screenshots, acceptance criteria, and metadata (priority, effort, labels, and — when `model_suggestion.enabled` — an advisory **Suggested model:** line naming one OpenAI model and one Anthropic model). Reporter-supplied technical detail is preserved verbatim inside the Reporter Context blockquote — only skill-generated technical content is prohibited.

The model suggestion is the one externally-derived value admitted into the body — advisory cost guidance (like effort), not an implementation hint. It always names exactly two models (one OpenAI, one Anthropic, joined by ` · `) and is stamped with its CursorBench data date so staleness is self-documenting — see `references/model-suggestion.md`.

## Modes

| Invocation | Mode | What happens |
|------------|------|--------------|
| `/issue-creator <text>` | Create | New structured issue from a text description |
| `/issue-creator <N>` | Normalize | Restructure existing issue #N into standard template |
| `/issue-creator <N> --dry-run` | Preview | Show normalization preview without applying |
| `/issue-creator <N> --force` | Force | Normalize even if security-labeled |
| `/issue-creator <multi-item text>` | Batch | Extract multiple issues from one input and create sequentially |
| `/issue-creator … --refresh-model-data` | Refresh | Force-refresh the skill-level model-data cache, then proceed |

Detect mode: if the argument is a number → Normalize. If the input contains multiple distinct items (numbered list, bullet points, multiple paragraphs describing different problems, or a planning document with several work items) → Batch. Otherwise → Create.

**Image/screenshot input**: When the user provides an image path or screenshot, read the image with the Read tool to extract visual context, then treat extracted information as the input description. Combine visual observations with any accompanying text. Additionally, upload the image to GitHub and embed it in the issue body — see the **Image Upload** section below.

## Prerequisites

Before any operation, verify the environment. On failure, output the exact error from `references/error-messages.md` and stop.

1. Confirm git repository: `git rev-parse --git-dir`
2. Confirm `gh` is installed: `which gh`
3. Confirm authentication: `gh auth status`
4. Confirm GitHub remote exists: `git remote -v`

## Repo Sync Before Edits (mandatory)

This skill can write to the repository: in Normalize mode it edits issue bodies, and when images are supplied it commits them to `.github/issue-assets/` via the GitHub contents API. Before any such write, sync with remote using the stash-first pattern (see `docs/sync-conventions.md` for the full convention and recovery procedure):

```bash
branch="$(git rev-parse --abbrev-ref HEAD)"
dirty=0
if [ -n "$(git status --porcelain)" ]; then
  git stash push -u -m "pre-sync: ${branch}"
  dirty=1
fi
git fetch origin
git pull --rebase origin "$branch"
if [ "$dirty" -eq 1 ]; then
  git stash pop || {
    echo "✗ Stash pop failed — recover with: git stash list && git stash show -p stash@{0}"
    exit 1
  }
fi
```

If `origin` is missing or rebase conflicts occur, stop and ask the user before continuing. In a pure Create-from-text run with no image upload, this sync is a no-op safeguard and adds negligible cost.

## Configuration

Load `.gitissue.yml` from the repo root once at skill start. If the file does not exist, use defaults and print:

```
○ First run — using default config. Run /init-gitissue to customize.
```

Defaults: `issue.auto_normalize: true`, `issue.template: "default"`, `issue.labels_auto_suggest: true`, `issue.normalize_comment: true`, `model_suggestion.enabled: true`

If the config file exists but contains invalid values, output the validation error from `references/error-messages.md` and stop. Do not re-read the config at each step.

If `model_suggestion.enabled` is `true` (the default), run the model-data cache lifecycle (check / seed / staleness-refresh) once now, before Step 1 — see `references/model-suggestion.md`. The cache is **skill-level** (a dated `model-data-<date>.json` in the installed skill folder, shared across all repos), not per-repo; `--refresh-model-data` forces a refresh first. When `false`, skip all model-suggestion steps silently.

## Subagent Architecture

The skill delegates **duplicate detection (Step 3)** to a subagent so the main agent's **context window** stays clean and the **token budget** stays predictable. Every other step stays in the main agent: parse input (Step 1) and classify (Step 2) are lightweight; clarify ambiguous intent (Step 3.5), generate content (Step 4), preview (Step 5), and create (Step 6) run inline.

In **batch mode**, the duplicate detector checks all batch items — including internal cross-checks — in a single pass, so only one subagent spawn is needed regardless of batch size, and duplicate checking runs in parallel with template generation.

Read `shared/agents/duplicate-detector.md` for the full duplicate detector prompt.

### Environment check

If the Agent tool is available, use the duplicate-detector subagent as described above for Step 3.
If not (e.g., Claude.ai or environments without the Agent tool), execute duplicate checking inline using the fallback instructions included in Step 3.

### Bundled dependency precheck

Verify that this skill's bundled agent prompt and template files are present.
If any are missing, stop immediately and print:

```
text
✗ Missing bundled dependency: {missing_file}

  To fix:  asm install https://github.com/luongnv89/idd --skill issue-creator
           (or reinstall the full distribution)

  Then restart the agent session and re-run /issue-creator.
```

Check these files relative to the skill's directory (the dirname of this SKILL.md):

- `references/agents/duplicate-detector.md` — duplicate detection subagent prompt
- `templates/bug.md` — bug issue template
- `templates/feature.md` — feature request template
- `templates/improvement.md` — improvement request template
- `references/docs/naming-conventions.md` — issue title and labeling conventions
- `references/docs/github-projects-sync.md` — GitHub Projects status sync reference
- `references/modes.md` — Normalize and Batch mode step specs and error paths
- `references/model-suggestion.md` — model-suggestion cache lifecycle and mapping
- `references/image-upload.md` — image upload procedure and failure handling
- `references/confidence-scoring.md` — confidence levels and per-field determination
- `references/clarify-intent.md` — Step 3.5 clarify-ambiguous-intent full procedure

---

## Image Upload

When the user provides image paths, upload each to GitHub and embed it in the issue body — in addition to reading the image for visual context. Supported formats: PNG, JPG/JPEG, GIF, WEBP, SVG (max 10 MB each). Embeds go in a **Screenshots** section between Description and Acceptance Criteria; omit the section when no images are provided. Upload failures never block creation — the issue is created text-only with a `⚠` warning. Durable embeds require a **public** repo.

See `references/image-upload.md` for the full procedure: validation, the base64-via-stdin `gh api` upload (with the `ARG_MAX` rationale), markdown placement, multi-image handling, failure messages, and normalization-mode preservation.

---

## Confidence Scoring System

Auto-enriched fields (type classification, acceptance criteria, and tool-suggested Metadata values — priority, effort, labels) carry a confidence level shown in previews and written into the issue body: **high** → `(high)` / `(high confidence)`, **medium** → `(medium)` / `(medium confidence)`, **low** → `(needs review)` in both. `high` means explicit keywords or stated requirements; `medium` is inferred from tone/context; `low` is ambiguous and defaulted. When populating templates, fill every `{…_confidence}` placeholder from the tables in `references/confidence-scoring.md`; never ship an inferred field unmarked.

See `references/confidence-scoring.md` for the full level criteria and the per-field determination tables.

---

## Mode: Create New Issue

### Step 1 — Parse Input

Extract from the description:
- Keywords: error messages, component names, file paths, function names
- Implied type: bug (broken behavior, errors, crashes), feature (new capability), improvement (enhancement to existing behavior)

### Step 2 — Classify Type and Title

**Type classification:**
- **bug** — broken behavior, errors, crashes, regressions
- **feature** — new capability, endpoint, UI element, workflow
- **improvement** — enhancement, refactoring, performance, UX polish

**Issue title conventions** (see `docs/naming-conventions.md` for the full reference):
- Use **imperative mood** (like a command): "Fix login crash on mobile" not "Login is crashing"
- Keep titles **concise, descriptive, and actionable** — under 70 characters
- Include **context** when helpful: "Fix checkout page redirect on Safari"
- The title should read as what needs to happen, not what is broken
- Optional **type prefix** for extra clarity: "Bug: App crashes on iOS login"

| Good | Bad |
|------|-----|
| Fix mobile auth redirect loop | Login is broken |
| Add dark mode toggle to settings | Dark mode |
| Refactor auth middleware for OAuth2 | Auth stuff needs updating |
| Bug: App crashes on iOS when tapping login | It doesn't work on my phone |

Assign confidence to the type classification:
- **high** — explicit crash/error/500 keywords (bug), "add new"/"create" (feature), "refactor"/"improve"/"optimize" (improvement)
- **medium** — inferred from description context (e.g., "doesn't work" → bug, "would be nice" → feature)
- **low** — ambiguous description, type defaulted based on most common pattern

### Step 3 — Check for Duplicates

#### Subagent delegation

Spawn the duplicate-detector subagent with:

```json
{
  "mode": "create",
  "items": [
    {
      "index": 1,
      "title": "{classified_title}",
      "keywords": ["{keyword1}", "{keyword2}"],
      "type": "{bug|feature|improvement}"
    }
  ],
  "repo_root": "{repo_root}"
}
```

Read `shared/agents/duplicate-detector.md` for the full prompt. The subagent returns a `duplicates` array with scored matches.

#### Fallback (no Agent tool)

If the Agent tool is not available, run inline:

```bash
gh issue list --state open --json number,title,body,labels --limit 100
```

Compare the new issue's title and key terms against existing issues.

#### Present results

If the subagent (or fallback) found potential duplicates (confidence `medium` or `high`):

```
⚠ Possible duplicate: #42 "Fix auth redirect loop"
  View: https://github.com/owner/repo/issues/42

  Continue creating? [Y/n]
```

If no duplicates found, proceed silently.

### Step 3.5 — Clarify Ambiguous Intent

Active intent capture: when **type classification** or **acceptance-criteria** confidence is `low` — and only in **interactive Create mode** — resolve the ambiguity before drafting. When both are `high`/`medium`, this step is a silent no-op and the one-shot Step 3 → Step 4 path is unchanged.

- **Resolve from the repo first.** A question is only worth asking if the repo cannot answer it. If inspection settles the field (e.g. a `ThemeToggle` already exists → bug, not feature), do not ask — raise confidence to `high` (conclusive) or `medium` (suggestive).
- **Output Contract boundary (critical):** repo inspection here only disambiguates intent and sets confidence; its findings MUST NOT leak into the issue body (no affected files, technical notes, root cause, or implementation hints). This step changes *classification*, never *body content*.
- **How to ask:** at most one or two questions, one at a time, each capturing intent (never implementation), with a recommended default equal to today's `(needs review)` guess, using the plain `[Y/n]` idiom (no special UI widget — the skill also runs on Claude.ai). Accepted default → record at `medium`; override → `high`. Then proceed to Step 4 regardless.
- **Non-interactive contexts (never block):** in Batch mode and any auto/non-interactive context, **skip this step entirely** — draft with the defaulted assumptions and mark those fields `(needs review)` exactly as today.

See `references/clarify-intent.md` for the full gating rules, the repo-resolution rationale, the example prompt, and the non-interactive specification.

### Step 4 — Generate Issue Content

If the user provided image paths, upload them now using the **Image Upload** procedure. Collect the resulting markdown embeds for inclusion in the issue body.

Read the appropriate template from `templates/` (bug.md, feature.md, or improvement.md) and populate every section:

1. **Type** — classified type with confidence
2. **Description** — synthesized from user input, including current/expected behavior (bugs), related components, related issues
3. **Reporter Context** — user's original text, verbatim, in a blockquote
4. **Screenshots** — embedded images (only if images were provided and uploaded successfully)
5. **Acceptance Criteria** — 3-5 testable criteria derived from the problem description, with confidence levels
6. **Metadata** — suggested priority, estimated effort (XS/S/M/L/XL), and suggested labels, **each with a trailing confidence marker** via `{priority_confidence}`, `{effort_confidence}`, and `{labels_confidence}` in the template, plus an advisory **Suggested model:** line keyed off the effort band — see `references/model-suggestion.md`. The suggestion **always names exactly two models — one OpenAI model and one Anthropic model — joined by ` · ` (OpenAI first)**, read from the effort band's `openai` and `anthropic` entries in the cache. `{data_version}` is the version portion of the cache's `source` (e.g. `3.1` from `CursorBench 3.1` — do not repeat the `CursorBench` prefix) and `{data_date}` is the date portion of `last_fetched`. Never collapse it to a single model or a single provider. When `model_suggestion.enabled` is false, remove the `**Suggested model:**` line from the Metadata section entirely, matching pre-feature behaviour.

**Note:** Per the Output Contract above, the issue body MUST NOT include predicted affected files, generated technical notes, root cause, or implementation hints. Acceptance criteria express *what done looks like*, not *how to implement it*.

### Step 5 — Preview and Confirm

```
◆ Issue Preview
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Type:     bug (high)
  Title:    Fix mobile auth redirect loop
  Images:   2 uploaded ✓
  ⚡ Model:  GPT-5.5 High · Opus 4.8 Medium  (~$7.42/task)
  Labels:   bug, auth, mobile
  Criteria: 3 acceptance criteria generated (medium)

Create issue? [Y/n]
```

The `Images:` line appears only when images were provided. Show count and upload status. If some failed: `Images: 1/2 uploaded (1 failed)`. The `⚡ Model:` line appears only when `model_suggestion.enabled`, and always pairs one OpenAI model with one Anthropic model joined by ` · ` (OpenAI first) — never a single model — see `references/model-suggestion.md`.

Wait for confirmation. If declined, stop without creating.

### Step 6 — Create Issue

```bash
gh issue create --title "{title}" --body "{populated_template}" --label "{labels}"
```

The body is the fully populated template including `<!-- gitissue:normalized v1 -->` at the top.

Print a structured step-by-step summary:

```
◆ Issue Created
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Parse input:       ✓ pass
  Classify:          ✓ pass ({type})
  Duplicates:        ✓ pass (no duplicates found)
  Template:          ✓ pass
  Preview:           ✓ approved
  Create:            ✓ pass
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            DONE

  #42  {title}
  https://github.com/owner/repo/issues/42
```

If duplicates were found but user proceeded:
```
  Duplicates:        ⚠ warn ({N} potential duplicates, user overrode)
```

On failure, output the matching error from `references/error-messages.md`.

---

## Modes: Normalize & Batch Create

In addition to **Create**, the skill supports two more modes, each with its own step-by-step flow:

- **Normalize** — fetch an existing issue, classify it, fill in missing sections, and update the issue body.
- **Batch Create** — parse a multi-item input, preview parsed items, and create one issue per item with per-item success/failure tracking.

Full per-mode step specs and error paths live in `references/modes.md`. Example runs (batch from a planning document, create from a vague description) live in `references/examples.md`.

---
## Platform Driver

All tracker access follows the GitHub driver — `--json` with explicit field selection, never parsed text output. The full operation catalog and driver rules live in docs/platform-github.md.

## Output Conventions

Terminal output follows the DESIGN.md contract — symbols `● ✓ ✗ ◆ ⚡ ⚠ ○`, two-space indent, `┄` separators, URLs on their own line, ≤80 chars, one blank line between sections, static sequential output (no animation); issue-creator additionally uses `+` (added field) and `=` (preserved field). Errors use the rich format from `references/error-messages.md`: `✗ what failed`, then `To fix:  <command>`, then a docs link when applicable.

## GitHub Projects Sync

After each issue is created (single or batch), if `projects.sync_enabled` is `true` in `.gitissue.yml`, sync it to the repo's GitHub Project board per `docs/github-projects-sync.md`: discover the linked project (or use the cached project ID), add the issue, and set its Status to `projects.status_map.todo` (default: "Todo"), printing `✓ Added to project "{project_title}" — Status: Todo`.

If `projects.sync_enabled` is `false` (default), skip silently. If any sync step fails, print a `⚠` warning and continue — never block issue creation on project sync failure. See `docs/github-projects-sync.md` for error messages and graceful degradation details.

## Expected Output

A successful create prints the issue URL and a compact summary:

```
  ✓ Issue #42 created
    https://github.com/owner/repo/issues/42

  Title:  Fix mobile auth redirect loop
  Type:   bug (high confidence)
  Labels: bug, auth, mobile
```

In batch mode, one line per issue is printed followed by a totals footer (`✓ 5 created, 1 skipped (duplicate)`).

## Edge Cases

- **Duplicate detection** — if an existing open issue closely matches, the skill asks before filing; the user can dedupe or create anyway.
- **Screenshot-only input** — the image is inspected, described in text, and a structured issue is drafted; the image is also attached to the issue body.
- **Ambiguous batch input** — if item boundaries are unclear, the skill shows a parsed preview and asks for confirmation before creating.
- **GitHub API rate limit** — creation stops at the last successful issue; the partial result is reported with a resume hint.
- **Empty body** — the issue is created with only a title; `(needs review)` is noted in the metadata section.

## Additional Resources

- **`references/error-messages.md`** — Complete error catalog with triggers and exact output
- **`docs/naming-conventions.md`** — Issue title and labeling conventions
- **`docs/github-projects-sync.md`** — Shared GitHub Projects status sync reference
- **`templates/bug.md`** — Bug report template
- **`templates/feature.md`** — Feature request template
- **`templates/improvement.md`** — Improvement template
- **`references/model-suggestion.md`** — Model-suggestion cache + complexity→model mapping
- **`references/image-upload.md`** — Image upload procedure, placement, and failure handling
- **`references/confidence-scoring.md`** — Confidence levels and per-field determination tables
- **`references/clarify-intent.md`** — Step 3.5 clarify-ambiguous-intent full procedure and example
