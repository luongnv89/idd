# /issue-resolver — Step 0: Configuration load and Workspace (0e)

One part of `references/pipeline-steps.md` — the index that maps every step to its file. Read only the part for the step you are on; a pointer to another step (*Step N — …*) resolves through that index.

## Configuration load

Full rationale for SKILL.md *Configuration*, which owns the command, the exit-code
handling and the default field list. Three details there are load-bearing and easy
to get wrong.

**Run it from the repo root.** `gi-config.py` resolves `.gitissue.yml` against the
*working directory*. Run it anywhere else and it still exits 0 — reporting
`config_file: null` and `first_run: true` — so the repo's real configuration is
discarded silently, with no error to notice. A wrong working directory therefore
looks exactly like a zero-config repo.

**Resolve the script path against this SKILL.md's own directory, not the working
directory.** The two are different by construction here: the skill is installed
somewhere under the agent's skills tree while the run happens in the user's repo.
Resolve it to an absolute path the same way the *Bundled dependency precheck*
resolves its list, and pass that absolute path to `python3`.

**The script and the manual read are alternatives, never a pair.** On exit 0 the
returned `config` is the whole answer; the defaults printed in SKILL.md are then
reference material only, and re-reading `.gitissue.yml` on top of a successful run
can only introduce a disagreement. The manual read runs *instead*, on the degrade
path, and only there.

**Why the clock is chained onto this call.** `run_started_epoch` has to be taken
before any pipeline work, and this is the first command the skill runs. Chaining
`; ec=$?; date +%s >&2; exit "$ec"` keeps stdout clean for the JSON parse and
preserves the script's own exit code for the branches above, so the measurement
costs no extra round trip. `elapsed` in the *Run Stats Footer*
(`references/run-stats.md`) is measured from it, at every terminal outcome — so a
run that never captures it reports `elapsed: n/a` rather than a wrong number.

## Step 0e — Workspace

Full procedure for the worktree offer described in SKILL.md *Step 0e — Workspace*.
**Interactive mode only** — ordinary auto mode is skipped. The offer and local
creation procedure remain interactive; `--auto` / `IDD_AUTO_MODE=1` uses the
in-place path (Repo Sync + *0f — Create branch*) byte-for-byte as before.
The worktree prompt never appears in auto mode. The sole exception is a worktree
auto-pilot already created for a parallel resolver lane; that caller-managed
path validates and adopts the workspace below, without showing a prompt or
creating another worktree.

### Caller-managed parallel worktree (auto-pilot only)

`IDD_CALLER_WORKTREE=1` is the narrow handoff for an auto-pilot parallel lane.
It is not a general auto-mode preference and is never inferred from issue text.
The main auto-pilot has already fetched the default branch, derived the branch
with `gi-branch.py --from-issue`, created a distinct sibling worktree from the
recorded base SHA, and prepared local setup. The caller launches this resolver
with canonical `Agent(description, prompt)` only; Agent has no cwd/environment
parameters. The structured `parallel_lane` record carries `lane_id`, `event_id`,
canonical absolute `worktree_path`, branch, base, and full base SHA. The worker
uses absolute file paths under that root and repeats safely bound environment
exports inside every quoted shell command; issue text can never set them. If its
tools cannot honor that contract, it stops before editing. The resolver still
derives `{branch_name}` once, then runs this validation from a shell command
whose first operation is `cd -- "$IDD_WORKTREE_PATH"`:

```bash
actual_root="$(git rev-parse --show-toplevel)"
actual_branch="$(git rev-parse --abbrev-ref HEAD)"
git_dir="$(cd "$(git rev-parse --git-dir)" && pwd)"
common_dir="$(cd "$(git rev-parse --git-common-dir)" && pwd)"

[ "$IDD_CALLER_WORKTREE" = "1" ]
[ "${IDD_AUTO_MODE:-0}" = "1" ]
[ -n "${IDD_LANE_ID:-}" ]
[ -n "${IDD_EVENT_ID:-}" ]
[ "$IDD_LANE_ID" = "$IDD_EVENT_ID" ]
[ "$actual_root" = "$IDD_WORKTREE_PATH" ]
[ "$actual_branch" = "$branch_name" ]
[ "$actual_branch" = "$IDD_LANE_BRANCH" ]
[ "$git_dir" != "$common_dir" ]                 # linked worktree, not original
git cat-file -e "${IDD_BASE_SHA}^{commit}"
git merge-base --is-ancestor "$IDD_BASE_SHA" HEAD
# The exact path + branch pair must appear in `git worktree list --porcelain`;
# another path for this branch, or another branch at this path, is a mismatch.
```

