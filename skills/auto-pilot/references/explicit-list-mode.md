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

Before starting the loop, validate every issue and retain the complete resolution
snapshot that the canonical post-selection capture step consumes:

```bash
gh issue view {N} --json number,title,body,state,labels,assignees,updatedAt
```

Store successful replies in `explicit_issue_records[N]`. This is explicit-list
mode's one **resolution-boundary body snapshot**. **Before spawning the
analyzer**, invoke the canonical mode-neutral *Step 1.2b — Capture
the caller payload* in `references/phases.md` once for the complete retained map:
validate every record, compact-serialize the map, and nonce-frame it for that
spawn. The analyzer and dependency ordering project from this captured map rather
than fetching bodies again. After optimization selects an individual or batch,
project its already-validated matching record(s) into a newly nonce-framed spawn
block without another body read or record-validation pass. An individual gets one
record; a batch gets a map keyed by issue number. This projection is still only
tentative: analyzer time creates a concurrent-edit window, so resolver Step 0i
compares each retained `updatedAt` with its mandatory live probe before any body
rewrite. A mismatch/missing/unparsable timestamp discards only that record and
runs the ordinary complete refreshed 0a fetch; siblings are unaffected.

For each issue, check:
- **Exists** — if not found, warn and remove from list
- **Open** — if closed, warn and remove from list
- **Not skip-labeled** — if labeled with a `skip_labels` value, warn and remove.
  **One exemption: `autopilot.quarantine_label`.** It is in the effective
  `skip_labels` set SKILL.md's *Configuration* step builds, so removing it here
  is what this step would otherwise do — and that would answer an issue the user
  named by hand with a line in a validation banner and nothing else. Keep a
  quarantined issue in the list; *Loop behavior* below owns that skip, and owning
  it there is what gives it an `[Issue {i}/{total}]` slot and its one run-log
  line. Nothing else is exempt: `wontfix` and the rest are still removed here.

```
● Validating issue list...
  ✓ #5  — Fix login crash (open)
  ⚠ #10 — Add dark mode (closed, removing)
  ✓ #12 — Refactor auth module (open)
  ○ #14 — Flaky import path (quarantined, keeping — skipped at its turn)
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
Stop. **The stop belongs ahead of the first persisted write, not after it** — the
same reordering Phase 1 applies (`references/phases.md` → *Step 1.1*): under
`--dry-run` the analysis is computed and printed but nothing is persisted, the
run lock is taken with `--dry-run` (reporting a holder, creating nothing), and
every run-state write carries `--dry-run` too. A dry run leaves the repository
byte-identical apart from the transient scratch file under `.gitissue/cache/`
that the same step deletes.

### Loop behavior

In explicit list mode, the loop iterates through the **optimized** order (not the original user order). Phase 1 triage is replaced: advance to the next issue (or batch), then project the selected record(s) from the complete map that *Step 1.2b* captured before analyzer spawn. Reframe for the new spawn nonce, but do not validate or read a body again.

#### Batch detection

Before starting the loop, build a **batch lookup map** from the analyzer's `batches` array. For each batch group, map every issue number in the group to its co-batch partners:

```
batch_map = {}
for batch in analyzer.batches:
    for issue in batch.issues:
        batch_map[issue] = batch  # includes all co-batch issues + reason + shared_files
