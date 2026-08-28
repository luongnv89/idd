# Summary Report Templates

Templates for the Step 7 summary report and the expected inline pipeline output. SKILL.md keeps the contract short; this file holds the full templates.

The Step 7 summary always shows the **five review dimensions** explicitly so reviewers can see, at a glance, that a PR is being judged on more than just tests. A PR can pass tests and still fail on `traceability` or `acceptance_criteria` — those dimensions are reported with their own status line.

The five dimensions are grouped under **two named axes** so *does it do the right thing* and *does it follow our conventions* read as separate tracks (see `verification-checks.md` → *Two-axis grouping — Spec vs Standards*):

- **Spec axis** — does the PR satisfy the issue's acceptance criteria? Groups `acceptance_criteria`, `correctness`, `safety`.
- **Standards axis** — does the PR follow documented project conventions? Groups `traceability`, `maintainability`.

The axes are a presentation grouping only. The status symbol on each dimension line, the `fix`/`note` semantics, and the soft-pass gate are all unchanged and stay per-dimension — there is no separate per-axis verdict line. Keep every dimension on its own line under the right axis header; the same five dimension names always appear.

## Summary — Clean PR

```
◆ PR Review: #{pr_number} (pass {N} — clean)
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Script pre-pass:   ✓ lint/format auto-fixed ({auto_fixed} files)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Review dimensions:
    Spec axis (satisfies acceptance criteria?):
      acceptance_criteria: ✓ pass ({n_pass}/{n_total} criteria pass)
      correctness:         ✓ pass
      safety:              ✓ pass
    Standards axis (follows project conventions?):
      traceability:        ✓ pass (Closes #{N}, commit ref, Decision Record, AC block, B1/squash: squash-only + PR_BODY)
      maintainability:     ○ partial ({note_count} note-level findings)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Tests:             ✓ pass ({count} passed)
  CI status:         ✓ pass ({checks_count} checks passed)
  Issues fixed:      ✓ {total_fixed} total across {cycles} cycles
  Issues noted:      ○ {note_count} (medium, not blocking)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            PASS

  {pr_url}
```

The `maintainability: partial` and `Issues noted` lines above are valid only when
`review.soft_pass: true`. With `review.soft_pass: false`, use the remaining-issues
summary below instead whenever a note or partial remains.

When Step 4 was skipped under `qa_handoff = trusted`, its `Result: PARTIAL` is
carried here rather than dropped — the `Tests:` line reports the skip and the
commit it is inherited from, never `✓ pass`:

```
  Tests:             ○ skipped (qa handoff @ {commit_sha_short})
```

## Summary — PR With Remaining Issues

```
◆ PR Review: #{pr_number} (pass {max} — issues remain)
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Review dimensions:
    Spec axis (satisfies acceptance criteria?):
      acceptance_criteria: ✗ fail ({n_fail}/{n_total} criteria fail, {n_unverified} unverified)
      correctness:         ⚠ partial ({N} issues)
      safety:              ✓ pass
    Standards axis (follows project conventions?):
      traceability:        ✗ fail — Closes #{N} missing
      maintainability:     ✓ pass
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Tests:             ✓ pass
  CI status:         ✓ pass
  Issues fixed:      ✓ {total_fixed} total across {max} cycles
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            WARN (manual review recommended)

  Remaining (grouped by axis):
    Spec axis:
      ● [acceptance_criteria] criterion 2: "{text}" — fail ({evidence})
      ● [correctness] {description} ({file}:{line})
    Standards axis:
      ● [traceability] PR body missing Closes #{N}

  {pr_url}
```

Each remaining finding keeps its `[dimension]` tag; the axis sub-headers only group them — a finding's blocking behavior comes from its dimension status, not its axis. The `traceability: fail` line is the one Standards-axis case where tests can be green and the PR is still blocked from soft-pass. Issue #36's contract: missing `Closes #N` always reports a traceability failure even if tests pass.

### Summary — Strict-pass blockers

When `review.soft_pass: false`, any remaining `action: "note"` finding or
`partial` dimension is a strict blocker even though it is not a fixer input:

```
  Result:            WARN (strict pass not reached)

  Remaining strict blockers:
    ● [maintainability] {description} — note (manual remediation required)
    ● [acceptance_criteria] {description} — partial (manual verification required)
```

Do not call this result clean or auto-merge it. Step 6 still delegates only
`action: "fix"` findings, so these blockers are reported rather than retried in a
non-productive fix loop.

## Summary — Human-Authored PR (Decision Record absent)

When a human-authored PR (one not produced by `/issue-resolver`) is reviewed, the Decision Record is typically absent. This is reported as `partial` traceability, not `fail`, per issue #36's "Human-Authored PRs" decision (see issue #36 body and the IDD methodology doc):

