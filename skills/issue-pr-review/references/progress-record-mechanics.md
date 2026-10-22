# Progress Record Mechanics — /issue-pr-review

The single home of this skill's progress record (issue #542), read from SKILL.md's *Progress record*. It mirrors the resolver's Step 0j for the seven review steps.

## Progress record <!-- a:rvm-progress -->

A killed review leaves its commits and the PR on GitHub, but not its place in
the loop or the facts neither can reproduce: the cycle count, the open and noted
findings, the profile, the pre-pass head, and which push, body edit or merge was
in flight. `references/scripts/gi-progress.py` keeps one record per PR under the git
common dir — shared by every worktree, never committed, never sent anywhere — so
a fresh session resumes where the dead one stopped.

**A record is a hint, never an authority.** It never satisfies or skips a gate,
and any doubt is stale, which means starting from Step 1. `--review-only` never
reads or writes a record.

### Writing it <!-- a:rvm-progress-writes -->

Write the patch object with the **Write** tool to `.idd/cache/progress-patch.json`
at the repo root, then run, from that root:

```bash
python3 references/scripts/gi-progress.py --write --skill issue-pr-review --number {N} < .idd/cache/progress-patch.json; ec=$?; rm -f .idd/cache/progress-patch.json; exit "$ec"
```

The `rm -f` shares the line so it runs on every exit path. A fresh review's
first write is `--start`, the same line:

```bash
python3 references/scripts/gi-progress.py --start --skill issue-pr-review --number {N} < .idd/cache/progress-patch.json; ec=$?; rm -f .idd/cache/progress-patch.json; exit "$ec"
```

