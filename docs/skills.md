# IDD Stack Skills Reference

This page documents every public skill shipped by IDD Stack, what each skill does, and the supported input forms. Skills are invoked as slash commands in an agent session. One skill — `/idd-doctor` — is **repo-internal**: it is authored in `src/internal-skills/` and built by `./scripts/build.sh` into the local, gitignored `internal-skills/` package. Load that emitted package, not the source tree. It is excluded from the public `skills/` and `dist/` surface (see `docs/ARCHITECTURE.md`) and is not distributed for external install.

## Quick map

| Skill | Primary purpose | Typical input |
|---|---|---|
| `/init-gitissue` | Generate `.gitissue.yml` for a repo | No arguments |
| `/issue-creator` | Create, normalize, or batch-create structured GitHub issues | Text, issue number, multi-item text, screenshots |
| `/plan-to-issues` | Turn a phased plan or a conversation into an epic plus one labelled issue per task | Plan file path, `--from-conversation`, `--dry-run`, `--phase`, `sync <epic#>` |
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

Initializes IDD Stack configuration for the current repository by detecting language, framework, test runner, and repo size, then writing `.gitissue.yml`.

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
| `/issue-creator … --refresh-model-data` | Refresh cache | Force-refreshes the user-level model-data cache before proceeding (combines with any mode when model suggestion is enabled). |
| `/issue-creator <multi-item text>` | Batch | Extracts multiple issues from one input and creates them sequentially. |
| `/issue-creator <image path> [text]` | Screenshot/image issue | Reads visual context, uploads the image to GitHub, embeds it in the issue body, and creates a structured issue. |
| `/issue-creator … --auto` | Autonomous | Runs non-interactively (combines with any mode): every gate logs a `⚠` and takes its safe default instead of prompting — see `docs/auto-mode.md`. |

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

## `/plan-to-issues`

Converts a phased plan file — any path, any producer — or a conversation about what to build into labelled GitHub issues under one tracking epic. It is the bulk counterpart of `/issue-creator` and the entry point upstream of the loop: plan → `/plan-to-issues` → `/issue-triage` → `/issue-resolver` (or `/auto-pilot`) → `/issue-pr-review`. No plan file is required.

### Input options

| Input | Mode | Behavior |
|---|---|---|
| `/plan-to-issues` | Create | Resolves the input — plan discovery first, then the conversation — and creates the epic plus one issue per task. |
| `/plan-to-issues <path.md>` | Create | Uses that plan file. |
| `/plan-to-issues --from-conversation` | Create | Drafts the task list from the conversation, shows it, and files it only after you confirm. |
| `/plan-to-issues --from-conversation --epic <n>` | Resume | Restores the confirmed task list from epic #n and files only the remaining tasks. |
| `/plan-to-issues --dry-run` | Preview | Prints the task table, labels, and plan-map preview. Creates nothing. |
| `/plan-to-issues --phase P0,P1` | Create (filtered) | Files only those phases; the map still lists every phase. |
| `/plan-to-issues sync <epic#>` | Sync | Re-renders the epic's static plan map. Creates no issues. |

### Output

- One **epic** issue: whole-effort acceptance criteria plus a static plan map grouped by phase. Live open/closed status comes from GitHub native sub-issues, not the body.
- One issue per **task**, written by `/issue-creator` in batch mode with `--parent <epic>` (`Part of #<epic>`), labelled `phase:pN`, type, `dim:`, and `priority:`, with `Depends on #N` markers that `/auto-pilot`'s merge gate reads.
- Re-runs are idempotent: an existing epic is reused and only missing tasks are filed. No source file is modified.

### Requirements

- Requires `git`, authenticated `gh`, and a GitHub remote.
- Requires the sibling `issue-creator` skill from the same distribution — it writes every issue body.
- `python3` renders the plan map; without it the skill follows the documented manual procedure.

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
| `/issue-triage … --auto` | Autonomous | Runs non-interactively (combines with any invocation): the repo-sync gate logs a `⚠` and syncs instead of prompting — see `docs/auto-mode.md`. |

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

Reviews an existing PR end-to-end: pre-pass, review, tests/build, CI, fix loop, and final report. By default, it fixes and repeats until clean; auto-merge only happens in `--auto` mode. After a merge, or on a PR it finds already merged, it cleans up the local checkout: it deletes the merged local branch, removes its clean worktrees, and switches from the merged branch to the updated base branch. Anything with uncommitted changes, untracked files, or commits the PR never had is kept and reported (an interactive run can delete untracked files after you confirm the list, never in auto mode); on an already-merged PR an interactive run shows the plan and asks first, and `--review-only` only reports.

### Input options

| Input | Mode | Behavior |
|---|---|---|
| `/issue-pr-review <N>` | Interactive fix loop | Reviews PR #N, fixes `action: fix` issues, repeats until clean or stopped, and reports. Does not auto-merge. |
| `/issue-pr-review <N> --auto` | Auto-pilot | Reviews, fixes, waits for CI, auto-merges when clean, then cleans up the local checkout (merged branch, clean worktrees, switch to the updated base). |
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

The loop pauses only for critical unresolved review failures, because that decision is not safely reversible. A dependency-blocked PR (`Depends on #N` / `Blocked by #N`) is never merged out of order, but it does not halt the run either: the PR is left open with outcome `blocked_by_dependency` and the loop continues to the next eligible issue. After every merge (clean, partial, or critical-issue, sequential or parallel, and for a merged PR found at resume) the loop cleans up the local checkout the same way `/issue-pr-review` does; anything it keeps is listed in the run summary's *Uncertainty* section.

### Requirements

- Requires `git`, authenticated `gh`, GitHub remote, push access, and merge permission.
- Requires the core IDD Stack skills from the same distribution: `issue-triage`, `issue-analysis`, `issue-resolver`, and `issue-pr-review`.

---

## `/idd-doctor` (repo-internal)

Runs a read-only health check for this IDD repository. It does not modify files, comments, issues, or PRs.

`/idd-doctor` is a **repo-internal** skill authored in `src/internal-skills/`. From a clone of this repository, run `./scripts/build.sh` and load the emitted local, gitignored `internal-skills/` package, not the source tree. It is excluded from the public `skills/` and `dist/` distribution surface (per `docs/ARCHITECTURE.md`) and has no external install command.

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
| File a phased plan or a conversation as an epic plus issues | `/plan-to-issues` or `/plan-to-issues <path.md>` |
| Understand one issue before implementing | `/issue-analysis <N>` |
| Decide what to work on next | `/issue-triage` or `/issue-triage update` |
| Implement one issue | `/issue-resolver <N>` |
| Review and clean up an existing PR | `/issue-pr-review <PR_NUMBER>` |
| Audit a PR without edits | `/issue-pr-review <PR_NUMBER> --review-only` |
| Process the backlog autonomously | `/auto-pilot` |
| Check IDD repo health | `/idd-doctor` |
