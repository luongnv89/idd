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

## Two-axis grouping — Spec vs Standards

The five dimensions are reported under **two named axes** that separate *does the PR do the right thing* from *does the PR follow our conventions*. A clean implementation of the wrong thing should not hide behind good style, and correct behavior should not be blocked by a convention nit — so the axes are reported separately. (Matt Pocock's two-axis review framing; plan reference P4.)

| Axis | Question | Dimensions grouped under it |
|------|----------|------------------------------|
| **Spec axis** | Does the PR satisfy the issue's acceptance criteria — does it do the right thing? | `acceptance_criteria`, `correctness`, `safety` |
| **Standards axis** | Does the PR follow documented project conventions? | `traceability`, `maintainability` |

Rationale for the split: `acceptance_criteria` is the literal Spec contract; `correctness` is "does the implementation actually do the right thing"; `safety` (security, crash paths, edge cases) is correctness-of-behavior, so it sits on Spec, not on convention conformance. `traceability` (`Closes #N`, Decision Record, commit references) and `maintainability` (code quality, test coverage, style, a11y/interaction conventions) are conformance to documented project conventions, so they sit on Standards.

**The axes are a presentation grouping only — they change nothing about analysis or gating.** The same findings, the same `action: "fix" | "note"` semantics, and the same per-dimension `pass`/`partial`/`fail` status rules apply unchanged. With `review.soft_pass: true`, `acceptance_criteria: fail` and a missing `Closes #N` are the only hard-blocks; with `review.soft_pass: false`, every note or partial is also a strict blocker. It is **not** recomputed as "Spec axis fail" or "Standards axis fail". Do not derive a per-axis verdict that gates the loop — the axis headers organize the report, the per-dimension statuses gate the configured pass.

When the verification gates disable a dimension (`review.require_acceptance_criteria_check: false` or `review.require_traceability_check: false`), that dimension still appears under its axis, reported as `pass — verification disabled`. A disabled dimension never changes which axis the others sit under.

## Acceptance-criteria verification (per criterion)

> Run only when `review.require_acceptance_criteria_check` is `true`. When `false`, skip this entire subsection and emit `○ acceptance_criteria: pass — verification disabled (review.require_acceptance_criteria_check: false)`.

Fetch the linked issue and parse its `## Acceptance Criteria` section into individual checklist items. For each criterion, evaluate against the PR diff and produce one of three statuses:

| Status | When |
|--------|------|
| `pass` | The PR demonstrably satisfies the criterion. Evidence is required: a file path with line range, a test name, or a one-line description of how the change fulfills the criterion. For **bug** issues, evidence for the fixed-symptom criterion MUST cite the Decision Record **Reproduction** line (command and red→green path), not only a checkmark. |
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
- No fails, but at least one `unverified` → ⚠ acceptance_criteria: partial (report-only when `review.soft_pass: true`; strict blocker when `false`)
- No criteria defined → ○ acceptance_criteria: pass (with the "manual review recommended" note)

Each `fail` criterion becomes a fixable issue in Step 6 with `category: acceptance_criteria`, `action: fix`, evidence as the description, and the criterion text as the suggested fix target.

## Traceability checks

> Run only when `review.require_traceability_check` is `true`. When `false`, skip this entire subsection and emit `○ traceability: pass — verification disabled (review.require_traceability_check: false)`.

Per the dual-write rule (see *Analysis Artifacts and Durable Memory* in `docs/idd-methodology.md`), the durable analysis signal must survive the squash-merge into git history. Run the following four checks against the PR body, the commits in the PR, and the repo's merge configuration:

1. **Issue link** — PR body contains `Closes #{N}`, `Fixes #{N}`, or `Resolves #{N}` for the linked issue. Detected with the same regex used by GitHub itself: `(?i)(close[sd]?|fix(e[sd])?|resolve[sd]?)\s+#\d+`. See *Refactor/chore exemption* below — the `Closes #N` requirement is relaxed for refactor/chore PRs (the other three checks still run).
2. **Commit references issue** — at least one commit between base and head references the issue number:
   ```bash
   git log "{base_branch}..{head_branch}" --grep="#{N}" --oneline
   ```
   The reference may live in the subject or body. A reference inside a `Co-authored-by:` trailer does not count.
3. **Durable analysis fields in PR body** — the PR body contains a `## Decision Record` section with the five stable labels (`Root cause`, `Options considered`, `Options rejected`, `Selected option`, `Residual risk`) and a `## Acceptance Criteria Verification` section (table or the explicit `No acceptance criteria defined` note). The labels are the contract — match them as exact strings, do not rewrite. For **bug** issues linked to the PR, the Decision Record MUST also include a **`Reproduction`** line (success or `not reproduced — …` degraded shape). Absence on a bug PR → `traceability: partial` with "Reproduction line missing on bug PR".
4. **Squash-commit binding** — check 3 proves the durable record is in the PR body; only the platform's squash-commit *message source* decides whether it reaches git history. On GitHub that is the repo's `squash_merge_commit_message` setting, and its default (`COMMIT_MESSAGES`) writes the list of commit subjects, not the PR body. **Read it; never infer it from check 3 or from the merge strategy** — that inference is the defect this check replaced (issue #295):
   ```bash
   gh api repos/{owner}/{repo} --jq '{squash_merge_commit_title, squash_merge_commit_message}'
   ```
   That read goes through `gh api` rather than `--json` field selection because `gh repo view --json squashMergeCommitMessage` returns `Unknown JSON field` (`docs/platform-github.md` → *Operation catalog* → *Preflight*). Outcomes:
   - `squash_merge_commit_message == PR_BODY` → the binding holds; check 4 passes and check 3's fields are the durable record.
   - Any other value → the **B1** binding is defeated: report `partial`, name the observed value, and say the record will not reach git history *via B1*. Scope the wording to B1 rather than asserting it reaches git history by no route at all: this check can only test B1, and a repo that keeps durable memory through B2 (merge-commit body) or B3 (git notes) instead is not defeated by a non-`PR_BODY` value. There is no declared-binding key to read — `.gitissue.yml` has none — so the check does not branch on one; such a repo reads the finding as informational, or turns the dimension off with `review.require_traceability_check: false`.
   - **A read that does not answer is not a pass.** If the call fails (no `gh`, unauthenticated, 404, insufficient permission) or the response carries no such field, report `partial — squash-merge binding unverified` with the reason. Never degrade to `pass`: asserting an unread binding is exactly the failure this check exists to catch.

   Both non-`pass` outcomes are properties of the **repository**, not of the PR. They are `note` findings only — never emit them as `action: fix` findings, because no change to this PR can satisfy them and the remedy is a repo-settings mutation an unattended fixer must not make. Name the fix in the report for a human instead: `gh api -X PATCH repos/{owner}/{repo} -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY`. Both flags are required — GitHub pairs `PR_BODY` only with `PR_TITLE`, so sending the message alone against the default `COMMIT_OR_PR_TITLE` fails with HTTP 422 `invalid_squash_commit_setting_combo`.

**Pass/partial/fail rule for the dimension:**

| Outcome | Conditions | Status |
|---------|-----------|--------|
| All four checks pass | Closes #N + commit ref + Decision Record + AC Verification block all present, **and** check 4 read `squash_merge_commit_message: PR_BODY` | ✓ traceability: pass |
| Squash-merge binding defeated | checks 1-3 pass; check 4 read a `squash_merge_commit_message` other than `PR_BODY` | ⚠ traceability: partial — "squash-merge binding defeated (`squash_merge_commit_message: {value}`) — the durable record will not reach git history via B1" |
| Squash-merge binding unverified | check 4's read did not answer: no `gh`, unauthenticated, 404, insufficient permission, or the field is absent | ⚠ traceability: partial — "squash-merge binding unverified ({reason})" |
| `Closes #{N}` absent on a refactor/chore-exempt PR | check 1 skipped via the *Refactor/chore exemption* below; checks 2-4 still run | ○ traceability: pass — exempt (refactor/chore PR; no Closes #N required), with any check 2-3 partial findings appended. A non-`pass` **check 4** is not exempt-able and holds the dimension at ⚠ partial |
| `Closes #{N}` absent | check 1 fails (regardless of other checks) | ✗ traceability: fail (blocking — see below) |
| Decision Record absent on a human-authored PR | check 3 partially fails: PR was not produced by `/issue-resolver` and has no Decision Record | ⚠ traceability: partial — "PR not produced by `/issue-resolver`; Decision Record absent" |
| Commit reference absent | check 2 fails but check 1 passes (PR body has Closes #N but no commit references the issue) | ⚠ traceability: partial — "no commit references #{N}" |
| Acceptance Criteria Verification block absent on a `/issue-resolver` PR | check 3 fails on a PR that does include a Decision Record | ⚠ traceability: partial — "Acceptance Criteria Verification block missing" |

When `review.soft_pass: true`, the `Closes #{N}` failure is the only traceability outcome that **blocks** the soft-pass; other partial outcomes are reported but do not block. When `review.soft_pass: false`, those partial outcomes are strict blockers too (but remain non-fixer `note` findings). The two check-4 outcomes get **no exception** from that rule, and none from the refactor/chore exemption either: under strict mode a defeated or unverified binding blocks, and it is meant to — a repo that has opted into strict review has said an unsatisfied convention is not shippable, and this one is unsatisfied at the repo level. The remedy is the one-line `gh api -X PATCH` in check 4, run by someone with admin rights; a repo that would rather not gate on it sets `review.soft_pass: true` (the default) or `review.require_traceability_check: false`. This matches issue #36's contract: a PR missing `Closes #N` reports a traceability failure even if tests pass; a human-authored PR without a Decision Record reports `partial`, not `fail`.

When traceability fails on `Closes #{N}`, emit a fixable issue in Step 6 with `category: traceability`, `action: fix`, suggested fix: "Add `Closes #{linked_issue}` to the PR body." The fix string names `{linked_issue}` and not `{N}` on purpose. It is the one `{N}` in this file that is emitted into `findings_json` and handed to the fixer (`shared/agents/fixer.md`), which carries no copy of this procedure and reads the string as written; there `{N}` is the PR number, and check 1's `#\d+` accepts any number, so a rendered `Closes #<PR>` would silently false-pass the gate that emitted the finding.

## Refactor/chore exemption

Some PRs aren't tied to a single tracked issue — skill quality passes, dependency bumps, doc-only updates. Forcing each one to open a tracking issue purely to satisfy the `Closes #N` gate is workflow ceremony with no information gain. To accommodate this, check 1 (`Closes #N`) is **skipped** when either of the following holds:

1. The PR has any label whose name appears in `review.traceability_exempt_labels` (default: `["refactor", "chore"]`). Match is exact and case-sensitive against GitHub label names.
2. The PR body contains a line matching `review.traceability_exempt_pattern` (default: `"^\\s*Type:\\s*(refactor|chore)\\s*$"`, case-insensitive, evaluated multiline-anchored against the body). The line may appear anywhere in the body. The default is shown in YAML double-quoted form, so `\\s` is the correct value to copy into `.gitissue.yml`.

The exemption applies **only to check 1**. Checks 2-4 still run; a missing commit reference or Decision Record is reported as `partial`, never `fail`. Check 4 has no "absent" mode — its non-`pass` outcomes are *defeated* and *unverified*, and neither is exempt-able, because the exemption is about this PR's link to an issue while check 4 is about the repository. **A non-`pass` check 4 keeps the dimension at `partial` even on an exempt PR**: rendering `pass — exempt` over a defeated binding would be the same "report pass on an unread binding" this check exists to end. Note that check 2 (`git log --grep="#{N}"`) is well-defined only when there is a tracked issue number; an exempt refactor/chore PR with no linked issue has no `#{N}` to grep for, so check 2 is reported as `n/a — no linked issue`, not `partial`. When an exempt PR _does_ have a linked issue (e.g., a refactor scoped under a tracking ticket) but no commit references it, the report is `○ pass — exempt; no commit references #{N} (note)`, not `fail`.

Report wording:

```
traceability:        ○ pass — exempt (refactor/chore PR; no Closes #N required)
```

If checks 2-3 produce partial findings on an exempt PR, append them as in the human-authored case (check 4 is not appended — a non-`pass` check 4 holds the dimension at `partial`):

```
traceability:        ○ pass — exempt (refactor/chore PR; no Closes #N required);
                       no commit references #{N}
```

To **disable** the exemption entirely (restore the strict issue #36 behavior), set `traceability_exempt_labels: []` and `traceability_exempt_pattern: ""` in `.gitissue.yml`.

The exemption check runs before the four traceability checks; if a PR matches, log which mechanism matched (label name or pattern) so reviewers can audit the decision in the report.
