Last check done: SPEC.md §2.1 does cover the `Part of` / `Depends on` distinction, so I dropped a suspected wrong-section finding. The same section also turned up a real conflict with the skill. Writing the report now.

# Prompt audit: `src/skills/plan-to-issues`

**Assumptions**
- **Scope.** The 17 files under `src/skills/plan-to-issues/` that the agent reads at run time: `SKILL.source.md` and the 16 files in `references/`.
  - Skipped `LICENSE` and `docs/README.md`, which is human-only and marked DO NOT READ.
  - I read `SPEC.md` and `src/shared/scripts/gi-plan-map.py` only to check facts, not to audit them.
- **Target model: Claude Opus 5.5.** These are coding-agent configuration files, the request names no model, and the skill sets `effort: high` but no model. So I audited against the model running this audit.
- **No non-Anthropic provider markers** were found.
- **Inventory.** One skill made of one SKILL plus 16 reference files, one subagent prompt (`references/plan-parser.md`), shell snippets, and two shared scripts it calls. There are no tool definitions and no code that builds API requests.

## Summary

Little here is written for an older model. There is one `CRITICAL`, no "think step by step", no hedges and no scaffolds, and the many "never" lines nearly all give a reason. The real problems are files in the skill disagreeing with each other or with the code. The three that matter most:

1. **A supported plan format fails Phase 1.**
   - `SKILL.source.md:160-164` and `references/phase-contracts.md:45-49` require "every phase appears with its goal and milestone", and treat any mismatch as **FAIL**.
   - But `references/plan-parsing.md:149-151` says a `/tasks-generator` plan has no milestones (they are `null`), and `:54` makes phases from sprints with no goal.
   - The renderer agrees with `plan-parsing.md`: `gi-plan-map.py:168-175` accepts a `null` goal and milestone.
   - So a `tasks.md` plan, which the skill explicitly supports, fails a strict reading of the gate.
2. **The skill contradicts the spec it cites.**
   - SPEC §2.1 (`SPEC.md:92`) says an epic SHOULD list its children as a `- [ ] #12 — <title>` checklist.
   - This skill forbids checkboxes in the map and deletes `/issue-creator`'s `## Children` checklist (`SKILL.source.md:238-239`).
   - Yet it cites "IDD SPEC §2.1" as its authority three times, and never says it departs from it.
3. **The file path still assumes a codebase-modernizer plan.**
   - `references/input-resolution.md:13` says "No filename is special".
   - But the file-path epic is always titled `Epic: Modernize <project> — Pre + P0–P4`, built from "baseline verdict, test command of record" (`references/epic-identity.md:118-121`).
   - A `/tasks-generator` plan or a hand-written roadmap has neither of those.

**Findings per group**
- **Group 1 (dated prompt text):** 1, low.
- **Group 2 (brittle skill files):** 13, of which 9 come with a proposed edit and 4 are flags (3 conflicts with no recorded order, 1 conflict with a file outside the requested scope).
- **Group 3 (tool descriptions):** not applicable, there are none.
- **Group 4 (request config):** not applicable, except the subagent check, which has 1 flag.

Every conflicting passage I checked with `git blame` comes from the same commit (`3d03822`, when the skill moved into this repo). So history can't say which side of a conflict is current, and those conflicts are flagged rather than fixed. The diff stays proposed: the Group 2 rules say not to apply these edits without your confirmation.

## Findings

### High confidence

**1. The Phase 1 gate is stricter than the plan formats the skill supports.**
- **Where:** `SKILL.source.md:160-164`, `references/phase-contracts.md:45-49`
- **Text:** "every phase appears with its goal and milestone; … the critical path is recorded. Any mismatch is a **FAIL**"
- **Pattern:** Group 2, a fact the repository contradicts.
- **Why it's wrong:** `plan-parsing.md:149-151` allows a `null` milestone, `:54` allows phases with no goal, and `:151` only checks the critical path "when the plan states one". `gi-plan-map.py:168-175` accepts `null` for goal and milestone, and `epic-dashboard.md:111` leaves out an empty critical-path section.
- **Action:** rewrite (hunks 1a and 1b).

