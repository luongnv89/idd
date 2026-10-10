#!/usr/bin/env bash
# test-qa-receipt-515.sh — Bind QA-skip decisions to authoritative revision receipts (issue #515)
#
# Acceptance criterion:
#   AC1: forged author markers plus unrelated green CI cannot skip QA.
#
# Before #515, /issue-pr-review's `trusted` verdict needed only a PR-body marker
# whose head= equalled the live head — text the PR author writes, binding a SHA
# the PR author can read. With any green check in the rollup that skipped both
# local test legs. `trusted` now also needs a revision receipt that
# shared/scripts/gi-receipt.py wrote for that exact commit, outside every branch
# and every PR body.
#
# Three layers, each on src/ AND the built skills/ tree where it applies:
#   R1-R2   the script ships as a shared script: stdlib-only, 0755, --help, bundled
#           byte-identical into both skills that cite it, on both precheck lists.
#   R3-R10  the script's behaviour, executed in throwaway git repositories.
#   R11     the AC, executed: the consumer's predicate driven with a forged marker,
#           an unrelated green rollup, and no receipt.
#   R12-R14 the prose contract at the producer and the consumer.
#
# Usage: bash tests/test-qa-receipt-515.sh
# Returns: exit 0 if all checks pass, exit 1 on failure.

# No `set -e`: most assertions below are `[ … ]; check LABEL "$?"`, and errexit
# would abort the suite on the first false condition instead of reporting it.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

check() {  # check LABEL CONDITION-EXIT-STATUS
  if [ "$2" = "0" ]; then pass "$1"; else fail "$1"; fi
}

check_has() {
  local file="$1" pattern="$2" label="$3"
  if grep -qE -- "$pattern" "$file" 2>/dev/null; then
    pass "$label"
  else
    fail "$label"
    echo "      missing pattern: $pattern"
    echo "      in file: ${file#$REPO_ROOT/}"
  fi
}

# shellcheck source=lib/anchors.bash
. "$REPO_ROOT/tests/lib/anchors.bash"

echo "◆ QA revision receipts (issue #515)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

SCRIPT="$REPO_ROOT/src/shared/scripts/gi-receipt.py"
SRC_PR_PKG="$REPO_ROOT/src/skills/issue-pr-review"
BUILT_PR_PKG="$REPO_ROOT/skills/issue-pr-review"
SRC_RES_PKG="$REPO_ROOT/src/skills/issue-resolver"
BUILT_RES_PKG="$REPO_ROOT/skills/issue-resolver"

# json_get FILE-OR-STRING KEY — read one top-level key from a JSON string.
json_get() {
  python3 -c 'import json,sys; v=json.loads(sys.argv[1]).get(sys.argv[2]); print("null" if v is None else (str(v).lower() if isinstance(v,bool) else v))' "$1" "$2"
}

# ───────────────────────────────────────────────────────────
# R1-R2: a well-formed shared script, shipped where it is cited.
# ───────────────────────────────────────────────────────────
if [ -f "$SCRIPT" ] && [ -x "$SCRIPT" ]; then
  pass "R1.1: gi-receipt.py exists and is executable (0755)"
else
  fail "R1.1: gi-receipt.py missing or not executable"
fi
python3 "$SCRIPT" --help >/dev/null 2>&1; check "R1.2: --help exits 0" "$?"
bad_imports="$(python3 - "$SCRIPT" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
mods = set()
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        mods.update(a.name.split(".")[0] for a in node.names)
    elif isinstance(node, ast.ImportFrom) and node.module:
        mods.add(node.module.split(".")[0])
std = set(getattr(sys, "stdlib_module_names", ())) | {"__future__"}
print(" ".join(sorted(m for m in mods if std and m not in std)))
PY
)"
if [ -z "$bad_imports" ]; then pass "R1.3: stdlib-only"; else fail "R1.3: non-stdlib imports: $bad_imports"; fi
if grep -qE 'return 1$|exit\(1\)' "$SCRIPT"; then
  fail "R1.4: the script never exits 1 (a non-verified receipt is an answer, not a verdict code)"
