# Per-step reference files — main-agent context measurement (#323)

**Issue:** [#323](https://github.com/luongnv89/idd/issues/323)
**Change:** `references/pipeline-steps.md` (`/issue-resolver`) and `references/phases.md`
(`/auto-pilot`) became an index plus one file per step or phase.
**Date:** 2026-09-03
**Status:** static measurement done; live measurement pending (procedure in §4).

## 1. Why a split, not a delegation pattern

#323 as filed asked for a pattern where the main agent extracts "only the context
needed for the next step" and hands it to a subagent. Two facts argued against
building that first:

- **The heavy steps are already delegated.** The resolver's Steps 1–4 run in
  subagents with a results-only handoff (`docs/shared-agent-conventions.md`,
  *Output discipline*). The main agent owns preflight, the tracker, checkpoints,
  the security gates, the run log and the run lock — the parts the conventions
  say an orchestrator must keep.
- **Context cannot be pruned once read.** A Claude Code context only shrinks at
  compaction. The only levers are *not reading* a file, or reading it in another
  agent's context. An acceptance criterion phrased as "the main agent's context
  contains only the slice" is therefore not a state anyone can produce or test.

What the main agent *does* read in full is whichever reference a step points it
at. Two of those were one file each for the whole pipeline: 90 KB and 118 KB.
The `Read` tool returns up to 2000 lines, so "read the *Step 3* section" of a
1560-line file lands the whole file in context. Splitting the file is the cheap
fix, so it went first; the measurement below says how much it buys and where
the next lever is.

## 2. Static measurement — bytes a step directs the main agent to read

Taken on the built tree (`skills/`) with `wc -c`. "Directed" means what the
skill prose tells the agent to read at that step; a live agent may read more or
less (§4 measures that).

### `/issue-resolver`

| Point in the run | Before (bytes) | After (bytes) |
|---|---|---|
| SKILL.md (always) | 24,175 | 24,175 |
| Pipeline spec opened at Step 0 | 89,627 (whole file) | 6,028 index + 17,658 step-0 |
| + Step 0h (only with `resolve.adaptive_effort`) | in the 89,627 | 7,774 |
| + Step 0i (only under a caller payload) | in the 89,627 | 8,686 |
| + Step 1 | — | 10,018 |
| + Step 2 (skipped by `light` and `analysis_reuse = fresh`) | — | 10,612 |
| + Step 3 | — | 19,473 |
| + Step 4 | — | 10,273 |
| + Step 5 | — | 2,546 |
| **Context after Step 0** (SKILL + spec) | **113,802** | **47,861** |
| **Context after a Step 1 early exit** (`already_resolved`) | 113,802 | 57,879 |
| **Context at the end of a full run** | 113,802 | 117,243 |

### `/auto-pilot`

| Point in the run | Before (bytes) | After (bytes) |
|---|---|---|
| SKILL.md (always) | 37,271 | 37,271 |
| Phase spec opened at Phase 0 | 118,460 (whole file) | 1,310 index + 14,415 phase-0 |
| + Phase 1 (skipped in explicit list mode) | — | 41,280 |
| + Phase 2 | — | 18,301 |
| + Phases 3 & 4 | — | 12,972 |
| + Phase 5 | — | 32,633 |
| **Context after Phase 0** | **155,731** | **52,996** |
| **Context after Phase 1 on an empty backlog** | 155,731 | 94,276 |
| **Context after one full iteration** | 155,731 | 158,182 |

### Reading the numbers

- **The split does not reduce the total for a full run.** A run that reaches
  every step reads the same prose plus ~3 KB of part headers. The gain is in
  *when* and *whether*: a preflight stop, an early exit, a `light` profile, a
  fresh analysis, or explicit list mode now skips the files it never needed,
  and the first two thirds of a run carry 55–65% less spec in context.
- **Compaction is where a long `/auto-pilot` run gains most.** After a
  compaction the agent re-reads the phase it is in — 13–41 KB — instead of the
  118 KB file it used to have to re-open to find any one section.
- **The next lever is delegation of Step 0, not more splitting.** Step 0 is the
  one step whose prose (17.7 KB + 7.8 KB + 8.7 KB) the main agent must read
  itself, because it owns it. That is [#440](https://github.com/luongnv89/idd/issues/440), filed from #323, and it is
  gated on §4, because the static numbers cannot say how much a live agent
  actually reads.

## 3. What was not split, and why

| File | Size | Reason it stayed |
|---|---|---|
| `auto-pilot/references/phases/phase-1-triage-pick.md` | 41 KB | Every iteration in triage mode runs all six of its sub-steps; a further split would add pointers without skipping reads. |
| `auto-pilot/references/subagent-prompts.md` | 26 KB | SKILL.md reads it once at start by design; the prompts are needed every iteration. |
| `issue-pr-review/references/review-loop-mechanics.md` | 39 KB | Candidate for the same treatment; left for a separate change so this one stays two skills wide. |

## 4. Live measurement — procedure (pending)

Static numbers say what the prose directs; only a transcript says what the agent
read. Run this once before and once after the split (the *before* is the parent
of the split commit), on the same small issue in a scratch repository:

1. Run `/issue-resolver <N>` interactively and let it finish (or `/auto-pilot
   --limit 1` for the loop skill).
2. Locate the session transcript under
   `~/.claude/projects/<project-slug>/<session-id>.jsonl`.
3. Sum the bytes of every `Read` tool call whose `file_path` falls under the
   installed skill's `references/`, per step (steps are delimited by the
   `[N/5]` tracker lines the skill prints):

   ```bash
   python3 - "$TRANSCRIPT" <<'PY'
   import json, os, sys
   total = {}
   for line in open(sys.argv[1]):
       try: rec = json.loads(line)
       except ValueError: continue
       for blk in (rec.get("message") or {}).get("content") or []:
           if isinstance(blk, dict) and blk.get("type") == "tool_use" and blk.get("name") == "Read":
               p = blk["input"].get("file_path", "")
               if "/references/" in p and os.path.isfile(p):
                   total[p] = os.path.getsize(p)
   for p, n in sorted(total.items(), key=lambda kv: -kv[1]): print(f"{n:>8}  {p}")
   print(f"{sum(total.values()):>8}  total reference bytes read by the main agent")
   PY
   ```

4. Record the *Run Stats Footer* tokens line from both runs beside the byte
   totals, when the host reported one.
5. Decision rule for the follow-up: delegate Step 0 only if the main agent's
   measured reference bytes at the end of Step 0 exceed the static 34 KB
   ceiling above by less than the cost of a spawn (the researcher spawn's own
   prompt is ~15 KB) — that is, only if Step 0 is still the largest single
   read the main agent makes. Otherwise the split alone is the answer and the
   follow-up closes as not needed.

## 5. Test-suite note

The suite asserted on the two files by path in 32 scripts. Those assertions are
about the spec, not about which file holds a sentence, so `tests/lib/spec.bash`
adds `spec_concat`, which reads an index followed by its part files as one temp
file; every path variable now goes through it. Three assertions were tightened
rather than redirected, because the split exposed that they passed by
co-location: the analysis-reuse ancestry check (`merge-base --is-ancestor` also
appears in the worktree-lane check, now in a different file), the
`tests_state` single-home check, and the `secscan_policy_ref` pairing, which
now counts one spawn site per step file.