A fresh lane additionally requires a clean tree. On a resume only,
`IDD_RESUME_LANE=1` permits staged, unstaged, and untracked edits **after** the
identity checks above pass, so the resolver can continue its own interrupted
work without destroying it. Before allowing that dirty resume, reject any
`MERGE_HEAD`, `REBASE_HEAD`, `CHERRY_PICK_HEAD`, `BISECT_LOG`, or rebase directory
under the worktree git dir. Never reset, clean, stash, force-checkout, or discard
the edits. An identity mismatch or active Git operation returns
`failure_step: preflight`, `status: blocked_dirty`, and leaves the worktree for
manual recovery; a clean sibling remains eligible for the serialized drain.

Any other failure is a workspace-contract failure: stop and return `failure_step:
preflight`. **Never fall back in-place** while sibling resolvers may be active,
never create a second worktree, and never run the in-place stash/rebase or *0f*.
A fallback would put two writers in one index; stopping one lane preserves every
successful sibling. When validation passes, mark the workspace as a worktree,
skip Repo Sync and *0f* because `git worktree add ... origin/${base}` already
satisfied both, and continue with Step 0g. The caller owns cleanup after the
serialized drain; the resolver must not remove this worktree.

Build two **independent sibling inputs** from the validated `parallel_lane`
record and carry both to every nested spawn:

- `workspace_contract`: `lane_id`, canonical absolute `repo_root` and
  `worktree_path` (the same value), expected `branch`, and full `base_sha`.
- `expected_lane_identity`: a separately copied `lane_id`, issue number,
  expected branch, and canonical worktree path. Never derive this sibling from
  `workspace_contract`; both come independently from the validated outer lane.

Before any nested work, require a non-empty `lane_id` shaped
`<screened-run-id>:<issue-number>`: the prefix matches
`[A-Za-z0-9][A-Za-z0-9._-]{0,63}`, the suffix is exactly this run's numeric issue
`N`, and the whole value matches `[A-Za-z0-9][A-Za-z0-9._:-]{0,127}`. Require
`workspace_contract.lane_id == expected_lane_identity.lane_id`, and bind the
identity by also requiring its issue, branch, and canonical worktree path to
match both the current issue and the corresponding workspace-contract values.
Missing, malformed, or mismatched input stops that nested agent and lane before
any repository operation. This duplicate-looking comparison is deliberate: a
single self-consistent object is not independent evidence of lane ownership.

Researcher, implementer, code reviewer, UI reviewer, and fixer then enforce the
remaining filesystem checks in their shared-agent contracts. The synthesizer is
filesystem-free, but validates the same identity binding before using or
carrying the context. Nested agents use absolute file paths under the canonical
root and wrap each Bash repository operation in one command beginning
`cd -- "$canonical_root" && ...` (or safely bound `git -C`); no nested operation
may read, edit, stage, test, or commit through the ambient checkout. Do not
invent Agent `cwd` or environment parameters — every spawn remains canonical
`Agent(description, prompt)`. On every non-caller-managed path set both
`workspace_contract = null` and `expected_lane_identity = null`, preserving
ordinary behavior byte-for-byte.

This handoff is structural, not a safety-gate waiver. The already-resolved
checks, live issue re-verification, both secret scans, QA, final tests, and push
still run in full. On auto-pilot's default single-lane path the signal is
absent, so this section is unreachable and ordinary auto mode is unchanged.

### Why a worktree

`git worktree` checks out a branch into a *separate directory* that shares the same `.git` object store. The user's current working tree — including any uncommitted changes — is never modified. Branch creation, implementation, and the QA test runs all happen in the isolated directory.

### The offer

Before Step 0e or 0f selects a workspace, derive `branch_name` exactly once —
`python3 references/scripts/gi-branch.py {N} --from-issue --type {type}`,
reading `.branch` from its JSON. Do not re-derive or replace this value on
either path.

