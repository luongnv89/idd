#!/usr/bin/env bash
# test-autopilot-hardening-259.sh — Issue #259 acceptance checks for the
# hardened unattended /auto-pilot loop: quarantine after repeated failures,
# rate-limit pause with automatic resume, a wall-clock runtime budget, and
# bounded retry of recoverable transient API errors.
#
# Acceptance criteria covered:
#   AC1  An issue that fails F consecutive runs is quarantined and not
#        re-attempted until the label is removed.          → T1 (behavior),
#                                                            T6 (wiring)
#   AC2  A rate-limit pause resumes automatically after reset when within the
#        runtime budget.                                   → T2, T7
#   AC3  A configured max-runtime stops the run cleanly with a persisted
#        report.                                           → T3, T8
#   AC4  No unattended stop occurs for recoverable transient API errors.
#                                                          → T4, T9
#
# T0 and T5 are hygiene that every AC leans on: the exit-code vocabulary
# (0 ok · 2 usage · 3 invalid input · 4 degrade, and never the reserved verdict
# code 1) and the one-JSON-line-per-invocation contract. T10 checks the install
# surface — the bundle, the precheck entry, the negative assertion, and the
# cross-run claim this whole issue exists to correct.
#
# The behavioral half runs src/shared/scripts/gi-ratelimit.py and gi-runlog.py
# directly in mktemp -d sandboxes — the build already asserts the shipped copies
# are byte-identical, so testing one file proves both and keeps this suite
# independent of build order. Every clock is pinned with --now and every sleep is
# one second, so the arithmetic is what is asserted, never real elapsed time.
# The wiring half reads the *built* skills, because what ships is what runs.
#
# No GitHub repo, no token, no network, and no build: it greps the committed
# built tree and mutates nothing outside its temp directory.
#
# Usage: bash tests/test-autopilot-hardening-259.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_SCRIPTS="$REPO_ROOT/src/shared/scripts"
SKILLS="$REPO_ROOT/skills"
RL="$SRC_SCRIPTS/gi-ratelimit.py"
LOG="$SRC_SCRIPTS/gi-runlog.py"
STATE="$SRC_SCRIPTS/gi-state.py"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Every exit status this run observed, so T5 can assert the reserved code 1 was
# never among them without repeating a single invocation.
SEEN_STATUSES=""

# Run a command, capturing stdout and the exit status without tripping `set -e`.
run_status() {
  local __out_var="$1"; shift
  local __status_var="$1"; shift
  local __out __status=0
  __out="$("$@" 2>/dev/null)" || __status=$?
  SEEN_STATUSES="$SEEN_STATUSES $__status"
  printf -v "$__out_var" '%s' "$__out"
  printf -v "$__status_var" '%s' "$__status"
}

# Read one key (dotted path supported) out of a JSON object on stdin. Non-string
# scalars come back in their JSON spelling — `true`, `false`, `null` — so an
# expectation reads the way the script's own documented output does.
jkey() {
  python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
for part in sys.argv[1].split("."):
    d = d[int(part)] if part.isdigit() else d[part]
print(d if isinstance(d, str) else json.dumps(d))
' "$1"
}

# assert_json LABEL JSON key=value [key=value ...] — every mismatch is reported
# together, so one failing field does not hide the next.
assert_json() {
  local label="$1" json="$2"; shift 2
  local bad="" pair key want got
  for pair in "$@"; do
    key="${pair%%=*}"
    want="${pair#*=}"
    got="$(printf '%s' "$json" | jkey "$key" 2>/dev/null || printf '<missing>')"
    [ "$got" = "$want" ] || bad="$bad ${key}=${got} (want ${want});"
  done
  if [ -z "$bad" ]; then
    pass "$label"
  else
    fail "$label —$bad"
  fi
}

expect_status() {
  local label="$1" want="$2" got="$3"
  if [ "$got" = "$want" ]; then
    pass "$label"
  else
    fail "$label (exit $got, want $want)"
  fi
}

# Fixed-string grep: these patterns are shipped prose full of backticks, braces
# and box-drawing characters, and a regex reading of them asserts something else.
expect_grep() {
  local label="$1" pattern="$2" file="$3"
  if grep -qF -- "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label"
    echo "      missing: $pattern"
    echo "      in file: ${file#$REPO_ROOT/}"
  fi
}

expect_grep_re() {
  local label="$1" pattern="$2" file="$3"
  if grep -qE -- "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label"
    echo "      missing pattern: $pattern"
    echo "      in file: ${file#$REPO_ROOT/}"
  fi
}

expect_block() {
  local label="$1" block="$2" pattern="$3"
  if [ -z "$block" ]; then
    fail "$label"
    echo "      block is empty — the extraction anchor no longer matches"
  elif printf '%s' "$block" | grep -qF -- "$pattern"; then
    pass "$label"
  else
    fail "$label"
    echo "      missing: $pattern"
  fi
}

# Append one realistic run-log record. The streak scan only reads `issue` and
# `outcome`, but a fixture shaped like the schema is the fixture a reader can
# check against docs/run-log-schema.md.
log_line() {  # file, issue, outcome [, ts]
  printf '{"ts":"%s","issue":%s,"mode":"auto","skill":"auto-pilot","outcome":"%s","pr":null}\n' \
    "${4:-2026-08-10T10:00:00Z}" "$2" "$3" >> "$1"
}

echo "◆ Auto-Pilot Unattended Hardening (issue #259)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T0: the scripts exist, are executable, stdlib-only, --help exits 0
# ───────────────────────────────────────────────────────────
if [ ! -f "$RL" ] || [ ! -f "$LOG" ]; then
  fail "T0: gi-ratelimit.py and gi-runlog.py exist"
  echo "  ✗ cannot continue without the scripts"
  exit 1
fi
pass "T0: gi-ratelimit.py and gi-runlog.py exist"

# Git records only the exec bit, and checkout applies the umask, so assert the
# bit rather than an absolute mode.
if python3 -c 'import os,sys;sys.exit(0 if os.stat(sys.argv[1]).st_mode & 0o111 else 1)' "$RL"; then
  pass "T0: gi-ratelimit.py is executable"
else
  fail "T0: gi-ratelimit.py is executable"
fi
while IFS= read -r line; do
  mode="${line%% *}"
  file="${line##*	}"
  case "$file" in
    *gi-ratelimit.py)
      if [ "$mode" = "100755" ]; then
        pass "T0: gi-ratelimit.py is committed 0755"
      else
        fail "T0: gi-ratelimit.py is committed $mode, expected 100755"
      fi
      ;;
  esac
done < <(cd "$REPO_ROOT" && git ls-files -s src/shared/scripts/)

if grep -qE '^(import|from) (yaml|requests|jinja2|numpy|pydantic)\b' "$RL"; then
  fail "T0: gi-ratelimit.py imports a third-party package"
else
  pass "T0: gi-ratelimit.py is stdlib-only"
fi
# The whole point of this helper is reproducible arithmetic over a clock. A
# network call or a subprocess would make the answer depend on the environment.
if grep -qE '^(import|from) (subprocess|urllib|http|socket)\b' "$RL"; then
  fail "T0: gi-ratelimit.py reaches the network or shells out"
else
  pass "T0: gi-ratelimit.py never touches the network and never shells out"
fi

run_status out st python3 "$RL" --help
expect_status "T0: gi-ratelimit.py --help exits 0" 0 "$st"
run_status out st python3 "$LOG" --help
expect_status "T0: gi-runlog.py --help exits 0" 0 "$st"

# The exit-code vocabulary must be stated where a reader of the script sees it,
# including the deliberate absence of a verdict code 1.
if head -95 "$RL" | grep -q "no\*\* verdict exit code 1\|no verdict exit code 1"; then
  pass "T0: the gi-ratelimit docstring rules out a verdict exit code 1"
else
  fail "T0: the gi-ratelimit docstring does not rule out a verdict exit code 1"
fi
# No flag may tempt a caller to put issue text on a command line: every input
# this script takes is a number or an instant.
if grep -qE '^\s*(parser\.add_argument\(\s*)?"--(title|body|issue-title|markdown|items|text)"' "$RL"; then
  fail "T0: gi-ratelimit.py offers a text-carrying flag — issue text would reach a shell"
else
  pass "T0: gi-ratelimit.py has no flag that would carry issue text on a command line"
fi

# ───────────────────────────────────────────────────────────
# T1 (AC1): the failure streak — counting, reset, threshold, fail-open
# ───────────────────────────────────────────────────────────
# `--failure-streak` is the read side of quarantine: the durable state is the
# label, and this count is only ever *progress toward* it.

# Interleaved issues: another issue's records are stepped over and never touch
# this issue's streak, or a busy backlog could never accumulate one.
L1="$TMP/interleaved.jsonl"
log_line "$L1" 61 failed 2026-08-10T09:00:00Z
log_line "$L1" 62 merged 2026-08-10T09:10:00Z
log_line "$L1" 61 failed 2026-08-10T09:20:00Z
log_line "$L1" 63 failed 2026-08-10T09:30:00Z
log_line "$L1" 62 merged 2026-08-10T09:40:00Z
log_line "$L1" 61 failed 2026-08-10T09:50:00Z

