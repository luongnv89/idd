#!/usr/bin/env bash
# test-autopilot-state-257.sh — Issue #257 acceptance checks for resumable
# /auto-pilot run state, the run lock, and the persisted run report.
#
# Acceptance criteria covered:
#   AC1  An interrupted run resumes at the recorded phase and reuses the
#        existing branch/PR instead of restarting the issue.
#   AC2  No issue is closed while its PR is unreviewed and unmerged.
#   AC3  A second concurrent run detects the lock and refuses to start.
#   AC4  The final run report is persisted to a file; a dry run leaves no
#        state mutation.
#
# The behavioral half runs src/shared/scripts/gi-state.py directly in a temp
# directory — the build already asserts the shipped copies are byte-identical,
# so testing one file proves both and keeps this suite independent of build
# order. The wiring half reads the *built* skills, because what ships is what
# runs.
#
# Usage: bash tests/test-autopilot-state-257.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_SCRIPTS="$REPO_ROOT/src/shared/scripts"
SKILLS="$REPO_ROOT/skills"
STATE="$SRC_SCRIPTS/gi-state.py"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Run a command, capturing stdout and the exit status without tripping `set -e`.
run_status() {
  local __out_var="$1"; shift
  local __status_var="$1"; shift
  local __out __status=0
  __out="$("$@" 2>/dev/null)" || __status=$?
  printf -v "$__out_var" '%s' "$__out"
  printf -v "$__status_var" '%s' "$__status"
}

# Read one key (dotted path supported) out of a JSON object on stdin.
jkey() {
  python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
for part in sys.argv[1].split("."):
    d = d[int(part)] if part.isdigit() else d[part]
print(d)
' "$1"
}

expect_grep() {
  local label="$1" pattern="$2" file="$3"
  if grep -q -- "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label"
  fi
}

# A fresh .gitissue-style directory, echoed so callers can `--dir` into it.
new_dir() {
  local d="$TMP/$1"
  mkdir -p "$d"
  printf '%s' "$d"
}

echo "◆ Auto-Pilot Run State, Lock and Report (issue #257)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T0: the script exists, is executable, stdlib-only, --help exits 0
# ───────────────────────────────────────────────────────────
if [ ! -f "$STATE" ]; then
  fail "T0: gi-state.py exists"
  echo "  ✗ cannot continue without the script"
  exit 1
fi
pass "T0: gi-state.py exists"

# Git records only the exec bit, and checkout applies the umask, so assert the
# bit rather than an absolute mode.
if python3 -c 'import os,sys;sys.exit(0 if os.stat(sys.argv[1]).st_mode & 0o111 else 1)' "$STATE"; then
  pass "T0: gi-state.py is executable"
else
  fail "T0: gi-state.py is executable"
fi
if python3 "$STATE" --help >/dev/null 2>&1; then
  pass "T0: gi-state.py --help exits 0"
else
  fail "T0: gi-state.py --help exits 0"
fi
expect_grep "T0: --lock --resume re-acquire names the host in the module docstring" \
  "same known owner pid, same" "$STATE"
expect_grep "T0: ownerless+unparseable-timestamp locks are retired by --force only" \
  "With no readable timestamp" "$STATE"
if grep -qE '^(import|from) (yaml|requests|jinja2|numpy|pydantic)\b' "$STATE"; then
  fail "T0: gi-state.py imports a third-party package"
else
  pass "T0: gi-state.py is stdlib-only"
fi
while IFS= read -r line; do
  mode="${line%% *}"
  file="${line##*	}"
  case "$file" in
    *gi-state.py)
      if [ "$mode" = "100755" ]; then
        pass "T0: gi-state.py is committed 0755"
      else
        fail "T0: gi-state.py is committed $mode, expected 100755"
      fi
      ;;
  esac
done < <(cd "$REPO_ROOT" && git ls-files -s src/shared/scripts/)

# The exit-code vocabulary must be stated where a reader of the script sees it,
# including the deliberate absence of a verdict code 1.
if head -60 "$STATE" | grep -q "no verdict exit code 1\|no.*verdict exit code 1"; then
  pass "T0: the docstring states there is no verdict exit code 1"
else
  fail "T0: the docstring does not rule out a verdict exit code 1"
fi
if head -60 "$STATE" | grep -q "stdin"; then
  pass "T0: the docstring documents that untrusted input arrives on stdin"
else
  fail "T0: the docstring does not say where untrusted input comes from"
fi
# No flag may tempt a caller to put an issue title on a command line.
if grep -qE '^\s*(parser\.add_argument\(\s*)?"--(title|body|issue-title|markdown|items|text)"' "$STATE"; then
  fail "T0: gi-state.py offers a text-carrying flag — issue text would reach a shell"
else
  pass "T0: gi-state.py has no flag that would carry issue text on a command line"
fi

# ───────────────────────────────────────────────────────────
# T1 (AC1): init → read round-trip, and the checkpoint merge
# ───────────────────────────────────────────────────────────
D1="$(new_dir d1)"
INIT='{"run_id":"r257","mode":"balanced","invocation":"/auto-pilot","queue":[42,45],"limit":10}'

run_status out st bash -c "printf '%s' '$INIT' | python3 '$STATE' --init --dir '$D1'"
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey run_id)" = "r257" ] \
   && [ -f "$D1/run-state.json" ]; then
  pass "AC1: --init writes run-state.json and prints the normalized state"
else
  fail "AC1: --init did not write the state (exit $st)"
fi

run_status out st python3 "$STATE" --read --dir "$D1"
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey phase)" = "init" ]; then
  pass "AC1: --read round-trips the state it just wrote"
else
  fail "AC1: --read does not round-trip (exit $st)"
fi

# Absence is an answer, not an error — the resume gate reads it as "fresh run".
EMPTY="$(new_dir d-empty)"
run_status out st python3 "$STATE" --read --dir "$EMPTY"
if [ "$st" = "0" ] && [ "$out" = "{}" ]; then
  pass "AC1: --read on a missing state exits 0 with {} (absent, not an error)"
else
  fail "AC1: --read on a missing state exits 0 with {} (got exit $st, $out)"
fi

# Corruption is an answer too, for the same reason: the gate falls to `stale`
# and starts fresh. Making it a stop would strand a run that did nothing wrong.
CORRUPT="$(new_dir d-corrupt)"
printf 'not json at all\n' > "$CORRUPT/run-state.json"
run_status out st python3 "$STATE" --read --dir "$CORRUPT"
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey corrupt)" = "True" ]; then
  pass "AC1: --read on a corrupt state exits 0 and reports corrupt"
else
  fail "AC1: --read on a corrupt state exits 0 with corrupt:true (got exit $st)"
fi

# The post-resolve checkpoint: branch + PR recorded, which is what a resume
# re-enters on instead of re-resolving the issue.
CHK='{"phase":"review","current":{"issue":42,"title":"Apply auth middleware","branch":"fix/42-auth","pr":87,"phase":"review"}}'
run_status out st bash -c "printf '%s' '$CHK' | python3 '$STATE' --update --dir '$D1'"
if [ "$st" = "0" ] \
   && [ "$(printf '%s' "$out" | jkey phase)" = "review" ] \
   && [ "$(printf '%s' "$out" | jkey current.branch)" = "fix/42-auth" ] \
   && [ "$(printf '%s' "$out" | jkey current.pr)" = "87" ]; then
  pass "AC1: a checkpoint records the phase, the branch and the PR"
else
  fail "AC1: the post-resolve checkpoint did not record branch/PR (exit $st)"
fi

# current merges key-by-key: a later checkpoint that names only the phase must
# not erase the branch and PR a resume needs.
run_status out st bash -c "printf '%s' '{\"phase\":\"merge\",\"current\":{\"phase\":\"merge\"}}' | python3 '$STATE' --update --dir '$D1'"
if [ "$(printf '%s' "$out" | jkey current.pr)" = "87" ] \
   && [ "$(printf '%s' "$out" | jkey current.phase)" = "merge" ]; then
  pass "AC1: current merges key-by-key — a phase-only patch keeps branch/PR"
else
  fail "AC1: a phase-only patch dropped the recorded branch/PR"
fi

