# Auto-Pilot Details

This file keeps the long-running operating notes out of `SKILL.md` so the skill body stays compact.

## Release Notes

### Changes in 2.1.0
- Review cycles reduced to 3.
- `/issue-pr-review` runs a script pre-pass for lint and format fixes before LLM review.
- `"fix"` vs `"note"` classification determines whether a cycle is consumed.
- Soft pass condition: zero `"fix"` issues remain.

### Breaking Changes in 2.0.0
- No default pause on failure; skipped issues continue through the loop.
- `auto_merge: false` no longer halts the loop.
- Confirmation prompts were removed from the autonomous path.

## Autonomy Rules

- Auto-decide ordinary work: branch changes, stashing, syncing, strategy choice, retries, and merges.
- Ask the user only for truly irreversible actions or unresolved critical issues.
- Prefer the safer option when in doubt so the loop keeps making progress.

## Context Window Management

The main agent stays lightweight and delegates code, diffs, and review work to subagents. That keeps later backlog iterations stable and avoids accumulating too much context in one session.