**2. The example preflight report shows the wrong file count.**
- **Where:** `references/preflight.md:396`
- **Text:** `Bundled files: √ pass (22/22)`
- **Pattern:** Group 2, an outdated number.
- **Why it's wrong:** the *Bundled dependency precheck* list (`SKILL.source.md:282-305`) now has 24 entries. `self-improve.md` was added in `6015d89`.
- **Action:** rewrite to `24/24`.

### Medium confidence

**3. The skill's own "Reference files" section repeats the precheck list and has fallen behind it.**
- **Where:** `SKILL.source.md:401-411`
- **Pattern:** Group 2, the same information in two places that now disagree.
- **Why it's wrong:** it leaves out `self-improve.md`, `gi-config.py` and all four `references/docs/` files. The precheck list at `:282-305` already describes every file.
- **Action:** remove the section.

**4. The preflight reference says to read it only after a check fails.**
- **Where:** `references/preflight.md:3-4`
- **Text:** "Read this when a check fails — or when you are unsure how to check one."
- **Pattern:** Group 2, a pointer that is wrong.
- **Why it's wrong:** `SKILL.source.md:137-138` sends the agent here for the commands. The G1–G6 probes and their pass/stop table exist only in this file, so Phase 0 can't run without reading it first.
- **Action:** rewrite.

**5. The parser subagent can't open the file it is told to follow.**
- **Where:** `references/plan-parser.md:3-5`, `:28`, `:45`, `:63-69`
- **Pattern:** Group 2, a pointer that doesn't work where it is read.
- **Why it's wrong:**
  - The subagent gets this file pasted into its prompt, then runs from the repository root. There, `references/plan-parsing.md`, the source of its procedure and its output format, does not exist.
  - Its self-check runs `"$PLAN"`, but nothing sets that variable; the input JSON names the plan `plan_path`.
- **Action:** rewrite to pass the rules file's absolute path in the input JSON.

**6. "IDD SPEC §2.1" points at a file that isn't in the installed skill.**
- **Where:** `references/epic-identity.md:5`, `references/issue-creator-bridge.md:42-43` and `:191`
- **Pattern:** Group 2, a pointer that doesn't work at run time.
- **Why it's wrong:** `SPEC.md` is at the repository root and is not bundled with the skill. `SKILL.source.md:398` already uses the full GitHub URL for the methodology doc.
- **Action:** rewrite to a linked `SPEC.md` URL. This only fixes the link; the disagreement with what §2.1 says is flag F1.

**7. A version number stands in for a reason.**
- **Where:** `references/epic-identity.md:98`
- **Text:** "or a pre-1.5.0 run"
- **Pattern:** Group 2, history in an instruction file (CLAUDE.md: "Describe current behaviour as the only behaviour").
- **Why it's wrong:** the skill is at version 2.4.1, and the agent has no way to tell which release made an epic. The adoption check already matches on the `epic` label or the title, not on version.
- **Action:** remove the phrase.

**8. The phase-contracts header describes the file's history.**
- **Where:** `references/phase-contracts.md:3`
- **Text:** "moved out of SKILL.md to keep it within the context budget"
- **Pattern:** Group 1d / Group 2: wording that compares against a version the agent never saw, plus a note meant for maintainers.
- **Action:** rewrite.

**9. The plan-map input example still includes a field the map doesn't use.**
- **Where:** `references/epic-dashboard.md:134`, `:144-146`
- **Text:** `"state": "closed"`, plus "retained … so an older render input still validates … Do not add a consumer for it."
- **Pattern:** Group 2 conflict combined with Group 1c, an example the model copies too closely.
- **Why it's wrong:**
  - The example shows the field, which may lead the agent to look up each issue's status. `sync-mode.md:31-32` says issue state "is deliberately not fetched".
  - "Do not add a consumer for it" is a note for maintainers (CLAUDE.md: keep maintainer material out of the bundle).
- **Action:** rewrite.

### Flags (no edit proposed)

