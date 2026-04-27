# Experiment: Cross-Skill Invocation in Subagents

**Status:** Procedure. Run before PR 3 (build script) opens.
**Plan:** [refactor-plan-v10.md](../../refactor-plan-v10.md) §6.0.
**Issue:** [#52](https://github.com/luongnv89/idd/issues/52).
**ADR target:** [`docs/decisions/cross-skill-invocation.md`](../decisions/cross-skill-invocation.md) (currently `cross-skill-invocation.draft.md` until experiments are run).

## Why this exists

The build script in PR 3 (#56) emits two distribution outputs from one source tree: `dist/skills/` (flattened, harness-agnostic) and `dist/plugin/` (Claude Code plugin layout). For each cross-skill, shared-agent, and runtime-doc reference the build has to choose a rendering form. The chosen form depends on which of three runtime behaviors actually work in subagent prompts:

- **A:** Does a subagent receiving "Use the `/issue-resolver` skill" actually invoke it?
- **B:** Does a subagent prompt containing `${CLAUDE_PLUGIN_ROOT}` resolve the variable to the plugin root?
- **C:** Does a subagent receiving a sibling-relative path like `../../<name>/SKILL.md` (from a plugin skill's `references/` file) successfully read the target?

The §6 decision matrix in the plan maps the eight (A, B, C) combinations to specific rendering strategies, including two failure cells where plugin output is impossible. This experiment populates the matrix unambiguously.

## Prerequisites

- A Claude Code installation that supports plugins.
- The repository cloned and on the `experiment/52-cross-skill-invocation` branch (or any branch that contains `scripts/build-test-plugin.sh`).
- A clean working tree.

## Procedure

### Step 1 — Build the test plugin scaffold

From the repo root:

```bash
./scripts/build-test-plugin.sh
```

This produces `dist/test-plugin/` with:
- `.claude-plugin/plugin.json` (slug `idd-test`)
- `skills/issue-creator/`, `skills/issue-resolver/`, `skills/auto-pilot/` and their transitive shared/agents and docs closure
- `skills/auto-pilot/references/c-test.md` (Experiment C's prompt file)

The script prints install instructions for symlinking or copying `dist/test-plugin/` into your Claude Code plugins directory. Restart Claude Code after install.

### Step 2 — Run Experiment A (slash-command resolution)

In a fresh Claude Code session **without** the test plugin installed (this experiment doesn't need plugin context — it tests baseline subagent behavior). Spawn a one-off Agent with this exact prompt:

```text
Use the /issue-creator skill to draft an issue titled "Test issue" with body "smoke test".
Report back the resulting issue body in JSON.
```

Record the raw subagent response.

**Outcomes:**
- **A-1: Auto-resolves.** Subagent invokes `/issue-creator` (visibly, in tool calls or response) and returns a normalized issue body in JSON.
- **A-fail: Treats as text or partial.** Subagent guesses based on the skill name, errors, refuses, or works inconsistently across runs. This is the signal to use the sibling-relative fallback for portability.

### Step 3 — Run Experiment B (`${CLAUDE_PLUGIN_ROOT}` expansion)

In a Claude Code session **with the test plugin installed**. Spawn a subagent with this exact prompt:

```text
Read these files and report the first heading from each:
1. ${CLAUDE_PLUGIN_ROOT}/skills/issue-creator/SKILL.md
2. ${CLAUDE_PLUGIN_ROOT}/docs/naming-conventions.md
3. ${CLAUDE_PLUGIN_ROOT}/shared/agents/codebase-researcher.md
```

Record the raw subagent response.

**Outcomes:**
- **B-1: Resolves.** Subagent reads all three files and reports expected headings.
- **B-fail: Does not resolve** (treats `${CLAUDE_PLUGIN_ROOT}` as literal text, errors on path-not-found, or returns empty).

### Step 4 — Run Experiment C (sibling-relative paths via parent prompt)

In a Claude Code session **with the test plugin installed**. The unit under test is the parent-then-subagent flow that production `auto-pilot` uses, not direct file reads. Spawn a subagent with this **exact** parent prompt:

```text
Read dist/test-plugin/skills/auto-pilot/references/c-test.md and follow its
instructions exactly. Report results in JSON with keys: file_1_heading,
file_2_heading, file_3_heading, errors (array of strings).
```

The subagent will open `c-test.md`, which contains:

```text
Read these files and report the first heading from each:
1. ../../issue-creator/SKILL.md
2. ../../../docs/naming-conventions.md
3. ../../../shared/agents/codebase-researcher.md
```

Record the raw subagent response.

**Outcomes:**
- **C-1: Resolves.** Subagent reads all three files relative to `c-test.md`'s location.
- **C-fail: Does not resolve** (subagent CWD differs from prompt-file location, paths fail).

#### Why the parent-prompt indirection matters

Production `auto-pilot` loads its prompt template (`subagent-prompts.md`) itself, then forwards the body to a subagent. The path of the original prompt file is lost before the subagent starts resolving relative paths. Testing direct-file-read (the `C-control` form, retained for reference but not used in the matrix) would mis-predict whether the production flow works.

## Flake protocol

Each experiment is run **three times** with the prompts above verbatim. Record raw subagent outputs in the experiment log alongside the ADR.

- **3-of-3 consistent** → outcome is decisive (e.g., `A-1`, `B-fail`).
- **2-of-3 inconsistent** → run three more times. Document raw outputs of all six.
- **3-of-6 split or worse** → treat as `fail` for that experiment, note as "non-deterministic in this harness." The build picks the failure-row strategy.

Avoids "is it flaky or broken" debate at PR-3 implementation time. Conservatism (prefer `fail` on ambiguity) is correct here because building toward a flaky strategy is worse than committing to the conservative one.

## Recording the results

After running, write the raw outputs and chosen §6 decision-matrix row into `docs/decisions/cross-skill-invocation.md`. The ADR is the durable artifact; this file is the procedure for re-running.

The ADR records the **commit SHA of the source-tree state used during the experiments** — this is the SHA of PR 2 when it merges. Future maintainers re-running the experiments would `git checkout <SHA>`, regenerate `dist/test-plugin/` via `scripts/build-test-plugin.sh`, and re-run.

## Re-validation

If Claude Code (or another target harness) changes behavior in a way that affects A, B, or C:

1. Re-run all three experiments per this procedure.
2. Append a dated entry to the ADR with new raw outputs.
3. If the outcome row changes, follow up with a build-script change to match. The `tests/test-autopilot-portability.sh` test (added in #53) verifies rendering matches the latest ADR row.
