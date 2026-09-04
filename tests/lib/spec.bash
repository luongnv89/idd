# spec.bash — read a split reference spec as one file (issue #323).
#
# Sourced by tests/*.sh; never executed as a test case. The `.bash` extension
# keeps it out of the `git ls-files 'tests/*.sh'` test glob, exactly as
# tests/lib/anchors.bash explains.
#
# WHY
# ───
# Issue #323 split the two oversized reference files — the resolver's
# `references/pipeline-steps.md` and auto-pilot's `references/phases.md` — into
# an index plus one file per step or phase, so a run reads only the step it is
# on. The suite's assertions are about the *spec* those files carry, not about
# which file holds a sentence, so a test that used to grep the single file now
# greps the index followed by its parts, in index order, as one temp file.
#
# spec_concat <index-path>
#   Prints the path of a temp file holding <index-path> followed by every
#   `*.md` under its part directory — `steps/` for pipeline-steps.md,
#   `phases/` for phases.md — in lexical order, which is the index order the
#   file names were chosen to sort in. Works for src/, skills/ and dist/ copies
#   alike, since the layout is identical in all three. A missing index prints
#   nothing and returns 1, so a caller's existence check still fires.
#
# CLEANUP (issue #443)
# ────────────────────
# Every call used to `mktemp` a file nobody removed. A full suite run left ~150
# of them (~20 MB) in $TMPDIR, and the count grew with every run.
#
# WHERE THE STATE LIVES. Callers spell the call `X="$(spec_concat ...)"`, so the
# function body runs in a command-substitution subshell: a shell array it
# appended to, or an EXIT trap it installed, dies with that subshell — and a
# trap installed there would fire immediately, deleting the file it just handed
# back. So the created paths are appended to a registry *file*, which outlives
# the subshell, and the EXIT trap is installed once at source time, in the shell
# that sourced this library.
#
# CHAINING. spec_chain_cleanup does not replace the caller's EXIT handler. It
# reads the installed one with `trap -p`, unquotes it with `eval` (bash prints a
# handler as one single-quoted word, so `eval` reverses exactly the quoting bash
# applied) and re-installs "spec_cleanup; <previous>". Deferred expansion
# survives the round trip: a handler holding `rm -rf "$TMP"` still expands $TMP
# at exit, not at install. A handler set to ignore (`trap "" EXIT`) is the one
# case not preserved — cleanup runs instead. Nothing in the suite does that.
#
# CLEANUP GOES FIRST in that pair, and the order is load-bearing. Appending
# instead would put it after whatever the caller wrote, where three ordinary
# handler shapes swallow it: one ending in `&` makes "<handler> &; spec_cleanup"
# a syntax error, one ending in a `#` comment comments the call out, and under
# `set -e` a handler whose first command fails aborts before reaching it. No
# handler in the suite has those shapes today; running first costs nothing and
# means none of them can ever silence the cleanup.
#
# The registry file is created lazily, by the first `spec_concat` append, so
# sourcing this library still touches nothing. Sourcing only picks the name and
# clears a stale file a recycled PID may have left, both failure-tolerant: an
# unwritable $TMPDIR must not abort the 20 scripts that source this under
# `set -e`, and `spec_concat` already degrades on its own `mktemp`.
#
# ORDERING is the one thing chaining cannot fix. `trap ... EXIT` *replaces* the
# handler, so a script arming its own trap AFTER sourcing this file drops the
# cleanup. Five scripts do that and spell it out themselves:
#   trap 'rm -rf "$TMP"; spec_cleanup' EXIT
# A new script should arm its EXIT trap before sourcing, or do the same.
# tests/test-spec-tmp-cleanup-443.sh fails when one does neither.
#
# The exit status is unaffected: an EXIT handler's own status never replaces the
# status the script exits with, and `rm -f` on a missing path is not an error.

# Remove every temp file spec_concat recorded for this shell. Idempotent, and
# always returns 0 so a chained handler cannot change the script's exit status.
spec_cleanup() {
  local f reg="${SPEC_TMP_REGISTRY:-}"
  if [ -n "$reg" ] && [ -f "$reg" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] && rm -f "$f"
    done <"$reg"
    rm -f "$reg"
  fi
  return 0
}

# Chain spec_cleanup onto the EXIT trap, preserving whatever is installed.
spec_chain_cleanup() {
  local installed prev cmd
  installed="$(trap -p EXIT)"
  case "$installed" in
    *spec_cleanup*) return 0 ;;
  esac
  prev="${installed#trap -- }"
  prev="${prev% EXIT}"
  cmd=""
  if [ -n "$prev" ]; then eval "cmd=$prev"; fi
  if [ -n "$cmd" ]; then
    trap "spec_cleanup; $cmd" EXIT
  else
    trap 'spec_cleanup' EXIT
  fi
  return 0
}

spec_concat() {
  local index="$1" dir base sub out
  [ -f "$index" ] || return 1
  dir="$(dirname "$index")"
  base="$(basename "$index")"
  case "$base" in
    pipeline-steps.md) sub="steps" ;;
    phases.md)         sub="phases" ;;
    *) echo "spec_concat: no part directory known for $base" >&2; return 2 ;;
  esac
  out="$(mktemp "${TMPDIR:-/tmp}/spec-${base%.md}.XXXXXX")" || return 1
  printf '%s\n' "$out" >>"${SPEC_TMP_REGISTRY:-/dev/null}" 2>/dev/null || true
  cat "$index" "$dir/$sub"/*.md >"$out"
  echo "$out"
}

# Sourced, not run: this is the one place that executes in the caller's own
# shell, so it is the only place the registry and the EXIT trap can be set up.
# The guard makes a second `. lib/spec.bash` a no-op.
if [ -z "${SPEC_TMP_REGISTRY:-}" ]; then
  SPEC_TMP_REGISTRY="${TMPDIR:-/tmp}/spec-registry.$$"
  rm -f "$SPEC_TMP_REGISTRY" 2>/dev/null || true
  spec_chain_cleanup
fi