**F1. The skill contradicts SPEC §2.1.**
- **Where:** `SKILL.source.md:229-239`, `references/epic-dashboard.md:43-44`, `references/issue-creator-bridge.md:148-151` versus `SPEC.md:92`
- **The conflict:** the spec says an epic SHOULD list its children as a checklist. The skill forbids checkboxes and removes `/issue-creator`'s list, giving a reason: GitHub doesn't tick a task-list box when the issue closes, so the box goes out of date.
- **Why it's a flag:** the fix may need an edit to `SPEC.md`, which is outside the requested scope.
- **Your decision:** either soften SPEC §2.1 to allow native sub-issues instead of a checklist, or have the skill state that it departs from the spec and why.

**F2. Two formats for the resume command.**
- **Where:** `references/phase-contracts.md:180-181`, `references/input-resolution.md:170-171` and `references/epic-identity.md:227-228` versus `references/reporting.md:55-56, 84-85` and `SKILL.source.md:257, 373`
- **The conflict:** the first three say "always print `Re-run this backlog with: …`" as its own line. The closing-summary template and the example put the same command in `Next action:`. An agent may print both or break the closing-summary format.
- **Why it's a flag:** all from the same commit, so there's no recorded order.
- **Your decision:** which form is the one rule. Probably `Next action:`, since that is what the template and example show.

**F3. When the dependency pass runs.**
- **Where:** `SKILL.source.md:219-220` and `references/phase-contracts.md:126-127` versus `references/issue-creator-bridge.md:181`
- **The conflict:** SKILL and phase-contracts say "After **every** phase". The bridge says "Run once, after every phase is filed".
- **Why it's a flag:** same commit, so there's no recorded order.
- **Your decision:** after each phase or once at the end. The completion probes work with either.

**F4. The file-path epic title only fits modernizer plans.**
- **Where:** `references/epic-identity.md:102, 118-122`, `references/issue-creator-bridge.md:20-40` versus `references/input-resolution.md:13-14` and `references/plan-parsing.md:9-12`
- **The conflict:** the hardcoded `Epic: Modernize <project> — Pre + P0–P4` title, and the adoption check that matches on it, don't fit `/tasks-generator` plans or hand-written ones.
- **Why it's a flag:** same commit, so there's no recorded order.
- **Your decision:** whether the title should come from the plan's `# <plan title>` line, as the conversation path already does with `Epic: <confirmed title>`.

**F5. Low: the one `CRITICAL:`.**
- **Where:** `SKILL.source.md:42`
- **Why it's only a flag:** it is the single emphasis marker in the skill, it sits on a safety rule that gives its reason, and nothing documents it as something the model gets wrong. Left alone.

**F6. Low: sync-mode's "Step 2 — identify the source" doesn't match its own step 2.**
- **Where:** `references/sync-mode.md:55`
- **The mismatch:** its numbered step 2 (`:23`) parses child issue numbers. Identifying the source happens when the epic is fetched in step 1.
- **Why it's only a flag:** I can't tell which step was meant.

**F7. Group 4: the parser subagent does a job a script could do.**
- **Where:** `references/plan-parser.md`
- **What I found:** it turns an anchored grammar into JSON with no judgement step: phase resolution, effort parsing and the severity lookup are all fixed rules. That is the "model call whose inputs fully determine its output" pattern. The repo's own rule is that determinism beats prose (`src/shared/scripts/`).
- **Suggestion:** a `gi-plan-parse.py` with a prose fallback would remove one model call per large plan.
- **Why it's only a flag:** the fix is new code, which is beyond a prompt-text diff.

## Proposed diff

These edits are proposed only, not applied. Edit `src/`, then rebuild with `bash scripts/build.sh --out <tmp-dir> --quiet`. No test pins any of the changed wording (I grepped `tests/` and `evals/`).

