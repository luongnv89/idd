#!/usr/bin/env bash
# test-runs-jsonl-rotation-354.sh — runs.jsonl rotation + parse-once reader
# (issue #354 / F-PERF-006, F-PERF-007).
#
# Behavior tests against the real scripts:
#   - gi-runlog.py rotates an oversized or idle active log into a timestamped
#     segment before appending, and readers (streak, append-once dedup,
#     idd-lint's loader) see identical logical content across the boundary.
#   - scripts/idd-lint.py parses runs.jsonl exactly once per
#     collect_github_stats call (instrumented assertion).
#
# Usage: bash tests/test-runs-jsonl-rotation-354.sh
# Returns: exit 0 if all tests pass, exit 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNLOG="$REPO_ROOT/src/shared/scripts/gi-runlog.py"
LINT="$REPO_ROOT/scripts/idd-lint.py"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failed_record() { # issue outcome [ts]
  printf '{"ts":"%s","issue":%s,"mode":"auto","skill":"issue-resolver","outcome":"%s","pr":null}' \
    "${3:-2026-08-20T00:00:00Z}" "$1" "$2"
}

echo "◆ Run-log rotation + parse-once Tests (issue #354)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T1: rotation cycle on an oversized fixture
# ───────────────────────────────────────────────────────────
# The old records move to one segment; the new record starts a fresh active
# log; the concatenation is the same logical content as before the write.
D="$TMP/t1"; mkdir -p "$D"; LOG="$D/runs.jsonl"
{
  for i in $(seq 1 40); do failed_record 9 failed "2026-08-01T00:00:$(printf '%02d' $i)Z"; echo; done
} > "$LOG"
PRE_STREAK="$(python3 "$RUNLOG" --failure-streak 9 --path "$LOG" | python3 -c 'import json,sys;print(json.load(sys.stdin)["streak"])')"
if failed_record 9 failed "2026-08-24T00:00:00Z" \
   | python3 "$RUNLOG" --append --path "$LOG" --rotate-max-bytes 500 >/dev/null 2>&1; then
  pass "T1: append after size trigger exits 0"
else
  fail "T1: append after size trigger exited nonzero"
fi
SEGMENTS="$(ls "$D"/runs-*.jsonl 2>/dev/null | wc -l | tr -d ' ')"
if [ "$SEGMENTS" = "1" ]; then
  pass "T1: exactly one timestamped segment created"
else
  fail "T1: expected 1 segment, found $SEGMENTS"
fi
ACTIVE_LINES="$(wc -l < "$LOG" | tr -d ' ')"
if [ "$ACTIVE_LINES" = "1" ]; then
  pass "T1: active log restarted with only the new record"
else
  fail "T1: active log has $ACTIVE_LINES lines, expected 1"
fi
TOTAL_LINES="$(cat "$D"/runs-*.jsonl "$LOG" | wc -l | tr -d ' ')"
if [ "$TOTAL_LINES" = "41" ]; then
  pass "T1: no record lost across the rotation boundary"
else
  fail "T1: segment+active hold $TOTAL_LINES lines, expected 41"
fi

# ───────────────────────────────────────────────────────────
# T2: streak reader sees identical logical content post-rotation
# ───────────────────────────────────────────────────────────
POST_STREAK="$(python3 "$RUNLOG" --failure-streak 9 --path "$LOG" | python3 -c 'import json,sys;print(json.load(sys.stdin)["streak"])')"
if [ "$POST_STREAK" = "$((PRE_STREAK + 1))" ] && [ "$PRE_STREAK" != "0" ]; then
  pass "T2: streak spans the boundary ($PRE_STREAK pre → $POST_STREAK post)"
else
  fail "T2: streak broke at rotation (pre=$PRE_STREAK post=$POST_STREAK)"
fi

# ───────────────────────────────────────────────────────────
# T3: idle-age trigger is mtime-based; fresh logs never rotate on ts
# ───────────────────────────────────────────────────────────
D="$TMP/t3"; mkdir -p "$D"; LOG="$D/runs.jsonl"
# A backdated record would rotate a content-age trigger instantly; mtime-based
# aging must leave this fresh log alone.
failed_record 5 success "2020-01-01T00:00:00Z" \
  | python3 "$RUNLOG" --append --path "$LOG" --rotate-max-days 30 >/dev/null 2>&1
if ls "$D"/runs-*-*.jsonl >/dev/null 2>&1; then
  fail "T3: backdated ts rotated a fresh log (age must be mtime-based)"
else
  pass "T3: backdated ts does not rotate a fresh log"
