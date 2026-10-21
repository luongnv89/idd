# ADR — Context-Threshold Compaction and Durable Re-entry

**Status:** Accepted (2026-10-21).
**Issue:** [#540](https://github.com/luongnv89/idd/issues/540).
**Runtime contract:** [context-threshold.md](https://github.com/luongnv89/idd/blob/main/docs/context-threshold.md).

## Context

Issue #540 asks that IDD skills run as long-running workflows in the manner of
**pi durable** (`@earendil-works/pi-durable`, the durable harness of the Pi
coding agent): when a session's remaining context drops below a per-skill
threshold (15% for `/auto-pilot`, 40% for every other skill), compact the
session with a prompt built for the next step, then carry on. The behavior must
be configurable and possible to turn off.

What a skill can and cannot do on the hosts IDD targets decided the shape:

| Capability | Can a skill do it? | Source |
|---|---|---|
| Trigger compaction | **No.** `/compact` is a user command, not available through the Skill tool; only the user or the host's auto-compact compacts | https://code.claude.com/docs/en/skills |
| Pass instructions to auto-compact | **No.** A `PreCompact` hook can only block, and auto-compaction carries no custom instructions | https://code.claude.com/docs/en/hooks |
| Observe remaining context | **Only on some models**, which receive an in-band `Token usage: X/Y; Z remaining` warning. The status line's `remaining_percentage` goes to a user display script, not the model | https://platform.claude.com/docs/en/build-with-claude/context-windows |
| Tune auto-compact | **User-side only**: `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` per launch, lower-only, main agent and subagents | https://code.claude.com/docs/en/env-vars |
| Survive a compaction | Invoked skill bodies are re-injected from the **start** of SKILL.md, capped per skill; reference files are not | https://code.claude.com/docs/en/skills |

Reading host transcripts or session files to estimate tokens is already ruled
out by [ADR — Run-Stats Token Reporting](https://github.com/luongnv89/idd/blob/main/docs/decisions/run-stats-token-reporting.md)
(#410).

**AC1 and AC3 were reframed.** As written, they asked the agent to compact and
to hand auto-compact a tailored prompt, which no skill can do on Claude Code. On
2026-10-21 the issue was amended so that AC1 and AC3 describe the deliverable:
the skill checkpoints and *prompts* compaction (an interactive `/compact <focus>`
line, or one warning in auto mode), the user or host compacts, and a re-entry
rule restores the next step's needs from durable state. The original wording is
preserved in a backup comment on the issue.

## Decision

A new top-level `compaction` config section (`enabled`, plus one
`threshold.<skill>` integer 1-99 per skill), one runtime doc bundled into all
eight skills, a threshold check at each skill's safe boundary, and a short
re-entry rule placed before *Prerequisites* in the three long-running skills
(`/auto-pilot`, `/issue-resolver`, `/issue-pr-review`) so it survives the
re-injection cap. The check fires only on an in-context figure and is silently
skipped otherwise; it never pauses or stops an auto run and adds no `Result:`
value. `compaction.enabled: false` turns every part off.

### pi durable → IDD mapping

| pi durable concept | IDD realization |
|---|---|
| Checkpoint at every step | auto-pilot's `.idd/run-state.json` (`gi-state.py`); git and GitHub for the resolver and reviewer |
| Transcript vs. work | GitHub is the source of truth; the conversation is a lossy view of it |
| Lossy compaction | The re-entry rule: re-read durable state and the current step's reference before acting |
| `settings.compaction{enabled, reserveTokens}` | The `compaction` section: `enabled` and per-skill `threshold` |
| `compact(instructions)` / `beforeCompact` | The generated `/compact <focus>` line (skill-authored literals and integers only) |
| `reset(handoffNote)` | The existing `/auto-pilot --resume` |
| Idempotency / reconcile | A live `gh … --json` read before any effectful repeat (push, PR, comment, label, merge) |

### What default-on writes

Nothing new reaches disk, with one exception: when `compaction.enabled` is true,
`/auto-pilot` writes a pre-spawn checkpoint into its **existing** run-state file
before the sequential resolver spawn (`{"phase":"resolve","current":{"issue":N,"title":null,"branch":null,"pr":null,"outcome":null,"started_at":null,"phase":"resolve"}}`)
and, only when the post-resolve checkpoint is not already in place, before the
Phase 3 reviewer spawn (the post-resolve record, with this PR's branch and
`outcome`/`started_at` null). Both markers name every `current` key on purpose.
`gi-state.py` merges `current` key by key, and Phase 3's `left_open` exit leaves
the previous issue's record set, so a marker naming only `issue` and `phase`
would inherit that issue's branch and PR, and a resume would reconcile the wrong
PR. Both patches are legal `gi-state.py` transitions
(`init`/`triage`/`cleanup` → `resolve` in `RUN_TRANSITIONS`, `resolve` and
`review` in `CURRENT_START`, and `review` → `review` as an idempotent
re-checkpoint), so `gi-state.py` is unchanged. A run that dies after the resolve
marker leaves a `current` with no branch and no PR (both `null`). Step 1.0's
resume gate recognizes that shape as the marker, clears it with
`{"current": null}` (an explicit null already clears `current`), and stays
resumable (see *Consequences*).

## Rejected alternatives

- **Estimating remaining context** from transcripts or a status-line sidecar:
  forbidden by #410, host-specific, and wrong by construction.
- **Writing user settings or environment** (e.g. setting the auto-compact
  override): a skill never changes the user's configuration.
- **Hooks** (`PreCompact`, `SessionStart(compact)`): they reverse the plugin's
  published "no hooks" posture and are Claude-Code-only.
- **An on-disk handoff record**: stale-record, working-directory, worktree and
  read-back hazards, for facts git, GitHub and the run state already hold.
- **A clean `/auto-pilot` stop at the threshold**: it regresses unattended runs,
  which the host's auto-compact plus the re-entry rule carry through.

## Consequences

- **Known limitation:** on models without the in-band figure the check is inert;
  only the re-entry rules act, after a compaction the host performed.
- **`--resume` after a crash mid-resolve keeps its seeds.** A sequential run
  that died during the resolver spawn used to leave `current: null`, which a
  resume continued with `processed[]` and `skip_list[]` seeded. The pre-spawn
  checkpoint now leaves `current` at `resolve` with no branch and no PR. Step
  1.0 reads that shape as the marker, not as a doubt: it clears `current` and
  stays resumable with both lists seeded, as before. Falling back to `absent`
  instead would start a fresh `--init`, which drops the seeds and resets
  `started_at`. This run's earlier `left_open`, `failed` and
  `blocked_by_dependency` issues are still open, so the fresh run would pick
  them again and write a second run-log line for each. The gate keys on the
  record's shape, not on `compaction.enabled`, because a state an enabled run
  wrote can be resumed by a disabled one. Issue N itself is picked again, and
  the resolver's Step 0b finds any PR the dead run opened.
- The three re-entry rules are bounded: a lost loop counter takes the existing
  cap path instead of restarting at cycle 1, and a caller-managed resolver lane
  re-validates its worktree and never falls back to the ambient checkout.

## Follow-ups

- An opt-in `SessionStart(compact)` hook that re-injects the re-entry rule.
- `--resume` for `/issue-resolver` and `/issue-pr-review`, from durable progress
  records that survive a killed session ([#542](https://github.com/luongnv89/idd/issues/542)).
- A `compaction.threshold.default` key.
- A Codex note ([#489](https://github.com/luongnv89/idd/issues/489)).

## Sources

- https://github.com/earendil-works/pi/tree/main/packages/durable
- https://flaviocopes.com/pi-durable/
- https://code.claude.com/docs/en/hooks
- https://code.claude.com/docs/en/env-vars
- https://platform.claude.com/docs/en/build-with-claude/context-windows
