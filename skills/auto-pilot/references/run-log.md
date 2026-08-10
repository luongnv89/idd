# Run-log monitoring contract

`/auto-pilot` appends to `.gitissue/runs.jsonl` — the same append-only run log
written by `/issue-resolver`. The schema and field list live in
`references/docs/run-log-schema.md`; follow it rather
than re-deriving fields. This file documents the two contracts that keep the log
accurate when auto-pilot orchestrates the resolver: the **single-writer rule**
and the **batch fan-out**.

## Run log vs. run state

They are different files with opposite lifetimes, and neither substitutes for
the other:

| | `.gitissue/runs.jsonl` (run log) | `.gitissue/run-state.json` (run state) |
|---|---|---|
| Shape | append-only, one JSON line per processed issue | one mutable JSON object, rewritten at each checkpoint |
| Scope | cross-run telemetry, grows forever | this run only; the next run overwrites it |
| Audience | `/idd-doctor` metrics, humans reading history | this loop, resuming itself after an interruption |
| Read by the loop? | yes, in one place only: `gi-runlog.py --failure-streak` counts an issue's consecutive `failed` records for *Phase 2.3*'s quarantine. Best-effort **by design** — the log is gitignored and deletable, so the streak is *progress toward* a quarantine and the durable state is the label on the issue. A missing or unreadable log reports `streak: 0` and quarantines nothing | yes, by *Step 1.0*'s resume gate |
| Lifetime | committed history of what ran | machine-local and gitignored, alongside `run.lock` and `last-run-report.md` |

A checkpoint is **not** a run-log line: it records where the loop is, not what an
issue's run concluded. Reading the run state to reconstruct telemetry would
double-count (it holds `processed[]` for every issue this run touched), and
reading the run log to resume would be wrong (it has no phase, no branch, and no
PR-in-flight). Everything below is about the run log and is unchanged by resume
support.

## Single-writer rule (per processed issue)

**Auto-pilot is the single writer per processed issue.** The resolver subagent
is invoked with `--no-run-log` (see *Resolver Subagent* in
`references/subagent-prompts.md`), so it **does not** append its own line — only
auto-pilot writes here. Writing in both places would double-write one line per
issue and skew `/idd-doctor`'s resolve-rate and median-QA metrics. The resolver
**returns** its telemetry (`qa_cycles`, `complexity`, `profile`, `duration_s`) in
its result; fold those into the **single line** auto-pilot writes (enriched with
that telemetry) so the per-issue QA signal survives even though the resolver
stayed silent. The resolver's run `status` informs auto-pilot's decision but is **not**
copied into the row's `outcome` — that field stays auto-pilot's own six
categorical label (set from the merge result).

## Batch fan-out (Batch Resolver path)

**Batch iterations** (the *Batch Resolver* path resolves several issues in one
PR) follow the **same single-writer rule** — the Batch Resolver also runs with
`--no-run-log` and returns its telemetry — but auto-pilot must **fan its one
result out into one line per attempted issue** (keyed on the attempted set, not
`issues_resolved`), with the shared `pr`/`complexity` on every line and the
scalar `qa_cycles`/`duration_s` attributed to the primary issue's line only. The
full fan-out contract (per-attempted-issue lines, per-issue `outcome` from
`issues_resolved`, and the re-resolve double-count guard for partial/failed
batches) lives in `references/explicit-list-mode.md` (*Run-log fan-out for the
batch*), since batching only occurs in explicit-list mode.

## Fields to populate

**`blocked_by_dependency` is an `outcome`, not a `skipped_reason`, when the gate
fires.** An issue whose PR was created and then refused by the Phase 5.1b
dependency gate writes **exactly one** line, at that iteration, with
`outcome: blocked_by_dependency` (no `skipped_reason`) — and is then added to the
session skip list so the continuing loop cannot re-pick it and log a second line.
The `skipped_reason: blocked_by_dependency` value is reserved for the different
case where an issue is skipped **before** resolution starts (Phase 1's triage
graph marks it blocked, so no PR exists). One line per issue, never both.

Populate from the iteration's known values plus the resolver's returned
telemetry: `ts` (current UTC, ISO 8601), `issue` (the number), `mode` (the
auto-pilot merge mode — `conservative` / `balanced` / `aggressive`), `skill`
(`auto-pilot`), `outcome` (one of the six categorical labels), `pr` (the PR
number when one was created, else `null`), and — from the resolver's report-back
— `qa_cycles`, `complexity`, `profile`, and `duration_s` when present (`profile`
is the adaptive-effort profile the resolve chose, `light` or `full`; omit it when
the resolver returned none). **When the outcome is `skipped`, always include
`skipped_reason`** (e.g. `already_resolved`,
`blocked_label`, `blocked_by_dependency`, `in_skip_list`, `assigned_to_other`,
`quarantined`); a skip never ran the resolver, so it carries no resolver
telemetry.

**`quarantined` is a `skipped_reason`, never an `outcome`, and never doubles a
line.** The iteration that *applies* the quarantine label is a `failed`
iteration and writes its one `failed` line as usual — the quarantine is decided
from that line, so no second line is written for it. `skipped_reason:
quarantined` belongs to the **later** run that skips the issue because it carries
`autopilot.quarantine_label`, which is an ordinary skip before resolution
started. One line per processed issue, unchanged.
