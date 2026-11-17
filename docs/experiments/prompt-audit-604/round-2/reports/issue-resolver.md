I audited `src/skills/issue-resolver` and found 15 places to rewrite or remove: 7 at high confidence and 8 at medium. I haven't edited any files. Most of them are wrong facts, pointers that lead nowhere in the built skill, or notes meant for maintainers. Only two are about wording written for older models.

**Assumptions.**
- **Scope:** the runtime files under `src/skills/issue-resolver/`, read as they are now, including the first pass's uncommitted edits. I left out `docs/README.md` (human-only, marked do-not-read) and `LICENSE`.
- **Target model:** Claude Opus 5.5, the model running this audit. The skill names no model; it only sets `metadata.effort: max`.
- **No Claude API code** in scope, so Group 4 (request settings) doesn't apply.

**The ones that matter most.**
- **The PARTIAL rule contradicts itself.** `step-reports.md` says a step may end `PARTIAL` "in exactly three places" and that any other failed check blocks the run. Twenty lines earlier the same file says any step with a check that couldn't be evaluated ends `PARTIAL`. An agent at Step 1 or 3 with an unevaluated check gets two opposite rules.
- **Pointers to files the built skill doesn't have.** Several lines send the agent to `/auto-pilot`'s or `/issue-analysis`'s files, a step name auto-pilot doesn't use, or a README the agent is told not to read. CLAUDE.md requires every pointer to resolve inside the skill's own bundle.

**Count by group:** Group 1 (wording for older models): 2. Group 2 (stale or conflicting skill text): 13. Group 3 (tool descriptions): 0. Group 4: not applicable.

## Findings

### High confidence

1. **`references/step-reports.md:51-55`** — rewrite
   - Quote: "`PARTIAL` is legitimate in exactly three places … Anywhere else a `×` is blocking."
   - Pattern: Group 2, files contradicting each other.
   - Why: lines 27-29 say any step with an unevaluated check ends `PARTIAL`, and lines 30-33 let Step 2 end `PARTIAL`. CLAUDE.md names "exactly three places" as the kind of list that goes stale.

2. **`references/steps/step-0j-resume.md:159-160`** — remove
   - Quote: "No label edit exists in this skill today; a future one must add an intent row here."
   - Pattern: Group 2, history and notes to maintainers.
   - Why: CLAUDE.md bans "today" wording and notes to a future maintainer inside a skill. There is nothing for the agent to do here.

3. **`references/steps/step-2-plan.md:337-339`** — rewrite
   - Quote: "It reuses the recommended option — no new phase, artifact or config key —"
   - Pattern: Group 1d, wording that compares against an older version.
   - Why: it describes a change the agent never saw. CLAUDE.md names "no new config key is introduced" as an example to avoid.

4. **`references/pipeline-steps.md:68-70`** — rewrite
   - Quote: "the four signals the run log folds into its single line"
   - Pattern: Group 2, out-of-date facts.
   - Why: `run-log-fields.md:10-12` lists about 20 run-log fields, not four.

5. **`references/report-templates.md:178`** — rewrite
   - Quote: "For bug issues the sixth `Reproduction` line is added separately"
   - Pattern: Group 2, out-of-date facts.
   - Why: the Decision Record template at lines 24-36 has 12 lines, and `Reproduction` is the 11th, not the 6th.

6. **`references/steps/step-3-implement.md:203-204`** — rewrite
   - Quote: "the same rule `/auto-pilot`'s *phases/phase-0-lock-resume.md* states for `current.branch`"
   - Pattern: Group 2, a pointer that doesn't resolve.
   - Why: that file is in auto-pilot's bundle, not this one. The comparison adds nothing the sentence doesn't already say.

7. **`references/steps/step-1-research.md:134`** — rewrite
   - Quote: "A caller that can review — `/auto-pilot` Phase 2.3 — routes it"
   - Pattern: Group 2, a pointer that doesn't resolve.
   - Why: auto-pilot calls it "Step 2.3 — Process Resolver Result" (`phase-2-resolve.md:206`), and that file isn't in this bundle.

### Medium confidence

8. **`references/steps/step-3-implement.md:155-157`** — rewrite
   - Quote: "with the same tools the skill README already names"
   - Pattern: Group 2, a pointer that doesn't resolve.
   - Why: the only README is marked do-not-read and is never loaded. The commands are already given inline, and the `asm install …` ellipsis leaves the source URL unstated.

