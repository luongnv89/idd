# Prompt audit, second pass: `src/internal-skills/idd-doctor`

**Assumptions**
- **Scope:** `SKILL.source.md` and the three files in `references/`, as they stand now, including the uncommitted first-pass edits. I left out `docs/README.md` (it's human-only and carries the do-not-read notice) and `LICENSE`.
- **Target model:** Claude Opus 5.5. The request doesn't name a model, and the skill pins only `effort: low`, so I audited against the model running this audit.

**Summary.** The first pass already removed the "v1" wording and the history phrasing. Two high-confidence defects remain:
- **The negation guard in Check 1 can switch off its own patterns.** The skill says to match negation markers as substrings, and `no` is a substring of "notes". Read that way, the guard suppresses every "…implementation notes" and "…technical notes" claim.
- **A fallback points to a footer shape that isn't there.** The *Run stats footer* section it names describes the footer but never shows it.

There are two medium findings as well: an output example that shows a different number of items than its own rule, and a note written for maintainers rather than for the agent.

Counts:

| Group | Result |
|---|---|
| 1 (dated prompt text) | 1 |
| 2 (brittle skill/config files) | 3 |
| 3 (tool descriptions) | not applicable, no tool definitions |
| 4 (request config) | not applicable, no request-building code |

## Findings

| # | Location | Evidence | Pattern | Why it's wrong | Confidence | Action |
|---|---|---|---|---|---|---|
| 1 | `SKILL.source.md:146` | "no negation marker (`no`, `not`, `never`, …)", under a heading that says "case-insensitive substring match" | G2: wrong degrees of freedom (loose prose for an exact operation) | Three of the skill's own patterns contain "no" ("generates/generated implementation notes", "generated technical notes"), so a literal substring reading can never flag them. `tests/test-idd-doctor.sh:385` treats the markers as words (`"no "`, `"not "`), which disagrees with the skill text. | High | rewrite |
| 2 | `SKILL.source.md:68` | "print those two lines from the shape in *Run stats footer*" | G2: volatile specifics (the pointer doesn't resolve) | The *Run stats footer* section (`:312-314`) only lists the fields. The two-line shape exists only in `references/run-stats.md`, which is the file this fallback assumes is missing. | High | rewrite (show the lines inline) |
| 3 | `references/run-log-summary.md:47` | `Top skip reasons: {reason1} ({c1}), {reason2} ({c2})` | G1c: the model copies its examples | The rule at `:18` says top 3. The model copies the length of examples, so it will tend to print two. | Medium | rewrite |
| 4 | `references/review-contract.md:66-69` | "**Interactive report: not applicable.** The doctor emits at most four check lines…" | G1c padding / G2 maintainer material in the bundle | It explains a design choice to a reviewer and gives the agent nothing to do. The *Format rule* bullets just above it (`:55-64`) already cover the default layout and unsupported formats. No test or `VALUES.md` item depends on it. | Medium | remove |

## Proposed diff (not applied)

```diff
--- a/src/internal-skills/idd-doctor/SKILL.source.md
+++ b/src/internal-skills/idd-doctor/SKILL.source.md
@@ -146 +146 @@
-A line **fails** if it contains any pattern below **and** no negation marker (`no`, `not`, `never`, `does not`, `doesn't`, `without`, `cannot`, `won't`).
+A line **fails** if it contains any pattern below **and** no negation marker as a whole word (`no`, `not`, `never`, `does not`, `doesn't`, `without`, `cannot`, `won't`). Only the forbidden patterns match as substrings; a marker inside another word (the `no` in "notes") does not count.
```

```diff
--- a/src/internal-skills/idd-doctor/SKILL.source.md
+++ b/src/internal-skills/idd-doctor/SKILL.source.md
@@ -68 +68,7 @@
-That stop is a terminal outcome: print the block, then the *Run Stats Footer* (`references/run-stats.md`), then stop. It runs before the clock capture in *Pipeline*, so there is no `run_started_epoch` and `elapsed` prints the literal `n/a`, with `agents 0`. If `references/run-stats.md` is itself the missing file, print those two lines from the shape in *Run stats footer*.
+That stop is a terminal outcome: print the block, then the *Run Stats Footer* (`references/run-stats.md`), then stop. It runs before the clock capture in *Pipeline*, so there is no `run_started_epoch` and `elapsed` prints the literal `n/a`, with `agents 0`. If `references/run-stats.md` is itself the missing file, print these two lines:
+
+```text
+  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
+  Run stats   elapsed n/a · agents 0
+```
```

```diff
--- a/src/internal-skills/idd-doctor/references/run-log-summary.md
+++ b/src/internal-skills/idd-doctor/references/run-log-summary.md
@@ -47 +47 @@
-        Top skip reasons: {reason1} ({c1}), {reason2} ({c2})
+        Top skip reasons: {reason1} ({c1}), {reason2} ({c2}), {reason3} ({c3})
```

```diff
--- a/src/internal-skills/idd-doctor/references/review-contract.md
+++ b/src/internal-skills/idd-doctor/references/review-contract.md
@@ -64,6 +64,0 @@
   limitation, then print the default terminal layout.
-
-**Interactive report: not applicable.** The doctor emits at most four check
-lines plus their findings and one summary section. A reader inspects the whole
-report without filtering, and every finding already carries its
-`{path}:{line_number}` source.
```

None of these hunks changes text the tests check: `T4` only looks for the phrase "negation guard", and nothing checks the footer fallback, the skip-reasons example line or the interactive-report paragraph. After editing `src/`, rebuild `skills/`.

## Flag-only notes (no edit proposed)

- **Column alignment:** "Merge method" is padded one space wider than the other three check names (`SKILL.source.md:108`, `error-messages.md:128-186`). The skill now says to pad "exactly as in" `error-messages.md`, so the agent copies the misalignment. It's cosmetic.
- **Redundant Check 2 pattern:** the `predicted affected files` row (`SKILL.source.md:192`) is already caught by `affected files` under substring matching, so one template line can count twice toward `{K}`. It's minor, and removing it wouldn't break `T5`.
- **Schema field list:** the restated run-log fields (`SKILL.source.md:291-292`) leave out the required `skill` field. "At least" keeps the sentence true; a plain pointer to `docs/run-log-schema.md` would be sturdier.
- **When to Use:** these bullets (`:20-24`) speak to the person invoking the skill, not to the agent running it. Low confidence.
- **Deterministic work done by the model:** Checks 1–3 and the run-log medians are fully deterministic, so a shared script would be more reliable than having the model match text and compute medians by hand. That's an architecture decision for you, so I haven't proposed a diff.
