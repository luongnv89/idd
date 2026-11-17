# Prompt audit, second pass: `src/skills/issue-creator`

**What I assumed**
- **Scope:** every authored file under `src/skills/issue-creator/`. I audited the working tree, which already includes your first-pass edits. I left out `LICENSE`, `docs/README.md` (a human-only file the agent never loads) and the data in `templates/model-data.json`, except to check examples against it.
- **Target model:** Claude Opus 5.5. This is a Claude Code skill with no model pinned, so I used the model running the audit.
- **Filter:** as you asked, only high- or medium-confidence findings whose action is rewrite or remove. I didn't apply any edits.

**Summary.** The surface is mostly clean. The first pass replaced most hardcoded model names with placeholders but left two copies in `model-suggestion.md`, so that file now contradicts its own "picks are not copied here" rule. The same file still has two passages about earlier versions and CI that your writing rules keep out of the bundle. The worked examples in `examples.md` show result lines the skill no longer prints.

Every script flag, output field and config key the skill cites exists in the scripts and in `docs/config-schema.md`. I checked them by reading the files, not by running anything. Findings by group: Group 1: 2 · Group 2: 3 · Groups 3 and 4: not applicable (no tool definitions or code that builds API requests).

## Findings

| # | Location | Evidence | Pattern | Why it's obsolete | Conf. | Action |
|---|---|---|---|---|---|---|
| 1 | `references/model-suggestion.md:69`, `:286` | `"XS": {… "openai": "GPT-5.6 Luna High", "anthropic": "Haiku 5.5 Extra High"}` and `**Suggested model:** GPT-5.6 Luna Max · Sonnet 5.5 Extra High _(CursorBench 4.0, 2026-11-17 — advisory)_` | G2 volatile specifics / contradiction | Lines 242–244 of the same file say the picks "are not copied here because a refresh replaces them", and CLAUDE.md says not to copy data that has a source file. The first pass made lines 252/260/275 placeholders but missed these two. The example body line is the strongest signal for what the agent writes. | High | rewrite to placeholders |
| 2 | `references/model-suggestion.md:44-50` | `> **Upgrade note.** … and a weekly seed refresh still reaches every install.` | G2 history narrative + maintainer material | "Weekly seed refresh" is the `.github/workflows/model-data-refresh.yml` CI job. The first pass removed that same CI note at line 179 but missed this one. The "Upgrade note" framing compares against an older install. | Medium | rewrite |
| 3 | `references/model-suggestion.md:123-126` | `> **Per-repo legacy cache.** A .idd/model-data.json in the repo is ignored — … It is stale project state, safe to delete; the skill does not touch or migrate it.` | G1d migration-relative phrasing | Nothing reads that path (`gi-model-cache.py` never mentions it). CLAUDE.md keeps the word "legacy" only where a compatibility path still runs. The paragraph describes a location the agent will never use, and "safe to delete" invites a deletion that isn't part of the skill's job. | Medium | remove |
| 4 | `references/examples.md:84`, `:107` | ``→ `✓ 3/3 issues created` `` and ``→ `✓ Created issue #15` `` | G1c stale examples | Neither line is an output the skill produces. Create prints the `◆ Issue Created` block (SKILL.md Step 6) and Batch prints `◆ Batch Create — {N}/{N} issues` (modes.md Step 6). Both are also followed by the review contract and the run-stats footer. | Medium | rewrite |
| 5 | `references/examples.md:98-103` | A preview block with no `⚡ Model:` line | G1c stale example | `model_suggestion.enabled` defaults to `true`, so a default-config preview always has the model line. This example shows the behaviour you'd only see with the feature disabled. | Medium | rewrite |

## Proposed diff

There's one finding per hunk. Finding 4 has a follow-on change: `tests/README-sprint2.md:361` is a manual test case that still expects `✓ 3/3 issues created`. It's not runtime text, but it would go stale with this change.

```diff
--- a/src/skills/issue-creator/references/model-suggestion.md
+++ b/src/skills/issue-creator/references/model-suggestion.md
@@ -68,3 +68,3 @@  # Finding 1
   "complexity_mapping": {
-    "XS": { "label": "trivial", "openai": "GPT-5.6 Luna High", "anthropic": "Haiku 5.5 Extra High" }
+    "XS": { "label": "trivial", "openai": "...", "anthropic": "..." }
   }
@@ -285,3 +285,3 @@  # Finding 1
 ```markdown
