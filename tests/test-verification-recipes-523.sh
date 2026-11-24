#!/usr/bin/env bash
# test-verification-recipes-523.sh — project-local verification recipes (#523).
#
# AC: Run project-local launch/drive/evidence/cleanup recipes, exercise mapped
#     capabilities and preserve evidence after owned-instance teardown.
#
#   V1   gi-recipe.py is a well-formed shared script (0755, stdlib-only,
#        --help exits 0, usage error exits 2).
#   V2   opt-in: no recipe at the base ref is `absent` and launches nothing;
#        auto mode runs only when the base-ref recipe's `auto` names the
#        consumer (--auto and IDD_AUTO_MODE=1 alike).
#   V3   the recipe is read from the base ref only — a branch that rewrites
#        it, or an uncommitted working-tree copy, never supplies it.
#   V4   the pilot: this repo's own .idd-recipe.json, exercised in a
#        throwaway copy of the static site — the mapped capability is driven
#        against the branch's code, unmapped ones are not, evidence survives
#        teardown and leaves the tree clean.
#   V5   owned-only teardown: the launched group (grandchildren included) is
#        gone, an unrelated decoy survives, cleanup ran, {instance_dir} is
#        removed — also when the helper is interrupted by SIGTERM.
#   V6   failing and hanging drives are `result: fail`.
#   V7   a launch that dies or never becomes ready is exit 4 with the group
#        torn down and its launch.log kept.
#   V8   an invalid recipe is exit 3 before anything launches; an unknown ref
#        is exit 4.
#   V9   the evidence is a valid revision-receipt artifact: it verifies, a
#        second run on the same commit does not disturb it, tampering does.
#   V10  wiring: both skills bundle and precheck the script, invoke it with the
#        base ref, and the shared doc stays skill-agnostic.
#   V11  the starter recipe gi-stack-detect drafts for /init-idd (#668) — with a
#        server and CLI-only — passes this script's own validate(), with one
#        capability per detected entry point and auto left empty.
#   V12  --ref is exactly one listed ref: a local origin/main, a missing remote
#        ref falling through to refs/heads/refs/remotes/..., a revision suffix,
#        a branch and tag of one name, and a $GIT_DIR/origin/main file never
#        supply the recipe; the legitimate forms still resolve; an empty or
#        option-shaped --ref is exit 2. Each guard has a reverse-applied mutant.
#
# Usage: bash tests/test-verification-recipes-523.sh
# Returns: exit 0 if all checks pass, exit 1 on failure.

# No `set -e`: assertions report and continue.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "0" ]; then pass "$1"; else fail "$1"; fi; }

