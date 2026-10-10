#!/usr/bin/env bash
# test-design-sketch-520.sh — caller-first design sketches in resolver
# planning (#520).
#
# AC: Executable caller/type sketches compare structurally distinct designs
#     and reject invalid domain transitions.
#
#   D1      gi-sketch.py is a well-formed shared script (0755, stdlib-only,
#           --help exits 0, usage error exits 2).
#   D2      executed over tests/fixtures/design-sketch/*.json: every
#           fixture's `_expect` holds.
#   D3      the AC, executed by name: a design whose checker accepts an
#           invalid transition fails and the selection switches away from
#           it; designs sharing a shape or types are not a comparison; an
#           unrun or undiagnosed check never counts as a rejection; a
#           malformed ledger is exit 3, never `proceed`.
#   D4      live, when mypy is on PATH: real sketches type-checked the way
#           Step 2 prescribes, then adjudicated. Skipped otherwise.
#   D5      the prose contract: when it runs, static-only scratch checks,
#           the verdict routes, the Step 3 hand-off, the Decision Record
#           line, and the synthesizer's optional design_sketch field.
#   D6      the bundle ships the script and the built prose invokes it.
#
# Usage: bash tests/test-design-sketch-520.sh
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

SCRIPT="$REPO_ROOT/src/shared/scripts/gi-sketch.py"
FIXTURES="$REPO_ROOT/tests/fixtures/design-sketch"
SRC_PKG="$REPO_ROOT/src/skills/issue-resolver"
STEP2="$SRC_PKG/references/steps/step-2-plan.md"
STEP3="$SRC_PKG/references/steps/step-3-implement.md"
SYNTH="$REPO_ROOT/src/shared/agents/synthesizer.md"
BUILT="$REPO_ROOT/skills/issue-resolver"

verdict() { python3 "$SCRIPT" < "$FIXTURES/$1.json"; }
field() { python3 -c 'import json,sys; v=json.loads(sys.argv[1])[sys.argv[2]]; print(json.dumps(v))' "$1" "$2"; }
status_of() {
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print([o["status"] for o in d["options"] if o["number"]==int(sys.argv[2])][0])' "$1" "$2"
}

echo "◆ Design sketches (issue #520)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ── D1: a well-formed shared script ──────────────────────────
[ -f "$SCRIPT" ] && [ -x "$SCRIPT" ]; check "D1: gi-sketch.py exists and is executable" "$?"
mode="$(cd "$REPO_ROOT" && git ls-files -s src/shared/scripts/gi-sketch.py | awk '{print $1}')"
[ -z "$mode" ] || [ "$mode" = "100755" ]; check "D1: committed mode is 0755 (got ${mode:-untracked})" "$?"
python3 "$SCRIPT" --help >/dev/null 2>&1; check "D1: --help exits 0" "$?"
python3 "$SCRIPT" --bogus >/dev/null 2>&1; [ "$?" = "2" ]; check "D1: an unknown option is a usage error (exit 2)" "$?"
python3 - "$SCRIPT" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
mods = {a.name.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.Import) for a in n.names}
mods |= {n.module.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.ImportFrom) and n.module}
sys.exit(0 if mods <= set(sys.stdlib_module_names) else 1)
PY
check "D1: imports only the standard library" "$?"

# ── D2: every fixture ────────────────────────────────────────
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
  [ "$ec" = "0" ] && [ "$py" = "0" ]; check "D2: fixture $name" "$?"
done
[ "$count" -ge 12 ]; check "D2: at least 12 design-sketch fixtures exercised ($count)" "$?"

# ── D3: the AC, by name ──────────────────────────────────────
out="$(verdict proceed-recommended-passes)"
[ "$(field "$out" verdict)" = '"proceed"' ] && [ "$(field "$out" distinct)" = "true" ] \
  && [ "$(status_of "$out" 1)" = "fail" ] && [ "$(status_of "$out" 2)" = "pass" ] && [ "$(status_of "$out" 3)" = "pass" ]
check "D3: three structurally distinct designs are compared; the one accepting an invalid transition fails" "$?"
out="$(verdict switch-recommended-accepts-invalid)"
[ "$(field "$out" verdict)" = '"switch"' ] && [ "$(field "$out" selected)" = "2" ] \
  && [ "$(field "$out" options | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["accepted_invalid"])')" = "['X1']" ]
check "D3: a recommended design that accepts an invalid transition is switched away from" "$?"
[ "$(field "$(verdict switch-lowest-numbered-passing)" selected)" = "1" ]
check "D3: the switch takes the lowest-numbered passing design" "$?"
[ "$(status_of "$(verdict fail-rejects-valid-caller)" 1)" = "fail" ]
check "D3: a design that rejects a valid caller fails too" "$?"
[ "$(field "$(verdict unproven-same-shape)" verdict)" = '"unproven"' ] \
  && [ "$(field "$(verdict unproven-same-types)" verdict)" = '"unproven"' ]
