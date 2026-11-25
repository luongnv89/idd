# Review rule hits

One entry per release: which practice-pack rules produced review findings, so a
rule that never fires is kept, reworded or pruned on a recorded human decision
(issue #670). A human-only project doc: no skill references it, so the build
bundles it nowhere.

## How an entry is produced

1. Run `python3 scripts/idd-lint.py stats --no-github` with this checkout's
   script, in a checkout whose `.idd/runs.jsonl` holds the runs made with the
   release being cut. The *Rule hits* section prints the reviewed runs (rows
   that carry `rules_hit`), the hits per rule ID, the zero-hit IDs and any hit
   ID no pack defines (`outside packs`). `--json` carries the same under
   `rule_hits`.
2. Add a `## vX.Y.Z` section below, newest first, with the reviewed-run count,
   the zero-hit IDs as printed, and a decision table for the pruning
   candidates.
3. A **pruning candidate** is a rule with zero hits in each of the last three
   release sections that had at least one reviewed run. A section with no
   reviewed runs is skipped, not counted as a miss.
4. A human decides each candidate — `keep`, `reword` or `prune` — and writes
   the reason and their name in the table. Pruning or rewording a rule is a
   separate change to `src/shared/references/practice-*.md`.

## What a count means

- **The ID set** is every `- **<prefix>N Name.**` rule line in the
  `src/shared/references/practice-*.md` packs beside the script that ran. When
  no pack is found, the zero-hit line reads `skipped`.
- **A hit** is a review finding whose `description` starts with that rule ID,
  reported at or above the reviewer's confidence threshold (80 in
  `/issue-resolver`'s QA, `review.confidence_threshold` in a PR review). "No
  hits" means never reported at that confidence, not never checked.
- **Rows.** `/issue-resolver` records the IDs its QA reviews reported;
  `/auto-pilot` records the union of the resolver's and its PR review's. A
  standalone `/issue-pr-review` writes no run-log row, so its reviews are not
  counted. A row written before the field existed has no `rules_hit` and is
  not a reviewed run.
- **Window.** The count reads every row in the reader window (the active log
  and its rotated segments), not only runs since the previous release, so two
  sections can count the same run. Overlap can only add hits, so it never makes
  a used rule look unused.

## Entry format

```markdown
## vX.Y.Z

Reviewed runs: N (`idd-lint stats --no-github` on YYYY-MM-DD)

Zero hits: C1 · C3 · …

| Rule | Decision | Reason | Decided by |
|------|----------|--------|------------|
| C3 | keep | still catches a class no other rule covers | maintainer |
```

The decision table lists pruning candidates only; write `No candidates.` when
there are none.

## Releases

Newest first.

## v0.29.0

Reviewed runs: 0 (`idd-lint stats --no-github` on 2026-11-25)

Zero hits: skipped (no run-log row records `rules_hit` yet)

No candidates.