run_status out st python3 "$LOG" --failure-streak 61 --path "$L1"
expect_status "AC1: a readable log exits 0" 0 "$st"
assert_json "AC1: three consecutive failures across interleaved issues count as a streak of 3" \
  "$out" mode=failure_streak issue=61 streak=3 threshold=3 quarantine=true
run_status out st python3 "$LOG" --failure-streak 63 --path "$L1"
assert_json "AC1: an unrelated issue's own streak is counted independently" \
  "$out" issue=63 streak=1 quarantine=false
run_status out st python3 "$LOG" --failure-streak 62 --path "$L1"
assert_json "AC1: an issue whose latest record is not a failure has a streak of 0" \
  "$out" issue=62 streak=0 quarantine=false
run_status out st python3 "$LOG" --failure-streak 99 --path "$L1"
assert_json "AC1: an issue with no records at all has a streak of 0" \
  "$out" issue=99 streak=0 quarantine=false

# One success clears everything before it — an issue that was fixed and later
# regresses must start its streak over rather than inherit an old one.
L2="$TMP/reset.jsonl"
log_line "$L2" 61 failed 2026-08-10T08:00:00Z
log_line "$L2" 61 failed 2026-08-10T08:10:00Z
log_line "$L2" 61 failed 2026-08-10T08:20:00Z
log_line "$L2" 61 merged 2026-08-10T08:30:00Z
log_line "$L2" 61 failed 2026-08-10T08:40:00Z
run_status out st python3 "$LOG" --failure-streak 61 --path "$L2"
assert_json "AC1: a non-failed outcome resets the streak (a streak, not a total)" \
  "$out" streak=1 quarantine=false
# `skipped` is not `failed`, and a skip is exactly what a quarantined issue
# records — reading it as a failure would let quarantine feed itself.
L2B="$TMP/skipped.jsonl"
log_line "$L2B" 61 failed 2026-08-10T08:00:00Z
log_line "$L2B" 61 skipped 2026-08-10T08:10:00Z
log_line "$L2B" 61 failed 2026-08-10T08:20:00Z
run_status out st python3 "$LOG" --failure-streak 61 --path "$L2B"
assert_json "AC1: only 'failed' extends a streak — 'skipped' ends it like any other outcome" \
  "$out" streak=1

# The threshold is the whole quarantine decision, so it must flip at exactly F
# and not one record early or late.
L3="$TMP/threshold.jsonl"
log_line "$L3" 61 failed 2026-08-10T07:00:00Z
log_line "$L3" 61 failed 2026-08-10T07:10:00Z
run_status out st python3 "$LOG" --failure-streak 61 --path "$L3"
assert_json "AC1: a streak one short of the threshold does not quarantine" \
  "$out" streak=2 threshold=3 quarantine=false
run_status out st python3 "$LOG" --failure-streak 61 --path "$L3" --threshold 2
assert_json "AC1: quarantine flips exactly at streak == threshold" \
  "$out" streak=2 threshold=2 quarantine=true
log_line "$L3" 61 failed 2026-08-10T07:20:00Z
run_status out st python3 "$LOG" --failure-streak 61 --path "$L3"
assert_json "AC1: the third consecutive failure reaches the default threshold of 3" \
  "$out" streak=3 threshold=3 quarantine=true
# `0` disables the feature outright, and it must do so without pretending the
# streak is zero — the count is still reported, only the verdict is suppressed.
run_status out st python3 "$LOG" --failure-streak 61 --path "$L3" --threshold 0
assert_json "AC1: --threshold 0 disables quarantine while still reporting the streak" \
  "$out" streak=3 threshold=0 quarantine=false
expect_status "AC1: --threshold 0 is a valid configuration, not an error" 0 "$st"
run_status out st python3 "$LOG" --failure-streak 61 --path "$L3" --threshold -1
expect_status "AC1: a negative --threshold exits 3 (invalid input)" 3 "$st"

# Fail open, twice over. The run log is gitignored, deletable, best-effort
# telemetry: losing it must lose progress toward a quarantine and never manifest
# as a quarantine on evidence nobody read.
run_status out st python3 "$LOG" --failure-streak 61 --path "$TMP/no-such-log.jsonl"
expect_status "AC1: a missing log exits 4 (degrade), never 0 and never 3" 4 "$st"
assert_json "AC1: the missing-log line is still printed, fail-open at streak 0" \
  "$out" mode=failure_streak issue=61 streak=0 quarantine=false
# A directory is the unreadable case: read_text raises OSError exactly as an
# unreadable file would, and the verdict must be the same fail-open line.
mkdir -p "$TMP/dir-log.jsonl"
run_status out st python3 "$LOG" --failure-streak 61 --path "$TMP/dir-log.jsonl"
expect_status "AC1: an unreadable log exits 4 with the same fail-open verdict" 4 "$st"
assert_json "AC1: the unreadable-log line still reports streak 0, quarantine false" \
  "$out" streak=0 quarantine=false

# Malformed lines are skipped, not fatal: this file has no schema migration, and
# a truncated final line is the ordinary shape of a killed process.
L4="$TMP/garbage.jsonl"
log_line "$L4" 61 failed 2026-08-10T06:00:00Z
printf 'not json at all\n' >> "$L4"
printf '\n' >> "$L4"
printf '[1,2,3]\n' >> "$L4"
printf '   \n' >> "$L4"
log_line "$L4" 61 failed 2026-08-10T06:10:00Z
printf '{"ts":"2026-08-10T06:20:00Z","issue":61,"outcome":"fai\n' >> "$L4"
run_status out st python3 "$LOG" --failure-streak 61 --path "$L4"
expect_status "AC1: a log with malformed lines is still readable (exit 0)" 0 "$st"
assert_json "AC1: blank, non-JSON, non-object and truncated lines are skipped, not fatal" \
  "$out" streak=2 quarantine=false
# A log that is nothing but garbage is not an unreadable log — it is a readable
# log with no evidence in it, which is a streak of 0 at exit 0.
L5="$TMP/all-garbage.jsonl"
printf 'not json\n{"issue":\nnope\n' > "$L5"
run_status out st python3 "$LOG" --failure-streak 61 --path "$L5"
expect_status "AC1: an all-garbage log is readable, so it exits 0" 0 "$st"
assert_json "AC1: an all-garbage log yields no evidence and no quarantine" \
  "$out" streak=0 quarantine=false

# The documented flag spelling in the skill is `--log`; `--path` is its alias.
# A test that only exercises one would not notice the other disappearing.
run_status out st python3 "$LOG" --failure-streak 61 --log "$L1"
assert_json "AC1: --log is accepted as the alias of --path" "$out" streak=3
# The default path is the documented one, so an invocation with no path at all
# still answers (fail-open) rather than crashing in a repo with no run log.
run_status out st bash -c "cd '$TMP' && python3 '$LOG' --failure-streak 61"
if [ "$st" = "0" ] || [ "$st" = "4" ]; then
  pass "AC1: the default log path is .gitissue/runs.jsonl and answers either way"
else
  fail "AC1: the default-path invocation exited $st (want 0 or 4)"
fi
expect_grep "AC1: the default path is the documented run log" \
  '.gitissue/runs.jsonl' "$LOG"

# The read mode writes nothing — it is telemetry read-back, not a second writer.
touch "$TMP/immutable.jsonl"
before="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$TMP/immutable.jsonl")"
run_status out st python3 "$LOG" --failure-streak 61 --path "$TMP/immutable.jsonl"
after="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$TMP/immutable.jsonl")"
if [ "$before" = "$after" ]; then
  pass "AC1: --failure-streak reads the log and writes nothing"
else
  fail "AC1: --failure-streak mutated the run log"
fi

# ───────────────────────────────────────────────────────────
# T2 (AC2): the rate-limit verdict and the chunked, budget-aware pause
# ───────────────────────────────────────────────────────────
# NOW is pinned everywhere: the assertion is the arithmetic, never the clock.
NOW=1000000000
RESET=$((NOW + 600))

verdict() {  # remaining, reset-or-empty, extra args…
  local remaining="$1" reset="$2"; shift 2
  local payload
  if [ -n "$reset" ]; then
    payload="{\"rate\":{\"remaining\":$remaining,\"reset\":$reset}}"
  else
    payload="{\"rate\":{\"remaining\":$remaining}}"
  fi
  printf '%s' "$payload" | python3 "$RL" --verdict --now "$NOW" --quiet "$@" 2>/dev/null
}

# Both sides of both band boundaries. The floor is 200 and the warn band is the
# floor scaled by 2.5, so 500 is the proceed edge and 200 the warn edge.
assert_json "AC2: remaining at the warn ceiling (500) proceeds" \
  "$(verdict 500 "$RESET")" mode=verdict action=proceed wait_s=0 resume_at=null
