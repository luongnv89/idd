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

# Atomicity: no temp file survives a checkpoint, and the file always parses.
leftovers="$(find "$D1" -name '*.tmp' | wc -l | tr -d ' ')"
if [ "$leftovers" = "0" ] && python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$D1/run-state.json"; then
  pass "AC1: the state write is atomic — no temp file survives, the file parses"
else
  fail "AC1: a checkpoint left $leftovers temp file(s) behind"
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
expect_grep "AC1: the checkpoint procedure calls gi-state --update" \
  "references/scripts/gi-state.py --update" "$AP_PHASES"

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

# Every invocation keeps a documented fallback beside it — the house rule for a
# script that can always be absent from the environment.
for f in "$AP_SKILL" "$AP_PHASES" "$AP_PREFLIGHT" "$AP_SUMMARY"; do
  if grep -q "gi-state.py" "$f"; then
    if grep -q "gi-state unavailable" "$f"; then
      pass "AC3: $(basename "$f") keeps a documented fallback beside its gi-state calls"
    else
      fail "AC3: $(basename "$f") calls gi-state.py with no documented fallback"
    fi
  fi
done
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
