# `/auto-pilot --stats` — read-only run report

Read only under `--stats`. It reports what past runs did; it starts no run.

## Read-only guarantee

The stats path loads no config, creates no run state, takes no lock,
stashes, switches or fetches nothing, and writes no report file, run-log line,
label or comment. It makes no edit of any kind. It skips every other SKILL.md
section, Self-Improve included.

## Run the report

From the repository root, with the script path resolved relative to SKILL.md:

```bash
python3 references/scripts/gi-stats.py
```

Add `--no-github` to stay offline, `--json` for a machine-readable object.

- **Exit 0** — print its output as is. It covers run outcomes (rows, outcome
  counts, success rate, unexplained QA ceiling breaches, slowest phase) and the
  look-back after merge per release (merged runs, reverts, reopened issues,
  follow-up bugs, flagged rate), names the walked ref, and prints any `⚠`
  freshness warning. A ceiling breach is data, never a failure.
- **Exit 2 or 4, no `python3`, or unparsable output** — print
  `⚠ gi-stats unavailable — counting the run log by hand` and use the fallback.

## Fallback: count the run log by hand

1. Read the newest rotated `.idd/runs-*.jsonl` segments (up to 10), oldest to
   newest, then `.idd/runs.jsonl`. Skip blank and malformed lines.
2. Count each `outcome` value and print the counts, then the total rows.
3. Say that the look-back rates (reverts, reopened issues, follow-up bugs)
   need the script.

No log anywhere → print `○ No runs recorded in .idd/runs.jsonl`.

## End

Print the run-stats footer (`references/run-stats.md`) with `elapsed n/a` and
`agents 0`, then stop.