# processed[] and skip_list[] append de-duplicated, and an explicit null clears
# current — the end-of-iteration checkpoint.
END='{"phase":"triage","current":null,"processed":[{"issue":42,"outcome":"merged","pr":87}],"skip_list":[45]}'
run_status out st bash -c "printf '%s' '$END' | python3 '$STATE' --update --dir '$D1'"
run_status out st bash -c "printf '%s' '$END' | python3 '$STATE' --update --dir '$D1'"
if [ "$(printf '%s' "$out" | jkey current)" = "None" ] \
   && [ "$(printf '%s' "$out" | jkey 'processed.0.outcome')" = "merged" ] \
   && [ "$(printf '%s' "$out" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(len(d["processed"]),len(d["skip_list"]))')" = "1 1" ]; then
  pass "AC1: processed/skip_list append de-duplicated and null clears current"
else
  fail "AC1: the end-of-iteration checkpoint duplicated entries or kept current"
fi

# `queue` is recorded intent at --init. An --update patch that names it used
# to rewrite the run's original scope; the two-lists invariant forbids that.
run_status out st bash -c "printf '%s' '{\"queue\":[99]}' | python3 '$STATE' --update --dir '$D1'"
if [ "$st" = "3" ]; then
  pass "AC1: --update refuses a queue patch (recorded intent is --init only)"
else
  fail "AC1: --update accepted a queue patch (exit $st)"
fi
run_status out st python3 "$STATE" --read --dir "$D1"
if [ "$(printf '%s' "$out" | python3 -c 'import json,sys;print(json.load(sys.stdin)["queue"])')" = "[42, 45]" ]; then
  pass "AC1: a refused queue patch left the --init queue untouched"
else
  fail "AC1: the --init queue was rewritten despite the refused patch"
fi

# Atomicity: no temp file survives a checkpoint, and the file always parses.
leftovers="$(find "$D1" -name '*.tmp' | wc -l | tr -d ' ')"
if [ "$leftovers" = "0" ] && python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$D1/run-state.json"; then
  pass "AC1: the state write is atomic — no temp file survives, the file parses"
else
  fail "AC1: a checkpoint left $leftovers temp file(s) behind"
fi

# A checkpoint heartbeat must be authorized by the durable owner pid, not just
# by a matching run id. This is sequential coverage of the flock-serialized
# update path, not a raw-writer race test.
D1HB="$(new_dir d1-heartbeat)"
printf '%s' '{"run_id":"runHeartbeat"}' | python3 "$STATE" --init --dir "$D1HB" >/dev/null
write_heartbeat_lock() {
  python3 - "$1" <<'PY'
import json, socket, sys
json.dump({
    "run_id": "runHeartbeat",
    "pid": 4242,
    "host": socket.gethostname(),
    "started_at": "2000-01-01T00:00:00Z",
    "heartbeat": "2000-01-01T00:00:00Z",
}, open(sys.argv[1], "w", encoding="utf-8"))
PY
}
write_heartbeat_lock "$D1HB/run.lock"
heartbeat_before="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["heartbeat"])' "$D1HB/run.lock")"
run_status out st bash -c "printf '%s' '{\"phase\":\"checkpoint\"}' | python3 '$STATE' --update --dir '$D1HB'"
heartbeat_after="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["heartbeat"])' "$D1HB/run.lock")"
if [ "$st" = "0" ] && [ "$heartbeat_after" = "$heartbeat_before" ]; then
  pass "AC3: update without --pid does not refresh a same-run-id foreign lock"
else
  fail "AC3: update without --pid refreshed a foreign lock (exit $st)"
fi
write_heartbeat_lock "$D1HB/run.lock"
heartbeat_before="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["heartbeat"])' "$D1HB/run.lock")"
run_status out st bash -c "printf '%s' '{\"phase\":\"checkpoint\"}' | python3 '$STATE' --update --dir '$D1HB' --pid 4243"
heartbeat_after="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["heartbeat"])' "$D1HB/run.lock")"
if [ "$st" = "0" ] && [ "$heartbeat_after" = "$heartbeat_before" ]; then
  pass "AC3: update with a different pid does not refresh a same-run-id foreign lock"
else
  fail "AC3: update with a different pid refreshed a foreign lock (exit $st)"
fi
write_heartbeat_lock "$D1HB/run.lock"
heartbeat_before="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["heartbeat"])' "$D1HB/run.lock")"
run_status out st bash -c "printf '%s' '{\"phase\":\"checkpoint\"}' | python3 '$STATE' --update --dir '$D1HB' --pid 4242"
heartbeat_after="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["heartbeat"])' "$D1HB/run.lock")"
if [ "$st" = "0" ] && [ "$heartbeat_after" != "$heartbeat_before" ]; then
  pass "AC3: update with the correct owner pid refreshes the lock heartbeat"
else
  fail "AC3: update with the correct owner pid did not refresh the lock (exit $st)"
fi

# Issue #260 extends the same atomic state with durable resolver lanes. Entries
# merge by issue so one returning worker cannot erase a still-active sibling.
LANES='{"phase":"resolve","lanes":[{"issue":50,"branch":"feat/50-a","phase":"resolve"},{"issue":51,"branch":"fix/51-b","phase":"planned"}]}'
run_status out st bash -c "printf '%s' '$LANES' | python3 '$STATE' --update --dir '$D1'"
run_status out st bash -c "printf '%s' '{\"lanes\":[{\"issue\":50,\"pr\":90,\"phase\":\"returned\",\"telemetry\":{\"status\":\"success\"}}]}' | python3 '$STATE' --update --dir '$D1'"
if [ "$st" = "0" ] \
   && [ "$(printf '%s' "$out" | jkey lanes.0.phase)" = "returned" ] \
   && [ "$(printf '%s' "$out" | jkey lanes.1.phase)" = "planned" ]; then
  pass "AC1 (#260): a returned lane merges without erasing its sibling"
else
  fail "AC1 (#260): durable lane merge lost or corrupted a sibling (exit $st)"
fi
run_status out st bash -c "printf '%s' '{\"lanes\":[]}' | python3 '$STATE' --update --dir '$D1'"
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)["lanes"]))')" = "0" ]; then
  pass "AC1 (#260): an empty lanes patch clears a fully drained batch"
else
  fail "AC1 (#260): a completed lane batch could not be cleared"
fi

# ───────────────────────────────────────────────────────────
# T2 (AC3): the run lock refuses a live holder, reclaims a stale one
# ───────────────────────────────────────────────────────────
# `--pid $$` records this shell, which is alive for the whole test — the stand-in
# for a run that is genuinely still going.
D2="$(new_dir d2)"
run_status out st python3 "$STATE" --lock --dir "$D2" --run-id runA --pid $$
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey status)" = "acquired" ] \
   && [ -f "$D2/run.lock" ]; then
  pass "AC3: --lock creates .gitissue/run.lock"
else
  fail "AC3: --lock did not create the lock (exit $st)"
fi

run_status out st python3 "$STATE" --lock --dir "$D2" --run-id runB --pid $$
if [ "$st" = "3" ] && [ "$(printf '%s' "$out" | jkey status)" = "held" ]; then
  pass "AC3: a second concurrent run exits 3 and refuses to start"
else
  fail "AC3: a second --lock while held must exit 3 (got $st)"
fi

# Exit 3, never 1: a verdict code would invert at every call site that reads a
# non-zero exit as "degrade to prose".
if [ "$st" != "1" ]; then
  pass "AC3: a held lock is exit 3 (a stop), never a verdict exit 1"
else
  fail "AC3: a held lock returned the reserved verdict code 1"
fi

# The refusal must name the holder, or the user cannot act on it.
if [ "$(printf '%s' "$out" | jkey holder.run_id)" = "runA" ] \
   && [ "$(printf '%s' "$out" | jkey holder.host)" != "" ]; then
  pass "AC3: the refusal reports the holder's run_id, pid and host"
else
  fail "AC3: the refusal does not identify the holder"
fi

# A lock past its TTL is stale and is reclaimed, so a crashed run never blocks
# the next one forever.
run_status out st python3 "$STATE" --lock --dir "$D2" --run-id runB --pid $$ --ttl 0
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey status)" = "reclaimed" ] \
   && [ "$(printf '%s' "$out" | jkey stale_reason)" = "ttl" ]; then
  pass "AC3: a lock older than --ttl is reported stale and reclaimed"
else
  fail "AC3: an aged lock was not reclaimed (exit $st)"
fi

# A lock whose recorded pid is gone on this host is stale too — the crash case.
D3="$(new_dir d3)"
DEAD_PID="$(python3 -c '
import os, subprocess, sys
p = subprocess.Popen([sys.executable, "-c", "pass"])
p.wait()
print(p.pid)
')"
python3 "$STATE" --lock --dir "$D3" --run-id runC --pid "$DEAD_PID" >/dev/null
run_status out st python3 "$STATE" --lock --dir "$D3" --run-id runD --pid $$
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey stale_reason)" = "dead-pid" ]; then
  pass "AC3: a lock whose pid is gone on this host is stale (the crash case)"
