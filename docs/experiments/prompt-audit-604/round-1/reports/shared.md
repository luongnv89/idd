# Prompt audit: `src/shared/agents` and `src/shared/references`

**Assumptions**
- **Scope:** the 9 agent definitions in `src/shared/agents/` and the 2 shared references in `src/shared/references/`. I skipped the built copies under `skills/`, `dist/agents/` and `.pi/agents/`, because the build generates them. I read `docs/shared-agent-conventions.md`, `scripts/build/*.py`, the `gi-secscan.py` argument parser and the skill files that cite these agents only to check claims. None of them is in scope for edits.
- **Target model:** Claude Opus 5.5 (`claude-opus-5-5`), the model running this audit. These are coding-agent configuration files, and none of them pins a model. The "Default tier" in each header only sets effort (`docs/agent-model-effort.md:24-30`).
- **How the build ships these files** (this decides which text reaches a subagent):
  - `code-reviewer`, `fixer`, `ui-reviewer` and `criteria-judge` send only the body of their `## Prompt` block.
  - The other five send the whole file, with the shared conventions inserted before `## Contract` (`scripts/build/agents.py:121-148`).
- No other model provider is involved.

## Summary

The prompts are in good shape. They show almost none of the old-model habits this audit looks for: no shouting, no "think step by step", no prefill or JSON-forcing tricks, no rules about update frequency, and no retired model names. Most of the emphatic lines that are there are security or merge gates with their reasons stated, and they stay.

The three findings that matter most:

1. **The code reviewer is told to report less in vague terms** (`code-reviewer.md:19,78`). On recent Opus models, wording like "quality over quantity" and "fewer issues beats a long list of nits" makes the model hold back real findings, so fewer bugs get reported. The concrete score threshold and the "Do NOT flag" list already set the bar.
2. **Five whole-file agents contradict themselves about the conventions file.** Each one links to `docs/shared-agent-conventions.md` (built as a GitHub URL) and calls it "their single source of truth". The text the build inserts right below that says "do not go looking for a conventions file".
3. **Text meant for other readers is sent to subagents.** `run-stats.md:3` says where the maintainers keep the file, and `issue-relationship-scanner.md:74-76` holds batching instructions for the calling skill. Both reach the model at run time.

**Findings per group**
- **Group 1 (dated prompt text):** 3 findings (1 low).
- **Group 2 (brittle skill and config files):** 5 findings (1 is flag-only).
- **Group 3 (tool descriptions):** not applicable. There are no tool definitions in scope.
- **Group 4 (request config and architecture):** request code is not applicable. The 9-agent roster has no redundant agents. 1 finding.

## Findings

