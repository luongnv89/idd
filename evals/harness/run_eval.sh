#!/usr/bin/env bash
# run_eval.sh — hermetic behavioral eval case runner
#
# Usage: bash evals/harness/run_eval.sh <case-dir>
#
# 1. Create temp work dir + STATE + OUT
# 2. Build PATH bin with `gh` wrapper → python3 gh_shim.py
# 3. Export EVAL_CASSETTES, EVAL_STATE_DIR, REPO_ROOT, EVAL_OUT
# 4. Optionally seed a git fixture if case has fixture_repo/ or case.json seed
# 5. Run subject.sh
# 6. Run grade.py
# 7. Clean temp on exit (trap)
#
# Fail closed: EVAL_RECORD must be unset (never record in CI).

set -euo pipefail

if [ "${1:-}" = "" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo "Usage: bash evals/harness/run_eval.sh <case-dir>"
  exit 2
fi

CASE_DIR="$(cd "$1" && pwd)"
HARNESS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HARNESS_DIR/../.." && pwd)"

if [ ! -f "$CASE_DIR/case.json" ]; then
  echo "✗ missing case.json in $CASE_DIR" >&2
  exit 2
fi
if [ ! -f "$CASE_DIR/subject.sh" ]; then
  echo "✗ missing subject.sh in $CASE_DIR" >&2
  exit 2
fi

# Fail closed: never run evals in record mode (would open network).
if [ "${EVAL_RECORD:-}" = "1" ]; then
  echo "✗ EVAL_RECORD=1 is set — record mode is forbidden for eval runs (CI fail-closed)" >&2
  echo "  Unset EVAL_RECORD and use committed cassettes under the case directory." >&2
  exit 2
fi
unset EVAL_RECORD || true

WORK="$(mktemp -d "${TMPDIR:-/tmp}/idd-eval.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

STATE="$WORK/state"
OUT="$WORK/out"
BIN="$WORK/bin"
mkdir -p "$STATE" "$OUT" "$BIN"

# gh wrapper — execs the Python shim with original argv
cat > "$BIN/gh" <<EOF
#!/usr/bin/env bash
exec python3 "$HARNESS_DIR/gh_shim.py" "\$@"
EOF
chmod 755 "$BIN/gh"

# Prefer case-local cassettes; fall back to empty calls list if absent
CASSETTES="$CASE_DIR/cassettes.json"
if [ ! -f "$CASSETTES" ]; then
  CASSETTES="$WORK/empty-cassettes.json"
  printf '%s\n' '{"version":1,"calls":[]}' > "$CASSETTES"
fi

export PATH="$BIN:$PATH"
export EVAL_CASSETTES="$CASSETTES"
export EVAL_STATE_DIR="$STATE"
export REPO_ROOT
export EVAL_OUT="$OUT"
export EVAL_CASE_DIR="$CASE_DIR"
export EVAL_WORK="$WORK"
# Ensure real network-facing GH is not preferred: our BIN is first.
# Subjects must not re-export PATH past the shim.

# Optional fixture_repo seed: copy into WORK/repo and init git if needed
if [ -d "$CASE_DIR/fixture_repo" ]; then
  REPO_FIXTURE="$WORK/repo"
  mkdir -p "$REPO_FIXTURE"
  # Copy contents (including hidden files except . and ..)
  cp -R "$CASE_DIR/fixture_repo"/. "$REPO_FIXTURE"/ 2>/dev/null || true
  export EVAL_FIXTURE_REPO="$REPO_FIXTURE"
fi

CASE_NAME="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('name',''))" "$CASE_DIR/case.json" 2>/dev/null || basename "$CASE_DIR")"
echo "◆ eval $CASE_NAME"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  case: $CASE_DIR"
echo "  out:  $OUT"
echo "  gh:   $(command -v gh)"

# subject runs with EVAL_OUT; cwd is case dir unless fixture set
SUBJECT_CWD="$CASE_DIR"
if [ -n "${EVAL_FIXTURE_REPO:-}" ]; then
  SUBJECT_CWD="$EVAL_FIXTURE_REPO"
fi

set +e
(
  cd "$SUBJECT_CWD"
  bash "$CASE_DIR/subject.sh"
)
SUBJECT_EXIT=$?
set -e

if [ "$SUBJECT_EXIT" -ne 0 ]; then
  echo "✗ subject.sh exited $SUBJECT_EXIT" >&2
  exit "$SUBJECT_EXIT"
fi
echo "  ✓ subject completed"

set +e
python3 "$HARNESS_DIR/grade.py" --case "$CASE_DIR" --out "$OUT"
GRADE_EXIT=$?
set -e

if [ "$GRADE_EXIT" -ne 0 ]; then
  echo "✗ eval failed: $CASE_NAME" >&2
  exit "$GRADE_EXIT"
fi

echo "✓ eval passed: $CASE_NAME"
exit 0
