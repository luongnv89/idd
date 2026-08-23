#!/usr/bin/env bash
# test-coverage-floor-333.sh — Validate the coverage floor wiring (issue #333).
#
# F-TEST-001: the shared stdlib Python helpers had zero coverage measurement.
# The fix pins a --fail-under floor at the first measured value, runs the
# measurement in CI over the script entry points, and publishes the report as
# an artifact. These are structural tests: they check that every piece of the
# wiring exists and agrees with the others, without re-running the measurement.
#
#  AC1. .coveragerc scopes the measurement to src/shared/scripts and pins a
#       numeric fail_under equal to the value recorded in the workflow pin.
#  AC2. scripts/coverage-run.sh exists, is committed mode 0755, exercises
#       every entry point under src/shared/scripts/, and enforces the floor
#       through `coverage report` (never a weaker local check).
#  AC3. The dist-check workflow has a coverage job that runs the runner,
#       installs coverage.py, and uploads the report as a run artifact.
#  AC4. The pinned floor is a plain integer >= 0 — regressions fail CI,
#       raising it is deliberate work (never lower it to turn CI green).
#
# Usage: bash tests/test-coverage-floor-333.sh
# Returns: exit 0 if all tests pass, exit 1 on any failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RCFILE="$REPO_ROOT/.coveragerc"
RUNNER="$REPO_ROOT/scripts/coverage-run.sh"
WORKFLOW="$REPO_ROOT/.github/workflows/dist-check.yml"

PASS=0
FAIL=0

pass() {
  echo "  ✓ $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  ✗ $1"
  FAIL=$((FAIL + 1))
}

echo "◆ Coverage floor (#333)"

# ───────────────────────────────────────────────────────────
# T1 (AC1): the config scopes and pins
# ───────────────────────────────────────────────────────────
if [ -f "$RCFILE" ]; then
  pass "T1: .coveragerc exists"
else
  fail "T1: .coveragerc is missing"
fi

if grep -q 'source *= *src/shared/scripts' "$RCFILE"; then
  pass "T1: measurement is scoped to src/shared/scripts"
else
  fail "T1: [run] source does not scope src/shared/scripts"
fi

FLOOR="$(sed -n 's/^[[:space:]]*fail_under[[:space:]]*=[[:space:]]*//p' "$RCFILE" | head -1 | tr -d '[:space:]')"
if printf '%s' "$FLOOR" | grep -qE '^[0-9]+$'; then
  pass "T1: fail_under is a plain integer ($FLOOR)"
else
  fail "T1: fail_under is missing or not an integer (got: '$FLOOR')"
fi

# ───────────────────────────────────────────────────────────
# T2 (AC2): the runner exercises every entry point, committed 0755
# ───────────────────────────────────────────────────────────
if [ -f "$RUNNER" ]; then
  pass "T2: scripts/coverage-run.sh exists"
else
  fail "T2: scripts/coverage-run.sh is missing"
fi

mode="$(cd "$REPO_ROOT" && git ls-files -s scripts/coverage-run.sh | awk '{print $1}')"
if [ "$mode" = "100755" ]; then
  pass "T2: runner is committed mode 0755"
else
  fail "T2: runner is committed mode ${mode:-<untracked>}, expected 100755"
fi

missing_entrypoints=0
for script in "$REPO_ROOT"/src/shared/scripts/*.py; do
  name="$(basename "$script")"
  if ! grep -q "$name" "$RUNNER"; then
    fail "T2: runner never invokes $name"
    missing_entrypoints=1
  fi
done
if [ "$missing_entrypoints" -eq 0 ]; then
  pass "T2: runner exercises every src/shared/scripts/*.py entry point"
fi

if grep -q 'coverage report' "$RUNNER"; then
  pass "T2: floor is enforced by coverage report itself"
else
  fail "T2: runner does not enforce the floor via coverage report"
fi

# ───────────────────────────────────────────────────────────
# T3 (AC3): the workflow measures, gates, and publishes an artifact
# ───────────────────────────────────────────────────────────
if grep -q '^  coverage:' "$WORKFLOW"; then
  pass "T3: dist-check.yml has a coverage job"
else
  fail "T3: dist-check.yml has no coverage job"
fi

if grep -q 'bash scripts/coverage-run.sh' "$WORKFLOW"; then
  pass "T3: the coverage job runs the runner"
else
  fail "T3: the coverage job does not run scripts/coverage-run.sh"
fi

if grep -q 'upload-artifact' "$WORKFLOW" && grep -q 'coverage-report' "$WORKFLOW"; then
  pass "T3: the coverage report is uploaded as a run artifact"
else
  fail "T3: no upload-artifact step for coverage-report/"
fi

# The floor must be pinned where a reviewer sees it: the rcfile is the single
# source of truth, so the workflow may not carry a diverging --fail-under.
if grep -q -- '--fail-under' "$WORKFLOW"; then
  fail "T3: workflow overrides --fail-under on the command line (.coveragerc is the source of truth)"
else
  pass "T3: the floor lives only in .coveragerc"
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "  ┄"
echo "  Passed: $PASS  Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
