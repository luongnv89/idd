# ADR — Documentation Canon and Release-Note Policy

**Status:** Accepted (2026-07-09).

## Context

A documentation review found three related ambiguities:

- `docs/CHANGELOG.md` had stopped at v0.4.0 while the canonical root
  `CHANGELOG.md` was current through v0.18.0. Two live documents still linked to
  the stale copy: `docs/DEVELOPMENT.md` and
  `src/skills/auto-pilot/SKILL.source.md`.
- `docs/release-notes/` contained only v0.7.0, v0.10.0, and v0.10.1 notes. It
  was eight releases behind the canonical changelog, and the missing narrative
  was not available in git history without inventing content.
- Updating an authored skill source without rebuilding would desynchronize the
  committed `skills/` output checked by `.github/workflows/dist-check.yml`.

## Decision

1. The root `CHANGELOG.md` is the only canonical version history. Delete the
   stale `docs/CHANGELOG.md` fork and point live references to the root file.
2. `docs/release-notes/` is a curated collection, not a per-release ledger. Do
   not backfill missing release notes when the source material does not exist.
3. When a documentation correction touches an authored skill source, rebuild
   the generated skills with `scripts/build.sh` in the same change.

## Consequences

- Readers have one authoritative changelog instead of two drifting histories.
- A sparse release-notes directory is expected and does not imply missing
  releases; the root changelog remains complete.
- Documentation fixes preserve source/generated parity and continue to satisfy
  the distribution check.

## Source Record

These decisions preserve the answers supplied during the 2026-07-09
`/doc-manager` pass. The compared sources were the root `CHANGELOG.md`, the
removed `docs/CHANGELOG.md`, the `docs/release-notes/` directory,
`docs/DEVELOPMENT.md`, `src/skills/auto-pilot/SKILL.source.md`, and
`.github/workflows/dist-check.yml`.
