# ADR — Run-Stats Token Reporting

**Status:** Accepted (2026-08-25).
**Issue:** [#410](https://github.com/luongnv89/idd/issues/410).
**Supersedes in part:** [#373](https://github.com/luongnv89/idd/issues/373) —
AC3 and AC5, for the `tokens` field only.

## Context

Issue #373 gave every IDD skill a two-line run-cost footer with three fields —
`elapsed`, `tokens`, `agents` — and a rule that any field whose value cannot be
determined prints the literal `n/a` rather than being omitted, guessed, or
reported as `0`. That rule is right for `elapsed` and `agents`, both of which a
skill can determine on nearly every run and genuinely loses only in edge cases
(a stop before the clock was captured; a resume that dropped the tally).

For `tokens` it produced a field that read `tokens n/a` on every run of every
skill, forever. The contract even said so, calling `tokens n/a` "the expected
reading on most hosts". A marker whose whole purpose is to distinguish *we do
not know* from *nothing happened* stops carrying information when it can never
resolve: it is a field announcing, once per run, that it will never have a
value. That is the bug #410 reports.

Whether a real count could be obtained was checked before choosing a fix, and
the answer is no — not portably. Claude Code does persist per-message `usage`
records in `~/.claude/projects/<slug>/<session>.jsonl`, but reading them is not
available to these skills for three independent reasons, any one of which is
sufficient:

1. **The skills are host-agnostic prose.** They are instructions executed by
   whatever agent runtime loads them. A procedure that reaches into one host's
   private session files is not a contract the other hosts can satisfy, and the
   footer's shape is a cross-skill, cross-host contract by construction.
2. **The contract's own *Overhead* section forbids the mechanism.** It rules out
   "a timing call per step, a running tally file, a subprocess, or a
   summarization pass". Locating a session file, reading it, and summing its
   usage records is precisely a subprocess plus a summarization pass, spent on
   measuring rather than on the work being measured.
3. **The number would be wrong anyway.** The footer prints before its own turn's
   usage record lands, so the last and largest slice is always missing; and
   subagent usage is written to separate session files, so `/auto-pilot` — the
   skill whose cost is most worth knowing — would report the orchestrator's
   tokens and none of the fleet's. A confidently wrong cost figure is worse than
   no figure.

## Decision

**`tokens` becomes a conditional field: printed where the host reports a usage
figure, omitted entirely where it does not.**

- `elapsed` and `agents` stay unconditional and keep the #373 `n/a` rule intact,
  including `agents 0` as a determined value.
- Where the host surfaced a usage figure to the skill in the run's own context,
  the footer prints `Run stats   elapsed 4m 12s · tokens 128,400 · agents 4`,
  with `tokens` in its fixed position between the other two.
- Where nothing reported one, the footer prints
  `Run stats   elapsed 4m 12s · agents 4` — the field and its ` · ` separator
  both dropped, with no placeholder and no dangling separator.
- Omission is not a per-skill choice. On a host that reports nothing, every
  skill drops the field; on a host that reports, every skill prints it. Field
  order and labels remain pinned, so #373's AC6 byte-identity guarantee is
  untouched.
- Manufacturing a figure stays forbidden: no estimating from output length, file
  sizes, or step counts, and no reading the host's transcript, session files, or
  logs to reconstruct one.

The contract text lives in the byte-identical `references/run-stats.md` carried
by all eight skills; `tests/test-run-stats-373.sh` now forbids the string
`tokens n/a` in it and asserts the omitted rendering is shown as canonical.

## Consequences

- #373's AC3 ("reports at minimum elapsed and tokens") and AC5 ("an
  undeterminable metric shows an explicit unavailable marker") remain binding on
  `elapsed` and `agents`. For `tokens` they are superseded by this record; the
  test suite's header says so, so a later reader does not mistake the change for
  drift.
- The footer's field count is no longer fixed at three. Anything parsing it must
  read fields by label, not by position — which the ` · `-delimited
  `label value` shape already supports.
- If a host does begin reporting usage to skills, nothing needs to change: the
  contract already specifies where the number goes and how it is formatted. This
  ADR does not close the door on token reporting; it stops printing a promise
  the current hosts cannot keep.
- This is a **current** decision record, written with the change it describes.
  `docs/decisions/no-backfill-merged-decision-records.md` forbids adding records
  retroactively to already-merged commits; it does not restrict recording a
  decision as it is made, which is what the dual-write rule asks for.

## Re-validation

Revisit if a usage figure becomes available to a skill through a host-neutral
interface — one that costs no subprocess, covers subagent usage, and is complete
at the moment the footer prints. Meeting fewer than all three does not reopen
this: a partial count printed as a total is the failure mode the third reason
above rules out.
