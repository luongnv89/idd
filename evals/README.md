# Behavioral eval harness

Hermetic, network-free behavioral evaluations for IDD Stack skills. Cases run a
**deterministic subject** (a skill stand-in that produces the same artifacts the
real skill should) under a PATH-fronted `gh` record/replay shim, then grade
outputs with **idd-lint** and **gi-runlog** — not prose greps of skill source.

## Quick start

From the repo root:

```bash
# One case
bash evals/harness/run_eval.sh evals/cases/issue-creator/basic

# CI entrypoints (also wired in .github/workflows/dist-check.yml)
bash tests/test-eval-harness.sh
bash tests/test-eval-creator.sh
bash tests/test-eval-resolver.sh
bash tests/test-eval-pr-review.sh
bash tests/test-eval-plan-to-issues.sh
bash tests/test-eval-triage-autopilot-357.sh
bash tests/test-cost-counters-465.sh
```

Requirements: `python3`, `bash`, `git`. **No** `gh` auth, **no** network, **no**
real GitHub repository.

## Layout

```
evals/
  harness/
    gh_shim.py      # PATH-fronted `gh` record/replay (stdlib)
    run_eval.sh     # case runner: seed env, PATH shim, subject, grade
    grade.py        # idd-lint + gi-runlog + gh-calls assertions
    agent_eval.py   # opt-in real-agent promotion lane (never in CI)
  promotion/
    lock.json       # committed digests of held-out tasks + private rubrics
    private/        # gitignored store: tasks, rubrics, runs, sealed keys
  cases/
    <skill>/
      <case-name>/
        case.json       # prompt metadata + grade assertions (+ optional repo_scripts)
        cassettes.json  # canned gh argv → stdout/stderr/exit
        subject.sh      # deterministic skill stand-in
        expected/       # optional fixtures / notes
```

## Cassette format

```json
{
  "version": 1,
  "calls": [
    {
      "argv": ["issue", "view", "1", "--json", "number,title,body,state"],
      "stdout": "{\"number\":1,...}\n",
      "stderr": "",
      "exit": 0
    },
    {
      "match": "prefix",
      "argv": ["auth", "status"],
      "stdout": "github.com\n  ✓ Logged in\n",
      "exit": 0
    }
  ]
}
```

- **Exact** argv match is preferred; `"match": "prefix"` matches a leading prefix.
- Comma-separated `--json` field lists are compared after sorting field names.
- Data-producing commands (`issue view/list`, `pr view/list`, `pr checks`)
  **require `--json`** — the shim exits 2 without it (enforces
  [docs/platform-github.md](../docs/platform-github.md)).
- `gh api` is exempt: the real `gh api` has no `--json` and selects fields with
  `--jq`. `--jq` and `--paginate` are plain argv tokens for matching, and an
  `api` cassette's `stdout` is the post-`--jq` text.
- `issue create` may be cassettes or allocated via `EVAL_STATE_DIR`.

### Environment

| Variable | Role |
|----------|------|
| `EVAL_CASSETTES` | Path to `cassettes.json` (set by `run_eval.sh`) |
| `EVAL_STATE_DIR` | Mutable state for sequential issue IDs |
| `EVAL_OUT` | Artifact directory written by `subject.sh` |
| `EVAL_GH_CALL_LOG` | When set, the shim appends one `{"argv": [...]}` line per invocation — the normalized argv only, no time, pid or path — before any dispatch, so help, version and refused calls count too. `run_eval.sh` sets it to a harness-owned file outside `OUT`, creates it empty before the subject runs, and publishes it as `OUT/gh-calls.jsonl` afterwards. Unset, the shim writes nothing. |
| `EVAL_SCRIPTS_DIR` | Directory holding the case's `repo_scripts` copies (empty when the case lists none) |
| `EVAL_RECORD=1` | **Local capture only** — runs real `gh` and appends. **Forbidden in CI**; `run_eval.sh` fails closed if set. |

## Grading

`case.json` `grade` is a list of assertions:

```json
{
  "tool": "idd-lint",
  "args": ["issue", "OUT/issue.md"],
  "expect_exit": 0,
  "label": "normalized issue body passes idd-lint"
}
```

