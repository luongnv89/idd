# Run Stats Footer

The run-cost footer every IDD skill prints to close a run. This file is
**byte-identical in every skill** — the shape is the contract, and a skill that
diverges from it makes the same number read differently in two places.
`tests/test-run-stats-373.sh` enforces that. Edit the copy in one skill only by
editing every copy.

## The footer

```
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Run stats   elapsed 4m 12s · tokens n/a · agents 4
```

Two lines, printed last — after the skill's own final report, closing summary,
or error block, whichever ended the run. Two-space indent, ` · ` between
fields, `┄` separator, per the skill's terminal-style contract.

## Every terminal outcome

The footer prints wherever the run stops, not only where it succeeds: a
completed pipeline, an early exit, a guard that refused to continue, a failed
step, an aborted or paused loop, a rate-limit or runtime-budget stop, and an
invalid-config stop. Where a skill appends a run-log line it also prints this
footer, and it prints it on the paths that never reach a run-log write too. A
run that produced no output at all is the only run without a footer.

## The three fields

Fixed, in this order. No skill adds, drops, or renames one.

| Field | Value | Source |
|-------|-------|--------|
| `elapsed` | wall-clock duration, `{H}h {M}m {S}s` with zero-valued leading units dropped (`4m 12s`, `48s`, `1h 03m 20s`) | `now - run_started_epoch` |
| `tokens` | tokens the run consumed, a plain integer with thousands separators (`128,400`) | the host runtime, when it reports a usage figure to the skill |
| `agents` | subagents the run spawned, an integer | the orchestrator's own count of spawns |

`run_started_epoch` is captured once, at skill start, by appending `; date +%s`
to the skill's first shell invocation — the config load. It costs no extra
round trip. A skill that already records a start time reuses that value and
captures nothing new.

## Unavailable values

A field whose value cannot be determined prints the literal `n/a` — never a
guess, never an omitted field, never `0`.

- **`tokens n/a` is the expected reading on most hosts.** A skill is prose
  executed by an agent; it has no token counter of its own. Print a number only
  when the runtime actually reports one. Never estimate from output length,
  file sizes, or step counts.
- `elapsed n/a` when no start time was captured — a stop *before* the config
  load has no anchor to measure from.
- `agents n/a` when the count was lost, for example across a resume that did
  not carry the tally.

`0` is a **determined** value and is correct where it is true: a skill that
spawns no subagents prints `agents 0`, not `agents n/a`. The distinction is
between *nothing happened* and *we do not know*.

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
