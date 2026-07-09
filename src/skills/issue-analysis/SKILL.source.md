---
name: issue-analysis
description: "Analyze one GitHub issue for root cause, complexity, and risk into .gitissue/analysis-N.json. Use when you need to analyze or scope issue #N. Don't use for creating issues (/issue-creator), triaging (/issue-triage), or resolving (/issue-resolver)."
license: MIT
compatibility: "Requires git and GitHub CLI (gh) with authentication. View mode (`/issue-analysis N view`) needs only local file access — no gh required."
effort: high
metadata:
  version: 0.5.2
  author: Luong NGUYEN <luongnv89@gmail.com>
---

# /issue-analysis N

Deep analysis of a single GitHub issue — root cause, architecture impact, implementation options, complexity, and risk. Produces a terminal report and persists results to `.gitissue/analysis-<N>.json`.

## Invocation

| Invocation | What happens |
|------------|--------------|
| `/issue-analysis <N>` | Full deep analysis of issue #N, persist to `.gitissue/analysis-<N>.json` |
| `/issue-analysis <N> view` | Render cached analysis from `.gitissue/analysis-<N>.json` without re-scanning |

The argument must be a GitHub issue number.

## View Mode

When invoked as `/issue-analysis <N> view`, skip the entire analysis pipeline (Steps 1-8) and the persist step. Instead:

1. Check for `.gitissue/analysis-<N>.json` at the repo root
2. If the file does not exist, output the empty-state message from `references/error-messages.md` and stop:
   ```
   ○ No analysis found for issue #N. Run /issue-analysis N to generate one.
   ```
3. Read and parse the JSON file
4. If the JSON is malformed or unparseable, output the error from `references/error-messages.md` and stop:
   ```
   ✗ .gitissue/analysis-N.json is corrupted

     To fix:  rm .gitissue/analysis-N.json && /issue-analysis N
     Check:   was the file edited manually?
   ```
5. Compute report age from the `timestamp` field relative to now
6. Render the full analysis report to terminal using the same DESIGN.md format as Step 6, with a cache header:

```
◆ Issue Analysis (cached)
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Issue:       #N {title}
  Last run:    {timestamp, formatted as YYYY-MM-DD HH:MM UTC}
  Report age:  {Nd Nh} (e.g., "3d 2h")

  ... (full analysis sections rendered from JSON) ...

○ Cached report. Run /issue-analysis N for fresh analysis.
```

After rendering, stop. View mode never writes to the file or makes API calls.

---

## Prerequisites

**View mode** (`/issue-analysis <N> view`) needs only a local `.gitissue/analysis-<N>.json` — skip the `gh` checks below.

For the full analysis pipeline, verify the environment before any operation. On failure, output the exact error from `references/error-messages.md` and stop.

1. Confirm git repository: `git rev-parse --git-dir`
2. Confirm `gh` is installed: `which gh`
3. Confirm authentication: `gh auth status`
4. Confirm GitHub remote exists: `git remote -v`

## Repo Sync (recommended)

Before analyzing, recommend syncing with the remote so codebase analysis uses current code:

```
⚡ Your branch may be behind the remote. Sync before analyzing?

  This ensures analysis targets the latest code.
  Sync now? [Y/n]
```

In **auto/subagent** mode (`IDD_AUTO_MODE=1` or invoked by `/auto-pilot`), skip this prompt and run the stash-first sync immediately.

If the user agrees (interactive), run the stash-first sync (see `docs/sync-conventions.md`):

```bash
branch="$(git rev-parse --abbrev-ref HEAD)"
dirty=0
if [ -n "$(git status --porcelain)" ]; then
  git stash push -u -m "pre-sync: ${branch}"
  dirty=1
fi
git fetch origin
git pull --rebase origin "$branch"
if [ "$dirty" -eq 1 ]; then
  git stash pop || {
    echo "✗ Stash pop failed — recover with: git stash list && git stash show -p stash@{0}"
    exit 1
  }
fi
```

