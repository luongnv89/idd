# skill-auto-improver run — `/issue-resolver`

**Issue:** [#416](https://github.com/luongnv89/idd/issues/416) · part of epic #413
**Target:** `src/skills/issue-resolver/` (measured against built `skills/issue-resolver/`)
**Measuring standard:** `skill-auto-improver` v2.1.0
**Mode:** Mode 1 — retrofit. Mode 2 (delegation conversion) declined; see §4.
**Date:** 2026-08-28

Measurement convention: `src/skills/<name>/` holds `SKILL.source.md`, not `SKILL.md`, so
`quick_validate.py` and `asm eval` cannot read the authored source. Every measurement below
was taken read-only against the built tree (`skills/issue-resolver/`); every edit was landed
in `src/skills/issue-resolver/` and the built tree regenerated with `./scripts/build.sh`.
`asm eval --fix` was never run against `skills/` — it writes `SKILL.md.bak` and mutates
frontmatter in a tree the build owns.

Body size was measured two ways, deliberately. `wc -w`/`wc -l` on the file is the working
number; `asm eval`'s own count strips the YAML frontmatter first, and that is the number
Gate 2 scores. The gap is a constant 72 words.

---

## 1. Gate status — baseline → final

| Gate | Check | Baseline | Final |
|------|-------|----------|-------|
| **Gate 1** | `quick_validate.py` exit | 0 (pass) | **0 (pass)** |
| Gate 1 | Frontmatter completeness (`asm eval` → `structure`) | 10/10 | **10/10** |
| Gate 1 | Body under 500 lines | 500 / 500 (**at cap**) | **328 (pass)** |
| Gate 1 | Body under 3000 words | **5609 (FAIL)** | **2991 (pass)** |
| Gate 1 | Negative-trigger clause in description | pass | pass (description untouched) |
| Gate 1 | `metadata.version` semver + `metadata.author` | pass (0.17.0) | **pass (0.18.0)** |
| Gate 1 | `docs/README.md` opens with AI-skip comment | pass | pass |
| Gate 1 | Bundled scripts print descriptive stderr | pass | pass |
| Gate 1 | Dependency preflight (conditional) | **2 of 4 elements** | **4 of 4 (pass)** — see §2 |
| **Gate 2** | `overallScore > 85` | 93 | **97 (grade A)** |
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

Baseline blocker, verbatim from the evaluator: *"Body is over 3000 words — split long
content into referenced files or templates."* Both `context-efficiency` (0 of its 4 length
points) and `prompt-engineering` (1 point) were docked on that one measurement, so the
relocation pass moved two categories at once. Final findings: *"Body length within healthy
range (2991 words)."*

Body size, command of record:

```
wc -w < src/skills/issue-resolver/SKILL.source.md   # 5681 → 3063
wc -l < src/skills/issue-resolver/SKILL.source.md   #  500 →  328
```

Source and built `SKILL.md` measure identically (3063 words / 328 lines), as they did at
baseline.

`metadata.version`: **0.17.0 → 0.18.0** (minor — sections relocated to `references/`, one
new dependency-preflight rule; no behavior or output-format change).

### What moved, and where

Nothing was deleted outright except the *Additional Resources* index, which self-declared as
redundant (*"the precheck list above, not this one, is the authoritative guard"*) and which
`scripts/build/doc_slimming.py` already strips before its bundled-doc reachability scan.
Everything else was **relocated**, and each destination section was written in the same
commit as the cut that pointed at it:

| Moved out of the body | New home (`references/`) |
|---|---|
| `gi-config.py` working-directory / script-path / clock rationale | `pipeline-steps.md` → *Configuration load* (new) |
| Pre-push secret-scan rationale (no config value on the CLI, `--policy-ref` at the base, `scanned: 0`, exit 1 never degrades) | `pipeline-steps.md` → *Step 5 — Deliver → Pre-push secret scan* (new) |
| Per-step auto-mode behavior enumeration | `pipeline-steps.md` → *Auto-mode behavior by step* (new) |
| Per-agent required return shapes and audited fields | `pipeline-steps.md` → *Orchestrating the agents* (new) |
| Caller-payload framing detail | `pipeline-steps.md` → *Step 0i — Caller payload gate* (existing) |
| Run-log field derivation and suppression | `report-templates.md` → *Run-log entry — field derivation and suppression* (existing) |

No exit code, fallback procedure, stop condition, script path, or `<!-- a: -->` anchor was
dropped. The three body anchors (`rs-0a-payload-concurrency`, `rs-0h-skill`,
`rs-deliver-clean-tree`) are present exactly once each, and every phrase the suite pins to
the SKILL body survived — verified after every commit by a scripted guard covering all 34
resolver-touching test files.

---

## 2. Gate 1 — dependency preflight finding

`references/skill-creator-checklist.md` §8 makes the preflight **conditional**: it applies
only to a target that invokes another skill, and *"adding an empty one is itself a defect."*

Signal scan of `/issue-resolver`:

- **Invokes `/issue-creator`?** No. Step 0d normalizes inline and says so explicitly:
  *"the resolver does **not** invoke `/issue-creator` as a subprocess."* Pinned by
  `tests/test-issue-resolver-0d-security.sh`.