fi
touch -t 202001010000 "$LOG"  # idle far beyond any window
python3 "$RUNLOG" --append --path "$LOG" --rotate-max-days 30 --tail-segments 1 >/dev/null 2>&1 <<EOF
{"ts":"2026-08-24T00:00:00Z","issue":6,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":null}
EOF
if [ "$(ls "$D"/runs-*.jsonl 2>/dev/null | wc -l | tr -d ' ')" = "1" ] \
   && [ "$(wc -l < "$LOG" | tr -d ' ')" = "1" ]; then
  pass "T3: idle log rotates before its next append"
else
  fail "T3: mtime-idle log did not rotate"
fi

# ───────────────────────────────────────────────────────────
# T4: --no-rotate keeps a single file even past every threshold
# ───────────────────────────────────────────────────────────
D="$TMP/t4"; mkdir -p "$D"; LOG="$D/runs.jsonl"
for i in 1 2 3; do
  failed_record 9 failed | python3 "$RUNLOG" --append --path "$LOG" \
    --rotate-max-bytes 10 --rotate-max-days 0 --no-rotate >/dev/null 2>&1
done
if [ "$(ls "$D" | grep -c 'jsonl')" = "1" ] && [ "$(wc -l < "$LOG")" = "3" ]; then
  pass "T4: --no-rotate appends in place"
else
  fail "T4: --no-rotate still rotated or lost lines"
fi

# ───────────────────────────────────────────────────────────
# T5: idd-lint loader sees identical logical content across segments
# ───────────────────────────────────────────────────────────
# Malformed lines are skipped with the shared no-schema-migration tolerance.
mkdir -p "$TMP/t5"
if D="$TMP/t5" LINT_PATH="$LINT" python3 - <<'PY'
import importlib.util, json, os, pathlib, sys
spec = importlib.util.spec_from_file_location('idd_lint', os.environ['LINT_PATH'])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
d = pathlib.Path(os.environ['D']); act = d / 'runs.jsonl'
seg = d / 'runs-20260801T000000Z.jsonl'
rows_old = [{'ts': '2026-08-01T00:00:00Z', 'issue': 1, 'outcome': 'success'},
            {'ts': '2026-08-02T00:00:00Z', 'issue': 2, 'outcome': 'failed'}]
seg.write_text('\n'.join(json.dumps(r) for r in rows_old) + '\ncorrupt {\n', encoding='utf-8')
act.write_text(json.dumps({'ts': '2026-08-24T00:00:00Z', 'issue': 3, 'outcome': 'success'}) + '\n', encoding='utf-8')
loaded = m.load_run_rows(act)
assert loaded and [r['issue'] for r in loaded] == [1, 2, 3], loaded
stats = m.collect_run_stats(loaded)
assert stats['runs'] == 3 and stats['issues'] == [1, 2, 3], stats
PY
then
  pass "T5: load_run_rows aggregates segments+active, skipping corrupt lines"
else
  fail "T5: load_run_rows missed segment rows or choked on corrupt input"
fi

# ───────────────────────────────────────────────────────────
# T6: parse-once instrumentation (AC) — exactly one parse per call
# ───────────────────────────────────────────────────────────
if LINT_PATH="$LINT" python3 - <<'PY'
import importlib.util, json, os, pathlib, tempfile
spec = importlib.util.spec_from_file_location('idd_lint', os.environ['LINT_PATH'])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as tmp:
    log = pathlib.Path(tmp) / 'runs.jsonl'
    log.write_text(json.dumps({'issue': 1, 'outcome': 'success'}) + '\n', encoding='utf-8')
    calls = []
    orig = m.load_run_rows
    def counting(path):
        calls.append('parse')
        return orig(path)
    m.load_run_rows = counting
    m._gh_json = lambda *a: [{'number': 1, 'body': '<!-- gitissue:normalized v1 -->'}]
    m.collect_issue_normalization_stats = lambda limit: {'open_issues': 0}
    m.collect_merged_pr_stats = lambda limit, window: None
    m.collect_github_stats(200, log)
    assert len(calls) == 1, f'expected 1 parse per collect_github_stats call, got {len(calls)}'
    calls.clear()
    rows = orig(log)
    m.collect_github_stats(200, log, run_rows=rows)
    assert calls == [], f'preloaded rows must not re-parse, got {calls}'
PY
then
  pass "T6: runs.jsonl parsed exactly once per collect_github_stats call"
else
  fail "T6: collect_github_stats parsed runs.jsonl more than once"
fi

# ───────────────────────────────────────────────────────────
# T7: append-once dedup survives rotation
# ───────────────────────────────────────────────────────────
D="$TMP/t7"; mkdir -p "$D"; LOG="$D/runs.jsonl"
REC='{"ts":"2026-08-24T00:00:00Z","event_id":"run-354:x","issue":42,"mode":"balanced","skill":"auto-pilot","outcome":"merged","pr":87}'
printf '%s' "$REC" | python3 "$RUNLOG" --append-once --path "$LOG" --rotate-max-bytes 1 >/dev/null 2>&1
# Rotation fired for the retry too (the log was over threshold); the event
# now lives in the segment, so dedup must find it there.
STATUS="$(printf '%s' "$REC" | python3 "$RUNLOG" --append-once --path "$LOG" --rotate-max-bytes 1 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["status"])' || true)"
COPIES=0
for f in "$D"/runs*.jsonl*; do
  [ -f "$f" ] || continue
  COPIES=$((COPIES + $(grep -cF '"run-354:x"' "$f" || true)))
done
if [ "$STATUS" = "already_present" ] && [ "$COPIES" = "1" ]; then
  pass "T7: identical retry stays deduped across the rotation boundary"
else
  fail "T7: status=$STATUS copies=$COPIES (want already_present / 1)"
fi
CONFLICT="$(printf '%s' "${REC/merged/failed}" | python3 "$RUNLOG" --append-once --path "$LOG" --rotate-max-bytes 0 2>/dev/null; echo "exit=$?")"
case "$CONFLICT" in
  *"exit=3"*) pass "T7: conflicting payload still rejected (exit 3)" ;;
  *) fail "T7: conflict handling regressed ($CONFLICT)" ;;