If `origin` is missing or rebase conflicts occur, inform the user and continue without syncing. If the user declines the prompt, proceed without syncing.

## Configuration

Load `.gitissue.yml` from the repo root once at skill start. If the file does not exist, use defaults and print:

```
○ First run — using default config. Run /init-gitissue to customize.
```

Analysis settings and defaults:

| Setting | Default | Description |
|---------|---------|-------------|
| `analysis.max_files` | `30` | Max files to read during deep analysis |
| `analysis.trace_depth` | `3` | How many levels of import dependencies to trace |
| `analysis.scan_timeout` | `120` | Max seconds for the full codebase scan phase |

If the config file exists but contains invalid values, output the validation error from `references/error-messages.md` and stop.

Do not re-read the config at each step.

---

## Subagent Architecture

The analysis pipeline delegates heavy work to subagents to keep the main agent's **context window** clean and minimize **token** usage. The main agent orchestrates and communicates with the user, while subagents handle codebase exploration and analytical synthesis within their own token budgets.

```
Main Agent (orchestrator)
├── Step 1: Fetch issue (lightweight — stays in main agent)
│
├── Spawn: Codebase Researcher subagent (Steps 2-5)
│   Extracts keywords, scans codebase, traces deps, reads git history,
│   cross-references issues/PRs
│   Returns: structured findings JSON
│
├── Main agent: Reviews findings, displays progress for Steps 2-5
│
├── Spawn: Synthesizer subagent (Steps 6-7)
│   Analyzes root cause/architecture, proposes implementation options
│   Returns: analysis text + options
│
└── Main agent: Step 8 (Output) and Persist
```

Read `shared/agents/codebase-researcher.md` for the full explorer prompt.
Read `shared/agents/synthesizer.md` for the full synthesizer prompt.

### Environment check

If the Agent tool is available, use subagents as described above.
If not (e.g., Claude.ai), execute each phase inline instead:
- Steps 2-5: Read files and scan directly in the main conversation
- Steps 6-7: Perform analysis inline
- Step 8: Output as normal

### Bundled dependency precheck

Verify that this skill's bundled subagent prompts and reference files are present.
If any are missing, stop immediately and print:

```
✗ Missing bundled dependency: {missing_file}

  To fix:  asm install https://github.com/luongnv89/idd --skill issue-analysis
           (or reinstall the full distribution)

  Then restart the agent session and re-run /issue-analysis.
```

Check these files relative to the skill's directory (the dirname of this SKILL.md):

- `references/agents/codebase-researcher.md` — Codebase Researcher subagent prompt (Steps 2-5)
- `references/agents/synthesizer.md` — Synthesizer subagent prompt (Steps 6-7)
- `references/subagent-steps.md` — per-step prompts and tool budgets for subagents
- `references/output-and-persist.md` — terminal report rendering spec and JSON schema
- `references/docs/sync-conventions.md` — stash-first sync convention and recovery
- `references/docs/idd-methodology.md` — IDD methodology (durable analysis fields)
- `references/docs/config-schema.md` — configuration schema reference

The steps below include both the subagent delegation path and the inline fallback.

---

## Pipeline Overview

The analysis pipeline has 8 steps plus a persist step. Display progress using the `[N/8]` step counter:

```
  ◆ Analysis Pipeline
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  [1/8] Fetch          ✓ issue #42 loaded (bug)
  [2/8] Extract        ✓ 8 keywords, 2 file refs
  [3/8] Research       ● reading 18 files...
  [4/8] History        ✓ 5 related commits, 1 prior fix attempt
  [5/8] Cross-refs     ✓ 2 related issues, 1 may resolve this
```

Each step prints a new line when it starts (with `●`) and updates to `✓` on success or `✗` on failure. Static sequential output — no animation.

---

## Step 1 — Fetch

```
● Fetching issue #N...
```

```bash
gh issue view {N} --json number,title,body,labels,assignees,state,comments,createdAt,updatedAt,author
```

**If not found:**
```
✗ Issue #N not found

  To fix:  gh issue list
  Check:   is this the right repository?
```
Stop.

