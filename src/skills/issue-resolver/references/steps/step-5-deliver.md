# /issue-resolver — Step 5: Deliver

One part of `references/pipeline-steps.md` — the index that maps every step to its file. Read only the part for the step you are on; a pointer to another step (*Step N — …*) resolves through that index.

## Step 5 — Deliver <!-- a:rs-step5-deliver -->

### Deliver-time risk tier <!-- a:rs-deliver-tier -->

Step 2 classified the *planned* files; the delivered diff can differ. After
*Update documentation* commits and immediately before the pre-push secret scan, on
the `HEAD` the QA marker's `head=` names, run from the repo root
`printf '%s' "$sensitive_json" | python3 shared/scripts/gi-sensitive.py --classify`
with `{"labels": [the issue's labels], "paths": [], "diff": "origin/${base}...HEAD"}`.
Any non-zero exit, unparsable output, or no `python3` is `tier: sensitive` (fail closed).

If `tier` is `sensitive` and Step 2's classification was not, or the classify could
not run, or its `reasons` name any path Step 2's classify did not mark sensitive (a
Step 2 that could not classify marked every planned path), run Step 2's
*Sensitive-change gate* (steps 2–5) once on the diff's paths before pushing.
Every probe is `phase: pre`, run on the delivered tree. Only `proceed` with empty
`test_obligations` and no `amended` blocker delivers; `replan`, `stop` or an
amendment is that gate's `stop`, before the push — **Auto:** the run ends `failed`
at Step 5, no PR. Record it in the Decision Record's *Sensitive-change gate* line,
marked "at deliver".

### Pre-push secret scan

Full rationale for SKILL.md *Step 5 — Deliver → Push branch and create PR*, which owns
the invocation, the pass condition and every exit code. Why no config value reaches
the command line, why `--policy-ref` names the base, and why `scanned: 0` with
`skipped > 0` is not a pass: `docs/pre-commit-security.md` (*Script Path* and rule 5).

**Why exit 1 never degrades.** Every other non-zero exit from a bundled script means the
script could not answer. Exit 1 here means it *did* answer, and the answer was `block`.
Reading it as a degrade inverts the verdict and pushes the secret. The one exception is
exit 1 with no parsable JSON on stdout — that is a crash, not a verdict, and is handled
as exit 2.

### Claim release

Right after the PR exists — `gh pr create` just succeeded, or a resume's
`pr_create` reconcile adopted the open PR and skipped it — release the claim
(*Release* in `docs/plan-and-claim.md`): only a claim that reads `own` is
removed, and a failed release is a `⚠` that never changes the outcome.

### Progress record at Deliver

Write each effect's intent to the progress record **before** the effect — the push,
`gh pr create`, then the `closing` step before the run-log write — so a killed
session's successor reconciles it live instead of repeating it (*Reconciling
effects*, `references/steps/step-0j-resume.md`). A run that resumed past
Step 4 did not see QA exit clean in this session: it drops the QA marker and writes
no receipt, and the reviewer runs its full pipeline.
