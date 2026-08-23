#!/usr/bin/env bash
# Coverage over the shared Python script entry points (issue #333 / F-TEST-001).
#
# Hermetic and offline: every invocation below is one the shell test suite
# itself exercises, with payloads copied from tests/. Some error-path
# invocations exit non-zero on purpose — that is data for the measurement,
# not a runner failure. The --fail-under floor lives in .coveragerc
# ([report] fail_under) and is enforced by `coverage report` at the end.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PY="${COVERAGE_PYTHON:-python3}"
RC=.coveragerc

if ! "$PY" -m coverage --version >/dev/null 2>&1; then
  echo "✗ coverage.py is not installed for $PY" >&2
  echo "To fix:  $PY -m pip install coverage" >&2
  echo "Docs:    https://coverage.readthedocs.io/" >&2
  exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SCRIPTS=src/shared/scripts

"$PY" -m coverage erase --rcfile="$RC" 2>/dev/null || rm -f .coverage .coverage.*

# run <args...> — one traced invocation; its exit status is not asserted.
run() { "$PY" -m coverage run -a --rcfile="$RC" "$@" >/dev/null 2>&1 || true; }

# Every entry point: the argparse surface (--help) the shell suite checks.
for s in "$SCRIPTS"/*.py; do
  run "$s" --help
done

# Network-bound entry points get --help only (they shell out to gh): gi-issue,
# gi-ci-wait, gi-secscan. Named here so the wiring check can see them.
run "$SCRIPTS/gi-issue.py" --help
run "$SCRIPTS/gi-ci-wait.py" --help
run "$SCRIPTS/gi-secscan.py" --help

# gi-config — merge defaults with this repo's real config, then a dotted key.
run "$SCRIPTS/gi-config.py"
run "$SCRIPTS/gi-config.py" --key resolve.qa_max_cycles

# gi-deps — local dependency numbers out of an issue body on stdin.
printf '%s' 'Depends on #12, blocked by #8. Cross-repo org/repo#77 is ignored.' | \
  run "$SCRIPTS/gi-deps.py"

# gi-dup-score — scorer request on stdin, existing issues from a file.
printf '%s' '{"mode":"create","items":[{"index":1,"title":"login broken","keywords":[],"type":"bug"}]}' > "$TMP/dup-request.json"
printf '[]\n' > "$TMP/dup-issues.json"
run "$SCRIPTS/gi-dup-score.py" --issues-from "$TMP/dup-issues.json" < "$TMP/dup-request.json"

# gi-runlog — validate-and-echo one record; count a failure streak from a log.
printf '%s' '{"ts":"2026-08-23T00:00:00Z","issue":333,"mode":"resolve","skill":"issue-resolver","outcome":"success","pr":1,"qa_cycles":1,"ceiling":2}' | \
  run "$SCRIPTS/gi-runlog.py" --echo
printf '%s' '{"ts":"2026-08-23T00:01:00Z","issue":61,"mode":"resolve","skill":"issue-resolver","outcome":"failed"}' >> "$TMP/runs.jsonl"
run "$SCRIPTS/gi-runlog.py" --failure-streak 61 --path "$TMP/runs.jsonl"

# gi-stack-detect — scan this repository.
run "$SCRIPTS/gi-stack-detect.py" --root .

# gi-state — init, read, and report run state in a temp dir.
mkdir -p "$TMP/state"
printf '%s' '{"run_id":"cov-run-0001","mode":"balanced","invocation":"/auto-pilot","queue":[333],"limit":1}' | \
  run "$SCRIPTS/gi-state.py" --init --dir "$TMP/state"
run "$SCRIPTS/gi-state.py" --read --dir "$TMP/state"
printf '%s' '{"run_id":"cov-run-0001","markdown":"## done"}' | \
  run "$SCRIPTS/gi-state.py" --report --dir "$TMP/state"

# gi-triage-graph — documented payload, computed offline (fixed --now clock).
cat > "$TMP/graph-scan.json" <<'EOF'
{"issues":[
 {"number":12,"title":"Fix auth redirect","type":"bug","labels":["bug","auth"],
  "createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-03-18T10:00:00Z",
  "affected_files":["auth.py","middleware.py"]},
 {"number":15,"title":"Refactor DB","type":"improvement","labels":[],
  "createdAt":"2026-02-01T00:00:00Z","updatedAt":"2026-03-10T10:00:00Z",
  "affected_files":["auth.py"]}],
 "edges":[{"a":12,"b":15}]}
EOF
run "$SCRIPTS/gi-triage-graph.py" --no-config --now 2026-03-20T14:30:00Z < "$TMP/graph-scan.json"

# gi-model-cache — lifecycle against an empty installed-skill folder.
mkdir -p "$TMP/skill"
run "$SCRIPTS/gi-model-cache.py" --skill-dir "$TMP/skill" --no-seed

# gi-ratelimit — pure arithmetic over fixed instants, no network.
run "$SCRIPTS/gi-ratelimit.py" --backoff --attempt 2 --now 2026-08-23T00:00:00Z
run "$SCRIPTS/gi-ratelimit.py" --budget --max-minutes 30 --started-at 2026-08-23T00:00:00Z --now 2026-08-23T00:10:00Z
printf '%s' '{"rate":{"remaining":4000,"limit":5000,"reset":1755902400}}' | \
  run "$SCRIPTS/gi-ratelimit.py" --verdict --now 2026-08-23T00:00:00Z

# gi-branch — derive a name locally (never --from-issue here: that needs gh).
run "$SCRIPTS/gi-branch.py" 42 --title "Fix login crash on mobile" --type bug --no-config

# Report: enforce the pinned floor, publish text + XML + HTML artifacts.
REPORT_DIR=coverage-report
mkdir -p "$REPORT_DIR"
"$PY" -m coverage report --rcfile="$RC" -m | tee "$REPORT_DIR/coverage.txt"
STATUS=${PIPESTATUS[0]}
"$PY" -m coverage xml --rcfile="$RC" -o "$REPORT_DIR/coverage.xml" >/dev/null 2>&1 || true
"$PY" -m coverage html --rcfile="$RC" -d "$REPORT_DIR/htmlcov" >/dev/null 2>&1 || true
exit "$STATUS"
