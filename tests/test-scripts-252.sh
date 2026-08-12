#!/usr/bin/env bash
# test-scripts-252.sh — Issue #252 acceptance checks for the second wave of
# shared scripts (gi-secscan, gi-ci-wait, gi-issue, gi-branch).
#
# Acceptance criteria covered:
#   AC1  gi-secscan replaces the re-derived bash at every commit site, with
#        config-extensible patterns and a block/warn exit contract.
#   AC2  gi-ci-wait returns a JSON verdict without per-poll LLM tool calls.
#   AC3  gi-issue serves repeat reads from a TTL cache, keyed by field set.
#   AC4  gi-branch derives names matching docs/naming-conventions.md.
#   AC5  Every replaced prose procedure survives as a documented fallback.
#
# The behavioral halves run each script directly out of src/shared/scripts/ —
# the build already asserts the shipped copies are byte-identical, so testing
# one file proves both and keeps this suite independent of build order. The
# wiring halves read the *built* skills, because what ships is what runs.
#
# Usage: bash tests/test-scripts-252.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_SCRIPTS="$REPO_ROOT/src/shared/scripts"
SKILLS="$REPO_ROOT/skills"
SECSCAN="$SRC_SCRIPTS/gi-secscan.py"
CIWAIT="$SRC_SCRIPTS/gi-ci-wait.py"
GIISSUE="$SRC_SCRIPTS/gi-issue.py"
GIBRANCH="$SRC_SCRIPTS/gi-branch.py"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# AWS's own documentation example key, assembled from two halves so the literal
# never appears in this file. gi-secscan scans file *contents*, so a checked-in
# 20-character AKIA… string would block every commit of this test suite. The
# canonical document's rule for exactly this case is to fix the fixture, never
# to weaken or skip the scan — so the fixture is fixed here.
AWS_FIXTURE_KEY="AKIA""IOSFODNN7EXAMPLE"
export AWS_FIXTURE_KEY

# Run a command, capturing stdout and the exit status without tripping `set -e`.
run_status() {
  local __out_var="$1"; shift
  local __status_var="$1"; shift
  local __out __status=0
  __out="$("$@" 2>/dev/null)" || __status=$?
  printf -v "$__out_var" '%s' "$__out"
  printf -v "$__status_var" '%s' "$__status"
}

# Read one key out of a JSON object on stdin.
jkey() {
  python3 -c 'import json,sys;print(json.loads(sys.stdin.read())[sys.argv[1]])' "$1"
}

echo "◆ Shared Scripts, Wave 2 (issue #252)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T0: all four scripts exist, are executable, and --help exits 0
# ───────────────────────────────────────────────────────────
for s in gi-secscan gi-ci-wait gi-issue gi-branch; do
  path="$SRC_SCRIPTS/$s.py"
  if [ ! -f "$path" ]; then
    fail "$s.py exists"
    continue
  fi
  # Git records only the exec bit, and checkout applies the umask, so assert
  # the bit rather than an absolute mode.
  if python3 -c 'import os,sys;sys.exit(0 if os.stat(sys.argv[1]).st_mode & 0o111 else 1)' "$path"; then
    pass "$s.py is executable"
  else
    fail "$s.py is executable"
  fi
  if python3 "$path" --help >/dev/null 2>&1; then
    pass "$s.py --help exits 0"
  else
    fail "$s.py --help exits 0"
  fi
done

# The committed mode must be 100755 — the build preserves it, and a 0644 source
# ships a non-executable copy into every skill.
while IFS= read -r line; do
  mode="${line%% *}"
  file="${line##*	}"
  case "$file" in
    *gi-secscan.py|*gi-ci-wait.py|*gi-issue.py|*gi-branch.py)
      if [ "$mode" = "100755" ]; then
        pass "$(basename "$file") is committed 0755"
      else
        fail "$(basename "$file") is committed $mode, expected 100755"
      fi
      ;;
  esac
done < <(cd "$REPO_ROOT" && git ls-files -s src/shared/scripts/)

# ───────────────────────────────────────────────────────────
# T1 (AC1): gi-secscan — the five rules and the block/warn contract
# ───────────────────────────────────────────────────────────
WORK="$TMP/scan"
mkdir -p "$WORK/node_modules"
printf 'nothing to see\n' > "$WORK/clean.txt"
# A placeholder, not a key: this must NOT fire, or the scan gets disabled.
printf 'api_key = "your-api-key-here"\nother = "xxx"\n' > "$WORK/placeholder.txt"
# A real-shaped AWS key: prefix + exactly 16 uppercase/digits.
printf 'AWS_ACCESS_KEY_ID=%s\n' "$AWS_FIXTURE_KEY" > "$WORK/leak.env.txt"
touch "$WORK/.env" "$WORK/node_modules/dep.js"
printf '\0\0\0%s\n' "$AWS_FIXTURE_KEY" > "$WORK/binary.bin"

cd "$WORK"

run_status out st python3 "$SECSCAN" clean.txt placeholder.txt
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey verdict)" = "clean" ]; then
  pass "AC1: clean tree exits 0 with verdict clean (placeholders do not fire)"
else
  fail "AC1: clean tree exits 0 with verdict clean (got exit $st)"
fi

run_status out st python3 "$SECSCAN" leak.env.txt
if [ "$st" = "1" ] && [ "$(printf '%s' "$out" | jkey verdict)" = "block" ]; then
  pass "AC1: a real API-key value blocks with exit 1"
else
  fail "AC1: a real API-key value blocks with exit 1 (got exit $st)"
fi

# The reported detail must not carry the secret itself — a scan that echoes the
# value into a transcript has leaked it a second time.
if ! printf '%s' "$out" | grep -q "$AWS_FIXTURE_KEY"; then
  pass "AC1: the blocking report redacts the matched value"
else
  fail "AC1: the blocking report echoes the matched secret verbatim"
fi

run_status out st python3 "$SECSCAN" .env
if [ "$st" = "1" ] && [ "$(printf '%s' "$out" | jkey verdict)" = "block" ]; then
  pass "AC1: a secret-bearing filename blocks with exit 1"
else
  fail "AC1: a secret-bearing filename blocks with exit 1 (got exit $st)"
fi

run_status out st python3 "$SECSCAN" binary.bin
if [ "$st" = "0" ]; then
  pass "AC1: binary files are skipped for value scanning"
else
  fail "AC1: binary files are skipped for value scanning (got exit $st)"
fi

run_status out st python3 "$SECSCAN" node_modules/dep.js
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey verdict)" = "warn" ]; then
  pass "AC1: a build artifact warns without blocking (exit 0, verdict warn)"
else
  fail "AC1: a build artifact warns without blocking (got exit $st)"
fi

# Mode contract: the same warning needs confirmation interactively and does not
# in auto mode. Real secrets are unaffected by mode — asserted below.
if [ "$(printf '%s' "$out" | jkey confirm_required)" = "True" ]; then
  pass "AC1: interactive mode marks warnings confirm_required"
else
  fail "AC1: interactive mode marks warnings confirm_required"
fi
run_status out st env IDD_AUTO_MODE=1 python3 "$SECSCAN" node_modules/dep.js
if [ "$(printf '%s' "$out" | jkey confirm_required)" = "False" ]; then
  pass "AC1: auto mode logs warnings without confirmation"
else
  fail "AC1: auto mode logs warnings without confirmation"
fi
run_status out st env IDD_AUTO_MODE=1 python3 "$SECSCAN" leak.env.txt
if [ "$st" = "1" ]; then
  pass "AC1: auto mode does not bypass a real-secret block"
else
  fail "AC1: auto mode does not bypass a real-secret block (got exit $st)"
fi

# Config-extensible patterns, via the config the skill already resolved.
run_status out st python3 "$SECSCAN" clean.txt \
  --config-json '{"config":{"security.extra_secret_file_pattern":"clean\\.txt$"}}'
if [ "$st" = "1" ]; then
  pass "AC1: security.extra_secret_file_pattern extends the filename rule"
else
  fail "AC1: security.extra_secret_file_pattern extends the filename rule (exit $st)"
fi
# Through the config FILE, the path every call site actually takes. A flag-only
# assertion would prove nothing about how the rules really get extended.
CFG="$TMP/cfgfile"
mkdir -p "$CFG"
printf 'security:\n  allow_pattern: "^leak\\\\.env\\\\.txt$"\n' > "$CFG/.gitissue.yml"
run_status out st python3 "$SECSCAN" leak.env.txt --config "$CFG/.gitissue.yml"
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey skipped)" = "1" ]; then
  pass "AC1: security.allow_pattern from .gitissue.yml excludes a path from every rule"
else
  fail "AC1: security.allow_pattern from .gitissue.yml excludes a path (exit $st)"
fi

# A config value containing a quote must be inert data, never shell syntax.
# This is the regression guard for the injection the config-file design removes.
printf 'security:\n  allow_pattern: "%s"\n' "'; touch $CFG/PWNED; echo '" \
  > "$CFG/evil.yml"
run_status out st python3 "$SECSCAN" clean.txt --config "$CFG/evil.yml"
if [ ! -e "$CFG/PWNED" ]; then
  pass "AC1: a quote-bearing security.* value cannot execute (no shell interpolation)"
else
  fail "AC1: a crafted security.* value executed a command — injection"
fi

printf 'security:\n  max_file_size_mb: "ten"\n' > "$CFG/badtype.yml"
run_status out st python3 "$SECSCAN" clean.txt --config "$CFG/badtype.yml"
[ "$st" = "3" ] && pass "AC1: a non-integer security.max_file_size_mb exits 3" \
                || fail "AC1: a non-integer security.max_file_size_mb exits 3 (got $st)"

run_status out st python3 "$SECSCAN" clean.txt --config "$CFG/.gitissue.yml" --no-config
[ "$st" = "0" ] && pass "AC1: --no-config ignores the config file" \
                || fail "AC1: --no-config ignores the config file (got $st)"