assert_json "AC2: one call below the ceiling (499) warns instead of proceeding" \
  "$(verdict 499 "$RESET")" action=warn wait_s=0
assert_json "AC2: remaining exactly at the floor (200) still only warns" \
  "$(verdict 200 "$RESET")" action=warn wait_s=0
assert_json "AC2: one call below the floor (199) leaves the warn band" \
  "$(verdict 199 "$RESET")" action=wait wait_s=600
assert_json "AC2: a comfortable budget proceeds and reports what it read" \
  "$(verdict 4321 "$RESET")" action=proceed remaining=4321 reset="$RESET"

# The pause decision itself: it is `wait` only while the reset fits the run's
# wall-clock deadline, which is the whole of "resumes … when within the budget".
assert_json "AC2: an exhausted budget with no deadline waits for the reset" \
  "$(verdict 10 "$RESET" --deadline 0)" action=wait wait_s=600 reset="$RESET"
assert_json "AC2: the resume instant is now + wait_s, in the repo's UTC format" \
  "$(verdict 10 "$RESET" --deadline 0)" resume_at=2001-09-09T01:56:40Z
assert_json "AC2: a reset landing exactly on the deadline still fits (waits)" \
  "$(verdict 10 "$RESET" --deadline "$RESET")" action=wait wait_s=600
assert_json "AC2: a reset one second past the deadline stops instead of overshooting" \
  "$(verdict 10 "$RESET" --deadline $((RESET - 1)))" action=stop wait_s=600
assert_json "AC2: a reset far past the deadline stops cleanly" \
  "$(verdict 10 "$RESET" --deadline $((NOW + 10)))" action=stop

# The two degenerate resets. A reset already behind `now` means the payload
# predates the window rollover — warn and let the next probe read the
# replenished budget — while an unknown reset cannot be waited for at all.
assert_json "AC2: a reset already in the past warns rather than waiting 0s forever" \
  "$(verdict 10 $((NOW - 1000)))" action=warn wait_s=0
assert_json "AC2: an unknown reset stops — there is nothing to wait for" \
  "$(verdict 10 '')" action=stop reset=null wait_s=0
# `action: wait` with a non-positive `wait_s` would be an infinite loop at the
# call site, so it must be unreachable by construction.
if [ "$(verdict 10 "$NOW" | jkey action)" != "wait" ]; then
  pass "AC2: a reset equal to now never yields a zero-length wait"
else
  fail "AC2: a zero-length 'wait' was emitted — the caller would loop forever"
fi

# `gh api rate_limit` reports the core budget twice; a caller that trimmed the
# payload with --jq may have kept either.
assert_json "AC2: the resources.core form of the payload is accepted too" \
  "$(printf '{"resources":{"core":{"remaining":10,"reset":%s}}}' "$RESET" \
    | python3 "$RL" --verdict --now "$NOW" --quiet 2>/dev/null)" action=wait wait_s=600
# …and the flat form, which is what the *documented call site* actually
# produces: `--jq '{remaining: .rate.remaining, reset: .rate.reset}'` yields
# neither `.rate` nor `.resources.core`, only read_rate's last fallback. T7
# asserts that command string ships; this asserts the two halves fit.
assert_json "AC2: the flat {remaining, reset} form the shipped --jq produces is accepted" \
  "$(printf '{"remaining":10,"reset":%s}' "$RESET" \
    | python3 "$RL" --verdict --now "$NOW" --quiet 2>/dev/null)" \
  action=wait wait_s=600 remaining=10 reset="$RESET"
# A raised floor keeps a proportional band rather than collapsing it.
assert_json "AC2: a raised --threshold scales the warn band with it" \
  "$(verdict 900 "$RESET" --threshold 400)" action=warn
assert_json "AC2: the same reading proceeds once it clears the raised band" \
  "$(verdict 1000 "$RESET" --threshold 400)" action=proceed

# Invalid input stops; it never degrades into a fabricated verdict.
run_status out st bash -c "printf 'not json' | python3 '$RL' --verdict --now $NOW"
expect_status "AC2: an unparsable payload exits 3 (stop), not a guessed verdict" 3 "$st"
run_status out st bash -c "printf '{\"rate\":{\"limit\":5000}}' | python3 '$RL' --verdict --now $NOW"
expect_status "AC2: a payload with no integer remaining exits 3" 3 "$st"
run_status out st bash -c "printf '{\"rate\":{\"remaining\":true}}' | python3 '$RL' --verdict --now $NOW"
expect_status "AC2: a boolean remaining is not an integer — exit 3" 3 "$st"
run_status out st bash -c "printf '[]' | python3 '$RL' --verdict --now $NOW"
expect_status "AC2: a JSON array payload exits 3" 3 "$st"

# A `reset` outside the years `datetime` can represent — a millisecond epoch is
# how that arrives in the wild — is invalid input, not a crash. Formatting
# `resume_at` raises ValueError, which nothing else catches, so the interpreter
# would exit 1 with a traceback: the one code reserved for a script-specific
# verdict, which every call site reading non-zero as "degrade" would sail past.
OOR=99999999999999
run_status out st bash -c "printf '{\"remaining\":10,\"reset\":$OOR}' | python3 '$RL' --verdict --now $NOW"
expect_status "AC2: an out-of-range reset exits 3 (invalid input), never the reserved 1" 3 "$st"
if [ -z "$out" ]; then
  pass "AC2: the rejected payload prints no half-formed verdict on stdout"
else
  fail "AC2: the rejected payload printed a verdict anyway: $out"
fi
oor_err="$(printf '{"remaining":10,"reset":%s}' "$OOR" \
  | python3 "$RL" --verdict --now "$NOW" 2>&1 >/dev/null || true)"
if printf '%s' "$oor_err" | grep -qF '✗ gi-ratelimit:' \
   && ! printf '%s' "$oor_err" | grep -q 'Traceback'; then
  pass "AC2: it reports the documented '✗ gi-ratelimit: …' line, with no traceback"
else
  fail "AC2: an out-of-range reset did not report the documented error line"
  printf '      stderr: %s\n' "$oor_err"
fi
# The same instant reaches the other modes that parse one. None of them formats
# an instant, so none can raise — assert it rather than assume it, so a mode that
# starts printing one comes back here.
run_status out st python3 "$RL" --wait --until "$OOR" --now "$NOW" --chunk-s 1 --quiet
expect_status "AC2: an out-of-range --until is answered at exit 0, never a traceback" 0 "$st"
run_status out st bash -c "printf '{\"remaining\":9999}' | python3 '$RL' --verdict --now $OOR --quiet"
expect_status "AC2: an out-of-range --now is answered at exit 0, never a traceback" 0 "$st"

# The pause. One chunk per invocation, so the caller can refresh the run-lock
# heartbeat between chunks — the lock's TTL is what a single long sleep breaks.
run_status out st python3 "$RL" --wait --until $((NOW - 5)) --now "$NOW" --quiet
expect_status "AC2: a pause whose target is already past exits 0" 0 "$st"
assert_json "AC2: a target already past sleeps nothing and reports done" \
  "$out" mode=wait waited_s=0 remaining_s=0 done=true

SECONDS=0
run_status out st python3 "$RL" --wait --until $((NOW + 3600)) --now "$NOW" --chunk-s 1 --quiet
elapsed=$SECONDS
assert_json "AC2: a long pause sleeps at most one chunk and reports the remainder" \
  "$out" waited_s=1 remaining_s=3599 done=false
if [ "$elapsed" -le 5 ]; then
  pass "AC2: the chunked pause really returned after one chunk (${elapsed}s wall clock)"
else
  fail "AC2: the pause slept ${elapsed}s — it is not chunked"
fi

run_status out st python3 "$RL" --wait --until $((NOW + 1)) --now "$NOW" --chunk-s 1 --quiet
assert_json "AC2: a final partial chunk completes the pause and reports done" \
  "$out" waited_s=1 remaining_s=0 done=true
# The chunk is capped by what is left, so the last sleep never overshoots the
# reset it was waiting for.
run_status out st python3 "$RL" --wait --until $((NOW + 1)) --now "$NOW" --chunk-s 300 --quiet
assert_json "AC2: the last chunk is clamped to the time actually remaining" \
  "$out" waited_s=1 done=true

# The budget guard: rather than overshoot a deadline the run never agreed to, the
# pause declines to sleep and hands the caller a clean stop signal.
SECONDS=0
run_status out st python3 "$RL" --wait --until $((NOW + 3600)) --deadline $((NOW + 30)) \
  --now "$NOW" --chunk-s 300 --quiet
elapsed=$SECONDS
expect_status "AC2: declining to sleep is an answer, not an error" 0 "$st"
assert_json "AC2: a chunk that would run past the deadline sleeps nothing and is not done" \
  "$out" waited_s=0 remaining_s=3600 done=false