9. **`references/bug-verification.md:104-111`** — rewrite
   - Quote: "defined in `/issue-analysis`'s output schema (`references/output-and-persist.md`) so the two skills agree on its shape"
   - Pattern: Group 2, a pointer that doesn't resolve.
   - Why: inside this skill, `references/output-and-persist.md` means a file the bundle doesn't have. The note about the two skills agreeing is for maintainers. The only runtime rule is "lift it when a fresh analysis carries it."

10. **`references/steps/step-4-qa.md:101`** — rewrite
    - Quote: "that is the Deliver order, which this variable does not change"
    - Pattern: Group 1d, wording that compares against an older version.

11. **`references/steps/step-4-qa.md:46-47`** — remove
    - Quote: "Two definitions of "the suite already ran on this commit" drift apart, so this is the only place either is stated."
    - Pattern: Group 2, a note to maintainers.
    - Why: it explains why the docs are organised this way. It tells the agent nothing to do.

12. **`references/steps/step-0h-analysis-reuse.md:12-15`** — rewrite
    - Quote: "Every other mention … — `references/report-templates.md` … and the bug-repro mirror in *Step 3* … — defers to this section. Do not restate or re-derive a freshness rule anywhere else."
    - Pattern: Group 2, a note to maintainers plus a copied list that has gone stale.
    - Why: the list leaves out the mentions in `bug-verification.md` and Steps 1-2. "Anywhere else" tells authors where to write text.

13. **`references/report-templates.md:176`** — remove
    - Quote: "That section is the single home of the definition: do not restate, tighten, or re-derive a freshness rule here."
    - Pattern: Group 2, a note to maintainers.
    - Why: the sentence before it already says to use the Step 0h test.

14. **`references/steps/step-0h-analysis-reuse.md:136-139`** — remove
    - Quote: "it needs no change from a caller: `/auto-pilot`'s explicit-list mode … gets the reuse purely by having written the file."
    - Pattern: Group 2, a note to maintainers.
    - Why: it's a design note about another skill. The resolver has nothing to do with it.

15. **`references/steps/step-1-research.md:198-199`** — remove
    - Quote: "The saving is real but bounded, and worth stating plainly: the codebase is researched once and *verified* once, rather than researched twice."
    - Pattern: Group 1c, padding.
    - Why: it argues for the design. Deleting it doesn't change what is allowed or how success is measured.

## Proposed diff

Not applied. Each hunk is one finding, so you can take any subset. After applying, rebuild `skills/` with `bash scripts/build.sh --out <tmp-dir> --quiet`. Only finding 1 changes a phrase a test checks for, so its hunk updates that test too.

