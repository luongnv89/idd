#!/usr/bin/env bash
# test-skill-bundle-budget-466.sh — Per-skill bundle size budgets (issue #466)
#
# Acceptance criteria:
#  - AC1: every emitted skill bundle has a recorded budget that CI enforces
#  - AC2: growing a bundle past its budget fails; shrinking it lets the budget
#         tighten
#  - AC3: a documented mechanism (scripts/skill-budget.py --ratchet) lowers the
#         ceilings as the footprint shrinks — no hand-edited constants
#  - AC4: budgets and current measurements live in one place
#         (scripts/skill-budgets.json), and a stale measurement fails
#
# Every negative case runs on a synthetic skills tree and a copy of a budgets
# file under mktemp -d, via --skills-dir/--budgets. The committed
# scripts/skill-budgets.json is only ever read.
#
# Usage: bash tests/test-skill-bundle-budget-466.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/skill-budget.py"
BUDGETS="$REPO_ROOT/scripts/skill-budgets.json"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "◆ Skill bundle budget tests (issue #466)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# run <args...> — run the script, capture output in $OUT and status in $RC.
run() {
  set +e
  OUT="$(python3 "$SCRIPT" "$@" 2>&1)"
  RC=$?
  set -e
}

# field <budgets-file> <skill> <budget|measured>
field() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["skills"][sys.argv[2]][sys.argv[3]])' "$1" "$2" "$3"
}

# write_bytes <file> <count> — a file of exactly <count> bytes.
write_bytes() {
  mkdir -p "$(dirname "$1")"
  python3 -c 'import sys; open(sys.argv[1], "w").write("x" * int(sys.argv[2]))' "$1" "$2"
}

# ── Script surface ────────────────────────────────────────────────────────
if [ -f "$SCRIPT" ]; then
  pass "scripts/skill-budget.py exists"
else
  fail "scripts/skill-budget.py is missing"
fi

mode="$(git -C "$REPO_ROOT" ls-files -s scripts/skill-budget.py | awk '{print $1}')"
if [ "$mode" = "100755" ]; then
  pass "scripts/skill-budget.py is committed with mode 100755"
else
  fail "scripts/skill-budget.py committed mode is '${mode:-untracked}', want 100755"
fi

run --help
if [ "$RC" -eq 0 ]; then
  pass "--help exits 0"
else
  fail "--help exited $RC"
fi

# ── AC1 / AC4: the committed budgets cover exactly the built skills ───────
if git -C "$REPO_ROOT" ls-files --error-unmatch scripts/skill-budgets.json >/dev/null 2>&1; then
  pass "scripts/skill-budgets.json is committed"
else
  fail "scripts/skill-budgets.json is not tracked"
fi

want="$(find "$REPO_ROOT/skills" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -exec basename {} \; | sort | tr '\n' ' ')"
got="$(python3 -c 'import json,sys; print(" ".join(sorted(json.load(open(sys.argv[1]))["skills"])))' "$BUDGETS" | tr -d '\n') "
if [ "$want" = "$got" ]; then
  pass "budgets cover exactly the skills/ directories ($(echo "$want" | wc -w | tr -d ' '))"
else
  fail "budgets cover [$got], skills/ holds [$want]"
fi

run --check
if [ "$RC" -eq 0 ]; then
  pass "--check passes on the committed skills/ tree"
else
  fail "--check fails on the committed tree (exit $RC) — run: ./scripts/build.sh && python3 scripts/skill-budget.py --ratchet"
  echo "$OUT" | sed 's/^/    /'
fi

run --check --json
if [ "$RC" -eq 0 ] && python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["ok"] is True and d["skills"]' "$OUT" 2>/dev/null; then
  pass "--json prints the budget table as a JSON object"
else
  fail "--json output is not the expected JSON object (exit $RC)"
fi

# ── Synthetic fixture: two skills, 5,000 and 3,000 prompt bytes ───────────
# new_fixture <dir> — build the tree and ratchet a fresh budgets file for it.
new_fixture() {
  rm -rf "$1"
  write_bytes "$1/skills/alpha/SKILL.md" 4000
  write_bytes "$1/skills/alpha/references/notes.md" 1000
  write_bytes "$1/skills/beta/SKILL.md" 3000
  python3 "$SCRIPT" --skills-dir "$1/skills" --budgets "$1/budgets.json" --ratchet >/dev/null
}

