#!/usr/bin/env bash
# test-merge-gate-copies-619.sh — auto-pilot's merge-time safety rules hold in
# every copy (issues #619, #620).
#
#   T1  the Step 5.1b dependency gate fails closed: its fetch uses only flags
#       gi-issue.py defines, and a failed or unparsable read never reaches
#       gi-deps.py as an empty body (#619, audit AP-01). The fenced block is
#       extracted from the built phase file and run against a stub fetcher.
#   T2  restated rules match their single home (#620): the partial-merge entry
#       names all four Step 2a gates (AP-08), the branch-switch entry points at
#       the stash-first block (AP-09), the run-lock fallback keeps its stop on a
#       lock younger than an hour (AP-17), and the rebase-failure line says
#       nothing is reset (AP-18).
#   T3  the built skill carries the changes, and the CI step exists.
#
# PHASE5 overrides the phase file T1 runs (to prove the test fails on the old
# block: PHASE5=<(git show main:skills/auto-pilot/references/phases/phase-5-merge.md)).
#
# Usage: bash tests/test-merge-gate-copies-619.sh
# Returns: exit 0 if all checks pass, exit 1 on failure
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AP="$ROOT/src/skills/auto-pilot"
DIST="$ROOT/skills/auto-pilot"
WORKFLOW="$ROOT/.github/workflows/dist-check.yml"
PHASE5="${PHASE5:-$DIST/references/phases/phase-5-merge.md}"

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
has() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3 (missing in ${1#"$ROOT"/})"; }
lacks() { grep -qF -- "$2" "$1" && fail "$3 (found in ${1#"$ROOT"/})" || pass "$3"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "◆ Merge-gate restatements (#619, #620)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ── T1 — the dependency gate's fetch fails closed ────────────────────────────
# The one fenced bash block that pipes into gi-deps.py.
python3 - "$PHASE5" "$TMP/gate.sh" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
blocks = re.findall(r"```bash\n(.*?)```", text, re.S)
hits = [b for b in blocks if "gi-deps.py" in b]
open(sys.argv[2], "w", encoding="utf-8").write(hits[0] if len(hits) == 1 else "")
PY
if [ -s "$TMP/gate.sh" ]; then
  pass "T1.1: Step 5.1b has exactly one bash block that runs gi-deps.py"
else
  fail "T1.1: expected one bash block running gi-deps.py in ${PHASE5#"$ROOT"/}"
fi

# Every flag on a gi-issue.py line of that block is one gi-issue.py --help lists.
help="$(python3 "$ROOT/src/shared/scripts/gi-issue.py" --help)"
unknown=""
for flag in $(grep -F 'gi-issue.py' "$TMP/gate.sh" | grep -oE -- '--[a-z][a-z-]*' | sort -u); do
  printf '%s' "$help" | grep -qE -- "(^|[[:space:]])${flag}([[:space:]]|$)" || unknown="$unknown $flag"
done
[ -z "$unknown" ] && pass "T1.2: the gate's gi-issue.py call uses only flags --help lists" \
  || fail "T1.2: the gate passes undefined gi-issue.py flag(s):$unknown"

# A sandbox where references/scripts/gi-issue.py is a stub and gi-deps.py
# records that it ran, then delegates to the real parser.
SB="$TMP/sb"
mkdir -p "$SB/references/scripts" "$SB/bin"
cat > "$SB/references/scripts/gi-issue.py" <<'PY'
import os, sys
sys.stdout.write(os.environ.get("STUB_OUT", ""))
sys.exit(int(os.environ.get("STUB_EC", "0")))
PY
cat > "$SB/references/scripts/gi-deps.py" <<PY
import runpy, sys
open("$SB/deps-ran", "w").close()
sys.argv = ["gi-deps.py"]
runpy.run_path("$ROOT/src/shared/scripts/gi-deps.py", run_name="__main__")
PY
# A fake gh for the degrade form: prints STUB_OUT, exits STUB_EC.
cat > "$SB/bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s' "${STUB_OUT:-}"
exit "${STUB_EC:-0}"
SH
chmod +x "$SB/bin/gh"

# Placeholders the agent substitutes before running the block.
sed -e 's/ N / 42 /g' -e 's/{pr_number}/7/g' -e 's/{reason}/read failed/g' \
  "$TMP/gate.sh" > "$SB/primary.sh"
# The degrade form replaces the first line with the commented gh assignment.
degrade="$(grep -E '^#[[:space:]]+issue_json=.*gh issue view' "$SB/primary.sh" | sed -E 's/^#[[:space:]]+//' || true)"
if [ -n "$degrade" ]; then
  { printf '%s\n' "$degrade"; tail -n +2 "$SB/primary.sh"; } > "$SB/degrade.sh"
  pass "T1.3: the block documents a gh degrade form that keeps the exit status"
else
  : > "$SB/degrade.sh"
  fail "T1.3: no checked gh degrade form (issue_json=\"\$(gh issue view …)\") in the block"
fi

# run_gate <script> <stub_ec> <stub_out> → prints the block's stdout; sets RAN.
run_gate() {
  rm -f "$SB/deps-ran"
  OUT="$(cd "$SB" && PATH="$SB/bin:$PATH" STUB_EC="$2" STUB_OUT="$3" bash "$1" 2>/dev/null || true)"
  RAN=no
  if [ -f "$SB/deps-ran" ]; then RAN=yes; fi
}
# expect_unread <id> <script> <ec> <out> <what>
expect_unread() {
  run_gate "$2" "$3" "$4"
  if [ "$RAN" = no ] && printf '%s' "$OUT" | grep -qF 'PR #7 left open — dependency markers unreadable'; then
    pass "$1: $5 → gi-deps.py never runs, PR left open"
  else
    fail "$1: $5 → gi-deps ran=$RAN, output: ${OUT:-<empty>}"
  fi
}
# expect_deps <id> <script> <out> <want> <what>
expect_deps() {
  run_gate "$2" 0 "$3"
  got="$(printf '%s' "$OUT" | tr '\n' ' ' | sed 's/ *$//')"
  if [ "$RAN" = yes ] && [ "$got" = "$4" ]; then
    pass "$1: $5 → dependencies: ${4:-none}"
  else
    fail "$1: $5 → gi-deps ran=$RAN, got '${got}', want '$4'"
  fi
}

P="$SB/primary.sh"
expect_unread "T1.4" "$P" 2 "" "gi-issue.py exits 2 with empty stdout (the old --jq failure)"
expect_unread "T1.5" "$P" 4 "" "gi-issue.py exits 4"
expect_unread "T1.6" "$P" 0 "not json" "gi-issue.py prints unparsable output"
expect_unread "T1.7" "$P" 0 '{"issue": {"body": null}}' "the envelope carries no string body"
expect_deps   "T1.8" "$P" '{"issue": {"body": "Depends on #12\nBlocked by: acme/lib#15, #20"}, "cached": false}' "12 20" "a good envelope"
expect_deps   "T1.9" "$P" '{"issue": {"body": "No markers here."}}' "" "a readable body with no markers"
D="$SB/degrade.sh"
expect_unread "T1.10" "$D" 1 "" "degrade gh read fails"
expect_deps   "T1.11" "$D" '{"body": "Blocked by #9"}' "9" "degrade gh read succeeds"

has "$AP/references/phases/phase-5-merge.md" '**A failed read is never an empty body.**' "T1.12: the gate states the fail-closed rule"
has "$AP/references/error-messages.md" '### Dependency markers unreadable (PR left open)' "T1.13: the catalog carries the unreadable-body entry"
lacks "$AP/references/phases/phase-5-merge.md" '--jq .issue.body' "T1.14: no gi-issue.py --jq call remains"

# ── T2 — restated rules match their single home ──────────────────────────────
EM="$AP/references/error-messages.md"
# AP-08: the partial-merge entry names all four Step 2a gates.
partial="$(grep -F 'must pass before this output is shown' "$EM" || true)"
if printf '%s' "$partial" | grep -qF 'merge floor, dependency, CI and merge identity'; then
  pass "T2.1: the partial-merge trigger names all four Step 2a gates"
else
  fail "T2.1: the partial-merge trigger does not name all four Step 2a gates"
fi
lacks "$EM" 'Step 2a (Step 5.1b dependency gate) must pass' "T2.2: the trigger no longer reduces Step 2a to the dependency gate"
lacks "$EM" 'merge PR only after dependency gate passes' "T2.3: the action no longer merges on the dependency gate alone"
lacks "$AP/references/phases/phase-3-4-review.md" 'PR merged anyway' "T2.4: the merge-mode table no longer merges unconditionally"
lacks "$AP/references/phases/phase-3-4-review.md" 'after the dependency gate passes' "T2.5: Step 2 waits for all four gates, not the dependency gate"

# AP-09: the branch-switch entry points at the stash-first block.
switch="$(grep -A6 -F '### Not on default branch (auto-resolved)' "$EM" | grep -F '**Action:**' || true)"
if printf '%s' "$switch" | grep -qF '*Auto-stash and branch sync*' && ! printf '%s' "$switch" | grep -qF 'git checkout {default_branch} &&'; then
  pass "T2.6: the branch-switch action points at the stash-first sync, no bare pull --rebase"
else
  fail "T2.6: the branch-switch action restates a bare sync: $switch"
fi
has "$AP/references/preflight.md" '## Auto-stash and branch sync' "T2.7: the pointed-at preflight section exists"

# AP-17: the run-lock fallback keeps its stop on a fresh lock.
lockline="$(grep -F 'print `⚠ gi-state unavailable`' "$AP/SKILL.source.md" || true)"
if printf '%s' "$lockline" | grep -qF 'younger than an hour' && printf '%s' "$lockline" | grep -qF 'stop rule'; then
  pass "T2.8: SKILL.md's run-lock fallback stops on a lock younger than an hour"
else
  fail "T2.8: SKILL.md's run-lock fallback drops the stop on a fresh .idd/run.lock"
fi
has "$AP/references/preflight.md" 'treat a file younger than an hour as a live' "T2.9: the home fallback still states the stop"
gistate="$(grep -A6 -F '### gi-state unavailable (degrade)' "$EM" | grep -F '**Action:**' || true)"
printf '%s' "$gistate" | grep -qF 'younger than an hour is a live holder and stops the run' \
  && pass "T2.10: the catalog's gi-state entry keeps the stop" \
  || fail "T2.10: the catalog's gi-state entry drops the stop on a fresh lock"

# AP-18: the rebase-failure line says what happens.
lacks "$AP/references/preflight.md" 'resetting to remote' "T2.11: the rebase-failure line no longer claims a reset"
has "$AP/references/preflight.md" '✗ Rebase failed — rebase aborted, nothing reset' "T2.12: the rebase-failure line says nothing is reset"

# ── T3 — built skill and CI ──────────────────────────────────────────────────
has "$DIST/references/phases/phase-5-merge.md" '**A failed read is never an empty body.**' "T3.1: the built phase file carries the fail-closed gate"
has "$DIST/references/error-messages.md" 'merge floor, dependency, CI and merge identity' "T3.2: the built catalog names the four gates"
has "$DIST/SKILL.md" 'younger than an hour is a live holder' "T3.3: the built SKILL.md keeps the run-lock stop"
lacks "$DIST/references/preflight.md" 'resetting to remote' "T3.4: the built preflight no longer claims a reset"
grep -qF 'run: bash tests/test-merge-gate-copies-619.sh' "$WORKFLOW" \
  && pass "T3.5: the CI step exists" || fail "T3.5: dist-check.yml lacks this test"

echo ""
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || { echo "  ✗ Merge-gate restatement tests failed"; exit 1; }
echo "  ✓ Merge-gate restatement tests passed"
