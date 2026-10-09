# Summary Report Templates

Templates for the Step 7 summary report and the expected inline pipeline output. SKILL.md keeps the contract short; this file holds the full templates.

The Step 7 summary always shows the **five review dimensions** explicitly so reviewers can see, at a glance, that a PR is being judged on more than just tests. A PR can pass tests and still fail on `traceability` or `acceptance_criteria` — those dimensions are reported with their own status line.

The five dimensions are grouped under **two named axes** so *does it do the right thing* and *does it follow our conventions* read as separate tracks (see `verification-checks.md` → *Two-axis grouping — Spec vs Standards*):

- **Spec axis** — does the PR satisfy the issue's acceptance criteria? Groups `acceptance_criteria`, `correctness`, `safety`.
- **Standards axis** — does the PR follow documented project conventions? Groups `traceability`, `maintainability`.

The axes are a presentation grouping only. The status symbol on each dimension line, the `fix`/`note` semantics, and the soft-pass gate are all unchanged and stay per-dimension — there is no separate per-axis verdict line. Keep every dimension on its own line under the right axis header; the same five dimension names always appear.

## Review contract

Apply these rules to the Step 7 summary of **every** terminal outcome — a clean
PR, remaining issues, a merge, and a stop before Step 7. They change only the
human-facing summary: the report-back fields `/auto-pilot` reads (`result`,
`ci_status`, …), PR-body markers, and exit behavior are untouched.

1. **Result first.** The first row after the header is `Result:` with one status
   and the main finding or stop reason:
   - `PASS` — the loop-exit condition held (soft or strict, per
     `review.soft_pass`) with every CI and test leg satisfied by a real pass, a
     config skip, or a `qa_handoff = trusted` test skip (listed under
     *Uncertainty*, never as `✓ pass`). The PR is clean. When an auto-merge
     follows, its `MERGED` or `BLOCKED (manual merge required)` block supersedes
     this row; otherwise (interactive, `--no-merge`, or
     `review.auto_merge: false`) it is the final status.
   - `MERGED` — `PASS`, and the auto-merge succeeded.
   - `PARTIAL` — the loop exited with no finding left, but a leg was not
     verified: a CI failure held non-blocking by
     `review.ignore_ci_billing_failures`, CI still pending at the stop, or a
     degraded tool that left a check unevaluated. Never merged. A `trusted` test
     skip is not on this list: Step 4's own completion report reads
     `Result: PARTIAL`, but the summary carries that gap as *Uncertainty* and
     stays `PASS`.
   - `WARN (manual review recommended)` / `WARN (strict pass not reached)` —
     findings remain after the cycle cap, a stagnation stop, a #36 hard-block, or a
     strict-pass blocker. Never merged.
   - `BLOCKED ({reason})` — the run stopped before a verdict, or the merge
     failed: a failed prerequisite or missing bundled dependency, invalid
     config, no PR or a closed PR, a `gi-secscan` block or stop, a merge
     conflict, or `BLOCKED (manual merge required)`.
2. **Evidence.** Name the checks that actually ran, with their observed result
   and the commit they ran on: test count and `headRefOid` short SHA, the
   `gi-ci-wait` verdict and `ci_status`, the `gi-secscan` exit and
   `policy_source`, the PR-body re-read after a `Closes` edit. Print `✓ pass` only
   for a check that ran and passed; print `○ skipped ({reason})` for one that did
   not run. Each remaining finding keeps its `[dimension]` tag and `file:line`.
   End with the PR URL on its own line.
3. **Uncertainty.** Label what was inferred or not executed here: tests
   inherited from a `trusted` QA marker (run by `/issue-resolver`, not by this
   review); a skipped browser UI leg; a manual CI fallback; a `light` depth
   profile; acceptance criteria marked `unverified`; reviewer findings, which are
   model judgments above `review.confidence_threshold`, not executed checks.
   Print `Uncertainty: none` only when every check ran here.
4. **Decision.** Print `Decision: No approval needed.` — the merge gates are
   configuration, not a prompt, and `--auto` runs never ask. Name the remaining
   user action separately on a `Next action:` row: merge the PR yourself
   (interactive `PASS` never merges), fix the listed findings and re-run, or the
   `To fix:` command of a `BLOCKED` error.

Rows that a stop before Step 7 cannot fill are omitted, never invented: a
`BLOCKED` summary carries `Result`, `Evidence` (what ran before the stop),
`Uncertainty`, `Decision`, and `Next action` only.

### Format rule

