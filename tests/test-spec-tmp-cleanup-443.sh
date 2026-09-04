#!/usr/bin/env bash
# test-spec-tmp-cleanup-443.sh — spec_concat temp files are cleaned up (issue #443).
#
# tests/lib/spec.bash hands each caller the path of a mktemp'd file holding an
# index plus its parts. Nothing removed those files, so a full suite run left
# ~150 of them (~20 MB) in $TMPDIR and the count grew with every run.
#
# The fix chains spec_cleanup onto the EXIT trap once, at source time, from the
# guard at the foot of tests/lib/spec.bash — in the caller's own shell, and by
# extending the installed handler rather than replacing it, so a script that
# armed its own trap keeps it. spec_concat itself installs nothing; it only
# appends the path it just created to a registry file. That chaining is
# invisible in normal output — it only shows up as files that are or are not
# there afterwards — so this test drives real scripts under a scratch $TMPDIR
# and counts what survives.
#
# Usage: bash tests/test-spec-tmp-cleanup-443.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$REPO_ROOT/tests/lib/spec.bash"
INDEX="$REPO_ROOT/src/skills/issue-resolver/references/pipeline-steps.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ spec_concat temp-file cleanup (issue #443)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

[ -f "$LIB" ] || { echo "  ✗ missing $LIB"; exit 1; }
[ -f "$INDEX" ] || { echo "  ✗ missing $INDEX"; exit 1; }

# Count surviving spec-* files in a scratch $TMPDIR.
leaked() { find "$1" -maxdepth 1 -name 'spec-*' | wc -l | tr -d ' '; }

# Run a fixture script with its own scratch TMPDIR. Prints the exit status.
#
# "${BASH:-bash}", not bare `bash`: every assertion below runs inside a fixture,
# so a bare `bash` would send them all to whatever is first on PATH and this
# script's own interpreter would test nothing but its own scan loops. On a mac
# with a newer bash installed, `/bin/bash tests/…` would then silently exercise
# bash 5 fixtures — the one thing the bash 3.2 leg exists to rule out.
run_fixture() {
  local script="$1" dir="$2" st=0
  mkdir -p "$dir"
  TMPDIR="$dir" "${BASH:-bash}" "$script" >"$dir/.stdout" 2>"$dir/.stderr" || st=$?
  echo "$st"
}

# ───────────────────────────────────────────────────────────
# AC1 — a plain caller leaves nothing behind
# ───────────────────────────────────────────────────────────
cat >"$TMP/plain.sh" <<EOF
set -euo pipefail
. "$LIB"
a="\$(spec_concat "$INDEX")"
b="\$(spec_concat "$INDEX")"
[ -s "\$a" ] && [ -s "\$b" ] || exit 1
[ "\$a" != "\$b" ] || exit 1
EOF
D="$TMP/d1"
st="$(run_fixture "$TMP/plain.sh" "$D")"
[ "$st" -eq 0 ] || fail "T1: plain caller fixture exited $st"
[ "$st" -eq 0 ] && {
  [ "$(leaked "$D")" -eq 0 ] \
    && pass "T1 (AC1): two spec_concat calls leave no temp file behind" \
    || fail "T1 (AC1): $(leaked "$D") spec-* file(s) survived a plain caller"
}

# ───────────────────────────────────────────────────────────
# AC2 — a pre-existing EXIT trap keeps its behaviour
# ───────────────────────────────────────────────────────────
cat >"$TMP/prior.sh" <<EOF
set -euo pipefail
OWN="\$TMPDIR/own-marker"
trap 'rm -f "\$OWN"' EXIT
: >"\$OWN"
. "$LIB"
s="\$(spec_concat "$INDEX")"
[ -s "\$s" ] || exit 1
EOF
D="$TMP/d2"
st="$(run_fixture "$TMP/prior.sh" "$D")"
[ "$st" -eq 0 ] || fail "T2: prior-trap fixture exited $st"
if [ "$st" -eq 0 ]; then
  [ ! -e "$D/own-marker" ] \
    && pass "T2 (AC2): the caller's own EXIT trap still runs after sourcing" \
    || fail "T2 (AC2): the caller's EXIT trap was dropped — own-marker survived"
  [ "$(leaked "$D")" -eq 0 ] \
    && pass "T2 (AC2): cleanup is chained onto that trap, not lost to it" \
    || fail "T2 (AC2): $(leaked "$D") spec-* file(s) survived alongside a prior trap"
fi

