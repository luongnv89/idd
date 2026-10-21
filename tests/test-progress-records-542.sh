#!/usr/bin/env bash
# test-progress-records-542.sh — durable progress records so a killed resolver
# or reviewer session can resume (issue #542).
#
# shared/scripts/gi-progress.py keeps one record per skill + number under the git
# common dir. A record is a hint, never an authority: it saves repeated work and
# never satisfies a safety gate. This file pins:
#
#   S1   script hygiene: 0755, --help, stdlib-only, the exit-code contract;
#   S2   the store: common dir, shared by worktrees, modes 0700/0600;
#   S3   the binding verdict against live git, and the read statuses;
#   S4   closed keys, transitions and monotone counters (exit 3, nothing written);
#   S5   clear, list, usage and degrade exits; injection-shaped text stays data;
#   S6   the prose contract in the built skills, and the ADR amendment.
#
# The sensitive-change gate's test obligations are named after their probe ids
# (p4 … p15b), so `grep -n 'p7-' tests/test-progress-records-542.sh` finds the
# case that discharges p7.
#
# Usage: bash tests/test-progress-records-542.sh
# Returns: exit 0 if all checks pass, exit 1 on failure.

# No `set -e`: assertions report and continue.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/src/shared/scripts/gi-progress.py"
SKILLS="$REPO_ROOT/skills"
RS="$SKILLS/issue-resolver"
RV="$SKILLS/issue-pr-review"
AP="$SKILLS/auto-pilot"
ADR="$REPO_ROOT/docs/decisions/context-threshold-durable-handoff.md"
WORKFLOW="$REPO_ROOT/.github/workflows/dist-check.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A lane environment leaking in from the caller would change every binding.
unset IDD_CALLER_WORKTREE IDD_LANE_ID IDD_EVENT_ID IDD_BASE_SHA IDD_WORKTREE_PATH \
      IDD_RESUME_LANE GIT_DIR GIT_WORK_TREE

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "0" ]; then pass "$1"; else fail "$1"; fi; }

# shellcheck source=lib/anchors.bash
. "$REPO_ROOT/tests/lib/anchors.bash"

echo "◆ Durable progress records (#542)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# new_repo DIR [BRANCH] — a repository with one commit, on BRANCH when given.
new_repo() {
  git init -q -b main "$1"
  git -C "$1" -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false \
    commit -q --allow-empty -m one
  [ -z "${2:-}" ] || git -C "$1" checkout -q -b "$2"
}
commit_in() {  # commit_in DIR MESSAGE — an empty commit
  git -C "$1" -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false \
    commit -q --allow-empty -m "$2"
}
# gp DIR ARGS... — run the script from DIR, stdin passed through; sets RC/OUT.
gp() {
  local dir="$1"; shift
  RC=0
  OUT="$(cd "$dir" && python3 "$SCRIPT" "$@" 2>"$TMP/err")" || RC=$?
}
# put DIR MODE SKILL N JSON — --start/--write with a patch on stdin.
put() {
  local dir="$1" mode="$2" skill="$3" n="$4" patch="$5"
  RC=0
  OUT="$(cd "$dir" && printf '%s' "$patch" | python3 "$SCRIPT" "--$mode" --skill "$skill" --number "$n" 2>"$TMP/err")" || RC=$?
}
# js EXPR — evaluate a Python expression over the JSON in $OUT (bound to d).
js() { printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1" 2>/dev/null; }

# ─── S1: hygiene ─────────────────────────────────────────────────────────────
[ -x "$SCRIPT" ]; check "S1a gi-progress.py exists and is executable" "$?"
python3 "$SCRIPT" --help >/dev/null 2>&1; check "S1b --help exits 0" "$?"
BAD_IMPORTS="$(python3 - "$SCRIPT" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
mods = set()
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        mods |= {a.name.split(".")[0] for a in node.names}
    elif isinstance(node, ast.ImportFrom) and node.module:
        mods.add(node.module.split(".")[0])
print(" ".join(sorted(m for m in mods if m not in sys.stdlib_module_names)))
PY
)"
[ -z "$BAD_IMPORTS" ]; check "S1c stdlib-only imports${BAD_IMPORTS:+ (found: $BAD_IMPORTS)}" "$?"
DOC="$(python3 -c 'import ast,sys; print(ast.get_docstring(ast.parse(open(sys.argv[1]).read())))' "$SCRIPT")"
printf '%s' "$DOC" | grep -qF 'never exits 1' \
  && printf '%s' "$DOC" | grep -qF 'A record is a hint, never an authority' \
  && printf '%s' "$DOC" | grep -qF 'Authored at src/shared/scripts/gi-progress.py' \
  && pass "S1d the docstring states the exit contract, the hint rule and the source path" \
  || fail "S1d docstring contract incomplete"

# ─── S2: the store ───────────────────────────────────────────────────────────
R="$TMP/store"; new_repo "$R" feat/7-store
put "$R" start issue-resolver 7 '{"step": 0, "base": "main"}'
COMMON="$(cd "$R" && python3 -c 'import os,subprocess; print(os.path.realpath(subprocess.check_output(["git","rev-parse","--git-common-dir"],text=True).strip()))')"
WANT="$COMMON/idd/progress/issue-resolver-7.json"
[ "$RC" = 0 ] && [ "$(js 'd["path"]')" = "$WANT" ] && [ -f "$WANT" ]
check "S2a --start writes <git common dir>/idd/progress/issue-resolver-7.json (rc=$RC)" "$?"
DMODE="$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$COMMON/idd/progress")"
FMODE="$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$WANT")"
[ "$DMODE" = "0o700" ] && [ "$FMODE" = "0o600" ]; check "S2b store dir 0700, record 0600 (got $DMODE/$FMODE)" "$?"
git -C "$R" worktree add -q "$TMP/store-wt" -b feat/8-wt 2>/dev/null
put "$TMP/store-wt" start issue-resolver 8 '{}'
[ "$RC" = 0 ] && [ "$(js 'd["path"]')" = "$COMMON/idd/progress/issue-resolver-8.json" ]
check "S2c a linked worktree writes into the same common-dir store" "$?"

