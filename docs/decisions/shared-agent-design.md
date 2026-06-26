# ADR — Shared Agent Design

**Status:** Accepted (2026-06-26).
**Issue:** [#160](https://github.com/luongnv89/idd/issues/160).
**Canonical reference:** [Claude How To — 04-subagents](https://github.com/luongnv89/claude-howto/tree/main/04-subagents).

## Context

The shared agents under `src/shared/agents/` power issue-resolver, issue-triage,
issue-creator, issue-pr-review, issue-analysis, and auto-pilot. They had grown
long and repetitive: each repeated its spawn note, autonomous-operation rule,
prompt-injection boundary, `gh --json` rule, and (for reviewers) the confidence
scale; the implementer embedded a ~50-line copy of the pre-commit security scan
that already lives in `docs/pre-commit-security.md`. Thinking depth was not tied
to task complexity, and handoffs lacked a uniform contract.

[04-subagents](https://github.com/luongnv89/claude-howto/tree/main/04-subagents)
is the canonical design reference for Claude Code subagents. This ADR records
which of its patterns IDD adopts and how.

## Patterns adopted

| 04-subagents pattern | IDD adoption |
|----------------------|--------------|
| **Focused single responsibility** | Unchanged — each agent already owns one job. |
| **Explicit `description` for delegation** | The persona + role label (e.g. *Ada Lovelace — Researcher*) is the visible identity, reused verbatim in every spawn `description`. |
| **Frontmatter-equivalent config** (`tools`, `model`, `effort`) | Documented as a compact header + [`docs/shared-agent-conventions.md`](../shared-agent-conventions.md) tool-posture table, **not** YAML. IDD spawns general-purpose agents (no `subagent_type`), so YAML `tools`/`model` would not take effect; the orchestrator enforces posture and tier through the prompt. |
| **Tool scoping — start restrictive** | Read-only posture (Read/Grep/Glob + read-only git/gh) for the six analysis/review agents; full-access (+ Edit/Write/commit) only for implementer and fixer. |
| **Model / effort tuned by the caller** | [`docs/agent-model-effort.md`](../agent-model-effort.md) — orchestrator selects tier per step from the most-recent complexity signal, reusing the existing `XS…XL` scale (no parallel scale). |
| **Structured output format** | Each agent keeps its exact JSON / named-markdown contract under `## Output`; a `## Contract` header summarizes inputs, returns, and stop conditions. |
| **Results-only handoff (clean context)** | Agents return only distilled results; the orchestrator records and surfaces them. Reinforced in the conventions doc's *Output discipline*. |

## Decisions

1. **Edit agent files in place; never rename.** `scripts/build.py` bundles by
   filename stem and keys `AGENT_DESCRIPTIONS` by stem. Renames would break the
   transitive-closure scan, the description lookup, and the emitted `name:`. All
   eight filenames are stable.
2. **Shared boilerplate lives in one runtime doc.**
   [`docs/shared-agent-conventions.md`](../shared-agent-conventions.md) holds the
   spawn note, tool posture, injection boundary, confidence scale, `gh --json`
   rule, autonomous-operation rule, and output discipline. Agents reference it
   via a bare `docs/shared-agent-conventions.md` token, so the build bundles it
   automatically.
3. **Personas are documentation, not behavior gates.** Seven agents already had
   personas; codebase-researcher's (Ada Lovelace) was strengthened into the
   header. Personas set voice and identity — they never change the I/O contract.
4. **The implementer references the security scan instead of embedding it.** The
   ~50-line inline bash block was replaced by a pointer to
   `docs/pre-commit-security.md` (its authoritative Primary Pattern), matching
   how the fixer already does it.
5. **`model`/`effort` stay advisory and orchestrator-owned.** Per
   [`docs/agent-model-effort.md`](../agent-model-effort.md); never blocks a step.

## Consequences

- Agent prompt bodies are materially shorter with the contracts preserved
  verbatim, so downstream JSON parsing is unaffected.
- A latent build bug was fixed: `AGENT_DESCRIPTIONS` was missing a `ui-reviewer`
  entry (it fell back to the generic description).
- New orchestrator guidance is bundled wherever a skill or agent references the
  two new runtime docs; the ADR itself is a project doc and is not bundled.
