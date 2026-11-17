# Prompt audit: `src/skills/issue-triage`

**What I assumed**
- **Scope:** the files the agent reads when it runs the skill: `SKILL.source.md` and `references/{detection,output-and-persist,examples,error-messages}.md`. I skipped `docs/README.md` (it's for humans, marked do-not-read and never loaded) and `LICENSE`. I also opened the scanner agent and the `gi-backlog`, `gi-ready` and `gi-triage-graph` scripts, only to check what the skill says about them.
- **Target model:** Claude Opus 5.5, the model running this audit. The skill doesn't pin a model; its frontmatter only sets `metadata.effort: medium`.
- **How I checked:** `git blame` needed approval in this session, so I didn't run it. Where two passages disagree, I took the current fact from the scripts and from what the skill itself does, not from which line is newer.

## Summary

The skill is in good shape on wording. Its strong language is rare and each instance gives a reason (for example, never put an issue title on a command line because titles come from reporters and the skill runs unattended). It has no thinking scaffolds, no shouting and no hedged requirements. Every finding is a fact that has gone stale or two passages that disagree. The three that matter most:

1. **The skill disagrees with itself about who sets edge direction.** `detection.md` tells the main agent to turn scanner edges into directed `blocks`/`blocked_by` itself. But SKILL Steps 3-7 and `gi-triage-graph.py` say to pass undirected `a`/`b` pairs, and the script directs them. An agent that follows `detection.md` works out the direction by hand, which is exactly the "plausible answer from prose" the script exists to replace.
2. **The examples never print the step completion reports**, even though SKILL says "No step is complete until its `Result:` line prints." Examples shape output more strongly than prose, so runs will tend to leave the reports out.
3. **Several statements are wrong or point nowhere:**
   - `detection.md` is said to hold "subagent prompts", but it has none.
   - An error message says merged PRs are checked over "the last 3 months", but the fetch has no date window.
   - The "no cache" invocation row promises an update suggestion that can't fire right after a fresh analysis.
   - "An update ends on that same view" contradicts the update example.

**Counts by group**
- Group 1 (dated prompt text): 1
- Group 2 (brittle configuration): 7, plus 2 flagged
- Group 3 (tool descriptions): not applicable
- Group 4 (request config): not applicable. There's no request code, and the one-scanner subagent roster has no redundancy.

## Findings

| # | Location | Evidence | Pattern | Why it's a problem | Confidence | Action |
|---|---|---|---|---|---|---|
| 1 | `references/detection.md:19`, `:109`; `SKILL.source.md:225` | "Convert undirected scanner edges to **directed** `blocks` / `blocked_by`…"; "add a dependency edge. Determine directionality…"; "directed edges after merge" | G2 contradiction / volatile specifics | Contradicted by `SKILL.source.md:341-342` ("`edges` are the scanner's undirected pairs (`a`/`b`), which the script directs") and `gi-triage-graph.py:29-38`. The scanner also returns `issue_a`/`issue_b` (scanner `:51`), which nothing tells the agent to rename to `a`/`b`. | High | rewrite (proposed only) |
| 2 | `SKILL.source.md:316`; `references/detection.md:3` | "its subagent prompts, confidence-scoring rules and merge logic"; "read this for the subagent prompts" | G2 volatile specifics | `detection.md` holds no prompt. The prompt lives in `shared/agents/issue-relationship-scanner.md`, which `detection.md:11` itself points to. | High | rewrite |
| 3 | `references/error-messages.md:97` | "No merged PRs found in the last 3 months" | G2 volatile specifics | The merged-PR fetch is `gh pr list --state merged … --limit 50` with no date filter (`detection.md:41`, scanner `:35`). Only `git log` uses `--since="3 months ago"`. | High | rewrite |
| 4 | `SKILL.source.md:20` vs `:41` | "with no cache, run a full analysis and persist, then suggest an update if the repo changed" vs "Run the full pipeline from Prerequisites and stop after Step 9" | G2 contradiction (same file) | Right after a fresh analysis, Step 4's checks compare against the timestamp just written, so the suggestion can never fire. Line 41 is the behaviour that can actually happen. | Medium | rewrite |
| 5 | `SKILL.source.md:422` | "an update ends on that same view" | G2 contradiction | The update example (`examples.md:106-141`) and Step 8 render the full triage table, not the cached-view header. | Medium | rewrite |
| 6 | `references/examples.md:9-52` | First-run example has no `√ … Result: PASS` blocks | G1c example over-indexing | SKILL `:269-273` and `output-and-persist.md:258-303` require a completion report for each step. The model copies example shape over prose, and the project rule says to change the examples along with the contract. | Medium | add |
| 7 | `references/output-and-persist.md:261-262` | "Emit it right after the step's `[N/9]` tracker line" | G2 pointer that doesn't resolve | No step in the skill prints a `[N/9]` line, and `terminal-style.md` doesn't define one. Its only definition is the example just below. | Medium | rewrite |
| 8 | `SKILL.source.md:169` | "The prompt skip matches `/issue-analysis`;" | G2 history narrative / maintainer note | A comparison with another skill that the agent running this one can't see, and it gives no instruction. The rest of the sentence carries the rule. | Medium | remove clause |
| 9 | `references/output-and-persist.md:239`, `:244` | "(its `references/phases/phase-5-merge.md`)"; "This keeps the schema — no field is added, none is removed" | G2 pointer that doesn't resolve / migration-relative phrasing | The path belongs to `/auto-pilot`'s bundle, and "no field is added" compares against a version the reader never saw. But it's a deliberate contract with the other skill that writes this file, and `tests/test-autopilot-triage-cache-258.sh:287-293` pins the phrases. | Low | flag |
| 10 | `SKILL.source.md:363` vs `gi-triage-graph.py:59-61` | exit 4 → "continue to Step 8" vs script: "degrade to the prose procedure" | G2 contradiction | SKILL's handling is the sensible one, because the payload is still on stdout. The script's docstring is the stale side, and it's outside the requested scope. | Low | flag |

## Proposed diff

Edit `src/`, then rebuild with `bash scripts/build.sh --out <tmp> --quiet`. None of these hunks breaks a phrase pinned in `tests/test-issue-triage.sh`. I haven't run the test suite.

```diff
# F1 — edge direction belongs to the script
--- a/src/skills/issue-triage/references/detection.md
+++ b/src/skills/issue-triage/references/detection.md
@@ -19 +19 @@
-3. Convert undirected scanner edges to **directed** `blocks` / `blocked_by` using creation date (`createdAt`), blocking count, and type precedence (bug before feature/improvement) — same heuristics as the inline Step 2 procedure.
+3. Keep the scanner's edges undirected: write each `issue_a`/`issue_b` pair as `{"a": …, "b": …}` in the triage scan. Steps 3-7 direct them — `gi-triage-graph.py`, or the inline Step 2 heuristics when that script degraded.
@@ -109 +109 @@
-3. Run a cross-batch pass: for any two issues from different batches, check if their `affected_files` overlap. If they do, add a dependency edge. Determine directionality using the same heuristics as the inline procedure: earlier creation date takes precedence, more blocking relationships take precedence, and bug type takes precedence over feature/improvement. If neither issue clearly precedes the other, mark them as co-dependent at the same level. This is a lightweight comparison the main agent does on the merged data.
+3. Run a cross-batch pass: for any two issues from different batches, check if their `affected_files` overlap. If they do, add an undirected `{"a": …, "b": …}` edge; Steps 3-7 direct it. This is a lightweight comparison the main agent does on the merged data.
--- a/src/skills/issue-triage/SKILL.source.md
+++ b/src/skills/issue-triage/SKILL.source.md
@@ -225 +225 @@
-… (full `body` per issue, `scope: "both"`, directed edges after merge). …
+… (full `body` per issue, `scope: "both"`, undirected `a`/`b` edges after merge). …
```

```diff
# F2 — detection.md holds no subagent prompt
--- a/src/skills/issue-triage/SKILL.source.md
+++ b/src/skills/issue-triage/SKILL.source.md
@@ -316 +316 @@
-… **Read `references/detection.md` now** — its subagent prompts, confidence-scoring rules and merge logic are what these steps execute, not optional tuning detail. …
+… **Read `references/detection.md` now** — its spawn rules, confidence-scoring rules and merge logic are what these steps execute, not optional tuning detail. …
--- a/src/skills/issue-triage/references/detection.md
+++ b/src/skills/issue-triage/references/detection.md
@@ -3 +3 @@
-Full spec for Step 1b (already-fixed detection via commit/PR history) and Step 2 (dependency analysis via file-overlap). SKILL.md keeps a summary; read this for the subagent prompts and confidence-scoring rules.
+Full spec for Step 1b (already-fixed detection via commit/PR history) and Step 2 (dependency analysis via file-overlap). SKILL.md keeps a summary; read this for the spawn and merge rules and confidence scoring.
```

```diff
# F3 — the merged-PR fetch has no date window
--- a/src/skills/issue-triage/references/error-messages.md
+++ b/src/skills/issue-triage/references/error-messages.md
@@ -97 +97 @@
-○ No merged PRs found in the last 3 months — skipping already-fixed detection.
+○ No merged PRs found — skipping already-fixed detection.
```

```diff
# F4 — no update suggestion after a first analysis
--- a/src/skills/issue-triage/SKILL.source.md
+++ b/src/skills/issue-triage/SKILL.source.md
@@ -20 +20 @@
-| `/issue-triage` | Show cached triage from `.idd/triage.json`; with no cache, run a full analysis and persist, then suggest an update if the repo changed. |
+| `/issue-triage` | Show cached triage from `.idd/triage.json` and suggest an update if the repo changed; with no cache, run a full analysis and persist. |
```

```diff
# F5 — an update ends on the Step 8 report, not the cached view
--- a/src/skills/issue-triage/SKILL.source.md
+++ b/src/skills/issue-triage/SKILL.source.md
@@ -422 +422 @@
-A cached view renders *Default Mode → 3* and the lines from *4. Detect changes and suggest update*; an update ends on that same view. Both close with the *Final Report* block under the *Review contract*.
+A cached view renders *Default Mode → 3* and the lines from *4. Detect changes and suggest update*; an update renders the Step 8 table, summary lines and any already-fixed block. Both close with the *Final Report* block under the *Review contract*.
```

```diff
# F6 — show the step completion reports in the first-run example
--- a/src/skills/issue-triage/references/examples.md
+++ b/src/skills/issue-triage/references/examples.md
@@ -12,3 +12,15 @@
   ● Fetching 4 open issues...
+  [1/9] Fetch       ✓ 4 open issues
+    √ Issues fetched   √ Config applied
+    Result: PASS
   ● Scanning commit history for already-fixed issues...
   ● Scanning codebase for issue dependencies...
+  [1b-2/9] Scan     ✓ 1 batch returned
+    √ Scanner returned   √ Dependencies mapped
+    Result: PASS
+  [3-7/9] Ordering  ✓ 4 issues ordered, 1 stale
+    √ Order computed   √ No cycle left unreported
+    √ Disjoint sets identified   √ Threshold applied
+    √ Every open issue scored   √ Every issue ranked
+    Result: PASS
@@ -29 +41,4 @@
   ✓ Triage saved to .idd/triage.json
+  [8-9/9] Output    ✓ report rendered, cache saved
+    √ Report rendered   √ .idd/triage.json written
+    Result: PASS
```

```diff
# F7 — define the tracker line where it is used
--- a/src/skills/issue-triage/references/output-and-persist.md
+++ b/src/skills/issue-triage/references/output-and-persist.md
@@ -260,3 +260,3 @@
 Every step ends with a completion report — the checkable bar that separates *the
-step ran* from *the step succeeded*. Emit it right after the step's `[N/9]`
-tracker line:
+step ran* from *the step succeeded*. Print it when the step finishes, headed by a
+`[N/9]` tracker line naming the step and its headline result:
```

```diff
# F8 — drop the cross-skill comparison
--- a/src/skills/issue-triage/SKILL.source.md
+++ b/src/skills/issue-triage/SKILL.source.md
@@ -169 +169 @@
-The prompt skip matches `/issue-analysis`; failure handling is exactly as above — only a failed stash pop stops an unattended run.
+Failure handling is exactly as above — only a failed stash pop stops an unattended run.
```

Findings 1, 2, 3 and 7 fix facts that the scripts and the bundle contradict, so please confirm those hunks before you take them rather than applying them as a batch. I haven't edited any files.

**Two flagged items for you to decide:**
- **Finding 9:** if you take it, rewrite the cross-skill section and update `tests/test-autopilot-triage-cache-258.sh` in the same commit.
- **Finding 10:** the fix belongs in `gi-triage-graph.py`'s docstring, which is outside this audit's scope.
