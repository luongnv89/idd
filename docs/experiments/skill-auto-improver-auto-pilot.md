# skill-auto-improver run — `/auto-pilot`

**Issue:** [#415](https://github.com/luongnv89/idd/issues/415) · part of epic #413
**Target:** `src/skills/auto-pilot/` (measured against built `skills/auto-pilot/`)
**Measuring standard:** `skill-auto-improver` v2.1.0 · `asm` v2.7.0
**Mode:** Mode 1 — retrofit. Mode 2 (delegation conversion) declined; see §4.
**Outcome:** Gate 2 passes on overall score; **Gate 1's word cap and Gate 2's
`context-efficiency` floor are a recorded D4 exception**, not a pass. See §6.
**Date:** 2026-08-28

Measurement convention, unchanged from #416/#418/#419/#420/#421: `src/skills/<name>/`
holds `SKILL.source.md`, not `SKILL.md`, so `quick_validate.py` and `asm eval` cannot
read the authored source. Every measurement below was taken read-only against the built
tree (`skills/auto-pilot/`); every edit landed in `src/skills/auto-pilot/` and the built
tree was regenerated with bare `./scripts/build.sh` (compile → verify → promote).
`asm eval --fix` was never run against `skills/`.

Body size was measured two ways. `wc -w`/`wc -l` on the file is the working number;
`asm eval` strips the YAML frontmatter first, and that is the number Gate 2 scores.
This skill's frontmatter is **85 words**, so its two numbers sit 85 apart at both ends
of the pass.

**What this pass is, in one line.** Deletion of a duplicated resource index, of the
31 per-file glosses on the bundled-dependency precheck list, of a run-log paragraph
that `references/run-log.md` already owned in full, and of four *Edge Cases* bullets
that restated Prerequisites 8 and 9 and two config keys — plus in-place compression of
every remaining section around its pinned literals. **No material was moved into this
skill's `references/`**, so decision **D3** of
`docs/decisions/shared-contract-pin-artifact.md` (*relocation is not a word-cap
strategy*) is not engaged: the words this pass removed are words the agent no longer
loads, not words that moved somewhere it still loads them from. One addition runs the
other way and is called out in §2 — the *Dependency Preflight* section, which is a
Gate 1 requirement this skill was missing.

---

## 1. Gate status — baseline → final

| Gate | Check | Baseline | Final |
|------|-------|----------|-------|
| **Gate 1** | `quick_validate.py` exit | 0 (pass) | **0 (pass)** |
| Gate 1 | Frontmatter audit (`asm eval` → `checks`) | all pass | **all pass** |
| Gate 1 | Body under 500 lines | 481 (pass) | **428 (pass)** |
| Gate 1 | Body under 3000 words | **5941 (FAIL)** | **5182 (FAIL — D4 exception, §6)** |
| Gate 1 | Negative-trigger clause in the description | pass | pass (description untouched) |
| Gate 1 | `metadata.version` semver + `metadata.author` | pass (2.5.0) | **pass (2.6.0)** |
| Gate 1 | `docs/README.md` opens with the AI-skip comment | pass | pass (untouched) |
| Gate 1 | Bundled scripts print descriptive stderr | pass | pass — executed, §2 |
| Gate 1 | Dependency preflight (conditional) | **applies, and was INCOMPLETE** | **closed — §2** |
| **Gate 2** | `overallScore > 85` | 93 (grade A) | **93 (grade A) — pass** |
| Gate 2 | every category `>= 8` | **min 6 — `context-efficiency` (FAIL)** | **min 6 (FAIL — D4 exception, §6)** |

Per-category (`asm eval --json`, built tree):

| Category | Baseline | Final |
|----------|---------:|------:|
| structure | 10 | 10 |
| description | 10 | 10 |
| prompt-engineering | 9 | 9 |
| context-efficiency | **6** | **6** |
| safety | 10 | 10 |
| testability | 10 | 10 |
| naming | 10 | 10 |
| **overall** | **93** | **93** |

Body size, command of record:

```
wc -w < src/skills/auto-pilot/SKILL.source.md   # 6026 → 5267
wc -l < src/skills/auto-pilot/SKILL.source.md   #  481 →  428
```

`asm eval` body words: **5941 → 5182** (−759). `metadata.version`: **2.5.0 → 2.6.0**
(minor — no restructure, but the skill gained two instructions it did not have: a
complete *Dependency Preflight* gate, and a run-stats footer bound to the pre-loop
stops that never reach *Final Summary*).

Every evaluator cue that scored at baseline still scores. The findings strings are
byte-identical apart from the word count: `prompt-engineering` still reads
*"Progressive disclosure cues present: overview, instructions, phases"*, *"Includes
example code block"*; `safety` still reads *"Covers multiple safety cues (confirm,
confirmation, error, errors)"* and *"Destructive actions paired with
confirmation/dry-run"*; `testability` still reads *"expected output, edge case, edge
cases, test"*. This was re-checked after **every** commit, not only at the end —
#418 lost four such cues at no word-count change, and the same failure mode was live
here because this pass deleted the `## Edge Cases`, `## Platform Driver` and
`### Why Subagents & What the Main Agent Does` headings and lowercased several
sentence-initial cue words.

### How preservation was checked

Thirty tracked suites name `auto-pilot`. Each was run under `bash -x` at the baseline
commit and every `grep` invocation extracted from the trace — patterns taken from the
traced command line, never guessed. 325 unique patterns resulted; replayed against the
body, **110** are live (they match at baseline), pinning **113 lines / 3384 words** of
the 6024-word baseline. A guard script re-asserted that full set after **every** edit.

**The guard was necessary and not sufficient, and both misses are recorded rather
than smoothed away.**

- **A flag-normalisation bug silently dropped 9 patterns.** The extractor kept `-e`
  in the replay flag list, so `grep -qiF -e PATTERN FILE` replayed as
  `grep -n -iF -e -e PATTERN`, matched nothing, and was scored "not live". The suite
  caught what the guard did not: `tests/test-runs-jsonl.sh` T3 requires the literal
  `non-fatal` in the body, and a compression sweep had removed it. Fixed in the
  source, the extractor corrected, and the baseline re-recorded from
  `git show ac633a9:…` so the whole pass was re-verified against the larger set. Two
  later edits were caught by the corrected guard before any test ran.
- **Line-wrapping broke two literals without deleting a word.** `grep` is
  line-scoped, so re-wrapping `may gate duplicated work, never a safety gate` and
  `every processed issue including skips` across a newline unpinned both. Neither is
  a content change; both were re-wrapped onto one line.

Beyond the guard, `git diff` was read one removed token at a time: **222** tokens
present in the baseline body and absent from the final one were listed and classified
individually. That review caught two regressions no test and no evaluator would have
caught, both fixed before the final commit:

- the *Additional Resources* index was the only place the body said the subagent
  prompts live in `references/subagent-prompts.md` and are **read once at skill
  start**. Deleting the index dropped that timing instruction — the file was left
  named only in the bare precheck list. Restored at *Subagent Architecture*, where
  the spawns are described.
- compressing *Subagent Architecture* had replaced the per-lane field list (*"each
  lane's issue, title, branch, PR, phase, and result"*) with a pointer to
  `references/orchestration.md`. That file documents the lane **phases**, not the
  lane **fields**, so the pointer was to something that is not there. The field list
  was restored inline.

Three losses are deliberate and are recorded rather than claimed as "no change":

1. `CHANGELOG.md` / `docs/release-notes/` version-history note (~22 words) — a
   pointer that changes nothing an agent does, the rubric item-6 no-op.
2. The `DESIGN.md` parenthetical on `docs/terminal-style.md` (*"the repo-root
   `DESIGN.md` is the human-facing companion and is not bundled"*) — human-facing
   provenance, not an instruction.
3. `.gitissue/run-state.json` *"that the next run overwrites"* — the lifetime
   contrast survives in the retained clause and in full in `references/run-log.md`
   → *Run log vs. run state*, which the body gates **read it now** before the write.

Finally, the anchors were re-asserted directly: `<!-- a:ap-skill-title -->`,
`<!-- a:ap-autonomy -->` and `<!-- a:ap-snapshot-budget -->` are all present and
each appears exactly once. The exact-count assertion
(`tests/test-consolidated-blocks-248.sh` T3.2 — the legacy `auto_merge` → mode
mapping stated exactly once across `SKILL.md`, `phases.md` and `configuration.md`)
still counts 1. Both prohibitions were re-asserted after every edit: the flattened
run-stats field list forbidden by `tests/test-run-stats-373.sh` #410, and the
"captures a second start time" phrasing forbidden by its AC4. The structural
assertions were re-asserted too — the `1. **Auto-decide**` / `2. **Confirm with
user**` list boundaries that `tests/test-autopilot-dependency-gate.sh` T10.2 walks
with `awk`, the `## Configuration` block that `tests/test-scripts-pipeline-251.sh`
T5 slices in embedded Python, and the *Bundled dependency precheck* heading whose
section T1 requires to name every bundled script.

### What was removed, and what it cost

| Cut | Where it survives | `wc` words |
|---|---|---:|
| *Additional Resources* index (5 entries) | Every path is still cited at a use site, except `docs/naming-conventions.md`, whose use sites are `references/phases.md` and `references/subagent-prompts.md`. The build still bundles it — the closure reads those files too — and the build is green. | ~69 |
| The 31 per-file glosses on the *Bundled dependency precheck* list | The list is a presence check; the paths are what is verified. One gloss is kept because a test pins it (`gi-ratelimit.py`). | ~230 |
| *"The run log is not the run state"* paragraph | `references/run-log.md` → *Run log vs. run state*, gated **read it now** before the write, which carries the same contrast as a table plus the double-counting rationale. | ~70 |
| Parallel-lane mechanics inside the single-writer paragraph | `references/run-log.md` → *Parallel resolver lanes*, same read-now gate. The two facts the body must state at its own call sites — append at *Phase 2.3* **before** `--failure-streak`, append at *Step 5.3* on success — were kept. | ~60 |
| Four *Edge Cases* bullets | Prerequisite 9 (merge permission), Prerequisite 8 (rate budget), and the `autopilot.quarantine_after` / `quarantine_label` defaults. Replaced by one sentence covering the two mid-run variants those bullets alone carried. | ~110 |
| `## Platform Driver`, `## Edge Cases`, `## Explicit List Mode`, `### Why Subagents & What the Main Agent Does` headings | Folded into *Output Conventions*, *Examples & Edge Cases*, *Mode Detection* and *Context Window Management*, each carrying every citation it had. | ~40 |
| Config-defaults glosses duplicating `references/configuration.md` | That file expands every key; the body keeps the key names, the values, and the two glosses that are operative rather than explanatory (`max_parallel` validation, `quarantine_label` append). | ~35 |
| In-place compression: every remaining section | Same instruction, fewer words. | ~410 |
| **Added** — `## Dependency Preflight (mandatory)` (§2) | — | **+150** |
| **Added** — run-stats footer bound to the pre-loop stops (§5) | — | **+40** |
| **Added back** — subagent-prompts pointer and the per-lane field list | — | **+30** |

---

## 2. Gate 1 — the two conditional items

### Dependency preflight: applies, was incomplete, now closed

`references/skill-creator-checklist.md` §8 makes the section conditional on a target
that **invokes another skill**. `/auto-pilot` fires that condition outright: it
invokes `/issue-triage`, `/issue-analysis`, `/issue-resolver` and `/issue-pr-review`,
and optionally `/issue-creator` mid-loop. It is the one skill in epic #413 where the
item applies.

The baseline carried a gate — Prerequisite 5 plus a `### Skill dependency precheck`
subsection routing to `references/preflight.md` — but it named only **two** of §8's
four required elements per dependency: the **name** and, via the error block, the
**install command**. A repo-wide grep confirmed that neither the **installer
bootstrap** (`npm install -g agent-skill-manager`) nor a **verification** step
(`asm list -p claude --json | grep …`) existed anywhere under `src/`.

The section is now a top-level `## Dependency Preflight (mandatory)`, placed above the
first mutating step (it precedes the run lock and the auto-stash), and carries all
four elements in a runnable form — detection, install, installer bootstrap, and
verification, all with the same `-p claude` so an install under a different provider
cannot report success while the dependency is missing:

```bash
for s in issue-triage issue-analysis issue-resolver issue-pr-review; do
  asm list -p claude --json | grep -q "\"$s\"" || {
    echo "Missing required skill: $s" >&2
    echo "Install it:      asm install $s -p claude --yes" >&2
    echo "No asm yet:      npm install -g agent-skill-manager" >&2
    echo "Verify:          asm list -p claude --json | grep '$s'" >&2
    exit 1
  }
done
```

The required-vs-optional split is preserved verbatim: a missing required skill stops
and prints the `✗ Missing required gitissue skill(s)` block, and `issue-creator` warns,
skips mid-loop normalization, and continues. So is the caller obligation — both
`--auto` and an exported `IDD_AUTO_MODE=1` — which is why the section names
`/issue-creator`'s Normalize apply gate as the one delegated gate sitting directly in
the loop's path.

### Bundled scripts print descriptive stderr: verified, not assumed

All ten bundled scripts were executed from the built tree. `--help` exits **0** for
every one. On invalid input, five exit **3** with a `✗`-prefixed message naming the
script and the field: `gi-config.py` (`✗ Invalid .gitissue.yml: …` with the parser's
line and column), `gi-runlog.py` (`✗ gi-runlog: missing required key(s): …`),
`gi-ratelimit.py` (`✗ gi-ratelimit: --threshold must be >= 0`), `gi-state.py`
(`✗ gi-state: --ttl must be zero or greater`) and `gi-triage-graph.py`
(`✗ gi-triage-graph: no request object on stdin`); `gi-ci-wait.py` and `gi-issue.py`
exit 3 on an out-of-range interval and TTL respectively. `gi-branch.py`, `gi-deps.py`
and `gi-gh.py` reject a malformed command line with argparse's own usage text and
exit **2** — the shared vocabulary's *usage error*, not a swallowed failure.
`gi-deps.py` has no invalid input by construction: it is a parser over arbitrary
issue text and reports no dependencies rather than failing.

Every exit-3 path the body routes is routed to a **stop**, not a degrade, and that
routing was preserved verbatim — including the `## Configuration` fatal branch
literals `Script file absent` / `broken install and not a degrade`, and the run-log
`**Exit 3:**` clause with `Correct the record and re-run, or drop the line.`

---

## 3. Predictability audit (Phase 2b — advisory, never gates)

Rubric resolved at `~/.claude/skills/skill-auto-improver/references/predictability-audit.md`
(no fail-soft skip). Walk of all 7 items:

| # | Rubric item | Verdict | Note |
|---|-------------|---------|------|
| 1 | Invocation chosen intentionally | **pass** | User-invoked, and the shape matches: the body opens on an *Invocation* table of eight forms and a *Combining flags* paragraph stating the three illegal pairs. The description keeps its negative-trigger clause naming the three skills a caller might reach for instead, and `compatibility` states the hard requirements (git, `gh` with auth and push access, merge permission for auto-merge, four sibling skills from the same distribution, `issue-creator` optional) before the body is read. |
| 2 | Branches mapped before the body | **pass** | Four orthogonal branches, each decided in one place above the phases: **mode** (triage vs. explicit list — *Mode Detection*); **merge mode** (`conservative`/`balanced`/`aggressive` × `merge_partial` — the *Merge Modes* table plus four resolution rules covering the legacy `auto_merge` fallback); **parallelism** (`max_parallel = 1` legacy path vs. bounded fan-out — *Subagent Architecture*); **run state** (`--resume` / `--fresh` / `--force-unlock` — *Invocation*, resolved at Phase 0 to `resumable`/`stale`/`absent`). The no-merge downgrade on insufficient permission is a fifth, decided at Prerequisite 9. |
| 3 | Demanding, checkable completion criteria | **pass** | Each phase closes with `√`/`×` per check plus a `Result: PASS \| PARTIAL \| FAIL` line, and the body states the gate outright — *"A phase is not complete until its `Result:` line is printed."* The loop's own terminal criteria are a 13-row *Stop Conditions* table, each row naming its exact printed string and its categorical outcome, and the six outcome labels are fixed and enumerated in three places that must agree (*Iteration Report*, *Stop Conditions*, *Final Summary*). |
| 4 | Progressive disclosure + delegability | **partial — the disclosure half is the open item** | 5182 `asm` words at 428 lines. The line cap is met with 72 lines to spare; the word cap is not, and §6 records why it is not reachable. The every-run specs are one-line read-now pointers (`references/summary-format.md` at *Step completion reports*, `references/run-log.md` before the write), which is what `tests/test-disclosure-gates-250.sh` AC3.2 asserts. Delegability sub-check below. |
| 5 | Leading words | **pass** | Recurring concepts are named once and referred to by name: *auto-decide* vs. *confirm with user*, *serialized drain*, *lane*, *Bundled dependency precheck*, *Dependency Preflight*, *Run Stats Footer*, *stop-and-ask exception*, *degrade vs. stop*, *body snapshot*. This pass extended the pattern — *Edge Cases* now defers to *Prerequisite 8* and *Prerequisite 9* by name instead of restating them, and *Subagent Architecture* defers to `references/orchestration.md` for the lane diagram instead of drawing a second one. |
| 6 | No duplication / stale sediment / sprawl / no-ops | **pass** (this pass fixed it), two items left open | **Removed:** the *Additional Resources* index; 31 precheck glosses; the run-log-vs-run-state paragraph and the parallel-lane mechanics, both owned in full by `references/run-log.md`; four *Edge Cases* bullets restating Prerequisites 8 and 9 and two config keys; the config-defaults glosses duplicating `references/configuration.md`; four single-pointer headings. **No-op removed:** the `CHANGELOG.md` / `docs/release-notes/` version-history note. **Left open, advisory:** (a) the *Caller-supplied context* paragraph is written as a change record — it names issues #256 and #285, a superseded literal, and two merged PRs — rather than as the contract it states; four of its clauses are pinned by `tests/test-subagent-context-256.sh`, so rewriting it as a plain contract would have to move those assertions first. (b) the six outcome labels are enumerated three times, in *Iteration Report*, *Stop Conditions* and *Final Summary*; all three are printed strings and two of the three are pinned line-by-line, so none was touched. |
| 7 | Publish-ready — no auto-improver dependency | **partial** | `quick_validate.py` exits 0 (*"Skill is valid!"*), `asm eval` 93/A, 428 lines, the description carries its negative-trigger clause, `metadata.version`/`author`/`effort` present, `docs/README.md` opens with the AI-skip comment, and the dependency preflight is now complete. The one item that would need a follow-up run is the word cap, and §6 records it as a D4 exception rather than as work outstanding. |

### Delegability sub-check (item #4)

Rule applied verbatim: *"a step heavy enough to hand off names no slice of
`references/` for its worker — record it as `step N is not delegable because <reason>`
(needs the user mid-step, depends on the previous step's exact text, or its slice is
what every run reads anyway). A skill with nothing to slice passes."*

Every step, walked. "Heavy enough to hand off" is judged by *Identifying a delegable
step*'s **context weight** test — a multi-file read, a per-item fan-out, or a fixed
procedure of a dozen-plus lines. `/auto-pilot` is the epic's most delegation-heavy
skill: three of its five phases already run outside the main agent.

| Step | Heavy enough to hand off? | Names its `references/` slice? |
|---|---|---|
| **Phase 2 — Resolve** | yes — a full resolve pipeline per issue, and under `max_parallel > 1` a per-item fan-out across isolated worktrees | **yes — and already delegated.** Spawned as `/issue-resolver --auto --no-run-log`. Its worker contract is `references/subagent-prompts.md` (*Resolver Subagent*, *Batch Resolver*), which the body names at *Subagent Architecture* and gates **read once at skill start**; the per-lane inputs (`{issue_payload}`, `{triage_context}`, the worktree) are pinned by name in the Phase 1 row and by `tests/test-subagent-context-256.sh`. |
| **Phases 3–4 — PR Review** | yes — the whole review-fix-CI cycle | **yes — and already delegated.** Spawned as `/issue-pr-review --auto --no-merge`, with the reviewer's trimmed input named (`{issue_payload_ids}`) and its prompt in `references/subagent-prompts.md`. The body states why the slice is trimmed and why `--no-merge` is not optional: merging is Phase 5's, and a reviewer that merges steals the dependency gate. |
| **Explicit-list analysis (replaces Phase 1)** | yes — a one-time multi-issue read that computes order, dependencies, shared files and batches | **yes — and already delegated.** A one-time analyzer subagent, with `references/explicit-list-mode.md` named as the slice carrying the parsing rules, the dependency scan and the validation error outputs, gated *read that file when executing explicit list mode*. |
| **Phase 1 — Triage and Pick** | borderline — a cache-freshness gate, a pick predicate, and a delegated `/issue-triage` | **phase 1 is not delegable because it depends on the previous step's exact text.** It fails **Independence**: the pick reads the *same* `.gitissue/triage.json` the cache gate just classified `fresh`/`stale` and the *same* `processed[]`/skip-list the orchestrator holds in `run-state.json`, and it writes the cache back in place after each merge (*Step 1.6*). A worker would have to be handed the run state to make the pick and hand it back to have the pick applied. The heavy half of it — the scan — is already a delegated skill. |
| **Phase 5 — Merge** | borderline — a mergeability probe, a CI wait, a dependency gate, a squash-merge and a close | **phase 5 is not delegable because it is the orchestrator's own authority.** It fails **Independence** on two counts: *Step 5.1a* decides whether the reviewer's returned `ci_status` may stand in for a fresh CI wait — a judgement about the previous step's exact return — and the merge is the one action the body reserves to the main agent in every mode. It also fails **Slice is separable**: its procedure is in `references/phases.md`, which the run has already been told to read for the phase it is executing. |
| **Phase 0 — Run state** | no | **phase 0 is not delegable because it is a single decision plus a lock.** It fails **context weight**, the first test, which ends the walk: resolve a three-valued resume gate, then `--init`. The lock must also be acquired in the orchestrator's own process — it is keyed to `$PPID`, the durable agent process, and a worker's shell exits taking the ownership claim with it. |
| **Prerequisites / Dependency Preflight / Configuration** | no | **not delegable because the orchestrator is what they gate.** Nine environment probes and two presence checks, each a single command; they fail **context weight**. They must also run in the orchestrator's own shell, because the run clock (`run_state.started_at`) and the resolved config are what everything after them reads. |
| **Iteration Report + run-log write** | no | **not delegable because its slice is what every run reads anyway** — `references/run-log.md` is gated **read it now** before the line is written — **and** because auto-pilot is by contract the *single writer* per processed issue. A worker that appended would be a second writer, which is the exact failure `--no-run-log` exists to prevent. |
| **Final Summary** | no | **not delegable because it depends on the previous steps' exact text** — every row is filled from a count and an outcome the orchestrator already holds. Fails **Independence**. |

**Pass.** All three genuinely heavy phases already name their slice and already run in
a subagent; every other step is recorded with the named test it fails. Advisory only —
this did not gate anything.

---

## 4. Delegation-conversion decision (Mode 2)

**Declined.**

**Named precondition it failed**, verbatim from `skill-auto-improver`'s
`references/delegation-conversion.md` → *When Mode 2 applies*, item **4**:

> **The user has confirmed the restructure in this run.** Name the steps you would
> convert and the version bump it forces, and wait. A conversion rewrites the skill's
> workflow; it is never something this skill decides on the user's behalf.

No user is present in this run and no confirmation was given, so the precondition
fails literally. `delegation-conversion.md` states the consequence in *When conversion
does not pay for itself*: the finding stays advisory and Mode 1 never converts a skill
quietly. That settles the mode on its own.

**A second precondition also fails, independently.** Item **1** requires that *"the
target **clears Gate 1** already. A conversion on top of an unpublishable skill
compounds two problems; retrofit first."* `/auto-pilot` does not clear Gate 1's word
cap — §6 records why — so the conversion is out of scope for this run whatever the
answer to item 4 would have been.

**Supporting observation — not a third precondition.** The conversion would also have
had little to convert. `/auto-pilot` **is** the per-step delegation pattern: three of
its five phases already run in subagents through the canonical contract, each already
naming its slice and pinning its input and output shapes. The remaining candidates all
match *When conversion does not pay for itself* → **"Nothing to withhold"**: Phase 1's
pick and Phase 5's merge read the run state the orchestrator owns, and the run-log
write is bound to `references/run-log.md`, which the body gates read-now. `SKILL.md`
should **net shrink** under a conversion; this one would net grow, on a body that is
already over the cap.

---

## 5. Run-stats footer (issue #414 shape) — AC4

The field set is `elapsed` · `tokens` (conditional) · `agents`, two lines, printed
**last at every terminal outcome**. It was **not widened, reordered or renamed** —
that claim stands unqualified. The contract lives in `references/run-stats.md`,
byte-identical across skills; `tests/test-run-stats-373.sh` (156 checks) passes on
both the source and the built tree, and `references/run-stats.md` was not touched.

The *Final Summary* call site kept its pinned shape and was not reworded:

> **Then the run-stats footer.** Close with the *Run Stats Footer* —
> `references/run-stats.md` — `elapsed`, `tokens` only where the host reported a count
> (otherwise left out), `agents`, run cost only, `n/a` for anything else undetermined.
> It is the last thing printed at **every** terminal outcome, including every stop
> condition in *Stop Conditions* and every abort that never reaches the summary at all
> — a failed prerequisite, a rate budget that could not be waited out, a runtime
> budget reached, an empty backlog, or an operator interrupt. `agents` counts every
> subagent the whole loop spawned across all iterations, not the last one's.

**AC4 asks for more than that sentence, so every terminal outcome was enumerated and
checked rather than asserted.** The 13 *Stop Conditions* rows, the critical-issue
pause and any unhandled failure are covered by name. `references/run-stats.md` →
*Every terminal outcome* covers the rest by construction rather than by list — *"The
footer prints wherever the run stops, not only where it succeeds … a guard that
refused to continue … an invalid-config stop … A run that produced no output at all
is the only run without a footer."*

**Four stops did not follow from either, and this pass closed them.** They are the
`/auto-pilot` analogue of the gap #420 found: they sit **above** *Final Summary* in
the body, so an agent that fails one of them stops at the instruction that told it to
stop and never reads the sentence that binds the footer. They are:

1. any of the nine **Prerequisites** failing;
2. a missing required skill at **Dependency Preflight**;
3. a missing file at the **Bundled dependency precheck**;
4. the two **Configuration** stops — `gi-config.py` exit 3 on an invalid
   `.gitissue.yml`, and an out-of-range `autopilot.max_parallel`, which "stops before
   Phase 0".

One sentence at the head of *Prerequisites* now scopes over all four, and states the
`elapsed` consequence the contract already governs for a stop taken before the clock
is captured:

> Before starting the loop, verify the environment. On failure, output the exact error
> from `references/error-messages.md`, close with the *Run Stats Footer*
> (`references/run-stats.md`), and stop — that ordering governs every stop in this
> section, in *Dependency Preflight*, in the *Bundled dependency precheck*, and at the
> run-lock and config stops below, and a stop before the config load prints
> `elapsed n/a`.

That also covers the fifth pre-loop stop, the run lock held by a live run — which is
additionally a *Stop Conditions* row, so it was already covered twice. No footer
instruction was added at any individual stop site; adding one per stop is the bloat
the predictability audit forbids by name, and on a body already over the word cap it
would be worse than that.

---

## 6. The word cap — D4 exception, with the accounting

**Gate 1's under-3000-words item and Gate 2's `context-efficiency >= 8` are one
finding** (the ADR's Context section: `context-efficiency` scores 6 or 8 and nothing
else, and the `+2` is the body word cap). Both are recorded here as a **D4 exception**
under `docs/decisions/shared-contract-pin-artifact.md`, which requires the exception
to be granted on a **post-pass** measurement and never on an estimate.

### The measurement

Method as the ADR specifies: 30 tracked suites naming `auto-pilot` traced under
`bash -x`; every `grep` pattern extracted from the traced command line, never guessed;
each replayed against the body and the matched line numbers unioned; a *pinned word*
is any word on a line at least one real assertion matches; *structural* is frontmatter,
headings, table rows and fenced lines that no assertion matches; **floor** is what
remains after deleting every non-pinned, non-structural word.

| Body | total (`asm`) | Pinned | Structural | Free prose | **Floor** |
|---|---:|---:|---:|---:|---:|
| Baseline, lower bound | 5941 | 3046 | 540 | 2438 | **3501** |
| Baseline, upper bound | 5941 | 3384 | 535 | 2105 | **3834** |
| **Post-pass, lower bound** | **5182** | 2891 | 569 | 1805 | **3375** |
| **Post-pass, upper bound** | **5182** | 3242 | 564 | 1459 | **3721** |

The ADR's own pre-pass figure for this skill was 3106–3207. This measurement is higher
on the same method because it is taken from a fuller pattern set — the `-e`-guarded
greps that the ADR's extractor and this one's first version both mis-normalised (§1).
The direction the ADR predicted still holds and is visible in the table: the floor
**fell** 126 words as the pass compressed assertion-carrying lines around their pinned
literals. It did not fall anywhere near far enough. **Deleting every remaining word of
free prose leaves 3375 `asm` words — 375 over the cap on the heuristic-free lower
bound, 721 over on the upper.**

### The objection this exception has to survive

The ADR granted `/issue-pr-review` its exception only after answering the strongest
available objection to it. The strongest one here is different, and it is this: many
of the live patterns are **single-word** category greps — `\bmerged\b`, `\bfailed\b`,
`\bskipped\b`, `\bleft_open\b`, `\bpartial_followup\b`, `\bblocked_by_dependency\b`,
`\bbalanced\b`, `\bconservative\b`, `\baggressive\b` — emitted by a loop in
`tests/test-autopilot-modes.sh` and `tests/test-autopilot-dependency-gate.sh` that
asserts each label appears *somewhere* in the body. Counting every line containing
"merged" as pinned overstates what those assertions require.

**Discount them entirely and the exception still stands.** Re-running the measurement
with all nine single-word patterns removed:

| Post-pass body | Pinned | Structural | Free prose | **Floor** |
|---|---:|---:|---:|---:|
| Lower bound, single-word greps discounted | 2506 | 668 | 2091 | **3089** |
| Upper bound, single-word greps discounted | 2949 | 621 | 1695 | **3485** |

3089 is still over 3000, on the most generous reading available — lower bound, nine
assertions written off, every free-prose word deleted.

### The other objection, and why it is not a route to the cap

A minimal set-cover over the live patterns — keep, for each assertion, only the single
cheapest line that satisfies it, and delete every other line — reaches **2487 `asm`
words**, under the cap. That number is real and is recorded here rather than omitted,
but it is not a body. What it deletes is not free prose: it is the ~600 words of
normative instruction that sit on assertion-carrying lines *beside* the literal — the
threshold arithmetic around `✗ Insufficient GitHub API rate budget for auto-pilot`,
the degrade-vs-stop routing around `gi-config unavailable`, the ordering rule around
`--append-once`. Under **D3** that material is every-run gate logic an agent must
apply to execute a step, and *"when the two conflict, the gate loses."* The set-cover
number measures how few words could still satisfy `grep`; it does not measure how few
words could still run the loop unattended.

### Relocation, taken seriously and rejected on the ADR's own rule

D4 requires that everything conditional be relocated before the exception is granted.
Each candidate, named:

| Candidate | Words | Verdict |
|---|---:|---|
| *Merge Modes* table + resolution rules | ~200 | **Cannot move.** Pinned by raw `grep`s naming `SKILL.source.md` in `tests/test-autopilot-modes.sh` (T3.1's *Resolution rules* home, T3.2's exactly-once count, the mode-name loop). The ADR's class table: *Raw `grep` naming a file → **No**. It pins a file by construction. Migrate it to an anchor first (issue #401's paced work) — do not silently re-target it.* Independently, the mode gate is evaluated at every merge, so **D3** forbids it too. |
| *Stop Conditions* table | ~330 | **Cannot move.** Four rows are pinned by anchored line-start `grep`s naming the file (`^\| Merge blocked …`, `^\| Mode forbids merge …`, `^\| Review exhausted …`, `^\| PR blocked by an unmerged dependency …`), and two more by their exact printed strings. Same class-table rule. |
| *Caller-supplied context* paragraph | ~250 | **Cannot move.** Nine literals pinned by `tests/test-subagent-context-256.sh` against the file, plus the `ap-snapshot-budget` anchor. |
| `## Configuration` block | ~330 | **Cannot move.** `tests/test-scripts-pipeline-251.sh` T5 slices the section out of the file in embedded Python and requires four literals and at least one inline dotted default inside it. |
| Run-log fences + exit-3 clause | ~180 | **Cannot move.** Same suite, same file-scoped Python. |
| *Bundled dependency precheck* list | ~90 | **Cannot move.** T1 requires the section to name every script bundled under `references/scripts/`. |
| `max_parallel > 1` lane mechanics | ~120 | **Already done.** The lane diagram and ownership rules moved to `references/orchestration.md` in an earlier issue; this pass deleted the body's remaining restatement of them. What is left is the two-sentence branch summary and the per-lane field list. |
| Run-log parallel-lane contract | ~130 | **Already done, and D3-blocked for the remainder.** `references/run-log.md` owns it; this pass deleted the body's duplicate. The pointer to it is gated **read it now** before the write, so moving anything further there lowers `wc -w` and lowers loaded context by zero — the exact trade D3 prohibits. |
| Explicit list mode | ~90 | **Already done.** `references/explicit-list-mode.md` owns it; the body carries a pointer gated on the `--issues` branch. |
| *Edge Cases* | ~110 | **Deleted, not moved** — four of seven bullets restated Prerequisites 8 and 9 and two config defaults; the rest sit beside the `references/examples.md` pointer, which is conditional (*read that file when debugging a specific scenario*). |

Everything conditional is already out. What remains is per-run gate logic pinned to
the file by raw `grep`s that #401 has not yet migrated to anchors, and that D3 would
forbid moving even after it does.

### What this means for #415

Under D4, `/auto-pilot` closes on **Gate 1 less the word cap** plus **Gate 2 less
`context-efficiency`**: `quick_validate.py` 0, frontmatter audit clean, 428 lines
(< 500), version and author present, `docs/README.md` AI-skip comment present, bundled
scripts verified, dependency preflight now complete; and `asm eval` overall 93 (> 85)
with every other category 9 or 10. The exception is recorded in the ADR's exceptions
table with this measurement.

---

## 7. Files changed

| File | Change |
|---|---|
| `src/skills/auto-pilot/SKILL.source.md` | 6026 → 5267 `wc` words, 481 → 428 lines; `metadata.version` 2.5.0 → 2.6.0; `## Dependency Preflight (mandatory)` added with all four §8 elements; run-stats footer bound to the four pre-loop stops; four sections folded; the resource index, 31 precheck glosses and two duplicated run-log paragraphs deleted |
| `skills/auto-pilot/SKILL.md` | regenerated (`./scripts/build.sh`) |
| `docs/decisions/shared-contract-pin-artifact.md` | `/auto-pilot` added to *Recorded exceptions* with the post-pass measurement; the deferred-verdict section marked resolved; the #413 consequence row updated |
| `docs/experiments/skill-auto-improver-auto-pilot.md` | this report |

No `references/*.md` file in the package was touched — a direct consequence of this
pass being deletion plus compression rather than relocation.

**Test suite of record** (`git ls-files 'tests/*.sh' | xargs -n1 bash`, serial,
`IDD_AUTO_MODE` unset): **82 passed, 1 failed** across 83 tracked scripts — identical
to the pre-change baseline on this machine.

- The single failure is `tests/test-runs-jsonl-rotation-354.sh` T4, the known
  macOS-only artifact (BSD `wc` pads its output). Unrelated to this change; ubuntu CI
  is green.
- `tests/test-scripts-252.sh` AC1, the other known non-defect, **passed** — it fails
  only with `IDD_AUTO_MODE=1` exported, and the variable was unset for every run.
- `tests/test-runs-jsonl.sh` T3 failed once mid-pass, on the real regression §1 names.
  It was fixed, not waived, and the suite has been green on it since.
- `tests/test-run-stats-373.sh` passes all 156 checks.

---

## 8. Unresolved gates

**One, and it is recorded rather than open.**

- **Gate 1 — body under 3000 words: not met (5182).**
- **Gate 2 — `context-efficiency >= 8`: not met (6).** Same finding.

Both are a **D4 recorded exception** on the post-pass floor of **3375** `asm` words
(lower bound), which survives discounting the nine single-word category greps (3089)
and which D3 forbids reaching by relocation. §6 carries the accounting; the ADR
carries the entry.

Everything else passes: `quick_validate.py` 0, frontmatter audit clean, 428 lines,
negative-trigger clause present, `metadata.version` 2.6.0 and `metadata.author`
present, `docs/README.md` AI-skip comment present, all ten bundled scripts verified by
execution, the dependency preflight complete, `asm eval` overall 93/A with every other
category 9 or 10.

Two advisories are deferred rather than unresolved, and both are named in §3 item 6:
the *Caller-supplied context* paragraph is written as a change record rather than as
the contract it states, and the six outcome labels are enumerated in three places.
Both are pinned prose; reconciling either means migrating assertions first.
