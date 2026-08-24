#!/usr/bin/env bash
# test-eval-harness.sh — unit tests for gh_shim + grade hermeticity (#261)
#
# Covers: exact cassette match, --json enforcement, no network (shim only),
# concurrent issue IDs, corrupt counter recovery, shell assertion allowlisting,
# grade exit matching, and EVAL_RECORD fail-closed.
#
# Usage: bash tests/test-eval-harness.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHIM="$REPO_ROOT/evals/harness/gh_shim.py"
GRADE="$REPO_ROOT/evals/harness/grade.py"
RUN="$REPO_ROOT/evals/harness/run_eval.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ eval harness unit tests (#261)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ─── T1: gh_shim exact match ───────────────────────────────
cat > "$TMP/cassettes.json" <<'EOF'
{
  "version": 1,
  "calls": [
    {
      "argv": ["issue", "view", "1", "--json", "number,title,body,state"],
      "stdout": "{\"number\":1,\"title\":\"t\",\"body\":\"b\",\"state\":\"OPEN\"}\n",
      "stderr": "",
      "exit": 0
    },
    {
      "match": "prefix",
      "argv": ["auth", "status"],
      "stdout": "ok\n",
      "exit": 0
    }
  ]
}
EOF

export EVAL_CASSETTES="$TMP/cassettes.json"
unset EVAL_RECORD || true
unset EVAL_STATE_DIR || true

OUT="$(python3 "$SHIM" issue view 1 --json number,title,body,state)"
if printf '%s' "$OUT" | grep -q '"number":1'; then
  pass "T1: gh_shim exact argv match returns cassette stdout"
else
  fail "T1: gh_shim exact argv match returns cassette stdout"
fi

# ─── T2: --json field order independent ────────────────────
OUT2="$(python3 "$SHIM" issue view 1 --json state,body,title,number)"
if printf '%s' "$OUT2" | grep -q '"number":1'; then
  pass "T2: --json field order is normalized for matching"
else
  fail "T2: --json field order is normalized for matching"
fi

# ─── T3: rejects issue view without --json ─────────────────
set +e
python3 "$SHIM" issue view 1 >/dev/null 2>"$TMP/nojson.err"
EC=$?
set -e
if [ "$EC" -eq 2 ] && grep -q -- '--json' "$TMP/nojson.err"; then
  pass "T3: issue view without --json exits 2"
else
  fail "T3: issue view without --json exits 2 (got $EC)"
fi

# ─── T4: prefix match ──────────────────────────────────────
OUT3="$(python3 "$SHIM" auth status)"
if [ "$OUT3" = "ok" ]; then
  pass "T4: prefix match for auth status"
else
  fail "T4: prefix match for auth status"
fi

# ─── T5: bare gh / --help exit 0 without cassette ──────────
unset EVAL_CASSETTES
set +e
python3 "$SHIM" --help >/dev/null 2>&1
H1=$?
python3 "$SHIM" >/dev/null 2>&1
H2=$?
set -e
export EVAL_CASSETTES="$TMP/cassettes.json"
if [ "$H1" -eq 0 ] && [ "$H2" -eq 0 ]; then
  pass "T5: bare gh and --help exit 0 without cassette"
else
  fail "T5: bare gh and --help exit 0 without cassette"
fi

# ─── T6: no network — PATH has only shim ───────────────────
BIN="$TMP/bin"
mkdir -p "$BIN"
cat > "$BIN/gh" <<EOF
#!/usr/bin/env bash
exec python3 "$SHIM" "\$@"
EOF
chmod 755 "$BIN/gh"
# Isolate PATH: only our bin + essential system dirs for python3/bash
ISOLATED_PATH="$BIN:/usr/bin:/bin"
OUT4="$(PATH="$ISOLATED_PATH" EVAL_CASSETTES="$TMP/cassettes.json" gh auth status)"
if [ "$OUT4" = "ok" ]; then
  pass "T6: isolated PATH (shim only) replays without real gh"
else
  fail "T6: isolated PATH (shim only) replays without real gh"
fi

# ─── T7: unmatched call fails closed (no record) ───────────
set +e
PATH="$ISOLATED_PATH" EVAL_CASSETTES="$TMP/cassettes.json" \
  gh issue list --json number >/dev/null 2>"$TMP/unmatched.err"