-**Suggested model:** GPT-5.6 Luna Max · Sonnet 5.5 Extra High _(CursorBench 4.0, 2026-11-17 — advisory)_
+**Suggested model:** {openai_model} · {anthropic_model} _(CursorBench {data_version}, {data_date} — advisory)_
 ```
```

```diff
@@ -44,7 +44,6 @@  # Finding 2
-> **Upgrade note.** Because the cache lives outside the skill folder, it
-> survives plugin updates and reinstalls. An upgrade can ship a newer bundled
-> seed, so the lifecycle compares the two by `last_fetched`: when the seed's
-> date is **newer** than the cache's, the seed wins and is written to
-> `{cache_dir}` (pruning the older copy); otherwise — including a tie — the
-> cache is kept. A refreshed cache is therefore never overwritten by an older
-> seed, and a weekly seed refresh still reaches every install.
+Because the cache lives outside the skill folder, it survives plugin updates
+and reinstalls, and a reinstall can ship a newer bundled seed. The lifecycle
+compares the two by `last_fetched`: when the seed's date is **newer** than the
+cache's, the seed wins and is written to `{cache_dir}` (pruning the older copy);
+otherwise — including a tie — the cache is kept, so a refreshed cache is never
+overwritten by an older seed.
```

```diff
@@ -122,6 +122,0 @@  # Finding 3
-
-> **Per-repo legacy cache.** A `.idd/model-data.json` in the repo is
-> **ignored** — the skill neither reads nor writes it, and model suggestions
-> never depend on it. It is stale project
-> state, safe to delete; the skill does not touch or migrate it.
```

```diff
--- a/src/skills/issue-creator/references/examples.md
+++ b/src/skills/issue-creator/references/examples.md
@@ -84 +84,2 @@  # Finding 4 (batch)
-5. On "All" → create each → `✓ 3/3 issues created`
+5. On "All" → create each, with per-item progress → the `◆ Batch Create — 3/3 issues`
+   report (`references/modes.md`, Batch Step 6), then the review contract and run-stats footer
@@ -107 +108,2 @@  # Finding 4 (create)
-6. On confirmation → `gh issue create` → `✓ Created issue #15`
+6. On confirmation → `gh issue create` → the `◆ Issue Created` block (Step 6),
+   then the review contract and run-stats footer
```

```diff
@@ -100,3 +100,4 @@  # Finding 5
      Type:     bug (high)
      Title:    Fix checkout page broken on Safari
+     ⚡ Model:  {openai_model} (~${openai_cost}/task) · {anthropic_model} (~${anthropic_cost}/task)
      Labels:   bug, checkout
```

```diff
--- a/tests/README-sprint2.md
+++ b/tests/README-sprint2.md
@@ -361 +361 @@  # Finding 4 follow-on (manual test case)
-- [ ] Final output shows `✓ 3/3 issues created` with all issue numbers and URLs
+- [ ] Final output shows the `◆ Batch Create — 3/3 issues` report with all issue numbers and URLs
```

No `tests/*.sh` script checks any of the removed text. `test-scripts-253.sh:465-466` checks the script's output for the M band, not the reference prose, so finding 1 doesn't affect it.

## Flag-only notes (no edits proposed)

- **`references/clarify-intent.md:19`:** `**Output Contract boundary (critical):** … MUST NOT leak`. This is emphasis on a rule that already gives its reason, and SKILL.md:253 says the same thing. It's working redundancy on a real constraint, so keep it.
- **`references/modes.md:143-147`:** the bash comment `# MANDATORY, not optional: …` repeats the reason already given at line 17. Also working redundancy.
- **`references/modes.md:311`:** "exactly as Step 3.5 skips its clarification prompt". Step 3.5 is in SKILL.md, not in modes.md, so the pointer should say SKILL.md.
- **SKILL.md Step 5 vs `model-suggestion.md:270-278`:** one preview example has an `Effort:` line and the other doesn't. It's a minor inconsistency in the preview format.
- **`references/image-upload.md:15`:** on GNU/Linux, `stat -f%z` may succeed with useless output instead of failing over to `stat -c%s`. I didn't test this. It's a code issue, not a prompt one.
- **`error-messages.md:168` / `image-upload.md:7`:** the 10 MB limit is described as a contents-API limit. That limit belongs to issue attachments, not the contents API. I didn't check this against current GitHub docs.
