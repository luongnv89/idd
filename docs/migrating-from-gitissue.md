# Migrating from the gitissue names to idd

Issue #537 renamed every `gitissue` identifier to `idd`. Repositories set up
before the rename keep working: each reader falls back to the legacy name and
prints a `⚠` line that tells you to rename. This page lists what changed, what
keeps working, and how to move over.

This is a project doc for people. No skill reads it at run time.

## What was renamed

| Legacy name | New name |
|-------------|----------|
| `.gitissue.yml` | `.idd.yml` |
| `.gitissue/` (run log, triage, analysis, run state, cache) | `.idd/` |
| `.gitissue-recipe.json` | `.idd-recipe.json` |
| `.gitissue-borrowed` (borrowed-skill marker file) | `.idd-borrowed` |
| `/init-gitissue` | `/init-idd` |
| `<!-- gitissue:… -->` markers (`normalized`, `qa`, `run-report`) | `<!-- idd:… -->` |
| `~/.cache/gitissue/` (model-suggestion cache) | `~/.cache/idd/` (`IDD_CACHE_DIR` still overrides it) |

## What keeps working without changes

- **Config.** With no `.idd.yml`, the legacy `.gitissue.yml` is read in its
  place and a `⚠ legacy .gitissue.yml found — rename to .idd.yml` line is
  printed. When both files exist, `.idd.yml` wins and the warning still prints.
- **Trusted policy and recipe on the base branch.** The pre-commit scan's
  `--policy-ref` reads `<ref>:.idd.yml` and falls back to `<ref>:.gitissue.yml`
  only when the new file is absent at that ref. The verification recipe does
  the same with `.idd-recipe.json` and `.gitissue-recipe.json`.
- **Borrowed-skill teardown** accepts either marker file and still refuses to
  delete a directory that carries neither.
- **Markers.** New issues and PRs get `idd:` markers. Markers already on
  existing issues and PRs are still read, and both namespaces count together.
  A PR body with one `gitissue:qa` and one `idd:qa` marker carries two
  markers, so its QA handoff reads as stale.
- **Run state.** When `.idd/` holds no run state, `gi-state.py` moves a legacy
  `.gitissue/run.lock`, `run-state.json` and `last-run-report.md` into `.idd/`
  once and prints one `⚠ migrated` line per file. A legacy lock whose owner is
  still running blocks the new run, and nothing is moved.

## Upgrade every client first

Upgrade every client before you rename the files. That means every plugin or
`asm` install, every teammate's machine, and every CI job that runs the skills.
An old client reads only `.gitissue.yml`, so after the rename it falls back to
default settings. If it runs the pre-commit scan, it also loses your
`security:` rules.

If you can't upgrade every client at once, keep both files for one release.
Both-present is supported and the new name wins.

**Shadowing.** Adding `.idd.yml` next to `.gitissue.yml` replaces the legacy
file entirely, `security:` block included. Nothing is merged across the two
files. Copy every key you rely on before you add the new file.

## Steps

1. **Upgrade the skills** so that `init-idd` replaces `init-gitissue`:
   - Plugin: `claude plugin marketplace update idd`, then
     `claude plugin update idd@idd`. The update replaces the whole skill set,
     so `init-gitissue` goes away on its own.
   - `asm`: `asm install https://github.com/luongnv89/idd`, then
     `asm uninstall init-gitissue`. Reinstalling adds `init-idd` but leaves
     the old skill in place.
   - `npx skills` or a manual copy: install `init-idd` the same way, then
     delete the old `init-gitissue` folder from your skills directory.
2. **Rename the config:** `git mv .gitissue.yml .idd.yml`. Alternatively,
   run `/init-idd`. It treats a legacy-only `.gitissue.yml` as the existing
   config, and **merge** writes `.idd.yml` with every key kept. Then run
   `git rm .gitissue.yml`.
3. **Rename the recipe**, if you have one:
   `git mv .gitissue-recipe.json .idd-recipe.json`.
4. **Mirror your ignore lines.** For every `.gitissue/<x>` line in
   `.gitignore`, add `.idd/<x>`. Re-running `/init-idd` does this for you and
   also adds `.idd/cache/`. It never adds a line twice.
5. **Clear out `.gitissue/`.** Its files are machine-local. Only `runs.jsonl`
   (the run log) and `run-state.json` (an unfinished auto-pilot run) are worth
   moving into `.idd/`. Everything else is regenerated, and `gi-state.py`
   migrates run state for you. Delete the rest.
6. **Delete `~/.cache/gitissue/`.** The model-suggestion cache rebuilds under
   `~/.cache/idd/`.

Once every client is upgraded, you can remove the legacy `.gitissue/` lines
from `.gitignore`.
