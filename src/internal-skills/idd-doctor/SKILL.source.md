---
name: idd-doctor
description: "Scan an IDD repo for doc drift, missing autopilot mode, and unsafe merge defaults. Use when running idd-doctor or checking the IDD setup. Read-only. Don't use for fixing issues, normalizing issues (use /issue-creator), or non-IDD health checks."
license: MIT
compatibility: Requires git. GitHub CLI (gh) is optional — used only for the merge-strategy check; skipped when gh is absent.
metadata:
  version: 0.4.1
  author: "Luong NGUYEN <luongnv89@gmail.com>"
  effort: low
---

# /idd-doctor

Run a report-only health check on an IDD repository, surfacing doc drift on the intent-code boundary, unsafe configuration, and merge defaults that conflict with IDD conventions.

**Invocation:** `/idd-doctor` — no arguments.

## When to Use

- **Do** run it before landing a change to `src/skills/issue-creator/` README/SKILL text or the issue templates.
- **Do** run it after `/init-gitissue`, to confirm the generated config sets `autopilot.mode`.
- **Do** wire it into pre-merge or pre-release checks.
- **Avoid** running it as a fix tool — v1 is **report-only**: no file modified, no issue commented on, no PR created.
- **Never** treat its output as a substitute for code review; it catches only the four classes of drift below.

## Scope (v1)

The doctor performs exactly four **gating checks** (each PASS / WARN / FAIL), then
one **informational, non-gating** section — the *run-log summary* — reporting
`.gitissue/runs.jsonl` telemetry that never affects the result. Anything beyond
those is **out of scope**:

| # | Check | What it verifies | Failure mode |
|---|-------|-----------------|--------------|
| 1 | Stale skill claims | The `/issue-creator` README and SKILL text make no claim that the skill inspects code (Check 1 lists the files and the forbidden phrases). | `FAIL` |
| 2 | Issue-template fields | No issue template asks the reporter for resolver-owned content (Check 2 lists the directories and the forbidden labels). | `FAIL` |
| 3 | Autopilot mode set | `.gitissue.yml`, if present in the repo root, carries an `autopilot.mode` key. | `FAIL` (only when `.gitissue.yml` exists) |
| 4 | Squash-merge default | Squash is the only merge strategy allowed **and** the squash message source is the PR body (SPEC §4.3 B1). | `WARN` |

### Explicitly out of scope for v1

`gh` authentication checks; full schema validation of `.gitissue.yml`; stale-triage detection; PR-format checks; commit-message linting; README link validation; and autofix of any kind.

## Prerequisites

Before any check, verify the environment. On failure, print the exact error from `references/error-messages.md` and stop.

1. Confirm git repository: `git rev-parse --git-dir`. On a non-zero exit, print *Not a git repository*.
2. Confirm the repo root is readable: `ls -a .`. On a non-zero exit, print *Could not read repo root*.

`gh` is **optional**: Check 4 needs it plus authentication, and skips with an `○` note rather than failing the run when either is absent.

### Bundled dependency precheck

Verify this skill's bundled reference files are present. If any is missing, stop immediately and print:

```text
✗ Missing bundled dependency: {missing_file}

  /idd-doctor is a repo-internal skill (not installed via asm/npx — see README).
  To fix:  from a clone of https://github.com/luongnv89/idd, run
           ./scripts/build.sh to regenerate the bundled references,
           then load internal-skills/idd-doctor/ and run /idd-doctor.

  Then restart the agent session and re-run /idd-doctor.
```

That stop is a terminal outcome: print the block, then the *Run Stats Footer* (`references/run-stats.md`), then stop. It runs before the clock capture in *Pipeline*, so there is no `run_started_epoch` and `elapsed` prints the literal `n/a`, with `agents 0`. If `references/run-stats.md` is itself the missing file, print those two lines from the shape in *Run stats footer*.

Check these, relative to this SKILL.md's directory:

- `references/error-messages.md`
- `references/review-contract.md`
- `references/run-log-summary.md`
- `references/run-stats.md`

## Configuration

This skill **reads** `.gitissue.yml` only to determine whether Check 3's `autopilot.mode` is set (that field is documented in `docs/config-schema.md`); it is otherwise config-free, with no `doctor:` section and no per-check toggles in v1.

If `.gitissue.yml` does **not** exist, Check 3 skips rather than fails (see *Check 3*) — a repo that has not yet run `/init-gitissue` is not punished for it.

---

## Pipeline

The doctor executes the four checks in order — one line each, then a summary footer, then the informational *Run-log summary*. Checks never short-circuit: every one runs even after a `FAIL`, so the operator sees the full picture in one pass. Each check prints its outcome line, findings, and fix hint exactly as `references/error-messages.md` gives them under that check's heading; the sections below define only *when* each outcome applies.