# ─── p5b: a lane path given through an `ln -s` parent still binds ────────────
# The record is written with the physical spelling of the lane path and read
# back with a spelling through a symlinked parent. Only a script that realpaths
# IDD_WORKTREE_PATH on both sides sees the same lane.
mkdir -p "$TMP/real"; ln -s "$TMP/real" "$TMP/link"
L="$TMP/real/lane-repo"; new_repo "$L"
git -C "$L" worktree add -q "$TMP/real/lane-wt" -b feat/9-lane 2>/dev/null
BASE_SHA="$(git -C "$L" rev-parse HEAD)"
PHYS_WT="$(cd "$TMP/real/lane-wt" && pwd -P)"
lane_env() { IDD_CALLER_WORKTREE=1 IDD_LANE_ID=run-1:9 IDD_EVENT_ID=run-1:9 IDD_BASE_SHA="$BASE_SHA" IDD_WORKTREE_PATH="$1" "${@:2}"; }
RC=0; OUT="$(cd "$PHYS_WT" && printf '{"step": 0}' | lane_env "$PHYS_WT" python3 "$SCRIPT" --start --skill issue-resolver --number 9 2>"$TMP/err")" || RC=$?
[ "$RC" = 0 ]; st=$?; check "p5b-lane-symlink: a lane record is written under IDD_CALLER_WORKTREE=1 (rc=$RC $(cat "$TMP/err"))" "$st"
RC=0; OUT="$(cd "$TMP/link/lane-wt" && lane_env "$TMP/link/lane-wt" python3 "$SCRIPT" --read --skill issue-resolver --number 9 2>"$TMP/err")" || RC=$?
[ "$RC" = 0 ] && [ "$(js 'd["binding"]["lane_match"]')" = "True" ] \
  && [ "$(js 'd["binding"]["workspace"]')" = "here" ] && [ "$(js 'd["binding"]["verdict"]')" = "bound" ]
st=$?  # captured before the label's command substitution resets it
check "p5b-lane-symlink: IDD_WORKTREE_PATH through an ln -s parent yields lane_match, here, bound (got $(js 'd["binding"]'))" "$st"
RC=0; OUT="$(cd "$TMP/link/lane-wt" && IDD_CALLER_WORKTREE=1 IDD_LANE_ID=run-2:9 IDD_EVENT_ID=run-1:9 IDD_BASE_SHA="$BASE_SHA" \
  IDD_WORKTREE_PATH="$TMP/link/lane-wt" python3 "$SCRIPT" --read --skill issue-resolver --number 9 2>"$TMP/err")" || RC=$?
[ "$(js 'd["binding"]["lane_match"]')" = "False" ] && [ "$(js 'd["binding"]["verdict"]')" = "stale" ]
check "p5b-lane-symlink: control — another lane id is lane_match false, stale" "$?"
# The same symlinked parent for the workspace verdicts (B6): `here` from the
# worktree, `elsewhere` from the main checkout, both reached through the link.
RC=0; OUT="$(cd "$TMP/link/lane-wt" && printf '{"step": 0}' | python3 "$SCRIPT" --start --skill issue-resolver --number 10 2>"$TMP/err")" || RC=$?
gp "$TMP/link/lane-wt" --read --skill issue-resolver --number 10
[ "$(js 'd["binding"]["workspace"]')" = "here" ]; check "p5b-lane-symlink: here from the worktree through the link" "$?"
gp "$TMP/link/lane-repo" --read --skill issue-resolver --number 10
[ "$(js 'd["binding"]["workspace"]')" = "elsewhere" ] && [ "$(js 'd["binding"]["worktree_path"]')" = "$PHYS_WT" ]
check "p5b-lane-symlink: elsewhere from the main checkout, reported as the physical path" "$?"

# ─── p10: workspace verdicts for an in-place run that switched away ──────────
W="$TMP/ws"; new_repo "$W" feat/11-ws
printf 'x\n' > "$W/tracked.txt"
git -C "$W" add tracked.txt && commit_in "$W" tracked
put "$W" start issue-resolver 11 '{"step": 3}'
git -C "$W" checkout -q main
gp "$W" --read --skill issue-resolver --number 11
[ "$(js 'd["binding"]["workspace"]')" = "branch_only" ] && [ "$(js 'd["binding"]["dirty"]')" = "False" ] \
  && [ "$(js 'd["binding"]["verdict"]')" = "bound" ]
st=$?  # captured before the label's command substitution resets it
check "p10-workspace-verdicts: S2 in place, switched to main, clean → branch_only, resumable (got $(js 'd["binding"]'))" "$st"
printf 'dirty\n' > "$W/untracked-host.txt"
gp "$W" --read --skill issue-resolver --number 11
[ "$(js 'd["binding"]["workspace"]')" = "branch_only" ] && [ "$(js 'd["binding"]["dirty"]')" = "True" ] \
  && [ "$(js 'd["binding"]["verdict"]')" = "stale" ] && [ "$(js '"dirty" in d["binding"]["reasons"]')" = "True" ]
check "p10-workspace-verdicts: S3 branch switched, dirty host → branch_only + dirty → stale" "$?"
rm -f "$W/untracked-host.txt"
git -C "$W" branch -q -D feat/11-ws
gp "$W" --read --skill issue-resolver --number 11
[ "$RC" = 0 ] && [ "$(js 'd["binding"]["workspace"]')" = "missing" ] && [ "$(js 'd["binding"]["verdict"]')" = "stale" ]
check "p10-workspace-verdicts: a deleted branch is missing → stale (rc=$RC)" "$?"

