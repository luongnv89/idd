# Prompt audit: `src/skills/auto-pilot`

**What I assumed**
- **Scope:** all 25 files under `src/skills/auto-pilot/`, which is the `SKILL.source.md` (352 lines), 22 reference files and the 4 subagent prompt files.
  - Read in full: `SKILL.source.md`, the four prompt files, `spawning.md`, `orchestration.md`, `phases.md`, `configuration.md`, `preflight.md`, and the phase 0, 1, 2, 3–4 and 5 files.
  - Read in part: `explicit-list-mode.md` (lines 80–279) and `error-messages.md` (lines 485–547).
  - Only searched with keyword patterns, not read through: `examples.md`, the rest of `error-messages.md`, `summary-format.md`, `summary-variants.md`, `step-reports.md`, `run-log.md`, `stats.md`, and `docs/README.md` (which agents never read).
  - I also checked the skill's claims against the sibling skills, `docs/config-schema.md` and `tests/`, but did not audit those.
- **Target model:** Claude Opus 5.5. This is a coding-agent skill, the request names no model, and the skill pins none (it only sets `metadata.effort: max`).
- **Nothing was edited.** The diff below is a proposal only.

## Summary

The skill has almost none of the wording that goes stale as models change. There's no heavy capital-letter emphasis, no "try to / if possible" hedging, no "think step by step" or scratchpad instructions, no old model names and no ticket numbers. What I did find is mostly facts that the repository itself now contradicts. The three that matter most:

1. **The dependency gate gives a wrong reason** (`phase-5-merge.md:254`). It says a re-picked issue would make the resolver "abort on its 'PR already targets this issue' guard" and log a failed run. The resolver no longer aborts there: it returns `pr_in_progress`, and the loop reviews the existing PR (`prompts/resolver.md:26-31`, `phase-2-resolve.md:256-270`).
2. **The fallback list of default settings is missing two keys** (`SKILL.source.md:182`). When `gi-config.py` can't run, the skill fills in settings from this list. It lacks `triage_cache_max_age_minutes` and `retriage_every`, although the skill uses `retriage_every` (`SKILL.source.md:214`) and `docs/config-schema.md:340,343` defines both.
3. **The skill prints two different messages for a PR blocked by a dependency.** The quick table in `SKILL.source.md:308` uses one wording; the full message in `error-messages.md:494` and `phase-5-merge.md:231` uses another.

**Findings per group**
- Group 1 (wording written for older models): 5 findings, all text that describes past behaviour or earlier versions.
- Group 2 (stale facts and broken pointers): 7 findings.
- Group 3 (tool descriptions): not applicable. The frontmatter `description` is routing text, and the skill defines no tools.
- Group 4 (request setup): not applicable, since there is no request-building code. I checked whether any of the four subagent types duplicate each other; none do.
- Low-confidence notes for you to judge: 6.

---

## Findings

### High confidence

**H1 · `references/phases/phase-5-merge.md:254`, a stale fact (Group 2)**
- **Text:** "the resolver would then abort on its "PR already targets this issue" guard and the run log would gain a second, bogus `failed` line"
- **Why it's wrong:** the resolver now reports `pr_in_progress`, and Phase 2 sends that PR to review (`prompts/resolver.md:26-31`, `phase-2-resolve.md:256-270`). The skip-list rule is still needed, but for a different reason: the same PR would be reviewed a second time and logged a second time.
- **Action:** rewrite.

**H2 · `SKILL.source.md:182`, an incomplete defaults list (Group 2)**
- **Problem:** the list omits `autopilot.triage_cache_max_age_minutes: 60` and `autopilot.retriage_every: 0`.
- **Why it matters:** this list is only used when `gi-config.py` can't run ("fill missing keys from the defaults below"). In that case Step 1.1a's cache check (`phase-1-triage-pick.md:53`) and the re-triage check at the top of Phase 1 would have no stated default. `docs/config-schema.md:340,343` defines both keys.
- **Action:** rewrite (add the two keys).

**H3 · `SKILL.source.md:308`, two versions of one message (Group 2)**
- **Text:** "`⚠ BLOCKED — PR #{pr_number} cannot merge until dependency #{N} is merged`"
- **Why it's wrong:** the full message, in `error-messages.md:494` and `phase-5-merge.md:231`, reads "`… until PR #{dep_pr_1} (closing #{dep_n1}) is merged`", and `examples.md:411` follows the full version. CLAUDE.md says every other mention of a safety rule must match the full statement exactly.
- **Action:** rewrite to match.

