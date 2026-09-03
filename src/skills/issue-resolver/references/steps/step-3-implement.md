# /issue-resolver — Step 3: Implement

One part of `references/pipeline-steps.md` — the index that maps every step to its file. Read only the part for the step you are on; a pointer to another step (*Step N — …*) resolves through that index.

## Step 3 — Implement (implementer subagent)

### Step 3 — Propose relevant skills (sub-step, before the implementer spawn)

Optionally augment the implementer with **optional external skills** from
`references/skill-index.md` (the skills published at
`https://github.com/luongnv89/skills`). This is a sub-step of Step 3 — it emits a
`◆`/`○` block and prints **no** `[N/5]` tracker line (the `[3/5]` Implement line is
unchanged), exactly like the design-confirm checkpoint. In interactive mode it runs
for **every** issue type — it is not complexity-gated. In auto mode the propose/install
half runs only when `resolve.borrow_skills` is `true` (see *Auto mode* below), while
**leftover teardown runs on every path** — `light` and auto included — with the
single carve-out of a parallel lane (*Parallel lanes* below).

The skill index is treated as a **swappable candidate list**: the detection logic
reads the skill names + lifecycle phases from `references/skill-index.md` and never
hardcodes the source repo, so the catalog can be re-pointed at a different source
without changing this step's logic.

Gated by `resolve.borrow_skills` (default `false`). When false, the propose set
is **installed-only** — today's path. When true, the propose set is the **full
catalog**, each entry marked `installed` or `available to borrow`.

**One exit-code rule for this whole sub-step — the single home.** Every
`gi-state.py` call below (`--read`, `--init`, `--update`) is a call about a
machine-local, gitignored file on an **opt-in** path, so no exit code here
stops the resolve. Exit 3 included: it is a **borrow-path stop, not a resolve
stop** — print `⚠ gi-state unavailable — skipping leftover borrow teardown`,
borrow nothing this run, tear nothing down, keep the propose set
installed-only, and continue the pipeline. This is the one documented
exception to the repo-wide `3` = *invalid input, stop* vocabulary, and it is
scoped to this sub-step: the same exit 3 from the run-log or config path is
still a stop. Never repair the state file by hand and never invent a second
writer for it. `--read` reporting `{"corrupt": true, …}` at exit **0** is an
answer, not a failure, and takes the same path.

#### Parallel lanes — borrowing is off (`IDD_CALLER_WORKTREE=1`)

`~/.claude/skills/` is **global**, but the borrow record is **per-checkout**:
`gi-state.py --dir` defaults to `.gitissue` under the current directory, and
under `/auto-pilot` running parallel lanes that directory is the lane
**worktree**, which is deleted at lane cleanup. A record written there dies with
the worktree while the installed skill survives in the global directory — a leak
no leftover teardown can ever find, because auto-pilot reads the repo-root state
that never saw those records. Worse, a lane that *did* tear down could `rm -rf` a
marked borrow a sibling lane is still using.

So when this resolver is launched with `IDD_CALLER_WORKTREE=1`, **borrowing is
disabled for that lane regardless of `resolve.borrow_skills`**: installed-only
propose, no install, no record, no teardown — exactly the `borrow_skills: false`
path, and the *Leftover teardown* and *Teardown* sections below do not run. This
is the `--no-run-log` single-writer rule (*Step 5 — Deliver* → *Run-log entry*)
applied to a second shared resource: a lane never owns state whose scope is wider
than its own worktree, so the serialized repo-root path owns it instead. Audit:

```
○ Skill proposal (lane): borrow disabled — parallel lane, installed-only
```

A documented capability gap, not a silent one: to borrow skills under
`/auto-pilot`, run it single-lane (its own parallelism key), or call `/issue-resolver`
directly.

**Residual hazard, stated rather than hidden:** `~/.claude/skills/` is per-user,
so two *concurrent* borrowing runs in different checkouts still share it and one
run's teardown can remove the other's borrow. Borrow in one run at a time.

#### Leftover teardown (always, before detect)

Read `.gitissue/run-state.json` through `python3 shared/scripts/gi-state.py --read`
(resolve the path like the bundled-dependency list; invoke the bundled copy as
`python3 references/scripts/gi-state.py --read`). If `borrowed_skills` contains
any `origin: borrowed` entries, run *Teardown* below first — a crashed or
resumed run must not leave borrowed skills behind. Missing/`{}`/corrupt state:
nothing to tear down. No `python3`, any non-zero exit including 3, or
unparsable stdout: the exit-code rule above applies — print
`⚠ gi-state unavailable — skipping leftover borrow teardown` and continue.