else
  fail "AC3: a dead-pid lock was not reclaimed (exit $st)"
fi

# Regression: the lock must NOT retire itself on the shell that took it. Every
# documented invocation is a one-shot command whose shell exits the instant it
# returns, so a --pid defaulting to the invoking process would leave a lock
# whose owner is already gone — read as dead-pid, silently reclaimed, and AC3
# defeated for every real run. `--pid` is therefore omitted here exactly as the
# fallback prose allows, and the taking shell is gone before the second call.
#
# The trailing `; exit 0` on the *taking* call is load-bearing: `bash -c "one
# command"` execs into that command, so python's parent would be this long-lived
# test shell and the throwaway wrapper this case is built on would never exist.
# A second command forces bash to fork, so the recorded pid really does die. The
# calls that are asserted on run unwrapped — `exit 0` would mask their status.
D3B="$(new_dir d3b)"
bash -c "python3 '$STATE' --lock --dir '$D3B' --run-id runOwnerless >/dev/null; exit 0"
if [ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["pid"])' "$D3B/run.lock")" = "0" ]; then
  pass "AC3: the documented --lock records pid 0 — no owner, so no liveness signal"
else
  fail "AC3: --lock recorded an owner pid nobody passed"
fi
run_status out st python3 "$STATE" --lock --dir "$D3B" --run-id runNext
if [ "$st" = "3" ] && [ "$(printf '%s' "$out" | jkey status)" = "held" ] \
   && [ "$(printf '%s' "$out" | jkey stale)" = "False" ]; then
  pass "AC3: a lock taken with no --pid is held, not self-reclaimed, once its shell exits"
else
  fail "AC3: an ownerless lock was reclaimed by the next run (exit $st)"
fi

# The refusal is on stderr with the ✗ vocabulary, and reports the owner as
# unknown rather than as the meaningless pid 0.
held_err="$(python3 "$STATE" --lock --dir "$D3B" --run-id runNext2 2>&1 >/dev/null || true)"
case "$held_err" in
  "✗ gi-state: the run lock is held by run runOwnerless (pid unknown on "*)
    pass "AC3: the ownerless refusal prints the ✗ held line naming the holder" ;;
  *)
    fail "AC3: the ownerless refusal printed '$held_err'" ;;
esac

# Unknown liveness is not immortality: the TTL still retires an ownerless lock,
# so a crashed run that could not name an owner clears on its own.
run_status out st python3 "$STATE" --lock --dir "$D3B" --run-id runTtl --ttl 0
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey status)" = "reclaimed" ] \
   && [ "$(printf '%s' "$out" | jkey stale_reason)" = "ttl" ]; then
  pass "AC3: an ownerless lock past --ttl is still retired (never immortal)"
else
  fail "AC3: an ownerless lock survived its TTL (exit $st)"
fi

# A resumed run must be able to take back its OWN live lock. The common
# interruption is the loop dying inside an agent process that is still alive, so
# the recorded owner pid is the pid the resume passes: refusing that would let
# the lock lock its own run out. Exclusivity is preserved by matching BOTH
# halves — the run id and a known owner pid.
D3C="$(new_dir d3c)"
python3 "$STATE" --lock --dir "$D3C" --run-id runOwner --pid $$ >/dev/null
run_status out st python3 "$STATE" --lock --resume --dir "$D3C" --run-id runOwner --pid $$
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey status)" = "reacquired" ] \
   && [ "$(printf '%s' "$out" | jkey lock.run_id)" = "runOwner" ]; then
  pass "AC3: --resume re-acquires its own live lock and keeps the recorded run id"
else
  fail "AC3: --resume was refused its own live lock (exit $st)"
fi

# The same re-acquire with NO state file: the run died before --init ever wrote
# one, so there is no recorded id to adopt. The lock this process owns supplies
# it — minting a fresh id here would orphan the very lock the run is holding and
# leave the closing --unlock refusing it.
D3D="$(new_dir d3d)"
own_id="$(python3 "$STATE" --lock --dir "$D3D" --pid $$ | jkey lock.run_id)"
run_status out st python3 "$STATE" --lock --resume --dir "$D3D" --pid $$
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey status)" = "reacquired" ] \
   && [ "$(printf '%s' "$out" | jkey lock.run_id)" = "$own_id" ]; then
  pass "AC3: --resume with no recorded state adopts the id of the lock it owns"
else
  fail "AC3: --resume minted a second id over the lock it already held (exit $st)"
fi

# A different live process resuming the same recorded run is still a second run.
run_status out st python3 "$STATE" --lock --resume --dir "$D3C" --run-id runOwner --pid 1
if [ "$st" = "3" ] && [ "$(printf '%s' "$out" | jkey status)" = "held" ]; then
  pass "AC3: --resume from a different owner pid is still refused (exit 3)"
else
  fail "AC3: --resume re-acquired a lock owned by another process (exit $st)"
fi

# Ownership is scoped to one host. A pid only means something on the machine
# that recorded it and two machines hand out the same numbers, so a foreign-host
# lock whose pid and run id both match must still be refused — otherwise
# --resume would be *weaker* than a plain --lock, which already refuses it, and
# a pid collision would hand one lock to two runs. `--force` stays the escape.
write_lock() {  # dir, run_id (JSON), pid, host — a hand-built lock, timestamped now
  python3 -c '
import json, sys, datetime
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
json.dump(
    {"run_id": json.loads(sys.argv[2]), "pid": int(sys.argv[3]), "host": sys.argv[4],
     "started_at": now, "heartbeat": now},
    open(sys.argv[1] + "/run.lock", "w"),
)
' "$@"
}
D3E="$(new_dir d3e)"
write_lock "$D3E" '"20260810T090000Z-1"' $$ "not-this-host"
run_status out st python3 "$STATE" --lock --resume --dir "$D3E" --run-id 20260810T090000Z-1 --pid $$
if [ "$st" = "3" ] && [ "$(printf '%s' "$out" | jkey status)" = "held" ]; then
  pass "AC3: --resume refuses a foreign-host lock even when pid and run id match"
else
  fail "AC3: --resume re-acquired a lock recorded on another host (exit $st)"
fi

# A lock file is still input. A non-string run_id reaching RUN_ID_RE is a
# TypeError, and an uncaught one exits 1 — the code this script reserves for a
# verdict, so every call site would read the crash as an answer. It must be
# screened like every other disk-sourced id and fall through to a documented
# exit instead.
D3F="$(new_dir d3f)"
write_lock "$D3F" '42' $$ "$(python3 -c 'import socket;print(socket.gethostname())')"
run_status out st python3 "$STATE" --lock --resume --dir "$D3F" --pid $$
if { [ "$st" = "0" ] || [ "$st" = "3" ]; } && [ "$st" != "1" ]; then
  pass "AC3: a lock with a non-string run_id exits 0/3, never the reserved code 1"
else
  fail "AC3: a malformed lock run_id crashed the script (exit $st)"
fi

# A lock file that is literal JSON `null` is valid JSON and used to parse as
# "file absent" (`(None, None)`), which wedged the lock: `--lock` and
# `--lock --force` both exited 3 (exclusive create found the file), and
# `--unlock --force` reported absent and left it. It is corrupt, not absent.
D3N="$(new_dir d3n)"
printf 'null\n' > "$D3N/run.lock"
run_status out st python3 "$STATE" --lock --dir "$D3N" --run-id runNull --pid $$
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey status)" = "reclaimed" ] \
   && [ "$(printf '%s' "$out" | jkey stale_reason)" = "corrupt" ] \
   && [ -f "$D3N/run.lock" ]; then
  pass "AC3: a JSON-null lock is reclaimed as corrupt, not treated as absent"
else
  fail "AC3: a JSON-null lock was not reclaimed (exit $st)"
fi
D3NF="$(new_dir d3nf)"
printf 'null\n' > "$D3NF/run.lock"
run_status out st python3 "$STATE" --lock --dir "$D3NF" --run-id runNullF --pid $$ --force
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey status)" = "reclaimed" ]; then
  pass "AC3: --lock --force reclaims a JSON-null lock"
else
  fail "AC3: --lock --force left a JSON-null lock in place (exit $st)"
fi
D3NU="$(new_dir d3nu)"
printf 'null\n' > "$D3NU/run.lock"
run_status out st python3 "$STATE" --unlock --dir "$D3NU" --force
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey status)" = "released" ] \
   && [ ! -f "$D3NU/run.lock" ]; then
  pass "AC3: --unlock --force releases a JSON-null lock rather than reporting absent"
