I audited `src/skills/issue-analysis` against the uncommitted working tree, so your first-pass edits are included, and changed no files. Four findings at high or medium confidence remain. All four are stale pointers or contradictions; two were created by the first pass. No dated-model prose (pressure language, scaffolds) is left at medium confidence or above.

**Assumptions**
- **Scope:** `SKILL.source.md` plus `references/*.md`. I left out `docs/README.md` (never loaded into context) and `LICENSE`. Cross-file facts were checked against `src/shared/`, `docs/` and the sibling skills.
- **Target model:** Claude Opus 5.5. The skill sets `effort: high` but names no model, so I used the model running this audit.
- No non-Anthropic provider code was found.

**Counts:** Group 1 (dated prompt text) 0 · Group 2 (stale facts and conflicts) 4 · Group 3 not applicable (no tool definitions) · Group 4 not applicable (no request-building code; the two subagents have distinct roles, so neither is redundant).

## Findings

| # | Location | Evidence | Pattern | Why it's wrong | Confidence | Action |
|---|---|---|---|---|---|---|
| 1 | `SKILL.source.md:216` | "in the format shown under *Expected Output*. Each step prints a new line when it starts (with `●`) and updates to `✓`…" | Group 2: stale pointer, and two rules that contradict | The first pass cut the tracker block out of *Expected Output*, which now just points to `references/examples.md`, so this pointer leads nowhere. "Updates to `✓`" also conflicts with "static sequential output (no animation)" at `:431`, and the examples print one line per finished step. | High | rewrite |
| 2 | `SKILL.source.md:192`, `:304` | "per-step prompts and tool budgets"; "the tool budgets every run needs" | Group 2: volatile specifics | `references/subagent-steps.md` contains no tool budgets (grep finds none). The agent is sent looking for content that doesn't exist. | High | rewrite |
| 3 | `SKILL.source.md:311` | "the rendering spec (section layout, color codes, truncation rules)" | Group 2: volatile specifics | `output-and-persist.md` defines no color codes; the output style uses symbols, not color. | High | rewrite |
| 4 | `references/output-and-persist.md:485` | `` `options[]` `` — "2-3 implementation approaches" | Group 2: same file contradicts itself | Lines 38–39 of the same file say "A single justified option is valid", and `inline-fallback.md:289` (first pass) agrees. The schema table still says 2–3. | High | rewrite |
| 5 | `references/subagent-steps.md:76` | "(or collected inline in Steps 2-5)" | Group 2: contradiction | The synthesizer is only spawned when the Agent tool exists, and then the explorer is spawned too. Without the Agent tool, Steps 2–7 all run inline (`SKILL.source.md:167-169`, `subagent-steps.md:65-67`). This branch can't happen. | Medium | remove |

## Proposed diff

These edits are to `src/` only. After applying, rebuild with `bash scripts/build.sh --out <tmp> --quiet` and run the suite. No test pins any of the replaced phrases (grep over `tests/` came back empty).

```diff
--- a/src/skills/issue-analysis/SKILL.source.md   (finding 1)
+++ b/src/skills/issue-analysis/SKILL.source.md
@@ -216 +216 @@
-The analysis pipeline has 8 steps plus a persist step. Display progress using the `[N/8]` step counter, one line per step, in the format shown under *Expected Output*. Each step prints a new line when it starts (with `●`) and updates to `✓` on success or `✗` on failure.
+The analysis pipeline has 8 steps plus a persist step. Display progress with the `[N/8]` step counter: one new line per step, `✓` on success or `✗` on failure, in the format `references/examples.md` shows. Lines are printed, never redrawn in place.
```

```diff
--- a/src/skills/issue-analysis/SKILL.source.md   (finding 2)
+++ b/src/skills/issue-analysis/SKILL.source.md
@@ -192 +192 @@
-- `references/subagent-steps.md` — per-step prompts and tool budgets
+- `references/subagent-steps.md` — subagent delegation payloads and return handling
@@ -304 +304 @@
-… **Read `references/subagent-steps.md` now** — it carries the delegation payload, the return handling, and the tool budgets every run needs before spawning either subagent. …
+… **Read `references/subagent-steps.md` now** — it carries the delegation payloads and the return handling every run needs before spawning either subagent. …
```

```diff
--- a/src/skills/issue-analysis/SKILL.source.md   (finding 3)
+++ b/src/skills/issue-analysis/SKILL.source.md
@@ -311 +311 @@
-… — the rendering spec (section layout, color codes, truncation rules) and the JSON schema …
+… — the rendering spec (section layout and truncation rules) and the JSON schema …
```

```diff
--- a/src/skills/issue-analysis/references/output-and-persist.md   (finding 4)
+++ b/src/skills/issue-analysis/references/output-and-persist.md
@@ -485 +485 @@
-| `options[]` | array | 2-3 implementation approaches |
+| `options[]` | array | Implementation approaches, usually 2–3; one when only one is justified |
```

```diff
--- a/src/skills/issue-analysis/references/subagent-steps.md   (finding 5)
+++ b/src/skills/issue-analysis/references/subagent-steps.md
@@ -76 +76 @@
-- Exploration findings: the full structured JSON returned by the explorer subagent (or collected inline in Steps 2-5)
+- Exploration findings: the full structured JSON returned by the explorer subagent
```

## Flag-only notes (no edit proposed)

- **Conflict outside this directory:** `src/shared/agents/synthesizer.md:13,18` requires 2–3 options, while issue-analysis accepts a single justified option. You decide which rule wins; whatever you choose, `subagent-steps.md:80` ("proposes 2-3") should match it.
- **`reproduction` field:** `output-and-persist.md:447` and `SKILL.source.md:322` spend a paragraph on a schema field that, by their own account, no skill writes. Dropping the field is a product call.
- **"never `sha`":** this appears four times (`SKILL.source.md:321`; `output-and-persist.md:264,267,284`). It reads like a guard against a failure that actually happened, so it's worth keeping unless a test shows it's no longer needed.
- **Undefined terms at `subagent-steps.md:38`:** "record the selected tier in the step log and pass that tier intent to the synthesizer" — no step log is defined, and the synthesizer payload has no tier field.
- **Persist step naming:** it is called "Step 9" at `SKILL.source.md:309-311` but "a persist step" outside the `[N/8]` counter elsewhere. This is cosmetic.
- **Leftover paragraph:** `subagent-steps.md:40` ("It performs keyword extraction…") repeats line 12 and the shared agent's own contract, after the return-handling section.
