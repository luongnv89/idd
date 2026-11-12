# Spawning a subagent by path instead of re-emitting its prompt (#561)

**Issue:** [#561](https://github.com/luongnv89/idd/issues/561), part of epic
[#547](https://github.com/luongnv89/idd/issues/547)
**Question:** can the main agent hand a subagent the path of its agent file
instead of reading the file and re-emitting it, and what does each form cost?
**Date:** 2026-11-12
**Status:** complete. Decision: **adopt per host**, provisional. Adopt on Claude
Code through a follow-up issue; keep the re-emit form on Codex CLI and on every
unmeasured host. This record changes no skill. Token and behaviour figures
below are copied or computed from the reduced results of the 12 runs in §3.
Wall-clock figures for Codex CLI, run times, the session-file counts and the
pilot cross-check in §2.4 come from the raw run files.

## 1. Question

The canonical spawn form has the main agent read the agent file and re-emit it
as the spawn prompt with every `{variable}` replaced
(`src/skills/issue-resolver/SKILL.source.md`, *Spawning a subagent (canonical
pattern)*;
[shared-agent-conventions.md](https://github.com/luongnv89/idd/blob/main/docs/shared-agent-conventions.md),
*Spawning (all agents)*). The main agent therefore pays for each agent prompt
twice: once to read it, once to write it out again.

A full resolver run spawns four prompts. At 7f18bef their built files are
50,666 bytes: codebase-researcher 15,018, synthesizer 9,780, implementer
15,758, code-reviewer 10,110.

The alternative, called the **path form** here, passes a short prompt: read
this absolute path, follow it, here are the bindings. Prior evidence is
Experiment C of
[the cross-skill invocation decision](https://github.com/luongnv89/idd/blob/main/docs/decisions/cross-skill-invocation.md):
a subagent read a repo-relative path and followed it in 3 of 3 runs, on Claude
Code only. It measured no tokens and no second host.

So the question has two parts, on Claude Code and on one other host:

1. **Behaviour.** Does the path form start one subagent that reads the file,
   honours its bindings, and returns the agent's output contract? The harness
   can observe two of the nine bindings, `{diff_command}` and `{pr_context}`
   (§6).
2. **Tokens.** Does it lower what the main agent and the whole session process?

## 2. Method

### 2.1 Arms and fixture

- **Arms:** `reemit` (the canonical form) and `path`. The two main-agent
  prompts are in §2.5. They differ only in how the spawn prompt is built.
- **Agent prompt:** the built `skills/issue-resolver/references/agents/code-reviewer.md`
  at 7f18bef (10,110 bytes, sha256
  `09cd59413a8cf2c7f06641a28a543eb3a9d916be51c80effb43459ab2d5c3343`). It was
  chosen because it carries the most spawn variables of the four: 9 distinct.
- **Location:** a byte-identical copy at an absolute path outside the
  session's working directory, as an installed skill bundle would be.
- **Fixture:** a two-commit scratch git repo. The branch diff has two seeded
  defects:

```diff
--- a/clamp.py
+++ b/clamp.py
@@ -3,8 +3,10 @@
 
 def clamp(value, low, high):
     """Return value limited to the inclusive range [low, high]."""
+    if low > high:
+        raise ValueError("low must not exceed high")
     if value < low:
         return low
-    if value > high:
-        return high
+    if value >= high:
+        return high - 1
     return value
```

  - The new `raise` breaks an invariant stated under `## Constraints`. That
    invariant reaches the subagent only through the `{pr_context}` binding, so
    a `constraints` finding proves the binding arrived.
  - `return high - 1` is an upper-bound error.

### 2.2 Hosts

| Host | Version | Invocation | Model | Notes |
|------|---------|------------|-------|-------|
| Claude Code | 2.1.322 | headless `claude -p --output-format stream-json --verbose` | `claude-fable-5-2` | normal user profile; MCP servers off (`--strict-mcp-config`); allowlist of Read, Agent, read-only git Bash, Grep, Glob |
| Codex CLI | 0.167.0 | `codex exec --json -s read-only` | `gpt-6-luna`, `model_reasoning_effort="medium"` | `multi_agent` feature on (stable, default) |

Codex CLI is the second host because it was the only non-Claude host with a
documented install path in this repo (README, *Works With Any Tool*) that was
already installed and authenticated on the machine. The account's configured
default model was refused by the service for this account type, so a model
from the account's advertised list was passed explicitly.

### 2.3 Runs

3 runs per arm per host, 12 runs, all on 2026-11-12. None excluded, none
failed.

- **Codex CLI order:** `path-0, reemit-0, path-1, reemit-1, path-2, reemit-2`
  (16:46–16:53 UTC).
- **Claude Code order:** `path-0` at about 16:44 UTC, then `reemit-0, path-1,
  reemit-1, path-2, reemit-2` at about 17:31–17:37 UTC. The gap was a wait for
  the account's usage window.
- **Pilot kept:** run 0 of the `path` arm on each host was the first run made
  and also the pilot that validated the harness. Its prompt and command are
  identical to runs 1 and 2, so it is kept.

### 2.4 Metrics

Tokens are host-reported only. Nothing is estimated.

| Field | Host | Source |
|-------|------|--------|
| `main` tokens | Claude Code | `usage` of the stream's final `result` event. It covers the main loop only: on the pilot its three input-side counters equal the sum of the main-loop messages' per-message usage (`input` 6, `cache_write` 16,929, `cache_read` 41,588). The stream's per-message `output_tokens` do not sum to the result's figure (808 against 1,560 on the pilot; stream events carry a message's usage before the message is complete), so the main-only attribution of `output` rests on the input-side match and is not independently shown |
| `total` tokens | Claude Code | `modelUsage` of the same event: the whole session |
| `sub` tokens | Claude Code | `total` − `main` |
| counters | Claude Code | four each: `input`, `cache_write`, `cache_read`, `output`. "Processed" below is their sum |
| `cost_usd` | Claude Code | the host's `total_cost_usd`, at list price. It moved with cache state, so it is reported but not used for the comparison (§3.1) |
| `main`, `sub` tokens | Codex CLI | the last `token_count.total_token_usage` of each thread's rollout file, main thread and child thread separately. `input_tokens` is cumulative across requests and includes `cached_input_tokens` |
| `total_tokens` | Codex CLI | main `total_tokens` + child `total_tokens` |
| `spawns` | both | subagents actually started |
| `spawn_calls` | Codex CLI | spawn tool calls made, rejected ones included |
| `main_read_agent_file`, `sub_read_agent_file` | both | that thread made a read call naming the agent file |
| `sub_ran_bound_diff` | both | the subagent ran a command containing the bound `{diff_command}` |
| `json_ok` | both | the main agent's final reply parsed as the reviewer's output contract with all five top-level keys |
| `constraints_finding` | both | an issue with category `constraints` |
| `upper_bound_finding` | both | a non-`constraints` issue whose text matches `high - 1`, `>=`, `upper` or `inclusive` |
| `spawn_prompt_bytes` | Claude Code | UTF-8 size of the spawn prompt |
| `fixed_lines_kept` / 93 | Claude Code | of the agent file's 93 non-empty lines that carry no `{variable}`, how many occur in the spawn prompt. This is re-emit fidelity. The test is a substring match, so the path arm scores 4 from the file's lone `{` and `}` lines, which match the braces of the binding names |
| `unreplaced_placeholders` | Claude Code | distinct agent-file placeholders present in the spawn prompt. In the path arm the short prompt names all 9 in its bindings list, so 9 is expected there and 0 in the re-emit arm |

`codex exec --json` also reports `turn.completed.usage`. It covers the main
thread only: it equals the main rollout's total, field for field, in all 6
runs.

**The two hosts' counters are not the same quantities. Do not compare them
across hosts.**

On Codex CLI the spawn message is stored encrypted in the rollout. Re-emit
fidelity is **not observable** there and is not inferred.

### 2.5 Reproduce

`<X>` is the scratch directory holding the prompts, the agent-file copy
(`<X>/bundle/references/agents/code-reviewer.md`) and the fixture repo
(`<X>/repo`, the working directory of every run). Each run pipes one arm
prompt to one host:

```bash
claude -p --output-format stream-json --verbose --strict-mcp-config \
  --allowedTools "Read" "Agent" "Task" "Bash(git diff:*)" "Bash(git log:*)" "Bash(git show:*)" "Grep" "Glob" \
  < "<X>/prompts/arm-$arm.txt" > "$out.jsonl" 2> "$out.err"

codex exec --json -s read-only --skip-git-repo-check -m gpt-6-luna \
  -c 'model_reasoning_effort="medium"' -o "$out.last" - \
  < "<X>/prompts/arm-$arm.txt" > "$out.jsonl" 2> "$out.err"
```

`arm-reemit.txt`:

```text
You are orchestrating one step of a pipeline. Use your host's agent-spawning tool to spawn exactly one subagent (the default general-purpose agent; do not select a specialised agent type) with:

- description: Reviewer — review issue #7
- prompt: the full text of the file <X>/bundle/references/agents/code-reviewer.md with every {variable} replaced by its binding below. Read that file yourself first and pass its text in the spawn prompt; the subagent must not need to read the file.

Bindings:
- {branch_name} = fix/7-clamp-upper-bound
- {base_branch} = main
- {pr_context} = the three lines between the BEGIN/END markers:
BEGIN pr_context
PR title: fix(clamp): validate bounds (#7)
## Constraints
- **Invariant:** `clamp()` never raises an exception for any numeric input.
END pr_context
- {diff_command} = git diff main...fix/7-clamp-upper-bound
- {confidence_threshold} = 80
- {challenge_context} = (empty string)
- {review_mode} = standard
- {workspace_contract} and {expected_lane_identity} = not supplied (both absent)

Wait for the subagent. Then reply with exactly the result it returned and nothing else. Do not review the diff yourself.
```

`arm-path.txt`:

```text
You are orchestrating one step of a pipeline. Use your host's agent-spawning tool to spawn exactly one subagent (the default general-purpose agent; do not select a specialised agent type) with:

- description: Reviewer — review issue #7
- prompt: the text between the BEGIN/END spawn prompt markers below, verbatim. Do not read the agent file yourself.

BEGIN spawn prompt
Read the file <X>/bundle/references/agents/code-reviewer.md and follow it as your complete instructions. It is a prompt template: wherever it contains a {variable}, substitute the binding below.

Bindings:
- {branch_name} = fix/7-clamp-upper-bound
- {base_branch} = main
- {pr_context} = the three lines between the BEGIN/END markers:
BEGIN pr_context
PR title: fix(clamp): validate bounds (#7)
## Constraints
- **Invariant:** `clamp()` never raises an exception for any numeric input.
END pr_context
- {diff_command} = git diff main...fix/7-clamp-upper-bound
- {confidence_threshold} = 80
- {challenge_context} = (empty string)
- {review_mode} = standard
- {workspace_contract} and {expected_lane_identity} = not supplied (both absent)
END spawn prompt

Wait for the subagent. Then reply with exactly the result it returned and nothing else. Do not review the diff yourself.
```

Raw run files are not committed: they carry local account identifiers. This
record carries only the reduced numbers. The runs left 13 session files under
the Codex sessions directory and 6 under the Claude Code profile's project
directory for the scratch path.

## 3. Raw per-run numbers

### 3.1 Claude Code — tokens

`main` and `sub` are `input / cache_write / cache_read / output`.

| Run | main | main processed | sub | sub processed | total processed | total output | cost_usd |
|-----|------|---------------:|-----|--------------:|----------------:|-------------:|---------:|
| `cc-path-0` | 6 / 16,929 / 41,588 / 1,560 | 60,083 | 6 / 26,600 / 46,248 / 1,681 | 74,535 | 134,618 | 3,241 | 0.6842 |
| `cc-path-1` | 6 / 2,115 / 56,306 / 1,484 | 59,911 | 6 / 16,055 / 56,438 / 1,704 | 74,203 | 134,114 | 3,188 | 0.3446 |
| `cc-path-2` | 6 / 2,166 / 56,306 / 1,523 | 60,001 | 6 / 6,283 / 66,524 / 1,834 | 74,647 | 134,648 | 3,357 | 0.2564 |
| `cc-reemit-0` | 8 / 21,880 / 77,177 / 5,681 | 104,746 | 6 / 25,647 / 49,045 / 1,522 | 76,220 | 180,966 | 7,203 | 0.9200 |
| `cc-reemit-1` | 8 / 5,852 / 93,007 / 5,464 | 104,331 | 6 / 15,282 / 59,290 / 1,530 | 76,108 | 180,439 | 6,994 | 0.5568 |
| `cc-reemit-2` | 6 / 6,188 / 93,007 / 5,796 | 104,997 | 6 / 15,280 / 59,377 / 1,526 | 76,189 | 181,186 | 7,322 | 0.5753 |

Run 0 of each arm started with a colder cache than runs 1 and 2: see its
larger `cache_write` and smaller `cache_read`. Processed totals barely move
with that; `cost_usd` does. That is why cost is not the comparison.

### 3.2 Claude Code — behaviour

All 6 runs: `spawns` 1, `sub_ran_bound_diff` true, `json_ok` true, `result`
`NEEDS_FIX`, `constraints_finding` true, `upper_bound_finding` true, 3 issues,
0 permission denials, no error.

| Run | main read file | sub read file | spawn_prompt_bytes | fixed_lines_kept | unreplaced_placeholders | num_turns | duration_s |
|-----|:--------------:|:-------------:|-------------------:|-----------------:|------------------------:|----------:|-----------:|
| `cc-path-0` | no | yes | 853 | 4 / 93 | 9 | 2 | 37.8 |
| `cc-path-1` | no | yes | 853 | 4 / 93 | 9 | 2 | 36.5 |
| `cc-path-2` | no | yes | 853 | 4 / 93 | 9 | 2 | 36.6 |
| `cc-reemit-0` | yes | no | 10,456 | 93 / 93 | 0 | 4 | 67.2 |
| `cc-reemit-1` | yes | no | 10,644 | 93 / 93 | 0 | 4 | 67.5 |
| `cc-reemit-2` | yes | no | 10,746 | 93 / 93 | 0 | 4 | 72.0 |

The re-emit arm was faithful: every fixed line kept, no placeholder left, in
3 of 3 runs. The path arm's spawn prompt was the same 853 bytes each time.

### 3.3 Codex CLI — tokens

| Run | main input | main cached | main output | main total | sub input | sub cached | sub output | sub total | total_tokens |
|-----|-----------:|------------:|------------:|-----------:|----------:|-----------:|-----------:|----------:|-------------:|
| `cx-path-0` | 61,271 | 27,648 | 503 | 61,774 | 110,788 | 86,912 | 783 | 111,571 | 173,345 |
| `cx-path-1` | 61,375 | 51,968 | 600 | 61,975 | 65,228 | 42,112 | 821 | 66,049 | 128,024 |
| `cx-path-2` | 104,187 | 93,696 | 1,238 | 105,425 | 148,818 | 142,976 | 1,519 | 150,337 | 255,762 |
| `cx-reemit-0` | 91,381 | 57,088 | 1,928 | 93,309 | 84,966 | 62,720 | 495 | 85,461 | 178,770 |
| `cx-reemit-1` | 92,587 | 78,592 | 2,546 | 95,133 | 87,582 | 64,896 | 623 | 88,205 | 183,338 |
| `cx-reemit-2` | 91,750 | 73,856 | 2,105 | 93,855 | 86,172 | 63,744 | 768 | 86,940 | 180,795 |

### 3.4 Codex CLI — behaviour

All 6 runs: `spawns` 1, `sub_ran_bound_diff` true, `json_ok` true, `result`
`NEEDS_FIX`, `constraints_finding` true. Wall-clock is first to last timestamp
of the main rollout.

| Run | spawn_calls | main read file | sub read file | upper_bound_finding | issues | wall_s |
|-----|------------:|:--------------:|:-------------:|:-------------------:|-------:|-------:|
| `cx-path-0` | 1 | no | yes | **no** | 1 | 33.3 |
| `cx-path-1` | 1 | no | yes | yes | 2 | 33.5 |
| `cx-path-2` | 3 | no | yes | yes | 2 | 62.3 |
| `cx-reemit-0` | 1 | yes | no | yes | 2 | 55.6 |
| `cx-reemit-1` | 1 | yes | no | yes | 2 | 67.0 |
| `cx-reemit-2` | 1 | yes | no | yes | 2 | 59.3 |

In the path arm the child read the absolute path outside the workspace, under
the read-only sandbox, in 3 of 3 runs.

**Incident, `cx-path-2`.** The main thread made 3 spawn tool calls. The host's
tool schema rejected the first two: one passed a `description` field the Codex
spawn tool does not have, and one used a task name with characters the tool
rejects. The third succeeded. Exactly one subagent ran. The retries are why
that run's main-thread tokens are higher than the other two path runs. The
prompt's host-neutral `description:` line caused it. That is a cost of
host-neutral spawn wording on Codex CLI, and both arms carry the same line.

## 4. Results

Median (min–max) of the 3 runs per arm.

**Claude Code**

| Metric | path | reemit |
|--------|-----:|-------:|
| main output tokens | 1,523 (1,484–1,560) | 5,681 (5,464–5,796) |
| main processed tokens | 60,001 (59,911–60,083) | 104,746 (104,331–104,997) |
| sub processed tokens | 74,535 (74,203–74,647) | 76,189 (76,108–76,220) |
| sub output tokens | 1,704 (1,681–1,834) | 1,526 (1,522–1,530) |
| total processed tokens | 134,618 (134,114–134,648) | 180,966 (180,439–181,186) |
| main-loop turns | 2 (2–2) | 4 (4–4) |
| duration_s | 36.6 (36.5–37.8) | 67.5 (67.2–72.0) |
| both defects found | 3 / 3 | 3 / 3 |

- The ranges do not overlap on any token row. Main output in the path arm is
  about 27% of the re-emit arm's (1,523 / 5,681). Total processed is about 26%
  lower (134,618 / 180,966). Turns halve. Wall-clock is about 54% of the
  re-emit arm's.
- The saving is in the main agent. The subagent processed slightly fewer
  tokens in the path arm in every run, not more: reading the file itself cost
  it no more than receiving the same text as its prompt. Its output was
  slightly higher.

**Codex CLI**

| Metric | path | reemit |
|--------|-----:|-------:|
| main output tokens | 600 (503–1,238) | 2,105 (1,928–2,546) |
| main total tokens | 61,975 (61,774–105,425) | 93,855 (93,309–95,133) |
| sub total tokens | 111,571 (66,049–150,337) | 86,940 (85,461–88,205) |
| total_tokens | 173,345 (128,024–255,762) | 180,795 (178,770–183,338) |
| wall_s | 33.5 (33.3–62.3) | 59.3 (55.6–67.0) |
| both defects found | 2 / 3 | 3 / 3 |

- Main output was lower in every path run: the highest path run (1,238) is
  below the lowest re-emit run (1,928).
- Total tokens were not reliably lower. Two path runs came in below every
  re-emit run (128,024 and 173,345) and one above every re-emit run (255,762,
  the incident run). The path arm spans 127,738 tokens; the re-emit arm 4,568.
- The child thread varied far more in the path arm (66,049–150,337) than in
  the re-emit arm (85,461–88,205).
- `cx-path-0` returned only the `constraints` finding and missed the
  upper-bound defect. No re-emit run missed it.

## 5. Decision

**Rule.** Adopt the path form on a host when, in every run, it:

- (a) starts exactly one subagent that reads the file and honours the two
  bindings the harness can observe, `{diff_command}` and `{pr_context}`;
- (b) returns the output contract with both seeded defects found as often as
  the re-emit form does; and
- (c) lowers the main agent's output tokens and the session's total processed
  tokens.

To be plain about it: **this rule was written down after the runs.** It is a
post-hoc bar, not a pre-registered one.

| Host | (a) | (b) | (c) | Verdict |
|------|-----|-----|-----|---------|
| Claude Code | held, 3 / 3 | held, 3 / 3 | held, 3 / 3 | **adopt**, through a follow-up issue |
| Codex CLI | held, 3 / 3 | failed: 2 / 3 against 3 / 3 | main output held 3 / 3; total tokens failed (1 of 3 path runs above every re-emit run) | **keep the re-emit form** for now |
| Gemini CLI, GitHub Copilot, other SKILL.md agents | unmeasured | unmeasured | unmeasured | **keep the re-emit form** |

**Decision: adopt per host. Provisional.**

- **Claude Code.** Every condition held in every run, with (a) judged on the
  two observed bindings only (§6). This issue changes nothing, so adoption
  needs a follow-up issue that amends
  [shared-agent-conventions.md](https://github.com/luongnv89/idd/blob/main/docs/shared-agent-conventions.md)
  and the spawn sites.
- **Codex CLI.** The path form worked mechanically in 3 of 3 runs (one
  subagent, the file read, the two observed bindings honoured) and the main
  thread wrote less. But one of three path runs missed a seeded defect, and
  total tokens did not fall in every run. With n = 3, one miss is not evidence
  of a quality loss. It still means condition (b) did not hold in every run,
  so the rule does not fire.
- **What "per host" costs.** Skill prose is host-neutral today. A per-host
  spawn form needs a way for a skill to know which host it runs on. A
  follow-up must design that. This record does not.

## 6. Limitations

- **One of four agent prompts.** Only `code-reviewer.md` was measured. The
  other three were measured in neither form. No byte-based extrapolation of
  the saving to the full 50,666 bytes is offered as a measurement.
- **Small n.** 3 runs per cell. One run decides a condition.
- **One model per host, one effort level.**
- **A tiny diff.** The subagent's own work is small next to its prompt, so the
  saving as a share of a real run will be smaller than here.
- **Headless single-step sessions, not a full `/issue-resolver` run.** In a
  real run the re-emitted prompt stays in the main agent's context and is
  re-read on every later turn. That cost is not captured.
- **Scratch path.** The agent file sat at a scratch absolute path, not a real
  install location such as a plugin cache.
- **Run-log `tokens` not used.** The field added by
  [#562](https://github.com/luongnv89/idd/issues/562) was not used because
  these were not skill runs: no `.idd/runs.jsonl` line exists for them.
- **Order and timing.** Arms were interleaved, not randomized, and the Claude
  Code pilot ran earlier than the other five Claude Code runs (§2.3).
- **Post-hoc rule.** See §5.
- **Two of nine bindings observed.** The harness observed `{diff_command}`
  (`sub_ran_bound_diff`) and `{pr_context}` (the `constraints` finding). The
  other seven (`{branch_name}`, `{base_branch}`, `{confidence_threshold}`,
  `{challenge_context}`, `{review_mode}`, `{workspace_contract}`,
  `{expected_lane_identity}`) were not individually verified in either arm on
  either host.
- **Main/sub split of output tokens on Claude Code.** The split is the host's
  `usage` against `modelUsage`. It was cross-checked on the input-side
  counters only: the stream's per-message `output_tokens` do not sum to the
  result's figure (808 against 1,560 on the pilot).
- **Codex re-emit fidelity unobservable.** See §2.4.