if [ "$elapsed" -le 3 ]; then
  pass "AC2: the budget guard returned immediately (${elapsed}s wall clock)"
else
  fail "AC2: the budget guard slept anyway (${elapsed}s)"
fi
# A chunk that lands exactly on the deadline is inside the budget.
run_status out st python3 "$RL" --wait --until $((NOW + 3600)) --deadline $((NOW + 1)) \
  --now "$NOW" --chunk-s 1 --quiet
assert_json "AC2: a chunk ending exactly on the deadline is still taken" \
  "$out" waited_s=1 done=false
# `--deadline 0` is the documented "no wall-clock deadline", not a deadline in
# 1970 — reading it the other way would make every unbounded pause decline.
run_status out st python3 "$RL" --wait --until $((NOW + 2)) --deadline 0 --now "$NOW" --chunk-s 1 --quiet
assert_json "AC2: --deadline 0 means unbounded, so the chunk is taken" \
  "$out" waited_s=1 done=false

run_status out st python3 "$RL" --wait --now "$NOW"
expect_status "AC2: --wait with no --until stops rather than guessing a target" 3 "$st"
run_status out st python3 "$RL" --wait --until $((NOW + 10)) --chunk-s 0 --now "$NOW"
expect_status "AC2: a zero --chunk-s would never make progress — exit 3" 3 "$st"
run_status out st python3 "$RL" --wait --until "not-an-instant" --now "$NOW"
expect_status "AC2: a malformed --until exits 3" 3 "$st"

# ───────────────────────────────────────────────────────────
# T3 (AC3): the wall-clock runtime budget
# ───────────────────────────────────────────────────────────
budget() {  # started_at, max_minutes, now
  python3 "$RL" --budget --started-at "$1" --max-minutes "$2" --now "$3" --quiet 2>/dev/null
}

assert_json "AC3: a run that just started has spent nothing of its budget" \
  "$(budget "$NOW" 10 "$NOW")" mode=budget elapsed_s=0 remaining_s=600 expired=false
assert_json "AC3: elapsed and remaining are complements of the configured budget" \
  "$(budget "$NOW" 10 $((NOW + 240)))" elapsed_s=240 remaining_s=360 expired=false
assert_json "AC3: one second short of the budget is not expired" \
  "$(budget "$NOW" 10 $((NOW + 599)))" elapsed_s=599 remaining_s=1 expired=false
assert_json "AC3: expiry flips exactly at the budget boundary" \
  "$(budget "$NOW" 10 $((NOW + 600)))" elapsed_s=600 remaining_s=0 expired=true
assert_json "AC3: remaining_s clamps at 0 rather than going negative past expiry" \
  "$(budget "$NOW" 10 $((NOW + 5000)))" elapsed_s=5000 remaining_s=0 expired=true
run_status out st python3 "$RL" --budget --started-at "$NOW" --max-minutes 10 \
  --now $((NOW + 5000)) --quiet
expect_status "AC3: an expired budget is an answer at exit 0, never a failure code" 0 "$st"

# `0` is the shipped default and must preserve today's unbounded behavior.
assert_json "AC3: --max-minutes 0 is unbounded — no remaining, never expired" \
  "$(budget "$NOW" 0 $((NOW + 999999)))" remaining_s=null expired=false elapsed_s=999999
# Clock skew must not manufacture an expiry, in either direction.
assert_json "AC3: a started_at in the future clamps elapsed to 0 instead of going negative" \
  "$(budget $((NOW + 500)) 10 "$NOW")" elapsed_s=0 remaining_s=600 expired=false
run_status out st python3 "$RL" --budget --started-at "$NOW" --max-minutes -1 --now "$NOW"
expect_status "AC3: a negative --max-minutes exits 3" 3 "$st"
run_status out st python3 "$RL" --budget --max-minutes 10 --now "$NOW"
expect_status "AC3: --budget with no --started-at exits 3" 3 "$st"
run_status out st python3 "$RL" --budget --started-at "yesterday" --max-minutes 10 --now "$NOW"
expect_status "AC3: a malformed --started-at exits 3" 3 "$st"
# The out-of-range instant again: this mode never formats one, so it answers
# instead of raising — and a future edit that made it print an instant would
# have to keep the 0/2/3/4 contract rather than exit 1.
run_status out st python3 "$RL" --budget --started-at 99999999999999 --max-minutes 10 \
  --now "$NOW" --quiet
expect_status "AC3: an out-of-range --started-at is answered, never a traceback" 0 "$st"

# The budget is measured from the `started_at` gi-state.py writes at --init, so
# the two scripts have to agree on the instant format. Generate a real stamp
# rather than hardcoding one: a format change in gi-state.py must fail here.
if [ -f "$STATE" ]; then
  BD="$TMP/budget-state"
  mkdir -p "$BD"
  STAMP="$(printf '{"run_id":"r259"}' | python3 "$STATE" --init --dir "$BD" 2>/dev/null | jkey started_at)"
  if [ -n "$STAMP" ]; then
    pass "AC3: gi-state.py --init records a started_at for the budget to measure from"
  else
    fail "AC3: gi-state.py --init recorded no started_at"
  fi
  run_status out st python3 "$RL" --budget --started-at "$STAMP" --max-minutes 1 --now "$STAMP" --quiet
  expect_status "AC3: gi-ratelimit parses gi-state's own started_at stamp" 0 "$st"
  assert_json "AC3: the run-state stamp measures as zero elapsed at its own instant" \
    "$out" elapsed_s=0 remaining_s=60 expired=false
  # …and the same stamp read one budget later is expired, so the two scripts
  # agree on the arithmetic and not merely on the parse.
  LATER="$(python3 -c '
import sys
from datetime import datetime, timedelta, timezone
t = datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
print((t + timedelta(minutes=1)).strftime("%Y-%m-%dT%H:%M:%SZ"))
' "$STAMP")"
  run_status out st python3 "$RL" --budget --started-at "$STAMP" --max-minutes 1 --now "$LATER" --quiet
  assert_json "AC3: one minute past a 1-minute budget is expired" \
    "$out" elapsed_s=60 remaining_s=0 expired=true
else
  fail "AC3: gi-state.py is missing — the started_at contract cannot be checked"
fi

# ───────────────────────────────────────────────────────────
# T4 (AC4): bounded exponential backoff for recoverable failures
# ───────────────────────────────────────────────────────────
# The whole of AC4 is "no unattended stop for a recoverable error": the loop
# retries on this schedule instead of stopping, and the schedule is bounded so
# retrying cannot become its own hang.
declare -a EXPECTED_DELAYS=(2 4 8 16)
for n in 1 2 3 4; do
  want="${EXPECTED_DELAYS[$((n - 1))]}"
  run_status out st python3 "$RL" --backoff --attempt "$n" --quiet
  expect_status "AC4: attempt $n is answered at exit 0" 0 "$st"
  assert_json "AC4: attempt $n backs off ${want}s" \
    "$out" mode=backoff attempt="$n" delay_s="$want" exhausted=false
done
# The delay cap and the attempt cap are independent: 16s is the cap, and it is
# reached at the last attempt rather than after it.
run_status out st python3 "$RL" --backoff --attempt 5 --quiet
expect_status "AC4: exhaustion is an answer, so it arrives at exit 0" 0 "$st"
assert_json "AC4: attempt 5 is past the schedule — exhausted, with no delay" \
  "$out" attempt=5 delay_s=0 exhausted=true
run_status out st python3 "$RL" --backoff --attempt 99 --quiet
assert_json "AC4: every attempt past the last is exhausted, never a growing sleep" \
  "$out" attempt=99 delay_s=0 exhausted=true
# 2+4+8+16 = 30s of added latency at worst: an unattended loop may retry, but it
# may not spend an unbounded amount of wall clock doing it.
TOTAL=0
for n in 1 2 3 4; do
  TOTAL=$((TOTAL + $(python3 "$RL" --backoff --attempt "$n" --quiet 2>/dev/null | jkey delay_s)))
done
if [ "$TOTAL" = "30" ]; then
  pass "AC4: the whole schedule costs 30s at worst (2+4+8+16)"
else
  fail "AC4: the schedule totals ${TOTAL}s, expected 30s"
fi
run_status out st python3 "$RL" --backoff --attempt 0
expect_status "AC4: --attempt 0 exits 3 — the schedule is 1-based" 3 "$st"
run_status out st python3 "$RL" --backoff --attempt -3
expect_status "AC4: a negative --attempt exits 3" 3 "$st"
run_status out st python3 "$RL" --backoff
expect_status "AC4: --backoff with no --attempt exits 3" 3 "$st"

# ───────────────────────────────────────────────────────────
# T5: the exit-code vocabulary and the one-JSON-line contract
# ───────────────────────────────────────────────────────────
# Code 1 is reserved for a script-specific verdict. Neither of these scripts
# claims one, so a 1 anywhere means an uncaught traceback — and every call site
# that reads non-zero as "degrade" would then degrade past a crash.
case " $SEEN_STATUSES " in
  *" 1 "*) fail "T5: a mode returned the reserved verdict exit code 1" ;;
  *)       pass "T5: no mode ever returned the reserved verdict exit code 1" ;;