# The prior handler is preserved literally, so its deferred expansion still
# happens at exit — a handler holding "$VAR" must see the value it has then,
# not the one it had when spec_concat re-installed the trap.
cat >"$TMP/deferred.sh" <<EOF
set -euo pipefail
V=before
trap 'printf "%s" "\$V" >"\$TMPDIR/seen"' EXIT
. "$LIB"
s="\$(spec_concat "$INDEX")"
V=after
EOF
D="$TMP/d3"
st="$(run_fixture "$TMP/deferred.sh" "$D")"
if [ "$st" -eq 0 ] && [ -f "$D/seen" ] && [ "$(cat "$D/seen")" = "after" ]; then
  pass "T3 (AC2): the preserved handler still expands its variables at exit"
else
  fail "T3 (AC2): deferred expansion broke — saw '$(cat "$D/seen" 2>/dev/null)'"
fi

# ───────────────────────────────────────────────────────────
# Exit status must survive the chained handler
#
# Both fixtures arm their own handler BEFORE sourcing, so the handler under
# test really is a chained one. A fixture arming its trap afterwards would
# replace spec.bash's outright and assert plain bash semantics instead.
# ───────────────────────────────────────────────────────────
cat >"$TMP/status.sh" <<EOF
trap 'printf REACHED >"\$TMPDIR/reached"' EXIT
. "$LIB"
s="\$(spec_concat "$INDEX")"
exit 7
EOF
D="$TMP/d4"
st="$(run_fixture "$TMP/status.sh" "$D")"
if [ "$st" -eq 7 ] && [ "$(cat "$D/reached" 2>/dev/null)" = REACHED ] && [ "$(leaked "$D")" -eq 0 ]; then
  pass "T4: an explicit exit status survives the chained handler"
else
  fail "T4: exit 7 became $st, reached='$(cat "$D/reached" 2>/dev/null)', $(leaked "$D") leak(s)"
fi

cat >"$TMP/status2.sh" <<EOF
trap 'printf REACHED >"\$TMPDIR/reached"' EXIT
. "$LIB"
s="\$(spec_concat "$INDEX")"
[ 1 -eq 2 ]
EOF
D="$TMP/d4b"
st="$(run_fixture "$TMP/status2.sh" "$D")"
if [ "$st" -eq 1 ] && [ "$(cat "$D/reached" 2>/dev/null)" = REACHED ] && [ "$(leaked "$D")" -eq 0 ]; then
  pass "T4: a fall-off-the-end status survives the chained handler"
else
  fail "T4: fall-off-the-end status became $st, $(leaked "$D") leak(s)"
fi

# The cleanup runs before the caller's handler, not after, so no handler shape
# can swallow it. A handler ending in `&` would make the appended form a syntax
# error; one ending in a comment would comment it out.
cat >"$TMP/swallow.sh" <<EOF
trap 'echo done # trailing comment' EXIT
. "$LIB"
s="\$(spec_concat "$INDEX")"
EOF
D="$TMP/d4c"
st="$(run_fixture "$TMP/swallow.sh" "$D")"
if [ "$st" -eq 0 ] && [ "$(leaked "$D")" -eq 0 ]; then
  pass "T4: a handler ending in a comment cannot swallow the cleanup"
else
  fail "T4: comment-terminated handler — exit $st, $(leaked "$D") leak(s)"
fi

# ───────────────────────────────────────────────────────────
# Chaining happens once, and the counter can tell one chain from two
#
# The loop below cannot itself produce a second chain — spec_chain_cleanup runs
# once, from spec.bash's source-time guard, and spec_concat installs nothing —
# so it asserts that many calls do not disturb what the single chain installed.
# What keeps the `-eq 1` assertion honest is the counter, checked separately
# against a handler that really does name spec_cleanup twice.
# ───────────────────────────────────────────────────────────
cat >"$TMP/idem.sh" <<EOF
set -euo pipefail
. "$LIB"

# Count occurrences, not matching lines. "trap -p EXIT" prints a one-line
# handler however many times spec_cleanup appears inside it, so "grep -c" reads
# a doubled chain as 1 and the assertion below could never fail. awk's gsub
# counts hits and always exits 0, so a zero count cannot trip "pipefail".
count_chained() {
  trap -p EXIT | awk '{ n += gsub(/spec_cleanup/, "&") } END { print n + 0 }'
}

for _ in 1 2 3 4; do s="\$(spec_concat "$INDEX")"; done
n="\$(count_chained)"
[ "\$n" -eq 1 ] || { echo "spec_cleanup appears \$n time(s)" >&2; exit 1; }

# Prove the counter can see a double chain, or the assertion above is vacuous.
# Install one deliberately, check it reads as 2, then restore what was there.
orig="\$(trap -p EXIT)"
trap 'spec_cleanup; spec_cleanup' EXIT
n2="\$(count_chained)"
eval "\$orig"
[ "\$n2" -eq 2 ] || { echo "a doubled handler counted as \$n2, not 2" >&2; exit 1; }
[ "\$(count_chained)" -eq 1 ] || { echo "restoring the handler failed" >&2; exit 1; }

