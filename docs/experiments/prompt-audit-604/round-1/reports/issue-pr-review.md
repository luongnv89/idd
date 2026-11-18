I audited `src/skills/issue-pr-review` and found 7 things worth changing. All of them are pointers that no longer lead anywhere or notes meant for a maintainer that ended up in the runtime bundle. None are dated prompting habits for an older model. I haven't edited any files; the proposed diff is below.

**What I assumed:**
- **Scope:** `SKILL.source.md` and the 8 files in `references/`. I left out `docs/README.md` (human-only, never loaded) and `LICENSE`. The shared agents and runtime docs the skill cites live outside this directory and weren't audited.
- **Target model:** Claude Opus 5.5, the model running this audit. The skill sets `effort: high` but pins no model.

**Main findings:**
- **A dead pointer next to the secret-scan gate** (`prepass-tests-ci-mechanics.md:158-159`). It says "Only after the scan passes (or warnings are accepted — see the scan contract in SKILL.md)". SKILL.md has no scan contract and no rule about accepting warnings; its only pass rule is the four-part condition. The aside reads like a second, looser way past a safety gate.
- **A script the skill doesn't use** (`review-loop-mechanics.md:57`). It says the head-ref rule is "already applied at the `gi-secscan` and `gi-branch` call sites", but `gi-branch.py` is neither bundled with nor called by this skill.
- **Maintainer notes the runtime agent reads on every run.** Examples: "No label edit exists in this skill today; a future one must add an intent row here", and "`/auto-pilot`'s Step 5.1a … the two must not diverge". Your CLAUDE.md says this kind of text belongs outside the bundle.

**Counts by group:** Group 1 (dated prompt text): 2 to change, 2 low-confidence notes. Group 2 (skill and config files): 5 to change, 3 notes only. Group 3 (tool descriptions): 0. Group 4 (request config): not applicable, since there is no code that builds API requests.

## Findings

| # | Location | Quoted text | Pattern | Why it's a problem | Confidence | Action |
|---|---|---|---|---|---|---|
| 1 | `references/prepass-tests-ci-mechanics.md:158-159` | "Only after the scan passes (or warnings are accepted — see the scan contract in SKILL.md)" | Group 2: facts that went stale; a safety rule should be stated in one place | SKILL.md has no "scan contract" or warning rule; the only pass rule is the four-part condition (`SKILL.source.md:218`). The pointer has been there since `1ad8566`. | High | rewrite |
| 2 | `references/review-loop-mechanics.md:57-59` | "the same rule already applied at the `gi-secscan` and `gi-branch` call sites" | Group 2: facts that went stale | `gi-branch.py` isn't in the precheck list (`SKILL.source.md:73-84`) and nothing here calls it. Added in `4f52767`. | High | rewrite |
| 3 | `references/progress-record-mechanics.md:141-142` | "**No label edit exists in this skill today; a future one must add an intent row here.**" | Group 2: history and maintainer notes | It's a note to whoever edits the skill next, and it uses "today", which CLAUDE.md rules out. | High | remove (move it to `docs/DEVELOPMENT.md` if you want to keep it) |
| 4 | `references/review-loop-mechanics.md:458-462` | "Keep this recompute: it is still required when CI is runnable." | Group 1d: wording that compares against an earlier version | It argues with someone deciding whether to delete the step. The runtime agent needs only the effect. | Medium | rewrite |
| 5 | `references/prepass-tests-ci-mechanics.md:293-295` | "`/auto-pilot`'s Step 5.1a is held to the same rule … and the two must not diverge." | Group 2: maintainer material in the bundle | It tells someone to keep two skills in sync. A run reviewing a PR can't act on it. | Medium | remove |
| 6 | `references/review-loop-mechanics.md:143-175`, `references/error-messages.md:89-103` | "The paragraphs above are written for the default configuration … decided here rather than left as an unstated consequence", then a three-bullet defence, restated in the error entry | Group 1c: padding; a safety rule should be stated once | The rule and its reasons fit in one paragraph. The rest talks about the document itself, and the error entry restates the argument instead of pointing to it. | Medium | rewrite (keeps every phrase `tests/test-followup-context-285.sh` checks for) |
| 7 | `references/verification-checks.md:126` | "(SPEC §4.3)" | Group 2: pointer that doesn't resolve | `SPEC.md` is at the repo root and isn't bundled, so the runtime agent can't open it, and the sentence already gives its own reason. | Medium | remove |
| 8 | `references/review-loop-mechanics.md:261-262, 413` | "converts a token optimization into a bypass. Do not make it." / "none may be added" | Group 2: maintainer material | Addressed to someone editing the skill, but these are safety prohibitions, so the audit rules say flag them rather than remove them. | Medium | flag: you decide whether to move them to `docs/DEVELOPMENT.md` |
| 9 | `references/review-loop-mechanics.md:177-207` | "the ambiguity costs a reader a moment, not a false-passing gate" | Group 2: restated list plus maintainer commentary | The mapping of `{N}` per file is useful at run time, but it restates every file's convention and will drift as those files change. | Low | flag |
| 10 | `SKILL.source.md:140` | "Tokens are saved by the zero-token pre-pass, reviewer/fixer reuse, and `fix`/`note` filtering." | Group 1c: padding | Commentary only; it changes nothing the agent does. | Low | flag |
| 11 | `references/error-messages.md:5` | "which is the contract working, not a hole in it" | Group 1c: defensive phrasing | Written to answer a reviewer, not to instruct the agent. | Low | flag |
| 12 | `review-loop-mechanics.md:130-135, 359`; `progress-record-mechanics.md:3`; `prepass-tests-ci-mechanics.md:278, 312, 326`; `report-templates.md:304, 404` | References to the resolver's Step 0d/0g/0j and auto-pilot's Step 5.1a/5.1c and Phase 5 | Group 2: pointers into other skills | They all exist in the repo but not in this skill's bundle. They mostly carry reasons, so they're harmless. | Low | flag |

