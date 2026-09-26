# Behavioral eval harness

Hermetic, network-free behavioral evaluations for gitissue skills. Cases run a
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
- Data-producing commands (`issue view/list`, `pr view/list`, `pr checks`, `api`)
  **require `--json`** — the shim exits 2 without it (enforces
  [docs/platform-github.md](../docs/platform-github.md)).
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

## Adding a case

1. Create `evals/cases/<skill>/<case-name>/` with `case.json`, `cassettes.json`,
   `subject.sh`.
2. Write a **deterministic** subject: fixed inputs → fixed artifacts under
   `$EVAL_OUT`. Prefer skill stand-ins over invoking the agent.
3. Grade with idd-lint / gi-runlog / gh-calls only.
4. Add or extend `tests/test-eval-<skill>.sh` to call `run_eval.sh`.
5. Ensure the test script is a named step in
   `.github/workflows/dist-check.yml` (T9 in `test-build-script.sh` enforces this).

### Growth target

Aim toward **≥5 prompts per skill**, including **negative-trigger** cases (empty
body, missing `Closes #N`, non-conventional branch, invalid run-log record).
Today's floor ships creator (2), resolver (2), pr-review (2), triage (1) and
auto-pilot (1), plus harness unit tests.

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

## Hermeticity rules

- Never require network or `gh auth`.
- Subjects use only PATH-shimmed `gh`, local files, `python3`, and `git`.
- Never enable `EVAL_RECORD` in tests or CI.
- No secrets in fixtures or cassettes.