**Capture the run clock before Check 1** — one `date +%s`, kept as `run_started_epoch`; the *Run Stats Footer* (`references/run-stats.md`) measures `elapsed` from it. Reading a clock is not a repo mutation, so it stays inside the *Read-only guarantee*.

Expected output for a clean repo (verify against this when testing):

```
  ◆ /idd-doctor — health check
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

    ● [1/4] Stale skill claims...
    ✓ [1/4] Stale skill claims    no stale language in /issue-creator

    ● [2/4] Issue-template fields...
    ✓ [2/4] Issue-template fields no forbidden fields in M templates

    ● [3/4] Autopilot mode...
    ✓ [3/4] Autopilot mode        autopilot.mode = conservative

    ● [4/4] Squash-merge default...
    ✓ [4/4] Squash-merge default  squash-only · squash message source PR_BODY

    ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    Result: PASS  (4 checks, 0 failed, 0 warned)
    Evidence:    ran 1 2 3 4 · scanned 2 skill files, M templates
    Uncertainty: checks 1-3 are text heuristics
    Decision:    No approval needed — report-only, nothing changed. Next: none
```

The run-log summary and the run-stats footer follow that block.

**Exit codes** (when invoked from a script wrapper):

| Result | Exit | When |
|--------|------|------|
| `PASS` | 0 | No `FAIL` and no `WARN`; a skipped check counts as neither |
| `WARN` | 0 | At least one `WARN`, no `FAIL` |
| `FAIL` | 1 | At least one `FAIL` |

The skill runs inside an agent, so there is no real exit code. A wrapper script greps the `Result:` line instead, so that line MUST carry `PASS`, `WARN`, or `FAIL` as the first word after `Result:`. Lines printed after it never carry a status word in that position.

---

## Check 1 — Stale skill claims

Scan the `/issue-creator` skill's `README.md` and `SKILL.md` for stale claims about its own scope. The forbidden patterns describe the **old** behavior where the creator allegedly inspected the codebase; the intent-only contract (SPEC.md §1.2 intent–code boundary) forbids them.

### What to scan

```
src/skills/issue-creator/docs/README.md
src/skills/issue-creator/SKILL.source.md
```

These two are the only files in scope. Other skills (`/issue-analysis`, `/init-gitissue`, `/auto-pilot`, etc.) legitimately scan code, so flagging them would be a false positive. Do **not** scan `references/`, `templates/`, `docs/`, the top-level `README.md`, or another skill's files. Add a future intent-only skill's files here explicitly; mechanical "scan all skills" matching is deliberately avoided in v1.

### Forbidden patterns (case-insensitive substring match, with surrounding negation)

A line **fails** if it contains any pattern below **and** no negation marker (`no`, `not`, `never`, `does not`, `doesn't`, `without`, `cannot`, `won't`).

| Pattern | Why it's forbidden |
|---------|-------------------|
| `scans the codebase` / `scan the codebase` | `/issue-creator` does not scan code |
| `predicts affected files` / `predict affected files` / `predicted affected files` | `/issue-creator` does not predict file paths |
| `generates implementation notes` / `generate implementation notes` / `generated implementation notes` / `generates technical notes` / `generated technical notes` | `/issue-creator` does not produce implementation guidance |
| `generates root cause` / `provides root cause` | Bug root-cause analysis is the resolver's job |
| `generates implementation hints` / `provides implementation hints` | Implementation hints belong in the resolver |

The negation guard exists so a line like *"the issue-creator skill **does not** scan the codebase"* is not flagged as drift — that file is correctly stating the contract.

### Pattern match algorithm

1. Read each file in scope.
2. For each line, lowercase-compare against each forbidden pattern.
3. If a pattern matches, scan the same line for any negation marker (case-insensitive).
4. If no negation marker is present on that line, record a finding `{file, line_number, pattern, snippet}`.

The negation check is **per-line**: a negation in a separate paragraph does not absolve a later positive claim.

### Outcome

- **Pass** — no finding in either file.
- **Fail** — at least one finding. Print the fail line, one per-finding block (`{path}:{line_number}`, `pattern:`, `line:`) per finding, then the fix hint once. A file in scope that does not exist is one finding: `{path} not found`.

---

## Check 2 — Issue-template fields

Scan issue-template files for field labels asking the reporter (or normalizer) for content the IDD methodology forbids: predicted affected files, generated technical notes, root cause, or implementation hints.

### What to scan

```
src/skills/issue-creator/templates/*.md
.github/ISSUE_TEMPLATE/*.md     # only if the directory exists
.github/ISSUE_TEMPLATE/*.yml    # GitHub form templates
.github/ISSUE_TEMPLATE/*.yaml
```

### Forbidden field labels (case-insensitive substring match)

