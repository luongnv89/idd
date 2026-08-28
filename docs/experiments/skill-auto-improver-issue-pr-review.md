# skill-auto-improver run — `/issue-pr-review`

**Issue:** [#417](https://github.com/luongnv89/idd/issues/417) · part of epic #413
**Target:** `src/skills/issue-pr-review/` (measured against built `skills/issue-pr-review/`)
**Measuring standard:** `skill-auto-improver` v2.1.0
**Mode:** Mode 1 — retrofit. Mode 2 (delegation conversion) declined; see §5.
**Date:** 2026-08-28

> **Two gates are left unresolved, both on body length:** Gate 1's *under 3000
> words* threshold, and Gate 2's *every category >= 8* floor, which for this skill
> is decided by `context-efficiency` and `context-efficiency` alone. Everything
> else passes: overall 93/A, every other category 10, `quick_validate.py` exit 0,
> 380 lines against the 500 cap.
>
> §6 is not an estimate and not a judgement call. The body is 4376 `wc -w`; the
> gate needs ≤ 3065. Of those words, **2835 sit on the 70 lines that carry a
> verified test assertion** and **672 are structural** (fences, tables, headings,
> the precheck list). Deleting *all* 869 remaining words of free prose still
> lands at 3507 — 442 words short. The target is unreachable without either
> deleting operative instruction or changing what the suite asserts, and #417
> puts test changes out of scope. §6.1 gives the method and the two constraint
> classes that do not show up as word counts.

Measurement convention: `src/skills/<name>/` holds `SKILL.source.md`, not
`SKILL.md`, so `quick_validate.py` and `asm eval` cannot read the authored source.
Every measurement below was taken read-only against the built tree
(`skills/issue-pr-review/`); every edit was landed in
`src/skills/issue-pr-review/`, including the version bump, and the built tree
regenerated with bare `./scripts/build.sh` (which promotes, so CI's
`git diff --exit-code -- skills/` stays clean). `asm eval --fix` was never run
against `skills/`.

Body size is reported two ways. `wc -w` on the file is the working number;
`asm eval` strips the YAML frontmatter first, and **that** is the number Gate 1
and Gate 2 score. This skill's frontmatter is 65 words, so its two numbers sit 65
apart — a property of this frontmatter, not a constant.

---

## 1. Gate status — baseline → final

| Gate | Check | Baseline | Final |
|------|-------|----------|-------|
| **Gate 1** | `quick_validate.py` exit | not measured at baseline | **0 — "Skill is valid!"** |
| Gate 1 | Frontmatter audit (`asm eval` → `structure`) | 10/10 | **10/10** |
| Gate 1 | Body under 500 lines | 500 / 500 (**at cap**) | **380 (pass)** |
| Gate 1 | Body under 3000 words | **6148 (FAIL)** | **4311 (still FAIL)** — §6 |
| Gate 1 | Negative-trigger clause in description | pass | pass (description untouched) |
| Gate 1 | `metadata.version` semver + `metadata.author` | pass (2.5.0) | **pass (2.7.0)** |
| Gate 1 | `docs/README.md` opens with the AI-skip comment | pass | pass |
| Gate 1 | Bundled scripts print descriptive stderr | pass | pass |
| Gate 1 | Dependency preflight (conditional) | **not applicable** | **not applicable** — §3 |
| **Gate 2** | `overallScore > 85` | 87 (grade B) | **93 (grade A)** |
| Gate 2 | every category `>= 8` | **min 6 (FAIL)** | **min 6 (still FAIL)** — §6 |

Per-category (`asm eval --json skills/issue-pr-review`, built tree):

| Category | Baseline | Final |
|----------|---------:|------:|
| structure | 10 | 10 |
| description | 10 | 10 |
| prompt-engineering | 9 | 9 |
| context-efficiency | **6** | **6** |
| safety | **9** | **10** |
| testability | **7** | **10** |
| naming | 10 | 10 |
| **overall** | **87 (B)** | **93 (A)** |

Body size, command of record:

```
wc -w < src/skills/issue-pr-review/SKILL.source.md   # 6213 → 4376
wc -l < src/skills/issue-pr-review/SKILL.source.md   #  500 →  380
```

Source and built `SKILL.md` measure identically, as they did at baseline.
`metadata.version`: **2.5.0 → 2.6.0** (minor — sections relocated to
`references/`, two new reference sections, two new body rules).

---

## 2. The three findings, and what closed them

The baseline had one length finding docked twice and two independent findings.
They were closed in that order deliberately: the two non-length fixes *add*
words, so landing them after the compression would have re-broken the count.

**`testability` 7 → 10.** Evaluator, verbatim: *"Include an \"Expected output\"
example so reviewers and the agent can verify correctness."* The check is a
match for `expected\s+(output|result|response)`, and the body had none. The
Pipeline Overview fence already **was** that example; it is now labelled as one
— *"**Expected output** — example of a clean run, one line per step"*. The word
`example` also feeds `prompt-engineering`'s fenced-example cue, which is why the
label carries it.

**`safety` 9 → 10.** The evaluator pairs a destructive action with a
confirmation; it found the confirmation cues and no destructive action, so the
pair never scored. That was accurate about the text, not about the skill: this
skill's auto-merge squash merges the PR **and deletes the head branch**, and the
body never said so. Step 7 now states the destructive action and the three gates
that confirm it (interactive never merges whatever `review.auto_merge` says;
`--auto` merges only when `review.auto_merge` is true and the PR is clean, and
pending CI is never clean; `--no-merge` suppresses it outright), plus the rule
that a refused merge is never "finished" by deleting the branch by hand. This is
a real gap closed, not a keyword drop.

**`context-efficiency` 6 and `prompt-engineering`'s length point.** One
measurement, docked in two categories: *"Body is over 3000 words — split long
content into referenced files or templates."* Unresolved — §6.

### What moved, and where

Every destination section was written in the **same commit** as the cut that
points at it.

| Moved out of the body | New home |
|---|---|
| Per-key config semantics: strict `soft_pass`, the two verification flags when `false`, exemption scope, browser-review gate — plus every default value, and the note that this is the by-hand read list when `gi-config` degrades | `references/review-loop-mechanics.md` → *Config keys and what they gate* (new) |
| Why `branch_name` must be command-substituted: which metacharacters git allows in a ref, why double quotes do not stop `$(…)` or a backtick, why substitution output is inert, why display templates keep the plain placeholder | `references/review-loop-mechanics.md` → *Binding the head-ref name* (new) |
| Step 5's manual polling loop, settle-window rule, failure extraction and bare-vs-bound cases (already owned there) | `references/prepass-tests-ci-mechanics.md` → *Step 5*, *Binding the verdict to a commit* |
| The `--policy-ref` trust-boundary rationale and the four-part-pass table (already owned there) | `references/prepass-tests-ci-mechanics.md` → *Commit auto-fixes* |
| Loop-control rationale: what `light` and `trusted` each change, the re-evaluation procedure | `references/review-loop-mechanics.md` → *What `light` changes in the loop*, *Re-evaluation after a push* |

**Deleted outright:** the *Additional Resources* index (154 words). It was
redundant with the *Bundled dependency precheck*, which the body itself names as
the authoritative guard. The build's zero-mention scan strips **both** blocks
before it runs, so the deletion cannot mask an orphan: the build reports 0
`"but no runtime instruction references it"` warnings, and
`tests/test-bundled-doc-slimming-249.sh` AC1 asserts exactly that. The precheck
paragraph's sentence naming the index was reworded in the same commit, so no
pointer dangles. `shared/agents/ui-reviewer.md` was the one entry with no other
body mention; it is named and spawned in `docs/ui-review.md`, which is bundled
and reached from Step 3 under a read-now pointer.

### One printed string changed, deliberately

The config degrade line is now
`⚠ gi-config unavailable — reading .gitissue.yml by hand`, not
`⚠ gi-config unavailable — using the inline defaults below`. The old wording
pointed at an inline default list that moved to the reference table, so leaving
it would have created the dangling pointer #416 was corrected for. This adopts
`/issue-resolver`'s existing wording rather than inventing a third.

**The cost is real and is recorded rather than glossed:** that paragraph was
byte-identical across five skills (`issue-analysis`, `issue-creator`,
`issue-pr-review`, `issue-triage`, `auto-pilot`); it is now identical across
four, with `issue-pr-review` joining `issue-resolver` on the by-hand wording. No
test asserts byte-identity of this paragraph — `tests/test-run-stats-373.sh`
AC6's identity check is on `references/run-stats.md`, and
`tests/test-scripts-pipeline-251.sh` T5 checks per-skill properties — so nothing
broke, but the divergence is a fact about the tree, not a non-event.

### How preservation was checked, and what each instrument could not see

Three instruments, in increasing order of what they actually catch:

1. **A pinned-literal guard.** 110 quoted strings extracted up front from the 20
   `tests/*.sh` files that mention this skill, re-checked after every commit and
   classified `RELOCATED` (now in `references/`, verify the test's real target)
   or `GONE`. Final state: 6 relocated, 0 gone. **It answers one question —
   is every literal still somewhere — and it never saw a single one of the eight
   real losses below.**
2. **The test suite.** It caught five: two phrases inside the
   `rv-depth-gate-refresh` span had been re-wrapped across a newline and these
   assertions are line-based (`even when \`review.adaptive_depth\` is \`false\``,
   `never review a linked issue on an empty`); Step 2 lost *"recompute the verdict
   then, before Step 3"*; the traceability outcomes bullet lost the
   human-authored-PR case; and Configuration lost *"that same `python3`
   invocation"*, which is what binds the clock capture to the config load rather
   than to a second round trip.
3. **A word-level diff read one removed token at a time** (`git diff --word-diff`,
   asking of each removal whether it is a verb, an exit code, a path, a
   stop-vs-degrade distinction, a printed string, or a section pointer). It
   caught three the green suite did not: Step 5 lost *"do not assume a later
   cycle will re-check once the fix loop has ended"* — without which auto mode
   may treat a pending-CI timeout as deferrable; the precheck lost *"immediately"*
   from its stop verb; and the printed string
   `⚠ gi-secscan unavailable — running the documented scan` had been wrapped
   across a newline, so it was no longer greppable as one string.

**Suite-green is not evidence that meaning survived.** Three of the eight losses
were found only after the suite was green.

No exit code, fallback procedure, stop condition, script path, guard, warning
verb, printed string, or `<!-- a: -->` anchor was dropped. All twelve body
anchors are present exactly once each.

---

## 3. Gate 1 — dependency preflight finding

`references/skill-creator-checklist.md` §8 makes the preflight **conditional**: it
applies only to a target that invokes another skill, and *"adding an empty one is
itself a defect."*

Signal scan of `/issue-pr-review`:

- **Invokes another gitissue skill?** No. The body states it: *"This skill
  requires no other gitissue skill."* Its only `asm install` line is the
  reinstall hint inside the `✗ Missing bundled dependency` block — that is a
  repair instruction for this skill, not a dependency on another.
- **Reads a path under `~/.claude/skills/`?** No. `grep` over
  `src/skills/issue-pr-review/**` returns nothing for `.claude/skills/`,
  `npx skills add`, or `borrow_skills`.
- **Delegates a phase to a named skill?** No. Every delegation is to a
  `shared/agents/*.md` **subagent prompt** — reviewer, ui-reviewer, fixer — not
  to a skill.

Repo-wide, the same grep returns only `issue-resolver` (its `resolve.borrow_skills`
path). This is consistent with `references/run-stats.md`, which states that *"only
two of the eight skills can invoke another skill at run time."*

**The condition does not fire, so no preflight was added.** Adding an empty one
would be the defect the checklist names.

---

## 4. Predictability audit (Phase 2b — advisory, never gates)

Walk of all 7 rubric items.

| # | Rubric item | Verdict | Note |
|---|-------------|---------|------|
| 1 | Invocation chosen intentionally | **pass** | User-invoked (`/issue-pr-review [N]`), and the shape matches: the body opens with an *Invocation* table of five forms and reads as "the user asked for this, proceed". The description keeps its negative-trigger clause because `/auto-pilot` reaches this skill model-invoked. |
| 2 | Branches mapped before the body | **pass** | Four orthogonal branches are selected before the loop runs and each is named in one place: mode (interactive / `--auto` / `--auto --no-merge` / `--review-only`), depth (*Depth gate*, `light`/`full`), QA reuse (*QA handoff gate*, `trusted`/`stale`/`absent`), and CI runnability (`ci_leg_runnable`). Their interaction has a single home — *Precedence, stated once*. |
| 3 | Demanding, checkable completion criteria | **pass** | Every step ends in a *Step completion report* — `√`/`×` per check plus `Result: PASS \| PARTIAL \| FAIL` — and the body states that a step is not complete until its `Result:` line prints. Criteria are tied to commands and values (the four-part secscan pass condition, `ci_status` bound to a 40-character SHA, the soft-pass conjunction), not impressions. |
| 4 | Progressive disclosure + delegability | **partial — this pass improved it but did not clear it** | Line count went 500 → 422 and five blocks of rationale moved to `references/` behind read-now pointers, but the body is still 4539 words against the standard's ~3000. §6 states why. Delegability sub-check below: pass. |
| 5 | Leading words | **pass** | Recurring concepts are named once and referred to by name: *stash-first pattern*, *fail-safe*, *degrade vs. stop*, *block verdict*, *trust boundary*, *soft-pass conjunction*, *depth carve-out*, *hard-block*, *collapsed into*. The compression pass consistently replaced re-explanation with the leading word plus a pointer. |
| 6 | No duplication / stale sediment / sprawl / no-ops | **pass** (improved) | Removed: the *Additional Resources* index (self-declared redundant); Step 5's restatement of the manual polling loop that `prepass-tests-ci-mechanics.md` owns in full; the `--policy-ref` rationale duplicated from the same file; the per-key config semantics duplicated between *Configuration* and the loop controls; ~30 justification clauses whose rationale now has one home. The build's closure, parity and precheck-drift guards all pass, and the zero-mention scan reports 0. |
| 7 | Publish-ready — no auto-improver dependency | **partial** | `quick_validate.py` exits 0; `asm eval` is 93/A; 422 lines; description carries the negative-trigger clause; `metadata.version`/`author`/`license` present. But `context-efficiency` is 6, below Gate 2's floor of 8, so a future auto-improver run would still flag this skill on the same measurement. |

### Delegability sub-check (item #4)

Rule applied verbatim: *"a step heavy enough to hand off names no slice of
`references/` for its worker — record it as `step N is not delegable because
<reason>` (needs the user mid-step, depends on the previous step's exact text, or
its slice is what every run reads anyway). A skill with nothing to slice passes."*

Every step heavy enough to hand off, walked:

| Step | Heavy enough to hand off? | Names its `references/` slice? |
|---|---|---|
| **Step 3 — Analyze & Review** | yes | **yes** — `shared/agents/code-reviewer.md` and `shared/agents/ui-reviewer.md`, with the spawn payload and `SendMessage` re-review prompt in `references/review-loop-mechanics.md`, the UI deltas in `references/ui-review-mechanics.md` and `docs/ui-review.md`, and the AC/traceability procedure in `references/verification-checks.md`. `branch_name`, `base_branch`, `pr_context`, `diff_command` and `review.confidence_threshold` are bound spawn variables. |
| **Step 6 — Fix Issues** | yes | **yes** — `shared/agents/fixer.md`, with spawn variables and the `Agent(...)` call in `references/review-loop-mechanics.md`; the fixer receives the `--policy-ref` base ref and the `gi-secscan.py` path as bound spawn variables precisely because an emitted agent prompt cannot resolve a skill-relative path. |
| **Step 2 — Script Pre-pass** | borderline | **step 2 is not delegable because its slice is what every run reads anyway** — the tool-detection table in `prepass-tests-ci-mechanics.md` is read on every run, and the step's real work is the `gi-secscan` gate, a safety gate a subagent must not own. |
| **Step 1 — Get PR Info** | borderline | **step 1 is not delegable because it needs the user mid-step** — the `--review-only` / worktree-free interactive path asks before any write, and 1's outputs (`headRefOid`, `linked_issue_snapshot`, `profile`, `qa_handoff`) are what every later step reads, so the slice is not separable. |
| **Step 5 — Check CI Status** | no | Single script invocation plus a verdict read — *Context weight* rules it out. |
| **Step 7 — Summary Report** | borderline | **step 7 is not delegable because it depends on the previous step's exact text** — the summary and the run-stats footer are built from Step 3's findings and Step 4/5's verdicts verbatim, and `elapsed` measures from a clock captured in *Configuration*. |

**Pass:** both heavy steps name their slice, and the four orchestrator-resident
steps are each recorded with their reason, which is the sub-check's stated bar.
Advisory only — this did not gate anything.

---

## 5. Delegation-conversion decision (Mode 2)

**Declined**, on two of the four preconditions in `skill-auto-improver`'s
`references/delegation-conversion.md` → *When Mode 2 applies* (*"All four must
hold. Any miss and the answer is Mode 1, or nothing"*):

- **Precondition 1, verbatim:** *"The target **clears Gate 1** already. A
  conversion on top of an unpublishable skill compounds two problems; retrofit
  first."* This target does **not** clear Gate 1 — its body is 4311 words against
  the 3000 threshold (§6). On its own this settles the mode.
- **Precondition 4, verbatim:** *"**The user has confirmed the restructure in this
  run.** Name the steps you would convert and the version bump it forces, and
  wait. A conversion rewrites the skill's workflow; it is never something this
  skill decides on the user's behalf."* No confirmation was given — the
  restructure was never put to the user.

It would also have had little to convert, which is why the decline is not merely
procedural: Steps 3 and 6 already spawn `shared/agents/*` subagents through the
canonical `Agent(...)` pattern, and each remaining orchestrator-resident step
fails a conversion precondition for the reason recorded in §4's sub-check.
Converting further would move a safety gate (`gi-secscan`) or an interactive
decision point into a worker.

A recorded decline with a named reason is a complete outcome.

---

## 6. Unresolved gates — the measured reason

**Gate 1's *under 3000 words* and Gate 2's *every category >= 8* are the same
finding.** `context-efficiency` scores `+2` for a body at or under 3000 words and
`+0` above it; the rest of its points (`+3` external references, `+2` no oversized
code block, `+1` a tokens/budget mention) are already earned, so the category is
6 and cannot reach the floor of 8 until the body is under 3000. Overall 93 is
comfortably above the >85 bar and is not the blocker.

The pass took the body from **6148 → 4311** asm words (−30%) and **500 → 380**
lines. It stopped there because what remains is contract that the repo's own
test suite pins to `SKILL.source.md` **by file, by phrase, and in some cases by
line and by region**. The composition below is measured, not estimated — the
method is in §6.1.

| Component | Words | Movable? |
|---|---:|---|
| Words on the **70 lines** that carry at least one verified assertion greping `SKILL.source.md` | **2835** | Only *around* the literal. The line must keep the asserted phrase, and several assertions are line-oriented conjunctions that forbid re-wrapping. |
| Structural words — fenced blocks, tables, headings | **672** | Mostly no. The *Expected output* fence is what the evaluator's `testability` check matches, and the *Bundled dependency precheck* list is asserted by `test-scripts-pipeline-251.sh` T1. |
| Free prose — not on an assertion line, not structural | **869** | Yes, in principle. |

**This is the arithmetic that closes the question.** Reaching Gate 1 needs
`wc -w` ≤ 3065 (asm ≤ 3000), i.e. **1311 more words**. Deleting *every one of the
869 free-prose words* — every pointer, every degrade path, every stop condition
not currently under a grep — still lands at 3507 `wc -w` / **3442 asm**, which
fails Gate 1. The remaining 442 words would have to come out of the 70
assertion-carrying lines or the structural block. So the target is not reachable
by relocation; it is reachable only by deleting operative instruction or by
changing what the tests assert, and #417 rules the latter out of scope.

For scale: the pure pinned-literal text — the characters a test matches
verbatim — is **18.6%** of the body (~815 words). The gap between that 815 and
the 2835 words on those lines is the instruction the literals sit inside, which
is why "only 18% is pinned" does **not** mean 82% is removable.

### 6.1 How the composition was measured

The 20 test files that assert against this skill were enumerated (the 9 that name
it obviously, plus 11 found by sweeping every tracked `tests/*.sh` for loops,
arrays and glob sweeps that reach it: `test-secscan-policy-274.sh`,
`test-scripts-252.sh`, `test-scripts-pipeline-251.sh`, `test-run-stats-373.sh`,
`test-disclosure-gates-250.sh`, `test-skill-line-cap-247.sh`,
`test-skill-frontmatter-keys-307.sh`, `test-agent-conventions-inline-245.sh`,
`test-flattened-self-contained.sh`, `test-root-skills-install-surface.sh`,
`test-bundled-doc-slimming-249.sh`). That yields **281 distinct assertions**, of
which 113 are positive line-oriented patterns against the body; those 113 were
replayed with `grep -noE` to mark the exact matched character spans, and the
spans were aggregated per line and per section.

Two classes of constraint do not show up as words but bound the rewrite anyway:

- **Region and span assertions.** `tests/lib/anchors.bash` bounds an
  `anchor_check` region at the next heading or the next `<!-- a:… -->`, so the
  eight assertions on `rv-depth-gate-refresh` must all live inside that one
  region. `anchor_span` additionally pins anchor *ordering*, and three spans
  (`rv-commit-autofix`→`rv-step3-analyze`, `rv-verify-gates`→`rv-step4-tests`,
  `rv-step5-ci`→`rv-step6-fix`) must **not** contain the string `qa_handoff`.
- **Test-mandated duplication.** `test-qa-handoff-255.sh` T20 requires the same
  eight patterns — including `ci_leg_runnable`, `empty statusCheckRollup|no_ci`
  and "ignore `tests=` and run the local suite as unmarked" — in **both** the
  Step 2 span and the Step 4 span. The obvious "state it once, point from the
  other" dedup is therefore forbidden, not merely unhelpful.

Two further lines are fixed by the evaluator rather than the suite: the labelled
*Expected output* fence (which earned `testability` 10 in this same PR) and the
destructive-auto-merge paragraph with its three gates (which earned `safety` 10).
Removing either to save words would re-break a gate this PR already closed.


**The honest position:** this skill's practical floor is around 4000–4200 words
while those contracts stay where the tests require them. Closing the gate
properly needs a decision this issue did not have standing to make — either
relaxing which file those ~30 assertions target so the contract can live in
`references/` behind read-now pointers, or accepting that
`/issue-pr-review` is a documented exception to the 3000-word cap. Both are
follow-up work, not something to smuggle in under a compression pass, and
neither is served by editing the tests to fit the lint.

Not attempted, and why: moving the per-step output fences into
`references/report-templates.md` would recover roughly 330 words, and no test
pins them. It was left alone because it does not change either gate's verdict
and it would put printed-string contract one pointer away from the step that
prints it — a worse trade than the 330 words are worth.

---

## 7. Run-stats footer (issue #414 shape)

The **contract is unchanged**; the prose carrying it was reworded during
compression and one clause was dropped and restored (*"that same `python3`
invocation"*, §2). The #414-settled field set is `elapsed` · `tokens`
(conditional) · `agents`, two lines, printed **last at every terminal outcome**.
It lives in `references/run-stats.md`, byte-identical across all eight skills;
the body carries only the pointer, the `run_started_epoch` capture in
*Configuration*, and the enumeration of terminal outcomes that never reach Step 7.
The field set was not widened, reordered or renamed.
`tests/test-run-stats-373.sh` (156 checks) passes on both trees.

---

## 8. Files changed

| File | Change |
|---|---|
| `src/skills/issue-pr-review/SKILL.source.md` | 6213 → 4376 `wc -w`, 500 → 380 lines; `metadata.version` 2.5.0 → 2.7.0; *Expected output* label and the destructive auto-merge rule added; *Additional Resources* deleted |
| `src/skills/issue-pr-review/references/review-loop-mechanics.md` | two new sections — *Config keys and what they gate* (now also carrying every default value, plus *Why the working directory and the script path both matter*) and *Binding the head-ref name*; *Why reuse the reviewer* gains *What the `trusted` collapse actually buys* |
| `src/skills/issue-pr-review/references/ui-review-mechanics.md` | new *The two legs, and why only one of them can be blocked* |
| `src/skills/issue-pr-review/references/error-messages.md` | new *Merge conflict with base* — the rebase-command block the Edge Cases pointer now depends on |
| `skills/issue-pr-review/SKILL.md` | regenerated (`./scripts/build.sh`) |
| `skills/issue-pr-review/references/review-loop-mechanics.md` | regenerated |
| `docs/experiments/skill-auto-improver-issue-pr-review.md` | this report |

Test suite of record (`git ls-files 'tests/*.sh' | xargs -n1 bash`, serial,
`IDD_AUTO_MODE` unset): **83 passed, 1 failed** — identical to the pre-change
baseline on this machine. The single failure is
`tests/test-runs-jsonl-rotation-354.sh` T4, a known macOS-only artifact (line 114
is the one `wc -l` not piped through `tr -d ' '`, so BSD padding makes
`"       3" != "3"`); ubuntu CI is green, and it reproduces on pristine `main`.