else
  fail "AC3: --unlock --force did not remove a JSON-null lock (exit $st)"
fi

# An ownerless lock with no readable timestamp cannot be aged, so TTL cannot
# retire it — only --force can. The prose used to claim "TTL or --force".
D3TS="$(new_dir d3ts)"
python3 -c '
import json, socket, sys
json.dump(
    {"run_id": "runNoTs", "pid": 0, "host": socket.gethostname(),
     "started_at": "not-a-timestamp", "heartbeat": "also-bad"},
    open(sys.argv[1], "w"),
)
' "$D3TS/run.lock"
run_status out st python3 "$STATE" --lock --dir "$D3TS" --run-id runNoTsNext
if [ "$st" = "3" ] && [ "$(printf '%s' "$out" | jkey status)" = "held" ]; then
  pass "AC3: an ownerless lock with an unparsable timestamp is held (TTL cannot age it)"
else
  fail "AC3: an unageable ownerless lock was not held (exit $st)"
fi
run_status out st python3 "$STATE" --lock --dir "$D3TS" --run-id runNoTsForce --force --pid $$
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey status)" = "reclaimed" ]; then
  pass "AC3: --force retires an ownerless lock with an unparsable timestamp"
else
  fail "AC3: --force did not retire the unageable ownerless lock (exit $st)"
fi

# Re-acquire must re-check ownership after the heartbeat. A concurrent
# `--lock --force` in that window used to be reported as `reacquired`.
D3R="$(new_dir d3r)"
python3 "$STATE" --lock --dir "$D3R" --run-id runRace --pid $$ >/dev/null
run_status out st python3 - "$STATE" "$D3R" $$ <<'PY'
import json, os, socket, sys, importlib.util
from datetime import datetime, timezone
from pathlib import Path

spec = importlib.util.spec_from_file_location("gi_state", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

stolen = {
    "run_id": "runThief",
    "pid": os.getpid() + 99999,
    "host": socket.gethostname(),
    "started_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "heartbeat": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
orig = mod._touch_lock_heartbeat

def steal(lock_path, run_id, pid=None, _lock_held=False):
    orig(lock_path, run_id, pid=pid, _lock_held=_lock_held)
    Path(lock_path).write_text(json.dumps(stolen) + "\n", encoding="utf-8")

mod._touch_lock_heartbeat = steal
sys.argv = ["gi-state.py", "--lock", "--resume", "--dir", sys.argv[2],
            "--run-id", "runRace", "--pid", sys.argv[3]]
raise SystemExit(mod.main())
PY
if [ "$st" = "3" ] && [ "$(printf '%s' "$out" | jkey status)" = "held" ]; then
  pass "AC3: re-acquire reports held when the lock is stolen during the heartbeat"
else
  fail "AC3: a stolen lock during re-acquire was reported as success (exit $st)"
fi

# The heartbeat must also refuse a replacement that appears after its first
# ownership read but before the atomic publish. This models the exact stale
# heartbeat overwrite window independently of the post-heartbeat re-check.
D3S="$(new_dir d3s)"
python3 "$STATE" --lock --dir "$D3S" --run-id runRace --pid $$ >/dev/null
run_status out st python3 - "$STATE" "$D3S" $$ <<'PY'
import importlib.util
import json
import os
import socket
import sys
from datetime import datetime, timezone
from pathlib import Path

spec = importlib.util.spec_from_file_location("gi_state", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
stolen = {
    "run_id": "runThief",
    "pid": os.getpid() + 99999,
    "host": socket.gethostname(),
    "started_at": now,
    "heartbeat": now,
}
orig_read = mod._read_json_file
reads = 0

def replace_after_ownership_read(path):
    global reads
    result = orig_read(path)
    if path.name == "run.lock" and reads == 0:
        staged = path.with_name("replacement.lock")
        staged.write_text(json.dumps(stolen) + "\n", encoding="utf-8")
        os.replace(staged, path)
    reads += 1
    return result

mod._read_json_file = replace_after_ownership_read
mod._touch_lock_heartbeat(Path(sys.argv[2]) / "run.lock", "runRace", pid=int(sys.argv[3]))
actual = json.loads((Path(sys.argv[2]) / "run.lock").read_text(encoding="utf-8"))
if actual.get("run_id") != "runThief":
    raise SystemExit(f"stale heartbeat overwrote replacement: {actual}")
PY
if [ "$st" = "0" ]; then
  pass "AC3: heartbeat refuses a lock replacement between ownership read and publish"
else
  fail "AC3: heartbeat CAS regression test failed (exit $st, $out)"
fi

# Two ownerless locks must not answer to each other: pid 0 is "unknown", and
# unknown matching unknown would re-open the self-reclaim hole on the --resume
# path instead of the plain one.
run_status out st python3 "$STATE" --lock --resume --dir "$D3B" --run-id runTtl
if [ "$st" = "3" ] && [ "$(printf '%s' "$out" | jkey status)" = "held" ]; then
  pass "AC3: --resume never re-acquires an ownerless lock on a pid-0 match"
else
  fail "AC3: an ownerless lock was re-acquired by an unrelated resume (exit $st)"
fi

# The re-acquire is a mutation like any other, so --dry-run must not perform it.
lock_before="$(cat "$D3C/run.lock")"
run_status out st python3 "$STATE" --lock --resume --dir "$D3C" --run-id runOwner --pid $$ --dry-run
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey status)" = "would_reacquire" ] \
   && [ "$(printf '%s' "$out" | jkey dry_run)" = "True" ] \
   && [ "$(cat "$D3C/run.lock")" = "$lock_before" ]; then
  pass "AC4: --lock --resume --dry-run reports would_reacquire and writes nothing"
else
  fail "AC4: the dry-run re-acquire did not report would_reacquire (exit $st)"
fi

# --force is the --force-unlock path past a live-looking holder.
D4="$(new_dir d4)"
python3 "$STATE" --lock --dir "$D4" --run-id runE --pid $$ >/dev/null
run_status out st python3 "$STATE" --lock --dir "$D4" --run-id runF --pid $$ --force
[ "$st" = "0" ] && pass "AC3: --force reclaims a live-looking lock (--force-unlock)" \
                || fail "AC3: --force did not reclaim the lock (got $st)"

# --unlock releases only this run's lock unless --force.
D5="$(new_dir d5)"
python3 "$STATE" --lock --dir "$D5" --run-id runG --pid $$ >/dev/null
run_status out st python3 "$STATE" --unlock --dir "$D5" --run-id someone-else
if [ "$st" = "3" ] && [ -f "$D5/run.lock" ]; then
  pass "AC3: --unlock refuses a lock belonging to another run"
else
  fail "AC3: --unlock released another run's lock (exit $st)"
fi
run_status out st python3 "$STATE" --unlock --dir "$D5" --run-id runG
if [ "$st" = "0" ] && [ ! -f "$D5/run.lock" ]; then
  pass "AC3: --unlock releases this run's own lock"
else
  fail "AC3: --unlock did not release the lock (exit $st)"
fi
run_status out st python3 "$STATE" --unlock --dir "$D5" --run-id runG
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey status)" = "absent" ]; then
  pass "AC3: releasing an absent lock is exit 0, not an error"
else
  fail "AC3: releasing an absent lock is exit 0 (got $st)"
fi

# ───────────────────────────────────────────────────────────
# T2b (AC1/AC3): the documented run sequence is ONE run
# ───────────────────────────────────────────────────────────
# The three calls exactly as the skill documents them, with no --run-id
# anywhere: preflight.md's `--lock`, phases.md Step 1.0's `--init`, and the
# closing `--unlock` from SKILL.md's *Stop Conditions*. A `--init` that minted
# its own id would leave the final `--unlock` refusing a lock it does not
# recognise, and the lock file would outlive the run that took it — blocking
# the next run for a full TTL.
D9="$(new_dir d9)"
run_status out st python3 "$STATE" --lock --dir "$D9"
lock_id="$(printf '%s' "$out" | jkey lock.run_id)"
[ "$st" = "0" ] || fail "AC3: the documented --lock call failed (exit $st)"

SEQ_INIT='{"mode":"balanced","invocation":"/auto-pilot","queue":[42],"limit":10}'
run_status out st bash -c "printf '%s' '$SEQ_INIT' | python3 '$STATE' --init --dir '$D9'"
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey run_id)" = "$lock_id" ]; then
  pass "AC1: --init with no run_id adopts the run id of the lock this run holds"
else
  fail "AC1: --init minted a second run id — the documented sequence orphans the lock"
