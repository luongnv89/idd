# Report understanding

How to grade whether a person can understand a skill's final report. This is a
maintainer document: no skill reads it at run time and the build never bundles
it. Each skill's runtime rules for its report (status values, the `Evidence`,
`Uncertainty` and `Decision` rows, the format rule) stay in that skill's own
review contract; this file only says how to judge a report against them.

Grade understanding **alongside** correctness, never instead of it. A report can
pass every correctness assertion and still leave a reader unable to say what
happened.

## The four criteria

| Criterion | Question for the reader |
|---|---|
| Result is findable | Can you find the status and the main finding without reading the detail rows or logs? |
| Facts and assumptions are separate | Can you tell the checks that ran from what was inferred, reused, skipped or degraded? |
| Claims are traceable | Can you trace each material claim to its evidence (a `file:line`, commit, PR, issue or named check)? |
| Next decision is clear | Can you say whether an approval is needed and what you do next? |

Each skill section below turns these into observable checks on that skill's
report.

## Rules

- **A heading's presence is not evidence of understanding.** Grade what the
  report says under it.
- **Contract tests inspect instructions and examples.** The `tests/*.sh` pins and
  the deterministic stand-ins under `evals/cases/` prove the written contract
  and the fixture, not live agent behavior or human understanding. In a
  behavioral evaluation, grade the agent's own report and recorded tool results.
- **Grade every scenario against all four criteria.** Each skill section lists
  the scenarios a behavioral evaluation should include.

## Human feedback

Ask a human reviewer the four questions above for each graded report. Record the
answers with the evaluation: in the eval case's `human_review` block, or in the
evaluation's feedback record when there is no case. **Never record them on a PR
or issue**: a skill such as `/idd-doctor` posts nothing, and a review comment is
not an evaluation record.

Missing, blank or nonresponsive feedback leaves human understanding
**unconfirmed**. Agent inspection and automated checks cannot confirm it.

A case's `human_review` block holds the four observable checks for that case
(`criteria`), the feedback rule (`feedback`) and what the case can and cannot
prove (`scope`); see [`cases/issue-creator/basic/case.json`](cases/issue-creator/basic/case.json).

## auto-pilot

Graded on the final summary, alongside merge-gate correctness.

| Criterion | Observable check |
|---|---|
| Result is findable | The first row states the status, `complete`/`partial`, and the main finding without reading the iteration rows or logs. |
| Facts and assumptions are separate | Observed checks (merge, CI verdict, follow-up filed, persisted report) are distinct from degraded or reused verdicts listed under `Uncertainty`. |
| Claims are traceable | Each `merged` row names its PR and its AC pass/fail/unverified counts; each `left_open`/`blocked_by_dependency` row names its blocker; `partial` names what made it partial. |
| Next decision is clear | The summary says `No approval needed.` or names the one pending critical decision, and lists remaining user actions on `Next action:`. |

Scenarios: a clean run, a run with a `left_open` PR, a critical-issue pause and a
rate-limited stop. Case: [`cases/auto-pilot/merge-gating`](cases/auto-pilot/merge-gating/).

## issue-resolver

Graded on the closing block, alongside correctness.

| Criterion | Observable check |
|---|---|
| Result is findable | The first row states `DONE`, `PARTIAL` or `BLOCKED` and the PR or stop reason, without reading the tracker or logs. |
| Facts and assumptions are separate | Observed checks (suite run, secret scan, `gh pr create` URL) are distinct from unverified ACs, skipped legs and `risk_rating`. |
| Claims are traceable | Each test claim names its count and SHA; `already_resolved` names the fixing commit; `BLOCKED` names the failed check; `PARTIAL` names the residual gap. A created PR is not reported as merged. |
| Next decision is clear | The output says `No approval needed.` and names the next action. |

Scenarios: a delivered PR, a PR with residual QA findings, a blocked secret scan,
and an `already_resolved` issue. Cases: [`cases/issue-resolver/`](cases/issue-resolver/).

## issue-analysis

Graded on the rendered report, alongside schema correctness.

| Criterion | Observable check |
|---|---|
| Result is findable | Opening text states status and the main finding; limitations are visible without searching logs. |
| Facts and assumptions are separate | Code observations, hypotheses, cached data, and untested reproduction are labeled distinctly. |
| Claims are traceable | Each material claim names supporting code, commit, tracker evidence, or an observed validation check. |
| Next decision is clear | Output identifies the next decision or says no approval is needed, and lists remaining work. |

