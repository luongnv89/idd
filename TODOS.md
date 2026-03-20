# TODOS — gitissue / IDD

Generated from /plan-ceo-review on 2026-03-20.
Updated from /plan-eng-review on 2026-03-20.
Updated from /plan-design-review on 2026-03-20.

## P1

### Resolve test timeout config
- **What:** Add `resolve.test_timeout` to `.gitissue.yml` schema (default: 300s). During verify phase, abort and report if tests don't complete within timeout.
- **Why:** Tests can hang indefinitely (infinite loops, network waits), leaving the resolve pipeline stuck with no feedback. A timeout converts a silent failure into a visible one.
- **Effort:** S (human: ~4 hours / CC: ~10 min)
- **Depends on:** F4 (issue-resolver) implementation
- **Context:** Add to config schema: `resolve.test_timeout: 300`. Skill instructs agent to use Bash timeout parameter.

### Use `gh --json` everywhere (convention)
- **What:** Every `gh` CLI call should use `--json` with explicit field selection instead of text output
- **Why:** Text output is fragile across gh versions. JSON is stable, parseable, and self-documenting. Also avoids N+1 in triage (get bodies in list call).
- **Effort:** S (convention, not extra work)
- **Depends on:** None — follow during implementation
- **Context:** Example: `gh issue view 42 --json number,title,body,labels,assignees,state` instead of `gh issue view 42`.

### Scripted test suite (`test.sh`)
- **What:** Shell scripts that create a test repo, run each gitissue command, verify output
- **Why:** Skills-only tools have no unit tests — scripted integration tests are the only regression safety net
- **Effort:** S (human: ~2 days / CC: ~30 min)
- **Depends on:** F1, F4 implemented
- **Context:** Create a `tests/` directory with shell scripts. Test repo should exercise: single issue creation, normalization (with backup verification), resolve pipeline, triage output. Verify template rendering on GitHub.

## P2

### Predicted-vs-actual file tracking
- **What:** Record predicted affected files in an HTML comment marker during normalization (`<!-- gitissue:predicted_files: a.py, b.py -->`). After resolution, compare against PR's actual changed files.
- **Why:** F13 (issue intelligence / feedback loop) depends on this data. Without it, the feedback loop has nothing to learn from.
- **Effort:** S (human: ~1 day / CC: ~15 min)
- **Depends on:** F2 implemented
- **Context:** Plant the data seed early so it accumulates passively. Comparison logic can be built in Phase 5.

### GitHub-rendered issue template mockup
- **What:** Create a sample normalized issue markdown file showing how it renders in GitHub's web UI — with section headers, Reporter Context blockquote, confidence markers, affected files list
- **Why:** Terminal output is well-specified in DESIGN.md. But the other output surface — how normalized issues appear in the GitHub browser — has no visual reference. A mockup ensures templates look intentional.
- **Effort:** S (human: ~2 hours / CC: ~15 min)
- **Depends on:** F3 (templates) design
- **Context:** Write a `docs/sample-normalized-issue.md` showing a fully normalized bug report. Use as a reference during template implementation.

### Security issue detection — skip normalization
- **What:** Detect security-tagged issues (labels: 'security', 'CVE', 'vulnerability') and skip normalization to avoid leaking exploit details into enriched fields
- **Why:** Normalization adds codebase context — for a security vulnerability, that context could reveal exactly how to exploit it
- **Effort:** S (human: ~4 hours / CC: ~10 min)
- **Depends on:** F2 implemented
- **Context:** Check issue labels before normalization. If security-related, warn user and skip unless explicitly overridden with `--force`.
