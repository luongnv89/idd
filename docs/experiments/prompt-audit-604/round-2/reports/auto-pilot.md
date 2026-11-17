# Prompt audit, second pass: `src/skills/auto-pilot`

I found 24 findings that need a rewrite or a removal: 7 at high confidence and 17 at medium. The diff below is only proposed; I haven't edited any files.

**Assumptions**
- **Scope:** every authored file under `src/skills/auto-pilot/` in its current state, including this branch's first-pass edits. I skipped `docs/README.md` (a human-only file the skill marks "do not read") and `LICENSE`. The built `skills/` copy is generated, so it's out of scope; rebuild it after taking any hunks.
- **Target model:** Claude Opus 5.5, the model running this audit. The skill pins `effort: max` in its metadata but no model.
- **Provider markers:** none. This is a set of Claude Code skill files, not an app that calls the API.

**The three findings that matter most**
1. **Two pointers to "SPEC §2" can't be followed.** `SPEC.md` is not shipped with the skill, so the agent can't open it. One of them also misstates what the spec requires: §2 only covers dependency markers, but the text cites it for all four merge gates.
2. **The review-exhausted rule hardcodes `critical` and `priority:critical`.** Further down, the same file uses the `autopilot.critical_labels` setting. A user who configures other labels gets the follow-up issue on one reading and the stop-and-ask pause on the other.
3. **Notes written for maintainers have built up in the phase files.** Examples: why a step is lettered 1.1a, which file "claims" what, a dry-run rule kept "so that it stays unreachable by design", and how to measure the body budget. The agent reads all of this on every run and may act on it. The project's own CLAUDE.md says this material belongs in `tests/`, `evals/` or `docs/DEVELOPMENT.md`.

**Findings per group**
- **Group 1, dated prompt text:** 8.
- **Group 2, brittle skill files:** 16.
- **Group 3, tool descriptions:** not applicable (there are none).
- **Group 4, request config:** not applicable. The sub-agent roster check found 0 redundant agents.

## Findings

High confidence first. Every action is `rewrite` or `remove`.