UM=$?
set -e
if [ "$UM" -ne 0 ] && grep -qi 'unmatched' "$TMP/unmatched.err"; then
  pass "T7: unmatched call fails closed without EVAL_RECORD"
else
  fail "T7: unmatched call fails closed without EVAL_RECORD (exit $UM)"
fi

# ─── T8: grade fails when expect_exit mismatches ───────────
CASE="$TMP/bad-grade-case"
mkdir -p "$CASE" "$TMP/out-empty"
# Minimal failing issue body
printf 'not an issue\n' > "$TMP/out-empty/issue.md"
cat > "$CASE/case.json" <<'EOF'
{
  "name": "harness/grade-mismatch",
  "skill": "issue-creator",
  "grade": [
    {
      "tool": "idd-lint",
      "args": ["issue", "OUT/issue.md"],
      "expect_exit": 0,
      "label": "should fail because body is bad but expect_exit is 0"
    }
  ]
}
EOF
set +e
REPO_ROOT="$REPO_ROOT" python3 "$GRADE" --case "$CASE" --out "$TMP/out-empty" >/dev/null 2>&1
G=$?
set -e
if [ "$G" -eq 1 ]; then
  pass "T8: grade exits 1 when expect_exit mismatches"
else
  fail "T8: grade exits 1 when expect_exit mismatches (got $G)"
fi

# ─── T9: grade passes when expect_exit matches failure ─────
cat > "$CASE/case.json" <<'EOF'
{
  "name": "harness/grade-match-fail",
  "skill": "issue-creator",
  "grade": [
    {
      "tool": "idd-lint",
      "args": ["issue", "OUT/issue.md"],
      "expect_exit": 1,
      "label": "expects lint failure"
    }
  ]
}
EOF
set +e
REPO_ROOT="$REPO_ROOT" python3 "$GRADE" --case "$CASE" --out "$TMP/out-empty" >/dev/null 2>&1
G2=$?
set -e
if [ "$G2" -eq 0 ]; then
  pass "T9: grade exits 0 when lint fails and expect_exit is 1"
else
  fail "T9: grade exits 0 when lint fails and expect_exit is 1 (got $G2)"
fi

# ─── T10: run_eval fails closed if EVAL_RECORD=1 ────────────
# Use creator basic case path if present
BASIC="$REPO_ROOT/evals/cases/issue-creator/basic"
if [ -d "$BASIC" ]; then
  set +e
  EVAL_RECORD=1 bash "$RUN" "$BASIC" >/dev/null 2>"$TMP/record.err"
  R=$?
  set -e
  if [ "$R" -ne 0 ] && grep -q 'EVAL_RECORD' "$TMP/record.err"; then
    pass "T10: run_eval.sh fails closed when EVAL_RECORD=1"
  else
    fail "T10: run_eval.sh fails closed when EVAL_RECORD=1 (exit $R)"
  fi
else
  fail "T10: basic case missing for EVAL_RECORD check"
fi

# ─── T11: pr list without --json rejected ──────────────────
export EVAL_CASSETTES="$TMP/cassettes.json"
set +e
python3 "$SHIM" pr list >/dev/null 2>"$TMP/prlist.err"
P=$?
set -e
if [ "$P" -eq 2 ]; then
  pass "T11: pr list without --json exits 2"
else
  fail "T11: pr list without --json exits 2 (got $P)"
fi

# ─── T12: exact match preferred over earlier prefix entry ──
cat > "$TMP/cassettes-order.json" <<'EOF'
{
  "version": 1,
  "calls": [
    {
      "match": "prefix",
      "argv": ["pr"],
      "stdout": "PREFIX\n",
      "exit": 0
    },
    {
      "argv": ["pr", "view", "8", "--json", "number,title,body,state"],
      "stdout": "{\"number\":8}\n",
      "exit": 0
    }
  ]
}
EOF
export EVAL_CASSETTES="$TMP/cassettes-order.json"
OUT12="$(python3 "$SHIM" pr view 8 --json number,title,body,state)"
if [ "$OUT12" = '{"number":8}' ]; then
  pass "T12: exact cassette beats earlier prefix match"