esac

# Usage errors are argparse's business and stay at 2; a *missing* companion flag
# is classified as invalid input (3) instead. Both are stops, never degrades,
# which is the property that matters at the call site.
run_status out st bash -c "python3 '$RL' --verdict --wait </dev/null"
expect_status "T5: two modes at once is a usage error (exit 2)" 2 "$st"
run_status out st bash -c "python3 '$RL' </dev/null"
expect_status "T5: no mode at all is a usage error (exit 2)" 2 "$st"
run_status out st bash -c "python3 '$RL' --backoff --attempt 1 --nope </dev/null"
expect_status "T5: an unknown flag is a usage error (exit 2)" 2 "$st"
run_status out st bash -c "python3 '$LOG' --echo --failure-streak 61 </dev/null"
expect_status "T5: gi-runlog's two modes at once is a usage error (exit 2)" 2 "$st"

one_json_line() {  # label, then a shell command string
  local label="$1" cmd="$2" out lines
  out="$(bash -c "$cmd" 2>/dev/null)" || true
  lines="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
  if [ "$lines" = "1" ] \
     && printf '%s' "$out" | python3 -c 'import json,sys;json.loads(sys.stdin.read())' 2>/dev/null; then
    pass "$label"
  else
    fail "$label (stdout was $lines line(s))"
  fi
}
one_json_line "T5: --verdict prints exactly one JSON line" \
  "printf '{\"rate\":{\"remaining\":10,\"reset\":$RESET}}' | python3 '$RL' --verdict --now $NOW"
one_json_line "T5: --wait prints exactly one JSON line" \
  "python3 '$RL' --wait --until $((NOW - 1)) --now $NOW"
one_json_line "T5: --backoff prints exactly one JSON line" \
  "python3 '$RL' --backoff --attempt 2"
one_json_line "T5: --budget prints exactly one JSON line" \
  "python3 '$RL' --budget --started-at $NOW --max-minutes 5 --now $NOW"
one_json_line "T5: --failure-streak prints exactly one JSON line" \
  "python3 '$LOG' --failure-streak 61 --path '$L1'"
one_json_line "T5: --failure-streak still prints one JSON line when it degrades" \
  "python3 '$LOG' --failure-streak 61 --path '$TMP/absent.jsonl'"

# --quiet suppresses only the human half; the machine half is unconditional.
q_err="$(python3 "$RL" --backoff --attempt 1 --quiet 2>&1 >/dev/null || true)"
loud_err="$(python3 "$RL" --backoff --attempt 1 2>&1 >/dev/null || true)"
if [ -z "$q_err" ] && [ -n "$loud_err" ]; then
  pass "T5: --quiet suppresses the stderr line and leaves stdout untouched"
else
  fail "T5: --quiet did not suppress the stderr report"
fi

# ───────────────────────────────────────────────────────────
# Wiring — the BUILT skills. What ships is what runs.
# ───────────────────────────────────────────────────────────
AP="$SKILLS/auto-pilot"
AP_SKILL="$AP/SKILL.md"
AP_PHASES="$AP/references/phases.md"
AP_PREFLIGHT="$AP/references/preflight.md"
AP_ERRORS="$AP/references/error-messages.md"
AP_CONFIG="$AP/references/configuration.md"
AP_SUMMARY="$AP/references/summary-format.md"
AP_EXAMPLES="$AP/references/examples.md"
AP_EXPLICIT="$AP/references/explicit-list-mode.md"
AP_RUNLOG="$AP/references/run-log.md"
AP_PLATFORM="$AP/references/docs/platform-github.md"
AP_SCHEMA="$AP/references/docs/config-schema.md"

missing_built=0
for f in "$AP_SKILL" "$AP_PHASES" "$AP_PREFLIGHT" "$AP_ERRORS" "$AP_CONFIG" \
         "$AP_SUMMARY" "$AP_EXAMPLES" "$AP_EXPLICIT" "$AP_RUNLOG" \
         "$AP_PLATFORM" "$AP_SCHEMA"; do
  [ -f "$f" ] || { missing_built=$((missing_built + 1)); echo "      missing: ${f#$REPO_ROOT/}"; }
done
if [ "$missing_built" = "0" ]; then
  pass "T6-T10: the built auto-pilot tree carries every file this issue touched"
else
  fail "T6-T10: $missing_built built file(s) missing — run ./scripts/build.sh"
  echo "  ✗ cannot continue the wiring half"
  echo "  Results: $PASS passed, $FAIL failed"
  exit 1
fi

# ───────────────────────────────────────────────────────────
# T6 (AC1): quarantine ships — the config keys, the read side, the
#      write side, both degrades, and explicit-list mode
# ───────────────────────────────────────────────────────────
expect_grep "AC1: SKILL.md documents autopilot.quarantine_after with its default" \
  'autopilot.quarantine_after: 3' "$AP_SKILL"
expect_grep "AC1: SKILL.md documents autopilot.quarantine_label with its default" \
  'autopilot.quarantine_label: "auto-pilot-quarantined"' "$AP_SKILL"
expect_grep_re "AC1: the bundled config schema carries quarantine_after: 3" \
  '^  quarantine_after: 3$' "$AP_SCHEMA"
expect_grep_re "AC1: the bundled config schema carries quarantine_label" \
  '^  quarantine_label: "auto-pilot-quarantined"$' "$AP_SCHEMA"

# The read side is the whole feature and it is *free*, but only because the label
# joins the effective skip_labels set. Without this one sentence the label is
# inert and quarantine does nothing across runs.
expect_grep "AC1: the label is appended to the effective skip_labels set at config load" \
  'append it to the effective `skip_labels` set as part of this config load' "$AP_SKILL"
expect_grep "AC1: phases.md states quarantine is honored through that set, not a second gate" \
  'Quarantine is honored here, and only because the label is in the set.' "$AP_PHASES"

# The write side, and its record-and-continue contract: quarantine must never
# stop an unattended run.
expect_grep "AC1: Phase 2.3 has a named quarantine subsection" \
  '#### Quarantine after repeated failures' "$AP_PHASES"
expect_grep "AC1: the quarantine check calls gi-runlog --failure-streak" \
  'references/scripts/gi-runlog.py --failure-streak' "$AP_PHASES"
expect_grep "AC1: the threshold is substituted from the configured key" \
  '--threshold {autopilot.quarantine_after}' "$AP_PHASES"
expect_grep "AC1: the label is applied with gh issue edit --add-label" \
  'gh issue edit {issue_number} --add-label "{autopilot.quarantine_label}"' "$AP_PHASES"
# That label is the only config *string* in the distribution that reaches a
# command line, and gi-config only checks its type — so the substitution site
# has to check its shape, exactly as the recorded branch and started_at do.
expect_grep "AC1: the quarantine label is format-checked before it is substituted" \
  '**Check the label before you substitute it**' "$AP_PHASES"
expect_grep "AC1: the check states the characters a label may contain" \
  '`^[A-Za-z0-9._:-]+$`' "$AP_PHASES"
expect_grep "AC1: a label failing the check skips the write instead of stopping the run" \
  '⚠ Quarantine label is not a usable label name — skipping' "$AP_PHASES"
expect_grep "AC1: the unusable label is one of the enumerated non-fatal degrades" \
  '**Three degrade paths, all non-fatal.**' "$AP_PHASES"
expect_grep "AC1: a quarantined issue is recorded and the loop continues" \
  '**continue to the next issue**' "$AP_PHASES"
expect_grep "AC1: the quarantine path is explicitly record-and-continue, never a stop" \
  'record-and-continue' "$AP_PHASES"
expect_grep "AC1: the run log is documented as progress toward a quarantine, never the state" \
  '**Why the label is the state.**' "$AP_PHASES"
expect_grep "AC1: 'until the label is removed' is the shipped promise" \
  'remove it to let /auto-pilot try again' "$AP_PHASES"
expect_grep "AC1: the error catalog carries the quarantine-applied block" \
  '### Issue quarantined after repeated failures' "$AP_ERRORS"

# Both degrade paths. Neither may stop the run, and neither may quarantine.
expect_grep "AC1: an unreadable log degrades to a documented count, never a stop" \
  '⚠ gi-runlog unavailable — skipping the quarantine check' "$AP_PHASES"
expect_grep "AC1: the degrade is stated as never quarantining on missing evidence" \
  '**Never quarantine on missing' "$AP_PHASES"
expect_grep "AC1: exit 4 is classified at the quarantine call site" \
  'exit 4 (the log is missing or' "$AP_PHASES"
expect_grep "AC1: a refused label write skips the label and continues" \
  '**The label write is refused.**' "$AP_PHASES"
expect_grep "AC1: the error catalog carries the label-write-denied block" \
  '### Quarantine label could not be applied (degrade)' "$AP_ERRORS"

