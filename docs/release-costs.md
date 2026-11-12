# Release cost record

One entry per release: the median token cost of each flow that writes a run-log
row, so a change in what a run costs is visible from one release to the next
(issue #562). A human-only project doc: no skill references it, so the build
bundles it nowhere.

## How an entry is produced

1. Run `python3 scripts/idd-lint.py stats --no-github` in a checkout whose
   `.idd/runs.jsonl` holds the runs made with the release being cut. The
   *Run log* section prints one `tokens <skill>` line per flow: the median of
   the `tokens` field and how many rows reported it (`--json` carries the same
   under `runs.by_skill`).
2. Add a `## vX.Y.Z` section below, newest first, with one row per flow.
3. Copy the median and the sample count as printed. Where the line reads
   `no data`, write `no data` and a sample count of 0.

`tests/test-plugin-manifest-469.sh` (S13) fails when the version in
`src/plugin/plugin.json` has no section here, or the section lacks a row for a
flow, or a row's median is neither an integer nor `no data`.

## Rules

- **Never invent a number.** `tokens` reaches a row only when the host reported
  a count to the skill and the Run Stats Footer printed it
  (`docs/run-log-schema.md`, *Footer agreement*;
  `docs/decisions/run-stats-token-reporting.md`). Most hosts report none, so
  `no data` is the expected entry until one does. It is not zero, and it is
  never filled in from an estimate, a transcript or a previous release.
- **Flows** are the skills that write run-log rows: `issue-resolver` and
  `auto-pilot`. An `auto-pilot` row carries the cost of the resolve it
  orchestrated for that issue, not of the whole loop.
- **Samples** is the number of rows the median was taken over. A median over a
  handful of rows is recorded as it is, with its count beside it.
- **Source** names where the number came from, so two entries measured
  differently are not compared as if they were the same quantity.
- `.idd/runs.jsonl` is local and untracked. The entry is the only durable
  record, so write it before the log rotates out of the reader window.

## Releases

Newest first.

## v0.27.0

| Flow | Median tokens | Samples | Source |
|------|--------------:|--------:|--------|
| `issue-resolver` | no data | 0 | no run-log row carries `tokens`: the field did not exist before #562 |
| `auto-pilot` | no data | 0 | no run-log row carries `tokens`: the field did not exist before #562 |

## Baseline: #465 (2026-09-26, before any release recorded a cost)

| Flow | Median tokens | Samples | Source |
|------|--------------:|--------:|--------|
| `issue-resolver` | 9,387,421 | 21 | `docs/experiments/cost-counters-465.md` §4.1 |
| `auto-pilot` | no data | 0 | not measured by #465 |

The baseline is a one-off lab measurement, not a run-log median:
`scripts/idd-cost-counters.py` mined 21 resolver runs from local session
transcripts and counted **processed** tokens, cache reads included. A run-log
`tokens` value is whatever figure the host reports to the skill, which need not
be the same quantity. Compare a release against the baseline for order of
magnitude only.
