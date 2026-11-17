# Prompt audit: `src/internal-skills/idd-doctor`

**What I assumed:**
- **Scope:** `SKILL.source.md` plus the three authored files in `references/`. I left out three files: `LICENSE`, `docs/README.md` (a human-only README that is never loaded at runtime) and the shared `run-stats.md` and `self-improve.md`, which are authored elsewhere. Nothing calls a non-Anthropic provider.
- **Target model:** no file pins a model, so I audited against the model running this audit, Claude Opus 5.5.

**Files read:** `SKILL.source.md` (352 lines), `references/error-messages.md` (224), `references/review-contract.md` (69), `references/run-log-summary.md` (64).

I checked every repo path the files name, and they all exist: `SPEC.md` §1.2 and §4.3 B1/B2, `DESIGN.md`, `docs/config-schema.md`, `docs/run-log-schema.md`, `docs/platform-github.md`, `docs/correction-guards.md`, `scripts/build.sh` and its usage, and `tests/test-idd-doctor.sh`. I also checked the run-log fields and outcome values.

## Summary

The prompt text is clean. Every `MUST` comes with a reason, the fragile check algorithms are rightly written as exact steps, and the trigger text is fine. The real problems are statements the repository now contradicts:

- **The review contract points at a warn line that no longer exists.** `review-contract.md:36` cites Check 4's "unreadable-source warn line". Commit `938a270` (#564) removed it ("Warn — message source unreadable"), so the `check 4 binding unverified` item no longer has a trigger.
- **The Configuration section says the doctor reads one config key; it reads three.** `SKILL.source.md:80` says `.idd.yml` is read only for `autopilot.mode`, but Check 4 also reads `review.merge_method` and `review.auto_merge` (line 239).
- **The files describe their behaviour against other versions.** Phrases like "v1", "a future v2", "the **old** behavior", "existing", "additive" and "no new dependency" describe a version the runtime agent never sees. `CLAUDE.md` forbids this ("Describe current behaviour as the only behaviour").

**Count by group:**

| Group | Count |
|---|---|
| 1 (dated text) | 3 |
| 2 (brittle config/skill files) | 10 (4 high, 4 medium, 2 flag) |
| 3 (tool descriptions) | 0 |
| 4 (request config) | not applicable (no request code) |
| Low-confidence flag | 1 |

## Findings

