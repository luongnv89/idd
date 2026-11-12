# Auto Mode — non-interactive execution contract

Authoritative definition of **auto mode**: how a run is detected as
non-interactive, and what a skill MUST do when it reaches a gate that would
otherwise wait for a human.

Skills reference this document instead of restating the rule at each gate. For
any skill that cites it, this document wins where a gate's wording disagrees.
Skills that predate it use the same `--auto` / `IDD_AUTO_MODE=1` signals — this
document names the existing convention, it does not introduce a new one.

## Detection

A run is in **auto mode** when **either** of these holds:

- the skill was invoked with the `--auto` flag, **or**
- `IDD_AUTO_MODE=1` is set in the environment.

Otherwise the run is **interactive**.

**Never rely on caller provenance alone.** Both signals above are explicit and
checkable; "who invoked me" is not. A skill MUST NOT conclude it is interactive
merely because it cannot detect `/auto-pilot`, and MUST NOT conclude it is
autonomous merely because it lacks a TTY. A skill MAY treat known-autonomous
provenance as an *additional* way to enter auto mode — several already do — but
the flag and the environment variable are the contract, and either one alone is
sufficient.

The obligation is therefore on the **caller**: any orchestrator that runs a skill
autonomously MUST pass `--auto` **and** export `IDD_AUTO_MODE=1` before the
invocation. Passing only one is a caller bug — skills honor either signal
precisely so a partially-configured caller still cannot deadlock.

```bash
export IDD_AUTO_MODE=1
```

This is the same contract the pre-commit security scan already relies on (its
[*Mode Contract*](https://github.com/luongnv89/idd/blob/main/docs/pre-commit-security.md))
and the same one the
[stash-first repo sync](https://github.com/luongnv89/idd/blob/main/docs/sync-conventions.md)
uses.

## The gate rule

An **interactive gate** is any point where a skill prints a prompt and waits —
`[Y/n]`, `[y/N]`, `[A]ll / [e]dit / [c]ancel`, `Choose:`, `Continue?`.

| Mode | Behavior at a gate |
|------|--------------------|
| Interactive | Unchanged — print the prompt, wait for the answer, honor it |
| Auto | **Never block.** Log one `⚠` line, take the gate's **printed default** (or a narrower answer it documents), continue |

A `[y/N]` gate takes **No**: the guarded action is not taken, and a run it ends
records a `skipped_reason`. Each gate documents its auto behavior; one wider than
its default MUST be a row of the [exception table](#exception-table).

A skill with no unguarded gate is the goal: **no `[y/N]` prompts, no `Choose:`
prompts, no `Continue?` prompts — every decision point has a defined auto
behavior.**

## Warning line format

One `⚠` line per gate that was auto-resolved, two-space indented, naming both
what was skipped and the default taken (see the
[terminal style contract](https://github.com/luongnv89/idd/blob/main/docs/terminal-style.md)):

```
  ⚠ Auto mode: {gate that was skipped} — {default taken}.
```

The line is not optional. An auto run that silently takes a default is
indistinguishable from an interactive run where the user approved it, which
destroys the audit trail the log is for.

## What auto mode does NOT change

Auto mode removes **confirmation** prompts. It never removes **safety** stops.

These still abort the run in auto mode, exactly as in interactive mode:

- **Data-safety preconditions** — e.g. a failed backup before a destructive edit.
  Auto-approving the *decision* to proceed never authorizes skipping the backup
  that makes it recoverable.
- **Real-secret detection** in the pre-commit security scan — always blocks,
  regardless of mode.
- **Missing prerequisites** — no repo, no `gh`, not authenticated, no remote —
  **for the operations that require them.** A prerequisite the skill only
  *recommends* is not a safety stop. Abort where the step is **mandatory** —
  it precedes a write, so proceeding unsynced or unauthenticated would corrupt
  something. Degrade to a `⚠` and continue where the step is documented as
  **optional or recommended** (e.g. a pre-read repo sync that only improves
  accuracy), exactly as the interactive decline path does.
- **Hard preflight failures** — issue not found, issue closed, rate budget
  exhausted.

Auto mode also never *widens* scope: it takes the default the interactive prompt
already offered, never a more destructive option. It **never closes an issue**
(only a merged PR's `Closes #N` does): on closing evidence it comments once and
records `already_resolved`; dependents stay blocked until a person closes it.

## Exception table

The only auto behaviors wider than the printed default:

| Id | Gate | Auto | Why |
|----|------|------|-----|
| `secscan-warnings` | Pre-commit scan warnings | Proceed | Hygiene signals, not leaks; a real secret still blocks |
| `analysis-empty-body` | `/issue-analysis` empty body | Title-only analysis | Read-only, local file; the resolver's own gate takes No |
| `already-resolved-comment` | Resolver already-resolved exit | Comment, never close | No one reads an unattended terminal |

Every `[y/N]` prompt is followed, before the next prompt or heading, by
`<!-- auto:no -->` or `<!-- auto:exception=<id> -->`; CI lints this.