```diff
# Finding 1a: Phase 1 gate matches the supported plan shapes
--- a/src/skills/plan-to-issues/SKILL.source.md
+++ b/src/skills/plan-to-issues/SKILL.source.md
@@ -160,5 +160,6 @@
 *Completion criteria:* task count equals `grep -cE '^#{3,4} Task ' <plan>`; every task has an id,
-title, ≥ 1 acceptance criterion, a `Dependencies` value (`None` allowed), and an effort; every phase
-appears with its goal and milestone; the dependency table references only ids in the worklist; the
-critical path is recorded. Any mismatch is a **FAIL** — report the missing ids rather than filing a
-partial backlog silently.
+title, ≥ 1 acceptance criterion, a `Dependencies` value (`None` allowed), and an effort; every phase
+appears, with its goal and milestone where the plan states them and `null` where it does not; the
+dependency table references only ids in the worklist; the critical path is recorded when the plan
+states one. Any mismatch is a **FAIL** — report the missing ids rather than filing a partial
+backlog silently.

# Finding 1b: same rule, phase-contracts copy
--- a/src/skills/plan-to-issues/references/phase-contracts.md
+++ b/src/skills/plan-to-issues/references/phase-contracts.md
@@ -45,5 +45,6 @@
 *Completion criteria:* the task count equals `grep -cE '^#{3,4} Task ' <plan>`; every task has an
-id, title, ≥ 1 acceptance criterion, a `Dependencies` value (`None` allowed), and an effort; every
-phase appears with its goal and milestone; the dependency table references only ids in the worklist;
-the critical path is recorded. Any mismatch is a **FAIL** — report the missing ids rather than
-filing a partial backlog silently.
+id, title, ≥ 1 acceptance criterion, a `Dependencies` value (`None` allowed), and an effort; every
+phase appears, with its goal and milestone where the plan states them and `null` where it does not;
+the dependency table references only ids in the worklist; the critical path is recorded when the
+plan states one. Any mismatch is a **FAIL** — report the missing ids rather than filing a partial
+backlog silently.

# Finding 2: bundled-file count in the preflight example
--- a/src/skills/plan-to-issues/references/preflight.md
+++ b/src/skills/plan-to-issues/references/preflight.md
@@ -396 +396 @@
-  Bundled files:      √ pass (22/22)
+  Bundled files:      √ pass (24/24)

# Finding 3: drop the restated, drifted file list
--- a/src/skills/plan-to-issues/SKILL.source.md
+++ b/src/skills/plan-to-issues/SKILL.source.md
@@ -399,13 +399 @@
 `references/error-messages.md`.
-
-## Reference files
-
-`references/`: `glossary.md` (term definitions) · `input-resolution.md` (input kinds, resolution
-order, the draft-and-confirm gate, conversation-path epic identity) · `preflight.md` (dependency
-detection, failure blocks) · `security-boundary.md` (injection and shell-interpolation rules) ·
-`phase-contracts.md` (full prose for Phases 0–6) · `acceptance-criteria.md` (unabridged contract) ·
-`reporting.md` (report format, check names, review contract, closing summary) · `sync-mode.md` ·
-`edge-cases.md` · `plan-parsing.md` (grammar, worklist schema) · `plan-parser.md` (Phase 1 parser
-spawn prompt for a large plan) · `labels.md` · `issue-creator-bridge.md` · `epic-identity.md` ·
-`epic-dashboard.md` · `error-messages.md` · `run-stats.md`.
-`shared/scripts/gi-plan-map.py` renders the map (stdin JSON → markdown stdout).

# Finding 4: preflight.md is read in Phase 0, not only on failure
--- a/src/skills/plan-to-issues/references/preflight.md
+++ b/src/skills/plan-to-issues/references/preflight.md
@@ -3,2 +3,2 @@
 Everything Phase 0 needs: how to probe `gh` for real readiness, how to detect each dependency, and the exact block to print when one is
-missing. Read this when a check fails — or when you are unsure how to check one.
+missing. Read this at the start of Phase 0, and before sync mode's reduced preflight.

# Finding 5: give the parser subagent a resolvable rules path
--- a/src/skills/plan-to-issues/references/plan-parser.md
+++ b/src/skills/plan-to-issues/references/plan-parser.md
@@ -3,3 +3,5 @@
 Spawn prompt for the Phase 1 parser subagent (plans over 400 lines). Paste this file into the
-`Agent` prompt with the input JSON below filled in; use the default general-purpose agent — never
-set `subagent_type`. It is skill-local, not a shared agent: only `/plan-to-issues` spawns it.
+`Agent` prompt with the input JSON below filled in — `rules_path` is the absolute path of this
+skill's `references/plan-parsing.md`; use the default general-purpose agent — never set
+`subagent_type`. It is skill-local, not a shared agent: only `/plan-to-issues` spawns it.
@@ -11,9 +13,13 @@
 ## Input
 
 ```json
 {
   "plan_path": "/abs/path/to/repo/MODERNIZATION_PLAN.md",
   "report_path": "/abs/path/to/repo/MODERNIZATION_REPORT.md",
+  "rules_path": "/abs/path/to/plan-to-issues/references/plan-parsing.md",
   "phase_filter": ["P0", "P1"]
 }
 ```
+
+Read `rules_path` first. Every mention of `references/plan-parsing.md` below means that file.
@@ -63 +69 @@
-Run these and include the results in `parse_check`. Report a mismatch; do not round it off.
+Run these with `PLAN` set to `plan_path`, and include the results in `parse_check`. Report a
+mismatch; do not round it off.

# Finding 6: make the SPEC pointers resolve (link only; content conflict is flag F1)
--- a/src/skills/plan-to-issues/references/epic-identity.md
+++ b/src/skills/plan-to-issues/references/epic-identity.md
@@ -5 +5,2 @@
-An epic is an ordinary issue that parents the others (IDD SPEC §2.1) — not a new artifact type. Its
+An epic is an ordinary issue that parents the others
+([SPEC.md](https://github.com/luongnv89/idd/blob/main/SPEC.md) §2.1) — not a new artifact type. Its
--- a/src/skills/plan-to-issues/references/issue-creator-bridge.md
+++ b/src/skills/plan-to-issues/references/issue-creator-bridge.md
@@ -42,2 +42,3 @@
-The milestone exit conditions become the epic's acceptance criteria — whole-effort outcome, per IDD
-SPEC §2.1. Then `gh issue edit <epic> --add-label epic`.
+The milestone exit conditions become the epic's acceptance criteria — whole-effort outcome, per
+[SPEC.md](https://github.com/luongnv89/idd/blob/main/SPEC.md) §2.1. Then
+`gh issue edit <epic> --add-label epic`.
@@ -191 +192,2 @@
-says the child serves the epic's outcome, `Depends on` says it cannot merge first (IDD SPEC §2.1).
+says the child serves the epic's outcome, `Depends on` says it cannot merge first
+([SPEC.md](https://github.com/luongnv89/idd/blob/main/SPEC.md) §2.1).

# Finding 7: drop the version-number history
--- a/src/skills/plan-to-issues/references/epic-identity.md
+++ b/src/skills/plan-to-issues/references/epic-identity.md
@@ -98 +98 @@
-   step 2 and step 4, or a pre-1.5.0 run, leaves an epic with no marker. Skip any issue that
+   step 2 and step 4 leaves an epic with no marker. Skip any issue that

# Finding 8: phase-contracts header states what the file is, not where it came from
--- a/src/skills/plan-to-issues/references/phase-contracts.md
+++ b/src/skills/plan-to-issues/references/phase-contracts.md
@@ -3,2 +3,2 @@
-The full prose for Phases 0–6, moved out of SKILL.md to keep it within the context budget.
-SKILL.md carries the contract in condensed form and points here; nothing below is optional.
+The full prose for Phases 0–6. SKILL.md carries the contract in condensed form and points here;
+nothing below is optional.

# Finding 9: render-input example stops modelling the ignored state field
--- a/src/skills/plan-to-issues/references/epic-dashboard.md
+++ b/src/skills/plan-to-issues/references/epic-dashboard.md
@@ -133,2 +133,2 @@
         { "task_id": "Pre.1", "title": "Make the project environment agent-runnable",
-          "issue": 101, "state": "closed", "depends_on": [], "unknown_deps": [] }
+          "issue": 101, "depends_on": [], "unknown_deps": [] }
@@ -144,3 +144,2 @@
-`issue` is `null` for a task that was not filed. `state` is **accepted and ignored** — it is retained
-in the schema so an older render input still validates, but nothing reads it: the map encodes no
-status. Do not add a consumer for it.
+`issue` is `null` for a task that was not filed. Leave out `state`: the renderer accepts and ignores
+it because the map encodes no status, so fetching issue state for the render input wastes calls.
```

Nothing was changed on disk. To apply all of the hunks or some of them, say which; flags F1–F4 need your call before anyone edits.
