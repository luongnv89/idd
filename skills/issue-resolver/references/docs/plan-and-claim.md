<!-- Generated from /docs/plan-and-claim.md. Do not edit. Edit source and run ./scripts/build.sh. -->
# Plan and Claim

Two issue-side signals a person can see without opening a terminal: a **plan comment** posted before code is written, and a **claim label** held while `/issue-resolver` works on the issue. `references/scripts/gi-plan.py` owns both comment formats and every verdict read from them (its docstring is the grammar); this file is the procedure. Settings: `resolver.require_plan`, `resolver.plan_approval`, `resolver.claim_label` (`references/docs/config-schema.md`).

## Reading the issue

Run from the workspace root. `"$login"` is `login="$(gh api user --jq .login)"`, read once per run. **An empty login** (an app or installation token cannot read it) prints `⚠ GitHub login unreadable — claim off, plan comments not read` once and is still passed as `--login ""`: the script then trusts no comment, so every plan reads `absent` and the claim `foreign` when the label is on the issue, else `none`. For the rest of that run the claim is off as with `resolver.claim_label: ""` — never written, never released — except that a label already on the issue still stops with *Claimed elsewhere*; and a resolver plan step that must post a plan takes *Plan awaiting approval* instead of posting, because a plan the run cannot read back would be reposted, and `plan-approved` stripped, on every run. `"$claim_run"` is the run id (*Claim*), `"$claim_label"` is `resolver.claim_label`, and a resolver on a bound `--resume` adds `--branch "$branch_name"`. Shell variables do not outlive one command: keep the three values and set them again ahead of each command that uses them.

```bash
mkdir -p .idd/cache && gh issue view {N} --json body,labels,comments > .idd/cache/plan-{N}.json && python3 references/scripts/gi-plan.py check --login "$login" --run "$claim_run" --claim-label "$claim_label" < .idd/cache/plan-{N}.json; ec=$?; rm -f .idd/cache/plan-{N}.json; exit "$ec"
```

Every read is live, never the issue cache. Only comments by `$login` can make a plan current or a claim own; a marker by another account can only make a claim `foreign`, and only a live one: a claim marker closed by its run's release comment, or written by an account that cannot add labels, never counts (`gi-plan.py` docstring, *Check rules*).

- **Exit 0** — read `plan` (`absent` · `current` · `stale`), `approved` and `claim` (`none` · `own` · `foreign`).
- **Exit 3** — a value outside its grammar: stop and report it.
- **No `python3`, exit 2, exit 4, unparsable output** — print `⚠ gi-plan unavailable — reading the issue by hand` and follow *Manual reading*.

## Plan

**Re-plan rule.** A plan's marker carries a hash of the issue body it was made for. `current` means the live body still hashes the same; any edit to the body makes it `stale`, and a stale plan is never used or approved — the next plan step posts a fresh one.

**Labels.** `planned` goes on with every plan post. `plan-approved` is a person's approval and counts only on a `current` plan; every plan post removes it first, so an approval never carries over to a new plan. The label approves the newest plan on the issue: a later plan by another account with write access supersedes this login's own, which then reads `stale` (`superseded: true`) and is re-planned. The resolver builds only plans its own login posted.

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

`/issue-resolver` only; `resolver.claim_label: ""` or an empty `$login` (*Reading the issue*) skips this section. **Run id** (`$claim_run`): under `/auto-pilot`, the spawn prompt's `run_id`; standalone, generated once at *0c* as `claim_run="resolver-$(date -u +%Y%m%dT%H%M%SZ)-$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"`.

**Claim write** — after the branch is derived (*0f* or the worktree path), before *0g*:

1. Read the issue. `foreign` → *Claimed elsewhere*. `own` → already held: skip to 6.
2. Record the progress intent `{"kind": "label_edit", "state": "intent", "key": {"label": "<claim_label>", "op": "add"}}`.
3. Post the claim comment first — a crash here adds no label, yet its live marker races claims posted within ten minutes (*No expiry*):

   ```bash
   mkdir -p .idd/cache && python3 references/scripts/gi-plan.py render-claim --run "$claim_run" --branch "$branch_name" > .idd/cache/claim-{N}.md && gh issue comment {N} --body-file .idd/cache/claim-{N}.md; ec=$?; rm -f .idd/cache/claim-{N}.md; exit "$ec"
   ```

   A non-zero exit claimed nothing: print `⚠ Claim not written — continuing unclaimed`, skip steps 4–5 (no label is added), and never release.
