# Ledger 2: src/shared/agents + src/shared/references (audit2/agents.md)

| # | Location | Finding (short) | Confidence | Outcome | Detail |
|---|---|---|---|---|---|
| 1 | `src/shared/agents/implementer.md:34` | "When the resolver wires this in" implies the repro step is optional | High | fixed | Verified: line 28 of the same file makes Task 1.5 mandatory for every bug. Line 34 → "Skip entirely for feature/improvement. **Before** the fix:". No test pin. |
| 2 | `src/shared/agents/implementer.md:64-66` | "### 7. Track what you did / Keep a running tally" is a redundant strategy tip | Medium | fixed | Removed the heading + line (4 lines). Output section (and line 13 Returns) already defines the summary; no "Task 7" reference anywhere (line 38 "constraint #7" is a different item). `tests/test-run-stats-373.sh:232` "running tally" pins an ADR, not this file. |
| 3 | `src/shared/agents/codebase-researcher.md:84` | "parallel-read when 3+" is a redundant strategy tip | Medium | fixed | Dropped the clause; `max_files` limit kept. No test pin. |
| N1 | `fixer.md:43` vs `implementer.md:62` | Two secret-scan acceptance rules differ | flag | kept | safety gate: needs maintainer decision (same as round-1 #7). |
| N2 | `src/shared/agents/implementer.md:62` | Scan acceptance rule self-contradicts on `scanned: 0, skipped: 0` | flag | kept | safety gate: needs maintainer decision (secret-scan acceptance wording). |
| N3 | `src/shared/agents/synthesizer.md:12` | "presents all three" vs allowed two-option case | flag | kept | Flag-only; fix reaches resolver SKILL text pinned by a test, outside this scope. Candidate: "presents all options" in both, with the pin updated. |
| N4 | `src/shared/agents/ui-reviewer.md:77` | "Prioritize mobile-first issues." has no output hook | flag | kept | Flag-only, intent (severity effect or not) unclear; needs maintainer intent. |
| N5 | line 6 of most agents | Flavour role lines | flag | kept | Audit itself recommends keeping one-line role statements. |
| N6 | `src/shared/references/run-stats.md` | Token-field rule restated ~5 times | flag | kept | All copies agree and are pinned by `tests/test-run-stats-373.sh`; audit guide says keep. |