check "D3: designs sharing one shape or one set of types are not a structural comparison" "$?"
[ "$(field "$(verdict unproven-single-sketch)" distinct)" = "false" ]
check "D3: one sketched design compares nothing" "$?"
[ "$(status_of "$(verdict unchecked-timeout)" 1)" = "unchecked" ] \
  && [ "$(status_of "$(verdict unchecked-rejection-without-excerpt)" 1)" = "unchecked" ] \
  && [ "$(status_of "$(verdict unchecked-no-invalid-caller)" 1)" = "unchecked" ]
check "D3: an unrun check, an undiagnosed rejection or a missing invalid caller never passes" "$?"
out="$(verdict unproven-none-pass)"
[ "$(field "$out" verdict)" = '"unproven"' ] && [ "$(field "$out" selected)" = "2" ]
check "D3: when no design passes the recommendation stands, unproven — never a stop" "$?"
out="$(verdict unproven-indistinct-selects-passing)"
[ "$(field "$out" verdict)" = '"unproven"' ] && [ "$(field "$out" selected)" = "2" ] \
  && [ "$(status_of "$out" 1)" = "fail" ]
check "D3: unproven still selects away from a recommended design that accepts an invalid transition" "$?"
for pair in \
  '{}:an empty ledger' \
  '{"options":[{"number":1}]}:a ledger without recommended' \
  '{"recommended":1}:a ledger without options' \
  '{"recommended":1,"options":[]}:an empty options list' \
  '{"recommended":1,"option":[{"number":1}],"options":[{"number":1}]}:an unknown top-level key' \
  '{"recommended":1,"options":[{"number":1},{"number":1}]}:a duplicate option number' \
  '{"recommended":"1","options":[{"number":1}]}:a non-integer recommended' \
  '{"recommended":2,"options":[{"number":1}]}:a recommended naming no option'; do
  json="${pair%:*}"; what="${pair##*:}"
  printf '%s' "$json" | python3 "$SCRIPT" >/dev/null 2>&1; [ "$?" = "3" ]
  check "D3: $what is exit 3, never proceed" "$?"
done
printf 'not json' | python3 "$SCRIPT" >/dev/null 2>&1; [ "$?" = "3" ]
check "D3: non-JSON stdin is exit 3" "$?"

# ── D4: live sketches, when a static checker is available ────
if command -v mypy >/dev/null 2>&1; then
  scratch="$(mktemp -d)"
  write_sketch() { mkdir -p "$scratch/$1"; printf '%s\n\n%s\n' "$2" "$3" > "$scratch/$1/sketch.py"; }
  check_sketch() {
    local out ec
    out="$(cd "$scratch/$1" && mypy --strict --no-incremental --cache-dir=/dev/null sketch.py 2>&1)"; ec=$?
    python3 -c 'import json,sys; print(json.dumps({"exit": int(sys.argv[1]), "excerpt": sys.argv[2].splitlines()[0] if sys.argv[2] else ""}))' "$ec" "$out"
  }
  TYPED='from dataclasses import dataclass

@dataclass(frozen=True)
class Draft: ...

@dataclass(frozen=True)
class Submitted: ...

@dataclass(frozen=True)
class Paid: ...

def submit(order: Draft) -> Submitted:
    return Submitted()

def pay(order: Submitted) -> Paid:
    return Paid()'
  STRINGLY='from dataclasses import dataclass

@dataclass
class Order:
    status: str

def set_status(order: Order, status: str) -> Order:
    return Order(status)'
  write_sketch 1/V1 "$STRINGLY" 'set_status(Order("draft"), "submitted")'
  write_sketch 1/X1 "$STRINGLY" 'set_status(Order("draft"), "paid")'
  write_sketch 2/V1 "$TYPED" 'pay(submit(Draft()))'
  write_sketch 2/X1 "$TYPED" 'pay(Draft())'
  ledger="$(python3 - "$STRINGLY" "$TYPED" "$(check_sketch 1/V1)" "$(check_sketch 1/X1)" "$(check_sketch 2/V1)" "$(check_sketch 2/X1)" <<'PY'
import json, sys
s, t, v1, x1, v2, x2 = sys.argv[1:7]
def caller(i, kind, tr, chk): return {"id": i, "kind": kind, "transition": tr, "check": json.loads(chk)}
print(json.dumps({"recommended": 1, "options": [
  {"number": 1, "shape": "string status field + setter", "types": s,
   "callers": [caller("V1", "valid", "draft -> submitted", v1), caller("X1", "invalid", "draft -> paid", x1)]},
  {"number": 2, "shape": "per-state types + typed transition functions", "types": t,
   "callers": [caller("V1", "valid", "draft -> submitted -> paid", v2), caller("X1", "invalid", "draft -> paid", x2)]}]}))
