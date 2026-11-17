# Prompt audit: `src/skills/issue-triage` (second pass)

**What I assumed.**
- **Scope:** the five runtime files in `src/skills/issue-triage/`: `SKILL.source.md` and the four files under `references/`. I audited the working tree as it stands, including the uncommitted first-pass edits. `LICENSE` and `docs/README.md` are not prompt text, so I left them out.
- **Target model:** Claude Opus 5.5, the model running this audit. The skill names no model; `metadata.effort: medium` is not a model choice. No other AI provider is involved.
- **History:** the `git log -S` lookups needed approval and did not run. Every finding below rests on a contradiction I can show in the repository, not on when a line was written.

**Summary.** The most important findings are places where the prose that `detection.md` calls "the authoritative statement of the script's rules" no longer matches `gi-triage-graph.py`:
- The P3 priority rules give a different answer from the script.
- One rule says to sort within each priority level, which the script never does.
- The circular-dependency example shows a cycle the script cannot produce from file overlap alone.

On the degrade path, where `python3` is missing or the script fails, a hand-run would follow this prose and produce a different order than the script does.

**Counts:** Group 1 (dated prompt text): 1 · Group 2 (stale facts and conflicts between files): 7 · Group 3 (tool descriptions): not applicable · Group 4 (request code): not applicable.

## Findings (high and medium confidence, rewrite only)

| # | Location | Evidence | Pattern | Why it's wrong | Conf. |
|---|---|---|---|---|---|
| 1 | `references/detection.md:209-211` | P3: "Features and improvements that do not block other issues" · "Stale issues with no dependencies (may be obsolete)" | G2 stale fact | `assign_priority` (`gi-triage-graph.py:609-639`) gives a stale bug that blocks nothing **P2**, and its docstring says it resolves this contradiction on purpose. It also gives P3 to an improvement that blocks exactly one issue and to an untyped issue; the prose covers neither. | High |
| 2 | `references/detection.md:213` | "Within each priority level, sort by: number of issues blocked (descending), then age (oldest first)." | G2 stale fact | Priority never reorders anything. The order is the topological levels sorted by type, then age, then number (`topological_levels`, line 545), and the table follows that order (`output-and-persist.md:91`). | High |
| 3 | `references/examples.md:179-188` | "2 open issues whose keyword scans overlap" → "Circular dependency detected: #5 → #9 → #5" | G2 stale fact + G1c example | `direct_edges` turns each undirected overlap pair into **one** directed edge, or into a `co_dependent` pair. Two issues linked only by file overlap can never form a cycle. A cycle needs an opposing `from`/`to` edge, which comes from a `Depends on` marker. | High |
| 4 | `references/output-and-persist.md:184-191` | `"summary": {… "circular_deps": []}` | G2 stale fact | The script emits `summary.co_dependent` (line 763), and both `SKILL.md:352` and this file's own field table (line 229) list it. The example is what a hand-written degrade payload will copy, so the field gets dropped. | High |
| 5 | `SKILL.source.md:318` | "flags open issues whose titles/bodies match recent commit messages or merged PR descriptions" | G2 conflict | The scanner contract (`issue-relationship-scanner.md:36`) and `detection.md:65` require a commit or PR-body reference **by issue number**, aimed at a PR that targets a different issue. Text matching is the thing they rule out. | High |
| 6 | `SKILL.source.md:319` | "computes pairwise overlap into a `dependencies[]` graph" | G2 stale fact | No `dependencies[]` exists anywhere in `src/` or `docs/`. The scanner returns `dependency_edges`, and the scan file uses `edges`. | High |
| 7 | `references/output-and-persist.md:239-242` | "deletes the merged issue's number from `issues[]`, … `summary.parallel_groups`, … `blocked_by` / `blocks` — plus the one derived consequence…" | G2 restated list fell behind its source | `/auto-pilot`'s Step 1.6 (`phase-5-merge.md:647-674`) does more: it also discards `circular_deps` chains, prunes `co_dependent` pairs, clears `potentially_fixed_by`, recounts the three summary counts and moves `updated` forward. The cited path does not exist in this skill's bundle. | Medium |
| 8 | `references/examples.md:3`, examples at 120-155 and 175-205 | The update and circular examples print no `[N/9]` / `Result:` lines and don't mark them as left out | G1c example over-indexing | `SKILL.md:273` says "No step is complete until its `Result:` line prints". The model copies an example's shape more strongly than the prose, and two of three full runs show the reports missing. | Medium |

## Proposed diff

None of this is applied. Each hunk is one finding.

