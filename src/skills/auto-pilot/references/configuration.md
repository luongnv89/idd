# Configuration defaults — full rationale

`/auto-pilot` reads `.gitissue.yml` once at start (never re-read per iteration).
The canonical schema lives in `docs/config-schema.md`; this file expands the
per-key rationale behind each `autopilot.*` default. The SKILL.md body carries
the bare default values — read this when you need the *why* or the edge-case
behavior.

- `autopilot.mode: balanced` — merge mode. See **Merge Modes** in SKILL.md for the three values.
- `autopilot.merge_partial: false` — never merge a PR with unresolved fixable review issues unless explicitly opted in. Only honored when `mode: aggressive`.
- `autopilot.max_iterations: 10` — maximum issues to process before stopping.
- `autopilot.review_cycles: 3` — maximum fix attempts per PR. After this many cycles, if issues remain the behavior depends on `autopilot.mode` (see *Merge Modes*). Reduced from 10 — the script pre-pass in issue-pr-review handles lint/format, so 3 LLM cycles suffice for logic issues. A cycle = one fix attempt + one review pass. Confirmation-only review passes (spawned after a PASS to verify, without a preceding fix) do not consume a cycle.
- `autopilot.auto_merge: true` — **legacy** field, retained for backwards compatibility. When `autopilot.mode` is set, `mode` wins and this field is ignored. When `mode` is unset and `auto_merge` is not explicitly present in the file, effective mode is `balanced`. When `mode` is unset but `auto_merge` is explicitly present, legacy mapping applies (`true` → aggressive+merge_partial; `false` → conservative).
- `autopilot.pause_on_failure: false` — skip failed issues and continue to the next one (autonomous default). When false, the auto-pilot logs the failure, adds the issue to the skip list, and moves on. Set to true only if you want the loop to halt on every failure for manual inspection.
- `autopilot.skip_labels: ["wontfix", "blocked", "do-not-merge"]` — skip issues with these labels.
- `autopilot.critical_labels: ["critical", "priority:critical"]` — labels that mark an issue as critical. When a critical issue has unresolved review problems after all cycles, the loop stops and asks the user for a decision instead of auto-creating a follow-up.
- `autopilot.respect_dependencies: true` — honor `Depends on #N` / `Blocked by #N` markers in issue bodies. Before merging PR-A, verify that every dependency referenced from issue A is closed and its PR merged; if not, do not merge — print a structured alert, record `blocked_by_dependency`, leave PR-A open, and continue to the next eligible issue (the run is not paused). Set to `false` to skip the gate entirely. See *Phase 5 — Merge* in `references/phases.md` for the full check.
- All `resolve.*` and `triage.*` settings are inherited by the sub-skills.
