# Prompt audit — November 2026 (issue #604)

Project doc: no skill reads it at run time. It records a `/doctor prompt-audit`
pass over every skill and what was done with each finding.

## Method

- **Tool:** Claude Code's built-in `/doctor prompt-audit` (Claude Code 2.1.326,
  Claude Opus 5.5), run non-interactively as
  `claude -p "/doctor prompt-audit <dir>"` from the repo root, one run per target.
  The audit is an LLM review: every finding was checked against the current files
  before it was acted on.
- **Targets (10):** the eight skills under `src/skills/`, the internal
  `src/internal-skills/idd-doctor/`, and `src/shared/agents/` +
  `src/shared/references/` together (the shared files every skill bundles).
- **Policy (the "Balanced" plan picked for #604):**
  - high/medium findings whose action is `rewrite` or `remove` → **fixed**;
  - low-confidence or flag-only findings → **kept**, with a reason;
  - anything that would reword or weaken a safety gate (secret scan, merge gates,
    worktree identity, QA marker/receipt, sensitive-change gate, premise reset),
    needs a new script or a build change, or would trade away a `docs/VALUES.md`
    item → **kept**, recorded as a maintainer decision or follow-up;
  - a fix whose home is outside the audited directory → **out-of-scope** in the
    ledger, then applied (or kept) serially; see *Out-of-scope rows* below.
- **Round 2:** the same audit re-run on the edited sources, restricted to
  high/medium rewrite/remove findings plus brief flag notes. Its findings were
  handled under the same policy.

## Results

| Target | Round 1 fixed / kept / out-of-scope | Round 2 fixed / kept / out-of-scope |
|--------|------|------|
| auto-pilot | 11 / 7 / 1 | 24 / 5 / 0 |
| init-idd | 12 / 4 / 1 | 3 / 4 / 0 |
| issue-analysis | 8 / 7 / 1 | 5 / 5 / 1 |
| issue-creator | 10 / 3 / 0 | 5 / 6 / 1 |
| issue-pr-review | 5 / 7 / 0 | 5 / 7 / 0 |
| issue-resolver | 13 / 5 / 1 | 14 / 7 / 0 |
| issue-triage | 8 / 2 / 0 | 8 / 6 / 0 |
| plan-to-issues | 9 / 7 / 1 | 5 / 4 / 0 |
| idd-doctor | 10 / 3 / 1 | 4 / 5 / 0 |
| shared agents + references | 5 / 3 / 1 | 3 / 6 / 0 |
| **Total** | **91 / 48 / 7** | **76 / 55 / 2** |

Each ledger was written to give every finding in its report one row with one
outcome: no finding is left open.

- Raw reports (quoted commands write `gi-issue[.]py` so repo-wide call-site scans skip them): `round-1/reports/<target>.md`, `round-2/reports/<target>.md`
- Ledgers (one row per finding, with the change or the reason):
  `round-1/ledgers/<target>.md`, `round-2/ledgers/<target>.md`

## Out-of-scope rows — final outcome

| Ledger | Row | Final outcome |
|--------|-----|---------------|
| round-1 idd-doctor | 10 — run-stats paragraph in `references/error-messages.md` argues with a reviewer | **fixed** in all nine skills' `error-messages.md`; the normative "never end without the footer" clause kept |
| round-1 shared | 5 — orchestrator batching rules inside `issue-relationship-scanner.md` | **fixed**: the two missing merge rules moved into `issue-triage/references/detection.md`, then the section removed from the agent |
| round-1 init-idd | 8b — "prior 2.1.x behavior" in `docs/config-schema.md` | **fixed** |
| round-1 issue-resolver | 5b — catalog-maintenance steps removed from `skill-index.md` | **fixed**: moved to `docs/DEVELOPMENT.md` (*Maintaining the issue-resolver skill catalog*) |
| round-2 issue-creator | 4b — `tests/README-sprint2.md` expected the old batch line | **fixed** |
| round-1 issue-analysis 16, round-2 issue-analysis F1 | synthesizer's "2–3 ranked options" vs "one justified option is valid" | **kept**: changes resolver/analysis wording that tests pin; maintainer decision |
| round-1 auto-pilot | L6 — widen `tests/test-runtime-text-history-628.sh` regex | **kept**: low confidence; needs a false-positive sweep |
| round-1 plan-to-issues | F1 — skill forbids the epic child checklist SPEC §2.1 says SHOULD exist | **kept**: SPEC change is a maintainer decision |

One more removal moved maintainer material out of the bundle: auto-pilot's
*Measuring the body-snapshot budget* note now lives in `docs/DEVELOPMENT.md`.

## Maintainer decisions recorded as kept

The ledgers carry the detail; these are the items that need a decision, not
more prose work:

- **Secret-scan pass rule drift** between `src/shared/agents/fixer.md` and
  `implementer.md` (staged-count check; an empty-stage scan reading as clean).
  Safety gate.
- **issue-pr-review:** the scan-warning pointer in
  `references/prepass-tests-ci-mechanics.md`, the "Keep this recompute" QA-handoff
  wording, and the auto-mode `browser_review: "true"` handling that differs
  between `references/ui-review-mechanics.md` and `docs/ui-review.md`.
- **Security-label skip** wording in issue-creator's Normalize mode.
- **New-script candidates:** the deterministic Part B of
  `issue-relationship-scanner.md` (commit/PR parsing), and idd-doctor's
  deterministic checks.
- **SPEC alignment:** the epic child checklist (plan-to-issues F1).

## Out of this audit's scope

`/doctor prompt-audit` with no argument audits only the repo-root `CLAUDE.md` and
`AGENTS.md`. That run found stale facts there (the issue-section list missing
`## Constraints`, docs trees missing `run-log-schema.md`, `ui-review.md` and
`agent-overrides.md`). Those files are not skills, so they are left for a
separate issue.
