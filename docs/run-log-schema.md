# `.gitissue/runs.jsonl` — Run Log Schema

The run log is the cross-run telemetry file written by `/issue-resolver` and
`/auto-pilot`. This document is the canonical schema for a `runs.jsonl` line: the
field set, the append rules, and the single-writer convention. It stands alone so
appending one telemetry line never requires the full configuration schema
([config-schema.md](https://github.com/luongnv89/idd/blob/main/docs/config-schema.md)).

## Schema

`runs.jsonl` is the first home for the `monitoring` value. It is an **append-only,
schema-light, newline-delimited JSON** file: each line is one self-contained JSON
object describing a single run. It is grep-friendly, diffable, and deletable like
the rest of `.gitissue/` — it is read back only by `/idd-doctor`'s run-log
summary, `scripts/idd-lint.py stats` (the no-agent evidence report), and
`gi-runlog.py --failure-streak` (`/auto-pilot`'s consecutive-failure count), so
truncation or deletion only resets the telemetry window. That last reader is
**best-effort by design**: the durable record of a quarantine is the label
`/auto-pilot` puts on the issue, so a truncated log loses only *progress toward*
one, never an existing quarantine.

The full field set — the *Always present* column is the required minimum:

| Field | Type | Always present | Description |
|-------|------|----------------|-------------|
| `ts` | string (ISO 8601 UTC) | yes | When the run finished, e.g. `2026-06-26T14:31:07Z` |
| `event_id` | string | no | Stable idempotency key for a parallel lane. Created at scheduling; used only with `--append-once`; omitted on legacy writers. |
| `issue` | integer | yes | Issue number the run processed |
| `mode` | string | yes | `interactive` or `auto` (resolver); the auto-pilot merge mode (`conservative` / `balanced` / `aggressive`) for auto-pilot rows |
| `skill` | string | yes | `issue-resolver` or `auto-pilot` — which skill wrote the line |
| `outcome` | string | yes | Terminal outcome. Resolver: `success`, `already_resolved`, `failed`. Auto-pilot: one of its six categorical outcomes (`merged`, `left_open`, `partial_followup`, `blocked_by_dependency`, `failed`, `skipped`). |
| `pr` | integer or null | yes | PR number when a PR was created, else `null` |
| `complexity` | string | no | Research complexity on the **3-value** run-log scale (`low` / `medium` / `high`) when known. Collapse the researcher's 5-value estimate before writing: `trivial` or `low` → `low`; `medium` → `medium`; `high` or `complex` → `high`. Never emit `trivial` or `complex` in runs.jsonl. |
| `profile` | string | no | The adaptive-effort pipeline profile the run selected: `light` (trivial fast path) or `full`. Omitted when `resolve.adaptive_effort` is `false` or the signal was unavailable. See [agent-model-effort.md](https://github.com/luongnv89/idd/blob/main/docs/agent-model-effort.md) (Complexity → pipeline profile). |
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
- Legacy `--append` writes are **best-effort and non-fatal**. A parallel lane's
  `--append-once` failure instead leaves its durable state at `log_pending`; it
  never raw-appends and resume retries the same event.
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
`--no-run-log` contract below. `--append-once` requires `event_id`, locks its
cross-process read/check/append/fsync transaction, reuses an identical event,
and exits `3` on conflicting data. Exit `0` wrote, found, or
printed the line; `2` is usage; `3` is invalid/conflicting; `4` is an I/O failure.
Legacy callers may use the documented raw fallback on `4`; parallel lanes must
leave `log_pending` and retry instead.

The same helper serves the one read. `--failure-streak N [--threshold F] [--log PATH]`
prints `{"mode":"failure_streak","issue":N,"streak":N,"threshold":F,"quarantine":bool}`:
the most recent consecutive `failed` records for that issue, stopping at its first
record with any other outcome (`--threshold 0` disables quarantine). Malformed lines are
skipped, per the no-schema-migration rule. Exit `4` means the log was missing or
unreadable and **the line is printed anyway** with `streak: 0`, so nothing is ever
quarantined on evidence nobody read. Without the script, count by hand: bottom-up,
skipping other issues, stopping at this one's first non-`failed` record.

**Single writer under `/auto-pilot`:** when `/auto-pilot` resolves an issue it runs
`/issue-resolver` as a subagent, so without coordination *both* would append — two
lines per processed issue, double-counting it in `/idd-doctor`'s metrics. To keep
**exactly one line per processed issue**, `/auto-pilot` passes the resolver
`--no-run-log`: the suppressed resolver does **not** append and instead **returns**
its telemetry — run `status` (the `outcome`), `qa_cycles`, `complexity`,
`duration_s` — for the orchestrator to fold into its single enriched line. The flag
is **orthogonal to `--auto`/`IDD_AUTO_MODE`**: a standalone
`/issue-resolver <N> --auto` is *not* suppressed. The rule: the outermost skill is
the single writer; an inner resolver stays silent.

**Batch fan-out (one line per attempted issue).** The *Batch Resolver* path
(`/auto-pilot --issues`, several issues in one PR) follows the same rule, so
`/auto-pilot` **fans the one batch result out into one line per attempted issue** —
the contract is per *processed issue*, never per PR — with the shared `pr` and
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
