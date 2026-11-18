# Prompt audit: `src/skills/init-idd`

**Assumptions**
- **Scope:** every runtime file under `src/skills/init-idd/`: `SKILL.source.md`, `references/{error-messages,examples,merge-strategy-check,review-contract}.md` and `templates/idd-template.yml`. I left out `LICENSE` and `docs/README.md` because the agent never loads them. I also left out the shared files bundled into the skill from elsewhere (`references/run-stats.md`, `references/self-improve.md`, the `references/docs/*` runtime docs and `gi-stack-detect.py`). I read the script only to check facts.
- **Target model:** these are coding-agent skill files. The skill sets no model (only `metadata.effort: low`), so I audited them against the model running this audit, **Claude Opus 5.5**.
- **Not run:** `bash scripts/build.sh` needed approval that wasn't given. I checked the build output against the committed `skills/init-idd/` instead.

## Summary

The four findings that matter most:

1. **The generated `.idd.yml` points users at files that don't exist in their repo.** The build turns `docs/X.md` in the template into `references/docs/X.md`. That path only exists inside the skill bundle, so in the user's repo the three doc pointers in the config's comments go nowhere. A fourth comment in the same file already uses an absolute URL.
2. **`SKILL.md` contradicts itself in two places.** It says "This skill GENERATES the config — it does not read one", then reads the existing file for the context threshold and for merge. Its Edge Cases also promise a "minimal" config, but Step 3 requires every schema field.
3. **The fallback detection tables have drifted from the script.** If the script can't run, the hand-run framework table matches `react` before `next`, so a Next.js repo comes out as React. The language tie-break and the 1000-file size boundary also disagree with the script.

**Counts by group:**
- **Group 1 (dated prompt text):** 5 findings (1a: 1 · 1c: 3 · 1d: 1).
- **Group 2 (brittle skill and config files):** 11 findings.
- **Group 3 (tool descriptions):** 0. The frontmatter `description` is routing text and is fine.
- **Group 4 (request config):** not applicable. There's no request-building code and the skill spawns no subagents.

## Findings