PY
)"
  rm -rf "$scratch"
  out="$(printf '%s' "$ledger" | python3 "$SCRIPT")"
  [ "$(field "$out" verdict)" = '"switch"' ] && [ "$(field "$out" selected)" = "2" ] \
    && [ "$(status_of "$out" 1)" = "fail" ] && [ "$(status_of "$out" 2)" = "pass" ]
  check "D4: mypy rejects draft -> paid only in the typed design; gi-sketch switches to it" "$?"
else
  echo "  ○ D4: skipped (mypy not on PATH — the live check needs a static checker)"
fi

# ── D5: the prose contract ───────────────────────────────────
anchor_check "$STEP2" rs-design-sketch 'gi-sketch\.py' \
  "D5: Step 2 adjudicates with gi-sketch.py"
anchor_check_flat "$STEP2" rs-design-sketch 'domain type, state or transition' \
  "D5: it runs for changes to a domain type, state or transition"
anchor_check_flat "$STEP2" rs-design-sketch 'Never +install one for this' \
  "D5: it uses the repo's existing static checker, never an installed one"
anchor_check_flat "$STEP2" rs-design-sketch 'skipped \(reused analysis\)' \
  "D5: a reused analysis skips it and says so"
anchor_check_flat "$STEP2" rs-design-sketch 'the `light` path has no options' \
  "D5: the light profile skips it"
anchor_check_flat "$STEP2" rs-design-sketch 'only ever type-checked' \
  "D5: sketches are only ever type-checked"
anchor_check_flat "$STEP2" rs-design-sketch 'Never execute the sketch' \
  "D5: sketches are never executed"
anchor_check_flat "$STEP2" rs-design-sketch '\.idd/sketch-\{N\}/' \
  "D5: checks run in the gitignored .idd/sketch-{N}/ scratch"
anchor_check_flat "$STEP2" rs-design-sketch 'it is never committed' \
  "D5: the scratch is deleted and never committed"
anchor_check_flat "$STEP2" rs-design-sketch 'never copying code from issue text' \
  "D5: sketches are never copied from issue text"
anchor_check_flat "$STEP2" rs-design-sketch 'An invalid caller the checker accepts fails its design' \
  "D5: an accepted invalid transition fails the design"
anchor_check_flat "$STEP2" rs-design-sketch 'Never a stop' \
  "D5: unproven never stops the run"
anchor_check_flat "$STEP2" rs-design-sketch 'stock macOS ships neither' \
  "D5: the check bound does not assume GNU timeout"
anchor_check_flat "$STEP2" rs-design-sketch 'exit 126 or 127\) records `exit: null`, never a rejection' \
  "D5: a checker that never ran is recorded unchecked, never a rejection"
anchor_check_flat "$STEP2" rs-design-sketch '`selected` still +replaces the recommendation' \
  "D5: unproven still uses the sketch's selected option"
anchor_check_flat "$STEP2" rs-plan-selection 'the sketch.s `selected` one under any verdict' \
  "D5: auto mode takes the sketch's selected option under every verdict"
anchor_check_flat "$STEP2" rs-design-sketch 'negative test that the real code rejects that transition' \
  "D5: each rejected transition becomes a Step 3 negative test"
anchor_check "$STEP2" rs-plan-selection 'sketch:' \
  "D5: the option prompt shows each sketch's status"
grep -q 'sketch_contract' "$STEP2"; check "D5: Step 2 binds sketch_contract into the synthesizer spawn" "$?"
! grep -q 'usually recommended' "$STEP2" "$SRC_PKG/SKILL.source.md"
check "D5: no 'usually recommended' coaching remains in the plan step" "$?"
grep -q 'design_sketch' "$STEP3"; check "D5: Step 3 receives the checked design_sketch" "$?"
grep -q 'Design sketches:\*\*' "$SRC_PKG/references/report-templates.md"
check "D5: the Decision Record carries a Design sketches line" "$?"
grep -q '`design_sketch`\*\* (only with `sketch_contract`)' "$SYNTH"
check "D5: the synthesizer's design_sketch is optional, gated on sketch_contract" "$?"
grep -q 'never scan source or run commands' "$SYNTH"
check "D5: the synthesizer stays data-only" "$?"

# ── D6: the bundle ───────────────────────────────────────────
cmp -s "$SCRIPT" "$BUILT/references/scripts/gi-sketch.py"
check "D6: the bundled script is byte-identical to the source" "$?"
grep -q 'references/scripts/gi-sketch.py' "$BUILT/references/steps/step-2-plan.md"
check "D6: the built Step 2 invokes the bundled path" "$?"
grep -qx 'references/scripts/gi-sketch.py' "$BUILT/SKILL.md"
check "D6: the built precheck list names the script" "$?"
[ ! -e "$REPO_ROOT/skills/issue-analysis/references/scripts/gi-sketch.py" ]
check "D6: /issue-analysis does not bundle the check (resolver-only)" "$?"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