# ─── p14: machine-local .idd/ and legacy .gitissue/ never make it dirty ─────
D="$TMP/dirty"; new_repo "$D" feat/12-dirty
printf 'a\n' > "$D/tracked.txt"; mkdir -p "$D/.idd"; printf '{}\n' > "$D/.idd/config-note.json"
git -C "$D" add tracked.txt .idd/config-note.json && commit_in "$D" tracked
put "$D" start issue-resolver 12 '{"step": 1}'
mkdir -p "$D/.idd/cache" "$D/.gitissue"
printf 'lock\n' > "$D/.idd/run.lock"; printf '{}\n' > "$D/.idd/run-state.json"
printf 'x\n' > "$D/.idd/cache/x"; printf 'lock\n' > "$D/.gitissue/run.lock"
gp "$D" --read --skill issue-resolver --number 12
[ ! -e "$D/.gitignore" ] && [ "$(js 'd["binding"]["dirty"]')" = "False" ] && [ "$(js 'd["binding"]["verdict"]')" = "bound" ]
check "p14-idd-untracked-ignored: untracked .idd/ and .gitissue/ entries leave dirty false (no .gitignore)" "$?"
printf 'b\n' > "$D/tracked.txt"
gp "$D" --read --skill issue-resolver --number 12
[ "$(js 'd["binding"]["dirty"]')" = "True" ] && [ "$(js 'd["binding"]["verdict"]')" = "stale" ]
check "p14-idd-untracked-ignored: a tracked edit is dirty (stale at step 1)" "$?"
git -C "$D" checkout -q -- tracked.txt; printf '{"x": 1}\n' > "$D/.idd/config-note.json"
gp "$D" --read --skill issue-resolver --number 12
[ "$(js 'd["binding"]["dirty"]')" = "True" ]
check "p14-idd-untracked-ignored: a tracked file under .idd/ still counts as dirty" "$?"

# ─── S3: binding against live git, and the read statuses ─────────────────────
B="$TMP/bind"; new_repo "$B" feat/13-bind
put "$B" start issue-resolver 13 '{"step": 1}'
commit_in "$B" ahead
gp "$B" --read --skill issue-resolver --number 13
[ "$(js 'd["binding"]["head_relation"]')" = "descendant" ] && [ "$(js 'd["binding"]["verdict"]')" = "stale" ] \
  && [ "$(js '"moved" in d["binding"]["reasons"]')" = "True" ]
check "S3a a descendant HEAD at a step that does not commit (1) is stale" "$?"
put "$B" start issue-resolver 13 '{"step": 3}'
commit_in "$B" ahead-again
gp "$B" --read --skill issue-resolver --number 13
[ "$(js 'd["binding"]["head_relation"]')" = "descendant" ] && [ "$(js 'd["binding"]["verdict"]')" = "bound" ]
check "S3b a descendant HEAD while Step 3 was in flight is bound" "$?"
git -C "$B" checkout -q --orphan unrelated && commit_in "$B" orphan && git -C "$B" branch -q -f feat/13-bind HEAD \
  && git -C "$B" checkout -q feat/13-bind
gp "$B" --read --skill issue-resolver --number 13
[ "$(js 'd["binding"]["head_relation"]')" = "other" ] && [ "$(js 'd["binding"]["verdict"]')" = "stale" ]
check "S3c an unrelated HEAD is other → stale" "$?"
put "$B" start issue-resolver 13 '{"step": 2}'
REC="$(js 'd["path"]')"
python3 - "$REC" <<'PY'
import json, sys
p = sys.argv[1]; r = json.load(open(p)); r["executor"]["host"] = "elsewhere.invalid"; json.dump(r, open(p, "w"))
PY
gp "$B" --read --skill issue-resolver --number 13
[ "$RC" = 0 ] && [ "$(js 'd["binding"]["executor_match"]')" = "False" ] && [ "$(js 'd["binding"]["verdict"]')" = "stale" ]
check "S3d a record written on another host is stale" "$?"
python3 - "$REC" <<'PY'
import json, sys
p = sys.argv[1]; r = json.load(open(p)); r["updated_at"] = "2001-01-01T00:00:00Z"; json.dump(r, open(p, "w"))
PY
gp "$B" --read --skill issue-resolver --number 13
[ "$RC" = 0 ] && [ "$(js 'd["status"]')" = "expired" ] && [ "$(js 'd["record"]')" = "None" ]
check "S3e a record not written for seven days is expired, with no record" "$?"
printf 'not json' > "$REC"
gp "$B" --read --skill issue-resolver --number 13
[ "$RC" = 0 ] && [ "$(js 'd["status"]')" = "corrupt" ]; check "S3f garbage is corrupt, exit 0" "$?"
rm -f "$REC"; ln -s /etc/hosts "$REC"
gp "$B" --read --skill issue-resolver --number 13
[ "$RC" = 0 ] && [ "$(js 'd["status"]')" = "corrupt" ]; check "S3g a symlinked record is corrupt, never followed" "$?"
rm -f "$REC"
gp "$B" --read --skill issue-resolver --number 13
[ "$RC" = 0 ] && [ "$(js 'd["status"]')" = "absent" ] && [ "$(js 'd["binding"]')" = "None" ]
check "S3h no record is absent, exit 0" "$?"
put "$B" start issue-resolver 13 '{"step": 2, "plan": {"overall_risk": "High"}}'
python3 - "$(js 'd["path"]')" <<'PY'
import json, sys
p = sys.argv[1]; r = json.load(open(p)); r["qa_handoff"] = "trusted"; json.dump(r, open(p, "w"))
PY
gp "$B" --read --skill issue-resolver --number 13
[ "$(js 'd["status"]')" = "corrupt" ]; check "S3i a hand-added forbidden key makes the record corrupt" "$?"

