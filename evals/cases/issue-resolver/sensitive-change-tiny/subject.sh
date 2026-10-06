#!/usr/bin/env bash
# Sensitive-change fixture (issue #518): run the REAL gi-sensitive.py the way the
# resolver's Step 2 gate does, on an XS change that flips one comparison in an
# auth module.
#
#   classify   planned path src/auth/session.py, no labels → sensitive (auth)
#   ledger 1   one held pre-change probe, one independent challenger blocker at
#              confidence 15, left open → stop
#   ledger 2   the same blocker rebutted with a file:line citation the script
#              verifies in this repo → proceed, post-change probe → obligation
#   ledger 3   the same blocker "rebutted" with no citation → stop
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"
: "${EVAL_WORK:?EVAL_WORK is required}"
: "${EVAL_SCRIPTS_DIR:?EVAL_SCRIPTS_DIR is required}"

GATE="$EVAL_SCRIPTS_DIR/gi-sensitive.py"
REPO="$EVAL_WORK/sensitive-repo"
rm -rf "$REPO"
mkdir -p "$REPO/src/auth"
cat > "$REPO/src/auth/session.py" <<'PY'
"""Session expiry check used by every authenticated route."""


def is_expired(now: int, expires_at: int) -> bool:
    return now > expires_at
PY
cd "$REPO"

verdict() {
  python3 -c 'import json,sys; r=json.load(sys.stdin); print(r[sys.argv[1]] if sys.argv[1] != "open_blockers" else ",".join(r["open_blockers"]))' "$1"
}

sensitive="$(printf '%s' '{"labels":["bug"],"paths":["src/auth/session.py"]}' | python3 "$GATE" --classify)"
triggered="$(printf '%s' "$sensitive" | python3 -c 'import json,sys; print(json.load(sys.stdin)["sensitive"])')"

ledger() {  # ledger DISPOSITION REBUTTAL_JSON
  cat <<JSON
{"probes": [
   {"id": "P1", "assumption": "is_expired has exactly one definition", "phase": "pre",
    "command": "grep -rn 'def is_expired' src", "expect": "one match in src/auth/session.py",
    "falsified_if": "a second definition shadows it", "result": "held"},
   {"id": "P2", "assumption": "a token expiring now is rejected", "phase": "post",
    "command": "python3 -c 'from auth.session import is_expired; assert is_expired(5, 5)'",
    "expect": "exit 0", "falsified_if": "exit 1 — the boundary still admits the token",
    "result": null}],
 "replanned": false,
 "challenge": {"independent": true, "blockers": [
   {"id": "B1", "claim": "other callers rely on the inclusive boundary", "confidence": 15,
    "disposition": "$1", "rebuttal": $2, "rechallenge": null}]}}
JSON
}

stop="$(ledger open null | python3 "$GATE" --adjudicate | verdict verdict)"
open_b="$(ledger open null | python3 "$GATE" --adjudicate | verdict open_blockers)"
proceed="$(ledger rebutted '{"reason": "P1 shows the single definition the callers share", "citation": "src/auth/session.py:4"}' \
  | python3 "$GATE" --adjudicate | verdict verdict)"
obligations="$(ledger rebutted '{"reason": "see P1", "citation": "probe:P1"}' \
  | python3 "$GATE" --adjudicate | python3 -c 'import json,sys; print(",".join(json.load(sys.stdin)["test_obligations"]))')"
uncited="$(ledger rebutted '{"reason": "I am sure no caller depends on it", "citation": ""}' \
  | python3 "$GATE" --adjudicate | verdict verdict)"

{
  echo "triggered $triggered"
  echo "singleton $stop $open_b"
  echo "cited $proceed"
  echo "obligations $obligations"
  echo "uncited $uncited"
} > "$EVAL_OUT/gate.txt"

expected="$(printf '%s\n' 'triggered True' 'singleton stop B1' 'cited proceed' 'obligations P2' 'uncited stop')"
if [ "$(cat "$EVAL_OUT/gate.txt")" != "$expected" ]; then
  echo "✗ unexpected gate outcomes:" >&2
  cat "$EVAL_OUT/gate.txt" >&2
  exit 1
fi

# The auto-mode stop ends the run `failed` at Step 2 with no PR — an existing
# run-log outcome, so the record validates without a schema change.
cat > "$EVAL_OUT/run-stop.json" <<'JSON'
{
  "ts": "2026-10-06T12:00:00Z",
  "issue": 518,
  "mode": "auto",
  "skill": "issue-resolver",
  "complexity": "low",
  "profile": "light",
  "qa_cycles": 0,
  "outcome": "failed",
  "pr": null,
  "duration_s": 9
}
JSON
