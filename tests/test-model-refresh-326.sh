#!/usr/bin/env bash
# test-model-refresh-326.sh — Validate scripts/gi-model-refresh.py (issue #326).
#
# The refresh script is CI-only tooling behind
# .github/workflows/model-data-refresh.yml. These are behavioral tests over a
# temporary seed copy — no network: stale runs inject a local payload through
# the test-only `--from-file` hook, exactly as the workflow would receive one
# from the fetch.
#
#  AC1. The script exists where the workflow runs it and answers --help.
#  AC2. A seed inside the TTL exits 0, reports updated:false, logs the skip,
#       and leaves the file byte-identical.
#  AC3. The staleness math matches gi-model-cache.py: age == TTL is fresh;
#       only age > TTL is stale.
#  AC4. A stale seed plus a valid payload rewrites it atomically with the
#       fetched content and today's last_fetched.
#  AC5. A garbage or non-model-data payload exits 4 (degrade) and never
#       touches the seed.
#  AC6. A missing/unreadable seed or a malformed --now exits 3 (stop).
#
# Usage: bash tests/test-model-refresh-326.sh
# Returns: exit 0 if all tests pass, exit 1 on any failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/gi-model-refresh.py"
SEED_SRC="$REPO_ROOT/src/skills/issue-creator/templates/model-data.json"

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

# run_case <out-file> <err-file> <cmd...> — capture stdout/stderr/exit code
# without tripping set -e.
run_case() {
  local __out="$1" __err="$2"
  shift 2
  set +e
  "$@" >"$__out" 2>"$__err"
  RUN_RC=$?
  set -e
}

# jget <json-text> <key> — top-level string/bool value of key, empty if absent.
jget() {
  printf '%s' "$1" | python3 -c '
import json, sys
value = json.load(sys.stdin).get(sys.argv[1])
print("" if value is None else str(value).lower() if isinstance(value, bool) else value)
' "$2"
}

