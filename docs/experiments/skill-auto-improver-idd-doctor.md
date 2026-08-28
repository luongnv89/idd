# skill-auto-improver run — `/idd-doctor`

**Issue:** [#422](https://github.com/luongnv89/idd/issues/422) · part of epic #413
**Target:** `src/internal-skills/idd-doctor/` — **the source package is the whole artifact**;
this skill has no built tree. See §0.
**Measuring standard:** `skill-auto-improver` v2.1.0 · `asm` v2.7.0
**Mode:** Mode 1 — retrofit. Mode 2 (delegation conversion) declined; see §4.
**Outcome:** Gate 1 passes. Gate 2 **cannot be measured on a shipped artifact** — measured
indicatively at **96 / grade A** on a synthesized copy. See §0 and §7.
**Date:** 2026-08-28

---

## 0. What could not be measured, and why

`/idd-doctor` is the repo's only **internal** skill. It is authored at
`src/internal-skills/idd-doctor/` and, unlike the seven public skills, it is **never built**:

- `skills/idd-doctor/` does not exist. `tests/test-root-skills-install-surface.sh` T5 asserts
  it must not.
- `scripts/build.py` contains **zero** references to `src/internal-skills`. It does not handle
  that source root at all. A bare `./scripts/build.sh` on this branch reports
  `✓ public skills: 7` and leaves `git diff -- skills/` empty.
- The package therefore ships `SKILL.source.md`, and no `SKILL.md` exists anywhere for it.

Both Gate 1's validator and all of Gate 2 require a file named `SKILL.md`. Every sibling in
this epic was measured against its built `skills/<name>/SKILL.md`; here there is nothing to
point them at. `docs/decisions/shared-contract-pin-artifact.md` had already reached the same
conclusion from the other direction — its **D1** names the source package alone as this
skill's governed artifact, "because every rule phrased around *the built package* is undefined
here" — and its skill table records `idd-doctor | — | — | not scoreable — no built tree`.

**What was done instead, stated plainly so the numbers are not over-read.** The package was
copied to a scratch directory **outside the repository**, its `SKILL.source.md` renamed to
`SKILL.md` in that copy only, and `quick_validate.py` and `asm eval --json` were run against
the copy. Nothing was written inside the repository; `asm eval --fix` was never run, on the
copy or anywhere else. The copy is faithful in the one way that can be checked independently:
`asm` counts its body at **3267 words** at the baseline commit, which is the exact figure the
ADR recorded for this skill by its own method.

So every Gate 2 figure below, and the `quick_validate.py` exit code, are **indicative
measurements of a synthesized artifact**. They are not official gate results, because the
artifact they describe is not one this repository produces or ships. The word count, the line
count, the frontmatter contents, the description clause, the README comment and the
bundled-script check are different: those are properties of the real source package and were
measured on it directly.

**The blocker is filed.** [#434](https://github.com/luongnv89/idd/issues/434) — *Decide whether
`src/internal-skills/` gets a built tree* — carries the decision and its distribution
consequences. It is referenced from #422. This report does not decide it: building an
internal skill starts shipping it, which is a product decision well outside a retrofit's scope.

**AC5 is blocked by the same gap, more directly than AC1 is.** #422's AC5 asks that "the built
skill tree is regenerated from it". For this skill there is no built tree to regenerate. The
build was run anyway (bare `./scripts/build.sh`, compile → verify → promote) to prove this
change did not disturb the seven skills that do have one: `git diff --exit-code -- skills/`
is clean.

---

## 1. Gate status — baseline → final

| Gate | Check | Baseline | Final | Measured on |
|------|-------|----------|-------|-------------|
| **Gate 1** | `quick_validate.py` exit | 0 (*"Skill is valid!"*) | **0 (pass)** | synthesized copy |
| Gate 1 | Frontmatter audit (`asm eval` → `frontmatter`) | all keys resolve | **all keys resolve** | synthesized copy |
| Gate 1 | Body under 500 lines | 464 (pass) | **417 (pass)** | real source |
| Gate 1 | Body under 3000 words | **3267 (FAIL)** | **2969 (pass)** | real source |
| Gate 1 | Negative-trigger clause in description | pass | pass (description untouched) | real source |
| Gate 1 | `metadata.version` semver + `metadata.author` | pass (0.2.0) | **pass (0.3.0)** | real source |
| Gate 1 | `docs/README.md` opens with the AI-skip comment | pass | pass (untouched) | real source |
| Gate 1 | Bundled scripts print descriptive stderr | **not applicable** | **not applicable** — see §2 | real source |
| Gate 1 | Dependency preflight (conditional) | **not applicable** | **not applicable** — see §2 | real source |
| **Gate 2** | `overallScore > 85` | 91 (grade A) | **96 (grade A)** | **synthesized copy — indicative** |
| Gate 2 | every category `>= 8` | **min 6 — `context-efficiency` (FAIL)** | **min 8 (pass)** | **synthesized copy — indicative** |

Per-category (`asm eval --json`, synthesized copy, indicative):

| Category | Baseline | Final |
|----------|---------:|------:|
| structure | 10 | 10 |
| description | 10 | 10 |
| prompt-engineering | 9 | **10** |
| context-efficiency | **6** | **8** |
| safety | 9 | 9 |
| testability | 10 | 10 |
| naming | 10 | 10 |
| **overall** | **91** | **96** |

Baseline blocker, verbatim from the evaluator: *"Body is over 3000 words — split long content
into referenced files or templates."* It docked `context-efficiency` 4 and `prompt-engineering`
1 (*"Body is very long (3267 words)"*), so one measurement moved two categories. Final findings:
*"Body length within healthy range (2969 words)."*

Body size, command of record:

```
wc -w < src/internal-skills/idd-doctor/SKILL.source.md   # 3340 → 3042
wc -l < src/internal-skills/idd-doctor/SKILL.source.md   #  464 →  417
```

`asm` strips the YAML frontmatter before counting; this skill's frontmatter is **73 words**, so
the `wc` and `asm` numbers sit 73 apart at both ends of the pass (3340/3267 → 3042/2969).

`metadata.version`: **0.2.0 → 0.3.0** (minor — no restructure, but the skill gained an
instruction it did not have: the bundled-dependency-precheck stop is now bound to the run-stats
footer, with its `elapsed n/a` consequence stated. See §5.)

**`safety` scores 9, not 10, and cannot score 10.** The evaluator awards 3 points for a
destructive action paired with a confirmation or dry-run, and 1.5 where the skill has no
destructive action at all. `/idd-doctor` is read-only by contract, so 1.5 is the ceiling and
8.5 → 9 is the arithmetic. It clears the ≥8 floor, and the alternative — inventing a destructive
action to score a point — would break the skill's central guarantee. Unchanged from baseline.

### The budget this pass had to hit, and how it was hit

`docs/decisions/shared-contract-pin-artifact.md` measured `/idd-doctor` at 3267 `asm` words
with an assertion-pinned floor of **1905–1991** and **1276–1362 words of free prose** against a
required cut of **267**. Unlike `/issue-triage` and `/auto-pilot`, this skill's floor sits over
1000 words below the cap, so the arithmetic was never tight: the required cut is a fifth of the
free prose. The actual pass cut **298** `asm` words. **No assertion was deleted or loosened, no
D4 exception was needed, and no material was relocated** — `git diff --stat` for the branch
touches `SKILL.source.md`, this report, and nothing else, so decision **D3** of the ADR
(*relocation is not a word-cap strategy*) is not engaged. The 298 words are words the agent no
longer loads, not words that moved somewhere it still loads them from.

### What was removed, and what it cost

| Cut | Where it survives | `wc` words |
|---|---|---:|
| *Additional Resources* index (5 entries) | Four of the five paths were already cited at their use sites; `docs/config-schema.md` was moved into the *Configuration* sentence that needs it, and `DESIGN.md` gained the *(repo root)* locator in *Output Conventions*. The fifth is a deliberate deletion — see below. | ~54 |
| *Testing*'s 10-item enumeration of what `tests/test-idd-doctor.sh` covers | One sentence naming the same coverage. The test file is the authority on its own assertions; the enumeration restated them without changing what the agent does. | ~87 |
| *Read-only guarantee*'s 4-bullet list | Folded into the section's own opening sentence, which previously omitted *tags* and *comments* and now carries both. The list was introduced by *"In detail, the skill is forbidden to:"* and then restated the sentence above it. | ~38 |
| *Scope (v1)* table rows 1 and 2 | Check 1 and Check 2 each enumerate their own files and forbidden phrases in full, two screens below. The rows now say what the check verifies and point at the section that lists them. | ~55 |
| Check 2's *Match algorithm* (3 numbered steps) | *"Check 1's Pattern match algorithm without its negation steps: every matching line records a finding `{file, line_number, pattern, snippet}`."* Check 1's four steps are untouched. | ~20 |
| Per-file glosses on the *Bundled dependency precheck* list | The `references/run-stats.md` gloss (*"run-stats footer contract (shape, fields, unavailable marker)"*) restated the contract file's own subject; the `references/error-messages.md` gloss is carried by the three use sites that name it. Follows the precedent #415 set for `/auto-pilot`. | ~12 |
| `docs/naming-conventions.md` pointer, described in the index as *"(referenced for context)"* | **Nowhere — deliberately.** This is a read-only skill that creates no branch, commit, PR or issue. A pointer to the naming conventions changes nothing an agent does here, which is the rubric item-6 no-op. It has no build-closure consequence either: nothing about this package is bundled, because nothing about it is built. | ~14 |
| Duplicate rendering of Check 3's skip line in *Configuration* | See *Three changes called out* below. | ~8 |
| Duplicate rendering of Check 3's skip line in its own *Procedure* step 1 | The *Output* table two paragraphs later. | ~7 |
| Duplicate fence of the run-log graceful-degradation line in *Run-log summary → Output* | *Procedure* step 1, which prints it. | ~14 |
| Two sibling-suite names in *Testing* (`tests/test-projects-sync.sh`, `tests/test-autopilot-modes.sh`) | Nowhere. Which other suites look similar is not an instruction. | ~12 |
| In-place compression: every remaining section | Same instruction, fewer words. | ~120 |
| **Added** — the precheck stop's run-stats binding (§5) | — | **+59** |
| **Added back** — *"For example"* and *"Never pass"* after an evaluator regression (§1, *How preservation was checked*) | — | **+4** |

**Three changes are called out rather than folded into "no behavior change".**

1. **A printed string was deleted, not relocated.** *Configuration* used to render Check 3's skip
   as `` `○ no .gitissue.yml — skipped` ``. Check 3's own *Procedure* and *Output* render the same
   line as `` `○ [3/4] Autopilot mode        skipped — no .gitissue.yml` ``. Those are two
   different strings for one printed line, and an agent reading *Configuration* first would print
   the wrong one. *Configuration* now says Check 3 *"skips rather than fails (see Check 3)"* and
   renders nothing. This is the only place in the pass where a printed string left the body
   without a surviving copy, and it left because it was wrong.
2. **A scope row was corrected while being shortened.** *Scope (v1)* row 4 read *"The
   repository's default merge strategy is squash (squash allowed AND merge-commit and
   rebase-merge disallowed)"* — the strategy level only. Check 4 has required **both** levels
   since #180: strategy **and** `squash_merge_commit_message == "PR_BODY"`. The row now reads
   *"Squash is the only merge strategy allowed **and** the squash message source is the PR body
   (SPEC §4.3 B1)"*. The pass predicate in Check 4's *Procedure* step 4 is unchanged.
3. **The `## Additional Resources` heading is gone entirely.** Four of its five entries survive
   as use-site citations; the fifth is the deliberate no-op above. No section was left with a
   dangling pointer: `references/error-messages.md` is named in *Prerequisites*, the *Bundled
   dependency precheck*, Check 4's `{summary}` paragraph and *Output Conventions*;
   `references/run-stats.md` in the precheck and the *Run stats footer*; `docs/config-schema.md`
   in *Configuration*; `docs/run-log-schema.md` in the *Run-log summary*; `DESIGN.md` in
   *Output Conventions* and the *Run-log summary* procedure.

### How preservation was checked, and what the check caught

Every tracked suite naming this skill or its source root was traced under `bash -x` at the
baseline commit and **every assertion applied to `SKILL.source.md` was extracted from the trace
line, not guessed**. Nine suites reach it: `test-idd-doctor.sh`, `test-run-stats-373.sh`,
`test-runs-jsonl.sh`, `test-skill-frontmatter-keys-307.sh`, `test-disclosure-gates-250.sh`,
`test-skill-line-cap-247.sh`, `test-root-skills-install-surface.sh`, `test-build-script.sh`,
`test-pre-commit-security.sh`. That yielded **52 pinned patterns** — 24 `grep -q[iEF]` literals
or regexes, 3 `check_flow` collapsed-newline sentences, 1 `check_flow_lacks` prohibition, the
four `## Check N —` headings plus their line-order comparison, and the frontmatter key-set and
`metadata.effort` audits.

A guard script re-asserted the full set, plus 33 further literals not covered by any test
(every exit code, `PR_TITLE`, `HTTP 422`, `gh auth status`, `date +%s`, `N = 50`, `tail -n 50`,
`qa_cycles`, `skipped_reason`, `already_resolved`, every forbidden-pattern variant, both
`src/skills/issue-creator/` paths, all three `docs/*.md` citations, `agents 0`, `n/a`, and the
`✗ Missing bundled dependency` header) after **every** edit. It includes the prohibition —
`check_flow_lacks` on the flattened sequence `` `elapsed`, `tokens`, `agents` `` from #410,
whose non-match at baseline reads like noise and whose reappearance would silently reinstate the
bug. The body carries no `<!-- a:… -->` anchor, so none could be lost.

**That guard was necessary and not sufficient. The evaluator caught a regression no test could.**
Compressing Check 4's `{summary}` paragraph turned *"For example `squash + merge-commit + …`"*
into a colon. That deleted the body's only standalone lowercase *example*, which is half of
`prompt-engineering`'s *"has code block AND mentions example"* item: the score fell 9 → 8 while
the guard stayed green and every suite stayed green. In the same pass *"Never pass: an unread
configuration…"* had become *"never pass, because…"*, halving the `Never` count. Both were
restored verbatim, and `prompt-engineering` recovered to 9 and then to 10 once the body cleared
3000 words. This is the same failure mode #418 recorded for `/issue-triage`'s `safety`
score, in a different category.

Beyond the guard, `git diff` was read one removed token at a time: **364 distinct tokens** present
in the baseline body and absent from the final one were listed and classified individually. Two
mechanical set-comparisons backed that up and are the reason the three call-outs above are
recorded rather than missed:

- **Printed lines as a set.** Every line beginning with `✓ ✗ ● ◆ ⚡ ⚠ ○`, plus every `Fix:`,
  `Or:`, `-f `, `Result:` and per-finding-format line, was extracted from both versions and
  differenced. Exactly one printed line is present at baseline and absent now — the run-log
  graceful-degradation fence, which survives in *Procedure* step 1 — and **no printed line was
  added**. The two Check 3 skip-line deletions are visible in the same comparison as duplicate
  removals rather than losses.
- **Fenced blocks as a set.** One fenced block was removed (the same run-log line); none was
  added; none was altered.

Finally, the guard's line/word report was re-run after every edit and the whole 52-pattern set
re-asserted on the final file. All present.

---

## 2. Gate 1 — the two conditional items

**Bundled scripts: not applicable, and correctly absent.** The whole package is four files, all
`.md` — `SKILL.source.md`, `docs/README.md`, `references/error-messages.md`,
`references/run-stats.md`. `find src/internal-skills -type f ! -name '*.md'` returns **0**.
There is no script to execute, so the *"bundled scripts print descriptive stderr, `--help` exits
0, bad input prints `✗ …` and exits 3"* item has nothing to check. This is a real property of the
real package, measured on it, not on the copy.

That absence is deliberate and consistent: the skill's *Bundled dependency precheck* lists two
files and both are `.md` contracts, and its checks are prose procedures over `grep`, `awk` and
`gh`, not shell-outs to `shared/scripts/`. No `shared/scripts/*.py` token appears anywhere in
the package.

**Dependency preflight: not applicable, and correctly absent.**
`references/skill-creator-checklist.md` §8 makes the section conditional on a target that
*invokes another skill*, and states that *"adding an empty one is itself a defect."* All three
signals were scanned across the package:

- **Calls `/other-skill`?** No. `/init-gitissue` appears twice (a *When to Use* recommendation
  and the Check 3 rationale) and `/issue-creator`, `/issue-analysis` and `/auto-pilot` appear as
  the subjects the doctor scans or as neighbouring skills it declines to scan. None is an
  invocation.
- **Delegates a phase to a named skill?** No. This skill delegates nothing — it spawns no
  subagent at all, which is why its run-stats footer prints `agents 0` as a determined value.
- **Reads a path under `~/.claude/skills/`, `~/.agents/skills/`, `~/.codex/skills/`?** No — grep
  across all four package files returns nothing. The only install-shaped string is
  *"not installed via asm/npx — see README"* inside the `✗ Missing bundled dependency` block,
  which is this skill's own self-description, not a dependency on another skill.

The condition does not fire, so nothing is required and nothing was added.

---

## 3. Predictability audit (Phase 2b — advisory, never gates)

Rubric resolved at `~/.claude/skills/skill-auto-improver/references/predictability-audit.md`
(no fail-soft skip). Walk of all 7 items:

| # | Rubric item | Verdict | Note |
|---|-------------|---------|------|
| 1 | Invocation chosen intentionally | **pass** | User-invoked and shaped as such: the body's second line is *"**Invocation:** `/idd-doctor` — no arguments"*, and *When to Use* opens on three **Do** clauses that read as "the operator asked for this, proceed". The description keeps its negative-trigger clause (*"Don't use for fixing issues, normalizing issues (use /issue-creator), or non-IDD health checks"*) because a model-invoked reading of "check the setup" would otherwise reach it, and `compatibility` states the `gh` carve-out (*"GitHub CLI (gh) is optional — used only for the merge-strategy check; skipped when gh is absent"*) so the cheap path is discoverable before the body is read. |
| 2 | Branches mapped before the body | **pass** | This skill has exactly one axis of branching and it is stated above *Pipeline*: `gh` present-and-authenticated versus not, decided in *Prerequisites* and consumed only by Check 4. Every other conditional is a per-check skip evaluated inside its own section against a stated file test (`.gitissue.yml` exists; template directories exist; `runs.jsonl` exists and is non-empty). There are no modes, no `--flags`, and no auto-versus-interactive split — the skill has no blocking prompt at all — so there is no branch-specific material an unaffected run loads. |
| 3 | Demanding, checkable completion criteria | **pass** | Unusually strong for its size. Every check closes on one of an enumerated set of literal output lines given in its own *Output* table, the run closes on `Result: {RESULT}  ({total} checks, {failed} failed, {warned} warned)`, and the body states the bar outright: *"the final line MUST end with `PASS`, `WARN`, or `FAIL` so a wrapper script can grep for it."* The exit-code table maps all three to 0/0/1. Check 4's pass condition is a four-clause boolean written as a fence, not prose, and #180's rule that an *unread* configuration must warn rather than pass is stated as a named outcome (`binding unverified`) with its own table row. |
| 4 | Progressive disclosure + delegability | **pass** (this pass fixed the disclosure half) | Was 3267 `asm` words at 464 lines, carrying a resource index that duplicated its own use-site citations, a 10-item description of a test file, a scope table that restated two checks in full, and a second copy of Check 2's match algorithm. Now 2969 words / 417 lines. The two `references/` files are one-line pointers gated at the sites that need them, which is what `tests/test-disclosure-gates-250.sh` asserts. Delegability sub-check below. |
| 5 | Leading words | **pass** | Recurring concepts are named once and referred to by name throughout: *gating check*, *run-log summary* (with its *informational, non-gating* qualifier attached at the definition), *Run Stats Footer*, *Bundled dependency precheck*, *negation guard*, *read-only guarantee*, *fix hint*, *terminal outcome*. This pass extended the pattern rather than breaking it — *Configuration* now names *Check 3* instead of re-rendering its skip line, Check 2's algorithm names *Check 1's Pattern match algorithm* instead of repeating it, and *Summary footer* names *the exit-code table* instead of saying "the table above". |
| 6 | No duplication / stale sediment / sprawl / no-ops | **pass** (this pass fixed it), two items left open | **Removed:** the *Additional Resources* index; *Testing*'s 10-item enumeration; *Read-only guarantee*'s bullet list restating its own opening sentence; *Scope (v1)*'s rows 1–2 restating Checks 1–2; Check 2's *Match algorithm* restating Check 1's; the precheck's per-file glosses; three duplicate renderings of two printed lines. **No-op removed:** the `docs/naming-conventions.md` pointer, marked *"(referenced for context)"* — a read-only skill that creates no branch, commit or PR takes no action from it. **Stale sediment fixed:** *Scope (v1)* row 4 described Check 4 at the strategy level only, which stopped being true when #180 added the message-source level. **Left open, advisory (a):** the four `✓ [N/4] …` lines in *Pipeline*'s expected-output fence are byte-identical to the Pass rows of the four *Output* tables. Both are printed strings, and they play different roles — a worked example versus a per-check spec — so neither was touched. **Left open, advisory (b):** the `✗ Missing bundled dependency` block instructs the operator to run `./scripts/build.sh` to regenerate this skill's bundled references, but that script does not touch `src/internal-skills/`. That is a *true* stale instruction, not a cosmetic one; it is not fixable inside this issue because the right fix depends on how #434 resolves, and it is named in #434's acceptance criteria. |
| 7 | Publish-ready — no auto-improver dependency | **pass, with §0's qualification** | On the synthesized copy: `quick_validate.py` exit 0 (*"Skill is valid!"*), `asm eval` 96/A with no category below 8. On the real package: 417 lines, description carries the negative-trigger clause, `metadata.version` / `metadata.author` / `license` present, `docs/README.md` opens with the AI-skip comment. The skill clears the standard without a follow-up auto-improver run — but "publish-ready" is a strange bar for a skill that is deliberately never published, and #434 is where that tension gets settled. |

### Delegability sub-check (item #4)

Rule applied verbatim: *"a step heavy enough to hand off names no slice of `references/` for its
worker — record it as `step N is not delegable because <reason>` (needs the user mid-step,
depends on the previous step's exact text, or its slice is what every run reads anyway). A skill
with nothing to slice passes."*

Every step, walked. "Heavy enough to hand off" is judged by *Identifying a delegable step*'s
**context weight** test — a multi-file read, a per-item fan-out, or a fixed procedure of a
dozen-plus lines. The relevant fact for this skill is that **it spawns no subagent anywhere**,
which is why its footer prints `agents 0` as a determined value rather than `n/a`.

| Step | Heavy enough to hand off? | Names its `references/` slice? |
|---|---|---|
| **Check 1 — Stale skill claims** | borderline — a two-file read with a per-line pattern-plus-negation scan | **Check 1 is not delegable because its slice is what every run reads anyway** — and there is no slice: the file list, the five-row forbidden-pattern table, the negation-marker list and the four-step algorithm are all inline, and moving them out would put every-run-mandatory material behind a read-now pointer, which ADR D3 and `tests/test-disclosure-gates-250.sh` AC1 make a green metric with no context saved. It also fails **context weight** on the honest reading: two files, both small, both named literally. |
| **Check 2 — Issue-template fields** | no | **Check 2 is not delegable because it is a glob and a substring match** — one directory glob plus an eight-row label table with no negation guard. It fails **context weight**, the first test, which ends the walk. |
| **Check 3 — Autopilot mode** | no | **Check 3 is not delegable because it is a single file test and one regex.** Fails **context weight**. |
| **Check 4 — Squash-merge default** | no | **Check 4 is not delegable because it is two `gh` reads and a four-clause boolean** — and it fails **Independence** as well: the `{summary}` string is rendered from the exact JSON both calls returned, not from a stated result a worker could hand back. |
| **Run-log summary** | borderline — a bounded file read plus three aggregations | **the run-log summary is not delegable because its slice is what every run reads anyway.** Its whole procedure is four inline steps over at most 50 lines that the `N = 50` cap already keeps inside the orchestrator's context budget; there is no reference file to hand over, and creating one would move every-run material behind a pointer for no context gain. |
| **Prerequisites / Bundled dependency precheck** | no | **not delegable because they are the run's own guards** — a worker cannot verify that *this* agent's bundle is intact, and `run_started_epoch` must be captured in the orchestrator's own shell (a worker's shell exits taking the value with it — the exact failure `delegation-conversion.md` → *Deriving the slice* item 5 names). |
| **Summary footer / Run stats footer** | no | **not delegable because they depend on the previous steps' exact text** — `{total}`, `{failed}` and `{warned}` are counts the orchestrator already holds, and `elapsed` is measured from an epoch only the orchestrator has. Fails **Independence**. |

**Pass.** No step in this skill meets the context-weight bar, the package has a two-file
`references/` tree containing two contracts rather than any separable procedure, and the rubric's
own clause applies literally: *a skill with nothing to slice passes*. Advisory only — this did
not gate the result.

---

## 4. Delegation-conversion decision (Mode 2)

**Declined.**

**Named precondition it failed**, verbatim from `skill-auto-improver`'s
`references/delegation-conversion.md` → *When Mode 2 applies*, item **4**:

> **The user has confirmed the restructure in this run.** Name the steps you would convert and
> the version bump it forces, and wait. A conversion rewrites the skill's workflow; it is never
> something this skill decides on the user's behalf.

No user is present in this run and no confirmation was given, so the precondition fails
literally. `delegation-conversion.md` requires **all four** to hold — *"Any miss and the answer
is Mode 1, or nothing"* — so this settles the mode on its own, exactly as it did for all six
landed siblings.

**Precondition 1 is also relevant here, and its history is worth recording.**

> 1. The target **clears Gate 1** already. A conversion on top of an unpublishable skill
>    compounds two problems; retrofit first.

At the **baseline** commit this skill did **not** clear Gate 1: the word cap is a Gate 1 item and
the body stood at 3267 words. Precondition 1 therefore failed at the moment the decision was
first available, which is precisely the case its own text describes — *retrofit first*. It passes
now, after this pass, which is the intended order. Precondition 4 is decisive either way.

**Two further preconditions miss, and they are the substantive reasons.** Precondition 2 asks for
a `references/` tree with more than one file **or** an inlined procedure long enough to move out.
The tree has two files, so the first clause is satisfied on a count — but both files are
*contracts* (`run-stats.md` is byte-identical across all eight skills and is governed elsewhere;
`error-messages.md` is the output catalog), not procedures a worker could be handed. Precondition
3 asks for at least one heavy step not ruled out by *Identifying a delegable step*; §3's walk
rules out every step by a named test.

A recorded decline is the complete outcome here. `SKILL.md` should **net shrink** under a
conversion; this one would net grow, because there is no inlined procedure to extract and the
only thing a conversion could add is worker contracts over material the orchestrator reads
regardless — the exact case `delegation-conversion.md` names under *When conversion does not pay
for itself*: **"Nothing to withhold."**

---

## 5. Run-stats footer (issue #414 shape) — AC4

The field set is `elapsed` · `tokens` (conditional) · `agents`, two lines, printed **last at
every terminal outcome**. It was **not widened, reordered or renamed** — that claim stands
unqualified. The contract lives in `references/run-stats.md`, byte-identical across all eight
skills; `tests/test-run-stats-373.sh` passes on this package, and `references/run-stats.md` was
not touched by this pass.

The body's call-site sentence kept its pinned shape and gained exactly one item in its
illustrative tail:

> Close with the *Run Stats Footer* — `references/run-stats.md` — `elapsed`, `tokens` only where
> the host reported a count (otherwise left out), `agents`, run cost only, `n/a` for anything
> else undetermined. It is the last thing printed at **every** terminal outcome, including a run
> that never reached Check 1: not a git repository, **a missing bundled dependency**, no
> `src/skills/` tree, or an unreadable `.gitissue.yml`. The doctor spawns no subagents, so
> `agents 0` is the determined value here, not `n/a`.

**AC4 asks for more than that sentence, so every terminal path was walked rather than asserted.**
This skill is read-only, so its terminal outcomes are the completed pipeline plus a small set of
guard stops and early exits. There are four:

| Terminal path | Footer bound? | How |
|---|---|---|
| Completed run (PASS / WARN / FAIL) | yes, at baseline | *Run stats footer* follows the run-log summary, which follows the summary footer. |
| Prerequisites failure — not a git repository | yes, at baseline | *Prerequisites* routes it to `references/error-messages.md`, whose first line is the blanket rule *"A block here that stops the run is followed by the run-stats footer … A stop that happens before the run clock was captured prints `elapsed n/a`, which is the contract working, not a hole in it."* The catalog carries the `Not a git repository` and `Could not read repo root` blocks. |
| Any other stop routed through the error catalog | yes, at baseline | Same blanket rule. It is exhaustive by construction over the catalog, not by enumeration. |
| **Bundled dependency precheck stop** | **no — this was the gap, and this pass closed it** | See below. |

**The gap, and why the blanket rules did not cover it.** The `✗ Missing bundled dependency` block
is the one stopping block that lives in `SKILL.source.md` rather than in
`references/error-messages.md`, so the catalog's *"A block here…"* sentence does not scope over
it — *here* means the catalog. The *Run stats footer* section's own enumeration named three early
exits and not this one. And the precheck sits **above** *Pipeline*, where the clock is captured
*before Check 1*, so a reader following that path meets an instruction to print a block and stop,
and never passes any instruction to print a footer. Structurally identical to the view-mode gap
#418 found in `/issue-triage` and the gaps #420 and #415 found in their targets. The precheck
section now reads, immediately after the block:

> That stop is a terminal outcome: print the block, then the *Run Stats Footer*
> (`references/run-stats.md`), then stop. It runs before the clock capture in *Pipeline*, so
> there is no `run_started_epoch` and `elapsed` prints the literal `n/a`, with `agents 0`. If
> `references/run-stats.md` is itself the missing file, print those two lines from the shape in
> *Run stats footer*.

Three things in that addition are deliberate. The `n/a` is not a guess and not `0` — it is what
`references/run-stats.md` requires for *"a stop before the config load [with] no anchor to
measure from"*, and this skill's anchor is captured later still. `agents 0` is the **determined**
value, because the doctor spawns no subagent on any path, so the `0`-versus-`n/a` distinction the
contract draws resolves to `0` even here. And the third sentence closes the one circularity a
reviewer would find: the footer's own contract file can be the file that is missing, in which
case the shape is taken from the body's *Run stats footer* section rather than from a file that
is not there.

The stop condition, the fatal-not-degrade routing, and the block's own text are all carried
forward unchanged — the addition sits after the fence, and the fence is byte-identical to
baseline. The `✗ Missing bundled dependency` header, the `asm/npx` note, the `./scripts/build.sh`
fix line and the `Then restart the agent session and re-run /idd-doctor.` line are all still
present. (That fix line's own truthfulness is a separate defect, recorded as §3's advisory (b)
and covered by #434.)

No footer instruction was added at the catalog-routed stops, and none should be — the catalog's
blanket rule already binds them, and adding one per stop is the bloat the predictability audit
forbids by name. The ~59 words this addition costs were paid for out of the same pass's cuts, and
together with nothing else they are why the bump is 0.3.0 rather than 0.2.1.

---

## 6. Files changed

| File | Change |
|---|---|
| `src/internal-skills/idd-doctor/SKILL.source.md` | 3340 → 3042 `wc` words, 464 → 417 lines; `metadata.version` 0.2.0 → 0.3.0; the bundled-dependency-precheck stop bound to the run-stats footer; *Scope (v1)* row 4 corrected to both levels of the §4.3 B1 binding; a contradictory second rendering of Check 3's skip line removed |
| `docs/experiments/skill-auto-improver-idd-doctor.md` | this report |

Neither `references/*.md` file in the package was touched — a direct consequence of this pass
being deletion plus compression rather than relocation. `docs/README.md` was not touched.
`skills/` was not touched: bare `./scripts/build.sh` was run and `git diff --exit-code --
skills/` is clean, which is the strongest statement available here, since the build does not
know this skill exists.

**Test suite of record** (`git ls-files 'tests/*.sh' | xargs -n1 bash`, serial, `IDD_AUTO_MODE`
unset): **82 passed, 1 failed** across 83 tracked scripts — identical to the pre-change baseline
on this machine.

- The single failure is `tests/test-runs-jsonl-rotation-354.sh` T4, the known macOS-only
  artifact (BSD `wc` pads its output, so `"       3" != "3"`). Unrelated to this change;
  reproduces on pristine `main`; ubuntu CI is green.
- `tests/test-scripts-252.sh` AC1, the other known non-defect, **passed** — it fails only with
  `IDD_AUTO_MODE=1` exported, and the variable was unset for every run.
- `tests/test-build-script.sh` is known-flaky in-loop; it was re-run standalone and passes.

---

## 7. Unresolved gates

**One, and it is the honest outcome of this issue rather than a failure of this pass.**

**Gate 2 is unmeasurable on a shipped artifact, blocked on build support for
`src/internal-skills/` — [#434](https://github.com/luongnv89/idd/issues/434).** `asm eval`
requires a `SKILL.md`; this package ships `SKILL.source.md` and `scripts/build.py` does not
handle its source root, so no `SKILL.md` exists for it anywhere in the repository. The synthesized
copy measures **96 / grade A, minimum category 8** — comfortably clear of both floors, and
consistent with where the ADR's arithmetic predicted this skill would land — but that is a
measurement of a file this repository does not produce. Recording it as a pass would be claiming
a gate result for an artifact that does not exist.

**Gate 1 passes**, and every item of it that does not need the validator binary was measured on
the real source package: 417 lines (< 500); 2969 `asm` words (< 3000); the description's
negative-trigger clause; `metadata.version` `0.3.0` and `metadata.author` present alongside
`license: MIT`; `docs/README.md` opening with the AI-skip comment; and the bundled-script check
correctly not applicable, because the package contains no non-`.md` file. `quick_validate.py`
exits 0 on the synthesized copy.

**No D4 exception was invoked, and none is owed.** The ADR predicted `/idd-doctor` clears the
word cap with over a thousand words of slack below its floor; it clears.

Three items are deferred rather than unresolved, and all three are named above rather than
folded away:

1. `context-efficiency` scores **8**, not 10, because the evaluator's top band is 120–1500 words.
   Reaching it is not available to this skill: the ADR puts its assertion-pinned floor at
   **1905–1991**, above the band's ceiling before a single word of free prose. 8 clears the gate.
   The body is held at 2969 rather than pressed against 3000.
2. `safety` scores **9** and structurally cannot score 10 — the missing 1.5 points are the
   destructive-action-plus-confirmation pairing, and this skill's whole contract is that it has
   no destructive action. See §1.
3. Predictability item **#6** leaves two advisories open: the *Pipeline* expected-output fence and
   the four *Output* tables render the same four Pass lines (both are printed strings, so
   reconciling them changes output), and the `✗ Missing bundled dependency` block instructs a
   build that does not touch this directory (fixable only once #434 decides which way it goes).
