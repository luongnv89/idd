#!/usr/bin/env bash
# test-postmerge-cleanup.sh — after a PR merges, the local checkout is cleaned
# up: worktrees on the merged branch are removed, the main checkout switches to
# the updated base, and the squash-merged local branch is deleted.
#
#   P1  gi-postmerge.py is a well-formed shared script (0755, stdlib-only,
#       --help exits 0, usage error exits 2, invalid --pr exits 3).
#   P2  executed against a real fixture (bare origin, squash merge, fake gh):
#       the clean, dirty, worktree, dirty-worktree, unmerged-commit, other-
#       branch, run-from-worktree, dry-run, not-merged, --delete-remote and
#       idempotent cases each leave the repository in the documented state;
#       so do the safety cases: an older stash, ignored files in a worktree,
#       a checkout mid-merge, fork PRs, a stale local tip, a moved remote.
#   P3  failures degrade: gh failing or no repository is exit 4, nothing changed.
#   P4  wiring: both merge sites (issue-pr-review, auto-pilot) and the
#       post-merge-cleanup doc carry the cleanup, the bundles ship the script,
#       and the prose fallback never forces a worktree removal.
#
# Usage: bash tests/test-postmerge-cleanup.sh
# Returns: exit 0 if all checks pass, exit 1 on failure.

# No `set -e`: assertions report and continue.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "0" ]; then pass "$1"; else fail "$1"; fi; }

SCRIPT="$REPO_ROOT/src/shared/scripts/gi-postmerge.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

# A fake gh on PATH answers `gh pr view` from $FAKE_GH_JSON.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
[ "${FAKE_GH_EXIT:-0}" = "0" ] || { echo "gh: backend down" >&2; exit "$FAKE_GH_EXIT"; }
cat "$FAKE_GH_JSON"
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

field() { python3 -c 'import json,sys; v=json.loads(sys.argv[1]); 
for k in sys.argv[2].split("."): v=v[int(k)] if isinstance(v,list) else v[k]
print(v if isinstance(v,str) else json.dumps(v))' "$1" "$2"; }

BRANCH="feat/42-dark-mode"

# fixture NAME [STATE] — origin with a squash-merged $BRANCH; the clone
# $TMP/NAME/repo is left on $BRANCH, one commit behind the new origin/main.
fixture() {
  local d="$TMP/$1" state="${2:-MERGED}"
  mkdir -p "$d"
  git init -q --bare -b main "$d/origin.git"
  git clone -q "$d/origin.git" "$d/repo" 2>/dev/null
  (
    cd "$d/repo" || exit 1
    echo base > app.txt && git add app.txt && git commit -q -m init
    git push -q origin main
    git checkout -q -b "$BRANCH"
    echo feature >> app.txt && git commit -q -am "feat: dark mode"
    git push -q origin "$BRANCH"
  )
  local head; head="$(git -C "$d/repo" rev-parse HEAD)"
  git clone -q "$d/origin.git" "$d/merger" 2>/dev/null
  (
    cd "$d/merger" || exit 1
    git checkout -q main
    git merge -q --squash "origin/$BRANCH" >/dev/null && git commit -q -m "feat: dark mode (#42)"
    git push -q origin main
    [ "$state" = "MERGED" ] && git push -q origin --delete "$BRANCH"
  ) 2>/dev/null
  printf '{"state":"%s","headRefName":"%s","headRefOid":"%s","baseRefName":"main","isCrossRepository":false}' \
    "$state" "$BRANCH" "$head" > "$d/pr.json"
  export FAKE_GH_JSON="$d/pr.json"
}
run() { (cd "$1" && python3 "$SCRIPT" --pr 42 "${@:2}"); }
on_branch() { git -C "$1" symbolic-ref --short HEAD; }
has_branch() { git -C "$1" show-ref --verify --quiet "refs/heads/$BRANCH"; }
at_origin_main() { [ "$(git -C "$1" rev-parse main)" = "$(git -C "$1" rev-parse origin/main)" ]; }

echo "◆ Post-merge cleanup (gi-postmerge)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ── P1: a well-formed shared script ──────────────────────────
[ -f "$SCRIPT" ] && [ -x "$SCRIPT" ]; check "P1: gi-postmerge.py exists and is executable" "$?"
mode="$(cd "$REPO_ROOT" && git ls-files -s src/shared/scripts/gi-postmerge.py | awk '{print $1}')"
[ -z "$mode" ] || [ "$mode" = "100755" ]; check "P1: committed mode is 0755 (got ${mode:-untracked})" "$?"
python3 "$SCRIPT" --help >/dev/null 2>&1; check "P1: --help exits 0" "$?"
python3 "$SCRIPT" --bogus >/dev/null 2>&1; [ "$?" = "2" ]; check "P1: an unknown option is a usage error (exit 2)" "$?"
python3 "$SCRIPT" --pr abc >/dev/null 2>&1; [ "$?" = "3" ]; check "P1: a non-integer --pr is invalid input (exit 3)" "$?"
python3 - "$SCRIPT" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
mods = {a.name.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.Import) for a in n.names}
mods |= {n.module.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.ImportFrom) and n.module}
sys.exit(0 if mods <= set(sys.stdlib_module_names) else 1)
PY
check "P1: imports only the standard library" "$?"

