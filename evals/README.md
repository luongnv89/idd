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
```

Requirements: `python3`, `bash`, `git`. **No** `gh` auth, **no** network, **no**
real GitHub repository.

## Layout

```
evals/
  harness/
    gh_shim.py      # PATH-fronted `gh` record/replay (stdlib)
    run_eval.sh     # case runner: seed env, PATH shim, subject, grade
    grade.py        # idd-lint + gi-runlog assertions
  cases/
    <skill>/
      <case-name>/
        case.json       # prompt metadata + grade assertions
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
| `shell` | hermetic `bash -c` check (rare) |

`expect_exit` is compared to the tool's exit code. Negative cases set
`expect_exit: 1` (e.g. unstructured body fails lint).

## Adding a case

1. Create `evals/cases/<skill>/<case-name>/` with `case.json`, `cassettes.json`,
   `subject.sh`.
2. Write a **deterministic** subject: fixed inputs → fixed artifacts under
   `$EVAL_OUT`. Prefer skill stand-ins over invoking the agent.
3. Grade with idd-lint / gi-runlog only.
4. Add or extend `tests/test-eval-<skill>.sh` to call `run_eval.sh`.
5. Ensure the test script is a named step in
   `.github/workflows/dist-check.yml` (T9 in `test-build-script.sh` enforces this).

### Growth target

Aim toward **≥5 prompts per skill**, including **negative-trigger** cases (empty
body, missing `Closes #N`, non-conventional branch, invalid run-log record).
Today's floor ships creator (2), resolver (1), pr-review (2) plus harness unit
tests.

## Hermeticity rules

- Never require network or `gh auth`.
- Subjects use only PATH-shimmed `gh`, local files, `python3`, and `git`.
- Never enable `EVAL_RECORD` in tests or CI.
- No secrets in fixtures or cassettes.
