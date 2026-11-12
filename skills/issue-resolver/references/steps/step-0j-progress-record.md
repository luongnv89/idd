# /issue-resolver — Step 0j: Progress record

One part of `references/pipeline-steps.md` — the index that maps every step to its file. Read only the part for the step you are on; a pointer to another step (*Step N — …*) resolves through that index.

## Step 0j — Progress record <!-- a:rs-0j-progress -->

**The single home of the progress record.** `references/scripts/gi-progress.py`
keeps one record per issue under the git common dir — shared by every worktree,
never committed, never sent anywhere — so a fresh session can pick up where a
killed one stopped.

**A record is a hint, never an authority.** It saves repeated work; it never
satisfies or skips a safety gate, and any doubt is stale, which means starting
from Step 0. Records are written whatever `compaction.enabled` says, and the
compaction *Context re-entry* rule never reads one.

### Writing it <!-- a:rs-0j-writes -->

Every write is the same two steps. Write the patch object with the **Write**
tool to `.idd/cache/progress-patch.json` under this run's workspace root — it
can carry issue-derived text, so it never goes on a command line — then run,
from that root:

```bash
python3 references/scripts/gi-progress.py --write --skill issue-resolver --number {N} < .idd/cache/progress-patch.json; ec=$?; rm -f .idd/cache/progress-patch.json; exit "$ec"
```

The `rm -f` is on the same line so it runs on every exit path: the patch never
lingers in a tree that a later clean-tree check measures. A fresh run's first
write is `--start` instead, the same line:

```bash
python3 references/scripts/gi-progress.py --start --skill issue-resolver --number {N} < .idd/cache/progress-patch.json; ec=$?; rm -f .idd/cache/progress-patch.json; exit "$ec"
```

| When | Patch |
|------|-------|
| After *0c — Guards* passes, fresh runs only (a resumed run's only `--start` is the verify-first reset under *Where a resume re-enters*) | `{"step": 0, "base": "<base>", "issue_updated_at": "<0a's updatedAt>", "worktree": <bool>}`, plus `"caller_run_id": "<run_id>"` under `/auto-pilot` (the spawn prompt's `run_id:` line) |
| Each `[N/5]` start from `[1/5]`, beside the clock read | `{"step": k}` plus what the previous step settled: `profile` and `analysis_reuse` at `[1/5]`, `research` (the researcher's JSON) at `[2/5]` with `"issue_updated_at": "<updatedAt after 0d>"` in the same patch (*research pin*, below), `plan` at `[3/5]`, `repro` once Step 3 returns one |
| Each Step 4 cycle start, then after it | `{"qa": {"cycle": c, "ceiling": n}}`; after it, the `premise_ledger`'s failures — each one entry carrying `"kind": "failure"`; a revision is never written (the script refuses it) — and `open_findings` |
| Immediately **before** an effect | `{"effect": {"kind": "…", "state": "intent", "key": {…}}}` — 0d's backup comment and `gh issue edit` (`issue_edit`), Step 1's already-resolved comment (`issue_comment`), the Step 5 push (`push`, `key.sha` = HEAD) and `gh pr create` (`pr_create`, `key.branch`); once the PR exists, `{"pr": <number>}` |
| Before the run-log write | `{"step": "closing", "outcome": "<status>", "effect": {"kind": "run_log", "state": "intent", "key": {}}}` |

**Research pin.** The script measures `research_pin` from the patch that
carries `research`, so that same patch re-sends `issue_updated_at` as the issue
this session left it: the `updatedAt` 0d's re-fetch returns, after its backup
comment and `gh issue edit` — 0a's only when 0d edited nothing. A resume's live
0a reads the normalized issue, so 0c's pre-0d value would never match and the
seeded Step 1 would always run in full. This is the reverse of 0h's condition 5,
which compares an analysis against the pre-normalization value.

`plan` is a summary, never the synthesizer's whole return: the selected option's
`number`, `name`, `summary` (at most 2,000 characters), `files_to_modify` and
`files_to_create` as paths, `test_strategy`, `complexity` and `risk`; up to five
`rejected` options with their `rejection_reason`; `overall_complexity`,
`overall_risk` and `sensitive`; the selected option's `criteria_covered` and the
`criteria` list those IDs were numbered against. The script refuses what a record must never hold
— `tests_state`, a QA verdict, a marker, a receipt — along with any counter that
moves backwards.

- **Exit 0** — written.
- **Exit 3** — the patch is wrong and nothing was written: fix it and retry
  once, else treat it as exit 4.
- **Exit 4, or no `python3`** — print *Progress record unavailable*
  (`references/error-messages.md`) once and stop writing for this run. **Never
  stop the run for it.** A missing script file is a broken install (precheck).

### Resume entry <!-- a:rs-0j-resume-entry -->

After the *Bundled dependency precheck* and before *0a*, read the record:

```bash
python3 references/scripts/gi-progress.py --read --skill issue-resolver --number {N}
```

It never fails on content. `status: absent` runs fresh, silently; `corrupt` or
`expired` is stale. With `ok`, the script has already compared the record with
live git (`binding`): `verdict: stale` is stale (name its `reasons`), and only
`bound` may resume.

- **Interactive:** print the *Progress record found* block and ask
  `Resume from step {k}/5? [Y/n]`. A record written in the last ten minutes
  adds `another session may still be running`. `--resume` answers yes in
  advance; a decline runs `--clear` and a fresh run.
- **Auto (`--auto` / `IDD_AUTO_MODE=1`):** resume only with `--resume`, never
  prompt. Without it the record is ignored, and this run's `--start` replaces it.
- **Caller-managed lane (`IDD_CALLER_WORKTREE=1`):** resume only with
  `IDD_RESUME_LANE=1` **and** `--resume`, `lane_match: true` and workspace
  `here`, inside the validated `IDD_WORKTREE_PATH` — never `branch_only`, never
  the ambient checkout.
- `--resume` with an absent or stale record prints why and starts from Step 0;
  it is never an error.

**Stale at any point** — here, while validating, or when a later check refutes
the record: print *Progress record is stale* with the reason, run `--clear`, and
continue as a fresh run.

**A record that may resume:** read `references/steps/step-0j-resume.md` before
going on — never on a fresh run.

### Terminal outcomes and the run log <!-- a:rs-0j-cleanup -->

At every terminal outcome — `success`, `already_resolved`, `failed`,
`pr_in_progress`, any stop — clear the record right after the *Closing Summary*
prints:

```bash
python3 references/scripts/gi-progress.py --clear --skill issue-resolver --number {N}
```

A killed run prints no summary, so only an interrupted run leaves a record; the
script also expires records after seven days. A resumed run writes its single
run-log line once: `duration_s` and `phases` cover this session, and
`qa_cycles` is the restored count plus this session's. Two sessions on one
issue: the last writer wins, and every effect is reconciled live before it
repeats, so a second session cannot duplicate a push, a PR, a comment or a close.