F="$TMP/fx"
new_fixture "$F"
if [ "$(field "$F/budgets.json" alpha measured)" = "5000" ] && \
   [ "$(field "$F/budgets.json" alpha budget)" = "6024" ] && \
   [ "$(field "$F/budgets.json" beta budget)" = "4024" ]; then
  pass "--ratchet seeds a new file at measured + 1024 headroom"
else
  fail "--ratchet seeded unexpected values: $(cat "$F/budgets.json")"
fi

run --skills-dir "$F/skills" --budgets "$F/budgets.json" --check
if [ "$RC" -eq 0 ]; then
  pass "--check passes on a freshly ratcheted fixture"
else
  fail "--check fails on a freshly ratcheted fixture (exit $RC)"
fi

# (a) growth past the budget → exit 1, with the fix spelled out.
write_bytes "$F/skills/alpha/references/extra.md" 2000
run --skills-dir "$F/skills" --budgets "$F/budgets.json" --check
if [ "$RC" -eq 1 ] && echo "$OUT" | grep -q 'over budget' && \
   echo "$OUT" | grep -q 'never raises'; then
  pass "(a) growth past the budget fails --check (exit 1) and says --ratchet never raises"
else
  fail "(a) growth past the budget: exit $RC, output: $OUT"
fi

# (d) --ratchet refuses to raise an over-budget skill, still refreshes others.
write_bytes "$F/skills/beta/SKILL.md" 2500
run --skills-dir "$F/skills" --budgets "$F/budgets.json" --ratchet
if [ "$RC" -eq 1 ] && [ "$(field "$F/budgets.json" alpha budget)" = "6024" ]; then
  pass "(d) --ratchet exits 1 and leaves the over-budget skill's budget unchanged"
else
  fail "(d) --ratchet on an over-budget skill: exit $RC, alpha budget $(field "$F/budgets.json" alpha budget)"
fi
if [ "$(field "$F/budgets.json" beta measured)" = "2500" ] && \
   [ "$(field "$F/budgets.json" beta budget)" = "3524" ]; then
  pass "(d) --ratchet still refreshes and tightens the other skills"
else
  fail "(d) beta not refreshed: $(cat "$F/budgets.json")"
fi

# (b) growth within headroom but an unrefreshed measurement → exit 1; then
#     --ratchet makes --check pass without raising the budget.
new_fixture "$F"
write_bytes "$F/skills/alpha/references/extra.md" 500
run --skills-dir "$F/skills" --budgets "$F/budgets.json" --check
if [ "$RC" -eq 1 ] && echo "$OUT" | grep -q 'measurement out of date'; then
  pass "(b) growth within headroom with a stale measurement fails --check (exit 1)"
else
  fail "(b) stale measurement: exit $RC, output: $OUT"
fi
python3 "$SCRIPT" --skills-dir "$F/skills" --budgets "$F/budgets.json" --ratchet >/dev/null
run --skills-dir "$F/skills" --budgets "$F/budgets.json" --check
if [ "$RC" -eq 0 ] && [ "$(field "$F/budgets.json" alpha budget)" = "6024" ] && \
   [ "$(field "$F/budgets.json" alpha measured)" = "5500" ]; then
  pass "(b) --ratchet refreshes the measurement and keeps the budget (6024)"
else
  fail "(b) after --ratchet: exit $RC, $(cat "$F/budgets.json")"
fi

# (c) a shrink beyond the headroom → exit 1; --ratchet lowers the budget to
#     actual + headroom and --check passes.
new_fixture "$F"
rm "$F/skills/alpha/references/notes.md"
write_bytes "$F/skills/alpha/SKILL.md" 2000
run --skills-dir "$F/skills" --budgets "$F/budgets.json" --check
if [ "$RC" -eq 1 ] && echo "$OUT" | grep -q 'unratcheted slack'; then
  pass "(c) a shrink beyond the headroom fails --check (exit 1)"