# The reason has to reach the telemetry and the summary, and every reason maps
# to exactly one bucket or the four counts stop summing.
expect_grep "AC1: the reason-to-bucket table carries the quarantined row" \
  '| `quarantined` | Phase 2.3'"'"'s quarantine threshold (*Quarantine after repeated failures*) | `Skipped` |' \
  "$AP_PHASES"
expect_grep "AC1: run-log.md adds quarantined to the skipped_reason vocabulary" \
  'quarantined' "$AP_RUNLOG"
expect_grep "AC1: configuration.md explains why the label, not a state file, is the truth" \
  'quarantine_after' "$AP_CONFIG"

# Explicit-list mode bypasses Phase 1, so AC1 needs the skip applied somewhere —
# and applied by exactly one step. Two steps skipping the same input would give it
# two dispositions: two different output lines, two different [Issue i/total]
# totals, and a run-log line that either exists or does not.
expect_grep "AC1: quarantine is honored in explicit-list mode too" \
  '**Quarantine is honored in this mode too — and this loop is the single step that' \
  "$AP_EXPLICIT"
expect_grep "AC1: explicit-list mode checks the label before resolving a listed issue" \
  'autopilot.quarantine_label' "$AP_EXPLICIT"
expect_grep "AC1: explicit-list mode records the quarantined skip reason" \
  'skipped_reason: quarantined' "$AP_EXPLICIT"
# …and the step that would otherwise have removed it first says it does not, so
# the two steps cannot both claim the same input.
expect_grep "AC1: upfront validation exempts the quarantine label from its removal" \
  '**One exemption: `autopilot.quarantine_label`.**' "$AP_EXPLICIT"
expect_grep "AC1: the exemption is scoped — every other skip label is still removed" \
  'Nothing else is exempt' "$AP_EXPLICIT"
expect_grep "AC1: the counter slot and the run-log line are stated, not left implied" \
  'one slot in the counter and **one** run-log line' "$AP_EXPLICIT"
# The disposition has to match the vocabulary the fan-out section already fixed,
# or a quarantined skip logs differently from every other ordinary skip.
expect_grep "AC1: the fan-out section still lists quarantined among ordinary skips" \
  '`quarantined` — still log their one line with a `skipped_reason`' "$AP_EXPLICIT"
expect_grep "AC1: run-log.md agrees the later, skipping run is what carries the reason" \
  'belongs to the **later** run that skips the issue' "$AP_RUNLOG"

# ───────────────────────────────────────────────────────────
# T7 (AC2): the rate-limit probe, the pause, and the resume
# ───────────────────────────────────────────────────────────
# One call, both fields. Without `reset` there is nothing to resume at, so the
# reset-aware selector is the precondition for the whole of AC2.
JQ="gh api rate_limit --jq '{remaining: .rate.remaining, reset: .rate.reset}'"
expect_grep "AC2: Prerequisite 8's probe reads remaining AND reset in one call" \
  "$JQ" "$AP_SKILL"
expect_grep "AC2: the driver reference selects both fields too" "$JQ" "$AP_PLATFORM"
expect_grep "AC2: the pause procedure pipes that same probe into the script" \
  "$JQ" "$AP_PREFLIGHT"
if grep -rqF -- "gh api rate_limit --jq '.rate.remaining'" "$AP"; then
  fail "AC2: a remaining-only probe still ships — a pause with no reset cannot resume"
else
  pass "AC2: no shipped auto-pilot file probes for remaining without reset"
fi

expect_grep "AC2: preflight.md owns a named rate-limit pause procedure" \
  '## Rate-limit pause' "$AP_PREFLIGHT"
expect_grep "AC2: the pause calls gi-ratelimit --verdict" \
  'python3 references/scripts/gi-ratelimit.py --verdict' "$AP_PREFLIGHT"
expect_grep "AC2: the deadline passed to the verdict is the runtime budget's epoch" \
  '--deadline "{budget_deadline_epoch}"' "$AP_PREFLIGHT"
for action in proceed warn wait stop; do
  expect_grep "AC2: the action table routes '$action'" "| \`$action\` |" "$AP_PREFLIGHT"
done
expect_grep "AC2: a 'wait' pauses and then re-probes — that is the automatic resume" \
  're-probe from the top of this section' "$AP_PREFLIGHT"
expect_grep "AC2: the pause is announced with the Rate budget exhausted block" \
  '### Rate budget exhausted — pausing until reset (non-fatal)' "$AP_ERRORS"
expect_grep "AC2: the announcement names the instant the run resumes at" \
  '○ Rate budget exhausted — pausing until {resume_at}' "$AP_ERRORS"

# The chunking is a correctness requirement, not a cosmetic one: one sleep past
# the 3600s lock TTL lets a second run reclaim a live lock mid-pause.
expect_grep "AC2: the pause calls gi-ratelimit --wait" \
  'python3 references/scripts/gi-ratelimit.py --wait' "$AP_PREFLIGHT"
expect_grep "AC2: the chunk is the documented 300s" '--chunk-s 300' "$AP_PREFLIGHT"
expect_grep "AC2: preflight.md states why the pause is chunked" \
  '**The pause is chunked, and that is not cosmetic.**' "$AP_PREFLIGHT"
expect_grep "AC2: the rationale names the lock TTL the chunking protects" \
  '3600s' "$AP_PREFLIGHT"
expect_grep "AC2: the heartbeat is refreshed between chunks" \
  'refresh the heartbeat' "$AP_PREFLIGHT"
expect_grep "AC2: gi-state.py stays the single writer of the lock file" \
  'single writer of' "$AP_PREFLIGHT"
expect_grep "AC2: done:false with waited_s:0 is documented as a clean stop" \
  'done: false' "$AP_PREFLIGHT"
expect_grep "AC2: the pause keeps a documented prose fallback beside the call" \
  '⚠ gi-ratelimit unavailable — computing the pause by hand' "$AP_PREFLIGHT"
expect_grep "AC2: the catalog carries the gi-ratelimit degrade block" \
  '### gi-ratelimit unavailable (degrade)' "$AP_ERRORS"
expect_grep "AC2: a stop verdict has its own fatal block" \
  '### Insufficient API rate budget (fatal — the wait does not fit)' "$AP_ERRORS"

# ───────────────────────────────────────────────────────────
# T8 (AC3): the runtime budget stops the run cleanly, with a report
# ───────────────────────────────────────────────────────────
expect_grep "AC3: SKILL.md documents autopilot.max_runtime_minutes with its default" \
  'autopilot.max_runtime_minutes: 0' "$AP_SKILL"
expect_grep_re "AC3: the bundled config schema carries max_runtime_minutes: 0" \
  '^  max_runtime_minutes: 0$' "$AP_SCHEMA"
expect_grep "AC3: Stop Conditions carries the runtime-budget row" \
  '| Runtime budget reached (`autopilot.max_runtime_minutes`) | `○ Runtime budget reached ({max} min) — stopping cleanly`' \
  "$AP_SKILL"
# The row count is the invariant: a table row deleted in a later edit is exactly
# the failure this pin exists to catch.
stop_rows="$(awk '/^## Stop Conditions/{f=1} f && /^\| /' "$AP_SKILL" | grep -cv '^| Condition' || true)"
if [ "$stop_rows" = "13" ]; then
  pass "AC3: Stop Conditions has 12 condition rows (plus its separator)"
else
  fail "AC3: Stop Conditions has $((stop_rows - 1)) condition rows, expected 12"
fi
expect_grep "AC3: phases.md owns a named runtime budget check" \
  '### Runtime budget check' "$AP_PHASES"
expect_grep "AC3: the check calls gi-ratelimit --budget" \
  'python3 references/scripts/gi-ratelimit.py --budget' "$AP_PHASES"
expect_grep "AC3: the budget is measured from the run state's started_at" \
  '--started-at "{run_state.started_at}"' "$AP_PHASES"
expect_grep "AC3: the configured maximum is substituted from the key" \
  '--max-minutes {autopilot.max_runtime_minutes}' "$AP_PHASES"
expect_grep "AC3: a recorded started_at is validated before it reaches a shell word" \
  '**Check `started_at` before you substitute it**' "$AP_PHASES"
expect_grep "AC3: expiry is documented as an answer at exit 0, not a failure" \
  'it is an answer, not a' "$AP_PHASES"
expect_grep "AC3: the check runs at the top of every iteration" \
  'At the **top of every iteration**' "$AP_PHASES"
expect_grep "AC3: the check also brackets a rate-limit pause" \
  '**Before** entering a rate-limit pause' "$AP_PHASES"
expect_grep "AC3: preflight.md's pause points back at the same budget check" \
  '*Runtime budget check*' "$AP_PREFLIGHT"
expect_grep "AC3: the error catalog carries the clean-stop block" \
  '### Runtime budget reached (clean stop)' "$AP_ERRORS"
expect_grep "AC3: the summary carries a fourth Result value for a budget stop" \
  'BUDGET REACHED' "$AP_SUMMARY"
