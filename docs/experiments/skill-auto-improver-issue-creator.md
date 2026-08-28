# skill-auto-improver run — `/issue-creator`

**Issue:** [#420](https://github.com/luongnv89/idd/issues/420) · part of epic #413
**Target:** `src/skills/issue-creator/` (measured against built `skills/issue-creator/`)
**Measuring standard:** `skill-auto-improver` v2.1.0 · `asm` v2.7.0
**Mode:** Mode 1 — retrofit. Mode 2 (delegation conversion) declined; see §4.
**Date:** 2026-08-28

Measurement convention, unchanged from [#416](https://github.com/luongnv89/idd/issues/416),
[#419](https://github.com/luongnv89/idd/issues/419) and
[#418](https://github.com/luongnv89/idd/issues/418): `src/skills/<name>/` holds
`SKILL.source.md`, not `SKILL.md`, so `quick_validate.py` and `asm eval` cannot read the
authored source. Every measurement below was taken read-only against the built tree
(`skills/issue-creator/`); every edit was landed in `src/skills/issue-creator/` and the built
tree regenerated with bare `./scripts/build.sh` (compile → verify → promote).
`asm eval --fix` was never run against `skills/`.

Body size was measured two ways. `wc -w`/`wc -l` on the file is the working number;
`asm eval` strips the YAML frontmatter first, and that is the number Gate 2 scores. This
skill's frontmatter is **70 words**, so its two numbers sit 70 apart at both ends of the
pass. Source and built `SKILL.md` measure identically (3051 words / 346 lines) — the build
rewrites reference tokens (`docs/X.md` → `references/docs/X.md`) without changing word or
line counts.

**What this pass is, in one line.** Deletion of a duplicated resource index, of prose that
restated a bundled reference the same sentence points at, and of rationale that changes
nothing an agent does — plus in-place compression everywhere else, and **one** relocation
of genuinely run-time-conditional material. 1859 `asm` words came out of the body; 1665 of
them are words the agent no longer loads at all.

---

## 1. Gate status — baseline → final

| Gate | Check | Baseline | Final |
|------|-------|----------|-------|
| **Gate 1** | `quick_validate.py` exit | 0 (pass) | **0 (pass)** |
| Gate 1 | Frontmatter audit (`asm eval` → `checks`) | all pass | **all pass** |
| Gate 1 | Body under 500 lines | 450 (pass) | **346 (pass)** |
| Gate 1 | Body under 3000 words | **4840 (FAIL)** | **2981 (pass)** |
| Gate 1 | Negative-trigger clause in description | pass | pass (description untouched) |
| Gate 1 | `metadata.version` semver + `metadata.author` | pass (0.8.0) | **pass (0.9.0)** |
| Gate 1 | `docs/README.md` opens with the AI-skip comment | pass | pass (untouched) |
| Gate 1 | Bundled scripts print descriptive stderr | pass | pass — see §2 |
| Gate 1 | Dependency preflight (conditional) | **not applicable** | **not applicable** — see §2 |
| **Gate 2** | `overallScore > 85` | 93 (grade A) | **97 (grade A)** |
| Gate 2 | every category `>= 8` | **min 6 — `context-efficiency` (FAIL)** | **min 8 (pass)** |

Per-category (`asm eval --json`, built tree):

| Category | Baseline | Final |
|----------|---------:|------:|
| structure | 10 | 10 |
| description | 10 | 10 |
| prompt-engineering | 9 | **10** |
| context-efficiency | **6** | **8** |
| safety | 10 | 10 |
| testability | 10 | 10 |
| naming | 10 | 10 |
| **overall** | **93** | **97** |

Baseline blocker, verbatim from the evaluator: *"Body is over 3000 words — split long
content into referenced files or templates."* It docked `context-efficiency` 4 points and
`prompt-engineering` 1 (*"Body is very long (4840 words)"*), so one measurement moved two
categories. Final finding: *"Body length within healthy range (2981 words)."*

Body size, command of record:

```
wc -w < src/skills/issue-creator/SKILL.source.md   # 4910 → 3051
wc -l < src/skills/issue-creator/SKILL.source.md   #  450 →  346
```

`metadata.version`: **0.8.0 → 0.9.0** (minor — no restructure, but the run gained two
instructions it did not have: a *Run Stats Footer* at the Normalize and Batch terminal
reports in `references/modes.md` (§5), and a conditional read-now gate on the new
`references/dup-score-fallback.md` (§1, *the one relocation*)).

### The budget this pass had to hit, and how it was hit

`docs/decisions/shared-contract-pin-artifact.md` measured `/issue-creator` at 4840 `asm`
words with an assertion-pinned floor of **2054–2323** and **2517–2786 words of free prose**
against a required cut of **1840**. The pass cut **1859**. As in #418, most of it came from
compressing and deleting *around* pinned literals rather than deleting whole free-prose
lines — a grep pins the literal, not the sentence carrying it. **No assertion was deleted or
loosened, and no D4 exception was needed.** The ADR predicted `/issue-creator` clears; it
clears, with 19 `asm` words of headroom under the cap.

### What was removed, and what it cost

| Cut | Where it survives | `asm` words |
|---|---|---:|
| *Additional Resources* index (10 entries) | Every path is cited at its use site or on the *Bundled dependency precheck* list. | ~110 |
| Per-entry glosses on the 28-item precheck list | The 28 paths all remain, grouped; each file's purpose is stated at the step that reads it. | ~150 |
| Configuration's second *"do not re-read the config"* sentence and its *"invalid values"* sentence | The paragraph above them already carries *Never re-read it* and the exit-3 stop. | ~30 |
| Ten `duplicate_detection.*` default values (`weights.*`, thresholds, `min_token_length`, `phrase_min_tokens`, `max_items`, `extra_stop_words`) | `docs/config-schema.md`, bundled as `references/docs/config-schema.md` and named on the same line. `duplicate_detection.backlog_limit: 100` stays inline because the body's own fallback fence uses it. | ~40 |
| Step 2's type-confidence bullets | `references/confidence-scoring.md` → *Fields with Confidence* → **Type classification**, which the body gates **read it now**. | ~55 |
| Step 2's Good/Bad table, 4 rows → one inline example | `docs/naming-conventions.md`, cited on the same line. | ~50 |
| Step 3.5's four how-to bullets | `references/clarify-intent.md`, which already carried every clause and is now gated read-now **when the step fires**. | ~115 |
| *Confidence Scoring System*'s level → marker mapping and its second pointer sentence | `references/confidence-scoring.md` → *Levels*, gated read-now. | ~45 |
| *Subagent Architecture*'s overview of Step 3 (what the scorer reads, what it self-fetches, what batch mode pools) | Step 3 and `references/modes.md` → *Step 3 — Duplicate Check* state all of it operationally, including *"in both directions"* and the pooled medium band. | ~90 |
| *Image Upload*'s table of contents for `references/image-upload.md` | That file, which the same sentence now says to read. | ~45 |
| *Platform Driver* heading | Folded into *Output Conventions*, carrying its `docs/platform-github.md` citation. | ~15 |
| *GitHub Projects Sync* discovery/caching narration | `docs/github-projects-sync.md` (*Discover Project*, *Cache the project ID*). | ~45 |
| *Expected Output*'s `✓ Issue #42 created` fence | Deliberately — see the called-out change below. | ~55 |
| *Repo Sync* rationale (contents-API narration, the `.gitissue/cache` transient explanation, the stash-pop tail) | `references/image-upload.md` and `docs/sync-conventions.md`. | ~55 |
| Output Contract's *"freeze stale understanding into durable memory"* and its bullet glosses | Nowhere — rationale, not instruction. | ~60 |
| The `--auto` eight-gate index | Each of the eight gates carries its own carve-out at its own site; the claim *"**no** blocking prompt"* is kept. | ~35 |
| In-place compression: every remaining section | Same instruction, fewer words. | ~700 |
| **Relocated** — the `gi-dup-score` inline-fallback algorithm | `references/dup-score-fallback.md` (new, written in the same commit). | **−165 body / +260 reference** |
| **Added** — Run Stats Footer at modes.md Steps 12 and 6 | — | 0 body (§5) |

**Four changes are called out rather than folded into "no behavior change".**

1. **A printed output block was removed.** `## Expected Output` carried a fenced
   `✓ Issue #42 created` / `Title:` / `Type:` / `Labels:` rendering that was a *second,
   contradictory* rendering of the same event as Step 6's `◆ Issue Created` block. An agent
   reading both had no rule for which to print. The section now names Step 6's block; the
   older fence is gone. Output changes: the `✓ Issue #42 created` form is no longer offered.
2. **The `duplicate_detection.*` defaults are no longer all inline.** Ten of the eleven key
   defaults moved to a citation of `docs/config-schema.md` (bundled, and named on the same
   line). If `gi-config.py` degrades *and* the agent does not open that bundled doc, it has
   `backlog_limit` inline but must read config-schema for the weights and thresholds. This
   is the one place a *value* stopped being in the body.
3. **One relocation happened, and D3 governs it.** `references/dup-score-fallback.md` is new
   and carries the parse/truncation rule plus the canonical scoring rules. This material
   executes **only** on the `gi-dup-score` degrade branch (no `python3`, exit 2/4, unparsable
   stdout), which is exactly the run-time-conditional class **D3** permits — and it is gated
   with the same *"read this file only when X is unavailable"* wording
   `tests/test-disclosure-gates-250.sh` AC1.2 endorses for `/issue-analysis`'s
   `references/inline-fallback.md`. The pinned fence (`duplicate_detection.backlog_limit must
   be a positive integer`, `probe_limit=$((backlog_limit + 1))`, the `--limit "$probe_limit"`
   fetch), the exit codes, and the `⚠ gi-dup-score unavailable — scoring duplicates inline`
   print all stay in the body: they are raw file-scoped greps in
   `tests/test-scripts-253.sh`, and the ADR's class table forbids silently re-targeting those.
4. **Two style clauses now live only in the doc the same sentence cites.** *Output
   Conventions* dropped *"one blank line between sections"* and *"(no animation)"*; both are
   in `docs/terminal-style.md`, which the sentence names. *Environment check* dropped
   *"If the script cannot run, execute the documented inline fallback"* — Step 3's degrade
   branch states that far more precisely, three screens below.

### How preservation was checked, and what the check cannot see

All 83 tracked `tests/*.sh` were run under `bash -x` at the baseline commit and every `grep`
invocation extracted from the trace — patterns taken from the traced command line, never
guessed. Patterns whose command line named `issue-creator/SKILL.md` or
`issue-creator/SKILL.source.md`, plus the stdin greps of the six creator-only suites, gave
66 candidate patterns; 54 match the body and became pins, the rest are either foreign
(they belong to `references/modes.md` or `references/model-suggestion.md`) or **negative**
assertions, which were re-asserted as prohibitions instead.

A guard script re-ran the whole set after **every** edit. It carries, beyond the traced
greps:

- **The embedded-Python assertions a grep extractor cannot see.**
  `tests/test-scripts-pipeline-251.sh` T5 slices the `## Configuration` section in Python
  (fences stripped) and requires at least one inline dotted default key plus the literals
  `gi-config unavailable`, `**Working directory:** the repo root`, `Script file absent`, and
  `broken install and not a degrade`. `tests/test-scripts-253.sh` asserts
  `failed-agent verdict is fail-safe ambiguity` on `SKILL.source.md`. All five are in the guard.
- **The `check_flow` assertions**, which flatten newlines before matching:
  `every\*\* terminal outcome`, `only where the host reported a count`, and
  `that same .python3. invocation.*ec=\$\?; date \+%s >&2; exit "\$ec"` — plus the
  `check_flow_lacks` prohibition on the flattened `` `elapsed`, `tokens`, `agents` ``.
  The third of these **caught a real regression mid-pass**: compressing *"chain that same
  `python3` invocation"* to *"chain that invocation"* broke `tests/test-run-stats-373.sh`
  AC4 while every other check stayed green. Restored verbatim.
- **The six `has_near` proximity assertions** of `tests/test-issue-creator-modes.sh` T9.2,
  T9.3 and T9.6, which are placement contracts: `Auto mode` and
  `⚠ Auto mode: duplicate confirmation skipped` within 20 lines *after*
  `Continue creating? [Y/n]`; `Auto mode` and `⚠ Auto mode: create confirmation skipped`
  within 25 after `Create issue? [Y/n]`; `Continue creating? [Y/n]` within 5 after
  `⚠ Possible duplicate:`; `Create issue? [Y/n]` within 12 after `◆ Issue Preview`.
- **The two count assertions** of `tests/test-consolidated-blocks-248.sh` T6: the body must
  carry **≥3** pointers to the *two-model rendering rule*, and must **not** carry the rule's
  own text (`one OpenAI model and one Anthropic model`, whose single home is
  `references/model-suggestion.md`).
- **The four negative assertions**: no `< .gitissue/cache/dup-request.json`, no
  `gh issue list … --limit 100`, no `^## Repo Sync Before Edits (mandatory)` heading, and no
  `git pull --rebase` inside a fenced block (`tests/test-disclosure-gates-250.sh` AC4).
- **The bare closure tokens.** The traced greps only ever see the *built* `references/…`
  forms, but `scripts/build.py` bundles off the **source** tokens, several of which appear
  exactly once in the body. Dropping the one sentence naming `shared/scripts/gi-gh.py` would
  have stopped the build bundling it while the precheck list still named it —
  `tests/test-scripts-pipeline-251.sh` T1 fails *after* a green guard. All thirteen bare
  tokens (`shared/scripts/gi-{gh,config,model-cache,dup-score}.py`,
  `shared/agents/duplicate-detector.md`, and the eight `docs/*.md`) are asserted.
- **`asm`'s own scoring, replicated exactly.** The guard reimplements the evaluator's five
  scorable categories from `agent-skill-manager.js` — the `Kb`/`Vb`/`Bb`/`Ub` cue lists and
  every regex — and fails if any category would drop below its target. This is what #418
  discovered the hard way with four silently-lost cues, and it **caught two here**:
  compressing *"skip all model-suggestion steps"* to *"…step"* removed the last lowercase
  `steps` and would have cost `prompt-engineering` its progressive-disclosure points; and
  relocating the scoring rules removed the last `per-token`, which was the body's **only**
  match for `context-efficiency`'s `/\btoken\b|\bbudget\b|\bcontext window\b/i` — note the
  **singular** `token`, so the surviving `` `tokens` `` in the run-stats sentence does not
  count. That would have capped `context-efficiency` at 7 and failed Gate 2 at any word
  count. The cue was restored as a true statement at the delegation site: *"That keeps up to
  100 issue bodies out of the main agent's token budget."*

Beyond the guard, `git diff` was read one removed token at a time: 539 tokens present in the
baseline body and absent from the final one were listed and classified individually. Each
was traced either to a surviving inline statement or to the file that owns it, and those
destinations were verified by grep rather than assumed — `references/dup-score-fallback.md`
(NFKC, stop-word policy, precedence, per-token weight, both directions, truncation,
quoting), `references/clarify-intent.md` (the `[Y/n]` idiom, *"never a special UI widget
(the skill must also run on Claude.ai)"*), `references/image-upload.md` (`ARG_MAX`, base64,
placement, multi-image, normalization-mode), `references/confidence-scoring.md`,
`references/modes.md` (*"in **both directions**"*, the pooled medium band),
`docs/naming-conventions.md` (the Good/Bad table),
`docs/github-projects-sync.md` (*Discover Project*, *Cache the project ID*),
`docs/config-schema.md` (all eleven `duplicate_detection.*` defaults), and
`docs/terminal-style.md`. The four losses that survive nowhere are the ones named above.

The body carries no `<!-- a:… -->` anchor, so none could be lost.

---

## 2. Gate 1 — the two conditional items

**Dependency preflight: not applicable, and correctly absent.**
`references/skill-creator-checklist.md` §8 makes the section conditional on a target that
*invokes another skill*, and states that *"adding an empty one is itself a defect."* All
three signals were scanned across the source package:

- **Calls `/other-skill`?** No. `/init-gitissue` appears inside the printed `○ First run`
  line (advice to the user, not an invocation); `/issue-analysis`, `/issue-triage` and
  `/issue-resolver` appear once, as prose naming who owns the four prohibited artifacts.
  In `references/modes.md`, `/issue-resolver` is named as the *other reader* of the issue
  cache (the rationale for the mandatory `gi-issue.py --invalidate`) and `/auto-pilot` as the
  orchestrator that *drives* this skill — neither is invoked by it.
- **Delegates a phase to a named skill?** No. Step 3's medium band is delegated to a shared
  **agent prompt** (`shared/agents/duplicate-detector.md`) through the Agent tool. An agent
  prompt is not a skill and has no installer.
- **Reads a path under `~/.claude/skills/`, `~/.agents/skills/`, `~/.codex/skills/`?** No —
  grep across `SKILL.source.md` and all nine `references/*.md` returns nothing. The
  `asm install` occurrences are the *self*-reinstall command inside the
  `✗ Missing bundled dependency` block, an upgrade note in `references/model-suggestion.md`,
  and the install line in the human-only `docs/README.md`.

The condition does not fire, so nothing is required and nothing was added.

**Bundled scripts print descriptive stderr: verified, not assumed.** All five bundled
scripts were executed from the built tree. `--help` exits 0 for every one. On invalid input:
`gi-config.py` against a malformed `.gitissue.yml` prints
`✗ Invalid .gitissue.yml: … while parsing a flow sequence` with the parser's line and column
and exits **3**; `gi-dup-score.py` on a request with no items prints
`✗ gi-dup-score: request must carry a non-empty 'items' array` and exits **3**;
`gi-model-cache.py --skill-dir /nonexistent` prints
`✗ gi-model-cache: --skill-dir is not a directory: /nonexistent` and exits **3**;
`gi-issue.py` with no arguments and `gi-gh.py --bogus` print argparse usage errors and exit
**2** (usage error, per the shared vocabulary). Every exit-3 path is routed to a **stop**,
not a degrade, in the body, and that routing was preserved verbatim.

---

## 3. Predictability audit (Phase 2b — advisory, never gates)

Rubric resolved at `~/.claude/skills/skill-auto-improver/references/predictability-audit.md`
(no fail-soft skip). Walk of all 7 items:

| # | Rubric item | Verdict | Note |
|---|-------------|---------|------|
| 1 | Invocation chosen intentionally | **pass** | User-invoked, and the shape matches: the body opens on an eight-form invocation list (`<text>`, `<N>`, `--dry-run`, `--force`, multi-item, `--parent`, `--refresh-model-data`, `--auto`) followed by a two-line mode-detection rule, and reads as "the user asked for this, proceed". The description keeps its negative-trigger clause because `/auto-pilot` reaches this skill model-invoked as its mid-loop normalizer. `compatibility` states the tool requirement (`git`, `gh` with auth) before the body is read. |
| 2 | Branches mapped before the body | **pass** | Three orthogonal branches are selected before any step runs, each named in one place: **mode** (Create / Normalize / Batch — decided in *Modes*, above *Prerequisites*; Normalize and Batch leave for `references/modes.md` and never enter Steps 1-6); **auto vs. interactive** (`--auto`, deferred to `docs/auto-mode.md`, with the skill's three body-level prompts each carrying its own carve-out at its own site); **Agent tool available vs. not** (*Environment check*, the sole gate on the medium-band spawn). A fourth, `model_suggestion.enabled`, is decided once in *Configuration* and gates every model-suggestion step. |
| 3 | Demanding, checkable completion criteria | **pass, with one advisory** | Step 6's `◆ Issue Created` block is a per-step tracker (`Parse input`, `Classify`, `Duplicates`, `Template`, `Preview`, `Create`) closing on a literal `Result: DONE`, and `references/modes.md` gives Normalize (`Result: DONE`) and Batch (`Result: DONE` / `PARTIAL`) the same shape. The duplicate override has an explicit `⚠ warn ({N} potential duplicates, {override_source})` row. **Advisory:** unlike `/issue-triage`, the body states no *"no step is complete until its `Result:` line prints"* rule, and there is no `√`/`×` per-check vocabulary — `tests/test-disclosure-gates-250.sh` AC3 does not list `/issue-creator`, so nothing requires one. Left as-is; adding it is a behavior change this issue did not ask for. |
| 4 | Progressive disclosure + delegability | **pass** (this pass fixed the disclosure half) | Was 4840 `asm` words at 450 lines, with a resource index duplicating the precheck list, three sections restating a bundled reference the same paragraph pointed at, and rationale for rules stated two paragraphs earlier. Now 2981 words / 346 lines. The every-run specs are one-line read-now pointers (`references/confidence-scoring.md`, `references/modes.md` in either non-Create mode) and the two conditional ones are gated on their condition (`references/clarify-intent.md` *when the step fires*, `references/image-upload.md` *with images present*, `references/dup-score-fallback.md` *only on this branch*), which is what `tests/test-disclosure-gates-250.sh` AC1 asserts for the sibling skills. Delegability sub-check below. |
| 5 | Leading words | **pass** | Recurring concepts are named once and referred to by name afterwards: *Output Contract*, *intent-capture tool only*, *auto mode*, *Bundled dependency precheck*, *Run Stats Footer*, *two-model rendering rule*, *fail-safe ambiguity*, *medium band*, *truncation probe*, *degrade vs. stop*. This pass extended the pattern rather than breaking it — Step 2 now cites the **Type classification** row by name instead of restating it, and *Expected Output* names Step 6's `◆ Issue Created` block instead of re-rendering it differently. |
| 6 | No duplication / stale sediment / sprawl / no-ops | **pass** (this pass fixed it), one item left open | **Removed:** the *Additional Resources* index; the precheck glosses; Configuration's two restated clauses; Step 2's confidence bullets and its Good/Bad table; Step 3.5's four how-to bullets; the *Confidence Scoring System* level table; *Subagent Architecture*'s overview of Step 3; *Image Upload*'s table of contents; *Platform Driver* as its own heading; the Projects Sync discovery narration; ten config defaults duplicating `docs/config-schema.md`. **Contradiction removed:** `## Expected Output` and Step 6 rendered the same success event two different ways; the body now has one. **No-ops removed:** *"encoding them here would freeze stale understanding into durable memory"*, *"a run that should not create an issue is one that should not have been started"*, *"it costs no extra round trip"*, *"the flag is optional and additive — a batch without `--parent` behaves exactly as it does today"* — each states a consequence that changes nothing an agent does. **Left open, advisory:** Step 6's tracker labels (`Parse input`, `Classify`, `Duplicates`, `Template`, `Preview`, `Create`) and the step headings (*Step 1 — Parse Input* … *Step 6 — Create Issue*) name the same six units of work in two vocabularies. Both label sets are printed strings, so reconciling either changes output; neither was touched. |
| 7 | Publish-ready — no auto-improver dependency | **pass** | `quick_validate.py` exit 0 (*"Skill is valid!"*), `asm eval` 97/A with no category below 8, 346 lines, description carries the negative-trigger clause, `metadata.version`/`author`/`license` present, `docs/README.md` opens with the AI-skip comment. The skill clears the standard without a follow-up auto-improver run. |

### Delegability sub-check (item #4)

Rule applied verbatim: *"a step heavy enough to hand off names no slice of `references/` for
its worker — record it as `step N is not delegable because <reason>` (needs the user
mid-step, depends on the previous step's exact text, or its slice is what every run reads
anyway). A skill with nothing to slice passes."*

Every step, walked. "Heavy enough to hand off" is judged by *Identifying a delegable step*'s
four tests, applied in order — **context weight**, **independence**, **no user mid-step**,
**slice is separable** — the first `no` ending it.

| Step | Heavy enough to hand off? | Names its slice? |
|---|---|---|
| **Step 3 — medium-band duplicate judgement** | yes — a per-candidate fan-out over up to 100 issue bodies, chunked by `medium_judgement.batch_size` | **yes — and already delegated.** Spawned as `shared/agents/duplicate-detector.md` through the Agent tool. Its worker needs no `references/` slice because the whole slice travels in the pinned payload — `{mode, items, candidates: chunk, issue_context: only the medium_issue_context rows referenced by that chunk}` — and the return is pinned too: one tri-state `decision` per candidate, matched by complete identity. The restructure Mode 2 performs is the shape this step already has. |
| **Step 3 — deterministic scoring** | no | **not delegable because it is a single script call.** `python3 shared/scripts/gi-dup-score.py < "$dup_request"` with a trap block around it. Fails **context weight**, the first test, which ends the walk. Its degrade path is now `references/dup-score-fallback.md`, which is loaded only on that branch — and a worker handed it would still need the orchestrator's shell for the trap/cleanup contract. |
| **Step 4 — Generate Issue Content** | borderline — a template read plus a six-field population | **step 4 is not delegable because it depends on the previous steps' exact text.** It needs the reporter's original text *verbatim*, the Step 2 classification *with its confidence*, and the Step 3.5 answers — the exact text, not the stated result. Fails **Independence**. Its slices (`templates/*.md`, `references/model-suggestion.md`, `references/confidence-scoring.md`) also fail **slice is separable**: `confidence-scoring.md` is gated read-now for every run. |
| **Normalize mode (`references/modes.md` Steps 1-12)** | yes — twelve steps, a backup, a body rewrite, a cache invalidation | **normalize is not delegable because it needs the user mid-step and it is the whole run.** Step 6 shows `◆ Normalization Preview` and Step 7 waits on `Apply normalization? [Y/n/dry-run]`. There is no orchestrator left behind to receive a worker's return — the mode *is* the run. Fails **no user mid-step**. |
| **Batch mode (`references/modes.md` Steps 1-6)** | yes — a per-item fan-out with per-item success/failure tracking | **batch is not delegable because it needs the user mid-step, and its slice is what every batch run reads anyway.** Step 4 waits on `Create {N} issues? [A]ll / [e]dit / [c]ancel`, and `references/modes.md` is gated **read it now** for the whole mode, so a worker would be handed a file the orchestrator has already loaded in full. Fails **no user mid-step** and **slice is separable**. |
| **Image Upload** | borderline — validation, a base64 `gh api` call per image, markdown placement | **image upload is not delegable because its slice is what the run reads anyway.** `references/image-upload.md` is gated read-now whenever images are present, which is exactly when the step runs; handing it to a worker withholds nothing. |
| **Prerequisites / Configuration** | no | **not delegable because the config load must happen in the orchestrator's own shell** — that is where `run_started_epoch` is captured (`python3 …; ec=$?; date +%s >&2; exit "$ec"`). A worker's shell exits taking the value with it, the exact failure `delegation-conversion.md` → *Deriving the slice* item 5 warns about. Also fails **context weight**: four probes and one script call. |
| **Steps 1, 2, 5, 6** | no | **not delegable because each is a single decision or a single call.** Step 1 extracts keywords; Step 2 assigns a type and a title; Step 5 waits on `Create issue? [Y/n]` (**no user mid-step**); Step 6 is one `gh issue create` plus a tracker filled from counts the orchestrator already holds (**Independence**). All fail **context weight** or later. |

**Pass.** The one genuinely heavy phase already delegates, already pins its payload and its
return, and needs no `references/` slice because nothing of its input lives in a file. Every
other step is recorded with the named test it fails. Advisory only — this did not gate the PASS.

---

## 4. Delegation-conversion decision (Mode 2)

**Declined.**

**Named precondition it failed**, verbatim from `skill-auto-improver`'s
`references/delegation-conversion.md` → *When Mode 2 applies*, item **4**:

> **The user has confirmed the restructure in this run.** Name the steps you would convert
> and the version bump it forces, and wait. A conversion rewrites the skill's workflow; it
> is never something this skill decides on the user's behalf.

No user is present in this run and no confirmation was given, so the precondition fails
literally. *When Mode 2 applies* requires **all four** — "any miss and the answer is Mode 1,
or nothing" — so this settles the mode on its own.

**Supporting observation — not a second precondition.** Precondition **3** (*"At least one
step is heavy … and is not ruled out by Identifying a delegable step"*) also misses. The
walk in §3 rules out every heavy candidate by a named test: Normalize and Batch on **no user
mid-step**, Step 4 on **Independence**, Image Upload and Batch on **slice is separable**,
Prerequisites/Configuration on the orchestrator-shell clock. The one step that is neither
heavy-and-ruled-out nor light — Step 3's medium band — is *already* delegated through the
canonical `Agent(...)` pattern with a pinned payload and a pinned return.

A recorded decline is the complete outcome here. `SKILL.md` should **net shrink** under a
conversion; this one would net grow, because the only delegation worth having is already
written and the remaining candidates would each need a worker contract over material the
orchestrator loads regardless.

---

## 5. Run-stats footer (issue #414 shape) — AC4

The field set is `elapsed` · `tokens` (conditional) · `agents`, two lines, printed **last at
every terminal outcome**. It was **not widened, reordered or renamed** — that claim stands
unqualified. The contract lives in `references/run-stats.md`, byte-identical across skills;
`tests/test-run-stats-373.sh` (156 checks) passes on both the source and the built tree, and
`references/run-stats.md` was **not touched** by this pass.

The body's call-site sentence kept its pinned shape:

> **Then the run-stats footer.** Close with the *Run Stats Footer* — `references/run-stats.md`
> — `elapsed`, `tokens` only where the host reported a count (otherwise left out), `agents`,
> run cost only, `n/a` for anything undetermined. It is the last thing printed at **every**
> terminal outcome in every mode, a run that created nothing included: a cancelled
> confirmation, an invalid config, a failed `gh issue create`. One footer per batch, never one
> per issue.

**AC4 asks for more than that sentence, so it was checked rather than asserted, and the check
found a real gap.** `## Expected Output` opens *"A successful create prints Step 6's
`◆ Issue Created` block"* — its scope is the **Create** pipeline. `references/modes.md`
Step 12 (*Normalize → Report*) and Step 6 (*Batch Create → Report*) are the terminal outcomes
of the other two modes, and neither named the footer: a Normalize run following modes.md
top-to-bottom prints `◆ Issue Normalized: #{N}`, reaches `Result: DONE`, and stops, never
passing the body's Expected Output paragraph at all. This is the same asymmetry #418
diagnosed for `/issue-triage`'s view mode, and it was closed the same way, in the same commit:

> Then the *Run Stats Footer* (`references/run-stats.md`) — the last thing a Normalize run
> prints, at **every** terminal outcome, the stops of Steps 1-4 and a failed update included.

> Then the *Run Stats Footer* (`references/run-stats.md`) — the last thing a Batch run prints,
> at **every** terminal outcome, a cancelled approval and a fully failed batch included.
> **One footer covers the whole batch**, never one per issue.

The body's own sentence also gained *"in every mode"*, so the Create-scoped opening no longer
narrows the blanket claim.

**For the stops, AC4 holds by construction rather than by list.**
`references/error-messages.md` opens with *"**A block here that stops the run is followed by
the run-stats footer**"*, and `references/run-stats.md` → *Every terminal outcome* is
exhaustive by construction: *"The footer prints wherever the run stops, not only where it
succeeds."* The four prerequisite failures, the invalid-config exit-3 stop, the
missing-bundled-dependency stop, the `gi-model-cache` exit-3 stop, the `gi-dup-score` exit-3
stop, a declined Step 5 preview, and a failed `gh issue create` are all covered by that plus
the body's blanket sentence, which now names three of them explicitly. No per-stop footer
instruction was added — adding one per stop is the bloat the predictability audit forbids by
name.

---

## 6. Files changed

| File | Change |
|---|---|
| `src/skills/issue-creator/SKILL.source.md` | 4910 → 3051 `wc` words, 450 → 346 lines; `metadata.version` 0.8.0 → 0.9.0 |
| `src/skills/issue-creator/references/modes.md` | Run Stats Footer added at Step 12 (Normalize Report) and Step 6 (Batch Report) |
| `src/skills/issue-creator/references/dup-score-fallback.md` | **new** — the `gi-dup-score` degrade-branch procedure (D3 relocation) |
| `skills/issue-creator/**` | regenerated (`./scripts/build.sh`) |
| `docs/experiments/skill-auto-improver-issue-creator.md` | this report |

No other `references/*.md` in the package was touched.

**Test suite of record** (`git ls-files 'tests/*.sh' | xargs -n1 bash`, serial,
`IDD_AUTO_MODE` unset): **82 passed, 1 failed** across 83 tracked scripts — identical to the
pre-change baseline on this machine.

- The single failure is `tests/test-runs-jsonl-rotation-354.sh` T4, the known macOS-only
  artifact (BSD `wc` pads its output, so `"       3" != "3"`). Unrelated to this change;
  reproduces on pristine `origin/main`; ubuntu CI is green.
- `tests/test-scripts-252.sh` AC1, the other known non-defect, **passed** — it fails only with
  `IDD_AUTO_MODE=1` exported, and the variable was unset for every run.
- `tests/test-run-stats-373.sh` failed once mid-pass, on the real regression §1 names
  (*"chain that same `python3` invocation"*). It was fixed, not waived, and has been green since.

---

## 7. Unresolved gates

**None.** Both gates pass on the built tree:

- **Gate 1** — `quick_validate.py` exit 0; 346 lines (< 500); 2981 `asm` words (< 3000);
  frontmatter audit clean with the negative-trigger clause, `metadata.version` `0.9.0` and
  `metadata.author` present; `docs/README.md` opens with the AI-skip comment; all five bundled
  scripts print descriptive stderr and exit 3 on invalid input; the dependency preflight is
  correctly absent because the condition does not fire.
- **Gate 2** — `asm eval` overall **97** (> 85), minimum category **8** (>= 8).

**No D4 exception was invoked, and none is owed.** The ADR predicted `/issue-creator` clears;
it clears.

Three items are deferred rather than unresolved, and all three are named above rather than
folded away:

1. `context-efficiency` scores **8**, not 10, because the evaluator's top band is 120–1500
   words and the remaining point is the singular-`token` cue, which the body now carries.
   Reaching the top band is not available to this skill: the ADR puts its assertion-pinned
   floor at **2054–2323** words, above the band's ceiling before a single word of free prose.
   8 clears the gate.
2. The body sits at **2981** `asm` words — 19 under the cap, tighter than `/issue-triage`'s 26
   and `/issue-resolver`'s 42. The next edit to this body must re-measure.
3. Predictability item **#3** leaves one advisory open (no *"no step is complete until its
   `Result:` line prints"* rule, no `√`/`×` per-check vocabulary), and item **#6** leaves
   another (the Step 6 tracker labels and the step headings name the same six units of work in
   two vocabularies; both are printed strings). See §3.