else
  fail "(c) unratcheted shrink: exit $RC, output: $OUT"
fi
python3 "$SCRIPT" --skills-dir "$F/skills" --budgets "$F/budgets.json" --ratchet >/dev/null
run --skills-dir "$F/skills" --budgets "$F/budgets.json" --check
if [ "$RC" -eq 0 ] && [ "$(field "$F/budgets.json" alpha budget)" = "3024" ]; then
  pass "(c) --ratchet lowers the budget to actual + headroom (3024) and --check passes"
else
  fail "(c) after --ratchet: exit $RC, $(cat "$F/budgets.json")"
fi

# (e) a new skill directory without an entry → exit 1.
new_fixture "$F"
write_bytes "$F/skills/gamma/SKILL.md" 100
run --skills-dir "$F/skills" --budgets "$F/budgets.json" --check
if [ "$RC" -eq 1 ] && echo "$OUT" | grep -q 'gamma: unbudgeted'; then
  pass "(e) an unbudgeted new skill fails --check (exit 1)"
else
  fail "(e) unbudgeted skill: exit $RC, output: $OUT"
fi

# (f) a stale entry for a removed skill → exit 1; --ratchet drops it.
new_fixture "$F"
rm -rf "$F/skills/beta"
run --skills-dir "$F/skills" --budgets "$F/budgets.json" --check
if [ "$RC" -eq 1 ] && echo "$OUT" | grep -q 'beta: stale entry'; then
  pass "(f) a stale entry for a removed skill fails --check (exit 1)"
else
  fail "(f) stale entry: exit $RC, output: $OUT"
fi
python3 "$SCRIPT" --skills-dir "$F/skills" --budgets "$F/budgets.json" --ratchet >/dev/null
if ! grep -q '"beta"' "$F/budgets.json"; then
  pass "(f) --ratchet drops the entry for the removed skill"
else
  fail "(f) --ratchet kept the stale beta entry"
fi

# (g) excluded paths never change the measurement.
new_fixture "$F"
write_bytes "$F/skills/alpha/docs/README.md" 9000
write_bytes "$F/skills/alpha/references/scripts/gi-x.py" 9000
write_bytes "$F/skills/alpha/templates/model-data.json" 9000
write_bytes "$F/skills/alpha/.DS_Store" 9000
write_bytes "$F/skills/alpha/references/__pycache__/x.pyc" 9000
write_bytes "$F/skills/.DS_Store" 9000
run --skills-dir "$F/skills" --budgets "$F/budgets.json" --check
if [ "$RC" -eq 0 ]; then
  pass "(g) docs/README.md, references/scripts/, *.json, dotfiles, __pycache__ are not measured"
else
  fail "(g) an excluded path changed the measurement (exit $RC): $OUT"
fi

# (h) a malformed or missing budgets file → exit 3.
new_fixture "$F"
printf '{"headroom_bytes": 1024, "skills": ' > "$F/budgets.json"
run --skills-dir "$F/skills" --budgets "$F/budgets.json" --check
if [ "$RC" -eq 3 ]; then
  pass "(h) malformed budgets JSON exits 3"
else
  fail "(h) malformed budgets JSON exited $RC"
fi
run --skills-dir "$F/skills" --budgets "$F/nope.json" --check
if [ "$RC" -eq 3 ] && echo "$OUT" | grep -q -- '--ratchet'; then
  pass "(h) a missing budgets file in --check exits 3 and names the --ratchet fix"
else
  fail "(h) missing budgets file: exit $RC, output: $OUT"
fi
run --skills-dir "$F/no-such-dir" --budgets "$BUDGETS" --check
if [ "$RC" -eq 3 ]; then
  pass "(h) a missing skills directory exits 3"
else
  fail "(h) missing skills directory exited $RC"
fi

run --check --ratchet
if [ "$RC" -eq 2 ]; then
  pass "--check and --ratchet together are a usage error (exit 2)"
else
  fail "--check --ratchet exited $RC, want 2"
fi

echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Skill bundle budget tests failed"
  exit 1
fi
echo "  ✓ Skill bundle budget contract holds"
exit 0