spec_cleanup
spec_cleanup
EOF
D="$TMP/d5"
st="$(run_fixture "$TMP/idem.sh" "$D")"
[ "$st" -eq 0 ] \
  && pass "T5: repeated calls chain once; spec_cleanup is idempotent" \
  || fail "T5: idempotence fixture exited $st — $(cat "$D/.stderr")"

# ───────────────────────────────────────────────────────────
# AC3 — no call site silently drops the cleanup
#
# Chaining cannot survive a `trap ... EXIT` armed after spec.bash is sourced:
# that replaces the handler outright. Every such call site must name
# spec_cleanup itself, so a new one cannot start leaking unnoticed.
#
# The scan is heredoc-aware. tests/test-scripts-253.sh writes a fixture script
# whose own traps live inside a heredoc body; those are not this script's traps
# and must not be flagged.
# ───────────────────────────────────────────────────────────
SCAN="$TMP/scan.awk"
cat >"$SCAN" <<'AWK'
{
  if (in_here) { if ($0 ~ ("^[ \t]*" term "[ \t]*$")) in_here = 0; next }
  if ($0 ~ /^[ \t]*#/) next
  if (match($0, /<<-?[ \t]*['"'"'"]?[A-Za-z_][A-Za-z0-9_]*['"'"'"]?/)) {
    t = substr($0, RSTART, RLENGTH)
    sub(/^<<-?[ \t]*/, "", t); gsub(/['"'"'"]/, "", t)
    term = t; in_here = 1
  }
  if ($0 ~ /(^[ \t]*|[;&|({][ \t]*|[ \t](then|do|else)[ \t]+)trap[ \t]/ && $0 ~ /EXIT/) print FNR ":" $0
}
AWK

# A process substitution's failure cannot fail the enclosing script, not even
# under `set -o pipefail`, so a moved tests/ directory or a broken glob would
# feed this loop nothing and the scan would pass having examined zero files.
# Count what was actually scanned and require it to be non-zero (20 today).
offenders=""
scanned=0
while IFS= read -r f; do
  src="$(awk '/^[ \t]*[.]|^[ \t]*source/ && /lib\/spec\.bash/ {print FNR; exit}' "$f")"
  [ -n "$src" ] || continue
  scanned=$((scanned + 1))
  while IFS= read -r hit; do
    n="${hit%%:*}"
    [ "$n" -gt "$src" ] || continue
    case "$hit" in *spec_cleanup*) continue ;; esac
    offenders="$offenders $(basename "$f"):$n"
  done < <(awk -f "$SCAN" "$f")
done < <(cd "$REPO_ROOT" && grep -rl 'lib/spec\.bash' tests/*.sh | sed "s|^|$REPO_ROOT/|")

if [ "$scanned" -eq 0 ]; then
  fail "T6 (AC3): the scan examined 0 files — the file list is broken"
elif [ -n "$offenders" ]; then
  fail "T6 (AC3): EXIT trap armed after sourcing spec.bash, cleanup dropped:$offenders"
else
  pass "T6 (AC3): $scanned scanned; every EXIT trap armed after sourcing chains spec_cleanup"
fi

# ───────────────────────────────────────────────────────────
# AC1, end to end — three real suite members leave $TMPDIR clean
#
# One caller arms no trap of its own (254); one arms a trap after its first
# spec_concat call and so must spell the cleanup out (260); one arms its own
# EXIT trap BEFORE sourcing — 258, the fastest of the four suite members that
# arm one before sourcing. Only that third shape drives spec_chain_cleanup's
# `trap -p` and `eval` round trip against a real handler in a script the suite
# actually maintains; elsewhere it is covered by the synthetic heredoc fixtures
# of T2, T3 and T4 alone. All three paths matter.
# ───────────────────────────────────────────────────────────
for real in test-analysis-reuse-254 test-autopilot-parallel-260 test-autopilot-triage-cache-258; do
  D="$TMP/real-$real"
  st="$(run_fixture "$REPO_ROOT/tests/$real.sh" "$D")"
  if [ "$st" -ne 0 ]; then
    fail "T7 (AC1): tests/$real.sh exited $st under a scratch TMPDIR"
  elif [ "$(leaked "$D")" -eq 0 ]; then
    pass "T7 (AC1): tests/$real.sh leaves no spec-* file in \$TMPDIR"
  else
    fail "T7 (AC1): tests/$real.sh left $(leaked "$D") spec-* file(s)"
  fi
done

echo
echo "  Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
