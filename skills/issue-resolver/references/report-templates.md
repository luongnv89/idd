# Report and PR Body Templates

Templates for the PR body, the single closing summary, and the expected pipeline output. SKILL.md references this file at the relevant steps — do not inline these templates back into SKILL.md.

## PR Body Template (Step 5 — Deliver) <!-- a:rt-pr-body-template -->

This template is the load-bearing artifact for durable project memory. Under squash-merge, GitHub copies the PR body verbatim into the commit message that lands on the default branch **only when the repo's `squash_merge_commit_message` is `PR_BODY`** — that is a per-repo setting, not platform behavior, and GitHub's default (`COMMIT_MESSAGES`) writes the list of commit subjects instead, dropping everything below at the merge boundary (issue #295). Read it with `gh api repos/{owner}/{repo} --jq .squash_merge_commit_message`; `gh repo view --json` cannot report it. Repos using merge-commit or rebase-merge — or squash-merge with any other message source — keep this content only on GitHub. Write the template in full regardless: the PR body is the half of the dual write this skill controls, and `/issue-pr-review` reports the binding's real status separately. See *Analysis Artifacts and Durable Memory* in `references/docs/idd-methodology.md`.

**Placeholder legend.** Inside the fence below, the `{braced}` tokens are the only fill-in slots. Every other character — field names, punctuation, `=` signs, section headings — is **literal** and is copied as-is, never regenerated and never re-worded.

```markdown
Closes #{issue_number}

## Summary

{One-paragraph summary}

## Approach

{Selected option name and description}

## Decision Record

- **Root cause:** {one-paragraph diagnosis from analysis Step 6}
- **Options considered:** Option 1 — {name}; Option 2 — {name}; Option 3 — {name}
- **Options rejected:** Option 1 — {one-line reason}; Option 3 — {reason}
- **Selected option:** Option {N} — {name}
- **Residual risk:** {what remains uncertain or accepted as known limitation, or "none identified"}
- **Effort profile:** {"light — fast path (pre-work Effort {band}); synthesis skipped, QA capped at 1 cycle" when the run used the light profile; omit this line entirely on the full profile — the default — so it appears only when the fast path actually fired}
- **Design-confirm:** {high-complexity issues only — "confirmed Option {N} at design-confirm checkpoint (complexity: {level})" in interactive mode, or "auto-selected Option {N} (complexity: {level})" in auto mode; omit this line for trivial/low/medium complexity}
- **Reproduction:** {bug issues only — success: `<command>` confirmed red for the stated reason → regression test `<path>` (or "manual — no seam"); degraded: `not reproduced — <one-line reason> (fix applied without confirmed red; criterion marked unverified)`; omit for non-bug issues}

Analyzed at: `{branch} @ {commit_sha_short}` ({YYYY-MM-DD})

## Changes

| File | Change |
|------|--------|
| `{file}` | {description} |

## Test Results

- Unit tests: {count} passed
- Integration tests: {count} passed (or skipped)
- E2e tests: {count} passed (or skipped)
- Build: passed
- QA cycles: {count}

## Acceptance Criteria Verification

| Criterion | Status | Evidence |
|-----------|--------|----------|
| {criterion text from issue body} | pass | {short pointer — file/line, test name, manual check} |
| {criterion text from issue body} | unverified | {explanation — out of scope, manual review needed} |

Use `pass`, `fail`, or `unverified` per criterion. Always cite evidence (a file path, a test name, or a one-line explanation). If the issue has no acceptance criteria, replace the table with `> **Note:** No acceptance criteria defined — manual review recommended.`

**Bug issues — reproduction evidence.** When the issue `type` is `bug`, the Evidence column must cite the reproduction command from the Step 3 bug-verification checkpoint (`references/bug-verification.md`), not just a checkmark. Format the cell as `Verified red: <command> → fixed → <regression test path>` (or `… → manual repro, no seam` when no test seam exists). If the symptom could not be reproduced, mark that criterion `unverified` and note `not reproduced: <reason>`.

<!-- gitissue:qa v1 head={head_sha} profile={profile} cycles={qa_cycles} review=clean tests={test_count}@{tests_sha} ui={ui_legs}:{ui_result}@{ui_sha} --> {omit this entire line unless QA exited clean, and omit the ` tests=…` field when no final suite ran — see *QA handoff marker* below}
```

The PR title follows `{type}({scope}): {description} (#{issue_number})` — see `references/docs/naming-conventions.md`.

### QA handoff marker

The last line of the body is a machine-readable **QA handoff** — the resolver's <!-- a:rt-qa-handoff -->
statement that this PR already went through a clean QA loop, so
`/issue-pr-review` can collapse its duplicate of that work into one confirmation
pass instead of re-running the identical review on an unchanged diff. The
consumer is `/issue-pr-review`'s *QA handoff gate*
(`references/review-loop-mechanics.md` in that skill); this section is the
**producer** contract.

```
<!-- gitissue:qa v1 head=<sha40> profile=<light|full> cycles=<n> review=clean tests=<count>@<sha40> ui=<none|code|code+browser>:<clean|noted>@<sha40> -->
```

| Field | Value | Derivation |
|-------|-------|------------|
| `head` | full 40-char lowercase hex SHA | `git rev-parse HEAD` taken **after the last commit and immediately before `git push`** — the exact commit the PR will point at |
| `profile` | `light` or `full` | the pipeline profile *Step 0g* selected. On `light`, QA is capped at 1 cycle, so `review=clean` is a strictly shallower claim and the consumer treats it as such |
| `cycles` | integer | QA cycles run in *Step 4* |
| `review` | always `clean` | emitted **only** on the clean QA exit — there is no dirty spelling of this field |
| `tests` | `<count>@<sha40>` | durable rendering of `tests_state`: the final suite's passing count and the SHA it actually ran against. This template is the marker rendering location, not a third run-state consumer. That suite runs **before** *Update documentation*, which may commit, so the two SHAs can differ — write the real one, never `head` by assumption. Both values are captured where the suite runs (`references/steps/step-4-qa.md`, *Step 4 — QA*, item 2), because they cannot be recovered afterwards. **Omit the whole field** when `resolve.auto_test` is `false`, or when no capture was recorded: no suite ran, or none was asserted, so there is nothing to assert. The consumer honors this field only when a CI leg can actually run (`ci_leg_runnable`); produce the field the same way regardless |
| `ui` | `<legs>:<result>@<sha40>` | legs are `none` (no UI review ran), `code` (code UI review only), or `code+browser` (both). Result is `clean` or `noted`. The legs are named separately because the code review is environment-independent while the browser leg is fail-soft and skips on a headless host — a flat verdict would let the consumer trust a leg that never ran. The SHA is the commit the UI review **actually ran against** — `git rev-parse HEAD` at the moment it ran, never `head` by assumption: *Step 4*'s UI review precedes that step's QA cycles, so every QA fix commit, and *Update documentation* after them, lands later. It is captured where that review is spawned (`references/steps/step-4-qa.md`, *Step 4 — UI/UX review*, *SHA capture*). Omit the `@<sha40>` on `ui=none`, where there is no review to bind, and whenever no capture was recorded; the consumer reads an unbound `ui=` as parsable but never skippable |

**Copy the field names, never recall them.** The grammar above is a **closed
literal vocabulary**. Render the marker by copying the *PR Body Template*'s last
line character-for-character and substituting only its `{braced}` tokens; a
field name reconstructed from memory is how issue #446 shipped a marker no
consumer would ever trust. `review=clean` is that exact spelling and has **no
synonym** — `verdict=`, `status=` and `result=` are not accepted, and a marker
spelling it any of those ways still matches the consumer's parse grep, so it is
never `absent`: the wrong key is ignored as an unknown one, `review=` is then
missing, and the marker resolves to `stale`, silently forfeiting every skip. `profile=` has no omit
rule and is **always written**. Only `tests=` and `ui=`'s `@<sha40>` carry the
omissions the field table above documents; nothing else may be dropped.

**Two absolute rules.**

1. **No secret-scan field, ever.** The marker never reports the outcome of
   `gi-secscan` or any other security gate, in any spelling. Its only possible
   consumer would be a safety gate, and a marker that can gate safety is a
   safety gate an attacker can write: the PR body is editable by whoever opened
   the PR (`gh pr edit --body`). Issue #274 — a PR disabling the secret-scanning
   gate through its own `.gitissue.yml` — is the standing proof this repo can
   lose a security gate to repo-controlled input. A field nobody is allowed to
   act on is a field a future edit eventually acts on, so it is not written at
   all.
2. **No marker on a non-clean exit.** On the `⚠ {N} issues remain` stagnation /
   max-cycles path, emit **no marker line**. Absent and dirty must take the
   identical path in the consumer, and the only way to guarantee that is to
   never emit a marker the consumer would have to interpret.

**The marker goes last, and exactly once.** The *PR Body Template* above already
carries it as the fence's final line — fill that line in, or delete it on a
non-clean exit. Never append a second copy on top of it: a body carrying two
markers is unparsable to the consumer and falls back to the full pipeline,
silently costing exactly the work the marker exists to save.
`/issue-pr-review`'s traceability fix prepends `Closes #N` to line 1 via
read-modify-write, so a marker on the final line is untouched by that edit by
construction.

### Lifting the Decision Record

Analysis JSON is **fresh** exactly when the predicate in `references/steps/step-0h-analysis-reuse.md` (*Step 0h — Analysis reuse gate*) says so — five checkable conditions, any doubt ⇒ stale. That section is the single home of the definition: do not restate, tighten, or re-derive a freshness rule here. When fresh, you may lift `root_cause`, `options_considered`, and `git_state` from the cache; **`selected_option` and `options_rejected` MUST always reflect this run's Step 2 outcome** — the synthesizer's options, or the options Step 2 lifted under `analysis_reuse = fresh` (*Step 2 — Plan → `reuse`*) — never a pick from an analysis this run did not prove fresh. Field labels are stable across skills — do not rename them.

If no analysis JSON exists (e.g., resolver was invoked without prior analysis), synthesize the same five core fields from the resolver's own Step 1 (Research) and Step 2 (Plan) findings, and use the synced base SHA as `commit_sha_short`. (For bug issues the sixth `Reproduction` line is added separately from the implementer's returned reproduction block — see the bug-verification checkpoint, not the analysis JSON.) Either source produces the same template — what matters is that the durable analysis signal lands in the PR body, the half of the dual write this skill controls, from which squash-merge carries it into git history under the repo-setting condition stated at the top of this file.

