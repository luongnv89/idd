#!/usr/bin/env bash
# test-config-errors-clock-pin-356.sh — gi-config error paths + a pinned lint
# clock (issue #356, findings F-TEST-003 and F-TEST-006).
#
# Part 1 (F-TEST-003) covers the four gi-config.py branches that reject or
# degrade on a bad `.gitissue.yml`: malformed YAML, non-UTF-8 bytes, a
# top-level sequence, and the no-PyYAML fallback. Each is asserted in *both*
# parser worlds, because the exit vocabulary deliberately differs between them:
# with a YAML parser a syntax error is the user's mistake (exit 3, stop);
# without one it is this project's parser being narrower than YAML (exit 4,
# degrade), and inverting those two is exactly the bug the fixtures guard.
#
# PyYAML is not in the stdlib and CI does not install it, so "with a YAML
# parser" is supplied by the real library when the interpreter has it and by a
# JSON-subset stand-in when it does not. The stand-in is a real parser, not a
# script of answers — JSON is a subset of YAML, so `json.loads` accepts and
# rejects the flow-style fixtures below exactly as PyYAML does. The branches
# under test belong to gi-config, not to PyYAML, and this keeps them reachable
# on every machine without a network install. Every fixture is therefore
# written in flow style: valid YAML, valid JSON, and outside the restricted
# grammar all at once.
#
# Part 2 (F-TEST-006) covers the clock pin in tests/test-idd-lint.sh. T25d
# needs a commit made earlier in the local day than "now", so it was vacuous
# during the second after local midnight. The pin derives a fixed-offset zone
# from the current UTC hour so local now is always 12:xx; this file checks the
# derivation across all 24 hours, checks the pin is still wired into T25d, and
# runs the lint suite under ambient zones sitting on midnight.
#
# Usage: bash tests/test-config-errors-clock-pin-356.sh
# Returns: exit 0 if all checks pass, exit 1 on failure
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GI_CONFIG="$ROOT/src/shared/scripts/gi-config.py"
SCHEMA="$ROOT/docs/config-schema.md"
LINT_TEST="$ROOT/tests/test-idd-lint.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ gi-config error paths + pinned lint clock (#356)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

[ -f "$GI_CONFIG" ] || { echo "  ✗ missing $GI_CONFIG"; exit 1; }
[ -f "$SCHEMA" ]    || { echo "  ✗ missing $SCHEMA"; exit 1; }
[ -f "$LINT_TEST" ] || { echo "  ✗ missing $LINT_TEST"; exit 1; }

# ─── Fixtures ───────────────────────────────────────────────
# One directory per fixture, each holding a `.gitissue.yml` under gi-config's
# default name so the default discovery path is what runs.
fixture() {  # fixture <name>; body on stdin
  mkdir -p "$TMP/$1"
  cat > "$TMP/$1/.gitissue.yml"
}

# Malformed: an unclosed flow sequence. Rejected by PyYAML, by json.loads, and
# by the restricted parser alike.
fixture malformed <<'YML'
issue: {auto_normalize: [unclosed
YML

# Non-UTF-8: a lone 0xE9 (cp1252 "é"), the byte an editor saving in a legacy
# encoding leaves behind. Read fails before any YAML parser is consulted.
printf 'issue: {branch_prefix: "caf\xe9"}\n' > "$TMP/nonutf8.tmp"
mkdir -p "$TMP/nonutf8"
mv "$TMP/nonutf8.tmp" "$TMP/nonutf8/.gitissue.yml"

# Top-level sequence: parses fine, but a config is a mapping.
fixture toplist <<'YML'
["one", "two"]
YML

# Control for the degrade path: restricted-grammar block YAML the vendored
# parser reads on its own.
fixture blockok <<'YML'
issue:
  auto_normalize: false
YML

# ─── Parser worlds ──────────────────────────────────────────
# WITH: real PyYAML when the interpreter has it, else the JSON-subset stand-in.
# WITHOUT: an importable module that raises ImportError, which is what
# gi-config's `except ImportError` sees when the library is genuinely absent.
WITH_DIR="$TMP/with"
WITHOUT_DIR="$TMP/without"
mkdir -p "$WITH_DIR" "$WITHOUT_DIR"

cat > "$WITHOUT_DIR/yaml.py" <<'PY'
raise ImportError("PyYAML masked by test-config-errors-clock-pin-356.sh")
PY

if python3 -c 'import yaml' 2>/dev/null; then
  WITH_PYTHONPATH=""
  WITH_LABEL="real PyYAML"
else
  cat > "$WITH_DIR/yaml.py" <<'PY'
"""A YAML parser covering the flow-style subset these fixtures use.

JSON is a subset of YAML, so `json.loads` accepts and rejects the fixtures in
test-config-errors-clock-pin-356.sh exactly as PyYAML does. Only the two names
gi-config imports are provided; nothing here decides an answer by inspecting
the fixture, so the gi-config branches under test are reached for real.
"""
import json


class YAMLError(Exception):
    pass


def safe_load(text):
    stripped = text.strip()
    if not stripped:
        return None
    try:
        return json.loads(stripped)
    except json.JSONDecodeError as exc:
        raise YAMLError(str(exc)) from exc
PY
  WITH_PYTHONPATH="$WITH_DIR"
  WITH_LABEL="JSON-subset stand-in (PyYAML absent)"
fi

# run_case <world> <fixture> -> exit code on stdout, stderr in $TMP/err.txt
run_case() {
  local world="$1" name="$2" rc=0
  local path=""
  case "$world" in
    with)    path="$WITH_PYTHONPATH" ;;
    without) path="$WITHOUT_DIR" ;;
  esac
  (
    cd "$TMP/$name"
    if [ -n "$path" ]; then export PYTHONPATH="$path"; fi
    python3 "$GI_CONFIG" --schema "$SCHEMA"
  ) > "$TMP/out.txt" 2> "$TMP/err.txt" || rc=$?
  echo "$rc"
}