SCRIPT="$REPO_ROOT/src/shared/scripts/gi-recipe.py"
RECEIPT="$REPO_ROOT/src/shared/scripts/gi-receipt.py"
PILOT="$REPO_ROOT/.idd-recipe.json"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/recipe-523.XXXXXX")"
DECOY=""
cleanup_tmp() {
  [ -n "$DECOY" ] && kill "$DECOY" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup_tmp EXIT

# jget <json> <python expression over v> — print one field of a verdict.
jget() { python3 -c 'import json,sys; v=json.loads(sys.argv[1]); print(eval(sys.argv[2]))' "$1" "$2" 2>/dev/null; }
alive() { kill -0 "$1" 2>/dev/null; }

# new_repo <dir> — a throwaway static-site repo on `main`, plus branch `feat`.
new_repo() {
  mkdir -p "$1" && (
    cd "$1" || exit 1
    git init -q -b main
    git config user.email t@example.invalid
    git config user.name t
    git config commit.gpgsign false
    printf '<h1>landing v1</h1>\n' > landing.html
    printf '<h1>docs</h1>\n' > docs.html
    printf '<h1>changelog</h1>\n' > changelog.html
    git add -A && git commit -qm init
  )
}
commit_recipe() { (cd "$1" && cat > .idd-recipe.json && git add .idd-recipe.json && git commit -qm recipe); }
branch_change() { (cd "$1" && git checkout -qb feat && printf '%s\n' "$2" > landing.html && git commit -qam change); }

# recipe <dir> <changed-lines> [args...] — sets OUT and EC.
recipe() {
  local dir="$1" changed="$2"; shift 2
  OUT="$(cd "$dir" && printf '%s' "$changed" | env -u IDD_AUTO_MODE python3 "$SCRIPT" --ref main --changed - "$@" 2>"$TMP/stderr")"
  EC=$?
}

# A server recipe whose drives, launch and cleanup are all scriptable.
server_recipe() { # <auto-json> <extra capability json or empty>
  cat <<JSON
{"version": 1, "auto": $1,
 "launch": {"command": ["sh", "-c", "echo \$\$ > \"\$IDD_EVIDENCE_DIR/launch.pid\"; echo \"\$IDD_INSTANCE_DIR\" > \"\$IDD_EVIDENCE_DIR/instance.path\"; sleep 300 & echo \$! > \"\$IDD_EVIDENCE_DIR/child.pid\"; exec python3 -m http.server \"\$IDD_PORT\" --bind 127.0.0.1"],
            "ready": {"url": "/landing.html", "timeout_s": 20}},
 "capabilities": [
   {"name": "landing", "paths": ["landing.html"], "drive": ["curl", "-sf", "-o", "{evidence_dir}/page.html", "{app_url}/landing.html"]}$2],
 "cleanup": [["sh", "-c", "echo cleaned > \"\$IDD_EVIDENCE_DIR/cleaned.txt\""]]}
JSON
}

echo "◆ Verification recipes (issue #523)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ── V1: a well-formed shared script ──────────────────────────
[ -f "$SCRIPT" ] && [ -x "$SCRIPT" ]; check "V1: gi-recipe.py exists and is executable" "$?"
mode="$(cd "$REPO_ROOT" && git ls-files -s src/shared/scripts/gi-recipe.py | awk '{print $1}')"
[ -z "$mode" ] || [ "$mode" = "100755" ]; check "V1: committed mode is 0755 (got ${mode:-untracked})" "$?"
python3 "$SCRIPT" --help >/dev/null 2>&1; check "V1: --help exits 0" "$?"
python3 "$SCRIPT" --bogus >/dev/null 2>&1; [ "$?" = "2" ]; check "V1: an unknown option is a usage error (exit 2)" "$?"
python3 "$SCRIPT" --ref main --consumer other --changed - </dev/null >/dev/null 2>&1; [ "$?" = "2" ]
check "V1: an unknown consumer is a usage error (exit 2)" "$?"
python3 - "$SCRIPT" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
mods = {a.name.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.Import) for a in n.names}
mods |= {n.module.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.ImportFrom) and n.module}
std = set(sys.stdlib_module_names) | {"__future__"}
sys.exit(1 if mods - std else 0)
PY
check "V1: imports the standard library only" "$?"

# ── V11: /init-idd's starter recipe validates (needs no curl) ──
STACK="$REPO_ROOT/src/shared/scripts/gi-stack-detect.py"
# starter_repo <dir> — commit the tree and fake a fetched origin/main.
starter_repo() {
  (cd "$1" && git init -q -b main && git config user.email t@example.invalid && git config user.name t \
    && git config commit.gpgsign false && git add -A && git commit -qm init \
    && git update-ref refs/remotes/origin/main HEAD \
    && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main)
}
SV="$TMP/starter-server"; mkdir -p "$SV/bin"
printf 'x\n' > "$SV/manage.py"
printf '{"name": "w", "bin": {"tool": "bin/tool.js"}}\n' > "$SV/package.json"
starter_repo "$SV"
SC="$TMP/starter-cli"; mkdir -p "$SC/cmd/worker"
printf '[project]\nname = "pt"\n[project.scripts]\npytool = "pt:main"\n' > "$SC/pyproject.toml"
printf 'package main\n' > "$SC/cmd/worker/main.go"
starter_repo "$SC"
for fixture in "$SV:2" "$SC:2"; do
  dir="${fixture%:*}"; want="${fixture##*:}"
  python3 "$STACK" --root "$dir" > "$TMP/stack.json" 2>/dev/null
  python3 - "$SCRIPT" "$TMP/stack.json" "$want" <<'PY'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("gi_recipe", sys.argv[1])
recipe = importlib.util.module_from_spec(spec); spec.loader.exec_module(recipe)
block = json.load(open(sys.argv[2]))["recipe"]
valid = recipe.validate(block["starter"])
assert len(valid["capabilities"]) == len(block["entry_points"]) == int(sys.argv[3]), block
assert valid["auto"] == [], valid["auto"]
PY
  rc=$?  # before the label's command substitution resets $?
  check "V11: the ${dir##*/} starter validates, one capability per entry point, auto empty" "$rc"
done