## Closing Summary

The closing summary is the **single** end-of-run block. It never repeats a
per-step pass/fail or a metric the `[N/5]` tracker already printed (files read,
complexity, option, files changed, test counts, QA cycles — see *Expected Inline
Pipeline Output*). Print it **once**: after the tracker's last line, or after the
error block of a stop. Pick the variant that matches the run's outcome.

### Review contract

Apply these rules to every variant. The resolver opens a PR and never merges it,
so no row asks for approval. The rows are human-facing only: the report-back
fields a caller reads and the run-log record keep their shape.

1. **Result first.** The first row is `Result:` with one status and the main
   finding or stop reason:
   - `DONE` — a PR was created and every step's completion report printed
     `Result: PASS`; or the issue was `already_resolved`.
   - `PARTIAL` — a PR was created, but at least one step printed
     `Result: PARTIAL` (residual QA findings, a failed board sync or run-log
     append, a check that could not be evaluated).
   - `BLOCKED` — the run stopped before a PR was created: a failed
     prerequisite, an invalid config, a missing bundled dependency, `not found`,
     `closed`, `pr_in_progress`, a declined design confirm, a step that printed
     `Result: FAIL`, a blocked secret scan, or a failed final test run.

   These run statuses are separate from the per-step `PASS | PARTIAL | FAIL`
   vocabulary (*Step Completion Reports*).