# ── P2: behavior on a real repository ────────────────────────
fixture clean
R="$TMP/clean/repo"
OUT="$(run "$R")"; EC=$?
[ "$EC" = 0 ] && [ "$(field "$OUT" ok)" = true ]
check "P2 clean: exit 0 and ok" "$?"
[ "$(on_branch "$R")" = main ] && at_origin_main "$R"
check "P2 clean: the checkout switched to the updated main" "$?"
! has_branch "$R"; check "P2 clean: the squash-merged local branch is deleted (branch -d would refuse it)" "$?"
! git -C "$R" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"
check "P2 clean: the stale remote-tracking ref is pruned" "$?"
OUT2="$(run "$R")"
[ "$(field "$OUT2" ok)" = true ] && [ "$(field "$OUT2" local_branch.action)" = absent ] \
  && [ "$(field "$OUT2" checkout.action)" = already ]
check "P2 idempotent: a second run is ok and changes nothing" "$?"

fixture dirty
R="$TMP/dirty/repo"
echo note > "$R/notes.txt"
OUT="$(run "$R")"
[ "$(on_branch "$R")" = main ] && [ "$(field "$OUT" stash)" = restored ] && [ -f "$R/notes.txt" ] \
  && [ -z "$(git -C "$R" stash list)" ]
check "P2 dirty: stash-first — switched, and the untracked file came back" "$?"

fixture wt
R="$TMP/wt/repo"
git -C "$R" checkout -q main
git -C "$R" worktree add -q "$TMP/wt/lane" "$BRANCH" 2>/dev/null
OUT="$(run "$R")"
[ ! -d "$TMP/wt/lane" ] && [ "$(field "$OUT" worktrees)" != "[]" ] && ! has_branch "$R" && at_origin_main "$R"
check "P2 worktree: the clean worktree is removed, branch deleted, main updated" "$?"

fixture wtdirty
R="$TMP/wtdirty/repo"
git -C "$R" checkout -q main
git -C "$R" worktree add -q "$TMP/wtdirty/lane" "$BRANCH" 2>/dev/null
echo wip >> "$TMP/wtdirty/lane/app.txt"
OUT="$(run "$R")"
[ -f "$TMP/wtdirty/lane/app.txt" ] && grep -q wip "$TMP/wtdirty/lane/app.txt" && has_branch "$R" \
  && [ "$(field "$OUT" ok)" = false ] && [ "$(field "$OUT" local_branch.reason)" = checked_out ]
check "P2 dirty worktree: kept untouched (never --force), branch kept, ok false" "$?"