else
  fail "T12: exact cassette beats earlier prefix match (got $OUT12)"
fi

# ─── T13: OUT token substitution does not corrupt OUTPUT ──
set +e
python3 - "$REPO_ROOT/evals/harness/grade.py" <<'PY'
import importlib.util
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("grade", sys.argv[1])
grade = importlib.util.module_from_spec(spec)
spec.loader.exec_module(grade)
out = Path("/tmp/eval-out-dir")
got = grade._sub_out("OUT/issue.md and also OUTPUT.md and TIMEOUT", out)
assert "OUTPUT.md" in got, got
assert "TIMEOUT" in got, got
assert str(out) + "/issue.md" in got, got
assert "OUT/" not in got.replace(str(out), ""), got
print("ok")
PY
T13=$?
set -e
if [ "$T13" -eq 0 ]; then
  pass "T13: OUT substitution preserves OUTPUT.md and TIMEOUT"
else
  fail "T13: OUT substitution preserves OUTPUT.md and TIMEOUT"
fi

# ─── T14: broken branch artifact fails grade ───────────────
# Subject-written branch must be what is graded, not a constant.
mkdir -p "$TMP/art-branch"
printf '%s\n' "Bad/Branch_Name" > "$TMP/art-branch/branch.txt"
cat > "$CASE/case.json" <<'EOF'
{
  "name": "harness/branch-from-artifact",
  "skill": "issue-creator",
  "grade": [
    {
      "tool": "shell",
      "args": ["python3 scripts/idd-lint.py branch \"$(tr -d '\\n' < OUT/branch.txt)\""],
      "expect_exit": 0,
      "label": "must fail on bad branch artifact"
    }
  ]
}
EOF
set +e
REPO_ROOT="$REPO_ROOT" python3 "$GRADE" --case "$CASE" --out "$TMP/art-branch" >/dev/null 2>&1
G3=$?
set -e
if [ "$G3" -eq 1 ]; then
  pass "T14: grade fails when subject branch artifact is invalid"
else
  fail "T14: grade fails when subject branch artifact is invalid (got $G3)"
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
# ─── T15/T16: structured red→green evidence ───────────────
mkdir -p "$TMP/red-green-out"
cat > "$CASE/case.json" <<'EOF'
{
  "name": "harness/red-green-evidence",
  "skill": "issue-resolver",
  "grade": [
    {
      "tool": "red-green",
      "file": "OUT/red-green.json",
      "expect_exit": 0,
      "label": "exact red and green exit values"
    }
  ]
}
EOF
printf '%s\n' '{"red_exit": 1, "green_exit": 0}' > "$TMP/red-green-out/red-green.json"
set +e
REPO_ROOT="$REPO_ROOT" python3 "$GRADE" --case "$CASE" --out "$TMP/red-green-out" >/dev/null 2>&1
RG=$?
set -e
if [ "$RG" -eq 0 ]; then
  pass "T15: valid structured red→green evidence passes"
else
  fail "T15: valid structured red→green evidence passes (got $RG)"
fi
printf '%s\n' '{"red_exit": 0, "green_exit": 1}' > "$TMP/red-green-out/red-green.json"
set +e
REPO_ROOT="$REPO_ROOT" python3 "$GRADE" --case "$CASE" --out "$TMP/red-green-out" >/dev/null 2>&1
RG_BAD=$?
set -e
if [ "$RG_BAD" -eq 1 ]; then
  pass "T16: invalid structured red→green evidence fails"
else
  fail "T16: invalid structured red→green evidence fails (got $RG_BAD)"
fi
printf '%s\n' '[]' > "$TMP/red-green-out/red-green.json"
set +e
REPO_ROOT="$REPO_ROOT" python3 "$GRADE" --case "$CASE" --out "$TMP/red-green-out" >/dev/null 2>&1
RG_ARRAY=$?
set -e
if [ "$RG_ARRAY" -eq 1 ]; then
  pass "T17: non-object structured red→green evidence fails"
else
  fail "T17: non-object structured red→green evidence fails (got $RG_ARRAY)"