else
  pass "R1.4: the script never exits 1 (a non-verified receipt is an answer, not a verdict code)"
fi
for skill in issue-resolver issue-pr-review; do
  built="$REPO_ROOT/skills/$skill/references/scripts/gi-receipt.py"
  if [ -f "$built" ] && cmp -s "$SCRIPT" "$built"; then
    pass "R2.1 ($skill): the bundled copy is byte-identical to the source"
  else
    fail "R2.1 ($skill): the bundled copy is missing or differs"
  fi
  check_has "$REPO_ROOT/src/skills/$skill/SKILL.source.md" '^references/scripts/gi-receipt\.py$' \
    "R2.2 ($skill): the Bundled dependency precheck lists it"
done

# ───────────────────────────────────────────────────────────
# R3-R10: behaviour, in throwaway repositories.
# ───────────────────────────────────────────────────────────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkrepo() {  # mkrepo DIR — a repo with one commit; prints nothing
  git init -q -b main "$1"
  git -C "$1" config user.email t@example.invalid
  git -C "$1" config user.name test
  echo one > "$1/a.txt"
  git -C "$1" add a.txt
  git -C "$1" commit -q -m one
}
R="$TMP/repo"
mkrepo "$R"
HEAD_SHA="$(git -C "$R" rev-parse HEAD)"
record() {  # record TESTS_SHA [COUNT] [UI-JSON] [PROFILE] — a valid stdin record
  printf '{"tool":"issue-resolver","profile":"%s","cycles":2,"review":"clean","ui":%s,"tests":{"count":%s,"sha":"%s","command":"bash tests/run.sh"}}' \
    "${4:-full}" "${3:-null}" "${2:-17}" "$1"
}
write() { (cd "$1" && python3 "$SCRIPT" --write); }
verify() { (cd "$1" && python3 "$SCRIPT" --verify "$2"); }

# R3: round trip.
set +e
out="$(record "$HEAD_SHA" | write "$R")"; ec=$?
set -e
check "R3.1: --write on a clean tree exits 0" "$ec"
[ "$(json_get "$out" sha)" = "$HEAD_SHA" ]; check "R3.2: the receipt is for HEAD, measured by the script" "$?"
STORE="$(cd "$R" && cd "$(git rev-parse --git-common-dir)" && pwd)/idd/receipts"
[ -f "$STORE/$HEAD_SHA.json" ]; check "R3.3: it is stored under the git common dir" "$?"
mode="$(python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$STORE/$HEAD_SHA.json")"
[ "$mode" = "0o600" ]; check "R3.4: the receipt file is private (0600, got $mode)" "$?"
v="$(verify "$R" "$HEAD_SHA")"
[ "$(json_get "$v" verified)" = "true" ]; check "R3.5: --verify accepts it" "$?"
[ "$(json_get "$v" tests)" = "17@$HEAD_SHA" ]; check "R3.6: --verify reports tests as count@sha for the marker comparison" "$?"
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); e=r["executor"]; sys.exit(0 if r["clean_tree"] is True and e.get("host") and "uid" in e and r["tests"]["command"] else 1)' "$STORE/$HEAD_SHA.json"
check "R3.7: it records clean tree, executor identity and the suite command" "$?"

# R4: absent.
OTHER="0123456789abcdef0123456789abcdef01234567"
set +e
v="$(verify "$R" "$OTHER")"; ec=$?
set -e
check "R4.1: an absent receipt is an answer (exit 0), not an error" "$ec"
[ "$(json_get "$v" verified)" = "false" ] && [ "$(json_get "$v" reason)" = "absent" ]
check "R4.2: an absent receipt is verified: false, reason absent" "$?"

# R5: a receipt never vouches for a different commit.
cp "$STORE/$HEAD_SHA.json" "$STORE/$OTHER.json"
[ "$(json_get "$(verify "$R" "$OTHER")" verified)" = "false" ]
check "R5.1: a receipt copied under another SHA's name does not verify" "$?"
rm -f "$STORE/$OTHER.json"