```

Also maintain a `processed` set (initially empty) that tracks which issues have been resolved — either individually or as part of a batch.

**`processed` and the session skip list are run-state fields, not pure memory.**
Both live in `.gitissue/run-state.json` (`processed[]`, `skip_list[]`) and are
appended de-duplicated at each end-of-iteration checkpoint
(`references/phases.md` → *Step 1.0b*, *End-of-iteration checkpoint*). The
in-memory copies stay the working set — every lookup above reads them — but a
resumed run seeds them from the state file, which is the only reason a crash
mid-batch does not re-resolve issues that already landed. When `gi-state.py` is
unavailable they degrade to exactly what they were before: in-memory sets that
do not survive the run.

**Quarantine is honored in this mode too — and this loop is the single step that
applies it.** Explicit list mode bypasses Phase 1 entirely, so nothing here
inherits *Step 1.2*'s pick predicate, and *Validate issues upfront* deliberately
exempts `autopilot.quarantine_label` from the removal it applies to every other
skip label. That leaves exactly one owner, which is the point: two steps skipping
the same input would give it two dispositions and two different
`[Issue {i}/{total}]` totals. Before resolving any listed issue, check its labels
for `autopilot.quarantine_label` and, if present, skip it with
`skipped_reason: quarantined` — one slot in the counter and **one** run-log line,
the disposition every ordinary skip gets (*Run-log fan-out for the batch* names
`quarantined` among them). A user who explicitly lists a quarantined issue is
telling the loop to try it again, so say so in the skip line — removing the label
is the documented way to do that:

```
○ [Issue {i}/{total}] #{N} — quarantined ({quarantine_label}); remove the label to retry
```

**The gate covers a batch's co-members, not only the slot's own issue.** A
quarantined issue that *Validate issues upfront* kept in the list can also sit in
an analyzer batch group, and a batch resolves **every** member at the spawn
position's turn — so a gate that read only the slot's own number would let a
quarantined co-member be resolved at another issue's turn and never reach its own
gate at all. Run the check over the whole set the Batch Resolver would receive —
the slot's issue plus every co-batch number `batch_map` holds for it — **before**
the spawn (*Batch detection* step 3), and give each quarantined number exactly one
disposition:

- **Remove it from its batch group in `batch_map`** first, so no later spawn can
  pull it back in either. Because the removal happens before the spawn, the
  *attempted set* the run-log fan-out is keyed on never contains it and that
  invariant needs no exception.
- **The slot's own issue** — the skip is this slot: print the line above, write
  its one run-log line, and advance. Whatever is left of the group keeps its
  batch; the next unprocessed member's slot becomes its spawn position.
- **A co-batch member** — nothing is printed or logged here, it is only dropped
  from the batch. Its own `optimized_order` slot is where the line above and its
  single run-log line are produced. That slot is always still ahead: the spawn
  position is the **first** member of the group `optimized_order` reaches, so
  every co-member sits later and none has had its slot consumed.
- **Fewer than two issues left after the drops** — there is no batch to resolve.
  Use the standard single-issue Resolver on the survivor (step 4), not the Batch
  Resolver.

`[Issue {i}/{total}]` still adds up: `total` is the validated issue count and a
drop removes no slot from `optimized_order`, so a quarantined issue consumes
exactly one `i` and writes exactly one run-log line — never zero (silently
resolved inside someone else's batch) and never two (skipped at the spawn *and*
at its own turn).

The write side is unchanged: a failure inside this mode runs the same *Quarantine
after repeated failures* procedure in `references/phases.md`.

When advancing to the next item in `optimized_order`:
1. **If already processed** (in the `processed` set): emit a skip line and advance.
   This skip is **display only** — it writes **no** `.gitissue/runs.jsonl` line,
   because the issue was already logged once at batch time (see *Run-log fan-out for
   the batch* — the last row of its disposition table). It is the single
   exception to logging every processed issue:
   ```
   ○ [Issue {i}/{total}] #{N} — already resolved in batch with #{batch_primary}
   ```
2. Check `batch_map` — is this issue number part of a batch?
3. **If yes**: collect all co-batch issue numbers and **run the quarantine gate
   above over that whole set before spawning anything** — every quarantined
   number is dropped from `batch_map` and is never sent to the resolver. Then use
   the **Batch Resolver Subagent** (see `references/subagent-prompts.md`) on what
   is left, or step 4's single-issue Resolver if the drops left only one. Do NOT
   pre-mark issues as processed — wait for the resolver result (see "Processing
   batch resolver results" below) to determine which issues were actually
   resolved.
4. **If no**: use the standard Resolver Subagent for a single issue. On success, add the issue to the `processed` set.

For batched issues, the resolver subagent receives all issue numbers in the batch:

```
● [Issue 1/3] Resolving #{n1} (+ batched: #{n2})...
  ⟶ Spawning batch resolver subagent...
```

The batch resolver creates a single branch and PR that addresses all issues in the batch. The PR body includes `Closes #{n1}` and `Closes #{n2}` for each issue in the batch.

**Processing batch resolver results:**

- **Full success** (`issues_resolved` contains all batch issues): add all batch issues to the `processed` set. After merge, they are skipped when encountered later in `optimized_order`.
- **Partial success** (`issues_resolved` is a subset of the batch): the PR addresses some but not all issues. Add only the resolved issues to the `processed` set. For every unresolved issue, **re-queue it for individual resolution** — remove it from `batch_map` and ensure it still has a turn in `optimized_order`. This **includes the batch's primary (spawn-position) issue** if it is unresolved: the primary occupies the batch's own slot in `optimized_order`, which has already been consumed, so a removed-but-not-re-appended primary would never be re-encountered and would silently drop (zero run-log lines — see the fan-out section below). Append any unresolved issue that has no remaining slot (the primary always; any co-batch member whose position was already passed) to the end of `optimized_order` so it is resolved individually:
  ```
  ⚠ Batch partially resolved: #{n1} addressed, #{n2} not addressed
    #{n2} will be resolved individually
  ```
- **Full failure** (`status: "failure"`): remove all issues in this batch from `batch_map` so they are treated as independent issues, then fall back to resolving each one individually (standard Resolver Subagent, one at a time). As in the partial case, **re-queue the primary too** — append any batch issue whose `optimized_order` slot was already consumed (the primary always) to the end so none are dropped:
  ```
  ⚠ Batch resolve failed for #{n1}, #{n2} — resolving individually
  ```