# Exit-code vocabulary: 2 usage, 3 invalid input.
run_status out st python3 "$SECSCAN"
[ "$st" = "2" ] && pass "AC1: no input source exits 2 (usage)" \
                || fail "AC1: no input source exits 2 (got $st)"
run_status out st python3 "$SECSCAN" clean.txt --staged
[ "$st" = "2" ] && pass "AC1: two input sources exit 2 (usage)" \
                || fail "AC1: two input sources exit 2 (got $st)"
printf 'security:\n  allow_pattern: "["\n' > "$CFG/badre.yml"
run_status out st python3 "$SECSCAN" clean.txt --config "$CFG/badre.yml"
[ "$st" = "3" ] && pass "AC1: an uncompilable security.* regex exits 3 (stop, not degrade)" \
                || fail "AC1: an uncompilable security.* regex exits 3 (got $st)"
run_status out st python3 "$SECSCAN" clean.txt --allow-pattern '['
[ "$st" = "3" ] && pass "AC1: an uncompilable --allow-pattern flag exits 3" \
                || fail "AC1: an uncompilable --allow-pattern flag exits 3 (got $st)"
run_status out st python3 "$SECSCAN" --config-json 'not json' clean.txt
[ "$st" = "3" ] && pass "AC1: unparsable --config-json exits 3" \
                || fail "AC1: unparsable --config-json exits 3 (got $st)"

# The path list may arrive on stdin — the pre-stage call shape.
run_status out st bash -c "printf 'clean.txt\nleak.env.txt\n' | python3 '$SECSCAN' --files-from -"
[ "$st" = "1" ] && pass "AC1: --files-from - reads the path list from stdin" \
                || fail "AC1: --files-from - reads the path list from stdin (exit $st)"

# ── Regressions: every one of these was a silent false negative ──────────────
# A scan that reports "clean" while a live key sits in the commit is the only
# failure mode of this script that matters, so each fix gets a pinned test.
REG="$TMP/reg"
mkdir -p "$REG"
(
  cd "$REG"
  git init -q -b main . >/dev/null 2>&1
  # Non-ASCII path: git quotes it as "conf\303\257gs/..." without -z, and the
  # escaped string names no file, so the content rule never ran.
  mkdir -p 'confïgs/deep'
  printf 'aws = %s\n' "$AWS_FIXTURE_KEY" > 'confïgs/deep/keys.txt'
  # One line of several MB: the head used to be discarded unscanned.
  python3 -c 'import sys;open("bundle.min.js","wb").write(b"var k=\""+sys.argv[1].encode()+b"\";" + b"a"*(3<<20))' "$AWS_FIXTURE_KEY"
  git add -A >/dev/null 2>&1
)

# `set -e` fires on a failing subshell, and a block verdict IS a non-zero exit,
# so every one of these captures the status explicitly.
reg_root=0
( cd "$REG" && python3 "$SECSCAN" --staged --quiet >/dev/null 2>&1 ) || reg_root=$?
reg_sub=0
( cd "$REG/confïgs" && python3 "$SECSCAN" --staged --quiet >/dev/null 2>&1 ) || reg_sub=$?
if [ "$reg_root" = "1" ] && [ "$reg_sub" = "1" ]; then
  pass "AC1: git-reported paths are resolved against the repo root, not the CWD"
else
  fail "AC1: scanning from a subdirectory misses files (root=$reg_root sub=$reg_sub)"
fi

blocked_paths=""
blocked_paths="$( cd "$REG" && python3 "$SECSCAN" --staged --quiet 2>/dev/null \
  | python3 -c 'import json,sys;print(" ".join(b["path"] for b in json.load(sys.stdin)["blocking"]))' )" || true
case "$blocked_paths" in
  *conf*gs/deep/keys.txt*) pass "AC1: a non-ASCII path is scanned (git -z, not core.quotePath)" ;;
  *) fail "AC1: a non-ASCII path is not scanned (got: $blocked_paths)" ;;
esac
case "$blocked_paths" in
  *bundle.min.js*) pass "AC1: a secret in the head of a multi-MB single line is found" ;;
  *) fail "AC1: a secret in the head of a multi-MB single line is missed (got: $blocked_paths)" ;;
esac

# A rename: `-z` porcelain emits `XY <new>\0<old>\0`, so the origin field must
# be consumed rather than read as a path of its own. The subtlest logic in the
# file, and silent if it regresses.
(
  cd "$REG"
  git -c user.email=t@t -c user.name=t commit -qm base >/dev/null 2>&1 || true
  printf 'k = %s\n' "$AWS_FIXTURE_KEY" > renamed_source.txt
  git add -A >/dev/null 2>&1
  git -c user.email=t@t -c user.name=t commit -qm add >/dev/null 2>&1
  git mv renamed_source.txt renamed_target.txt >/dev/null 2>&1
  git add -A >/dev/null 2>&1
)
rename_paths=""
rename_paths="$( cd "$REG" && python3 "$SECSCAN" --working-tree --quiet 2>/dev/null \
  | python3 -c 'import json,sys;d=json.load(sys.stdin);print(" ".join(b["path"] for b in d["blocking"]))' )" || true
case "$rename_paths" in
  *renamed_target.txt*) pass "AC1: a rename's new path is scanned (-z origin field consumed)" ;;
  *) fail "AC1: a rename's new path is not scanned (got: $rename_paths)" ;;
esac
case "$rename_paths" in
  *renamed_source.txt*) fail "AC1: a rename's origin field was misread as a live path" ;;
  *) pass "AC1: a rename's origin field is not misreported as a path" ;;
esac

# Non-UTF-8 on stdin must be exit 3, never exit 1 — exit 1 is the block verdict,
# so a crash there would read as "a secret was found" with no JSON to say which.
run_status out st bash -c "printf '\\xff\\xfe' | python3 '$SECSCAN' '$WORK/clean.txt' --config-json -"
[ "$st" = "3" ] && pass "AC1: non-UTF-8 on --config-json stdin exits 3, not the block code 1" \
                || fail "AC1: non-UTF-8 on --config-json stdin exits 3 (got $st)"

cd "$REPO_ROOT"

# ───────────────────────────────────────────────────────────
# T2 (AC2): gi-ci-wait — one JSON verdict, no per-poll tool calls
# ───────────────────────────────────────────────────────────
# `gh` is stubbed so the test never touches the network and can pin each
# verdict. The stub emits a scripted sequence of `gh pr checks --json` payloads.
STUB="$TMP/bin"
mkdir -p "$STUB"
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
# Emits $GH_FIXTURE, or the Nth line of $GH_SEQUENCE on the Nth call.
if [ -n "${GH_SEQUENCE:-}" ]; then
  n=0
  [ -f "$GH_COUNT_FILE" ] && n="$(cat "$GH_COUNT_FILE")"
  n=$((n + 1))
  echo "$n" > "$GH_COUNT_FILE"
  sed -n "${n}p" "$GH_SEQUENCE"
  exit 0
fi
printf '%s' "${GH_FIXTURE:-[]}"
STUBEOF
chmod +x "$STUB/gh"

# A PATH with python3 but deliberately no gh — the "cannot complete" degrade.
NOGH="$TMP/nogh"
mkdir -p "$NOGH"
ln -sf "$(command -v python3)" "$NOGH/python3"

GH_FIXTURE='[{"name":"build","state":"SUCCESS","bucket":"pass","link":"u"}]'
run_status out st env GH_FIXTURE="$GH_FIXTURE" PATH="$STUB:$PATH" \
  python3 "$CIWAIT" 42 --once
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey verdict)" = "pass" ]; then
  pass "AC2: all-green checks return verdict pass on exit 0"
else
  fail "AC2: all-green checks return verdict pass on exit 0 (exit $st)"
fi

GH_FIXTURE='[{"name":"build","state":"FAILURE","bucket":"fail","link":"u"}]'
run_status out st env GH_FIXTURE="$GH_FIXTURE" PATH="$STUB:$PATH" \
  python3 "$CIWAIT" 42 --once
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey verdict)" = "fail" ]; then
  pass "AC2: a failing check returns verdict fail on exit 0 (verdict, not status)"
else
  fail "AC2: a failing check returns verdict fail on exit 0 (exit $st)"
fi

GH_FIXTURE='[]'
run_status out st env GH_FIXTURE="$GH_FIXTURE" PATH="$STUB:$PATH" \
  python3 "$CIWAIT" 42 --once
if [ "$(printf '%s' "$out" | jkey verdict)" = "none" ]; then
  pass "AC2: no configured checks return verdict none"
else
  fail "AC2: no configured checks return verdict none"
fi

# Pending must stay pending — reporting a running check as clean is the failure
# that merges a broken PR.
GH_FIXTURE='[{"name":"build","state":"IN_PROGRESS","bucket":"pending","link":"u"}]'
run_status out st env GH_FIXTURE="$GH_FIXTURE" PATH="$STUB:$PATH" \
  python3 "$CIWAIT" 42 --once
if [ "$(printf '%s' "$out" | jkey verdict)" = "pending" ]; then
  pass "AC2: a still-running check returns verdict pending, never pass"
else
  fail "AC2: a still-running check returns verdict pending, never pass"
fi

# An unrecognized bucket is pending, not done — guessing "finished" about a
# state we do not model is the dangerous direction.
GH_FIXTURE='[{"name":"build","state":"WEIRD","bucket":"something-new","link":"u"}]'
run_status out st env GH_FIXTURE="$GH_FIXTURE" PATH="$STUB:$PATH" \
  python3 "$CIWAIT" 42 --once
if [ "$(printf '%s' "$out" | jkey verdict)" = "pending" ]; then
  pass "AC2: an unmodeled bucket is treated as pending, not as done"
else
  fail "AC2: an unmodeled bucket is treated as pending, not as done"
fi

