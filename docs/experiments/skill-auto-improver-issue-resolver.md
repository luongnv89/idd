# skill-auto-improver run — `/issue-resolver`

**Issue:** [#416](https://github.com/luongnv89/idd/issues/416) · part of epic #413
**Target:** `src/skills/issue-resolver/` (measured against built `skills/issue-resolver/`)
**Measuring standard:** `skill-auto-improver` v2.1.0
**Mode:** Mode 1 — retrofit. Mode 2 (delegation conversion) declined; see *Delegation decision*.
**Date:** 2026-08-28

Measurement convention: `src/skills/<name>/` holds `SKILL.source.md`, not `SKILL.md`, so
`quick_validate.py` and `asm eval` cannot read the authored source. Every measurement below
was taken read-only against the built tree (`skills/issue-resolver/`); every edit was landed
in `src/skills/issue-resolver/` and the built tree regenerated with `./scripts/build.sh`.
`asm eval --fix` was never run against `skills/` — it writes `SKILL.md.bak` and mutates
frontmatter in a tree the build owns.

---

## 1. Gate status — baseline → final

| Gate | Check | Baseline | Final |
|------|-------|----------|-------|
| **Gate 1** | `quick_validate.py` exit | 0 (pass) | 0 (pass) |
| Gate 1 | Frontmatter audit (`asm` `skill-best-practice`) | 15/15 (pass) | 15/15 (pass) |
| Gate 1 | Body under 500 lines | 500 / 500 (at cap) | *pending* |
| Gate 1 | Body under 3000 words | **5609 (FAIL)** | *pending* |
| Gate 1 | Negative-trigger clause in description | pass | pass |
| Gate 1 | `metadata.version` semver + `metadata.author` | pass (0.17.0) | *pending* |
| Gate 1 | `docs/README.md` opens with AI-skip comment | pass | pass |
| Gate 1 | Bundled scripts print descriptive stderr | pass | pass |
| Gate 1 | Dependency preflight (conditional) | *see §2* | *pending* |
| **Gate 2** | `overallScore > 85` | 93 | *pending* |
| Gate 2 | every category `>= 8` | **min 6 — `context-efficiency` (FAIL)** | *pending* |

Baseline per-category (`asm eval --json`, provider `quality`):

| Category | Baseline | Final |
|----------|---------:|------:|
| structure | 10 | *pending* |
| description | 10 | *pending* |
| prompt-engineering | 9 | *pending* |
| context-efficiency | **6** | *pending* |
| safety | 10 | *pending* |
| testability | 10 | *pending* |
| naming | 10 | *pending* |

Baseline blocker, verbatim from the evaluator: *"Body is over 3000 words — split long
content into referenced files or templates."* Both `context-efficiency` (0 of its 4
length points) and `prompt-engineering` (1 point) are docked on the same measurement,
so a single relocation pass moves two categories.

`metadata.version`: **0.17.0 → 0.18.0** (minor — sections relocated to `references/`
and a new dependency-preflight section added; no behavior or output-format change).

---

## 2. Gate 1 — dependency preflight finding

`references/skill-creator-checklist.md` §8 makes the preflight **conditional**: it applies
only to a target that invokes another skill, and *"adding an empty one is itself a defect."*

Signal scan of `/issue-resolver`:

- **Invokes `/issue-creator`?** No. Step 0d normalizes inline and says so explicitly:
  *"the resolver does **not** invoke `/issue-creator` as a subprocess — it performs Step 0d
  inline."* Pinned by `tests/test-issue-resolver-0d-security.sh`.
- **Reads a path under `~/.claude/skills/`?** **Yes** — Step 3's *Propose relevant skills*
  probes `$HOME/.claude/skills/$name` for every entry in `references/skill-index.md`.
- **Delegates a phase to a named skill?** **Yes, conditionally** — when
  `resolve.borrow_skills: true`, Step 3 installs catalogued skills with
  `npx skills add …` / `asm install … --skill <name>` and hands them to the implementer
  as `selected_skills`.

So the condition fires, and the gate's four elements were audited against the borrow path.
Two of the four were already present (the dependency **name** comes from
`references/skill-index.md`; the **install command** is stated at the install site). Two were
missing repo-wide — confirmed by grep across `src/`: no **installer bootstrap**
(`npm install -g agent-skill-manager`) and no **verification step**
(`asm list -p claude --json`). Both were added.

---

## 3. Predictability audit (Phase 2b — advisory, never gates)

Rubric resolved at `~/.claude/skills/skill-creator/references/predictability-rubric.md`
(no fail-soft skip). Walk of all 7 items:

| # | Rubric item | Verdict | Note |
|---|-------------|---------|------|
| 1 | Invocation chosen intentionally | *pending* | |
| 2 | Branches mapped before the body | *pending* | |
| 3 | Demanding, checkable completion criteria | *pending* | |
| 4 | Progressive disclosure + delegability | *pending* | |
| 5 | Leading words | *pending* | |
| 6 | No duplication / stale sediment / sprawl / no-ops | *pending* | |
| 7 | Publish-ready — no auto-improver dependency | *pending* | |

### Delegability sub-check (item #4)

*pending*

---

## 4. Delegation-conversion decision (Mode 2)

*pending*

---

## 5. Run-stats footer (issue #414 shape)

*pending*

---

## 6. Files changed

*pending*

---

## 7. Unresolved gates

*pending*
