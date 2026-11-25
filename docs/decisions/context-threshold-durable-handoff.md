# ADR — Context-Threshold Compaction and Durable Re-entry

**Status:** Accepted (2026-10-21); amended 2026-10-22 by [#542](https://github.com/luongnv89/idd/issues/542) — see *Amendment — durable progress records (#542)* — and 2026-11-25 by [#690](https://github.com/luongnv89/idd/issues/690) — see *Amendment — every skill reviewed for cut-off resume (#690)*.
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
| Checkpoint at every step | auto-pilot's `.idd/run-state.json` (`gi-state.py`); git and GitHub for the resolver and reviewer, and since #542 a progress record per resolver and reviewer run (`gi-progress.py`) |
| Transcript vs. work | GitHub is the source of truth; the conversation is a lossy view of it |
| Lossy compaction | The re-entry rule: re-read durable state and the current step's reference before acting |
| `settings.compaction{enabled, reserveTokens}` | The `compaction` section: `enabled` and per-skill `threshold` |
| `compact(instructions)` / `beforeCompact` | The generated `/compact <focus>` line (skill-authored literals and integers only) |
| `reset(handoffNote)` | The existing `/auto-pilot --resume`, and since #542 `--resume` on `/issue-resolver` and `/issue-pr-review` |
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
  *Reversed by #542 for killed sessions* — see *Amendment*; this ADR's
  compaction contract still writes nothing new.
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
- Done: `--resume` for `/issue-resolver` and `/issue-pr-review`, from durable progress
  records that survive a killed session ([#542](https://github.com/luongnv89/idd/issues/542)) — see *Amendment*.
- A `compaction.threshold.default` key.
- A Codex note ([#489](https://github.com/luongnv89/idd/issues/489)).

## Amendment — durable progress records (#542)

**Accepted:** 2026-10-22. **Issue:** [#542](https://github.com/luongnv89/idd/issues/542).

The decision above rejected an on-disk handoff record because git, GitHub and
the run state already held what a *compaction* loses. A **killed** session loses
more: a fresh `/issue-resolver N` or `/issue-pr-review N` has no conversation to
read, so it started over from its first step and repeated research, planning,
QA or review cycles that had already finished. Issue #542 reverses that one
rejection, for killed sessions only.

`gi-progress.py` now keeps one progress record per skill and issue or PR number.
Each skill writes it at every step boundary, at each QA or review cycle, and
immediately before every effect (a write-ahead intent). It holds only what git
and GitHub cannot reproduce: the step high-water mark, the plan summary, cycle
counts, the premise-reset ledger, open findings and the last effect. A fresh
session resumes from it with `--resume` (or, interactively, after a prompt),
validates it against live git and GitHub, re-runs every gate, and prints what it
restored. `/auto-pilot --resume` passes `--resume` only to the spawn it is
resuming. The compaction contract above is unchanged: *What default-on writes*
still describes the threshold check, the re-entry rules never read a progress
record, and records are written whatever `compaction.enabled` says.

| Hazard | Answer |
|---|---|
| **Stale records** | The script binds each record to the head, branch, toplevel and executor it measured itself, and re-measures them on every read. Another user or host, a missing branch, a head that is neither equal nor a descendant, or a moved head or dirty tree outside a committing step reads `stale`. The skill adds the GitHub half: a closed issue, a merged or closed PR, another head branch, a cross-repository PR. Stale is reported, cleared, and the run starts from the beginning. Records expire after seven days and are cleared at every terminal outcome. |
| **Working directory** | The store is `<git common dir>/idd/progress/`, inside `.git`: no branch can commit it, no PR body reaches it, and one clone finds it from any directory. Every path comparison is canonicalized with `realpath` on both sides, so a symlinked parent cannot split one checkout into two. |
| **Worktrees** | The common dir is shared by every worktree, so a record written in a parallel lane or a resolver worktree is visible from the main checkout. The read reports the workspace as `here`, `elsewhere` (with the registered path), `branch_only` or `missing`. A recorded path never reaches `cd`: the resolver recomposes it from the re-derived branch and compares physical paths. A lane resumes only with `IDD_RESUME_LANE=1`, `--resume` and a matching lane identity, and `/auto-pilot` binds a record only when its `caller_run_id` equals the run it is resuming. |
| **Read-back trust** | A record is a hint, never an authority. A closed key set refuses every gate-satisfying fact (`tests_state`, `qa_handoff`, a receipt, a marker, a verdict) and every fact the script measures, and counters only grow. A record never satisfies or skips a safety gate: the secret scan, the CI wait, the acceptance-criteria and traceability checks, the sensitive-change gate (a sensitive restored plan never resumes past Step 3) and the QA marker (written only when QA exited clean in this session) all run live. Free text never reaches a shell word, and every effect in flight is reconciled with a live `gh … --json` read before it repeats. |

Rejected for #542: extending `gi-state.py` (its store is relative to the working
directory and holds one run, so each worktree would keep its own copy) and a
marker on GitHub (a PR body or comment is attacker-writable, and no PR exists
before the resolver delivers).

## Amendment — every skill reviewed for cut-off resume (#690)

**Accepted:** 2026-11-25. **Issue:** [#690](https://github.com/luongnv89/idd/issues/690).

Issue #690 asks that every skill's workflow survive a cut-off session: finished
steps are kept, a new session on the same task continues from the first
unfinished step, it says what it recovered, and it redoes whatever no longer
matches the repo, issue or PR. All nine skills were reviewed against that. Four
gained resume rules, one gained a report-only check, and four are recorded as
reviewed with no change.

| Skill | Outcome | Mechanism, or the decision recorded |
|---|---|---|
| `/auto-pilot` | Reviewed, no change | `gi-state.py` run state, the run lock and the Step 1.0 resume gate already cover it. Resume needs the explicit `--resume`; a bare re-run takes the stale or fresh path. |
| `/issue-resolver` | Reviewed, no change | The `gi-progress.py` record (#542). **Decision kept:** in auto mode a re-run without `--resume` starts over (`--start` replaces the record); an interactive run asks. |
| `/issue-pr-review` | Reviewed, no change | The `gi-progress.py` record (#542). **Decisions kept:** the same auto-mode `--resume` rule, and `--review-only` reads and writes no record, so a cut-off review-only run starts over. |
| `/issue-analysis` | Changed | A stage file keeps the explorer's and the synthesizer's validated returns, pinned to `HEAD` and the issue's `updatedAt`. A re-run with a holding pin skips Steps 2-7. Under `--plan` the stage outlives the persist until the plan post is verified, and a resumed run asks `gi-plan.py check` before posting again, whatever the pin says, because the post itself moves `updatedAt`. |
| `/issue-triage` | Changed | Each returned scanner batch is staged, pinned to `HEAD` and to each issue's number and `updatedAt`. A re-run reuses the batches whose pin holds and scans the rest. Auto mode follows the same pin. |
| `/issue-creator` | Changed | Batch reads this login's issues live before the first create and never creates an item twice. Normalize reuses a backup comment that already holds the live body, and posts a missing normalization comment after a cut-off between the body edit and that comment. Single Create keeps no record: its duplicate check flags the earlier create. |
| `/plan-to-issues` | Changed | A reused or adopted epic prints what was filed and what comes next, and reports a worklist that differs from the filed tasks. `--epic <n>` on an unmarked epic adopts it and restores the draft from the epic body. The dependency pass appends a marker only when it is absent. |
| `/init-idd` | Changed (report-only) | An existing `.idd.yml` is validated before the overwrite/merge/cancel choice and a failure prints one warning. Auto mode still takes cancel. |
| `/idd-doctor` | Reviewed, no change | Read-only and one pass: a cut-off loses printed output only. |

**The shared contract** is one closure leaf, `src/shared/references/resume-cut-off.md`,
bundled into the four changed skills that print a recovery block: saved
progress is a hint and never an authority, an effect is read live before it is
repeated, stale progress is named and redone, and the recovery block and stale
notice have one shape. A second leaf, `src/shared/references/stage-file.md`,
holds the stage-file contract for the two skills that write one.

**Stage files** live in `<git common dir>/idd/stage/` (`analysis-<N>.json`,
`triage.json`), beside the progress records and for the same reasons: no
branch can commit them and no stash or clean-tree check sees them. They are
written through a temp file and an atomic rename, refused through a symlinked
directory, read as untrusted data that never reaches a command line, and
removed at the skill's terminal persist. No script owns them and
`gi-progress.py` is unchanged: it reads only `idd/progress/`.

**What is still lost** — each is at most the step in progress, or a recorded limit:

- `/plan-to-issues`, conversation path: a session cut off between the draft
  confirm and the epic create call has no durable record, so the draft is
  drafted and confirmed again. A task whose body changed under the same id and
  title is not detected; the stale notice never re-files, edits or closes a
  filed child.
- `/issue-creator` Normalize: labels suggested by a run cut off before its
  label step are not recovered. A batch item whose title was reworded between
  runs is not recovered and falls to the duplicate flag.
- `/issue-analysis`: the inline path (no Agent tool) writes no stage, and a
  re-run of a *finished* analysis stays a fresh analysis.
- `/issue-triage`: a PR merged between the cut-off and the resume, with
  `HEAD` unmoved, is not seen by a reused batch; reused batches are named
  under *Uncertainty*.
- `/init-idd`: the pre-choice check reports; it does not re-run the merge
  strategy check or the starter recipe of a run cut off after the write.
- `/issue-resolver`, `/issue-pr-review`, `/auto-pilot`: the three decisions
  kept above. On those paths "continues instead of starting over" holds only
  with `--resume` or the interactive prompt.

Rejected for #690: a new `--resume` flag or config key on the five changed
skills (the surface counts stay where they were), a stage store under
`.idd/cache/` (an untracked file there can reach a stash or fail a clean-tree
check), a stage file for `/plan-to-issues` (it writes to the tracker only),
and editing the resolver, reviewer or auto-pilot, whose bundles sit at or over
the release growth cap.

## Sources

- https://github.com/earendil-works/pi/tree/main/packages/durable
- https://flaviocopes.com/pi-durable/
- https://code.claude.com/docs/en/hooks
- https://code.claude.com/docs/en/env-vars
- https://platform.claude.com/docs/en/build-with-claude/context-windows