fi
printf '%s\n' '{not-json' > "$TMP/red-green-out/red-green.json"
set +e
REPO_ROOT="$REPO_ROOT" python3 "$GRADE" --case "$CASE" --out "$TMP/red-green-out" >/dev/null 2>&1
RG_MALFORMED=$?
set -e
if [ "$RG_MALFORMED" -eq 1 ]; then
  pass "T18: malformed structured red→green evidence fails"
else
  fail "T18: malformed structured red→green evidence fails (got $RG_MALFORMED)"
fi

# ─── T19: parallel issue creates allocate unique numbers ───
PARALLEL_STATE="$TMP/parallel-state"
mkdir -p "$PARALLEL_STATE"
export EVAL_CASSETTES="$TMP/cassettes.json"
pids=""
for i in $(seq 1 200); do
  EVAL_STATE_DIR="$PARALLEL_STATE" python3 "$SHIM" issue create \
    --title "parallel-$i" --body "body-$i" > "$TMP/parallel-$i.out" \
    2> "$TMP/parallel-$i.err" &
  pids="$pids $!"
done
parallel_ok=1
for pid in $pids; do
  wait "$pid" || parallel_ok=0
done
unique_count="$(cat "$TMP"/parallel-*.out | sort -u | wc -l | tr -d ' ')"
final_counter="$(cat "$PARALLEL_STATE/issue_counter" 2>/dev/null || true)"
issue_files="$(find "$PARALLEL_STATE" -name 'issue_*.json' -type f | wc -l | tr -d ' ')"
if [ "$parallel_ok" -eq 1 ] && [ "$unique_count" -eq 200 ] \
  && [ "$final_counter" = "200" ] && [ "$issue_files" -eq 200 ]; then
  pass "T19: parallel issue creates allocate 200 unique numbers"
else
  fail "T19: parallel issue creates are unique (urls=$unique_count counter=$final_counter files=$issue_files)"
fi

# ─── T20: corrupt counter warns and resets without traceback ─
CORRUPT_STATE="$TMP/corrupt-state"
mkdir -p "$CORRUPT_STATE"
printf '%s\n' 'not-a-number' > "$CORRUPT_STATE/issue_counter"
set +e
EVAL_STATE_DIR="$CORRUPT_STATE" python3 "$SHIM" issue create \
  --title "after-corruption" --body "body" > "$TMP/corrupt.out" 2> "$TMP/corrupt.err"
CORRUPT_EXIT=$?
printf '%0300d\n' 0 > "$CORRUPT_STATE/issue_counter"
EVAL_STATE_DIR="$CORRUPT_STATE" python3 "$SHIM" issue create \
  --title "after-oversize" --body "body" > "$TMP/oversize-counter.out" \
  2> "$TMP/oversize-counter.err"
OVERSIZE_EXIT=$?
printf '%s\n' '9223372036854775807' > "$CORRUPT_STATE/issue_counter"
EVAL_STATE_DIR="$CORRUPT_STATE" python3 "$SHIM" issue create \
  --title "after-exhaustion" --body "body" > "$TMP/exhausted-counter.out" \
  2> "$TMP/exhausted-counter.err"
EXHAUSTED_EXIT=$?
set -e
if [ "$CORRUPT_EXIT" -eq 0 ] && [ "$OVERSIZE_EXIT" -eq 0 ] \
  && [ "$EXHAUSTED_EXIT" -eq 1 ] \
  && grep -q 'invalid issue counter' "$TMP/corrupt.err" \
  && grep -q 'counter exceeds 64 bytes' "$TMP/oversize-counter.err" \
  && ! grep -q 'Traceback' "$TMP/corrupt.err" \
  && ! grep -q 'Traceback' "$TMP/oversize-counter.err" \
  && grep -q 'issue counter exhausted' "$TMP/exhausted-counter.err" \
  && ! grep -q 'Traceback' "$TMP/exhausted-counter.err" \
  && grep -q '/issues/1$' "$TMP/corrupt.out" \
  && grep -q '/issues/1$' "$TMP/oversize-counter.out" \
  && [ "$(cat "$CORRUPT_STATE/issue_counter")" = "9223372036854775807" ]; then
  pass "T20: invalid counters reset and exhaustion fails without reuse"
