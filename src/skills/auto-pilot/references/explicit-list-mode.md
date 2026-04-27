# /auto-pilot — Explicit List Mode

Detail of the explicit `--issues` mode, extracted from SKILL.md to keep the main file focused. Read this when the user passes `--issues`.

## Explicit List Mode

When `--issues` is provided, the triage phase is replaced by an analysis & optimization phase that finds the smartest way to resolve the given issues:

### Parsing the issue list

Accept issue numbers as:
- Comma-separated: `--issues 5,10,12`
- Space-separated: `--issues 5 10 12`
- Hash-prefixed: `--issues #5,#10,#12`
- Mixed: `--issues #5, 10, #12`

Strip `#` prefixes and whitespace. Deduplicate while preserving order (first occurrence wins). Remove any issues in the `--skip` list.

If the list is empty after dedup and skip removal:
```
✗ No issues to process

  The issue list is empty after removing duplicates and skipped issues.
  To fix:  provide at least one issue number: /auto-pilot --issues 5,10
```
Stop.

### Validate issues upfront

Before starting the loop, validate all issues in one batch:

```bash
gh issue view {N} --json number,title,state,labels,assignees
```

For each issue, check:
- **Exists** — if not found, warn and remove from list
- **Open** — if closed, warn and remove from list
- **Not skip-labeled** — if labeled with a `skip_labels` value, warn and remove

```
● Validating issue list...
  ✓ #5  — Fix login crash (open)
  ⚠ #10 — Add dark mode (closed, removing)
  ✓ #12 — Refactor auth module (open)
```

If all issues are invalid:
```
✗ No valid issues to process

  All issues in the list are closed or not found.
```
Stop.

### Analysis & Optimization

After validation, the auto-pilot analyzes all issues to find the smartest resolution strategy. The goal: resolve the maximum number of issues with the minimum number of changes by identifying dependencies, shared files, and batching opportunities.

```
● Analyzing {valid_count} issues for optimal resolution strategy...
  ⟶ Spawning analyzer subagent...
```

Spawn the **Analyzer Subagent** (see `references/subagent-prompts.md`) with the full list of validated issue numbers. The analyzer:

1. **Runs `/issue-analysis` on each issue** — identifies affected files, root causes, complexity, and implementation approach
2. **Builds a dependency graph** — issue A's fix may conflict with or depend on issue B's fix (e.g., both touch `auth.js`)
3. **Detects batch opportunities** — issues that share affected files or have related root causes can often be resolved together in a single PR with fewer total changes
4. **Computes optimal order** — topological sort considering: dependencies first, then batch groups together, then independent issues by complexity (simplest first)

### Handling analyzer results

**On success**, the analyzer returns:
- `optimized_order`: array of issue numbers in recommended resolution order
- `batches`: array of batch groups, each with `issues` (numbers that should be resolved together) and `reason` (why they batch well)
- `dependencies`: array of `{issue, depends_on, reason}` explaining ordering constraints
- `analysis_summary`: one-line-per-issue summary of affected files and complexity

**On failure** (analyzer subagent returns failure or times out), fall back gracefully. Output the error from `references/error-messages.md`:
```
⚠ Issue analysis failed — falling back to user-defined order

  The analyzer could not complete analysis for all issues.
  Proceeding with original order without batching optimization.
```
Set `optimized_order` to the original validated list, `batches` to empty, and proceed to Confirmation. The auto-pilot still works — it just loses the optimization.

**On partial failure** (analyzer could not analyze a specific issue), output for each failed issue:
```
⚠ Could not analyze #{N} — excluded from batching

  Issue #{N} will be resolved individually in its original position.
```
Exclude that issue from any batch groups but keep it in the `optimized_order` at its original position.

### Displaying analysis results

On success, display the analysis results:

```
◆ Analysis Results
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Issues analyzed:  {valid_count}

  Dependencies detected:
  ● #{a} must come before #{b} — {reason}

  Batch opportunities:
  ⚡ #{x}, #{y} share {N} files — can batch-resolve together
  ⚡ #{p}, #{q} have related root cause — can batch-resolve together

  Optimized resolution order:
  1. #{n1} — {title1} {complexity}
  2. #{n2} — {title2} {complexity} (batched with #{n1})
  3. #{n3} — {title3} {complexity}
```

