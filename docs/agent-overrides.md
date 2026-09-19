# Agent Overrides — per-role model and effort at spawn time

The single home of the rule an orchestrator applies when it spawns a subagent.
Read the resolved `agents.model.<role>` and `agents.effort.<role>` from the
config loaded at skill start
([schema](https://github.com/luongnv89/idd/blob/main/docs/config-schema.md));
without `gi-config` every role is `null`.

## Per-spawn rule

Per spawn, per knob, for the role being spawned:

| Resolved value | Spawn tool | Do |
|----------------|-----------|----|
| `null` | any | Pass nothing — byte-for-byte the call the skill documents: no `model`, no effort line |
| set | has a matching parameter | Pass the value **verbatim** |
| set (`model`) | no such parameter | Skip; print `○ {role}: model override not supported here — inheriting` |
| set (`effort`) | no such parameter | Append `Thinking effort: {value}` to the prompt; print `○ {role}: effort override not supported here — passed as a prompt hint` once |

Values are opaque: never translate or guess one. "Never set `subagent_type`"
is unchanged. A re-messaged agent keeps its spawn configuration.

## Fallback ladder

1. **Rejected spawn** (unknown model, invalid parameter): print
   `⚠ {role}: spawn with model '{x}' failed — retrying with main agent config`,
   respawn **once** with no overrides, and mark the role **degraded** — no
   overrides for the rest of the run.
2. **No Agent tool:** the skill's inline fallback runs; print
   `○ agents: no subagent tool — overrides ignored` once.

**Spawn failure only.** The ladder triggers on a spawn the tool rejects —
never on output quality, a blocking verdict or a failed test.

## What an override never touches

- **Safety gates.** Secret scans, repo sync, hard-blocks and tool posture run
  identically under any model.
- **The pipeline profile.** `light` / `full` selection is unchanged.
- **The advisory tier.** A configured model **wins** over the advisory `XS … XL`
  tier for that role; the tier stays as the prompt hint.

## Tracker line

A step spawned with a model override appends `· model: {x}` to its tracker
line, or `· model: {x} → inherited` after a fallback.