- **Reads a path under `~/.claude/skills/`?** **Yes** — Step 3's *Propose relevant skills*
  probes `$HOME/.claude/skills/$name` for every entry in `references/skill-index.md`.
- **Delegates a phase to a named skill?** **Yes, conditionally** — when
  `resolve.borrow_skills: true`, Step 3 installs catalogued skills with
  `npx skills add …` / `asm install … --skill <name>` and hands them to the implementer
  as `selected_skills`.

The condition fires. Two of the four elements were already present at baseline (the
dependency **name** comes from `references/skill-index.md`; the **install command** is
stated at the install site). Two were missing repo-wide, confirmed by grep across `src/`:

- **Installer bootstrap** — added at the install site in `pipeline-steps.md`: probe
  `command -v npx` / `command -v asm`, name `npm install -g agent-skill-manager` as the
  source of `asm`, and degrade (`⚠ No skill installer on PATH … borrowing disabled`,
  propose set stays installed-only) rather than installing an installer unattended.
- **Verification step** — added: confirm with `asm list -p claude --json` (or the
  `~/.claude/skills/<name>/SKILL.md` existence check where `asm` is absent) that the name is
  actually discoverable; a name that does not come back is an install failure and never
  reaches `selected_skills`.

Both landed in `references/pipeline-steps.md`, not the SKILL body — the install site lives
there, and the body was under a hard word gate this pass was closing.

---

## 3. Predictability audit (Phase 2b — advisory, never gates)

Rubric resolved at `~/.claude/skills/skill-creator/references/predictability-rubric.md`
(no fail-soft skip). Walk of all 7 items:

| # | Rubric item | Verdict | Note |
|---|-------------|---------|------|
| 1 | Invocation chosen intentionally | **pass** | User-invoked (`/issue-resolver N`), and the shape matches: the body opens with an *Invocation* table of three forms and reads as "the user asked for this, proceed", not "apply this now". The description still carries the negative-trigger clause because `/auto-pilot` reaches the skill model-invoked. |
| 2 | Branches mapped before the body | **pass** | Four orthogonal branches are selected before any step runs and each is named in one place: mode (interactive / `--auto`), workspace (in-place / accepted worktree / caller-managed `IDD_CALLER_WORKTREE=1`), profile (*0g*, `light` / `full`), and reuse (*0h*, `fresh` / `stale` / `absent`). Branch-specific mechanics are disclosed per branch in `pipeline-steps.md`, not inlined. |
| 3 | Demanding, checkable completion criteria | **pass** | Every step ends in a *Step completion report* — `√`/`×` per check plus `Result: PASS \| PARTIAL \| FAIL` — and the body states *"A step is incomplete until `Result:` prints."* Criteria are tied to commands and counts (`git status --porcelain=v1 --untracked-files=all` empty, `scanned` not 0, the `[N/5]` tracker), not impressions. |
| 4 | Progressive disclosure + delegability | **pass** (this pass fixed it) | Was the failing item: 5609 words in an always-loaded body, at the 500-line cap. Now 2991 words / 328 lines, with every relocated block reached by a one-line pointer naming its target section. Delegability sub-check below. |
| 5 | Leading words | **pass** | Recurring concepts are named once and referred to by name: *stash-first pattern*, *fail-safe*, *red-capable reproduction checkpoint*, *single writer*, *single home*, *degrade vs. stop*, *block verdict*, *last-green test state*, *profile*. The compression pass consistently replaced re-explanation with the leading word plus a pointer. |
| 6 | No duplication / stale sediment / sprawl / no-ops | **pass** (this pass fixed it) | Removed: the *Additional Resources* index (self-declared redundant with the precheck list); three `[N/5]` tracker fences duplicating *Expected Inline Pipeline Output*; the per-step auto-mode enumeration that restated each step's own auto clause; ~40 justification clauses whose rationale now has one home in `references/`. No dead reference remains — every italic section name a body pointer cites resolves to a real `##`/`###` heading in the named file, and the build's closure and precheck-drift guards pass. |
| 7 | Publish-ready — no auto-improver dependency | **pass** | `quick_validate.py` exit 0, `asm eval` 97/A with no category below 8, 328 lines, description carries the negative-trigger clause, `metadata.version`/`author`/`license` present. The skill now clears the standard without a follow-up auto-improver run. |

### Delegability sub-check (item #4)

Rule applied verbatim: *"a step heavy enough to hand off names no slice of `references/` for
its worker — record it as `step N is not delegable because <reason>` (needs the user
mid-step, depends on the previous step's exact text, or its slice is what every run reads
anyway). A skill with nothing to slice passes."*

Every step heavy enough to hand off, walked:

