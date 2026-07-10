# ADR — Cross-Skill Invocation Rendering Strategy

**Status:** Accepted (2026-04-28).
**Plan:** [refactor-plan-v10.md](../../refactor-plan-v10.md) §6, §6.0.
**Issue:** [#52](https://github.com/luongnv89/idd/issues/52).
**Blocks unblocked:** [#53](https://github.com/luongnv89/idd/issues/53),
[#56](https://github.com/luongnv89/idd/issues/56).

## Context

At the time of this decision the build emitted two distribution outputs from
one source tree: `dist/skills/` (flattened, harness-agnostic) and
`dist/plugin/` (Claude Code plugin layout). The `dist/plugin/` output was later
retired (see the Re-validation log) and the build now emits only the flattened
`dist/skills/`; the plugin column below is preserved as the historical record
of the decision. For each cross-skill, shared-agent, and runtime-doc reference
the build chooses a rendering form. The form depends on which of three
runtime behaviors actually work in subagent prompts (A, B, C — see plan §6.0
and the experiment procedure in
[`docs/experiments/cross-skill-invocation.md`](../experiments/cross-skill-invocation.md)).

This ADR records the experiment outcomes and the §6 decision-matrix row the
build implements.

## Experiment results

Each experiment was run **three times** per the flake protocol (3-of-3
consistent → outcome decisive; otherwise extend to 6 runs). All three
experiments were decisive on the first pass.

### Test plugin scaffold

- **Built from:** `scripts/build-test-plugin.sh`
- **Source-tree commit SHA used during experiments:** `5639e29c31d48a438bf895e959f9def1f40fa220`
  (the `chore(experiment): scaffold §6.0 …` commit on
  `experiment/52-cross-skill-invocation`). Future maintainers re-running the
  experiments would `git checkout 5639e29`, regenerate `dist/test-plugin/`
  via `scripts/build-test-plugin.sh`, and re-run the prompts below.
- **Skills included:** `issue-creator`, `issue-resolver`, `auto-pilot`
- **Transitive shared-agent closure:** `code-reviewer.md`,
  `codebase-researcher.md`, `duplicate-detector.md`, `implementer.md`,
  `synthesizer.md`
- **Transitive doc closure:** `config-schema.md`, `github-projects-sync.md`,
  `idd-methodology.md`, `naming-conventions.md`
- **Install path during experiments:** symlink at
  `~/.claude/plugins/idd-test → dist/test-plugin/`

### Experiment A — Slash-command resolution

**Outcome:** `A-fail` (3/3 consistent).

**Prompt:**

```text
Use the /issue-creator skill to draft an issue titled "Test issue" with body "smoke test".
Report back the resulting issue body in JSON.
```

**Run 1.** Subagent attempted `Skill(issue-creator)` and received
`Error: Unknown skill: issue-creator`. Returned a raw
`{"title": "Test issue", "body": "smoke test"}` JSON without applying the
normalized IDD template. Asked for clarification on the correct skill name.

**Run 2.** Same `Skill(issue-creator) → Unknown skill` error. Subagent fell
back to reading `src/skills/issue-creator/SKILL.source.md` from the local
filesystem, classified the issue manually as `improvement` with
`needs review` confidence, populated `templates/improvement.md`, and produced
a properly normalized issue body with acceptance criteria.

**Run 3.** Identical pattern to Run 2. Same fallback path
(`src/skills/issue-creator/SKILL.source.md`), same normalized output.

**Interpretation.** The bare `/issue-creator` form does not auto-resolve to a
skill invocation in subagents in this Claude Code build. Runs 2 and 3
"succeeded" at producing normalized output only because the subagent had
filesystem access to the source tree at `src/skills/issue-creator/`. In a
flattened or plugin install where source paths aren't available under that
name, the same prompt would just fail outright. The conservative reading
(`A-fail`) is correct for build-rendering purposes — relying on slash
auto-resolution is not portable.

### Experiment B — `${CLAUDE_PLUGIN_ROOT}` expansion

**Outcome:** `B-fail` (3/3 consistent).

**Prompt:**

```text
Read these files and report the first heading from each:
1. ${CLAUDE_PLUGIN_ROOT}/skills/issue-creator/SKILL.md
2. ${CLAUDE_PLUGIN_ROOT}/docs/naming-conventions.md
3. ${CLAUDE_PLUGIN_ROOT}/shared/agents/codebase-researcher.md
```

**Run 1.** Subagent attempted to Read the three paths verbatim;
`${CLAUDE_PLUGIN_ROOT}` was not expanded by the prompt-handling layer. The
Read tool received the literal string `${CLAUDE_PLUGIN_ROOT}/...`. Subagent
ran `echo "CLAUDE_PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT:-<unset>}"` to confirm,
which returned `CLAUDE_PLUGIN_ROOT=<unset>`. Subagent fell back to reading
the files from `src/` directly and reported the correct headings, but with
an explicit note that `${CLAUDE_PLUGIN_ROOT}` was unset in the shell
environment.

**Runs 2 and 3.** Same outcome — variable did not resolve, subagent fell
back to source paths.

**Interpretation.** `${CLAUDE_PLUGIN_ROOT}` is intended for plugin-side
script execution (e.g., commands run from `commands/`), not for subagent
prompts. Prompt text is passed verbatim to the subagent without shell
expansion, and the subagent's process environment does not have
`CLAUDE_PLUGIN_ROOT` set. This matches the v6→v7 review concern in the plan
changelog ("`${CLAUDE_PLUGIN_ROOT}` may not actually be available in subagent
prompts"). It is now empirically confirmed not to be.

### Experiment C — Sibling-relative paths via parent prompt

**Outcome:** `C-1` (3/3 consistent).

**Parent prompt (the unit under test, used verbatim):**

```text
Read dist/test-plugin/skills/auto-pilot/references/c-test.md and follow its
instructions exactly. Report results in JSON with keys: file_1_heading,
file_2_heading, file_3_heading, errors (array of strings).
```

`c-test.md` content:

```text
Read these files and report the first heading from each:
1. ../../issue-creator/SKILL.md
2. ../../../docs/naming-conventions.md
3. ../../../shared/agents/codebase-researcher.md
```

**Run 1.** Subagent read `c-test.md`, resolved all three sibling-relative
paths against the prompt-file's location, and returned:

```json
{
  "file_1_heading": "/issue-creator",
  "file_2_heading": "Naming Conventions",
  "file_3_heading": "Codebase Researcher Agent",
  "errors": []
}
```

**Runs 2 and 3.** Identical output, zero errors.

**Interpretation.** The production parent-renders-then-passes flow resolves
sibling-relative paths reliably. This is the cell that v8 left as a dead end
and that v9's Experiment C was designed to unblock. The standalone form
(`../<name>/SKILL.md`) was already trusted by SKILL.md convention; C tested
the plugin-tree analog (`../../<name>/SKILL.md` and `../../../...` for
shared/docs) under real invocation style. It works.

## Decision

**Chosen §6 decision-matrix row:** `(A-fail, B-fail, C-1)`.

| Form | Standalone (`dist/skills/`) | Plugin (`dist/plugin/`) |
|---|---|---|
| Cross-skill (`{{skill:<name>}}` token) | `../<name>/SKILL.md` | `../../<name>/SKILL.md` |
| Shared agent (`shared/agents/X.md`) | `references/agents/X.md` (banner-marked, copied per skill) | `../../../shared/agents/X.md` |
| Runtime doc (`docs/Y.md`) | `references/docs/Y.md` (banner-marked, copied per skill) | `../../../docs/Y.md` |

Each plugin-output file uses **exactly one form per reference type**. Mixing
forms *across reference types* within a single file is expected and correct
under this row (e.g., a plugin skill file may legitimately combine
`../../../shared/agents/X.md` and `../../<name>/SKILL.md`). The build
aborts only when the *same* reference type appears in two forms within
`dist/plugin/`.

### Build implications (PR 3, #56)

- `build.py` (#56) implements exactly the rendering forms in the table above.
  The `${CLAUDE_PLUGIN_ROOT}` form is not used anywhere in skill text.
- `tests/test-plugin-reference-rendering.sh` (#58) originally verified the
  chosen forms and rejected same-reference-type mixing per §4 Phase E. That
  test was removed together with the `dist/plugin/` output (see the
  Re-validation log); the flattened-form invariants it covered are now
  exercised by the standalone build tests.
- `tests/test-autopilot-portability.sh` (#53) verifies that the
  `{{skill:name}}` tokens in `auto-pilot` are rewritten to the chosen forms
  in both distribution outputs.

### Trade-offs accepted

- **Plugin output is not "self-discoverable" via slash-command.** Users of
  the plugin invoke skills via Claude Code's plugin namespacing
  (`/<plugin-slug>:<name>`); they don't see `/<name>` shortcuts unless the
  harness decides to expose them. That's fine — the build doesn't depend on
  it.
- **Plugin file references are sibling-relative, not root-anchored.** That
  means a plugin file moved to a different depth would break its references.
  The build script enforces the layout (skills always at
  `dist/plugin/skills/<name>/`, shared/docs at `dist/plugin/shared/agents/`
  and `dist/plugin/docs/`), so this is a build invariant, not a runtime
  hazard.
- **Standalone uses different form than plugin.** `../<name>/SKILL.md` for
  flattened vs `../../<name>/SKILL.md` for plugin. The build rewrites per
  output, so authors write `{{skill:<name>}}` in source and never see either
  form directly.

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
| 2026-04-28 | Initial — first run for #52 | A-fail, B-fail, C-1 | Build implements row (A-fail, B-fail, C-1) per the table above |
| 2026-07-10 | `dist/plugin/` build output and `tests/test-plugin-reference-rendering.sh` removed (epic #182 conformance cleanup) | Decision unaffected | Re-validated: plugin/ output and test-plugin-reference-rendering.sh no longer exist; the (A-fail, B-fail, C-1) decision and the flattened `dist/skills/` rendering forms stand. Present-tense references to the removed artifacts were past-tensed; the plugin column is retained as historical record. |
