# Step Completion Reports

Emitted after every phase.

```text
◆ [Phase Name] (phase N of 7 — [context])
··································································
  [Check 1]:          √ pass
  [Check 2]:          × fail — [reason]
  [Criteria]:         √ N/M met
  ____________________________
  Result:             PASS | FAIL | PARTIAL
```

## Per-phase check names

- **Preflight:** `Tools present`, `gh ready`, `Repo writable`, `API budget`, `Skills installed`,
  `Bundled files`, `Input resolved`
- **Parse / draft:** `Input resolved`, `Task count matches` (file path) or `Draft confirmed`
  (fresh conversation) or `Source restored` (`--epic` resume), `Fields complete`, `Deps
  resolvable`, `Critical path recorded`
- **Labels:** `Set computed`, `Existing checked`, `Missing created`, `Dropped recorded`
- **Epic:** `Existing epic checked`, `Epic created`, `Epic labelled`, `Source marker bound`
- **File issues:** `Batches run`, `Duplicates skipped`, `Labels applied`, `Parent markers present`,
  `Sub-issues registered`, `Dependency pass`
- **Plan map:** `Render exit 0`, `Sentinels intact`, `Every issue listed once`, `No status asserted`
- **Verify:** `Epic re-read`, `Children re-read`, `Repairs applied`, `Unresolved 0`
- **Sync (one report):** `Sentinels found`, `Children fetched`, `Unmapped listed`, `Map rewritten`

## Review contract

Apply these rules to the *Closing Summary* of every terminal outcome — a Create run, a `--dry-run`
preview, a `sync`, and an early stop. This skill files issues; it authorizes no change to code.

1. **Result first.** The first row after the header is `Result:` with one status and the main
   finding or stop reason:
   - `DONE` — every phase reported `PASS`, every completion criterion held on re-read, and nothing
     was dropped, degraded, or left unmapped.
   - `PARTIAL` — issues were filed (or the map re-rendered) but at least one row is `×` or `⚠`: a
     dropped label, a failed or unmapped task, sub-issues unavailable, a degraded script, an
     unknown dependency id, a repair that did not hold.
   - `BLOCKED` — the run stopped before the first mutation: a failed preflight group, an invalid
     config, a missing bundled file or `issue-creator`, unresolvable input, a declined draft, or a
     `sync` target with no sentinels.
   - `PREVIEW` — a `--dry-run`: the task table and map preview printed, nothing created.
2. **Evidence.** Name what was verified by re-reading, not by exit code: the epic body's marker and
   sentinels, the children count from the `Part of #<epic>` filter, the `sub_issues` length, and
   the renderer's exit. A `√` row is allowed only for a check that ran and passed.
3. **Uncertainty.** Name every degrade (TRIAGE permission, sub-issues unavailable, no `python3`),
   every dropped label, every `⚠ unknown dep`, every task that failed to file — by task id — and
   every `/issue-creator` field it marked `(needs review)`. Write `none` only when there is none.
4. **Decision.** What still needs a person: a multi-account confirm, a duplicate warning
   `/issue-creator` surfaced, an adoption prompt, a `> 100 tasks` confirm. `No approval needed.`
   when nothing does.
5. **Next action.** One command: the resume handle after a partial or conversation run
   (`/plan-to-issues --from-conversation --epic <n>`), the fix command after a stop, else
   `/issue-triage` to order the new backlog.

Never print `Result: DONE` with a `×` or `⚠` row above it.

## Closing Summary

```text
◆ Plan to Issues — {N} issues under epic #{epic}
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:      DONE — {N} filed under #{epic}, map rendered

  Source:      {kind} {value} ({phases} phases, {tasks} tasks{, draft confirmed})
  Epic:        #{epic} {title}
  Labels:      {required} required, {created} created, {dropped} dropped
  Issues:      {filed} filed, {skipped} skipped, {failed} failed
  Map:         {phases} phases, {milestones} milestones, critical path {path}
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Evidence:    epic re-read √ · {n}/{n} children re-read √ · sub_issues {n} · {repairs} repairs
  Uncertainty: {degrades, dropped labels, unknown deps, (needs review) fields — or none}
  Decision:    No approval needed.
  Next action: /issue-triage

  https://github.com/{owner}/{repo}/issues/{epic}
```

The `Source:` line is the only difference between input kinds: a plan file prints
`file MODERNIZATION_PLAN.md (...)`; a conversation prints `conversation "Harden the ingest path"
(1 phase, 6 tasks, draft confirmed)` and its `Next action` is the resume handle
`/plan-to-issues --from-conversation --epic {epic}`. The run-stats footer
(`references/run-stats.md`) follows this block.