# R6: a dirty tree is refused, and nothing is written.
echo dirt > "$R/untracked.txt"
set +e
record "$HEAD_SHA" | write "$R" >/dev/null 2>&1; ec=$?
set -e
[ "$ec" = "4" ]; check "R6.1: --write on a dirty tree (untracked file) exits 4" "$?"
rm -f "$R/untracked.txt"
echo two >> "$R/a.txt"
git -C "$R" commit -q -am two
SHA2="$(git -C "$R" rev-parse HEAD)"
echo change >> "$R/a.txt"
set +e
record "$SHA2" | write "$R" >/dev/null 2>&1; ec=$?
set -e
[ "$ec" = "4" ] && [ ! -e "$STORE/$SHA2.json" ]
check "R6.2: --write on a modified tracked file exits 4 and writes nothing" "$?"
git -C "$R" checkout -q -- a.txt

# R7: one store per clone — a linked worktree writes, the main checkout verifies.
git -C "$R" worktree add -q "$TMP/lane" -b lane >/dev/null 2>&1
echo lane > "$TMP/lane/l.txt"
git -C "$TMP/lane" add l.txt
git -C "$TMP/lane" commit -q -m lane
LANE_SHA="$(git -C "$TMP/lane" rev-parse HEAD)"
record "$LANE_SHA" 3 | write "$TMP/lane" >/dev/null
[ "$(json_get "$(verify "$R" "$LANE_SHA")" verified)" = "true" ]
check "R7.1: a receipt written in a linked worktree verifies from the main checkout" "$?"

# R8: invalid input is exit 3 and writes nothing.
set +e
printf '{"tool":"issue-resolver","profile":"full","cycles":1,"review":"noted"}' | write "$R" >/dev/null 2>&1; ec1=$?
printf 'not json' | write "$R" >/dev/null 2>&1; ec2=$?
verify "$R" "5d73a6e" >/dev/null 2>&1; ec3=$?
verify "$R" "$(printf '%s' "$HEAD_SHA" | tr a-f A-F)" >/dev/null 2>&1; ec4=$?
set -e
[ "$ec1" = "3" ]; check "R8.1: a record whose review is not clean is refused (exit 3)" "$?"
[ "$ec2" = "3" ]; check "R8.2: a record that is not JSON is refused (exit 3)" "$?"
[ "$ec3" = "3" ]; check "R8.3: a short SHA is invalid input (exit 3)" "$?"
[ "$ec4" = "3" ]; check "R8.4: an uppercase SHA is invalid input (exit 3)" "$?"

# R9: tampering, foreign executors and symlinks never verify.
tamper() {  # tamper EXPR — rewrite the HEAD receipt with a python expression on r
  python3 - "$STORE/$SHA2.json" "$1" <<'PY'
import json, sys
p, expr = sys.argv[1], sys.argv[2]
r = json.load(open(p))
exec(expr)
json.dump(r, open(p, "w"))
PY
}
record "$SHA2" | write "$R" >/dev/null
cp "$STORE/$SHA2.json" "$TMP/good.json"
tamper 'r["clean_tree"] = False'
[ "$(json_get "$(verify "$R" "$SHA2")" verified)" = "false" ]; check "R9.1: a receipt recording a dirty tree does not verify" "$?"
cp "$TMP/good.json" "$STORE/$SHA2.json"
tamper 'r["executor"]["host"] = "elsewhere.invalid"'
[ "$(json_get "$(verify "$R" "$SHA2")" verified)" = "false" ]; check "R9.2: a receipt from another host does not verify" "$?"
cp "$TMP/good.json" "$STORE/$SHA2.json"
tamper 'r["review"] = "noted"'
[ "$(json_get "$(verify "$R" "$SHA2")" verified)" = "false" ]; check "R9.3: a receipt without review: clean does not verify" "$?"
rm -f "$STORE/$SHA2.json"
ln -s "$TMP/good.json" "$STORE/$SHA2.json"
[ "$(json_get "$(verify "$R" "$SHA2")" verified)" = "false" ]; check "R9.4: a symlinked receipt does not verify" "$?"
rm -f "$STORE/$SHA2.json"
echo evidence > "$TMP/suite.log"
printf '{"tool":"issue-resolver","profile":"full","cycles":1,"review":"clean","tests":null,"artifacts":["%s"]}' "$TMP/suite.log" | write "$R" >/dev/null
[ "$(json_get "$(verify "$R" "$SHA2")" verified)" = "true" ]; check "R9.5: a receipt with an intact artifact verifies" "$?"
echo forged >> "$TMP/suite.log"
[ "$(json_get "$(verify "$R" "$SHA2")" verified)" = "false" ]; check "R9.6: an artifact changed after the receipt makes it not verify" "$?"

