# Skill Auto-Improver Report

**Target**: `skills/`
**Iterations**: 3

## Final Results

| Skill | Overall | Description | Prompt Eng. | Context Eff. | Testability |
|---|---:|---:|---:|---:|---:|
| `auto-pilot` | 94 | 8 | 10 | 9 | 10 |
| `init-gitissue` | 94 | 8 | 10 | 9 | 10 |
| `issue-analysis` | 94 | 8 | 10 | 9 | 10 |
| `issue-creator` | 99 | 10 | 10 | 9 | 10 |
| `issue-pr-review` | 97 | 10 | 10 | 9 | 10 |
| `issue-pr-review-fix-loop` | 97 | 10 | 10 | 9 | 10 |
| `issue-resolver` | 94 | 8 | 10 | 9 | 10 |
| `issue-triage` | 96 | 8 | 10 | 9 | 10 |

## Files Changed

- `skills/auto-pilot/SKILL.md`
- `skills/init-gitissue/SKILL.md`
- `skills/issue-analysis/SKILL.md`
- `skills/issue-creator/SKILL.md`
- `skills/issue-pr-review/SKILL.md`
- `skills/issue-pr-review-fix-loop/SKILL.md`
- `skills/issue-resolver/SKILL.md`
- `skills/issue-triage/SKILL.md`
- `skills/auto-pilot/references/auto-pilot-details.md`
- `skills/init-gitissue/references/init-runbook.md`
- `skills/issue-analysis/references/analysis-runbook.md`
- `skills/issue-creator/references/creator-runbook.md`
- `skills/issue-pr-review/references/review-runbook.md`
- `skills/issue-pr-review-fix-loop/references/fix-loop-runbook.md`
- `skills/issue-resolver/references/resolver-runbook.md`
- `skills/issue-triage/references/triage-runbook.md`

## Key Fixes

- Moved long, repetitive instructions into per-skill reference files to keep the main bodies compact.
- Restored prompt-engineering structure with explicit `When to Use`, `Instructions`, `Acceptance Criteria`, and `Edge Cases` sections.
- Added skill-specific expected-output examples to raise testability across the whole set.

## Result

PASS. All eight skills clear the 85/8 floor. The final batch scores are stable: prompt engineering is 10/10 across the board, context efficiency is 9/10, and testability is 10/10 after the example updates.