# ─── p6: every forbidden key is refused, and nothing is written ──────────────
FORBIDDEN="$(python3 -c 'import json,runpy,sys; print(" ".join(sorted(runpy.run_path(sys.argv[1])["FORBIDDEN_KEYS"])))' "$SCRIPT")"
MISSING_FLOOR=""
for key in tests_state tests qa_handoff review receipt marker qa_clean verdict ci_sha verified_head \
           head branch toplevel executor lane completed; do
  case " $FORBIDDEN " in *" $key "*) ;; *) MISSING_FLOOR="$MISSING_FLOOR $key" ;; esac
done
[ -n "$FORBIDDEN" ] && [ -z "$MISSING_FLOOR" ]
check "p6-forbidden-keys: FORBIDDEN_KEYS holds the 16-key floor${MISSING_FLOOR:+ (missing:$MISSING_FLOOR)}" "$?"
F="$TMP/forbid"; new_repo "$F" feat/14-forbid
ACCEPTED=""
for key in $FORBIDDEN; do
  put "$F" start issue-resolver 14 "{\"$key\": \"x\"}"
  [ "$RC" = 3 ] && [ ! -e "$F/.git/idd/progress/issue-resolver-14.json" ] || ACCEPTED="$ACCEPTED start:$key(rc=$RC)"
done
put "$F" start issue-resolver 15 '{"step": 0}'
BEFORE="$(cat "$F/.git/idd/progress/issue-resolver-15.json")"
for key in $FORBIDDEN; do
  put "$F" write issue-resolver 15 "{\"$key\": \"x\"}"
  [ "$RC" = 3 ] && [ "$(cat "$F/.git/idd/progress/issue-resolver-15.json")" = "$BEFORE" ] || ACCEPTED="$ACCEPTED write:$key(rc=$RC)"
  put "$F" start issue-pr-review 15 "{\"$key\": \"x\"}"
  [ "$RC" = 3 ] && [ ! -e "$F/.git/idd/progress/issue-pr-review-15.json" ] || ACCEPTED="$ACCEPTED reviewer:$key(rc=$RC)"
done
[ -z "$ACCEPTED" ]
st=$?  # captured before the label's command substitution resets it
check "p6-forbidden-keys: each of $(printf '%s' "$FORBIDDEN" | wc -w | tr -d ' ') keys exits 3 and writes nothing${ACCEPTED:+ —$ACCEPTED}" "$st"
put "$F" write issue-resolver 15 '{"qa": {"cycle": 1, "tests_state": "3@x"}}'
[ "$RC" = 3 ] && [ "$(cat "$F/.git/idd/progress/issue-resolver-15.json")" = "$BEFORE" ]
check "p6-forbidden-keys: a forbidden key nested in qa is refused too" "$?"

# ─── S4: closed keys, transitions, counters ──────────────────────────────────
refused() {  # refused LABEL SKILL N PATCH — exit 3 and a byte-identical record
  local before; before="$(cat "$F/.git/idd/progress/$2-$3.json" 2>/dev/null)"
  put "$F" write "$2" "$3" "$4"
  [ "$RC" = 3 ] && [ "$(cat "$F/.git/idd/progress/$2-$3.json" 2>/dev/null)" = "$before" ]
  check "S4 $1 → exit 3, nothing written (rc=$RC)" "$?"
}
put "$F" write issue-resolver 15 '{"step": 1, "profile": "full"}'
refused "an unknown key" issue-resolver 15 '{"step_name": "x"}'
refused "a reviewer key on a resolver record" issue-resolver 15 '{"findings": {"open": []}}'
refused "an illegal forward jump (1 → 3)" issue-resolver 15 '{"step": 3}'
refused "profile full → light" issue-resolver 15 '{"profile": "light"}'
refused "a branch with shell metacharacters" issue-resolver 15 '{"effect": {"kind": "pr_create", "state": "intent", "key": {"branch": "feat/1-$(touch x)"}}}'
refused "an unknown effect kind" issue-resolver 15 '{"effect": {"kind": "label", "state": "intent", "key": {}}}'
refused "a malformed SHA" issue-resolver 15 '{"effect": {"kind": "push", "state": "intent", "key": {"sha": "abc"}}}'
refused "resume that is not a boolean" issue-resolver 15 '{"resume": "yes"}'
BIG="$(python3 -c 'import json; print(json.dumps({"research": {"blob": "x" * 70000}}))')"
refused "research over 64 KiB" issue-resolver 15 "$BIG"
refused "a non-object patch" issue-resolver 15 '[1, 2]'
put "$F" start issue-resolver 16 '{"resume": true}'
[ "$RC" = 3 ]; check "S4 resume on --start → exit 3" "$?"