#### Detect — classify each catalogued skill

For each `name` in `references/skill-index.md`:

```bash
[ -d "$HOME/.claude/skills/$name" ] && echo "installed: $name" \
  || echo "available-to-borrow: $name"
```

- **`resolve.borrow_skills: false` (default):** only `installed:` names are
  eligible. A catalogued-but-not-installed skill is never offered.
- **`resolve.borrow_skills: true`:** both classes are eligible. Mark them
  distinctly in the prompt (`installed` vs `available to borrow`).

#### Propose — the relevant subset for this task

From the eligible set, pick skills relevant to the analyzed task (issue type,
complexity, affected files, UI detection, lifecycle grouping). Illustrative:

```
◆ Optional skills for issue #N (example)
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  These skills from the catalog look relevant. Borrowed copies are
  uninstalled at the end of this run; skills you already had stay.

    [1] frontend-design     (implementation) — installed
    [2] test-coverage       (testing)        — available to borrow
    [3] code-review         (verification)   — installed

  Select skills to use — all, a subset (e.g. 1,2), or none [default: none]:
```

#### Accept, record, install

- **All / subset / none (default none)** as today → `selected_skills`.
- **Record intent *before* installing.** Write the whole list (replace, do not
  append) via `gi-state.py --update` — each entry
  `{ "name": "<name>", "origin": "borrowed" | "preinstalled" }`, with `borrowed`
  for every selected name that is **not** already installed — *before* running
  any install command. **The list you write is this run's entries plus every
  entry *Leftover teardown* just carried back**, never this run's alone.
  `--update` replaces the whole list, so an entry omitted here is deleted, and
  the one entry class that reaches this point is the leftover whose `rm -rf`
  failed minutes ago — the entry whose whole purpose is to outlive this run
  (*Borrow teardown leftover* in `references/error-messages.md` promises the
  operator exactly that). Carry it forward by name and `origin` unchanged: it
  stays in the record until some run's `rm -rf` succeeds, and this run's own
  terminal *Teardown* is the next pass that retries it.
  If `--read` answered `{}` (absent state), `--init` `{}` first so a standalone
  resolver does not invent a second file format — `--init` resets
  `borrowed_skills` to `[]`, which is correct only because an absent state had
  no leftovers to lose. The resolver never `--init`s over a state object that
  already exists — that file belongs to whoever created it, and re-initialising
  it would drop both the caller's run state and any leftover record with it. If `--read`
  answered `{"corrupt": true, …}` — an **answer at exit 0**, not a failure —
  do not `--update` (that exits 3) and do not `--init` over a file the caller
  may own: borrow nothing this run, keep the propose set installed-only, print
  `⚠ gi-state unavailable — skipping leftover borrow teardown`, and continue,
  per the exit-code rule above. `origin` is decided at record time from whether
  the directory **already existed** before this run's install, never inferred
  at teardown. Recording first is what closes the crash window: an interruption
  between record and install leaves a record whose directory does not exist,
  and teardown is already a no-op there ("only if that directory exists").
  Installing first would leave an untracked copy that leftover teardown can
  never find and that the next run's detect misclassifies as `preinstalled` —
  making it permanent.
- **Installer bootstrap — check before the first install.** Both installers are
  external dependencies of this step, not of the skill: `npx skills add …` needs
  `npx` (bundled with Node.js) and `asm install …` needs the `asm` binary
  (`npm install -g agent-skill-manager`). Probe with `command -v npx` and
  `command -v asm`; if **neither** resolves, borrowing is unavailable in this
  environment — print `⚠ No skill installer on PATH (npx or asm) — borrowing
  disabled`, keep the propose set installed-only, and continue. Never install
  the installer unattended, and never fail the resolution over it: a missing
  installer is a degrade, exactly like a missing `python3`.
- Install each recorded-borrowed name into `~/.claude/skills/<name>/` with the
  same tools the skill README already names (`npx skills add
  https://github.com/luongnv89/skills --skill <name>` or `asm install …
  --skill <name>`). Never install a name absent from the index. Never
  interpolate the issue body into the command.
