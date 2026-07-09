---
name: idd-doctor
description: "Scan an IDD repo for doc drift, missing autopilot mode, and unsafe merge defaults. Use when running idd-doctor or checking the IDD setup. Read-only. Don't use for fixing issues, normalizing issues (use /issue-creator), or non-IDD health checks."
license: MIT
compatibility: Requires git. GitHub CLI (gh) is optional — used only for the merge-strategy check; skipped when gh is absent.
effort: low
metadata:
  version: 0.2.0
  author: Luong NGUYEN <luongnv89@gmail.com>
---

# /idd-doctor

Run a report-only health check on an IDD repository. Surfaces doc drift on the intent-code boundary, unsafe configuration, and merge defaults that conflict with IDD conventions.

**Invocation:** `/idd-doctor` — no arguments.

## When to Use

- **Do** run this skill before landing any change that touches `src/skills/issue-creator/` README/SKILL text or the issue templates.
- **Do** run it after `/init-gitissue` to confirm the generated config sets `autopilot.mode`.
- **Do** wire it into pre-merge or pre-release checks.
- **Avoid** running it as a fix tool — v1 is **report-only**. No files are modified, no issues are commented on, no PRs are created.
- **Never** treat its output as a substitute for code review; it only catches the four classes of drift listed below.

## Scope (v1)

The doctor performs exactly four **gating checks** (each can PASS / WARN / FAIL).
After the checks it also prints one **informational, non-gating** section — the
*run-log summary* — that reports `.gitissue/runs.jsonl` telemetry but never
affects the PASS/WARN/FAIL result. Anything beyond the four checks and this
summary is **out of scope**:

| # | Check | What it verifies | Failure mode |
|---|-------|-----------------|--------------|
| 1 | Stale skill claims | `src/skills/issue-creator/README.md` and `src/skills/issue-creator/SKILL.source.md` are free of language asserting `/issue-creator` scans the codebase, predicts affected files, or generates implementation notes. | `FAIL` |
| 2 | Issue-template fields | Issue templates under `src/skills/issue-creator/templates/` and `.github/ISSUE_TEMPLATE/` (if present) do not request predicted affected files, generated technical notes, root cause, or implementation hints. | `FAIL` |
| 3 | Autopilot mode set | If `.gitissue.yml` exists in the repo root, it contains an `autopilot.mode` key. | `FAIL` (only when `.gitissue.yml` exists) |
| 4 | Squash-merge default | The repository's default merge strategy is squash (squash allowed AND merge-commit and rebase-merge disallowed). | `WARN` |

### Explicitly out of scope for v1

- `gh` authentication checks
- Full schema validation of `.gitissue.yml`
- Stale-triage detection
- PR-format checks
- Commit-message linting
- README link validation
- Autofix of any kind

## Prerequisites

Before any check, verify the environment. On failure, output the exact error from `references/error-messages.md` and stop.

1. Confirm git repository: `git rev-parse --git-dir`

`gh` is **optional**. The merge-strategy check (Check 4) requires `gh` and authentication; if either is missing, that check is skipped with an `○` note rather than failing the whole run.

### Bundled dependency precheck

Verify that this skill's bundled reference files are present.
If any are missing, stop immediately and print:

```
text
✗ Missing bundled dependency: {missing_file}

  To fix:  asm install https://github.com/luongnv89/idd --skill idd-doctor
           (or reinstall the full distribution)

  Then restart the agent session and re-run /idd-doctor.
```

Check these files relative to the skill's directory (the dirname of this SKILL.md):

- `references/error-messages.md` — Error catalog

## Configuration

This skill **reads** `.gitissue.yml` (only to determine whether `autopilot.mode` is set in Check 3) and is otherwise config-free. There is no `doctor:` section in `.gitissue.yml` and no per-check toggles in v1.

If `.gitissue.yml` does **not** exist, Check 3 is skipped with an `○ no .gitissue.yml — skipped` note rather than failing. Repos that have not yet run `/init-gitissue` should not be punished by the doctor.

---

## Pipeline

The doctor executes the four checks in order, prints one line per check, then a summary footer, then an informational run-log summary (see *Run-log summary*). Checks never short-circuit — every check runs even after a `FAIL`, so the operator sees the full picture in one pass.

Expected output for a clean repo (verify against this when testing the skill):

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
    ✓ [4/4] Squash-merge default  squash-only

    ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    Result: PASS  (4 checks, 0 failed, 0 warned)