| # | Location | Evidence | Pattern | Why it's a problem | Confidence | Action |
|---|---|---|---|---|---|---|
| 1 | `templates/idd-template.yml:6,52,186` | `see docs/platform-github.md`, `See docs/naming-conventions.md`, `See docs/github-projects-sync.md` (built: `references/docs/…`) | G2 Volatile specifics: path doesn't resolve | The template is written into the **user's** repo as `.idd.yml`, where `references/docs/` doesn't exist. Line 246 already uses `https://github.com/luongnv89/idd/blob/main/docs/…`, which the build accepts (only `/src/docs/` URLs fail). | High | rewrite to absolute URLs. Also drop the precheck line for `github-projects-sync.md`, because nothing else in the skill cites it. |
| 2 | `SKILL.source.md:102` | `This skill GENERATES the config — it does not read one.` | G2 conflict (same file) + 1a caps | `:104` reads `compaction.*` from an existing `.idd.yml`, and `:136` (merge) reads the existing file. | High | rewrite |
| 3 | `SKILL.source.md:475,477` | `falls back to a minimal generic config with inline comments guiding manual edits` / `writes a minimal default config` | G2 conflict (same file) | `:303-306` and `:320` always write the full template with every schema field. No "manual-edit comments" are defined anywhere. | High | rewrite |
| 4 | `SKILL.source.md:201-217` | Framework table lists `react` before `next`, with no precedence rule | G2 duplicated data that drifted | `gi-stack-detect.py:105-113` tests `next`, `nuxt` and `angular` before `react` because every Next.js project also depends on `react`. If the script can't run, a Next.js repo resolves to React. | High | rewrite (reorder rows and add a first-match rule) |
| 5 | `SKILL.source.md:183,195,253-255` | `repo root (or nearby)`; `use the language with the most source files`; `100 - 1000 → medium`, `> 1000 → large` | G2 duplicated data that drifted | The script takes the shallowest marker and breaks ties by table order (`:326-333`). Its bands are `<100`, `<1000`, then large (`:157`), so 1000 files is large, not medium. | Medium | rewrite |
| 6 | `SKILL.source.md:25` | `it reads only a handful of files (package.json, requirements.txt, etc.)` | G2 Volatile specifics | This line dates from 2026-04-20, before the script existed. Step 1 now hands those reads to `gi-stack-detect.py` precisely so the agent doesn't read them. | Medium | remove |
| 7 | `SKILL.source.md:108` | `**always create it** … regardless of context — even when … No early exit, no conditions, no cancel option.` | 1a pressure language / 1c repetition | The rule is said four times. Opus 5.5 follows a single plain statement, and the stacked emphasis makes it read as more absolute than the legacy-file exception allows. | Medium | rewrite |
| 8 | `templates/idd-template.yml:136-139` | `that combined opt-in reaches the prior 2.1.x "merge anyway with follow-up" path` | 1d migration-relative phrasing | It describes the setting by comparing it to a version the reader never saw. The project's own writing rules (CLAUDE.md, "Describe current behaviour as the only behaviour") forbid this. The same phrase is in `docs/config-schema.md:310`, which is outside this scope. | Medium | rewrite |
| 9 | `SKILL.source.md:484` | `(bundled at build time; the repo-root DESIGN.md is the human-facing companion and is not bundled)` | G2 maintainer material in the bundle | It points the runtime agent at a file it can't reach. CLAUDE.md's "Keep maintainer material out of the bundle" rule covers this. | Medium | remove the parenthetical |
| 10 | `references/error-messages.md:5` | `…is the gap that contract exists to close… which is the contract working, not a hole in it.` | 1c padding / G2 history narrative | It argues the rule with a reviewer instead of stating it. Only the rule itself is actionable. | Medium | rewrite |
| 11 | `references/error-messages.md:100-108` | `### Directory not writable` | G2 duplicate that can drift | No step in `SKILL.md` raises it, and review-contract's `BLOCKED` list leaves it out. Its trigger overlaps *Write failed* (permission denied, read-only filesystem), so the agent has two blocks for one condition. | Medium | remove, and fold its trigger into *Write failed* |
| 12 | `references/review-contract.md:76-78` | `An interactive report does not apply — there is nothing to filter, and project convention forbids terminal animation…` | 1c prohibition against a failure the model wasn't going to make / rubric answer | Deleting it changes neither what's allowed nor how success is measured. It answers a review-checklist question, not a runtime one. | Medium | remove that sentence |
| 13 | `SKILL.source.md:22` | `**Avoid** running it every session — it is a one-time setup skill.` | 1c prohibition list | The model has no reason to run this every session anyway. | Low | flag |
| 14 | `SKILL.source.md:176-179` | `Pass --rules FILE to replace a built-in table…` | G2 option menu | Nothing says when to use it, and `unresolved` already covers repos the tables miss. | Low | flag |
| 15 | `SKILL.source.md:238-239` | `spec/ directory with Gemfile containing rspec`; `*.test.js … \| (infer from config)` | G2 drift | The script only checks `Gemfile::rspec` and has no `(infer from config)` row. | Low | flag |
| 16 | `references/examples.md:17,60` | `scan_timeout_per_issue: 30` listed under "Defaults" | 1c example over-indexing | Step 2 derives three values, but the example implies a fourth. The value itself is right. | Low | flag |

## Proposed diff

Each hunk covers one finding. Hunk 1 changes what the build bundles, so rebuild and run the suite after taking it. `naming-conventions.md` will then be cited only from the *Additional Resources* index, which may make the build print a `⚠` warning. No test pins any of the phrases changed below.

```diff
# Finding 1: generated config points at bundle-only paths
--- a/src/skills/init-idd/templates/idd-template.yml
+++ b/src/skills/init-idd/templates/idd-template.yml
@@ -5,3 +5,4 @@
 # Platform for issue management
-# Values: "github" (only implemented driver — see docs/platform-github.md)
+# Values: "github" (the only implemented driver). Driver reference:
+# https://github.com/luongnv89/idd/blob/main/docs/platform-github.md
 platform: github
@@ -51,3 +52,4 @@
   # Set a custom string (e.g., "issue-") to override type-based naming
-  # See docs/naming-conventions.md for the full branch/commit/PR grammar
+  # Full branch/commit/PR grammar:
+  # https://github.com/luongnv89/idd/blob/main/docs/naming-conventions.md
   branch_prefix: "auto"
@@ -185,3 +187,4 @@
 # GitHub Projects board sync settings
-# See docs/github-projects-sync.md for the full integration reference
+# Full integration reference:
+# https://github.com/luongnv89/idd/blob/main/docs/github-projects-sync.md
 projects:
--- a/src/skills/init-idd/SKILL.source.md
+++ b/src/skills/init-idd/SKILL.source.md
@@ -71,5 +71,4 @@
 - `references/docs/config-schema.md` — full configuration schema
-- `references/docs/naming-conventions.md` — naming conventions (referenced by generated config)
+- `references/docs/naming-conventions.md` — naming conventions
 - `references/docs/idd-methodology.md` — IDD methodology reference
-- `references/docs/github-projects-sync.md` — GitHub Projects status sync reference
 - `references/docs/platform-github.md` — GitHub platform driver reference
@@ -482 +481 @@
-- **`docs/naming-conventions.md`** — Branch, commit, PR, and issue naming conventions (referenced by generated config)
+- **`docs/naming-conventions.md`** — Branch, commit, PR, and issue naming conventions
```