2. **Evidence.** Name only checks that ran, each with its observed result: the
   final suite (`{count} passed@{sha7}`, or its skip reason), the secret-scan
   verdict and `policy_source`, the QA verdict, the PR URL that `gh pr create`
   returned, the docs search (*Update documentation*), and the run-log write
   (`appended`, `echoed`, or `fallback`). For `already_resolved`, cite the fixing
   commit or PR. For `BLOCKED`, cite the failed check and its observed output.
3. **Uncertainty.** List what this run did not verify: PR-body AC rows not marked
   `pass`, a skipped browser UI review, `resolve.auto_test: false`, a script that
   degraded to its prose procedure, the inline fallback without the Agent tool,
   a reused analysis (`analysis_reuse = fresh` — verified first, not re-derived),
   and the `light` profile's single QA cycle. Label `risk_rating` as a judgment,
   not a measurement. Write `none identified` only when no item applies.
4. **Decision.** Print `Decision: No approval needed.` in interactive and auto
   mode alike. Name the remaining user action on `Next action:`:
   - a created PR: `/issue-pr-review {pr_number}` (review, then merge);
   - under `/auto-pilot`: `none — auto-pilot reviews and merges`;
   - `pr_in_progress`: `/issue-pr-review {pr_number}` for the existing PR;
   - any other `BLOCKED`: the `To fix:` command of the error block.

