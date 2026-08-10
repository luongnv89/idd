# `.gitissue/runs.jsonl` — Run Log Schema

The run log is the cross-run telemetry file written by `/issue-resolver` and
`/auto-pilot`. This document is the canonical schema for a `runs.jsonl` line:
the field set, the append rules, and the single-writer convention. It is a
standalone runtime doc so a skill that only needs to append one telemetry line
never has to read the full configuration schema
([config-schema.md](https://github.com/luongnv89/idd/blob/main/docs/config-schema.md)),
which describes `.gitissue.yml` and the rest of the `.gitissue/` state directory.

## Schema

`runs.jsonl` is the first home for the `monitoring` value. It is an **append-only,
schema-light, newline-delimited JSON** file: each line is one self-contained JSON
object describing a single run. It is grep-friendly, diffable, and deletable like
the rest of `.gitissue/` — it is read back only by `/idd-doctor`'s run-log
summary, `scripts/idd-lint.py stats` (the no-agent evidence report), and
`gi-runlog.py --failure-streak` (`/auto-pilot`'s consecutive-failure count), so
truncation or deletion only resets the telemetry window.

That last reader is **best-effort by design**. The durable record of a
quarantine is the label `/auto-pilot` puts on the issue; the streak counted here
is only *progress toward* one. A truncated log therefore loses progress toward a
quarantine, never an existing one, and an unreadable log reports a streak of `0`
— nothing is ever quarantined on evidence nobody read.

Each line carries at minimum a **timestamp, issue number, mode, outcome**, and the
**PR number when one was created**. The full field set:

| Field | Type | Always present | Description |
|-------|------|----------------|-------------|
| `ts` | string (ISO 8601 UTC) | yes | When the run finished, e.g. `2026-06-26T14:31:07Z` |
| `issue` | integer | yes | Issue number the run processed |
| `mode` | string | yes | `interactive` or `auto` (resolver); the auto-pilot merge mode (`conservative` / `balanced` / `aggressive`) for auto-pilot rows |
| `skill` | string | yes | `issue-resolver` or `auto-pilot` — which skill wrote the line |
| `outcome` | string | yes | Terminal outcome. Resolver: `success`, `already_resolved`, `failed`. Auto-pilot: one of its six categorical outcomes (`merged`, `left_open`, `partial_followup`, `blocked_by_dependency`, `failed`, `skipped`). |
| `pr` | integer or null | yes | PR number when a PR was created, else `null` |
| `complexity` | string | no | Research complexity on the **3-value** run-log scale (`low` / `medium` / `high`) when known. Collapse the researcher's 5-value estimate before writing: `trivial` or `low` → `low`; `medium` → `medium`; `high` or `complex` → `high`. Never emit `trivial` or `complex` in runs.jsonl. |
| `profile` | string | no | The adaptive-effort pipeline profile the run selected: `light` (trivial fast path) or `full`. Omitted when `resolve.adaptive_effort` is `false` or the signal was unavailable. Lets `/idd-doctor` and audits see how often the fast path fired. See [agent-model-effort.md](https://github.com/luongnv89/idd/blob/main/docs/agent-model-effort.md) (Complexity → pipeline profile). |
| `qa_cycles` | integer | no | Number of QA review-fix cycles run (resolver) |
| `duration_s` | integer | no | Wall-clock duration of the run in seconds, when measurable |
| `skipped_reason` | string | no | Why the issue was skipped (auto-pilot skips, and any `skipped`/`already_resolved` outcome), e.g. `already_resolved`, `blocked_label`, `blocked_by_dependency`, `in_skip_list`, `assigned_to_other`, `quarantined` |

Example lines:

```jsonl
{"ts":"2026-06-26T14:31:07Z","issue":141,"mode":"auto","skill":"issue-resolver","complexity":"medium","profile":"full","qa_cycles":2,"outcome":"success","pr":150,"duration_s":372}
{"ts":"2026-06-26T15:02:41Z","issue":152,"mode":"auto","skill":"issue-resolver","complexity":"low","profile":"light","qa_cycles":1,"outcome":"success","pr":161,"duration_s":94}
{"ts":"2026-06-26T14:48:12Z","issue":118,"mode":"balanced","skill":"auto-pilot","outcome":"skipped","pr":null,"skipped_reason":"blocked_by_dependency"}
```

**Append rules:**
- Create `.gitissue/` with `mkdir -p` if it does not exist, then append exactly one
  line terminated by a single `\n`. Never rewrite or reorder existing lines.
- Writing the line is **best-effort and non-fatal** — if the append fails, the run
  still reports its result normally. A run is never failed because telemetry could
  not be written.
- There is **no schema migration**: new optional fields may be added over time;
  readers must tolerate missing keys and unknown keys. Absent optional fields are
  simply omitted (not written as `null`, except `pr` which is always present).

**The `gi-runlog` helper.** A skill that bundles `references/scripts/gi-runlog.py`
should pipe the record to it on stdin rather than hand-rolling the append: the script
enforces every rule above — required-field and `outcome` validation, the 5→3
`complexity` collapse, dropping optional keys whose value is `null`, filling an absent
`ts` from the UTC clock, and emitting the keys in the example lines' order above —
that order is the canonical one, not the field table's. `--append` (the
default) creates `.gitissue/` and appends exactly one `\n`-terminated line to `--path`
(default `.gitissue/runs.jsonl`); `--echo` runs the identical validation and
normalization, prints the line, and **writes nothing** — the machine form of the
`--no-run-log` contract below. Exit `0` wrote or printed the line; `2` is a usage
error; `3` means the record was invalid and nothing was written; `4` means the record
was valid but the append itself failed. Only `3` signals a caller bug — `4` stays
best-effort and non-fatal per the rules above, and a caller that cannot run the script
at all falls back to the `mkdir -p` + append described here.

The same helper serves the one read. `--failure-streak N [--threshold F] [--log PATH]`
takes no stdin, writes nothing, and prints
`{"mode":"failure_streak","issue":N,"streak":N,"threshold":F,"quarantine":bool}` — the
consecutive most-recent `failed` records for that issue, stopping at its first record
with any other outcome (`--threshold 0` disables quarantine). Exit `0` read the log;
exit `4` means it was missing or unreadable and **the line is printed anyway** with
`streak: 0`, so a caller that ignores the exit code still cannot quarantine on missing
evidence. Malformed lines are skipped, not fatal — the tolerance the
no-schema-migration rule asks of every reader. Without the script, count by hand:
bottom-up, skipping other issues, stopping at this one's first non-`failed` record.

**Single writer under `/auto-pilot`:** when `/auto-pilot` resolves an issue it
runs `/issue-resolver` as a subagent, so without coordination *both* skills would
append — two lines per processed issue, which double-counts that issue in
`/idd-doctor`'s resolve-rate and median-QA metrics (they aggregate over every
line). To keep **exactly one line per processed issue**, `/auto-pilot` passes the
resolver the `--no-run-log` flag: the suppressed resolver does **not** append and
instead **returns** its telemetry — its run `status` (the `outcome`) plus
`qa_cycles`, `complexity`, and `duration_s` — to the orchestrator, which folds it into the single enriched
`auto-pilot` line. The flag is **orthogonal to `--auto`/`IDD_AUTO_MODE`** — a
standalone `/issue-resolver <N> --auto` is *not* suppressed and remains the single
writer for that run. So the rule is: the outermost skill is the single writer; an
inner resolver invoked by `/auto-pilot` stays silent.

**Batch fan-out (one line per attempted issue).** The same single-writer rule
covers the *Batch Resolver* path (`/auto-pilot --issues`, where the analyzer bundles
several issues into one PR): the Batch Resolver also runs with `--no-run-log` and
returns its telemetry, and `/auto-pilot` writes the lines. Because "one line per
**processed issue**" — not per PR — is the contract, `/auto-pilot` **fans the one
batch result out into one line per attempted issue** (the set sent into the Batch
Resolver, *not* the success-only `issues_resolved`, or a failed batch would drop
fully-attempted issues). The fan-out is *across the run*, not all-at-batch-time:
at batch time `/auto-pilot` writes a line only for the issues **in**
`issues_resolved` (their `outcome` is the success outcome — `merged`/`left_open`),
and re-queues the rest so each unresolved attempted issue gets its one line at its
individual retry (which sets *its* `outcome`). No `failed` line is written at batch
time. The shared `pr` and `complexity` go on every line, while the batch-scalar `qa_cycles`
and `duration_s` are attributed to **one line only** (the primary issue's) so a
batch is not weighted N-fold in `/idd-doctor`'s medians. On a partial/failed batch,
`/auto-pilot` writes a line only for the resolved issues now and **re-queues every
unresolved issue — including the batch's primary (spawn-position) issue — for
individual resolution**, where that resolve writes its single line; re-queuing the
primary is mandatory (its `optimized_order` slot is already consumed, so without an
explicit re-append it would drop to zero lines — the inverse under-count). No
`failed` batch line is written for an unresolved issue, so a
batch-failed-then-individually-resolved issue is never double-counted. One further
carve-out: when the loop later reaches a batch-resolved member it emits an
`already resolved in batch` skip that is **display only and writes no run-log line**
(it was already logged at batch time) — the single exception to logging every
processed issue including skips. Net: exactly one line per attempted issue across
the run, with no re-resolve double-count and no inverse under-count. The authored
contract lives in
`src/skills/auto-pilot/references/explicit-list-mode.md` (*Run-log fan-out for the
batch*).
