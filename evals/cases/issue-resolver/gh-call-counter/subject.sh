#!/usr/bin/env bash
# gh-call counter (issue #465): run the REAL gi-issue.py through the shim in the
# resolver's read pattern and let the shim's call log count what it cost.
#
#   read 1       cache miss       → gh issue view
#   read 2       TTL hit          → no gh call
#   --invalidate drop the entry   → no gh call
#   read 3       cache miss       → gh issue view
#   read 4       --refresh        → gh issue view
#
# Expected: exactly 3 gh calls. --ttl 86400 makes read 2 a hit on any clock,
# and the cache lives under $EVAL_WORK, never in a real repository.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"
: "${EVAL_WORK:?EVAL_WORK is required}"
: "${EVAL_SCRIPTS_DIR:?EVAL_SCRIPTS_DIR is required}"

ISSUE="$EVAL_SCRIPTS_DIR/gi-issue.py"
CACHE="$EVAL_WORK/issue-cache"
FIELDS="number,title,body,labels,state"

read_issue() {
  python3 "$ISSUE" 7 --fields "$FIELDS" --ttl 86400 --cache-dir "$CACHE" "$@" \
    | python3 -c 'import json,sys; print("cached" if json.load(sys.stdin)["cached"] else "fetched")'
}

{
  echo "read-1 $(read_issue)"
  echo "read-2 $(read_issue)"
  python3 "$ISSUE" 7 --invalidate --cache-dir "$CACHE" >/dev/null
  echo "invalidate"
  echo "read-3 $(read_issue)"
  echo "read-4 $(read_issue --refresh)"
} > "$EVAL_OUT/reads.txt"

expected="$(printf '%s\n' 'read-1 fetched' 'read-2 cached' 'invalidate' 'read-3 fetched' 'read-4 fetched')"
if [ "$(cat "$EVAL_OUT/reads.txt")" != "$expected" ]; then
  echo "✗ unexpected cache outcomes:" >&2
  cat "$EVAL_OUT/reads.txt" >&2
  exit 1
fi