A wrapped row continues on the next line, aligned under its value, so every line
stays within 80 characters.

### Successful Resolution

Every step printed `Result: PASS`:

```
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:       DONE — issue #{issue_number} resolved ({risk_rating} risk)
  Evidence:     final tests {count} passed@{sha7}
                secret scan pass ({policy_source}) · QA review clean
                run log {run_log_state}
  Uncertainty:  {items, or "none identified"}
  Decision:     No approval needed.
  Next action:  /issue-pr-review {pr_number}

  PR #{pr_number}: {pr_title}
  https://github.com/owner/repo/pull/{pr_number}
  Closes #{issue_number}
```

### Resolution With Warnings

A PR was created, but a step printed `Result: PARTIAL`. The `Result:` row names
the residual gap — the remaining count and cycle total are new facts (the
tracker's `[4/5] QA` line showed the in-progress state, not the final count):

```
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:       PARTIAL — issue #{issue_number} PR created ({risk_rating} risk)
                QA: {remaining} issues remain after {cycles} cycles
  Evidence:     final tests {count} passed@{sha7}
                secret scan pass ({policy_source}) · run log {run_log_state}
  Uncertainty:  {remaining} unresolved QA findings listed in the PR body
  Decision:     No approval needed.
  Next action:  /issue-pr-review {pr_number}

  PR #{pr_number}: {pr_title}
  https://github.com/owner/repo/pull/{pr_number}
  Closes #{issue_number}
```

### Already Resolved

Step 0 or Step 1 found the fix already on the default branch. No PR is created,
so the PR reference is omitted:

```
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:       DONE — issue #{issue_number} already resolved, no PR needed
  Evidence:     fixed by {sha7} ({merged PR #M | closing commit})
  Uncertainty:  matched by commit and PR text; the suite was not re-run
  Decision:     No approval needed.
  Next action:  {"none — issue closed", or "close #{issue_number}"}
```

### Blocked

The run stopped before a PR was created. The error block from
`references/error-messages.md` prints first; this block follows it:

```
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:       BLOCKED — {stop reason}
  Evidence:     {failed check}: {observed output}
  Uncertainty:  {steps not run, e.g. "Steps 1-5 not run; no code changed"}
  Decision:     No approval needed.
  Next action:  {To fix command, or /issue-pr-review {pr_number}}
```

### Format rule

The default format is the terminal block above, after the `[N/5]` tracker. The
PR body is the durable Markdown record. If the user asks for another format (for
example a Markdown summary or JSON), render it from the same facts and keep the
`Result`, `Evidence`, `Uncertainty`, `Decision` and `Next action` rows. If the
host cannot render the requested format, say so and print the terminal block.

The resolver produces no interactive report: one run covers one issue and one
PR, the closing block has at most a dozen rows, and the PR body's *Acceptance
Criteria Verification* table already ties each criterion to its evidence. No
review of this output needs repeated filtering.

### Evaluate report understanding

Grade actual outputs against these criteria as well as correctness:

| Criterion | Observable check |
|---|---|
| Result is findable | The first row states `DONE`, `PARTIAL` or `BLOCKED` and the PR or stop reason, without reading the tracker or logs. |
| Facts and assumptions are separate | Observed checks (suite run, secret scan, `gh pr create` URL) are distinct from unverified ACs, skipped legs and `risk_rating`. |
| Claims are traceable | Each test claim names its count and SHA; `already_resolved` names the fixing commit; `BLOCKED` names the failed check; `PARTIAL` names the residual gap. A created PR is not reported as merged. |
| Next decision is clear | The output says `No approval needed.` and names the next action. |

When running behavioral evaluations, include a delivered PR, a PR with residual
QA findings, a blocked secret scan, and an `already_resolved` issue, and grade
each closing block against all four rows. Ask human reviewers the matching four
questions and record their answers in the eval case's `human_review` block.
Missing, blank, or nonresponsive feedback leaves human understanding
unconfirmed; agent inspection cannot confirm it.

## Expected Inline Pipeline Output

A successful resolve prints the full 6-step tracker, then the single Closing
Summary block — per-step status appears only in the tracker, the PR reference only
in the closing block:

```
  ◆ Resolve Pipeline
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  [0/5] Preflight    ✓ issue #42 open, not yet resolved, effort: full
  [1/5] Research     ✓ read 12 files, complexity: medium
  [2/5] Plan         ✓ option 2 selected: balanced refactor
  [3/5] Implement    ✓ 3 files changed, 8 unit tests, 2 e2e tests
  [4/5] QA           ✓ clean after 2 cycles
  [5/5] Deliver      ✓ PR #87 created
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:       DONE — issue #42 resolved (low risk)
  Evidence:     final tests 14 passed@3f9c2a1
                secret scan pass (ref:origin/main) · QA review clean
                run log appended
  Uncertainty:  browser UI review skipped (no running app)
  Decision:     No approval needed.
  Next action:  /issue-pr-review 87

  PR #87: fix(auth): resolve mobile auth redirect (#42)
  https://github.com/user/repo/pull/87
  Closes #42
```

The tracker metrics — files read, complexity, option, files changed, test counts,
QA cycles — stay on the `[N/5]` lines above. Below the separator are only the
*Review contract* rows, the `risk_rating`, and the PR reference.

## Run-log entry — field derivation and suppression

Full detail for SKILL.md *Step 5 — Deliver → Run-log entry (monitoring)*, which
owns the trigger (every terminal outcome), the append snippet, and the
`--no-run-log` switch. This section carries the parts a run only needs once it is
actually writing the line.

### Fields to populate

Build the object from values already known during the run — `ts`, `issue`,
`mode`, `skill`, `outcome`, `pr`, plus the optional `complexity`, `profile`,
`agent_overrides`, `qa_cycles`, `ceiling`, `breach_reason`, `duration_s`, `phases`, and `skipped_reason` —
following the schema in `references/docs/run-log-schema.md` rather than re-deriving fields
here.

These derivations are the resolver's own:

- **`complexity`** — collapse the researcher's 5-value scale to the 3-value
  run-log scale before writing: `trivial`/`low` → `low`, `medium` → `medium`,
  `high`/`complex` → `high`.
- **`profile`** — the pipeline profile chosen in *Step 0g* (`light` or `full`).
  Omit the field only when `resolve.adaptive_effort` is `false`, or when no
  profile was selected at all (for example an early failure before Step 0g ran).
- **`agent_overrides`** — tally every configured (non-`null`) `agents.model` /
  `agents.effort` knob of each role this run spawned: `applied` when all of them
  reached their spawn (verbatim, or effort as the prompt hint), `fallback` when
  none did (unsupported-parameter skip, a role degraded by a rejected spawn, no
  Agent tool), `partial` for a mix. **Omit the field when no spawned role had an
  override configured** — never write `null` or a fourth value (exit 3).
- **`phases`** — seconds per step, from the epochs taken as each `[N/5]` step
  starts (SKILL.md *Configuration*): `preflight` runs from `run_started_epoch` to
  the `[1/5]` start, then `research`, `plan`, `implement`, `qa` (every cycle) and
  `deliver` each to the next boundary, the last to the terminal outcome. Omit a
  step that never started (an early exit or failure); the step in progress at
  that exit is measured to it. Omit the field when no boundary was captured.
- **`ceiling`** — class policy: `1` if `profile` is `light`; `resolve.qa_max_cycles`
  (default 5) if complexity is `high`; otherwise `2`. Fail-safe omitted
  profile/complexity as full + medium (`2`).
- **`breach_reason`** — required when `qa_cycles` exceeds `ceiling`; omit
  otherwise. `gi-runlog.py` rejects an over-ceiling row without it (exit 3).

`outcome` is one of `success` (a PR was delivered), `already_resolved` (Step 0/1
found the issue already fixed and exited early), or `failed` (a step failed).

### Suppression rule (single writer under `/auto-pilot`)

`--no-run-log` is passed only by `/auto-pilot`, which runs this resolver as a
subagent and writes the **single** run-log line per issue itself — appending here
too would double-write and skew `/idd-doctor`'s metrics. Instead **return** the
telemetry (`outcome`, `qa_cycles`, `ceiling`, `breach_reason`, `complexity`, `profile`, `agent_overrides`, `duration_s`, `phases`) in the
subagent result so the orchestrator folds it into its own line.

The flag is independent of `--auto`: a standalone `/issue-resolver <N> --auto`
run is *not* suppressed and still writes its own line.

## Step Completion Reports

Every step ends with a completion report — the checkable bar that separates *the
step ran* from *the step succeeded*. Emit it right after the step's `[N/5]`
tracker line:

```
  [3/5] Implement    ✓ 3 files changed, 8 unit tests
    √ Every AC addressed   √ Tests written   × Commits conventional
    Result: FAIL
```

Rules that make the report worth reading:

- `√` — the check passed. `×` — it did not. One entry per check the step actually
  validates. Checks are **gates that could have failed**, never restatements of a
  metric the tracker line already carries (files read, counts, option number) —
  restating those would report the same fact twice.
- `Result: PASS` — every check is `√`; continue.
- `Result: PARTIAL` — only non-blocking checks are `×`; continue, and carry the
  gap into the closing summary so it is never silently dropped.
- `Result: FAIL` — a blocking check is `×`; stop, or enter that step's defined
  failure path. In auto mode follow the step's documented auto behavior instead
  of prompting.
- A step may not be reported complete without a `Result:` line. If a check could
  not be evaluated (a tool was unavailable, a gate was skipped by config), mark
  it `×` and use `PARTIAL` — never assume `√`.
- One clarification of that rule, because two paths reach Step 2 without spawning
  the synthesizer: *Step 2 — Plan*'s `Options produced` check is `√` whenever
  options are in hand at the end of the step — synthesized this run, lifted from
  a fresh analysis (`analysis_reuse = fresh`), or replaced by the `light`
  profile's direct minimal plan — and `×`/`PARTIAL` only when the step ends with
  no plan at all. The check asks whether the plan exists, not which machinery
  produced it.

`√` and `×` are the completion-report check glyphs defined in
`references/docs/terminal-style.md`; the run's own status symbols stay `✓ ✗ ⚠ ○`.

### Per-step checks

| Step | Checks |
|------|--------|
| 0 — Preflight | `Issue fetched` · `No PR already targets it` · `Guards clear` · `Branch created` |
| 1 — Research | `Codebase scanned` · `Not already resolved` · `Complexity rated` |
| 2 — Plan | `Options produced` · `Option selected` · `Scope inside the issue` |
| 3 — Implement | `Every AC addressed` · `Tests written` · `Commits conventional` |
| 4 — QA | `Review clean` · `Tests pass` · `Build clean` · `AC verified` |
| 5 — Deliver | `Tests green` · `Branch pushed` · `PR opens with Closes #N` |

`PARTIAL` is legitimate in exactly two places: *Step 4 — QA* when the loop hits
`review_cycles` with residual non-blocking findings (delivered with known
issues), and *Step 5 — Deliver* when the PR is created but an optional extra
(project-board sync, run-log append) failed. Anywhere else a `×` is blocking.
