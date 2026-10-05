# /issue-creator — Examples

## Review contract

Apply this contract to Create, Normalize, and Batch terminal reports, including
dry runs, cancellations, skipped issues, and failures. It supplements their step
summaries and precedes the Run Stats Footer. Preserve the caller's existing
authorization; this contract adds no approval gate.

### Report the observed outcome

1. Start with the result and completion status: `DONE`, `PARTIAL`, `BLOCKED`,
   `CANCELLED`, `SKIPPED`, or `DRY RUN`. State what changed. A preview or approval
   is not a completed write. For a batch, account for every input item as created,
   removed by the user, failed, or not attempted.
2. Give evidence for each material claim. Link created or updated issues and
   identify the checks actually performed. Verify writes with an uncached read
   through docs/platform-github.md. Compare saved title/body with the intended
   content; verify labels when applied. For Normalize, also cite the verified
   backup. A successful command or a normalization marker alone cannot establish
   that the complete requested content was saved.
3. State material uncertainty beside the result. Label inferred fields with
   their confidence, unresolved duplicates as possible matches, and incomplete
   or truncated duplicate scans as limited coverage. Report failed uploads,
   unverified writes, and project/checklist warnings separately. Issue creation
   does not establish that the reported bug was reproduced or fixed.
4. State the next decision. If the authorized work is finished, say
   `No approval needed.` Name any remaining action separately. On partial or
   blocked runs, identify the affected items and the precise retry or repair
   step. If a create may have succeeded but verification failed, reconcile it
   with a live read before retrying; do not risk creating another copy.

Use concise text for one issue and a per-item table or list for a batch. Keep
the result and material uncertainty visible before the detailed step statuses.
Do not generate an interactive report for these short operation summaries.
Honor a requested alternative format while retaining the four items above.

Example, with an unresolved duplicate:

```text
◆ Issue Created — DONE: #42, Fix mobile auth redirect loop
  Evidence: uncached read confirmed the intended title, body, and labels.
  https://github.com/owner/repo/issues/42
  Uncertainty: #15 remains a possible duplicate; bug reproduction untested.
  No approval needed. Remaining action: review the possible duplicate.
```

If a write cannot be verified, use `PARTIAL` or `BLOCKED` as appropriate and
name the uncertainty; never print the successful example unchanged. A dry run
reports the preview as evidence and explicitly says that no changes were applied.

### Evaluate report understanding

When evaluating actual skill outputs, check all four criteria below in addition
to issue-body correctness. Exclude negative-trigger cases where no skill runs.

| Criterion | Observable check |
|---|---|
| Result is findable | Opening text states status and outcome; batch counts reconcile with every item. |
| Facts and assumptions are separate | Verified writes cite observed reads; inferred fields, scan limits, and untested behavior are labeled. |
| Claims are traceable | Issue/backup links and observed checks support the claimed scope; partial success never becomes an overall success claim. |
| Next decision is clear | The report names a required decision or says no approval is needed, and lists remaining actions. |

For repository evals, extend the existing `grade` assertions for the basic
issue-creator case to inspect its report artifact. That case uses a deterministic
stand-in: passing it verifies the fixture contract, not an agent following this
skill. In live behavioral evaluations, grade the agent's own report and recorded
tool results against the same criteria.

Ask human reviewers whether they could find the result, separate facts from
assumptions, trace claims, and identify the next decision. Record their answers
in the evaluation's feedback record. Missing, blank, or nonresponsive feedback
leaves human understanding **unconfirmed**; automated checks do not confirm it.

---

Full example runs for batch creation and vague-description scenarios.

## Example: Batch from a planning document

**User says:** `/issue-creator` followed by:
```
Here are the items from our sprint planning:
1. Fix the Safari checkout redirect bug — payments fail on iOS Safari
2. Add dark mode toggle to the settings page
3. Refactor auth middleware to support OAuth2
```

1. Detect → 3 items from numbered list
2. Preview table → 3 rows with types and effort estimates
3. Duplicates → none found
4. Approval:
   ```
   ● Parsing input...
     Found 3 items in input

   ◆ Batch Preview
   ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
     #  │ Type        │ Title                              │ Effort
     ───┼─────────────┼────────────────────────────────────┼───────
     1  │ bug         │ Fix Safari checkout redirect        │ S
     2  │ feature     │ Add dark mode toggle                │ M
     3  │ improvement │ Refactor auth middleware for OAuth2  │ L

   Create 3 issues? [A]ll / [e]dit / [c]ancel
   ```
5. On "All" → create each → `✓ 3/3 issues created`

---

## Example: Create from a vague description

**User says:** `/issue-creator the checkout page is broken on Safari`

1. Parse → keywords: "checkout", "broken", "Safari"; type: bug
2. Classify → bug (high confidence)
3. Duplicates → none found
4. Generate → populates bug.md template with Safari-specific acceptance criteria
5. Preview:
   ```
   ◆ Issue Preview
   ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
     Type:     bug (high)
     Title:    Fix checkout page broken on Safari
     Labels:   bug, checkout
     Criteria: 3 acceptance criteria generated (medium)

   Create issue? [Y/n]
   ```
6. On confirmation → `gh issue create` → `✓ Created issue #15`

