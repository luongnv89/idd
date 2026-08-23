#!/usr/bin/env bash
# test-bug-sweep-343.sh — Issue #343 acceptance checks: low-severity bug sweep.
#
# Four regression blocks, one per finding:
#   F-BUG-004  gi-issue write_cache is torn-write-safe under concurrent
#              fetches (mkstemp + os.replace, unique temp per writer).
#   F-BUG-005  idd-lint read_input catches OSError/UnicodeDecodeError and
#              exits 2 with an error message — never a traceback (0/1/2
#              exit contract).
#   F-BUG-006  P03 validates ACV rows position-independently so a headerless
#              table keeps its first data row; the dead len(r) < 3 branch in
#              no_evidence is gone.
#   F-BUG-007  gi-state sweeps orphaned run.lock.retired-* strays under
#              _lock_guard; --dry-run still does not mutate.
#
# Usage: bash tests/test-bug-sweep-343.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GIISSUE="$REPO_ROOT/src/shared/scripts/gi-issue.py"
GISTATE="$REPO_ROOT/src/shared/scripts/gi-state.py"
LINT="$REPO_ROOT/scripts/idd-lint.py"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "◆ Low-severity bug sweep (issue #343)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T1 — F-BUG-004: write_cache atomicity
# ───────────────────────────────────────────────────────────
if grep -q "tempfile.mkstemp" "$GIISSUE"; then
  pass "T1: write_cache uses tempfile.mkstemp (unique temp per writer)"
else
  fail "T1: write_cache still uses a fixed temp name"
fi
if ! grep -q 'path.with_suffix(".tmp")' "$GIISSUE"; then
  pass "T1: fixed .tmp sibling name removed"
else
  fail "T1: write_cache still writes a fixed path.with_suffix(.tmp) name"
fi

CACHE="$TMP/cache"
mkdir -p "$CACHE"
python3 - "$GIISSUE" "$CACHE" <<'EOF'
import importlib.util
import json
import os
import sys

