# /auto-pilot — Phase Details

Full step-by-step specification of each loop phase. SKILL.md contains the
overview; this file is the index, and each phase's full per-step guidance lives
in its own file under `references/phases/` so an iteration reads only the phase
it is in — never the whole loop (issue #323). Read the phase file when
implementing or debugging that phase.

## Phase files

| Phase | File | Steps inside | Read when |
|-------|------|--------------|-----------|
| 0 — Run lock, resume entry, and checkpoints | `references/phases/phase-0-lock-resume.md` | 1.0, 1.0b, checkpoints, *Runtime budget check* | Once, before the loop |
| 1 — Triage and Pick | `references/phases/phase-1-triage-pick.md` | 1.1a, 1.1, 1.1b, 1.2, 1.2b, 1.3 | Top of each iteration |
| 2 — Resolve (subagent) | `references/phases/phase-2-resolve.md` | 2.x | Before spawning a resolver lane |
| 3 & 4 — PR Review (via /issue-pr-review) | `references/phases/phase-3-4-review.md` | 3.x, 4.x | Before spawning the reviewer |
| 5 — Merge | `references/phases/phase-5-merge.md` | 5.x incl. 5.1b, *End-of-iteration checkpoint* | Before the merge gate |

A pointer of the form `references/phases.md` (*Step N.n*) or (*Phase N*) resolves
through this table: the step number's leading digit names the phase file.

---