expect_grep "AC3: the Result line enumerates the budget stop alongside the others" \
  '{COMPLETED / PAUSED / LIMIT REACHED / BUDGET REACHED}' "$AP_SUMMARY"
# "Stops cleanly with a persisted report" is two obligations, and the report is
# the half that is easy to drop.
expect_grep "AC3: the budget stop persists the final summary with --report" \
  '--report' "$AP_SKILL"
expect_grep "AC3: the stop-condition row names both the persisted report and the lock release" \
  'the final summary is persisted with `--report`, and the lock is released' "$AP_SKILL"
expect_grep "AC3: summary-format.md ties the budget stop to the persisted report" \
  'Runtime budget check' "$AP_SUMMARY"
expect_grep "AC3: configuration.md explains why the budget is a start gate, not a kill switch" \
  '**start gate, not a kill switch**' "$AP_CONFIG"
expect_grep "AC3: an unbounded default preserves today's behavior" \
  '0` (the default) is unbounded' "$AP_CONFIG"
expect_grep "AC3: the worked example shows a budget-triggered stop" \
  'BUDGET REACHED' "$AP_EXAMPLES"

# ───────────────────────────────────────────────────────────
# T9 (AC4): recoverable failures are retried, not stopped on
# ───────────────────────────────────────────────────────────
expect_grep "AC4: driver rule 5 is the single home of the retry contract" \
  '5. **Retry only transient failures, on bounded exponential backoff.**' "$AP_PLATFORM"
expect_grep "AC4: rule 5 enumerates the recoverable classes" \
  '5xx, connection reset or timeout' "$AP_PLATFORM"
expect_grep "AC4: rule 5 enumerates what is NOT recoverable" \
  'Not recoverable: 401, 404' "$AP_PLATFORM"
expect_grep "AC4: rule 5 routes primary exhaustion to the pause path, never to backoff" \
  "rule 4's pause path, never backoff" "$AP_PLATFORM"
expect_grep "AC4: preflight.md owns the retry loop that acts on rule 5" \
  '## Transient-failure retry' "$AP_PREFLIGHT"
expect_grep "AC4: the retry loop calls gi-ratelimit --backoff" \
  'python3 references/scripts/gi-ratelimit.py --backoff --attempt {n}' "$AP_PREFLIGHT"
expect_grep "AC4: the shipped schedule matches the script's" \
  '2s, 4s, 8s, 16s' "$AP_PREFLIGHT"
expect_grep "AC4: exhaustion is documented as arriving at exit 0" \
  'exhausted: true' "$AP_PREFLIGHT"
expect_grep "AC4: SKILL.md points transient-failure handling at rule 5 and the loop" \
  'Retrying after transient failures' "$AP_SKILL"

# The mid-run 403 is where AC4 and AC2 meet, and it is the block that used to
# tell a nonexistent human to wait and retry.
ERR_403="$(awk '/^### API rate limit during a loop read/{f=1;next} f && /^### /{exit} f' "$AP_ERRORS")"
expect_block "AC4: the mid-run 403 block classifies the failure by driver rule 5" \
  "$ERR_403" '**Action:** Classify it by driver rule 5'
expect_block "AC4: the 403 block routes a secondary limit to the bounded backoff" \
  "$ERR_403" '*Transient-failure retry*'
expect_block "AC4: the 403 block routes primary exhaustion to the pause" \
  "$ERR_403" '*Rate-limit pause*'
expect_block "AC4: the 403 block says an unattended run has no human remedy" \
  "$ERR_403" 'an unattended run has none'

# The negative that gives AC4 its teeth. The remedy is scoped to auto-pilot: the
# interactive skills keep it deliberately, because they *do* have a reader.
if grep -rqF -- 'wait a few minutes, then retry' "$AP"; then
  fail "AC4: a shipped auto-pilot file still tells a nobody to wait and retry"
  grep -rnF -- 'wait a few minutes, then retry' "$AP" | sed 's/^/      /'
else
  pass "AC4: 'wait a few minutes, then retry' appears nowhere under skills/auto-pilot/"
fi
# …and the scoping is real: a grep that matched nothing anywhere would pass the
# assertion above while proving nothing about the removal.
interactive_hits="$(grep -rlF -- 'wait a few minutes, then retry' "$SKILLS" 2>/dev/null | wc -l | tr -d ' ')"
if [ "$interactive_hits" -gt 0 ]; then
  pass "AC4: the human-directed remedy survives in the interactive skills ($interactive_hits file(s))"
else
  fail "AC4: the remedy is gone everywhere — the auto-pilot negative asserts nothing"
fi

# ───────────────────────────────────────────────────────────
# T10: the install surface — bundle, precheck, and the cross-run claim
# ───────────────────────────────────────────────────────────
BUNDLED="$AP/references/scripts/gi-ratelimit.py"
if [ -f "$BUNDLED" ]; then
  pass "T10: auto-pilot bundles gi-ratelimit.py"
  if cmp -s "$RL" "$BUNDLED"; then
    pass "T10: the bundled copy is byte-identical to the source"
  else
    fail "T10: the bundled gi-ratelimit.py has drifted from src/shared/scripts/"
  fi
  if python3 -c 'import os,sys;sys.exit(0 if os.stat(sys.argv[1]).st_mode & 0o111 else 1)' "$BUNDLED"; then
    pass "T10: the bundled copy preserves the source's exec bit"
  else
    fail "T10: the bundled gi-ratelimit.py lost its exec bit"
  fi
else
  fail "T10: auto-pilot bundles gi-ratelimit.py"
fi

# The precheck list and the bundle must agree — a file that ships without a
# precheck entry is a file whose absence nobody notices until a run half-works.
PRECHECK="$(awk '/^### Bundled dependency precheck/{f=1;next} f && /^#/{exit} f' "$AP_SKILL")"
expect_block "T10: the precheck list names references/scripts/gi-ratelimit.py" \
  "$PRECHECK" '- `references/scripts/gi-ratelimit.py`'
expect_block "T10: the precheck entry says what the script is for" \
  "$PRECHECK" 'rate-limit verdict, chunked pause'
# The invocation is always `python3 references/scripts/…`, never `./…`: zip and
# tar installs drop the exec bit and the committed 0755 is a human convenience.
if grep -rqF -- './references/scripts/gi-ratelimit.py' "$AP"; then
  fail "T10: a call site invokes the bundled script as ./… — a stripped exec bit breaks it"
else
  pass "T10: every gi-ratelimit call site runs it through python3, never ./"
fi

# The cross-run property this whole issue exists to fix: "failed, so it will be
# retried next run" is no longer an unqualified promise anywhere.
expect_grep "T10: the failure path qualifies its own retry-next-run claim" \
  '"Retry on next run" is only true while retrying is still worth the tokens.' "$AP_PHASES"
expect_grep "T10: examples.md scopes its empty-skip-list claim to the session list" \
  '**"Empty skip list" is about the session list only.**' "$AP_EXAMPLES"
expect_grep "T10: examples.md states a quarantined issue does NOT come back next run" \
  'while one skipped for a quarantine does not' "$AP_EXAMPLES"
expect_grep "T10: examples.md names the label as what filters it, before the skip list" \
  'in the effective `skip_labels` set, before the' "$AP_EXAMPLES"
# …and the seeded-skip-list claim the plan flagged as already unbacked on main:
# gi-state.py validates skip_list as bare integers, so no reason is persisted.
expect_grep "T10: phases.md no longer claims a seeded skip_list entry keeps its reason" \
  'validates `skip_list` as bare integers' "$AP_PHASES"
expect_grep "T10: phases.md names the consequence — every seeded entry is 'resumed'" \
  'entry the state seeds is therefore `resumed`' "$AP_PHASES"

# The worked example is the one place all three behaviors are shown together, so
# a reader can see that none of them stops the run except the budget.
expect_grep "T10: a worked example covers all three hardening behaviors" \
  '## Unattended hardening: quarantine, rate-limit pause, runtime budget' "$AP_EXAMPLES"

# ───────────────────────────────────────────────────────────
# T11 (AC1, QA cycle 2): the quarantine label is honored on a
#      reused-cache iteration, where the triage row's labels are stale
# ───────────────────────────────────────────────────────────
# The hole this pins: Step 1.2's `skip_labels` criterion is answered from the
# triage graph, whose per-issue `labels` are as old as the cached payload. Phase
# 2.3 applies the quarantine label mid-run and lands NO commit, so Step 1.1a's
# commits-since check keeps reading that cache as `fresh` — and the very run that
# quarantined the issue re-picks and re-resolves it. The close is Step 1.2b's
# post-pick re-check, which already holds the picked issue's live `labels`.
PICK_BLOCK="$(awk '/^### Step 1.2 — Pick Next Issue/{f=1;next} f && /^### /{exit} f' "$AP_PHASES")"
CAPTURE_BLOCK="$(awk '/^### Step 1.2b — Capture the caller payload/{f=1;next} f && /^### /{exit} f' "$AP_PHASES")"
AP_RUNSCHEMA="$AP/references/docs/run-log-schema.md"