fi

run_status out st python3 "$STATE" --unlock --dir "$D9"
if [ "$st" = "0" ] && [ ! -f "$D9/run.lock" ]; then
  pass "AC3: lock → init → unlock exits 0 and removes .gitissue/run.lock"
else
  fail "AC3: the documented unlock exited $st and left the lock behind"
fi

# An explicit run_id in the payload still wins — adoption is a default, not an
# override.
D9B="$(new_dir d9b)"
python3 "$STATE" --lock --dir "$D9B" --run-id lock-run --pid $$ >/dev/null
run_status out st bash -c "printf '%s' '{\"run_id\":\"payload-run\"}' | python3 '$STATE' --init --dir '$D9B'"
if [ "$(printf '%s' "$out" | jkey run_id)" = "payload-run" ]; then
  pass "AC1: an explicit payload run_id still wins over the lock's"
else
  fail "AC1: --init overrode the run_id the payload supplied"
fi

# ───────────────────────────────────────────────────────────
# T2c (AC3): concurrent reclaim has exactly one winner
# ───────────────────────────────────────────────────────────
# Six runs classify one dead-pid lock as stale at the same instant. Reclaiming
# with a plain atomic write lets every one of them succeed — os.replace never
# refuses an existing file — and the mutual exclusion the lock exists for is
# gone. The winner writes a lock naming this live shell, so every loser that
# re-reads must see a live holder and stop with exit 3.
D11="$(new_dir d11)"
DEAD_PID2="$(python3 -c '
import subprocess, sys
p = subprocess.Popen([sys.executable, "-c", "pass"])
p.wait()
print(p.pid)
')"
python3 "$STATE" --lock --dir "$D11" --run-id stale-run --pid "$DEAD_PID2" >/dev/null
RACE="$TMP/race"
mkdir -p "$RACE"
for i in 1 2 3 4 5 6; do
  (
    racer_status=0
    python3 "$STATE" --lock --dir "$D11" --run-id "racer$i" --pid $$ \
      > "$RACE/$i.out" 2>/dev/null || racer_status=$?
    echo "$racer_status" > "$RACE/$i.st"
  ) &
done
wait
winners=0
zero_exits=0
losers=0
for i in 1 2 3 4 5 6; do
  # `reclaimed` and `acquired` are the same win: a racer whose read lands in the
  # instant between the winner's retire and its create sees no lock at all and
  # takes the ordinary fresh-lock path. What must never happen is two of them.
  if grep -qE '"status": "(reclaimed|acquired)"' "$RACE/$i.out"; then
    winners=$((winners + 1))
  fi
  case "$(cat "$RACE/$i.st")" in
    0) zero_exits=$((zero_exits + 1)) ;;
    3) losers=$((losers + 1)) ;;
  esac
done
if [ "$winners" = "1" ] && [ "$zero_exits" = "1" ] && [ "$losers" = "5" ]; then
  pass "AC3: concurrent reclaim of one stale lock has exactly one winner"
else
  fail "AC3: $winners run(s) reclaimed the same stale lock ($zero_exits exit-0, $losers exit-3)"
fi
if [ -f "$D11/run.lock" ] && [ "$(find "$D11" -name 'run.lock.retired-*' | wc -l | tr -d ' ')" = "0" ]; then
  pass "AC3: the contended reclaim leaves one lock and no retired leftovers"
else
  fail "AC3: the contended reclaim left the lock directory inconsistent"
fi

# ───────────────────────────────────────────────────────────
# T3 (AC4): the persisted report, and --dry-run writes nothing
# ───────────────────────────────────────────────────────────
D6="$(new_dir d6)"
printf '{"run_id":"r257"}' | python3 "$STATE" --init --dir "$D6" >/dev/null
REPORT='{"run_id":"r257","markdown":"◆ Auto-Pilot Summary\n  merged: 2\n"}'
run_status out st bash -c "printf '%s' '$REPORT' | python3 '$STATE' --report --dir '$D6'"
if [ "$st" = "0" ] && [ -f "$D6/last-run-report.md" ] \
   && printf '%s' "$out" | grep -q "last-run-report.md"; then
  pass "AC4: --report writes last-run-report.md and prints the path"
else
  fail "AC4: --report did not persist the run report (exit $st)"
fi
if grep -q "gitissue:run-report v1" "$D6/last-run-report.md" \
   && grep -q "r257" "$D6/last-run-report.md" \
   && grep -q "Auto-Pilot Summary" "$D6/last-run-report.md"; then
  pass "AC4: the report carries the run marker, the run id and the summary"
else
  fail "AC4: the persisted report is missing its marker or its body"
fi

# The whole point of routing every write through one script: --dry-run on every
# mutating mode validates, prints, and writes NOTHING.
D7="$(new_dir d7)"
run_status out st bash -c "printf '{\"run_id\":\"r257\"}' | python3 '$STATE' --init --dir '$D7' --dry-run"
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey dry_run)" = "True" ] \
   && [ ! -f "$D7/run-state.json" ]; then
  pass "AC4: --init --dry-run writes no state file"
else
  fail "AC4: --init --dry-run created a state file (exit $st)"
fi
run_status out st python3 "$STATE" --lock --dir "$D7" --run-id r257 --pid $$ --dry-run
if [ "$st" = "0" ] && [ ! -f "$D7/run.lock" ]; then
  pass "AC4: --lock --dry-run creates no lock"
else
  fail "AC4: --lock --dry-run created a lock file (exit $st)"
fi
D7_ABSENT="$TMP/dry-run-absent"
run_status out st python3 "$STATE" --lock --dir "$D7_ABSENT" --run-id r257 --dry-run
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey status)" = "would_acquire" ] \
   && [ ! -e "$D7_ABSENT" ]; then
  pass "AC4: --lock --dry-run does not create an absent lock directory"
else
  fail "AC4: --lock --dry-run created an absent lock directory (exit $st)"
fi
run_status out st python3 "$STATE" --unlock --dir "$D7_ABSENT" --run-id r257 --dry-run
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey status)" = "absent" ] \
   && [ ! -e "$D7_ABSENT" ]; then
  pass "AC4: --unlock --dry-run does not create an absent lock directory"
else
  fail "AC4: --unlock --dry-run created an absent lock directory (exit $st)"
fi
run_status out st bash -c "printf '%s' '$REPORT' | python3 '$STATE' --report --dir '$D7' --dry-run"
if [ "$st" = "0" ] && [ ! -f "$D7/last-run-report.md" ]; then
  pass "AC4: --report --dry-run writes no report"
else
  fail "AC4: --report --dry-run wrote the report (exit $st)"
fi

# --update --dry-run must leave the previous state byte-identical.
printf '{"run_id":"r257"}' | python3 "$STATE" --init --dir "$D7" >/dev/null
before="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$D7/run-state.json")"
run_status out st bash -c "printf '%s' '{\"phase\":\"merge\"}' | python3 '$STATE' --update --dir '$D7' --dry-run"
after="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$D7/run-state.json")"
if [ "$st" = "0" ] && [ "$before" = "$after" ]; then
  pass "AC4: --update --dry-run leaves the state byte-identical"
else
  fail "AC4: --update --dry-run mutated the state file"
fi
# And nothing at all was created in the directory beyond what --init wrote.
extra="$(cd "$D7" && ls | grep -cv '^run-state.json$' || true)"
[ "$extra" = "0" ] && pass "AC4: a dry run leaves no artifact behind at all" \
                   || fail "AC4: a dry run left $extra unexpected file(s)"

# --unlock is a mutating mode too: a dry run must not release a real lock.
D12="$(new_dir d12)"
python3 "$STATE" --lock --dir "$D12" --run-id r257 --pid $$ >/dev/null
run_status out st python3 "$STATE" --unlock --dir "$D12" --run-id r257 --dry-run
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey status)" = "would_release" ] \
   && [ -f "$D12/run.lock" ]; then
  pass "AC4: --unlock --dry-run reports the release and leaves the lock in place"
else
  fail "AC4: --unlock --dry-run released the lock (exit $st)"
fi

# A dry run reports who holds the lock — but a live holder is still a stop, or a
# dry run would be the documented way to pretend the lock is free.
run_status out st python3 "$STATE" --lock --dir "$D12" --run-id other --pid $$ --dry-run
if [ "$st" = "3" ] && [ "$(printf '%s' "$out" | jkey status)" = "held" ] \
   && [ "$(printf '%s' "$out" | jkey holder.run_id)" = "r257" ]; then
  pass "AC4: --lock --dry-run against a live holder still exits 3 and names it"
