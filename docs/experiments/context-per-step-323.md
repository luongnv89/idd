# Per-step reference files — main-agent context measurement (#323)

**Issue:** [#323](https://github.com/luongnv89/idd/issues/323)
**Change:** `references/pipeline-steps.md` (`/issue-resolver`) and `references/phases.md`
(`/auto-pilot`) became an index plus one file per step or phase.
**Date:** 2026-09-03
**Status:** complete. Static and live measurements both recorded; the §4 decision
rule fired negative, so #440 closes as not needed.

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
The `Read` tool has no way to fetch "the *Step 3* section", so pointing at one
section of a 1560-line file lands as much of the whole file as the tool will
return. §4 measures how much that turned out to be — less than the whole file,
but 3.1× the next largest read. Splitting the file is the cheap fix, so it went
first; the measurement below says how much it buys and where the next lever is.

## 2. Static measurement — bytes a step directs the main agent to read

Taken 2026-09-03 on the built tree (`skills/`) with `wc -c`. "Directed" means
what the skill prose tells the agent to read at that step; a live agent may read
more or less (§4 measures that). These cells are a dated record of what the
split produced and are deliberately left unrefreshed; §4.2 reconciles the five
that no longer match today's tree.

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
- **Delegating Step 0 was the candidate next lever, and §4 rules it out.** Step
  0 is the one step whose prose (17.7 KB + 7.8 KB + 8.7 KB) the main agent must
  read itself, because it owns it — which is why
  [#440](https://github.com/luongnv89/idd/issues/440) was filed from #323 and
  gated on the live measurement, since static numbers cannot say how much a live
  agent actually reads. The measurement is now in §4: after the split, Step 0's
  largest single file (17,658 B) is no longer the largest single read the main
  agent makes (`report-templates.md`, 20,292 B), so #440 closes as not needed.

## 3. What was not split, and why

| File | Size | Reason it stayed |
|---|---|---|
| `auto-pilot/references/phases/phase-1-triage-pick.md` | 41 KB | Every iteration in triage mode runs all six of its sub-steps; a further split would add pointers without skipping reads. |
| `auto-pilot/references/subagent-prompts.md` | 26 KB | SKILL.md reads it once at start by design; the prompts are needed every iteration. |
| `issue-pr-review/references/review-loop-mechanics.md` | 39 KB | Candidate for the same treatment; left for a separate change so this one stays two skills wide. |

## 4. Live measurement — result

Static numbers say what the prose directs; only a transcript says what the agent
read. The procedure below was run on 2026-09-04 against the real session
transcripts for this repository. **Verdict: the split alone is the answer, and
[#440](https://github.com/luongnv89/idd/issues/440) closes as not needed.** The
deciding number is 17,658 bytes against 20,292.

### 4.1 Procedure

1. Run `/issue-resolver <N>` interactively and let it finish (or `/auto-pilot
   --limit 1` for the loop skill).
2. Locate the session transcript under
   `~/.claude/projects/<project-slug>/<session-id>.jsonl`.
3. Sum, per `Read` tool call whose `file_path` falls under an installed skill's
   `references/`, the bytes the call actually **returned** — not the file's size
   on disk. The two differ in both directions: `Read` truncates a large file on
   returned output size, so `os.path.getsize` overstates it, and `Read` prefixes
   every line with its number, so on a small file `getsize` understates it. Skip
   every record carrying `isSidechain: true`: those are subagent turns, and the
   whole question is what the *main* agent read.

   ```bash
   python3 - "$TRANSCRIPT" <<'PY'
   import json, sys
   pending, total = {}, {}
   for line in open(sys.argv[1], errors="replace"):
       try: rec = json.loads(line)
       except ValueError: continue
       if rec.get("isSidechain"): continue          # subagent, not the main agent
       for blk in (rec.get("message") or {}).get("content") or []:
           if not isinstance(blk, dict): continue
           if blk.get("type") == "tool_use" and blk.get("name") == "Read":
               p = (blk.get("input") or {}).get("file_path", "")
               if "/skills/" in p and "/references/" in p and blk.get("id"):
                   pending[blk["id"]] = p
           elif blk.get("type") == "tool_result" and blk.get("tool_use_id") in pending:
               c = blk.get("content")
               n = (sum(len(b.get("text", "")) for b in c if isinstance(b, dict))
                    if isinstance(c, list) else len(c or ""))
               fp = pending.pop(blk["tool_use_id"])
               total[fp] = total.get(fp, 0) + n
   for p, n in sorted(total.items(), key=lambda kv: -kv[1]): print(f"{n:>8}  {p}")
   print(f"{sum(total.values()):>8}  total reference bytes read by the main agent")
   PY
   ```

4. Record the *Run Stats Footer* tokens line beside the byte totals, when the
   host reported one.
5. Apply the decision rule in §4.3.

### 4.2 Numbers

**Before — pre-split, live.** One `/issue-resolver` main-agent transcript in
this project carries pipeline reads. All twelve of its reference reads:

| Bytes returned | File |
|---|---|
| 59,078 | `references/pipeline-steps.md` |
| 18,962 | `references/report-templates.md` |
| 15,615 | `references/agents/codebase-researcher.md` |
| 14,035 | `references/agents/implementer.md` |
| 10,194 | `references/agents/fixer.md` |
| 10,194 | `issue-pr-review/references/agents/fixer.md` (cross-skill) |
| 9,551 | `references/docs/agent-model-effort.md` |
| 9,235 | `references/agents/synthesizer.md` |
| 8,633 | `references/docs/run-log-schema.md` |
| 8,273 | `references/agents/code-reviewer.md` |
| 7,870 | `references/docs/shared-agent-conventions.md` |
| 6,353 | `references/docs/sync-conventions.md` |
| **177,993** | **total** |

The pipeline spec is the largest single read by 3.1×, and 33.2% of everything
the main agent read. It entered context at 59,078 bytes, not the 89,627 of §2,
because the call was truncated: a single `Read` with no `offset` or `limit`
returned 1,030 of the file's 1,560 lines and stopped mid-sentence. **The bound
is on returned output size, not line count.** The file is comfortably under
`Read`'s 2,000-line ceiling and was cut anyway, at roughly 59 KB of rendered
output. That correction matters twice over: it refutes §1's original reasoning,
which as first written held that the `Read` tool's 2,000-line cap meant a
1,560-line file lands whole, and it means "under 2,000 lines" is not evidence
that a file arrives whole.

**After — post-split, static is a sound proxy for live.** The observed cut
above happened at roughly 59 KB of output. The largest file the split produced
anywhere is `/auto-pilot`'s `phase-1-triage-pick.md` (§2), 41,280 bytes over
696 lines, which `Read` renders as 43,566 characters — 73.7% of the 59,078 the
truncated call returned, counted on the same character basis. That file is
still under the observed bound, but with far less room than the ones this
comparison turns on. Within `/issue-resolver` the largest is
`step-3-implement.md` at 19,515 bytes and 313 lines, about a third of the cut,
so none of the `/issue-resolver` files below comes near the bound and each
arrives whole. Their rendered size is slightly *larger* than `wc -c`, because
`Read` prefixes every line with its number; §4.4 carries that arithmetic. The
prose files bearing on the comparison, on the built `skills/issue-resolver`
tree, re-measured 2026-09-04 — this is not a full ranking, but nothing it omits
exceeds 17,658, and the largest bundled `references/scripts/*.py` exceed every
row here without belonging in the table at all, being executed rather than
read:

| Bytes | File | When the main agent reads it |
|---|---|---|
| 20,292 | `references/report-templates.md` | unconditionally, at the top of every run |
| 19,515 | `references/steps/step-3-implement.md` | every full run, before the implementer spawn |
| 17,658 | `references/steps/step-0-preflight.md` | Step 0 |
| 15,032 | `references/agents/codebase-researcher.md` | Step 1 spawn |
| 8,686 | `references/steps/step-0i-caller-payload.md` | Step 0, only under a caller payload |
| 7,809 | `references/steps/step-0h-analysis-reuse.md` | Step 0, only with `adaptive_effort` |
| 6,028 | `references/pipeline-steps.md` (index) | Step 0 |

`references/docs/pre-commit-security.md` is larger still at 19,830, but it does
not belong in this comparison: it reaches the implementer and the fixer as a
spawn-variable *path*, and the orchestrator reads it only on the degrade branch
where `gi-secscan.py` cannot run. The measured transcript never read it.

**Reconciling these with §2.** Five of §2's After cells differ from today's
tree — four in the `/issue-resolver` table and one in `/auto-pilot` — and they
differ for two different reasons. Three were measured mid-PR, before the final
build: no commit since the split has touched them — the table below shows their
`a6e29d6` and today columns identical — so the sizes §2 records for them were
never on any committed tree. One is ordinary post-merge drift. One is both.
Every other cell in §2's After column, in both tables, still matches to the
byte.

| File | §2 says | at `a6e29d6` | today | Why it differs |
|---|---|---|---|---|
| `issue-resolver/steps/step-0h-analysis-reuse.md` | 7,774 | 7,809 | 7,809 | measured pre-build; unchanged since |
| `issue-resolver/steps/step-3-implement.md` | 19,473 | 19,515 | 19,515 | measured pre-build; unchanged since |
| `auto-pilot/references/phases.md` (index) | 1,310 | 1,546 | 1,546 | measured pre-build; unchanged since |
| `issue-resolver/steps/step-4-qa.md` | 10,273 | 10,312 | 10,783 | both: measured pre-build, then `6592b8a` |
| `issue-resolver/SKILL.md` | 24,175 | 24,175 | 24,912 | drift only, by `6592b8a` |

`report-templates.md` moved the same way (19,156 → 20,292, by `6592b8a`) but
§2's table never carried a cell for it. §2's totals are self-consistent with
its own cells, so that table was coherent when written; it is left standing as
the dated record it is.

### 4.3 Decision

The rule: delegate Step 0 only if, after the split, Step 0 is still the largest
single reference read the main agent makes — only if it stays big enough that
moving it into a subagent buys more than the spawn costs.

**It is not.** Step 0's largest single file is `step-0-preflight.md` at 17,658
bytes. `report-templates.md` is larger at 20,292 and is read unconditionally at
the top of every run. Narrow the field to step files alone and the answer does
not change: `step-3-implement.md` at 19,515 is read on every full run. The
pre-split spec led its nearest rival by 3.1×; the post-split Step 0 file is no
longer even first. The lever the pre-split number pointed at is gone, spent by
the split itself.

**The rule's own wording is ambiguous, and it is worth naming.** As originally
written — before this note replaced it with a pointer back here — step 5 of
§4.1 read: "delegate Step 0 only if the main agent's measured reference bytes
at the end of Step 0 exceed the static 34 KB ceiling above by less than the
cost of a spawn (the researcher spawn's own prompt is ~15 KB) — that is, only
if Step 0 is still the largest single read the main agent makes. Otherwise the
split alone is the answer and the follow-up closes as not needed." Its first
clause anchors on that "static 34 KB ceiling" — the three Step 0 files summed.
That was 34,118 bytes against §2's cells and is 34,153 against today's, and
either *would* exceed 20,292. Its "that is" clause says "largest single read."
The single-read reading governs, because #440's body states it independently
as the normative gate, and because §2 marks `0h` conditional on
`resolve.adaptive_effort` and `0i` conditional on a caller payload. A standalone
`/issue-resolver N` reads 23,686 bytes of Step 0 across two files, or 31,495
with `0h`; 34,153 is a worst case, not the common path. (The ceiling figure
counts the three step files without the index, while the common-path figures
include it — carrying the index into the worst case makes it 40,181.)

**A second argument settles it independently of any byte count.** Delegation
cannot deliver its own premise here.

- `step-0-preflight.md` is not "Step 0". It holds the configuration load and
  `0e — Workspace`. Gates `0a`–`0d`, `0f` and `0g` are written inline in
  `SKILL.md`, which is 24,912 bytes and always loaded, so no subagent can move
  them out of the orchestrator's context under any design.
- What `0e` actually does is create a git worktree and copy gitignored local
  config into a directory the orchestrator then runs in. A subagent cannot hand
  back a working directory.
- *Caller-supplied context payloads* in `docs/shared-agent-conventions.md` says
  a payload field may never skip, shorten or soften the resolver's mandatory
  Repo Sync. That sync appears five times in `step-0-preflight.md`, including on
  the worktree-accept, worktree-failure-fallback and cleanup paths, and again in
  the in-place summary and the caller-managed-worktree skip. An orchestrator
  that must re-verify it reads that prose anyway.

**Outcome:** #440 closes as not needed. The remaining candidate for the same
treatment is `issue-pr-review/references/review-loop-mechanics.md` (§3), which
is a splitting question, not a delegation one.

### 4.4 Stated limitations

- **One transcript, not a matched pair.** The procedure asked for the same issue
  run before and after the split. The installed skill under `~/.claude/skills/`
  is still the pre-split build, so no post-split live run exists to pair with.
  The verdict rests on the before-run establishing *which* files the main agent
  actually reads, plus static post-split sizes for how big they are.

  That substitution is safe here, and the arithmetic says why rather than
  asserting it. Static and live diverge two ways: truncation, which cost the
  pre-split spec 34% of its bytes, and `Read`'s per-line number prefix, which
  adds a little. None of the three files below comes near the truncation bound,
  so only the prefix applies, and it is calculable — `{n}\t` per line:

  | `wc -c` | as `Read` renders it | Lines | File |
  |---|---|---|---|
  | 20,292 | 20,776 | 311 | `references/report-templates.md` |
  | 19,515 | 20,421 | 313 | `references/steps/step-3-implement.md` |
  | 17,658 | 18,606 | 289 | `references/steps/step-0-preflight.md` |

  The ranking is unchanged. The deciding margin against `report-templates.md`
  narrows from 2,634 to 2,170, and the step-file backstop margin from 1,857 to
  1,815. One caveat on units: the rendered column counts *characters*, which is
  what the live measurement counts, while `wc -c` counts bytes, and these files
  carry 652, 238 and 100 bytes of multibyte punctuation respectively. Rendered
  as bytes the three would be 21,428 / 20,659 / 18,706 and both margins would
  widen instead. The ranking holds on either basis, which is the only thing the
  rule turns on. A matched live pair would sharpen the totals; it cannot move
  that.
- **Per-step attribution was not recoverable.** As originally written, the
  procedure asked for a per-step split delimited by the `[N/5]` tracker lines.
  The measured agent printed all the tracker tokens in one planning block
  before doing its reads, so the reads cannot be assigned to steps after the
  fact, and §4.1 now asks only for per-file totals. The per-file ranking the
  rule needs is unaffected.
- **No token line.** The host reported no usage figure for the measured run, so
  the tokens line step 4 asks for is absent.

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
