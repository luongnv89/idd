# Plugin Schema Provenance

`scripts/plugin-schema.json` is a **best-effort** validator for
`dist/plugin/.claude-plugin/plugin.json`. It is used as a fallback when
`claude plugin validate` is unavailable (per refactor-plan-v10.md §4 Phase E).

## Source

Derived from public Claude Code plugin documentation at:

  https://docs.claude.com/en/docs/claude-code/plugins

Captured: 2026-04-28.

## Required fields

The schema currently requires `name`, `slug`, and `version` — the minimum any
plugin manifest must declare. `skills` is described as an array of
`{name, source}` entries but only `name` is required per skill. All other
top-level fields are permitted (`additionalProperties: true`) so the schema
does not block legitimate plugin extensions added upstream.

## Authoritative validator

When available, `claude plugin validate <plugin.json>` overrides this local
schema. The build script (`scripts/build.py`) checks for the CLI first and
only falls back to this schema when the CLI is missing.

## Re-validation cadence

Quarterly review: re-fetch the public Claude Code plugin docs and update
`x-derivedAt` plus the inline `$comment` if the upstream contract changes
(new required fields, renamed fields, stricter slug pattern, etc.). This is
a non-goal-cadence task per plan §13.