# ─── p7: the resume re-walk is legal end to end; counters only grow ──────────
K="$TMP/rewalk"; new_repo "$K" feat/17-rewalk
walk() {  # walk SKILL N PATCH... — every write must exit 0
  local skill="$1" n="$2" bad=""; shift 2
  for p in "$@"; do put "$K" write "$skill" "$n" "$p"; [ "$RC" = 0 ] || bad="$bad $p(rc=$RC $(cat "$TMP/err"))"; done
  printf '%s' "$bad"
}
put "$K" start issue-resolver 17 '{"step": 0}'
BAD="$(walk issue-resolver 17 '{"step": 1}' '{"step": 2}' '{"step": 3}')"
BAD="$BAD$(walk issue-resolver 17 '{"resume": true}' '{"step": 1}' '{"step": 3}' '{"step": 4}' '{"step": 5}' '{"step": "closing", "outcome": "success"}')"
[ -z "$BAD" ]; check "p7-rewalk-kill-twice: resolver resumed at step 3 writes exit 0 end to end${BAD:+ —$BAD}" "$?"
put "$K" start issue-resolver 18 '{"step": 0}'
BAD="$(walk issue-resolver 18 '{"step": 1}' '{"step": 2}' '{"step": 3}' '{"step": 4, "qa": {"cycle": 1}}')"
BAD="$BAD$(walk issue-resolver 18 '{"resume": true}' '{"step": 1}' '{"step": 2}' '{"step": 3}' '{"step": 4, "qa": {"cycle": 2}}' '{"step": 5}' '{"step": "closing"}')"
[ -z "$BAD" ]; check "p7-rewalk-kill-twice: resolver resumed at step 4 writes exit 0 end to end${BAD:+ —$BAD}" "$?"
put "$K" start issue-pr-review 19 '{"step": 1}'
BAD="$(walk issue-pr-review 19 '{"step": 2}' '{"step": 3, "cycle": 1}' '{"step": 4}' '{"step": 5}')"
BAD="$BAD$(walk issue-pr-review 19 '{"resume": true}' '{"step": 1}' '{"step": 3, "cycle": 2}' '{"step": 4}' '{"step": 5}' '{"step": 6}' '{"step": 3, "cycle": 3}' '{"step": 4}' '{"step": 5}' '{"step": 6}' '{"step": 7}' '{"step": "closing", "outcome": "PASS"}')"
[ -z "$BAD" ]; check "p7-rewalk-kill-twice: reviewer resumed at step 5 (with a 6 → 3 loop) writes exit 0 end to end${BAD:+ —$BAD}" "$?"
put "$K" start issue-pr-review 20 '{"step": 1}'
BAD="$(walk issue-pr-review 20 '{"step": 2}' '{"step": 3, "cycle": 1}' '{"step": 4}' '{"step": 5}' '{"step": 6}' '{"step": 7}')"
BAD="$BAD$(walk issue-pr-review 20 '{"resume": true}' '{"step": 1}' '{"step": 3, "cycle": 2}' '{"step": 4}' '{"step": 5}' '{"step": 7}' '{"step": "closing", "outcome": "MERGED"}')"
[ -z "$BAD" ]; check "p7-rewalk-kill-twice: reviewer resumed at step 7 writes exit 0 end to end${BAD:+ —$BAD}" "$?"
# Kill twice: each resumed session keeps growing the cycle and the ledger.
E1='{"kind": "failure", "cycle": 1, "premise_id": "p1", "premise": "cache key"}'
E2='{"kind": "failure", "cycle": 2, "premise_id": "p1", "premise": "cache key again"}'
put "$K" start issue-resolver 21 '{"step": 0}'
BAD="$(walk issue-resolver 21 '{"step": 1}' '{"step": 2}' '{"step": 3}' '{"step": 4, "qa": {"cycle": 1}}' "{\"qa\": {\"cycle\": 2, \"premise_ledger\": [$E1]}}")"
BAD="$BAD$(walk issue-resolver 21 '{"resume": true}' '{"step": 1}' '{"step": 2}' '{"step": 3}' '{"step": 4}' "{\"qa\": {\"cycle\": 3, \"premise_ledger\": [$E1, $E2]}}")"
BAD="$BAD$(walk issue-resolver 21 '{"resume": true}' '{"step": 1}')"
gp "$K" --read --skill issue-resolver --number 21
[ -z "$BAD" ] && [ "$(js 'd["record"]["qa"]["cycle"]')" = 3 ] && [ "$(js 'len(d["record"]["qa"]["premise_ledger"])')" = 2 ] \
  && [ "$(js 'd["record"]["step"]')" = 4 ] && [ "$(js 'd["record"]["resumed"]')" = 2 ]
check "p7-rewalk-kill-twice: after two kills --read shows cycle 3, a ledger of 2, high-water step 4, resumed 2${BAD:+ —$BAD}" "$?"
BEFORE="$(cat "$K/.git/idd/progress/issue-resolver-21.json")"
put "$K" write issue-resolver 21 '{"qa": {"cycle": 2}}'
RC1=$RC
put "$K" write issue-resolver 21 "{\"qa\": {\"premise_ledger\": [$E2]}}"
[ "$RC1" = 3 ] && [ "$RC" = 3 ] && [ "$(cat "$K/.git/idd/progress/issue-resolver-21.json")" = "$BEFORE" ]
check "p7-rewalk-kill-twice: lowering the cycle or shrinking the ledger exits 3 and writes nothing" "$?"
put "$K" write issue-pr-review 19 '{"cycle": 1}'
[ "$RC" = 3 ]; check "p7-rewalk-kill-twice: the reviewer cycle cannot decrease either" "$?"

# ─── p8: --list on an absent store; numbers are integers ─────────────────────
LS="$TMP/list"; new_repo "$LS"
gp "$LS" --list
[ "$RC" = 0 ] && [ "$OUT" = '{"records": []}' ] && [ ! -e "$LS/.git/idd" ]
check "p8-list-absent: an absent store prints {\"records\": []}, exit 0, and creates nothing (got '$OUT')" "$?"
put "$LS" start issue-resolver 22 '{}'
put "$LS" start issue-pr-review 87 '{}'
printf 'junk' > "$LS/.git/idd/progress/issue-resolver-x.json"
gp "$LS" --list
[ "$RC" = 0 ] && [ "$(js 'all(type(r["number"]) is int for r in d["records"])')" = "True" ] \
  && [ "$(js 'sorted((r["skill"], r["number"]) for r in d["records"])')" = "[('issue-pr-review', 87), ('issue-resolver', 22)]" ]
check "p8-list-absent: --list rows carry integer numbers and skip names outside the grammar" "$?"

