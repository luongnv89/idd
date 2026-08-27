# ADR — The Run-Stats Footer Field Set

**Status:** Accepted (2026-08-27).
**Issue:** [#414](https://github.com/luongnv89/idd/issues/414).
**Extends:** [run-stats-token-reporting.md](./run-stats-token-reporting.md) —
the `tokens` conditionality this record leaves intact.

## Context

`skill-auto-improver` v2.1.0 closes its runs with a six-field footer —
`elapsed`, `tokens`, `cost`, `agents`, `skills`, `tool calls` — rendered over
three lines, with `tokens` and `cost` conditional and the remaining four
printing `n/a` where the run could not determine them. Every IDD skill closes
with three fields on two lines: `elapsed`, `tokens` where the host reported
one, and `agents`. The two footers have diverged, and the question this record
answers is whether IDD should close the gap by widening its own.

The gap is not a per-skill matter. The footer contract is carried
byte-identically in eight skill sources — the seven distributed skills plus the
repo-internal `idd-doctor` — and `tests/test-run-stats-373.sh` pins that
identity with a checksum, so a field added anywhere is a field added
everywhere. The field set is therefore one repo-wide decision, not eight local
ones, and settling it once is the only way to settle it at all. Every per-skill
retrofit issue under epic #413 defers its run-stats criterion to this record
rather than re-deciding the shape in seven places.

## Decision

**Keep `elapsed`, `tokens` (conditional), and `agents`. Add nothing.**

**`elapsed` is kept, unconditional.** It costs two clock reads, one at the
start of the run and one at the end. Every host can supply them, and wall-clock
time is the one figure on the line that is always a real cost, whatever the
run did.

**`tokens` is kept, conditional** — printed where the host reports a usage
figure to the skill, omitted entirely where it does not, exactly as
[run-stats-token-reporting.md](./run-stats-token-reporting.md) left it. That
decision is not re-litigated here; this record only declines to build anything
new on top of it.

**`agents` is kept, unconditional,** with `0` a determined value rather than a
missing one. Subagent spawns are few, discrete, and already scripted by the
orchestrator, so the orchestrator's own count needs no instrumentation to
produce — it is reading a number it was already keeping.

**`cost` is dropped.** Assessed against the re-validation clause of the token
record, which reads: "Revisit if a usage figure becomes available to a skill
through a host-neutral interface — one that costs no subprocess, covers
subagent usage, and is complete at the moment the footer prints. Meeting fewer
than all three does not reopen this." A cost figure fails that clause a
fortiori. It needs everything `tokens` needs — a host-neutral, subprocess-free,
subagent-complete usage figure available when the footer prints — and then, on
top, a price table and the identity of every model the run used. The contract's
own rule for what counts as a reported figure, "Not derived, not looked up, not
computed", forbids that lookup independently of the clause. A field conditional
on a figure no current host reports would print on no run of any skill, which
is precisely the defect issue #410 removed when it stopped `tokens` printing a
permanent `n/a`.

**`skills` is dropped, on the #165 activity-versus-cost line.** A count of
skills invoked measures what the run *did*, not what it cost — the same
distinction on which the activity metrics #165 removed were removed, and the
one the *The #165 narrowing stands* paragraph below restates for all three
rejected fields. That is the primary ground and it holds in every skill,
including the two where the number would vary.

Two secondary grounds support it. First, all-eight-or-none: only
`/issue-resolver`, through its borrowed-skills path, and `/auto-pilot` can
invoke another skill at run time, and the contract's rule that omission is not
a per-skill choice makes the field all-eight-or-none, so it cannot be carried
only where it is interesting. Second, the line and word budgets in
*Consequences* below, which price every added field across eight call sites.

To keep the record honest about what does **not** ground this: "the field would
be a constant in six skills" is not a disqualifying reason, and an earlier
draft of this record was wrong to lean on it. `agents` is likewise a constant
`0` in `/init-gitissue`, which spawns no subagents, and `agents` is kept — the
contract's own *Unavailable values* section says `0` is a **determined** value.
A determined constant resolves; what #410 removed was a field that can *never*
have a value, a permanent `n/a`. That is true of `cost` and it is not true of
`skills`. The #410 ground is therefore not available here, which is why the
#165 ground carries the decision.

**`tool calls` is dropped.** Producing the number means a running tally
maintained across every step of the run, and the contract's *Overhead* section
forbids that mechanism by name: "Never add a timing call per step, a running
tally file, a subprocess, or a summarization pass." The asymmetry with `agents`
is real and is the point. Subagent spawns happen at a handful of discrete,
scripted points the orchestrator already writes; tool calls have no enumerable
set, so counting them means instrumenting every step of the run to measure the
run — the overhead the contract exists to prevent.

**The #165 narrowing stands.** Issue #165 removed from this footer the metrics
the run's own report had already printed — files read, files changed, test
counts, issues triaged — leaving it to answer one question: what did this run
cost? That narrowing has no decision record of its own; it survives only as the
contract's *What the footer must not carry* section. This record **upholds and
reaffirms** it rather than reversing it. Each of the three rejected fields
counts run *activity* rather than run *cost* — how many skills, how many tool
calls, and, in `cost`'s case, a figure resting on one no host supplies — so
adopting any of them would be a reversal of #165. A reversal must be recorded
as one, argued on its own terms, not arrived at sideways by adding a field. The
divergence from `skill-auto-improver` is now intentional and recorded, so the
#413 children that defer here have their answer.

## Consequences

- The contract gains a section and no field. The printed block is unchanged, so
  AC6's byte-identity guarantee across the eight copies and every #410
  assertion in `tests/test-run-stats-373.sh` are untouched — the copies still
  agree, and the footer still renders exactly as it did.
- **A wider footer is not a free prose change, and the budgets say so.**
  `src/skills/issue-resolver/SKILL.source.md` and
  `src/skills/issue-pr-review/SKILL.source.md` each sit at exactly 500 lines
  against `CAP=500` in `tests/test-skill-line-cap-247.sh` — zero headroom — and
  six of the seven built skills already exceed 3000 words. Every added
  field multiplies call-site prose across eight skills and pushes on both the
  built and the source line caps at once, so a fourth field would have to be
  paid for by cutting other instruction text first. The reasoning above can
  live in the contract at no such cost because `references/run-stats.md` is
  outside the bundled-doc byte budget:
  `tests/test-bundled-doc-slimming-249.sh` sums only
  `skills/*/references/docs/*.md`. Prose about a field is cheap where the field
  itself is not.
- A future widening reopens *this* record. It is not an edit to the contract's
  field table, and a pull request that adds a row without amending this record
  is doing the second thing while claiming the first.
- This is a **current** decision record, written with the change it describes.
  `docs/decisions/no-backfill-merged-decision-records.md` forbids adding
  records retroactively to already-merged commits; it does not restrict
  recording a decision as it is made.

## Re-validation

- **`cost`** — revisit only if a host reports, host-neutrally and at no
  subprocess cost, both a complete token figure covering subagent usage and the
  model identity needed to price it, with both available at the moment the
  footer prints.
- **`tool calls`** — revisit only if a host reports a tally the skill does not
  have to maintain itself.
- **`skills`** — revisit only if a count of skills invoked stops being a
  run-activity metric: that is, only if #165's activity-versus-cost line is
  itself reopened and the reopening recorded as such. How many skills can
  invoke another one does not bear on it; `agents` was never held to that bar.

Partial satisfaction reopens none of them. A field that resolves on some hosts
is the defect this record and #410 both refuse.
