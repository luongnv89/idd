#!/usr/bin/env bash
# test-eval-plan-to-issues.sh — behavioral evals for plan-to-issues (#503)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN="$REPO_ROOT/evals/harness/run_eval.sh"
CASES="$REPO_ROOT/evals/cases/plan-to-issues"

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ plan-to-issues behavioral evals (#503)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# Fail closed: no record mode in CI
if [ "${EVAL_RECORD:-}" = "1" ]; then
  echo "✗ EVAL_RECORD must be unset in CI" >&2
  exit 1
fi

run_case() {
  local name="$1"
  local dir="$CASES/$name"
  set +e
  bash "$RUN" "$dir"
  local ec=$?
  set -e
  if [ "$ec" -eq 0 ]; then
    pass "case $name"
  else
    fail "case $name (exit $ec)"
  fi
}

run_case "file-path"
run_case "sync"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
