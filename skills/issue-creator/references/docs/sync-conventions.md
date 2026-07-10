<!-- Generated from /docs/sync-conventions.md. Do not edit. Edit source and run ./scripts/build.sh. -->
# Sync Conventions

Standard convention for syncing a working branch with the remote before any IDD skill modifies files. Centralizing this here ensures every skill that performs a `git pull --rebase` first protects uncommitted changes — the unsafe pattern (bare rebase on a dirty tree) can silently destroy staged or unstaged work, so it must never appear in skill instructions.

## Why This Matters

`git pull --rebase` rewrites local history. When the working tree has uncommitted changes that overlap with incoming commits, rebase either fails outright or — worse — leaves the tree in a confusing intermediate state where the user's work appears lost. The fix is mechanical: stash before, pop after. This document is the canonical reference; skills should link here rather than copy-pasting the snippet, so the convention can be updated in one place.

---

## Primary Pattern: Stash-First Sync

This is the **only** documented sync path. Every skill that runs `git pull --rebase` MUST follow it.

```bash
branch="$(git rev-parse --abbrev-ref HEAD)"

# Protect any uncommitted changes (staged + unstaged + untracked).
# The descriptive message lets the user identify the stash later.
dirty=0
if [ -n "$(git status --porcelain)" ]; then
  git stash push -u -m "pre-sync: ${branch} $(date +%Y-%m-%dT%H:%M:%S)"
  dirty=1
fi

# Sync with remote.
git fetch origin
git pull --rebase origin "$branch"

# Restore uncommitted changes.
if [ "$dirty" -eq 1 ]; then
  git stash pop || {
    echo "✗ Stash pop failed — your changes are still safe in the stash"
    echo "  Recovery:"
    echo "    git stash list                       # find the stash ref (e.g. stash@{0})"
    echo "    git stash show -p stash@{0}          # preview what's in it"
    echo "    git checkout stash@{0} -- <path>     # restore individual files"
    echo "    git stash pop --index stash@{0}      # retry pop after resolving conflicts"
    exit 1
  }
fi
```

### Behavior Notes

- **`git status --porcelain`** is the canonical dirty-tree check — empty output means clean, any output means dirty (modified, staged, or untracked).
- **`git stash push -u`** includes untracked files (`-u` = `--include-untracked`). Without `-u`, new files are left exposed and can collide with the rebase.
- **The stash message** must be descriptive (branch name + timestamp) so the user can identify it via `git stash list`. Generic messages like `"pre-sync"` make recovery harder when multiple stashes accumulate.
- **`git stash pop`** can fail with merge conflicts. When it does, the stash is preserved on the stash stack — the user's changes are not lost. The recovery output above tells the user exactly how to access them.
- **Stash ref stability:** newly pushed stashes always become `stash@{0}`. The recovery instructions assume this; if a script creates additional stashes between push and pop, capture the ref returned by `git stash push` instead.

---

## When the Sync Fails

| Failure | Cause | Recovery |
|---------|-------|----------|
| `fatal: 'origin' does not appear to be a git repository` | No remote configured | Stop and ask the user to add a remote: `git remote add origin <url>`. In auto mode, abort with a clear error. |
| `error: Could not apply <commit>` (rebase conflict) | Local commits conflict with incoming | Stop. In interactive mode, ask the user to resolve. In auto mode, run `git rebase --abort` and report. |
| `error: Your local changes to the following files would be overwritten by merge` | Stash-first was skipped (do not let this reach the user) | Indicates a skill bypassed the convention. Report the skill bug. |
| `CONFLICT (content): Merge conflict in <file>` (during stash pop) | Rebased commits touch the same lines as the stash | Use the recovery output above. Stash is preserved on the stack. |

---

## Skill-Side Responsibilities

Every IDD skill that performs a sync step MUST:

1. **Use the stash-first block above** — never document a bare `git pull --rebase` as the primary path.
2. **Link to this document** — write `(see the sync conventions reference)` next to the snippet so users find this reference.
3. **Document the recovery** — at minimum, instruct on `git stash list` and `git stash show -p stash@{0}` if a pop conflict occurs. Skills are free to inline the full recovery block from this document.
4. **Honor the mode contract** — in interactive mode, prompt the user before stashing or aborting on conflict. In auto mode (`--auto`), perform the stash-first sync without prompting; abort cleanly with a recovery hint if it fails.

---

## Lint Enforcement

`tests/test-sync-safety.sh` recursively scans every Markdown file under `src/skills/` (both `SKILL.source.md` files and everything under each skill's `references/`). It walks the **fenced code blocks** (```` ``` ````-delimited, e.g. ```` ```bash ````/```` ```sh ````) and checks each one: if a fenced block contains `git pull --rebase`, that **same fenced block** must also contain a preceding `git stash` invocation. There is no line-distance window and no comment escape hatch — the guard is purely per-block. Inline mentions in single backticks and ordinary prose are ignored, because only fenced code blocks are what the skill actually instructs the agent to execute. Failing the lint blocks merges. This is the regression guard — without it, future skill edits could silently reintroduce the unsafe form.

---

## Quick Reference (Copy-Paste Snippet)

For skills that want the minimal form inline:

```bash
# Stash-first sync — see the sync conventions reference for full recovery procedure.
branch="$(git rev-parse --abbrev-ref HEAD)"
dirty=0
if [ -n "$(git status --porcelain)" ]; then
  git stash push -u -m "pre-sync: ${branch}"
  dirty=1
fi
git fetch origin
git pull --rebase origin "$branch"
if [ "$dirty" -eq 1 ]; then
  git stash pop || {
    echo "✗ Stash pop failed — recover with: git stash list && git stash show -p stash@{0}"
    exit 1
  }
fi
```
