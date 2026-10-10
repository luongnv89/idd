# Review contract — /init-idd

The rules for the *Step 4 — Report* block in SKILL.md. Apply them at every
terminal outcome: a generated, merged, or replaced config, a cancel, and an early
stop. The run-stats footer still prints last (`references/run-stats.md`).

## Result first

The first row after the header is `Result:`, with one status and the main
finding or stop reason:

| Status | Condition |
|---|---|
| `DONE` | `.idd.yml` was written, re-read, and passed all three checks in *Validate the written config* (parses as YAML, no placeholder left, `platform` present). |
| `PARTIAL` | `.idd.yml` was written, but no YAML parser was available, so the parse check did not run. |
| `BLOCKED` | The run stopped before a validated config existed: failed prerequisite, missing bundled dependency, `gi-stack-detect` exit 3, an existing file that does not parse in merge mode, a failed write, or a failed validation. Name the error block that stopped it. |
| `CANCELLED` | `.idd.yml` already existed and was kept unchanged — the user chose `cancel`, or auto mode took the safe default. |

A merge-strategy warning or skip does not change the status: it is a repository
setting, not part of the generated config.

The header names the outcome: `◆ Init IDD — setup complete` for `DONE` and
`PARTIAL`, `— stopped` for `BLOCKED`, `— cancelled` for `CANCELLED`. On `BLOCKED`
and `CANCELLED`, print only `Result`, `Evidence`, `Uncertainty`, `Decision`, and
`Next action` — no detection rows for a scan that did not run.

## Evidence

Name the checks that actually ran and what they returned:

- `gi-stack-detect` exit code, or `inline` when Step 1 degraded to the tables.
- The marker file behind each detected value (`language_source`,
  `test_runner_source`) and `file_count_source` (`git ls-files` or a walk).
- The path written and the parser that re-read it (`PyYAML` or `ruby`).
- The merge-strategy reads that ran (see `references/merge-strategy-check.md`).

Print `✓` only for a check that ran and passed. Print `○ skip` for a check that
did not run and `⚠ warn` for one that ran with a finding. The `Validation:` row
establishes only that the file parses, has no placeholder token, and names a
`platform` — not that each value suits the project.

## Uncertainty

Label inferences separately from observed checks:

- Language, framework, and test runner come from marker files and dependency
  names. No build or test command ran, so `resolve.auto_test: true` assumes the
  detected runner works.
- A field the agent resolved by hand (named in `unresolved`, or every field after
  an inline degrade) is an inference; say which fields.
- A skipped validation or merge-strategy read leaves that property unknown.
- In merge mode, preserved values were not re-checked against the new scan.

Print `Uncertainty: none beyond marker-file detection` when nothing else applies.

## Decision

Print `Decision: No approval needed.` This skill writes one local file and
commits nothing. The overwrite/merge/cancel prompt is the only gate, and it is
answered before the report (auto mode answers it with cancel). Name the remaining user actions separately on the
`Next action:` row:

- `DONE` / `PARTIAL`: review and commit `.idd.yml`, then `/issue-creator`.
  Add each merge-strategy `To fix:` command, and the parse check on `PARTIAL`.
- `BLOCKED`: the `To fix:` command of the error that stopped the run.
- `CANCELLED`: re-run `/init-idd` and choose `merge` or `overwrite` to change
  the file.

## Format rule

The default format is the static terminal block in SKILL.md *Step 4 — Report*:
one config file and about ten rows, inspectable at once. An interactive report
does not apply — there is nothing to filter, and project convention forbids
terminal animation; the written `.idd.yml` is the inspectable artifact. If
the user asks for another format (for example a Markdown table or a diff against
the previous file), produce it from the same values and keep the `Result`,
`Evidence`, `Uncertainty`, and `Decision` rows. If the host cannot render the
requested format, say so and print the terminal block.

## Evaluate report understanding

Grade actual outputs against these criteria as well as config correctness:

| Criterion | Observable check |
|---|---|
| Result is findable | The first row states the status and what happened to `.idd.yml` without reading other rows. |
| Facts and assumptions are separate | Observed checks (script exit, file re-read, parser, `gh` reads) are distinct from marker-file inferences and hand-resolved fields. |
| Claims are traceable | Each detected value names its marker file; `BLOCKED` names the error block; `PARTIAL` names the skipped check. |
| Next decision is clear | The output says `No approval needed.` and names the remaining user actions, including commit and any merge-settings fix. |

When running behavioral evaluations, include a fresh generate, a merge, a cancel
(interactive and auto mode), a degraded scan, and a failed validation, and grade
each report against all four rows. Ask human reviewers the matching four
questions and record their answers with the eval results. Missing, blank, or
nonresponsive feedback leaves human understanding unconfirmed; agent inspection
cannot confirm it.