```

**Exit codes** (when invoked from a script wrapper):

| Result | Exit | When |
|--------|------|------|
| `PASS` | 0 | All four checks pass (warnings are not failures, but they affect the result label) |
| `WARN` | 0 | At least one `WARN`, no `FAIL` |
| `FAIL` | 1 | At least one `FAIL` |

The skill itself runs inside an agent — there is no real exit code, but the final line MUST end with one of `PASS`, `WARN`, or `FAIL` so wrapper scripts can grep for it.

---

## Check 1 — Stale skill claims

Scan the `/issue-creator` skill's `README.md` and `SKILL.md` for stale claims about its own scope. The forbidden patterns describe the **old** behavior where the creator allegedly inspected the codebase. The intent-only contract (SPEC.md §1.2 intent–code boundary) forbids these claims.

### What to scan

```
src/skills/issue-creator/README.md
src/skills/issue-creator/SKILL.source.md
```

These are the only files in scope. Other skills (`/issue-analysis`, `/init-gitissue`, `/auto-pilot`, etc.) legitimately scan code as part of their work; flagging them would be a false positive. Do **not** scan `references/`, `templates/`, `docs/`, the top-level `README.md`, or any other skill's files.

If a future skill is created that also claims to be intent-only, add its files to this list explicitly. Mechanical "scan all skills" matching is intentionally avoided in v1.

### Forbidden patterns (case-insensitive substring match, with surrounding negation)

A line **fails** if it contains any of the patterns below **and** does not also contain a negation marker (`no`, `not`, `never`, `does not`, `doesn't`, `without`, `cannot`, `won't`).

| Pattern | Why it's forbidden |
|---------|-------------------|
| `scans the codebase` / `scan the codebase` | `/issue-creator` does not scan code |
| `predicts affected files` / `predict affected files` / `predicted affected files` | `/issue-creator` does not predict file paths |
| `generates implementation notes` / `generate implementation notes` / `generated implementation notes` / `generates technical notes` / `generated technical notes` | `/issue-creator` does not produce implementation guidance |
| `generates root cause` / `provides root cause` | Bug root-cause analysis is the resolver's job |
| `generates implementation hints` / `provides implementation hints` | Implementation hints belong in the resolver |

The negation guard exists so that a line like *"the issue-creator skill **does not** scan the codebase"* is not flagged as drift — the file is correctly stating the contract.

### Pattern match algorithm

1. Read each file in scope.
2. For each line, lowercase-compare against each forbidden pattern.
3. If a pattern matches, scan the same line for any negation marker (case-insensitive).
4. If no negation marker is present on the matching line, record a finding `{file, line_number, pattern, snippet}`.

The negation check is **per-line**. A negation in a separate paragraph does not absolve a later positive claim.

### Output

| Outcome | Line |
|---------|------|
| Pass | `✓ [1/4] Stale skill claims    no stale language in /issue-creator` |
| Fail | `✗ [1/4] Stale skill claims    {K} drifted line(s) in {J} file(s)` followed by a per-finding block |

Per-finding block format (indented under the check line):

```
        {path}:{line_number}
        pattern: {matched_pattern}
        line:    {trimmed_line_text}
```

---

## Check 2 — Issue-template fields

Scan issue-template files for field labels that ask the reporter (or normalizer) to provide content the IDD methodology forbids: predicted affected files, generated technical notes, root cause, or implementation hints.

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
| `affected files` | predicting affected files is the resolver's job |
| `predicted affected files` | same |
| `technical notes` (with `generated` or as a header label like `## Technical Notes`) | generated technical notes belong in the resolver, not the issue |
| `## technical notes` | section header for forbidden content |
| `root cause` | root-cause analysis is the resolver's job |
| `implementation hints` | implementation hints belong in the resolver |
| `implementation notes` | same |
| `architecture constraints` | architecture constraints belong in analysis/resolver output, not issue templates |

The match is **substring**, case-insensitive. A literal phrase like `Affected Files:` in a template file body counts. Do **not** apply the negation guard from Check 1 here — issue templates are field labels, not prose, so a field named "Affected Files" is unambiguous drift regardless of surrounding text.

### Match algorithm

1. Read each file in scope.
2. For each line, lowercase-compare against each forbidden pattern.
3. If a pattern matches, record a finding `{file, line_number, pattern, snippet}`.

### Output

| Outcome | Line |
|---------|------|
| Pass | `✓ [2/4] Issue-template fields no forbidden fields in N template(s)` |
| Fail | `✗ [2/4] Issue-template fields {K} forbidden field(s) in {J} template(s)` followed by a per-finding block |

Per-finding format (same as Check 1).

If no template files exist at all (neither `src/skills/issue-creator/templates/` nor `.github/ISSUE_TEMPLATE/`), the check passes with `✓ [2/4] Issue-template fields no template files found — nothing to check`.

