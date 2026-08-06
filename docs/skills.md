# gitissue Skills Reference

This page documents every public skill shipped by gitissue / IDD, what each skill does, and the supported input forms. Skills are invoked as slash commands in an agent session. One skill — `/idd-doctor` — is **repo-internal**: it lives in `src/internal-skills/`, is excluded from the built `skills/` and `dist/` surface (see `docs/ARCHITECTURE.md`), and is not distributed for external install.

## Quick map

| Skill | Primary purpose | Typical input |
|---|---|---|
| `/init-gitissue` | Generate `.gitissue.yml` for a repo | No arguments |
| `/issue-creator` | Create, normalize, or batch-create structured GitHub issues | Text, issue number, multi-item text, screenshots |
| `/issue-analysis` | Deep-analysis report for one issue | Issue number, optional `view` |
| `/issue-triage` | Prioritize and order the issue backlog | No args, `update`, `--limit N` |
| `/issue-resolver` | Resolve one issue and open an atomic PR | Issue number, optional `--auto` |
| `/issue-pr-review` | Review a PR, run tests/CI, fix issues in cycles | PR number or current branch PR, optional modes |
| `/auto-pilot` | Fully autonomous backlog loop | Optional issue list, limit, dry-run, skip |
| `/idd-doctor` (repo-internal) | Read-only IDD repository health check | No arguments |

## Shared conventions

- `N` means a GitHub issue or PR number, depending on the skill.
- Skills that use GitHub require `gh` to be installed and authenticated unless noted otherwise.
- Skills load `.gitissue.yml` once at startup when they use config.
- `--auto` means autonomous mode: no user prompts where the skill can safely decide.
- `--review-only` means no fixes and no merge.
- Slash commands shown here are the documented public interface; natural-language requests may trigger the same skills when the agent supports skill discovery.

---

## `/init-gitissue`

Initializes IDD configuration for the current repository by detecting language, framework, test runner, and repo size, then writing `.gitissue.yml`.

### Input options

| Input | Mode | Behavior |
|---|---|---|
| `/init-gitissue` | Generate config | Scans the repo and creates `.gitissue.yml` if missing. |

### Existing config behavior

If `.gitissue.yml` already exists, the skill asks whether to:

- `overwrite` — replace it with a freshly generated config.
- `merge` — preserve existing values and add missing schema fields.
- `cancel` — stop without changing files.

### Requirements

- Requires `git` only.
- Does not require `gh` or GitHub authentication.

---

## `/issue-creator`

Creates structured, intent-focused GitHub issues. It preserves reporter context and acceptance criteria, but does not inspect code or guess implementation details.

### Input options

| Input | Mode | Behavior |
|---|---|---|
| `/issue-creator <text>` | Create | Creates one new structured issue from a text description. |
| `/issue-creator <N>` | Normalize | Rewrites existing issue #N into the standard template. |
| `/issue-creator <N> --dry-run` | Preview | Shows the normalization preview without applying it. |
| `/issue-creator <N> --force` | Force normalize | Normalizes even when the issue has security-sensitive labels. |
| `/issue-creator … --refresh-model-data` | Refresh cache | Force-refreshes the skill-level model-data cache before proceeding (combines with any mode when model suggestion is enabled). |
| `/issue-creator <multi-item text>` | Batch | Extracts multiple issues from one input and creates them sequentially. |
| `/issue-creator <image path> [text]` | Screenshot/image issue | Reads visual context, uploads the image to GitHub, embeds it in the issue body, and creates a structured issue. |

### Mode detection

- Numeric argument → normalize that issue.
- Multiple distinct bullets/numbered items/paragraphs → batch mode.
- Otherwise → create one issue.

### Supported image formats

PNG, JPG/JPEG, GIF, WEBP, and SVG, up to 10 MB per image.

### Requirements

- Requires `git` and authenticated `gh`.
- Requires a GitHub remote.

---

## `/issue-analysis`

Performs deep analysis for one GitHub issue and persists the result to `.gitissue/analysis-<N>.json`.

### Input options

