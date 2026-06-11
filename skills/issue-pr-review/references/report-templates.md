# Summary Report Templates

Templates for the Step 7 summary report and the expected inline pipeline output. SKILL.md keeps the contract short; this file holds the full templates.

The Step 7 summary always shows the **five review dimensions** explicitly so reviewers can see, at a glance, that a PR is being judged on more than just tests. A PR can pass tests and still fail on `traceability` or `acceptance_criteria` — those dimensions are reported with their own status line.

## Summary — Clean PR

```
◆ PR Review: #{pr_number} (pass {N} — clean)
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Script pre-pass:   ✓ lint/format auto-fixed ({auto_fixed} files)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Review dimensions:
    correctness:         ✓ pass
    acceptance_criteria: ✓ pass ({n_pass}/{n_total} criteria pass)
    traceability:        ✓ pass (Closes #{N}, commit ref, Decision Record, AC block)
    maintainability:     ○ partial ({note_count} note-level findings)
    safety:              ✓ pass
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Tests:             ✓ pass ({count} passed)
  CI status:         ✓ pass ({checks_count} checks passed)
  Issues fixed:      ✓ {total_fixed} total across {cycles} cycles
  Issues noted:      ○ {note_count} (medium, not blocking)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            PASS

  {pr_url}
```

## Summary — PR With Remaining Issues

```
◆ PR Review: #{pr_number} (pass {max} — issues remain)
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Review dimensions:
    correctness:         ⚠ partial ({N} issues)
    acceptance_criteria: ✗ fail ({n_fail}/{n_total} criteria fail, {n_unverified} unverified)
    traceability:        ✗ fail — Closes #{N} missing
    maintainability:     ✓ pass
    safety:              ✓ pass
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Tests:             ✓ pass
  CI status:         ✓ pass
  Issues fixed:      ✓ {total_fixed} total across {max} cycles
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            WARN (manual review recommended)

  Remaining:
    ● [acceptance_criteria] criterion 2: "{text}" — fail ({evidence})
    ● [traceability] PR body missing Closes #{N}
    ● [correctness] {description} ({file}:{line})

  {pr_url}
```

The `traceability: fail` line is the one case where tests can be green and the PR is still blocked from soft-pass. Issue #36's contract: missing `Closes #N` always reports a traceability failure even if tests pass.

## Summary — Human-Authored PR (Decision Record absent)

When a human-authored PR (one not produced by `/issue-resolver`) is reviewed, the Decision Record is typically absent. This is reported as `partial` traceability, not `fail`, per issue #36's "Human-Authored PRs" decision (see issue #36 body and the IDD methodology doc):

```
  Review dimensions:
    correctness:         ✓ pass
    acceptance_criteria: ✓ pass ({n_pass}/{n_total} criteria pass)
    traceability:        ⚠ partial — PR not produced by /issue-resolver;
                           Decision Record absent
    maintainability:     ✓ pass
    safety:              ✓ pass
```

Acceptance-criteria checks still apply at full strength — they do not relax for human PRs. `Closes #{N}` checks also still apply at full strength — a human PR missing the issue link still fails traceability, **unless** the PR matches the refactor/chore exemption described below.

## Summary — Refactor/Chore Exempt PR

Refactor or chore PRs (skill quality passes, dependency bumps, doc-only updates) are exempt from the `Closes #N` hard-fail when they match `review.traceability_exempt_labels` or `review.traceability_exempt_pattern`. Check 1 is skipped; checks 2-4 still run and report `partial` if absent.

```
  Review dimensions:
    correctness:         ✓ pass
    acceptance_criteria: ○ pass — none defined; manual review recommended
    traceability:        ○ pass — exempt (refactor/chore PR; no Closes #N required)
    maintainability:     ✓ pass
    safety:              ✓ pass
```

The `acceptance_criteria` line above shows the common case for refactor/chore PRs (no linked issue, so no AC defined). When a refactor PR does have a linked issue with acceptance criteria, those criteria still verify normally — the refactor exemption relaxes only check 1 of traceability, never AC. The "verification disabled" wording appears only when `review.require_acceptance_criteria_check: false` is explicitly set.

When checks 2-4 produce partial findings on an exempt PR, append them inline:

```
    traceability:        ○ pass — exempt (refactor/chore PR; no Closes #N required);
                           no commit references #{N}
```

Note: check 2 (`git log --grep="#{N}"`) is well-defined only when the exempt PR has a linked issue number to grep for. If the PR is opened without any tracked issue, check 2 is reported as `n/a — no linked issue` rather than `partial`.

The match mechanism (label name or pattern) is logged so reviewers can audit which exemption rule fired. To restore strict issue #36 behavior (no exemption), set `review.traceability_exempt_labels: []` and `review.traceability_exempt_pattern: ""`.

## Auto-Merge (auto mode only)

If the PR is clean AND `--auto` is set:

```bash
gh pr merge {N} --squash --delete-branch
```

Append to the report on success:

```
  Merge:             ✓ pass (squash merged)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            MERGED

  ✓ PR #{N} merged — branch {branch_name} deleted
```

On merge failure:

```
  Merge:             ✗ fail ({reason})
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            BLOCKED (manual merge required)
```

Auto-merge is gated on the same soft-pass condition as the loop exit, including `traceability != fail` and zero `acceptance_criteria: fail`. A PR that passes tests and CI but fails traceability or acceptance criteria is **not** auto-merged.

In interactive mode: never auto-merge — just report status.

## Expected Inline Output

A clean review prints the 7-step tracker and a summary:

```
  [1/7] PR Info       ✓ #87 fix(auth): resolve redirect (#42)
  [2/7] Script Pre    ✓ 3 lint fixes applied
  [3/7] Review        ✓ correctness:pass ac:pass trace:pass maint:pass safety:pass
                        0 fixable, 1 noted
  [4/7] Tests         ✓ 12 passed
  [5/7] CI            ✓ all checks green
  [6/7] Fix           ○ skipped — nothing to fix
  [7/7] Summary       ✓ PR ready to merge

  ✓ PR #87 passed review (soft-pass: 1 medium note)
```