| # | Location | Evidence | Pattern | Why it no longer fits | Confidence | Action |
|---|---|---|---|---|---|---|
| 1 | `src/shared/agents/{codebase-researcher,duplicate-detector,implementer,issue-relationship-scanner,synthesizer}.md:8` | "`docs/shared-agent-conventions.md` is their single source of truth (and carries the orchestrator-side spawn parameters)" | G2: instructions that contradict each other / maintainer material in the bundle | These five ship as whole files, so this line reaches the subagent as a GitHub URL. The text the build inserts just below it (`scripts/build/common.py:185-188`) says "do not go looking for a conventions file". The doc also says its other sections are not inlined (`docs/shared-agent-conventions.md:26-27`), so the link leads to material meant for the calling skill. | High | `rewrite` → "The shared conventions are inlined into the prompt below." |
| 2 | `src/shared/agents/code-reviewer.md:19`, `:78` | "Review with high precision — quality over quantity." / "Fewer actionable issues beats a long list of nits." | G1a / 1d: vague "report less" wording in a review prompt | Anthropic's migration guide says Opus 4.7 and later follow "be conservative / don't nitpick" wording literally: the model finds the bugs, then leaves them out of its report. The guide says this is unchanged on Opus 5. The concrete bar (`>= {confidence_threshold}`, the severity rules, the "Do NOT flag" list on line 77) is the form the guide recommends, so these two vague lines add nothing except the drop in reported bugs. | Medium | `remove` both phrases |
| 3 | `src/shared/references/run-stats.md:3` | "The run-cost footer contract, authored once in `src/shared/references/`." | G2: maintainer material and a path the reader doesn't have | This file is copied into every skill and read at run time, where `src/` doesn't exist. CLAUDE.md says "Keep maintainer material out of the bundle" and "Write paths as the built skill sees them". The single-copy rule is already enforced by the build's collision abort and by the "no skill authors its own copy" check in `tests/test-run-stats-373.sh`. | Medium | `remove`. The diff also drops the test pin at `tests/test-run-stats-373.sh:140-141`. |
| 4 | `src/shared/agents/codebase-researcher.md:22` | "(docs/shared-agent-conventions.md, *Caller-supplied context payloads*)" | G2: a pointer that doesn't resolve for the reader | That section is not inlined (`docs/shared-agent-conventions.md:26-27`), so a subagent can only follow it over the network. The sentence is complete without the pointer. | Medium | `rewrite`: drop the parenthetical |
| 5 | `src/shared/agents/issue-relationship-scanner.md:74-76` | "## Parallel batching (orchestrator) … the main agent splits into batches of ~5 and spawns one scanner per batch" | 1c: instructions placed where they don't apply / G2: copies of one rule in several files | This is a whole-file agent, so every scanner subagent receives instructions addressed to the calling skill. Their real home, with fuller merge rules, is `src/skills/issue-triage/references/detection.md:17,106-109`; `issue-triage/SKILL.source.md:209-213` has them too. No test pins this section. | Medium | `remove` |
| 6 | `src/shared/agents/issue-relationship-scanner.md:70` | "`referenced_issues` is retained for compatibility" | 1d: wording that describes an older version | It describes the field against a previous version the model never saw. No script uses the field, and `detection.md:18` says not to rely on it alone. CLAUDE.md asks to "Describe current behaviour as the only behaviour". | Medium | `rewrite` (see diff). `detection.md:18` has the same "compatibility" wording but is outside this audit's scope. |
| 7 | `src/shared/agents/fixer.md:43` vs `implementer.md:62` | Implementer: "Compare `scanned` against the number of files you staged as well … print `⚠ gi-secscan unavailable — running the documented scan`". Fixer has neither. | G2: two copies of a safety rule that differ | The two copies of the "when does exit 0 count as a pass" rule have drifted apart. `docs/pre-commit-security.md` doesn't state this rule, so neither copy can point to a single home. | Medium | `flag`. This is a safety gate, so the audit does not rewrite it. You decide whether the fixer should gain the staged-count check. |
| 8 | `src/shared/agents/issue-relationship-scanner.md:30-37` (Part B) | Commit and PR parsing, the `target_issues` rule, and "`high` = closing keyword … `medium` = bare mention" | G4: a model doing a fully rule-based job | The input (`git log`, `gh pr list/view`) fully determines the output. Part A's keyword extraction is real judgement and should stay with the model. Part B is a candidate for a stdlib script, the way `gi-dup-score.py` took over the arithmetic from `duplicate-detector`. | Medium | `flag`. The fix is a new shared script, which is outside a prompt diff. |
| 9 | `src/shared/agents/codebase-researcher.md:6` | "Trace every dependency like a program flow" | 1c: generic virtue that conflicts with a stated limit | It reaches the subagent and pulls against `trace_depth` and `max_files` (lines 85 and 152). The constraints probably win, so this is only a low-confidence style flag. | Low | `flag` |

**Checked and kept:**
- The `MUST` / `NEVER` lines in the secscan, staging and prompt-injection rules. They are security gates with reasons attached.
- The "Return ONLY this JSON block" lines. The calling skill parses that output, so they pin a required format.
- The repeated "never install an e2e framework" lines in `implementer.md`. The copies agree.
- The quality-bar taglines in `ui-reviewer.md` and `implementer.md`. They give the reviewer a concrete standard.
- All of `self-improve.md` and `criteria-judge.md`: the rules carry their reasons and protect safety steps.
- The synthesizer's option scaffold. It is part of the PR Decision Record contract.

## Proposed diff

These are proposed only. Nothing has been applied. Each hunk covers one finding.

```diff
# Finding 1 — same edit in all five whole-file agents
--- a/src/shared/agents/codebase-researcher.md
+++ b/src/shared/agents/codebase-researcher.md
@@ -8 +8 @@
-The shared conventions are inlined into the prompt below; `docs/shared-agent-conventions.md` is their single source of truth (and carries the orchestrator-side spawn parameters).
+The shared conventions are inlined into the prompt below.
--- a/src/shared/agents/duplicate-detector.md
+++ b/src/shared/agents/duplicate-detector.md
@@ -8 +8 @@
-The shared conventions are inlined into the prompt below; `docs/shared-agent-conventions.md` is their single source of truth (and carries the orchestrator-side spawn parameters).
+The shared conventions are inlined into the prompt below.
--- a/src/shared/agents/implementer.md
+++ b/src/shared/agents/implementer.md
@@ -8 +8 @@
-The shared conventions are inlined into the prompt below; `docs/shared-agent-conventions.md` is their single source of truth (and carries the orchestrator-side spawn parameters).
+The shared conventions are inlined into the prompt below.
--- a/src/shared/agents/issue-relationship-scanner.md
+++ b/src/shared/agents/issue-relationship-scanner.md
@@ -8 +8 @@
-The shared conventions are inlined into the prompt below; `docs/shared-agent-conventions.md` is their single source of truth (and carries the orchestrator-side spawn parameters).
+The shared conventions are inlined into the prompt below.
--- a/src/shared/agents/synthesizer.md
+++ b/src/shared/agents/synthesizer.md
@@ -8 +8 @@
-The shared conventions are inlined into the prompt below; `docs/shared-agent-conventions.md` is their single source of truth (and carries the orchestrator-side spawn parameters).
+The shared conventions are inlined into the prompt below.
```