```
  Review dimensions:
    Spec axis (satisfies acceptance criteria?):
      acceptance_criteria: ✓ pass ({n_pass}/{n_total} criteria pass)
      correctness:         ✓ pass
      safety:              ✓ pass
    Standards axis (follows project conventions?):
      traceability:        ⚠ partial — PR not produced by /issue-resolver;
                             Decision Record absent
      maintainability:     ✓ pass
```

Acceptance-criteria checks still apply at full strength — they do not relax for human PRs. `Closes #{N}` checks also still apply at full strength — a human PR missing the issue link still fails traceability, **unless** the PR matches the refactor/chore exemption described below.

## Summary — Squash-Only Binding Qualified, Defeated, or Unverified

Traceability check 4 combines two independent repository reads: the merge strategy and the squash-commit message source (`references/verification-checks.md` → *Traceability checks*). A clean traceability pass needs squash-only + `PR_BODY`; anything else is a **repository** finding, not a PR defect.

When `squash_merge_commit_message` is `PR_BODY` but merge-commit and/or rebase remain enabled, B1 holds only for squash merges, so the dimension reports `partial`:

```
    Standards axis (follows project conventions?):
      traceability:        ⚠ partial — B1/squash qualified only
                             ({strategy_summary};
                             squash_merge_commit_message: PR_BODY) — merge-commit
                             and/or rebase can bypass the durable record
      maintainability:     ✓ pass

  To fix (repo admin):
    gh api -X PATCH repos/{owner}/{repo} -f allow_squash_merge=true -f allow_merge_commit=false -f allow_rebase_merge=false -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY
```

When the message-source read answers with anything but `PR_BODY`, the PR body is complete but the durable record will not reach git history via B1, so the dimension is still `partial`:

```
    Standards axis (follows project conventions?):
      traceability:        ⚠ partial — squash-merge binding defeated
                             (squash_merge_commit_message: {value}); the durable
                             record will not reach git history via B1
      maintainability:     ✓ pass
```

The repo-settings patch above fixes both partials. Both `squash_merge_commit_*` flags are required: GitHub pairs `PR_BODY` only with `PR_TITLE`, so a PATCH naming the message alone against the default `COMMIT_OR_PR_TITLE` is rejected with HTTP 422 `invalid_squash_commit_setting_combo`.

When either read does not answer — no `gh`, unauthenticated, 404, insufficient permission, or the field is absent — the wording names the reason and the status is still `partial`, never `pass`:

```
      traceability:        ⚠ partial — squash-merge binding unverified ({reason})
```

All three lines are `note` findings: they are never handed to the fixer in Step 6, because no edit to this PR can change a repo setting. Under `review.soft_pass: true` (default) they are report-only; under `soft_pass: false` they block like any other partial dimension.

When check 4 read `squash_merge_commit_message: PR_BODY` and the merge-effective keyword set (raw body, no markdown strip) diverges from the markdown-aware PR-link set, append a `note` line naming the issues that will close at squash-merge under B1:

```
      traceability:        ⚠ partial — merge-effective closers under B1
                             differ from the PR-link surface; will close at
                             squash-merge: #{extra_ids}
```

Under `COMMIT_MESSAGES` (or any non-`PR_BODY` value) do not treat code-span or blockquote keywords as merge-effective; omit this divergence line.

## Summary — Refactor/Chore Exempt PR

Refactor or chore PRs (skill quality passes, dependency bumps, doc-only updates) are exempt from the `Closes #N` hard-fail when they match `review.traceability_exempt_labels` or `review.traceability_exempt_pattern`. Check 1 is skipped; checks 2-4 still run — a missing commit reference or Decision Record (checks 2-3) reports `partial`, never `fail`. Check 4 has no "absent" mode, and is the exception to the rendering below: a qualified-only, defeated, or unverified binding is a repository finding, not a PR one, so it holds the dimension at `partial` rather than being appended to an exempt `pass`.

```
  Review dimensions:
    Spec axis (satisfies acceptance criteria?):
      acceptance_criteria: ○ pass — none defined; manual review recommended
      correctness:         ✓ pass
      safety:              ✓ pass
    Standards axis (follows project conventions?):
      traceability:        ○ pass — exempt (refactor/chore PR; no Closes #N required)
      maintainability:     ✓ pass
```

The `acceptance_criteria` line above shows the common case for refactor/chore PRs (no linked issue, so no AC defined). When a refactor PR does have a linked issue with acceptance criteria, those criteria still verify normally — the refactor exemption relaxes only check 1 of traceability, never AC. The "verification disabled" wording appears only when `review.require_acceptance_criteria_check: false` is explicitly set.

When checks 2-3 produce partial findings on an exempt PR, append them inline (check 4 is not appended — a non-`pass` check 4 holds the dimension at `partial`, as above):

```
    traceability:        ○ pass — exempt (refactor/chore PR; no Closes #N required);
                           no commit references #{N}
```

Note: check 2 (`git log --grep="#{N}"`) is well-defined only when the exempt PR has a linked issue number to grep for. If the PR is opened without any tracked issue, check 2 is reported as `n/a — no linked issue` rather than `partial`.

