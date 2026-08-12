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

**Not used in `--review-only`.** Run the pre-commit security scan first — `python3 references/scripts/gi-secscan.py --working-tree`, run from the repo root so it reads the repo's `security.*` extensions from `.gitissue.yml` itself (never pass a config value on the command line — this skill has a PR's branch checked out).

The full exit contract is in SKILL.md (*Step 2 — Commit auto-fixes*) and is not
optional here: **exit 1 is a block** — stop, do not commit, report the path from
`blocking[]`, never fall through to another scan. **Exit 3 is also a stop**, not
a degrade: an uncompilable `security.*` regex means the repo's own rules were
never applied, and a misconfigured scan has not run, so its silence is not a
pass. Only a missing `python3`, **exit 2** (an unresolved script path or a
malformed invocation), or **exit 4** degrades to the Primary Pattern in
`docs/pre-commit-security.md`. Only after the scan passes (or warnings are
accepted — see the scan contract in SKILL.md), commit and push:

```bash
# Gated above by references/scripts/gi-secscan.py (see pre-commit-security.md).
git add -A
git commit -m "style: auto-fix lint and format issues"
git push origin "$branch_name"   # bound in SKILL.md Step 1; never a literal ref name
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
| `pass` | every check reached a terminal non-failing bucket and the normalized check-name set settled | `✓ all checks passed` |
| `fail` | at least one check failed or was cancelled after the set settled — see `failing[]` | `✗ {N} checks failed` |
| `pending` | checks still run, or the terminal set never settled before timeout | `⚠ checks still running` — **not clean** (see below) |
| `none` | the repository reports no checks for this PR | `○ no CI checks configured` |

The waiter uses an elapsed `--settle-window` (default 30 seconds) for every
non-empty terminal snapshot. A check-name addition or removal resets that window;
this prevents a green first poll from authorizing a merge before a later failing
check registers. The explicit `--once` diagnostic mode reports one snapshot
without claiming settlement.

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

### Binding the verdict to a commit

A CI verdict is a statement about **one commit**, not about a PR. Record
`ci_sha` = the head this wait ran against — and take it from the `headRefOid`
**already in hand**, on the script path and the manual loop alike. Issue no
second `gh pr view` for it: Step 1's PR read fetched that field, and the
*Re-evaluation after a push* rule re-reads it after every push this skill makes
(Step 2's auto-fix commit as much as any fixer push), so the value held when the
wait starts is this skill's current head. `/auto-pilot`'s Step 5.1a is held to
the same rule — one widened read, no standalone `headRefOid` call — and the two
must not diverge. The one case a reused value misses is a head moved by
something other than this skill; that costs the caller a stale SHA, which
re-verifies as `absent` and re-polls, never a wrong merge. Report the outcome to
the caller as `ci_status` = `passed@<sha40>` or `failed@<sha40>`. Full
40-character SHA; the short form is display-only.

Three cases stay **bare**, with no `@` suffix, because there is no commit-bound
claim to make: `no_ci` (nothing ran), `review.check_ci: false` (nothing was
asked), and any degraded path where `headRefOid` could not be read. A bare value
is not malformed — it is simply not evidence about a particular commit, and a
caller must treat it as no evidence at all.

This changes nothing inside this skill: Step 5 still waits, still blocks on
`fail`, still refuses to treat `pending` as clean, and is **never** skipped by
anything a PR body claims. The binding exists so that a caller which has already
seen this verdict can re-verify the head cheaply rather than re-running the whole
wait — the difference between an in-process return value from a subagent this
run spawned, and a marker written into a PR body by whoever authored it. Only
the first can be re-verified against the commit it names without trusting its
author. See `/auto-pilot`'s *Step 5.1a — CI verdict gate* for the consuming side.
