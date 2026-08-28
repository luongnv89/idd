# ADR — Which artifact the shared-contract tests pin skill prose to

**Status:** Accepted (2026-08-28).
**Issue:** [#426](https://github.com/luongnv89/idd/issues/426) · part of epic
[#413](https://github.com/luongnv89/idd/issues/413).
**Supersedes nothing.** Extends the anchor convention recorded for
[#358](https://github.com/luongnv89/idd/issues/358) and paced by
[#401](https://github.com/luongnv89/idd/issues/401).

## Context

Epic #413 retrofits all eight IDD skills to the `skill-auto-improver` v2.1.0
hard gates. Two of them bind on size:

- **Gate 1** — the SKILL body must be under **500 lines** *and* under **3000
  words**. `asm` strips the YAML frontmatter before counting, so the number that
  scores is `wc -w` minus the frontmatter.
- **Gate 2** — `asm eval` **overall > 85** and **every category ≥ 8**. Only
  `context-efficiency` is at risk: it scores `+3` for external references, `+2`
  for no oversized code block, `+1` for a token/budget mention, and `+2` for a
  body at or under 3000 words. Every IDD skill already earns the first three, so
  `context-efficiency` is **6 or 8 and nothing else** — 6 above the word cap, 8
  at or below it. Gate 1's word cap and Gate 2's category floor are one finding.

[#417](https://github.com/luongnv89/idd/issues/417) ran the full compression
pass on `/issue-pr-review` (PR #425) and could not clear it. Its accounting
(`docs/experiments/skill-auto-improver-issue-pr-review.md` §6) showed that of
4377 body words, 2835 sat on the 70 lines carrying a verified test assertion, so
deleting *every* remaining word of free prose still landed at 3410 — over the
ceiling. #417 concluded the blocker was the repo's own suite pinning prose to
`SKILL.source.md` **by file**, and that the fix was a repo-wide decision it had
no standing to make.

That framing generalised from one skill. This ADR measures all eight before
deciding.

## Measurement

**Method.** Every tracked `tests/*.sh` was run under `bash -x` and its trace
captured. Each traced `grep` invocation yields the *actual* pattern the suite
matches — extracted, never guessed. Patterns are attributed to a skill body two
ways:

- **Lower bound (exact).** Only greps where the skill body appeared literally as
  a file argument on the traced command line. No attribution heuristic
  whatsoever. These are the raw file-scoped greps and block extractions.
- **Upper bound.** Adds the stdin greps that `anchors.bash` performs inside a
  region, attributed to the file the preceding `anchor_region`/`anchor_span`
  `awk` call named.

Each surviving pattern is replayed with `grep -nE`/`-nF` against the body and
the matched line numbers unioned. A *pinned word* is any word on a line that at
least one real assertion matches. Degenerate patterns (`.`, used by
`check_block_has` as a non-empty test) are excluded. Structural words are those
on frontmatter, headings, table rows, and fenced-block lines that no assertion
matches. **Floor** is the body size that remains after deleting *every*
non-pinned, non-structural word — #417's arithmetic, applied to all eight.

Cross-check: this method reproduces #417's independently-derived numbers for
`/issue-pr-review` (4312 asm words; 2722–3058 pinned words against its 2835;
floor 3239–3474 against its 3410).

| Skill | Issue | `asm` words | Pinned (low–high) | Structural | Free prose | **Floor (low–high)** | Cut needed |
|---|---|---:|---:|---:|---:|---:|---:|
| `init-gitissue` | #421 | **2879** | 318–435 | 905 | 1609–1679 | 1200–1270 | **0 — already under** |
| `issue-resolver` | #416 | **2958** | 1507–1851 | 364–424 | 815–1099 | 1859–2143 | **0 — cleared in #416** |
| `issue-analysis` | #419 | 3141 | 1043–1139 | 764–781 | 1310–1389 | 1752–1831 | 141 |
| `idd-doctor` | #422 | 3267 | 1441–1539 | 525–537 | 1276–1362 | 1905–1991 | 267 |
| `issue-triage` | #418 | 3799 | 2049–2100 | 775–789 | 995–1032 | 2767–2804 | 799 |
| `issue-creator` | #420 | 4840 | 1595–1895 | 493–524 | 2517–2786 | 2054–2323 | 1840 |
| `issue-pr-review` | #417 | 4312 | 2722–3058 | 480–581 | 838–1073 | **3239–3474** | 1312 |
| `auto-pilot` | #415 | 5941 | 2405–2553 | 737–784 | 2734–2835 | **3106–3207** | 2941 |

`asm eval` on the built tree, same day, confirms the split the table predicts:

| Skill | overall | `context-efficiency` | both gates |
|---|---:|---:|---|
| `init-gitissue` | 97 | **8** | **pass** |
| `issue-resolver` | 97 | **8** | **pass** |
| `issue-analysis` | 93 | 6 | fail (word cap) |
| `issue-triage` | 93 | 6 | fail (word cap) |
| `issue-creator` | 93 | 6 | fail (word cap) |
| `issue-pr-review` | 93 | 6 | fail (word cap) |
| `auto-pilot` | 93 | 6 | fail (word cap) |
| `idd-doctor` | — | — | not scoreable — no built tree |

`quick_validate.py` (skill-creator) exits 0 — *"Skill is valid!"* — on
`skills/init-gitissue`, `skills/issue-resolver` and `skills/issue-pr-review`, so
for those three the word cap is the only Gate 1 item still open, and for the
first two it is not open either.

**What the measurement shows.** For six of the eight skills the assertion load is
nowhere near binding: their floors sit 1000–2000 words below the cap, and the
gap between today's body and 3000 words is ordinary free prose. The suite is not
what blocks them. Only two bodies stay over the cap after deleting every free
word: `/issue-pr-review` (floor 3239 even on the heuristic-free lower bound) and
`/auto-pilot` (floor 3106).

## The question relocation actually raises

The tempting reading of #417 is "relocate the pinned prose into `references/`
and the body clears the cap." Two facts kill that as a general strategy.

1. **`context-efficiency` already earns its `+3` for external references in
   every skill.** Moving more prose into `references/` earns nothing further.
   The only outstanding point is the `+2` for the body itself.
2. **`tests/test-disclosure-gates-250.sh` AC1 requires every-run-mandatory
   material to sit behind a *read-now* pointer.** Material the body gates as
   read-now is loaded on every run. Relocating it moves words out of `wc -w` and
   moves nothing out of the agent's context window.

So relocation is real economy only for material that is **conditional at run
time** — an Agent-tool-unavailable fallback, a read-when-debugging appendix, an
edge case reached on one branch. For every-run-mandatory material it buys a
green metric and no context. That is the distinction this ADR turns into a rule.

`/issue-pr-review` is the worked case. Its pinned words are distributed across
`Depth gate`, `QA handoff gate`, `Step 2`…`Step 7`, `Review Loop`, and
`Verification gates` — every one a pipeline step or a gate evaluated on every
run — and #417 had already relocated the conditional remainder into seven
reference files totalling 15272 words, each cited from the body with **read it
now**. There is nothing conditional left to move.

## Decisions

**D1. The governed artifact is the skill package, not the SKILL body.**
A shared-contract assertion pins a behaviour to `src/skills/<name>/` (body +
that skill's own `references/*.md`) and to its built counterpart
`skills/<name>/`. Which file inside the package carries the contract is an
authoring choice, not part of the contract. For `/idd-doctor` the governed
artifact is the source package `src/internal-skills/idd-doctor/` alone: it has
no built tree, and `scripts/build.py` does not handle `src/internal-skills/`
(that gap is #422's, and stays open).

"The skill's own files" deliberately excludes `references/agents/`,
`references/docs/`, `references/scripts/`, `templates/`, and `docs/README.md`.
Bundled agents, docs, and scripts are governed by their sources under
`src/shared/`; a copy in a bundle is not a second contract site.

**D2. Anchors resolve package-wide.** `tests/lib/anchors.bash` now accepts a
**package directory** wherever it accepts a file. Given a directory, it locates
the single file in the package carrying the anchor and proceeds exactly as
before. The uniqueness teeth get stronger, not weaker: the anchor must appear
exactly once *across the whole package*, so relocating a contract keeps its
assertion and duplicating one still fails. A caller that names a file keeps
today's file-scoped behaviour, which stays correct — a file is a member of its
package.

**D3. Relocation is not a word-cap strategy.** Prose may be moved out of a SKILL
body, taking its anchor and its assertions with it, **only when the material is
conditional at run time**. Material the body gates with *read it now* — or that
an agent must apply on every run to execute a step — stays in the body. Moving
it to satisfy Gate 1 trades real context for a metric and is prohibited. When
the two conflict, the gate loses.

**D4. A skill whose measured floor exceeds the cap is a recorded exception.**
The procedure: run the compression pass, relocate everything conditional, then
re-measure the floor by the method above. If the floor still exceeds 3000 `asm`
words, record the skill here with its number, and close its #413 child on Gate 1
*less the word cap* plus Gate 2 *less `context-efficiency`*. An exception is
granted on a post-pass measurement, never on an estimate.

### Recorded exceptions

| Skill | Floor | Basis |
|---|---:|---|
| **`/issue-pr-review`** | **3239** (lower bound) — 3474 upper | The compression pass ran in #417 / PR #425: 6213 → 4377 `wc -w`, 500 → 379 lines, seven reference files, every conditional section already relocated. Even on the heuristic-free lower bound, deleting every free-prose word leaves 3239. Its pinned material is the per-step gates themselves; D3 forbids moving them. |
| **`/auto-pilot`** | **3375** (lower bound) — 3688 upper; **3089** on the lower bound with every single-word category grep discounted | The compression pass ran in #415 / PR #433: 6026 → 5232 `wc -w`, 481 → 429 lines, 5941 → 5147 `asm` words. Measured **after** the pass by the method above (30 tracked suites traced under `bash -x`, 110 live patterns replayed and unioned). Deleting every free-prose word still leaves 3375. Its pinned material is the per-phase gates, the merge-mode table, the stop-condition table and the run-log write contract; all are raw `grep`s naming `SKILL.source.md`, which the class table forbids re-targeting, and all are every-run gate logic that D3 forbids relocating in any case. |

#### The 330-word objection, answered

#417 §6 names one relocation candidate it left alone: *"moving the per-step
output fences into `references/report-templates.md` would recover roughly 330
words, and no test pins them."* Those fences sit in the structural bucket above,
so on the **lower** bound the arithmetic is 3239 − 330 = **2909 — under the
cap**. The exception has to survive that subtraction, and it does, on two counts.

**On the upper bound it survives outright:** 3474 − 330 = 3144, still over.

**On the lower bound it survives under D3, and this is the purest case of the
trade D3 prohibits.** `references/report-templates.md` is *already* gated
read-now in the body — *"Check names, semantics and format:
`references/report-templates.md` (Step Completion Reports) — **read it now**"* —
and the Step 7 summary templates are read from the same file. The agent loads
that file in full on every run. Moving 330 words from the body into it lowers
`wc -w` by 330 and lowers the agent's loaded context by **exactly zero**. Same
context, smaller number. If that counted, the cap would be measuring nothing.
It does not count, so `/issue-pr-review` is an exception.

### The deferred verdict, resolved — `/auto-pilot`

**Resolved 2026-08-28 in [#415](https://github.com/luongnv89/idd/issues/415):
`/auto-pilot` is a recorded exception.** The pass ran, the floor was re-measured
post-pass, and it did not clear. The accounting is
`docs/experiments/skill-auto-improver-auto-pilot.md` §6. The original framing of
the deferral follows.


`/auto-pilot` measures a floor of 3106–3207, over the cap by 106 words on the
lower bound, and is **neither a clear nor an exception**. It is the only skill
of the eight whose verdict this ADR defers, and it defers it for a reason that
does not apply to any other:

`/issue-pr-review`'s floor was measured **after** its compression pass ran — the
body went 6213 → 4377 `wc -w`, seven reference files were carved out, and the
conditional material was exhausted — so 3239 is a floor. `/auto-pilot`'s 3106
was measured on an **untouched** 6024-word body still carrying 2734–2835 words
of free prose. Compression does not only delete free prose; it also shortens the
assertion-carrying lines *around* their pinned literals, which is where 2405–2553
of the floor's words sit. So 3106 is an upper estimate of `/auto-pilot`'s floor,
not its floor.

#415 runs the pass, then re-measures under D4. If the post-pass floor still
exceeds 3000, `/auto-pilot` joins the exceptions table on that measurement. It
does not get an exception in advance, and it does not get re-litigated as an
artifact question.

## Which assertions may follow a relocation, and which may not

D2 makes relocation *possible*; it does not make every assertion relocatable.

| Class | Follows the contract? | Why |
|---|---|---|
| `anchor_check` / `anchor_check_flat` on a machine token | **Yes** | The token identifies the contract; the file it sits in does not. |
| `anchor_lacks` inside a region | **Yes** | The prohibition scopes to the region, which travels with the anchor. |
| `anchor_present` | **Yes** | Same. |
| `anchor_span` across two anchors | **Yes, within one file** | A span is a contiguous stretch of one document. Package resolution finds the file holding the start anchor and requires the end anchor in that same file. |
| Raw `grep` naming a file | **No** | It pins a file by construction. Migrate it to an anchor first (issue #401's paced work) — do not silently re-target it. |
| Ordering, adjacency, and "stated at each site" assertions | **No** | These *are* placement contracts. See below. |

### Worked example — `tests/test-qa-handoff-255.sh` T20 stays as it is

T20 requires the same eight patterns inside **both** the Step 2 span and the
Step 4 span, which reads like test-mandated duplication. It is not. Issue #283
established that the `tests=` skip is decided at **two independent points** in
the pipeline: Step 2's script pre-pass and Step 4's test run. Each evaluates the
three-part AND — `qa_handoff = trusted` **and** a `tests=` SHA equal to `head`
**and** `ci_leg_runnable` — on its own. An agent that reaches Step 4 must be
able to re-derive `ci_leg_runnable` there; a Step 4 that said only "apply the
same gate as Step 2" creates a real failure mode in which a stale marker skips
the suite. The duplication is a gate stated at each site that applies it, which
is exactly what the contract requires.

T20 is therefore **not relaxed**, and its two decision-site spans
(`rv-step2-prepass`…`rv-step3-analyze` and `rv-step4-tests`…`rv-step5-ci`,
T20.1–T20.16) stay **file-scoped on purpose**. They are the canonical example of
an assertion whose subject genuinely is placement: what they pin is that *each
decision site states its own gate*. Both spans still carry all eight patterns.

Of T20's remaining checks, only T20.23 and T20.24 move to the package root —
they are `anchor_span` calls, and a span follows its anchors. T20.17–T20.22 and
T20.25–T20.27 stay file-scoped: they are raw `grep`s naming
`references/review-loop-mechanics.md` and `references/report-templates.md` by
path, and the class table above forbids silently re-targeting those. Migrating
them is issue #401's paced work. The distinction is per assertion, not per test
file.

## Consequence for every child of #413

| Child | Skill | Consequence under this ADR |
|---|---|---|
| **#415** | `/auto-pilot` | **Deferred verdict, now resolved as an exception** (see the exceptions table). Run the pass: 2734–2835 words of free prose, plus removable prose around the pinned literals. Today's 3106–3207 floor is an over-estimate for an un-compressed body. Not exempt in advance — re-measure under D4 afterwards, and add it to the exceptions table only if the post-pass floor still exceeds 3000. |
| **#416** | `/issue-resolver` | Closed. Clears both gates (97 overall, `context-efficiency` 8, 2958 words). No action. |
| **#417** | `/issue-pr-review` | **Unblocked as a recorded exception.** Its floor exceeds the cap on the lower-bound measurement, and D3 forbids the only remaining route to the cap. Close #417 on the gates it did clear — Gate 1 less the word cap, Gate 2 less `context-efficiency`, overall 93/A, every other category 10 — citing this ADR's exceptions table. Nothing is owed. |
| **#418** | `/issue-triage` | Clears. Floor 2767–2804 against a 3799-word body: cut 799 words from 995–1032 of free prose. Tight but not blocked. Do **not** re-litigate the artifact question. |
| **#419** | `/issue-analysis` | Clears comfortably. Floor 1752–1831; 141 words to cut from 1310–1389 of free prose. |
| **#420** | `/issue-creator` | Clears. Floor 2054–2323; 1840 words to cut from 2517–2786 of free prose. |
| **#421** | `/init-gitissue` | Already passes both gates today — 97 overall, `context-efficiency` 8, 2879 words. Verify and close; no compression needed. |
| **#422** | `/idd-doctor` | Body is 3267 `asm`-equivalent words with a floor of 1905–1991, so the cap is 267 words away and reachable. But it has **no built tree**, so `asm eval` cannot score it and Gate 2 cannot be measured at all. Under D1 its governed artifact is the source package. #422 stays blocked on build support for `src/internal-skills/`, which this ADR does not resolve. |

## Alternatives rejected

- **Pin to the built `skills/<name>/` tree only.** The suite deliberately
  asserts on both trees, because a contract that ships only in `src/` is
  installed for nobody and one that exists only in `skills/` is unauthored.
  `/idd-doctor` has no built tree at all, so the rule would be undefined for one
  of the eight.
- **Relax the assertions to fit the cap.** Rejected outright. The gates are a
  linting standard; the assertions are the behavioural contract. Where they
  disagree the contract wins, which is what D3 and the exceptions table encode.
- **Blanket per-skill exceptions (direction 3 alone).** The measurement does not
  support it: six of eight skills are not blocked by the suite at all. A blanket
  exception would excuse ordinary compression work that is simply outstanding.
- **Migrate all ~33 raw-grep suites to anchors in this change.** `docs/DEVELOPMENT.md`
  paces that as "one named cluster per PR, not the whole inventory" (#401 AC4).
  D2 makes package resolution available to each cluster as it migrates.