**If closed:**
```
⚠ Issue #N is closed. Analyzing anyway for reference.
```
Unlike issue-resolver, analysis does NOT stop on closed issues — analyzing a closed issue is a valid use case (understanding what was done, reviewing approach). Print the warning and continue.

**No guards:** Analysis is read-only and non-destructive. No assignment guard or blocking label guard is needed — there is no risk of duplicating work or violating blocks.

### Classify type

From the issue title, body, and labels, determine the issue type: `bug`, `feature`, or `improvement`. Use these heuristics:

- Labels containing `bug`, `defect`, `error` → bug
- Labels containing `feature`, `enhancement`, `request` → feature
- Labels containing `improvement`, `refactor`, `tech-debt` → improvement
- If no label match, infer from title/body keywords: "fix", "broken", "error", "crash" → bug; "add", "new", "support" → feature; "improve", "refactor", "optimize", "update" → improvement
- Default to `improvement` if ambiguous

After fetch:
```
[1/8] Fetch          ✓ issue #N loaded ({type})
```

---

## Steps 2-7 — Explorer & Synthesizer

Steps 2-5 run inside the Codebase Researcher subagent (Explorer phase); Steps 6-7 run inside the Synthesizer subagent. Full per-step prompts, expected outputs, and tool budgets live in `references/subagent-steps.md` — read that file when tuning either subagent.

Quick summary:
- **Step 2** — extract keywords & file refs from the issue.
- **Step 3** — codebase scan (grep/glob, read up to 20 files).
- **Step 4** — git history scan (related commits, prior fix attempts).
- **Step 5** — cross-reference related issues & PRs.
- **Step 6** — root cause synthesis.
- **Step 7** — implementation options & complexity/risk scoring.

---
## Step 8-9 — Output & Persist

Step 8 renders the analysis as a structured terminal report following DESIGN.md conventions; Step 9 persists the same data to `.gitissue/analysis-<N>.json`. Full rendering spec (section layout, color codes, truncation rules) and JSON schema live in `references/output-and-persist.md` — read that file when implementing or debugging either step.

Summary:
- Terminal report has 8 sections: header, classification, root cause, affected files, options, complexity, risk, recommendation.
- JSON top-level keys: `version`, `timestamp`, `source`, `issue`, `extraction`, `affected_files`, `analysis`, `options`, `recommended_option`, `overall_complexity`, `overall_risk`, `history`, `cross_references`, `scan_stats`, `git_state`, `decision_record` — see `references/output-and-persist.md`.

### Durable analysis fields

`/issue-analysis` JSON is local cache — see *Analysis Artifacts and Durable Memory* in `docs/idd-methodology.md`. To make the analysis durable, two structured fields are persisted alongside the existing analysis content so `/issue-resolver` can lift them into the PR body:

1. **`git_state`** — the branch and commit SHA the analysis ran against. This pins the analysis to a specific point in time so reviewers can verify the current-code reality the recommendation was made against.
2. **`decision_record`** — five core fields lifted from Steps 6 and 7: `root_cause`, `options_considered`, `options_rejected`, `selected_option`, `residual_risk`. The labels are stable across `/issue-analysis`, `/issue-resolver`, and `/issue-pr-review` because the downstream presence checks are string-matched. Bug issues additionally carry an optional sixth `reproduction` field, but `/issue-analysis` does not populate it (it is produced post-fix by `/issue-resolver`'s bug-verification checkpoint) — see `references/output-and-persist.md`.

Persisting these fields does **not** change the analysis pipeline — it only adds two new keys to the JSON and a *Decision Record* section to the terminal report. See `references/output-and-persist.md` for the exact schema and rendering.

---

## Final Report

After all 8 steps and persistence complete, print a structured step-by-step summary so the user can see what happened at each stage:

```
◆ Issue Analysis: #{N} — {title}
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Fetch:             ✓ pass (issue loaded)
  Extract targets:   ✓ pass ({keywords_count} keywords, {file_refs_count} file refs)
  Research:          ✓ pass ({files_read} files scanned)
  Git history:       ✓ pass ({commits_count} related commits)
  Cross-references:  ✓ pass ({related_count} related issues)
  Root cause:        ✓ pass
  Options:           ✓ pass ({options_count} approaches proposed)
  Report:            ✓ pass
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            DONE

  Complexity: {XS|S|M|L|XL} │ Risk: {Low|Medium|High}
  Recommended: Option {N} — {name}
  Saved: .gitissue/analysis-N.json
```

If a step produced no results (e.g., no git history found), mark it with a note:

```
  Git history:       ○ skip (no related commits found)
```

If the issue may already be resolved:

```
◆ Issue Analysis: #{N} — {title}
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Fetch:             ✓ pass
  Extract targets:   ✓ pass
  Research:          ⚡ may already be fixed by {sha7}
  ...
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            DONE (verify if already resolved)
```

---

## Expected Output

A successful analysis prints the 8-step tracker and a condensed report, then persists the full result to `.gitissue/analysis-<N>.json`:

```
  ◆ Analysis Pipeline
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  [1/8] Fetch          ✓ issue #42 loaded (bug)
  [2/8] Extract        ✓ 8 keywords, 2 file refs
  [3/8] Research       ✓ read 18 files, traced 12 deps
  [4/8] History        ✓ 5 related commits, 1 prior fix attempt
  [5/8] Cross-refs     ✓ 2 related issues, 1 may resolve this
  [6/8] Analysis       ✓ root cause identified
  [7/8] Options        ✓ 3 approaches proposed
  [8/8] Persist        ✓ .gitissue/analysis-42.json

  Root cause:      {short summary}
  Affected files:  {count} files, {count} modules
  Complexity:      M (estimated)
  Risk:            medium (touches auth middleware)
  Recommendation:  {one-sentence next step}
```

View mode (`/issue-analysis N view`) reads the JSON and renders the same report without re-running the pipeline.

## Edge Cases

### Issue body is empty

If the issue has no body text:
```
⚠ Issue #N has no description. Analysis may be limited.

  Continue anyway? [y/N]
```
Default is No. If declined, stop. If accepted, proceed with title-only keywords — the analysis will note limited confidence.

### No relevant files found

If the codebase scan finds no matching files:
```
⚠ Could not find files relevant to issue #N

  The issue may reference components not in this codebase.
  Check:   are the keywords in the issue specific enough?
  Tip:     normalize the issue with /issue-creator N first
```
Stop. Analysis requires at least one relevant file.

### Re-analysis (existing JSON)

If `.gitissue/analysis-<N>.json` already exists when running a full analysis (not view mode), overwrite it silently. The new analysis replaces the old one entirely.

---

## Example Runs

Full example outputs (happy path, view mode, already-closed issue) are kept in `references/examples.md` so SKILL.md stays focused on pipeline mechanics.

---

---

## Platform Driver

All tracker access follows the GitHub driver — `--json` with explicit field selection, never parsed text output. The full operation catalog and driver rules live in docs/platform-github.md.

## Output Conventions

Terminal output follows the DESIGN.md contract — symbols `● ✓ ✗ ◆ ⚡ ⚠ ○`, two-space indent, `┄` separators, URLs on their own line, ≤80 chars, one blank line between sections, static sequential output (no animation), plus a `[N/8]` pipeline step counter and `│ ─ ┼` tables (right-align numbers, `—` for empty cells). Errors use the rich format from `references/error-messages.md`: `✗ what failed`, then `To fix:  <command>`, then a docs link when applicable.

## Additional Resources

- **`shared/agents/codebase-researcher.md`** — Codebase Researcher subagent prompt (Steps 2-5 delegation)
- **`shared/agents/synthesizer.md`** — Synthesizer subagent prompt (Steps 6-7 delegation)
- **`references/error-messages.md`** — Complete error catalog with triggers and exact output
- **`DESIGN.md`** — Terminal output style guide (repo root)
- **`docs/config-schema.md`** — Full configuration schema
