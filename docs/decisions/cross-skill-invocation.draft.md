# ADR DRAFT — Cross-Skill Invocation Rendering Strategy

> **Status: DRAFT.** This file is a scaffold. The acceptance criteria in
> [#52](https://github.com/luongnv89/idd/issues/52) require **raw experiment
> outputs** and a **chosen §6 decision-matrix row** before this ADR is valid.
> Run [`docs/experiments/cross-skill-invocation.md`](../experiments/cross-skill-invocation.md),
> fill in every `TBD` below, then **rename this file** to
> `cross-skill-invocation.md` and commit. The draft form is intentionally not
> the final filename so that a published `cross-skill-invocation.md` always
> means "decision is made and load-bearing for the build."

---

## Context

**Plan:** [refactor-plan-v10.md](../../refactor-plan-v10.md) §6, §6.0.
**Issue:** [#52](https://github.com/luongnv89/idd/issues/52). Blocks
[#53](https://github.com/luongnv89/idd/issues/53) (auto-pilot rewrite) and
[#56](https://github.com/luongnv89/idd/issues/56) (build script).

The build emits two distribution outputs from one source tree:
`dist/skills/` (flattened, harness-agnostic) and `dist/plugin/` (Claude Code
plugin layout). For each cross-skill, shared-agent, and runtime-doc reference
the build chooses a rendering form. The form depends on which of three runtime
behaviors actually work in subagent prompts (A, B, C — see plan §6.0 and the
experiment procedure). This ADR records what we observed and which §6
decision-matrix row the build implements.

## Experiment results

Each experiment was run **TBD** times per the flake protocol in
`docs/experiments/cross-skill-invocation.md` (3 minimum; 6 if 2-of-3 split).

### Test plugin scaffold

- **Built from:** `scripts/build-test-plugin.sh`
- **Source-tree commit SHA used:** `TBD` (run `git rev-parse HEAD` after the
  PR-2 commit lands; this is the SHA future maintainers `git checkout` to
  re-run the experiments).
- **Skills included:** `issue-creator`, `issue-resolver`, `auto-pilot`
- **Transitive shared-agent closure:** `code-reviewer.md`, `codebase-researcher.md`,
  `duplicate-detector.md`, `implementer.md`, `synthesizer.md`
- **Transitive doc closure:** `config-schema.md`, `github-projects-sync.md`,
  `idd-methodology.md`, `naming-conventions.md`

### Experiment A — Slash-command resolution

**Outcome:** `TBD` (one of `A-1`, `A-fail`).

Raw subagent outputs:

```text
Run 1: TBD
Run 2: TBD
Run 3: TBD
[Run 4-6 if needed: TBD]
```

### Experiment B — `${CLAUDE_PLUGIN_ROOT}` expansion

**Outcome:** `TBD` (one of `B-1`, `B-fail`).

Raw subagent outputs:

```text
Run 1: TBD
Run 2: TBD
Run 3: TBD
[Run 4-6 if needed: TBD]
```

### Experiment C — Sibling-relative paths via parent prompt

**Outcome:** `TBD` (one of `C-1`, `C-fail`).

Raw subagent outputs:

```text
Run 1: TBD
Run 2: TBD
Run 3: TBD
[Run 4-6 if needed: TBD]
```

## Decision

**Chosen §6 decision-matrix row:** `(A=TBD, B=TBD, C=TBD)`

| A | B | C | Standalone rendering | Plugin rendering |
|---|---|---|---|---|
| 1 | 1 | any | `/<name>` | `/<plugin-slug>:<name>`; shared/docs use `${CLAUDE_PLUGIN_ROOT}/...` |
| 1 | fail | 1 | `/<name>` | `/<plugin-slug>:<name>`; shared/docs use `../../../...` (sibling-relative) |
| 1 | fail | fail | `/<name>` | **Plugin output blocked** — slash works but plugin shared/doc references have no working form |
| fail | 1 | any | `../<name>/SKILL.md` | `${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md`; shared/docs use `${CLAUDE_PLUGIN_ROOT}/...` |
| fail | fail | 1 | `../<name>/SKILL.md` | `../../<name>/SKILL.md`; shared/docs use `../../../...` |
| fail | fail | fail | `../<name>/SKILL.md` | **Plugin output blocked** — no working form available |

(Replace this entire table with a single line stating the chosen row when
filling in the ADR — keeping the table here helps readers see what was
considered.)

### Build implications

- **Standalone rendering for `dist/skills/<name>/`:** `TBD`
- **Cross-skill rendering for `dist/plugin/skills/<name>/`:** `TBD`
- **Shared-agent rendering for `dist/plugin/skills/<name>/references/`:** `TBD`
- **Runtime-doc rendering for `dist/plugin/skills/<name>/references/`:** `TBD`

The build script (#56) implements exactly these forms. The
`tests/test-plugin-reference-rendering.sh` test (#58) verifies that
`dist/plugin/` does not mix two forms for the *same* reference type
(cross-type mixing across forms is permitted per §4 Phase E — e.g., row
(A-1, B-fail, C-1) deliberately produces `/<plugin-slug>:<name>` for
cross-skill calls and `../../../shared/agents/X.md` for shared agents in the
same file; both correct, no mix).

## Consequences

- **PR 3 (#56) unblocked.** The build script now has unambiguous rendering
  rules to implement.
- **`auto-pilot` rewrite (#53) unblocked.** Source uses `{{skill:name}}`
  tokens; build rewrites them per the chosen row.
- **Re-validation cadence:** if Claude Code (or another target harness)
  changes behavior on A, B, or C, re-run the experiment procedure, append a
  dated entry below, and follow up with a build-script change. Append-only
  history; never edit prior entries.

## Re-validation log

| Date | Triggering change | Outcome | Action taken |
|------|-------------------|---------|--------------|
| `TBD` | Initial — first run for #52 | A=TBD, B=TBD, C=TBD | Build implements row above |