```diff
# Finding 2: "does not read one" contradicts the threshold read and merge
--- a/src/skills/init-idd/SKILL.source.md
+++ b/src/skills/init-idd/SKILL.source.md
@@ -102 +102 @@
-This skill GENERATES the config — it does not read one. Check if `.idd.yml` already exists in the repo root before proceeding. **Capture the run clock in that same check:** …
+This skill writes the config rather than loading it at start; it reads an existing file only for the context threshold below and the merge path. Check if `.idd.yml` already exists in the repo root before proceeding. **Capture the run clock in that same check:** …
```

```diff
# Finding 3: "minimal" config contradicts Step 3
--- a/src/skills/init-idd/SKILL.source.md
+++ b/src/skills/init-idd/SKILL.source.md
@@ -475,3 +475,3 @@
-- **Unrecognized language** — falls back to a minimal generic config with inline comments guiding manual edits.
+- **Unrecognized language** — writes the full template with generic defaults; the Language row prints its `⚠ warn` variant.
 - **Not a git repository** — prints the exact error from `references/error-messages.md` and stops; no file is written.
-- **Empty repo (no source files)** — writes a minimal default config; the Language and Test runner rows print their `⚠ warn` variants.
+- **Empty repo (no source files)** — writes the full template with the small-repo defaults; the Language and Test runner rows print their `⚠ warn` variants.
```

```diff
# Finding 4: fallback framework table must match the script's precedence
--- a/src/skills/init-idd/SKILL.source.md
+++ b/src/skills/init-idd/SKILL.source.md
@@ -199,9 +199,12 @@
-Parse dependency files to identify frameworks:
+Parse dependency files to identify frameworks. Test the rows in order and take
+the first match: `next` and `nuxt` come before `react` and `vue` because every
+Next.js or Nuxt project also depends on those.
 
 | Dependency name | Framework |
 |-----------------|-----------|
-| `react`, `react-dom` | React |
 | `next` | Next.js |
-| `vue` | Vue.js |
 | `nuxt` | Nuxt.js |
 | `angular`, `@angular/core` | Angular |
+| `react`, `react-dom` | React |
+| `vue` | Vue.js |
 | `express` | Express |
```

```diff
# Finding 5: language tie-break and size boundary must match the script
--- a/src/skills/init-idd/SKILL.source.md
+++ b/src/skills/init-idd/SKILL.source.md
@@ -183 +183 @@
-Check for these files in the repo root (or nearby):
+Check for these files anywhere in the repository:
@@ -195 +195 @@
-If several language markers exist, use the one at the repo root. If several are at the root, use the language with the most source files. If none is detected, use empty state.
+If several language markers exist, use the shallowest one; at equal depth, the row that comes first in this table. If none is detected, use empty state.
@@ -253,3 +253,3 @@
 | < 100 | small |
-| 100 - 1000 | medium |
-| > 1000 | large |
+| 100 – 999 | medium |
+| 1000 or more | large |
```

```diff
# Finding 6: token-budget claim predates the script
--- a/src/skills/init-idd/SKILL.source.md
+++ b/src/skills/init-idd/SKILL.source.md
@@ -24,3 +24,1 @@
 
-**Context and token budget:** this skill stays small — it reads only a handful of files (`package.json`, `requirements.txt`, etc.) to keep the main agent's context window compact.
-
 ## Instructions
```

