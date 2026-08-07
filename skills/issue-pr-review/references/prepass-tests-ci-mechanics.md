# Pre-pass, Tests/Build, and CI Mechanics

Tool-detection tables and command details for *Step 2 — Script Pre-pass*, *Step 4 — Run Tests & Build*, and *Step 5 — Check CI Status*. SKILL.md keeps each step's intent, the security-scan contract, and the tracker output lines; this file holds the per-tool/per-system detection and commands.

## Step 2 — Script Pre-pass detection

Detect available lint/format/test tools from the project.

**When `--review-only` is set:** run the detection-only variant of this step — see *Review-only mode* in SKILL.md for the exact contract.

**Default (fix loop):** run each auto-fix command below. Capture output but don't block on warnings — only block on errors that prevent the fix from running.

| Tool type | Detection | Auto-fix command |
|-----------|-----------|-----------------|
| ESLint | `.eslintrc*` or `eslint` in package.json | `npx eslint --fix .` |
| Prettier | `.prettierrc*` or `prettier` in package.json | `npx prettier --write .` |
| Black | `pyproject.toml` with `[tool.black]` | `python -m black .` |
| Ruff | `pyproject.toml` with `[tool.ruff]` or `ruff.toml` | `ruff check --fix . && ruff format .` |
| isort | `pyproject.toml` with `[tool.isort]` | `python -m isort .` |
| gofmt | `go.mod` | `gofmt -w .` |
| rustfmt | `Cargo.toml` | `cargo fmt` |
| clang-format | `.clang-format` | `find . -name '*.c' -o -name '*.h' \| xargs clang-format -i` |

```bash
# Example for a Node.js project:
npx eslint --fix . 2>&1
npx prettier --write . 2>&1
```

Then run the project's test suite to catch failures early (before the LLM review):

```bash
# Detected test runner
npm test          # or pytest, go test ./..., cargo test, etc.
```

### Commit auto-fixes

**Not used in `--review-only`.** Run the pre-commit security scan first — `python3 references/scripts/gi-secscan.py --working-tree`, run from the repo root so it reads the repo's `security.*` extensions from `.gitissue.yml` itself (never pass a config value on the command line — this skill has a PR's branch checked out), degrading to the Primary Pattern in `references/docs/pre-commit-security.md` only when the script cannot run. Its exit 1 is a block: stop, do not commit. Only after the scan passes (or warnings are accepted — see the scan contract in SKILL.md), commit and push:

```bash
# Gated above by references/scripts/gi-secscan.py (see pre-commit-security.md).
git add -A
git commit -m "style: auto-fix lint and format issues"
git push origin {branch_name}
```

## Step 4 — Build-system detection

Detect and run the project's build system:

| Build system | Detection | Command |
|-------------|-----------|---------|
| Node.js (TS) | `tsconfig.json` | `npx tsc --noEmit` |
| Node.js (JS) | `package.json` build script | `npm run build` |
| Python | `pyproject.toml` | `python -m compileall` |
| Go | `go.mod` | `go build ./...` |
| Rust | `Cargo.toml` | `cargo build` |

Then detect and run all test types:

1. **Unit tests** — `pytest`, `npm test`, `go test ./...`, etc.
2. **Integration tests** — if integration test directory/config exists
3. **E2e tests** — if e2e framework exists (playwright, cypress, etc.)

Timeout: `review.test_timeout` seconds (default: 300).

## Step 5 — CI polling and failure extraction

Prefer the script — it performs the entire wait inside one invocation, so the
main agent spends one tool call on the answer instead of one per poll:

```bash
python3 references/scripts/gi-ci-wait.py {N} \
  --interval {review.ci_poll_interval} --timeout {review.ci_timeout}
```

It prints one JSON object. Read `verdict`:

| `verdict` | Meaning | Step 5 outcome |
|-----------|---------|----------------|
| `pass` | every check reached a terminal non-failing bucket | `✓ all checks passed` |
| `fail` | at least one check failed or was cancelled — see `failing[]` | `✗ {N} checks failed` |
| `pending` | the budget elapsed with checks still running | `⚠ checks still running` — **not clean** (see below) |
| `none` | the repository reports no checks for this PR | `○ no CI checks configured` |

Exit 3 (a non-numeric PR, a non-positive interval or timeout) is a stop — a
misconfigured wait has not run. Only a missing `python3` or exit 4 degrades:
print `⚠ gi-ci-wait unavailable — polling manually` and apply the loop below.

**Manual fallback.** Poll GitHub Actions / CI status for the PR:

```bash
gh pr checks {N} --json name,state,bucket
```

1. Check immediately after tests.
2. If checks are still running, poll every `review.ci_poll_interval` seconds.
3. Timeout after `review.ci_timeout` seconds.

On failure, extract failure details from the CI log:

```bash
gh run view {run_id} --log-failed
```

When checks are still running after `review.ci_timeout`: pending CI is **not clean** — it never satisfies soft-pass and auto mode must not merge or proceed while CI is pending (including when the fix loop finds zero fixables and would otherwise exit). In interactive mode: ask to wait more or proceed without merging. In auto mode: **do not proceed past an unresolved CI timeout** — extend polling or stop with remaining issues; do not assume a later cycle will re-check once the fix loop has already ended.