| tool | meaning |
|------|---------|
| `idd-lint` | `python3 scripts/idd-lint.py <args>` (`OUT` → artifact dir) |
| `gi-runlog-echo` | `python3 src/shared/scripts/gi-runlog.py --echo < file` |
| `file-exists` | artifact path must exist |
| `red-green` | red→green evidence JSON has exactly `red_exit: 1`, `green_exit: 0` |
| `shell` | hermetic `bash -c` check (rare) |
| `gh-calls` | the shim's call log (`file`, default `OUT/gh-calls.jsonl`) matches every expectation given: `expect_count` (exact total), `expect_by_command` (exact count per first-two-token command, e.g. `{"issue view": 3}`), `expect_argv` (exact normalized argv sequence). A missing log always fails. |

`expect_exit` is compared to the tool's exit code. Negative cases set
`expect_exit: 1` (e.g. unstructured body fails lint).

## Running real repo scripts

A case may exercise a shared script itself instead of a stand-in by listing it
in `case.json`:

```json
"repo_scripts": ["src/shared/scripts/gi-issue.py", "src/shared/scripts/gi-gh.py"]
```

`run_eval.sh` accepts only regular files named
`src/shared/scripts/<lowercase-hyphen>.py`, rejects anything else (traversal,
symlinks, other directories) with exit 2 before any subject runs, and
**copies** the files into `$EVAL_SCRIPTS_DIR`, so the subject still never
reaches the checkout. List every sibling a script loads (`gi-issue.py` needs
`gi-gh.py`).

## Cost counters (#465)

