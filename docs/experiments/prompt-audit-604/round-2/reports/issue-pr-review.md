I audited `src/skills/issue-pr-review` and found seven fixes worth proposing. All seven are in the reference files; `SKILL.source.md` has none. Three are high confidence because other files in the repo contradict them, and four are medium. Below are the findings and the proposed hunks. Nothing has been applied.

**What I assumed**
- **Scope:** `SKILL.source.md` and the 8 files in `references/`, as they stand now, including your uncommitted first-pass edits. I left out `docs/README.md`, which is a human-only file marked "do not read".
- **Target model:** Claude Opus 5.5, the model running this audit. The skill names no model, only `effort: high`.

**Summary**
The worst problem is a note in `review-loop-mechanics.md` that lists, file by file, whether `{N}` means the PR or the linked issue. Two of its claims are wrong. The worse one says `{N}` means the linked issue everywhere in `verification-checks.md`, but that file's `gh pr diff {N}` needs the PR number. An agent that trusted the note could hand the criteria judge the diff of the wrong PR.

The other two high-confidence findings:
- A pointer in `prepass-tests-ci-mechanics.md` sends the reader to SKILL.md for how to accept scan warnings, but SKILL.md doesn't cover it.
- An example in `report-templates.md` uses different step labels from SKILL.md and is missing the `Result:` row the report rules require.

By group: dated prompt text 1, brittle skill files 6. There are no tool descriptions in scope, and no request-building code, so the other two groups don't apply.

## Findings

| # | Location | Evidence | Pattern | Why it's wrong | Conf. | Action |
|---|---|---|---|---|---|---|
| 1 | `references/review-loop-mechanics.md:164-187` | "`references/verification-checks.md` — the linked issue throughout." / "SKILL.md — the PR, with one prose exception" | Brittle files: facts the repo now contradicts; one-off special cases piling up | `verification-checks.md:39` uses `gh pr diff {N}`, which is the PR number. SKILL.md also uses the issue `#N` at `:157` and `:332`, not only in the one place the note names. A per-file list breaks every time a file changes, so one general rule works better | High | rewrite |
| 2 | `references/verification-checks.md:39` | "`diff_command` = `gh pr diff {N}`" | Brittle files: two files disagree | Everywhere else in this file `{N}` is the linked issue (`Refs #{N}`, `--grep="#{N}"`). This is the only line where it means the PR, and the line doesn't say so | Medium | rewrite |
| 3 | `references/prepass-tests-ci-mechanics.md:158-159` | "or warnings are accepted — see the scan contract in SKILL.md" | Brittle files: a pointer that doesn't resolve | SKILL.md *Commit auto-fixes* says nothing about warnings. The `warn` rules live in *Mode Contract* in `docs/pre-commit-security.md` (`:35`) | High | rewrite |
| 4 | `references/report-templates.md:408-424` (and the intro at `:3`) | `[2/7] Script Pre`, `[4/7] Tests`, `[5/7] CI`, `[7/7] Summary`, a closing line `✓ PR #87 passed review (soft-pass: 1 medium note)` | Brittle files: two files disagree; outdated example | SKILL.md *Pipeline Overview* (`:128-138`) and each step's template use `Pre-pass`, `Test`, `CI Status`, `Report`, and add `qa:` to step 1. The *Review contract* (added 2026-10-05, after this example) puts `Result:` first. Examples steer output more strongly than prose, and SKILL.md already holds the correct one | High | remove |
| 5 | `references/report-templates.md:433`, `:476` | `[4/7] Tests` | Brittle files: two files disagree | SKILL.md's step 4 template (`:267-268`) labels it `[4/7] Test` | Medium | rewrite |
| 6 | `references/review-loop-mechanics.md:438-442` | "Keep this recompute: it is still required when CI is runnable. Independently, …" | Dated prompt text: phrased as a change from an earlier version; a note to maintainers | "Keep … still required" argues with an older version of the rule that the runtime agent never saw. The instruction itself ("Recompute it after any push") is already stated at `:430` | Medium | rewrite |
| 7 | `references/review-loop-mechanics.md:502` | "**Cycles 2-3:**" | Brittle files: hard-coded value | `review.max_cycles` can be changed in config. The same file's heading at `:548` and SKILL.md `:229` both say "Cycles 2+" | Medium | rewrite |

No tests or evals pin any of these strings. The only nearby pin is the heading `## Step 2 — Script Pre-pass detection` in `tests/test-state-scope-522.sh:445`, and no hunk touches it.

## Proposed diff