# ── V12: a look-alike ref never supplies the recipe (needs no curl) ──
# main carries a recipe whose one capability is `real`; the checked-out branch
# `feat` — the code under review — carries one named `evil`. Every cell runs
# --plan, so nothing launches and the capability names show which recipe loaded.
cap_recipe() { printf '{"version":1,"launch":{"command":["true"],"ready":{"url":"/"}},"capabilities":[{"name":"%s","drive":["true"]}]}' "$1"; }
# look_alike <dir> <kind> — kinds:
#   plain   the real refs/remotes/origin/main and nothing else
#   shadow  plus a local branch origin/main at feat (what `gh pr checkout` makes)
#   nested  refs/remotes/origin/main deleted; a local branch named
#           refs/remotes/origin/main at feat
#   lone    refs/remotes/origin/main deleted; a local branch origin/main at feat
#   gitdir  plus a file $GIT_DIR/origin/main holding feat's commit id, which git
#           reads first for `origin/main` and `for-each-ref` never lists
#   tag     a branch `base` at main and a tag `base` at feat
look_alike() {
  local d="$1" kind="$2"
  new_repo "$d"; cap_recipe real | commit_recipe "$d"
  (cd "$d" && git update-ref refs/remotes/origin/main HEAD && git checkout -qb feat)
  cap_recipe evil | commit_recipe "$d"
  (
    cd "$d" || exit 1
    case "$kind" in
      shadow) git branch origin/main feat ;;
      nested) git update-ref -d refs/remotes/origin/main && git update-ref refs/heads/refs/remotes/origin/main feat ;;
      lone) git update-ref -d refs/remotes/origin/main && git branch origin/main feat ;;
      gitdir) mkdir -p .git/origin && git rev-parse feat > .git/origin/main ;;
      tag) git branch base main && git tag base feat ;;
    esac
  )
}
# plan_caps <dir> <ref> [script] — sets EC, CAPS (loaded capability names), ERR.
plan_caps() {
  local out
  out="$(cd "$1" && printf 'landing.html' | env -u IDD_AUTO_MODE python3 "${3:-$SCRIPT}" --ref "$2" --consumer resolve --changed - --plan 2>"$TMP/stderr")"
  EC=$?
  CAPS="$(jget "$out" '[c["name"] for c in v["capabilities"]]')"
  ERR="$(cat "$TMP/stderr")"
}
# The negative cells: name, kind, ref, required stderr reason ('' = any).
V12_CELLS="shadow|origin/main|
nested|refs/remotes/origin/main|
lone|origin/main|
tag|base|
shadow|origin/main~0|is not a ref name
shadow|origin/main^0|is not a ref name
shadow|origin/main@{0}|is not a ref name
shadow|origin/main^{commit}|is not a ref name"
# refused <kind> <ref> <reason> [script] — exit 0 when the recipe is refused (exit 4).
refused() {
  local d="$TMP/v12-$1-$RANDOM$RANDOM"
  look_alike "$d" "$1"; plan_caps "$d" "$2" "${4:-}"
  [ "$EC" = 4 ] && [ -z "$CAPS" ] && { [ -z "$3" ] || printf '%s' "$ERR" | grep -qF "$3"; }
}
while IFS='|' read -r kind ref reason; do
  refused "$kind" "$ref" "$reason"
  check "V12: --ref $ref with a look-alike ($kind) is refused, exit 4${reason:+, as revision syntax} (exit $EC, loaded ${CAPS:-nothing})" "$?"
done <<EOF
$V12_CELLS
EOF
# Every read goes through the listed ref's object id, never the name.
pinned() {
  local d="$TMP/v12-gitdir-$RANDOM$RANDOM"
  look_alike "$d" gitdir
  [ "$(cd "$d" && git rev-parse origin/main)" = "$(cd "$d" && git rev-parse feat)" ] || return 1
  plan_caps "$d" origin/main "${1:-}"
  [ "$EC" = 0 ] && [ "$CAPS" = "['real']" ]
}
pinned; check "V12: --ref origin/main loads the listed ref's recipe, not git's own lookup of the name (exit $EC, loaded ${CAPS:-nothing})" "$?"
R="$TMP/v12-plain"; look_alike "$R" plain
for good in origin/main refs/remotes/origin/main main refs/heads/main; do
  plan_caps "$R" "$good"
  [ "$EC" = 0 ] && [ "$CAPS" = "['real']" ]; check "V12: --ref $good resolves and loads the base recipe (exit $EC, loaded ${CAPS:-nothing})" "$?"
done
plan_caps "$R" HEAD
[ "$EC" = 0 ] && [ "$CAPS" = "['evil']" ]; check "V12: --ref HEAD resolves to the checked-out commit's recipe (exit $EC)" "$?"
usage_errors() { # [script] — exit 0 when both malformed values are exit 2
  local s="${1:-$SCRIPT}" bad
  for bad in "" "-x"; do
    (cd "$R" && printf 'x' | python3 "$s" --ref="$bad" --consumer resolve --changed - >/dev/null 2>&1)
    [ "$?" = 2 ] || return 1
  done
}
usage_errors; check "V12: --ref='' and --ref=-x are usage errors (exit 2), before any ref check" "$?"