else
  fail "AC4: --lock --dry-run against a live holder must exit 3 (got $st)"
fi

# ───────────────────────────────────────────────────────────
# T4: the exit-code vocabulary — 2 usage, 3 invalid input, 4 degrade
# ───────────────────────────────────────────────────────────
D8="$(new_dir d8)"
printf '{"run_id":"r257"}' | python3 "$STATE" --init --dir "$D8" >/dev/null
run_status out st bash -c "printf 'not json' | python3 '$STATE' --update --dir '$D8'"
[ "$st" = "3" ] && pass "T4: malformed stdin exits 3" \
                || fail "T4: malformed stdin exits 3 (got $st)"
run_status out st bash -c "printf '{\"nope\":1}' | python3 '$STATE' --update --dir '$D8'"
[ "$st" = "3" ] && pass "T4: an unknown patch key exits 3" \
                || fail "T4: an unknown patch key exits 3 (got $st)"
run_status out st bash -c "printf '{\"current\":{\"issue\":\"not-an-int\"}}' | python3 '$STATE' --update --dir '$D8'"
[ "$st" = "3" ] && pass "T4: a wrongly-typed current.issue exits 3" \
                || fail "T4: a wrongly-typed current.issue exits 3 (got $st)"
run_status out st bash -c "printf '{\"markdown\":\"\"}' | python3 '$STATE' --report --dir '$D8'"
[ "$st" = "3" ] && pass "T4: an empty report markdown exits 3" \
                || fail "T4: an empty report markdown exits 3 (got $st)"
# generated_at is interpolated into the `<!-- gitissue:run-report v1 … -->`
# marker, so a value carrying `-->` would end the marker early: it is
# pattern-checked exactly like run_id, not passed through.
run_status out st bash -c "printf '%s' '{\"markdown\":\"x\",\"generated_at\":\"--> oops\"}' | python3 '$STATE' --report --dir '$D8'"
if [ "$st" = "3" ] && [ ! -f "$D8/last-run-report.md" ]; then
  pass "T4: a marker-breaking generated_at exits 3 and writes no report"
else
  fail "T4: an unvalidated generated_at reached the report marker (exit $st)"
fi
run_status out st bash -c "printf '{\"phase\":\"x\"}' | python3 '$STATE' --update --dir '$TMP/no-such-dir'"
[ "$st" = "3" ] && pass "T4: --update with no run state exits 3 (run --init first)" \
                || fail "T4: --update with no run state exits 3 (got $st)"
run_status out st python3 "$STATE" --dir "$D8"
[ "$st" = "2" ] && pass "T4: no mode exits 2 (usage)" \
                || fail "T4: no mode exits 2 (got $st)"
run_status out st bash -c "printf '{\"run_id\":\"r257\"}' | python3 '$STATE' --init --read --dir '$D8'"
[ "$st" = "2" ] && pass "T4: two modes exit 2 (usage)" \
                || fail "T4: two modes exit 2 (got $st)"
run_status out st python3 "$STATE" --lock --dir "$D8" --ttl -5
[ "$st" = "3" ] && pass "T4: a negative --ttl exits 3" \
                || fail "T4: a negative --ttl exits 3 (got $st)"
run_status out st bash -c "printf '{\"run_id\":\"r257\"}' | python3 '$STATE' --init --dir /proc/nonexistent/dir"
[ "$st" = "4" ] && pass "T4: an unwritable directory exits 4 (degrade to prose)" \
                || fail "T4: an unwritable directory exits 4 (got $st)"

# current.branch is the one recorded field a later step interpolates into a
# shell word (`gh pr list --head …` in the resume gate), and a branch name can
# come from a PR somebody else opened. Git and GitHub permit `$()`, backticks,
# `;`, `&&`, `|`, a leading `-`, whitespace and newlines in a ref, so every one
# of them must be refused at write time — exit 3, and nothing on disk changes.
D13="$(new_dir d13)"
printf '{"run_id":"r257"}' | python3 "$STATE" --init --dir "$D13" >/dev/null
branch_before="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$D13/run-state.json")"
inj_fail=0
# The payloads carry backticks and `$(…)`: they are read into a variable and
# piped, never spliced into a `bash -c` string, or the *test* would run them.
while IFS= read -r payload; do
  st=0
  printf '%s' "$payload" | python3 "$STATE" --update --dir "$D13" >/dev/null 2>&1 || st=$?
  [ "$st" = "3" ] || { inj_fail=$((inj_fail + 1)); echo "    (branch payload accepted: $payload → exit $st)"; }
done <<'PAYLOADS'
{"current":{"branch":"fix/1-x$(id)"}}
{"current":{"branch":"fix/1-x`id`"}}
{"current":{"branch":"fix/1-x;id"}}
{"current":{"branch":"fix/1-x&&id"}}
{"current":{"branch":"fix/1-x|id"}}
{"current":{"branch":"-fix/1-x"}}
{"current":{"branch":"fix/1-x\ny"}}
{"current":{"branch":"fix/1 -x"}}
{"current":{"branch":"fix/1-x>out"}}
PAYLOADS
branch_after="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$D13/run-state.json")"
if [ "$inj_fail" = "0" ] && [ "$branch_before" = "$branch_after" ]; then
  pass "B4: a shell-metacharacter current.branch exits 3 and writes nothing"
else
  fail "B4: $inj_fail injection payload(s) reached the run state"
fi
# …and a conventional branch still round-trips, or the gate would be useless.
run_status out st bash -c "printf '%s' '{\"current\":{\"issue\":7,\"branch\":\"fix/7-mobile-auth-redirect\",\"phase\":\"review\"}}' | python3 '$STATE' --update --dir '$D13'"
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey current.branch)" = "fix/7-mobile-auth-redirect" ]; then
  pass "B4: a docs/naming-conventions.md branch name still round-trips"
else
  fail "B4: a conventional branch name was refused (exit $st)"
fi

# `$` in Python also matches before a trailing newline, so the patterns must end
# in `\Z`: `fix/1-x\n` in a shell word is two words, not one.
if grep -q 'BRANCH_RE = re.compile' "$STATE" && ! grep -qE '^(RUN_ID|PHASE|BRANCH|TS)_RE = re\.compile\(r"\^.*\$"\)' "$STATE"; then
  pass "B4: the validation patterns are anchored with \\Z, not \$"
else
  fail "B4: a validation pattern still ends in \$ — a trailing newline slips through"
fi

# L1: the report marker's run_id fallback comes off disk, so it is pattern-
# checked like the submitted one. An unchecked `-->` ends the marker early and
# leaves the rest of the header as visible report text.
D14="$(new_dir d14)"
printf '{"run_id":"r257"}' | python3 "$STATE" --init --dir "$D14" >/dev/null
python3 - "$D14/run-state.json" <<'PY'
import json, sys
path = sys.argv[1]
state = json.load(open(path, encoding="utf-8"))
state["run_id"] = "x --> evil"
json.dump(state, open(path, "w", encoding="utf-8"))
PY
run_status out st bash -c "printf '%s' '{\"markdown\":\"body\"}' | python3 '$STATE' --report --dir '$D14'"
marker="$(head -1 "$D14/last-run-report.md" 2>/dev/null || true)"
if [ "$st" = "0" ] && ! printf '%s' "$marker" | grep -q 'evil'; then
  pass "L1: a marker-breaking run_id on disk never reaches the report marker"
else
  fail "L1: the state file's run_id broke the report marker ($marker)"
fi

# L2: two sequential, unrelated runs must not share a run id. Run 1 leaves its
# state file behind; run 2's plain --lock must mint a fresh id rather than
# inheriting it, or both runs' reports and telemetry carry the same name.
D15="$(new_dir d15)"
python3 "$STATE" --lock --dir "$D15" --pid $$ >/dev/null
printf '{}' | python3 "$STATE" --init --dir "$D15" >/dev/null
run1="$(python3 "$STATE" --read --dir "$D15" | jkey run_id)"
python3 "$STATE" --unlock --dir "$D15" >/dev/null
run_status out st python3 "$STATE" --lock --dir "$D15" --pid $$
run2="$(printf '%s' "$out" | jkey lock.run_id)"
if [ "$st" = "0" ] && [ -n "$run1" ] && [ "$run1" != "$run2" ]; then
  pass "L2: a plain --lock over a leftover state mints a fresh run id"
else
  fail "L2: the second run inherited run id $run1 from the finished run's state"
