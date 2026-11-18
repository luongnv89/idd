# Ledger (pass 2): idd-doctor (src/internal-skills/idd-doctor/)

| # | Location | Finding (short) | Confidence | Outcome | Detail |
|---|---|---|---|---|---|
| 1 | SKILL.source.md:146 | Substring-matched negation marker `no` suppresses the "…notes" patterns | High | fixed | Verified: three patterns contain "notes"; tests/test-idd-doctor.sh:385 already matches markers as words (`"no "`). Now "no negation marker as a whole word (...); the `no` inside \"notes\" is not a marker." Not a safety gate (lint check). No test pins the old wording (T4 pins only "negation guard"). |
| 2 | SKILL.source.md:68 | Fallback points to a footer shape the *Run stats footer* section never shows | High | fixed | Verified: section lists fields only; shape lives in references/run-stats.md (the file assumed missing). Replaced pointer inline, net-neutral instead of a 5-line code block: "print a `┄` separator line, then `  Run stats   elapsed n/a · agents 0`." |
| 3 | references/run-log-summary.md:47 | Example shows 2 skip reasons, rule says top 3 | Medium | fixed | Added `, {reason3} ({c3})` to the example line. No test pins it. |
| 4 | references/review-contract.md:66-70 | "Interactive report: not applicable" maintainer rationale | Medium | fixed | Paragraph removed; *Format rule* bullets above cover the layout. No test pins it (grep of tests/*.sh). |
| F1 | SKILL.source.md:108, error-messages.md:128-186 | `Merge method` padded one column wider | Flag | kept | Flag-only, cosmetic; exact Check 4 strings pinned by tests/test-squash-binding-295.sh and test-idd-doctor.sh (same as round-1 #13). |
| F2 | SKILL.source.md:192 | `predicted affected files` redundant with `affected files` | Flag | kept | Flag-only; minor double count, no edit proposed. |
| F3 | SKILL.source.md:291-292 | Restated run-log field list omits `skill` | Flag | kept | Flag-only; "at least" keeps it true; no edit proposed. |
| F4 | SKILL.source.md:20-24 | When to Use addresses the invoker | Low/Flag | kept | Low confidence; helps routing (same as round-1 #14). |
| F5 | Checks 1-3, run-log medians | Deterministic work done by the model | Flag | kept | needs new script: follow-up (architecture decision). |
