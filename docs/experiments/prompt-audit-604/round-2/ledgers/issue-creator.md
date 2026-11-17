# Ledger (second pass): src/skills/issue-creator

| # | Location | Finding (short) | Confidence | Outcome | Detail |
|---|---|---|---|---|---|
| 1 | references/model-suggestion.md:69, :286 | Two copied model picks left after round 1 | High | fixed | :69 schema example `XS` band → `"openai": "...", "anthropic": "..."`; :280 body example → `**Suggested model:** {openai_model} · {anthropic_model} _(CursorBench {data_version}, {data_date} — advisory)_`. `tests/test-scripts-253.sh:465` pins script output, not this prose. |
| 2 | references/model-suggestion.md:44-50 | "Upgrade note" + weekly CI seed refresh in bundle | Medium | fixed | Blockquote replaced by plain paragraph (same lifecycle rule, `last_fetched` comparison, tie keeps cache) without "Upgrade note" framing or the CI "weekly seed refresh" clause. One line shorter. |
| 3 | references/model-suggestion.md:123-126 | "Per-repo legacy cache" note describes a path nothing reads | Medium | fixed | Paragraph removed. Premise verified: `src/shared/scripts/gi-model-cache.py` never references `.idd/model-data.json` (its only "legacy" use is the `.gitissue.yml` config name). Round 1 kept it as Low/flag; this pass rates it Medium/remove with a verified premise. |
| 4 | references/examples.md:84, :107 | Example result lines the skill does not print | Medium | fixed | :84 → "create each, with per-item progress → the `◆ Batch Create — 3/3 issues` report (`references/modes.md`, Batch Create Step 6), then the review contract and run-stats footer"; :107 → "the `◆ Issue Created` block (Step 6), then the review contract and run-stats footer". Verified headings at modes.md:376/382 and SKILL.source.md:307. |
| 4b | tests/README-sprint2.md:361 | Manual test case still expects `✓ 3/3 issues created` | Medium | out-of-scope | Not a `tests/*.sh` pin, outside target dir. Proposed edit in `tests/README-sprint2.md:361`: ``- [ ] Final output shows `✓ 3/3 issues created` with all issue numbers and URLs`` → ``- [ ] Final output shows the `◆ Batch Create — 3/3 issues` report with all issue numbers and URLs``. |
| 5 | references/examples.md:98-103 | Default-config preview example lacks `⚡ Model:` line | Medium | fixed | Added `⚡ Model:  {openai_model} (~${openai_cost}/task) · {anthropic_model} (~${anthropic_cost}/task)` between Title and Labels, matching SKILL.source.md Step 5. |
| F1 | references/clarify-intent.md:19 | Emphasis on Output Contract boundary | Flag | kept | Flag-only; working redundancy on a real constraint (report agrees). |
| F2 | references/modes.md:143-147 | `# MANDATORY` bash comment repeats line 17 | Flag | kept | Flag-only; working redundancy. |
| F3 | references/modes.md:311 | "Step 3.5" pointer lives in SKILL.md | Flag | kept | Flag-only (no confidence/action given); candidate one-word fix "SKILL.md Step 3.5" for a later pass. |
| F4 | SKILL.md Step 5 vs model-suggestion.md:270-278 | `Effort:` line in one preview, not the other | Flag | kept | Flag-only; minor format inconsistency, no edit proposed. |
| F5 | references/image-upload.md:15 | `stat -f%z` on GNU may not fail over | Flag | kept | Flag-only, untested by the auditor; code behaviour needs a real check before editing. |
| F6 | error-messages.md:168 / image-upload.md:7 | 10 MB limit attributed to contents API | Flag | kept | Flag-only; auditor did not verify against GitHub docs. |

Orchestrator note: issue-creator bundle bytes shrink slightly (model-suggestion.md −6 lines); `tests/test-skill-bundle-budget-466.sh` ratchet may need the serial `--ratchet` run. SKILL.source.md untouched.
