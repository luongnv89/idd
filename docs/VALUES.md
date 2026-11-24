# IDD Stack — Core Values and Properties

The checklist every IDD skill, shared agent, shared script and runtime doc is held to.
`docs/idd-methodology.md` (*Principles*) says what the **method** believes; this file says
what the **skill set** must keep true while it changes.

It is a project doc: no skill reads it at run time, so it is never bundled.

## How to use this file

- **Before changing a skill, agent, script or runtime doc**, read the four pillars. The
  change must not turn a checked item into an unchecked one.
- **A change that would weaken a checked item needs the maintainer's explicit request.**
  Stop and ask; do not trade a value away as a side effect of another task. When the
  maintainer approves, record it in the *Change log* at the bottom.
- **Adding, removing or rewording a value** is also the maintainer's call only.
- **Unchecked items are targets**, not defects. A PR that makes one hold ticks the box and
  names the guard that now keeps it held.
- **Re-run the review before each minor release**: run the test of record, then walk the
  unchecked items and every item whose guard is `judgement` or `prose pin`.

Legend:

- `[x]` held today. A regression is a defect.
- `[ ]` target, not yet held. The `Partial:` note says what already exists and what is
  missing.
- **Guard** names what keeps the item true:
  - a **behavioural** test runs the script or build and checks the result;
  - a **prose pin** test only proves the instruction is still written in the skill, not that
    an agent follows it;
  - **judgement** means no test covers it and a reviewer has to look.

Markings were last reviewed on 2026-11-11 against v0.27.0. The items named in the
values improvement plan's milestones (#547) were re-graded on 2026-11-20 against `main`
at 57722ec.

## When values conflict

Trustworthiness → Verification → Simplicity → Token efficiency.

Never drop a check to save tokens, and never hide a failure to keep a run simple. Reduce
depth before removing a gate: the `light` profile reviews less deeply, it does not skip
review.

---

## Pillar 1 — Token efficiency

Every byte a skill puts into an agent's context must earn its place.

- [x] **TE1 — SKILL.md stays under 500 lines.** Guard: `tests/test-skill-line-cap-247.sh`
  (behavioural).
- [x] **TE2 — A bundle never grows silently.** Prompt surface above the recorded budget
  fails CI until the budget is changed in the same PR. Guard: `scripts/skill-budget.py`,
  `tests/test-skill-bundle-budget-466.sh` (behavioural).
- [x] **TE3 — Bundled docs carry only what the skill names** (config excerpt, methodology
  digest). Guard: `tests/test-bundled-doc-slimming-249.sh`, build verification
  (behavioural).
- [x] **TE4 — Work is not repeated.** Issue reads, the backlog snapshot, a fresh analysis
  and the last green test run are reused. Guard: `tests/test-backlog-snapshot-468.sh`,
  `tests/test-scripts-253.sh` (behavioural); `tests/test-analysis-reuse-254.sh`,
  `tests/test-qa-handoff-255.sh` (prose pin).
- [x] **TE5 — Effort scales with the task.** Light/full pipeline profile, per-role model and
  effort overrides. Guard: `tests/test-agents-config-454.sh`,
  `tests/test-agent-overrides-455.sh`; the light profile is a prose pin in
  `tests/test-consolidated-blocks-248.sh`.
- [x] **TE6 — Every run ends with a cost footer**: duration and per-phase seconds, and
  tokens when the host reports them. Guard: `tests/test-run-stats-373.sh`.
- [x] **TE7 — Long runs survive a full context.** Context-threshold check and durable
  progress records. Guard: `tests/test-context-threshold-540.sh`,
  `tests/test-progress-records-542.sh` (behavioural).
- [ ] **TE8 — Bundles do not grow release over release without approval.** Partial: a
  bundle more than 2% above its size at the last release tag fails CI unless the *Change
  log* has a row naming the skill and the tag, each SKILL.md has a byte ceiling, and the
  always-read bytes are budgeted (#558; `tests/test-skill-bundle-budget-466.sh`,
  behavioural). Missing: a row exempts its skill for the whole release and the check reads
  no byte figure from it, so growth after the first row passes unseen (#653 grew two
  bundles past their last approved sizes with no new row); five of eight bundles sit above
  the cap on exemptions, up to +11.25%; and the SKILL.md ceiling has no release cap.
