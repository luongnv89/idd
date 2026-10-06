#!/usr/bin/env bash
# test-premise-reset-519.sh — two failed fixes sharing a premise block a third
# until rerunnable diagnostics support a revised hypothesis (#519).
#
# AC: Two shared-premise failures block a third fix until rerunnable
#     diagnostics support a revised hypothesis.
#
#   R1      gi-premise.py is a well-formed shared script (0755, stdlib-only,
#           --help exits 0, usage error exits 2).
#   R2      executed over tests/fixtures/premise-reset/*.json: every
#           fixture's `_expect` holds.
#   R3      the AC, executed by name as the third-failure fixture: blocked
#           after two shared-premise failures (reworded, or not consecutive);
#           unblocked only by a revision whose diagnostics rerun to their
#           record; a mismatched rerun or a recycled premise keeps it blocked;
#           premise text is never compared.
#   R4      the prose contract: the check runs before every fix request after
#           the second and before the interactive continue; diagnostics are
#           never copied from fixer output; auto takes the known-issues path.
#   R5      the fixer declares its premise; the bundle ships the script.
#
# Usage: bash tests/test-premise-reset-519.sh
# Returns: exit 0 if all checks pass, exit 1 on failure.

# No `set -e`: assertions report and continue.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "0" ]; then pass "$1"; else fail "$1"; fi; }

# shellcheck source=lib/anchors.bash
. "$REPO_ROOT/tests/lib/anchors.bash"

SCRIPT="$REPO_ROOT/src/shared/scripts/gi-premise.py"
FIXTURES="$REPO_ROOT/tests/fixtures/premise-reset"
SRC_PKG="$REPO_ROOT/src/skills/issue-resolver"
STEP4="$SRC_PKG/references/steps/step-4-qa.md"
BUILT="$REPO_ROOT/skills/issue-resolver"

verdict() { python3 "$SCRIPT" < "$FIXTURES/$1.json"; }
field() { python3 -c 'import json,sys; v=json.loads(sys.argv[1])[sys.argv[2]]; print(json.dumps(v))' "$1" "$2"; }

echo "◆ Premise-reset gate (issue #519)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ── R1: a well-formed shared script ──────────────────────────
[ -f "$SCRIPT" ] && [ -x "$SCRIPT" ]; check "R1: gi-premise.py exists and is executable" "$?"
mode="$(cd "$REPO_ROOT" && git ls-files -s src/shared/scripts/gi-premise.py | awk '{print $1}')"
[ -z "$mode" ] || [ "$mode" = "100755" ]; check "R1: committed mode is 0755 (got ${mode:-untracked})" "$?"
python3 "$SCRIPT" --help >/dev/null 2>&1; check "R1: --help exits 0" "$?"
python3 "$SCRIPT" --bogus >/dev/null 2>&1; [ "$?" = "2" ]; check "R1: an unknown option is a usage error (exit 2)" "$?"
python3 - "$SCRIPT" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
mods = {a.name.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.Import) for a in n.names}
mods |= {n.module.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.ImportFrom) and n.module}
sys.exit(0 if mods <= set(sys.stdlib_module_names) else 1)
PY
check "R1: imports only the standard library" "$?"