# ─── p15 / p15b: caller_run_id is screened, stored, listed — and restamped ───
C="$TMP/runid"; new_repo "$C" feat/23-runid
put "$C" start issue-resolver 23 '{"caller_run_id": "bad id; rm -rf /"}'
[ "$RC" = 3 ] && [ ! -e "$C/.git/idd/progress/issue-resolver-23.json" ]
check "p15-caller-run-id: a malformed caller_run_id exits 3, nothing written" "$?"
put "$C" start issue-resolver 23 '{"caller_run_id": "20261021T120000Z-4242"}'
gp "$C" --read --skill issue-resolver --number 23
R1="$(js 'd["record"]["caller_run_id"]')"
gp "$C" --list
[ "$R1" = "20261021T120000Z-4242" ] && [ "$(js 'd["records"][0]["caller_run_id"]')" = "20261021T120000Z-4242" ]
check "p15-caller-run-id: caller_run_id round-trips through --read and --list" "$?"
put "$C" write issue-resolver 23 '{"step": 1, "caller_run_id": "20261021T120000Z-9999"}'
[ "$RC" = 3 ]; check "p15-caller-run-id: an ordinary write cannot change the stamp" "$?"
put "$C" write issue-resolver 23 '{"resume": true}'
gp "$C" --list
[ "$(js 'd["records"][0]["caller_run_id"]')" = "None" ]
check "p15b-restamp-on-resume: a resume:true write without caller_run_id nulls the stamp" "$?"
put "$C" write issue-resolver 23 '{"resume": true, "caller_run_id": "20261022T000000Z-7"}'
gp "$C" --list
[ "$(js 'd["records"][0]["caller_run_id"]')" = "20261022T000000Z-7" ]
check "p15b-restamp-on-resume: a resume:true write with caller_run_id takes the new holder's stamp" "$?"

# ─── S5: clear, usage and degrade exits; text stays data ─────────────────────
gp "$C" --clear --skill issue-resolver --number 23
FIRST="$(js 'd["cleared"]')"
gp "$C" --clear --skill issue-resolver --number 23
[ "$FIRST" = "True" ] && [ "$(js 'd["cleared"]')" = "False" ] && [ "$RC" = 0 ]
check "S5a --clear removes the record and is idempotent" "$?"
put "$C" write issue-resolver 23 '{"step": 1}'
[ "$RC" = 4 ]; check "S5b --write with no record exits 4" "$?"
mkdir -p "$TMP/norepo"
gp "$TMP/norepo" --read --skill issue-resolver --number 1
[ "$RC" = 4 ]; check "S5c outside a git repository exits 4" "$?"
gp "$C" --read --skill issue-analysis --number 1; RC1=$RC
gp "$C" --read --skill issue-resolver --number 0; RC2=$RC
gp "$C" --read --skill issue-resolver; RC3=$RC
gp "$C" --list --skill issue-resolver --number 1
[ "$RC1" = 2 ] && [ "$RC2" = 2 ] && [ "$RC3" = 2 ] && [ "$RC" = 2 ]
check "S5d a bad --skill, --number 0, a missing --number, or --list with a key exit 2" "$?"
INJ='{"step": 0, "plan": {"selected": {"name": "x", "summary": "$(touch pwned) `touch pwned2`; rm -rf ~"}}}'
put "$C" start issue-resolver 24 "$INJ"
gp "$C" --read --skill issue-resolver --number 24
[ "$(js 'd["record"]["plan"]["selected"]["summary"]')" = '$(touch pwned) `touch pwned2`; rm -rf ~' ] \
  && [ ! -e "$C/pwned" ] && [ ! -e "$C/pwned2" ]
check "S5e a summary carrying \$(…) and backticks is stored verbatim and runs nothing" "$?"
for i in 1 2 3 4 5 6 7 8; do
  (cd "$C" && printf '{"step": 0, "qa": {"cycle": %s}}' "$i" | python3 "$SCRIPT" --write --skill issue-resolver --number 24 >/dev/null 2>&1) &
done
wait
gp "$C" --read --skill issue-resolver --number 24
[ "$(js 'd["status"]')" = "ok" ]; check "S5f concurrent writers leave a parseable record" "$?"

# ─── S6: the prose contract in the built skills ──────────────────────────────
# p4: the CI step is one plain name/run pair (the gate's CI-shape obligation).
if python3 - "$WORKFLOW" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
hits = [i for i, l in enumerate(lines) if l.strip() == "- name: test-progress-records-542"]
runs = [l for l in lines if "tests/test-progress-records-542.sh" in l]
build = [i for i, l in enumerate(lines) if l.strip() == "run: ./scripts/build.sh"]
if len(hits) != 1 or len(runs) != 1 or not build or hits[0] < build[0]:
    sys.exit(1)
start = hits[0]
indent = len(lines[start]) - len(lines[start].lstrip())
block = [lines[start]]
for line in lines[start + 1:]:
    if line.strip() and len(line) - len(line.lstrip()) <= indent:
        break
    block.append(line)
keys = [l.strip().split(":", 1)[0] for l in block if l.strip()]
sys.exit(0 if keys == ["- name", "run"] and block[1].strip() == "run: bash tests/test-progress-records-542.sh" else 1)
PY
then pass "p4-ci-step-only-runs-suite: dist-check.yml runs the suite as one plain name/run step, no env/secrets/with"
else fail "p4-ci-step-only-runs-suite: the step is missing, duplicated, misplaced, or carries extra keys"
fi

# p9: a cross-repository PR is never this run's own.
anchor_check_flat "$RS" rs-0j-reconcile 'isCrossRepository' "p9-cross-repo: the resolver reconcile reads isCrossRepository"
anchor_check_flat "$RS" rs-0j-reconcile 'this run.s own only when [^.]*isCrossRepository: false.*Anything else.*returns .pr_in_progress.' \
  "p9-cross-repo: 0b ownership needs isCrossRepository false; anything else stays pr_in_progress"
anchor_check_flat "$RS" rs-0j-reconcile '[Cc]ross-repository PR.*returns .pr_in_progress.' \
  "p9-cross-repo: a cross-repository PR returns pr_in_progress"
anchor_check_flat "$RV" rvm-progress-reconcile 'isCrossRepository: false' \
  "p9-cross-repo: the reviewer's push and merge reconcile require isCrossRepository false"

# p11: a sensitive restored plan never resumes past Step 3.
anchor_check_flat "$RS" rs-0j-sensitive '\*\*A restored plan that classifies as sensitive never resumes past Step 3\.\*\*' \
  "p11-sensitive-clamp: a sensitive restored plan never resumes past Step 3"