---

## Check 3 — Autopilot mode

Verify that `.gitissue.yml`, when present, sets `autopilot.mode`. The `mode` key is what makes the conservative-merge default reachable; without it, legacy `auto_merge` falls back to the old aggressive behavior in some code paths.

### Procedure

1. Check whether `.gitissue.yml` exists in the repo root. If not, **skip** with `○ [3/4] Autopilot mode        skipped — no .gitissue.yml`.
2. If present, read the file as text (do not require a YAML parser — a regex check is sufficient and avoids adding dependencies).
3. Look for a line matching the regex `^[[:space:]]*mode:[[:space:]]*[^#[:space:]]+` inside an `autopilot:` block. Equivalent shell heuristic:

   ```bash
   awk '/^autopilot:/{f=1;next} /^[^[:space:]#]/{f=0} f' .gitissue.yml | grep -E '^[[:space:]]+mode:[[:space:]]*(conservative|balanced|aggressive)\b'
   ```

4. If a match is found, capture the mode value for the report.

### Output

| Outcome | Line |
|---------|------|
| Skip | `○ [3/4] Autopilot mode        skipped — no .gitissue.yml` |
| Pass | `✓ [3/4] Autopilot mode        autopilot.mode = {value}` |
| Fail | `✗ [3/4] Autopilot mode        .gitissue.yml has no autopilot.mode` |

The fail line is followed by a fix hint indented one extra level:

```
        Fix: add to .gitissue.yml under `autopilot:`
          mode: conservative
```

---

## Check 4 — Squash-merge default

Verify that the repository's default merge strategy is squash. IDD uses one-commit-per-PR semantics, so any non-squash strategy is a footgun.

### Procedure

1. Confirm `gh` is on `PATH` and authenticated.
   - If `gh` is missing: skip with `○ [4/4] Squash-merge default  skipped — gh not installed`.
   - If `gh auth status` fails: skip with `○ [4/4] Squash-merge default  skipped — gh not authenticated`.
2. Run:

   ```bash
   gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed
   ```

3. Parse the JSON. The check **passes** iff:

   ```
   squashMergeAllowed == true
     AND mergeCommitAllowed == false
     AND rebaseMergeAllowed == false
   ```

4. Otherwise, **warn** (not fail) — repo settings are owner-controlled and the doctor only nudges.

### Output

| Outcome | Line |
|---------|------|
| Skip | `○ [4/4] Squash-merge default  skipped — gh not installed` (or *not authenticated*) |
| Pass | `✓ [4/4] Squash-merge default  squash-only` |
| Warn | `⚠ [4/4] Squash-merge default  {summary} — recommend squash-only` |

The summary text lists which strategies are currently allowed, e.g. `squash + merge-commit + rebase enabled`.

The warn line is followed by a fix hint indented one extra level:

```
        Fix: in repo Settings → General → Pull Requests, allow only "Squash merging"
        Or:  gh api -X PATCH repos/:owner/:repo \
               -f allow_squash_merge=true \
               -f allow_merge_commit=false \
               -f allow_rebase_merge=false
```

---

## Summary footer

After all four checks, print:

```
    ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    Result: {RESULT}  ({total} checks, {failed} failed, {warned} warned)
```

`{RESULT}` is `PASS`, `WARN`, or `FAIL` per the table above.

If any check failed, append a one-line hint:

```
    Run /idd-doctor after applying fixes to verify.
```

---

## Run-log summary (informational, non-gating)

After the summary footer, print a short **run-log summary** over the last N runs
recorded in `.gitissue/runs.jsonl`. This surfaces the cross-run `monitoring`
signal (resolve rate, QA effort, recurring skip reasons) that the per-run output
otherwise forgets. It is **informational only** — it never changes the
PASS/WARN/FAIL result, has no exit code, and (like every part of this skill) is
strictly **read-only**: it reads `runs.jsonl` and writes nothing.

The run-log schema is defined in `docs/config-schema.md` (*`.gitissue/runs.jsonl`
— run log*): one JSON object per line, with at least `ts`, `issue`, `mode`,
`outcome`, and `pr`, plus optional `qa_cycles` and `skipped_reason`.

### Procedure

1. If `.gitissue/runs.jsonl` does **not** exist or is empty, **degrade gracefully**
   — print `○ Run-log summary           no runs recorded yet (.gitissue/runs.jsonl)`
   and stop the section. Absence is never a failure.
2. Otherwise read the file and take the **last N** lines (default `N = 50`). The
   `N = 50` cap bounds the agent's context budget — never load the whole log into
   the context window on a long-lived repo. Tolerate malformed lines: silently
   skip any line that is not valid JSON rather than aborting the summary.