```diff
# Finding 7: one plain statement instead of four
--- a/src/skills/init-idd/SKILL.source.md
+++ b/src/skills/init-idd/SKILL.source.md
@@ -108 +108 @@
-When the file is missing (and no legacy `.gitissue.yml` stands in for it — *Legacy names*), **always create it** without prompting. This happens regardless of context — even when the skill is invoked non-interactively from another skill. No early exit, no conditions, no cancel option.
+When the file is missing (and no legacy `.gitissue.yml` stands in for it — *Legacy names*), create it without prompting, including when another skill invokes this one non-interactively.
```

```diff
# Finding 8: describe merge_partial without version history
--- a/src/skills/init-idd/templates/idd-template.yml
+++ b/src/skills/init-idd/templates/idd-template.yml
@@ -135,4 +135,4 @@
   # Allow merging PRs that still have unresolved fixable review issues.
-  # Default: false — never merge a partial PR. Only honored when mode is
-  # "aggressive"; that combined opt-in reaches the prior 2.1.x "merge anyway
-  # with follow-up" path.
+  # Default: false — never merge a partial PR. Honored only when mode is
+  # "aggressive": the PR is then merged and its unresolved issues get a
+  # follow-up issue.
   merge_partial: false
```

```diff
# Finding 9: drop maintainer note from the runtime bundle
--- a/src/skills/init-idd/SKILL.source.md
+++ b/src/skills/init-idd/SKILL.source.md
@@ -484 +484 @@
-- **`docs/terminal-style.md`** — Terminal output style contract (bundled at build time; the repo-root `DESIGN.md` is the human-facing companion and is not bundled)
+- **`docs/terminal-style.md`** — Terminal output style contract
```

```diff
# Finding 10: state the footer rule, not the argument for it
--- a/src/skills/init-idd/references/error-messages.md
+++ b/src/skills/init-idd/references/error-messages.md
@@ -5 +5 @@
-**A block here that stops the run is followed by the run-stats footer** — see `references/run-stats.md`. A stop is a terminal outcome like any other, and printing the error block and exiting without the footer is the gap that contract exists to close. A stop that happens before the run clock was captured prints `elapsed n/a`, which is the contract working, not a hole in it. A `⚠` block that warns and continues is not a terminal outcome and prints no footer of its own.
+**A block here that stops the run is followed by the run-stats footer** (`references/run-stats.md`). A stop before the run clock was captured prints `elapsed n/a`. A `⚠` block that warns and continues is not a terminal outcome and prints no footer of its own.
```

```diff
# Finding 11: one error block for an unwritable repo root
--- a/src/skills/init-idd/references/error-messages.md
+++ b/src/skills/init-idd/references/error-messages.md
@@ -87 +87 @@
-**Trigger:** File write to `.idd.yml` fails (permission denied, disk full, read-only filesystem).
+**Trigger:** File write to `.idd.yml` fails (permission denied, disk full, read-only filesystem, or a repo root that does not allow file creation).
@@ -100,10 +100,0 @@
-### Directory not writable
-```
-✗ Repository root is not writable
-
-  To fix:  check permissions: ls -la .
-  Check:   is this a read-only mount?
-  Docs:    https://github.com/luongnv89/idd/blob/main/docs/config-schema.md
-```
-**Trigger:** The repo root directory does not allow file creation.
-
```

```diff
# Finding 12: drop the rubric answer from the format rule
--- a/src/skills/init-idd/references/review-contract.md
+++ b/src/skills/init-idd/references/review-contract.md
@@ -75,5 +75,2 @@
-The default format is the static terminal block in SKILL.md *Step 4 — Report*:
-one config file and about ten rows, inspectable at once. An interactive report
-does not apply — there is nothing to filter, and project convention forbids
-terminal animation; the written `.idd.yml` is the inspectable artifact. If
-the user asks for another format (for example a Markdown table or a diff against
+The default format is the static terminal block in SKILL.md *Step 4 — Report*.
+If the user asks for another format (for example a Markdown table or a diff against
```

No files were edited. All of the above is proposed only. Findings 1–6, 9 and 11 come from checking claims against the repo, so they're for you to confirm rather than apply wholesale. To check them after applying: `bash scripts/build.sh --out <tmp> --quiet`, then `git ls-files 'tests/*.sh' | xargs -n1 bash`. That rebuild matters most for finding 1, because it changes what gets bundled and what the precheck list must contain.
