# Ledger: src/skills/issue-analysis

| # | Location | Finding (short) | Confidence | Outcome | Detail |
|---|---|---|---|---|---|
| 1 | references/output-and-persist.md:25-30 | "Concise summary + static table" default contradicts Step 8 full sections / examples.md | High | fixed | Replaced the 6-line default paragraph with "Render the Step 8 sections below in order." plus the retained requested-format and `Saved:` rules (output-and-persist.md:25-27). |
| 2 | SKILL.source.md:378-399 | *Expected Output* block is a third report shape (lowercase `medium`, different tracker counts) | High | fixed | Replaced the code block with one sentence pointing to the `[N/8]` tracker, Step 8 report, save line, *Final Report* and `references/examples.md` (SKILL.source.md *Expected Output*). |
| 3 | SKILL.source.md:324 | "nothing else changes" compares against a past version | High | fixed | Now "Exact schema and rendering, including the report's *Decision Record* section: `references/output-and-persist.md`." |
| 4 | SKILL.source.md:365 | `DONE (verify if already resolved)` drifted from subagent-steps.md:32 | High | fixed | Changed to `DONE (verify already resolved)`; no test pins the old string. |
| 5 | references/inline-fallback.md:291 | "cover a spectrum… one larger structural change" pushes invented options | High | fixed | Now "Make each approach genuinely distinct. One justified option is valid; never invent alternatives to fill the 2-3 slots." (matches the Validate analysis data rule). |
| 6 | references/inline-fallback.md:44 | "most thorough scan… more than issue-resolver" booster | Medium | fixed | Sentence removed. |
| 7 | SKILL.source.md:281 | Shouted "Unlike issue-resolver… does NOT stop" | Medium | fixed | Now "Print the warning and continue: reviewing what was done is a valid use of analysis." |
| 8 | references/error-messages.md:105 | Corrupted-file trigger omits validation failure | Medium | fixed | Trigger now "finds the file but it does not parse or fails *Validate analysis data* (`references/output-and-persist.md`)", matching SKILL.source.md view-mode step 4. |
| 9 | output-and-persist.md `reproduction` rows | Schema rows for a field no skill writes | Low | kept | Low/flag-only; cross-skill contract with /issue-resolver and pinned by tests/test-issue-analysis.sh — maintainer call. |
| 10 | SKILL.source.md:287-293 | Keyword table for type classification | Low | kept | Low/flag-only; deterministic fallback, cheap, no contradiction. |
| 11 | SKILL.source.md:27,214,308-311; output-and-persist.md:3 | "Step 8-9"/"persist step" naming vs `[N/8]` counter | Low | kept | Low/flag-only; heading rename risks test pins and cross-skill references. |
| 12 | references/subagent-steps.md:40 | Ambiguous "It performs keyword extraction" | Low | kept | Low/flag-only; meaning recoverable from section context. |
| 13 | SKILL.source.md:256 | gi-gh.py sentence splits "run:" from its command | Low | kept | Low/flag-only; no wrong instruction. |
| 14 | inline-fallback.md:271 vs subagent-steps.md:85 | Different `[6/8]` tracker wording per path | Low | kept | Low/flag-only; both are valid ✓ lines, cosmetic. |
| 15 | output-and-persist.md:276-281 | decision_record lift better as a script | Low | kept | needs new script: follow-up. |
| 16 | src/shared/agents/synthesizer.md:13,18 | "2–3 ranked options" conflicts with one-option rule | Low | out-of-scope | Low/flag-only and outside target. Suggested edit if wanted: synthesizer.md, "2–3 ranked options" → "1–3 ranked options (one justified option is valid; never invent alternatives)". Not verified in detail; orchestrator to decide. |
