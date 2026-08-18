# ADR — B1 (Squash-Merge Body) Is This Repo's Durable-Memory Binding

**Status:** Accepted (2026-08-18).
**Issue:** [#180](https://github.com/luongnv89/idd/issues/180).
**Related:** [`no-backfill-merged-decision-records.md`](no-backfill-merged-decision-records.md)
— what to do about the merges that landed while this binding was defeated;
[#295](https://github.com/luongnv89/idd/issues/295) — the repair itself.

## Context

[SPEC.md §4.2](../../SPEC.md) requires every durable analysis signal to appear in
**both** the PR body and a git-history artifact on the default branch. §4.3 lists
three ways to satisfy the git-history half — **B1** squash-merge body, **B2**
merge-commit body, **B3** git notes — and says a repo claiming L3 conformance
MUST declare which one it uses.

This repo had never written that declaration down. Every tool and document
behaved as though B1 were in force, which is how #295 happened: three prose sites
described GitHub's copy of the PR body into the squash commit as unconditional
platform behavior, and `/issue-pr-review` traceability check 4 reported `pass`
from that assumption rather than from a reading. The binding an implementation
assumes but never states is the one nothing can check.

## Decision

**This repo declares binding B1 — squash-merge body ([SPEC.md §4.3](../../SPEC.md)).**

The Decision Record reaches git history because GitHub copies the pull request
body verbatim into the squash commit that lands on `main`. Nothing else is
required of an author: no notes ref to push, no merge-commit discipline. That is
the whole appeal of B1, and also its whole fragility — the copy is conditional on
two repository settings, and neither is a file anyone reviews.

B2 and B3 were not adopted. B2 needs merge automation or per-merge discipline
this project does not have; B3 (`refs/notes/idd`) is neither fetched nor pushed
by default, so it would be invisible to exactly the offline reader the dual-write
rule serves. Both remain available to repos that cannot use B1.

## The 2026-08-15 repair

B1 was declared-by-behavior but **not in force** for this repo's whole history up
to 2026-08-15. `squash_merge_commit_message` sat at GitHub's default,
`COMMIT_MESSAGES`, which writes the list of squashed commit subjects instead of
the PR body. The strategy was right and the binding was still defeated.

Under #295 the setting was flipped to `PR_BODY` — together with
`squash_merge_commit_title=PR_TITLE`, because GitHub pairs `PR_BODY` only with
`PR_TITLE` and rejects the message on its own with HTTP 422.

Two merges bracket the repair and are the evidence that it took effect:

| PR | Merge commit | Merged at | Landing message |
|----|--------------|-----------|-----------------|
| [#306](https://github.com/luongnv89/idd/pull/306) | `1bf5ef1` | 2026-08-14T19:33:53Z | commit subjects (`COMMIT_MESSAGES`) — Decision Record lost |
| [#304](https://github.com/luongnv89/idd/pull/304) | `c741d36` | 2026-08-15T08:27:13Z | full PR body — Decision Record landed |

`idd-lint stats --since '2026-08-15 00:00:00'` reads that boundary directly: it
joins each merged PR to its own `mergeCommit.oid` and reports whether the
Decision Record survived. Without `--since` the same row is informational rather
than a warning, because the lifetime shortfall is a decided matter — see the
no-backfill ADR.

## Residual risk

The 2026-08-15 repair fixed the message source. Closing the two non-squash merge
paths was a separate change, and it has since been made:

```console
$ gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed
{"mergeCommitAllowed":false,"rebaseMergeAllowed":false,"squashMergeAllowed":true}
```

Squash is the only button, and its message source is `PR_BODY`, so the full
check-4 predicate holds: B1 is in force rather than merely declared.

What remains is not a merge path but a mutability. All three flags are
repository settings, not files — nothing in the tree records them, no review
gates a change to them, and re-enabling either bypass is a checkbox under
Settings → General → Pull Requests. Were that to happen, the two paths would
behave exactly as they did before:

- **Merge commit.** `merge_commit_message` is `PR_TITLE`, so the merge commit
  would carry the title and no body. The Decision Record would not land.
- **Rebase.** The PR body is never consulted at all; the branch's own commit
  messages are replayed. The Decision Record would not land.

Neither bypass leaves a mark distinguishable from an ordinary merge in the button
UI, so this is not a risk discipline can carry on its own — which is why
`/idd-doctor` check 4 reads both levels and warns when either is wrong, and why
it reports `binding unverified` rather than a pass when the message source
cannot be read at all. That check is what turns an unreviewable setting into
something a routine doctor run surfaces.

## Enforcement is the owner's, not the tool's

The lockdown above was applied by the repository owner. This project does not
apply it, then or now:

```bash
gh api -X PATCH repos/:owner/:repo \
  -f allow_merge_commit=false \
  -f allow_rebase_merge=false
```

Repository settings are owner-controlled, and the same stance governs the
tooling: `/idd-doctor` warns rather than fails on check 4 precisely because
"repo settings are owner-controlled and the doctor only nudges"
(`src/internal-skills/idd-doctor/SKILL.source.md`, Check 4). A tool that mutated
an owner's repository to make its own check pass would be a worse defect than the
one it fixed. The command stays recorded here, and in the doctor's fix hint, so
that an owner whose repo drifts back meets it at the moment the warning appears.

As of this declaration this repo's B1 binding is **in force** — squash-only,
`PR_BODY` message source, both bypasses closed. That is the honest statement,
and it is the one the tooling now prints: check 4 reports a pass rather than a
warning.

## Consequences

- The declaration is checkable. `/idd-doctor` check 4 tests the full predicate —
  squash-only **and** `squash_merge_commit_message == "PR_BODY"` — instead of the
  strategy alone, which SPEC §4.3 explicitly forbids treating as sufficient.
- `idd-lint stats` measures the binding rather than inferring it, by joining each
  merged PR to its landing commit. A lifetime gap renders `○` informational; only
  a loss inside an explicit `--since` window renders `⚠`.
- Anyone forking this repo inherits the fork's own settings, not these. The
  declaration says what the binding is; the doctor says whether it currently
  holds. Those are deliberately two different reads.

## Re-validation

Revisit if this project adopts B2 or B3, or if GitHub changes the settings that
condition the squash-message copy. Reversing the declaration means re-answering
why B1's zero-author-effort property is no longer worth its dependence on two
repository settings — not merely re-weighing the residual risk above.
