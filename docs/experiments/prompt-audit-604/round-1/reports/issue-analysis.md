I audited `src/skills/issue-analysis` and found 8 problems worth fixing plus 8 smaller items noted only. The biggest problem: the skill gives the model three different shapes for the final report. Below is the full report and a proposed diff. Nothing has been applied, and I haven't run the build or the tests.

**Assumptions**
- **Scope:** `SKILL.source.md` and its five reference files (`subagent-steps.md`, `inline-fallback.md`, `output-and-persist.md`, `error-messages.md`, `examples.md`). Left out: `docs/README.md` (human-only, never loaded), `LICENSE`, and files that load with the skill but live elsewhere (`src/shared/agents/*`, `src/shared/references/*`, the bundled `docs/*.md`).
- **Target model:** Claude Opus 5.5, the model running this audit. The skill sets `effort: high` but names no model.
- **No other AI provider** appears in these files, and there is no code that builds API requests.

## Summary

1. **Three different report shapes.** `output-and-persist.md:25-28` says to default to "a concise summary and a static table comparing the 2–3 options". Step 8, `SKILL.source.md:43` and `examples.md` (refreshed today in #640) all show the full sections, with options as separate blocks. The *Expected Output* block (`SKILL.source.md:380-399`, from April) shows a third shape that nothing else defines, with lowercase `Risk: medium`.
2. **Instructions on how many options to propose disagree.** The inline fallback says to "cover a spectrum… one larger structural change" (`inline-fallback.md:291`, August). The newer check in `output-and-persist.md:41-42` (October) says one justified option is valid and not to "invent alternatives merely to fill the usual 2–3 slots".
3. **A result label drifted between two copies.** `subagent-steps.md:32` says `DONE (verify already resolved)`; the Final Report example says `DONE (verify if already resolved)`.

Counts by group:
- **Group 1 (dated prompt text):** 4, made up of two cases of emphasis or "be thorough" boosting (1a), one case of strategy coaching (1c, overlapping with the options finding above) and one case of "compared to an older version" phrasing (1d).
- **Group 2 (brittle skill files):** 5, all places where the skill contradicts itself or two copies have drifted.
- **Group 3 (tool descriptions):** not applicable. The frontmatter `description` is trigger text, and I didn't flag it.
- **Group 4 (request config):** not applicable, since there is no request code. The two shared agents it spawns (researcher, synthesizer) do different jobs, so neither is redundant.

## Findings

| # | Location | Evidence | Pattern | Why it's a problem | Conf. | Action |
|---|---|---|---|---|---|---|
| 1 | `references/output-and-persist.md:25-28` | "Default to a concise summary and a static table comparing the 2–3 options… These bounded comparisons do not need an interactive report." | G2: files contradict each other | Conflicts with Step 8 "Display the full analysis" (`:64`), `SKILL.source.md:43` and `examples.md`. Blame orders them: d564faa (2026-10-05) is older than the examples refresh 19b5b2e (2026-11-17). "Interactive report" names something this skill never produces. | High | rewrite |
| 2 | `SKILL.source.md:380-399` | "prints the 8-step tracker and a condensed report… `Risk: medium (touches auth middleware)`" | G2: duplicated info drifted; 1c: example over-indexing | A third report shape that conflicts with the Final Report block (`:335-352`) and `examples.md`. Lowercase `medium` breaks `Low\|Medium\|High`, and its `[5/8]` counts differ from the examples. From 8ddf344 (April). Examples shape output more strongly than prose does. | High | rewrite |
| 3 | `SKILL.source.md:324` | "These add two JSON keys… nothing else changes." | 1d: "compared to a past version" phrasing | Describes a change against a version the runtime reader never saw. `CLAUDE.md` *Writing skill text* names exactly this phrasing. | High | rewrite |
| 4 | `SKILL.source.md:365` | `DONE (verify if already resolved)` | G2: duplicated info drifted | `subagent-steps.md:32` (a13a6b8, July) says `DONE (verify already resolved)`. The `:365` line is older (8e15f28, March). | High | rewrite |
| 5 | `references/inline-fallback.md:291` | "should cover a spectrum: typically one minimal/tactical fix, one moderate refactor, and one larger structural change" | 1c: strategy coaching; G2: conflict | Pushes the model to invent options, which the newer check in `output-and-persist.md:41-42` forbids. | High | rewrite |
| 6 | `references/inline-fallback.md:44` | "This is the most thorough codebase scan in IDD Stack — more comprehensive than issue-resolver's Research step." | 1a: "be thorough" booster | Current models are already thorough, and the scan is bounded by `max_files`, `trace_depth` and `scan_timeout`. It also compares against a step the reader doesn't have. | Medium | remove |
| 7 | `SKILL.source.md:281` | "Unlike issue-resolver, analysis does NOT stop on closed issues" | 1a: capitalised emphasis | Shouted contrast with another skill. The warning text just above already says "Analyzing anyway". | Medium | rewrite |
| 8 | `references/error-messages.md:105` | "finds the file but JSON parsing fails" | G2: duplicated info drifted | The rule (`SKILL.source.md:34-35`) also stops on a file that fails *Validate analysis data*. Per `CLAUDE.md`, an error-catalog entry should copy its rule exactly or point to it. | Medium | rewrite |
| 9 | `references/output-and-persist.md:450`, `:555-559` | `reproduction`: "no skill populates this field" | G2: field nothing writes | Five schema rows describe a field the skill must never write (`tests/test-issue-analysis.sh:154`). It's a contract with another skill, so whether to cut it is your call. | Low | flag |
| 10 | `SKILL.source.md:287-293` | Keyword table for issue type ("update" → improvement) | 1b: lookup table for a judgment call | The labels part is deterministic and useful; the title-keyword part is a judgment the model already makes well. | Low | flag |
| 11 | `SKILL.source.md:27,214,308-311`, `output-and-persist.md:3` | "the persist step" vs "Step 8-9", "Step 9 persists" | G2: one step, two names | The `[N/8]` counter has no Step 9. Renaming headings may break tests that pin them. | Low | flag |
| 12 | `references/subagent-steps.md:40` | "It performs keyword extraction…" | 1d: text added piece by piece | The paragraph sits after the complexity-mapping paragraph, so "It" no longer clearly means the explorer. | Low | flag |
| 13 | `SKILL.source.md:256` | The `gi-gh.py` sentence | 1d: text added piece by piece | Splits "With no usable supplied record, run:" from its command. | Low | flag |
| 14 | `inline-fallback.md:271` vs `subagent-steps.md:85` | `✓ architecture mapped` / `✓ current impl analyzed` | G2: duplicated info drifted | The two paths print different `[6/8]` lines. | Low | flag |
| 15 | `references/output-and-persist.md:276-281` | Building `decision_record` from `options[]` | G4: model doing deterministic work | A purely mechanical lift that fits a `gi-*.py` helper better than prose. | Low | flag |
| 16 | `src/shared/agents/synthesizer.md:13,18` (out of scope) | "2–3 ranked options" | G2: conflict | Same conflict as #5, on the delegated path. Needs its own edit. | Low | flag |

**Kept on purpose:**
- The caller payload gate, the prompt-injection boundary and the stash-first sync script. These are fragile or security-relevant steps where exact text is right.
- The repeated "`commit_sha`, never `sha`", `issue.updatedAt` and "never guess the clock" rules. They are emphatic, but the copies agree and they guard a failure the resolver would otherwise hit silently (`output-and-persist.md:287`).
- The `.gitissue.yml` fallback. That compatibility path still runs.
- The "Read … now" pointers to reference files.

## Proposed diff

Every hunk edits `src/`, never the built `skills/`. Taken together the diff makes the bundle about 1 KB smaller. That matters because #640 left the skill only 31 B under its size limit. One finding per hunk:

```diff
--- a/src/skills/issue-analysis/references/output-and-persist.md
+++ b/src/skills/issue-analysis/references/output-and-persist.md
@@ -22,12 +22,9 @@
    such as reviewing the recommended option or rerunning an incomplete scan.
    Do not request implementation approval merely to finish this analysis.
 
-Default to a concise summary and a static table comparing the 2–3 options; keep
-the detailed sections below when useful or requested. A small diagram may explain
-architecture relationships when the output supports it; otherwise use text.
-These bounded comparisons do not need an interactive report. Honor a requested
-format while retaining result, evidence, uncertainty, and decision. Print `Saved:`
-only after the new file was verified; a retained old cache is not a successful save.
+Render the Step 8 sections below in order. Honor a requested format while
+retaining result, evidence, uncertainty, and decision. Print `Saved:` only after
+the new file was verified; a retained old cache is not a successful save.
 
 ## Validate analysis data
```

```diff
--- a/src/skills/issue-analysis/SKILL.source.md
+++ b/src/skills/issue-analysis/SKILL.source.md
@@ -377,27 +377,7 @@
 ## Expected Output
 
-A successful analysis prints the 8-step tracker and a condensed report, then persists the full result to `.idd/analysis-<N>.json`:
-
-```
-  ◆ Analysis Pipeline
-  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
-  [1/8] Fetch          ✓ issue #42 loaded (bug)
-  [2/8] Extract        ✓ 8 keywords, 2 file refs
-  [3/8] Research       ✓ read 18 files, traced 12 deps
-  [4/8] History        ✓ 5 related commits, 1 prior fix attempt
-  [5/8] Cross-refs     ✓ 2 related issues, 1 may resolve this
-  [6/8] Analysis       ✓ root cause identified
-  [7/8] Options        ✓ 3 approaches proposed
-  [8/8] Report         ✓ analysis complete
-
-  Root cause:      {short summary}
-  Affected files:  {count} files, {count} modules
-  Complexity:      M (estimated)
-  Risk:            medium (touches auth middleware)
-  Recommendation:  {one-sentence next step}
-```
-
-View mode renders the same report from the JSON without re-running the pipeline.
+A successful analysis prints the `[N/8]` tracker, the Step 8 report, the save line and the *Final Report*; `references/examples.md` shows a full run. View mode renders the same report from the JSON without re-running the pipeline.
 
 ## Edge Cases
```

```diff
--- a/src/skills/issue-analysis/SKILL.source.md
+++ b/src/skills/issue-analysis/SKILL.source.md
@@ -323,3 +323,3 @@
 
-These add two JSON keys and a *Decision Record* section to the terminal report; nothing else changes. Exact schema and rendering: `references/output-and-persist.md`.
+Exact schema and rendering, including the report's *Decision Record* section: `references/output-and-persist.md`.
 
```

```diff
--- a/src/skills/issue-analysis/SKILL.source.md
+++ b/src/skills/issue-analysis/SKILL.source.md
@@ -364,3 +364,3 @@
   ...
-  Result:            DONE (verify if already resolved)
+  Result:            DONE (verify already resolved)
 ```
```

```diff
--- a/src/skills/issue-analysis/references/inline-fallback.md
+++ b/src/skills/issue-analysis/references/inline-fallback.md
@@ -290,3 +290,3 @@
 
-The approaches should cover a spectrum: typically one minimal/tactical fix, one moderate refactor, and one larger structural change (when applicable). For simple issues, 2 options may suffice.
+Make each approach genuinely distinct. One justified option is valid; never invent alternatives to fill the 2–3 slots.
 
```

```diff
--- a/src/skills/issue-analysis/references/inline-fallback.md
+++ b/src/skills/issue-analysis/references/inline-fallback.md
@@ -42,6 +42,4 @@
 ### Step 3 — Research (Deep Codebase Scan)
 
-This is the most thorough codebase scan in IDD Stack — more comprehensive than issue-resolver's Research step.
-
 ### Phase 3a — Broad search
```

```diff
--- a/src/skills/issue-analysis/SKILL.source.md
+++ b/src/skills/issue-analysis/SKILL.source.md
@@ -280,3 +280,3 @@
 ```
-Unlike issue-resolver, analysis does NOT stop on closed issues — reviewing what was done is a valid use case. Print the warning and continue.
+Print the warning and continue: reviewing what was done is a valid use of analysis.
 
```

```diff
--- a/src/skills/issue-analysis/references/error-messages.md
+++ b/src/skills/issue-analysis/references/error-messages.md
@@ -104,3 +104,3 @@
 ```
-**Trigger:** `/issue-analysis N view` finds the file but JSON parsing fails.
+**Trigger:** `/issue-analysis N view` finds the file but it does not parse or fails *Validate analysis data* (`references/output-and-persist.md`).
 
```

**Before you take hunks:**
- I grepped `tests/`, `scripts/`, auto-pilot and issue-resolver for every phrase these hunks remove, and nothing depends on them. Neither `examples.md` nor any other file uses the exact string `DONE (verify if already resolved)`.
- The two hunks on the *Expected Output* section and the concise-summary default each pick a winner between two conflicting passages. I went by `git blame` dates, so check that those dates match what you intend.
- After applying, rebuild with `bash scripts/build.sh --out <tmp-dir> --quiet`, then run `git ls-files 'tests/*.sh' | xargs -n1 bash` and `python3 scripts/skill-budget.py --check`.