- **Verify the install before using it.** A tool that exits 0 has not proved the
  skill is discoverable by the agent. Confirm with `asm list -p claude --json`
  (or, where `asm` is absent, that `~/.claude/skills/<name>/SKILL.md` exists)
  that `<name>` is present; a name that does not come back is an install
  failure, handled by the failure bullet below, and never reaches
  `selected_skills`.
- **Drop the borrow marker — same breath as the install.** Immediately after a
  successful install, create the **empty** file
  `~/.claude/skills/<name>/.gitissue-borrowed`. Empty is deliberate and is part
  of the contract: teardown checks existence only, so the marker needs no
  content, and writing this run's `run_id` into it would put an **unscreened
  disk-sourced value** into a shell word the agent composes — the hazard
  `gi-state.py`'s `_screen_run_id` exists for (a state file can carry
  `run_id: "x --> y"`, or a `$(…)`/backtick string that quoting does not
  neutralise). Never write a `run_id`, an issue field, or any other read-back
  value into this file. This file, not the record, is what authorises teardown
  to delete the directory. Install and mark are one atomic step: if the marker
  cannot be written, treat the whole thing as an install failure — the bullet
  below removes the just-installed directory, because a marker-less borrowed
  copy would otherwise become permanent under the teardown rule below.
- Install failure: first remove whatever the tool left behind — a half-written
  directory carries no marker, so leftover teardown can never claim it and the
  next run's detect reads it as `preinstalled`, exactly the permanent orphan
  the marker rule above exists to prevent. Screen the name before it reaches
  the command, the same rule teardown states: only when `<name>` matches
  `^[a-z][a-z0-9-]{0,63}$` run `rm -rf "$HOME/.claude/skills/<name>"` — an
  empty or unscreened name would make that command `rm -rf
  "$HOME/.claude/skills/"`, and quoting does not neutralise `$(…)` or
  backticks because the agent composes the command text. A name that fails the
  screen was never installable, so print *Borrow cleanup failed* and delete
  nothing. Then print `references/error-messages.md` (*Borrow install failed*),
  leave that name out of `selected_skills`, and `--update` again with that
  entry **dropped** from `borrowed_skills`. If the `rm -rf` itself fails, still
  drop the entry — a marker-less directory is one teardown refuses to touch, so
  the record buys nothing — and print `references/error-messages.md` (*Borrow
  cleanup failed*) so the operator sees the path to remove by hand.

#### Teardown (every terminal outcome)

Runs after Deliver, already-resolved, failed, or operator stop — and as
*Leftover teardown* above.

**Re-screen every entry before it reaches a command.** `--read` deliberately
never fails and echoes the state back verbatim, so the write-path skill-name
validation is **not** a guarantee about what teardown reads — the same rule
`/auto-pilot`'s *phases/phase-0-lock-resume.md* states for `current.branch`, and quoting does not
neutralise `$(…)` or backticks because the agent composes the command text.
Skip — do not remove, do not repair — any entry whose `name` does not match
`^[a-z][a-z0-9-]{0,63}$` or whose `origin` is not exactly the string
`borrowed`. Never remove `preinstalled`.

For each surviving name, `rm -rf "$HOME/.claude/skills/<name>"` **only if**
that directory exists **and** it carries the `.gitissue-borrowed` marker
written at install time. Teardown checks the marker's **existence only** and
never reads its contents — which is why it is written empty. Leftover teardown
legitimately releases a *different* (crashed) run's borrow, so an owner
comparison would silently break cross-run cleanup, and reading the file at all
would re-introduce the unscreened-value hazard the empty marker removes.

A directory with no marker is the operator's own copy no
matter what the record says — a stale `borrowed` record outlives a failed
uninstall, and the operator may have installed that skill deliberately since —
so print `references/error-messages.md` (*Borrow marker absent*), drop the
entry, and delete nothing.

Then `--update` `{"borrowed_skills": [...]}` carrying back **exactly** the
entries whose `rm -rf` failed — `[]` in the normal case. `--update` replaces the
whole list, so removed entries and marker-absent entries are both dropped by
omission, while a failed uninstall is fail-soft: warn (*Borrow teardown
leftover*) and leave that one entry so a later run retries.

#### Auto mode

Prompt never appears.