The match mechanism (label name or pattern) is logged so reviewers can audit which exemption rule fired. To restore strict issue #36 behavior (no exemption), set `review.traceability_exempt_labels: []` and `review.traceability_exempt_pattern: ""`.

## Auto-Merge (auto mode only)

If the PR is clean AND `--auto` is set (and `--no-merge` is **not** set):

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

Auto-merge is gated on the same configured pass condition as the loop exit, including `traceability != fail` and zero `acceptance_criteria: fail`. With `review.soft_pass: false`, it additionally requires zero notes and no partial dimensions. A PR that passes tests and CI but fails traceability or acceptance criteria — or has a strict-pass blocker — is **not** auto-merged.

When `--no-merge` is set (even in auto mode): skip the merge step entirely and report status only. The PR stays open for the owning agent (e.g. auto-pilot Phase 5) to merge through its own mode gate and dependency gate.

In interactive mode: never auto-merge — just report status.

## Expected Inline Output

A clean review prints the 7-step tracker and a summary:

```
  [1/7] PR Info       ✓ #87 fix(auth): resolve redirect (#42), depth: full
  [2/7] Script Pre    ✓ 3 lint fixes applied
  [3/7] Review        ✓ spec[ac:pass correctness:pass safety:pass]
                        standards[trace:pass maint:pass]
                        0 fixable, 1 noted
  [4/7] Tests         ✓ 12 passed
  [5/7] CI            ✓ all checks green
  [6/7] Fix           ○ skipped — nothing to fix
  [7/7] Summary       ✓ PR ready to merge

  ✓ PR #87 passed review (soft-pass: 1 medium note)
```

## Step Completion Reports

Every step ends with a completion report — the checkable bar that separates *the
step ran* from *the step succeeded*. Emit it right after the step's `[N/7]`
tracker line:

```
  [4/7] Tests        ✓ 128 passed, 0 failed
    √ Suite passed   × Build clean
    Result: FAIL
```

Rules that make the report worth reading:

- `√` — the check passed. `×` — it did not. One entry per check the step actually
  validates. Checks are **gates that could have failed**, never restatements of a
  metric the tracker line already carries (files read, counts, option number) —
  restating those is the duplication issue #165 removed.
- `Result: PASS` — every check is `√`; continue.
- `Result: PARTIAL` — only non-blocking checks are `×`; continue, and carry the
  gap into the closing summary so it is never silently dropped.
- `Result: FAIL` — a blocking check is `×`; stop, or enter that step's defined
  failure path. In auto mode follow the step's documented auto behavior instead
  of prompting.
- A step may not be reported complete without a `Result:` line. If a check could
  not be evaluated (a tool was unavailable, a gate was skipped by config), mark
  it `×` and use `PARTIAL` — never assume `√`.

`√` and `×` are the completion-report check glyphs defined in
`docs/terminal-style.md`; the run's own status symbols stay `✓ ✗ ⚠ ○`.

### Per-step checks

| Step | Checks |
|------|--------|
| 1 — Get PR Info | `PR fetched` · `Linked issue resolved` · `Diff readable` |
| 2 — Script Pre-pass | `Pre-pass ran` · `Findings collected` |
| 3 — Analyze & Review | `Review completed` · `Findings confidence-filtered` |
| 4 — Run Tests & Build | `Suite passed` · `Build clean` |
| 5 — Check CI Status | `CI queried` · `Required checks green` |
| 6 — Fix Issues | `Fixes applied` · `Re-review clean` |
| 7 — Summary Report | `AC verified` · `Verdict recorded` · `Merge decision stated` |

`PARTIAL` covers the documented soft paths: no CI configured (Step 5); a Step 5
CI failure held non-blocking by `review.ignore_ci_billing_failures: true`; the
fix loop exhausting `review_cycles` with only non-blocking findings left (Step
6); or Step 4's test + build run skipped under `qa_handoff = trusted`, which
evaluates neither of that step's checks and so renders

```
  [4/7] Tests        ○ tests skipped (qa handoff @ {commit_sha_short})
    × Suite passed   × Build clean
    Result: PARTIAL
```

The ignored-CI path renders the same way, and its `×` is load-bearing: the wait
ran and the checks are red, so `Required checks green` is genuinely false. The
flag makes that non-blocking, not true.

```
  [5/7] CI Status    ⚠ {N} checks failed — not blocking (review.ignore_ci_billing_failures: true)
    √ CI queried   × Required checks green
    Result: PARTIAL
```

The closing summary carries the same gap — `CI status: ○ {N} checks failed (not blocking — review.ignore_ci_billing_failures)` and a `Result: PARTIAL` verdict, never `PASS`. The caller still receives `ci_status` as `failed@<sha40>`.

A failing test, a red required check, or an unaddressed blocking finding is
always `FAIL`.