#### Run-log fan-out for the batch (one line per attempted issue)

The Batch Resolver runs with `--no-run-log` (see *Batch Resolver Subagent* in
`references/subagent-prompts.md`), so auto-pilot is the single writer here too.
A batch resolves N issues in one PR, but the contract is **one line per processed
(attempted) issue**, not per PR or per batch — so auto-pilot fans the one returned
result out. The **attempted set** is the issue numbers sent into the Batch Resolver
(what `batch_map` holds at spawn); the invariant is keyed on that set and **never**
on `issues_resolved` (success-only keying would drop processed-but-failed issues —
the inverse under-count #156/#158 exist to kill).

The invariant holds **across the whole auto-pilot run**, not at batch time: an
attempted issue is logged here if it resolved here, and at its individual retry
otherwise. Never both (double-count) and never neither (drop).

| Disposition of an attempted issue | Batch-time line? | Where its one line comes from |
|---|---|---|
| In `issues_resolved`, batch PR merged this iteration | yes — `outcome: merged` | this batch |
| In `issues_resolved`, PR left open | yes — `outcome: left_open` | this batch |
| Not in `issues_resolved` (partial or full failure) | **no** — no unresolved issue is ever written a `failed` line at batch time | its individual retry, after re-queuing |
| Later skipped as `already resolved in batch` | no — display only | already logged at batch time |

Writing a `failed` batch line for an unresolved issue **and** letting its
individual retry log it would double-count it — the exact
double-count this fix removes. It is strictly one-or-the-other, resolved by disposition:
**resolved-here → logged here; unresolved → logged at its retry, never here.**

**Re-queue every unresolved attempted issue — including the batch's primary
(spawn-position) issue. Re-queuing the primary is mandatory and is the half that
is easy to miss:** the primary sits at the batch's own slot in `optimized_order`,
which has already been consumed, so without an explicit re-append to the end of
`optimized_order` it has no later turn and would drop to **zero** lines (the
inverse under-count criterion 5 forbids, and the failure the #158 Technical Notes
name: "a failed batch drops fully-processed issues").

**An in-batch skip writes no run-log line.** The last table row is the **one
exception** to auto-pilot's "log every processed issue including skips" rule: an *in-batch* skip is the already-counted other half
of a batch line, not a fresh processed issue. Ordinary skips —
`blocked_label`, `blocked_by_dependency`, `in_skip_list`, `assigned_to_other`,
`quarantined` — still log their one line with a `skipped_reason`.

Build each written line from `references/docs/run-log-schema.md`, with these batch attributions:

- **Shared fields on every line:** the batch `pr` (the one PR number) and `complexity`.
- **Scalar telemetry attributed once:** `qa_cycles` and `duration_s` describe the
  *whole batch*, so put them on **one line only — the primary (first) issue's
  line** — and omit them from the others. Writing them on all N lines would weight
  one batch N-fold in `/idd-doctor`'s median-QA-cycles and duration aggregates.

The Batch Resolver **returns** `qa_cycles`, `complexity`, and `duration_s` so
auto-pilot can populate them. Each append uses the same best-effort, non-fatal
`mkdir -p .gitissue` + single-`\n` rule as everywhere else — a failed append never
stops the loop. Append only; never rewrite prior lines.

For non-batched issues, the flow is identical to before:

```
● [Issue 3/3] Resolving #{n3}...
```

The `[Issue {i}/{total}]` counter reflects total issues (not batches), so the user can track overall progress.

All other phases (Resolve, Review, Fix, Merge) run identically to triage mode,
with one exception, and it is Phase 1 work rather than a fourth phase changing:
*Step 1.6 — Update the triage cache after a merge* is numbered in Phase 1 and
merely *executed* after a merge, so it is skipped here with the rest of Phase 1
(see *Re-triage between iterations* below).

### Re-triage between iterations

Explicit list mode does **not** re-triage between iterations. The analysis determined the order upfront — respect it. The only per-iteration pre-work is syncing to the default branch (Step 2.1).

Triage mode no longer re-triages every iteration either (issue #258): it triages once, reuses a `fresh` `.gitissue/triage.json`, and updates that payload in place after each merge. Explicit list mode remains the stronger form of the same property — it never triages at all, so there is no cache to keep current and no pick miss to recover from.

That is why *Step 1.6 — Update the triage cache after a merge* is skipped here, and the step's own note says so: with no payload this run wrote or read, a `.gitissue/triage.json` that is missing, stale, or absent is not a degrade. Skip it silently — no `⚠ Could not update the triage cache` line, and no `retriage_required` flag, which this mode has no *Step 1.1* to clear. Step 1.6's `Fail-safe: any doubt is "run it."` is a triage-mode rule; the mode is known at invocation, so reaching it here is never a doubt.

