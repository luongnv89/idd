#!/usr/bin/env bash
# Third-failure fixture (issue #519): run the REAL gi-premise.py the way the
# resolver's Step 4 premise-reset check does.
#
#   cycles 1-2  two fixes both act on "the cache key omits the locale" (worded
#               differently) and the locale test still fails → blocked
#   diagnostic  the orchestrator runs the test itself, records exit + excerpt,
#               reruns it, and the rerun matches → a revised premise
#               ("the locale is read before it is set") is accepted → unblocked
#   mismatch    a rerun that no longer shows the recorded excerpt (a flaky
#               diagnostic) → the block holds
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"
: "${EVAL_WORK:?EVAL_WORK is required}"
: "${EVAL_SCRIPTS_DIR:?EVAL_SCRIPTS_DIR is required}"

PREMISE="$EVAL_SCRIPTS_DIR/gi-premise.py"
REPO="$EVAL_WORK/premise-repo"
rm -rf "$REPO"
mkdir -p "$REPO"
cat > "$REPO/cache.py" <<'PY'
LOCALE = "en"            # BUG: read at import time, before the request sets it


def set_locale(value):
    global _requested
    _requested = value


def cache_key(path):
    return f"{LOCALE}:{path}"
PY
cat > "$REPO/test_cache.py" <<'PY'
import cache

cache.set_locale("fr")
key = cache.cache_key("/home")
if not key.startswith("fr:"):
    print(f"AssertionError: expected 'fr' got {key.split(':')[0]!r}")
    raise SystemExit(1)
print("ok")
PY
cd "$REPO"

blocked() { python3 "$PREMISE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["blocked"])'; }

failures='[{"cycle": 1, "premise_id": "A", "premise": "the cache key omits the locale"},
           {"cycle": 2, "premise_id": "A", "premise": "locale missing from the key builder"}]'
after_two="$(printf '{"failures": %s}' "$failures" | blocked)"

# The orchestrator's own diagnostic: the recorded suite command, run twice.
set +e
first="$(python3 test_cache.py 2>&1)"; first_exit=$?
second="$(python3 test_cache.py 2>&1)"; second_exit=$?
set -e
printf '%s\n' "$second" > "$EVAL_OUT/diagnostic-rerun.txt"

revision() {  # revision RERUN_EXIT RERUN_OUTPUT
  python3 - "$failures" "$first_exit" "$first" "$1" "$2" <<'PY'
import json, sys
failures, rec_exit, rec_out, rerun_exit, rerun_out = sys.argv[1:]
print(json.dumps({
    "failures": json.loads(failures),
    "revisions": [{
        "resets": "A", "after_cycle": 2, "premise_id": "B",
        "premise": "LOCALE is read at import time, before set_locale runs",
        "supports": "the key carries 'en' although set_locale('fr') ran first",
        "diagnostics": [{
            "command": "python3 test_cache.py",
            "recorded": {"exit": int(rec_exit), "excerpt": rec_out.strip()},
            "rerun": {"exit": int(rerun_exit), "output": rerun_out},
        }],
    }],
}))
PY
}
unblocked="$(revision "$second_exit" "$second" | blocked)"
mismatch="$(revision 0 "ok" | blocked)"

{
  echo "after-two-failures blocked=$after_two"
  echo "diagnostic exit=$first_exit rerun=$second_exit"
  echo "revised-premise blocked=$unblocked"
  echo "mismatched-rerun blocked=$mismatch"
} > "$EVAL_OUT/premise.txt"

expected="$(printf '%s\n' 'after-two-failures blocked=True' 'diagnostic exit=1 rerun=1' 'revised-premise blocked=False' 'mismatched-rerun blocked=True')"
if [ "$(cat "$EVAL_OUT/premise.txt")" != "$expected" ]; then
  echo "✗ unexpected premise outcomes:" >&2
  cat "$EVAL_OUT/premise.txt" >&2
  exit 1
fi