# `none` is two different answers wearing one label, and telling them apart is a
# merge-safety property: a repository with no CI reports none forever, while a
# repository that *does* have CI also reports none for the seconds between a
# push and GitHub registering the run. Auto-pilot merges on none, so returning
# it from the first poll after a push merges a PR whose checks never ran.
run_status out st env GH_FIXTURE='[]' PATH="$STUB:$PATH" \
  python3 "$CIWAIT" 42 --once
if [ "$(printf '%s' "$out" | jkey none_confirmed)" = "False" ]; then
  pass "AC2: a single-poll none is not confirmed — one poll cannot tell the two apart"
else
  fail "AC2: --once reported none as confirmed, which is a mergeable verdict"
fi

run_status out st env GH_FIXTURE='[]' PATH="$STUB:$PATH" \
  python3 "$CIWAIT" 42 --interval 1 --timeout 30 --none-grace 2 --settle-window 1
if [ "$(printf '%s' "$out" | jkey verdict)" = "none" ] \
   && [ "$(printf '%s' "$out" | jkey none_confirmed)" = "True" ] \
   && [ "$(printf '%s' "$out" | jkey polls)" -ge 2 ]; then
  pass "AC2: none is confirmed only after the grace window stays empty"
else
  fail "AC2: none was confirmed without the grace window elapsing"
fi

# A transient empty snapshot after checks appeared must not be relabeled as
# confirmed no-CI. The latest empty snapshot is retained, but none_confirmed
# remains false because a check set was observed earlier.
SEQ_TERMINAL_EMPTY="$TMP/seq-terminal-empty"
{
  echo '[{"name":"build","state":"SUCCESS","bucket":"pass","link":"u"}]'
  echo '[]'
  echo '[]'
} > "$SEQ_TERMINAL_EMPTY"
rm -f "$TMP/count-terminal-empty"
run_status out st env GH_SEQUENCE="$SEQ_TERMINAL_EMPTY" GH_COUNT_FILE="$TMP/count-terminal-empty" \
  PATH="$STUB:$PATH" python3 "$CIWAIT" 42 --interval 1 --timeout 3 --none-grace 1 --settle-window 1
if [ "$(printf '%s' "$out" | jkey verdict)" = "none" ] \
   && [ "$(printf '%s' "$out" | jkey none_confirmed)" = "False" ]; then
  pass "AC2/#273: terminal-to-empty transition never confirms no CI"
else
  fail "AC2/#273: transient empty snapshot was treated as confirmed no CI"
fi

# The regression guard for the race itself: checks that register on the third
# poll must be waited for, not raced past.
SEQ_LATE="$TMP/seq-late"
{
  echo '[]'
  echo '[]'
  echo '[{"name":"build","state":"SUCCESS","bucket":"pass","link":"u"}]'
  echo '[{"name":"build","state":"SUCCESS","bucket":"pass","link":"u"}]'
} > "$SEQ_LATE"
rm -f "$TMP/count-late"
run_status out st env GH_SEQUENCE="$SEQ_LATE" GH_COUNT_FILE="$TMP/count-late" \
  PATH="$STUB:$PATH" python3 "$CIWAIT" 42 --interval 1 --timeout 30 --none-grace 10 --settle-window 1
if [ "$(printf '%s' "$out" | jkey verdict)" = "pass" ]; then
  pass "AC2: checks that register on a later poll are waited for, not raced past"
else
  fail "AC2: the wait returned before the checks registered — the merge race"
fi

# A terminal snapshot is not trusted until its normalized membership settles.
# The second poll adds a failing check; returning pass from poll one would
# recreate issue #273's early-verdict race.
SEQ_GROWING="$TMP/seq-growing"
{
  echo '[{"name":"lint","state":"SUCCESS","bucket":"pass","link":"u"}]'
  echo '[{"name":"lint","state":"SUCCESS","bucket":"pass","link":"u"},{"name":"security","state":"FAILURE","bucket":"fail","link":"u"}]'
  echo '[{"name":"lint","state":"SUCCESS","bucket":"pass","link":"u"},{"name":"security","state":"FAILURE","bucket":"fail","link":"u"}]'
} > "$SEQ_GROWING"
rm -f "$TMP/count-growing"
run_status out st env GH_SEQUENCE="$SEQ_GROWING" GH_COUNT_FILE="$TMP/count-growing" \
  PATH="$STUB:$PATH" python3 "$CIWAIT" 42 --interval 1 --timeout 10 --settle-window 1
if [ "$(printf '%s' "$out" | jkey verdict)" = "fail" ] \
   && [ "$(printf '%s' "$out" | jkey settled)" = "True" ]; then
  pass "AC2/#273: terminal verdict waits for a stable check set before returning"
else
  fail "AC2/#273: terminal verdict trusted a check set that was still growing"
fi

# A slow poll that crosses the timeout must not win over the deadline. This
# invokes the implementation directly with deterministic poll and clock hooks.
python3 - "$CIWAIT" <<'PY'
import importlib.util
import sys

