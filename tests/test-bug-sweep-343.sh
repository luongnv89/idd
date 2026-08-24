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

ATOMIC_STATUS=0
python3 - "$GIISSUE" "$CACHE" <<'EOF' || ATOMIC_STATUS=$?
import importlib.util
import json
import os
import sys
import threading
from pathlib import Path

spec = importlib.util.spec_from_file_location("gi_issue", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
cache_dir = Path(sys.argv[2])
target = cache_dir / "observed.json"
target.write_text('{"writer":"old"}', encoding="utf-8")

# Force two writers to overlap. With the old shared `.tmp` path, writer B's
# descriptor follows writer A's rename onto the live cache and corrupts what a
# reader sees. Unique mkstemp files keep B's partial write private.
original_dump = m.json.dump
b_open = threading.Event()
a_done = threading.Event()
b_partial = threading.Event()
reader_checked = threading.Event()
thread_errors = []

def controlled_dump(payload, handle):
    if payload["writer"] == "A":
        if not b_open.wait(2):
            raise RuntimeError("writer B did not open")
        handle.write('{"writer":"A"}')
        return
    b_open.set()
    if not a_done.wait(2):
        raise RuntimeError("writer A did not publish")
    handle.write("X")
    handle.flush()
    b_partial.set()
    if not reader_checked.wait(2):
        raise RuntimeError("reader did not inspect partial write")
    handle.seek(0)
    handle.truncate()
    handle.write('{"writer":"B"}')

def write_a():
    try:
        m.write_cache(target, {"writer": "A"})
    except BaseException as exc:
        thread_errors.append(exc)
    finally:
        a_done.set()

def write_b():
    try:
        m.write_cache(target, {"writer": "B"})
    except BaseException as exc:
        thread_errors.append(exc)

m.json.dump = controlled_dump
a = threading.Thread(target=write_a)
b = threading.Thread(target=write_b)
a.start()
b.start()
if not b_partial.wait(3):
    thread_errors.append(RuntimeError("writer B never reached partial write"))
try:
    visible = json.loads(target.read_text(encoding="utf-8"))
    visible_valid = visible.get("writer") == "A"
except (OSError, ValueError):
    visible_valid = False
reader_checked.set()
a.join(3)
b.join(3)
m.json.dump = original_dump

# A failed publish is best-effort: preserve the old cache and remove the temp.
target.write_text('{"writer":"stable"}', encoding="utf-8")
original_replace = m.os.replace
m.os.replace = lambda *_args: (_ for _ in ()).throw(OSError("forced replace failure"))
m.write_cache(target, {"writer": "new"})
m.os.replace = original_replace
preserved = json.loads(target.read_text(encoding="utf-8")) == {"writer": "stable"}
no_strays = not list(cache_dir.glob(f".{target.name}.*.tmp"))

# If fdopen itself fails, write_cache must close the raw mkstemp descriptor.
original_mkstemp = m.tempfile.mkstemp
original_fdopen = m.os.fdopen
captured = []
def capture_mkstemp(*args, **kwargs):
    fd, name = original_mkstemp(*args, **kwargs)
    captured.append((fd, name))
    return fd, name
m.tempfile.mkstemp = capture_mkstemp
m.os.fdopen = lambda *_args, **_kwargs: (_ for _ in ()).throw(OSError("forced fdopen failure"))
m.write_cache(cache_dir / "fdopen.json", {"writer": "new"})
m.tempfile.mkstemp = original_mkstemp
m.os.fdopen = original_fdopen
fd_closed = bool(captured)
for fd, name in captured:
    try:
        os.fstat(fd)
    except OSError:
        pass
    else:
        fd_closed = False
    if Path(name).exists():
        fd_closed = False

ok = visible_valid and not thread_errors and preserved and no_strays and fd_closed
sys.exit(0 if ok else 1)
EOF
if [ "$ATOMIC_STATUS" -eq 0 ]; then
  pass "T1: readers see only complete JSON; failed writes preserve cache and clean resources"
else
  fail "T1: atomic visibility or failure cleanup regression"
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

BIN_STDIN_ERR="$(printf '\xff' | python3 "$LINT" issue - 2>&1 >/dev/null)" && BIN_STDIN_STATUS=0 || BIN_STDIN_STATUS=$?
if [ "$BIN_STDIN_STATUS" -eq 2 ] && printf '%s' "$BIN_STDIN_ERR" | grep -q "cannot read input"; then
  pass "T2: non-UTF-8 stdin → exit 2 with an error message"
else
  fail "T2: non-UTF-8 stdin → exit $BIN_STDIN_STATUS (want 2), stderr: $BIN_STDIN_ERR"
fi
if printf '%s' "$BIN_STDIN_ERR" | grep -q "Traceback"; then
  fail "T2: non-UTF-8 stdin still prints a traceback"
else
  pass "T2: non-UTF-8 stdin produces no traceback"
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
printf '%s\n' 'keep' > "$STATE_DIR/run.lock.retiredness-123"

# Hold the stable-directory flock while --lock starts. The retired stray must
# remain until the guard is released; deleting it early would prove the sweep
# ran outside _lock_guard.
READY="$TMP/guard-ready"
python3 - "$STATE_DIR" "$READY" <<'EOF' &
import fcntl
import os
import sys
import time
from pathlib import Path

fd = os.open(sys.argv[1], os.O_RDONLY)
fcntl.flock(fd, fcntl.LOCK_EX)
Path(sys.argv[2]).write_text("ready", encoding="utf-8")
time.sleep(0.8)
fcntl.flock(fd, fcntl.LOCK_UN)
os.close(fd)
EOF
GUARD_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -e "$READY" ] && break
  sleep 0.05
done
SWEEP_FILE="$TMP/sweep-out"
python3 "$GISTATE" --dir "$STATE_DIR" --run-id sweep-a --lock >"$SWEEP_FILE" 2>&1 &
SWEEP_PID=$!
sleep 0.15
if [ -e "$STATE_DIR/run.lock.retired-999999" ]; then
  pass "T4: retired-lock sweep waits for _lock_guard"
else
  fail "T4: retired-lock sweep ran before acquiring _lock_guard"
fi
wait "$GUARD_PID"
wait "$SWEEP_PID" && SWEEP_STATUS=0 || SWEEP_STATUS=$?
SWEEP_OUT="$(cat "$SWEEP_FILE")"
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
if [ -e "$STATE_DIR/run.lock.retiredness-123" ]; then
  pass "T4: similarly named non-retired file is preserved"
else
  fail "T4: sweep removed a similarly named unrelated file"
fi

printf '%s\n' '{"run_id": "ghost-unlock", "pid": 0}' > "$STATE_DIR/run.lock.retired-777777"
UNLOCK_OUT="$(python3 "$GISTATE" --dir "$STATE_DIR" --run-id sweep-a --unlock 2>&1)" && UNLOCK_STATUS=0 || UNLOCK_STATUS=$?
if [ "$UNLOCK_STATUS" -eq 0 ] && printf '%s' "$UNLOCK_OUT" | grep -q '"status": "released"' \
   && [ ! -e "$STATE_DIR/run.lock.retired-777777" ]; then
  pass "T4: guarded --unlock also sweeps retired strays"
else
  fail "T4: --unlock did not release and sweep: $UNLOCK_OUT"
fi

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