**H4 · `references/phases/phase-3-4-review.md:7`, describes a past version (Group 1)**
- **Text:** "This replaces the former inline review-fix loop with a more comprehensive pipeline that includes CI status monitoring."
- **Why it's a problem:** it compares against a version the runtime agent never saw, which can send it looking for a "former" loop. CLAUDE.md's *Describe current behaviour as the only behaviour* rule forbids exactly this.
- **Action:** remove the sentence.

### Medium confidence

**M1 · `references/phases/phase-2-resolve.md:276` (Group 1, text that compares versions)**
- **Text:** "(an older resolver, or a PR it could not identify)"
- **Why:** the skill's `compatibility` field requires the resolver to come from the same distribution, so "an older resolver" points at something that shouldn't exist.
- **Action:** rewrite.

**M2 · `references/phases/phase-1-triage-pick.md:208` (Group 1, describes history)**
- **Text:** "carries neither a GitHub `state` nor an `assignees` field, and never did"
- **Action:** rewrite (drop "and never did").

**M3 · `references/explicit-list-mode.md:213` (Group 1, compares versions)**
- **Text:** "they degrade to exactly what they were before: in-memory sets"
- **Why:** "before" here refers to an earlier implementation.
- **Action:** rewrite.

**M4 · `references/phases/phase-5-merge.md:524` (Group 1, compares versions)**
- **Text:** "use the original stash-first sync below byte-for-byte"
- **Why:** CLAUDE.md names "the original path" as a forbidden phrase. The repo's own wording check in `tests/test-runtime-text-history-628.sh:96` only catches `original (path|in-place|sequential)`, so this one slips past it.
- **Action:** rewrite.

**M5 · `references/phases/phase-5-merge.md:216`, a pinned tool version (Group 2)**
- **Text:** "unavailable on older `gh` versions (pre-2.45)"
- **Why:** CLAUDE.md says skill text names no tool versions. The condition that actually matters is that the field didn't come back.
- **Action:** rewrite.

**M6 · `references/phases/phase-3-4-review.md:125` and `references/phases/phase-5-merge.md:136`, pointers that don't resolve (Group 2)**
- **Text:** "SPEC §2 requires these checks…" and "(SPEC §2 MUST-ignore for cross-repo)"
- **Why:** `SPEC.md` sits at the repository root and is not bundled into the skill, so the agent can't open it. Both rules are already stated in full where they're cited, so the pointer adds nothing the agent can use.
- **Action:** rewrite both.
- **Note:** other skills cite `SPEC §` in the same way, and `tests/test-issue-resolver-0d-security.sh` pins one of those. That's outside this scope.

**M7 · `references/phases/phase-0-lock-resume.md:114`, a vague pointer (Group 2)**
- **Text:** "(`references` in `/issue-resolver` → *Step 3 — Propose relevant skills* → *Teardown*)"
- **Why:** it names a directory, not a file. The section actually lives in `issue-resolver/references/steps/step-3-implement.md:7,202`.
- **Action:** rewrite.

**M8 · `references/phases/phase-1-triage-pick.md:440`, a note for maintainers inside the bundle (Group 2)**
- **Text:** "so a new skip-list writer adds a row here"
- **Conflict:** CLAUDE.md says notes to a future maintainer go in `docs/DEVELOPMENT.md` or `tests/`, never in the bundle. Git history puts that rule (`74a4977`, 2026-11-16) after the note (`042099d`, 2026-08-10).
- **Action:** move the note into the comment above test T11.29b, which currently pins it, and drop the T11.29b check.
- **Needs your confirmation:** it's an edit to resolve a conflict between two instruction files.

### Low confidence (no edit proposed)

- **`references/spawning.md:3` — "CRITICAL — never set `subagent_type`".** This emphasis is the justified kind: it targets one known failure and gives the error that failure produces. Two tests also pin it on purpose (`test-agent-overrides-455.sh:209`, `test-spawn-by-path-611.sh:79`). I'd keep it.
- **More argument written for maintainers.** These passages make the case to whoever edits the file rather than telling the agent what to do. Low value per agent run, but not harmful:
  - `phase-1-triage-pick.md:19` ("which is what `references/configuration.md` claims")
  - `phase-1-triage-pick.md:30-35` (why the step is "lettered onto *Step 1.1*", pinned by T13.11)
  - `phase-5-merge.md:619-620`, `639-641` and `699-700`
- **Summaries of another skill's pipeline.** `prompts/reviewer.md:13-22` and `phase-3-4-review.md:9-19` restate what `/issue-pr-review` does. They match it in substance. They leave out that the `light` profile and a trusted QA handoff cap review at one cycle, but "repeat up to N" still holds. Duplicates that agree are fine.
- **Ordering done by the model.** `prompts/analyzer.md:37-40` has the model sort issues into dependency order, which is mechanical work code could do. Moving it would mean writing a new script, and the lists are small, so the risk is low.
- **Unclear who restores the stash.** `SKILL.source.md:164` says "`git stash pop` after the run" (the skill does it), while `preflight.md:333-335` says the stash "can be restored with `git stash pop`" (the user can do it). The repository doesn't show which is intended, so you'd need to decide.
- **The repo's wording check has gaps.** `tests/test-runtime-text-history-628.sh` doesn't catch "former", "and never did", "what they were before", "an older …" or "pre-X.Y". Widening it is outside this audit.

