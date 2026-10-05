# Review contract — /idd-doctor

Read this before printing the *Summary footer*. It defines the four rows that
follow the `Result:` line, the format rule, and the criteria a reviewer grades
a doctor report against. The doctor is report-only: it authorizes no change,
so it never asks for approval.

## The rows

Print these three rows directly under the `Result:` line, at the same indent,
on every run that reached the summary footer:

```
    Result: WARN  (4 checks, 0 failed, 1 warned)
    Evidence:    ran 1 2 4 · skipped 3 (no .gitissue.yml) · scanned 2 skill files, 3 templates
    Uncertainty: check 3 not verified (skipped); checks 1-3 are text heuristics
    Decision:    No approval needed — report-only, nothing changed. Next: apply the check 4 Fix hint, then re-run /idd-doctor
```

The `Result:` line itself is unchanged and stays the one line a wrapper script
greps (see *Exit codes* in SKILL.md). The rows are additive human-facing
output and never carry `PASS`, `WARN`, or `FAIL` as a status token.

1. **Result.** The existing `Result:` line states the status first. `PASS`
   means every check that **ran** passed; it does not mean a skipped check
   passed. The `Uncertainty` row carries that distinction.
2. **Evidence.** Name what the run actually observed:
   - `ran {N…}` — the check numbers that reached a pass, warn, or fail verdict.
   - `skipped {N} ({reason})` — one entry per skipped check, with the reason
     from its skip line. Omit the clause when nothing skipped.
   - `scanned {a} skill files, {b} templates` — the files Checks 1 and 2 read.
     A missing file is a Check 1 finding, not a scanned file.
   - Every finding already printed its `{path}:{line_number}` under its check
     line. Do not repeat findings here.
3. **Uncertainty.** List each item that applies, separated by `; `:
   - `check {N} not verified ({reason})` for each skipped check.
   - `check 4 binding unverified` when Check 4 printed its unreadable-source
     warn line.
   - `checks 1-3 are text heuristics` — always printed when any of Checks 1–3
     ran. Check 1 is a per-line substring match with a negation guard, so a
     claim worded differently is missed and a negation on the same line hides
     a claim. Check 3 confirms the key is present, not that the value or the
     rest of `.gitissue.yml` is valid.
4. **Decision.** Always start with `No approval needed — report-only, nothing
   changed.` Then, when at least one check failed or warned, add
   `Next: apply the check {N…} Fix hint(s), then re-run /idd-doctor`. When
   nothing failed or warned, add `Next: none`. The doctor never applies a fix
   itself (see *Read-only guarantee*).

On a run that stopped before Check 1 (see *Prerequisites*), the error block
is the result, its `To fix:` line is the next action, and the run prints no
summary rows.

## Format rule

- **Default:** the static terminal layout in SKILL.md (*Output Conventions*).
  The whole report — four check lines, findings, summary, and run-log section —
  is inspectable at once, so no other format is needed.
- **Requested alternative:** when the user asks for Markdown or JSON, render
  the same check results and the same four contract items (result, evidence,
  uncertainty, decision) in that format. Keep the result in the first line or
  first key.
- **Unsupported request:** when the user asks for a format the host cannot
  produce (for example an HTML dashboard), print one `⚠` line naming the
  limitation, then print the default terminal layout.

**Interactive report: not applicable.** The doctor emits at most four check
lines plus their findings and one summary section. A reader inspects the whole
report without filtering, and every finding already carries its
`{path}:{line_number}` source.

## Understanding criteria

Grade an actual doctor report against these criteria when a behavioral review
is run. A heading's presence is not evidence of understanding.

| Criterion | Observable check |
|---|---|
| Main result is findable | The `Result:` line states `PASS`, `WARN`, or `FAIL` before any contract row, without reading findings. |
| Facts and assumptions are separated | `Evidence` names only checks that ran; skipped checks and heuristic limits appear under `Uncertainty`, never as passes. |
| Claims are traceable | Every failed or warned check has a `{path}:{line_number}` finding or a quoted configuration value; `PASS` is never claimed for a skipped check. |
| Next decision is clear | `Decision` says no approval is needed and names the fix hints to apply, or `Next: none`. |

Ask a human reviewer whether they could find the result, separate facts from
assumptions, trace each finding, and name the next action. Record the answers
on the PR or issue that ran the review. Missing, blank, or nonresponsive
feedback leaves human understanding **unconfirmed**; an agent's own inspection
cannot confirm it.