```diff
# Finding 2
--- a/src/shared/agents/code-reviewer.md
+++ b/src/shared/agents/code-reviewer.md
@@ -19 +19 @@
-You are an expert code reviewer. Review with high precision — quality over quantity.
+You are an expert code reviewer.
@@ -76,4 +76,3 @@
 - PASS = zero "fix" or "blocker" issues (medium "note" issues may exist — they don't block). NEEDS_FIX = at least one.
 - Do NOT flag: style/naming preferences, missing comments, import ordering, lint/format violations (tooling handles those), or anything subjective.
-- Fewer actionable issues beats a long list of nits.
 ```
```

```diff
# Finding 3
--- a/src/shared/references/run-stats.md
+++ b/src/shared/references/run-stats.md
@@ -1,5 +1,3 @@
 # Run Stats Footer
 
-The run-cost footer contract, authored once in `src/shared/references/`.
-
 ## The footer
--- a/tests/test-run-stats-373.sh
+++ b/tests/test-run-stats-373.sh
@@ -140,2 +140,0 @@
-check_flow "$SPEC" 'authored once in .src/shared/references/.' \
-  "AC6: the contract states its single-source rule"
```

```diff
# Finding 4
--- a/src/shared/agents/codebase-researcher.md
+++ b/src/shared/agents/codebase-researcher.md
@@ -22 +22 @@
-Two optional artifacts, **one contract, two trust profiles**. Both are caller-supplied context payloads (docs/shared-agent-conventions.md, *Caller-supplied context payloads*) — never a reason to skip a safety check.
+Two optional artifacts, **one contract, two trust profiles**. Both are caller-supplied context payloads — never a reason to skip a safety check.
```

```diff
# Finding 5
--- a/src/shared/agents/issue-relationship-scanner.md
+++ b/src/shared/agents/issue-relationship-scanner.md
@@ -73,6 +73,2 @@
 
-## Parallel batching (orchestrator)
-
-For 10+ issues, the main agent splits into batches of ~5 and spawns one scanner per batch (same turn), normally with `scope: "both"`. Merge: concatenate the `issues` maps, `dependency_edges`, `potentially_fixed`, and `merged_prs` arrays, then run a second pass for cross-batch edges (issues from different batches sharing files). Do not spawn separate history and dependency scanners for the same batch.
-
 ## Constraints
```

```diff
# Finding 6
--- a/src/shared/agents/issue-relationship-scanner.md
+++ b/src/shared/agents/issue-relationship-scanner.md
@@ -70 +70 @@
-- `history_scan.merged_prs`: merged PRs that reference an open issue; `referenced_issues` is retained for compatibility, while `references` preserves each reference's `source` (`body`, `title`, or `branch`) and `target_issues` identifies the PR's target issue numbers. …
+- `history_scan.merged_prs`: merged PRs that reference an open issue; `referenced_issues` lists every referenced issue number for traceability only, `references` preserves each reference's `source` (`body`, `title`, or `branch`), and `target_issues` identifies the PR's target issue numbers. …
```
(The rest of line 70, starting "`changed_files` holds…", is unchanged.)

## Before you take these hunks

- **Tests.** No test pins the text these hunks change, except the run-stats pin that the Finding 3 hunk removes. After applying, rebuild with `bash scripts/build.sh --out <tmp> --quiet` and run `git ls-files 'tests/*.sh' | xargs -n1 bash`. The tests that touch these files are `test-run-stats-373.sh`, `test-subagent-context-256.sh`, `test-agent-conventions-inline-245.sh` and the bundle-budget test. Bundles only shrink.
- **Project values.** None of the hunks loosens a gate in `docs/VALUES.md`. The Finding 5 hunk moves toward TE10 (one home per instruction).
- **Finding 2 needs a behavioural check.** Run the code reviewer before and after on a branch with known bugs. More findings should come back while the 80-point threshold still filters. If the extra "note" findings are noise, the guide's alternative is to have the reviewer report everything with confidence and severity, and let `issue-pr-review` / `issue-resolver` filter afterwards.