4. Add `"$claim_label"` with the *Label write*. A failed write leaves no claim: post this run's *Release comment*, print `⚠ Claim not written — continuing unclaimed`, skip step 5, and never release.
5. Read the issue again: it must read `own`. Two runs that claimed at once both see each other's markers and the first writer wins, so the loser reads `foreign`: post this run's *Release comment* (its marker lost, so it must not race a later claim), stop with *Claimed elsewhere* and leave the label — it belongs to the winner, whose live marker the read named.
6. `python3 references/scripts/gi-issue.py {N} --invalidate`.

**Release comment** — closes this run's claim marker, so a claim that ended never races a later one. `$claim_run` is the run that wrote the marker: this run's id, or on a bound resume the read's `claim_run`:

```bash
mkdir -p .idd/cache && python3 references/scripts/gi-plan.py render-release --run "$claim_run" --branch "$branch_name" > .idd/cache/release-{N}.md && gh issue comment {N} --body-file .idd/cache/release-{N}.md; ec=$?; rm -f .idd/cache/release-{N}.md; exit "$ec"
```

**Release** — right after the PR exists (created, or adopted by a resume), and at every terminal outcome without a PR once the claim write ran: read the issue, and only when it reads `own`, record `{"op": "remove"}` the same way, post the *Release comment*, then run `gh issue edit {N} --remove-label "$claim_label"`, confirm with `gh issue view {N} --json labels`, and invalidate as in step 6. The comment goes first: a label removed with its marker still live would make a claim posted in the next ten minutes read `foreign` and stop with the label on. Never remove a claim that does not read `own`. A failed release prints `⚠ Claim not released — gh issue edit {N} --remove-label "{claim_label}"` and never changes the outcome.

**No expiry.** A claim lasts until it is released or a person removes the label; nothing takes one over automatically. A label with no live marker behind it — its run died before releasing — reads `foreign` to every run until a person removes it with the command *Claimed elsewhere* prints. A dead run's live marker still races any claim posted within ten minutes of it, so removing its label sooner only blocks the next run again. When the read's `claim_login` is `$login`, close the marker first — the *Release comment* with `claim_run` and `branch_name` set to the read's `claim_run` and `claim_branch` — then remove the label; a marker by another account only its author can close, so wait until it is ten minutes old.

## Label write

`gh issue edit {N} --add-label "<label>"`. If it fails, run `gh label create "<label>"` whatever it returns, then retry the add once. Confirm with `gh issue view {N} --json labels`, then `python3 references/scripts/gi-issue.py {N} --invalidate`. A label that cannot be confirmed is a failed write.

## Manual reading

When `gi-plan.py` cannot run: every plan reads `stale` (the hash cannot be checked), so nothing is approved, and a plan step that must post one stops instead (*Plan awaiting approval*); `/issue-analysis --plan` posts nothing. The claim: the label absent → `none`. Present → `own` only when the newest comment by `$login` whose first line is `<!-- idd:claim v1 run=<run> branch=<branch> -->` names this run (or, on a bound resume, this branch) and no live claim marker for another run, by anyone, comes before it within ten minutes or after it by more than ten minutes; anything else is `foreign`, except that on a bound resume with no live marker left, a newest closed marker by `$login` for this branch still reads `own`. A marker is not live when a later comment by its author opens `<!-- idd:claim-released v1 run=<same run> branch=<branch> -->`, or when its author is another account whose `authorAssociation` is not `OWNER`, `MEMBER` or `COLLABORATOR`; on a bound resume an earlier `$login` marker for this branch is not a racer. With an empty `$login` every claim marker is untrusted. Write the claim comment by hand as that marker line plus `Claimed by IDD Stack run \`<run>\` on branch \`<branch>\`.`, and the release comment as the `idd:claim-released` line plus `Released by IDD Stack run \`<run>\` on branch \`<branch>\`.`
