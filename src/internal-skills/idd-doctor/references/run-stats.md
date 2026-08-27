# Run Stats Footer

The run-cost footer every IDD skill prints to close a run. This file is
**byte-identical in every skill** — the shape is the contract, and a skill that
diverges from it makes the same number read differently in two places.
`tests/test-run-stats-373.sh` enforces that. Edit the copy in one skill only by
editing every copy.

## The footer

```
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Run stats   elapsed 4m 12s · agents 4
```

Where the host reports a token count, that count takes its place between
`elapsed` and `agents`:

```
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Run stats   elapsed 4m 12s · tokens 128,400 · agents 4
```

Two lines, printed last — after the skill's own final report, closing summary,
or error block, whichever ended the run — in both renderings. Two-space
indent, ` · ` between fields, `┄` separator, per the skill's terminal-style
contract.

## Every terminal outcome

The footer prints wherever the run stops, not only where it succeeds: a
completed pipeline, an early exit, a guard that refused to continue, a failed
step, an aborted or paused loop, a rate-limit or runtime-budget stop, and an
invalid-config stop. Where a skill appends a run-log line it also prints this
footer, and it prints it on the paths that never reach a run-log write too. A
run that produced no output at all is the only run without a footer.

## The fields

Fixed, in this order. No skill adds, reorders, or renames one. `elapsed` and
`agents` are always present; `tokens` is the one conditional field — it prints
only where the host runtime reported a usage figure, and is left out entirely
otherwise. That is not a per-skill choice: on a host that reports nothing every
skill drops it, and on a host that reports every skill prints it.

| Field | Value | Source |
|-------|-------|--------|
| `elapsed` | wall-clock duration, `{H}h {M}m {S}s`. Drop zero-valued *leading* units, never interior or trailing ones; the leading unit is unpadded and every unit after it is zero-padded to two digits — `4m 12s`, `48s`, `1h 03m 20s`, `2h 00m 07s` | `now - run_started_epoch` |
| `tokens` | tokens the run consumed, a plain integer with thousands separators (`128,400`). **Conditional** — printed only where the host reported a figure; otherwise the field and its ` · ` separator are both left out | the host runtime, when it reports a usage figure to the skill |
| `agents` | subagents the run spawned, an integer | the orchestrator's own count of spawns |

`run_started_epoch` is captured once, at skill start, in the same shell as
the skill's first command — the config load — via
`cmd; ec=$?; date +%s >&2; exit "$ec"`. Read the epoch from stderr so stdout
and the command's exit stay intact. It costs no extra round trip. A skill
that already records a start time reuses that value and captures nothing
new.

## Unavailable values

`elapsed` and `agents` are unconditional. A field whose value cannot be
determined prints the literal `n/a` — never a guess, never an omitted field,
never `0`.

- `elapsed n/a` when no start time was captured — a stop *before* the config
  load has no anchor to measure from.
- `agents n/a` when the count was lost, for example across a resume that did
  not carry the tally.

`0` is a **determined** value and is correct where it is true: a skill that
spawns no subagents prints `agents 0`, not `agents n/a`. The distinction is
between *nothing happened* and *we do not know*.

## The conditional token count

`tokens` is the exception: where there is no figure the field is left out, not
marked. A skill is prose executed by an agent; it has no token counter of its
own, and on most hosts nothing reports one to it. A marker that can never
resolve is not information — it is a field announcing, every run, that it will
never have a value.

- **The host reported a figure → print it.** `tokens 128,400`, thousands
  separators, in the field's fixed position between `elapsed` and `agents`.
- **Nothing reported one → leave the field out.** Print
  `Run stats   elapsed 4m 12s · agents 4`: no dangling ` · `, no placeholder in
  its place.
- **What counts as reported.** A usage figure the host surfaced to you, in this
  run's own context, as part of running it. Not derived, not looked up, not
  computed. If you would have to go and find it, that is the leave-it-out case.
- **Never manufacture one.** Never estimate from output length, file sizes, or
  step counts, and never read the host's transcript, session files, or logs to
  reconstruct one — that is a subprocess and a summarization pass, which
  *Overhead* forbids.

## What the footer must not carry

Run cost only. Never repeat a metric the run already printed — files read,
files changed, test counts, QA cycles, issues triaged, iterations, the outcome
itself. Those belong to the skill's own report; restating them here is the
duplication issue #165 removed. The footer answers "what did this run cost?",
and nothing else.

## Overhead

Measuring must never become a measurable share of what it measures. The whole
footer costs one epoch read at start, one at the end, and two lines of output.
Never add a timing call per step, a running tally file, a subprocess, or a
summarization pass to produce it.

## Fields considered and not carried

Three fields that other tools' run footers carry are deliberately absent here.
Each was assessed once, repo-wide, in issue #414; their absence is a recorded
decision, not an oversight, and re-proposing one means reopening that record
rather than editing this list.

- **A cost figure.** A skill cannot compute one from what it has. It needs a
  token count — the one conditional field, absent on most hosts — plus a price
  table and the identity of every model the run used. Each of those is derived,
  looked up, or computed, which *The conditional token count* rules out by
  name. A field resting on all three would resolve on no run of any skill,
  which is exactly the defect issue #410 removed.
- **A count of skills invoked.** Only two of the eight skills can invoke
  another skill at run time; in the other six the field would be a constant.
  Dropping it in those six is not available either, because omission is not a
  per-skill choice, by the rule stated in *The fields*.
- **A count of tool calls.** Producing one means a running tally maintained
  across every step of the run, which *Overhead* forbids by name. `agents`
  survives the same test only because subagent spawns are few, discrete, and
  already scripted by the orchestrator, so counting them adds no per-step work.

Issue #165 narrowed this footer to run cost alone, and that narrowing stands.
Each of the three counts run activity rather than run cost, so adopting one
would be a reversal of #165, and a reversal has to be recorded as one, not
arrived at by adding a field.