3. Compute, over the parsed runs:
   - **Resolve rate** — share of runs whose `outcome` indicates a delivered
     resolution. Count `success` (resolver) and `merged` (auto-pilot) as resolved;
     report as `resolved / total` plus a percentage.
   - **Median QA cycles** — median of the `qa_cycles` field across runs that
     carry it (omit runs without the field). Report `n/a` if none carry it.
   - **Common skip reasons** — the top few `skipped_reason` values by frequency
     among `skipped` / `already_resolved` runs, each with its count.
4. Print the section using DESIGN.md symbols.

### Output

```
    ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    ○ Run-log summary           last {n} of {total} runs
        Resolve rate:    {resolved}/{n} ({pct}%)
        Median QA cycles: {median}
        Top skip reasons: {reason1} ({c1}), {reason2} ({c2})
```

When no runs have been recorded, the single graceful-degradation line replaces the
block:

```
    ○ Run-log summary           no runs recorded yet (.gitissue/runs.jsonl)
```

A read heuristic for steps 1–3 (no new dependency — `tail` + a JSON-aware pass):

```bash
[ -s .gitissue/runs.jsonl ] && tail -n 50 .gitissue/runs.jsonl
```

---

## Read-only guarantee

The skill MUST NOT modify any file in the repo, create branches or commits, open issues or PRs, or mutate `.gitissue.yml` or any config file. In detail, the skill is forbidden to:

- Modify any file in the repo
- Create branches, commits, tags, or PRs
- Edit issue bodies or post comments
- Mutate `.gitissue.yml` or any config file

The implementation reads files (via `Read` / `cat`) and runs read-only `gh` queries (`gh repo view --json …`, `gh auth status`). Test fixtures (see *Testing*) assert that the working tree is unchanged after a doctor run.

---

## Testing

Integration tests live in `tests/test-idd-doctor.sh` and follow the same pattern as `tests/test-projects-sync.sh` and `tests/test-autopilot-modes.sh` — pure bash, exit 0 on pass.

The test suite covers:

1. SKILL.md, README.md, and references files exist with the expected structure
2. Each forbidden Check 1 pattern is enumerated in the SKILL doc
3. Each forbidden Check 2 pattern is enumerated in the SKILL doc
4. The four-check pipeline is documented in order
5. Read-only guarantee is documented
6. The `gh repo view` field selection matches the documented contract
7. The skip behavior for missing `gh`, missing `.gitissue.yml`, and missing template directories is documented
8. The exit-code mapping (PASS=0, WARN=0, FAIL=1) is documented
9. The fix hint format is documented for both Check 3 and Check 4
10. The run-log summary is documented as informational/non-gating, reads `.gitissue/runs.jsonl`, degrades gracefully when the file is absent, and reports resolve rate, median QA cycles, and common skip reasons

Run with:

```bash
bash tests/test-idd-doctor.sh
```

---

## Output Conventions

Terminal output follows the DESIGN.md contract — symbols `● ✓ ✗ ◆ ⚡ ⚠ ○`, two-space indent, `┄` separators, URLs on their own line, ≤80 chars, one blank line between sections, static sequential output (no animation). Per-check line format: `{symbol} [N/4] {Check name (16 chars)} {detail}`; per-finding indent 8 spaces (4 + 4). Errors use the rich format from `references/error-messages.md`: `✗ what failed`, then `To fix:  <command>`, then a docs link when applicable.

## Edge Cases

- **`.gitissue.yml` exists but has no `autopilot:` section** — Check 3 fails with the standard fix hint.
- **`.gitissue.yml` has `autopilot.mode` set to a non-canonical value** (e.g., `mode: yolo`) — Check 3 still passes (any non-empty value satisfies the "key set" requirement); a future v2 may add value validation.
- **A skill README contains the forbidden pattern inside a code block or fenced quote** — Check 1 still flags it. The intent of v1 is mechanical strictness, not contextual nuance.
- **GitHub Enterprise repos without `gh` auth** — Check 4 is skipped, never failed.
- **`/issue-creator` skill is missing** — Check 1 fails with a clear `src/skills/issue-creator/README.md not found` finding (the `/issue-creator` skill is required for an IDD repo).

## Additional Resources

- **`references/error-messages.md`** — Complete error catalog with triggers and exact output
- **`docs/naming-conventions.md`** — Branch, commit, PR, and issue naming conventions (referenced for context)
- **`docs/config-schema.md`** — Full configuration schema (Check 3 references the `autopilot.mode` field)
- **`DESIGN.md`** — Terminal output style guide (repo root)
