# Deterministic cost counters for skill runs (#465)

**Issue:** [#465](https://github.com/luongnv89/idd/issues/465), part of epic
[#464](https://github.com/luongnv89/idd/issues/464)
**Change:** the eval shim logs every `gh` call; `grade.py` grades the count;
`scripts/idd-cost-counters.py` summarizes a call log and mines the evidence.
**Date:** 2026-09-26
**Status:** complete. One counter adopted provisionally (gh calls per scripted
flow). Its exact count is kept as a deterministic regression check, but it is
not a validated cost counter: the evidence in §6 was measured on agent-issued
calls, and the lab counts script-issued ones, so its link to cost is inferred,
not measured. Four proposed and not adopted. Every number below is output of
the tool in §3.4.

## 1. Question

Epic #464 wants to make skill runs cheaper. Before anyone optimizes against a
number, that number has to be shown to move with what a run costs. If it does
not, a change that lowers it lowers nothing that matters. So the question is
narrow. Is there a per-run counter that:

1. a scripted flow produces **reproducibly**: same flow, same count, no
   wall-clock flakiness, no network; and
2. comes with **recorded evidence** that it correlates with observed run cost?

A counter needs both. One without evidence can't be trusted as a target.
Evidence without a deterministic lab producer means there's nothing to put in
a test.

## 2. Why the counting is lab-side

Nothing in this change runs inside a skill. That is deliberate, and two
accepted decisions require it:

- [The run-stats field set ADR](https://github.com/luongnv89/idd/blob/main/docs/decisions/run-stats-field-set.md)
  (#414) keeps the run footer to `elapsed`, `tokens` (conditional) and
  `agents`. Its overhead rule forbids running tallies and subprocesses spent
  on measuring.
- [The token-reporting ADR](https://github.com/luongnv89/idd/blob/main/docs/decisions/run-stats-token-reporting.md)
  (#410) rules out a skill reading host session transcripts at run time.

The counters therefore live in two places, and neither runs as part of a skill:

- **The eval lab.** `evals/harness/gh_shim.py` writes one line per invocation
  to `EVAL_GH_CALL_LOG`. `run_eval.sh` publishes that log as
  `OUT/gh-calls.jsonl`, and the `gh-calls` grading tool asserts on it. The
  `issue-resolver/gh-call-counter` case runs the real shared `gi-issue.py`
  through the shim (via the new `repo_scripts` case key) and expects exactly
  3 calls.
- **An offline repo tool.** `scripts/idd-cost-counters.py evidence` reads
  local transcripts after the fact. It is repository tooling, not a skill, and
  nothing runs it at skill run time. The same offline-mining approach was used
  before, in
  [the #323 context measurement](https://github.com/luongnv89/idd/blob/main/docs/experiments/context-per-step-323.md)
  (§4.1).

## 3. Method

### 3.1 Sample

- **Source:** the local Claude Code session transcripts of this repository
  (`~/.claude/projects/<repo-slug>/`). Snapshot taken 2026-09-26. The
  transcripts are not committed. This document carries only the numbers
  derived from them.
- **Runs:** every `<dir>/*/subagents/*.meta.json` with `spawnDepth == 1` whose
  `description` matches the flow selector. The run's transcript is the sibling
  `.jsonl` file.
  - resolver: `^Resolve`
  - review: `^(Review PR|reviewer|Code review)`
- **Exclusion:** `--exclude '#465'` drops this issue's own resolve run. That
  run was still in progress, and still growing, when the snapshot was taken.
- **Nesting:** a run's totals include every descendant transcript. A child is
  linked to its parent when the child meta's `toolUseId` equals the id of an
  `Agent`/`Task` tool_use in the parent, applied recursively.

### 3.2 Per-run metrics

| Metric | Definition |
|--------|------------|
| `gh` | matches of `` (?:^\|[\s;&\|(`$])gh\s+(?:issue\|pr\|api\|repo\|run\|label\|project\|search\|release\|workflow\|auth)\b `` in Bash tool_use commands. This counts the `gh` invocations the **agent** writes into a command. It does **not** count `gh` calls made inside a shared script the agent runs (`gi-issue.py`, `gi-ci-wait.py` and the like): the transcript shows only the command that runs the script, never the `gh` processes the script spawns |
| `gh_bytes` | tool_result size of the Bash calls with at least one `gh` match |
| `result_bytes` | every tool_result: a string counts its UTF-8 bytes, anything else the length of its JSON serialization |
| `spawns` | `Agent`/`Task` tool_uses |
| `tools` | all tool_uses (the control variable) |
| `tokens` | for each distinct assistant `message.id`, the **max** of each of `input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens` and `output_tokens` across that id's rows, then the four summed over ids. The max matters because streamed rows repeat a message's usage, so a plain sum double-counts it |
| `wall_s` | max − min row timestamp of the run's own transcript |

`tokens` is the cost reference. It counts processed tokens, cache reads
included. It is **not** a billed amount (see §6).

### 3.3 Statistics

- **Correlation:** Spearman ρ, with tied values sharing their average rank.
- **Significance:** a two-sided permutation p on |ρ|, from 20,000 shuffles
  with seed 465. Zero hits is reported as `<5e-05`, not as p = 0. Runs are
  sorted (description, then session, then transcript name) before any
  statistic, so p reproduces exactly for a given snapshot and seed.
- **Partial Spearman controlling for `tools`:** tests whether a counter
  tracks cost beyond simply tracking how long the run was.
- **Independent cross-check:** ρ against `duration_s` from `.gitissue/runs.jsonl`.
  That duration is recorded by the skill itself, not taken from the
  transcript. The join key is the first three-digit number in the run
  description. An issue that appears in more than one run, or that has other
  than exactly one `duration_s` record, is dropped. Resolver flow only: review
  descriptions carry PR numbers, which the issue-keyed run log cannot join.

### 3.4 Reproduce

```bash
python3 scripts/idd-cost-counters.py evidence ~/.claude/projects/<repo-slug> \
  --exclude '#465' --runs-log .gitissue/runs.jsonl          # add --json for JSON
```

The port was checked against the analysis scripts that first produced these
figures. Fed the runs in the same order, it reproduces every ρ, partial ρ and
p exactly. The committed tool sorts the runs first, which changes how the
seeded shuffles pair values, so its p values differ from that first pass by
permutation noise (review gh 0.0012 → 0.0018; resolver gh_bytes 0.026 →
0.02455; a single hit in 20,000 becoming none, reported as `<5e-05`). Every ρ
and partial ρ is unchanged, and no p moves across the 0.05 bar.

## 4. Raw per-run numbers

Session is an 8-character session-id prefix.

### 4.1 Resolver flow (n = 21)

| Run | Session | gh | gh_bytes | result_bytes | spawns | tools | tokens | wall_s | children |
|-----|---------|---:|---------:|-------------:|-------:|------:|-------:|-------:|---------:|
| Resolve 415 auto-pilot | `adbacce0` | 13 | 7,017 | 290,836 | 0 | 127 | 22,842,929 | 3,429 | 0 |
| Resolve 417 retry branched | `adbacce0` | 78 | 5,574 | 235,511 | 0 | 112 | 17,837,021 | 3,600 | 0 |
| Resolve 418 issue-triage | `adbacce0` | 18 | 7,612 | 264,187 | 0 | 128 | 21,664,489 | 14,694 | 0 |
| Resolve 419 issue-analysis | `adbacce0` | 9 | 6,498 | 149,250 | 0 | 97 | 11,123,988 | 2,346 | 0 |
| Resolve 420 issue-creator | `adbacce0` | 33 | 7,154 | 354,915 | 0 | 145 | 31,255,760 | 3,167 | 0 |
| Resolve 421 init-gitissue | `adbacce0` | 2 | 4,657 | 166,777 | 0 | 64 | 4,761,724 | 863 | 0 |
| Resolve 422 idd-doctor | `adbacce0` | 128 | 12,452 | 268,165 | 0 | 229 | 50,803,525 | 2,468 | 0 |
| Resolve 426 shared contract | `adbacce0` | 53 | 16,959 | 144,253 | 0 | 125 | 17,692,740 | 2,133 | 0 |
| Resolve issue #446 | `7177f099` | 3 | 390 | 193,613 | 1 | 86 | 7,678,083 | 1,188 | 1 |
| Resolve issue #447 | `7177f099` | 8 | 1,333 | 103,076 | 1 | 201 | 22,300,336 | 1,833 | 1 |
| Resolve issue #454 | `2adabbbe` | 3 | 7,083 | 139,560 | 1 | 52 | 4,292,507 | 929 | 1 |
| Resolve issue #455 | `2adabbbe` | 3 | 6,498 | 152,015 | 1 | 51 | 4,298,875 | 1,200 | 1 |
| Resolve issue #456 | `2adabbbe` | 6 | 3,996 | 127,592 | 1 | 51 | 4,482,215 | 1,134 | 1 |
| Resolve issue #458 | `2adabbbe` | 5 | 2,335 | 26,916 | 1 | 16 | 1,055,405 | 504 | 1 |
| Resolve issue #462 | `2adabbbe` | 6 | 3,699 | 97,139 | 1 | 51 | 4,329,830 | 940 | 1 |
| Resolve issue #466 | `5412f37c` | 11 | 8,601 | 416,232 | 3 | 101 | 9,387,421 | 1,223 | 3 |
| Resolve issue #467 | `5412f37c` | 6 | 3,387 | 325,222 | 1 | 93 | 12,841,396 | 1,290 | 1 |
| Resolve issue 414 run-stats | `adbacce0` | 8 | 8,382 | 365,919 | 5 | 163 | 10,726,933 | 4,067 | 5 |
| Resolve issue 416 issue-resolver | `adbacce0` | 3 | 4,260 | 93,897 | 0 | 34 | 2,585,628 | 340 | 0 |
| Resolve issue 416 retry | `adbacce0` | 3 | 5,143 | 214,044 | 0 | 71 | 6,230,730 | 1,130 | 0 |
| Resolve issue 417 pr-review | `adbacce0` | 3 | 142 | 93,740 | 0 | 35 | 1,922,745 | 607 | 0 |

### 4.2 Review flow (n = 22)

| Run | Session | gh | gh_bytes | result_bytes | spawns | tools | tokens | wall_s | children |
|-----|---------|---:|---------:|-------------:|-------:|------:|-------:|-------:|---------:|
| Code review PR 445 | `1a9da389` | 1 | 19,400 | 44,594 | 0 | 19 | 1,221,942 | 820 | 0 |
| Code review PR 450 | `e00e60b3` | 4 | 28,921 | 57,299 | 0 | 19 | 834,838 | 414 | 0 |
| Code reviewer cycle 2 — verify #440 corrections | `e7dbec98` | 0 | 0 | 62,108 | 0 | 17 | 698,841 | 324 | 0 |
| Code reviewer cycle 2 — verify fixes | `093e4b8e` | 0 | 0 | 167,971 | 0 | 36 | 1,980,713 | 371 | 0 |
| Code reviewer — QA cycle 1 issue #442 | `a7357538` | 0 | 0 | 80,750 | 0 | 28 | 1,454,780 | 555 | 0 |
| Code reviewer — QA issue #440 docs change | `e7dbec98` | 2 | 4,876 | 68,332 | 0 | 28 | 1,476,966 | 499 | 0 |
| Code reviewer — review issue #431 branch | `093e4b8e` | 0 | 0 | 119,184 | 0 | 32 | 1,937,794 | 463 | 0 |
| Review PR #448 | `7177f099` | 7 | 11,766 | 219,382 | 2 | 165 | 17,277,219 | 987 | 2 |
| Review PR #449 | `7177f099` | 8 | 36,170 | 139,795 | 1 | 40 | 2,069,908 | 575 | 1 |
| Review PR #457 | `2adabbbe` | 10 | 20,830 | 136,712 | 1 | 30 | 2,153,274 | 385 | 1 |
| Review PR #460 | `2adabbbe` | 3 | 20,871 | 168,347 | 1 | 24 | 1,766,800 | 463 | 1 |
| Review PR #461 | `2adabbbe` | 4 | 12,058 | 151,987 | 1 | 27 | 1,954,122 | 311 | 1 |
| Review PR #463 | `2adabbbe` | 5 | 17,090 | 75,888 | 1 | 17 | 1,171,379 | 449 | 1 |
| Review PR #470 | `5412f37c` | 9 | 32,556 | 194,807 | 1 | 40 | 3,527,748 | 378 | 1 |
| Review PR #471 | `5412f37c` | 9 | 15,238 | 325,292 | 1 | 64 | 6,784,077 | 942 | 1 |
| Review PR 423 | `adbacce0` | 29 | 100,355 | 402,328 | 4 | 155 | 14,587,102 | 2,083 | 4 |
| Review PR 424 | `adbacce0` | 11 | 24,510 | 393,700 | 2 | 109 | 8,813,295 | 3,886 | 2 |
| Review PR 427 | `adbacce0` | 17 | 34,955 | 248,504 | 3 | 121 | 9,905,241 | 3,535 | 3 |
| reviewer — confirmation review for PR #441 | `0333fb6a` | 0 | 0 | 54,132 | 0 | 16 | 414,919 | 372 | 0 |
| reviewer — review PR #441 | `0333fb6a` | 0 | 0 | 213,574 | 0 | 23 | 2,785,879 | 395 | 0 |
| reviewer — review PR #444 | `8711e053` | 3 | 19,360 | 64,553 | 0 | 30 | 1,623,311 | 419 | 0 |
| reviewer — review PR #452 | `f751e1a5` | 2 | 19,829 | 26,067 | 0 | 4 | 257,525 | 42 | 0 |

## 5. Results

ρ values are rounded to two places. p is the seeded permutation p from §3.3.

| Counter | Flow | ρ vs tokens | p | partial ρ \| tools | ρ vs wall_s | p |
|---------|------|------------:|--:|-------------------:|------------:|--:|
| gh calls | resolver | 0.81 | <5e-05 | 0.44 | 0.81 | <5e-05 |
| gh calls | review | 0.66 | 0.0018 | 0.25 | 0.51 | 0.0163 |
| gh output bytes | resolver | 0.49 | 0.02455 | −0.16 | 0.59 | 0.0049 |
| gh output bytes | review | 0.35 | 0.11245 | 0.05 | 0.38 | 0.0819 |
| tool-result bytes | resolver | 0.66 | 0.0014 | 0.09 | 0.71 | 0.0004 |
| tool-result bytes | review | 0.93 | <5e-05 | 0.79 | 0.53 | 0.0111 |
| subagent spawns | resolver | −0.30 | 0.19165 | −0.53 | −0.12 | 0.5991 |
| subagent spawns | review | 0.76 | <5e-05 | 0.46 | 0.55 | 0.00755 |

**Duration cross-check (resolver, n = 15 after the join rules):** gh calls
against `duration_s` gives ρ 0.64 (p 0.0114). For comparison, tokens against
`duration_s` gives ρ 0.79 (p 0.00075).

## 6. Adoption rule and verdicts

**Rule:** a counter is adopted when, against tokens, ρ ≥ 0.5 with p < 0.05 in
**both** flow samples, **and** a scripted flow can produce it deterministically
in the eval lab. To be plain about it: **the threshold was chosen after the
data above had been seen.** It is a post-hoc bar, not a pre-registered one, and
it should be read that way.

A counter that meets the bar only through a related quantity, measured on a
different set of calls, is adopted **provisionally**, not validated. That is the
case for gh calls per flow below.

| Counter | Verdict | Why |
|---------|---------|-----|
| **gh calls per flow** | **adopted provisionally** | The quantity "gh invocations per run" passes in both flows: 0.81 / 0.66, p <5e-05 / 0.0018. The duration cross-check agrees (0.64, p 0.0114). The lab produces it deterministically: the `gh-call-counter` case counts exactly 3, byte-identical across runs (`tests/test-cost-counters-465.sh`). The qualification: the evidence was measured on agent-issued calls, and the lab counts script-issued calls, a disjoint set (see the second caveat below). The lab counter's link to cost is inferred, not measured. What "provisionally" means: (a) the exact-count assertion (the `gh-call-counter` case graded at exactly 3; `tests/test-cost-counters-465.sh` T2/T10, run in CI) is kept as a deterministic regression count, so CI fails if the count moves; (b) it is not a validated cost counter, and not a cost budget, target or ratchet, so nothing should be optimized against it as a cost proxy yet; (c) promoting it to a validated cost counter needs evidence measured on script-issued gh calls, for example per-run counts of gh processes spawned inside shared scripts, correlated against run cost. |
| gh output bytes | proposed — not adopted | Below the bar in both flows: 0.49 in resolver, and 0.35 in review, where p 0.112 is not significant. Its partial ρ is near zero or negative. |
| subagent spawns | proposed — not adopted | The sign flips between flows (−0.30 resolver, 0.76 review). This is a flow-mix artifact. The older resolver runs (session `adbacce0`, issues 415–426) ran inline with 0 spawns but were among the most expensive runs. The review sample mixes orchestrators, which spawn reviewers, with single reviewers, which spawn nothing. |
| runtime tool-result bytes | proposed — not adopted | Clears the correlation bar (0.66 / 0.93), but nothing in the lab can produce it deterministically. It is the size of what an agent chose to read and run, and the eval lab runs no agent. The resolver's partial ρ of 0.09 also says it mostly tracks the number of tool calls. |
| static bundle / directed-read bytes | proposed — not adopted | Constant for a given build, so it has no per-run variance and cannot correlate with per-run cost. `scripts/skill-budget.py` (#466) stays what it is: a size budget, not a validated cost counter. |

### Caveats on the provisionally adopted counter

- **It is partly a proxy for run length.** With `tools` held fixed, the
  partial ρ drops to 0.44 (resolver) and 0.25 (review). A good share of the
  correlation is "longer runs make more calls of every kind". A drop in gh
  calls is evidence of a cheaper run, not proof of one.
- **The evidence and the lab count measure disjoint sets of calls.** The
  transcript metric (§3.2) counts only the `gh` invocations the agent writes
  into a Bash command. A command that runs `gi-issue.py` has no `gh` in its
  text, so every `gh` call made inside a shared script is left out. The eval
  case counts the opposite set: only the `gh` calls made by shared scripts
  such as `gi-issue.py`, and none the agent composes. No call is in both. So
  the ρ values above validate the **quantity** "gh invocations per run" as a
  cost proxy, measured on agent-issued calls. They were not measured on the
  lab counter. The lab counter's link to cost is inferred by analogy: the
  unit is the same (one `gh` process, one GitHub round trip), and only the
  issuer differs. That inference is plausible. It is not evidence.
- **The lab sees only script-issued calls.** In real runs most `gh` calls
  come from the prose, which the agent composes itself. Resolve 422 issued 128.
  So a lower lab count shows a script got cheaper. It does not show the prose
  around that script did too. That gap is residual risk for anyone who uses
  the lab count as a proxy for a whole run.

## 7. Limitations

- **Small n.** 21 and 22 runs. A few outlying runs can move ρ noticeably.
- **Observational.** No run was repeated under controlled conditions, so
  correlation is all this shows.
- **Tokens are processed tokens, not billed cost.** The totals include cache
  reads, which are priced differently from fresh input and output tokens. No
  price table was applied.
- **Mixed builds.** Some runs used an installed skill build that differed from
  HEAD at the time, so the sample covers several versions of the prose.
- **Mixed flows.** The resolver sample mixes inline runs from an early
  auto-pilot session with orchestrated runs. The review sample mixes PR
  orchestrators with single reviewer agents.
- **Post-hoc threshold.** See §6.
