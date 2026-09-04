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
  cat "$index" "$dir/$sub"/*.md >"$out"
  echo "$out"
}