# check <label> <want_rc> <got_rc> <needle>...  — exit code plus every needle
check() {
  local label="$1" want="$2" got="$3"; shift 3
  local missing=""
  local needle
  for needle in "$@"; do
    grep -qF -- "$needle" "$TMP/err.txt" || missing="$missing  [$needle]"
  done
  if [ "$got" = "$want" ] && [ -z "$missing" ]; then
    pass "$label"
  else
    fail "$label (want exit $want, got $got${missing:+; stderr missing:$missing})"
    sed 's/^/      /' "$TMP/err.txt" | head -5
  fi
}

# ─── Part 1a: with a YAML parser — a bad file is the user's error (exit 3) ───
echo "  ┄ with a YAML parser — $WITH_LABEL"

# Vacuity guard: if `import yaml` fails here, every check below silently tests
# the degrade path instead and the exit-3 branches go unvisited.
if (export PYTHONPATH="$WITH_PYTHONPATH"; python3 -c 'import yaml') 2>/dev/null; then
  pass "T1.0: a YAML parser is importable — the exit-3 branches are reachable"
else
  fail "T1.0: no YAML parser importable — T1.1-T1.3 would be vacuous"
fi

RC="$(run_case with malformed)"
check "T1.1: malformed YAML is invalid config (exit 3)" 3 "$RC" \
  "✗ Invalid .gitissue.yml:" "is not valid YAML"

RC="$(run_case with nonutf8)"
check "T1.2: non-UTF-8 bytes are invalid config (exit 3)" 3 "$RC" \
  "✗ Invalid .gitissue.yml:" "is not valid UTF-8" "re-save the file as UTF-8"

RC="$(run_case with toplist)"
check "T1.3: a top-level sequence is invalid config (exit 3)" 3 "$RC" \
  "✗ Invalid .gitissue.yml:" "must contain a mapping at the top level"

# ─── Part 1b: without PyYAML — a parser limit degrades (exit 4), not exit 3 ──
echo "  ┄ without PyYAML — the vendored restricted parser"

if (export PYTHONPATH="$WITHOUT_DIR"; python3 -c 'import yaml') 2>/dev/null; then
  fail "T2.0: the PyYAML mask did not take — T2.1-T2.4 would be vacuous"
else
  pass "T2.0: the PyYAML mask makes 'import yaml' fail as a real absence does"
fi

RC="$(run_case without malformed)"
check "T2.1: malformed YAML degrades, never exit 3 (exit 4)" 4 "$RC" \
  "⚠ gi-config:" "without PyYAML"
if grep -qF "✗ Invalid .gitissue.yml" "$TMP/err.txt"; then
  fail "T2.1b: the degrade path claimed the config was invalid"
else
  pass "T2.1b: the degrade path does not blame the config it cannot parse"
fi

RC="$(run_case without nonutf8)"
check "T2.2: non-UTF-8 stays a user error without PyYAML (exit 3)" 3 "$RC" \
  "✗ Invalid .gitissue.yml:" "is not valid UTF-8"

RC="$(run_case without toplist)"
check "T2.3: flow-style YAML outside the restricted grammar degrades (exit 4)" 4 "$RC" \
  "⚠ gi-config:" "without PyYAML"

RC="$(run_case without blockok)"
if [ "$RC" = "0" ] && python3 -c '
import json, sys
payload = json.load(open(sys.argv[1], encoding="utf-8"))
assert payload["config"]["issue.auto_normalize"] is False, payload["config"]["issue.auto_normalize"]
assert payload["config_file"] == ".gitissue.yml", payload["config_file"]
assert payload["first_run"] is False, payload["first_run"]
' "$TMP/out.txt" 2>/dev/null; then
  pass "T2.4: without PyYAML a restricted-grammar config still loads and overrides"