fixture unmerged
R="$TMP/unmerged/repo"
echo extra > "$R/extra.txt" && git -C "$R" add extra.txt && git -C "$R" commit -q -m extra
OUT="$(run "$R")"
has_branch "$R" && [ "$(field "$OUT" local_branch.reason)" = unmerged_commits ] && [ "$(on_branch "$R")" = main ]
check "P2 unmerged commits: the branch the PR never saw is kept" "$?"

fixture other
R="$TMP/other/repo"
git -C "$R" checkout -q -b spike main
OUT="$(run "$R")"
[ "$(on_branch "$R")" = spike ] && at_origin_main "$R" && ! has_branch "$R" \
  && [ "$(field "$OUT" checkout.reason)" = on_other_branch ]
check "P2 other branch: stays on it, local main still fast-forwarded" "$?"

fixture inside
R="$TMP/inside/repo"
git -C "$R" checkout -q main
git -C "$R" worktree add -q "$TMP/inside/lane" "$BRANCH" 2>/dev/null
OUT="$(run "$TMP/inside/lane")"
[ ! -d "$TMP/inside/lane" ] && [ "$(field "$OUT" cwd_removed)" = true ] && ! has_branch "$R"
check "P2 run from the worktree: it is removed and cwd_removed says so" "$?"

fixture dry
R="$TMP/dry/repo"
before="$(git -C "$R" for-each-ref --format='%(refname) %(objectname)')"
OUT="$(run "$R" --dry-run)"
after="$(git -C "$R" for-each-ref --format='%(refname) %(objectname)')"
[ "$before" = "$after" ] && [ "$(on_branch "$R")" = "$BRANCH" ] \
  && [ "$(field "$OUT" checkout.action)" = planned ] && [ "$(field "$OUT" local_branch.action)" = planned ]
check "P2 dry run: no ref moves, every step reported as planned" "$?"

fixture open OPEN
R="$TMP/open/repo"
OUT="$(run "$R")"
[ "$(field "$OUT" merged)" = false ] && [ "$(field "$OUT" ok)" = false ] \
  && [ "$(on_branch "$R")" = "$BRANCH" ] && has_branch "$R"
check "P2 not merged: an answer (merged false, ok false), nothing touched" "$?"

