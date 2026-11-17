I found three edits worth making in `src/shared/agents/` and none in `src/shared/references/`. Nothing has been changed; the diff below is proposed only.

**Assumptions**
- **Scope:** the 9 files in `src/shared/agents/` and the 2 in `src/shared/references/`, read in their current state, including the uncommitted edits from the first pass. The shared-agent conventions that the build adds to each agent come from `docs/shared-agent-conventions.md`, which is outside this scope.
- **Target model:** Claude Opus 5.5. None of these files names a model, because the calling skill picks a size (S, M or L) at run time.

**Summary:** The most important finding is a stale condition in the implementer. It suggests the bug-reproduction step is optional, but every bug issue runs it. The other two are small strategy tips that tell the model nothing it doesn't already do. Counts by group: dated prompt text 2 · skill and config files 1 · tool descriptions not applicable (none in scope) · request config and architecture not applicable (no request-building code; the reviewer, judge and fixer agents each do a different job, so none is redundant).

## Findings

| # | Location | Text | Pattern | Why it should change | Confidence | Action |
|---|---|---|---|---|---|---|
| 1 | `src/shared/agents/implementer.md:34` | "When the resolver wires this in, **before** the fix:" | Stale fact; wording that compares against an old version | The resolver runs this step on every bug issue (`src/skills/issue-resolver/SKILL.source.md:299`, `references/bug-verification.md:17`), and line 28 of the same file says the same. The condition hints at a way to switch the step off that doesn't exist. | High (the repo contradicts it) | rewrite → "**Before** the fix:" |
| 2 | `src/shared/agents/implementer.md:64-66` | "### 7. Track what you did / Keep a running tally for the summary." | Strategy tip next to the task rules | Deleting it changes nothing the agent must do or how its work is judged, because the Output section already sets the summary. No file refers to "Task 7". (Constraint #7 is a different item.) | Medium | remove |
| 3 | `src/shared/agents/codebase-researcher.md:84` | "parallel-read when 3+" | Strategy tip next to the task rules | Current models already read files in parallel without being told. The limit on how many files to read stays in the same sentence. | Medium | remove the clause |

No test checks any of the three phrases (I searched `tests/*.sh` for each).

## Proposed diff

```diff
--- a/src/shared/agents/implementer.md
+++ b/src/shared/agents/implementer.md
@@ -34 +34 @@
-Skip entirely for feature/improvement. When the resolver wires this in, **before** the fix:
+Skip entirely for feature/improvement. **Before** the fix:
```

```diff
--- a/src/shared/agents/implementer.md
+++ b/src/shared/agents/implementer.md
@@ -63,6 +63,2 @@
-### 7. Track what you did
-
-Keep a running tally for the summary.
-
 ## Output
```

```diff
--- a/src/shared/agents/codebase-researcher.md
+++ b/src/shared/agents/codebase-researcher.md
@@ -84 +84 @@
-- **2b:** rank `critical` (direct path match) / `high` (keyword + import link to a critical file) / `medium` (keyword only) / `low` (transitive dep). Read the top `max_files` files; parallel-read when 3+.
+- **2b:** rank `critical` (direct path match) / `high` (keyword + import link to a critical file) / `medium` (keyword only) / `low` (transitive dep). Read the top `max_files` files.
```

If you apply these, rebuild with `bash scripts/build.sh` so the copies under `skills/*/references/agents/` pick them up, then run the test suite.

## Notes only (no edit proposed)

- **The two secret-scan rules differ** (`fixer.md:43` vs `implementer.md:62`). The implementer also checks the `scanned` count against the number of files it staged and prints a `⚠` line when it falls back to the manual scan. The fixer does neither. This is a safety rule, so you decide which version is correct.
- **The implementer's scan rule contradicts itself** (`implementer.md:62`). It warns that `"scanned": 0` checked nothing, then accepts exit 0 unless `scanned` is 0 *and* `skipped` is above 0. So a scan with nothing staged (0 and 0) passes. The "compare against the files you staged" check probably catches this, but the wording is worth tightening.
- **Two options or three** (`synthesizer.md:12`). "The orchestrator presents all three" doesn't fit the two-option case the same file allows. The resolver's own steps also say "presents all three options", and a test checks that phrase, so a fix would reach outside this scope.
- **Vague priority line** (`ui-reviewer.md:77`). "Prioritize mobile-first issues." has nothing in the output format to act on. It's unclear whether it is meant to affect severity.
- **Flavour lines** at line 6 of most agent files (e.g. "Sift tons of ore…"). These are one-line role statements, which the audit guide says to keep.
- **`run-stats.md`** states the token-field rule about five times, but every copy agrees and several are checked by `tests/test-run-stats-373.sh`. The audit guide says to leave copies that agree, so I left them.