| Input | Mode | Behavior |
|---|---|---|
| `/issue-analysis <N>` | Full analysis | Fetches issue #N, scans the codebase, identifies root cause, affected areas, options, risk, and complexity, then writes `.gitissue/analysis-<N>.json`. |
| `/issue-analysis <N> view` | Cached view | Reads `.gitissue/analysis-<N>.json` and renders the cached report without rescanning or calling GitHub. |

### Requirements

- Full analysis requires `git`, authenticated `gh`, and a GitHub remote.
- `view` mode only needs local file access to the cached JSON.

---

## `/issue-triage`

Analyzes the open issue backlog for priority, dependencies, parallelizable work, stale issues, and already-fixed signals. Results are cached in `.gitissue/triage.json`.

### Input options

| Input | Mode | Behavior |
|---|---|---|
| `/issue-triage` | Cached view | Shows cached triage immediately. If no cache exists, runs the first full analysis automatically. |
| `/issue-triage update` | Full update | Re-analyzes open issues and overwrites `.gitissue/triage.json`. |
| `/issue-triage --limit N` | Limited update | Re-analyzes up to N issues and overwrites the cache. |

### Default behavior

Viewing is cheap and instant. After showing cached data, the skill checks local git history and report age, then suggests `/issue-triage update` if the cache may be stale.

### Requirements

- Cached view needs local file access.
- Full update requires `git`, authenticated `gh`, and a GitHub remote.

---

## `/issue-resolver`

Resolves one GitHub issue end-to-end and creates an atomic PR.

### Input options

| Input | Mode | Behavior |
|---|---|---|
| `/issue-resolver <N>` | Interactive | Resolves issue #N, asks the user to pick an implementation plan, implements, tests, and opens a PR. |
| `/issue-resolver <N> --auto` | Auto-pilot | Resolves issue #N autonomously with no user prompts. |
| `/issue-resolver <N> --no-run-log` | Modifier | Suppresses the resolver's own `.gitissue/runs.jsonl` append and returns telemetry to the caller instead. Orthogonal to `--auto`; passed only by `/auto-pilot`, which is the single writer of the run-log line. |

### Pipeline summary

1. Preflight and repo sync.
2. Research the issue and current codebase.
3. Synthesize implementation options.
4. Implement selected option with tests.
5. Run QA review/test/build/fix loop.
6. Push branch and create PR.

### Requirements

- Requires `git`, authenticated `gh`, GitHub remote, and push access.

---

## `/issue-pr-review`

Reviews an existing PR end-to-end: pre-pass, review, tests/build, CI, fix loop, and final report. By default, it fixes and repeats until clean; auto-merge only happens in `--auto` mode.

### Input options

| Input | Mode | Behavior |
|---|---|---|
| `/issue-pr-review <N>` | Interactive fix loop | Reviews PR #N, fixes `action: fix` issues, repeats until clean or stopped, and reports. Does not auto-merge. |
| `/issue-pr-review <N> --auto` | Auto-pilot | Reviews, fixes, waits for CI, and auto-merges when clean. |
| `/issue-pr-review` | Detect PR | Auto-detects the PR for the current branch and runs the default fix loop. |
| `/issue-pr-review --review-only` | Read-only | Runs one review/test/CI pass, reports findings, never fixes, loops, or merges. |

### Fix-loop stop conditions

The review-fix cycle stops when:

- zero `action: fix` issues remain;
- tests pass;
- CI passes or no CI is configured;
- traceability is not `fail`;
- no acceptance criterion is `fail`;
- the max cycle count is reached (`review.max_cycles`, default `3`);
- the same issue appears in two consecutive cycles;
- a blocking operational error occurs, such as rebase conflict or secret detection.

Medium `action: note` findings and non-blocking `partial` dimensions may remain and are reported.

### Review-only distinction

Use `--review-only` when you want an audit report but do not want the agent to edit files, commit fixes, push, loop, or merge.

### Requirements

- Requires `git`, authenticated `gh`, a GitHub remote, and access to the PR branch.

---

## `/auto-pilot`