else
  fail "T20: counter errors avoid traceback/reuse (exits $CORRUPT_EXIT/$OVERSIZE_EXIT/$EXHAUSTED_EXIT)"
fi

# ─── T21: non-allowlisted shell assertion is never executed ─
MALICIOUS_CASE="$TMP/malicious-shell-case"
MALICIOUS_OUT="$TMP/malicious-shell-out"
mkdir -p "$MALICIOUS_CASE" "$MALICIOUS_OUT"
cat > "$MALICIOUS_CASE/case.json" <<'EOF'
{
  "name": "harness/reject-shell-command",
  "grade": [
    {
      "tool": "shell",
      "args": ["touch OUT/executed"],
      "expect_exit": 0,
      "label": "non-allowlisted command"
    }
  ]
}
EOF
set +e
REPO_ROOT="$REPO_ROOT" python3 "$GRADE" --case "$MALICIOUS_CASE" \
  --out "$MALICIOUS_OUT" > "$TMP/malicious-grade.out" 2>&1
MALICIOUS_EXIT=$?
set -e
if [ "$MALICIOUS_EXIT" -eq 1 ] \
  && grep -q 'rejected before execution' "$TMP/malicious-grade.out" \
  && [ ! -e "$MALICIOUS_OUT/executed" ]; then
  pass "T21: non-allowlisted shell assertion is rejected before execution"
else
  fail "T21: non-allowlisted shell assertion is rejected (exit $MALICIOUS_EXIT)"
fi

# ─── T22: malformed argv artifacts fail without traceback ──
MALFORMED_OUT="$TMP/malformed-artifact-out"
mkdir -p "$MALFORMED_OUT"
printf 'fix/342-safe\0suffix\n' > "$MALFORMED_OUT/nul.txt"
printf '\377\n' > "$MALFORMED_OUT/non-utf8.txt"
dd if=/dev/zero of="$MALFORMED_OUT/oversized.txt" bs=65537 count=1 2>/dev/null
printf 'fix/342-safe\n' > "$MALFORMED_OUT/valid.txt"
cat > "$CASE/case.json" <<'EOF'
{
  "name": "harness/reject-malformed-artifacts",
  "grade": [
    {
      "tool": "shell",
      "args": ["python3 scripts/idd-lint.py branch \"$(tr -d '\\n' < OUT/nul.txt)\""],
      "expect_exit": 0,
      "label": "NUL artifact"
    },
    {
      "tool": "shell",
      "args": ["python3 scripts/idd-lint.py commit \"$(tr -d '\\n' < OUT/non-utf8.txt)\""],
      "expect_exit": 0,
      "label": "non-UTF-8 artifact"
    },
    {
      "tool": "shell",
      "args": ["python3 scripts/idd-lint.py branch \"$(tr -d '\\n' < OUT/oversized.txt)\""],
      "expect_exit": 0,
      "label": "oversized artifact"
    },
    {
      "tool": "shell",
      "args": ["python3 scripts/idd-lint.py branch \"$(tr -d '\\n' < OUT/valid.txt)\""],
      "expect_exit": 0,
      "label": "valid artifact still runs"
    }
  ]
}
EOF
set +e
REPO_ROOT="$REPO_ROOT" python3 "$GRADE" --case "$CASE" \
  --out "$MALFORMED_OUT" > "$TMP/malformed-grade.out" 2>&1
MALFORMED_EXIT=$?
set -e
if [ "$MALFORMED_EXIT" -eq 1 ] \
  && grep -q 'NUL byte' "$TMP/malformed-grade.out" \
  && grep -q 'not valid UTF-8' "$TMP/malformed-grade.out" \
  && grep -q 'exceeds the 64 KiB argv limit' "$TMP/malformed-grade.out" \
  && grep -q '✓ valid artifact still runs' "$TMP/malformed-grade.out" \
  && ! grep -q 'Traceback' "$TMP/malformed-grade.out"; then
  pass "T22: malformed argv artifacts fail cleanly and grading continues"
else
  fail "T22: malformed argv artifacts fail cleanly (exit $MALFORMED_EXIT)"
fi

echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