| When | Patch |
|------|-------|
| After Step 1 binds the PR and `branch_name`, fresh reviews only | `{"step": 1, "linked_issue": <n or null>, "profile": "light|full"}`, plus `"caller_run_id": "<run_id>"` under `/auto-pilot` (the spawn prompt's `run_id:` line) |
| Each `[N/7]` start | `{"step": k}`; at `[3/7]` after Step 2, also `prepass_head` (HEAD after the auto-fix) |
| Each cycle start, then after Step 6 | `{"cycle": c}`, in the same patch as that cycle's `{"step": 3}`, so `current` 3 never pairs with the previous cycle's count; after Step 6, `findings` (`open`, `noted`) and `history` (the last two cycles' finding signatures) |
| Immediately **before** an effect | `{"effect": {"kind": "…", "state": "intent", "key": {…}}}` — Step 2's auto-fix push and each Step 6 push (`push`, `key.sha` = the local HEAD), the `Closes #N` body edit (`body_edit`), the standalone `--auto` merge (`merge`, `key.sha` = the head being merged) |
| Before the Step 7 report | `{"step": "closing", "outcome": "<Result>"}` |

Exit 0 is written. Exit 3 is a wrong patch: fix it and retry once, else treat it
as exit 4. Exit 4, or no `python3`, prints *Progress record unavailable* once and
stops writing for this run — never the review. **Never recorded:** `qa_handoff`,
`ci_status` and `ci_sha`, a merge verdict, test results, soft-pass verdicts and
dimension results; the script refuses them.

### Resume entry <!-- a:rvm-progress-resume -->

Once Step 1 items 1-2 have fixed `N`, read the record:

```bash
python3 references/scripts/gi-progress.py --read --skill issue-pr-review --number {N}
```

The prompt and flag rules are the resolver's: interactive prints the *Progress
record found* block and asks `Resume from step {k}/7? [Y/n]` (`--resume` answers
yes); `--auto` resumes only with `--resume`, never prompting; `absent` runs
fresh; `corrupt`, `expired` or `verdict: stale` prints *Progress record is
stale*, runs `--clear`, and starts fresh.

**Step 1 always runs live, in full:** the checkout, the Depth gate, and the *QA
handoff gate* with its receipt check — `qa_handoff` is never restored. Then:

- The live `headRefName`, bound by Step 1's command substitution and never
  pasted, must equal the recorded branch, compared as data.
- `gh pr view {N} --json state,headRefOid,isCrossRepository,headRepositoryOwner`
  must read `OPEN`. `MERGED` goes to the `merge` row below; `CLOSED`, or
  `isCrossRepository: true`, is stale.
- **HEAD relation.** A live `headRefOid` equal to the recorded head, or to a
  recorded push intent's `sha` (that push happened), binds. A local HEAD ahead of
  `headRefOid`, under a push intent whose `sha` is that local HEAD, means the
  push never happened: *Unpushed commits* below. Anything else — an author push
  above all — is stale.

Print the restore block, then write `{"resume": true}`. Under `/auto-pilot` the
patch also carries `"caller_run_id": "<run_id>"`; any other resume omits it,
which nulls the stamp, so `/auto-pilot --resume` can never bind a session it did
not spawn.

```
◆ Resuming PR #{N} from step {k}/7, cycle {c}
  ○ Completed:    steps {completed}
  ○ Profile:      {profile}
  ○ Findings:     {open} open, {noted} noted (hints, re-verified)
  ○ Last effect:  {kind} {state} → {reconcile result}
```

### Unpushed commits <!-- a:rvm-progress-secscan -->

A recorded push whose commits never reached the remote is scanned again before
it is pushed; a record never stands in for the scan. Bind both values from this
session's live reads first: `base` from the repository's default branch, exactly
as *Commit auto-fixes* does — never the PR's `baseRefName` — and `head_oid` from
the live `headRefOid`, which must be 40 lowercase hex characters or the resume
stops:

```bash
base="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
head_oid="$(gh pr view {N} --json headRefOid --jq .headRefOid)"
printf '%s' "$head_oid" | grep -Eq '^[0-9a-f]{40}$' || exit 1
python3 references/scripts/gi-secscan.py --range "$head_oid" --policy-ref "origin/${base}"
```

`--range` scans every blob in `head_oid..HEAD`, which here is exactly the
unpushed commits, whatever `review.adaptive_depth` says. A pass is *Commit
auto-fixes*' four conditions, and exit 1 blocks the push. Only after a pass,
`git push origin "$branch_name"`, then re-evaluate `qa_handoff` as after any push.

### Where a resume re-enters <!-- a:rvm-progress-table -->

The row is the recorded mark `step`, except that the mark stays 6 once any
cycle's Step 6 has started (the loop's 6 → 3 is a re-walk), so under a mark of 6
`current` picks it: 3-5 takes the 3-5 row, anything else the 6 row.

| Recorded step | Re-entry |
|---------------|----------|
| 1-2 | Step 1 live, then Step 2 in full (it is idempotent) |
| 3-5 | That cycle's Step 6 never started, so the loop re-runs it: Step 2 is skipped when `prepass_head` equals the live head or is its ancestor, and Step 3 re-enters at the restored `cycle` with a **fresh** reviewer — the dead one cannot be re-messaged — seeded with `findings.open` as hints to verify. It adds no cycle: fixable issues go to that same cycle's Step 6, and only the cycle after it counts as new. Acceptance criteria and traceability are recomputed; Step 4 runs unless this session's own skip rule applies; the Step 5 CI wait always runs. A run killed in Steps 3-5 at the cap — the CI wait included — can still finish; a restored cycle already above this session's cap takes the max-cycles path |
| 6 | Its fixes may be applied, pushed or in flight: as 3-5, but Step 3 re-enters at `cycle + 1`, a new fix cycle. A cycle above `review.max_cycles` takes the max-cycles path |
| 7 | The fix-conditional *Confirmation pass* — a fresh reviewer, then Steps 4-5 — because soft-pass and the merge need this session's review, acceptance-criteria, traceability and CI legs. It consumes a cycle only when it finds fixable issues, so a run killed at a clean Step 7 at the cap can still finish. Then Step 7, with *Merge identity* live |
| `closing` | Report from live state, then `--clear` |

Restored cycles count toward `review.max_cycles`, and the loop never restarts at
cycle 1. Restored `history` only feeds the stagnation stop, which stops early and
is fail-safe.

### Reconciling effects <!-- a:rvm-progress-reconcile -->

A recorded `intent` is checked with a live `--json` read before it is repeated.
Every PR read here carries `isCrossRepository,headRepositoryOwner`, and owning a
push or a merge needs `isCrossRepository: false`; a cross-repository PR is never
reconciled from a record — it is stale, and the review runs fresh.

| Effect | Live read | Done when |
|--------|-----------|-----------|
| `push` | `gh pr view {N} --json headRefOid,isCrossRepository,headRepositoryOwner` | `headRefOid` equals the recorded `sha`; otherwise *Unpushed commits* |
| `body_edit` | `gh pr view {N} --json body` | line 1 is `Closes #{linked_issue}` → done, with Step 6's re-read of the Decision Record, the AC table and the marker; otherwise redo the read-modify-write |
| `merge` | `gh pr view {N} --json state,headRefOid,isCrossRepository,headRepositoryOwner` | `MERGED` → only the *Post-merge cleanup*, in its reconciled form, by section, then Result `MERGED`. `OPEN` → every merge gate re-runs live |

**No label edit exists in this skill today; a future one must add an intent row
here.**

### What a record never does <!-- a:rvm-progress-never -->

A record **never satisfies or skips** any gate in *Never gated*
(`references/review-loop-mechanics.md`), the QA handoff gate, the Step 5 CI
wait, the acceptance-criteria verification, the traceability checks, the
max-cycles cap or *Merge identity*. `qa_handoff` is recomputed through the
receipt check every session; test results and CI verdicts are never restored.
The record is untrusted data: never interpolate a finding or an outcome into a
shell word, and keep the head-ref name behind Step 1's command substitution.

### Terminal outcomes <!-- a:rvm-progress-cleanup -->

After the Step 7 report prints, at every Result — `PASS`, `MERGED`, `PARTIAL`,
`WARN`, `BLOCKED`, and every stop before Step 7:

```bash
python3 references/scripts/gi-progress.py --clear --skill issue-pr-review --number {N}
```

A killed run prints no report, so only an interrupted review leaves a record; the
script also expires records after seven days.