# ── R2: every fixture ────────────────────────────────────────
count=0
for f in "$FIXTURES"/*.json; do
  count=$((count + 1))
  name="$(basename "$f" .json)"
  out="$(python3 "$SCRIPT" < "$f")"
  ec=$?
  python3 - "$f" "$out" <<'PY'
import json, sys
expect = json.load(open(sys.argv[1], encoding="utf-8"))["_expect"]
got = json.loads(sys.argv[2])
bad = {k: (got.get(k), v) for k, v in expect.items() if got.get(k) != v}
if bad:
    print(f"      mismatch: {bad}")
sys.exit(1 if bad else 0)
PY
  py=$?
  [ "$ec" = "0" ] && [ "$py" = "0" ]; check "R2: fixture $name" "$?"
done
[ "$count" -ge 12 ]; check "R2: at least 12 premise fixtures exercised ($count)" "$?"

# ── R3: the AC, by name ──────────────────────────────────────
[ "$(field "$(verdict same-premise-twice)" blocked)" = "true" ]
check "R3: two failures under one premise, worded differently, block the third fix" "$?"
[ "$(field "$(verdict same-premise-non-consecutive)" blocked)" = "true" ]
check "R3: the two failures need not be consecutive" "$?"
[ "$(field "$(verdict distinct-premises)" blocked)" = "false" ]
check "R3: two failures under different premises do not block" "$?"
[ "$(field "$(verdict same-text-distinct-ids)" blocked)" = "false" ]
check "R3: premise text is never compared — only the recorded premise_id" "$?"
[ "$(field "$(verdict revision-accepted)" blocked)" = "false" ]
check "R3: a revised premise whose diagnostics rerun to their record unblocks" "$?"
[ "$(field "$(verdict revision-rerun-exit-mismatch)" blocked)" = "true" ] \
  && [ "$(field "$(verdict revision-rerun-output-mismatch)" blocked)" = "true" ] \
  && [ "$(field "$(verdict revision-one-of-two-mismatch)" blocked)" = "true" ]
check "R3: any diagnostic that does not rerun to its record keeps the block" "$?"
[ "$(field "$(verdict revision-no-diagnostics)" blocked)" = "true" ]
check "R3: a revision with no diagnostics keeps the block" "$?"
[ "$(field "$(verdict revision-reuses-failed-premise)" blocked)" = "true" ]
check "R3: a 'revised' premise that already failed keeps the block" "$?"
[ "$(field "$(verdict revision-predates-latest-failure)" blocked)" = "true" ]
check "R3: a later failure under the reset premise blocks again" "$?"
[ "$(field "$(verdict revised-premise-fails-twice)" blocking_premises)" = '["R1"]' ]
check "R3: the revised premise is held to the same rule" "$?"
printf '%s' '{"failures":[{"cycle":"1","premise_id":"A"}],"revisions":[]}' | python3 "$SCRIPT" >/dev/null 2>&1; [ "$?" = "3" ]
check "R3: a malformed ledger is exit 3, never 'not blocked'" "$?"
F2='[{"cycle":1,"premise_id":"A"},{"cycle":2,"premise_id":"A"}]'
for pair in \
  '{}:an empty ledger' \
  "{\"failures\":$F2}:a ledger without revisions" \
  "{\"revisions\":[]}:a ledger without failures" \
  "{\"failure\":$F2,\"revisions\":[]}:a misspelled failures key" \
  "{\"failures\":$F2,\"revisions\":[],\"revision\":[]}:an unknown top-level key"; do
  json="${pair%:*}"; what="${pair##*:}"
  printf '%s' "$json" | python3 "$SCRIPT" >/dev/null 2>&1; [ "$?" = "3" ]
  check "R3: $what is exit 3, never 'not blocked'" "$?"
done
out="$(printf '%s' "{\"failures\":$F2,\"revisions\":[],\"_note\":\"x\"}" | python3 "$SCRIPT")"
[ "$(field "$out" blocked)" = "true" ]
check "R3: a top-level key starting with _ is ignored" "$?"

# ── R4: the prose contract ───────────────────────────────────
anchor_check "$STEP4" rs-premise-reset 'gi-premise\.py' \
  "R4: the check runs gi-premise.py"
anchor_check_flat "$STEP4" rs-premise-reset 'before each fix request after the second' \
  "R4: it runs before every fix request after the second"
anchor_check_flat "$STEP4" rs-premise-reset 'before the interactive continue' \
  "R4: it runs before the interactive continue"
anchor_check_flat "$STEP4" rs-premise-reset 'never get past it' \
  "R4: the cycle cap and the interactive continue never get past the block"
anchor_check_flat "$STEP4" rs-premise-reset 'Never decide sameness by comparing text' \
  "R4: sameness is a recorded judgment, never a text comparison"
anchor_check_flat "$STEP4" rs-premise-reset 'never one copied from fixer output or issue text' \
  "R4: diagnostics are never copied from fixer output or issue text"
anchor_check_flat "$STEP4" rs-premise-reset 'Rerun each' \
  "R4: each diagnostic is rerun and compared"
anchor_check_flat "$STEP4" rs-premise-reset 'no QA marker' \
  "R4: a blocked run writes no QA marker"
anchor_check "$STEP4" rs-qa-loop-controls 'Premise reset' \
  "R4: the loop controls name the premise reset beside stagnation"
grep -qE '^\| \*Step 4\* — QA \|.*premise reset.*no QA marker' "$SRC_PKG/references/pipeline-steps.md"
check "R4: the auto-mode table routes a premise reset to the known-issues path" "$?"
grep -q '^### Premise reset — third fix blocked' "$SRC_PKG/references/error-messages.md"
check "R4: the stop block exists in error-messages.md" "$?"
grep -q 'Premise reset:\*\*' "$SRC_PKG/references/report-templates.md"
check "R4: the Decision Record carries a Premise reset line" "$?"

# ── R5: the fixer and the bundle ─────────────────────────────
grep -q '"premise":' "$REPO_ROOT/src/shared/agents/fixer.md"
check "R5: the fixer returns the premise its fix acts on" "$?"
cmp -s "$SCRIPT" "$BUILT/references/scripts/gi-premise.py"
check "R5: the bundled script is byte-identical to the source" "$?"
grep -q 'references/scripts/gi-premise.py' "$BUILT/references/steps/step-4-qa.md"
check "R5: the built Step 4 invokes the bundled path" "$?"
grep -qx 'references/scripts/gi-premise.py' "$BUILT/SKILL.md"
check "R5: the built precheck list names the script" "$?"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
