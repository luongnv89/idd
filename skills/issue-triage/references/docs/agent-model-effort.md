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

| Tier | Effort band (issue Metadata) | Thinking / effort | Anthropic model (advisory) |
|------|-------------------------------|-------------------|----------------------------|
| XS | XS | low | Opus 4.7 Low |
| S | S | low–medium | Opus 4.8 Low |
| M | M | medium | Opus 4.8 Medium |
| L | L | high (extra-high) | Opus 4.7 Extra High |
| XL | XL | max | Fable 5 Max |

The research pipeline's 5-value complexity (`trivial / low / medium / high / complex`)
maps to effort bands `XS / S / M / L / XL` (see `complexity_mapping` in issue-creator
model-data). For **runs.jsonl** only, collapse to `low / medium / high` per
`references/docs/config-schema.md` — do not reuse the word `complex` as a run-log value.

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
3. **Spawn** general-purpose, naming the role in `description`, and pass the
   tier intent in the prompt when it materially changes how the agent works
   (e.g. "research external approaches" for L/XL).

Selection is bounded by the same cost-awareness as model suggestion: prefer the
lowest tier that can do the step correctly.

## Complexity → pipeline profile

Model/effort selection above is **advisory** — it tunes *how hard* each agent
thinks but never changes *which* steps run. The **pipeline profile** is a
distinct, second mechanism layered on the **same `XS … XL` scale**: it scales
*how much pipeline runs* — which optional steps fire, how many QA/review cycles
are allowed — so a trivial one-character edit does not pay the full
orchestration cost of a multi-subsystem change. Unlike model/effort, the profile
**does** change control flow (it can collapse a step or cap a loop), so it is a
**gated** control, not advisory. The two are independent: model/effort sizes the
agents a step spawns; the profile decides whether the lighter-weight step runs at
all. They share the scale and nothing else — do **not** invent a second
classifier for the profile.

### The two profiles

| Profile | Effort band | Intent |
|---------|-------------|--------|
| **light** | XS, S | Trivial/small work — collapse optional phases, cap the review-fix loop to one cycle. |
| **full**  | M, L, XL | Everything today runs unchanged — the current pipeline in full. |

The profile is a **coarse** switch (two states), deliberately not one profile per
band: the goal is a fast path for the long tail of trivial work, not five
gradations. Model/effort selection already provides the fine-grained,
per-agent scaling within either profile.

### Selecting the profile (pre-work signal)

The profile is chosen from a **pre-work** signal — before the first expensive
subagent spawn — so the saving is real. If the profile were derived from an
agent's *output* (e.g. the researcher's `complexity`), the dominant cost would
already be paid before the decision, and the fast path would save almost nothing.
The pre-work signal is the issue's **`Effort` band** in its `## Metadata` section
(the `XS … XL` value written by `/issue-creator`, the same scale this whole
document uses).

Resolve the profile from that band, **erring toward `full` whenever the signal
is weak**:

| Condition on the pre-work signal | Profile |
|----------------------------------|---------|
| `Effort` is `M`, `L`, or `XL` | **full** |
| `Effort` is `XS` or `S` **and** asserted (not low-confidence) | **light** |
| `Effort` is `XS`/`S` but marked `(needs review)` / low-confidence | **full** (ambiguous → fuller) |
| `Effort` is absent / unparseable | **full** (safe default) |

The low-confidence and absent rows are the safety contract: an uncertain estimate
must never under-serve a task that turns out to be hard. A skill **may** refine
the profile *upward* once a stronger signal arrives (e.g. the researcher reports
`high`/`complex` on what the band called `S`) — never downward. Downgrading on a
mid-pipeline signal would defeat the pre-work guarantee and risk truncating work
already deep in the full path.

### What each consuming skill does with the profile

This document defines the *scale → profile* mapping and the pre-work-signal rule;
each skill owns exactly *which* of its steps the `light` profile collapses (its
pipeline reference spells out the per-step mechanics):

- **`/issue-resolver`** — `light` keeps a **lighter** Research step (the
  already-resolved safety check still runs), skips the 3-option synthesis in Plan
  (a direct minimal plan is used), skips the interactive propose-relevant-skills
  sub-step, and caps QA at **one** cycle. Implement and Deliver are unchanged, and
  the durable PR artifacts (Decision Record + Acceptance Criteria Verification
  table) are **always** emitted — the profile never removes durable memory.
- **`/issue-pr-review`** — has no researcher, so it derives its own pre-work
  signal (diff size / files-changed / labels / linked-issue `Effort`, taking the
  **fuller** of any that disagree) and scales review **depth** — the `light`
  profile caps the review-fix loop to one cycle and skips optional passes, while
  the acceptance-criteria and traceability hard-blocks still run at full strength.

### Surfacing the profile (transparency)

The chosen profile is **surfaced to the user** wherever the skill already reports
progress, so the effort decision is transparent and reviewable — never a hidden
downgrade:

- On the pipeline **tracker line** for the step where it is decided (e.g. the
  resolver's `[0/5] Preflight` line names `effort: light` or `effort: full`).
- In the **run log** (`.gitissue/runs.jsonl`) as the optional `profile` field, so
  `/idd-doctor` and audits can see how often the fast path fired (see
  `references/docs/config-schema.md`).

### Opting out

Each consuming skill exposes an explicit off-switch so a maintainer can force the
full pipeline on every issue regardless of band: `resolve.adaptive_effort`
(default `true`) for `/issue-resolver` and `review.adaptive_depth` (default
`true`) for `/issue-pr-review`. When the switch is `false`, the skill behaves
exactly as it did before this mechanism existed — the profile is pinned to
`full`. Defaults are **on** so zero-config users get the fast path for trivial
work automatically; the switch exists for maintainers who prefer uniform
full-treatment (see `references/docs/config-schema.md`).