**Finding 1**
```diff
--- a/src/skills/issue-pr-review/references/review-loop-mechanics.md
+++ b/src/skills/issue-pr-review/references/review-loop-mechanics.md
@@ -164,24 +164,8 @@
-The binding is decided per file, not once for the skill, so read every `{N}`
-against the document it sits in. Below, `{N}` means an issue or PR number; the
-counting uses that share the braces — `{N} tests passed`, `{N} checks failed`,
-`Cycle {N}` — are a different placeholder and are not catalogued here.
-
-- `references/verification-checks.md` — the linked issue throughout. That
-  …
-- SKILL.md — the PR, with one prose exception: the *Review Loop*'s restatement
-  of the hard-block, "a missing `Closes #N`". It names the condition, not a
-  command or a fix string, so nothing downstream substitutes it.
+Elsewhere, read each `{N}` from its own line: a PR command (`gh pr …`,
+`/issue-pr-review {N}`) takes the PR number; a closing keyword, a `Refs` line,
+a commit reference or a `gh issue …` command takes the linked issue. The
+counting uses — `{N} tests passed`, `{N} checks failed`, `Cycle {N}` — are a
+different placeholder.
```
(This removes the whole block from `:164` to `:187`. The `{linked_issue}` paragraph at `:157-162`, including its anchor, stays as it is.)

**Finding 2**
```diff
--- a/src/skills/issue-pr-review/references/verification-checks.md
+++ b/src/skills/issue-pr-review/references/verification-checks.md
@@ -39 +39 @@
-… `diff_command` = `gh pr diff {N}`, `head_sha` = …
+… `diff_command` = `gh pr diff {pr_number}` (the PR, not the linked issue), `head_sha` = …
```

**Finding 3**
```diff
--- a/src/skills/issue-pr-review/references/prepass-tests-ci-mechanics.md
+++ b/src/skills/issue-pr-review/references/prepass-tests-ci-mechanics.md
@@ -158,2 +158,3 @@
-`docs/pre-commit-security.md`. Only after the scan passes (or warnings are
-accepted — see the scan contract in SKILL.md), commit and push:
+`docs/pre-commit-security.md`. Only after the scan passes — on `warn`, once the
+*Mode Contract* in `docs/pre-commit-security.md` lets it proceed — commit and
+push:
```

**Finding 4**
```diff
--- a/src/skills/issue-pr-review/references/report-templates.md
+++ b/src/skills/issue-pr-review/references/report-templates.md
@@ -3 +3 @@
-Templates for the Step 7 summary report and the expected inline pipeline output. SKILL.md keeps the contract short; this file holds the full templates.
+Templates for the Step 7 summary report and the step completion reports; SKILL.md's *Pipeline Overview* shows the inline tracker. SKILL.md keeps the contract short; this file holds the full templates.
@@ -408,17 +408,0 @@
-## Expected Inline Output
-
-A clean review prints the 7-step tracker and a summary:
-
-```
-  [1/7] PR Info       ✓ #87 fix(auth): resolve redirect (#42), depth: full
-  …
-  ✓ PR #87 passed review (soft-pass: 1 medium note)
-```
-
```

**Finding 5**
```diff
@@ -433 +433 @@
-  [4/7] Tests        ✓ 128 passed, 0 failed
+  [4/7] Test         ✓ 128 passed, 0 failed
@@ -476 +476 @@
-  [4/7] Tests        ○ tests skipped (qa handoff @ {commit_sha_short})
+  [4/7] Test         ○ tests skipped (qa handoff @ {commit_sha_short})
```

**Finding 6**
```diff
--- a/src/skills/issue-pr-review/references/review-loop-mechanics.md
+++ b/src/skills/issue-pr-review/references/review-loop-mechanics.md
@@ -438,5 +438,4 @@
-  committed, Step 4's afterwards — leaving only Step 5's CI. Keep this
-  recompute: it is still required when CI is runnable. Independently, the
-  `tests=` skip is refused when `ci_leg_runnable` is false, so a missed
-  recompute on a no-CI / `review.check_ci: false` path cannot auto-merge on
-  zero test evidence.
+  committed, Step 4's afterwards — leaving only Step 5's CI. On a no-CI /
+  `review.check_ci: false` path the `tests=` skip is already refused
+  (`ci_leg_runnable` is false), so a missed recompute there cannot auto-merge
+  on zero test evidence.
```

**Finding 7**
```diff
@@ -502 +502 @@
-- **Cycles 2-3:** Send the reviewer a follow-up message via `SendMessage` …
+- **Cycles 2+:** Send the reviewer a follow-up message via `SendMessage` …
```

## Notes only (no edit proposed)
- **Auto mode with `browser_review: "true"` is ambiguous.** `ui-review-mechanics.md:63-65` says auto mode always runs code review only. `docs/ui-review.md:90-92`, which is supposed to be the single source for these rules, says `"true"` goes on to the capability check. The same commit wrote both, so history can't say which is current. Aligning them would loosen a restriction, so you need to decide whether auto mode may ever run the browser leg.
- **`report-templates.md:69-72`:** "Interactive filtering is therefore not applicable" answers a question the runtime agent never faces. It looks left over from a grading standard. Low confidence.
- **Repeated explanation:** the "trusted collapse saves no reviewer spawn" reasoning appears three times (`review-loop-mechanics.md:412-423` and `:507-517`, `SKILL.source.md:229`). The copies agree, so I left them.
- **`SKILL.source.md:257`:** an aside about the live head splits the step 4 skip rule mid-sentence ("so … therefore …"). This hurts readability but isn't a dated pattern.
- **`SKILL.source.md:218`:** the four-part scan pass rule doesn't say how a `warn` verdict is handled in interactive mode. If you take finding 3, that file covers it; SKILL.md still doesn't mention it.