```diff
--- a/src/skills/issue-triage/references/detection.md   (#1)
@@ -209,5 +209,5 @@
 **P3 (Low)**:
-- Features and improvements that do not block other issues
-- Stale issues with no dependencies (may be obsolete)
+- Everything no rule above places: features that block nothing, improvements
+  that block fewer than two issues, and issues with no type. Staleness alone
+  never changes a priority.
--- a/src/skills/issue-triage/references/detection.md   (#2)
@@ -213 +213 @@
-Within each priority level, sort by: number of issues blocked (descending), then age (oldest first).
+Priority never changes the execution order from Step 4; the table stays in that order.
--- a/src/skills/issue-triage/references/examples.md   (#3)
@@ -179,3 +179,5 @@
-**2 open issues whose keyword scans overlap:**
-- #5 "Fix login flow" (bug; login auth session)
-- #9 "Refactor session management" (improvement; session auth refactor)
+**2 open issues whose keyword scans overlap (the overlap edge runs from the older
+#5 to #9), while #5's body says `Depends on #9`:**
+- #5 "Fix login flow" (bug, older)
+- #9 "Refactor session management" (improvement)
--- a/src/skills/issue-triage/references/output-and-persist.md   (#4)
@@ -190,2 +190,3 @@
     "suggested_order": [12, 8, 15, 3],
-    "circular_deps": []
+    "circular_deps": [],
+    "co_dependent": []
   },
--- a/src/skills/issue-triage/SKILL.source.md   (#5)
@@ -318 +318 @@
-- **Step 1b** — flags open issues whose titles/bodies match recent commit messages or merged PR descriptions, marking them `potentially_fixed` with evidence links.
+- **Step 1b** — flags an open issue that a commit or merged-PR body names by number while that PR targeted a different issue, marking it `potentially_fixed` with evidence links.
--- a/src/skills/issue-triage/SKILL.source.md   (#6)
@@ -319 +319 @@
-… and computes pairwise overlap into a `dependencies[]` graph. Affected files come from that scan, never the body.
+… and returns pairwise file overlap as undirected `dependency_edges`. Affected files come from that scan, never the body.
--- a/src/skills/issue-triage/references/output-and-persist.md   (#7)
@@ -239,4 +239,4 @@
-**Cross-skill incremental updates.** One other skill writes this file: `/auto-pilot`, in its *Step 1.6 — Update the triage cache after a merge* (its `references/phases/phase-5-merge.md`), which triages once per run and then keeps the payload current in place rather than re-triaging every iteration. That writer is bound by two invariants, and they are what let a second skill touch a file this one owns:
+**Cross-skill incremental updates.** One other skill writes this file: `/auto-pilot`, in its *Step 1.6 — Update the triage cache after a merge*, which triages once per run and then keeps the payload current in place rather than re-triaging every iteration. That step holds the full rule list; two invariants bound it, and they are what let a second skill touch a file this one owns:
 
-1. **Removal only, never a recomputation.** It deletes the merged issue's number from `issues[]`, from `summary.suggested_order`, from `summary.parallel_groups`, and from every remaining issue's `blocked_by` / `blocks` — plus the one derived consequence, flipping an issue whose `blocked_by` just emptied from `blocked` to `ready`. It never re-derives an order, …
+1. **Removal only, never a recomputation.** It removes the merged issue's number wherever the payload carries it, recounts the summary counts from the records that remain, and flips an issue whose `blocked_by` just emptied from `blocked` to `ready`. It never re-derives an order, …
-2. **Exactly one appended `history[]` entry per update**, with `source: "/auto-pilot"`. So …
+2. **Exactly one appended `history[]` entry per update**, with `source: "/auto-pilot"`, and the top-level `updated` moves to that entry's time. So …
--- a/src/skills/issue-triage/references/examples.md   (#8)
@@ -3 +3,3 @@
-One full run per mode.
+One full run per mode. After the first run, examples leave out the `[N/9]` step
+completion reports for brevity; every real run prints them.
```

**Checks for hunk 7:** it keeps all four phrases that `tests/test-autopilot-triage-cache-258.sh` pins (T3.12–T3.15). No test pins the wording changed by hunks 1–6 or 8. After applying any hunk, rebuild `skills/` with `bash scripts/build.sh`.

## Notes I'm not proposing an edit for

- **Empty-backlog result:** the `Review contract` requires a *Final Report* at every early stop, but no `Result` value fits "no open issues" (`DONE` needs a written cache). The empty-repository example shows only the footer. You need to choose the value.
- **Closed issues:** `triage.include_closed` merges closed issues into the scan, but the schema says closed issues are never written into `issues[]`. You need to decide which is right.
- **`potentially_fixed_by` keys:** nothing maps the scanner's keys (`fixed_by_pr`, `branch_name`, `commit_sha`, `confidence_reason`) to the schema's keys (`pr`, `branch`, `commit`). A cached view also cannot show the confidence reason. Fixing this means adding text, which is outside this pass.
- **Cycle message:** "These issues share affected files…" in `detection.md:156` and `error-messages.md:81` misdescribes a cycle that includes a marker edge.
- **"Updated by":** after an `/auto-pilot` incremental write, the cached view's "Updated by" still reads the top-level `source` (`/issue-triage`).
- **`brew install gh`** in `error-messages.md:22` is a macOS-only fix command.