# make_seed <dest> <last-fetched> — copy the shipped seed to <dest> and pin its
# last_fetched to an explicit test date. Hermetic: the tests must not depend on
# the seed's real last_fetched, which this very feature rewrites every week.
make_seed() {
  python3 - "$SEED_SRC" "$1" "$2" <<'PY'
import json, sys

data = json.load(open(sys.argv[1]))
data["last_fetched"] = sys.argv[3]
json.dump(data, open(sys.argv[2], "w"), indent=2)
PY
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "◆ Model Data Refresh Tests (issue #326)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T0 (AC1): files exist; the CLI contract answers --help
# ───────────────────────────────────────────────────────────
for f in "$SCRIPT" "$SEED_SRC" "$REPO_ROOT/.github/workflows/model-data-refresh.yml"; do
  if [ -f "$f" ]; then
    pass "T0: ${f#"$REPO_ROOT"/} exists"
  else
    fail "T0: $f not found"
    exit 1
  fi
done

run_case "$TMP/help.out" "$TMP/help.err" python3 "$SCRIPT" --help
if [ "$RUN_RC" -eq 0 ] && grep -q -- '--from-file' "$TMP/help.out"; then
  pass "T0: --help exits 0 and documents the --from-file test hook"
else
  fail "T0: --help broken (rc=$RUN_RC)"
fi

# ───────────────────────────────────────────────────────────
# T1 (AC2): a fresh seed skips the update, cleanly
# ───────────────────────────────────────────────────────────
SEED1="$TMP/fresh.json"
make_seed "$SEED1" "2026-06-12T00:00:00Z"   # 4 days before the injected --now
BEFORE="$(cat "$SEED1")"

run_case "$TMP/t1.out" "$TMP/t1.err" \
  python3 "$SCRIPT" --seed "$SEED1" --now 2026-06-16
OUT="$(cat "$TMP/t1.out")"
if [ "$RUN_RC" -eq 0 ] \
   && [ "$(jget "$OUT" updated)" = "false" ] \
   && [ "$(jget "$OUT" age_days)" = "4" ]; then
  pass "T1: a seed 4 days old exits 0 with updated:false"
else
  fail "T1: fresh run wrong (rc=$RUN_RC, out: $OUT)"
fi

if grep -q 'fresher than 7 days — skipping update' "$TMP/t1.err"; then
  pass "T1: the skip carries a clear log message"
else
  fail "T1: no clear skip message on stderr ($(cat "$TMP/t1.err"))"
fi

if [ "$(cat "$SEED1")" = "$BEFORE" ]; then
  pass "T1: the untouched seed is byte-identical"
else
  fail "T1: a skipped run modified the seed"
fi

# ───────────────────────────────────────────────────────────
# T2 (AC3): age == TTL is still fresh — same boundary as gi-model-cache
# ───────────────────────────────────────────────────────────
run_case "$TMP/t2.out" "$TMP/t2.err" \
  python3 "$SCRIPT" --seed "$SEED1" --now 2026-06-19
if [ "$RUN_RC" -eq 0 ] && [ "$(jget "$(cat "$TMP/t2.out")" updated)" = "false" ]; then
  pass "T2: age == ttl_days (7) is not yet stale"
else
  fail "T2: age == TTL misclassified (rc=$RUN_RC)"
fi

# ───────────────────────────────────────────────────────────
# T3 (AC4): a stale seed plus a valid payload refreshes in place
# ───────────────────────────────────────────────────────────
FIXTURE="$TMP/payload.json"
python3 - "$SEED_SRC" "$FIXTURE" <<'PY'
import json, sys

data = json.load(open(sys.argv[1]))
data["marker"] = "refresh-fixture"
data["last_fetched"] = "2026-01-01T00:00:00Z"
json.dump(data, open(sys.argv[2], "w"), indent=2)
PY

# Re-pin the seed to a stale date relative to the injected --now 2026-07-01.
make_seed "$SEED1" "2026-06-12T00:00:00Z"

run_case "$TMP/t3.out" "$TMP/t3.err" \
  python3 "$SCRIPT" --seed "$SEED1" --from-file "$FIXTURE" --now 2026-07-01
OUT="$(cat "$TMP/t3.out")"
if [ "$RUN_RC" -eq 0 ] && [ "$(jget "$OUT" updated)" = "true" ]; then
  pass "T3: a stale seed plus a valid payload exits 0 with updated:true"
else
  fail "T3: refresh run wrong (rc=$RUN_RC, out: $OUT)"
fi

REFRESHED="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("marker",""),d.get("last_fetched",""))' "$SEED1")"
if [ "$REFRESHED" = "refresh-fixture 2026-07-01T00:00:00Z" ]; then
  pass "T3: the seed now carries the fetched content and today's last_fetched"
else
  fail "T3: refreshed seed wrong ($REFRESHED)"
fi

if [ "$(jget "$OUT" previous_last_fetched)" = "2026-06-12T00:00:00Z" ]; then
  pass "T3: the report records the previous last_fetched"
else
  fail "T3: previous_last_fetched missing ($(printf '%s' "$OUT"))"
fi

# No stray temp files left beside the rewritten seed.
if ls "$TMP"/.model-data.* >/dev/null 2>&1; then
  fail "T3: atomic write left a .model-data.* temp file behind"
else
  pass "T3: atomic write left no temp files"
fi

# ───────────────────────────────────────────────────────────
# T4 (AC5): garbage fetched content degrades (exit 4), seed untouched
# ───────────────────────────────────────────────────────────
GARBAGE="$TMP/garbage.json"
printf 'not json at all\n' > "$GARBAGE"
cp "$SEED1" "$TMP/t4.before"
run_case "$TMP/t4.out" "$TMP/t4.err" \
  python3 "$SCRIPT" --seed "$SEED1" --from-file "$GARBAGE" --now 2026-08-01
if [ "$RUN_RC" -eq 4 ] && cmp -s "$SEED1" "$TMP/t4.before"; then
  pass "T4: a corrupt payload exits 4 and leaves the seed intact"
else
  fail "T4: corrupt payload mishandled (rc=$RUN_RC)"
fi

# Valid JSON that is not a model-data document hits the same boundary.
JUNK="$TMP/junk.json"
printf '{"hello": 1}\n' > "$JUNK"
run_case "$TMP/t5.out" "$TMP/t5.err" \
  python3 "$SCRIPT" --seed "$SEED1" --from-file "$JUNK" --now 2026-08-01
if [ "$RUN_RC" -eq 4 ] && cmp -s "$SEED1" "$TMP/t4.before"; then
  pass "T5: a non-model-data payload exits 4 through the shared validation boundary"
else
  fail "T5: non-model-data payload mishandled (rc=$RUN_RC)"
fi

# ───────────────────────────────────────────────────────────
# T6 (AC6): caller-supplied input problems stop with exit 3
# ───────────────────────────────────────────────────────────
run_case "$TMP/t6.out" "$TMP/t6.err" \
  python3 "$SCRIPT" --seed "$TMP/no-such-seed.json" --now 2026-08-01
[ "$RUN_RC" -eq 3 ] && pass "T6: a missing seed exits 3 (stop)" \
                 || fail "T6: missing seed exited $RUN_RC, expected 3"

run_case "$TMP/t7.out" "$TMP/t7.err" \
  python3 "$SCRIPT" --seed "$SEED1" --now 2026-02-30
[ "$RUN_RC" -eq 3 ] && pass "T6: an impossible --now date exits 3" \
                 || fail "T6: impossible --now exited $RUN_RC, expected 3"

run_case "$TMP/t8.out" "$TMP/t8.err" \
  python3 "$SCRIPT" --seed "$SEED1" --ttl-days -1 --now 2026-08-01
[ "$RUN_RC" -eq 3 ] && pass "T6: a negative --ttl-days exits 3" \
                 || fail "T6: negative --ttl-days exited $RUN_RC, expected 3"

# ───────────────────────────────────────────────────────────
# T7: stdout is always exactly one JSON object on success paths
# ───────────────────────────────────────────────────────────
if python3 -c 'import json,sys; json.loads(open(sys.argv[1]).read())' "$TMP/t3.out" 2>/dev/null \
   && [ "$(wc -l < "$TMP/t3.out" | tr -d ' ')" -le 1 ]; then
  pass "T7: success output is a single JSON object line"
else
  fail "T7: success output is not a single JSON object"
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  Result: FAIL"
  exit 1
else
  echo "  Result: PASS"
  exit 0
fi
