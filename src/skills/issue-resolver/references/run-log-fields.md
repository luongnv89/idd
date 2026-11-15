# Run-log entry — field derivation and suppression

Full detail for SKILL.md *Step 5 — Deliver → Run-log entry (monitoring)*, which
owns the trigger (every terminal outcome), the append snippet, and the
`--no-run-log` switch. This section carries the parts a run only needs once it is
actually writing the line.

## Fields to populate

Build the object from values already known during the run — `ts`, `issue`,
`mode`, `skill`, `outcome`, `pr`, plus the optional `complexity`, `profile`,
`agent_overrides`, `qa_cycles`, `ceiling`, `breach_reason`, `verification`, `duration_s`, `phases`, `tokens`, `agents`, `model`, `effort`, `skill_version`, and `skipped_reason` —
following the schema in `docs/run-log-schema.md` rather than re-deriving fields
here.

These derivations are the resolver's own:

- **`complexity`** — collapse the researcher's 5-value scale to the 3-value
  run-log scale before writing: `trivial`/`low` → `low`, `medium` → `medium`,
  `high`/`complex` → `high`.
- **`profile`** — the pipeline profile chosen in *Step 0g* (`light` or `full`).
  Omit the field only when `resolve.adaptive_effort` is `false`, or when no
  profile was selected at all (for example an early failure before Step 0g ran).
- **`agent_overrides`** — tally every configured (non-`null`) `agents.model` /
  `agents.effort` knob of each role this run spawned: `applied` when all of them
  reached their spawn (verbatim, or effort as the prompt hint), `fallback` when
  none did (unsupported-parameter skip, a role degraded by a rejected spawn, no
  Agent tool), `partial` for a mix. **Omit the field when no spawned role had an
  override configured** — never write `null` or a fourth value (exit 3).
- **`phases`** — seconds per step, from the epochs taken as each `[N/5]` step
  starts (SKILL.md *Configuration*): `preflight` runs from `run_started_epoch` to
  the `[1/5]` start, then `research`, `plan`, `implement`, `qa` (every cycle) and
  `deliver` each to the next boundary, the last to the terminal outcome. Omit a
  step that never started (an early exit or failure); the step in progress at
  that exit is measured to it. Omit the field when no boundary was captured.
- **`ceiling`** — class policy: `1` if `profile` is `light`; `resolve.qa_max_cycles`
  (default 5) if complexity is `high`; otherwise `2`. Fail-safe omitted
  profile/complexity as full + medium (`2`).
- **`breach_reason`** — required when `qa_cycles` exceeds `ceiling`
  (`gi-runlog.py` exits 3 without it); omit otherwise.
- **`verification`** — `success` only, by the `docs/run-log-schema.md` rule
  applied to the PR's AC table: any row not `pass` → `partial`, deferred rows
  excluded only on a `Refs #N` PR (`/issue-pr-review` *Intentional reference*);
  so does Step 0's `Criteria confirmed` at `×`. Not returned under `--no-run-log`.

- **`tokens`, `agents`, `duration_s`** — the row and the *Run Stats Footer*
  (`references/run-stats.md`) agree. `tokens` is the count the footer prints:
  write it only when the host reported one, never derived, estimated or `0`.
  `agents` is the footer's spawn count; omit it when the footer prints `n/a`.
  `duration_s` is the terminal epoch minus `run_started_epoch`, the clock the
  footer's `elapsed` reads.
- **`skill_version`** — this skill's own `metadata.version` (SKILL.md frontmatter).
- **`model`, `effort`** — this session's model and reasoning effort, only when
  the host states them; never guessed from a tier or a config default.

`outcome` is one of `success` (a PR was delivered), `already_resolved` (Step 0/1
found the issue already fixed and exited early), or `failed` (a step failed). A
`failed` run an auto-mode default No stopped also carries — and, under
`--no-run-log`, returns — `skipped_reason` (`assigned_to_other`, `blocked_label`,
`needs_clarification`, `empty_body`, `large_scope`, `max_commits_exceeded`).

## Suppression rule (single writer under `/auto-pilot`)

`--no-run-log` is passed only by `/auto-pilot`, which runs this resolver as a
subagent and writes the **single** run-log line per issue itself — appending here
too would double-write and skew `/idd-doctor`'s metrics. Instead **return** the
telemetry (`outcome`, `qa_cycles`, `ceiling`, `breach_reason`, `complexity`, `profile`, `agent_overrides`, `duration_s`, `phases`) in the
subagent result so the orchestrator folds it into its own line — with `tokens`,
`agents`, `model` and `effort` by the same rules (`skill_version` is the
writer's, so it is not returned).

The flag is independent of `--auto`: a standalone `/issue-resolver <N> --auto`
run is *not* suppressed and still writes its own line.
