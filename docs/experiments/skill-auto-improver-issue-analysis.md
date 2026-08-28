# skill-auto-improver run — `/issue-analysis`

**Issue:** [#419](https://github.com/luongnv89/idd/issues/419) · part of epic #413
**Target:** `src/skills/issue-analysis/` (measured against built `skills/issue-analysis/`)
**Measuring standard:** `skill-auto-improver` v2.1.0 · `asm` v2.7.0
**Mode:** Mode 1 — retrofit. Mode 2 (delegation conversion) declined; see §4.
**Date:** 2026-08-28

Measurement convention, unchanged from [#416](https://github.com/luongnv89/idd/issues/416):
`src/skills/<name>/` holds `SKILL.source.md`, not `SKILL.md`, so `quick_validate.py` and
`asm eval` cannot read the authored source. Every measurement below was taken read-only
against the built tree (`skills/issue-analysis/`); every edit was landed in
`src/skills/issue-analysis/` and the built tree regenerated with bare `./scripts/build.sh`
(compile → verify → promote). `asm eval --fix` was never run against `skills/`.

Body size was measured two ways. `wc -w`/`wc -l` on the file is the working number;
`asm eval` strips the YAML frontmatter first, and that is the number Gate 2 scores. This
skill's frontmatter is **72 words**, so its two numbers sit 72 apart at both ends of the
pass — a property of this frontmatter, not a constant to carry to another skill. Source and
built `SKILL.md` measure identically (2965 words / 426 lines).

**What this pass is, in one line.** Deletion of duplicated navigation and fences, plus
in-place compression. **No material was moved into `references/`**, so decision **D3** of
`docs/decisions/shared-contract-pin-artifact.md` — *relocation is not a word-cap strategy* —
is not engaged at all. The 248 `asm` words this pass removed are words the agent no longer
loads, not words that moved somewhere it still loads them from.

---

## 1. Gate status — baseline → final

| Gate | Check | Baseline | Final |
|------|-------|----------|-------|
| **Gate 1** | `quick_validate.py` exit | 0 (pass) | **0 (pass)** |
| Gate 1 | Frontmatter audit (`asm eval` → `checks`) | 15/15 pass | **15/15 pass** |
| Gate 1 | Body under 500 lines | 465 (pass) | **426 (pass)** |
| Gate 1 | Body under 3000 words | **3141 (FAIL)** | **2893 (pass)** |
| Gate 1 | Negative-trigger clause in description | pass | pass (description untouched) |
| Gate 1 | `metadata.version` semver + `metadata.author` | pass (0.5.2) | **pass (0.6.0)** |
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

Baseline blocker, verbatim from the evaluator: *"Body is over 3000 words — split long content
into referenced files or templates."* It docked `context-efficiency` 4 points (the `+2` for a
body at or under 3000 words, plus the length band) and `prompt-engineering` 1 point
(*"Body is very long (3141 words)"*), so one measurement moved two categories. Final findings:
*"Body length within healthy range (2893 words)."*

Body size, command of record:

```
wc -w < src/skills/issue-analysis/SKILL.source.md   # 3213 → 2965
wc -l < src/skills/issue-analysis/SKILL.source.md   #  465 →  426
```

`metadata.version`: **0.5.2 → 0.6.0** (minor — no restructure, but the View Mode section
gained an explicit run-stats instruction and a stale step cross-reference was corrected).

### What was removed, and what it cost

Nothing was relocated. Every cut is either a deletion of material carried elsewhere in the
same body, or a shorter sentence saying the same thing.

| Cut | Where it survives | Words |
|---|---|---:|
| *Additional Resources* index (6 entries) | Every entry is named by the *Bundled dependency precheck* list above it. Its two unique doc citations — `docs/terminal-style.md` and `docs/config-schema.md` — remain as runtime references at the View Mode render step, Step 8-9, *Configuration* and *Output Conventions*. | ~95 |
| *Pipeline Overview*'s partial `[1/8]…[5/8]` fence | *Expected Output* already carries the complete 8-row tracker; *Pipeline Overview* now names it as the format source. The `[N/8]` rule, the `●`/`✓`/`✗` transitions and the *static sequential output (no animation)* rule all survive (the last in *Output Conventions*, where it was already stated). | ~35 |
| *Final Report*'s already-resolved variant header and separator | The block above it is the same block; the variant now shows only the two rows that differ. | ~20 |
| *"The steps below describe the subagent delegation path…"* | *Environment check* and the *Steps 2-7* heading each already state the same gate. | ~15 |
| Stray duplicate `---` separator | — | 0 |
| In-place compression: *Configuration*, *Durable analysis fields*, *Subagent Architecture* intro, *Steps 2-7* summary, precheck-list descriptions, *Output Conventions*, and eight one-clause trims | Same instruction, fewer words. | ~110 |
| **Added** — View Mode's explicit run-stats instruction (§5) | — | +18 |

**How preservation was checked, and what the check cannot see.** Every tracked test that
touches `/issue-analysis` (10 files) was run once under `bash -x` at the baseline commit, and
every `grep` invocation in the trace was extracted from the command line — patterns taken, not
guessed. 47 of those patterns match the body. They were replayed after **every** edit, with
`-c`/`-o` patterns checked on exact occurrence counts and the rest on presence; all 47 held at
every checkpoint, including the anchor `<!-- a:ia-caller-payload-gate -->`, which
`tests/test-issue-analysis.sh` counts with `grep -cF` and which must appear exactly once
(package-wide, under **D2**).

That guard answers one question — *is every pinned literal still present?* — and #416 recorded
the lesson that suite-green is consistent with semantic loss. So it was not the only check.
`git diff --word-diff` was read one removed token at a time against the classes #416 named:
verb, exit code, script path, stop-vs-degrade distinction, printed literal, section pointer,
anchor. Then 27 named literals were re-asserted directly on the final file — every `Exit 0/3/4`
branch, `✗ Missing bundled dependency`, `⚠ gi-config unavailable`, `○ First run`,
`run_started_epoch`, `[N/8]`, `●`, *static sequential output*, *no animation*,
`IDD_AUTO_MODE=1`, all three `shared/scripts/*.py` tokens, both `shared/agents/*.md` tokens,
and all six `docs/*.md` runtime references. All present.

**One printed string changed, and it is called out rather than folded into "no behavior
change".** *Final Report*'s already-resolved example no longer prints its own
`◆ Issue Analysis: #{N} — {title}` header and `┄` rule inside the example fence. The rendered
output is unchanged — the block above it is the same block, and the variant now shows only the
rows that differ — but the *example* a reader sees is shorter, and an agent reading only that
fence would no longer see the header. That is a real difference in the instruction, not a
formatting no-op.

**One correctness fix, unrelated to size.** View Mode step 6 said *"using the same
`docs/terminal-style.md` format as Step 6"*. Step 6 is root-cause synthesis; the step that
renders the report is Step 8. Corrected to *Step 8*. This is a predictability item #6 finding
(stale sediment) that predates this pass; it is fixed here because the fix is one character.

---

## 2. Gate 1 — the two conditional items

**Dependency preflight: not applicable, and correctly absent.**
`references/skill-creator-checklist.md` §8 makes the section conditional on a target that
*invokes another skill*, and states that *"adding an empty one is itself a defect."* All three
signals were scanned across the source package:

- **Calls `/other-skill`?** No. `/issue-creator N` (in the *No relevant files found* tip) and
  `/init-gitissue` (in the `○ First run` line) are strings printed **to the user** as advice,
  not invocations. `/issue-resolver` and `/auto-pilot` appear only as prose references to
  neighbouring skills.
- **Delegates a phase to a named skill?** No. Steps 2-5 and 6-7 are delegated to shared **agent
  prompts** (`shared/agents/codebase-researcher.md`, `shared/agents/synthesizer.md`) through
  the Agent tool. An agent prompt is not a skill and has no installer.
- **Reads a path under `~/.claude/skills/`, `~/.agents/skills/`, `~/.codex/skills/`?** No —
  grep across `SKILL.source.md` and all six `references/*.md` returns nothing. The single
  `asm install` occurrence is the *self*-reinstall command inside the
  `✗ Missing bundled dependency` block, which is the bundled-dependency guard, not a
  dependency on another skill.

The condition does not fire, so nothing is required and nothing was added. Unlike
`/issue-resolver` (#416), which borrows catalogued skills at Step 3, `/issue-analysis` has no
borrow path at all.

**Bundled scripts print descriptive stderr: verified, not assumed.** All three bundled scripts
were executed from the built tree. `--help` exits 0 for `gi-config.py`, `gi-gh.py` and
`gi-issue.py`. `gi-config.py` run against a deliberately malformed `.gitissue.yml` prints
`✗ Invalid .gitissue.yml: …` with the parser's line and column to stderr and exits **3** —
the "invalid user input, stop" code the body's *Configuration* section routes to a stop, not a
degrade. That routing is stated in the body and was preserved verbatim.

---

## 3. Predictability audit (Phase 2b — advisory, never gates)

Rubric resolved at `~/.claude/skills/skill-creator/references/predictability-rubric.md`
(no fail-soft skip). Walk of all 7 items:

| # | Rubric item | Verdict | Note |
|---|-------------|---------|------|
| 1 | Invocation chosen intentionally | **pass** | User-invoked (`/issue-analysis N`), and the shape matches: the body opens with an *Invocation* table of two forms and reads as "the user asked for this, proceed". The description keeps its negative-trigger clause because `/auto-pilot` reaches this skill model-invoked, and `compatibility` states the view-mode carve-out (*"needs only local file access — no gh required"*) so the cheaper branch is discoverable before the body is read. |
| 2 | Branches mapped before the body | **pass** | Three orthogonal branches are selected before any step runs, each named in exactly one place: **mode** (`view` vs. full — decided in *Invocation*/*View Mode*, above *Prerequisites*, and view mode skips Steps 1-8 and persist outright); **auto vs. interactive** (`IDD_AUTO_MODE=1` or invoked by `/auto-pilot` — stated once in *Repo Sync* and once in the empty-body edge case, the only two prompts); **Agent tool available vs. not** (*Environment check*, which is the sole gate on `references/inline-fallback.md`). Branch-specific mechanics sit behind pointers, not inline. |
| 3 | Demanding, checkable completion criteria | **advisory** | The criteria that exist are checkable and tied to counts, not impressions: each tracker row is `✓`/`✗`/`○` with a number (`{files_read} files scanned`, `{commits_count} related commits`), *Final Report* ends in a literal `Result: DONE`, Step 9 must write 16 named top-level JSON keys whose only definition is `references/output-and-persist.md`, and *No relevant files found* is a hard stop with a stated bar (*"Analysis requires at least one relevant file"*). **The gap:** unlike `/issue-resolver`, the body states no rule making the tracker row a *gate* — there is no equivalent of *"a step is incomplete until `Result:` prints"*, so the tracker is a display convention an agent could in principle print without having met the bar. **Not acted on.** The fix is a sentence, and the body was under a hard word gate this pass was closing; adding words to close an advisory finding while failing a hard gate inverts the priority the audit itself sets (*"Never bloat to satisfy a finding"*). Recorded as open and advisory. |
| 4 | Progressive disclosure + delegability | **pass** (this pass fixed the disclosure half) | Was 3141 `asm` words with a redundant navigation index and two duplicated output fences. Now 2893 words / 426 lines. The two every-run specs are already one-line read-now pointers (`references/subagent-steps.md`, `references/output-and-persist.md`), and the one conditional spec is gated the other way (`references/inline-fallback.md` — read **only** when the Agent tool is unavailable), which is what `tests/test-disclosure-gates-250.sh` AC1.2/AC1.4/AC1.5 assert. Delegability sub-check below. |
| 5 | Leading words | **pass** | Recurring concepts are named once and referred to by name: *stash-first sync*, *caller payload gate*, *Bundled dependency precheck*, *Run Stats Footer*, *view mode*, *degrade vs. stop*, *`git_state`*, *`decision_record`*. This pass extended the pattern rather than breaking it — *Pipeline Overview* now says *"in the format shown under *Expected Output*"* instead of re-drawing a partial copy of that fence. |
| 6 | No duplication / stale sediment / sprawl / no-ops | **pass** (this pass fixed it), one item left open | **Removed:** the *Additional Resources* index (all 6 entries carried by the precheck list); the partial `[1/8]…[5/8]` fence (duplicating *Expected Output*); the already-resolved variant's repeated header and rule; the *"steps below describe the subagent delegation path"* line (duplicating *Environment check*); a stray double `---`. **Stale sediment fixed:** View Mode's *"same format as Step 6"* → *Step 8*. **Left open, advisory:** *Expected Output*'s tracker and *Final Report*'s summary label the same eight steps in two vocabularies (`Extract` / `Extract targets`, `History` / `Git history`, `Cross-refs` / `Cross-references`). These are two different renderings of one run rather than duplicated instruction, and both label sets are printed strings — changing either changes output, so it was not touched. |
| 7 | Publish-ready — no auto-improver dependency | **pass** | `quick_validate.py` exit 0, `asm eval` 97/A with no category below 8, 426 lines, description carries the negative-trigger clause, `metadata.version`/`author`/`license` present, `docs/README.md` opens with the AI-skip comment. The skill clears the standard without a follow-up auto-improver run. |

### Delegability sub-check (item #4)

Rule applied verbatim: *"a step heavy enough to hand off names no slice of `references/` for
its worker — record it as `step N is not delegable because <reason>` (needs the user
mid-step, depends on the previous step's exact text, or its slice is what every run reads
anyway). A skill with nothing to slice passes."*

Every step, walked. "Heavy enough to hand off" is judged by *Identifying a delegable step*'s
**context weight** test — a multi-file read, a per-item fan-out, or a fixed procedure of a
dozen-plus lines.

| Step | Heavy enough to hand off? | Names its `references/` slice? |
|---|---|---|
| **Steps 2-5 — Explorer** (extract, codebase scan, git history, cross-refs) | yes — multi-file read bounded by `analysis.max_files` / `trace_depth` / `scan_timeout` | **yes** — spawned as `shared/agents/codebase-researcher.md`, with `references/subagent-steps.md` named as the slice carrying *"the delegation payload, the return handling, and the tool budgets"*, gated **read it now**. Returns structured findings JSON. |
| **Steps 6-7 — Synthesizer** (root cause, options, complexity/risk) | yes — analytical synthesis over the whole explorer return | **yes** — spawned as `shared/agents/synthesizer.md`, same slice (`references/subagent-steps.md`), plus the explorer's returned findings as the bound input. Returns analysis text + options. |
| **Steps 8-9 — Output & Persist** | yes — a rendering spec plus a 16-key JSON schema | **step 8-9 is not delegable because its slice is what every run reads anyway.** `references/output-and-persist.md` is gated *"**Read `references/output-and-persist.md` now**"* — every run loads it in full, so handing it to a worker withholds nothing. It also fails **Independence**: the report is rendered from the synthesizer's returned analysis text and the explorer's returned counts verbatim, not from their stated results. |
| **Step 1 — Fetch** (incl. the caller payload gate) | no | **step 1 is not delegable because it is a single fetch and a classification** — one `gi-issue.py` call (or its `gh` fallback), one payload-record accept/reject decision, one type label. It fails the **context weight** test, which is the first test and ends the walk. |
| **View Mode** | borderline — renders the full report from JSON | **view mode is not delegable because its slice is what every run reads anyway** — it needs exactly `references/output-and-persist.md`, the read-now file, and it *is* the whole run: there is no orchestrator left behind to receive a worker's return. |
| **Prerequisites / Repo Sync / Configuration** | no | **not delegable because they need the user mid-step** — *Repo Sync* asks `Sync now? [Y/n]` in interactive mode, and the config load must happen in the orchestrator's own shell because that is where `run_started_epoch` is captured (`python3 …; ec=$?; date +%s >&2; exit "$ec"`). A worker's shell exits taking the value with it — the exact failure `delegation-conversion.md` → *Deriving the slice* item 5 warns about. |
| **Edge case — empty issue body** | no | **not delegable because it needs the user mid-step** — `Continue anyway? [y/N]`, default No, in interactive mode. |

**Pass.** Both heavy phases already name their slice; every other step is recorded with the
test it fails. Advisory only — this did not gate the PASS.

---

## 4. Delegation-conversion decision (Mode 2)

**Declined.**

**Named precondition it failed**, verbatim from `skill-auto-improver`'s
`references/delegation-conversion.md` → *When Mode 2 applies*, item **4**:

> **The user has confirmed the restructure in this run.** Name the steps you would convert and
> the version bump it forces, and wait. A conversion rewrites the skill's workflow; it is never
> something this skill decides on the user's behalf.

No user is present in this run and no confirmation was given, so the precondition fails
literally. The same file states the consequence in *When conversion does not pay for itself*:
*"The user declines the restructure. The finding stays advisory. It is never promoted to a
blocker, and Mode 1 never converts a skill quietly."* That settles the mode on its own.

**Supporting observation — not a second precondition.** The conversion would also have had
nothing to convert, which is why the decline is not merely procedural:

- The only two heavy phases, Steps 2-5 and Steps 6-7, **already** run in subagents through the
  canonical `Agent(...)` pattern, and **already** name `references/subagent-steps.md` as the
  worker's slice with a pinned `Output` shape (structured findings JSON, then analysis text +
  options). The restructure Mode 2 performs is the shape this skill already has.
- The one remaining candidate, Steps 8-9, matches *When conversion does not pay for itself* →
  **"Nothing to withhold. No `references/` tree, or one file every run reads anyway."**
  `references/output-and-persist.md` is gated read-now, so a worker would be handed a file the
  orchestrator has already loaded.
- Precondition **3** (*"At least one step is heavy … and is not ruled out by Identifying a
  delegable step"*) therefore also misses: every heavy step is either already delegated or
  ruled out by a named test in §3's sub-check.

A recorded decline is the complete outcome here. `SKILL.md` should **net shrink** under a
conversion; this one would net grow, because the delegation is already documented and the only
thing left to add would be a second worker contract over material the orchestrator reads
regardless.

---

## 5. Run-stats footer (issue #414 shape) — AC4

The field set is `elapsed` · `tokens` (conditional) · `agents`, two lines, printed **last at
every terminal outcome**. It was **not widened, reordered or renamed** — that claim stands
unqualified. The contract lives in `references/run-stats.md`, byte-identical across skills;
`tests/test-run-stats-373.sh` (156 checks) passes on both the source and the built tree.

The body's own line was not reworded:

> **Then the run-stats footer.** Close with the *Run Stats Footer* — `references/run-stats.md`
> — `elapsed`, `tokens` only where the host reported a count (otherwise left out), `agents`,
> run cost only, `n/a` for anything else undetermined. It is the last thing printed at
> **every** terminal outcome, including a run that ended early — an issue that was not found or
> is closed, an invalid config, or a scan that could not complete.

**AC4 asks for more than that sentence, so it was checked rather than asserted.** That
enumeration is illustrative (*"including"*), and it names three early exits out of at least
nine the body actually has. The exhaustive rule is not in the body — it is in
`references/run-stats.md` → *Every terminal outcome*, which is exhaustive **by construction**
rather than by list:

> The footer prints wherever the run stops, not only where it succeeds: a completed pipeline,
> an early exit, a guard that refused to continue, a failed step, an aborted or paused loop, a
> rate-limit or runtime-budget stop, and an invalid-config stop. … A run that produced no
> output at all is the only run without a footer.

Since that file is a bundled dependency named in the precheck list and cited from the body at
the point the footer is printed, **AC4 holds** for the pipeline path: the body's blanket
*"every terminal outcome"* plus the reference's construction covers the prerequisite failures,
the missing-bundled-dependency stop, the empty-body decline and the no-relevant-files stop,
none of which the body enumerates.

**One gap was real and was closed in this pass.** View mode *"skip[s] the entire analysis
pipeline (Steps 1-8) and the persist step"*, so a reader reaching its three exits never passes
the *Final Report* section where the footer instruction lives. The section previously ended
*"After rendering, stop."* It now reads:

> Every view-mode exit — empty state, corrupted JSON, rendered report — closes with the *Run
> Stats Footer* (`references/run-stats.md`), then stops. View mode never writes to the file or
> makes API calls.

This is an **addition** (+18 words) paid for out of the same pass's cuts, and it is why the
version bump is 0.6.0 rather than a patch. Note the consequence, which `references/run-stats.md`
already governs: view mode skips *Configuration*, so no `run_started_epoch` is captured and
`elapsed` prints the literal `n/a` — *"a stop before the config load has no anchor to measure
from"* — not a guess and not `0`.

---

## 6. Files changed

| File | Change |
|---|---|
| `src/skills/issue-analysis/SKILL.source.md` | 3213 → 2965 `wc` words, 465 → 426 lines; `metadata.version` 0.5.2 → 0.6.0; View Mode run-stats instruction added; `Step 6` → `Step 8` cross-reference fix |
| `skills/issue-analysis/SKILL.md` | regenerated (`./scripts/build.sh`) |
| `docs/experiments/skill-auto-improver-issue-analysis.md` | this report |

No `references/*.md` file in the package was touched — a direct consequence of this pass being
deletion plus compression rather than relocation.

**Test suite of record** (`git ls-files 'tests/*.sh' | xargs -n1 bash`, serial,
`IDD_AUTO_MODE` unset): **82 passed, 1 failed** across 83 tracked scripts — identical to the
pre-change baseline on this machine.

- The single failure is `tests/test-runs-jsonl-rotation-354.sh` T4, the known macOS-only
  artifact (line 114 is the one `wc -l` not piped through `tr -d ' '`, so BSD `wc` padding
  makes `"       3" != "3"`). Unrelated to this change; reproduces on pristine `origin/main`;
  ubuntu CI is green.
- `tests/test-scripts-252.sh` AC1, the other known non-defect, **passed** — it fails only with
  `IDD_AUTO_MODE=1` exported, and the variable was unset for both runs.
- Recorded for honesty: on the *first* of two full-suite runs, `tests/test-build-script.sh` T9
  also failed, reporting `tests/test-landing-structure.sh` as not wired into a workflow. It did
  not reproduce on the second full run, nor on a direct re-run, nor on a clean worktree at the
  baseline commit `68ca1fb`. This change touches no test and no workflow file, and no tracked
  test writes to `.github/workflows/`. Treated as a transient in the harness, not a finding.

---

## 7. Unresolved gates

**None.** Both gates pass on the built tree:

- **Gate 1** — `quick_validate.py` exit 0 (*"Skill is valid!"*); 426 lines (< 500); 2893 `asm`
  words (< 3000); frontmatter audit 15/15 with the negative-trigger clause, `metadata.version`
  `0.6.0` and `metadata.author` present; `docs/README.md` opens with the AI-skip comment;
  bundled scripts print descriptive stderr; the dependency preflight is correctly absent
  because the condition does not fire.
- **Gate 2** — `asm eval` overall **97** (> 85), minimum category **8** (>= 8).

Two items are deferred rather than unresolved, and both are named above rather than folded
away:

1. `context-efficiency` scores **8**, not 10, because the evaluator's top band is 120–1500
   words. Reaching it is not available to this skill: the ADR's measurement puts its
   assertion-pinned floor at **1752–1831** words, above the band's ceiling before a single word
   of free prose. 8 clears the gate. The body is held at 2893 rather than pressed against 3000
   so the next edit has room to add a sentence without re-breaking the category.
2. Predictability item **#3** is open and advisory: the step tracker is a display convention,
   not a stated gate. See §3 for why it was not closed in this pass.
