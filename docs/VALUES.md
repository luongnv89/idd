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

Markings were last reviewed on 2026-11-11 against v0.27.0.

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
- [ ] **TE8 — Bundles do not grow release over release without approval.** Partial: growth
  is explicit (TE2), but the budget is raised by hand in the same PR and has risen in most
  changes to it. The line cap (TE1) is met with denser lines; SKILL.md has no byte ceiling.
- [ ] **TE9 — Progressive disclosure: a step reads only what that step needs.** Partial:
  steps and phases are split into their own files and two skills have tested disclosure
  gates (`tests/test-disclosure-gates-250.sh`); the common resolver and auto-pilot paths
  still load more than half the bundle, including whole files for one section.
- [ ] **TE10 — One home per instruction: written once and pointed to, never copied.**
  Partial: eight blocks are pinned by `tests/test-consolidated-blocks-248.sh`; `run-stats.md`
  is authored once per skill, and the Self-Improve section and common error messages repeat
  across skills.
- [ ] **TE11 — Runtime token cost per resolved issue is tracked across releases.** Partial:
  one measurement exists in `docs/experiments/cost-counters-465.md`; the run log has no
  token field and the `gh`-call counter runs in the eval lab only.

## Pillar 2 — Verification of work

Nothing is done on an agent's say-so. Three things are verified: the **intention**, the
**code**, and the **outcome**.

### Intention

- [x] **VW1 — What was inferred is marked, never presented as known.** Confidence markers
  on type, criteria and metadata. Guard: `tests/test-issue-creator-confidence-191.sh`
  (prose pin).
- [x] **VW2 — Every issue IDD writes carries acceptance criteria.** Guard: issue templates,
  `scripts/idd-lint.py` (checks that at least one criterion exists).
- [ ] **VW3 — An unclear issue is never implemented unattended.** Partial: interactive
  create asks up to two questions at low confidence; batch and auto mode guess and mark
  `(needs review)`, and nothing downstream reads the marker. An issue with no criteria, or
  with criteria the resolver wrote itself, still resolves and merges.
- [ ] **VW4 — Criteria are testable, not just present.** Partial: `SPEC.md` §1 requires it;
  nothing checks it.
- [ ] **VW5 — The plan is mapped to each criterion before implementation.** Partial: design
  sketches reject invalid state transitions (`tests/test-design-sketch-520.sh`) and the
  design-confirm checkpoint is interactive only; plan options carry no criteria mapping.
- [ ] **VW6 — The contract states its boundaries**: non-goals, invariants that must not
  change, and non-functional constraints. Partial: the implementer notes out-of-scope items;
  the issue template has no place for them.
- [ ] **VW7 — A change to the issue mid-run is noticed.** Partial: checked when an analysis
  is reused and by the review's fresh read; not between preflight and deliver, or between
  review and merge.

### Code

- [x] **VW8 — Each acceptance criterion is judged separately, with evidence, and a `fail`
  blocks the merge.** Guard: `tests/test-issue-pr-review-traceability.sh` (prose pin).
- [x] **VW9 — The suite and the build run in every QA cycle, and a merge is bound to the
  head commit that was verified.** Holds on default config. Guard:
  `tests/test-merge-identity-516.sh` (head binding); judgement for the per-cycle run.
- [ ] **VW10 — Unverified work never merges as clean.** Partial: `unverified` is a distinct
  status, but under the default `review.soft_pass: true` it is report-only, so a PR with no
  proven criterion can pass and merge.
- [ ] **VW11 — Criterion evidence is independent and reproducible.** Partial: a `pass` needs
  evidence, but a one-line description counts, and the PR reviewer is handed the PR body
  with the resolver's own verdicts. Resolver QA does spawn a fresh reviewer per cycle.
- [ ] **VW12 — Tests prove what they claim.** Partial: the implementer must report mutation
  sensitivity, pinned outputs and any weakened test
  (`tests/test-behavior-test-contracts-521.sh`, prose pin); the report is its own,
  `not_verified` never blocks, and the PR review does not read it.
- [ ] **VW13 — A bug fix is red before and green after.** Partial: the reproduction is
  required and recorded; a missing one never stops the run, and the review cites it without
  re-running it.
