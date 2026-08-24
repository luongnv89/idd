# `.gitissue/runs.jsonl` — Run Log Schema

The cross-run telemetry file written by `/issue-resolver` and `/auto-pilot`.
Canonical schema for a `runs.jsonl` line: field set, append rules, rotation, and
the single-writer convention. It stands alone so appending one line never needs
the full configuration schema
([config-schema.md](https://github.com/luongnv89/idd/blob/main/docs/config-schema.md)).

## Schema

`runs.jsonl` is the first home for the `monitoring` value: an **append-only,
schema-light, newline-delimited JSON** file, one self-contained object per run,
deletable like the rest of `.gitissue/`. Its readers — `/idd-doctor`'s run-log
summary, `scripts/idd-lint.py stats` and `gi-runlog.py --failure-streak` — are
**best-effort by design**: truncation costs only *progress toward* a quarantine,
never an existing one, whose durable record is the label `/auto-pilot` applies.
**Rotation** (below) bounds the file's size.

Full field set; *Always present* is the required minimum:

| Field | Type | Always present | Description |
|-------|------|----------------|-------------|
| `ts` | string (ISO 8601 UTC) | yes | When the run finished, e.g. `2026-06-26T14:31:07Z` |
| `event_id` | string | no | Idempotency key for a parallel lane, minted at scheduling. Used only with `--append-once`; legacy writers omit it. |
| `issue` | integer | yes | Issue number the run processed |
| `mode` | string | yes | Resolver rows: `interactive`/`auto`. Auto-pilot rows: its merge mode (`conservative`/`balanced`/`aggressive`) |
| `skill` | string | yes | `issue-resolver` or `auto-pilot` — which skill wrote the line |
| `outcome` | string | yes | Terminal outcome. Resolver: `success`, `already_resolved`, `failed`. Auto-pilot: `merged`, `left_open`, `partial_followup`, `blocked_by_dependency`, `failed`, `skipped`. |
| `pr` | integer or null | yes | PR number when a PR was created, else `null` |
| `complexity` | string | no | Research complexity on the **3-value** run-log scale, when known. Collapse the researcher's 5-value estimate: `trivial`/`low` → `low`, `medium` → `medium`, `high`/`complex` → `high`. Never emit `trivial` or `complex`. |
| `profile` | string | no | Adaptive-effort pipeline profile: `light` (trivial fast path) or `full`. Omitted when `resolve.adaptive_effort` is `false` or the signal was unavailable. See [agent-model-effort.md](https://github.com/luongnv89/idd/blob/main/docs/agent-model-effort.md) (Complexity → profile). |
| `qa_cycles` | integer | no | QA review-fix cycles run |
| `ceiling` | integer | no | Class QA-cycle policy ceiling: 1 for `light`, `resolve.qa_max_cycles` (default 5) for `full`+`high`, else 2. Omit unless recorded; a recorded value must be a positive integer and overrides the computed one. |
| `breach_reason` | string | no | Why `qa_cycles` exceeded `ceiling`. Required when `qa_cycles` > `ceiling`; omit otherwise; `gi-runlog` rejects an over-ceiling row without it (exit 3) and `idd-lint stats` exits 1 on such rows. |
| `duration_s` | integer | no | Wall-clock run duration in seconds, when measurable |
| `skipped_reason` | string | no | Why the issue was skipped (auto-pilot skips, any `skipped`/`already_resolved` outcome): e.g. `already_resolved`, `blocked_label`, `blocked_by_dependency`, `in_skip_list`, `assigned_to_other`, `quarantined` |

Example lines:

```jsonl
{"ts":"2026-06-26T14:31:07Z","issue":141,"mode":"auto","skill":"issue-resolver","complexity":"medium","profile":"full","qa_cycles":2,"outcome":"success","pr":150,"duration_s":372}
{"ts":"2026-06-26T15:02:41Z","issue":152,"mode":"auto","skill":"issue-resolver","complexity":"low","profile":"light","qa_cycles":1,"outcome":"success","pr":161,"duration_s":94}
{"ts":"2026-06-26T14:48:12Z","issue":118,"mode":"balanced","skill":"auto-pilot","outcome":"skipped","pr":null,"skipped_reason":"blocked_by_dependency"}
```

**Append rules:**
- Create `.gitissue/` with `mkdir -p` if absent, then append one line ending in a
  single `\n`. Never rewrite or reorder existing lines.
- Legacy `--append` writes are **best-effort and non-fatal**. A parallel lane's
  `--append-once` failure instead leaves its durable state at `log_pending`; it
  never raw-appends, and resume retries the same event.
- **No schema migration**: optional fields may appear over time, so readers must
  tolerate missing and unknown keys. Absent optional fields are omitted, never
  written as `null` — except `pr`, which is always present.

**The `gi-runlog` helper.** A skill bundling `references/scripts/gi-runlog.py`
should pipe the record to it on stdin rather than hand-roll the append: it
enforces every rule above — required-field and `outcome` validation, the 5→3
`complexity` collapse, dropping `null` optional keys, filling an absent `ts` from
UTC, and the canonical key order (the example lines', not the table's). Its modes
are mutually exclusive. `--append` (default) creates `.gitissue/` and appends one
`\n`-terminated line to `--path` (default `.gitissue/runs.jsonl`); `--echo`
validates identically, prints the line and **writes nothing**; `--append-once`
requires `event_id`, locks its cross-process read/check/append/fsync transaction,
reuses an identical event and exits `3` on conflict. Exits: `0` ok; `2` usage;
`3` invalid/conflicting; `4` I/O failure — legacy callers may raw-append on `4`,
parallel lanes leave `log_pending` and retry.

The one read: `--failure-streak N [--threshold F] [--log PATH]` prints
`{"mode":"failure_streak","issue":N,"streak":N,"threshold":F,"quarantine":bool}`
— that issue's most recent consecutive `failed` records, stopping at its first
record with any other outcome (`--threshold 0` disables quarantine). Malformed
lines are skipped. Exit `4` (log missing or unreadable) still prints the line
with `streak: 0`, so nothing is quarantined on unread evidence. Without the
script: count bottom-up, skipping other issues, stopping at the first
non-`failed` record.

**Rotation (size/age).** The active log never grows without bound. Before an
append-mode write, `gi-runlog.py` renames it to a sibling segment
`runs-<YYYYMMDDTHHMMSSZ>.jsonl` (UTC stamp, `-N` on a same-second collision) once
it has reached `--rotate-max-bytes` (default 1048576) **or** sat idle past
`--rotate-max-days` (default 30); the record then starts a fresh log. Age is the
file's mtime, not any `ts` inside it, so a backdated record cannot rotate a fresh
log. Rotation is best-effort: a failed rename warns on stderr and the record
still appends. `--no-rotate` disables it, `--echo` never rotates, and the raw
fallback bypasses it entirely.

Readers window rather than slurp: the streak read, the `--append-once` dedup scan
and `scripts/idd-lint.py stats` all read the newest `--tail-segments` (default
10) segments plus the active log, oldest first, as one logical log. A record past
that window is out of every reader's scope, so its `event_id` may be reused.

**Single writer under `/auto-pilot`:** `/auto-pilot` runs `/issue-resolver` as a
subagent, so uncoordinated both would append, double-counting every processed
issue in `/idd-doctor`'s metrics. So `/auto-pilot` passes the resolver
`--no-run-log`: it **returns** its telemetry — run `status` (the `outcome`),
`qa_cycles`, `ceiling`, `breach_reason`, `complexity`, `duration_s` — and the
orchestrator folds it into one enriched line. The flag is **orthogonal to
`--auto`/`IDD_AUTO_MODE`**: a standalone `/issue-resolver <N> --auto` still logs.
The rule: the outermost skill is the single writer; an inner resolver stays silent.

**Batch fan-out (one line per attempted issue).** The *Batch Resolver* path
(`/auto-pilot --issues`) follows the same rule, so `/auto-pilot` **fans the one
batch result out into one line per attempted issue**, never per PR — the shared
`pr` and `complexity` on every line, the batch-scalar `qa_cycles` and
`duration_s` on **one line only** so `/idd-doctor`'s medians are not weighted
N-fold. At batch time only the issues in `issues_resolved` get a line. No `failed` line is written at batch time; every
unresolved attempted issue — including the batch's primary (spawn-position)
issue, whose `optimized_order` slot is already consumed — is re-queued for
individual resolution, which writes its one line: no re-resolve double-count and
no inverse under-count. One carve-out: the later `already resolved in batch` skip
is display only and writes no run-log line. Authored contract:
`src/skills/auto-pilot/references/explicit-list-mode.md` (*Run-log fan-out for
the batch*).