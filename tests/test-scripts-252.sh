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

# The whole wait happens in one invocation: several polls, one process, one
# verdict. That is the property that removes the per-poll agent tool call.
SEQ="$TMP/seq"
{
  echo '[{"name":"build","state":"IN_PROGRESS","bucket":"pending","link":"u"}]'
  echo '[{"name":"build","state":"IN_PROGRESS","bucket":"pending","link":"u"}]'
  echo '[{"name":"build","state":"SUCCESS","bucket":"pass","link":"u"}]'
} > "$SEQ"
run_status out st env GH_SEQUENCE="$SEQ" GH_COUNT_FILE="$TMP/count" \
  PATH="$STUB:$PATH" python3 "$CIWAIT" 42 --interval 1 --timeout 30
polls="$(printf '%s' "$out" | jkey polls)"
if [ "$(printf '%s' "$out" | jkey verdict)" = "pass" ] && [ "$polls" -ge 3 ]; then
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
expect_grep "AC5: pr-review keeps the manual CI poll" \
  "gh pr checks" "$SKILLS/issue-pr-review/references/prepass-tests-ci-mechanics.md"
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

# No call site may interpolate a config VALUE into the command line. .gitissue.yml
# is repo-controlled and /issue-pr-review reviews with a PR's branch checked out,
# so a crafted value inside a quoted shell word would run on the reviewer's
# machine at the moment the gate runs. The script reads the file itself instead.
injected=0
while IFS= read -r hit; do
  case "$hit" in
    *--config-json*|*--allow-pattern*|*--extra-secret-*|*--max-file-size-mb*)
      fail "AC1: gi-secscan call site interpolates config into the command line: $hit"
      injected=1 ;;
  esac
done < <(grep -rhn --include='*.md' "python3 .*gi-secscan\.py" \
           "$REPO_ROOT/src/skills" "$REPO_ROOT/src/shared/agents" \
           "$REPO_ROOT/docs/pre-commit-security.md")
[ "$injected" -eq 0 ] && pass "AC1: no gi-secscan call site puts a config value on the command line"

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

# A degrade must reach the same outcomes as the fast path, not fewer.
if grep -q "proceed with the merge" "$SKILLS/auto-pilot/references/examples.md"; then
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