- [ ] **TE9 — Progressive disclosure: a step reads only what that step needs.** Partial:
  steps and phases are split into their own files, two skills have tested disclosure gates
  (`tests/test-disclosure-gates-250.sh`), and the bytes behind "read now" pointers are
  budgeted per skill (`tests/test-skill-bundle-budget-466.sh`, behavioural). The
  resolver's always-read set fell from 50.5 KB to 11.2 KB (#559). Missing: auto-pilot
  still reads 46.8 KB up front, `summary-format.md` whole for its final summary;
  issue-pr-review reads 125 KB across five whole files; and the budget counts only the
  pointers, so nothing measures what a common path loads.
- [ ] **TE10 — One home per instruction: written once and pointed to, never copied.**
  Partial: `run-stats.md` and `self-improve.md` have one authored source in
  `src/shared/references/`, each SKILL.md keeps only a short Self-Improve pointer, and
  `tests/test-consolidated-blocks-248.sh` pins eight blocks and fails when an authored file
  is byte-identical in two skills (T12, behavioural) (#560). `gi-stats.py` mirroring
  `idd-lint.py` is an accepted exception (*Change log*). Missing: the common error
  messages still repeat across skills: *Not a git repository* in eight `error-messages.md`
  files, *Not authenticated* and *Invalid config* in six, *GitHub CLI not found* and *No
  GitHub remote* in five.
- [ ] **TE11 — Runtime token cost per resolved issue is tracked across releases.** Partial:
  the run log takes optional `tokens`, `agents`, `model`, `effort` and `skill_version`
  fields, and `tokens` and `agents` must agree with the run-cost footer (#562;
  `tests/test-runs-jsonl.sh` T14a–f, behavioural for the fields; T14h–k, prose pin for
  the footer agreement), and `docs/release-costs.md` records one median per flow per
  release, a section `tests/test-plugin-manifest-469.sh` (S13) requires for the current
  version.
  Missing: the only release entry, v0.27.0, reads `no data`; `tokens` is written only when
  the host reports a count; the `gh`-call counter still runs in the eval lab only; and the
  one measured figure is still the #465 baseline.

## Pillar 2 — Verification of work

Nothing is done on an agent's say-so. Three things are verified: the **intention**, the
**code**, and the **outcome**.

### Intention

- [x] **VW1 — What was inferred is marked, never presented as known.** Confidence markers
  on type, criteria and metadata. Guard: `tests/test-issue-creator-confidence-191.sh`
  (prose pin).
- [x] **VW2 — Every issue IDD writes carries acceptance criteria.** Guard: issue templates,
  `scripts/idd-lint.py` (checks that at least one criterion exists).
- [x] **VW3 — An unclear issue is never implemented unattended.** An issue with no criteria,
  or a `(needs review)` type or criterion, is marked unclear by triage and skipped by the
  auto-pilot pick; the resolver's readiness gate takes its default No in auto mode, a
  resolve of one ends `PARTIAL`, and the merge floor stays unmet while a criterion carries
  the marker. Guard: `tests/test-issue-readiness-553.sh` T1–T3 (behavioural: `gi-ready.py`,
  `gi-triage-graph.py`, `gi-runlog.py`), T4 (prose pin).
- [ ] **VW4 — Criteria are testable, not just present.** Partial: `SPEC.md` §1 requires it;
  nothing checks it.
- [x] **VW5 — The plan is mapped to each criterion before implementation.** Every plan
  option lists `criteria_covered`, and a selected option that leaves a criterion uncovered
  stops planning with the gap named, in every profile and in auto mode. Guard:
  `tests/test-plan-criteria-coverage-554.sh` T1–T3 (behavioural, `gi-ready.py --coverage`),
  T4 (prose pin).
- [x] **VW6 — The contract states its boundaries**: non-goals, invariants that must not
  change, and non-functional constraints. The optional `## Constraints` section (`SPEC.md`
  §1.1) holds them, `/issue-creator` fills it only from the reporter's words, and the code
  reviewer reports any diff that touches one at any confidence. Guard:
  `tests/test-issue-constraints-557.sh` T1–T2 (behavioural, `idd-lint`, `gi-ready.py`),
  T3 (prose pin).
- [ ] **VW7 — A change to the issue mid-run is noticed.** Partial: checked when an analysis
  is reused and by the review's fresh read; not between preflight and deliver, or between
  review and merge.

### Code

- [x] **VW8 — Each acceptance criterion is judged separately, with evidence, and a `fail`
  blocks the merge.** Guard: `tests/test-issue-pr-review-traceability.sh` (prose pin).
- [x] **VW9 — The suite and the build run in every QA cycle, and a merge is bound to the
  head commit that was verified.** Holds on default config. Guard:
  `tests/test-merge-identity-516.sh` (head binding); judgement for the per-cycle run.
- [x] **VW10 — Unverified work never merges as clean.** An unattended merge needs the
  *Merge floor*: the criteria check enabled, at least one `pass`, and no `unverified` or
  `(needs review)` criterion; an interactive run below it asks, default No. Holds on
  default config. Guard: `tests/test-merge-identity-516.sh` M12 (behavioural: auto-pilot's
  merge blocks refuse unless `merge_floor` is `met` for that head and base;
  `/issue-pr-review`'s block binds the floor's base tip, and its unmet stop is prose);
  `tests/test-consolidated-blocks-248.sh` T11, `tests/test-review-followups-584.sh` T2
  (prose pin); eval `issue-pr-review/unverified-only-auto` (stand-in). The floor itself is
  computed in prose, not in a script.
- [x] **VW11 — Criterion evidence is independent and reproducible.** An isolated criteria
  judge sees the issue and the diff only, never the PR body, and `gi-criteria.py`
  downgrades to `unverified` a `pass` without a test green at head or a command with its
  observed output. The PR review's code-reviewer is isolated the same way: it gets the PR
  title, the author's approach and residual risk and the linked issue's constraints and
  criteria, never the author's test results, criteria table, sensitivity rows or QA
  marker. Guard: `tests/test-criteria-evidence-555.sh` T1–T3 (behavioural), T4 and T7
  (prose pin).
- [ ] **VW12 — Tests prove what they claim.** Partial: the implementer must report mutation
  sensitivity, pinned outputs and any weakened test
  (`tests/test-behavior-test-contracts-521.sh`, prose pin), and the review re-runs a bug
  fix's regression test red at base and green at head (`tests/test-bug-proof-556.sh`).
  Missing: for any other test the sensitivity record is the implementer's own, and the
  review lists a `sensitivity not verified` row under Uncertainty without blocking on it.
- [x] **VW13 — A bug fix is red before and green after.** The review re-runs the cited
  regression test at the merge-base (red) and at head (green), and an unattended merge of a
  bug PR needs that `red→green` proof; `not reproduced`, `manual` or `unproven` leaves it
  open. Guard: `tests/test-bug-proof-556.sh` T1–T3 (prose pin); eval
  `issue-pr-review/regression-green-at-base` (stand-in on a real git fixture).
- [ ] **VW14 — Behaviour is exercised, not only read.** Partial: verification recipes are
  real and tested (`tests/test-verification-recipes-523.sh`, behavioural) but opt-in, and
  the browser UI review is skipped in auto mode.
- [ ] **VW15 — Non-functional criteria are verified** when the issue states them. Partial:
  the code reviewer has a security category, UI changes get an accessibility review, a
  stated `**Limit:**` in `## Constraints` is checked against the diff, and the performance
  practice pack reviews data access, loops and I/O; a performance limit is read, never
  measured.

### Outcome

- [x] **VW16 — The skill set is tested on every change.** The test of record runs in CI,
  with negative mutation tests of the build and a coverage floor on the shared scripts.
  Guard: `.github/workflows/dist-check.yml`, `tests/test-build-negative-mutations.sh`,
  `tests/test-coverage-floor-333.sh`.
- [x] **VW17 — Every run reports what it verified and what it did not.** Each summary keeps
  Result, Evidence and Uncertainty apart; auto-pilot prints every merged PR's AC
  pass/fail/unverified counts and calls a run `complete` only when each merge is
  `verification: full`; a disabled check prints `disabled`; the run log carries
  `verification`. Guard: `tests/test-runs-jsonl.sh` T13a–e (behavioural, `gi-runlog.py`),
  T13f–l (prose pin).
- [ ] **VW18 — Skill behaviour is verified with real agent runs.** Partial: the hermetic
  evals replay fixed stand-ins, and every skill has at least one case; the real-agent
  promotion lane has three locked held-out tasks
  (`tests/test-eval-promotion-517.sh` T13), but no promotion run has been
  recorded yet.
- [ ] **VW19 — The outcome is checked after merge.** A reopened issue, a revert or a
  follow-up bug is linked back to the run that shipped the change. Partial: `idd-lint stats`
  and `/auto-pilot --stats` (`gi-stats.py`) join each merged run's PR to reverts, reopened
  issues and follow-up bugs, name the flagged PRs and report the counts per release (#568,
  #573; `tests/test-idd-lint-stats-project.sh`, `tests/test-stats-573.sh`, behavioural),
  and a `/issue-pr-review --revert` row names the reverted PR and its revert PR (#571).
  Missing: the check runs only when someone asks for the report, the link is computed, not
  written into the run record, and offline it sees reverts only.

## Pillar 3 — Simplicity

Easy to install, easy to fit into any workflow, low ceremony to keep using.

- [x] **SI1 — Install is one command, with no build step.** `skills/` is committed and
  complete. Guard: `tests/test-root-skills-install-surface.sh`.
- [x] **SI2 — Each skill is self-contained.** Its agents, docs and scripts ship inside it,
  and a precheck names anything missing. Guard: `tests/test-flattened-self-contained.sh`,
  `tests/test-dependency-closure.sh`.
- [x] **SI3 — It works with zero configuration.** `.idd.yml` is optional and every key has a
  default. Guard: `tests/test-scripts-pipeline-251.sh` (behavioural).
- [x] **SI4 — It needs only git, the tracker and its CLI.** No service, no database, no
  runtime. Scripts are stdlib-only and optional; every script call has a documented prose
  fallback. Guard: `tests/test-scripts-pipeline-251.sh`, judgement.
- [x] **SI5 — Each phase skill works alone.** The two orchestrators (`/auto-pilot`,
  `/plan-to-issues`) name the sibling skills they need and stop with a fix hint when one is
  absent. Guard: judgement.
- [x] **SI6 — The method works without the tooling.** `SPEC.md` and
  `docs/manual-idd-quickstart.md` are enough to run IDD by hand. Guard: judgement.
- [x] **SI7 — It works with any SKILL.md-compatible agent**, and installs as a Claude Code
  or Codex plugin. Guard: `tests/test-plugin-manifest-469.sh`,
  `tests/test-codex-plugin-489.sh`, `tests/test-autopilot-portability.sh`.
- [ ] **SI8 — The surface stays small, and its size is counted.** A new skill, config key,
  flag, gate or script must replace prose or remove a step. Partial: skills, shared
  scripts, script lines, config keys, flags, gate headings and files with `gh` calls are
  counted in `scripts/surface-counts.json`, and CI fails when one rises without that file
  changing in the same PR (#563; `tests/test-surface-counts-563.sh`, behavioural).
  Missing: raising a count is a hand edit nothing checks against the rule, and since the
  counter landed scripts rose 25 → 28, config keys 109 → 118, flags 26 → 30 and script
  lines 14,493 → 16,470, with one recorded exception (#573).
- [ ] **SI9 — It fits an existing workflow without imposing its own.** Partial: branch
  prefix, labels, merge mode, merge method (`review.merge_method`) and CI handling are
  configurable, and a repo PR template is kept with the IDD sections added; Conventional
  Commit titles are fixed, a rebase merge has no commit binding, and with the merge left to
  a human a full traceability pass needs that method's message source set to `PR_BODY`.
- [ ] **SI10 — It works with more than one tracker.** Partial: `SPEC.md` is tool-neutral and
  `docs/platform-github.md` catalogues the commands, but skills inline `gh` calls at each
  step and GitHub is the only driver.

## Pillar 4 — Trustworthiness

A maintainer can hand work to the skills and believe what they report.

- [x] **TR1 — No skill writes to the default branch, force-pushes, bypasses branch
  protection or changes repo settings.** Work lands on branches and PRs. Guard: judgement.
- [x] **TR2 — A merge is authorized against a fresh, receipted identity** of the commit that
  was reviewed. Guard: `tests/test-merge-identity-516.sh` (behavioural).
- [x] **TR3 — Known secrets and secret files are never committed.** A pre-commit scan runs
  in every commit-capable skill, and its policy is read from the base ref, not from the
  branch under review. Guard: `tests/test-pre-commit-security.sh`,
  `tests/test-secscan-policy-274.sh` (behavioural).
- [x] **TR4 — Sensitive changes get a stronger gate in the resolver.** Guard:
  `tests/test-sensitive-gate-518.sh` (behavioural).
- [x] **TR5 — Verdicts are deterministic.** Where a rule decides an outcome, a script
  decides it, with the shared exit-code vocabulary. Guard: `tests/test-scripts-252.sh`,
  `tests/test-scripts-253.sh`, `tests/test-state-scope-522.sh` (behavioural).
- [x] **TR6 — Every PR links its issue.** A missing `Closes #N` blocks; the commit reference
  and the Decision Record are checked and reported. Guard:
  `tests/test-issue-pr-review-traceability.sh` (prose pin), `scripts/idd-lint.py`.
- [x] **TR7 — Skills do not rewrite themselves.** They propose; a human approves. Guard:
  `tests/test-correction-guards-524.sh` for the corrections loop; judgement for the
  Self-Improve section.
- [ ] **TR8 — Reports are honest.** A failure reads as a failure, a skipped or disabled
  check as skipped, and unverified work as unverified. Partial: a soft-pass merge shows its
  unverified count, a disabled dimension reads `disabled`, and a resolver run on an unready
  issue or with an AC row not `pass` logs `verification: partial`
  (`tests/test-runs-jsonl.sh` T13a–e, behavioural for the field; T13f–l, prose pin; T13k
  also greps `src/` and `docs/` for a disabled check reported as `pass`). Missing: a
  resolver `PARTIAL` from residual QA findings or a check that could not be evaluated still
  logs `outcome: success` with `verification: full`.
- [ ] **TR9 — Auto mode never does more than the interactive default would.** Partial:
  every `[y/N]` gate takes its printed No in auto mode or is a row of the exception table in
  `docs/auto-mode.md`, a lint fails an unmarked gate, and an already-resolved issue gets a
  comment, never a close (`tests/test-auto-mode-gates-549.sh` T1–T4). One further gap is
  tracked privately per `SECURITY.md`.
- [ ] **TR10 — Existing work and data are never lost.** Partial: sync stashes first; a sync
  conflict resets the default branch only when `origin/<base>..HEAD` is empty and the
  tracked tree is clean, else auto-pilot stops and discards nothing
  (`tests/test-sync-safety.sh` T6–T8, behavioural; T5, static lint); post-merge cleanup
  keeps a dirty worktree and a branch with unmerged commits
  (`tests/test-postmerge-cleanup.sh`, behavioural); `/issue-creator` previews and backs up
  before a rewrite. Missing: the resolver's normalize step rewrites an issue body without a
  preview; it posts a backup comment first and skips the rewrite when that fails, but no
  test pins that order.
- [ ] **TR11 — Untrusted text is data, not instructions.** Partial: the shared agents treat
  issue titles, bodies and comments as data. The remaining gaps are tracked privately per
  `SECURITY.md`.
- [ ] **TR12 — Doubt fails safe.** A missing record, unreadable state or ambiguous result
  runs the check, blocks or stops. Partial: run state is a hint, never an authority; the
  premise reset blocks (`tests/test-premise-reset-519.sh`); a sync conflict with local work
  stops (`tests/test-sync-safety.sh` T6, T8); an unreadable dependency body or a missing
  `merge_floor` leaves the PR open (`tests/test-merge-gate-copies-619.sh` T1,
  `tests/test-review-followups-584.sh` T2); unreadable judge output is `unverified`
  (`tests/test-criteria-evidence-555.sh` T3). Missing: without `python3`, auto-pilot stops
  on a live `.idd/run.lock` but runs without taking one.
- [ ] **TR13 — Provenance is durable.** The PR records which model, effort and skill version
  produced the change. Partial: the resolver's PR body carries a *Produced by* line in the
  Decision Record (model, effort, skill version, locally modified), never in a commit
  trailer or the QA marker, and the run log takes `model`, `effort` and `skill_version`
  (#567; `tests/test-idd-lint.sh` T31, prose pin for the template, behavioural for the lint
  and trailer checks). Missing: model and effort read `unknown` when the host does not
  state them, the locally-modified flag is only `yes` or `unknown`, `idd-lint` P07 only
  warns when the line is absent, and commits a `/issue-pr-review` fix cycle adds carry no
  provenance.
- [ ] **TR14 — Autonomy is earned.** One risk tier, computed from the actual diff, drives
  review depth, verification and merge mode, and tightens or relaxes with the measured track
  record. Partial: `gi-sensitive.py --classify` returns one tier (`sensitive` or
  `standard`) from labels and the delivered diff; the resolver classifies again at
  Deliver, the review's Depth gate forces `full` on a sensitive or unknown tier whatever
  the Effort, and the merge floor leaves a sensitive PR open (#569;
  `tests/test-sensitive-gate-518.sh` G7, behavioural). Missing: the tier has two levels and
  no input from the track record, it does not drive verification, and a standard-tier
  resolver run still takes its profile from the issue's own Effort text.
- [ ] **TR15 — Every change is cheap to undo.** A documented revert path that keeps the
  trace intact. Partial: `/issue-pr-review <M> --revert` reverts a squash or merge commit
  through a new PR, reopens the issue with a link to the revert and logs a `revert_opened`
  row (`tests/test-idd-lint-stats-project.sh` T10, eval `issue-pr-review/revert-squash`,
  behavioural, against a stand-in); a rebase merge has no path, and no agent run is tested.
- [ ] **TR16 — Human attention is protected.** PR size limits, a short human-first summary,
  and a cap on PRs waiting for review. Partial: the PR body is summary-first, the size
  gates stop auto mode with a split recommendation, and an opt-in
  `autopilot.max_open_prs` caps open IDD PRs (#570). Missing: the cap is off by default,
  a custom branch prefix is not counted, and no PR size limit exists beyond the file and
  commit gates.

---

## Supporting properties

These keep the pillars standing. The same rules apply.

- [x] **SP1 — Autonomy.** In auto mode no skill stops on a prompt. Guard:
  `tests/test-autopilot-modes.sh`, `docs/auto-mode.md`.
- [x] **SP2 — Resilience.** A killed or rate-limited run resumes; a failing issue is
  quarantined and the loop continues; corrupt state starts fresh. Guard:
  `tests/test-autopilot-state-257.sh`, `tests/test-autopilot-hardening-259.sh`,
  `tests/test-progress-records-542.sh`.
- [ ] **SP3 — Observability.** A maintainer can tell whether the automation is getting
  better or worse. Partial: the resolver and auto-pilot write a local run log, and
  `/auto-pilot --stats` (`gi-stats.py`) reports run outcomes and the post-merge look-back
  from an installed skill, the look-back per release (#573; `tests/test-stats-573.sh`,
  behavioural). Missing: outcomes and token cost are totals, not per release; the log is
  local to one checkout and rotates; `docs/release-costs.md` has no measured entry;
  `/idd-doctor` is not shipped; and nothing beyond the look-back table shows a trend
  across releases.
- [ ] **SP4 — Enforcement over prose.** A rule that matters is a behavioural test, a lint
  check or a build abort. Partial: the build validators and shared scripts are tested this
  way; many skill rules are guarded by prose pins only.
- [ ] **SP5 — Projects learn from their runs.** Recurring review findings become guards in
  the target repo. Partial: `idd-lint corrections` counts repeated fix-cycle scopes and skip
  reasons and records approval-gated proposals; the Self-Improve section only runs with a
  user present.
- [ ] **SP6 — The whole system stays coherent.** Many small correct PRs must not erode the
  architecture; something checks the codebase as a whole. Partial: `/idd-doctor` checks IDD
  conformance only.

## Out of scope by decision

- Greenfield design and discovery before a concrete change can be accepted or rejected.
  `/plan-to-issues` starts from a finished plan; producing the plan is not IDD's job.

## Change log

Record every approved change to a value here: date, item, what changed, who asked.

| Date | Item | Change | Requested by |
|------|------|--------|--------------|
| 2026-11-11 | all | Initial checklist; markings set by review against v0.27.0 | maintainer |
| 2026-11-12 | issue-pr-review | Growth-cap exemption against v0.27.0: the bundle is 11,441 bytes (+3.72%) above its size at that tag (307,009 → 318,450). The growth accumulated on main between v0.27.0 and the cap's introduction in #558; approved on 2026-11-12 to let the cap land | maintainer |
| 2026-11-12 | issue-resolver | Growth-cap exemption against v0.27.0: the bundle is 11,924 bytes (+2.82%) above its size at that tag (421,981 → 433,905). The growth accumulated on main between v0.27.0 and the cap's introduction in #558; approved on 2026-11-12 to let the cap land | maintainer |
| 2026-11-12 | auto-pilot | Growth-cap exemption against v0.27.0: the bundle is 10,096 bytes (+2.30%) above its size at that tag (437,809 → 447,905). The growth accumulated on main between v0.27.0 and the cap's introduction in #558, and its last part came from #588 merging on 2026-11-12 before the cap landed; approved on 2026-11-12 to let the cap land | maintainer |
| 2026-11-14 | SI9 | Re-graded after #564; still unchecked. The `Partial:` note now records that the merge method is configurable and a repo PR template is kept, and that Conventional Commit titles, the rebase binding and the hand-merge message source remain | maintainer |
| 2026-11-15 | TR5 | Accepted exception: the auto-pilot open-PR cap (`autopilot.max_open_prs`, #570) counts open IDD PRs and decides its stop in prose rather than in a script; the cap is opt-in and off by default | maintainer |
| 2026-11-15 | auto-pilot | Growth-cap exemption against v0.27.0 raised: the bundle is 13,456 bytes (+3.07%) above its size at that tag (437,809 → 451,265). Covers the open-PR cap (#570) and the read-only `/auto-pilot --stats` path (#573); approved on 2026-11-15 | maintainer |
| 2026-11-15 | issue-pr-review | Growth-cap exemption against v0.27.0 raised: the bundle is 17,169 bytes (+5.59%) above its size at that tag (307,009 → 324,178). Covers the revert path (#571) and the risk tier (#569); approved on 2026-11-15 | maintainer |
| 2026-11-15 | TE10, SI8 | Accepted exception: gi-stats.py mirrors idd-lint.py's stats definitions byte for byte (pinned by tests/test-stats-573.sh T3) so idd-lint.py stays a single downloadable file, and `--stats` adds a script and a flag without replacing prose (#573) | maintainer |
| 2026-11-18 | issue-resolver | Growth-cap exemption against v0.27.0 raised: the bundle is 27,406 bytes (+6.49%) above its size at that tag (421,981 → 449,387). Covers the practice packs, their Step 3/4 wiring and the refreshed skill catalog (#649); approved on 2026-11-18 | maintainer |
| 2026-11-18 | issue-pr-review | Growth-cap exemption against v0.27.0 raised: the bundle is 29,677 bytes (+9.67%) above its size at that tag (307,009 → 336,686). Covers the shared practice packs its reviewer now checks a PR against (#649); approved on 2026-11-18 | maintainer |
| 2026-11-19 | issue-triage | Growth-cap exemption against v0.27.0: the bundle is 12,503 bytes (+9.08%) above its size at that tag (137,591 → 150,094). Covers the closed-question route mode: `references/route-mode.md`, the bundled `gi-route.py`, and its error and example entries (#647); approved on 2026-11-19 | maintainer |
| 2026-11-19 | issue-analysis | Growth-cap exemption against v0.27.0: the bundle is 14,374 bytes (+8.68%) above its size at that tag (165,496 → 179,870). Covers the `--plan` form that posts the recommended option as a plan comment, and the bundled `gi-plan.py` (#648); approved on 2026-11-19 | maintainer |
| 2026-11-19 | issue-resolver | Growth-cap exemption against v0.27.0 raised: the bundle is 47,254 bytes (+11.19%) above its size at that tag (421,981 → 469,235). Covers the plan-comment gate and the `agent:working` claim and release, with the bundled `gi-plan.py` and `docs/plan-and-claim.md` (#648); approved on 2026-11-19 | maintainer |
| 2026-11-19 | issue-pr-review | Growth-cap exemption against v0.27.0 raised: the bundle is 31,449 bytes (+10.24%) above its size at that tag (307,009 → 338,458). Covers the plan-conformance check and the bundled `gi-plan.py` (#648); approved on 2026-11-19 | maintainer |
| 2026-11-20 | VW3, VW5, VW6, VW10, VW11, VW13, VW17 | Ticked after a re-grade against `main` at 57722ec, each naming its guard. The `Partial:` notes of TE8–TE11, VW12, VW15, VW19, SI8, TR8–TR10, TR12–TR14 and SP3 were rewritten to the current state and name what is still missing; SI9, TR11, TR15, TR16 and VW18 were already current (#547) | maintainer |
| 2026-11-24 | issue-pr-review | Growth-cap exemption against v0.28.0: the bundle is 6,759 bytes (+1.99%) above its size at that tag (338,690 → 345,449), and reading reviewer rules from the base branch with diff-triggered REVIEW.md rules adds about 384 more to `code-reviewer.md` (about +2.11%), which the 2% cap cannot fit (#660); approved on 2026-11-24 | maintainer |