`issue-resolver/gh-call-counter` runs the real `gi-issue.py` through the shim in
the resolver's read pattern — miss, TTL hit, invalidate, miss, `--refresh` — and
grades the call log at exactly 3 `gh` calls, the same on every run.
`python3 scripts/idd-cost-counters.py calls <log>` summarizes any call log; its
`evidence` subcommand is the offline transcript miner behind the decision to
adopt this counter provisionally: the exact count is a deterministic regression
check, not a validated cost counter, because the evidence was measured on
agent-issued `gh` calls and this case counts script-issued ones. Method, raw
numbers and verdicts are in
[docs/experiments/cost-counters-465.md](https://github.com/luongnv89/idd/blob/main/docs/experiments/cost-counters-465.md).

## Safety-gate fixtures (#518, #519)

Two resolver cases exercise the real gate scripts on fixture repositories.
`issue-resolver/sensitive-change-tiny` runs `gi-sensitive.py` on a one-line
auth change. The change triggers the gate. A lone challenger blocker at
confidence 15 stops it, a `file:line` rebuttal the script verifies closes it,
and an uncited rebuttal does not. `issue-resolver/third-failure-premise-reset`
runs `gi-premise.py`. Two fixes that fail under one premise block the third
fix. A diagnostic that the subject reruns for real, and whose rerun matches
its record, lifts the block. A mismatched rerun leaves the block in place.

## Adding a case

1. Create `evals/cases/<skill>/<case-name>/` with `case.json`, `cassettes.json`,
   `subject.sh`.
2. Write a **deterministic** subject: fixed inputs → fixed artifacts under
   `$EVAL_OUT`. In this hermetic lane, stand-ins are the rule: no case
   invokes a real agent. Real-agent behavior is measured in the
   [promotion lane](#promotion-lane-real-agent-opt-in) below.
3. Grade with idd-lint / gi-runlog / gh-calls only.
4. Add or extend `tests/test-eval-<skill>.sh` to call `run_eval.sh`.
5. Ensure the test script is a named step in
   `.github/workflows/dist-check.yml` (T9 in `test-build-script.sh` enforces this).

### Growth target

Aim toward **≥5 prompts per skill**, including **negative-trigger** cases (empty
body, missing `Closes #N`, non-conventional branch, invalid run-log record).
Today's floor ships creator (2), resolver (2), pr-review (3), triage (1),
auto-pilot (1) and plan-to-issues (2), plus harness unit tests.

### Cases on a host without a sandbox

`run_eval.sh` fails closed when the host has no OS-level network sandbox, so a
developer machine without Linux user+network namespaces cannot execute a
subject. `tests/test-eval-triage-autopilot-357.sh` shows the pattern that keeps
such cases covered anyway: assert the case manifest, replay the cassettes
through `gh_shim.py` directly, cross-check the case's expected answers against
the repo's own deterministic tools (`gi-triage-graph.py`, `gi-deps.py`), and run
`subject.sh` + `grade.py` in a disposable directory. Those checks are
host-independent; the sandboxed `run_eval.sh` run stays the authoritative one
and is required in CI via `IDD_EVAL_REQUIRE_SANDBOX=1`. **Never** relax the
sandbox gate in `run_eval.sh` to make a case runnable.

## Promotion lane (real agent, opt-in)

Stand-ins prove the artifacts a skill *should* produce. Whether a real agent
following a changed `skills/` tree behaves better is a different question, and
`evals/harness/agent_eval.py` answers it. It compares a **baseline** and a
**candidate** revision on held-out tasks graded blind against private rubrics.

It lives outside `run_eval.sh` on purpose. A real agent needs its model
provider's network, which the sandbox exists to deny. `run_eval.sh` also copies
the whole case, grading spec included, into the workspace, so a capable agent
could read its own answer key. The lane is **never run in CI**: `run` exits 2
when `CI` or `GITHUB_ACTIONS` is set, when `IDD_EVAL_AGENT=1` is missing, and
when `EVAL_RECORD=1` is set. `tests/test-eval-promotion-517.sh` drives it with a
stub agent, so CI covers the driver without starting a model.

**Store.** Held-out material never enters the repository. The default store is
the gitignored `evals/promotion/private/`, or `$IDD_PROMOTION_STORE` / `--store`.

| Path | Format |
|------|--------|
| `tasks/<id>/task.json` | `{"version": 1, "id", "skill", "prompt", "min_runs": 3}`: the only text the agent sees |
| `tasks/<id>/cassettes.json`, `fixture_repo/` | optional `gh` replay cassettes and workspace seed |
| `rubrics/<id>.json` | `{"version": 1, "task_id", "canary" (≥16 chars), "criteria": [{"id", "text"}], "checks": [grade.py assertions], "pass_threshold": 1.0, "min_pass_rate": 0.5}` |
| agent config (anywhere) | `{"command": [argv with {prompt_file} {workspace} {skills_dir} {out_dir}], "model", "cli", "cli_version", "tools": [...], "pass_env": [names]}` |

**Lock.** `agent_eval.py lock --task-id <id>` writes the task-tree and rubric
digests into the committed `evals/promotion/lock.json`, which publishes the
commitment and keeps the content private. `run` refuses a task that is not
locked, or whose task or rubric changed since it was locked. It also refuses a
dirty tree (exit 4), so the lock it reads is the committed one.

**Leakage checks.** Before any agent starts, `run` exits 3 when either arm's
`skills/` contains the rubric canary or any 8-word shingle of the task prompt
(the held-out check). It also exits 3, naming the criterion and the file, when
a criterion shares an 8-word shingle with either arm's `skills/`. An agent
quoting its own skill would otherwise trip the post-run check for certain, so
rephrase the criterion. It also exits 3 when the staged prompt, fixture or
cassettes carry the canary, an 8-word shingle of any criterion, or a
byte-for-byte rubric copy (the staging check). After each run, before its root
is removed, it scans every regular file under that root (workspace, `HOME`,
`gh` state, `out/`, the call log, the transcripts and the skills copy) for the
canary, and the transcripts, the call log and every `out/` file for criteria
shingles. Files are streamed, so size is no limit, and an unreadable file
counts as a leak. Compressed git objects are not decoded. A hit marks the run
`leak`.

**Blinding.** Runs are shuffled by a sealed seed under random blind ids. Each
run gets its own fresh `idd-agent-*` root in the system temp dir, outside the
store and the repo, so no private rubric sits a few `..` above its cwd. The
root holds only that run's stage, its own arm's `skills/` (extracted from git
for that run) and the `gh` shim, under names that are the same for every run.
It is copied into `runs/<id>/raw/<bid>/` and removed before the next run
starts, so no run can reach an earlier run's transcript or the other arm's
skills through it. The pre-run scan's extract of both arms is removed before
the first agent starts. The agent is not sandboxed, though: it can still read
the repository's git history, so the lane assumes an agent that follows its
skills rather than a hostile one. Every staged file and directory, and the
fixture's commit, carries one fixed timestamp, so mtimes do not reveal the arm.
Each `blind/<bid>/` packet holds scrubbed transcripts, the call log, text
`out/` files and `criteria.json` (ids and text only, with no canary and no
checks). Packets are written in sorted blind-id order and `blind/` is stamped
with one fixed mtime, so creation order says nothing about run order.
Scrubbing redacts both arms' SHAs and skills trees (with 7–12 character
prefixes) and every temp and run path anywhere, refs only as whole words (a
ref `main` leaves `domain` alone), and the words *baseline* and *candidate*.
The arm mapping is sealed in `sealed/key.json`, and provenance records its
digest. The seed and the run order are sealed in `sealed/order.json`, and
provenance records only `runs.seed_sha256`, a salted commitment to the seed.
Replaying the seed against the run order would unblind every packet. Omit
`--seed` (provenance's `runs.seed_supplied` says whether you passed one) when
the operator also grades. **Graders open `blind/` only**: `raw/`, `checks/`,
`sealed/` and the `run` command's stderr are for the operator and the verdict.
A run gets one verdict: re-scoring after the key is unsealed would show which
arm each blind id belongs to, so a second `verdict` exits 3.

**Grading and verdict.** The rubric's `checks` run per run through `grade.py`,
which grades the objective part. Graders fill `blind/scores.template.json` with
`true`/`false` per criterion. A run passes when the agent exited 0, its checks
passed, it did not leak, and its true fraction is at least `pass_threshold`. The
verdict is `invalid` if any run leaked, `insufficient` below the task's
`min_runs`, `reject` if the candidate's pass rate is below the baseline's,
`promote` if it is at least the baseline's and at least `min_pass_rate`, and
`hold` otherwise.

**Provenance.** `provenance.json` uses `gi-receipt.py`'s field names (`sha`,
`clean_tree`, `executor`, `artifacts` as `{path, sha256, bytes}`,
`written_at`). The driver measures the repository HEAD, each arm's `sha` and
`skills_tree`, the harness file digests, the task, rubric and lock digests, the
seed commitment and the run counts. Under `agent.declared` it records what the
operator *declares*: model, CLI, CLI version and tools. The driver cannot verify these.
`verify --run-dir D` re-hashes every listed artifact and the sealed key, and
checks the sealed seed against its commitment.

**Operator procedure.**

```bash
export IDD_EVAL_AGENT=1                       # explicit opt-in, local only
A=evals/harness/agent_eval.py
python3 $A lock --task-id <id>                # author task + rubric privately first
git add evals/promotion/lock.json && git commit -m "chore(evals): lock <id>"
python3 $A run --task-id <id> --baseline main --candidate <branch> \
  --agent-config ~/agent.json                 # prints run_dir + scores template
# graders fill blind/scores.template.json and open nothing but blind/
python3 $A verdict --run-dir <run_dir> --scores scores.json
python3 $A verify --run-dir <run_dir>
```

The agent runs with an isolated `HOME`, `gh` config, `TMPDIR`,
`XDG_CACHE_HOME` and `XDG_CONFIG_HOME`, all inside its run root, so nothing is
shared through the system `/tmp` and the post-run scan sees what it writes
there. A PATH-fronted `gh_shim.py` replays the task's cassettes. Only the
variables named in `pass_env` come from your environment, and GitHub tokens,
`EVAL_*`, `IDD_*` and the variables the driver sets itself are refused there.
A socket, FIFO or device the agent leaves behind is not copied into `raw/`;
the run's sealed record lists it under `skipped`. Pass the model credentials your CLI needs this way. The
command must print the full session, tool calls included, on stdout or stderr,
for example through a streaming or verbose JSON output mode. Leak detection and
grading see nothing else.

Exit codes: `0` ok (an agent's own non-zero exit is data) · `2` usage or
refused · `3` invalid input, pre-run leak or a second verdict · `4` cannot
complete.

## Hermeticity rules

- Never require network or `gh auth`.
- Subjects use only PATH-shimmed `gh`, local files, `python3`, and `git`.
- Never enable `EVAL_RECORD` in tests or CI.
- No secrets in fixtures or cassettes.
