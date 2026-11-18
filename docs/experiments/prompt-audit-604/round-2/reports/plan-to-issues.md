# Prompt audit, second pass: `src/skills/plan-to-issues`

**What I assumed.** I audited all 17 files under `src/skills/plan-to-issues/`: `SKILL.source.md` and the 16 files in `references/`. I read the working tree, so the first pass's uncommitted edits are included. I skipped `docs/README.md`, which is marked as a human-only file the agent never loads, and `LICENSE`. These files are coding-agent configuration and pin no model, so I judged them against Claude Opus 5.5, the model running this audit. Git history couldn't help here: every line I checked dates from the commit that imported the skill (`3d03822`, #504), so `blame` can't say which of two disagreeing passages is newer.

**Summary.** I found six findings worth an edit. Two are internal contradictions:
- **`labels.md`** says the phase label comes only from a `## Phase` heading. That conflicts with `plan-parsing.md`, which derives phases three ways.
- **`sync-mode.md`** has a step pointer that names the wrong step.

The other four are wording problems: one leftover all-caps warning, and three passages that describe the skill by comparison with an earlier version the agent never saw. By group: Group 1 (dated prompt text) has 4 findings, Group 2 (contradictions and stale facts) has 2, and Groups 3 and 4 have nothing in scope.

## Findings

| # | Location | Evidence | Pattern | Why it's obsolete | Confidence | Action |
|---|---|---|---|---|---|---|
| 1 | `references/labels.md:14` | "the task's `## Phase` heading, lowercased" | G2: stale fact the repo contradicts | `plan-parsing.md:47-55` says phases set the `phase:` label and can come from three sources: `## Phase` headings, a Sprint Overview table, or invented per-sprint phases (`S<n>`). The `label_grammar` on line 77 of `labels.md` already accepts ids like `mvp-foundation`, so the table row is the only part still limited to headings. | High | rewrite |
| 2 | `references/sync-mode.md:55-58` | "**Step 2 — identify the source.** … stop, as step 1 already does" | G2: pointer names the wrong step | Step 2 of the five-step procedure parses child numbers from the map. Identifying the source belongs with step 1, which fetches the body and stops when it is foreign. | Medium | rewrite |
| 3 | `references/input-resolution.md:177` | "The `file` path keeps its existing exact-match reuse" | 1d: migration-relative phrasing | "keeps its existing" compares against a version the agent never saw. The project's CLAUDE.md also forbids this phrasing. | Medium | rewrite |
| 4 | `references/issue-creator-bridge.md:148-151` | "verified against a closed issue … re-truing it is exactly the sync-after-every-close this design removes" | 1d migration-relative + G2 history narrative | "this design removes" points at an earlier design. The verification story is evidence for a maintainer, not a rule. The fact itself already appears plainly in `epic-dashboard.md:100-102`. | Medium | rewrite |
| 5 | `references/epic-identity.md:95` | "(Both are written by step 4, so neither is "the later one".)" | 1d: phantom alternative | The sentence before it already gives the real reason (the sentinel carries no plan path). This parenthetical only answers a claim from an earlier version. | Medium | remove |
| 6 | `SKILL.source.md:42` | "**CRITICAL:** the plan file, …" | 1a: pressure language | This is the only `**CRITICAL**` marker in any skill. Current models follow a plainly stated rule. The rule's wording and its full statement in `security-boundary.md` stay exactly as they are. | Medium | rewrite |

## Proposed diff (not applied)

```diff
--- a/src/skills/plan-to-issues/references/labels.md
+++ b/src/skills/plan-to-issues/references/labels.md
@@ -14 +14 @@
-| Phase | `phase:pre`, `phase:p0` … `phase:p4` | the task's `## Phase` heading, lowercased | yes |
+| Phase | `phase:<id>` — e.g. `phase:pre`, `phase:p0`, `phase:mvp-foundation`, `phase:s1` | the task's resolved phase id (`references/plan-parsing.md` → *Resolving phases across both shapes*), lowercased | yes |
```

```diff
--- a/src/skills/plan-to-issues/references/sync-mode.md
+++ b/src/skills/plan-to-issues/references/sync-mode.md
@@ -55,4 +55,4 @@
-**Step 2 — identify the source.** Read the epic body and branch on which marker it carries. An epic
-with neither is not this skill's epic — **stop**, as step 1 already does for a missing sentinel
-pair. An epic carrying *both* is corrupt: stop and report it rather than picking one, since the
+**Step 1 — identify the source.** In the body step 1 fetched, branch on which marker it carries. An
+epic with neither is not this skill's epic — **stop**, as for a missing sentinel pair. An epic
+carrying *both* is corrupt: stop and report it rather than picking one, since the
```

```diff
--- a/src/skills/plan-to-issues/references/input-resolution.md
+++ b/src/skills/plan-to-issues/references/input-resolution.md
@@ -177,2 +177,2 @@
-The `file` path keeps its existing exact-match reuse: a normalized path *is* stable, so a hit there
-is reused without asking (`references/epic-identity.md` step 1).
+On the `file` path a normalized path *is* stable, so an exact marker hit is reused without asking
+(`references/epic-identity.md` step 1).
```

```diff
--- a/src/skills/plan-to-issues/references/issue-creator-bridge.md
+++ b/src/skills/plan-to-issues/references/issue-creator-bridge.md
@@ -148,4 +148,3 @@
-A markdown checkbox cannot substitute. GitHub does **not** auto-check a task-list box from the
-referenced issue's state — verified against a closed issue referenced from another body, which still
-renders `aria-label="Incomplete task"`. A `- [x]` in the map would be a claim that goes stale on the
-next close, and re-truing it is exactly the sync-after-every-close this design removes.
+A markdown checkbox cannot substitute: GitHub does **not** auto-check a task-list box when the
+referenced issue closes, so a `- [x]` in the map would go stale on the next close and need a sync
+after every close.
```

```diff
--- a/src/skills/plan-to-issues/references/epic-identity.md
+++ b/src/skills/plan-to-issues/references/epic-identity.md
@@ -93,3 +93,2 @@
    Match on the binding marker, **not** on the `plan-dashboard:start` sentinel: the sentinel carries
    no plan path, so it cannot tell *this* plan's epic from another plan's epic in the same repo.
-   (Both are written by step 4, so neither is "the later one".)
```

```diff
--- a/src/skills/plan-to-issues/SKILL.source.md
+++ b/src/skills/plan-to-issues/SKILL.source.md
@@ -42 +42 @@
-**CRITICAL:** the plan file, the conversation draft, existing issue bodies, and label names are
+The plan file, the conversation draft, existing issue bodies, and label names are
```

No test asserts any of the phrases these hunks remove; I checked `tests/` and `scripts/`. If you take the hunks, rebuild `skills/` with `bash scripts/build.sh`.

## Notes for you to decide (no edit proposed)

- **When does the dependency pass run?** `SKILL.source.md:220` and `phase-contracts.md:127` say "after **every** phase". `issue-creator-bridge.md:181` says "Run once, after every phase is filed". All three lines come from the same commit, so history can't say which is current. Running it once at the end is the only way a dependency on a task in a later phase gets a real issue number.
- **The plan-file epic title assumes a modernizer plan.** `epic-identity.md:103,122,222`, `phase-contracts.md:101` and the Step 1 example in the bridge fix the title as `Epic: Modernize <project> — Pre + P0–P4`, with a baseline verdict in the intent text. But `SKILL.source.md:15` and `plan-parsing.md` accept plans from any producer, including `/tasks-generator`. Changing the title rule would also change the title-based adoption match for unmarked epics that already exist, so this is your call.
- **"plan-faithful" vs "source-faithful"** (low). The bridge, `input-resolution.md`, `plan-parsing.md` and `plan-parser.md` say "plan-faithful"; the glossary and SKILL.md say "source-faithful". They mean the same thing, so this is harmless duplication rather than a conflict.