# R10: tests evidence must come from this commit's history.
set +e
record "$LANE_SHA" | write "$R" >/dev/null 2>&1; ec=$?
set -e
[ "$ec" = "3" ]; check "R10.1: tests.sha that is not HEAD or an ancestor is refused (exit 3)" "$?"

# ───────────────────────────────────────────────────────────
# R11 (AC1, executable): the consumer's predicate, driven end to end.
#
# qa_verdict BODY HEADREFOID REPO — the QA handoff gate as SKILL.md and
# review-loop-mechanics.md state it: one v1 marker, 40-hex head= equal to the
# live head, review=clean, AND a receipt for that head that verifies and whose
# tests equal the marker's tests=. tests_skip adds the three-part AND of the
# skips table: trusted, tests= SHA equal to head, and ci_leg_runnable.
# ───────────────────────────────────────────────────────────
PARSE_RE='<!-- (gitissue|idd):qa v[0-9]+ [^>]*-->'
marker_field() {  # marker_field MARKER KEY — the value of one whole key=value pair
  local tok
  for tok in $1; do
    case "$tok" in "$2="*) printf '%s' "${tok#*=}"; return 0 ;; esac
  done
  return 1
}
qa_verdict() {
  local body="$1" head_ref="$2" repo="$3" m head review tests profile ui v
  m="$(printf '%s\n' "$body" | grep -oE "$PARSE_RE" || true)"
  [ -n "$m" ] || { echo absent; return; }
  [ "$(printf '%s\n' "$m" | grep -c .)" = "1" ] || { echo stale; return; }
  case "$m" in "<!-- idd:qa v1 "*|"<!-- gitissue:qa v1 "*) ;; *) echo stale; return ;; esac
  head="$(marker_field "$m" head || true)"
  review="$(marker_field "$m" review || true)"
  tests="$(marker_field "$m" tests || echo null)"
  profile="$(marker_field "$m" profile || echo null)"
  ui="$(marker_field "$m" ui || echo null)"
  printf '%s' "$head" | grep -qE '^[0-9a-f]{40}$' || { echo stale; return; }
  [ "$review" = "clean" ] && [ "$head" = "$head_ref" ] || { echo stale; return; }
  v="$(cd "$repo" && python3 "$SCRIPT" --verify "$head" 2>/dev/null)" || { echo stale; return; }
  [ "$(json_get "$v" verified)" = "true" ] || { echo stale; return; }
  [ "$(json_get "$v" tests)" = "$tests" ] || { echo stale; return; }
  [ "$(json_get "$v" profile)" = "$profile" ] || { echo stale; return; }
  [ "$(json_get "$v" ui)" = "$ui" ] || { echo stale; return; }
  echo trusted
}
tests_skip() {  # tests_skip VERDICT MARKER HEAD CI_LEG_RUNNABLE — yes | no
  local tests
  tests="$(marker_field "$2" tests || true)"
  if [ "$1" = trusted ] && [ "${tests#*@}" = "$3" ] && [ "$4" = true ]; then echo yes; else echo no; fi
}