**Checked and left alone:**
- The 8 bolded "**read it now**" lines are reading-order instructions, not inflated emphasis.
- The paragraph on what a `trusted` QA handoff skips appears three times (`SKILL.source.md:229`, `review-loop-mechanics.md:432-443` and `:527-537`). The three copies agree, so the audit rules say leave them.
- The long security reasoning (head-ref binding, policy ref, receipt trust model) and the exact bash procedures are context and fragile steps the agent needs.
- No pressure language, step-by-step thinking scaffolds, retired model names or "don't narrate" lines turned up.

## Proposed diff

Each hunk is one finding. Rows 1–7 are Group 2 or rewrite edits, so they're for you to confirm. After applying, rebuild `skills/` with `bash scripts/build.sh` and run the test suite; I haven't run either.

```diff
--- a/src/skills/issue-pr-review/references/prepass-tests-ci-mechanics.md   (#1)
+++ b/src/skills/issue-pr-review/references/prepass-tests-ci-mechanics.md
@@ -156,4 +156,4 @@
 malformed invocation), or **exit 4** degrades to the Primary Pattern in
-`docs/pre-commit-security.md`. Only after the scan passes (or warnings are
-accepted — see the scan contract in SKILL.md), commit and push:
+`docs/pre-commit-security.md`. Only after the scan passes — all four
+conditions above — commit and push:
```

```diff
--- a/src/skills/issue-pr-review/references/review-loop-mechanics.md   (#2)
+++ b/src/skills/issue-pr-review/references/review-loop-mechanics.md
@@ -57,3 +57,2 @@
-This is the same rule already applied at the `gi-secscan` and `gi-branch` call
-sites; the head-ref name is the one untrusted value this skill cannot hand
-straight to a script.
+The `gi-secscan` call sites bind `base` the same way; the head-ref name is the
+one untrusted value this skill cannot hand straight to a script.
```

```diff
--- a/src/skills/issue-pr-review/references/progress-record-mechanics.md   (#3)
+++ b/src/skills/issue-pr-review/references/progress-record-mechanics.md
@@ -140,6 +140,3 @@
 
-**No label edit exists in this skill today; a future one must add an intent row
-here.**
-
 ### What a record never does <!-- a:rvm-progress-never -->
```

```diff
--- a/src/skills/issue-pr-review/references/review-loop-mechanics.md   (#4)
+++ b/src/skills/issue-pr-review/references/review-loop-mechanics.md
@@ -457,6 +457,5 @@
   suite has run — Step 2's leg is skipped before the auto-fix is even
-  committed, Step 4's afterwards — leaving only Step 5's CI. Keep this
-  recompute: it is still required when CI is runnable. Independently, the
-  `tests=` skip is refused when `ci_leg_runnable` is false, so a missed
-  recompute on a no-CI / `review.check_ci: false` path cannot auto-merge on
-  zero test evidence.
+  committed, Step 4's afterwards — leaving only Step 5's CI. On a no-CI /
+  `review.check_ci: false` path the `tests=` skip is refused anyway
+  (`ci_leg_runnable` is false), so there a missed recompute cannot auto-merge
+  on zero test evidence.
```