# V12-M: reverse-apply each guard in a scratch copy; its cell must then fail.
M="$TMP/mutants"; mkdir -p "$M"
# mutate <out> <anchor> <replacement> [<anchor> <replacement>...] — 1 if an anchor drifted.
mutate() {
  python3 - "$SCRIPT" "$@" <<'PY'
import sys
src, out, *pairs = sys.argv[1:]
text = open(src, encoding="utf-8").read()
for anchor, replacement in zip(pairs[::2], pairs[1::2]):
    if anchor not in text:
        sys.exit(1)
    text = text.replace(anchor, replacement, 1)
open(out, "w", encoding="utf-8").write(text)
PY
}
AMBIGUOUS=$'    if len(found) > 1:\n'
REMOTE_RULE=$'    if "/" in ref and not ref.startswith("refs/") and found[0] != f"refs/remotes/{ref}":\n'
OFF=$'    if False:\n'
# Two guards each stop the shadow cell, so its mutant drops both.
mutate "$M/shadow.py" "$AMBIGUOUS" "$OFF" "$REMOTE_RULE" "$OFF"; check "V12-M: the ambiguity check and remote-tracking rule are present to reverse-apply" "$?"
! refused shadow origin/main '' "$M/shadow.py"; check "V12-M: without them a local origin/main shadowing the remote supplies the recipe (exit $EC, loaded ${CAPS:-nothing})" "$?"
mutate "$M/nested.py" $'    if not found:\n        raise CannotComplete(\n' $'    if not found:\n        return _commit_of(ref)\n        raise CannotComplete(\n'
check "V12-M: the unlisted-name refusal is present to reverse-apply" "$?"
! refused nested refs/remotes/origin/main '' "$M/nested.py"; check "V12-M: resolving an unlisted refs/ name by git's own lookup reaches refs/heads/refs/remotes/origin/main (exit $EC, loaded ${CAPS:-nothing})" "$?"
mutate "$M/lone.py" "$REMOTE_RULE" "$OFF"; check "V12-M: the remote-tracking rule is present to reverse-apply" "$?"
! refused lone origin/main '' "$M/lone.py"; check "V12-M: without it a lone local origin/main supplies the recipe (exit $EC, loaded ${CAPS:-nothing})" "$?"
mutate "$M/tag.py" "$AMBIGUOUS" "$OFF"; check "V12-M: the ambiguity check is present to reverse-apply" "$?"
! refused tag base '' "$M/tag.py"; check "V12-M: without it the tag of the same name supplies the recipe (exit $EC, loaded ${CAPS:-nothing})" "$?"
mutate "$M/format.py" $'    if _git("check-ref-format", "--allow-onelevel", ref).returncode != 0:\n' "$OFF"
check "V12-M: the check-ref-format guard is present to reverse-apply" "$?"
! refused shadow 'origin/main~0' 'is not a ref name' "$M/format.py"; check "V12-M: without it origin/main~0 is no longer refused as revision syntax" "$?"
mutate "$M/pin.py" $'    oid = _commit_of(rows[found[0]])\n' $'    oid = _commit_of(ref)\n'; check "V12-M: the read through the listed object id is present to reverse-apply" "$?"
! pinned "$M/pin.py"; check "V12-M: resolving the name instead lets \$GIT_DIR/origin/main supply the recipe (exit $EC, loaded ${CAPS:-nothing})" "$?"
mutate "$M/usage.py" $'    if not args.ref:\n' "$OFF" $'    if args.ref.startswith("-"):\n' "$OFF"; check "V12-M: the usage guards are present to reverse-apply" "$?"
! usage_errors "$M/usage.py"; check "V12-M: without them an empty or option-shaped --ref is not a usage error" "$?"

if ! command -v curl >/dev/null 2>&1; then
  echo "  ○ curl not found — the behavioural legs need it to drive the pilot"
  echo "  Result: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ]
  exit
fi

# ── V2: opt-in ───────────────────────────────────────────────
R="$TMP/absent"; new_repo "$R"; branch_change "$R" '<h1>v2</h1>'
recipe "$R" 'landing.html' --consumer resolve
[ "$EC" = 0 ] && [ "$(jget "$OUT" 'v["status"]')" = absent ]; check "V2: no recipe at the base ref is status absent (exit 0)" "$?"
[ ! -e "$R/.git/idd/evidence" ]; check "V2: an absent recipe launches nothing and writes no evidence" "$?"

