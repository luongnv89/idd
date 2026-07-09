# Decisions Log

Append-only log of documentation ambiguities resolved with the user during doc-manager passes.

## 2026-07-09
- Q: `docs/CHANGELOG.md` diverged from the canonical root `CHANGELOG.md` (last real entry `[0.4.0] - 2026-03-24`; root is current through v0.18.0). Two live docs pointed readers at it (`docs/DEVELOPMENT.md:148`, `src/skills/auto-pilot/SKILL.source.md:14`). Archive-with-redirect, delete, or leave-and-flag?
- A (user): Delete `docs/CHANGELOG.md`. Repoint both references to root `CHANGELOG.md`.
- Source: `CHANGELOG.md` (root, canonical) vs deleted `docs/CHANGELOG.md`

- Q: `docs/release-notes/` only has 3 files (`v0.7.0-smoke-tests.md`, `v0.10.0.md`, `v0.10.1.md`), 8 releases behind current v0.18.0. Backfilling the missing reports would mean inventing content not present in git history. Note the gap, or leave and flag?
- A (user): Add a note that it is not maintained per-release; do not backfill.
- Source: `docs/release-notes/` (dir listing), root `CHANGELOG.md` (canonical version history)

- Q: `src/skills/auto-pilot/SKILL.source.md:14` pointed to the (now-deleted) `docs/CHANGELOG.md` and implied `docs/release-notes/` was a complete version history. Editing an authored skill source desyncs the committed `skills/` build output verified by CI's `dist-check.yml` unless rebuilt. Edit + rebuild, or skip source/skills and only fix top-level docs?
- A (user): Edit the source and run `scripts/build.sh` to keep `skills/auto-pilot/SKILL.md` in sync.
- Source: `src/skills/auto-pilot/SKILL.source.md:14`, `.github/workflows/dist-check.yml`
