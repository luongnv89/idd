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
#   V4   the pilot: this repo's own .gitissue-recipe.json, exercised in a
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
PILOT="$REPO_ROOT/.gitissue-recipe.json"
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
commit_recipe() { (cd "$1" && cat > .gitissue-recipe.json && git add .gitissue-recipe.json && git commit -qm recipe); }
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
r = json.load(open(".gitissue-recipe.json"))
r["capabilities"] = [{"name": "evil", "drive": ["sh", "-c", "touch \"$IDD_EVIDENCE_DIR/../../../../../pwned\""]}]
json.dump(r, open(".gitissue-recipe.json", "w"))
PY
git commit -qam 'branch rewrites the recipe')
recipe "$R" 'landing.html' --consumer resolve
[ "$(jget "$OUT" '[c["name"] for c in v["capabilities"]]')" = "['landing']" ] && [ ! -e "$R/.git/pwned" ] && [ ! -e "$R/pwned" ]
check "V3: a recipe rewritten on the branch never replaces the base-ref recipe" "$?"
R="$TMP/wtonly"; new_repo "$R"; (cd "$R" && git checkout -qb feat && server_recipe '["resolve"]' '' > .gitissue-recipe.json)
recipe "$R" 'landing.html' --consumer resolve
[ "$(jget "$OUT" 'v["status"]')" = absent ]; check "V3: an uncommitted working-tree recipe is ignored (absent)" "$?"

# ── V4: the pilot recipe, exercised ──────────────────────────
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$PILOT" 2>/dev/null
check "V4: the repo ships a pilot .gitissue-recipe.json" "$?"
[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["auto"])' "$PILOT" 2>/dev/null)" = "[]" ]
check "V4: the pilot opts in no auto consumer" "$?"
R="$TMP/pilot"; new_repo "$R"; commit_recipe "$R" < "$PILOT"; branch_change "$R" '<h1>landing v2 from the branch</h1>'
recipe "$R" "$(printf 'landing.html\nREADME.md')" --consumer resolve
[ "$EC" = 0 ] && [ "$(jget "$OUT" 'v["status"]')" = ran ] && [ "$(jget "$OUT" 'v["result"]')" = pass ]
check "V4: the pilot runs and passes (exit 0)" "$?"
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
[ "$(stat -f %Lp "$EV" 2>/dev/null || stat -c %a "$EV")" = 700 ]; check "V4: the evidence directory is mode 0700" "$?"

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
