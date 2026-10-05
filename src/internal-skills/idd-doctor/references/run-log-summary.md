# Run-log summary — metrics and output

Read this for SKILL.md *Run-log summary* step 3 onward. The section is
informational and non-gating: nothing here changes the `Result:` line, and the
doctor writes nothing while computing it.

## Metrics

Compute each metric over the parsed runs (the last `N` lines, malformed lines
already skipped):

- **Resolve rate** — share of runs whose `outcome` is a delivered resolution.
  Count `success` (resolver) and `merged` (auto-pilot) as resolved, and report
  `resolved / total` with a percentage.
- **Median QA cycles** — median `qa_cycles` across the runs carrying it (omit
  runs without the field); `n/a` if none carry it.
- **Common skip reasons** — the top 3 `skipped_reason` values by frequency
  among `skipped` / `already_resolved` runs, each with its count; `none` when
  no run carries one.
- **Agent overrides** — among the runs carrying `agent_overrides`, the count of
  each value: `applied`, `partial`, `fallback`. A run without the field had no
  override configured and is not counted; an unknown value is ignored. When no
  run carries it, print `none configured` instead of three zeros.
- **Slowest phase** — among the runs carrying a `phases` object, the median
  seconds of each phase name (skip a non-object `phases` and any entry that is
  not a non-negative integer). Print the phase with the highest median, its
  median, and how many runs recorded it. `n/a` when no run carries the field.

## Output

Print the section with DESIGN.md symbols:

```
    ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    ○ Run-log summary           last {n} of {total} runs · {m} malformed skipped
        Resolve rate:    {resolved}/{n} ({pct}%)
        Median QA cycles: {median}
        Top skip reasons: {reason1} ({c1}), {reason2} ({c2})
        Agent overrides:  {applied} applied · {partial} partial · {fallback} fallback
        Slowest phase:    {phase} (median {median}s · {runs} runs)
```

Omit the ` · {m} malformed skipped` clause when `{m}` is 0. When no runs are
recorded, SKILL.md step 1's single graceful-degradation line replaces the
whole block.

A read heuristic for the input (no new dependency — `tail` plus a JSON-aware
pass):

```bash
[ -s .gitissue/runs.jsonl ] && tail -n 50 .gitissue/runs.jsonl
```
