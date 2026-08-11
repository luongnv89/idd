#!/usr/bin/env bash
# test-eval-harness.sh — unit tests for gh_shim + grade hermeticity (#261)
#
# Covers: exact cassette match, --json enforcement, no network (shim only),
# grade fails when expect_exit mismatches, EVAL_RECORD fail-closed.
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

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
