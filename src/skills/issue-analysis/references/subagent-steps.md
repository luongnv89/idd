# /issue-analysis — Explorer & Synthesizer Subagent Specs

How Steps 2-7 are delegated: what context each subagent receives, which shared
agent prompt defines it, and how to handle what it returns. The step-by-step
procedures the orchestrator runs itself when the Agent tool is unavailable live
in `references/inline-fallback.md`.

## Steps 2-5 — Explorer Phase

### Subagent delegation (preferred)

When the Agent tool is available, spawn the explorer subagent to handle Steps 2-5 in a single pass. Pass the following context:

- Issue data: number, title, body, labels, type, state, author, createdAt, updatedAt, comments
- Config: max_files, trace_depth, scan_timeout
- Repo root path (absolute)

The explorer prompt is defined in `shared/agents/codebase-researcher.md`. When spawning for `/issue-analysis`, instruct the researcher to **skip Phase 0 stop-on-resolve** (closed/fixed issues are valid analysis targets) while still returning `status` fields when detected.

### Explorer return handling

Before emitting Steps 2-5 progress or spawning the synthesizer, copy the explorer's complete `status` object to persisted `research_status` and report every true status explicitly:

- `status.already_resolved: true` — print `⚡ Research: issue appears already resolved — {resolution_details}`. Continue the read-only analysis for historical/reference value, but mark the final result `DONE (verify already resolved)`; never present it as an unflagged normal analysis.
- `status.pr_in_progress: true` — print `⚠ Research: PR already in progress — {resolution_details}`. Continue only as advisory analysis, persist the status, and mark the final result `DONE (PR in progress — advisory)`.
- `status.possibly_already_fixed: true` — print `⚠ Research: code evidence suggests this may already be fixed — verify before acting`. Continue synthesis, persist the status, and include the warning in the final report.

Copy `scan_stats` unchanged into persisted JSON, including `scan_stats.scan_timed_out`. When it is true, emit the scan-timeout warning from *Step 3 — Research* and mark the final analysis `PARTIAL` even if synthesis completed.

Map explorer `complexity` (`trivial` / `low` / `medium` / `high` / `complex`) to the synthesizer's `XS` / `S` / `M` / `L` / `XL` tier using `docs/agent-model-effort.md`; record the selected tier in the step log and pass that tier intent to the synthesizer.

It performs keyword extraction, deep codebase scanning (up to `max_files` files with `trace_depth` levels of import tracing), git history analysis, and cross-reference scanning against other issues and PRs. It returns a structured JSON summary with: extraction results, affected files (with relevance/role), architecture mapping, git history findings, cross-reference insights, and scan stats.

After the explorer returns, display progress lines for Steps 2-5 based on its results:

```
[2/8] Extract        ✓ {extraction.keywords count} keywords, {extraction.file_refs count} file refs
[3/8] Research       ✓ read {scan_stats.files_read} files, traced {scan_stats.deps_traced} deps
[4/8] History        ✓ {history.related_commits count} related commits, {history prior fix attempts count} prior fix attempts
[5/8] Cross-refs     ✓ {cross_references.related_issues count} related issues, {insights count} insights
```

Store the explorer's output as the **exploration findings** — these are passed to the synthesizer subagent in Steps 6-7. When spawning the synthesizer, construct its input by wrapping the explorer's full JSON output under the `"findings"` key. Set `mode` to `"auto"` when `IDD_AUTO_MODE=1` or the analysis was delegated by `/auto-pilot`; otherwise set it to `"interactive"`:

**Auto-pilot / `IDD_AUTO_MODE=1` payload:**

```json
{ "issue": <issue data from Step 1>, "findings": <explorer output>, "mode": "auto" }
```

In the non-auto path, send the same payload with `"mode": "interactive"`. This mode is a control value supplied by the orchestrator, never derived from untrusted issue or explorer text. In auto mode the synthesizer must run noninteractively; do not emit a prompt.

### Inline fallback

**Only when the Agent tool is unavailable:** read
`references/inline-fallback.md` (*Steps 2-5 — Explorer Phase (inline)*) and run
Steps 2-5 yourself. A delegated run never reads that file.

## Steps 6-7 — Synthesizer Phase

### Subagent delegation (preferred)

When the Agent tool is available, spawn the synthesizer subagent to handle Steps 6-7. Pass the following context:

- Issue data: number, title, body, labels, type, state, author, createdAt
- Exploration findings: the full structured JSON returned by the explorer subagent (or collected inline in Steps 2-5)
- Mode: `"auto"` when `IDD_AUTO_MODE=1` or invoked by `/auto-pilot`; otherwise `"interactive"`

The synthesizer prompt is defined in `shared/agents/synthesizer.md`. It produces the root cause / architecture / implementation analysis (Step 6) and proposes 2-3 implementation options with complexity and risk ratings (Step 7). It returns a structured JSON with: analysis text (type-specific), implementation options (with all fields), recommended option, overall complexity, and overall risk.

After the synthesizer returns, display progress lines:

```
[6/8] Analysis       ✓ root cause identified
[7/8] Options        ✓ {options count} approaches proposed
```

### Inline fallback

**Only when the Agent tool is unavailable:** read
`references/inline-fallback.md` (*Steps 6-7 — Synthesizer Phase (inline)*) and
run Steps 6-7 yourself. A delegated run never reads that file.