else
  fail "T2.4: restricted-grammar config exited $RC without applying its override"
  sed 's/^/      /' "$TMP/err.txt" | head -5
fi

# ─── Part 2: the pinned lint clock (F-TEST-006) ─────────────
echo "  ┄ pinned lint clock"

# T3.1: the derivation, across every hour of the day. A POSIX TZ offset says
# what to add to local time to reach UTC, so the sign inverts: hour-12 names
# the zone whose local noon is that UTC hour.
# Driven through python3 rather than `date -d`, which is a GNU extension: the
# zone strings still go to the same libc, so a zone this platform rejects is
# still caught here.
if python3 - <<'PY' > "$TMP/deriv.txt" 2>&1
import calendar, os, time

bad = []
for hour in range(24):
    offset = hour - 12
    os.environ["TZ"] = f"IDD{offset}"
    time.tzset()
    epoch = calendar.timegm((2026, 8, 24, hour, 30, 0, 0, 0, 0))
    got = time.localtime(epoch).tm_hour
    if got != 12:
        bad.append(f"UTC {hour:02d}:30 -> local {got:02d} (TZ=IDD{offset})")
print("\n".join(bad))
raise SystemExit(1 if bad else 0)
PY
then
  pass "T3.1: the TZ derivation puts local now at 12:xx for all 24 UTC hours"
else
  fail "T3.1: TZ derivation misses noon"
  sed 's/^/      /' "$TMP/deriv.txt" | head -5
fi

# T3.2: the pin is actually wired into T25d, and released afterwards. Without
# this the derivation above could keep passing while the suite went back to
# reading the wall clock.
if grep -qF 'export TZ="IDD$(( 10#$(date -u '"'"'+%H'"'"') - 12 ))"' "$LINT_TEST" \
   && grep -qF 'SINCE_TZ_WAS="${TZ+set}"' "$LINT_TEST" \
   && grep -qF 'if [ -n "$SINCE_TZ_WAS" ]; then export TZ="$SINCE_TZ_OLD"; else unset TZ; fi' "$LINT_TEST"; then
  pass "T3.2: test-idd-lint.sh pins the clock for T25d and restores TZ after it"
else
  fail "T3.2: the T25d clock pin or its TZ restore is missing from test-idd-lint.sh"
fi

# T3.3: the pin sits *before* the fixture it protects — a pin applied after
# TODAY or the backdated commit would leave the window it was meant to close.
if python3 - "$LINT_TEST" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
def first(needle):
    for i, line in enumerate(lines):
        if needle in line:
            return i
    raise SystemExit(f"marker not found: {needle}")
pin = first('export TZ="IDD$((')
today = first('TODAY="$(date ')
release = first('if [ -n "$SINCE_TZ_WAS" ];')
bare = first('--since "$TODAY" --json')
raise SystemExit(0 if pin < today < bare < release else 1)
PY
then
  pass "T3.3: the pin brackets TODAY, the backdated fixture, and both --since runs"
else
  fail "T3.3: the clock pin does not bracket the T25d fixture it protects"
fi

# T3.4: the suite passes under ambient zones that put local now on midnight —
# the wall-clock window F-TEST-006 recorded. Two zones a second apart across
# the boundary, so both sides of it are covered.
NOW_UTC_H=$(( 10#$(date -u '+%H') ))
MIDNIGHT_TZ="IDD$(( NOW_UTC_H ))"          # local now ≈ 00:xx
ROLLOVER_TZ="IDD$(( NOW_UTC_H + 1 ))"      # local now ≈ 23:xx
for z in "$MIDNIGHT_TZ" "$ROLLOVER_TZ"; do
  ambient="$(TZ="$z" date '+%H:%M')"
  if TZ="$z" bash "$LINT_TEST" > "$TMP/lint-$z.txt" 2>&1; then
    pass "T3.4: test-idd-lint.sh passes with ambient local time $ambient (TZ=$z)"
  else
    fail "T3.4: test-idd-lint.sh failed with ambient local time $ambient (TZ=$z)"
    grep -E '✗' "$TMP/lint-$z.txt" | sed 's/^/      /' | head -5
  fi
  if grep -qF "T25d.0: clock pinned to 12:" "$TMP/lint-$z.txt"; then
    pass "T3.5: T25d ran at pinned 12:xx despite ambient $ambient"
  else
    fail "T3.5: T25d did not report the pinned 12:xx clock under ambient $ambient"
  fi
done

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ config error paths / clock pin checks failed"
  exit 1
fi

echo "  ✓ gi-config rejects and degrades as documented; the lint clock is pinned"
exit 0