| # | Location | Evidence | Pattern | Why it's a problem | Conf | Action |
|---|---|---|---|---|---|---|
| 1 | `references/phases/phase-5-merge.md:136` | `(SPEC §2 MUST-ignore for cross-repo)` | G2 Volatile specifics (pointer doesn't resolve) | `SPEC.md` is at the repo root and isn't in the bundle. The rule it points to is in the bundled `docs/idd-methodology.md` (*Issue Dependencies*). | High | rewrite |
| 2 | `references/phases/phase-3-4-review.md:125` | `SPEC §2 requires these checks before **any** automated merge` | G2 Volatile specifics | The pointer doesn't resolve, and it's wrong: SPEC §2 only requires the dependency check, not the merge floor, CI or merge-identity gates. | High | remove |
| 3 | `references/phases/phase-3-4-review.md:75` | `(no `critical` or `priority:critical` label)` | G2 Volatile specifics | Hardcodes the default. Line 209 of the same file uses `autopilot.critical_labels`. | High | rewrite |
| 4 | `references/orchestration.md:55-56` | `the analyzer still runs once … The ordinary path remains one resolver` | G1d Migration-relative phrasing | Compares against a version from before parallel lanes that the agent never saw. CLAUDE.md forbids this. | High | rewrite |
| 5 | `references/orchestration.md:92-93` | `The existing singleton `current` remains the compatibility seam` | G1d Migration-relative phrasing | "Existing", "remains" and "compatibility seam" all imply an older design. | High | rewrite |
| 6 | `references/explicit-list-mode.md:371` | `the flow is identical to before:` | G1d Migration-relative phrasing | CLAUDE.md names "as before" as banned. "Before" could also mean an earlier skill version. | High | rewrite |
| 7 | `references/explicit-list-mode.md:3` | `extracted from SKILL.md to keep the main file focused` | G2 History narrative | `tests/test-issue-analysis.sh` T11 already fails this exact phrase in another skill. | High | rewrite |
| 8 | `phase-2-resolve.md:213`, `phase-0-lock-resume.md:86`, `phase-5-merge.md:256`, `run-log.md:143`, `phase-1-triage-pick.md:54-55`, `phase-5-merge.md:53-54` | `the existing result handling`, `the existing singleton review phase`, `the existing ⚠ No eligible…`, `…, unchanged` | G1d Migration-relative phrasing | Leftover comparatives the first pass missed. CLAUDE.md lists "unchanged". | Medium | rewrite (6 hunks) |
| 9 | `references/spawning.md:3` | `**CRITICAL — never set `subagent_type`:** … Do NOT pass` | G1a Pressure language | The rule is real and has its reason next to it, so plain wording carries it. Capitals make the model over-apply it. | Medium | rewrite |
| 10 | `references/spawning.md:18` | `**On Claude Code, spawn by path** (provisional).` | G2 Maintainer material | A status tag for maintainers. It hints at an alternative path the agent may go looking for. | Medium | rewrite |
| 11 | `references/prompts/resolver.md:35` (item 10) | `AUTONOMY: Make every decision yourself. … Never stop to ask the user anything.` | G1c Padding (repetition) | Repeats item 3 in the same prompt. Only the tie-breaker sentence adds anything new. | Medium | rewrite |
| 12 | `references/prompts/batch-resolver.md:79-80` | `(A batch of several issues is rarely trivial, so this is usually "full".)` | G1c Strategy coaching | Pushes the subagent toward a value it should report as observed. | Medium | remove |
| 13 | `references/examples.md:11-70` | The full-session example has no per-phase `√/×` + `Result:` reports, no `Resolver lanes:` line, no `○ CI verdict` / `○ Merge identity` lines, and a `{conservative \| balanced \| aggressive}` placeholder | G1c Stale few-shot | SKILL.md says "A phase is not complete until its `Result:` line is printed". The model copies examples more closely than prose, and this example shows none of those lines. | Medium | rewrite |
| 14 | `phase-1-triage-pick.md:18-21` | `which is what `references/configuration.md` claims. This check does **not** live in *Step 1.6* …` | G2 Maintainer material | Defends the design to a reviewer. It doesn't tell the agent what to do. | Medium | rewrite |
| 15 | `phase-1-triage-pick.md:30-35` | `(Lettered onto *Step 1.1* because it gates *Step 1.1* …` | G2 Maintainer material | A numbering note. Its test (T13.11) says it exists so "the next reader [doesn't renumber] it back", i.e. it's for maintainers. | Medium | rewrite |
| 16 | `phase-1-triage-pick.md:506-513` | `Call it that, never "live": …` | G2 Maintainer material | A vocabulary rule for authors. No printed line uses the word. | Medium | rewrite |
| 17 | `phase-1-triage-pick.md:224-233` | `still bulk-fetches no issue bodies … the per-iteration context saving survives intact` | G1d Migration-relative + G2 duplicate | Compares against the design before the cache existed, and repeats the body-size reasoning from lines 129-136. | Medium | rewrite |
| 18 | `phase-5-merge.md:584-585` | `Numbered in Phase 1 because it maintains Phase 1's payload; executed here because…` | G2 Maintainer material | `references/phases.md` lines 9-14 already explain where the step lives. | Medium | remove |
| 19 | `phase-5-merge.md:619-620` | `each of the other two carries a pointer back here, because this step sits at the far end of the file.` | G2 Maintainer material | Describes the file's layout for maintainers. The tests' comments already record this. | Medium | rewrite |
| 20 | `phase-5-merge.md:633-642` | `in practice this step is unreachable under it, and the rule is stated here so that it stays unreachable by design rather than by accident` | G2 Maintainer material | Talks about the design to its authors. The rule itself fits in one sentence. | Medium | rewrite |
| 21 | `phase-5-merge.md:691-700` | `Stating it in both places with two different timings is how the two steps drift apart; *Step 1.2* is the single home…` | G2 Maintainer material | A note about where rules live in the docs. The rewrite keeps every test-pinned phrase. | Medium | rewrite |
| 22 | `references/orchestration.md:99-105` | `## Measuring the body-snapshot budget … Measure body-returning reads by issue and by boundary/reason` | G2 Maintainer material (eval guidance) | Measurement guidance for maintainers. CLAUDE.md puts this in `evals/` or `docs/DEVELOPMENT.md`. | Medium | remove (relocate) |
| 23 | `references/summary-variants.md:33-40` | ``RATE LIMITED` covers **both** call sites … which is why it is its own value … each false of it.` | G2 Maintainer material | Argues why the value exists. Only the zero-count rule matters at run time. | Medium | rewrite |
| 24 | `references/phases.md:6-7` | `Read the phase file when implementing or debugging that phase.` | G2 Maintainer material | Written for someone implementing or debugging. At run time the rule is SKILL.md's "read the current phase's file". | Medium | rewrite |

## Proposed diff

One hunk per finding. Three of them break tests that pin the old wording; update those tests in the same commit, as CLAUDE.md requires:
- **#9** breaks `tests/test-agent-overrides-455.sh:209` (T5f) and `tests/test-spawn-by-path-611.sh:79` (T2.8). Change both pins to `**Never set \`subagent_type\`.**`.
- **#15** breaks `tests/test-autopilot-triage-cache-258.sh:1030` (T13.11). Drop that check. T13.12 and T13.13 still pass.

For all the other hunks I grepped `tests/` for the phrases being changed and found no pins. After applying, rebuild with `bash scripts/build.sh` and run `git ls-files 'tests/*.sh' | xargs -n1 bash`.

```diff
# 1 — references/phases/phase-5-merge.md:136
-For each line that matches `(?im)\b(?:depends\s+on|blocked\s+by)\b`, collect **local** issue numbers only (SPEC §2 MUST-ignore for cross-repo):
+For each line that matches `(?im)\b(?:depends\s+on|blocked\s+by)\b`, collect **local** issue numbers only — cross-repo references are ignored (`docs/idd-methodology.md`, *Issue Dependencies*):
```
```diff
# 2 — references/phases/phase-3-4-review.md:125
-…then run the shared **Step 5.1a — CI verdict gate** against the current PR head. SPEC §2 requires these checks before **any** automated merge, including partial merges. The CI gate may accept…
+…then run the shared **Step 5.1a — CI verdict gate** against the current PR head. The CI gate may accept…
```
```diff
# 3 — references/phases/phase-3-4-review.md:75
-For non-critical issues (no `critical` or `priority:critical` label), the auto-pilot always captures…
+For non-critical issues (no label in `autopilot.critical_labels`), the auto-pilot always captures…
```
```diff
# 4 — references/orchestration.md:55-56
-In explicit-list mode the analyzer still runs once before the loop. The ordinary
-path remains one resolver followed by one reviewer. The parallel path is bounded
+In explicit-list mode the analyzer runs once before the loop. The sequential
+path is one resolver followed by one reviewer. The parallel path is bounded
```
```diff
# 5 — references/orchestration.md:92-93
-  The existing singleton `current` remains the compatibility seam for the one
-  lane currently draining.
+  The singleton `current` holds the one lane currently draining.
```
```diff
# 6 — references/explicit-list-mode.md:371
-For non-batched issues, the flow is identical to before:
+A non-batched issue runs the single-issue Resolver:
```
```diff
# 7 — references/explicit-list-mode.md:3
-Detail of the explicit `--issues` mode, extracted from SKILL.md to keep the main file focused. Read this when the user passes `--issues`.
+Read this when the user passes `--issues`.
```
```diff
# 8a — references/phases/phase-2-resolve.md:213
-without a cleanup attempt. Only then apply the existing result handling below.
+without a cleanup attempt. Only then apply the result handling below.
# 8b — references/phases/phase-0-lock-resume.md:86
-| `review` / `fix` / `merge` | Copy that lane into `current` and re-enter the existing singleton review phase (a `merge` lane…
+| `review` / `fix` / `merge` | Copy that lane into `current` and re-enter the singleton review phase (a `merge` lane…
# 8c — references/phases/phase-5-merge.md:256
-…**only when no eligible issue remains** — through the existing `⚠ No eligible issues to pick` stop condition in Phase 1, never from the gate itself.
+…**only when no eligible issue remains** — through Phase 1's `⚠ No eligible issues to pick` stop condition, never from the gate itself.
# 8d — references/run-log.md:143
-started. One line per processed issue, unchanged.
+started. One line per processed issue.
# 8e — references/phases/phase-1-triage-pick.md:54-55
-| `stale` | the file exists and parses, but any one of those checks fails or cannot be run | run Step 1.1's full triage, unchanged |
-| `absent` | the file is missing, unparsable, or carries no `summary.suggested_order` | run Step 1.1's full triage, unchanged |
+| `stale` | the file exists and parses, but any one of those checks fails or cannot be run | run Step 1.1's full triage |
+| `absent` | the file is missing, unparsable, or carries no `summary.suggested_order` | run Step 1.1's full triage |
# 8f — references/phases/phase-5-merge.md:53-54
-| `stale` | the returned SHA differs from the live head | run the full wait below, unchanged |
-| `absent` | no `ci_status` field, … or `review.check_ci: false` | run the full wait below, unchanged |
+| `stale` | the returned SHA differs from the live head | run the full wait below as written |
+| `absent` | no `ci_status` field, … or `review.check_ci: false` | run the full wait below as written |
```
```diff
# 9 — references/spawning.md:3
-**CRITICAL — never set `subagent_type`:** Every subagent below is spawned with the **default general-purpose agent**. Do NOT pass a `subagent_type` parameter to the Agent tool. `issue-resolver`, …
+**Never set `subagent_type`.** Every subagent below is spawned with the default general-purpose agent, so pass no `subagent_type` parameter to the Agent tool. `issue-resolver`, …
```
```diff
# 10 — references/spawning.md:18
-**On Claude Code, spawn by path** (provisional).
+**On Claude Code, spawn by path.**
```
```diff
# 11 — references/prompts/resolver.md:35
-10. AUTONOMY: Make every decision yourself. If you encounter an ambiguous choice, pick the safer/simpler option. Never stop to ask the user anything.
+10. On an ambiguous choice, pick the safer, simpler option.
```
```diff
# 12 — references/prompts/batch-resolver.md:79-80
-  when resolve.adaptive_effort is false. (A batch of several issues is rarely
-  trivial, so this is usually "full".)
+  when resolve.adaptive_effort is false.
```
```diff
# 13 — references/examples.md (full-session example)
   Limit:              3
+  Resolver lanes:     1 (review/merge serialized)
   Review cycles:      3
-  Merge mode:         {conservative | balanced | aggressive}
+  Merge mode:         balanced
 …
 ● Picking next issue from triage order...
   Selected: #12 — Fix auth redirect loop
+○ Issue payload: captured from Phase 1 (#12) — passed to subagents
+  Phase 1 — Triage and Pick
+    √ Triage current   √ Issue picked   √ Dependencies clear
+    Result: PASS
 …
     Tests:   4 written, 12 passed
+  Phase 2 — Resolve
+    √ Resolver returned   √ PR created   √ Telemetry returned   √ Quarantine checked
+    Result: PASS
 …
     CI: all checks passed
+  Phase 3-4 — PR Review
+    √ Review ran   √ Fix cycles converged   √ CI green
+    Result: PASS

+○ CI verdict: trusted (passed @ 9f2c1ab) — head unchanged, checks green, no re-poll
+○ Merge identity: fresh (head 9f2c1ab, base main not ahead) — merging
 ✓ PR #45 merged — #12 closed
   https://github.com/owner/repo/pull/45
 ✓ Triage cache updated — #12 resolved, 7 remain
+  Phase 5 — Merge
+    √ Mergeable   √ Merged   √ Issue closed
+    Result: PASS
```
```diff
# 14 — references/phases/phase-1-triage-pick.md:18-21
-nothing), and on every non-merging iteration. `N: 1` therefore forces a full
-triage every iteration, which is what `references/configuration.md` claims.
-This check does **not** live in *Step 1.6* — that step runs only after a merge,
-so a trigger there cannot fire on a non-merging iteration.
+nothing), and on every non-merging iteration, so `N: 1` forces a full triage
+every iteration.
```
```diff
# 15 — references/phases/phase-1-triage-pick.md:30-35
-(Lettered onto *Step 1.1* because it gates *Step 1.1* — the gate, the scan and
-*Step 1.1b*'s live read are one triage cluster, evaluated in that order. Phase
-0's *Step 1.0* and *Step 1.0b* are a different thing entirely: they are the run
-state — the resume entry gate and the checkpoint procedure — and they own
-`.idd/run-state.json`, not `.idd/triage.json`. Nothing in this step
-reads or writes the run state.)
+Phase 0's *Step 1.0* and *Step 1.0b* are a different thing entirely: they own
+`.idd/run-state.json`, not `.idd/triage.json`. Nothing in this step reads or
+writes the run state.
```
```diff
# 16 — references/phases/phase-1-triage-pick.md:506-513
-**Post-pick eligibility re-check.** This record is as fresh as `gi-issue.py`'s
-TTL allows — a real read at pick time in practice, since this loop fetches each
-issue once per run, so the TTL has nothing of its own to serve back. Call it
-that, never "live": it is the same TTL-cached read the resolver's *Step 0i*
-already describes as possibly old before the caller ever held it. On that
-footing it is still the freshest answer this step has to criteria *Step 1.2*
-could otherwise take only from a list read moments earlier or from a cached
-triage row.
+**Post-pick eligibility re-check.** This record is as fresh as `gi-issue.py`'s
+TTL allows — in practice a real read at pick time, since this loop fetches each
+issue once per run — and it is the freshest answer this step has to *Step 1.2*'s
+criteria.
```
```diff
# 17 — references/phases/phase-1-triage-pick.md:224-233
-**Two scalar fields, and no `body`.** The orchestrator still bulk-fetches no
-issue bodies — this list cannot carry one — so the body budget is untouched:
-exactly one body per iteration in triage mode, fetched for the picked issue
-alone in *Step 1.2b*; explicit-list mode retains the same snapshot shape at
-validation and reuses it from the mode-neutral capture, so no body enters this
-context from the analyzer path either. A hundred `{number, assignees}` rows is a
-few kilobytes against the
-~150KB a hundred bodies would cost, so the per-iteration context saving survives
-intact. Nothing here is a triage: no graph is built, no order is computed, and
-`.idd/triage.json` is neither read nor written.
+**Two scalar fields, and no `body`** — the one body per iteration is fetched for
+the picked issue alone in *Step 1.2b* (*Step 1.1* gives the reason). Nothing here
+is a triage: no graph is built, no order is computed, and `.idd/triage.json` is
+neither read nor written.
```
```diff
# 18 — references/phases/phase-5-merge.md:584-585
-Numbered in Phase 1 because it maintains Phase 1's payload; executed here
-because a merge is what makes it necessary.
-
```
```diff
# 19 — references/phases/phase-5-merge.md:619-620
-reached through a human decision. Three sites, one rule; each of the other two
-carries a pointer back here, because this step sits at the far end of the file.
+reached through a human decision. Three sites, one rule.
```
```diff
# 20 — references/phases/phase-5-merge.md:633-642
-**Under `--dry-run`, compute the removal and print it, but write nothing.** This
-step is the one place in the triage-cache flow that persists anything, so it takes the same
-rule *Step 1.1*'s `--out` and every `gi-state.py` call take: a dry run mutates no
-file on disk. Apply the nine rules below in memory, print the `✓ Triage cache
-updated` line with the counts the update *would* have produced, and skip the
-write-back — never write `.idd/triage.json`. Nothing downstream is harmed:
-`--dry-run` stops at *Step 1.3* before any merge, so in practice this step is
-unreachable under it, and the rule is stated here so that it stays unreachable
-by design rather than by accident. *Step 1.1a*, the read side of this cache, is
-read-only and needs no such rule.
+**Under `--dry-run`, write nothing.** Apply the nine rules below in memory,
+print the `✓ Triage cache updated` line with the counts the update would have
+produced, and never write `.idd/triage.json`.
```
```diff
# 21 — references/phases/phase-5-merge.md:691-700
-**When a full re-triage runs instead.** The `autopilot.retriage_every` trigger
-does **not** live here — it is evaluated at the top of every iteration from the
-1-based `{i}` counter, so it fires on non-merging iterations too. This step's
-only remaining `retriage_required` write is the degrade path below.
-
-**A pick miss is not a trigger here.** *Step 1.2* owns it, and handles it
-**in the same iteration** — re-enter Step 1.1 once, re-run the pick. A pick miss
-cannot reach this step in any case, because this step runs only after a merge.
-Stating it in both places with two different timings is how the two steps drift
-apart; *Step 1.2* is the single home of that retry.
+**A pick miss is not a trigger here**, and neither is `autopilot.retriage_every`:
+both are evaluated in Phase 1, and *Step 1.2* retries a pick miss **in the same
+iteration**. This step's only `retriage_required` write is the degrade path
+below.
```
```diff
# 22 — references/orchestration.md:99-105 (move to docs/DEVELOPMENT.md or evals/ if it should be kept)
-## Measuring the body-snapshot budget
-
-SKILL.md → *Caller-supplied context* names the three freshness boundaries
-(resolution, mutation, review). Measure body-returning reads by issue and by
-boundary/reason, never by total `gh` calls: the resolver's non-body
-`state,comments,updatedAt` probe preserves its 0a stops and 0h freshness check
-and is not a body read.
```
```diff
# 23 — references/summary-variants.md:33-40
-`RATE LIMITED` covers **both** call sites of that block, which is why it is its
-own value rather than a reading of one of the other four. Mid-run the stop lands
-between units of work and the counts are whatever completed. At **Prerequisite
-8** nothing ever started, so the report is a `0/{max}` summary with every count
-at zero and no iteration rows — and `COMPLETED` (nothing was done), `PAUSED` (no
-decision is waiting), `LIMIT REACHED` (no iteration ran) and `BUDGET REACHED`
-(the wall clock had time left; it was the API budget that did not) are each false
-of it.
+`RATE LIMITED` covers both call sites of that block. Mid-run the counts are
+whatever completed; at **Prerequisite 8** the report is a `0/{max}` summary with
+every count at zero and no iteration rows.
```
```diff
# 24 — references/phases.md:6-7
-it is in — never the whole loop. Read the phase file when
-implementing or debugging that phase.
+it is in — never the whole loop. Read a phase's file when the loop reaches it.
```

## Flag-only notes

These are not in the diff.

- **Two files disagree about where `skipped_reason: quarantined` is recorded.** `references/summary-format.md:14-19` says it goes on the iteration that applied the label, and that later runs log an "ordinary label skip". `references/run-log.md:137-154` and `explicit-list-mode.md` say it belongs to the later run, and that explicit-list mode logs it as `quarantined`. Both passages come from the same commit (`7426e8c`), so git history can't say which is current. You need to decide which reading is right.
- **The tests deliberately pin maintainer rationale into the runtime text.** Examples: T13.33 for "no fifth bucket **on purpose**" in `phase-1-triage-pick.md:428-435`, and T10.25. That conflicts with CLAUDE.md's rule to keep maintainer material out of the bundle. I left those passages alone; whether rationale belongs in test comments instead is your call.
- **The reviewer prompt and Phase 3-4 restate `/issue-pr-review`'s pipeline.** That's `prompts/reviewer.md` items 3-3h and `phase-3-4-review.md:9-17`. The copies agree with the source today and are heavily test-pinned, but they leave out the source's `min(1, configured_cap)` cycle cap under `light`/`trusted`. Fixing that is a refactor, not a fix for a dated pattern.
- **`metadata.effort: max` on an orchestrator that delegates all the heavy work** might be oversized on Opus 5.5. Nothing has been measured, so no edit.
- **`phase-1-triage-pick.md` (698 lines) is still a stack of race-by-race patches.** Restructuring it is beyond a rewrite or removal pass.