fi
# …and the resume path still adopts it on purpose, so a continued run keeps its
# identity across the interruption.
run_status out st python3 "$STATE" --unlock --dir "$D15" --force
run_status out st python3 "$STATE" --lock --resume --dir "$D15" --pid $$
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey lock.run_id)" = "$run1" ]; then
  pass "L2: --lock --resume adopts the recorded run id"
else
  fail "L2: --lock --resume did not continue run $run1 (exit $st)"
fi
python3 "$STATE" --unlock --dir "$D15" --force >/dev/null 2>&1 || true
run_status out st python3 "$STATE" --read --resume --dir "$D15"
[ "$st" = "2" ] && pass "L2: --resume outside --lock is a usage error (exit 2)" \
                || fail "L2: --resume on a non-lock mode should exit 2 (got $st)"

# A crafted issue title must be inert data: it arrives on stdin and is never
# evaluated. This loop runs unattended, so the title is attacker-authored text.
INJ="$(new_dir inj)"
(
  cd "$INJ"
  printf '{"run_id":"r257"}' | python3 "$STATE" --init --dir . >/dev/null 2>&1
  printf '{"current":{"issue":1,"title":"x\\"; touch PWNED; echo \\""}}' \
    | python3 "$STATE" --update --dir . >/dev/null 2>&1
) || true
[ ! -e "$INJ/PWNED" ] && pass "T4: a quote-bearing issue title in the state cannot execute" \
                      || fail "T4: a crafted issue title executed a command — injection"

# ───────────────────────────────────────────────────────────
# T5 (AC1/AC3/AC4): wiring — the built skills ship and call the script
# ───────────────────────────────────────────────────────────
BUNDLED="$SKILLS/auto-pilot/references/scripts/gi-state.py"
if [ -f "$BUNDLED" ]; then
  pass "AC1: auto-pilot bundles gi-state.py"
  if cmp -s "$STATE" "$BUNDLED"; then
    pass "AC1: the bundled copy is byte-identical to the source"
  else
    fail "AC1: the bundled gi-state.py has drifted from src/shared/scripts/"
  fi
else
  fail "AC1: auto-pilot bundles gi-state.py"
fi

AP_SKILL="$SKILLS/auto-pilot/SKILL.md"
expect_grep "AC1: the precheck list names the bundled script" \
  "references/scripts/gi-state.py" "$AP_SKILL"
expect_grep "AC1: the invocation table documents --resume" \
  "\-\-resume" "$AP_SKILL"
expect_grep "AC1: the invocation table documents --fresh" \
  "\-\-fresh" "$AP_SKILL"
expect_grep "AC3: the invocation table documents --force-unlock" \
  "\-\-force-unlock" "$AP_SKILL"
expect_grep "AC4: --resume is documented as incompatible with --dry-run" \
  "cannot combine with \`--dry-run\`" "$AP_SKILL"

AP_PHASES="$SKILLS/auto-pilot/references/phases.md"
AP_PREFLIGHT="$SKILLS/auto-pilot/references/preflight.md"
AP_ERRORS="$SKILLS/auto-pilot/references/error-messages.md"
AP_SUMMARY="$SKILLS/auto-pilot/references/summary-format.md"
AP_RUNLOG="$SKILLS/auto-pilot/references/run-log.md"

expect_grep "AC1: phases.md defines the three-valued resume gate" \
  "resumable | stale | absent" "$AP_PHASES"
expect_grep "AC1: a resume reconciles the recorded branch against GitHub" \
  "gh pr list --head" "$AP_PHASES"
expect_grep "AC1: the state file is documented as a hint, never an authority" \
  "hint, never an authority" "$AP_PHASES"

# B4: the reconciliation line puts a recorded branch into a shell word. No
# shipped skill may leave that substitution bare — quotes stop word-splitting,
# and the prose beside it must say what stops `$(…)`: the write-time check.
if python3 - "$SKILLS" <<'PY'
import pathlib, re, sys
bad = []
for path in pathlib.Path(sys.argv[1]).rglob("*.md"):
    for n, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        if "gh pr list --head" not in line:
            continue
        if re.search(r'--head\s+(?!["\'])\S*\{', line):
            bad.append(f"{path}:{n}: unquoted branch substitution — {line.strip()}")
for entry in bad:
    print(entry)
sys.exit(1 if bad else 0)
PY
then
  pass "B4: no shipped skill interpolates a recorded branch into an unquoted shell word"
else
  fail "B4: a shipped skill still passes {branch_name} to gh pr list --head unquoted"
fi
expect_grep "B4: the resume gate requires a conventional branch before substituting it" \
  "docs/naming-conventions.md" "$AP_PHASES"
expect_grep "AC1: the checkpoint procedure calls gi-state --update" \
  "references/scripts/gi-state.py --update" "$AP_PHASES"
# Step 1.0 must ship an executable --init, not only prose about one: --update
# exits 3 until the state file exists, so a loop that never runs --init is a
# loop that can never be resumed.
expect_grep "AC1: Step 1.0 ships an executable --init invocation" \
  "references/scripts/gi-state.py --init" "$AP_PHASES"
expect_grep "AC1: the --init payload is written to a file, never a command line" \
  "state-init.json" "$AP_PHASES"
expect_grep "AC1: the SKILL phase table makes Phase 0 discoverable" \
  "^| 0 | Run state |" "$AP_SKILL"
# A reclaimed lock is stale-lock evidence, never stale-state evidence: a genuine
# --resume either reclaims its dead lock or re-acquires its own live one, and
# neither says anything about the state file it is about to read.
if grep -q "A reclaimed lock (TTL elapsed, or the holder's pid is gone) prints this line too" "$AP_ERRORS"; then
  fail "AC1: a reclaimed lock still drives the resume gate to stale — --resume would init over the state it needs"
else
  pass "AC1: a reclaimed lock no longer drives the resume gate to stale"
fi