# The re-check is the enforcement point, so the criterion has to live in *that*
# block — not merely somewhere in phases.md, which was already true and still let
# a quarantined issue through.
expect_block "AC1: Step 1.2b rejects a pick whose live labels are in skip_labels" \
  "$CAPTURE_BLOCK" 'is in the effective `skip_labels` set'
expect_block "AC1: the re-check reads the label names off the fetched record" \
  "$CAPTURE_BLOCK" '`.issue.labels[].name`'
expect_block "AC1: the re-check names the reused-cache blind spot it closes" \
  "$CAPTURE_BLOCK" '**Live labels close the reused cache'
expect_block "AC1: it states the no-commit reason the cache stays fresh" \
  "$CAPTURE_BLOCK" 'a run that merged nothing lands no'
expect_block "AC1: the close is stated for the whole skip_labels set, not just quarantine" \
  "$CAPTURE_BLOCK" 'closes it for **every** value in the set'
expect_block "AC1: the live check costs no extra call — labels are already fetched" \
  "$CAPTURE_BLOCK" 'because `labels` is already in the field list this step requests'

# The disposition, which is what keeps the counts and the telemetry honest: a
# reason per rejection, one bucket each, no run-log line, no iteration slot.
expect_block "AC1: a quarantine-label rejection records the reason 'quarantined'" \
  "$CAPTURE_BLOCK" '| a live label matches `autopilot.quarantine_label` | `quarantined` |'
expect_block "AC1: any other skip label records the reason 'blocked_label'" \
  "$CAPTURE_BLOCK" '| a live label matches any other `skip_labels` value | `blocked_label` |'
expect_block "AC1: 1.2b still defers the bucket to Step 1.2's table" \
  "$CAPTURE_BLOCK" 'reason-to-bucket table is the single home'
expect_block "AC1: a label rejection writes no run-log line" \
  "$CAPTURE_BLOCK" '**no `.gitissue/runs.jsonl` line is written**'
expect_block "AC1: a label rejection consumes no iteration slot" \
  "$CAPTURE_BLOCK" '`[Iteration {i}/{max}]` slot is consumed'
expect_block "AC1: the reuse path is stated to match what a full triage would do" \
  "$CAPTURE_BLOCK" 'reuse path and the triage path reach the same disposition'
expect_block "AC1: the skip line names the quarantine label so an unattended log says why" \
  "$CAPTURE_BLOCK" 'quarantined ({autopilot.quarantine_label})'

# Step 1.2 keeps the read side, but must no longer claim the cached answer is
# sufficient — a reader who stops there is the reader who shipped the bug.
expect_block "AC1: Step 1.2 admits its labels come from the triage row" \
  "$PICK_BLOCK" '**But the labels this step reads are the triage row'
expect_block "AC1: Step 1.2 names the reuse iteration as the stale case" \
  "$PICK_BLOCK" 'A **reuse** iteration cannot'
expect_block "AC1: Step 1.2 points the live reading at Step 1.2b" \
  "$PICK_BLOCK" 'once more **live** in *Step 1.2b*'
expect_block "AC1: the Not skipped criterion says the label half is re-asked live" \
  "$PICK_BLOCK" 're-asks this one against live labels after the pick'
# Every reason still maps to a bucket, or the four counts stop summing.
expect_block "AC1: the bucket table carries the 1.2b quarantined row" \
  "$PICK_BLOCK" '| `quarantined` | *Step 1.2b*'"'"'s post-pick re-check (live `autopilot.quarantine_label`) | `Skipped` |'
expect_block "AC1: the bucket table carries the 1.2b blocked_label row" \
  "$PICK_BLOCK" '| `blocked_label` | *Step 1.2b*'"'"'s post-pick re-check (any other live `skip_labels` value) | `Skipped` |'
expect_block "AC1: the sum invariant survives the two added rows" \
  "$PICK_BLOCK" 'every filtered issue lands in exactly one bucket'

# Cross-file agreement — cycle 1's lesson was that one claim with three homes
# gets two of them updated.
expect_grep "AC1: run-log.md says a triage-mode label skip writes no line at all" \
  '**no** line at all, exactly as a `wontfix` issue does today' "$AP_RUNLOG"
expect_grep "AC1: run-log.md still gives explicit-list mode its counter slot and line" \
  'it gets an `[Issue {i}/{total}]` slot and its' "$AP_RUNLOG"
expect_grep "AC1: the No-eligible catalog names the two new skip-list reasons" \
  '`quarantined` or `blocked_label` when its live labels are in' "$AP_ERRORS"
for reason in 'quarantined' 'blocked_label'; do
  expect_grep "AC1: the bundled run-log schema already admits skipped_reason $reason" \
    "$reason" "$AP_RUNSCHEMA"
done

# ───────────────────────────────────────────────────────────
# T12 (AC2, QA cycle 2): the Prerequisite 8 pause is satisfiable
#      as written — no run state and no lock exist there yet
# ───────────────────────────────────────────────────────────
# The pause procedure is shared by two call sites. Written for the mid-run one it
# asks Prerequisite 8 for three things it cannot have: a deadline derived from
# run_state.started_at, a heartbeat refresh between chunks, and a lock to release
# on the stop branch. Unstated, the deadline silently becomes unbounded — which
# is the promise SKILL.md's Prerequisite 8 makes, broken.
PAUSE_BLOCK="$(awk '/^## Rate-limit pause/{f=1;next} f && /^## /{exit} f' "$AP_PREFLIGHT")"

expect_block "AC2: the deadline is stated to have one derivation per call site" \
  "$PAUSE_BLOCK" '**It has two derivations, one per call site.**'
expect_block "AC2: mid-run it is still measured from the recorded started_at" \
  "$PAUSE_BLOCK" '`run_state.started_at + autopilot.max_runtime_minutes × 60`'
expect_block "AC2: at Prerequisite 8 it comes from the clock instead" \
  "$PAUSE_BLOCK" 'derive it from the clock: `now + autopilot.max_runtime_minutes'
expect_block "AC2: the preflight derivation says why no run state exists yet" \
  "$PAUSE_BLOCK" 'writes `started_at` in `references/phases.md` (*Step 1.0*), which runs after the'
expect_block "AC2: 0 still means unbounded at both sites" \
  "$PAUSE_BLOCK" '`0` means unbounded'
expect_block "AC2: fabricating a started_at is ruled out, with the consequence named" \
  "$PAUSE_BLOCK" 'an unsatisfiable deadline degrades into an'

expect_block "AC2: the preflight site is stated to hold no lock and no run state" \
  "$PAUSE_BLOCK" '**The preflight site holds no lock and has no run state'
expect_block "AC2: the between-chunk heartbeat refresh is scoped out of preflight" \
  "$PAUSE_BLOCK" 'the between-chunk heartbeat refresh **does not apply**'
expect_block "AC2: the pause may not create run-state.json ahead of --init" \
  "$PAUSE_BLOCK" 'ahead of the `--init` that owns creating it'
expect_block "AC2: chunking itself is unchanged — only the refresh drops away" \
  "$PAUSE_BLOCK" 'The chunked `--wait` call itself is unchanged'
expect_block "AC2: the bracketing runtime-budget check is scoped out too" \
  "$PAUSE_BLOCK" 'the bracketing *Runtime budget check* does not apply either'
expect_block "AC2: the deadline is named as the enforcement at the preflight site" \
  "$PAUSE_BLOCK" 'The `--deadline` above **is** the'
expect_block "AC2: 'release the lock' is scoped to the mid-run case in the prose" \
  "$PAUSE_BLOCK" 'is the mid-run half of that row'
expect_block "AC2: the stop row itself carries the scope, not just the prose below it" \
  "$PAUSE_BLOCK" 'release the lock (mid-run only — at Prerequisite 8 none is held yet)'
expect_block "AC2: mid-run behavior is restated so the scoping cannot be read as a removal" \
  "$PAUSE_BLOCK" 'Mid-run every one of those reads normally'

# All three files have to tell the same story — SKILL.md makes the promise, the
# catalog prints the stop, preflight.md owns the procedure.
expect_grep "AC2: Prerequisite 8 says the fit is measured from the clock" \
  'The fit is measured from the clock here' "$AP_SKILL"
expect_grep "AC2: Prerequisite 8 says no run lock is held at that site" \
  '**no run lock yet**' "$AP_SKILL"
expect_grep "AC2: the fatal block scopes its lock release to the mid-run case" \
  '**At Prerequisite 8 there is no lock yet**' "$AP_ERRORS"
expect_grep "AC2: the fatal block still requires the persisted report at both sites" \
  'the preflight stop is the report and this block alone' "$AP_ERRORS"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Auto-pilot hardening tests failed"
  exit 1
fi
echo "  ✓ All auto-pilot hardening checks passed"