- [ ] **VW14 — Behaviour is exercised, not only read.** Partial: verification recipes are
  real and tested (`tests/test-verification-recipes-523.sh`, behavioural) but opt-in, and
  the browser UI review is skipped in auto mode.
- [ ] **VW15 — Non-functional criteria are verified** when the issue states them. Partial:
  the code reviewer has a security category and UI changes get an accessibility review;
  nothing covers performance.

### Outcome

- [x] **VW16 — The skill set is tested on every change.** The test of record runs in CI,
  with negative mutation tests of the build and a coverage floor on the shared scripts.
  Guard: `.github/workflows/dist-check.yml`, `tests/test-build-negative-mutations.sh`,
  `tests/test-coverage-floor-333.sh`.
- [ ] **VW17 — Every run reports what it verified and what it did not.** Partial: the PR
  body carries the criteria table and the summaries have Uncertainty rows; auto-pilot
  reports a soft-pass merge as clean, a disabled check prints `pass`, and the run log has no
  verification field.
- [ ] **VW18 — Skill behaviour is verified with real agent runs.** Partial: the hermetic
  evals replay fixed stand-ins, the real-agent promotion lane has no locked tasks, and
  three skills have no eval cases.
- [ ] **VW19 — The outcome is checked after merge.** A reopened issue, a revert or a
  follow-up bug is linked back to the run that shipped the change. Partial: none; the trace
  ends at merge.

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
  flag, gate or script must replace prose or remove a step. Partial: bundle bytes are
  budgeted; skills, scripts, config keys, flags and gates are not counted, and all have
  grown.
- [ ] **SI9 — It fits an existing workflow without imposing its own.** Partial: branch
  prefix, labels, merge mode and CI handling are configurable; squash merge, the PR body
  template and Conventional Commit titles are fixed, and a full traceability pass needs the
  repo set to squash-only with `PR_BODY`.
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
  check as skipped, and unverified work as unverified. Partial: the statuses exist and an
  unread setting is never reported as `pass`; auto-pilot collapses a soft-pass into
  `merged`, a disabled check prints `pass`, and a resolver `PARTIAL` is logged as `success`.
- [ ] **TR9 — Auto mode never does more than the interactive default would.** Partial:
  `docs/auto-mode.md` states it; auto mode proceeds past several default-No prompts, and
  closes an issue it judges already resolved. One further gap is tracked privately per
  `SECURITY.md`.
- [ ] **TR10 — Existing work and data are never lost.** Partial: sync stashes first
  (`tests/test-sync-safety.sh`) and `/issue-creator` previews and backs up before a rewrite;
  auto-pilot hard-resets the local default branch on a sync conflict, and the resolver's
  normalize step rewrites an issue body without a preview.
- [ ] **TR11 — Untrusted text is data, not instructions.** Partial: the shared agents treat
  issue titles, bodies and comments as data. The remaining gaps are tracked privately per
  `SECURITY.md`.
- [ ] **TR12 — Doubt fails safe.** A missing record, unreadable state or ambiguous result
  runs the check, blocks or stops. Partial: run state is a hint, never an authority, and
  the premise reset blocks (`tests/test-premise-reset-519.sh`); the cases under TR9 and TR10
  fail open, and a missing `python3` runs without the run lock.
- [ ] **TR13 — Provenance is durable.** The PR records which model, effort and skill version
  produced the change. Partial: none; the run log records the pipeline profile and whether
  agent overrides applied, and it is local and gitignored.
- [ ] **TR14 — Autonomy is earned.** One risk tier, computed from the actual diff, drives
  review depth, verification and merge mode, and tightens or relaxes with the measured track
  record. Partial: profile, sensitive-change gate, review depth and merge mode are separate
  mechanisms with separate inputs, and the profile is chosen from the issue's own Effort
  text.
- [ ] **TR15 — Every change is cheap to undo.** A documented revert path that keeps the
  trace intact. Partial: atomic PRs make it possible; no skill does it.
- [ ] **TR16 — Human attention is protected.** PR size limits, a short human-first summary,
  and a cap on PRs waiting for review. Partial: the PR body is summary-first and
  `autopilot.max_parallel` caps resolver concurrency; the size warnings do not stop auto
  mode and nothing caps the review queue.

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
  better or worse. Partial: the resolver and auto-pilot write a local run log;
  `/idd-doctor` and `idd-lint stats` are not shipped in any installed skill and there is no
  trend view.
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
