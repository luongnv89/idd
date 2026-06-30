# Confidence Scoring System

Auto-enriched fields include a confidence level. Confidence is displayed in previews and written into the issue body.

## Levels

| Level | Criteria | Preview display | Issue body display |
|-------|----------|-----------------|-------------------|
| **high** | Explicit keywords match clearly (e.g., crash/error → bug, "add new" → feature) or requirements stated directly | `(high)` | `(high confidence)` |
| **medium** | Inferred from description context or tone | `(medium)` | `(medium confidence)` |
| **low** | Ambiguous, defaulted based on common patterns | `(needs review)` | `(needs review)` |

## Fields with Confidence

| Field | How confidence is determined |
|-------|------------------------------|
| **Type classification** | high = explicit error/crash keywords (bug) or "add"/"new" (feature); medium = inferred from description tone; low = ambiguous, defaulted |
| **Acceptance criteria** | high = directly derived from explicit requirements in description; medium = inferred from problem description; low = generic criteria from template |
