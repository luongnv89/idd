# Correction Guards — recurring corrections → enforcement (issue #524)

How a correction the pipeline keeps re-learning becomes a deterministic guard.
The normative gate every agent and skill follows is the *Correction-to-enforcement*
section of `docs/shared-agent-conventions.md`; this document is the maintainer-facing
procedure, signal definitions, and ledger schema behind it. It is a project doc:
no skill reads it at run time, and `scripts/idd-lint.py corrections` implements
every deterministic step described here.

## Why

Some lessons are already encoded as structure: build aborts, `idd-lint` rules,
`gi-*` helpers, the negative-mutation build tests. What was missing is the loop
that *turns a recurring correction into* that structure. Reviewer findings and
fix cycles repeated run after run stayed folklore — each run re-paid the same
review round-trip — and nothing stopped an agent from "fixing" the skills
themselves in passing. This loop closes both holes: recurrence is detected from
plain data, proposals are deduplicated, and no skill text changes without a
human-approved proposal.

## Correction signals

Two signals, both free — the data already exists:

| Signal | Key | Source | Recurrence |
|--------|-----|--------|------------|
| Review-feedback fix cycle | `review-fix:<scope>` | commit subjects matching `fix(<scope>): address review feedback` (the fixer's commit convention) | scope seen ≥ `--threshold` times (default 2) |
| Repeated skip reason | `skip:<reason>` | `skipped_reason` in `.gitissue/runs.jsonl` | reason seen ≥ `--threshold` times |

The commit scan defaults to `--all` refs, not `HEAD`: this repo squash-merges,
so a PR's fix-cycle commits live on the PR branch and never appear on main's
first-parent history. Scopes and reasons are normalized to lowercase
`[a-z0-9._-]` keys, truncated at 40 characters.

## The loop

1. **Detect.** Run `python3 scripts/idd-lint.py corrections`. It exits 1 while
   any recurring key has no proposal — the same "findings exit 1" contract as
   the lint subcommands. `--json` emits the machine-readable form.
2. **Propose.** `... corrections --record` appends one `proposed` record per
   recurring key to `.gitissue/improvement-proposals.jsonl`, each carrying a
   suggested guard kind (`helper-guard`, `convention`, …) and its evidence.
   **Dedup:** a key whose latest event is `proposed`, `approved`, or `landed`
   is never re-proposed; fresh evidence accrues to the open record. A
   `rejected` key may be proposed again if the signal recurs.
3. **Approve — a human act.** `... corrections --approve <key>` records the
   approval. Agents and skills in auto mode never run this: they propose only.
   `--reject <key>` closes a proposal without action; both accept `--note`.
4. **Land.** `... corrections --landed <key>` is accepted only for an
   `approved` key, and only after the PR ships both parts:
   - a **reproducing negative test** — a `tests/*.sh` that fails on the
     pre-guard behavior (the correction, reproduced), registered as a named
     step in `.github/workflows/dist-check.yml`;
   - the **guard** itself — a type/schema rule, an `idd-lint` check, or a
     helper/build abort, whichever makes the corrected mistake impossible or
     immediately loud.

## Ledger schema

`.gitissue/improvement-proposals.jsonl` — append-only, newline-delimited JSON,
one event per line, local and deletable like the rest of `.gitissue/`. Readers
tolerate malformed lines (skip, never raise). A key's current status is its
**latest** event. Promote a proposal that matters to a GitHub issue; the ledger
is scratch, not the durable record.

Proposal event (written by `--record`):

```json
{"ts":"2026-10-06T12:00:00Z","key":"review-fix:resolver","kind":"helper-guard","summary":"7 review-feedback fix cycles under scope 'resolver'","evidence":["fix(resolver): address review feedback (#518)"],"count":7,"event":"proposed"}
```

Status event (written by `--approve` / `--reject` / `--landed`):

```json
{"ts":"2026-10-06T13:00:00Z","key":"review-fix:resolver","event":"approved","note":"ok — land as an idd-lint scope check"}
```

Fields: `ts` (ISO-8601 UTC), `key`, `event` (one of `proposed`, `approved`,
`rejected`, `landed`) are always present; `kind` (one of `negative-test`,
`lint-guard`, `helper-guard`, `convention`), `summary`, `evidence`, and `count`
describe a proposal; `note` is optional on status events.

## Surfacing

`/idd-doctor`'s informational run-log summary reports the count of pending
(`proposed`) skill improvements when a ledger exists, so the queue is visible
on every health check without changing the doctor's PASS/WARN/FAIL result.

## CLI reference

```
python3 scripts/idd-lint.py corrections [--branch REF] [--limit N] [--threshold N]
    [--log PATH] [--proposals PATH] [--json]
python3 scripts/idd-lint.py corrections --record
python3 scripts/idd-lint.py corrections --approve KEY [--note TEXT]
python3 scripts/idd-lint.py corrections --reject  KEY [--note TEXT]
python3 scripts/idd-lint.py corrections --landed  KEY [--note TEXT]
```

Exit codes follow the `idd-lint` contract: `0` clean/recorded, `1` recurring
corrections without an open proposal, `2` usage error (including invalid status
transitions — approving a key with no proposal, landing one not yet approved).
The command never writes outside the proposals ledger, and never edits `src/`,
`docs/`, `skills/`, or tests: proposals are data, approval is human, guards land
through ordinary PRs.