Runs the full IDD loop over the issue backlog: triage, pick, resolve, review, fix, merge, repeat.

### Input options

| Input | Behavior |
|---|---|
| `/auto-pilot` | Triage all open issues, pick the next issue, resolve, review, merge according to config, and continue. |
| `/auto-pilot --issues 5,10,12` | Process only issues #5, #10, and #12 in that exact order. Skips backlog triage ordering. |
| `/auto-pilot --limit N` | Process at most N issues, then stop. |
| `/auto-pilot --dry-run` | Run triage and show the execution plan without resolving anything. |
| `/auto-pilot --skip N` | Skip issue #N for this session. |

### Flag combinations

- `--issues` can combine with `--dry-run` and `--skip`.
- `--issues` cannot combine with `--limit` because the explicit issue list is already the limit.

Example:

```text
/auto-pilot --issues 5,10,12 --skip 10 --dry-run
```

### Merge behavior

Controlled by `.gitissue.yml`:

- `autopilot.mode: conservative` — creates/reviews PRs but never auto-merges.
- `autopilot.mode: balanced` — default; merges clean PRs, leaves unresolved PRs open.
- `autopilot.mode: aggressive` — may merge partial PRs only when `autopilot.merge_partial: true` is also set.

The loop pauses only for critical unresolved review failures, because that decision is not safely reversible. A dependency-blocked PR (`Depends on #N` / `Blocked by #N`) is never merged out of order, but it does not halt the run either: the PR is left open with outcome `blocked_by_dependency` and the loop continues to the next eligible issue.

### Requirements

- Requires `git`, authenticated `gh`, GitHub remote, push access, and merge permission.
- Requires the core IDD skills from the same distribution: `issue-triage`, `issue-analysis`, `issue-resolver`, and `issue-pr-review`.

---

## `/idd-doctor` (repo-internal)

Runs a read-only health check for this IDD repository. It does not modify files, comments, issues, or PRs.

`/idd-doctor` is a **repo-internal** skill: it lives in `src/internal-skills/`, is excluded from the built `skills/` and `dist/` distribution surface (per `docs/ARCHITECTURE.md`), and has no external install command. It is intended to run from a clone of this repository.

### Input options

| Input | Mode | Behavior |
|---|---|---|
| `/idd-doctor` | Report-only check | Scans for stale intent-code-boundary claims, forbidden issue-template fields, missing `autopilot.mode`, and unsafe merge defaults. |

### Checks

| Check | Result type |
|---|---|
| Stale skill claims in issue-creator docs | `FAIL` on drift |
| Forbidden issue-template fields | `FAIL` on forbidden fields |
| Missing `autopilot.mode` when `.gitissue.yml` exists | `FAIL` |
| Repository squash-merge default | `WARN` when not squash-only; skipped (`○`) when `gh` is absent or unauthenticated |

After the four gating checks, the doctor prints one **informational, non-gating** section — a *run-log summary* over the last N runs (default 50) recorded in `.gitissue/runs.jsonl`. It reports resolve rate, median QA cycles, and common skip reasons, and never affects the PASS/WARN/FAIL result. When no runs are recorded, it degrades gracefully to a single `○` line.

### Requirements

- Requires `git`.
- `gh` is optional; without it, the merge-strategy check is skipped with an informational note.

---

## Choosing the right skill

| Goal | Use |
|---|---|
| First-time setup | `/init-gitissue` |
| Turn a bug report or feature request into a structured issue | `/issue-creator <text>` |
| Normalize an existing issue | `/issue-creator <N>` |
| Understand one issue before implementing | `/issue-analysis <N>` |
| Decide what to work on next | `/issue-triage` or `/issue-triage update` |
| Implement one issue | `/issue-resolver <N>` |
| Review and clean up an existing PR | `/issue-pr-review <PR_NUMBER>` |
| Audit a PR without edits | `/issue-pr-review <PR_NUMBER> --review-only` |
| Process the backlog autonomously | `/auto-pilot` |
| Check IDD repo health | `/idd-doctor` |