path = sys.argv[1]
spec = importlib.util.spec_from_file_location("ciwait_timeout", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class Clock:
    def __init__(self):
        self.now = 0.0
    def __call__(self):
        return self.now

clock = Clock()
polls = iter([
    [{"name": "lint", "bucket": "pass"}],
])

def poll_once(_pr, _repo):
    clock.now = 11.0  # gh returned after the ten-second timeout
    return next(polls)

mod.poll_once = poll_once
result = mod.wait("42", None, interval=1, timeout=10, settle_window=0,
                  sleep=lambda _seconds: None, clock=clock)
assert result["verdict"] == "pending", result
assert result["settled"] is False, result
assert result["checks"] == [{"name": "lint", "bucket": "pass"}], result
print("pass: AC2/#273: timeout wins when a poll completes after deadline")
PY

# Exact-boundary timeout also wins over a zero-width settle window.
python3 - "$CIWAIT" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("ciwait_boundary", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
clock_now = [0.0]
def clock():
    return clock_now[0]
def poll_once(_pr, _repo):
    clock_now[0] = 10.0
    return [{"name": "lint", "bucket": "pass"}]
mod.poll_once = poll_once
result = mod.wait("42", None, interval=1, timeout=10, settle_window=0,
                  sleep=lambda _seconds: None, clock=clock)
assert result["verdict"] == "pending", result
assert result["settled"] is False, result
print("pass: AC2/#273: exact deadline wins over zero-width settlement")
PY

# A zero-width settle window still requires a second unchanged observation.
# The first green poll must not win before a newly registered failing check.
SEQ_ZERO_WINDOW="$TMP/seq-zero-window"
{
  echo '[{"name":"lint","state":"SUCCESS","bucket":"pass","link":"u"}]'
  echo '[{"name":"lint","state":"SUCCESS","bucket":"pass","link":"u"},{"name":"security","state":"FAILURE","bucket":"fail","link":"u"}]'
  echo '[{"name":"lint","state":"SUCCESS","bucket":"pass","link":"u"},{"name":"security","state":"FAILURE","bucket":"fail","link":"u"}]'
} > "$SEQ_ZERO_WINDOW"
rm -f "$TMP/count-zero-window"
run_status out st env GH_SEQUENCE="$SEQ_ZERO_WINDOW" GH_COUNT_FILE="$TMP/count-zero-window" \
  PATH="$STUB:$PATH" python3 "$CIWAIT" 42 --interval 1 --timeout 10 --settle-window 0
if [ "$(printf '%s' "$out" | jkey verdict)" = "fail" ] \
   && [ "$(printf '%s' "$out" | jkey settled)" = "True" ] \
   && [ "$(printf '%s' "$out" | jkey polls)" -ge 3 ]; then
  pass "AC2/#273: zero settle window still waits for a second terminal observation"
else
  fail "AC2/#273: zero settle window trusted the first terminal observation"
fi

# The whole wait happens in one invocation: several polls, one process, one
# verdict. That is the property that removes the per-poll agent tool call.
SEQ="$TMP/seq"
{
  echo '[{"name":"build","state":"IN_PROGRESS","bucket":"pending","link":"u"}]'
  echo '[{"name":"build","state":"IN_PROGRESS","bucket":"pending","link":"u"}]'
  echo '[{"name":"build","state":"SUCCESS","bucket":"pass","link":"u"}]'
  echo '[{"name":"build","state":"SUCCESS","bucket":"pass","link":"u"}]'
} > "$SEQ"
run_status out st env GH_SEQUENCE="$SEQ" GH_COUNT_FILE="$TMP/count" \
  PATH="$STUB:$PATH" python3 "$CIWAIT" 42 --interval 1 --timeout 30 --settle-window 1
polls="$(printf '%s' "$out" | jkey polls)"
if [ "$(printf '%s' "$out" | jkey verdict)" = "pass" ] && [ "$polls" -ge 4 ]; then
  pass "AC2: a multi-poll wait resolves inside one invocation ($polls polls, 1 call)"
else
  fail "AC2: a multi-poll wait resolves inside one invocation (verdict/polls wrong)"
fi

run_status out st python3 "$CIWAIT" abc
[ "$st" = "3" ] && pass "AC2: a non-numeric PR exits 3" \
                || fail "AC2: a non-numeric PR exits 3 (got $st)"
run_status out st env GH_FIXTURE='[]' PATH="$STUB:$PATH" python3 "$CIWAIT" 42 --interval 0
[ "$st" = "3" ] && pass "AC2: a non-positive interval exits 3" \
                || fail "AC2: a non-positive interval exits 3 (got $st)"
# No gh at all is the degrade path, not a stop.
run_status out st env PATH="$NOGH" python3 "$CIWAIT" 42 --once
[ "$st" = "4" ] && pass "AC2: a missing gh exits 4 (degrade to manual polling)" \
                || fail "AC2: a missing gh exits 4 (got $st)"

# A gh error with empty stdout must NOT be read as "no CI configured": that
# would let a caller merge a PR whose checks it never actually saw.
ERRSTUB="$TMP/errbin"
mkdir -p "$ERRSTUB"
printf '#!/bin/sh\necho "HTTP 502: Bad gateway" >&2\nexit 1\n' > "$ERRSTUB/gh"
chmod +x "$ERRSTUB/gh"
run_status out st env PATH="$ERRSTUB:$PATH" python3 "$CIWAIT" 42 --once
[ "$st" = "4" ] && pass "AC2: a gh API error exits 4, never verdict none with exit 0" \
                || fail "AC2: a gh API error exits 4 (got $st, out=$out)"

# ───────────────────────────────────────────────────────────
# T3 (AC3): gi-issue — TTL cache, keyed by issue AND field set
# ───────────────────────────────────────────────────────────
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
# Counts calls so a cache hit is provable, and echoes the requested fields.
if [ -n "${GH_COUNT_FILE:-}" ]; then
  n=0
  [ -f "$GH_COUNT_FILE" ] && n="$(cat "$GH_COUNT_FILE")"
  echo $((n + 1)) > "$GH_COUNT_FILE"
fi
printf '%s' "${GH_FIXTURE:-}"
STUBEOF
chmod +x "$STUB/gh"

CACHE="$TMP/cache"
COUNT="$TMP/issue-count"
: > "$COUNT"
export_env=(GH_FIXTURE='{"number":7,"title":"Sample"}' GH_COUNT_FILE="$COUNT")

run_status out st env "${export_env[@]}" PATH="$STUB:$PATH" \
  python3 "$GIISSUE" 7 --fields number,title --cache-dir "$CACHE"
first_cached="$(printf '%s' "$out" | jkey cached)"
run_status out st env "${export_env[@]}" PATH="$STUB:$PATH" \
  python3 "$GIISSUE" 7 --fields number,title --cache-dir "$CACHE"
second_cached="$(printf '%s' "$out" | jkey cached)"
calls="$(cat "$COUNT")"
if [ "$first_cached" = "False" ] && [ "$second_cached" = "True" ] && [ "$calls" = "1" ]; then
  pass "AC3: a repeat read is served from cache (1 gh call for 2 reads)"
else
  fail "AC3: a repeat read is served from cache (cached=$first_cached/$second_cached, calls=$calls)"
fi

# A different field set must miss: serving a body-less payload to a caller that
# asked for the body is worse than a second network call.
run_status out st env "${export_env[@]}" PATH="$STUB:$PATH" \
  python3 "$GIISSUE" 7 --fields body --cache-dir "$CACHE"
if [ "$(printf '%s' "$out" | jkey cached)" = "False" ]; then
  pass "AC3: the cache key includes the field set (a wider read is a miss)"
else
  fail "AC3: the cache key includes the field set (a wider read wrongly hit)"
fi

run_status out st env "${export_env[@]}" PATH="$STUB:$PATH" \
  python3 "$GIISSUE" 7 --fields number,title --cache-dir "$CACHE" --refresh
if [ "$(printf '%s' "$out" | jkey cached)" = "False" ]; then
  pass "AC3: --refresh bypasses a fresh entry (the post-edit read path)"
else
  fail "AC3: --refresh bypasses a fresh entry"
fi

run_status out st env "${export_env[@]}" PATH="$STUB:$PATH" \
  python3 "$GIISSUE" 7 --fields number,title --cache-dir "$CACHE" --ttl 0
if [ "$(printf '%s' "$out" | jkey cached)" = "False" ]; then
  pass "AC3: --ttl 0 disables the cache entirely"
else
  fail "AC3: --ttl 0 disables the cache entirely"
fi

run_status out st env "${export_env[@]}" PATH="$STUB:$PATH" \
  python3 "$GIISSUE" 7 --cache-dir "$CACHE" --invalidate
if [ "$(printf '%s' "$out" | jkey dropped)" -ge 1 ]; then
  pass "AC3: --invalidate drops every entry for the issue"
else
  fail "AC3: --invalidate drops every entry for the issue"
fi

run_status out st python3 "$GIISSUE" xyz
[ "$st" = "3" ] && pass "AC3: a non-numeric issue number exits 3" \
                || fail "AC3: a non-numeric issue number exits 3 (got $st)"
run_status out st python3 "$GIISSUE" 7 --fields 'bad-field!'
[ "$st" = "3" ] && pass "AC3: a malformed field name exits 3" \
                || fail "AC3: a malformed field name exits 3 (got $st)"
run_status out st env PATH="$NOGH" python3 "$GIISSUE" 7 --cache-dir "$TMP/nope"
[ "$st" = "4" ] && pass "AC3: a missing gh exits 4 (degrade to gh issue view)" \
                || fail "AC3: a missing gh exits 4 (got $st)"

# ───────────────────────────────────────────────────────────
# T4 (AC4): gi-branch — names that match the conventions document
# ───────────────────────────────────────────────────────────
branch_of() {
  python3 "$GIBRANCH" "$@" 2>/dev/null | jkey branch
}

check_branch() {
  local expected="$1"; shift
  local got
  got="$(branch_of "$@")"
  if [ "$got" = "$expected" ]; then
    pass "AC4: $expected"
  else
    fail "AC4: expected $expected, got $got"
  fi
}

check_branch "feat/15-add-dark-mode-toggle" 15 --title "Add dark mode toggle" --type feature
check_branch "fix/42-mobile-auth-redirect-loop" 42 --title "Fix mobile auth redirect loop" --type bug
check_branch "refactor/8-clean-up-auth-middleware" 8 --title "Clean up auth middleware" --type improvement
check_branch "docs/23-update-api-reference-docs" 23 --title "Update API reference docs" --type documentation
# A redundant type label in the title must not be repeated in the slug.
check_branch "fix/42-app-crashes-on-login" 42 --title "Bug: App crashes on login" --type bug
# Custom prefix: verbatim, then {N}-{slug} — no separator the user did not write.
check_branch "issue-42-add-dark-mode" 42 --title "Add dark mode" --prefix "issue-"
check_branch "team/42-add-dark-mode" 42 --title "Add dark mode" --prefix "team/"

# Every "auto" name must satisfy the repository's own branch grammar. Sourcing
# the regex from idd-lint.py rather than restating it is the point: the two
# cannot silently drift.
python3 - "$GIBRANCH" "$REPO_ROOT/scripts/idd-lint.py" <<'PY' > "$TMP/branch-report"
import json, re, subprocess, sys
script, lint = sys.argv[1], sys.argv[2]
lint_src = open(lint, encoding="utf-8").read()
m = re.search(r'^BRANCH_RE = re\.compile\(r"([^"]+)"\)', lint_src, re.M)
if not m:
    print("FAIL|AC4: BRANCH_RE not found in idd-lint.py")
    raise SystemExit
lint_re = re.compile(m.group(1))

cases = [
    (1, "Add dark mode toggle", "feature"),
    (999, "A" * 200, "bug"),
    (42, "Ship security-scan, CI-wait, issue-cache, and branch-name scripts", "feature"),
    (7, "!!!", "chore"),
    (12, "  spaces   and---dashes  ", "improvement"),
    (5, "Emoji only 🎉🎉", "test"),
]
bad = []
for number, title, kind in cases:
    out = subprocess.run(
        [sys.executable, script, str(number), "--title", title, "--type", kind],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        bad.append(f"{title!r}: exit {out.returncode}")
        continue
    data = json.loads(out.stdout)
    branch = data["branch"]
    if not lint_re.match(branch):
        bad.append(f"{title!r} -> {branch!r} fails idd-lint BRANCH_RE")
    elif len(branch) >= 50:
        bad.append(f"{title!r} -> {branch!r} is {len(branch)} chars (>= 50)")
    elif not data["valid"]:
        bad.append(f"{title!r} -> {branch!r} self-reports valid=false")

if bad:
    for entry in bad:
        print(f"FAIL|AC4: {entry}")
else:
    print("PASS|AC4: every auto-prefix name satisfies idd-lint's BRANCH_RE and the 50-char cap")
PY
while IFS='|' read -r verdict label; do
  [ -n "$verdict" ] || continue
  if [ "$verdict" = "PASS" ]; then pass "$label"; else fail "$label"; fi
done < "$TMP/branch-report"

run_status out st python3 "$GIBRANCH" abc --type bug
[ "$st" = "3" ] && pass "AC4: a non-numeric issue number exits 3" \
                || fail "AC4: a non-numeric issue number exits 3 (got $st)"
# '²'.isdigit() is true but int('²') raises; the guard must use isdecimal(),
# or the ValueError escapes main() as exit 1 with a traceback.
for script in "$GIBRANCH" "$GIISSUE" "$CIWAIT"; do
  run_status out st python3 "$script" '²'
  if [ "$st" = "3" ]; then
    pass "AC4: $(basename "$script") rejects a Unicode digit with exit 3"
  else
    fail "AC4: $(basename "$script") on a Unicode digit exits $st, expected 3"
  fi
done
run_status out st python3 "$GIBRANCH" 42 --title x --type spike
[ "$st" = "3" ] && pass "AC4: an unmapped issue type exits 3" \
                || fail "AC4: an unmapped issue type exits 3 (got $st)"
if [ "$(branch_of 42 --title x --type spike --type-map 'spike=chore')" = "chore/42-x" ]; then
  pass "AC4: --type-map extends the type→prefix mapping"
else
  fail "AC4: --type-map extends the type→prefix mapping"
fi

# ───────────────────────────────────────────────────────────
# T5 (AC1/AC5): wiring — the built skills call the scripts and keep a fallback
# ───────────────────────────────────────────────────────────
# Read the built skills, not the sources: what ships is what runs.
expect_bundled() {
  local skill="$1" script="$2"
  if [ -f "$SKILLS/$skill/references/scripts/$script" ]; then
    pass "AC1: $skill bundles $script"
  else
    fail "AC1: $skill bundles $script"
  fi
}
expect_bundled issue-resolver gi-secscan.py
expect_bundled issue-resolver gi-branch.py
expect_bundled issue-resolver gi-issue.py
expect_bundled issue-pr-review gi-secscan.py
expect_bundled issue-pr-review gi-ci-wait.py
expect_bundled issue-pr-review gi-issue.py
expect_bundled auto-pilot gi-ci-wait.py
expect_bundled auto-pilot gi-issue.py
expect_bundled issue-analysis gi-issue.py
expect_bundled issue-creator gi-issue.py

# Every commit/push site now names the script. The security-scan sites are the
# ones AC1 is about: the resolver's pre-push pass and pr-review's auto-fix commit.
expect_grep() {
  local label="$1" pattern="$2" file="$3"
  if grep -q -- "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label"
  fi
}
expect_grep "AC1: resolver's pre-push scan calls gi-secscan" \
  "references/scripts/gi-secscan.py" "$SKILLS/issue-resolver/SKILL.md"
expect_grep "AC1: pr-review's auto-fix commit calls gi-secscan" \
  "references/scripts/gi-secscan.py" "$SKILLS/issue-pr-review/SKILL.md"
expect_grep "AC1: the implementer receives the scan path as a spawn variable" \
  "secscan_script" "$SKILLS/issue-resolver/references/pipeline-steps.md"
expect_grep "AC1: the fixer receives the scan path as a spawn variable" \
  "secscan_script" "$SKILLS/issue-pr-review/references/review-loop-mechanics.md"
expect_grep "AC2: pr-review Step 5 calls gi-ci-wait" \
  "references/scripts/gi-ci-wait.py" "$SKILLS/issue-pr-review/SKILL.md"
expect_grep "AC3: the resolver's Step 0a fetch calls gi-issue" \
  "references/scripts/gi-issue.py" "$SKILLS/issue-resolver/SKILL.md"
expect_grep "AC4: the resolver derives the branch name with gi-branch" \
  "references/scripts/gi-branch.py" "$SKILLS/issue-resolver/SKILL.md"

# An agent prompt renders its references as absolute URLs, so it must NOT carry
# a skill-relative script path — that is why the spawn variables above exist.
for agent in implementer fixer; do
  f="$SKILLS/issue-resolver/references/agents/$agent.md"
  [ -f "$f" ] || f="$SKILLS/issue-pr-review/references/agents/$agent.md"
  if [ -f "$f" ] && grep -q "references/scripts/" "$f"; then
    fail "AC1: $agent.md must not cite a skill-relative script path (issue #245)"
  else
    pass "AC1: $agent.md cites no skill-relative script path"
  fi
done

# AC5: every replaced procedure survives as a documented fallback.
expect_grep "AC5: the security scan keeps its Primary Pattern fallback" \
  "Primary Pattern" "$SKILLS/issue-resolver/references/docs/pre-commit-security.md"
expect_grep "AC5: the resolver keeps a gh issue view fallback" \
  "gh issue view" "$SKILLS/issue-resolver/SKILL.md"
# The issue-pr-review fallback must preserve the waiter's merge-safety contract,
# not merely mention a generic status poll.
PR_CI_FALLBACK="$SKILLS/issue-pr-review/references/prepass-tests-ci-mechanics.md"
if grep -qF '**Manual fallback (same merge-safe contract).' "$PR_CI_FALLBACK" \
  && grep -qF 'gh pr view {N} --json headRefOid,statusCheckRollup' "$PR_CI_FALLBACK" \
  && grep -qF 'non-empty rollup has ever appeared' "$PR_CI_FALLBACK" \
  && grep -qF 'normalized check-name' "$PR_CI_FALLBACK" \
  && grep -qF 'none-grace' "$PR_CI_FALLBACK" \
  && grep -qF 're-read `headRefOid`' "$PR_CI_FALLBACK" \
  && grep -qF 'leaves the PR open' "$PR_CI_FALLBACK"; then
  pass "AC5/#273: pr-review manual fallback enforces rollup, stability, none-grace, head binding, and leave-open semantics"
else
  fail "AC5/#273: pr-review manual fallback omits one or more merge-safety invariants"
fi
expect_grep "AC5: the branch rules remain applicable by hand" \
  "Deriving the Short Description" "$SKILLS/issue-resolver/references/docs/naming-conventions.md"
expect_grep "AC5: auto-pilot keeps the manual statusCheckRollup poll" \
  "statusCheckRollup" "$SKILLS/auto-pilot/references/examples.md"

# A block must never be swallowed by the degrade path — every security-scan call
# site has to say so explicitly, or an agent will read exit 1 as "fall back".
for f in "$SKILLS/issue-resolver/SKILL.md" "$SKILLS/issue-pr-review/SKILL.md"; do
  if grep -qi "exit 1 is\|Exit 1 is" "$f"; then
    pass "AC1: $(basename "$(dirname "$f")") states that exit 1 blocks rather than degrades"
  else
    fail "AC1: $(basename "$(dirname "$f")") does not state that exit 1 blocks"
  fi
done

# A --staged scan must read the bytes `git commit` will write, not the file on
# disk. They diverge as soon as a path is staged and then edited, and scanning
# the working-tree copy reports clean over a blob that still carries the key —
# the one failure mode of a security gate that matters.
STAGEDIR="$TMP/staged-blob"
mkdir -p "$STAGEDIR"
(
  cd "$STAGEDIR"
  git init -q .
  git config user.email t@example.com
  git config user.name t
  printf 'id=%s\n' "$AWS_FIXTURE_KEY" > secret.txt
  git add secret.txt
  printf 'id=REDACTED\n' > secret.txt   # working tree now clean, blob is not
) >/dev/null 2>&1
run_status out st sh -c "cd '$STAGEDIR' && python3 '$SECSCAN' --staged --quiet"
if [ "$st" = "1" ]; then
  pass "AC1: --staged blocks on the staged blob after the working tree was cleaned"
else
  fail "AC1: --staged missed a secret in the staged blob (exit $st) — it scanned the working tree"
fi

# The converse must hold too, or the gate blocks on bytes nobody is committing.
CONVERSE="$TMP/staged-converse"
mkdir -p "$CONVERSE"
(
  cd "$CONVERSE"
  git init -q .
  git config user.email t@example.com
  git config user.name t
  printf 'id=clean\n' > f.txt
  git add f.txt
  printf 'id=%s\n' "$AWS_FIXTURE_KEY" > f.txt   # unstaged edit, not being committed
) >/dev/null 2>&1
run_status out st sh -c "cd '$CONVERSE' && python3 '$SECSCAN' --staged --quiet"
if [ "$st" != "1" ]; then
  pass "AC1: --staged ignores an unstaged edit that is not being committed"
else
  fail "AC1: --staged blocked on working-tree bytes that are not staged"
fi
run_status out st sh -c "cd '$CONVERSE' && python3 '$SECSCAN' --working-tree --quiet"
[ "$st" = "1" ] && pass "AC1: --working-tree still blocks on the file on disk" \
                || fail "AC1: --working-tree missed a secret on disk (exit $st)"

# A staged deletion has no blob to read; it must not crash or be misreported.
DELDIR="$TMP/staged-delete"
mkdir -p "$DELDIR"
(
  cd "$DELDIR"
  git init -q .
  git config user.email t@example.com
  git config user.name t
  echo hello > a.txt
  git add a.txt
  git commit -qm init
  git rm -q a.txt
) >/dev/null 2>&1
run_status out st sh -c "cd '$DELDIR' && python3 '$SECSCAN' --staged --quiet"
[ "$st" = "0" ] || [ "$st" = "1" ] && pass "AC1: a staged deletion scans without error" \
                                   || fail "AC1: a staged deletion exited $st"

# A filename is attacker-controlled on a branch under review, and a space is a
# legal filename character. Normalising the path git reported renames it: the
# scan then reads a different file's bytes, or none, and reports clean either
# way. Both shapes below returned exit 0 over a live key before this was fixed.
WS="$TMP/ws-paths"
mkdir -p "$WS"
(
  cd "$WS"
  git init -q .
  git config user.email t@example.com
  git config user.name t
  printf 'id=%s\n' "$AWS_FIXTURE_KEY" > " lead.txt"      # sibling exists, clean
  printf 'clean\n' > "lead.txt"
  printf 'id=%s\n' "$AWS_FIXTURE_KEY" > " solo.txt"      # no sibling at all
  git add -A
) >/dev/null 2>&1
run_status out st sh -c "cd '$WS' && python3 '$SECSCAN' --staged --quiet"
if [ "$st" = "1" ]; then
  pass "AC1: a staged path with leading whitespace is scanned, not renamed"
else
  fail "AC1: a whitespace-bearing staged path passed the gate (exit $st)"
fi
run_status out st sh -c "cd '$WS' && python3 '$SECSCAN' --working-tree --quiet"
[ "$st" = "1" ] && pass "AC1: --working-tree scans whitespace-bearing paths too" \
                || fail "AC1: --working-tree skipped a whitespace-bearing path (exit $st)"

# A carriage return is as legal in a filename as a space, and `text=True` on the
# git read would translate it to a newline — renaming the path before it is used.
CR="$TMP/cr-paths"
mkdir -p "$CR"
(
  cd "$CR"
  git init -q .
  git config user.email t@example.com
  git config user.name t
  printf 'id=%s\n' "$AWS_FIXTURE_KEY" > "$(printf 'solo.txt\r')"
  printf 'id=%s\n' "$AWS_FIXTURE_KEY" > "$(printf 'cr.txt\r')"
  printf 'clean\n' > cr.txt
  git add -A
) >/dev/null 2>&1
run_status out st sh -c "cd '$CR' && python3 '$SECSCAN' --staged --quiet"
[ "$st" = "1" ] && pass "AC1: a filename containing a carriage return is scanned as named" \
                || fail "AC1: a carriage-return filename passed the gate (exit $st)"

# A filename is a byte string, not text. An undecodable byte must round-trip
# (os.fsdecode/surrogateescape) — `errors="replace"` would turn it into U+FFFD
# and name a different file, and a strict decode would abort the whole scan. A
# name that is only spaces is a legal file too.
BYTES="$TMP/byte-paths"
mkdir -p "$BYTES"
(
  cd "$BYTES"
  git init -q .
  git config user.email t@example.com
  git config user.name t
  python3 -c "
import os, sys
key = os.environ['AWS_FIXTURE_KEY']
for name in (b'notes\xff.txt', b'bad\xc3(name.txt', b'   '):
    open(os.fsdecode(name), 'w').write('id=' + key + chr(10))
open('readme.md', 'w').write('clean' + chr(10))
"
  git add -A
) >/dev/null 2>&1
for mode in --staged --working-tree; do
  run_status out st sh -c "cd '$BYTES' && python3 '$SECSCAN' $mode --quiet"
  if [ "$st" = "1" ]; then
    pass "AC1: $mode scans undecodable and whitespace-only filenames"
  else
    fail "AC1: $mode passed a secret in an undecodable filename (exit $st)"
  fi
done
# The verdict must still be machine-readable with such a path in it.
run_status out st sh -c "cd '$BYTES' && python3 '$SECSCAN' --staged --quiet"
if printf '%s' "$out" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "AC1: the JSON verdict stays parsable with a surrogate-escaped path"
else
  fail "AC1: a surrogate-escaped path produced unparsable JSON"
fi

# Each mode must read the bytes it is about to ship, not whatever is on disk.
# --range is the pre-push gate: the branch tip is what `git push` sends, so
# committing a key and then tidying the working copy must still block.
RANGEDIR="$TMP/range-mode"
mkdir -p "$RANGEDIR"
(
  cd "$RANGEDIR"
  git init -q -b feat .
  git config user.email t@example.com
  git config user.name t
  echo base > x.txt
  git add -A
  git commit -qm base
  git branch main-base
  printf 'aws_key = "%s"\n' "$AWS_FIXTURE_KEY" > deploy.py
  git add -A
  git commit -qm 'feat: deploy'
  printf 'aws_key = os.environ["AWS_KEY"]\n' > deploy.py   # tidy, not committed
) >/dev/null 2>&1
run_status out st sh -c "cd '$RANGEDIR' && python3 '$SECSCAN' --range main-base --quiet"
if [ "$st" = "1" ]; then
  pass "AC1: --range scans the committed blob, not the tidied working copy"
else
  fail "AC1: --range passed a secret that is committed and about to be pushed (exit $st)"
fi

# `git status --porcelain` collapses a new subtree to `?? a/`, which is not a
# file: every path under it is skipped, and counted, and reported clean.
UNTRACKED="$TMP/untracked-dir"
mkdir -p "$UNTRACKED"
(
  cd "$UNTRACKED"
  git init -q -b work .
  git config user.email t@example.com
  git config user.name t
  git commit -q --allow-empty -m init
  mkdir -p a/b/c
  printf 'id=%s\n' "$AWS_FIXTURE_KEY" > a/b/c/.env
) >/dev/null 2>&1
run_status out st sh -c "cd '$UNTRACKED' && python3 '$SECSCAN' --working-tree --quiet"
if [ "$st" = "1" ]; then
  pass "AC1: --working-tree descends into an untracked directory"
else
  fail "AC1: an untracked directory hid a secret from --working-tree (exit $st)"
fi

# The repository root is a path too. Stripping trailing whitespace off
# `rev-parse --show-toplevel` points `base` at a directory that does not exist,
# so every content and size rule misses — on a git-sourced list, which raises no
# unreadable-path warning either. The same silent pass, one level above the file.
for suffix in " " "$(printf '\r')" "$(printf '\t')"; do
  ROOTDIR="$TMP/root-ws/dir$suffix"
  mkdir -p "$ROOTDIR"
  (
    cd "$ROOTDIR"
    git init -q .
    git config user.email t@example.com
    git config user.name t
    printf 'id=%s\n' "$AWS_FIXTURE_KEY" > secret.txt
    git add -A
  ) >/dev/null 2>&1
  ok=1
  for mode in --staged --working-tree; do
    run_status out st sh -c "cd \"$ROOTDIR\" && python3 '$SECSCAN' $mode --quiet"
    [ "$st" = "1" ] || ok=0
  done
  mkdir -p "$ROOTDIR/sub"
  run_status out st sh -c "cd \"$ROOTDIR/sub\" && python3 '$SECSCAN' --staged --quiet"
  [ "$st" = "1" ] || ok=0
  if [ "$ok" = "1" ]; then
    pass "AC1: a repo root ending in whitespace still scans (suffix $(printf '%s' "$suffix" | od -An -c | tr -d ' '))"
  else
    fail "AC1: a repo root ending in whitespace skipped every content rule"
  fi
done

# A caller-supplied list has no git guarantee behind it, so a path that resolves
# to nothing must be visible rather than counted as scanned and clean.
UL="$TMP/unreadable-list"
mkdir -p "$UL"
printf 'no-such-file.txt\n' > "$UL/list.txt"
run_status out st sh -c "cd '$UL' && python3 '$SECSCAN' --files-from list.txt --quiet"
if printf '%s' "$out" | grep -q 'unreadable-path'; then
  pass "AC1: a listed path that cannot be read is reported, not silently skipped"
else
  fail "AC1: an unreadable listed path was reported as a clean scan"
fi

# A binary blob larger than the pipe buffer is decided by the 8 KiB sniff, so
# the reader stops early and git dies of EPIPE. Reading that non-zero status as
# "no blob" silently drops the size rule for the staged bytes.
BIN="$TMP/big-binary"
mkdir -p "$BIN"
(
  cd "$BIN"
  git init -q .
  git config user.email t@example.com
  git config user.name t
  python3 -c "open('big.bin','wb').write(b'\x00\x01\x02' + bytes(12 * 1024 * 1024))"
  git add big.bin
  rm big.bin        # staged only: the size must come from the index, not disk
) >/dev/null 2>&1
run_status out st sh -c "cd '$BIN' && python3 '$SECSCAN' --staged --quiet"
if printf '%s' "$out" | grep -q 'large-file'; then
  pass "AC1: the size rule reads the staged blob for a binary file"
else
  fail "AC1: a 12 MB staged binary blob produced no large-file warning"
fi

# --- Call-site injection lint (all seven shared scripts) ---------------------
#
# Two command injections shipped in this branch one review cycle apart, both of
# the same shape: an untrusted value pasted into a shell word on a script's
# command line. A blocklist of the flag names those two used would not have
# caught either one before it was written, so this lint is an ALLOWLIST: every
# `{placeholder}` on a shared-script command line must be named below with a
# reason it cannot carry attacker text. A new placeholder fails until someone
# adds it and says why — that is what closes the class by construction rather
# than patching it twice.
#
# Three deliberate choices, each closing a bypass that was demonstrated against
# an earlier draft of this lint:
#   * A call is recognized by `python3 <anything>` where the argument is a
#     gi-*.py path OR a {placeholder} path — `python3 {secscan_script} --staged`
#     in the shared agents is a real invocation and must be linted.
#   * Markdown fence state is not tracked at all. A fence toggle can be lost to a
#     line continuation, and `~~~` and 4-space-indented blocks are code too, so
#     any logical line carrying a call is inspected, narrowed to the backtick
#     span when the line has one.
#   * Logical lines are joined across `\` and trailing `|`, so a flag or a
#     `printf` upstream of the pipe cannot hide on an adjacent line. A heredoc on
#     a call line is refused outright — its body is unreachable from here.
#
# Issue #278 hardened three more properties, each after a mutant walked through
# the previous shape:
#   * The scan is over every file the repository *tracks*, not over a list of
#     four roots. A call site in a file nobody thought to list — the repo root,
#     a `.yml` template — used to be invisible.
#   * The non-vacuity guard is per script, and it is a pinned *count*. The old
#     aggregate `checked >= 25` (currently 76) stayed satisfied when one of a
#     script's two call sites was deleted.
#   * A command substitution counts wherever it sits, quoted or not — quoting
#     stops word-splitting, not `$(gh issue view …)` pasting a reporter-written
#     title onto the line. The one exception is the substitution that *contains*
#     the call, which is the documented capture idiom
#     `body="$(python3 …gi-issue.py …)"` and puts nothing on any command line.
python3 - "$REPO_ROOT" <<'PY' > "$TMP/injection-report"
import pathlib, re, subprocess, sys

root = pathlib.Path(sys.argv[1])
# Every file the repository ships, minus the build output (`skills/`,
# `dist/`), the vendored copy (`.pi/`), and this suite's own fixtures.
SKIP_PREFIXES = ("skills/", "dist/", ".pi/", "tests/")
SCAN_SUFFIXES = (".md", ".yml", ".yaml", ".json", ".txt")
SCRIPT_NAME = re.compile(r"gi-[a-z0-9-]+\.py")
# Pinned per script: "at least one call site somewhere" stayed true when one
# of two sites was deleted. A count that moves is a contract change and has
# to be an explicit edit here.
EXPECTED_SITES = {
    # 3 since issue #260: /auto-pilot parallel worktree prep also derives the
    # lane branch via gi-branch.py (beside the two issue-resolver sites).
    "gi-branch.py": 3, "gi-ci-wait.py": 4, "gi-config.py": 6,
    # 15 since issue #258: /auto-pilot Step 1.2b fetches the picked issue's
    # record on demand, because Phase 1's bulk list no longer carries `body`.
    # 14 since issue #285: the dependency-parsing step in
    # /auto-pilot's phases.md no longer re-reads the body it is already
    # holding — Step 1.2b's resolution-boundary snapshot is parsed as data on
    # stdin instead, so that `--fields body` re-read site is gone by design.
    # 13 since issue #296: pr-review's Depth gate reads the `Effort` band out of
    # `linked_issue_snapshot` — the record SKILL.md already retained at the
    # review boundary — so review-loop-mechanics.md no longer restates the fetch
    # it had inherited from before that boundary existed.
    "gi-deps.py": 1, "gi-issue.py": 13,
    # 4 since issue #260: parallel failed-lane quarantine and the serialized
    # drain both call --append-once, beside the legacy --append and the
    # --failure-streak read from issue #259.
    # 5 since issue #261: the behavioral eval grader invokes gi-runlog.py.
    "gi-model-cache.py": 2, "gi-runlog.py": 5, "gi-secscan.py": 4,
    "gi-stack-detect.py": 1, "gi-triage-graph.py": 2,
}
# A call is any mention of a shared script by filename, however it is launched
# (python3, python3.11, uv run, a bare ./path relying on the exec bit), plus the
# indirect form where the *script path itself* is a placeholder — `python3
# {secscan_script} --staged` in the shared agents is a real invocation.
_LAUNCH = r"(?:python[0-9.]*|uv\s+run|\"?\$\{?\w+\}?\"?)"
CALL = re.compile(
    # launched by an interpreter, whatever its name or version, and with any
    # a few of the interpreter's own words in between — `python3 -X utf8 …`,
    # `uv run --no-project …` — which must not hide the call
    _LAUNCH + r"(?:\s+\S+){0,4}?\s+\S*gi-[a-z0-9-]+\.py"
    # or executed directly off the exec bit
    r"|\./\S*gi-[a-z0-9-]+\.py"
    # or the indirect form, where the script path is itself a placeholder —
    # `python3 {secscan_script} --staged` in the shared agents is a real call
    r"|" + _LAUNCH + r"(?:\s+\S+){0,4}?\s+\S*\{[^{}]+\}"
)

# Placeholders permitted on a shared-script command line, and why each is safe.
ALLOWED = {
    "{N}": "issue/PR number — an integer",
    "{n}": "loop-controlled integer — an issue/PR number, or a retry attempt",
    "{issue_number}": "integer",
    "{pr_number}": "integer",
    "{linked_issue}": "integer",
    "{parent}": "integer",
    "{run_id}": "CI run id — an integer from the GitHub API",
    "{type}": "one of six literals the skill classifies, never free text",
    "{secscan_script}": "absolute path bound by the orchestrating skill",
    "{security_convention}": "bundled doc path bound by the orchestrating skill",
    "{review.ci_poll_interval}": "gi-config validates it against an int default",
    "{review.ci_timeout}": "gi-config validates it against an int default",
    "{autopilot.quarantine_after}": "gi-config validates it against an int default",
    "{autopilot.max_runtime_minutes}": "gi-config validates it against an int default",
    # Issue #259. `started_at` is neither an --init key nor a --update key, so no
    # caller ever supplies it: gi-state writes it from its own UTC clock. The
    # file is still on disk and hand-editable, so the call site re-checks the
    # YYYY-MM-DDTHH:MM:SSZ form before substituting — the same
    # check-before-you-substitute rule Step 1.0 applies to current.branch, the
    # only other recorded field that reaches a shell word.
    "{run_state.started_at}": "script-written UTC stamp, re-checked at the call site",
    "{budget_deadline_epoch}": "integer epoch the loop computes itself; 0 when unbounded",
    "{reset_epoch}": "integer epoch — the .rate.reset field of the rate_limit payload",
}
# Placeholder styles the skills actually use. `{...}` must hold at least one
# non-space character, so `find -exec … {} \;` is not a placeholder, while
# `{ padded }` still is. `<name>` and `[name]` are constrained to identifiers so
# a redirection, a glob range, or a markdown link is not mistaken for one.
# `${VAR}` is a shell expansion, not a paste — VAR checks it.
PLACEHOLDER = re.compile(
    # An identifier in braces. Deliberately not "any braces": `jq '{verdict:
    # .verdict}'`, `awk '{print $1}'` and a regex `{20,}` are not placeholders,
    # and flagging them would make the lint something people route around.
    r"(?<!\$)\{\s*[A-Za-z_][\w.-]*\s*\}"
    # <NAME>: an angle-bracketed identifier is never shell syntax, so any
    # length counts — `<key>` is as much a placeholder as `<FILE-LIST>`.
    r"|<[A-Za-z_][\w-]*>"
    # `[name]` — added in issue #278, where it was one of five mutants that
    # walked through. The earlier draft left the style out because a square
    # bracket is a glob range and a regex character class before it is ever a
    # placeholder, and the documented `--extra-secret-value-pattern` examples
    # contain `[A-Z0-9]`. Narrowing the rule to a *lowercase* identifier of two
    # or more characters separates the two: `[A-Z0-9]` is uppercase, `[e]dit`
    # and `[Y/n]` are one character or not identifiers, and `[issue_title]` is
    # caught. Verified against the whole corpus — it adds no finding today.
    r"|\[[a-z_][a-z0-9_.-]+\]"
)

# Shell variables permitted on a shared-script command line, and why each is
# inert. Quoting stops word-splitting, not the value itself from becoming an
# argument, so the allowlist is about *provenance*: every entry is either a
# path the skill composed, a name a script derived, or a value that reaches the
# script on stdin rather than on the command line.
ALLOWED_VARS = {
    "$skill_dir": "path the skill resolves from its own SKILL.md dirname",
    "$wt_dir": "worktree path the skill composes itself",
    "$base": "base branch name read from the repo, never reporter text",
    "${base}": "base branch name read from the repo, never reporter text",
    "$branch_name": "derived by gi-branch.py --from-issue, which sanitizes it",
    "$run_json": "run-log JSON the skill composed; reaches gi-runlog on stdin",
    "$no_run_log": "a flag the skill sets itself, tested by `[ -n … ]`",
    "$issue_body": "reaches gi-deps on stdin through printf, never as an argument",
    "$PPID": "shell built-in integer pid; reaches gi-state --pid, parsed as int",
}
VAR = re.compile(r"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?")
# Command substitution pastes its output into the command line unquoted. Only
# the `$(…)` form is checked: a backtick is also the markdown code delimiter in
# these files, so matching one cannot tell a legacy `…` substitution from the
# span it is written inside. Anything reachable through a backtick is reachable
# through `$(…)`, which is checked, so the gap is in notation, not in coverage.
SUBST = re.compile(r"\$\(")


def loose_substitutions(cmd):
    """(start, end) of every `$(…)` on the line, with naive paren balancing.

    `end` is `len(cmd)` when the substitution never closes, which is itself a
    finding: an unclosed one swallows whatever follows it.
    """
    out, i = [], cmd.find("$(")
    while i != -1:
        depth, j = 0, i + 1
        while j < len(cmd):
            if cmd[j] == "(":
                depth += 1
            elif cmd[j] == ")":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        out.append((i, j))
        i = cmd.find("$(", max(j, i + 2))
    return out
# `sh -c "…"` re-parses its argument, so the double-quote reasoning below does
# not hold inside one.
REPARSE = re.compile(
    # Any shell whose argument is re-parsed: `sh -c`, `bash -lc`, `sh -ce`,
    # `bash -o pipefail -c`. The `-…c…` token may carry other letters and may
    # sit behind options that take arguments of their own.
    # The shell must be the command word, not the tail of a filename: `\b`
    # alone matches the `sh` inside `build.sh`, which turned any later `-c`
    # option into a false "re-parse". `/` stays out of the lookbehind, so
    # `/bin/sh -c` and `/usr/bin/bash -lc` are still shells.
    r"(?<![\w.-])(?:sh|bash|zsh|dash|ksh)(?:\s+\S+)*?\s+-[A-Za-z]*c[A-Za-z]*\b"
    # xargs word-splits its input and honours quotes, and turns a filename
    # starting with `-` into an option — the same hazard by another route
    r"|\bxargs\b|\beval\b"
)
DQUOTED = re.compile(r'"(?:[^"\\]|\\.)*"')
SQUOTED = re.compile(r"'[^']*'")

def logical_lines(path: pathlib.Path):
    """Yield (line_no, text) with `\\`- and `|`-continuations joined."""
    lines = path.read_text(encoding="utf-8").splitlines()
    i = 0
    while i < len(lines):
        joined, j = lines[i], i
        # A trailing `|` continues a shell pipeline — unless the line also
        # opens with one, which makes it a markdown table row.
        while (
            j + 1 < len(lines)
            and re.search(r"(\\|\|)\s*$", joined)
            and not (joined.lstrip().startswith("|") and joined.rstrip().endswith("|"))
        ):
            j += 1
            joined = re.sub(r"\\\s*$", " ", joined) + " " + lines[j].strip()
        # An odd backtick count means an inline code span was hard-wrapped
        # mid-command. Pull in following lines until it closes, so the span can
        # be extracted as one region instead of falling back to the raw line.
        pulled = 0
        # A fence marker is backticks too — never treat one as an open span.
        is_fence = joined.lstrip().startswith("```") or joined.lstrip().startswith("~~~")
        while (
            not is_fence
            and joined.count("`") % 2
            and j + 1 < len(lines)
            and pulled < 4
        ):
            j += 1
            pulled += 1
            joined += " " + lines[j].strip()
        yield i + 1, joined
        i = j + 1

def commands(text: str):
    """The command region(s) of a logical line that invoke a shared script.

    When any backtick span on the line is a call, *every* span on that line is
    part of the command text. Prose splits one command across spans — "run
    `python3 …gi-secscan.py` with `--allow-pattern "{x}"`" — and inspecting only
    the span holding the executable would let the flag carrying the untrusted
    value sit in the span beside it, unlinted.
    """
    spans = re.findall(r"`([^`]+)`", text)
    if not any(CALL.search(span) for span in spans):
        return [text] if CALL.search(text) else []
    out = []
    dangling = False
    seen_call = False
    for span in spans:
        is_call = bool(CALL.search(span))
        # Once the call span has been seen, every later span is part of the
        # command: `…gi-x.py` `then paste` `{untrusted}` walked past the
        # option-shaped heuristic below. Spans *before* the call stay out —
        # `git add <file>` in the prose ahead of a call is a different command.
        if seen_call:
            out.append(span)
            continue
        seen_call = is_call
        # A sibling continues the command line when it opens with an option, a
        # pipe or another command, or when the span before it ended on an option
        # still waiting for its value — `…gi-x.py --allow-pattern` `{untrusted}`
        # is one command split across two spans. A sibling naming an output
        # shape, or the variable the call assigns to, is prose.
        admitted = bool(
            is_call or dangling or re.match(r"\s*(-|\||printf\b|echo\b)", span)
        )
        if admitted:
            out.append(span)
        # An option left without a value keeps every later span on the line in
        # the command. Sticky, because consuming only the next span lets a decoy
        # — `--allow-pattern` `see` `{untrusted}` — carry the value past the
        # check; armed only from a span that is already part of the command, so
        # unrelated prose ending in something option-shaped does not arm it.
        if admitted and not dangling:
            dangling = bool(re.search(r"(?:^|\s)--?[A-Za-z][\w-]*\s*$", span))
    return out

proc = subprocess.run(
    ["git", "-C", str(root), "ls-files", "-z"], capture_output=True, check=False
)
if proc.returncode != 0:
    print("FAIL|AC1: cannot enumerate tracked files — the lint is not scanning")
    raise SystemExit(0)
tracked = [p for p in proc.stdout.decode("utf-8", "replace").split("\0") if p]

bad = []
checked = 0
sites = {name: set() for name in EXPECTED_SITES}
if True:
    for rel in tracked:
        if rel.startswith(SKIP_PREFIXES) or not rel.endswith(SCAN_SUFFIXES):
            continue
        path = root / rel
        if not path.is_file():
            continue
        rp = pathlib.Path(rel)
        for lineno, text in logical_lines(path):
            for cmd in commands(text):
                checked += 1
                for name in SCRIPT_NAME.findall(cmd):
                    if name in sites:
                        sites[name].add((rel, lineno))
                if "<<" in cmd:
                    bad.append(
                        f"{rp}:{lineno}: a heredoc on a shared-script command "
                        f"line hides its body from this lint — pass the value "
                        f"through a quoted variable instead"
                    )
                for token in PLACEHOLDER.findall(cmd):
                    if token.strip() not in ALLOWED:
                        bad.append(
                            f"{rp}:{lineno}: {token} is interpolated into a "
                            f"shared-script command line and is not on the "
                            f"reviewed allowlist"
                        )
                if REPARSE.search(cmd):
                    bad.append(
                        f"{rp}:{lineno}: a shared-script call inside `sh -c` or "
                        f"`eval` re-parses its argument, so quoting no longer "
                        f"makes a value inert — invoke the script directly"
                    )
                # A parameter expansion inside double quotes is inert whatever
                # it holds; an unquoted one word-splits and globs, and a command
                # substitution pastes its output into the command line.
                unquoted = DQUOTED.sub(lambda m: " " * len(m.group(0)), cmd)
                # Single quotes suppress expansion outright, so `'$LIST'` is a
                # literal. Placeholders are checked before this, on the raw
                # text, because the agent substitutes those before the shell
                # ever sees the quotes.
                unquoted = SQUOTED.sub(lambda m: " " * len(m.group(0)), unquoted)
                for token in VAR.findall(unquoted):
                    bad.append(
                        f"{rp}:{lineno}: {token} is unquoted on a shared-script "
                        f"command line"
                    )
                for token in set(VAR.findall(cmd)):
                    if token not in ALLOWED_VARS:
                        bad.append(
                            f"{rp}:{lineno}: {token} is on a shared-script command "
                            f"line and is not on the reviewed variable allowlist"
                        )
                call = CALL.search(cmd)
                for start, end in loose_substitutions(cmd):
                    if (
                        call is not None
                        and start < call.start()
                        and call.end() <= end < len(cmd)
                    ):
                        continue  # `body="$(python3 …gi-issue.py …)"` — a capture
                    bad.append(
                        f"{rp}:{lineno}: a command substitution puts its output on "
                        f"a shared-script command line — quoting it does not make "
                        f"it inert; assign it to a variable the allowlist names"
                    )

drift = [
    f"{name}: {len(sites[name])} call site(s), pinned at {want}"
    for name, want in sorted(EXPECTED_SITES.items())
    if len(sites[name]) != want
]
if drift:
    print("FAIL|AC1: the per-script call-site count moved — " + "; ".join(drift)
          + ". A deleted call site is a contract change; update EXPECTED_SITES "
          "deliberately or restore the site")
elif bad:
    for entry in sorted(set(bad)):
        print(f"FAIL|AC1: {entry}")
else:
    print(
        f"PASS|AC1: no untrusted value is interpolated at any of the {checked} "
        f"shared-script call sites"
    )
PY
while IFS='|' read -r verdict label; do
  [ -n "$verdict" ] || continue
  if [ "$verdict" = "PASS" ]; then pass "$label"; else fail "$label"; fi
done < "$TMP/injection-report"

# And the derivation sites must actually use the safe form.
if grep -q -- "--from-issue" "$SKILLS/issue-resolver/SKILL.md"; then
  pass "AC4: the resolver derives the branch with --from-issue"
else
  fail "AC4: the resolver does not use --from-issue (title would reach a shell)"
fi

# A quote-bearing title must be inert data. This is the regression guard.
INJ="$TMP/inj"
mkdir -p "$INJ/bin"
printf '#!/bin/sh\nprintf %%s "$GH_TITLE_JSON"\n' > "$INJ/bin/gh"
chmod +x "$INJ/bin/gh"
( cd "$INJ" && PATH="$INJ/bin:$PATH" \
  GH_TITLE_JSON='{"title":"Fix login\"; touch PWNED; echo \"","labels":[]}' \
  python3 "$GIBRANCH" 42 --from-issue --type bug >/dev/null 2>&1 ) || true
if [ ! -e "$INJ/PWNED" ]; then
  pass "AC4: a quote-bearing issue title cannot execute (never on a command line)"
else
  fail "AC4: a crafted issue title executed a command — injection"
fi

# The subagent spawn bindings must be absolute, or the gate silently never runs.
for f in "$SKILLS/issue-resolver/references/pipeline-steps.md" \
         "$SKILLS/issue-pr-review/references/review-loop-mechanics.md"; do
  if grep -q "absolute" "$f"; then
    pass "AC1: $(basename "$f") requires an absolute secscan_script path"
  else
    fail "AC1: $(basename "$f") binds a skill-relative path a subagent cannot resolve"
  fi
done

# Exit 2 (an unresolved path) must degrade, not be read as a pass.
for f in "$SKILLS/issue-resolver/references/agents/implementer.md" \
         "$SKILLS/issue-resolver/references/agents/fixer.md"; do
  if grep -qi "exit .\?2" "$f"; then
    pass "AC1: $(basename "$f") classifies exit 2 as a degrade"
  else
    fail "AC1: $(basename "$f") leaves exit 2 unclassified (a scan that never ran)"
  fi
done

# auto-pilot's degraded CI filter must test .conclusion, or a COMPLETED-but-
# FAILED check prints nothing and empty output reads as all-green.
if grep -q "conclusion" "$SKILLS/auto-pilot/references/examples.md"; then
  pass "AC5: auto-pilot's degraded CI filter tests .conclusion, not just .status"
else
  fail "AC5: auto-pilot's degraded CI filter would merge a PR with failing checks"
fi

# gi-ci-wait can return `none`; the merge gate must say what that does.
if grep -q "none" "$SKILLS/auto-pilot/references/phases.md"; then
  pass "AC2: auto-pilot's merge gate handles the none verdict"
else
  fail "AC2: auto-pilot's merge gate leaves the none verdict unhandled"
fi

# Every flow that writes an issue must invalidate the cache, or a later read —
# possibly from another skill, since the cache is repo-wide — is served the
# pre-write body.
for f in "$REPO_ROOT/src/skills/issue-creator/references/modes.md" \
         "$REPO_ROOT/src/skills/issue-resolver/SKILL.source.md"; do
  edits="$(grep -c "gh issue edit" "$f" || true)"
  invalidates="$(grep -c -- "--invalidate" "$f" || true)"
  if [ "$edits" -gt 0 ] && [ "$invalidates" -ge "$edits" ]; then
    pass "AC3: $(basename "$f") invalidates the cache after every gh issue edit ($invalidates/$edits)"
  else
    fail "AC3: $(basename "$f") has $edits gh issue edit(s) but only $invalidates invalidate(s)"
  fi
done

# A degrade must reach the same outcomes as the fast path, not fewer. The
# success wording remains in the primary CI path; the degraded path itself must
# not merge on an empty or unsettled snapshot.
if grep -q "proceeds with the merge" "$SKILLS/auto-pilot/references/examples.md"; then
  pass "AC5: auto-pilot's degraded CI poll can still reach a merge"
else
  fail "AC5: auto-pilot's degraded CI poll documents no success outcome"
fi

# The two skills that run the scan must carry the security section in their
# per-skill config excerpt, or gi-config warns and skips validating those keys.
for s in issue-resolver issue-pr-review; do
  if grep -q "^security:" "$SKILLS/$s/references/docs/config-schema.md"; then
    pass "AC1: $s's config excerpt carries the security section"
  else
    fail "AC1: $s's config excerpt omits the security section (keys go unvalidated)"
  fi
done

# ───────────────────────────────────────────────────────────
# T6: the new security.* config keys exist in both parity surfaces
# ───────────────────────────────────────────────────────────
for key in extra_secret_file_pattern extra_secret_value_pattern allow_pattern max_file_size_mb; do
  if grep -q "^  $key:" "$REPO_ROOT/src/skills/init-gitissue/templates/gitissue-template.yml" \
     && grep -q "security\.$key" "$REPO_ROOT/docs/config-schema.md"; then
    pass "AC1: security.$key is documented and present in the init template"
  else
    fail "AC1: security.$key is missing from the schema or the init template"
  fi
done

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Shared-scripts wave 2 tests failed"
  exit 1
fi
echo "  ✓ All shared-scripts wave 2 checks passed"