The default is the static terminal summary below: the five dimension lines plus
at most `review.max_cycles` cycles of findings fit on one screen, and project
convention forbids terminal animation. Interactive filtering is therefore not
applicable; each finding already carries its dimension, `file:line`, and
severity beside its claim. When the user asks for another format (for example a
Markdown table to paste into a PR comment), render it from the same results and
keep the `Result`, `Evidence`, `Uncertainty`, and `Decision` rows. When the host
cannot render the requested format, say so and print the terminal summary.

### Report-understanding criteria

Grade a Step 7 summary on these, alongside correctness:

| Criterion | Observable check |
|-----------|------------------|
| Main result is findable | The first row states `Result:` with its status and main finding; no scrolling or log reading is needed. |
| Facts and assumptions are separated | `Evidence` names checks that ran here; inherited, skipped, or model-judged items appear under `Uncertainty`. |
| Claims are traceable | Each finding names its dimension and `file:line`; each pass names the check and commit; a step `PASS` never stands in for a merge. |
| Next decision is clear | `Decision:` and `Next action:` state whether approval is needed and what the user does next. |

Behavioral evals apply these to actual summaries. Ask human reviewers the same
four questions and record their answers in the eval's feedback; absent, blank,
or nonresponsive feedback leaves human understanding unconfirmed.

## Summary — Clean PR

```
◆ PR Review: #{pr_number} (pass {N} — clean)
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Result:            PASS — {main finding, e.g. "clean; ready to merge"}
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
  Evidence:          tests {count} passed @ {sha7}; CI {ci_status}
  Uncertainty:       {inherited/skipped/model-judged items, or "none"}
  Decision:          No approval needed.
  Next action:       merge PR #{pr_number} (this run does not merge)

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

  Result:            WARN (manual review recommended) — {n} blocking findings remain
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

  Remaining (grouped by axis):
    Spec axis:
      ● [acceptance_criteria] criterion 2: "{text}" — fail ({evidence})
      ● [correctness] {description} ({file}:{line})
    Standards axis:
      ● [traceability] PR body missing Closes #{N}
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Evidence:          tests {count} passed @ {sha7}; CI {ci_status}; {max} cycles run
  Uncertainty:       {unverified criteria, model-judged findings, skipped legs}
  Decision:          No approval needed.
  Next action:       fix the Remaining findings, then re-run /issue-pr-review {pr_number}

  {pr_url}
```

Each remaining finding keeps its `[dimension]` tag; the axis sub-headers only group them — a finding's blocking behavior comes from its dimension status, not its axis. The `traceability: fail` line is the one Standards-axis case where tests can be green and the PR is still blocked from soft-pass. Issue #36's contract: missing `Closes #N` always reports a traceability failure even if tests pass.

### Summary — Strict-pass blockers

When `review.soft_pass: false`, any remaining `action: "note"` finding or
`partial` dimension is a strict blocker even though it is not a fixer input. The
`Result:` row replaces the remaining-issues summary's first row:

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

A PR matching `review.traceability_exempt_labels` or `review.traceability_exempt_pattern` skips check 1 only (`references/verification-checks.md` → *Refactor/chore exemption*); checks 2-4 still run. Check 4 is the exception to the rendering below: a qualified-only, defeated, or unverified binding is a repository finding, not a PR one, so it holds the dimension at `partial` rather than being appended to an exempt `pass`.

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

The `acceptance_criteria` line shows the common no-linked-issue case; a linked issue's criteria still verify normally — the exemption never relaxes AC. Check 2-3 partials are appended inline:

```
    traceability:        ○ pass — exempt (refactor/chore PR; no Closes #N required);
                           no commit references #{N}
```

Log the matching mechanism (label name or pattern). Emptying both keys disables the exemption; an intentional `Refs #N` PR (*Intentional reference*) is not an exemption and still renders `○ pass — intentional reference (Refs #{N}; {k} AC deferred)`, its deferred criteria as `○ deferred`.

## Auto-Merge (auto mode only)