| Step | Heavy enough to hand off? | Names its `references/` slice? |
|---|---|---|
| **Step 1 — Research** | yes | **yes** — `shared/agents/codebase-researcher.md`, payload and phases from `pipeline-steps.md` (*Step 1 — Research*), plus `prior_analysis` / `triage_context` as bound spawn variables. |
| **Step 2 — Plan** | yes | **yes** — `shared/agents/synthesizer.md`, payload from *Step 2 — Plan*. |
| **Step 3 — Implement** | yes | **yes** — `shared/agents/implementer.md`, payload from *Step 3 — Implement*, plus `references/bug-verification.md` for the reproduction checkpoint and `selected_skills` from `references/skill-index.md`. |
| **Step 4 — QA** | yes | **yes** — `shared/agents/code-reviewer.md`, `shared/agents/fixer.md`, `shared/agents/ui-reviewer.md`; the fixer receives `security_convention`, `secscan_script` and `secscan_policy_ref` as bound spawn variables precisely because an emitted agent prompt cannot resolve a skill-relative path. |
| **Step 0 — Preflight** | borderline (0a–0h) | **step 0 is not delegable because it needs the user mid-step** — 0c's assignment/label guard and 0e's worktree offer are interactive decision points, and 0a/0d mutate the issue the rest of the run reads. |
| **Step 5 — Deliver** | borderline | **step 5 is not delegable because it depends on the previous step's exact text** — the PR body's Decision Record and Acceptance Criteria Verification table are built from Step 2's selected option and Step 4's findings verbatim, and the run-stats footer measures from a clock captured in *Configuration*. |

No finding: every heavy step names its slice, and the two orchestrator-resident steps are
recorded with their reason. Advisory only — this did not gate the PASS.

---

## 4. Delegation-conversion decision (Mode 2)

**Declined.** Named precondition it failed: *Mode 2 requires an undelegated heavy phase to
convert, and `/issue-resolver` has none.*

- Steps 1, 2 and 3 each already spawn a `shared/agents/*` subagent through the canonical
  `Agent(...)` pattern; Step 4 spawns the reviewer, the fixer and (auto-detected) the
  ui-reviewer. There is no heavy phase left running in the orchestrator's own context.
- The only orchestrator-resident work is Step 0, Step 4's loop control and Step 5, and each
  fails a conversion precondition for the reason recorded in §3's sub-check: Step 0 needs
  the user mid-step; Step 4's loop control *is* the orchestration; Step 5 depends on the
  previous step's exact text.

A recorded decline is the complete outcome here. Converting further would move the
interactive gates or the durable-memory assembly into a worker, which the methodology
forbids for the same reason it forbids a subagent owning a safety gate.

---

## 5. Run-stats footer (issue #414 shape)

Unchanged by this pass, and deliberately so. The contract settled by #414 is
`elapsed` · `tokens` (conditional) · `agents`, two lines, printed **last at every terminal
outcome**. It lives in `references/run-stats.md`; the SKILL body carries only the pointer,
the `run_started_epoch` capture in *Configuration*, and the enumeration of the terminal
outcomes that never reach the *Closing Summary* block (preflight stop, invalid-config stop,
`already_resolved`, blocked secret scan, failed final test run, any failed step). The field
set was not widened, reordered or renamed. `tests/test-run-stats-373.sh` (156 checks) passes
on both the source and the built tree.

---

## 6. Files changed

| File | Change |
|---|---|
| `src/skills/issue-resolver/SKILL.source.md` | compressed 5681 → 3063 words, 500 → 328 lines; `metadata.version` 0.17.0 → 0.18.0 |
| `src/skills/issue-resolver/references/pipeline-steps.md` | four new sections (*Configuration load*, *Orchestrating the agents*, *Auto-mode behavior by step*, *Step 5 — Deliver → Pre-push secret scan*) plus the installer bootstrap and install verification on the borrow path |
| `skills/issue-resolver/SKILL.md` | regenerated (`./scripts/build.sh`) |
| `skills/issue-resolver/references/pipeline-steps.md` | regenerated |
| `docs/experiments/skill-auto-improver-issue-resolver.md` | this report |

Test suite of record (`git ls-files 'tests/*.sh' | xargs -n1 bash`, serial,
`IDD_AUTO_MODE` unset): **82 passed, 1 failed** — identical to the pre-change baseline on
this machine. The single failure is `tests/test-runs-jsonl-rotation-354.sh` T4, a known
macOS-only artifact (line 114 is the one `wc -l` not piped through `tr -d ' '`, so BSD
`wc` padding makes `"       3" != "3"`); ubuntu CI is green. It is unrelated to this change
and reproduces on pristine `origin/main`.

---

## 7. Unresolved gates

**None.** Both gates pass on the built tree:

- Gate 1 — `quick_validate.py` exit 0; 328 lines (< 500); 2991 words (< 3000); frontmatter
  complete; dependency preflight now carries all four elements.
- Gate 2 — `asm eval` overall **97** (> 85), minimum category **8** (>= 8).

One item is deliberately deferred rather than unresolved: `context-efficiency` scores 8, not
10, because the evaluator's top band is 120–1500 words. Reaching it would require moving
test-pinned contract prose out of the SKILL body — the suite asserts ~40 literal phrases
against `SKILL.source.md` itself (the 0g `light`-profile table rows, the 0e worktree offer
block, the 0d security-label branch, the run-log literals, the secscan pass condition) — so
the practical floor for this skill is a little under 3000 words. 8 clears the gate.