```diff
--- a/src/skills/issue-resolver/references/step-reports.md      # finding 1
+++ b/src/skills/issue-resolver/references/step-reports.md
@@ -51,5 +51,7 @@
-`PARTIAL` is legitimate in exactly three places: *Step 0 — Preflight* when only
-`Criteria confirmed` is `×` (an issue not ready, resolved on a yes, or criteria 0d wrote); *Step 4 — QA* when the loop hits
-its cycle cap with residual non-blocking findings (delivered with known
-issues), and *Step 5 — Deliver* when the PR is created but an optional extra
-(project-board sync, run-log append) failed. Anywhere else a `×` is blocking.
+Besides the two cases above (a check that could not be evaluated, and Step 2's
+`Options produced`), `PARTIAL` is legitimate on
+*Step 0 — Preflight* when only `Criteria confirmed` is `×` (an issue not ready,
+resolved on a yes, or criteria 0d wrote); on *Step 4 — QA* when the loop hits
+its cycle cap with residual non-blocking findings (delivered with known
+issues); and on *Step 5 — Deliver* when the PR is created but an optional extra
+(project-board sync, run-log append) failed. Any other `×` is blocking.
--- a/tests/test-issue-readiness-553.sh                          # finding 1 (pinned phrase)
+++ b/tests/test-issue-readiness-553.sh
@@ -211 +211 @@
-has "$RS/references/step-reports.md" 'legitimate in exactly three places: *Step 0 — Preflight*' \
+has "$RS/references/step-reports.md" '*Step 0 — Preflight* when only `Criteria confirmed` is `×`' \
--- a/src/skills/issue-resolver/references/steps/step-0j-resume.md   # finding 2
+++ b/src/skills/issue-resolver/references/steps/step-0j-resume.md
@@ -157,5 +157,2 @@
 | `run_log` | — | `closing` is recorded → never append again |
 
-**No label edit exists in this skill today; a future one must add an intent row
-here.**
-
 **0b ownership exception.** On a resume, 0b's open-PR list also reads
--- a/src/skills/issue-resolver/references/steps/step-2-plan.md   # finding 3
+++ b/src/skills/issue-resolver/references/steps/step-2-plan.md
@@ -337,3 +337,3 @@
 only high-complexity interactive work earns one extra confirmation before Step 3. It
-reuses the recommended option — no new phase, artifact or config key — and is separate
-from the sensitive-change gate, which keys off sensitivity, not size.
+presents the recommended option and is separate from the sensitive-change gate, which
+keys off sensitivity, not size.
--- a/src/skills/issue-resolver/references/pipeline-steps.md      # finding 4
+++ b/src/skills/issue-resolver/references/pipeline-steps.md
@@ -68,3 +68,3 @@
-**Audited per step:** `complexity`, `qa_cycles`, `outcome` and `duration_s` — the four
-signals the run log folds into its single line — plus the `[N/5]` tracker line the user
-sees.
+**Audited per step:** `complexity`, `qa_cycles`, `outcome` and `duration_s` — fields of
+the run-log line (`references/run-log-fields.md`) — plus the `[N/5]` tracker line the
+user sees.
--- a/src/skills/issue-resolver/references/report-templates.md    # finding 5
+++ b/src/skills/issue-resolver/references/report-templates.md
@@ -178 +178 @@
-… `commit_sha_short`. (For bug issues the sixth `Reproduction` line is added separately from the implementer's returned reproduction block — see the bug-verification checkpoint, not the analysis JSON.) Either source …
+… `commit_sha_short`. (For bug issues the `Reproduction` line comes from the implementer's returned reproduction block — see the bug-verification checkpoint, not the analysis JSON.) Either source …
--- a/src/skills/issue-resolver/references/steps/step-3-implement.md   # finding 6
+++ b/src/skills/issue-resolver/references/steps/step-3-implement.md
@@ -201,5 +201,4 @@
 **Re-screen every entry before it reaches a command.** `--read` deliberately
 never fails and echoes the state back verbatim, so the write-path skill-name
-validation is **not** a guarantee about what teardown reads — the same rule
-`/auto-pilot`'s *phases/phase-0-lock-resume.md* states for `current.branch`, and quoting does not
+validation is **not** a guarantee about what teardown reads, and quoting does not
 neutralise `$(…)` or backticks because the agent composes the command text.
--- a/src/skills/issue-resolver/references/steps/step-1-research.md    # finding 7
+++ b/src/skills/issue-resolver/references/steps/step-1-research.md
@@ -133,3 +133,3 @@
 - Auto mode: return `status: pr_in_progress` with `pr_number` / `branch_name` and
-  stop. A caller that can review — `/auto-pilot` Phase 2.3 — routes it into
-  review of that PR instead of skipping the issue.
+  stop. A caller that can review, such as `/auto-pilot`, routes it into review of
+  that PR instead of skipping the issue.
--- a/src/skills/issue-resolver/references/steps/step-3-implement.md   # finding 8
+++ b/src/skills/issue-resolver/references/steps/step-3-implement.md
@@ -154,4 +154,4 @@
-- Install each recorded-borrowed name into `~/.claude/skills/<name>/` with the
-  same tools the skill README already names (`npx skills add
-  https://github.com/luongnv89/skills --skill <name>` or `asm install …
-  --skill <name>`). Never install a name absent from the index. Never
+- Install each recorded-borrowed name into `~/.claude/skills/<name>/` with
+  `npx skills add https://github.com/luongnv89/skills --skill <name>` or
+  `asm install https://github.com/luongnv89/skills --skill <name>`. Never
+  install a name absent from the index. Never
--- a/src/skills/issue-resolver/references/bug-verification.md     # finding 9
+++ b/src/skills/issue-resolver/references/bug-verification.md
@@ -104,8 +104,4 @@
-3. **Optional cache mirror.** The `decision_record.reproduction` field in
-   `.idd/analysis-<N>.json` is defined in `/issue-analysis`'s output schema
-   (`references/output-and-persist.md`) so the two skills agree on its shape, but no
-   skill writes it: `/issue-analysis` is read-only and runs *before* the fix, so it cannot
-   produce the post-fix `regression_test` proof, and the resolver does **not** create or
-   write the cache file. The resolver **lifts** the field only when a fresh analysis
-   file already carries one — the JSON is deletable local cache, not the home of
-   project memory, and the PR body (above) is the always-present durable home.
+3. **Optional cache mirror.** When a fresh analysis file (*Step 0h*) already carries
+   `decision_record.reproduction`, lift it too. The resolver never creates or writes
+   `.idd/analysis-<N>.json`: it is deletable local cache, and the PR body (above) is
+   the durable home.
--- a/src/skills/issue-resolver/references/steps/step-4-qa.md      # finding 10
+++ b/src/skills/issue-resolver/references/steps/step-4-qa.md
@@ -99,4 +99,3 @@
 *Update documentation* commits **after** Step 5's Verify (see the Deliver order in