Scenarios: a fresh analysis, a cached view, a scan timeout, and failed
persistence. Case: [`cases/issue-analysis/fresh-read-only`](cases/issue-analysis/fresh-read-only/)
(a fresh analysis).

## issue-triage

Graded on the *Final Report* block, alongside ordering correctness.

| Criterion | Observable check |
|---|---|
| Result is findable | The first row states the status and the suggested start without reading the table or logs. |
| Facts and assumptions are separate | Observed checks (fetch, script exit, persisted file) are distinct from inferred edges, `maybe-fixed` flags and cached data. |
| Claims are traceable | Each `maybe-fixed` flag links its commit or PR; each blocked status names its blocker; `PARTIAL` names the failed check. |
| Next decision is clear | The output says `No approval needed.` and names the remaining user actions. |

Scenarios: a full update, a cached view, a degraded scan and a failed write.
Case: [`cases/issue-triage/ordering`](cases/issue-triage/ordering/).

## issue-creator

Graded on the Create, Normalize and Batch reports, alongside issue-body
correctness. Exclude negative-trigger cases where no skill runs.

| Criterion | Observable check |
|---|---|
| Result is findable | Opening text states status and outcome; batch counts reconcile with every item. |
| Facts and assumptions are separate | Verified writes cite observed reads; inferred fields, scan limits, and untested behavior are labeled. |
| Claims are traceable | Issue/backup links and observed checks support the claimed scope; partial success never becomes an overall success claim. |
| Next decision is clear | The report names a required decision or says no approval is needed, and lists remaining actions. |

For repository evals, extend the `grade` assertions of
[`cases/issue-creator/basic`](cases/issue-creator/basic/) to inspect its report
artifact. That case uses a deterministic stand-in: passing it verifies the
fixture contract, not an agent following the skill.

## issue-pr-review

Graded on the Step 7 summary, alongside correctness.

| Criterion | Observable check |
|---|---|
| Result is findable | The first row states `Result:` with its status and main finding; no scrolling or log reading is needed. |
| Facts and assumptions are separate | `Evidence` names checks that ran here; inherited, skipped, or model-judged items appear under `Uncertainty`. |
| Claims are traceable | Each finding names its dimension and `file:line`; each pass names the check and commit; a step `PASS` never stands in for a merge. |
| Next decision is clear | `Decision:` and `Next action:` state whether approval is needed and what the user does next. |

Cases: [`cases/issue-pr-review/`](cases/issue-pr-review/).

## init-idd

Graded on the *Step 4 — Report* block, alongside config correctness.

| Criterion | Observable check |
|---|---|
| Result is findable | The first row states the status and what happened to `.idd.yml` without reading other rows. |
| Facts and assumptions are separate | Observed checks (script exit, file re-read, parser, `gh` reads) are distinct from marker-file inferences and hand-resolved fields. |
| Claims are traceable | Each detected value names its marker file; `BLOCKED` names the error block; `PARTIAL` names the skipped check. |
| Next decision is clear | The output says `No approval needed.` and names the remaining user actions, including commit and any merge-settings fix. |

Scenarios: a fresh generate, a merge, a cancel (interactive and auto mode), a
degraded scan, and a failed validation. Case:
[`cases/init-idd/python-generate`](cases/init-idd/python-generate/) (a fresh
generate).

## idd-doctor

Graded on the doctor report. The doctor is read-only and posts no comment, so
the reviewer's answers go with the evaluation, never on a PR or issue.

| Criterion | Observable check |
|---|---|
| Result is findable | The `Result:` line states `PASS`, `WARN`, or `FAIL` before any contract row, without reading findings. |
| Facts and assumptions are separate | `Evidence` names only checks that ran; skipped checks and heuristic limits appear under `Uncertainty`, never as passes. |
| Claims are traceable | Every failed or warned check has a `{path}:{line_number}` finding or a quoted configuration value; `PASS` is never claimed for a skipped check. |
| Next decision is clear | `Decision` says no approval is needed and names the fix hints to apply, or `Next: none`. |

`tests/test-idd-doctor.sh` checks the spec's correctness only. Case:
[`cases/idd-doctor/drift-report`](cases/idd-doctor/drift-report/) (a `FAIL`
report with one warned check).