anchor_check_flat "$RS" rs-0j-sensitive 'min\(recorded, 3\)' "p11-sensitive-clamp: the resume point is min(recorded, 3)"
anchor_check_flat "$RS" rs-0j-sensitive 're-derived at read time' "p11-sensitive-clamp: the clamp is re-derived at read time"
anchor_check_flat "$RS" rs-0j-sensitive 'fail closed' "p11-sensitive-clamp: a classifier that cannot run fails closed"

# p12: every write call removes its patch file on the same line, every exit path.
P12="$(python3 - "$RS" "$RV" <<'PY'
import pathlib, sys
calls, bad = 0, []
for pkg in sys.argv[1:]:
    root = pathlib.Path(pkg)
    for f in [root / "SKILL.md", *sorted((root / "references").rglob("*.md"))]:
        if "/references/docs/" in str(f) or "/references/agents/" in str(f):
            continue
        for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            if "gi-progress.py --write" in line or "gi-progress.py --start" in line:
                if "python3 " not in line:
                    continue
                calls += 1
                if "< .idd/cache/progress-patch.json" not in line \
                        or "rm -f .idd/cache/progress-patch.json" not in line \
                        or line.index("rm -f") < line.index("gi-progress.py"):
                    bad.append(f"{f.name}:{n}")
print(calls, " ".join(bad))
PY
)"
P12_CALLS="${P12%% *}"; P12_BAD="${P12#* }"
[ "${P12_CALLS:-0}" -ge 4 ] && [ -z "$P12_BAD" ]
check "p12-patch-cleanup: all $P12_CALLS --write/--start call lines read stdin from the patch and rm -f it after${P12_BAD:+ — bad: $P12_BAD}" "$?"
anchor_check_flat "$RS" rs-0j-writes 'every exit path' "p12-patch-cleanup: the resolver says the rm -f runs on every exit path"

# p13: the reviewer's resume scan takes its policy from the default branch.
anchor_region "$RV" rvm-progress-secscan > "$TMP/secscan-region.txt" 2>/dev/null || true
P13="$(python3 - "$TMP/secscan-region.txt" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
# The build renders the source token shared/scripts/ as references/scripts/.
want = re.compile(r'python3 (shared|references)/scripts/gi-secscan\.py --range "\$head_oid" --policy-ref "origin/\$\{base\}"')
scan = [i for i, l in enumerate(lines) if want.fullmatch(l.strip())]
if len(scan) != 1:
    print("scan line"); sys.exit()
before = lines[:scan[0]]
binds = [l.strip() for l in before if re.match(r"\s*base=", l)]
if binds != ['base="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"']:
    print("base binding"); sys.exit()
if any("baseRefName" in l for l in before if re.match(r"\s*\w+=", l)):
    print("baseRefName bound"); sys.exit()
if not any("head_oid" in l and "^[0-9a-f]{40}$" in l for l in before):
    print("head_oid check"); sys.exit()
print("ok")
PY
)"
[ "$P13" = "ok" ]
check "p13-default-branch-policy: base binds from defaultBranchRef, head_oid is checked, then the exact scan line (${P13:-no region})" "$?"
anchor_check_flat "$RV" rvm-progress-secscan 'never the PR.s .baseRefName.' "p13-default-branch-policy: prose refuses baseRefName"

# p15: auto-pilot binds a resume only on an equal caller_run_id.
P0="$AP/references/phases/phase-0-lock-resume.md"
anchor_check_flat "$P0" ap-step10-skill-resume 'gi-progress\.py --list' "p15-caller-run-id: Step 1.0 lists the records"
anchor_check_flat "$P0" ap-step10-skill-resume '.caller_run_id. equals the .run_id.' \
  "p15-caller-run-id: Step 1.0 binds only records whose caller_run_id equals this run's run_id"
anchor_check_flat "$P0" ap-step10-skill-resume 'null or different .caller_run_id.* stays unbound' \
  "p15-caller-run-id: a null or different stamp stays unbound"
anchor_check_flat "$P0" ap-step10-skill-resume 'whatever .compaction\.enabled. says' \
  "p15-caller-run-id: the listing does not depend on compaction.enabled"
PROMPTS="$AP/references/subagent-prompts.md"
RES_PROMPT="$(anchor_span "$PROMPTS" ap-resolver-spawn ap-reviewer-spawn || true)"
REV_PROMPT="$(anchor_span "$PROMPTS" ap-reviewer-spawn ap-analyzer-spawn || true)"
for which in RES_PROMPT REV_PROMPT; do
  block="${!which}"
  printf '%s\n' "$block" | grep -qF 'resume: {resume}' && printf '%s\n' "$block" | grep -qF 'run_id: {run_id}' \
    && printf '%s\n' "$block" | grep -qE 'pass --resume only when' \
    && pass "p15-caller-run-id: the ${which%_PROMPT} spawn prompt carries resume: {resume} and run_id: {run_id}" \
    || fail "p15-caller-run-id: the ${which%_PROMPT} spawn prompt lacks resume/run_id lines"
done
anchor_check_flat "$RS" rs-0j-restore 'nulls the stamp' "p15b-restamp-on-resume: the resolver states the restamp rule"
anchor_check_flat "$RV" rvm-progress-resume 'nulls the stamp' "p15b-restamp-on-resume: the reviewer states the restamp rule"