R="$TMP/optin"; new_repo "$R"; server_recipe '["resolve"]' '' | commit_recipe "$R"; branch_change "$R" '<h1>v2</h1>'
recipe "$R" 'landing.html' --consumer review --auto
[ "$EC" = 0 ] && [ "$(jget "$OUT" 'v["status"]')" = skipped ] && jget "$OUT" 'v["reason"]' | grep -q 'auto opt-in not set for review'
check "V2: --auto skips a consumer the recipe's auto list does not name" "$?"
OUT="$(cd "$R" && printf 'landing.html' | IDD_AUTO_MODE=1 python3 "$SCRIPT" --ref main --consumer review --changed - 2>/dev/null)"
[ "$(jget "$OUT" 'v["status"]')" = skipped ]; check "V2: IDD_AUTO_MODE=1 implies --auto" "$?"
[ ! -e "$R/.git/idd/evidence" ]; check "V2: a skipped recipe launches nothing" "$?"
recipe "$R" 'landing.html' --consumer resolve --auto
[ "$EC" = 0 ] && [ "$(jget "$OUT" 'v["status"]')" = ran ]; check "V2: --auto runs for a consumer the recipe opts in" "$?"
recipe "$R" 'docs.html' --consumer resolve
[ "$(jget "$OUT" 'v["status"]')" = skipped ] && jget "$OUT" 'v["reason"]' | grep -q 'no capability mapped'
check "V2: no capability mapped to the diff is skipped" "$?"
recipe "$R" 'landing.html' --consumer resolve --plan
[ "$(jget "$OUT" 'v["status"]')" = planned ] && [ "$(jget "$OUT" '[c["name"] for c in v["capabilities"] if c["mapped"]]')" = "['landing']" ] \
  && [ "$(jget "$OUT" 'v["owned"]')" = None ]
check "V2: --plan lists the mapped capabilities without launching" "$?"

# ── V3: base ref only ────────────────────────────────────────
R="$TMP/baseref"; new_repo "$R"; server_recipe '[]' '' | commit_recipe "$R"; branch_change "$R" '<h1>v2</h1>'
(cd "$R" && python3 - <<'PY'
import json
r = json.load(open(".idd-recipe.json"))
r["capabilities"] = [{"name": "evil", "drive": ["sh", "-c", "touch \"$IDD_EVIDENCE_DIR/../../../../../pwned\""]}]
json.dump(r, open(".idd-recipe.json", "w"))
PY
git commit -qam 'branch rewrites the recipe')
recipe "$R" 'landing.html' --consumer resolve
[ "$(jget "$OUT" '[c["name"] for c in v["capabilities"]]')" = "['landing']" ] && [ ! -e "$R/.git/pwned" ] && [ ! -e "$R/pwned" ]
check "V3: a recipe rewritten on the branch never replaces the base-ref recipe" "$?"
R="$TMP/wtonly"; new_repo "$R"; (cd "$R" && git checkout -qb feat && server_recipe '["resolve"]' '' > .idd-recipe.json)
recipe "$R" 'landing.html' --consumer resolve
[ "$(jget "$OUT" 'v["status"]')" = absent ]; check "V3: an uncommitted working-tree recipe is ignored (absent)" "$?"

# ── V4: the pilot recipe, exercised ──────────────────────────
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$PILOT" 2>/dev/null
check "V4: the repo ships a pilot .idd-recipe.json" "$?"
[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["auto"])' "$PILOT" 2>/dev/null)" = "[]" ]
check "V4: the pilot opts in no auto consumer" "$?"
R="$TMP/pilot"; new_repo "$R"; commit_recipe "$R" < "$PILOT"; branch_change "$R" '<h1>landing v2 from the branch</h1>'
# The branch also plants an `http` package that would shadow the stdlib
# module the launch runs; the pilot only passes if `python3 -I` ignores it.
(cd "$R" && mkdir http && : > http/__init__.py && printf 'raise SystemExit(9)\n' > http/server.py \
  && git add http && git commit -qm 'branch shadows http.server')