esac

# ───────────────────────────────────────────────────────────
# T8: rotation failure is non-fatal — warn, then append anyway
# ───────────────────────────────────────────────────────────
# A rename that cannot proceed (permissions, exotic filesystems) must cost a
# stderr warning, never the record. The rename is stubbed to fail so the
# contract is exercised deterministically.
if ROTATE_PATH="$RUNLOG" python3 - <<'PY'
import importlib.util, io, os, pathlib, tempfile
from contextlib import redirect_stderr

spec = importlib.util.spec_from_file_location('gi_runlog', os.environ['ROTATE_PATH'])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as tmp:
    log = pathlib.Path(tmp) / 'runs.jsonl'
    log.write_text('x\n', encoding='utf-8')
    orig_rename = pathlib.Path.rename
    def broken_rename(self, target):
        raise OSError(13, 'Permission denied')
    pathlib.Path.rename = broken_rename
    try:
        err = io.StringIO()
        with redirect_stderr(err):
            seg = m.maybe_rotate(log, max_bytes=1, max_days=0)
    finally:
        pathlib.Path.rename = orig_rename
    assert seg is None and 'could not rotate' in err.getvalue(), (seg, err.getvalue())
    assert log.exists(), 'active log vanished after a failed rotation'
PY
then
  pass "T8: failed rename warns and leaves the active log intact"
else
  fail "T8: rotation failure was fatal or silent"
fi

# ───────────────────────────────────────────────────────────
# T9: usage guards and echo isolation
# ───────────────────────────────────────────────────────────
D="$TMP/t9"; mkdir -p "$D"; LOG="$D/runs.jsonl"
printf '%s' '{"ts":"2026-08-24T00:00:00Z","issue":1,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":null}' \
  | python3 "$RUNLOG" --echo --path "$LOG" --rotate-max-bytes 1 >/dev/null 2>&1
if [ ! -e "$LOG" ]; then
  pass "T9: --echo never creates or rotates a log"
else
  fail "T9: --echo touched the filesystem"
fi
if printf '%s' '{"ts":"2026-08-24T00:00:00Z","issue":1,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":null}' \
   | python3 "$RUNLOG" --append --path "$LOG" --rotate-max-bytes -5 >/dev/null 2>&1; then
  fail "T9: negative --rotate-max-bytes accepted"
else
  rc=$?
  if [ "$rc" = "2" ]; then
    pass "T9: negative threshold is a usage error (exit 2)"
  else
    fail "T9: negative threshold returned exit $rc, want 2"
  fi
fi

# ───────────────────────────────────────────────────────────
# T10: rotated segments are gitignored (regression — a segment is
# machine-local telemetry and must never become committable)
# ───────────────────────────────────────────────────────────
if git -C "$REPO_ROOT" check-ignore -q .gitissue/runs.jsonl; then
  pass "T10: active run log is gitignored"
else
  fail "T10: .gitissue/runs.jsonl is NOT gitignored"
fi
SEG_IGNORED=1
for seg in .gitissue/runs-20260101T000000Z.jsonl .gitissue/runs-20260824T120000Z.jsonl; do
  git -C "$REPO_ROOT" check-ignore -q "$seg" || { SEG_IGNORED=0; fail "T10: $seg is NOT gitignored"; }
done
if [ "$SEG_IGNORED" = "1" ]; then
  pass "T10: rotated runs-<stamp>.jsonl segments are gitignored"
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ run-log rotation tests failed"
  exit 1
fi

echo "  ✓ runs.jsonl rotation and parse-once reader behave as specified (#354)"
exit 0