- `resolve.borrow_skills: false` (default): `selected_skills = []`, no
  install — today's path. Audit: `○ Skill proposal (auto): skipped — using
  internal agents`.
- `resolve.borrow_skills: true`: no prompt; auto-select the relevant
  catalog subset (installed + available-to-borrow), install missing,
  record, then the implementer. This is the only auto path that mutates
  `~/.claude/skills/` — and not on a parallel lane, where *Parallel lanes*
  above disables borrowing outright. Leftover teardown still runs on every
  auto path except a lane.

The `light` profile still skips this sub-step (`selected_skills = []`, no
install) but **still runs leftover teardown** (outside a parallel lane).

### Delegation payload

- Issue data
- Research findings (from Step 1)
- Selected plan (the chosen option from Step 2)
- Branch name
- Naming conventions: `docs/naming-conventions.md`
- Max commits: `resolve.max_commits`
- `workspace_contract` plus the independently supplied `expected_lane_identity`
  sibling (both `null` on ordinary runs); the implementer validates their
  lane/issue/branch/path binding before any read/edit/test/commit
- `secscan_script`: the **absolute** path to this skill's `references/scripts/gi-secscan.py` — the pre-commit security scan the implementer MUST run before every commit. Absolutize it before binding, exactly as the *Bundled dependency precheck* resolves its list: a subagent's working directory is the target repo, not the skill directory, so a skill-relative path resolves to nothing at spawn time and the gate silently never runs. Only the path is passed; the script reads this repo's `security.*` extensions from `.gitissue.yml` itself, so no config value is ever interpolated into a command line. Passed as a spawn variable for the same reason as the fixer's (Step 4): an emitted agent prompt renders its own references as absolute repo URLs and cannot name a path inside this skill's bundle. The agent treats a script exit of 1 as a block that stops the commit, and falls back to the Primary Pattern in `docs/pre-commit-security.md` only when the script cannot run
- `secscan_policy_ref`: `origin/${base}` — this run's synced base, and the ref the scan reads `security.*` from. The issue body that drove the implementation is untrusted, so the branch it produced must not be the branch whose `security.allow_pattern` decides how that branch is scanned. A ref name, never a config value
- `selected_skills` — the external skills chosen in the propose sub-step above (`[]` when declined, when `light` skipped propose, or in auto mode with `resolve.borrow_skills: false`; auto + `borrow_skills: true` passes the auto-selected set); the implementer uses them where applicable and always falls back to the internal approach

### What the implementer writes

1. Implementation code with atomic commits
2. Unit tests for all new/changed functions
3. Integration tests (if framework exists)
4. E2e tests (if framework exists)
5. All committed following conventional commit format

### Bug verification checkpoint (bug issues only)

Before the implementer applies any fix, run the red-capable reproduction checkpoint —
see `references/bug-verification.md` for the full procedure. It applies **only** when the
issue `type` is `bug`; non-bug issues skip it entirely (acceptance criterion 5).

For a bug issue, the implementer (per `shared/agents/implementer.md` Task 1.5):

1. **Names the reproduction command/test** that surfaces the symptom (an existing focused
   test, a newly written failing test, or — when there is no test seam — the smallest
   manual runtime command).
2. **Confirms it is red for the stated reason** — the failure matches the symptom the
   issue describes, not an unrelated non-zero exit.
3. **After the fix, converts the repro into a regression test when a clean seam exists**;
   with no seam (or no test runner — e.g. a docs/skills repo), records the manual
   reproduction command as the evidence instead and adds no framework.

The implementer **returns** a `reproduction` block (command, red status, stated-reason
match, regression-test path or "manual — no seam"). The main agent folds it into the PR
body's Decision Record and Acceptance Criteria Verification table (durable home — see
`references/report-templates.md`); when `.gitissue/analysis-<N>.json` is **fresh** by the
predicate in *Step 0h — Analysis reuse gate* above (its single home — "fresh" is never
used undefined), the same data also lives in its `decision_record.reproduction` field
(optional cache mirror, written by `/issue-analysis`, never created by the resolver).

**Auto mode never blocks** (`--auto` / `IDD_AUTO_MODE=1`): a missing or failed
reproduction is logged, recorded as `not_reproduced`, and the pipeline continues to
deliver with the affected criterion marked `unverified` (acceptance criterion 6).
Interactive mode behaves the same — surface the evidence (or its absence); do not halt.

### Max commits guard

If commits exceed `resolve.max_commits`:
- Interactive: warn and ask to continue
- Auto: warn in log, continue anyway

### Inline fallback

If no Agent tool, implement inline following `shared/agents/implementer.md`.