If no dependencies or batching opportunities are found, the original user-defined order is preserved:
```
  ○ No dependencies or batching opportunities detected
  ○ Using user-defined order
```

### Execution Plan (auto-start)

Display the execution plan and immediately begin — no confirmation prompt. The user invoked `/auto-pilot` with an explicit list, so intent is clear.

Compute `saved_iterations` as: sum of `(batch.issues.length - 1)` across all batches. Each batch of N issues resolves them in 1 iteration instead of N, saving N-1 iterations. If there are no batches, omit the `Batches:` line entirely.

```
◆ Auto-Pilot Plan (explicit list)
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Issues to process:  {valid_count} (of {original_count} provided)
  Review cycles:      {review_cycles}
  Auto-merge:         {yes/no}
  Mode:               explicit list (analyzed + optimized)
  Batches:            {batch_count} (saving ~{saved_iterations} iterations)

  Optimized execution order:
  1. #{n1} — {title1}
  2. #{n2} — {title2} (batched with #{n1})
  3. #{n3} — {title3}

  ⟶ Starting immediately...
```

If `--dry-run`:
```
○ Dry run complete. No issues resolved.
```
Stop.

### Loop behavior

In explicit list mode, the loop iterates through the **optimized** order (not the original user order). Phase 1 is replaced: instead of triaging and picking, advance to the next issue (or batch) in the optimized list.

#### Batch detection

Before starting the loop, build a **batch lookup map** from the analyzer's `batches` array. For each batch group, map every issue number in the group to its co-batch partners:

```
batch_map = {}
for batch in analyzer.batches:
    for issue in batch.issues:
        batch_map[issue] = batch  # includes all co-batch issues + reason + shared_files
```

Also maintain a `processed` set (initially empty) that tracks which issues have been resolved — either individually or as part of a batch.

When advancing to the next item in `optimized_order`:
1. **If already processed** (in the `processed` set): emit a skip line and advance:
   ```
   ○ [Issue {i}/{total}] #{N} — already resolved in batch with #{batch_primary}
   ```
2. Check `batch_map` — is this issue number part of a batch?
3. **If yes**: collect all co-batch issue numbers, use the **Batch Resolver Subagent** (see `references/subagent-prompts.md`). Do NOT pre-mark issues as processed — wait for the resolver result (see "Processing batch resolver results" below) to determine which issues were actually resolved.
4. **If no**: use the standard Resolver Subagent for a single issue. On success, add the issue to the `processed` set.

For batched issues, the resolver subagent receives all issue numbers in the batch:

```
● [Issue 1/3] Resolving #{n1} (+ batched: #{n2})...
  ⟶ Spawning batch resolver subagent...
```

The batch resolver creates a single branch and PR that addresses all issues in the batch. The PR body includes `Closes #{n1}` and `Closes #{n2}` for each issue in the batch.

**Processing batch resolver results:**

- **Full success** (`issues_resolved` contains all batch issues): add all batch issues to the `processed` set. After merge, they are skipped when encountered later in `optimized_order`.
- **Partial success** (`issues_resolved` is a subset of the batch): the PR addresses some but not all issues. Add only the resolved issues to the `processed` set. For unresolved issues, remove them from the `batch_map` so they are treated as individual issues when encountered later in `optimized_order`:
  ```
  ⚠ Batch partially resolved: #{n1} addressed, #{n2} not addressed
    #{n2} will be resolved individually
  ```
- **Full failure** (`status: "failure"`): remove all issues in this batch from `batch_map` so they are treated as independent issues, then fall back to resolving each one individually (standard Resolver Subagent, one at a time):
  ```
  ⚠ Batch resolve failed for #{n1}, #{n2} — resolving individually
  ```

For non-batched issues, the flow is identical to before:

```
● [Issue 3/3] Resolving #{n3}...
```

The `[Issue {i}/{total}]` counter reflects total issues (not batches), so the user can track overall progress.

All other phases (Resolve, Review, Fix, Merge) run identically to triage mode.

### Re-triage between iterations

Explicit list mode does **not** re-triage between iterations. The analysis determined the order upfront — respect it. The only per-iteration pre-work is syncing to the default branch (Step 2.1).