# Four phase-boundary checkpoints: post-resolve, post-review, post-fix-cycle,
# post-merge. A count, not a presence check — deleting one silently loses the
# resume point it was written for.
checkpoints="$(grep -c "^\*\*Checkpoint (post-\|^\*\*End-of-iteration checkpoint" "$AP_PHASES" || true)"
if [ "$checkpoints" -ge 5 ]; then
  pass "AC1: phases.md carries the four phase-boundary checkpoints plus the end-of-iteration one ($checkpoints)"
else
  fail "AC1: only $checkpoints checkpoint(s) in phases.md, expected 5"
fi
expect_grep "AC1: the end-of-iteration checkpoint clears current and appends processed" \
  "Clearing \`current\`" "$AP_PHASES"

# AC4: the dry-run guard precedes the triage --out write.
if python3 - "$AP_PHASES" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
out_write = text.find("--out .gitissue/triage.json")
guard = text.find("Under `--dry-run`, drop the `--out` flag")
stop = text.find("○ Dry run complete")
if out_write == -1 or guard == -1:
    sys.exit(1)
# The guard must sit between the invocation and the Step 1.3 stop, so a dry run
# never reaches a persisted write.
sys.exit(0 if out_write < guard < stop else 1)
PY
then
  pass "AC4: the dry-run guard sits ahead of the persisted triage write"
else
  fail "AC4: the --out write is still reachable before the dry-run stop"
fi

# AC3: the lock section precedes the stash — the first mutation.
if python3 - "$AP_PREFLIGHT" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
lock = text.find("## Run lock")
stash = text.find("git stash --include-untracked")
sys.exit(0 if -1 < lock < stash else 1)
PY
then
  pass "AC3: the Run lock section precedes the first stash in preflight.md"
else
  fail "AC3: the lock is documented after the first mutation"
fi
expect_grep "AC3: preflight.md calls gi-state --lock" \
  "references/scripts/gi-state.py --lock" "$AP_PREFLIGHT"
expect_grep "AC3: preflight.md documents pid, host and started_at" \
  "started_at" "$AP_PREFLIGHT"
expect_grep "AC3: preflight.md documents the TTL and liveness rule" \
  "TTL and liveness" "$AP_PREFLIGHT"
expect_grep "AC3: preflight.md documents --force-unlock" \
  "force-unlock" "$AP_PREFLIGHT"
# --force reclaims regardless of the holder, so concurrent --force calls all
# win. That is the documented human escape hatch, not a bug — but a reader who
# mistakes it for a safe way past contention loses the mutual exclusion.
if grep -q "single-operator escape hatch" "$AP_PREFLIGHT"; then
  pass "AC3: preflight.md marks --force as a single-operator escape hatch"
else
  fail "AC3: preflight.md does not warn that --force is not concurrency-safe"
fi
# L2: the resume path is the only one that inherits a recorded run id.
if grep -q -- "--lock --resume\|add \`--resume\` to that call" "$AP_PREFLIGHT"; then
  pass "L2: preflight.md documents --lock --resume for a continued run"
else
  fail "L2: preflight.md does not document how a resumed run keeps its run id"
fi

# Every invocation keeps a documented fallback beside it — the house rule for a
# script that can always be absent from the environment. The file set is
# asserted explicitly rather than filtered by an `if grep`: a guard that skips
# the file it cannot match asserts nothing the day that file stops naming the
# script, which is exactly when it should fail.
for f in "$AP_SKILL" "$AP_PHASES" "$AP_PREFLIGHT"; do
  base="$(basename "$f")"
  if ! grep -q "gi-state.py" "$f"; then
    fail "AC3: $base no longer invokes gi-state.py — the fallback check below would assert nothing"
  elif grep -q "gi-state unavailable" "$f"; then
    pass "AC3: $base keeps a documented fallback beside its gi-state calls"
  else
    fail "AC3: $base calls gi-state.py with no documented fallback"
  fi
done
# summary-format.md is the other shape: it documents the --report payload while
# SKILL.md carries the invocation, so it must carry the degrade line even though
# it never names the script.
if grep -q "gi-state unavailable" "$AP_SUMMARY"; then
  pass "AC3: summary-format.md documents the gi-state degrade for the run report"
else
  fail "AC3: summary-format.md drops the gi-state degrade for the run report"
fi
expect_grep "AC3: the error catalog carries the concurrent-run block" \
  "Another /auto-pilot run is in progress" "$AP_ERRORS"
expect_grep "AC1: the error catalog carries the resume line" \
  "Resuming run" "$AP_ERRORS"
expect_grep "AC1: the error catalog carries the stale-state line" \
  "Recorded run state is stale" "$AP_ERRORS"
expect_grep "AC3: the error catalog carries the gi-state degrade line" \
  "gi-state unavailable" "$AP_ERRORS"
expect_grep "AC4: summary-format.md documents the persisted report" \
  "Persisted run report" "$AP_SUMMARY"
expect_grep "AC4: the summary template prints the persisted report path" \
  "last-run-report.md" "$AP_SUMMARY"
expect_grep "AC1: run-log.md contrasts the run log with the run state" \
  "Run log vs. run state" "$AP_RUNLOG"

# The three artifacts are documented and gitignored — a committed lock would
# make every clone look busy.
for f in run-state.json run.lock last-run-report.md; do
  if grep -q "\.gitissue/$f" "$REPO_ROOT/.gitignore" \
     && grep -q "$f" "$REPO_ROOT/docs/config-schema.md"; then
    pass "AC4: .gitissue/$f is gitignored and documented"
  else
    fail "AC4: .gitissue/$f is missing from .gitignore or config-schema.md"
  fi
done
expect_grep "AC4: config-schema.md carries the machine-local carve-out" \
  "Carve-out" "$REPO_ROOT/docs/config-schema.md"
# The carve-out is only meaningful beside the rule it carves out of: the rest of
# .gitissue/ is committed. A byte-budget squeeze dropped this line once already.
expect_grep "AC4: config-schema.md still states the commit-the-directory rule" \
  "commit the directory (project state, not secrets)" "$REPO_ROOT/docs/config-schema.md"

# No new config key: the defaults table and the init template stay untouched.
if grep -q "run_state\|resume_ttl\|autopilot.lock" "$REPO_ROOT/docs/config-schema.md" \
   || grep -q "run_state\|resume_ttl" "$REPO_ROOT/src/skills/init-gitissue/templates/gitissue-template.yml"; then
  fail "AC4: a new config key was introduced — #257 is deliberately key-free"
else
  pass "AC4: no new config key was introduced"
fi

# ───────────────────────────────────────────────────────────
# T6 (AC2): no issue is closed behind an unreviewed, unmerged PR
# ───────────────────────────────────────────────────────────
RES_STEPS="$SKILLS/issue-resolver/references/pipeline-steps.md"
RES_SKILL="$SKILLS/issue-resolver/SKILL.md"
RESEARCHER="$SKILLS/issue-resolver/references/agents/codebase-researcher.md"
AP_PROMPTS="$SKILLS/auto-pilot/references/subagent-prompts.md"

# The shared early exit is split: the auto-close path must be reachable only
# from closing evidence.
if python3 - "$RES_STEPS" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
start = text.find("### Early exit")
if start == -1:
    print("no early-exit section")
    sys.exit(1)
section = text[start:start + 4000]
# The one sentence that must NOT exist any more: a single branch closing the
# issue for `already_resolved: true` OR `pr_in_progress: true`.
if re.search(r"already_resolved: true` or `pr_in_progress: true", section):
    print("the early exit still shares one branch")
    sys.exit(1)
pr = section.find("pr_in_progress")
if pr == -1:
    print("pr_in_progress is not handled")
    sys.exit(1)
sys.exit(0)
PY
then
  pass "AC2: the resolver's already_resolved / pr_in_progress early exits are split"
else
  fail "AC2: the resolver still shares one closing branch for both statuses"
fi

expect_grep "AC2: already_resolved requires a merged PR or a closing commit" \
  "closing evidence" "$RES_STEPS"
expect_grep "AC2: pr_in_progress never closes the issue" \
  "never close the issue" "$RES_STEPS"
expect_grep "AC2: pr_in_progress returns the PR number and branch" \
  "pr_number" "$RES_STEPS"
expect_grep "AC2: the resolver's Step 0b guard states the same rule" \
  "never close the issue" "$RES_SKILL"

# The researcher must report the matched PR's merge state, not a boolean — that
# is the distinction the caller needs to tell "in flight" from "done".
expect_grep "AC2: the researcher reports the matched PR's merge state" \
  "pr_state" "$RESEARCHER"
expect_grep "AC2: the researcher returns the matched PR in its status block" \
  "matched_pr" "$RESEARCHER"

# `gh pr list` returns the most recent N matches, so one --state all window lets
# merged PRs crowd out the open PR targeting this issue. Two scoped reads keep
# each window dedicated to the question it answers.
# The prose still names `--state all` to say why it is wrong, so the negative
# is on the invocation, not on the mention.
if grep -q -- "gh pr list --state all" "$RESEARCHER"; then
  fail "AC2: the researcher still reads PRs with a single --state all window"
else
  pass "AC2: the researcher no longer spends one window on both PR questions"
fi
expect_grep "AC2: the researcher reads open PRs in their own window" \
  "gh pr list --state open" "$RESEARCHER"
expect_grep "AC2: the researcher reads merged PRs in their own window" \
  "gh pr list --state merged" "$RESEARCHER"
# already_resolved is the one status that still auto-closes, so a MERGED PR is
# closing evidence only on the default branch — the rule Phase 0a already
# applies to a closing commit.
expect_grep "AC2: closing evidence from a MERGED PR is gated on the base branch" \
  "baseRefName" "$RESEARCHER"

# The report-back must carry the identifiers Phase 2.3 routes on.
expect_grep "AC2: the resolver spawn prompt reports pr_in_progress" \
  "pr_in_progress" "$AP_PROMPTS"
expect_grep "AC2: the batch resolver spawn prompt reports pr_in_progress" \
  "EXISTING open PR's number" "$AP_PROMPTS"
expect_grep "AC2: Phase 2.3 routes pr_in_progress into review of the existing PR" \
  "reviewing the existing PR" "$AP_PHASES"

# And the negative: no auto-pilot or resolver file may pair the pr_in_progress
# path with closing the issue.
if python3 - "$SKILLS" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
bad = []
for path in root.rglob("*.md"):
    text = path.read_text(encoding="utf-8", errors="replace")
    for m in re.finditer(r"pr_in_progress", text):
        # Emphasis markers are noise here: "must **not** close the issue" and
        # "must not close the issue" are the same sentence, and a lint that
        # reads one as a finding is a lint people route around.
        window = text[m.start(): m.start() + 600].replace("*", "")
        if re.search(r"close the issue", window, re.I) and not re.search(
            r"(never|not|no longer) close the issue|do not close|leave the issue open",
            window,
            re.I,
        ):
            bad.append(f"{path.relative_to(root)}: closes the issue on the pr_in_progress path")
if bad:
    for entry in sorted(set(bad)):
        print(entry)
    sys.exit(1)
sys.exit(0)
PY
then
  pass "AC2: no shipped skill closes an issue on the pr_in_progress path"
else
  fail "AC2: a shipped skill still closes the issue behind an unmerged PR"
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Auto-pilot run-state tests failed"
  exit 1
fi
echo "  ✓ All auto-pilot run-state checks passed"
