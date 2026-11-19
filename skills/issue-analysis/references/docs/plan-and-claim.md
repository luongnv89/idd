<!-- Generated from /docs/plan-and-claim.md. Do not edit. Edit source and run ./scripts/build.sh. -->
# Plan and Claim

Two issue-side signals a person can see without opening a terminal: a **plan comment** posted before code is written, and a **claim label** held while `/issue-resolver` works on the issue. `references/scripts/gi-plan.py` owns both comment formats and every verdict read from them (its docstring is the grammar); this file is the procedure. Settings: `resolver.require_plan`, `resolver.plan_approval`, `resolver.claim_label` (`references/docs/config-schema.md`).

## Reading the issue

Run from the workspace root. `"$login"` is `login="$(gh api user --jq .login)"`, read once per run; when it is empty, skip the script: every claim reads `foreign` (none can be proven own) and every plan `absent`. `"$claim_run"` is the run id (*Claim*), `"$claim_label"` is `resolver.claim_label`, and a resolver on a bound `--resume` adds `--branch "$branch_name"`. Shell variables do not outlive one command: keep the three values and set them again ahead of each command that uses them.

```bash
mkdir -p .idd/cache && gh issue view {N} --json body,labels,comments > .idd/cache/plan-{N}.json && python3 references/scripts/gi-plan.py check --login "$login" --run "$claim_run" --claim-label "$claim_label" < .idd/cache/plan-{N}.json; ec=$?; rm -f .idd/cache/plan-{N}.json; exit "$ec"
```

Every read is live, never the issue cache. Only comments by `$login` can make a plan current or a claim own; a marker by another account can only make a claim `foreign`.

- **Exit 0** — read `plan` (`absent` · `current` · `stale`), `approved` and `claim` (`none` · `own` · `foreign`).
- **Exit 3** — a value outside its grammar: stop and report it.
- **No `python3`, exit 2, exit 4, unparsable output** — print `⚠ gi-plan unavailable — reading the issue by hand` and follow *Manual reading*.

## Plan

**Re-plan rule.** A plan's marker carries a hash of the issue body it was made for. `current` means the live body still hashes the same; any edit to the body makes it `stale`, and a stale plan is never used or approved — the next plan step posts a fresh one.

**Labels.** `planned` goes on with every plan post. `plan-approved` is a person's approval and counts only on a `current` plan; every plan post removes it first, so an approval never carries over to a new plan.

**Posting a plan** — `/issue-analysis --plan` and the resolver use the same order:

1. `gh issue edit {N} --remove-label plan-approved`, then read `gh issue view {N} --json labels`. An error that the label is not on the issue counts as removed only when that read confirms it is gone. Still present: remove once more and re-read; still present, **post nothing** — the resolver takes *Plan awaiting approval*, `/issue-analysis` prints its error with `gh issue edit {N} --remove-label plan-approved`.
2. Write `{"criteria": [{id, text}], "option": <the selected option>}` to `.idd/cache/plan-input-{N}.json` with the Write tool (it holds issue text, never a command-line word), then render from the live body — the script hashes the body it reads, never a retyped copy — and post:

   ```bash
   mkdir -p .idd/cache && gh issue view {N} --json body > .idd/cache/plan-body-{N}.json && python3 references/scripts/gi-plan.py render-plan --issue .idd/cache/plan-body-{N}.json < .idd/cache/plan-input-{N}.json > .idd/cache/plan-{N}.md && gh issue comment {N} --body-file .idd/cache/plan-{N}.md; ec=$?; rm -f .idd/cache/plan-body-{N}.json .idd/cache/plan-input-{N}.json .idd/cache/plan-{N}.md; exit "$ec"
   ```

   Exit 3 from `render-plan` (no name, no files, a bad criterion id) posts nothing.
3. Add `planned` with the *Label write*.
4. Re-read the labels live: if `plan-approved` is back, repeat step 1's removal and confirm; if it cannot be confirmed gone, the plan is not approved.

## Claim

`/issue-resolver` only; `resolver.claim_label: ""` skips this section. **Run id** (`$claim_run`): under `/auto-pilot`, the spawn prompt's `run_id`; standalone, generated once at *0c* as `claim_run="resolver-$(date -u +%Y%m%dT%H%M%SZ)-$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"`.

**Claim write** — after the branch is derived (*0f* or the worktree path), before *0g*:

1. Read the issue. `foreign` → *Claimed elsewhere*. `own` → already held: skip to 6.
2. Record the progress intent `{"kind": "label_edit", "state": "intent", "key": {"label": "<claim_label>", "op": "add"}}`.
3. Post the claim comment first — a marker without the label claims nothing, so a crash here leaves nothing a later run reads as foreign:

   ```bash
   mkdir -p .idd/cache && python3 references/scripts/gi-plan.py render-claim --run "$claim_run" --branch "$branch_name" > .idd/cache/claim-{N}.md && gh issue comment {N} --body-file .idd/cache/claim-{N}.md; ec=$?; rm -f .idd/cache/claim-{N}.md; exit "$ec"
   ```
4. Add `"$claim_label"` with the *Label write*. A failed write leaves no claim: print `⚠ Claim not written — continuing unclaimed`, skip step 5, and never release.
5. Read the issue again: it must read `own`. Two runs that claimed at once both see each other's markers and the first writer wins, so the loser reads `foreign`: stop with *Claimed elsewhere* and leave the label — it belongs to the winner.
6. `python3 references/scripts/gi-issue.py {N} --invalidate`.

**Release** — right after `gh pr create` succeeds, and at every terminal outcome without a PR once the claim write ran: read the issue, and only when it reads `own`, record `{"op": "remove"}` the same way, run `gh issue edit {N} --remove-label "$claim_label"`, confirm with `gh issue view {N} --json labels`, then invalidate as in step 6. Never remove a claim that does not read `own`. A failed release prints `⚠ Claim not released — gh issue edit {N} --remove-label "{claim_label}"` and never changes the outcome.

**No expiry.** A claim lasts until it is released or a person removes the label; nothing takes one over automatically. A claim released less than ten minutes before a new run's claim still reads `foreign` to that run (the race window): continue at the interactive prompt, or wait.

## Label write

`gh issue edit {N} --add-label "<label>"`. If it fails, run `gh label create "<label>"` whatever it returns, then retry the add once. Confirm with `gh issue view {N} --json labels`, then `python3 references/scripts/gi-issue.py {N} --invalidate`. A label that cannot be confirmed is a failed write.

## Manual reading

When `gi-plan.py` cannot run: every plan reads `stale` (the hash cannot be checked), so nothing is approved, and a plan step that must post one stops instead (*Plan awaiting approval*); `/issue-analysis --plan` posts nothing. The claim: the label absent → `none`. Present → `own` only when the newest comment by `$login` whose first line is `<!-- idd:claim v1 run=<run> branch=<branch> -->` names this run (or, on a bound resume, this branch) and no claim marker for another run, by anyone, comes before it within ten minutes; anything else is `foreign`. Write the claim comment by hand as that marker line plus `Claimed by IDD Stack run \`<run>\` on branch \`<branch>\`.`