# setpr KEY JSON-VALUE — edit the fake gh answer of the current fixture.
setpr() { python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d[sys.argv[2]]=json.loads(sys.argv[3]); json.dump(d,open(p,"w"))' "$FAKE_GH_JSON" "$1" "$2"; }

fixture stashkeep
R="$TMP/stashkeep/repo"
echo older > "$R/older.txt" && git -C "$R" stash push -q -u -m older
echo note > "$R/notes.txt"
OUT="$(run "$R")"
[ "$(on_branch "$R")" = main ] && [ -f "$R/notes.txt" ] && [ ! -f "$R/older.txt" ] \
  && [ "$(git -C "$R" stash list | wc -l | tr -d ' ')" = 1 ] && git -C "$R" stash list | grep -q older
check "P2 stash: only this run's stash is popped; an older stash is left alone" "$?"

# A moved submodule reads as dirty, but `git stash push` saves nothing and
# still exits 0 — a blind pop would apply the user's older stash.
fixture stashnoop
R="$TMP/stashnoop/repo"
git init -q "$TMP/stashnoop/sub" && git -C "$TMP/stashnoop/sub" commit -q --allow-empty -m s1
git -C "$R" -c protocol.file.allow=always submodule add -q "$TMP/stashnoop/sub" sub >/dev/null 2>&1
git -C "$R" commit -q -m "add sub"
git -C "$R/sub" commit -q --allow-empty -m s2
echo older > "$R/older.txt" && git -C "$R" stash push -q -u -m older
OUT="$(run "$R")"
[ ! -f "$R/older.txt" ] && git -C "$R" stash list | grep -q older && [ "$(field "$OUT" stash)" = none ]
check "P2 stash: a stash push that saved nothing never pops an older stash" "$?"

fixture wtign
R="$TMP/wtign/repo"
git -C "$R" checkout -q main
git -C "$R" worktree add -q "$TMP/wtign/lane" "$BRANCH" 2>/dev/null
echo '*.log' >> "$R/.git/info/exclude" && echo keep > "$TMP/wtign/lane/debug.log"
OUT="$(run "$R")"
[ -f "$TMP/wtign/lane/debug.log" ] && has_branch "$R" && [ "$(field "$OUT" ok)" = false ] \
  && echo "$OUT" | grep -q '"reason": "ignored_files"'
check "P2 ignored files: a worktree whose ignored files a remove would delete is kept" "$?"

fixture midmerge
R="$TMP/midmerge/repo"
git -C "$R" rev-parse HEAD > "$R/.git/MERGE_HEAD"
OUT="$(run "$R")"
[ "$(on_branch "$R")" = "$BRANCH" ] && [ "$(field "$OUT" checkout.reason)" = operation_in_progress ] \
  && has_branch "$R" && [ "$(field "$OUT" ok)" = false ]
check "P2 in progress: a checkout mid-merge is never stashed or switched" "$?"

fixture forkname
R="$TMP/forkname/repo"
git -C "$R" checkout -q main
setpr isCrossRepository true; setpr headRefOid '"1111111111111111111111111111111111111111"'
OUT="$(run "$R")"
has_branch "$R" && [ "$(field "$OUT" local_branch.reason)" = not_pr_head ] && [ "$(field "$OUT" ok)" = false ]
check "P2 fork, same name: an unrelated local branch is reported, never deleted" "$?"

fixture forkexact
R="$TMP/forkexact/repo"
setpr isCrossRepository true
OUT="$(run "$R")"
[ "$(on_branch "$R")" = main ] && ! has_branch "$R" && [ "$(field "$OUT" ok)" = true ]
check "P2 fork, exact head: the fork checkout is switched off and deleted" "$?"

fixture behind
R="$TMP/behind/repo"
echo more >> "$R/app.txt" && git -C "$R" commit -q -am more
newer="$(git -C "$R" rev-parse HEAD)" && git -C "$R" reset -q --hard HEAD~1
setpr headRefOid "\"$newer\""
OUT="$(run "$R")"
! has_branch "$R" && [ "$(field "$OUT" local_branch.action)" = deleted ]
check "P2 behind: a local tip behind the merged head holds nothing new and is deleted" "$?"

fixture moved OPEN
R="$TMP/moved/repo"
setpr state '"MERGED"'
echo late >> "$R/app.txt" && git -C "$R" commit -q -am late && git -C "$R" push -q origin "$BRANCH" 2>/dev/null
OUT="$(run "$R" --delete-remote)"
[ "$(field "$OUT" remote_branch)" = kept ] \
  && git -C "$TMP/moved/origin.git" show-ref --verify --quiet "refs/heads/$BRANCH"
check "P2 --delete-remote: a remote branch pushed past the merged head is kept" "$?"

fixture remote OPEN
R="$TMP/remote/repo"
sed -i.bak 's/"OPEN"/"MERGED"/' "$TMP/remote/pr.json"
OUT="$(run "$R" --delete-remote)"
[ "$(field "$OUT" remote_branch)" = deleted ] \
  && ! git -C "$TMP/remote/origin.git" show-ref --verify --quiet "refs/heads/$BRANCH"
check "P2 --delete-remote: a remote branch gh left behind is deleted" "$?"

# lane NAME — fixture NAME with the clone on main and $BRANCH in a linked
# worktree at $TMP/NAME/lane.
lane() {
  fixture "$1"
  git -C "$TMP/$1/repo" checkout -q main
  git -C "$TMP/$1/repo" worktree add -q "$TMP/$1/lane" "$BRANCH" 2>/dev/null
}

# status.showUntrackedFiles=no hides untracked files from a plain `git status
# --porcelain`; a plain `git worktree remove` then deletes them.
lane untracked
R="$TMP/untracked/repo"
git -C "$R" config status.showUntrackedFiles no
echo draft > "$TMP/untracked/lane/draft.txt"
OUT="$(run "$R")"
[ -f "$TMP/untracked/lane/draft.txt" ] && has_branch "$R" && [ "$(field "$OUT" ok)" = false ] \
  && [ "$(field "$OUT" worktrees.0.reason)" = untracked_files ] \
  && [ "$(field "$OUT" worktrees.0.files)" = '["draft.txt"]' ] && [ "$(field "$OUT" worktrees.0.file_count)" = 1 ]
check "P2 untracked (showUntrackedFiles=no): worktree and file kept, reason untracked_files, file listed" "$?"
OUT="$(run "$R" --remove-worktree "$TMP/untracked/lane")"
[ ! -d "$TMP/untracked/lane" ] && ! has_branch "$R" && [ "$(field "$OUT" ok)" = true ] \
  && [ "$(field "$OUT" worktrees.0.action)" = removed ]
check "P2 --remove-worktree: the confirmed untracked-only worktree is removed and the branch deleted" "$?"

lane refuse
R="$TMP/refuse/repo"
echo draft > "$TMP/refuse/lane/draft.txt" && echo wip >> "$TMP/refuse/lane/app.txt"
OUT="$(run "$R" --remove-worktree "$TMP/refuse/lane")"
[ -f "$TMP/refuse/lane/draft.txt" ] && grep -q wip "$TMP/refuse/lane/app.txt" && has_branch "$R" \
  && [ "$(field "$OUT" worktrees.0.reason)" = dirty ] && [ "$(field "$OUT" ok)" = false ]
check "P2 --remove-worktree: refused when the worktree has tracked changes" "$?"

lane wrongpath
R="$TMP/wrongpath/repo"
OUT="$(run "$R" --remove-worktree "$TMP/wrongpath/repo")"
[ -d "$TMP/wrongpath/repo/.git" ] && [ "$(field "$OUT" ok)" = false ] \
  && echo "$OUT" | grep -q 'not_merged_branch_worktree'
check "P2 --remove-worktree: a path that is not a worktree on the merged branch is left alone" "$?"

lane ignonly
R="$TMP/ignonly/repo"
echo '*.log' >> "$R/.git/info/exclude" && echo keep > "$TMP/ignonly/lane/debug.log"
OUT="$(run "$R")"
[ -f "$TMP/ignonly/lane/debug.log" ] && [ "$(field "$OUT" worktrees.0.reason)" = ignored_files ] \
  && [ "$(field "$OUT" worktrees.0.files)" = '["debug.log"]' ]
check "P2 ignored only: reason ignored_files, the file listed" "$?"

lane locked
R="$TMP/locked/repo"
git -C "$R" worktree lock "$TMP/locked/lane"
OUT="$(run "$R")"
[ -d "$TMP/locked/lane" ] && has_branch "$R" && [ "$(field "$OUT" worktrees.0.action)" = kept ] \
  && [ "$(field "$OUT" worktrees.0.reason)" = locked ]
check "P2 locked: a locked worktree is kept" "$?"

# A local commit on main the remote never saw: fast-forward refuses, nothing resets.
fixture divswitch
R="$TMP/divswitch/repo"
git -C "$R" checkout -q main && echo local > "$R/local.txt" && git -C "$R" add local.txt \
  && git -C "$R" commit -q -m local && git -C "$R" checkout -q "$BRANCH"
localmain="$(git -C "$R" rev-parse main)"
OUT="$(run "$R")"
[ "$(field "$OUT" fast_forward)" = diverged ] && [ "$(field "$OUT" ok)" = false ] \
  && [ "$(git -C "$R" rev-parse main)" = "$localmain" ] && [ "$(on_branch "$R")" = main ]
check "P2 diverged base (switch path): reported, ok false, main not reset" "$?"

fixture divother
R="$TMP/divother/repo"
git -C "$R" checkout -q main && echo local > "$R/local.txt" && git -C "$R" add local.txt \
  && git -C "$R" commit -q -m local && git -C "$R" checkout -q -b spike
localmain="$(git -C "$R" rev-parse main)"
OUT="$(run "$R")"
[ "$(field "$OUT" fast_forward)" = diverged ] && [ "$(field "$OUT" ok)" = false ] \
  && [ "$(git -C "$R" rev-parse main)" = "$localmain" ] && [ "$(on_branch "$R")" = spike ]
check "P2 diverged base (other branch): reported, ok false, main not reset" "$?"

fixture forkremote OPEN
R="$TMP/forkremote/repo"
setpr state '"MERGED"'; setpr isCrossRepository true
OUT="$(run "$R" --delete-remote)"
[ "$(field "$OUT" remote_branch)" = skipped ] \
  && git -C "$TMP/forkremote/origin.git" show-ref --verify --quiet "refs/heads/$BRANCH"
check "P2 fork + --delete-remote: the remote branch is skipped and still present" "$?"

fixture baselinked
R="$TMP/baselinked/repo"
git -C "$R" worktree add -q "$TMP/baselinked/basewt" main 2>/dev/null
OUT="$(run "$R")"
[ "$(on_branch "$R")" = "$BRANCH" ] && [ "$(field "$OUT" checkout.reason)" = base_checked_out_elsewhere ] \
  && has_branch "$R" && [ "$(field "$OUT" ok)" = false ] && [ "$(on_branch "$TMP/baselinked/basewt")" = main ]
check "P2 base in a linked worktree: reported, never forced" "$?"

# origin/main moved past the PR on the same line the local edit touches.
fixture popconflict
R="$TMP/popconflict/repo"
(cd "$TMP/popconflict/merger" && git pull -q origin main 2>/dev/null && echo upstream >> app.txt \
  && git commit -q -am upstream && git push -q origin main 2>/dev/null)
echo wip >> "$R/app.txt"
OUT="$(run "$R")"
stash_sha="$(git -C "$R" rev-parse --short=7 refs/stash 2>/dev/null)"
[ "$(field "$OUT" stash)" = pop_failed ] && [ "$(field "$OUT" ok)" = false ] && [ -n "$stash_sha" ] \
  && echo "$OUT" | grep -q "conflicted in app.txt" && echo "$OUT" | grep -q "$stash_sha" \
  && echo "$OUT" | grep -q 'reset --merge' && [ "$(git -C "$R" stash list | wc -l | tr -d ' ')" = 1 ]
check "P2 stash pop conflict: ok false, the conflicted path and the kept stash named" "$?"

# ── P3: degrade paths ────────────────────────────────────────
fixture ghdown
R="$TMP/ghdown/repo"
FAKE_GH_EXIT=1 run "$R" >/dev/null 2>&1; EC=$?
[ "$EC" = 4 ] && [ "$(on_branch "$R")" = "$BRANCH" ] && has_branch "$R"
check "P3: gh failing is exit 4 and nothing changed" "$?"
mkdir -p "$TMP/norepo"
(cd "$TMP/norepo" && python3 "$SCRIPT" --pr 42 >/dev/null 2>&1); [ "$?" = 4 ]
check "P3: outside a repository is exit 4" "$?"

# ── P4: wiring ───────────────────────────────────────────────
DOC="$REPO_ROOT/docs/post-merge-cleanup.md"
[ -f "$DOC" ]; check "P4: docs/post-merge-cleanup.md is the runtime doc for the cleanup" "$?"
[ -z "$(grep -- '--force' "$DOC" | grep -v 'only after the user confirms (never in auto mode)')" ]
check "P4: the prose fallback forces a worktree removal only after the user confirms, never in auto mode" "$?"
grep -q 'status --porcelain --untracked-files=all --ignored' "$DOC" && grep -q 'absolute-git-dir' "$DOC" \
  && grep -q 'locked' "$DOC" && grep -q 'diff-filter=U' "$DOC"
check "P4: the fallback probes untracked files, in-progress operations, locks, and a conflicting pop" "$?"
grep -q 'git branch -D' "$DOC" && grep -q 'headRefOid' "$DOC" && grep -q 'merged_head' "$DOC"
check "P4: the fallback deletes a squash-merged branch only against the merged head" "$?"
for skill in issue-analysis issue-creator issue-triage issue-resolver; do
  [ ! -f "$REPO_ROOT/skills/$skill/references/docs/post-merge-cleanup.md" ]
  check "P4: $skill (it merges nothing) does not carry the cleanup doc" "$?"
done
for skill in issue-pr-review auto-pilot; do
  BUILT="$REPO_ROOT/skills/$skill"
  cmp -s "$SCRIPT" "$BUILT/references/scripts/gi-postmerge.py"
  check "P4: $skill bundles gi-postmerge.py byte-identical to the source" "$?"
  grep -qE '^(- )?`?references/scripts/gi-postmerge\.py`?' "$BUILT/SKILL.md"
  check "P4: $skill's precheck list names the script" "$?"
done
PR_SRC="$REPO_ROOT/src/skills/issue-pr-review"
grep -q 'shared/scripts/gi-postmerge.py --pr {N}' "$PR_SRC/references/report-templates.md"
check "P4: issue-pr-review runs the cleanup after its auto-merge" "$?"
grep -q 'already merged' "$PR_SRC/SKILL.source.md" && grep -q 'gi-postmerge' "$PR_SRC/SKILL.source.md"
check "P4: issue-pr-review cleans up a PR that is already merged" "$?"
AP_MERGE="$REPO_ROOT/src/skills/auto-pilot/references/phases/phase-5-merge.md"
[ "$(grep -c 'shared/scripts/gi-postmerge.py --pr {pr_number}' "$AP_MERGE")" -ge 2 ]
check "P4: auto-pilot Step 5.3 runs the cleanup on both the sequential and parallel paths" "$?"
grep -q 'state --jq .state' "$AP_MERGE"
check "P4: auto-pilot reconciles a non-zero merge exit against the PR state" "$?"
[ "$(grep -c 'shared/scripts/gi-postmerge.py --pr {pr_number} --delete-remote' "$AP_MERGE")" -ge 2 ] \
  && grep -q 'shared/scripts/gi-postmerge.py --pr {N} --delete-remote' "$PR_SRC/references/report-templates.md"
check "P4: a reconciled merge runs the cleanup with --delete-remote (both skills, both auto-pilot paths)" "$?"
grep -q 'Delete these {n} untracked files and remove worktree {path}? \[y/N\]' "$PR_SRC/references/report-templates.md" \
  && grep -q -- '--remove-worktree "$wt"' "$PR_SRC/references/report-templates.md"
check "P4: issue-pr-review asks before deleting untracked files (default No)" "$?"
! grep -q -- '--remove-worktree "' "$AP_MERGE" && grep -q 'pass `--remove-worktree`' "$AP_MERGE"
check "P4: auto-pilot never passes --remove-worktree" "$?"
grep -q 'if \[ -z "$(git -C "$wt_dir" status --porcelain --untracked-files=all --ignored)" \]; then' "$AP_MERGE" \
  && ! grep -q -- 'worktree remove .*--force' "$AP_MERGE"
check "P4: auto-pilot removes a lane worktree only when the --untracked-files=all --ignored probe is empty, never forced" "$?"
grep -q 'gi-postmerge\|/issue-pr-review {pr_number}' \
  "$REPO_ROOT/src/skills/issue-resolver/references/steps/step-0-preflight.md"
check "P4: the resolver's kept-worktree note points at the post-merge cleanup" "$?"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