# The forged marker is rendered from the producer's own template, so it is
# exactly what a genuine resolver would write — only the receipt is missing.
TEMPLATE="$(grep -oE '<!-- idd:qa v1 [^>]*-->' "$SRC_RES_PKG/references/report-templates.md" | grep -F '{head_sha}' | head -1 || true)"
[ -n "$TEMPLATE" ]; check "R11.0: the producer template still renders the marker" "$?"
F="$TMP/forge"
mkrepo "$F"
echo "untested change" >> "$F/a.txt"
git -C "$F" commit -q -am "never tested"
FHEAD="$(git -C "$F" rev-parse HEAD)"
render() {  # render HEAD COUNT
  printf '%s' "$TEMPLATE" | sed -e "s/{head_sha}/$1/g" -e "s/{profile}/full/g" -e "s/{qa_cycles}/1/g" \
    -e "s/{test_count}/$2/g" -e "s/{tests_sha}/$1/g" -e "s/{ui_legs}/code/g" \
    -e "s/{ui_result}/clean/g" -e "s/{ui_sha}/$1/g"
}
FORGED="$(render "$FHEAD" 128)"
BODY="Closes #515

## Summary
A PR whose author wrote the QA marker by hand.

$FORGED"
# An unrelated green check: non-empty, every check passing. ci_leg_runnable
# asks only that the rollup is non-empty with review.check_ci true.
ROLLUP='[{"name":"spellcheck","status":"COMPLETED","conclusion":"SUCCESS"}]'
CI_LEG_RUNNABLE="$(python3 -c 'import json,sys; print("true" if json.loads(sys.argv[1]) else "false")' "$ROLLUP")"
[ "$CI_LEG_RUNNABLE" = "true" ]; check "R11.1: (fixture) the unrelated green rollup makes ci_leg_runnable true" "$?"

verdict="$(qa_verdict "$BODY" "$FHEAD" "$F")"
[ "$verdict" = "stale" ]; check "R11.2 (AC1): a forged marker with no receipt is stale, not trusted" "$?"
[ "$(tests_skip "$verdict" "$FORGED" "$FHEAD" "$CI_LEG_RUNNABLE")" = "no" ]
check "R11.3 (AC1): forged marker + unrelated green CI skips no test run" "$?"

# Non-vacuity: the same predicate DOES trust a marker its receipt backs.
record "$FHEAD" 128 "\"code:clean@$FHEAD\"" | write "$F" >/dev/null
verdict="$(qa_verdict "$BODY" "$FHEAD" "$F")"
[ "$verdict" = "trusted" ]; check "R11.4: (vacuity guard) with a matching receipt the same marker is trusted" "$?"
[ "$(tests_skip "$verdict" "$FORGED" "$FHEAD" "$CI_LEG_RUNNABLE")" = "yes" ]
check "R11.5: (vacuity guard) and only then is the duplicate test run skipped" "$?"
# A real receipt never lends trust to a different claimed count.
INFLATED="$(render "$FHEAD" 999)"
[ "$(qa_verdict "${BODY/$FORGED/$INFLATED}" "$FHEAD" "$F")" = "stale" ]
check "R11.6: a marker whose tests= the receipt does not back is stale" "$?"
# Nor to a forged depth claim or UI leg — both drive skips of their own.
LIGHT="${FORGED/profile=full/profile=light}"
[ "$(qa_verdict "${BODY/$FORGED/$LIGHT}" "$FHEAD" "$F")" = "stale" ]
check "R11.6b: a marker whose profile= the receipt does not back is stale" "$?"
UIB="${FORGED/ui=code:clean/ui=code+browser:clean}"
[ "$(qa_verdict "${BODY/$FORGED/$UIB}" "$FHEAD" "$F")" = "stale" ]
check "R11.6c: a marker whose ui= the receipt does not back is stale" "$?"
# A receipt for an older commit does not cover a newer head.
echo more >> "$F/a.txt"
git -C "$F" commit -q -am "after the receipt"
NEW="$(git -C "$F" rev-parse HEAD)"
NEWM="$(render "$NEW" 128)"
[ "$(qa_verdict "${BODY/$FORGED/$NEWM}" "$NEW" "$F")" = "stale" ]
check "R11.7: a marker re-pointed at a newer head has no receipt and is stale" "$?"