recipe "$R" "$(printf 'landing.html\nREADME.md')" --consumer resolve
[ "$EC" = 0 ] && [ "$(jget "$OUT" 'v["status"]')" = ran ] && [ "$(jget "$OUT" 'v["result"]')" = pass ]
check "V4: the pilot runs and passes (exit 0), never running a branch-shadowed http.server" "$?"
[ "$(jget "$OUT" '[c["name"] for c in v["capabilities"] if c["driven"]]')" = "['landing']" ]
check "V4: only the capability mapped to the diff is driven" "$?"
EV="$(jget "$OUT" 'v["evidence_dir"]')"
grep -q 'landing v2 from the branch' "$EV/landing/landing.html" 2>/dev/null
check "V4: the drive exercised the branch's code, and its evidence survived teardown" "$?"
[ "$(jget "$OUT" 'v["torn_down"]')" = True ] && ! alive "-$(jget "$OUT" 'v["owned"]["pgid"]')"
check "V4: the owned instance is torn down" "$?"
[ -f "$EV/verdict.json" ] && [ -f "$EV/launch.log" ] && [ -f "$EV/landing/drive.log" ]
check "V4: launch.log, drive.log and verdict.json are kept" "$?"
case "$EV" in "$(cd "$R" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"/idd/evidence/*) true ;; *) false ;; esac
check "V4: evidence lives under <git common dir>/idd/evidence/" "$?"
[ -z "$(cd "$R" && git status --porcelain=v1 --untracked-files=all)" ]; check "V4: the work tree stays clean" "$?"
# Python, not stat(1): GNU `stat -f` means --file-system and prints to stdout
# before failing, so a BSD-first `stat -f %Lp || stat -c %a` breaks on Linux.
[ "$(python3 -c 'import os,sys; print(format(os.stat(sys.argv[1]).st_mode & 0o777, "o"))' "$EV")" = 700 ]; check "V4: the evidence directory is mode 0700" "$?"

# ── V5: owned-only teardown ──────────────────────────────────
sleep 300 & DECOY=$!
R="$TMP/owned"; new_repo "$R"; server_recipe '[]' '' | commit_recipe "$R"; branch_change "$R" '<h1>v2</h1>'
recipe "$R" 'landing.html' --consumer resolve
EV="$(jget "$OUT" 'v["evidence_dir"]')"
[ "$(jget "$OUT" 'v["result"]')" = pass ]; check "V5: the scripted server recipe passes" "$?"
child="$(cat "$EV/child.pid" 2>/dev/null)"; leader="$(cat "$EV/launch.pid" 2>/dev/null)"
[ -n "$child" ] && ! alive "$child" && [ -n "$leader" ] && ! alive "$leader"
check "V5: the launch leader and its background grandchild are gone" "$?"
[ "$leader" = "$(jget "$OUT" 'v["owned"]["pgid"]')" ]; check "V5: the owned group is the launch's own" "$?"
alive "$DECOY"; check "V5: an unrelated process survives teardown" "$?"
[ -f "$EV/cleaned.txt" ] && [ "$(jget "$OUT" 'v["cleanup"]')" = "[0]" ]; check "V5: the cleanup command ran" "$?"
inst="$(cat "$EV/instance.path" 2>/dev/null)"
[ -n "$inst" ] && [ ! -e "$inst" ]; check "V5: {instance_dir} is removed at teardown" "$?"

# Interrupted mid-drive: SIGTERM to the helper still tears the instance down.
R="$TMP/sigterm"; new_repo "$R"
server_recipe '[]' ', {"name": "slow", "drive": ["sh", "-c", "echo $$ > \"$IDD_EVIDENCE_DIR/started\"; exec sleep 30"]}' | commit_recipe "$R"
branch_change "$R" '<h1>v2</h1>'
printf 'landing.html' > "$TMP/changed"
(cd "$R" && exec env -u IDD_AUTO_MODE python3 "$SCRIPT" --ref main --consumer resolve --changed "$TMP/changed" >"$TMP/sig.out" 2>/dev/null) &
helper=$!
started=""
for _ in $(seq 1 100); do
  started="$(find "$R/.git/idd/evidence" -name started -size +0 2>/dev/null | head -1)"
  [ -n "$started" ] && break
  sleep 0.1
done
kill -TERM "$helper" 2>/dev/null
wait "$helper"; sig_ec=$?
OUT="$(cat "$TMP/sig.out")"
[ -n "$started" ] && [ "$sig_ec" = 4 ] && [ "$(jget "$OUT" 'v["status"]')" = unavailable ]
check "V5: SIGTERM mid-drive ends the run as unavailable (exit 4)" "$?"
EV="$(jget "$OUT" 'v["evidence_dir"]')"
leader="$(cat "$EV/launch.pid" 2>/dev/null)"
[ "$(jget "$OUT" 'v["torn_down"]')" = True ] && [ -n "$leader" ] && ! alive "$leader" && ! alive "$(cat "$EV/child.pid" 2>/dev/null)"
check "V5: an interrupted run still tears the owned instance down" "$?"
slow="$(cat "$started" 2>/dev/null)"
[ -n "$slow" ] && ! alive "$slow"; check "V5: the interrupted drive's own process is gone" "$?"
kill "$DECOY" 2>/dev/null; DECOY=""

# ── V6: failing and hanging drives ───────────────────────────
R="$TMP/drivefail"; new_repo "$R"
server_recipe '[]' ', {"name": "broken", "drive": ["sh", "-c", "exit 7"]}, {"name": "hang", "drive": ["sleep", "30"], "timeout_s": 1}' | commit_recipe "$R"
branch_change "$R" '<h1>v2</h1>'
recipe "$R" 'landing.html' --consumer resolve
[ "$EC" = 0 ] && [ "$(jget "$OUT" 'v["result"]')" = fail ]; check "V6: a failing drive makes result fail (still exit 0)" "$?"
[ "$(jget "$OUT" '[c["exit"] for c in v["capabilities"] if c["name"]=="broken"][0]')" = 7 ]; check "V6: the drive's exit status is reported" "$?"
[ "$(jget "$OUT" '[c["timed_out"] for c in v["capabilities"] if c["name"]=="hang"][0]')" = True ]; check "V6: a hanging drive is timed out" "$?"
[ "$(jget "$OUT" '[c["exit"] for c in v["capabilities"] if c["name"]=="landing"][0]')" = 0 ]; check "V6: a passing drive beside them still reports 0" "$?"

# ── V7: launch failures ──────────────────────────────────────
R="$TMP/dies"; new_repo "$R"
printf '%s' '{"version":1,"launch":{"command":["sh","-c","echo boom; exit 1"],"ready":{"url":"/","timeout_s":5}},"capabilities":[{"name":"x","drive":["true"]}]}' | commit_recipe "$R"
recipe "$R" 'landing.html' --consumer resolve
EV="$(jget "$OUT" 'v["evidence_dir"]')"
[ "$EC" = 4 ] && [ "$(jget "$OUT" 'v["status"]')" = unavailable ] && grep -q boom "$EV/launch.log" 2>/dev/null
check "V7: a launch that dies is exit 4 and keeps its launch.log" "$?"
R="$TMP/neverready"; new_repo "$R"
printf '%s' '{"version":1,"launch":{"command":["sh","-c","echo $$ > \"$IDD_EVIDENCE_DIR/launch.pid\"; exec sleep 60"],"ready":{"url":"/","timeout_s":1}},"capabilities":[{"name":"x","drive":["true"]}]}' | commit_recipe "$R"
recipe "$R" 'landing.html' --consumer resolve
EV="$(jget "$OUT" 'v["evidence_dir"]')"
[ "$EC" = 4 ] && jget "$OUT" 'v["reason"]' | grep -q 'not ready' && [ "$(jget "$OUT" 'v["torn_down"]')" = True ] \
  && ! alive "$(cat "$EV/launch.pid" 2>/dev/null)"
check "V7: a launch that never becomes ready is exit 4 and torn down" "$?"
[ "$(jget "$OUT" '[c["driven"] for c in v["capabilities"]]')" = "[False]" ]; check "V7: nothing is driven against an app that never became ready" "$?"

# ── V8: invalid recipes and refs ─────────────────────────────
bad() { # <label> <recipe text>
  local d="$TMP/bad$PASS$FAIL"; new_repo "$d"; printf '%s' "$2" | commit_recipe "$d"
  recipe "$d" 'landing.html' --consumer resolve
  [ "$EC" = 3 ] && [ ! -e "$d/.git/idd/evidence" ]; check "V8: $1 is exit 3 and launches nothing" "$?"
}
GOOD_LAUNCH='"launch":{"command":["true"],"ready":{"url":"/"}}'
bad "malformed JSON" '{"version": 1,'
bad "an unknown key" "{\"version\":1,$GOOD_LAUNCH,\"capabilities\":[{\"name\":\"x\",\"drive\":[\"true\"]}],\"hooks\":[]}"
bad "a non-loopback app_url" "{\"version\":1,\"app_url\":\"https://example.com\",$GOOD_LAUNCH,\"capabilities\":[{\"name\":\"x\",\"drive\":[\"true\"]}]}"
bad "an unparsable app_url" "{\"version\":1,\"app_url\":\"http://[::1:{port}\",$GOOD_LAUNCH,\"capabilities\":[{\"name\":\"x\",\"drive\":[\"true\"]}]}"
bad "a ready URL with an invalid port" '{"version":1,"launch":{"command":["true"],"ready":{"url":"{app_url}:99999999/"}},"capabilities":[{"name":"x","drive":["true"]}]}'
bad "a shell-string command" '{"version":1,"launch":{"command":"python3 -m http.server","ready":{"url":"/"}},"capabilities":[{"name":"x","drive":["true"]}]}'
bad "a duplicate capability name" "{\"version\":1,$GOOD_LAUNCH,\"capabilities\":[{\"name\":\"x\",\"drive\":[\"true\"]},{\"name\":\"x\",\"drive\":[\"true\"]}]}"
bad "a ready URL that leaves the loopback host" '{"version":1,"launch":{"command":["true"],"ready":{"url":"{app_url}@example.com/"}},"capabilities":[{"name":"x","drive":["true"]}]}'
bad "an unknown auto consumer" "{\"version\":1,\"auto\":[\"deploy\"],$GOOD_LAUNCH,\"capabilities\":[{\"name\":\"x\",\"drive\":[\"true\"]}]}"
R="$TMP/badref"; new_repo "$R"
(cd "$R" && printf 'x' | python3 "$SCRIPT" --ref origin/nope --consumer resolve --changed - >/dev/null 2>&1); [ "$?" = 4 ]
check "V8: an unknown ref is exit 4" "$?"

# ── V9: evidence as revision-receipt artifacts ───────────────
R="$TMP/pilot"
recipe "$R" 'landing.html' --consumer resolve
EV_LIST="$OUT"
HEAD_SHA="$(cd "$R" && git rev-parse HEAD)"
record="$(python3 -c 'import json,sys; print(json.dumps({"tool":"issue-resolver","profile":"full","cycles":1,"review":"clean","tests":None,"ui":"none:clean","artifacts":json.loads(sys.argv[1])["evidence"]}))' "$EV_LIST")"
(cd "$R" && printf '%s' "$record" | python3 "$RECEIPT" --write >/dev/null 2>&1); check "V9: gi-receipt accepts the evidence as artifacts" "$?"
verified() { (cd "$R" && python3 "$RECEIPT" --verify "$HEAD_SHA" | python3 -c 'import json,sys; print(json.load(sys.stdin)["verified"])'); }
[ "$(verified)" = True ]; check "V9: the receipt verifies with the evidence digested" "$?"
recipe "$R" 'landing.html' --consumer review
[ "$(jget "$OUT" 'v["evidence_dir"]')" != "$(jget "$EV_LIST" 'v["evidence_dir"]')" ] && [ "$(verified)" = True ]
check "V9: a second run on the same commit writes a new directory and keeps the receipt valid" "$?"
printf 'tampered' >> "$(jget "$EV_LIST" 'v["evidence_dir"]')/landing/landing.html"
[ "$(verified)" = False ]; check "V9: tampered evidence fails receipt verification" "$?"

# ── V10: wiring ──────────────────────────────────────────────
for skill in issue-resolver issue-pr-review; do
  src="$REPO_ROOT/src/skills/$skill/SKILL.source.md"
  built="$REPO_ROOT/skills/$skill"
  grep -qx 'references/scripts/gi-recipe.py' "$src"; check "V10: $skill precheck lists the script (source)" "$?"
  grep -qx 'references/scripts/gi-recipe.py' "$built/SKILL.md"; check "V10: $skill precheck lists the script (built)" "$?"
  cmp -s "$SCRIPT" "$built/references/scripts/gi-recipe.py"; check "V10: $skill bundles a byte-identical copy" "$?"
done
STEP4="$REPO_ROOT/skills/issue-resolver/references/steps/step-4-qa.md"
grep -q 'python3 references/scripts/gi-recipe.py --ref "origin/${base}" --consumer resolve --changed -' "$STEP4"
check "V10: the resolver's Step 4 runs the bundled helper against origin/\${base}" "$?"
MECH="$REPO_ROOT/skills/issue-pr-review/references/ui-review-mechanics.md"
grep -q 'python3 references/scripts/gi-recipe.py --ref "origin/${base}" --consumer review --changed -' "$MECH" \
  && grep -q 'defaultBranchRef' "$MECH"
check "V10: pr-review runs the bundled helper against the default branch, not baseRefName" "$?"
grep -q 'recipe_state' "$REPO_ROOT/src/skills/issue-resolver/references/report-templates.md"
check "V10: the receipt artifacts carry the recipe evidence" "$?"
UIDOC="$REPO_ROOT/docs/ui-review.md"
grep -q 'a:ui-verification-recipe' "$UIDOC" && grep -q 'only from the base ref' "$UIDOC" && grep -q 'auto` list names `{ui_config_scope}`' "$UIDOC"
check "V10: docs/ui-review.md documents the base-ref source and the per-consumer auto opt-in" "$?"
! grep -qE 'gh pr diff|resolve\.ui_review|shared/scripts/' "$UIDOC"; check "V10: docs/ui-review.md stays skill-agnostic" "$?"
grep -q 'test-verification-recipes-523' "$REPO_ROOT/.github/workflows/dist-check.yml"; check "V10: the suite is registered in dist-check.yml" "$?"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