| Pattern | Why it's forbidden |
|---------|-------------------|
| `affected files` | predicting them is the resolver's job |
| `predicted affected files` | same |
| `technical notes` (also matches a `## Technical Notes` header) | generated technical notes belong in the resolver, not the issue |
| `root cause` | root-cause analysis is the resolver's job |
| `implementation hints` | they belong in the resolver |
| `implementation notes` | same |
| `architecture constraints` | they belong in analysis/resolver output, not a template |

The match is **substring**, case-insensitive; a literal `Affected Files:` in a template body counts. Do **not** apply Check 1's negation guard here — templates carry field labels, not prose, so a field named "Affected Files" is unambiguous drift whatever surrounds it.

### Match algorithm

Check 1's *Pattern match algorithm* without its negation steps: every matching line records a finding `{file, line_number, pattern, snippet}`.

### Outcome

- **Pass (no templates)** — no file matches any glob above. Nothing was scanned, so `Evidence` reports `0 templates`.
- **Pass** — every scanned template is clean.
- **Fail** — at least one finding. Print the fail line, one per-finding block per finding (Check 1's format), then the fix hint once.

---

## Check 3 — Autopilot mode

Verify that `.gitissue.yml`, when present, sets `autopilot.mode`. That key makes the conservative-merge default reachable; without it, legacy `auto_merge` falls back to the old aggressive behavior in some code paths.

### Procedure

1. Check whether `.gitissue.yml` exists in the repo root. If not, skip with `○ [3/4] Autopilot mode        skipped — no .gitissue.yml`.
2. Read the file as text — no YAML parser required; a regex check suffices and adds no dependency. If the file exists but cannot be read, print the *Fail (unreadable)* line and go to Check 4.
3. Look for a line matching `^[[:space:]]+mode:[[:space:]]*[^#[:space:]]+` inside an `autopilot:` block. Any non-empty value matches; the value is not validated in v1. Equivalent shell heuristic:

   ```bash
   awk '/^autopilot:/{f=1;next} /^[^[:space:]#]/{f=0} f' .gitissue.yml | grep -E '^[[:space:]]+mode:[[:space:]]*[^#[:space:]]+'
   ```

4. If a line matches, the check passes; capture the value for the pass line.
5. If no line matches, the check fails; print the fail line and its fix hint.

---

## Check 4 — Squash-merge default

Verify the repository's merge configuration carries the SPEC §4.3 **B1** binding: squash is the only strategy, **and** the squash commit message is the PR body. IDD uses one-commit-per-PR semantics, so any non-squash strategy is a footgun — and a squash-only repo still defeats B1 if `squash_merge_commit_message` is GitHub's default `COMMIT_MESSAGES`, which writes the commit subjects and drops the Decision Record at the merge boundary. SPEC §4.3 requires warning at **both** levels, and forbids reporting the binding satisfied on the strategy alone or when the configuration cannot be read.

### Procedure

1. Confirm `gh` is on `PATH` and authenticated.
   - If `gh` is missing: skip with `○ [4/4] Squash-merge default  skipped — gh not installed`.
   - If `gh auth status` fails: skip with `○ [4/4] Squash-merge default  skipped — gh not authenticated`.
2. Read the **strategy**:

   ```bash
   gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed
   ```

   If this call fails (for example, no GitHub remote), skip with `○ [4/4] Squash-merge default  skipped — repo settings unreadable` and stop the check; nothing was read, so nothing is claimed.
3. Read the **message source** — a second, separate call. It is not a `gh repo view` field (`gh repo view --json squashMergeCommitMessage` fails with `Unknown JSON field`), so read the REST API:

   ```bash
   gh api repos/{owner}/{repo} --jq '{squash_merge_commit_title,squash_merge_commit_message}'
   ```

4. Parse both. The check **passes** iff:

   ```
   squashMergeAllowed == true
     AND mergeCommitAllowed == false
     AND rebaseMergeAllowed == false
     AND squash_merge_commit_message == "PR_BODY"
   ```

5. If step 2 succeeded but step 3 did not — a 404, a token lacking permission, an absent field — the message source is **unknown**. Print the *Warn — message source unreadable* line, which ends `binding unverified`. Never pass: an unread configuration is not a satisfied binding (SPEC §4.3). A missing or unauthenticated `gh` still **skips** (step 1): a skip claims nothing about the binding, which is not the same as claiming it holds.
6. Otherwise, **warn** (not fail) with `⚠ [4/4]` and the fix hint — repo settings are owner-controlled and the doctor only nudges. Build `{summary}` from the strategy and message-source tables in `references/error-messages.md`.

---

## Summary footer

After all four checks, print the separator, then `Result: {RESULT}  ({total} checks, {failed} failed, {warned} warned)` — `{RESULT}` per the exit-code table, `{total}` always 4. Then print the `Evidence`, `Uncertainty`, and `Decision` rows from `references/review-contract.md`, which also holds the format rule for a requested Markdown or JSON report. The exact layouts are under *Summary footer* in `references/error-messages.md`.

---

## Run-log summary (informational, non-gating)

After the summary footer, print a short **run-log summary** over the last N runs
in `.gitissue/runs.jsonl` — the cross-run `monitoring` signal (resolve rate, QA
effort, recurring skip reasons) the per-run output otherwise forgets. It is
**informational only**: it never changes the PASS/WARN/FAIL result, has no exit
code, and (like every part of this skill) is strictly **read-only** — it reads
`runs.jsonl` and writes nothing.

The schema is `docs/run-log-schema.md` (*`.gitissue/runs.jsonl` — run log*): one
JSON object per line carrying at least `ts`, `issue`, `mode`, `outcome`, and
`pr`, plus optional `qa_cycles`, `skipped_reason`, `agent_overrides` and `phases`.

### Procedure

1. If `.gitissue/runs.jsonl` does **not** exist or is empty, **degrade gracefully**
   — print `○ Run-log summary           no runs recorded yet (.gitissue/runs.jsonl)`
   and stop the section. Absence is never a failure.
2. Otherwise take the **last N** lines (default `N = 50`). That cap bounds the
   agent's context budget — never load a long-lived repo's whole log into the
   context window. Tolerate malformed lines: skip any that is not valid JSON
   rather than aborting the summary, and count them as `{m}`.
3. Compute the five metrics — resolve rate, median QA cycles, common skip
   reasons, agent overrides, slowest phase — and print the section, both
   exactly as `references/run-log-summary.md` defines them. When a
   `.gitissue/improvement-proposals.jsonl` ledger exists, that reference's
   optional *Skill improvements* line also reports pending correction-guard
   proposals (issue #524) — still informational, still read-only.

---

## Run stats footer

After the run-log summary, close with the *Run Stats Footer* — `references/run-stats.md` — `elapsed`, `tokens` only where the host reported a count (otherwise left out), `agents`, run cost only, `n/a` for anything else undetermined. It is the last thing printed at **every** terminal outcome, including a run that never reached Check 1: not a git repository, an unreadable repo root, or a missing bundled dependency. A missing `/issue-creator` or an unreadable `.gitissue.yml` is a check finding, not a stop. The doctor spawns no subagents, so `agents 0` is the determined value here, not `n/a`. It reports the run's own cost and never a metric a check already printed.

---

## Read-only guarantee

The skill MUST NOT modify any file in the repo, create branches, commits, tags, or PRs, edit issue bodies or post comments, or mutate `.gitissue.yml` or any config file.

It reads files (via `Read` / `cat`) and runs read-only `gh` queries (`gh repo view --json …`, `gh api repos/{owner}/{repo}`, `gh auth status`). Test fixtures (see *Testing*) assert the working tree is unchanged after a doctor run.

---

## Testing

`tests/test-idd-doctor.sh` (pure bash, exit 0 on pass) asserts this spec against itself — structure, both pattern catalogs, check order, read-only guarantee, `gh` field selections, skips, exit codes, and the run-log summary. Run `bash tests/test-idd-doctor.sh`. Those assertions check correctness only; grade a real report's readability against the *Understanding criteria* in `references/review-contract.md`.

---

## Output Conventions

Terminal output follows the `DESIGN.md` contract (repo root) — symbols `● ✓ ✗ ◆ ⚡ ⚠ ○`, two-space indent, `┄` separators, URLs on their own line, ≤80 chars, one blank line between sections, static sequential output (no animation). Per-check line: `{symbol} [N/4] {Check name (16 chars)} {detail}`; per-finding indent 8 spaces (4 + 4). Errors use the rich format from `references/error-messages.md`: `✗ what failed`, `To fix:  <command>`, then a docs link when applicable. This terminal layout is the default; a requested Markdown or JSON report follows the *Format rule* in `references/review-contract.md`.

## Edge Cases

- **`.gitissue.yml` has no `autopilot:` section** — Check 3 fails with the standard fix hint.
- **`autopilot.mode` set to a non-canonical value** (e.g. `mode: yolo`) — Check 3 still passes; any non-empty value satisfies "key set", and a future v2 may validate values.
- **A skill README carries a forbidden pattern inside a code block or fenced quote** — Check 1 still flags it; v1 is mechanically strict, not contextually nuanced.
- **GitHub Enterprise repos without `gh` auth** — Check 4 is skipped, never failed.
- **`/issue-creator` is missing** — Check 1 fails with a `src/skills/issue-creator/docs/README.md not found` finding; that skill is required in an IDD repo.
