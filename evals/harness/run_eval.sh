#!/usr/bin/env bash
# run_eval.sh — hermetic behavioral eval case runner
#
# Usage: bash evals/harness/run_eval.sh <case-dir>
#
# The subject is copied into WORK, given a disposable workspace and minimal
# environment, then run inside an OS-level network sandbox.  Grading runs
# outside that sandbox so it can resolve repository tools.
#
# Fail closed: EVAL_RECORD must be unset (never record in CI), and no
# supported OS-level network sandbox means no subject execution.

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
CASE_COPY="$WORK/case"
SUBJECT_WORK="$WORK/repo"
HOME_DIR="$WORK/home"
GH_CONFIG="$WORK/gh-config"
GH_SHIM_COPY="$WORK/gh_shim.py"
mkdir -p "$STATE" "$OUT" "$BIN" "$CASE_COPY" "$SUBJECT_WORK" "$HOME_DIR" "$GH_CONFIG"

# Copy the complete case, including subject.sh, before execution. This keeps
# $0, case-relative paths, and the working directory outside the checkout.
cp -R "$CASE_DIR"/. "$CASE_COPY"/
chmod 755 "$CASE_COPY/subject.sh"

# Copy the shim too, so the subject cannot discover or mutate the checkout
# through a wrapper pointing back into the harness source tree.
cp "$HARNESS_DIR/gh_shim.py" "$GH_SHIM_COPY"

# gh wrapper — uses the harness interpreter directly, so PATH need not expose
# the directory that may contain a real gh executable.
PYTHON_BIN="$(command -v python3 || true)"
if [ -z "$PYTHON_BIN" ] || [ ! -x "$PYTHON_BIN" ]; then
  echo "✗ python3 is required for eval execution" >&2
  exit 2
fi
cat > "$BIN/gh" <<EOF
#!/usr/bin/env bash
exec "$PYTHON_BIN" "$GH_SHIM_COPY" "\$@"
EOF
cat > "$BIN/python3" <<EOF
#!/usr/bin/env bash
exec "$PYTHON_BIN" "\$@"
EOF
chmod 755 "$BIN/gh" "$BIN/python3"
# Subjects use git for fixture work. Wrap it too, avoiding a PATH entry that
# could expose unrelated host executables.
GIT_BIN="$(command -v git || true)"
if [ -n "$GIT_BIN" ] && [ -x "$GIT_BIN" ]; then
  cat > "$BIN/git" <<EOF
#!/usr/bin/env bash
exec "$GIT_BIN" "\$@"
EOF
  chmod 755 "$BIN/git"
fi

# Keep cassette input under WORK so a subject cannot alter checkout data.
if [ -f "$CASE_DIR/cassettes.json" ]; then
  CASSETTES="$WORK/cassettes.json"
  cp "$CASE_DIR/cassettes.json" "$CASSETTES"
else
  CASSETTES="$WORK/empty-cassettes.json"
  printf '%s\n' '{"version":1,"calls":[]}' > "$CASSETTES"
fi

# Optional fixture_repo seed: copy into WORK/repo. Without a fixture this is
# still a disposable workspace, never the checkout case directory.
if [ -d "$CASE_DIR/fixture_repo" ]; then
  cp -R "$CASE_DIR/fixture_repo"/. "$SUBJECT_WORK"/ 2>/dev/null || true
fi

CASE_NAME="$("$PYTHON_BIN" -c "import json,sys; print(json.load(open(sys.argv[1])).get('name',''))" "$CASE_DIR/case.json" 2>/dev/null || basename "$CASE_DIR")"
echo "◆ eval $CASE_NAME"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  case: $CASE_DIR"
echo "  out:  $OUT"
echo "  gh:   $BIN/gh"

# The subject gets only variables needed to run an eval. In particular, do
# not pass credentials, proxies, or Git worktree variables from the host.
SUBJECT_CMD="$WORK/run-subject.sh"
cat > "$SUBJECT_CMD" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "$SUBJECT_WORK"
exec env -i \\
  HOME="$HOME_DIR" \\
  GH_CONFIG_DIR="$GH_CONFIG" \\
  PATH="$BIN:/usr/bin:/bin" \\
  EVAL_CASSETTES="$CASSETTES" \\
  EVAL_STATE_DIR="$STATE" \\
  EVAL_OUT="$OUT" \\
  EVAL_CASE_DIR="$CASE_COPY" \\
  EVAL_WORK="$WORK" \\
  bash "$CASE_COPY/subject.sh"
EOF
chmod 755 "$SUBJECT_CMD"

# PATH isolation and proxy/DNS tricks are not network isolation. Use the
# native macOS sandbox or a Linux user+network namespace, and fail closed when
# neither is available. map-current-user ensures the subject is never root.
OS_NAME="$(uname -s)"
if [ "$(id -u)" -eq 0 ]; then
  echo "✗ refusing to run eval subject as root" >&2
  exit 2
fi
set +e
if [ "$OS_NAME" = "Darwin" ]; then
  SANDBOX_EXEC="$(command -v sandbox-exec || true)"
  if [ -z "$SANDBOX_EXEC" ]; then
    echo "✗ no supported macOS network sandbox (sandbox-exec)" >&2
    exit 2
  fi
  SANDBOX_PROFILE="$WORK/network.sb"
  printf '%s\n' '(version 1)' '(allow default)' '(deny network*)' > "$SANDBOX_PROFILE"
  "$SANDBOX_EXEC" -f "$SANDBOX_PROFILE" "$SUBJECT_CMD"
  SUBJECT_EXIT=$?
elif [ "$OS_NAME" = "Linux" ]; then
  UNSHARE="$(command -v unshare || true)"
  if [ -z "$UNSHARE" ]; then
    echo "✗ no supported Linux network sandbox (unshare)" >&2
    exit 2
  fi
  "$UNSHARE" --user --map-current-user --net true >/dev/null 2>&1
  PROBE_EXIT=$?
  if [ "$PROBE_EXIT" -ne 0 ]; then
    echo "✗ Linux user+network namespace unavailable; refusing unsandboxed eval" >&2
    exit 2
  fi
  "$UNSHARE" --user --map-current-user --net "$SUBJECT_CMD"
  SUBJECT_EXIT=$?
else
  echo "✗ unsupported OS $OS_NAME; refusing unsandboxed eval" >&2
  exit 2
fi
set -e

if [ "$SUBJECT_EXIT" -ne 0 ]; then
  echo "✗ subject.sh exited $SUBJECT_EXIT" >&2
  exit "$SUBJECT_EXIT"
fi
echo "  ✓ subject completed"

set +e
REPO_ROOT="$REPO_ROOT" "$PYTHON_BIN" "$HARNESS_DIR/grade.py" --case "$CASE_DIR" --out "$OUT"
GRADE_EXIT=$?
set -e

if [ "$GRADE_EXIT" -ne 0 ]; then
  echo "✗ eval failed: $CASE_NAME" >&2
  exit "$GRADE_EXIT"
fi

echo "✓ eval passed: $CASE_NAME"
exit 0
