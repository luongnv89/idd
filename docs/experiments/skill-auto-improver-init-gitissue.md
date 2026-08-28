# skill-auto-improver run — `/init-gitissue`

**Issue:** [#421](https://github.com/luongnv89/idd/issues/421) · part of epic #413
**Target:** `src/skills/init-gitissue/` (measured against built `skills/init-gitissue/`)
**Measuring standard:** `skill-auto-improver` v2.1.0 · `asm` v2.7.0
**Mode:** Mode 1 — retrofit, short-circuited at Phase 0. Mode 2 (delegation conversion)
declined; see §4.
**Date:** 2026-08-28

**The headline, first.** `/init-gitissue` **already cleared both hard gates before this run
touched anything**, and it still clears them after. That was predicted by
[#426](https://github.com/luongnv89/idd/issues/426) /
`docs/decisions/shared-contract-pin-artifact.md`, and this run **re-measured it rather than
trusting the prediction**. `skill-auto-improver` short-circuits at its Phase 0 when a target
already clears both gates; that is a legitimate, complete outcome, and it is what #421's
acceptance criteria ask to be recorded. **No compression pass was run, and none was needed.**
The deliverable here is the audit, not a rewrite.

Measurement convention, unchanged from [#416](https://github.com/luongnv89/idd/issues/416):
`src/skills/<name>/` holds `SKILL.source.md`, not `SKILL.md`, so `quick_validate.py` and
`asm eval` cannot read the authored source. Every measurement below was taken read-only
against the built tree (`skills/init-gitissue/`); the one edit was landed in
`src/skills/init-gitissue/` and the built tree regenerated with bare `./scripts/build.sh`
(compile → verify → promote). `asm eval --fix` was never run against `skills/`.

**Decision D3 of the ADR is not engaged at all.** Nothing was relocated into `references/`,
nothing was deleted from the body, and the body's word count is byte-for-byte what it was
(2949 `wc` words / 456 lines, before and after). The single change is an alignment inside
`references/examples.md`, plus the version line.

---

## 1. Gate status — baseline → final

| Gate | Check | Baseline | Final |
|------|-------|----------|-------|
| **Gate 1** | `quick_validate.py` exit | **0 (pass)** — *"Skill is valid!"* | **0 (pass)** |
| Gate 1 | Frontmatter audit (`asm eval` → `skill-best-practice`) | **15/15 pass** | **15/15 pass** |
| Gate 1 | Body under 500 lines | **456 (pass)** | **456 (pass)** |
| Gate 1 | Body under 3000 words | **2879 `asm` words (pass)** | **2879 (pass)** |
| Gate 1 | Negative-trigger clause in description | pass | pass (description untouched) |
| Gate 1 | `metadata.version` semver + `metadata.author` | pass (0.3.6) | **pass (0.3.7)** |
| Gate 1 | `docs/README.md` opens with the AI-skip comment | pass | pass (untouched) |
| Gate 1 | Bundled script prints descriptive stderr | pass — **executed**, see §2 | pass |
| Gate 1 | Dependency preflight (conditional) | **not applicable** | **not applicable** — see §2 |
| **Gate 2** | `overallScore > 85` | **97 (grade A)** | **97 (grade A)** |
| Gate 2 | every category `>= 8` | **min 8 (pass)** | **min 8 (pass)** |

Per-category (`asm eval --json`, built tree). The two columns are identical because the change
this pass landed is outside `SKILL.md`'s body:

| Category | Baseline | Final |
|----------|---------:|------:|
| structure | 10 | 10 |
| description | 10 | 10 |
| prompt-engineering | 10 | 10 |
| context-efficiency | **8** | **8** |
| safety | 10 | 10 |
| testability | 10 | 10 |
| naming | 10 | 10 |
| **overall** | **97** | **97** |

The evaluator reported no blocker at either end. `prompt-engineering` finding, verbatim:
*"Body length within healthy range (2879 words)."* `context-efficiency` carries one
suggestion — *"Consider moving large sections into referenced files"* — which is a
suggestion, not a finding, and is addressed in §7.

Body size, commands of record:

```
wc -w < src/skills/init-gitissue/SKILL.source.md   # 2949 → 2949 (unchanged)
wc -l < src/skills/init-gitissue/SKILL.source.md   #  456 →  456 (unchanged)
```

The frontmatter is **70 words**, which is the whole of the gap between the 2949 `wc` number
and the 2879 `asm` number that Gate 2 scores. That offset is a property of this frontmatter,
not a constant to carry to another skill.

`metadata.version`: **0.3.6 → 0.3.7** (PATCH). The discriminating question is whether the
*canonical instruction* changed. It did not — a stale worked example was brought into line
with a body that already governs it, and every governing string in `SKILL.md` is untouched.
That rules out the 0.4.0 a behaviour change would force. It does not rule out a bump: under
**D1** the governed artifact is the *package*, and a shipped file inside it changed, so
"no bump" would be wrong too. PATCH is the honest reading of both constraints.

### The one change this pass made, and why it is not busywork

Predictability item **#6** (stale sediment) found that `references/examples.md` had drifted
away from the canonical report block in `SKILL.md` → *Step 4 — Report*, in three places. The
drift is datable: `git log -S` puts the last alignment of that file at
**2eef890** (*"align examples with canonical templates and clean stale artifacts"*, #237), and
the `Validation:` row it is missing arrived **after** that, at **3ffe861** (#269). Items 2 and
3 predate #237 entirely (**02e91cb**, #109) and were missed by that alignment.

| # | Drift | Canonical source | Fix |
|---|---|---|---|
| 1 | All three example fences print `Result: DONE` with **no `Validation:` row at all**, and none of the three narrative walks names the validation step | *Step 3 — Validate the written config (mandatory)* makes validation a hard bar (*"do not report success"*) and *Step 4* renders `Validation:  ✓ parses as YAML, no placeholders left` as a report row | Row added to all three fences; one narrative line added to each walk |
| 2 | Merge example prints `Config:  ✓ merged .gitissue.yml (3 new fields, 8 preserved)` | *Step 4 → Variations → Merge mode*: `Config:  ✓ merged into existing .gitissue.yml ({N} new, {M} preserved)` | Example now instantiates the canonical string with `{N}`=3, `{M}`=8 |
| 3 | Python example prints `Test runner:  ○ skip (not detected)` | *Step 4 → Variations → No test runner detected*: `Test runner:  ⚠ warn (none — auto_test disabled)`. `○ skip (not detected)` is the **framework** row's variation, not the test runner's | Example now uses the canonical `⚠ warn` row |

This is a real finding rather than cosmetics: item 1 meant the file whose stated purpose is
*"read that file when debugging detection or merge behavior"* demonstrated a `DONE` verdict
reached **without** the validation the body makes mandatory — the exact defect #269 added the
gate to prevent.

**Two printed strings changed, and they are called out rather than folded into "no behaviour
change"** (the #419 precedent). The removed tokens are `○ skip (not detected)` on the Python
example's test-runner row, and `fields,` in the merge example's Config line. In both cases the
string that replaced it is the body's own canonical variation, copied verbatim. Everything
else in the diff is additive.

**Preservation check.** `git diff --word-diff` was read one removed token at a time; the two
removals above are the entire removal set. 28 named literals were then re-asserted across the
whole source package after the edit — every `✗`/`⚠`/`○` block, `run_started_epoch`,
*Never degrade past exit 3*, `invalid_squash_commit_setting_combo`, `squash_merge_commit_message`,
the `Run Stats Footer` pointer, the bare shared-script token, all six bundled `docs/*.md`
references, `templates/gitissue-template.yml`, `Result: DONE`, `Result: PARTIAL`, and
`agents 0`. All present. No tracked test matches any of the three drifted strings
(`grep -rF` across `tests/*.sh` returns nothing for `merged .gitissue.yml`, `3 new fields`,
`skip (not detected)`, `auto_test disabled`, or `merged into existing`); the one test that
pins a `Validation:` row, `tests/test-disclosure-gates-250.sh` AC2, scopes it to
`SKILL.source.md`, which this pass did not touch below the frontmatter.

---

## 2. Gate 1 — the two conditional items

**Bundled script prints descriptive stderr: verified by execution, not assumed.** The skill
bundles exactly one script, `gi-stack-detect.py`, and it was run from the **built** tree:

| Invocation | Exit | stderr |
|---|---:|---|
| `--help` | **0** | (usage on stdout) |
| `--root /nonexistent-xyz` | **3** | `✗ gi-stack-detect: --root is not a directory: /nonexistent-xyz` |
| `--rules <not-JSON>` | **3** | `✗ gi-stack-detect: --rules … is not valid JSON — Expecting value: line 1 column 1 (char 0)` |
| `--bogus` | **2** | `usage: … error: unrecognized arguments: --bogus` |

Stdout stays empty on both exit-3 paths, so a caller that parses stdout gets nothing to
misread. This matches the exit vocabulary CLAUDE.md fixes (`0` ok · `2` usage · `3` invalid
input, stop · `4` cannot complete, degrade) and the four-row *Classify **every** outcome* table
the body carries at the call site — including the row that says exit 3 is a **stop**, never a
degrade.

**Dependency preflight: not applicable, and correctly absent.**
`references/skill-creator-checklist.md` §8 makes the section conditional on a target that
*invokes another skill*, and states that adding an empty one is itself a defect. All three
signals were scanned across the whole source package (`SKILL.source.md`, all three
`references/*.md`, and `templates/gitissue-template.yml`):

- **Calls `/other-skill`?** **No.** `/issue-creator` occurs three times as the literal
  `Next action: /issue-creator to create your first issue` — a string printed **to the user**
  as advice after the run has finished — and once inside the `description`'s negative-trigger
  clause, where its job is to *stop* this skill from firing. `/issue-resolver`,
  `/issue-pr-review` and `/auto-pilot` occur only in the generated config template's YAML
  comments, naming which skill consumes which key. None is an invocation.
- **Delegates a phase to a named skill?** **No.** This skill spawns nothing at all — there is
  no `Agent(` call anywhere in the package, which is why `agents 0` is the determined constant
  in its footer (§5).
- **Reads a path under `~/.claude/skills/`, `~/.agents/skills/`, `~/.codex/skills/`?** **No** —
  grep across the package returns nothing. The single `asm install` occurrence is the
  *self*-reinstall command inside the `✗ Missing bundled dependency` block, which is the
  bundled-dependency guard, not a dependency on another skill.

The condition does not fire, so nothing is required and nothing was added.

**The 15 frontmatter checks, for the record.** They come from `asm eval --json` →
`providers[skill-best-practice].raw.checks` (`checkCount` 15, `passedChecks` 15):
`frontmatter-present`, `frontmatter-object`, `allowed-keys`, `name-present`,
`name-kebab-case`, `description-present`, `description-shape`, `description-runtime-budget`,
`effort-enum`, `compatibility-shape`, `metadata-version-present`, `metadata-version-semver`,
`metadata-author-present`, `name-matches-directory`, `negative-trigger-clause`.

Two observations that are **not** defects but are worth recording, because both are one edit
away from becoming one:

1. **`description-runtime-budget` passes at 249 characters against a 250-character target.**
   One character of headroom. Any future edit to the description has to shorten something
   else in the same edit. This is why the description was not touched by this pass.
2. `references/frontmatter-audit.md` check #10 (*"Every string with special chars is
   double-quoted"*) reads on `metadata.author`, whose value carries `<`, `>` and `@` unquoted.
   It parses unambiguously — YAML plain scalars admit all three mid-string, `asm`'s
   `frontmatter-object` and `allowed-keys` checks both pass, and `quick_validate.py` exits 0 —
   and the line is **byte-identical in all eight IDD skills**. Quoting it in one skill alone
   would create drift where there is none. Recorded as a repo-wide style observation, out of
   scope for #421.

---

## 3. Predictability audit (Phase 2b — advisory, never gates)

Rubric resolved at `~/.claude/skills/skill-creator/references/predictability-rubric.md`
(no fail-soft skip). Walk of all 7 items:

| # | Rubric item | Verdict | Note |
|---|-------------|---------|------|
| 1 | Invocation chosen intentionally | **pass** | User-invoked and the shape matches: *"**Invocation**: `/init-gitissue` — no arguments"* sits at line 16, the *When to Use* block opens **Do**/**Avoid**/**Never**, and the description carries the negative-trigger clause because two adjacent skills (`/issue-creator`, plain `git init`) would otherwise catch the same phrasing. `compatibility` states the cheap-branch carve-out — *"Requires git. No GitHub CLI or authentication needed"* — before the body is read, which is the one thing that distinguishes this skill's prerequisites from every other IDD skill's. |
| 2 | Branches mapped before the body | **pass** | Two orthogonal branches, both selected in *Configuration Check* before any step runs, each stated in exactly one place: **file exists vs. not** (the missing case is *"always create it without prompting … No early exit, no conditions, no cancel option"*; the existing case is the three-way overwrite/merge/cancel prompt), and **`gh` available vs. not** (gated once, at *Merge strategy warning (optional, when `gh` is available)*, and skipped with a printed `○` line otherwise). A third selector sits inside Step 1 — the script's `unresolved` list — and is explicitly narrowed: *"**`unresolved` is the LLM fallback trigger, and the only one.**"* |
| 3 | Demanding, checkable completion criteria | **pass** | Unusually strong for a generator skill, and it is the item most skills fail. *Step 3 → Validate the written config (mandatory)* opens *"A write that succeeded is not a config that works"* and names three mechanical bars — a YAML parse, a `grep -nE` for eight surviving placeholder tokens that **must return nothing**, and the presence of the `platform` key. `## Expected Output` then names the row that carries the verdict: *"the `Validation:` row is the checkable bar: the run only reports `DONE` after the written file parsed as YAML with no placeholder tokens left."* The no-parser case is routed to `PARTIAL`, *"never `PASS`"*. Every terminal row is `✓`/`⚠`/`○` plus a literal `Result:` value. |
| 4 | Progressive disclosure + delegability | **pass** | 456 lines / 2879 `asm` words, both inside the caps with headroom, and no section is a candidate for extraction under **D3**: the three detection tables are the documented by-hand procedure for the degrade branch (*"run the whole of the tables below by hand"*), and `tests/test-scripts-253.sh` AC5 pins two of them by name for exactly that reason. The `references/` tree is three files, each gated the right way round — `error-messages.md` and `run-stats.md` are named at their use sites; `examples.md` is gated **conditionally** (*"read that file when debugging detection or merge behavior"*), which is the correct disclosure for illustrative material. Delegability sub-check below. |
| 5 | Leading words | **pass** | Recurring concepts are named once and referred to by name: *Bundled dependency precheck* (named in *Prerequisites*, then referred to twice — from the Step 1 outcome table and from the Step 1 path-resolution clause — rather than restated), *Run Stats Footer*, *run_started_epoch*, *merge mode* / *overwrite mode*, *unresolved*, *derived* block, *the B1 durable-memory binding*, and *stop vs. degrade*. Step 2 is a model of the pattern: *"The script's `derived` block already carries these three values; the tables below are what it computed them from"* — the tables are given one job, not two. |
| 6 | No duplication / stale sediment / sprawl / no-ops | **advisory at entry, closed by this pass** | The finding was the three-item drift in `references/examples.md` documented in §1 — the missing `Validation:` row, the merge Config line, and the no-test-runner row. Fixed, because the fix is three lines of alignment against strings the body already governs and it removes a worked example that demonstrated success without the mandatory gate. **Checked and deliberately left alone:** the Step 4 report fence does not render the run-stats footer inside it. That is not sediment — **no** IDD skill renders a `Run stats` line inside a fence (verified by grep over every file of all eight source packages, `references/` and `templates/` included, discounting the eight byte-identical copies of `run-stats.md` itself; the one hit outside those is a `## Run stats footer` **heading** in `/idd-doctor`, not a rendered line), so the example fences are consistent with the repo-wide convention, and adding one here would create the drift, not remove it. **Also checked:** the *Instructions* list (6 lines) versus the four `## Step N` headings. Not duplication — the list is the pre-body map item #2 rewards, and it names prerequisites and the config check, which the Step headings do not. |
| 7 | Publish-ready — no auto-improver dependency | **pass** | `quick_validate.py` exit 0, `asm eval` 97/A with no category below 8, 456 lines, 2879 words, description carries the negative-trigger clause, `metadata.version`/`author`/`license`/`compatibility` all present and valid, `docs/README.md` opens with the AI-skip comment. The skill clears the standard with no follow-up auto-improver run — which is the same fact the Phase 0 short-circuit reports. |

### Delegability sub-check (item #4)

Rule applied verbatim: *"a step heavy enough to hand off names no slice of `references/` for
its worker — record it as `step N is not delegable because <reason>` (needs the user
mid-step, depends on the previous step's exact text, or its slice is what every run reads
anyway). **A skill with nothing to slice passes.**"*

"Heavy enough to hand off" is judged by *Identifying a delegable step*'s four tests, in order,
first `no` ending the walk: **context weight**, **independence**, **no user mid-step**,
**slice is separable**.

The structural fact that shapes the whole walk: **this skill has no `references/` slice to
hand anyone.** Its heaviest material — the language, framework, test-runner and repo-size
tables — lives in the body, not in `references/`, and it lives there under contract:
`tests/test-scripts-253.sh` AC5 pins *"init-gitissue keeps the language detection table"* and
*"init-gitissue keeps the test-runner detection table"* as the documented fallback for the
degrade branch. Of the three reference files, two are read-at-use-site and one is
conditional-and-illustrative. That is the rule's own escape hatch, and it is why the item
passes.

| Step | Heavy enough to hand off? | Names its `references/` slice? |
|---|---|---|
| **Prerequisites + Bundled dependency precheck** | no | **not delegable because it is a single command and a file-existence list** — one `git rev-parse --git-dir`, then eleven `test -f`-shaped checks. Fails **context weight**, the first test, which ends the walk. |
| **Configuration Check** | no | **not delegable because it needs the user mid-step, and because the run clock must be captured in the orchestrator's own shell.** The file-exists branch prompts `Choose: [overwrite/merge/cancel]`. Independently, this is the step that chains `…; ec=$?; date +%s >&2; exit "$ec"` and keeps the stderr epoch as `run_started_epoch` — a worker's shell exits taking that value with it, which is the exact failure `delegation-conversion.md` → *Deriving the slice* item 5 warns about by name. |
| **Step 1 — Scan Repository** | **borderline yes** — the largest block in the body (three tables, a size band, a template count) | **step 1 is not delegable because its slice is the body itself, and there is nothing left to withhold.** The scan is already delegated — to a **deterministic script**, `gi-stack-detect.py`, which returns one JSON object. What remains for the agent is the `unresolved` fallback: *"For each field it names, and *only* those, work it out yourself from the tables below."* Those tables are in `SKILL.md`, pinned there by AC5, so the orchestrator has loaded them before it could dispatch anything — which `delegation-conversion.md` → *Deriving the slice* item 2 states buys back no context at all. Extracting them to `references/` first is the move **D3** prohibits: they are read-now material on the degrade branch, so relocating them would trade real context for a metric. |
| **Step 2 — Suggest Defaults** | no | **not delegable because it is three table lookups** — a size→timeout row, a boolean, a size→threshold row, all three already computed by the script's `derived` block. Fails **context weight**. |
| **Step 3 — Write Config** (incl. the mandatory validation and the merge-strategy preflight) | **borderline yes** — a template substitution, a three-part validation, and two `gh` reads | **step 3 is not delegable because its output depends on the previous step's exact text, and it operates on files only the orchestrator holds.** It substitutes eight placeholder tokens with Step 1/2's *exact values*, not their stated results, then re-reads *the file it just wrote* to validate it. Fails **independence**. The merge-strategy preflight is a separable errand, but it is two `gh` calls and two conditionals — it fails **context weight** on its own. |
| **Step 4 — Report** | no | **not delegable because its slice is what every run reads anyway** — it renders from Step 1-3's returned values plus `docs/terminal-style.md`, which the *Output Conventions* section makes a whole-run contract. It is also the last step: there is no orchestrator left behind to receive a worker's return. |

**Pass**, on the rule's own terms — *a skill with nothing to slice passes* — with every step
recorded against the test it fails rather than skipped. Advisory only; this did not gate the
PASS, and per `references/predictability-audit.md` a delegability finding *"routes to Mode 2,
never a Mode 1 edit."*

---

## 4. Delegation-conversion decision (Mode 2)

**Declined.**

**Named precondition it failed**, quoted verbatim from `skill-auto-improver`'s
`references/delegation-conversion.md` → *When Mode 2 applies*, item **4** — one of four that
*"All four must hold. Any miss and the answer is Mode 1, or nothing"*:

> 4. **The user has confirmed the restructure in this run.** Name the steps you would
>    convert and the version bump it forces, and wait. A conversion rewrites the skill's
>    workflow; it is never something this skill decides on the user's behalf.

This run is unattended. No user is present and no confirmation was given, so the precondition
fails literally, and it fails for a reason with extra force here: `/init-gitissue` is
**interactive by nature** — its one prompt (`Choose: [overwrite/merge/cancel]`) is a decision
it takes *from* the user mid-run — so an unattended agent restructuring the workflow of a
skill built around a user prompt is exactly the substitution item 4 exists to prevent. The
same file states the consequence under *When conversion does not pay for itself*: *"The user
declines the restructure. The finding stays advisory. It is never promoted to a blocker, and
Mode 1 never converts a skill quietly."* That settles the mode on its own.

**Supporting observations — not second preconditions**, recorded so the decline is not read as
merely procedural:

- **Precondition 3 also misses.** *"At least one step is heavy … and is not ruled out by
  Identifying a delegable step."* §3's walk rules out all six steps by a named test: two on
  **context weight**, one on **independence**, one on **no user mid-step**, and two on
  **slice is separable**. Nothing survives.
- **Precondition 2 is satisfied only on a technicality that D3 then closes.** The
  `references/` tree does have three files, and the body does carry an inlined procedure long
  enough to move out — the detection tables. But that procedure is pinned in the body by
  `tests/test-scripts-253.sh` AC5 as the degrade-branch fallback, and moving it is what **D3**
  prohibits: *"Material the body gates with *read it now* — or that an agent must apply on
  every run to execute a step — stays in the body."*
- **`When conversion does not pay for itself` matches on two of its five bullets.**
  *"Nothing to withhold. No `references/` tree, or one file every run reads anyway"* — the two
  non-illustrative reference files are named at their use sites, and the third is already
  conditional. *"Every step is a single decision. The spawn costs more than the slice saves"*
  — Prerequisites, Configuration Check and Step 2 are literally that.
- **A conversion would net grow `SKILL.md`,** which the same file names as the failure
  signature: *"SKILL.md should **net shrink**. A conversion that grows the body has moved
  nothing."* The only extractable block is one that must stay; what would be added is a worker
  contract over material the orchestrator reads regardless. And the version bump it forces is
  **MAJOR** (`1.0.0`), on a skill whose behaviour would be identical.

A recorded decline is the complete outcome here.

---

## 5. Run-stats footer (issue #414 shape) — AC4

The field set is `elapsed` · `tokens` (conditional) · `agents`, two lines, printed **last at
every terminal outcome**. It was **not widened, reordered or renamed** — that claim stands
unqualified. The contract lives in `references/run-stats.md`, verified byte-identical across
all eight skill packages (`md5` over every copy: one digest,
`30529bc887f4ce88302d3739502a5b20`), and **not touched** by this pass.
`tests/test-run-stats-373.sh` passes on both the source and the built tree.

The body's call-site sentence was not reworded:

> **Then the run-stats footer.** Close with the *Run Stats Footer* — `references/run-stats.md`
> — `elapsed`, `tokens` only where the host reported a count (otherwise left out), `agents`,
> run cost only, `n/a` for anything else undetermined. It is the last thing printed at
> **every** terminal outcome, including a run that wrote no config — a failed prerequisite, a
> declined overwrite, or a scan that could not complete. This skill spawns no subagents, so
> `agents 0` is the determined value here, not `n/a`.

`agents 0` is the **documented precedent, not a defect**: `references/run-stats.md` →
*Unavailable values* states *"`0` is a **determined** value and is correct where it is true: a
skill that spawns no subagents prints `agents 0`, not `agents n/a`."*
`tests/test-run-stats-373.sh` AC5 pins it for this skill by name.

**AC4 asks for more than that sentence, so every terminal outcome was enumerated and checked
against a covering rule rather than asserted.** #420 found a real gap of this class in
`/issue-creator` — two terminal *report modes* that never printed the footer because they
lived in a reference file and never passed the body's blanket sentence. **`/init-gitissue` has
no gap of that class, and the reason is structural: it has exactly one report section.** Its
eight *Variations* all modify rows *inside* that same `◆ Init Gitissue` block — two of them
(*No language detected*, *No test runner detected*) additionally print an `○` tip earlier in
the flow — and none is an alternative mode; there is no second terminal renderer anywhere in
the package. Three layers cover the
outcomes between them:

| # | Terminal outcome | Where it stops | Covered by |
|---|---|---|---|
| 1 | Not a git repository | *Prerequisites* | body's blanket sentence — named explicitly (*"a failed prerequisite"*) |
| 2 | Missing bundled dependency | *Bundled dependency precheck* | `run-stats.md` → *Every terminal outcome*: *"a guard that refused to continue"* |
| 3 | `cancel` at the overwrite/merge prompt | *Configuration Check* | body's blanket sentence — named explicitly (*"a declined overwrite"*) |
| 4 | Stack detection exit 3 | *Step 1*, outcome table | body's blanket sentence (*"a scan that could not complete"*) **and** `error-messages.md` |
| 5 | Config write failed | *Step 3* | `error-messages.md` opening rule |
| 6 | Directory not writable | *Step 3* | `error-messages.md` opening rule |
| 7 | Generated config failed validation | *Step 3 → Validate (mandatory)* | `error-messages.md` opening rule |
| 8 | Success — `Result: DONE` | *Step 4* | the footer instruction itself |
| 9 | `Result: PARTIAL` — no YAML parser | *Step 4 → Variations* | the footer instruction itself (same report block) |

The `error-messages.md` layer is that file's own opening rule, byte-identical across all eight
skills: *"**A block here that stops the run is followed by the run-stats footer** … printing
the error block and exiting without the footer is the gap that contract exists to close. A stop
that happens before the run clock was captured prints `elapsed n/a`, which is the contract
working, not a hole in it. A `⚠` block that warns and continues is not a terminal outcome and
prints no footer of its own."* That last clause is what correctly excludes the two
merge-strategy `⚠` warnings and the three `○` skip lines, which warn and continue.

Outcomes **1** and **2** stop *before* the *Configuration Check* captures `run_started_epoch`,
so they print `elapsed n/a`. That is stated by the rule above and is the contract working.

**No footer instruction was added at any stop site.** Adding one per stop is the bloat the
predictability audit forbids by name, and unlike `/issue-analysis` (view mode) or
`/issue-creator` (normalize and batch modes), there is no branch here that exits the run
without passing the *Step 4* section's scope.

---

## 6. Files changed

| File | Change |
|---|---|
| `src/skills/init-gitissue/SKILL.source.md` | one line — `metadata.version` 0.3.6 → 0.3.7. Body unchanged: 2949 `wc` words / 456 lines before and after |
| `src/skills/init-gitissue/references/examples.md` | three worked examples aligned with the canonical *Step 4 — Report* block and its Variations: `Validation:` row added to all three fences, one validation line added to each narrative walk, merge Config line and no-test-runner row switched to the canonical strings |
| `skills/init-gitissue/SKILL.md`, `skills/init-gitissue/references/examples.md` | regenerated (bare `./scripts/build.sh` — compile → verify → promote) |
| `docs/experiments/skill-auto-improver-init-gitissue.md` | this report |

No other skill's sources were touched, `references/run-stats.md` and `references/error-messages.md`
were not touched, and `templates/gitissue-template.yml` was not touched.

**Test suite of record** (`git ls-files 'tests/*.sh' | xargs -n1 bash`, serial,
`IDD_AUTO_MODE` unset): **82 passed, 1 failed** across 83 tracked scripts — identical to the
pre-change baseline captured on this branch before the first edit.

- The single failure is `tests/test-runs-jsonl-rotation-354.sh` T4, the known macOS-only
  artifact (BSD `wc -l` pads its output, so `"       3" != "3"`). It reproduces at the baseline
  commit, is unrelated to this change, and ubuntu CI is green.
- `tests/test-scripts-252.sh` AC1, the other known non-defect, **passed** — it fails only with
  `IDD_AUTO_MODE=1` exported, and the variable was unset for both runs.
- `tests/test-scripts-253.sh` AC5 pins `gi-stack-detect.py` at **exactly one** call site across
  every tracked `.md`/`.yml`/`.json`/`.txt` file outside `skills/`, `dist/`, `.pi/` and
  `tests/`. That site is the body's Step 1 invocation, and this report deliberately names the
  script without writing a runnable invocation of it, so the count stays at one.

---

## 7. Unresolved gates

**None. Both gates passed before this run and pass after it** — which is the whole finding.

- **Gate 1** — `quick_validate.py` exit 0 (*"Skill is valid!"*); 456 lines (< 500); 2879 `asm`
  words (< 3000); frontmatter audit 15/15 with the negative-trigger clause,
  `metadata.version` `0.3.7` and `metadata.author` present; `docs/README.md` opens with the
  AI-skip comment; the one bundled script prints descriptive stderr and exits 3 on bad input,
  verified by execution; the dependency preflight is correctly absent because none of the
  three signals fires.
- **Gate 2** — `asm eval` overall **97** (> 85), minimum category **8** (>= 8).

One item is deferred rather than unresolved, and the reasoning is **specific to this skill**
rather than borrowed from a sibling report:

**`context-efficiency` scores 8, not 10, and 10 is arithmetically reachable here — the decline
is a choice, not an impossibility.** The evaluator's top length band is **120–1500 words**
(`references/category-playbook.md` §4: 4 points for a body in that range). The ADR's
measurement puts this skill's assertion-pinned floor at **1200–1270** words — *inside* the
band. That is the opposite of `/issue-analysis` (#419), whose 1752–1831 floor puts 10 out of
reach before a single word of free prose, and it means the honest reason to stop at 8 is not
availability:

1. **The gate is already cleared.** 8 ≥ 8 and 97 > 85. Cutting 1379 words to move a passing
   metric two points is the trade **D3** exists to forbid — *"When the two conflict, the gate
   loses"* — inverted into the case where there is no conflict at all and the cut would be
   gratuitous.
2. **What would have to go is governing instruction.** Reaching 1500 means deleting roughly
   85% of the 1609–1679 words the ADR classes as free prose, leaving ~230–300. That budget
   does not survive the `unresolved` fallback rules, the four-row exit-code classification,
   the mandatory-validation bar, or the squash-merge preflight's two-flag explanation — each
   of which changes what the agent does.
3. **The one relocation that would help is the one D3 names.** The detection tables are the
   largest block, and `tests/test-scripts-253.sh` AC5 pins them in the body as the
   degrade-branch fallback. Moving them lowers `wc -w` and lowers the agent's loaded context
   by exactly zero on the branch that needs them.

The body sits at 2879 against a 3000 cap — 121 words of headroom — so the next edit can add a
sentence without re-breaking the category. `context-efficiency` 8 is recorded as the settled
state for this skill, not as an open finding.
