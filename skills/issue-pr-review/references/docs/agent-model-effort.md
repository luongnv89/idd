<!-- Generated from /docs/agent-model-effort.md. Do not edit. Edit source and run ./scripts/build.sh. -->
# Agent Model / Effort Selection

How an **orchestrator** skill picks the model and thinking effort it spawns each
shared agent with. The orchestrator is the decision point: it knows the issue's
complexity, so it sizes the agent to the task instead of every agent running at a
fixed tier. Mirrors the 04-subagents *Configuration* pattern (`model` / `effort`
tuned per delegation) — see the ADR at `docs/decisions/shared-agent-design.md`
(https://github.com/luongnv89/idd/blob/main/docs/decisions/shared-agent-design.md).

This is **advisory guidance**, not an enforced control: IDD spawns
general-purpose agents, so the orchestrator selects the tier when it decides how
to run a step. It never blocks a step.

## Complexity → model / effort

Reuse the single `XS … XL` scale already defined for issue effort and model
suggestion by the `issue-creator` skill (its `model-suggestion` reference and the
`complexity_mapping` table in its bundled `model-data` snapshot). Do **not**
invent a parallel scale.

| Tier | Label | Thinking / effort | Anthropic model (advisory) |
|------|-------|-------------------|----------------------------|
| XS | trivial | low | Opus 4.7 Low |
| S | simple | low–medium | Opus 4.8 Low |
| M | moderate | medium | Opus 4.8 Medium |
| L | complex | high (extra-high) | Opus 4.7 Extra High |
| XL | super complex | max | Fable 5 Max |

The analysis pipeline labels complexity `trivial / low / medium / high / complex`;
map those onto `XS / S / M / L / XL` rather than carrying two scales side by side.

## Where complexity comes from

1. **codebase-researcher** returns a `complexity` field (`trivial … complex`).
2. **synthesizer** returns `overall_complexity` (`XS … XL`) on the selected option.
3. The orchestrator uses the **most recent** of these as the tier for the next
   step — e.g. resolve Step 3 (implement) is sized from the selected option's
   `complexity`, not a fixed default.

## Per-agent default tier (floor)

When no upstream complexity signal exists yet (e.g. the first step), start at the
agent's default tier and let the orchestrator scale **up** as signals arrive.

| Agent | Default | Scales up when |
|-------|---------|----------------|
| codebase-researcher | M | issue spans many files / external research needed (→ L/XL) |
| synthesizer | M | researcher reported `high`/`complex` (→ L) |
| implementer | L | selected option is `L`/`XL`, or many files/tests (→ XL) |
| code-reviewer | M | large diff or security-sensitive change (→ L) |
| ui-reviewer | S | multi-viewport / accessibility-heavy change (→ M) |
| fixer | M | findings span multiple files or root-cause is unclear (→ L) |
| duplicate-detector | S | 50+ open issues (→ M) |
| issue-relationship-scanner | S | large batch / deep history scan (→ M) |

## Orchestrator responsibilities

For each spawned step the orchestrator should:

1. **Select** the tier from the rules above (most-recent complexity signal, else
   the agent's default floor).
2. **Record** the chosen tier in its step log / audit trail (see the monitoring
   notes in the skill's pipeline reference).
3. **Spawn** general-purpose, naming the persona in `description`, and pass the
   tier intent in the prompt when it materially changes how the agent works
   (e.g. "research external approaches" for L/XL).

Selection is bounded by the same cost-awareness as model suggestion: prefer the
lowest tier that can do the step correctly.
