<!-- Generated from /docs/run-log-schema.md. Do not edit. Edit source and run ./scripts/build.sh. -->
# `.gitissue/runs.jsonl` — Run Log Schema

The run log is the cross-run telemetry file written by `/issue-resolver` and
`/auto-pilot`. This is the canonical schema for a `runs.jsonl` line: the
field set, the append rules, and the single-writer convention. It stands alone so
appending one line never requires the full configuration schema
([config-schema.md](https://github.com/luongnv89/idd/blob/main/docs/config-schema.md)).

## Schema

`runs.jsonl` is the first home for the `monitoring` value. It is an **append-only,
schema-light, newline-delimited JSON** file: each line is one self-contained JSON
object describing a single run. It is grep-friendly, diffable, and deletable like
the rest of `.gitissue/` — read back only by `/idd-doctor`'s run-log
summary, `scripts/idd-lint.py stats` (the no-agent evidence report), and
`gi-runlog.py --failure-streak`, so
truncation only resets the telemetry window. That reader is **best-effort by
design**: the durable record of a quarantine is the label `/auto-pilot` puts on
the issue, so truncation loses only *progress toward* one, never an existing
quarantine.

The full field set — the *Always present* column is the required minimum:

| Field | Type | Always present | Description |
|-------|------|----------------|-------------|
| `ts` | string (ISO 8601 UTC) | yes | When the run finished, e.g. `2026-06-26T14:31:07Z` |
| `event_id` | string | no | Stable idempotency key for a parallel lane. Created at scheduling; used only with `--append-once`; omitted on legacy writers. |
| `issue` | integer | yes | Issue number the run processed |
| `mode` | string | yes | `interactive`/`auto` (resolver); auto-pilot's merge mode (`conservative`/`balanced`/`aggressive`) for auto-pilot rows |
| `skill` | string | yes | `issue-resolver` or `auto-pilot` — which skill wrote the line |
| `outcome` | string | yes | Terminal outcome. Resolver: `success`, `already_resolved`, `failed`. Auto-pilot: one of six categorical outcomes (`merged`, `left_open`, `partial_followup`, `blocked_by_dependency`, `failed`, `skipped`). |
| `pr` | integer or null | yes | PR number when a PR was created, else `null` |
| `complexity` | string | no | Research complexity on the **3-value** run-log scale (`low`/`medium`/`high`) when known. Collapse the researcher's 5-value estimate first: `trivial`/`low` → `low`; `medium` → `medium`; `high`/`complex` → `high`. Never emit `trivial` or `complex` in runs.jsonl. |
| `profile` | string | no | Adaptive-effort pipeline profile selected: `light` (trivial fast path) or `full`. Omitted when `resolve.adaptive_effort` is `false` or the signal was unavailable. See [agent-model-effort.md](https://github.com/luongnv89/idd/blob/main/docs/agent-model-effort.md) (Complexity → pipeline profile). |
| `qa_cycles` | integer | no | Number of QA review-fix cycles run |
| `ceiling` | integer | no | Class QA-cycle policy ceiling: 1 for `light`, `resolve.qa_max_cycles` (default 5) for `full`+`high`, else 2. Omit unless recorded; a recorded value overrides the computed ceiling and must be a positive integer. |
| `breach_reason` | string | no | Why `qa_cycles` exceeded `ceiling`. Required when `qa_cycles` > `ceiling`; omit otherwise. `gi-runlog` rejects an over-ceiling row without it (exit 3); `idd-lint stats` exits 1 on such rows. |
| `duration_s` | integer | no | Wall-clock duration of the run in seconds, when measurable |
| `skipped_reason` | string | no | Why the issue was skipped (auto-pilot skips, and any `skipped`/`already_resolved` outcome), e.g. `already_resolved`, `blocked_label`, `blocked_by_dependency`, `in_skip_list`, `assigned_to_other`, `quarantined` |

Example lines:

```jsonl
{"ts":"2026-06-26T14:31:07Z","issue":141,"mode":"auto","skill":"issue-resolver","complexity":"medium","profile":"full","qa_cycles":2,"outcome":"success","pr":150,"duration_s":372}
{"ts":"2026-06-26T15:02:41Z","issue":152,"mode":"auto","skill":"issue-resolver","complexity":"low","profile":"light","qa_cycles":1,"outcome":"success","pr":161,"duration_s":94}
{"ts":"2026-06-26T14:48:12Z","issue":118,"mode":"balanced","skill":"auto-pilot","outcome":"skipped","pr":null,"skipped_reason":"blocked_by_dependency"}
```

**Append rules:**
- Create `.gitissue/` with `mkdir -p` if it does not exist, then append one
  line terminated by a single `\n`. Never rewrite or reorder existing lines.
- Legacy `--append` writes are **best-effort and non-fatal**. A parallel lane's
  `--append-once` failure instead leaves its durable state at `log_pending`; it
  never raw-appends and resume retries the same event.
- There is **no schema migration**: new optional fields may be added over time;
  readers must tolerate missing and unknown keys. Absent optional fields are
  simply omitted (not written as `null`, except `pr` which is always present).

**The `gi-runlog` helper.** A skill bundling `references/scripts/gi-runlog.py`
should pipe the record to it on stdin rather than hand-rolling the append: it
enforces every rule above — required-field and `outcome` validation, the 5→3
`complexity` collapse, dropping `null` optional keys, filling an absent `ts` from
UTC, and the canonical key order (the example lines', not the field
table's). `--append` (default) creates `.gitissue/` and appends one `\n`-terminated
line to `--path` (default `.gitissue/runs.jsonl`); `--echo` runs the identical
validation, prints the line, and **writes nothing** — the machine form of the
`--no-run-log` contract. `--append-once` requires `event_id`, locks its
cross-process read/check/append/fsync transaction, reuses an identical event, and
exits `3` on conflicting data. Exits: `0` wrote/found/printed; `2` usage; `3`
invalid/conflicting; `4` I/O failure. Legacy callers may use the documented raw
fallback on `4`; parallel lanes must leave `log_pending` and retry.

The same helper serves the one read. `--failure-streak N [--threshold F] [--log PATH]`
prints `{"mode":"failure_streak","issue":N,"streak":N,"threshold":F,"quarantine":bool}`:
the most recent consecutive `failed` records for that issue, stopping at its first
record with any other outcome (`--threshold 0` disables quarantine). Malformed lines
are skipped, per the no-schema-migration rule. Exit `4` (log missing or unreadable)
still prints the line with `streak: 0`, so nothing is quarantined on unread evidence.
Without the script: count bottom-up, skipping other issues, stopping at the first
non-`failed` record.

**Single writer under `/auto-pilot`:** `/auto-pilot` runs `/issue-resolver` as a
subagent, so without coordination *both* would append — two lines per processed
issue, double-counting it in `/idd-doctor`'s metrics. So `/auto-pilot` passes the
resolver `--no-run-log`: it does **not** append and instead **returns** its
telemetry — run `status` (the `outcome`), `qa_cycles`, `ceiling`, `breach_reason`,
`complexity`, `duration_s` — for the orchestrator to fold into one enriched line.
The flag is **orthogonal to `--auto`/`IDD_AUTO_MODE`**: a standalone
`/issue-resolver <N> --auto` is *not* suppressed. The rule: the outermost skill is
the single writer; an inner resolver stays silent.

**Batch fan-out (one line per attempted issue).** The *Batch Resolver* path
(`/auto-pilot --issues`) follows the same rule, so
`/auto-pilot` **fans the one batch result out into one line per attempted issue** —
per *processed issue*, never per PR — with the shared `pr` and
`complexity` on every line and the batch-scalar `qa_cycles` and `duration_s` on
**one line only**, so a batch is not weighted N-fold in `/idd-doctor`'s medians.
The fan-out runs *across the run*: at batch time only the issues in
`issues_resolved` get a line. No `failed` line is written at batch time; every
unresolved attempted issue — including the batch's primary (spawn-position)
issue, whose `optimized_order` slot is already consumed — is re-queued for
individual resolution, where that resolve writes its one line. Hence no
re-resolve double-count and no inverse under-count. One carve-out: the later
`already resolved in batch` skip is display only and writes no run-log line. The
authored contract lives in
`src/skills/auto-pilot/references/explicit-list-mode.md` (*Run-log fan-out for the
batch*).