spec = importlib.util.spec_from_file_location("gi_issue", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
from pathlib import Path

cache_dir = Path(sys.argv[2])
target = cache_dir / "issue-1.json"
m.write_cache(target, {"hello": "world"})
ok = json.loads(target.read_text(encoding="utf-8")) == {"hello": "world"}
mode = ok and (os.stat(target).st_mode & 0o777) == 0o600
strays = [p.name for p in cache_dir.iterdir() if ".tmp" in p.name]
sys.exit(0 if (ok and mode and not strays) else 1)
EOF
if [ $? -eq 0 ]; then
  pass "T1: single write lands valid JSON at mode 0600 with no tmp strays"
else
  fail "T1: single write broken (payload, mode, or stray temp file)"
fi

for i in 1 2 3 4 5 6 7 8; do
  python3 - "$GIISSUE" "$CACHE/conc.json" "$i" <<'EOF' &
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("gi_issue", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
from pathlib import Path

for _ in range(30):
    m.write_cache(Path(sys.argv[2]), {"writer": int(sys.argv[3])})
EOF
done
wait
CONC_STATUS=0
python3 - "$CACHE/conc.json" <<'EOF' || CONC_STATUS=$?
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
sys.exit(0 if isinstance(data, dict) and "writer" in data else 1)
EOF
if [ "$CONC_STATUS" -eq 0 ]; then
  pass "T1: final cache file parses after 8 concurrent writers x30 writes"
else
  fail "T1: concurrent writers tore the cache write"
fi

# ─────────────────────────────────────────────────────────--
# T2 — F-BUG-005: read_input exit contract
# ───────────────────────────────────────────────────────────
ERR_OUT="$(python3 "$LINT" issue "$TMP/does-not-exist.md" 2>&1 >/dev/null)" && LINT_STATUS=0 || LINT_STATUS=$?
if [ "$LINT_STATUS" -eq 2 ] && printf '%s' "$ERR_OUT" | grep -q "cannot read input"; then
  pass "T2: unreadable file → exit 2 with an error message"
else
  fail "T2: unreadable file → exit $LINT_STATUS (want 2), stderr: $ERR_OUT"
fi
if printf '%s' "$ERR_OUT" | grep -q "Traceback"; then
  fail "T2: unreadable file still prints a traceback"
else
  pass "T2: unreadable file produces no traceback"
fi

printf '\xff\xfe\x00b\x00a\x00d' > "$TMP/binary.md"
BIN_OUT="$(python3 "$LINT" issue "$TMP/binary.md" 2>&1 >/dev/null)" && BIN_STATUS=0 || BIN_STATUS=$?
if [ "$BIN_STATUS" -eq 2 ] && printf '%s' "$BIN_OUT" | grep -q "cannot read input"; then
  pass "T2: non-UTF-8 input → exit 2 with an error message"
else
  fail "T2: non-UTF-8 input → exit $BIN_STATUS (want 2), stderr: $BIN_OUT"
fi

# ───────────────────────────────────────────────────────────
# T3 — F-BUG-006: P03 position-independent ACV rows
# ───────────────────────────────────────────────────────────
cat > "$TMP/pr-headerless.md" <<'EOF'
## Acceptance Criteria Verification

| fix login redirect | pass | tests/test-x.sh |
| add logout button | unverified | manual only |
EOF
P03_OUT="$(python3 "$LINT" --level L2 pr "$TMP/pr-headerless.md" 2>&1)" || true
if printf '%s' "$P03_OUT" | grep -q "AC verification table valid (2 rows)"; then
  pass "T3: headerless ACV table keeps both data rows"
elif printf '%s' "$P03_OUT" | grep -q "AC verification table valid (1 rows)\|has no data rows"; then
  fail "T3: headerless ACV table lost its first data row"
else
  fail "T3: unexpected P03 verdict for headerless table: $(printf '%s' "$P03_OUT" | grep P03 || echo none)"
fi

cat > "$TMP/pr-canonical.md" <<'EOF'
## Acceptance Criteria Verification

| Criterion | Status | Evidence |
|-----------|--------|----------|
| fix login redirect | pass | tests/test-x.sh |
EOF
P03_CANON="$(python3 "$LINT" --level L2 pr "$TMP/pr-canonical.md" 2>&1)" || true
if printf '%s' "$P03_CANON" | grep -q "AC verification table valid (1 row)"; then
  pass "T3: canonical header table still skips the header by content"
else
  fail "T3: canonical header table regressed: $(printf '%s' "$P03_CANON" | grep P03 || echo none)"
fi

if sed -n '/P03 (L2)/,/^\s*if level/p' "$LINT" | grep -q "len(r) < 3"; then
  fail "T3: dead len(r) < 3 branch still present in the P03 block"
else
  pass "T3: dead len(r) < 3 branch removed from the P03 block"
fi

# ───────────────────────────────────────────────────────────
# T4 — F-BUG-007: orphaned retired-lock strays swept
# ───────────────────────────────────────────────────────────
STATE_DIR="$TMP/state"
mkdir -p "$STATE_DIR"
printf '%s\n' '{"run_id": "ghost", "pid": 0}' > "$STATE_DIR/run.lock.retired-999999"
SWEEP_OUT="$(python3 "$GISTATE" --dir "$STATE_DIR" --run-id sweep-a --lock 2>&1)" && SWEEP_STATUS=0 || SWEEP_STATUS=$?
if [ "$SWEEP_STATUS" -eq 0 ] && printf '%s' "$SWEEP_OUT" | grep -q '"status": "acquired"'; then
  pass "T4: lock acquired over a stray retired lock"
else
  fail "T4: --lock failed over a stray retired lock: $SWEEP_OUT"
fi
if [ ! -e "$STATE_DIR/run.lock.retired-999999" ]; then
  pass "T4: orphaned run.lock.retired-* stray swept under _lock_guard"
else
  fail "T4: stray run.lock.retired-* survived a guarded --lock"
fi

python3 "$GISTATE" --dir "$STATE_DIR" --run-id sweep-a --unlock >/dev/null 2>&1 || true

printf '%s\n' '{"run_id": "ghost2", "pid": 0}' > "$STATE_DIR/run.lock.retired-888888"
python3 "$GISTATE" --dir "$STATE_DIR" --run-id sweep-b --lock --dry-run >/dev/null 2>&1 || true
if [ -e "$STATE_DIR/run.lock.retired-888888" ]; then
  pass "T4: --dry-run leaves the stray in place (no mutation without the guard)"
else
  fail "T4: --dry-run mutated state by sweeping the stray"
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
if [ "$FAIL" -eq 0 ]; then
  echo "✓ $PASS checks passed"
  exit 0
fi
echo "✗ $FAIL of $((PASS + FAIL)) checks failed"
exit 1