---

## Proposed diff

Every hunk below falls under Group 2's "proposed only" rule, M8 especially, so apply only what you agree with. After any edit to `src/`, rebuild with `bash scripts/build.sh --out <tmp-dir> --quiet` and run the suite (`git ls-files 'tests/*.sh' | xargs -n1 bash`). Don't hand-edit `skills/`.

```diff
# H1
--- a/src/skills/auto-pilot/references/phases/phase-5-merge.md
+++ b/src/skills/auto-pilot/references/phases/phase-5-merge.md
@@ -254 +254 @@
-Before advancing, add `#{issue_number}` to the **session skip list** — the same in-memory list Phase 2.3 uses for failed issues. This is required, not cosmetic: when the dependency issue is `CLOSED` but its PR is still `OPEN` (the race case the gate treats as unsatisfied), Phase 1's triage graph sees the dependency as done and would re-pick `#{issue_number}` on the next iteration; the resolver would then abort on its "PR already targets this issue" guard and the run log would gain a second, bogus `failed` line for an issue that was already recorded. Skipping it ...
+Before advancing, add `#{issue_number}` to the **session skip list** — the same in-memory list Phase 2.3 uses for failed issues. This is required, not cosmetic: when the dependency issue is `CLOSED` but its PR is still `OPEN` (the race case the gate treats as unsatisfied), Phase 1's triage graph sees the dependency as done and would re-pick `#{issue_number}` on the next iteration; the resolver would then report `pr_in_progress` for the open PR, the loop would review and gate that same PR a second time, and the run log would gain a second line for an issue that was already recorded. Skipping it ...
```
(The line continues unchanged after "Skipping it".)

```diff
# H2
--- a/src/skills/auto-pilot/SKILL.source.md
+++ b/src/skills/auto-pilot/SKILL.source.md
@@ -182 +182 @@
-... · `autopilot.respect_dependencies: true` · `autopilot.quarantine_after: 3` · ...
+... · `autopilot.respect_dependencies: true` · `autopilot.triage_cache_max_age_minutes: 60` · `autopilot.retriage_every: 0` (never) · `autopilot.quarantine_after: 3` · ...
```
(Only this part of the long defaults line changes.)

```diff
# H3
--- a/src/skills/auto-pilot/SKILL.source.md
+++ b/src/skills/auto-pilot/SKILL.source.md
@@ -308 +308 @@
-| PR blocked by an unmerged dependency | `⚠ BLOCKED — PR #{pr_number} cannot merge until dependency #{N} is merged` (`blocked_by_dependency`, *loop continues*) |
+| PR blocked by an unmerged dependency | `⚠ BLOCKED — PR #{pr_number} cannot merge until PR #{dep_pr_1} (closing #{dep_n1}) is merged` (`blocked_by_dependency`, *loop continues*) |
```

```diff
# H4
--- a/src/skills/auto-pilot/references/phases/phase-3-4-review.md
+++ b/src/skills/auto-pilot/references/phases/phase-3-4-review.md
@@ -7 +7 @@
-After the PR is created, the auto-pilot delegates review, testing, CI checking and fixing to the `/issue-pr-review` skill, run as `--auto --no-merge`; the merge itself is Phase 5's. This replaces the former inline review-fix loop with a more comprehensive pipeline that includes CI status monitoring.
+After the PR is created, the auto-pilot delegates review, testing, CI checking and fixing to the `/issue-pr-review` skill, run as `--auto --no-merge`; the merge itself is Phase 5's.
```

```diff
# M1
--- a/src/skills/auto-pilot/references/phases/phase-2-resolve.md
+++ b/src/skills/auto-pilot/references/phases/phase-2-resolve.md
@@ -276,2 +276,2 @@
-If the report-back carries no `pr_number` (an older resolver, or a PR it could
-not identify), there is nothing to review: record `skipped` with
+If the report-back carries no `pr_number` (the resolver could not identify the
+PR), there is nothing to review: record `skipped` with
```

```diff
# M2
--- a/src/skills/auto-pilot/references/phases/phase-1-triage-pick.md
+++ b/src/skills/auto-pilot/references/phases/phase-1-triage-pick.md
@@ -207,2 +207,2 @@
 **Not assigned** — are answers only GitHub holds: `.idd/triage.json` carries
-neither a GitHub `state` nor an `assignees` field, and never did. Evaluating them
+neither a GitHub `state` nor an `assignees` field. Evaluating them
```

```diff
# M3
--- a/src/skills/auto-pilot/references/explicit-list-mode.md
+++ b/src/skills/auto-pilot/references/explicit-list-mode.md
@@ -212,3 +212,3 @@
 mid-batch does not re-resolve issues that already landed. When `gi-state.py` is
-unavailable they degrade to exactly what they were before: in-memory sets that
-do not survive the run.
+unavailable they stay in-memory sets that do not survive the run.
```

```diff
# M4
--- a/src/skills/auto-pilot/references/phases/phase-5-merge.md
+++ b/src/skills/auto-pilot/references/phases/phase-5-merge.md
@@ -523,3 +523,3 @@
 When the PR did not merge (`left_open`, `blocked_by_dependency`, `failed`),
-or as the degrade path above, use the original stash-first sync below
-byte-for-byte to protect any uncommitted changes that may have accumulated
+or as the degrade path above, run the stash-first sync below
+exactly as written to protect any uncommitted changes that may have accumulated
```

```diff
# M5
--- a/src/skills/auto-pilot/references/phases/phase-5-merge.md
+++ b/src/skills/auto-pilot/references/phases/phase-5-merge.md
@@ -216 +216 @@
-For each unsatisfied dependency, record `{issue_number, issue_title, issue_state, pr_number, pr_state}` for the alert. If `closedByPullRequestsReferences` is unavailable on older `gh` versions (pre-2.45), fall back to:
+For each unsatisfied dependency, record `{issue_number, issue_title, issue_state, pr_number, pr_state}` for the alert. If the read does not return `closedByPullRequestsReferences` (the installed `gh` does not know the field), fall back to:
```

```diff
# M6a
--- a/src/skills/auto-pilot/references/phases/phase-3-4-review.md
+++ b/src/skills/auto-pilot/references/phases/phase-3-4-review.md
@@ -125 +125 @@
-... against the current PR head. SPEC §2 requires these checks before **any** automated merge, including partial merges. The CI gate ...
+... against the current PR head. These checks run before **any** automated merge, including partial merges. The CI gate ...
```

```diff
# M6b
--- a/src/skills/auto-pilot/references/phases/phase-5-merge.md
+++ b/src/skills/auto-pilot/references/phases/phase-5-merge.md
@@ -136 +136 @@
-For each line that matches `(?im)\b(?:depends\s+on|blocked\s+by)\b`, collect **local** issue numbers only (SPEC §2 MUST-ignore for cross-repo):
+For each line that matches `(?im)\b(?:depends\s+on|blocked\s+by)\b`, collect **local** issue numbers only (a cross-repo reference never gates a merge):
```

```diff
# M7
--- a/src/skills/auto-pilot/references/phases/phase-0-lock-resume.md
+++ b/src/skills/auto-pilot/references/phases/phase-0-lock-resume.md
@@ -113,3 +113,3 @@
 lists any `origin: borrowed` entries, run the resolver's
-teardown (`references` in `/issue-resolver` → *Step 3 — Propose relevant
-skills* → *Teardown*): uninstall only those names from `~/.claude/skills/`,
+teardown (`/issue-resolver`'s `references/steps/step-3-implement.md` →
+*Step 3 — Propose relevant skills* → *Teardown*): uninstall only those names from `~/.claude/skills/`,
```

```diff
# M8 (move the maintainer note into the test that enforces the invariant)
--- a/src/skills/auto-pilot/references/phases/phase-1-triage-pick.md
+++ b/src/skills/auto-pilot/references/phases/phase-1-triage-pick.md
@@ -439,2 +439,2 @@
 counts summing to the candidates Step 1.2 rejected. A reason with no bucket would
-break that sum silently, so a new skip-list writer adds a row here. Omit the
+break that sum silently. Omit the
--- a/tests/test-autopilot-triage-cache-258.sh
+++ b/tests/test-autopilot-triage-cache-258.sh
@@ -797,3 +797,4 @@
 # G3 — Step 1.2's four buckets are stated to always sum to the rejected
 # candidates, so a skip-list writer with no bucket breaks that sum silently.
-# Step 1.2b became the third writer.
+# Step 1.2b is the third writer. A new skip-list writer adds a row to that
+# table (maintainer rule; kept here, out of the runtime bundle).
@@ -814,2 +815,0 @@
-check_block_has "$PICK_BLOCK" 'a new skip-list writer adds a row here' \
-  "T11.29b: the table states what a future skip-list writer owes the invariant"
```

None of H1–M7 removes a phrase the tests pin; I searched `tests/` for each one. M8 removes a pinned phrase, so its hunk includes the test change.
