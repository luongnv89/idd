# Ledger (pass 2): src/skills/issue-analysis

| # | Location | Finding (short) | Confidence | Outcome | Detail |
|---|---|---|---|---|---|
| 1 | SKILL.source.md:216 | Progress pointer to *Expected Output* + "updates to ✓" contradicts static output | High | fixed | SKILL.source.md:216 now "one new line per step, `✓` on success or `✗` on failure, in the format `references/examples.md` shows. Lines are printed, never redrawn in place." |
| 2 | SKILL.source.md:192, :304 | "tool budgets" absent from subagent-steps.md | High | fixed | :192 → "subagent delegation payloads and return handling"; :304 → "the delegation payloads and the return handling every run needs". Verified: no "budget" in subagent-steps.md. |
| 3 | SKILL.source.md:311 | "color codes" not in output-and-persist.md | High | fixed | Now "(section layout and truncation rules)". Verified: no colour mention in output-and-persist.md. |
| 4 | references/output-and-persist.md:485 | `options[]` "2-3" contradicts single-option rule (:38-39) | High | fixed | Row now "Implementation approaches, usually 2–3; one when only one is justified". |
| 5 | references/subagent-steps.md:76 | "(or collected inline in Steps 2-5)" unreachable branch | Medium | fixed | Parenthetical removed; synthesizer is only spawned on the subagent path. |
| F1 | src/shared/agents/synthesizer.md:13,18; subagent-steps.md:80 | Synthesizer requires 2–3 options vs one-option rule | flag | out-of-scope | Proposed: synthesizer.md "2–3 ranked options" → "1–3 ranked options (one justified option is valid; never invent alternatives)"; then subagent-steps.md:80 "proposes 2-3 implementation options" → "proposes implementation options (usually 2-3)". Left unedited in-scope to keep both sides consistent; orchestrator decides. |
| F2 | output-and-persist.md:447; SKILL.source.md:322 | `reproduction` field no skill writes | flag | kept | Flag-only; product call, cross-skill contract pinned by tests/test-issue-analysis.sh. |
| F3 | SKILL.source.md:321; output-and-persist.md:264,267,284 | "never `sha`" repeated 4x | flag | kept | Flag-only; auditor itself advises keeping it as a guard. |
| F4 | subagent-steps.md:38 | Undefined "step log" / tier field | flag | kept | Flag-only; fixing needs a payload contract decision with the shared synthesizer. |
| F5 | SKILL.source.md:309-311 | "Step 9" vs "persist step" naming | flag | kept | Flag-only, cosmetic; same as round-1 #11. |
| F6 | subagent-steps.md:40 | Leftover "keyword extraction" paragraph | flag | kept | Flag-only; same as round-1 #12. |
