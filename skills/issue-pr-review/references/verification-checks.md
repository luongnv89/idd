# Verification Checks — Acceptance Criteria & Traceability

Full specification for the two verification dimensions that Step 3 of `/issue-pr-review` adds on top of the reviewer subagent's findings: **acceptance-criteria verification** (per criterion) and **traceability**. SKILL.md keeps the pass/fail and hard-block rules; this file holds the detailed procedure for each check, plus the refactor/chore exemption.

Apply this file during Step 3, after collecting the reviewer subagent's findings and before aggregating the five user-facing dimensions for the cycle report.

## Verification gates

Two `.gitissue.yml` flags decide whether the acceptance-criteria and traceability checks run at all:

| Flag | Default | When `true` (default) | When `false` |
|------|---------|----------------------|--------------|
| `review.require_acceptance_criteria_check` | `true` | Run per-criterion verification described below; any `fail` blocks soft-pass. | Skip the check entirely. Report `○ acceptance_criteria: pass` with the explicit note `verification disabled (review.require_acceptance_criteria_check: false)`. Never blocks soft-pass; emit no fixable issues for this dimension. |
| `review.require_traceability_check` | `true` | Run the four traceability checks below; missing `Closes #N` blocks soft-pass. | Skip the check entirely. Report `○ traceability: pass` with the explicit note `verification disabled (review.require_traceability_check: false)`. Never blocks soft-pass; emit no fixable issues for this dimension. |

Both default to `true`, which preserves the issue #36 contract verbatim. Setting either flag to `false` is an explicit opt-out — the corresponding hard-block conditions in *Loop controls* (see SKILL.md Review Loop) no longer apply for that dimension.

A separate, narrower opt-out exists for refactor/chore PRs (see *Refactor/chore exemption* below). It relaxes only check 1 (`Closes #N`) for the matching PR; the other three traceability checks still run.

## Reviewer-category → dimension mapping

The five user-facing dimensions and the fixed mapping from reviewer categories live in SKILL.md (*Dimensional review output*). The reviewer's JSON output partitions findings by its own categories; this skill aggregates them: `correctness` → `correctness`; `code_quality` + `test_coverage` → `maintainability`; `security` + `edge_cases` → `safety`. The remaining two dimensions (`acceptance_criteria`, `traceability`) are produced by the checks below. Each dimension's status: any `action: fix` finding → ✗ `fail`; only `action: note` findings → ⚠ `partial`; no findings → ✓ `pass`.

## Acceptance-criteria verification (per criterion)

> Run only when `review.require_acceptance_criteria_check` is `true`. When `false`, skip this entire subsection and emit `○ acceptance_criteria: pass — verification disabled (review.require_acceptance_criteria_check: false)`.

Fetch the linked issue and parse its `## Acceptance Criteria` section into individual checklist items. For each criterion, evaluate against the PR diff and produce one of three statuses:

| Status | When |
|--------|------|
| `pass` | The PR demonstrably satisfies the criterion. Evidence is required: a file path with line range, a test name, or a one-line description of how the change fulfills the criterion. |
| `fail` | The PR does not satisfy the criterion. Evidence is required: what's missing or what contradicts the criterion. |
| `unverified` | The criterion cannot be verified from the diff alone (e.g., needs production validation, manual user testing, or behavior outside the change set). Explanation is required. |

Output a structured block:

```
○ Acceptance Criteria
  | # | Criterion | Status | Evidence |
  |---|-----------|--------|----------|
  | 1 | "{criterion text}" | pass | tests/foo.test.ts: case 'rejects empty' |
  | 2 | "{criterion text}" | fail | exclusion list still hard-codes /login |
  | 3 | "{criterion text}" | unverified | needs manual mobile-device test |
```

If the issue has no acceptance criteria:

```
○ Acceptance Criteria — none defined; manual review recommended
```

**Pass/partial/fail rule for the dimension:**
- All criteria `pass` → ✓ acceptance_criteria: pass
- Any criterion `fail` → ✗ acceptance_criteria: fail (blocks soft-pass; treat as fixable)
- No fails, but at least one `unverified` → ⚠ acceptance_criteria: partial (does not block soft-pass; surfaced in report)
- No criteria defined → ○ acceptance_criteria: pass (with the "manual review recommended" note)

Each `fail` criterion becomes a fixable issue in Step 6 with `category: acceptance_criteria`, `action: fix`, evidence as the description, and the criterion text as the suggested fix target.

## Traceability checks

> Run only when `review.require_traceability_check` is `true`. When `false`, skip this entire subsection and emit `○ traceability: pass — verification disabled (review.require_traceability_check: false)`.

Per the dual-write rule (see *Analysis Artifacts and Durable Memory* in `references/docs/idd-methodology.md`), the durable analysis signal must survive the squash-merge into git history. Run the following four checks against the PR body and the commits in the PR:

1. **Issue link** — PR body contains `Closes #{N}`, `Fixes #{N}`, or `Resolves #{N}` for the linked issue. Detected with the same regex used by GitHub itself: `(?i)(close[sd]?|fix(e[sd])?|resolve[sd]?)\s+#\d+`. See *Refactor/chore exemption* below — the `Closes #N` requirement is relaxed for refactor/chore PRs (the other three checks still run).
2. **Commit references issue** — at least one commit between base and head references the issue number:
   ```bash
   git log "{base_branch}..{head_branch}" --grep="#{N}" --oneline
   ```
   The reference may live in the subject or body. A reference inside a `Co-authored-by:` trailer does not count.
3. **Durable analysis fields in PR body** — the PR body contains a `## Decision Record` section with the five stable labels (`Root cause`, `Options considered`, `Options rejected`, `Selected option`, `Residual risk`) and a `## Acceptance Criteria Verification` section (table or the explicit `No acceptance criteria defined` note). The labels are the contract — match them as exact strings, do not rewrite.
4. **Squash-commit-body assumption** — under squash-merge (the project default per `references/docs/idd-methodology.md`), GitHub copies the PR body verbatim into the commit message. Treat passing check 3 as evidence the squash commit will carry the durable summary; no separate check is needed pre-merge. Note this assumption explicitly in the report so reviewers know what is and is not verified.

**Pass/partial/fail rule for the dimension:**

| Outcome | Conditions | Status |
|---------|-----------|--------|
| All four checks pass | Closes #N + commit ref + Decision Record + AC Verification block all present | ✓ traceability: pass |
| `Closes #{N}` absent on a refactor/chore-exempt PR | check 1 skipped via the *Refactor/chore exemption* below; checks 2-4 still run | ○ traceability: pass — exempt (refactor/chore PR; no Closes #N required), with any check 2-4 partial findings appended |
| `Closes #{N}` absent | check 1 fails (regardless of other checks) | ✗ traceability: fail (blocking — see below) |
| Decision Record absent on a human-authored PR | check 3 partially fails: PR was not produced by `/issue-resolver` and has no Decision Record | ⚠ traceability: partial — "PR not produced by `/issue-resolver`; Decision Record absent" |
| Commit reference absent | check 2 fails but check 1 passes (PR body has Closes #N but no commit references the issue) | ⚠ traceability: partial — "no commit references #{N}" |
| Acceptance Criteria Verification block absent on a `/issue-resolver` PR | check 3 fails on a PR that does include a Decision Record | ⚠ traceability: partial — "Acceptance Criteria Verification block missing" |

The `Closes #{N}` failure is the only traceability outcome that **blocks** the soft-pass. All other partial outcomes are reported but do not block. This matches issue #36's contract: a PR missing `Closes #N` reports a traceability failure even if tests pass; a human-authored PR without a Decision Record reports `partial`, not `fail`.

When traceability fails on `Closes #{N}`, emit a fixable issue in Step 6 with `category: traceability`, `action: fix`, suggested fix: "Add `Closes #{N}` to the PR body."

## Refactor/chore exemption

Some PRs aren't tied to a single tracked issue — skill quality passes, dependency bumps, doc-only updates. Forcing each one to open a tracking issue purely to satisfy the `Closes #N` gate is workflow ceremony with no information gain. To accommodate this, check 1 (`Closes #N`) is **skipped** when either of the following holds:

1. The PR has any label whose name appears in `review.traceability_exempt_labels` (default: `["refactor", "chore"]`). Match is exact and case-sensitive against GitHub label names.
2. The PR body contains a line matching `review.traceability_exempt_pattern` (default: `"^\\s*Type:\\s*(refactor|chore)\\s*$"`, case-insensitive, evaluated multiline-anchored against the body). The line may appear anywhere in the body. The default is shown in YAML double-quoted form, so `\\s` is the correct value to copy into `.gitissue.yml`.

The exemption applies **only to check 1**. Checks 2-4 (commit reference, Decision Record, Acceptance Criteria Verification block) still run; their absence is reported as `partial`, never `fail`. Note that check 2 (`git log --grep="#{N}"`) is well-defined only when there is a tracked issue number; an exempt refactor/chore PR with no linked issue has no `#{N}` to grep for, so check 2 is reported as `n/a — no linked issue`, not `partial`. When an exempt PR _does_ have a linked issue (e.g., a refactor scoped under a tracking ticket) but no commit references it, the report is `○ pass — exempt; no commit references #{N} (note)`, not `fail`.

Report wording:

```
traceability:        ○ pass — exempt (refactor/chore PR; no Closes #N required)
```

If checks 2-4 produce partial findings on an exempt PR, append them as in the human-authored case:

```
traceability:        ○ pass — exempt (refactor/chore PR; no Closes #N required);
                       no commit references #{N}
```

To **disable** the exemption entirely (restore the strict issue #36 behavior), set `traceability_exempt_labels: []` and `traceability_exempt_pattern: ""` in `.gitissue.yml`.

The exemption check runs before the four traceability checks; if a PR matches, log which mechanism matched (label name or pattern) so reviewers can audit the decision in the report.