# ───────────────────────────────────────────────────────────
# R12-R14: the prose contract, src and built.
# ───────────────────────────────────────────────────────────
for pair in "src:$SRC_PR_PKG" "built:$BUILT_PR_PKG"; do
  tag="${pair%%:*}"
  pkg="${pair#*:}"
  skill="$pkg/SKILL.source.md"; [ -f "$skill" ] || skill="$pkg/SKILL.md"
  trusted_row="$(grep -E '^\| `trusted` \| the marker parses' "$skill" | head -1 || true)"
  if printf '%s' "$trusted_row" | grep -q 'revision receipt for that SHA verifies'; then
    pass "R12.1 ($tag): the trusted row itself requires a verified receipt"
  else
    fail "R12.1 ($tag): the trusted row does not require a verified receipt"
  fi
  anchor_check "$pkg" rv-receipt-gate 'gi-receipt\.py --verify "\$head_oid"' \
    "R12.2 ($tag): the gate verifies the receipt for the live head"
  anchor_check "$pkg" rv-receipt-gate 'before Step 2 runs any PR code' \
    "R12.3 ($tag): the receipt is read before any PR code runs"
  anchor_check "$pkg" rv-receipt-gate 'No prose fallback may produce `trusted`' \
    "R12.4 ($tag): no degrade path can produce trusted"
  anchor_check "$pkg" rv-receipt-gate 'without a receipt, skips nothing' \
    "R12.5 ($tag): a marker plus green CI without a receipt skips nothing"
  anchor_check "$pkg" rv-receipt-gate "receipt's .profile., .tests. and .ui. equal the marker's .profile=., .tests=. and .ui=." \
    "R12.6 ($tag): the receipt must agree with the marker's profile=, tests= and ui="
  anchor_check_flat "$pkg" rvm-verify-receipt 'Re-evaluation never re-reads the store' \
    "R12.7 ($tag): re-evaluation after a push never re-reads the store"
  anchor_check_flat "$pkg" rvm-verify-receipt 'not cryptographic authentication' \
    "R12.8 ($tag): the receipt's limits are stated, not oversold"
  anchor_check_flat "$pkg" rvm-parse-marker 'revision receipt for that[[:space:]]+SHA verifies' \
    "R12.9 ($tag): the parse rules' trusted-iff names the receipt"
done

for pair in "src:$SRC_RES_PKG" "built:$BUILT_RES_PKG"; do
  tag="${pair%%:*}"
  pkg="${pair#*:}"
  anchor_check "$pkg" rs-revision-receipt 'gi-receipt\.py --write' \
    "R13.1 ($tag): Deliver writes the receipt"
  anchor_check "$pkg" rs-revision-receipt 'Whenever the marker is filled' \
    "R13.2 ($tag): a receipt is written whenever the marker is"
  anchor_check "$pkg" rs-revision-receipt 'never hand-write one' \
    "R13.3 ($tag): the degrade never hand-writes a receipt"
  anchor_check_flat "$pkg" rt-revision-receipt '`null` whenever the marker omits `tests=`' \
    "R13.4 ($tag): tests is optional, mirroring the marker's omit rule"
  anchor_check_flat "$pkg" rt-revision-receipt 'never what the record claims' \
    "R13.5 ($tag): the script measures HEAD and the clean tree itself"
  check_has "$pkg/references/steps/step-4-qa.md" 'tests_command' \
    "R13.6 ($tag): Step 4 keeps the suite command for the receipt"
done

for f in "$REPO_ROOT/docs/idd-methodology.md" "$BUILT_PR_PKG/references/docs/idd-methodology.md"; do
  check_has "$f" 'revision receipt' "R14.1 (${f#$REPO_ROOT/}): the methodology names the receipt"
done
for f in "$REPO_ROOT/src/skills/auto-pilot/references/phases/phase-3-4-review.md" \
         "$REPO_ROOT/skills/auto-pilot/references/phases/phase-3-4-review.md"; do
  check_has "$f" 'backed by a verified revision receipt' \
    "R14.2 (${f#$REPO_ROOT/}): auto-pilot's narration ties the skip to the receipt"
done

echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