```diff
--- a/src/skills/issue-pr-review/references/prepass-tests-ci-mechanics.md   (#5)
+++ b/src/skills/issue-pr-review/references/prepass-tests-ci-mechanics.md
@@ -292,5 +292,3 @@
 (Step 2's auto-fix commit as much as any fixer push), so the value held when the
-wait starts is this skill's current head. `/auto-pilot`'s Step 5.1a is held to
-the same rule — one widened read, no standalone `headRefOid` call — and the two
-must not diverge. The one case a reused value misses is a head moved by
+wait starts is this skill's current head. The one case a reused value misses is a head moved by
 something other than this skill; that costs the caller a stale SHA, which
```

```diff
--- a/src/skills/issue-pr-review/references/review-loop-mechanics.md   (#6a)
+++ b/src/skills/issue-pr-review/references/review-loop-mechanics.md
@@ -143,33 +143,10 @@
 **When `review.require_acceptance_criteria_check` is `false`, the stop still applies.** <!-- a:rvm-verification-flag-false -->
-The paragraphs above are written for the default configuration, and on the
-opt-out path their reasoning does not hold on its own terms — so this branch is
-decided here rather than left as an unstated consequence. With that flag
-… (lines 146-175, through "so it is not the thing that decides this branch.")
+The flag governs reporting, not reading: it turns off per-criterion verification
+(`○ acceptance_criteria: disabled`), not the review boundary's read of the linked
+issue. That read still feeds the Depth gate's `Effort` and label signals, and
+`issue_context` — specified as *empty if none* — which the fixer and ui-reviewer
+spawns receive ungated, so an unread issue would reach them looking exactly like
+a PR that links no issue. Continuing would also print the `disabled` note while a
+second, unchosen cause applied. No flag moves a PR between *nothing to read*
+(proceed) and *the read failed* (stop).
```

```diff
--- a/src/skills/issue-pr-review/references/error-messages.md   (#6b)
+++ b/src/skills/issue-pr-review/references/error-messages.md
@@ -89,15 +89,9 @@
 **Trigger:** the PR body links an issue (`Closes #{N}` or a first-line `Refs #{N}`), but neither the Step 1
 *Depth gate* refresh nor its direct-`gh` degrade returns a usable record — on the
 first attempt or on the single re-run. This is a **stop**, not a degrade: Step 3
 would otherwise verify acceptance criteria against an empty snapshot and report
-the `acceptance_criteria` hard-block as `pass`. That describes the default
-configuration, and the stop is **not** conditional on it. When
-`review.require_acceptance_criteria_check` is `false` the hard-block does not
-run at all — Step 3 reports `○ acceptance_criteria: disabled` for that dimension —
-yet this error is still raised, because the flag governs how the dimension is
-reported, not whether the linked issue was read. Printing that note past a
-failed read would credit a deliberate opt-out for a gap nobody opted into.
-Full reasoning, including why the stop is kept rather than relaxed:
-*The empty-record fail-safe* in `references/review-loop-mechanics.md`. A PR
+the `acceptance_criteria` hard-block as `pass`. When
+`review.require_acceptance_criteria_check` is `false` (Step 3 reports
+`○ acceptance_criteria: disabled`) the error is still raised. Reasons:
+*The empty-record fail-safe* in `references/review-loop-mechanics.md`. A PR
 with **no** linked issue is not this error and is never stopped by it — same
 section.
```

```diff
--- a/src/skills/issue-pr-review/references/verification-checks.md   (#7)
+++ b/src/skills/issue-pr-review/references/verification-checks.md
@@ -126 +126 @@
-     - IDD will not → report `partial — hand merge will not carry the PR body` (SPEC §4.3). The fix is `review.auto_merge: true` in `.idd.yml` or `/auto-pilot` in a mode that merges, never a repo-settings change.
+     - IDD will not → report `partial — hand merge will not carry the PR body`. The fix is `review.auto_merge: true` in `.idd.yml` or `/auto-pilot` in a mode that merges, never a repo-settings change.
```

**Before you apply:**
- **Test pins:** I checked `tests/` for phrases these hunks change. `tests/test-followup-context-285.sh` checks for "stop still applies", "reporting, not reading", `issue_context`, "empty if none" and "still raised", and the rewrites keep all of them. No test matches the other edited lines; the `SPEC §4.3` hits in tests are comments in other test files.
- **Other skills:** `SPEC §` citations also appear in `issue-resolver`, `issue-creator`, `plan-to-issues`, `idd-doctor` and `auto-pilot`. If you agree with #7, the same change applies there.