| # | Location | Evidence | Pattern | Why it's wrong | Conf. | Action |
|---|---|---|---|---|---|---|
| 1 | `references/review-contract.md:36` | "`check 4 binding unverified` when Check 4 printed its unreadable-source warn line" | 2: Volatile specifics (pointer doesn't resolve) | `938a270` removed *Warn — message source unreadable*. An unread message source now prints *Warn — hand merge* with `{value}` = `unread` (`error-messages.md:161,165`). | High | rewrite |
| 2 | `SKILL.source.md:80` | "reads `.idd.yml` only to determine whether Check 3's `autopilot.mode` is set" | 2: Volatile specifics | Contradicted by Check 4 step 1 (line 239), which reads `review.merge_method` and `review.auto_merge`. | High | rewrite |
| 3 | `references/review-contract.md:3-4` | "It defines the four rows that follow the `Result:` line" | 2: Files contradict each other | The same file says "Print these three rows directly under the `Result:` line" (line 9). Blame shows line 3 is from `b798d1d1` and line 4 from `7304ca31` (today). | High | rewrite |
| 4 | `SKILL.source.md:344` | "`{symbol} [N/4] {Check name (16 chars)} {detail}`" | 2: Volatile specifics | The check names are 12–21 characters, and every example pads them to a 22–23 column. No 16-character field exists. | High | rewrite (point to the catalog) |
| 5 | `SKILL.source.md:23, 26, 40, 80, 221, 349, 350` | "v1 is **report-only**", "## Scope (v1)", "out of scope for v1", "in v1", "a future v2 may validate values", "v1 is mechanically strict" | 1d: Migration-relative phrasing | These invent a v2 for the agent to look for. No test pins these headings (the test at `test-idd-doctor.sh:639` checks `docs/README.md`, not the skill). | Medium | rewrite |
| 6 | `SKILL.source.md:133` | "The forbidden patterns describe the **old** behavior where the creator allegedly inspected the codebase" | 2: History narrative | The rule's authority is the contract, not a past behaviour. | Medium | rewrite |
| 7 | `SKILL.source.md:142` | "Add a future intent-only skill's files here explicitly; mechanical "scan all skills" matching is deliberately avoided in v1." | 2: Maintainer material in the bundle | This is a note to a future maintainer, read on every run. The sentence before it already gives the runtime reason. | Medium | remove |
| 8 | `SKILL.source.md:92, 332, 336-338` | "(verify against this when testing)", "Test fixtures (see *Testing*) assert…", the `## Testing` section | 2: Maintainer material in the bundle | Describes the test suite, which the runtime agent should not act on. `docs/DEVELOPMENT.md:263` already covers testing. | Medium | move to `docs/README.md` |
| 9 | `references/review-contract.md:20-21, 23` | "The rows are additive human-facing output", "The existing `Result:` line" | 1d: Migration-relative phrasing | "additive" and "existing" compare against a footer the agent never saw. | Medium | rewrite |
| 10 | `references/error-messages.md:5` | "…is the gap that contract exists to close… which is the contract working, not a hole in it" | 2: History narrative / 1c padding | Argues with a past reviewer instead of stating the rule. The rule itself is also stated at `SKILL.source.md:68,314`. | Medium | rewrite |
| 11 | `references/run-log-summary.md:59` | "(no new dependency — `tail` plus a JSON-aware pass)" | 1d: Migration-relative phrasing | "new" relative to an unstated baseline. `CLAUDE.md` names this exact example. | Medium | rewrite |
| 12 | `SKILL.source.md:344` and `error-messages.md:159,165-166` | "≤80 chars" vs Check 4 lines of about 95–135 characters | 2: Files contradict each other | `DESIGN.md:117` says "Max width: 80 characters (truncate with `...`)". The Check 4 catalog lines break it. Fixing it means wrapping, shortening or exempting these lines, which is a design choice. | High (conflict) | flag |
| 13 | `SKILL.source.md:107-108`, `error-messages.md:128-186` | `Merge method           ` is padded to 23 columns; the other three checks use 22 | 2: Volatile specifics | Cosmetic. `test-squash-binding-295.sh` and others may pin the exact string, so check before changing it. | Low | flag |
| 14 | `SKILL.source.md:18-24` | "**Do** wire it into pre-merge or pre-release checks." | Idiom: human advice in the agent body | The agent can't act on it, and routing belongs in `description`. No pattern documents harm here. | Low | flag |

Not flagged: the `Interactive report: not applicable` stanza. The same convention appears in four other skills, so it is working redundancy.

## Proposed diff

These are proposals only, not applied. The edits under findings 1–4 come from Group 2 rows, so confirm them yourself before applying. No test pins any of the edited phrases. After applying, rebuild with `bash scripts/build.sh --out <tmp> --quiet` and run `bash tests/test-idd-doctor.sh`.

```diff
# Finding 1 — review-contract.md
@@ -36,2 +36,2 @@
-   - `check 4 binding unverified` when Check 4 printed its unreadable-source
-     warn line.
+   - `check 4 binding unverified` when Check 4 printed *Warn — hand merge*
+     with `{value}` `unread`.
```

```diff
# Finding 2 — SKILL.source.md
@@ -80 +80 @@
-This skill **reads** `.idd.yml` only to determine whether Check 3's `autopilot.mode` is set (that field is documented in `docs/config-schema.md`); it is otherwise config-free, with no `doctor:` section and no per-check toggles in v1.
+This skill **reads** three `.idd.yml` keys, all documented in `docs/config-schema.md`: `autopilot.mode` (Check 3), and `review.merge_method` and `review.auto_merge` (Check 4). It has no `doctor:` section and no per-check toggles.
```

```diff
# Finding 3 — review-contract.md
@@ -3,2 +3,2 @@
-Read this before printing the *Summary footer*. It defines the four rows that
-follow the `Result:` line and the format rule. The doctor is report-only: it
+Read this before printing the *Summary footer*. It defines the three rows that
+follow the `Result:` line and the format rule. The doctor is report-only: it
```

```diff
# Finding 4 — SKILL.source.md
@@ -344 +344 @@
-... Per-check line: `{symbol} [N/4] {Check name (16 chars)} {detail}`; per-finding indent 8 spaces (4 + 4). ...
+... Per-check line: `{symbol} [N/4] {Check name} {detail}`, with the check name padded exactly as in `references/error-messages.md`; per-finding indent 8 spaces (4 + 4). ...
```

```diff
# Finding 5 — SKILL.source.md (version-relative phrasing)
@@ -23 +23 @@
-- **Avoid** running it as a fix tool — v1 is **report-only**: no file modified, no issue commented on, no PR created.
+- **Avoid** running it as a fix tool — it is **report-only**: no file modified, no issue commented on, no PR created.
@@ -26 +26 @@
-## Scope (v1)
+## Scope
@@ -40 +40 @@
-### Explicitly out of scope for v1
+### Out of scope
@@ -221 +221 @@
-3. Look for a line matching `^[[:space:]]+mode:[[:space:]]*[^#[:space:]]+` inside an `autopilot:` block. Any non-empty value matches; the value is not validated in v1. Equivalent shell heuristic:
+3. Look for a line matching `^[[:space:]]+mode:[[:space:]]*[^#[:space:]]+` inside an `autopilot:` block. Any non-empty value matches; the value is not validated. Equivalent shell heuristic:
@@ -349,2 +349,2 @@
-- **`autopilot.mode` set to a non-canonical value** (e.g. `mode: yolo`) — Check 3 still passes; any non-empty value satisfies "key set", and a future v2 may validate values.
-- **A skill README carries a forbidden pattern inside a code block or fenced quote** — Check 1 still flags it; v1 is mechanically strict, not contextually nuanced.
+- **`autopilot.mode` set to a non-canonical value** (e.g. `mode: yolo`) — Check 3 still passes; any non-empty value satisfies "key set".
+- **A skill README carries a forbidden pattern inside a code block or fenced quote** — Check 1 still flags it; the match is mechanically strict, not contextually nuanced.
```

```diff
# Finding 6 — SKILL.source.md
@@ -133 +133 @@
-Scan the `/issue-creator` skill's `README.md` and `SKILL.md` for stale claims about its own scope. The forbidden patterns describe the **old** behavior where the creator allegedly inspected the codebase; the intent-only contract (SPEC.md §1.2 intent–code boundary) forbids them.
+Scan the `/issue-creator` skill's `README.md` and `SKILL.md` for claims that the creator inspects the codebase. The intent-only contract (SPEC.md §1.2 intent–code boundary) forbids such claims.
```

```diff
# Finding 7 — SKILL.source.md
@@ -142 +142 @@
-... or another skill's files. Add a future intent-only skill's files here explicitly; mechanical "scan all skills" matching is deliberately avoided in v1.
+... or another skill's files.
```

```diff
# Finding 8 — SKILL.source.md (move test notes out of the bundle)
@@ -92 +92 @@
-Expected output for a clean repo (verify against this when testing):
+Expected output for a clean repo:
@@ -332 +332 @@
-It reads files (via `Read` / `cat`) and runs read-only `gh` queries (`gh repo view --json …`, `gh api repos/{owner}/{repo}`, `gh auth status`). Test fixtures (see *Testing*) assert the working tree is unchanged after a doctor run.
+It reads files (via `Read` / `cat`) and runs read-only `gh` queries (`gh repo view --json …`, `gh api repos/{owner}/{repo}`, `gh auth status`).
@@ -334,7 +334,1 @@
 ---
-
-## Testing
-
-`tests/test-idd-doctor.sh` (pure bash, exit 0 on pass) asserts this spec against itself — structure, both pattern catalogs, check order, read-only guarantee, `gh` field selections, skips, exit codes, and the run-log summary. Run `bash tests/test-idd-doctor.sh`.
-
----
# src/internal-skills/idd-doctor/docs/README.md — add under ## Resources:
+- `tests/test-idd-doctor.sh` asserts the spec (structure, pattern catalogs, check order, read-only guarantee, `gh` fields, skips, exit codes, run-log summary): `bash tests/test-idd-doctor.sh`.
```

```diff
# Finding 9 — review-contract.md
@@ -19,5 +19,5 @@
 The `Result:` line itself stays the one line a wrapper script
-greps (see *Exit codes* in SKILL.md). The rows are additive human-facing
-output and never carry `PASS`, `WARN`, or `FAIL` as a status token.
+greps (see *Exit codes* in SKILL.md). The rows are human-facing output and
+never carry `PASS`, `WARN`, or `FAIL` as a status token.
 
-1. **Result.** The existing `Result:` line states the status first. `PASS`
+1. **Result.** The `Result:` line states the status first. `PASS`
```

```diff
# Finding 10 — error-messages.md
@@ -5 +5 @@
-**A block here that stops the run is followed by the run-stats footer** — see `references/run-stats.md`. A stop is a terminal outcome like any other, and printing the error block and exiting without the footer is the gap that contract exists to close. A stop that happens before the run clock was captured prints `elapsed n/a`, which is the contract working, not a hole in it. A `⚠` block that warns and continues is not a terminal outcome and prints no footer of its own.
+**A block here that stops the run is followed by the run-stats footer** — see `references/run-stats.md`. A stop before the run clock was captured prints `elapsed n/a`. A `⚠` block that warns and continues is not a terminal outcome and prints no footer of its own.
```

```diff
# Finding 11 — run-log-summary.md
@@ -59,2 +59,2 @@
-A read heuristic for the input (no new dependency — `tail` plus a JSON-aware
-pass):
+A read heuristic for the input — `tail` plus a JSON-aware pass, nothing
+beyond the shell:
```

Findings 12–14 are flags only. Finding 12 needs your decision: wrap or shorten the Check 4 catalog lines, or exempt them from `DESIGN.md`'s 80-character rule.