If the PR is clean AND `--auto` is set (and `--no-merge` is **not** set), run the
merge identity check, then merge with the expected-head guard (issue #516):

```bash
verified_head="{ci_sha}"   # Step 5's ci_sha; with none, the headRefOid the final review cycle read
read -r head_now base_ref <<<"$(gh pr view {N} --json headRefOid,baseRefName --jq '"\(.headRefOid) \(.baseRefName)"')"
behind_by="$(gh api "repos/{owner}/{repo}/compare/${base_ref}...${verified_head}" --jq .behind_by)"
if [ -n "$verified_head" ] && [ "$head_now" = "$verified_head" ] && [ "$behind_by" = "0" ]; then
  gh pr merge {N} --squash --delete-branch --match-head-commit "$verified_head"
else
  echo "BLOCKED (stale merge authorization)"   # never merged; report it and stop
fi
```

The check is the subset of `/auto-pilot`'s *Step 5.1c — Merge identity gate*
that a standalone review needs. A CI verdict covers one commit on one base, so
the merge needs both unchanged. `head_now` must equal `verified_head`, and
`behind_by` must be exactly `0`, meaning the live tip of the base branch is an
ancestor of the checked head and the squash lands exactly the tree CI ran on.
Compare against the branch name, never `baseRefOid`: that field is the base as
of the PR's last sync and can trail the live branch by many commits.
`--match-head-commit` makes GitHub refuse the merge when the head moved after
the check. Anything else (a moved head, a base that moved ahead, a failed read
or compare, an empty or non-integer answer) is **not** a merge. Report
`BLOCKED (stale merge authorization)` and stop. Never re-wait and never update
the branch here. **Patch-id equality never replaces fresh integration checks.**
A rebased or cherry-picked twin of a checked commit needs its own CI on its
own SHA. One residual stays open: a base that advances in the seconds between
the compare and the merge. Branch protection's *Require branches to be up to
date before merging* closes it on the server.

**A non-zero exit is not proof the merge failed.** gh merges on the server
before its local cleanup, which can fail (a dirty tree, a branch held by a
worktree). On a non-zero exit from `gh pr merge` itself, re-read `gh pr view {N} --json state --jq .state`:
`MERGED` is a merge (`Merge: ✓ pass (reconciled)`; run the cleanup with
`--delete-remote`, since gh stopped before deleting the remote branch); anything
else is the merge failure below.

**Post-merge cleanup** <!-- a:rv-post-merge-cleanup --> runs after every merge
this skill makes (`references/docs/post-merge-cleanup.md`):

```bash
python3 references/scripts/gi-postmerge.py --pr {N}
```

`merged: false` touched nothing: report its `problems[0]`, never a cleanup.
Otherwise `ok: false` prints `⚠ Cleanup incomplete` (`references/error-messages.md`)
and does **not** change `Result: MERGED`. Exit 4 or no `python3` runs that doc's
manual procedure. When `cwd_removed` is true, `cd` to `main_worktree`.

The merge runs after the summary prints, so close with a merge block whose first
row supersedes the summary's `Result:`. On success:

```
  Result:            MERGED — PR #{N} squash merged, branch {branch_name} deleted
  Merge:             ✓ pass (gh pr merge exit 0)
  Cleanup:           ✓ on {base} @ {base_sha7}; removed {branch_name}{, worktree {path}}
  Decision:          No approval needed.
```

`Cleanup:` drops `on {base} @ …` unless `checkout.action` is `switched` or
`already`, reads `⚠ partial — {n} kept (see below)` when `ok` is false, and
`○ manual procedure (gi-postmerge unavailable)` on the degrade path.

**Already merged.** Step 1 found the PR already `MERGED` (merged on GitHub, or
by an earlier run). No review runs. `--review-only` reports only. Interactive
runs `--dry-run` first, prints the plan, and asks
`Clean up local branch and switch to {base}{ (stashing local changes)}? [Y/n]`,
the suffix shown when the plan's `stash` is `planned`. `--auto` runs the cleanup
directly unless `--no-merge` is set, because the caller then owns cleanup.

```
  Result:            PASS — PR #{N} already merged; local checkout cleaned up
  Cleanup:           ✓ on {base} @ {base_sha7}; removed {branch_name}
  Decision:          No approval needed.
```

On merge failure:

```
  Result:            BLOCKED (manual merge required) — {reason}
  Merge:             ✗ fail ({reason})
  Decision:          No approval needed.
  Next action:       resolve {reason}, then re-run /issue-pr-review {N} --auto
```

On a stale merge identity (nothing was merged):

```
  Result:            BLOCKED (stale merge authorization) — {reason}
  Merge:             ✗ not attempted (head {verified_head_short} vs base {base_ref}: {reason})
  Decision:          No approval needed.
  Next action:       gh pr update-branch {N}, then re-run /issue-pr-review {N} --auto
```

Auto-merge is gated on the configured loop-exit pass condition **plus exclusions the loop exit does not apply**: pending CI is never clean, and a terminal CI failure held non-blocking by `review.ignore_ci_billing_failures: true` is never clean either — that key satisfies the loop's CI leg so the fix loop can stop and report `PARTIAL`, and it never satisfies this gate. The shared part includes `traceability != fail` and zero `acceptance_criteria: fail`. With `review.soft_pass: false`, it additionally requires zero notes and no partial dimensions. A PR that passes tests and CI but fails traceability or acceptance criteria — or has a strict-pass blocker — is **not** auto-merged.

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

`√` and `×` are the completion-report check glyphs defined in
`references/docs/terminal-style.md`; the run's own status symbols stay `✓ ✗ ⚠ ○`.

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
