# skill-auto-improver run — `/issue-triage`

**Issue:** [#418](https://github.com/luongnv89/idd/issues/418) · part of epic #413
**Target:** `src/skills/issue-triage/` (measured against built `skills/issue-triage/`)
**Measuring standard:** `skill-auto-improver` v2.1.0 · `asm` v2.7.0
**Mode:** Mode 1 — retrofit. Mode 2 (delegation conversion) declined; see §4.
**Date:** 2026-08-28

Measurement convention, unchanged from [#416](https://github.com/luongnv89/idd/issues/416)
and [#419](https://github.com/luongnv89/idd/issues/419): `src/skills/<name>/` holds
`SKILL.source.md`, not `SKILL.md`, so `quick_validate.py` and `asm eval` cannot read the
authored source. Every measurement below was taken read-only against the built tree
(`skills/issue-triage/`); every edit was landed in `src/skills/issue-triage/` and the built
tree regenerated with bare `./scripts/build.sh` (compile → verify → promote).
`asm eval --fix` was never run against `skills/`.

Body size was measured two ways. `wc -w`/`wc -l` on the file is the working number;
`asm eval` strips the YAML frontmatter first, and that is the number Gate 2 scores. This
skill's frontmatter is **74 words**, so its two numbers sit 74 apart at both ends of the
pass. Source and built `SKILL.md` measure identically (3048 words / 405 lines) — the build
rewrites reference tokens (`docs/X.md` → `references/docs/X.md`) without changing word or
line counts.

**What this pass is, in one line.** Deletion of duplicated navigation, three restatements
of one topology, and a duplicated defaults table, plus in-place compression everywhere
else. **No material was moved into this skill's `references/`** — `git diff --stat` for the
whole branch touches exactly two files, `SKILL.source.md` and its built counterpart — so
decision **D3** of `docs/decisions/shared-contract-pin-artifact.md` (*relocation is not a
word-cap strategy*) is not engaged. The 825 `asm` words this pass removed are words the
agent no longer loads, not words that moved somewhere it still loads them from. One
qualification to that claim is recorded in §1.

---

## 1. Gate status — baseline → final

| Gate | Check | Baseline | Final |
|------|-------|----------|-------|
| **Gate 1** | `quick_validate.py` exit | 0 (pass) | **0 (pass)** |
| Gate 1 | Frontmatter audit (`asm eval` → `checks`) | all pass | **all pass** |
| Gate 1 | Body under 500 lines | 498 (pass — 2 from the cap) | **405 (pass)** |
| Gate 1 | Body under 3000 words | **3799 (FAIL)** | **2974 (pass)** |
| Gate 1 | Negative-trigger clause in description | pass | pass (description untouched) |
| Gate 1 | `metadata.version` semver + `metadata.author` | pass (0.5.5) | **pass (0.6.0)** |
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
`prompt-engineering` 1 (*"Body is very long (3799 words)"*), so one measurement moved two
categories. Final findings: *"Body length within healthy range (2974 words)."*

Body size, command of record:

```
wc -w < src/skills/issue-triage/SKILL.source.md   # 3873 → 3048
wc -l < src/skills/issue-triage/SKILL.source.md   #  498 →  405
```

`metadata.version`: **0.5.5 → 0.6.0** (minor — no restructure, but view mode gained two
new instructions it did not have: an explicit run-stats footer at every view-mode exit, and
a bundled dependency precheck before its first bundled-file read).

### The budget this pass had to hit, and how it was hit

`docs/decisions/shared-contract-pin-artifact.md` measured `/issue-triage` at 3799 `asm`
words with an assertion-pinned floor of **2767–2804** and only **995–1032 words of free
prose** against a required cut of **799**. That arithmetic assumes cuts are whole-line
deletions of unpinned prose. The actual pass cut **825** `asm` words, more than the free
prose alone allows, because most of it came from *compressing assertion-carrying lines
around their pinned literals* — the same mechanism the ADR names when it declines to treat
`/auto-pilot`'s pre-compression floor as a floor. **No assertion was deleted or loosened,
and no D4 exception was needed.**

An independent pinned-word measurement taken at the baseline commit, by the ADR's method
(83 tracked suites traced under `bash -x`, every `grep` pattern extracted from the traced
command line rather than guessed, replayed against both the source and the built body and
unioned) put 110 lines / 2155 words under at least one assertion. That set was replayed
after every edit.

### What was removed, and what it cost

| Cut | Where it survives | `wc` words |
|---|---|---:|
| *Additional Resources* index (4 entries) | Three are named by the *Bundled dependency precheck* list; all four paths remain cited at their use sites. | ~75 |
| *Parallel execution* and *Batch splitting* subsections, incl. two ASCII diagrams | The orchestrator diagram already stated per-batch spawn, `scope: "both"`, ~5-issue batches, merge and cross-batch edges. `references/detection.md` and the payload contract survive in the prose that replaced them. | ~150 |
| *Environment check*'s third statement of the batch-splitting rule | The orchestrator diagram (`10+ issues → parallel batches of ~5`). | ~25 |
| Config defaults **table** | The four key names and their defaults stay inline in the body; the one-line glosses were a duplicate of the bundled `docs/config-schema.md` *triage* section (which the build emits with both the commented schema and a defaults table) and the body cites it by name. | ~45 |
| Second `gh issue list` command (closed issues) | *"With `triage.include_closed` true, run the same command with `--state closed` and merge."* | ~20 |
| Duplicated *"Do not re-read the config at each step"* and *"If the config file exists but contains invalid values…"* | The Configuration paragraph's *never re-read it* clause and its exit-3 branch. | ~30 |
| `## Platform Driver`, `## GitHub Projects Sync`, `## Example Runs` headings | Folded into `## Output Conventions` as three sentences carrying every citation they had (`docs/platform-github.md`, `docs/github-projects-sync.md`, `references/examples.md`, `read-only`). | ~40 |
| *"Future versions may reorder project board items based on triage priority."* | Nowhere — deliberately. A forward-looking note that changes nothing an agent does is the rubric item-6 no-op. | ~13 |
| In-place compression: every remaining section | Same instruction, fewer words. | ~440 |
| **Added** — view-mode run-stats footer + view-mode precheck (§5) | — | **+60** |
| **Added back** — `Progress output:` label and the two full section names in *Expected Output* | — | **+10** |

**Two changes are called out rather than folded into "no behavior change".**

1. **A printed string moved out of its fence.** *Final Report*'s cached variant used to be a
   complete second fence. It now prints *"that same block under the header
   `◆ Issue Triage — cached`, with only these rows:"* followed by the four rows that
   differ. The rendered output is unchanged, but `◆ Issue Triage — cached` and its `┄`
   rule are now inline prose rather than fenced example lines, and an agent reading only
   the fence would no longer see the header. This follows the precedent `/issue-analysis`
   set in #419.
2. **The `--state closed` command is now derived, not spelled out.** The fenced duplicate
   of the Step 1 `gh issue list` line is gone; the instruction says to run *the same
   command* with `--state closed`. The `--json` field set is therefore inherited rather
   than restated.

**One qualification to "nothing was relocated".** The config defaults *table* was deleted,
not moved: its four key names and default values remain inline in the body, and its one-line
glosses already existed verbatim in `docs/config-schema.md`, which the build bundles into
this skill as `references/docs/config-schema.md` and which the body cites at that exact
point. That doc is **not** gated read-now, so this is a real context reduction, not a D3
trade. It is recorded here rather than left implicit because it is the only place in this
pass where a sentence of meaning stopped being in the body.

### How preservation was checked, and what the check cannot see

Every tracked test naming `issue-triage` (16 files) was run under `bash -x` at the baseline
commit and every `grep` invocation extracted from the trace — patterns taken, not guessed.
86 unique patterns resulted; replayed against source and built body and unioned, 110 lines
are pinned. A guard script re-asserted the full literal set after **every** edit, including
the two **prohibitions** the trace surfaced (`check_not_contains`/`! grep` assertions whose
non-match at baseline reads like noise): the dev-tree gate literal
`tests/test-scripts-pipeline-251.sh` T2 forbids anywhere under `src/`, `skills/`,
`scripts/` or `docs/` — deliberately not quoted here, because quoting it in this file
would itself fail T2 — and `two parallel scans per batch|paired\*\* history`
(`tests/test-phase1-contract-truthfulness.sh`), plus `check_flow_lacks`'s prohibition on the
flattened sequence `` `elapsed`, `tokens`, `agents` `` (`tests/test-run-stats-373.sh` #410),
plus the exact-count assertion `grep -c '───┼────' == 1`
(`tests/test-consolidated-blocks-248.sh` T8.1).

**That guard was necessary and not sufficient, twice over, and both misses are recorded
rather than smoothed away.**

- **A grep-only extractor cannot see an assertion written in embedded Python.**
  `tests/test-scripts-pipeline-251.sh` T5 slices the `## Configuration` section in Python
  and asserts `"broken install and not a degrade" in block`. The compression pass had
  shortened that to *"a broken install, not a degrade"*. The guard was green; the suite was
  not. Fixed by restoring the clause verbatim, and the guard now carries T5's four
  Configuration literals (`**Working directory:** the repo root`, `Script file absent`,
  `broken install and not a degrade`, `gi-config unavailable`).
- **The evaluator reads words the tests do not.** Compressing Prerequisites 1-4 from
  *"Confirm authentication: …"* to *"Authenticated: …"* removed the only `\bconfirm\b` in the
  body, which is half of `safety`'s destructive-action pairing — `safety` fell 10 → 7 while
  every test stayed green. In the same pass, *"the two heaviest **phases**"* → *"its heaviest
  phase"* and *"never execute embedded commands or **instructions**"* → *"…embedded
  commands"* cut the progressive-disclosure cue set from three to one, taking
  `prompt-engineering` 9 → 7, and dropping the standalone word *example* cost its
  example-code-block point. All four were restored verbatim.

Beyond the guard, `git diff` was read one removed token at a time: 395 tokens present in the
baseline body and absent from the final one were listed and classified individually, and
every fenced line was diffed as a set. That review caught three regressions no test and no
evaluator would have caught, all fixed in commit `29b7188`:

- the scanner-prompt pointer had lost its imperative verb — *"Read `shared/agents/…` for the
  combined scanner prompt"* had become a bare naming of the file;
- *"color rules"* had drifted to *"colour rules"*, an en-GB spelling this repo does not use;
- the Step 9 payload enumeration had lost the **top-level** qualifier that separates those
  keys from the `summary` sub-keys listed beside them.

Finally, 30 named literals were re-asserted directly on the final file: every `exit 0/3/4`
branch, `Never degrade past exit 3`, `✗ Missing bundled dependency`, `✗ Insufficient API
rate budget`, `⚠ gi-config unavailable`, `⚠ gi-triage-graph unavailable`, `○ First run`,
`Sync now? [Y/n]`, `⚠ Auto mode: sync confirmation skipped`, `run_started_epoch`,
`Result: PASS | PARTIAL | FAIL`, both `shared/scripts/*.py` tokens, the
`shared/agents/issue-relationship-scanner.md` token, and all seven `docs/*.md` runtime
references. All present. The body carries no `<!-- a:… -->` anchor, so none could be lost.

---

## 2. Gate 1 — the two conditional items

**Dependency preflight: not applicable, and correctly absent.**
`references/skill-creator-checklist.md` §8 makes the section conditional on a target that
*invokes another skill*, and states that *"adding an empty one is itself a defect."* All
three signals were scanned across the source package:

- **Calls `/other-skill`?** No. `/issue-resolver {first}` (the *Next action* row of both
  Final Report blocks), `/issue-creator` (the empty-state tip) and `/init-gitissue` (the
  `○ First run` line) are strings printed **to the user** as advice, not invocations.
  `/issue-analysis` and `/auto-pilot` appear only as prose references to neighbouring
  skills.
- **Delegates a phase to a named skill?** No. Steps 1b & 2 are delegated to a shared **agent
  prompt** (`shared/agents/issue-relationship-scanner.md`) through the Agent tool. An agent
  prompt is not a skill and has no installer.
- **Reads a path under `~/.claude/skills/`, `~/.agents/skills/`, `~/.codex/skills/`?** No —
  grep across `SKILL.source.md` and all five `references/*.md` returns nothing. The single
  `asm install` occurrence is the *self*-reinstall command inside the `✗ Missing bundled
  dependency` block, which is the bundled-dependency guard, not a dependency on another
  skill.

The condition does not fire, so nothing is required and nothing was added.

**Bundled scripts print descriptive stderr: verified, not assumed.** Both bundled scripts
were executed from the built tree. `--help` exits 0 for `gi-config.py` and
`gi-triage-graph.py`. Against a deliberately malformed `.gitissue.yml`, `gi-config.py`
prints `✗ Invalid .gitissue.yml: …` with the parser's line and column to stderr and exits
**3**; `gi-triage-graph.py` fed an issue without a number and an out-of-range
`triage.stale_threshold_days` prints `✗ gi-triage-graph: triage.stale_threshold_days must be
an integer >= 1, got '[oops'` and exits **3**. Both exit-3 paths are routed to a **stop**,
not a degrade, in the body, and that routing was preserved verbatim — including the literal
*Never degrade past exit 3*.

---

## 3. Predictability audit (Phase 2b — advisory, never gates)

Rubric resolved at `~/.claude/skills/skill-auto-improver/references/predictability-audit.md`
(no fail-soft skip). Walk of all 7 items:

| # | Rubric item | Verdict | Note |
|---|-------------|---------|------|
| 1 | Invocation chosen intentionally | **pass** | User-invoked, and the shape matches: the body opens on an *Invocation* table of four forms (`/issue-triage`, `update`, `--limit N`, `… --auto`) and reads as "the user asked for this, proceed". The description keeps its negative-trigger clause because `/auto-pilot` reaches this skill model-invoked, and `compatibility` states the view-mode carve-out (*"Default mode (cached view) needs only local file access — no gh required"*) so the cheap branch is discoverable before the body is read. |
| 2 | Branches mapped before the body | **pass** | Three orthogonal branches are selected before any step runs, each named in one place: **mode** (view vs. update — decided in *Invocation* and *Default Mode*, both above *Prerequisites*; view mode never enters Steps 1-9); **auto vs. interactive** (`--auto`, deferred to `docs/auto-mode.md`; the skill has exactly one blocking prompt, `Sync now? [Y/n]`, and its auto carve-out is stated at that gate); **Agent tool available vs. not** (*Environment check*, the sole gate on the inline procedure). |
| 3 | Demanding, checkable completion criteria | **pass** | Stronger than its sibling's. Each step closes with `√`/`×` per check plus a `Result: PASS \| PARTIAL \| FAIL` line, and the body states the gate outright — *"No step is complete until its `Result:` line prints."* `/issue-analysis` has no equivalent sentence, which #419 recorded as an open advisory; `/issue-triage` does. The Final Report ends on a literal `Result: DONE` or `Result: CACHED`; Step 9's success bar is a named top-level key set plus six `summary` sub-keys; the empty state and the rate-budget threshold are both hard stops with stated numbers (0 open issues; `remaining` below 100). |
| 4 | Progressive disclosure + delegability | **pass** (this pass fixed the disclosure half) | Was 3799 `asm` words at 498 lines — two lines from `tests/test-skill-line-cap-247.sh`'s `CAP=500` — with a redundant resource index and three renderings of one topology. Now 2974 words / 405 lines. The two every-run specs are one-line read-now pointers (`references/detection.md` at Steps 1b & 2, `references/output-and-persist.md` at *Step completion reports*), which is what `tests/test-disclosure-gates-250.sh` AC1.6 and AC3.2 assert. Delegability sub-check below. |
| 5 | Leading words | **pass** | Recurring concepts are named once and referred to by name: *view mode*, *stash-first sync*, *Bundled dependency precheck*, *Run Stats Footer*, *full-scope scanner*, *auto mode*, *degrade vs. stop*, *prose procedure*. This pass extended the pattern rather than breaking it — *Environment check* now cites the orchestrator diagram's batch rule instead of restating it, and the Configuration section's two separate "never re-read the config" sentences became one clause. |
| 6 | No duplication / stale sediment / sprawl / no-ops | **pass** (this pass fixed it), one item left open | **Removed:** the *Additional Resources* index; the *Parallel execution* and *Batch splitting* diagrams (both restating the orchestrator diagram above them); *Environment check*'s third statement of the batch rule; the config defaults table (duplicating the bundled `docs/config-schema.md` *triage* section); the duplicate `gh issue list --state closed` fence; the second "never re-read the config" sentence; the "invalid values" sentence duplicating the exit-3 branch; three single-pointer sections folded into *Output Conventions*. **No-op removed:** *"Future versions may reorder project board items based on triage priority"* — a forward-looking note that changes nothing an agent does. **Stale sediment fixed:** the precheck list described `references/docs/idd-methodology.md` as *"IDD methodology (durable analysis fields)"*; durable analysis fields are `/issue-analysis`'s use of that doc, and `/issue-triage` cites it for the `Depends on #N` / `Blocked by #N` marker grammar. Corrected to *"dependency markers"*. **Left open, advisory:** the *Final Report* tracker labels (`Fetch issues`, `Already-fixed`, `Dependencies`, `Circular deps`, `Execution order`, `Parallelizable`, `Stale detection`, `Priority`, `Persist`) and the step headings (*Step 1*, *Steps 1b & 2*, *Steps 3-7*, *Step 8-9*) name the same nine units of work in two vocabularies. Both label sets are printed strings — changing either changes output — so neither was touched. |
| 7 | Publish-ready — no auto-improver dependency | **pass** | `quick_validate.py` exit 0 (*"Skill is valid!"*), `asm eval` 97/A with no category below 8, 402 lines, description carries the negative-trigger clause, `metadata.version`/`author`/`license` present, `docs/README.md` opens with the AI-skip comment. The skill clears the standard without a follow-up auto-improver run. |

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
| **Steps 1b & 2 — Already-Fixed & Dependency Detection** | yes — a per-batch fan-out over a whole-codebase keyword scan, bounded by `triage.scan_timeout_per_issue` | **yes — and already delegated.** Spawned as `shared/agents/issue-relationship-scanner.md`, one full-scope scanner per batch, with `references/detection.md` named as the slice carrying the subagent prompts, confidence-scoring rules and merge logic, gated **read it now**. The payload is pinned (`{ issues: [{number, title, body}], repo_root, scan_timeout, scope: "both" }`) and so is the return (potentially-fixed issues, affected files, directed edges). |
| **Steps 3-7 — Order, Parallel Sets, Staleness, Priority** | borderline — one script call plus a five-row outcome classification | **steps 3-7 are not delegable because their slice is what every run reads anyway.** The happy path is a single `gi-triage-graph.py` invocation, which fails **context weight** outright; the degrade path is the prose procedure in `references/detection.md`, which the run has already loaded in full at Steps 1b & 2. |
| **Step 8-9 — Output & Persist** | yes — a rendering spec plus a JSON schema | **step 8-9 is not delegable because its slice is what every run reads anyway.** `references/output-and-persist.md` is gated **read it now** before Step 1 for the step-completion format, so handing it to a worker withholds nothing. It also fails **Independence**: the table is rendered from the script's exact payload, not from a stated result. |
| **Step 1 — Fetch Issues** | no | **step 1 is not delegable because it is a single fetch and two guards** — one `gh issue list`, a >100 warning, an empty-state stop. It fails **context weight**, the first test, which ends the walk. |
| **View mode (Default Mode 1-4)** | borderline — a cache read, a render, and three local checks | **view mode is not delegable because it is the whole run** — there is no orchestrator left behind to receive a worker's return, and its render spec is inline in *Default Mode → 3* rather than in a separable slice. |
| **Prerequisites / Repo Sync / Configuration** | no | **not delegable because they need the user mid-step** — *Repo Sync* asks `Sync now? [Y/n]` in interactive mode, and the config load must happen in the orchestrator's own shell because that is where `run_started_epoch` is captured (`python3 …; ec=$?; date +%s >&2; exit "$ec"`). A worker's shell exits taking the value with it — the exact failure `delegation-conversion.md` → *Deriving the slice* item 5 warns about. |
| **Final Report** | no | **not delegable because it depends on the previous steps' exact text** — every tracker row is filled from a count the orchestrator already holds. Fails **Independence**. |

**Pass.** The one genuinely heavy phase already names its slice and already runs in a
subagent; every other step is recorded with the named test it fails. Advisory only — this
did not gate the PASS.

---

## 4. Delegation-conversion decision (Mode 2)

**Declined.**

**Named precondition it failed**, verbatim from `skill-auto-improver`'s
`references/delegation-conversion.md` → *When Mode 2 applies*, item **4**:

> **The user has confirmed the restructure in this run.** Name the steps you would convert
> and the version bump it forces, and wait. A conversion rewrites the skill's workflow; it
> is never something this skill decides on the user's behalf.

No user is present in this run and no confirmation was given, so the precondition fails
literally. `delegation-conversion.md` states the consequence in *When conversion does not pay
for itself*: the finding stays advisory and Mode 1 never converts a skill quietly. That
settles the mode on its own.

**Supporting observation — not a second precondition.** The conversion would also have had
little to convert:

- The only heavy phase, Steps 1b & 2, **already** runs in a subagent through the canonical
  `Agent(...)` pattern, **already** names `references/detection.md` as the worker's slice,
  and **already** pins both the `Input` payload and the `Output` shape. The restructure
  Mode 2 performs is the shape this step already has.
- The two remaining candidates, Steps 3-7 and Steps 8-9, both match *When conversion does
  not pay for itself* → **"Nothing to withhold. No `references/` tree, or one file every run
  reads anyway."** Both slices (`references/detection.md`, `references/output-and-persist.md`)
  are gated read-now, so a worker would be handed a file the orchestrator has already loaded.
- Precondition **3** (*"At least one step is heavy … and is not ruled out by Identifying a
  delegable step"*) therefore also misses: every heavy step is either already delegated or
  ruled out by a named test in §3's sub-check.

A recorded decline is the complete outcome here. `SKILL.md` should **net shrink** under a
conversion; this one would net grow, because the delegation is already documented and the
only thing left to add would be two worker contracts over material the orchestrator reads
regardless.

---

## 5. Run-stats footer (issue #414 shape) — AC4

The field set is `elapsed` · `tokens` (conditional) · `agents`, two lines, printed **last at
every terminal outcome**. It was **not widened, reordered or renamed** — that claim stands
unqualified. The contract lives in `references/run-stats.md`, byte-identical across skills;
`tests/test-run-stats-373.sh` (156 checks) passes on both the source and the built tree, and
`references/run-stats.md` was not touched by this pass.

The body's call-site sentence kept its pinned shape and was reworded only in its
illustrative tail:

> **Then the run-stats footer.** Close with the *Run Stats Footer* — `references/run-stats.md`
> — `elapsed`, `tokens` only where the host reported a count (otherwise left out), `agents`,
> run cost only, `n/a` for anything else undetermined. It is the last thing printed at
> **every** terminal outcome, including a run that ended early — no open issues, a failed
> fetch, an invalid config, a timed-out scan.

**AC4 asks for more than that sentence, so it was checked rather than asserted.** That
enumeration is illustrative (*"including"*) and names four early exits out of at least nine
the body actually has. The exhaustive rule is in `references/run-stats.md` → *Every terminal
outcome*, which is exhaustive **by construction** rather than by list: *"The footer prints
wherever the run stops, not only where it succeeds … A run that produced no output at all is
the only run without a footer."*

**AC4 holds for every exit from the pipeline** on the blanket sentence plus that
construction. The four prerequisite failures (`git rev-parse`, `which gh`, `gh auth status`,
`git remote -v`), the rate-budget stop, the missing-bundled-dependency stop, the invalid-config
stop, the `gi-triage-graph` exit-3 stop and the empty-state stop are all early exits *from*
the run the *Final Report* section closes, and *"every terminal outcome"* scopes over them by
construction even though none is enumerated. No footer instruction was added at any of those
sites, and none should be — adding one per stop is the bloat the predictability audit forbids
by name.

**View mode is the one case that does not follow from that, and it was closed in this pass.**
The asymmetry is not arbitrary. *Final Report* opens *"With the triage table (Step 8) and
persist (Step 9) complete…"*, and view mode enters neither step — it is not an early exit
*from* the pipeline, it is a branch that never enters it, so the sentence's own scope excludes
it and a reader following the view-mode branch never passes the instruction at all. The
section previously ended *"After the suggestion (or the 'up to date' message), **stop**. View
mode never writes to the file or makes API calls beyond the local git log check."* It now
reads:

> Every view-mode exit — corrupted cache, or a rendered report with or without a suggestion —
> closes with the *Run Stats Footer* (`references/run-stats.md`), then **stops**. View mode
> never writes the file and makes no API call beyond that git log; it skips *Configuration*,
> so there is no `run_started_epoch` and `elapsed` prints `n/a`.

The stop condition and the no-write / no-API guarantee are carried forward into that same
sentence rather than dropped. Note the `n/a` consequence, which `references/run-stats.md`
already governs: view mode skips *Configuration*, so no `run_started_epoch` is captured and
`elapsed` prints the literal `n/a` — *"a stop before the config load has no anchor to measure
from"* — not a guess and not `0`.

**That addition exposed a second defect, pre-existing, and it was closed too.** `## Default
Mode` sat at line 29 and the *Bundled dependency precheck* at line 251, so a view-mode run
following the body top-to-bottom reached three instructions to read a bundled file —
`references/error-messages.md` twice (the corrupted-cache message and the empty-state message)
and now `references/run-stats.md` — with nothing on that path having verified any of them is
present. Under CLAUDE.md's *fatal vs. degrade* rule a missing bundled file is fatal, not a
degrade, and the precheck is the guard that detects it. The Default Mode preamble now runs the
precheck first:

> Invoked as `/issue-triage` (no `update`, no `--limit`), first run the *Bundled dependency
> precheck* below — view mode reads bundled files too, and a missing one is a broken install
> — then:

The forward reference by section name follows the pattern *Configuration* already uses, which
likewise sits above the section it names. No test covers this: the suite only pins that
`references/run-stats.md` appears somewhere in the body. Both additions total ~60 words and
were paid for out of the same pass's cuts; together they are why the bump is 0.6.0 rather than
0.5.6.

---

## 6. Files changed

| File | Change |
|---|---|
| `src/skills/issue-triage/SKILL.source.md` | 3873 → 3048 `wc` words, 498 → 405 lines; `metadata.version` 0.5.5 → 0.6.0; view-mode run-stats footer added and routed through the *Bundled dependency precheck*; `idd-methodology.md` precheck description corrected |
| `skills/issue-triage/SKILL.md` | regenerated (`./scripts/build.sh`) |
| `docs/experiments/skill-auto-improver-issue-triage.md` | this report |

No `references/*.md` file in the package was touched — a direct consequence of this pass being
deletion plus compression rather than relocation.

**Test suite of record** (`git ls-files 'tests/*.sh' | xargs -n1 bash`, serial,
`IDD_AUTO_MODE` unset): **82 passed, 1 failed** across 83 tracked scripts — identical to the
pre-change baseline on this machine.

- The single failure is `tests/test-runs-jsonl-rotation-354.sh` T4, the known macOS-only
  artifact (BSD `wc` pads its output, so `"       3" != "3"`). Unrelated to this change;
  reproduces on pristine `origin/main`; ubuntu CI is green.
- `tests/test-scripts-252.sh` AC1, the other known non-defect, **passed** — it fails only with
  `IDD_AUTO_MODE=1` exported, and the variable was unset for every run.
- `tests/test-scripts-pipeline-251.sh` T5 failed once mid-pass, on a real regression this
  report names in §1. It was fixed, not waived, and the suite has been green on it since.

---

## 7. Unresolved gates

**None.** Both gates pass on the built tree:

- **Gate 1** — `quick_validate.py` exit 0; 405 lines (< 500); 2974 `asm` words (< 3000);
  frontmatter audit clean with the negative-trigger clause, `metadata.version` `0.6.0` and
  `metadata.author` present; `docs/README.md` opens with the AI-skip comment; both bundled
  scripts print descriptive stderr and exit 3 on invalid input; the dependency preflight is
  correctly absent because the condition does not fire.
- **Gate 2** — `asm eval` overall **97** (> 85), minimum category **8** (>= 8).

**No D4 exception was invoked, and none is owed.** The ADR predicted `/issue-triage` clears;
it clears.

Two items are deferred rather than unresolved, and both are named above rather than folded
away:

1. `context-efficiency` scores **8**, not 10, because the evaluator's top band is 120–1500
   words. Reaching it is not available to this skill: the ADR's measurement puts its
   assertion-pinned floor at **2767–2804** words, above the band's ceiling before a single
   word of free prose. 8 clears the gate. The body is held at 2974 rather than pressed against
   3000, though that leaves less room for the next edit than `/issue-analysis` kept.
2. Predictability item **#6** leaves one advisory open: the *Final Report* tracker labels and
   the step headings name the same nine units of work in two vocabularies. Both are printed
   strings, so reconciling them changes output. See §3.