-SKILL.md), so a doc-only commit is never covered by `tests_state` — that is
-the Deliver order, which this variable does not change, and the reason `tests=` is captured
-in Step 4 rather than at push time.
+SKILL.md), so a doc-only commit is never covered by `tests_state`; that is why
+`tests=` is captured in Step 4 rather than at push time.
--- a/src/skills/issue-resolver/references/steps/step-4-qa.md      # finding 11
+++ b/src/skills/issue-resolver/references/steps/step-4-qa.md
@@ -45,3 +45,2 @@
 of the same state; `references/report-templates.md` is only that marker's
-rendering location, not a third consumer. Two definitions of "the suite already
-ran on this commit" drift apart, so this is the only place either is stated.
+rendering location, not a third consumer.
--- a/src/skills/issue-resolver/references/steps/step-0h-analysis-reuse.md   # finding 12
+++ b/src/skills/issue-resolver/references/steps/step-0h-analysis-reuse.md
@@ -12,4 +12,3 @@
-researches the codebase **once** instead of twice. Every other mention of a
-*fresh* analysis in this skill — `references/report-templates.md` (*Lifting the
-Decision Record*) and the bug-repro mirror in *Step 3* (`references/steps/step-3-implement.md`) — defers to this
-section. Do not restate or re-derive a freshness rule anywhere else.
+researches the codebase **once** instead of twice. Wherever this skill calls an
+analysis *fresh*, it means fresh by this predicate and by no other test.
--- a/src/skills/issue-resolver/references/report-templates.md    # finding 13
+++ b/src/skills/issue-resolver/references/report-templates.md
@@ -176 +176 @@
-… five checkable conditions, any doubt ⇒ stale. That section is the single home of the definition: do not restate, tighten, or re-derive a freshness rule here. When fresh, …
+… five checkable conditions, any doubt ⇒ stale. When fresh, …
--- a/src/skills/issue-resolver/references/steps/step-0h-analysis-reuse.md   # finding 14
+++ b/src/skills/issue-resolver/references/steps/step-0h-analysis-reuse.md
@@ -134,6 +134 @@
 passes. Both keep the *Verify not already resolved* phase in full.
-
-Because the gate reads only an on-disk artifact and this run's own base, it
-needs no change from a caller: `/auto-pilot`'s explicit-list mode, which runs
-`/issue-analysis` and then `/issue-resolver` back to back on the same tree, gets
-the reuse purely by having written the file.
--- a/src/skills/issue-resolver/references/steps/step-1-research.md    # finding 15
+++ b/src/skills/issue-resolver/references/steps/step-1-research.md
@@ -196,5 +196,2 @@
 its own `prior_analysis` contract and skips exactly the work item 3 names instead
 of re-running it.
-
-The saving is real but bounded, and worth stating plainly: the codebase is
-researched once and *verified* once, rather than researched twice.
 
```

None of the other phrases these hunks remove are checked by any test in `tests/` or `evals/`.

## Flag-only notes (no change proposed)

- **`steps/step-0i-caller-payload.md`:** the `updatedAt` exact-match rule appears three times (lines 7-15, 42-51, 87-99). The copies agree, so I'm only noting it.
- **`report-templates.md:105`** and **`step-4-qa.md:45`:** "not a third run-state consumer" reads like a maintainer note. I left it because `tests/test-followup-context-285.sh` checks for it.
- **`steps/step-0-preflight.md:289`:** "(that cleanup keeps it while it holds any)" doesn't name which cleanup. It means `/issue-pr-review`'s post-merge cleanup.
- **`steps/step-0i-caller-payload.md:47, 53`:** "explicit-list analyzer optimization" and "the existing array of records" are mild history wording, low confidence.
- **`bug-verification.md:8-10`:** "a softened, pragmatic form of TDD" is history wording, low confidence.
- **The capitalised `MUST`s** (`SKILL.md:177`, `:309`; `report-templates.md:176`) each come with a reason or guard a safety step, so I kept them.
