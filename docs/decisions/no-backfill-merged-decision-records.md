# ADR — No Backfill of Merged Decision Records

**Status:** Accepted (2026-08-14).
**Issue:** [#295](https://github.com/luongnv89/idd/issues/295).
**Related:** [#180](https://github.com/luongnv89/idd/issues/180) — the same gap
measured from the coverage side (`idd-lint stats`: 1/16 Decision Records in git
history vs 51/90 in merged PR bodies).

## Context

The IDD dual-write rule ([SPEC.md §4.2](../../SPEC.md)) requires every durable
analysis signal to appear in **both** the PR body and a git-history artifact on
the default branch. This repo declares binding **B1 — squash-merge body**
([SPEC.md §4.3](../../SPEC.md)): the platform copies the PR body into the squash
commit that lands on `main`.

That copy is conditional on a per-repo GitHub setting nothing in this project
read until #295: `squash_merge_commit_message`. This repo's value has been
`COMMIT_MESSAGES` — GitHub's default — for its whole history, so every squash
commit on `main` carries the list of commit subjects instead of the PR body:

```console
$ gh api repos/luongnv89/idd --jq .squash_merge_commit_message
COMMIT_MESSAGES

$ git log -1 --format='%B' 5eb1cfb
refactor(context): define freshness boundaries (#285) (#294)

* refactor(context): define freshness boundaries (#285)
* fix(context): address review feedback (#285)
```

The reasoning is not lost — it is intact in each PR body on GitHub — but the
git-history half of the dual write has never landed. The question this ADR
answers is what to do about the commits that already merged.

## Decision

**No backfill.** The Decision Records missing from already-merged commits on
`main` stay missing. This project will not rewrite, amend, or annotate historical
commits to satisfy the dual-write rule retroactively.

Two options were considered and rejected:

1. **Rewrite `main`** (`git filter-repo` / interactive rebase to replace each
   squash commit message with its PR body). Rejected: it changes the SHA of every
   commit on the default branch, breaking every existing reference — issue and PR
   cross-links, `.gitissue/analysis-*.json` commit pins, the analysis-reuse
   ancestry predicate (`/issue-resolver` *Step 0h*), release tags, and any clone
   or fork. It trades a recorded documentation gap for a much larger traceability
   break, which is a net loss against the very property the rule protects.
2. **Attach git notes retroactively** (binding B3, `refs/notes/idd`). Rejected as
   disproportionate rather than harmful: notes do not rewrite history, but they
   are not fetched or pushed by default, so a backfilled note would be invisible
   to exactly the offline reader the dual-write rule serves. Standing up and
   documenting a second binding to cover ~16 historical commits is more machinery
   than the gap justifies. B3 stays available for repos that cannot use B1; it is
   not being adopted here for backfill.

## Consequences

- Commits merged before the fix answer "why does this change exist?" only through
  their linked PR on GitHub. The chain from code to *intent* is unbroken — every
  commit carries its `(#N)` issue reference, so `git blame` → commit → issue still
  works offline-ish; only the *reasoning* half needs the tracker.
- Conformance is therefore honest rather than clean: this repo's B1 binding is
  satisfied from the fix forward, not for its history. This ADR is the record, so
  the gap is a known decision instead of something rediscovered by the next audit.
- `idd-lint stats` will keep reporting a low git-history Decision-Record ratio
  until enough new merges dilute the historical ones. That is expected, not a
  regression; a reader comparing the two numbers should read this ADR first.
- The forward fix is separate and does not depend on this decision: flip
  `squash_merge_commit_message` to `PR_BODY`, and — since a setting can always be
  flipped back or start wrong in a fork — never assume the binding again. Issue
  #295 makes `/issue-pr-review` traceability check 4 read the setting and report
  `partial` when it is defeated, and makes `/init-gitissue` warn on the
  `squash_merge_commit_*` sub-settings rather than the merge strategy alone.

## Re-validation

Revisit only if the project adopts a different durable-memory binding (B2 or B3)
for reasons unrelated to backfill, or if a tool appears that can attach the
records without changing commit SHAs and without a fetch-by-default problem. A
change of mind here means re-answering the SHA-stability objection above, not
just re-weighing the value of the records.
