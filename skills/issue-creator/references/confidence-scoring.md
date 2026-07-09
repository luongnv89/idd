# Confidence Scoring System

Auto-enriched fields include a confidence level. Confidence is displayed in previews and written into the issue body. Per SPEC §1.3, tools that infer a value MUST append the marker; an unmarked field is asserted by its human author.

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
| **Metadata — Priority** | high = reporter stated urgency or blocking impact; medium = inferred from type/severity; low = defaulted band (e.g. P2) |
| **Metadata — Effort** | high = scope explicit in description; medium = inferred from described change size; low = defaulted XS/S/M/L/XL from template |
| **Metadata — Labels** | high = labels explicitly named by reporter; medium = inferred from keywords/paths; low = generic type-based defaults |