# The rest of the contract (AC1-AC5).
anchor_check_flat "$RS" rs-progress '[Nn]ever satisfies or skips a safety gate' "S6a resolver SKILL: a record never satisfies or skips a safety gate"
anchor_check_flat "$RV" rv-progress '[Nn]ever satisfies or skips a safety gate' "S6b reviewer SKILL: a record never satisfies or skips a safety gate"
anchor_check_flat "$RV" rv-progress '--review-only' "S6c reviewer SKILL: --review-only never reads or writes a record"
anchor_check_flat "$RV" rvm-progress 'never reads or writes a record' "S6c2 reviewer mechanics: the --review-only exclusion"
anchor_check_flat "$RS" rs-0j-gates '.tests_state. \*\*is never restored\*\*' "S6d tests_state is never restored"
anchor_check_flat "$RS" rs-0j-gates 'only when QA exited clean in this session' "S6e the marker and receipt only after a clean QA in this session"
grep -qF '**only when QA exited clean** in this session' "$RS/SKILL.md"
check "S6f resolver Step 5 keeps 'only when QA exited clean' and adds 'in this session'" "$?"
for effect in 'issue_edit' 'issue_close' '`push`' '`pr_create`' 'run_log'; do
  anchor_check "$RS" rs-0j-reconcile "$effect" "S6g resolver reconciles $effect"
done
anchor_check "$RS" rs-0j-reconcile 'gh pr list --head "\$branch_name" --state all --json' "S6h the PR-create reconcile is a live --json read"
anchor_check "$RS" rs-0j-reconcile 'backup comment' "S6i the comment effect is reconciled against 0a's comments"
for effect in '`push`' '`body_edit`' '`merge`'; do
  anchor_check "$RV" rvm-progress-reconcile "$effect" "S6j reviewer reconciles $effect"
done
anchor_check "$RV" rvm-progress-reconcile 'gh pr view \{N\} --json state,headRefOid' "S6k the merge reconcile is a live --json read"
anchor_check_flat "$RS" rs-0j-reconcile '[Nn]o label edit exists in this skill today; a future one must add an intent row here' \
  "S6l resolver: the label rule (AC4 names label)"
anchor_check_flat "$RV" rvm-progress-reconcile '[Nn]o label edit exists in this skill today; a future one must add an intent row here' \
  "S6m reviewer: the label rule"
anchor_check_flat "$RS" rs-0j-validate '[Nn]ever .cd. into it' "S6n a recorded worktree path never reaches cd"
anchor_check_flat "$RS" rs-0j-validate 'pwd -P' "S6o the worktree comparison is physical (pwd -P)"
anchor_check_flat "$RS" rs-0j-restore 'Resuming issue #\{N\} from step \{k\}/5' "S6p AC2: the resolver prints what it restored"
anchor_check_flat "$RV" rvm-progress-resume 'Resuming PR #\{N\} from step \{k\}/7' "S6q AC2: the reviewer prints what it restored"
anchor_check_flat "$RS" rs-0j-cleanup 'every terminal outcome' "S6r AC5: the resolver clears at every terminal outcome"
anchor_check_flat "$RV" rvm-progress-cleanup 'every Result' "S6s AC5: the reviewer clears at every Result"
grep -qE '^\| `/issue-resolver <N> --resume` \|' "$RS/SKILL.md"; check "S6t resolver Invocation lists --resume" "$?"
grep -qE '^\| `/issue-pr-review <N> --resume` \|' "$RV/SKILL.md"; check "S6u reviewer Invocation lists --resume" "$?"
for pair in "$RS/SKILL.md:references/steps/step-0j-progress-record.md" "$RS/SKILL.md:references/scripts/gi-progress.py" \
            "$RV/SKILL.md:references/progress-record-mechanics.md" "$RV/SKILL.md:references/scripts/gi-progress.py" \
            "$AP/SKILL.md:references/scripts/gi-progress.py"; do
  f="${pair%%:*}"; want="${pair#*:}"
  grep -qE "^(- \`)?${want//./\\.}(\`.*)?$" "$f" && [ -f "$(dirname "$f")/$want" ]
  st=$?  # captured before the label's command substitution resets it
  check "S6v $(basename "$(dirname "$f")") prechecks and bundles $want" "$st"
done
grep -qE '^\| `/auto-pilot --resume` \|.*progress record' "$AP/SKILL.md"
check "S6w auto-pilot --resume also resumes the in-flight skill from its progress record" "$?"
STEP53="$(anchor_span "$AP/references/phases/phase-5-merge.md" ap-step53-cleanup ap-step16-cache-update || true)"
printf '%s\n' "$STEP53" | grep -qE 'gi-progress\.py --clear --skill issue-resolver --number \{issue_number\}'
check "S6x auto-pilot's Step 5.3 clears the resolver record at the issue's terminal outcome" "$?"
printf '%s\n' "$STEP53" | grep -qE 'gi-progress\.py --clear --skill issue-pr-review --number \{pr_number\}'
check "S6y auto-pilot's Step 5.3 clears the reviewer record too" "$?"
NEWCTX="$(grep -rhoE '<!-- a:ctx-[a-z0-9-]+ -->' "$RS/references/steps/step-0j-progress-record.md" "$RV/references/progress-record-mechanics.md" 2>/dev/null || true)"
[ -z "$NEWCTX" ]; check "S6z the new files add no ctx- anchor" "$?"

# The ADR records the reversal and answers each hazard (AC6).
grep -qE '^## Amendment — durable progress records \(#542\)$' "$ADR"; check "S7a ADR carries the #542 amendment section" "$?"
AMEND="$(awk '/^## Amendment — durable progress records/{on=1; next} on && /^## /{exit} on' "$ADR")"
for hazard in 'Stale records' 'Working directory' 'Worktrees' 'Read-back trust'; do
  printf '%s\n' "$AMEND" | grep -qE "^\| \*\*$hazard\*\* \|" \
    && pass "S7b the amendment's hazard table answers: $hazard" || fail "S7b the amendment's hazard table lacks: $hazard"
done
grep -qF '**An on-disk handoff record**' "$ADR" && grep -qiE 'reversed by #542' "$ADR"
check "S7c the rejected alternative is marked reversed by #542, its hazard text kept" "$?"
grep -qF 'gi-progress.py' "$ADR"; check "S7d the ADR names gi-progress.py" "$?"

echo ""
echo "  Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