`--from-issue` is mandatory rather than stylistic: it makes the script read the
issue title and `resolve.branch_prefix` for itself. Both are attacker-controlled
— anyone can file an issue on a public repository — and a value interpolated
into a shell word can close its quote and append a command that `/auto-pilot`
then runs unattended. `{type}` is one of the six literals the skill classified,
never free text; without it the script infers the type from the issue labels.

The script also reports `truncated` (the title did not fit under 50 characters)
and `valid` (its own output checked against the repository's branch grammar).
`valid: false` is expected and harmless with a custom `resolve.branch_prefix` —
a configured prefix is outside the six-prefix grammar by definition.

Exit 3 means the input was unusable — a non-numeric issue number, or an issue
type with no mapping (extend it with `--type-map 'spike=chore'`). That is a
stop, not a degrade. Only a missing `python3` or exit 4 degrades: apply the
rules in `references/docs/naming-conventions.md` by hand — `"auto"` gives
`{type}/{N}-{short-description}`, and any other `resolve.branch_prefix` is used
verbatim as `{configured-prefix}{N}-{short-description}`.

Present the prompt from SKILL.md (*Step 0e — Workspace*). It must state, before the user answers:

- the derived **branch** name (`{branch_name}`),
- the **worktree path** (the naming convention below), and
- what **setup** will be copied/run (gitignored local config + the project's detected install/bootstrap).

Default is **accept** (`[Y/n]`). This satisfies acceptance criterion 5 (the proposal states what is copied and the workspace/branch naming).

### Naming convention

- **Branch:** `{branch_name}` — the same prefix-derived name used by the in-place path (`references/docs/naming-conventions.md`).
- **Worktree directory:** a *sibling* of the repo root, derived from the branch with `/` → `-` so it is a single path segment:

  ```
  ../{repo}-worktrees/{branch_name with / → -}
  ```

  Example: repo `idd`, branch `feat/123-resolver-worktree-prompt` → `../idd-worktrees/feat-123-resolver-worktree-prompt`.

  A sibling directory (outside the repo) keeps the worktree out of the repo's own status and ignore rules. If you instead place it *inside* the repo, the path **must** already be covered by `.gitignore` — otherwise the worktree's own files surface as untracked changes in the parent. Prefer the sibling location.

### Create the worktree

`git worktree add -b` creates the branch **and** the workspace in one command, off a freshly fetched base — so this replaces both the mandatory Repo Sync and *0f — Create branch* on the accepted path. No `git pull --rebase` / stash dance is needed (the new branch starts at `origin/<base>` directly).

```bash
repo_root="$(git rev-parse --show-toplevel)"        # absolute path to the repo
base="$(git rev-parse --abbrev-ref HEAD)"           # base branch to fork from
repo="$(basename "$repo_root")"
# branch_name was derived once before this step: "auto" →
# {type}/{N}-{short-description}; custom resolve.branch_prefix →
# {configured-prefix}{N}-{short-description}.
# Absolute worktree path (sibling of the repo) — independent of the current
# directory, so later steps that `cd` into it stay correct.
wt_dir="$(dirname "$repo_root")/${repo}-worktrees/$(printf '%s' "$branch_name" | tr '/' '-')"

git fetch origin
created_branch_in_step_0e=1
git worktree add -b "$branch_name" "$wt_dir" "origin/${base}"
```

Keep `repo_root` and `wt_dir` available for the setup step below (both are
absolute, so the copy works regardless of the current directory).

**If the branch already exists** (`git worktree add -b` fails): in interactive mode ask `continue` (set `created_branch_in_step_0e=0`, then add a worktree for the existing branch with `git worktree add "$wt_dir" "$branch_name"`) or `fresh` (delete the branch, keep `created_branch_in_step_0e=1`, then retry). See `references/error-messages.md` → *Branch already exists (worktree path — Step 0e)*.

**If worktree creation fails for any other reason** (e.g. path exists, disk, locked worktree): warn, print the message from `references/error-messages.md` → *Worktree creation failed*, and **fall back to the in-place path** (Repo Sync + *0f — Create branch*). Never abort the resolution just because the worktree could not be made.

After creation, **change into the worktree** so every subsequent step (research, implement, QA, deliver) operates there:

```bash
cd "$wt_dir"
```

### Prepare the workspace (generic — discovered, not hardcoded)

The goal: the worktree can build and run immediately, without the user reconfiguring it. A fresh worktree shares git history but **not** gitignored files (local config) or installed dependencies. Reconstruct them **by detecting what this repo uses** — do not assume any specific stack:

1. **Copy gitignored local config** from the original working tree into the worktree. These are the files git does not track but the app needs at runtime — typically environment files. Copy what exists; skip silently what does not:

   ```bash
   # Absolute paths from the creation block — works from any directory, so this
   # does not depend on a prior `cd` or on shell state carrying across steps.
   for f in .env .env.local .env.development .env.test; do
     [ -f "$repo_root/$f" ] && cp "$repo_root/$f" "$wt_dir/$f"
   done
   ```

   If the repo keeps other gitignored local config (service-account JSON, local certs, a `config.local.*`), copy those too. Use the repo's `.gitignore` as the guide for what is local-only. **Never copy secrets anywhere outside the worktree, and never commit them** — the pre-commit security scan (`references/docs/pre-commit-security.md`) still blocks secret-bearing files on push.

2. **Install dependencies** using the project's **detected** package manager — the same detection the researcher/implementer rely on. Examples (pick the one matching the repo, do not run all): `npm ci` / `pnpm install` / `yarn` (Node), `pip install -r requirements.txt` or `uv sync` inside the project venv (Python), `bundle install` (Ruby), `go mod download` (Go), `cargo fetch` (Rust). If the repo has no dependency manifest, skip this step.

3. **Run project bootstrap** if the repo defines one — e.g. a `Makefile` `setup`/`bootstrap` target, a `scripts/setup.sh`, a documented "getting started" command, or generated files (`prisma generate`, etc.). Skip if none exists.

Report what was prepared, e.g. `✓ Worktree ready — copied .env, ran npm ci`. Keep it factual: list only what actually ran.

**If setup fails after the worktree was created** (copy error, dependency install failure, bootstrap failure): warn, print the message from `references/error-messages.md` → *Worktree setup failed*, then clean up the partial workspace before falling back to the in-place path. This avoids stranding the resolver on a branch that is already checked out in the failed worktree.

```bash
cd "$repo_root"
cleanup_ok=1
git worktree remove "$wt_dir" --force 2>/dev/null || cleanup_ok=0
if [ "$cleanup_ok" -eq 1 ] && git worktree list --porcelain | grep -q "worktree $wt_dir$"; then
  cleanup_ok=0
fi
if [ "$cleanup_ok" -eq 0 ]; then
  git worktree prune 2>/dev/null || true
  if git worktree list --porcelain | grep -q "worktree $wt_dir$"; then
    cleanup_ok=0
  else
    cleanup_ok=1
  fi
fi
if [ "$cleanup_ok" -eq 0 ]; then
  # Do not fall back in-place while the branch is still checked out in the failed worktree.
  stop with *Worktree setup failed* recovery commands and exit the resolution attempt.
fi
# Delete the branch only if this Step 0e created it with `git worktree add -b`.
# If the user chose to continue an existing branch, keep the branch and let 0f's
# existing branch flow handle it.
if [ "${created_branch_in_step_0e:-0}" = "1" ]; then
  git branch -D "$branch_name" 2>/dev/null || true
fi
```

After **verified** cleanup (`cleanup_ok=1`), run the mandatory Repo Sync and *0f — Create branch* in the original working tree. If cleanup cannot remove the worktree entry, **stop** — print `references/error-messages.md` → *Worktree setup failed* and do not attempt the in-place path while the same branch may still be checked out in `{wt_dir}`.

### Cleanup (after delivery)

A caller-managed parallel worktree is never removed here: auto-pilot removes it
only after that lane's serialized review/merge/log/cache drain. An interactive
worktree is intentionally left in place after the PR is created so the user can inspect it. Tell them how to remove it when done:

```
○ Worktree left at {wt_dir} for inspection.
  Remove with:  git worktree remove {wt_dir}
```

Do not auto-remove it — the user may still want the local artifacts.
