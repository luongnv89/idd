#!/usr/bin/env bash
# test-static-checks-664.sh — the resolver runs the repo's lint, format and
# type checks in check mode in every QA cycle, from the one table the PR
# review's pre-pass also reads (issue #664).
#
#  AC1. Every resolver QA cycle runs the detected rows' Check commands, never
#       a Fix command, over the files changed against the base. The documented
#       file-list block is executed here from the built skill: a deleted file,
#       a symlink and an unknown base never reach a tool, a name with a space
#       stays one argument, and `-x.js` arrives as a path.
#  AC2. A failed check is a fixable finding and blocks the clean exit; a check
#       that did not run is never a pass; the PR body states the outcome.
#  AC3. One shared table: both built skills carry it byte-identical, both
#       precheck lists name it, the review keeps no table of its own, no
#       lint/format command can run tree-wide in either stage, and the type
#       check is the command the review's build step already runs.
#
# Usage: bash tests/test-static-checks-664.sh

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHARED="$ROOT/src/shared/references/static-checks.md"
RES="$ROOT/src/skills/issue-resolver"
REV="$ROOT/src/skills/issue-pr-review"
STEP4="$RES/references/steps/step-4-qa.md"
BUILT_STEP4="$ROOT/skills/issue-resolver/references/steps/step-4-qa.md"
TEMPLATES="$RES/references/report-templates.md"
PREPASS="$REV/references/prepass-tests-ci-mechanics.md"
REV_SKILL="$REV/SKILL.source.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "0" ]; then pass "$1"; else fail "$1"; fi; }
has() { # has <file> <fixed-string> <label>
  if grep -qF -- "$2" "$1"; then pass "$3"; else fail "$3 ($(basename "$1"): '$2')"; fi
}
lacks() { # lacks <file> <fixed-string> <label>
  if grep -qF -- "$2" "$1"; then fail "$3 ($(basename "$1") still has '$2')"; else pass "$3"; fi
}

echo "AC3 — one shared table"
# Rows as TSV: tool, detection, files, check, fix. Exit 1 on a malformed table.
python3 - "$SHARED" > "$TMP/rows.tsv" <<'PY'
import sys
rows = []
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.startswith("| ") or line.startswith("| Tool ") or set(line.strip()) <= set("|- "):
        continue
    cells = [c.strip() for c in line.strip().strip("|").split(" | ")]
    if len(cells) != 5 or not all(cells):
        sys.exit(1)
    rows.append(cells)
for cells in rows:
    print("\t".join(cells))
PY
check "the shared table parses: five non-empty cells per row" "$?"

tools="$(cut -f1 "$TMP/rows.tsv" | tr '\n' ' ')"
want="ESLint Prettier Black Ruff isort gofmt rustfmt clang-format tsc "
if [ "$tools" = "$want" ]; then
  pass "the table holds the eight pre-pass tools plus tsc, and nothing else"
else
  fail "the table's tools are '$tools' — expected '$want'"
fi

# p-scope (i): a lint/format command is bare — the file list is its only
# source of paths, so no cell may name the tree.
python3 - "$TMP/rows.tsv" <<'PY'
import re, sys
bad = []
for line in open(sys.argv[1], encoding="utf-8"):
    tool, _detect, files, check, fix = line.rstrip("\n").split("\t")
    if tool == "tsc":
        continue
    if files == "project-wide" or not files.startswith("`"):
        bad.append(f"{tool}: no Files pattern")
    for cell in (check, fix):
        commands = re.findall(r"`([^`]+)`", cell)
        if not commands:
            bad.append(f"{tool}: a cell holds no command")
        for command in commands:
            for word in command.split()[1:]:
                if word in (".", "..", "*") or "/" in word or word.startswith("$"):
                    bad.append(f"{tool}: '{command}' names a path")
for b in bad:
    print("      " + b)
sys.exit(1 if bad else 0)
PY
check "no lint/format Check or Fix cell names a path, so none can run tree-wide" "$?"

# p-scope (ii)
has "$SHARED" 'A lint or format row never runs without a file list' "the shared file keeps the never-without-a-file-list rule"
has "$SHARED" "| grep -z -E '<Files>' | xargs -0 -r <command>" "the shared file states the pipe every lint/format command ends"
has "$SHARED" 'an empty filtered list skips the row' "an empty filtered list skips the row"
has "$SHARED" 'any output is a failure' "gofmt's exit-0 listing is read as a failure"
# p-scope (iii)
has "$PREPASS" '"$scope/approved-args" | xargs -0 -r <Fix command>' "the review pre-pass runs Fix commands through the approved-paths pipe"
has "$PREPASS" 'Never fall back to a tree-wide formatter or `git add -A`' "the review pre-pass keeps its tree-wide ban"
has "$STEP4" '"$checks/files" | xargs -0 -r <Check command>' "the resolver runs Check commands through its changed-files pipe"
has "$STEP4" 'it never runs bare over the tree' "the resolver never runs a row over the tree"

# The check-mode and fix-mode commands differ wherever a tool can fix.
awk -F'\t' '$1 != "tsc" && $4 == $5 { bad = 1 } END { exit bad }' "$TMP/rows.tsv"
check "every lint/format row has a Check command distinct from its Fix command" "$?"
if awk -F'\t' '$1 != "gofmt" && $1 != "tsc"' "$TMP/rows.tsv" | cut -f4 | grep -qE -- '--fix|--write|-w`| -i`'; then
  fail "a Check cell carries a mutating flag"
else
  pass "no Check cell carries a mutating flag"
fi
[ "$(awk -F'\t' '$1 == "gofmt" { print $4 }' "$TMP/rows.tsv")" = '`gofmt -l`' ]
check "gofmt checks with -l, never -w" "$?"

# p-tsc-drift: the type check is the review's own build command.
tsc_shared="$(awk -F'\t' '$1 == "tsc" { print $4 }' "$TMP/rows.tsv")"
tsc_review="$(awk '/^## Step 4 — Build-system detection/ { f = 1 } f && /`tsconfig.json`/ { n = split($0, c, " [|] "); gsub(/ *[|] *$/, "", c[n]); print c[n]; exit }' "$PREPASS")"
if [ -n "$tsc_shared" ] && [ "$tsc_shared" = "$tsc_review" ]; then
  pass "the tsc row's command equals the review's Step 4 tsconfig build command ($tsc_shared)"
else
  fail "tsc drift: shared '$tsc_shared' vs review Step 4 '$tsc_review'"
fi
[ "$(awk -F'\t' '$1 == "tsc" { print $3 "/" $5 }' "$TMP/rows.tsv")" = "project-wide/none" ]
check "tsc is project-wide and has no Fix command" "$?"
has "$SHARED" 'any error is a failure' "any tsc error is a failure, as in the review's build"

# p-bundle
for skill in issue-resolver issue-pr-review; do
  built="$ROOT/skills/$skill/references/static-checks.md"
  if [ -f "$built" ] && cmp -s "$SHARED" "$built"; then
    pass "skills/$skill carries static-checks.md byte-identical"
  else
    fail "skills/$skill copy of static-checks.md is missing or differs (run ./scripts/build.sh)"
  fi
  for md in "$ROOT/src/skills/$skill/SKILL.source.md" "$ROOT/skills/$skill/SKILL.md"; do
    awk '/^### Bundled dependency precheck/ { f = 1; next } f && /^#{2,4} / { exit } f' "$md" \
      | grep -qxF 'references/static-checks.md'
    check "$skill precheck list names static-checks.md (${md#"$ROOT/"})" "$?"
  done
done

lacks "$PREPASS" 'eslint' "the review pre-pass keeps no tool table of its own"
has "$PREPASS" 'each detected lint/format row of `references/static-checks.md`' "the review pre-pass reads the shared table"
has "$PREPASS" "never its \`tsc\` row" "the review pre-pass leaves tsc to its build step"
has "$REV_SKILL" "each detected lint/format row's Check command from \`references/static-checks.md\`" "review-only mode runs the shared Check commands"
lacks "$REV_SKILL" 'npx eslint .' "review-only mode names no tree-wide command"

echo "AC1 — every cycle, check mode only"
has "$STEP4" '**Static checks** — in every cycle' "the checks are their own part of every cycle"
has "$STEP4" 'Run the Check command of every detected row of `references/static-checks.md`, never a Fix command' "check mode only"
has "$STEP4" "whatever \`resolve.auto_test\` says" "resolve.auto_test does not gate the checks"
order="$(grep -n -o -E 'a:rs-qa-run-tests|\*\*Static checks\*\*|a:rs-qa-evaluate' "$STEP4" | cut -d: -f2- | tr '\n' ' ')"
[ "$order" = "a:rs-qa-run-tests **Static checks** a:rs-qa-evaluate " ]
check "the checks sit after the suite and before the evaluation" "$?"

# The documented file-list block, taken from the built skill and executed.
python3 - "$BUILT_STEP4" "$TMP/list.sh" <<'PY'
import re, sys, textwrap
text = open(sys.argv[1], encoding="utf-8").read()
blocks = [b for b in re.findall(r"^[ ]*```bash\n(.*?)^[ ]*```", text, flags=re.S | re.M)
          if '"$checks/changed"' in b]
if len(blocks) != 1:
    sys.exit(1)
open(sys.argv[2], "w", encoding="utf-8").write(textwrap.dedent(blocks[0]))
PY
check "the built step file holds one changed-file-list block" "$?"
js_files="$(awk -F'\t' '$1 == "ESLint" { print $3 }' "$TMP/rows.tsv" | tr -d '`')"

REPO="$TMP/repo"
BIN="$TMP/bin"
mkdir -p "$REPO" "$BIN" "$TMP/mk"
cat > "$BIN/fakecheck" <<'CHK'
#!/bin/sh
# Records each argument on its own line; exits 1 like a failed check.
for f in "$@"; do printf '%s\n' "$f" >> "$CHECK_LOG"; done
exit 1
CHK
chmod +x "$BIN/fakecheck"
(
  cd "$REPO" || exit 1
  git init -q -b main
  git config user.email t@example.com
  git config user.name t
  for f in keep.js gone.js untouched.js; do printf 'base\n' > "$f"; done
  git add -A && git commit -qm base
  git update-ref refs/remotes/origin/main HEAD
  git checkout -q -b feat/1-change
  printf 'edit\n' >> keep.js
  git rm -q gone.js
  printf 'new\n' > ./-x.js
  printf 'new\n' > "sp ace.js"
  printf 'new\n' > new.py
  ln -s keep.js link.js
  git add -A && git commit -qm change
  printf 'scratch\n' > uncommitted.js
) >/dev/null 2>&1

export CHECK_LOG="$TMP/check.log"
(
  cd "$REPO" || exit 1
  export PATH="$BIN:$PATH" TMPDIR="$TMP/mk"
  set +o pipefail   # the documented pipe runs in a plain shell
  base=main
  # shellcheck disable=SC1091
  . "$TMP/list.sh" || exit 9
  tr '\0' '\n' < "$checks/files" > "$TMP/files.txt"
  grep -z -E "$js_files" "$checks/files" | xargs -0 -r fakecheck
  echo "$?" > "$TMP/fail.rc"
  grep -z -E '\.go$' "$checks/files" | xargs -0 -r fakecheck
  echo "$?" > "$TMP/empty.rc"
  grep -z -E '.' "$checks/files" | xargs -0 -r no-such-static-check 2>/dev/null
  echo "$?" > "$TMP/missing.rc"
)
check "the documented block runs to completion" "$?"
listed="$(LC_ALL=C sort "$TMP/files.txt" | tr '\n' '|')"
[ "$listed" = "./-x.js|./keep.js|./new.py|./sp ace.js|" ]
check "the list is the changed regular files: no deleted, symlinked, untouched or uncommitted path (got $listed)" "$?"
[ "$(LC_ALL=C sort "$CHECK_LOG" | tr '\n' '|')" = "./-x.js|./keep.js|./sp ace.js|" ]
check "the tool received only the paths its Files pattern matches, one argument per file" "$?"
grep -qx './-x.js' "$CHECK_LOG" && ! grep -q '^-' "$CHECK_LOG"
check "every argument is ./-prefixed, so -x.js is never an option" "$?"
[ "$(cat "$TMP/fail.rc")" != "0" ]
check "a failing check surfaces as a non-zero exit through the pipe" "$?"
[ "$(cat "$TMP/empty.rc")" = "0" ] && [ "$(grep -c . "$CHECK_LOG")" = "3" ]
check "a row with no matching file runs nothing" "$?"
[ "$(cat "$TMP/missing.rc")" = "127" ]
check "a missing tool exits 127, the documented not-run signal" "$?"
(
  cd "$REPO" || exit 1
  export TMPDIR="$TMP/mk"
  base=no-such-base
  # shellcheck disable=SC1091
  . "$TMP/list.sh" 2>/dev/null
  [ ! -e "$checks/files" ]
)
check "an unreadable base writes no file list, so nothing reads as 'no files changed'" "$?"

echo "AC2 — a failure is a finding, and the PR body states the outcome"
has "$STEP4" '**failed** — a fixable finding. The fixer gets the tool'"'"'s output, and the cycle is not clean.' "a failed check is a fixable finding"
has "$STEP4" 'Reviewer returns `PASS` AND all tests pass AND build succeeds AND no static check failed → exit loop' "the clean exit needs no failed check"
has "$STEP4" 'failing test/build/static-check output' "the fixer receives the check output"
has "$STEP4" 'It is never a pass and never goes to the fixer, and it does not block the clean exit.' "a check that did not run is never a pass and never blocks"
has "$STEP4" '`xargs` exit 126 or 127' "the not-run signal is named"
has "$STEP4" '⚠ Static check not run: {tool} — {reason}' "a check that did not run prints a warning line"
results="$(awk '/^## Test Results/ { f = 1; next } f && /^## / { exit } f' "$TEMPLATES")"
bullet="$(printf '%s\n' "$results" | grep -F -- '- Static checks:' || true)"
if [ "$(printf '%s\n' "$bullet" | grep -c .)" = "1" ]; then
  pass "the PR body template has one Static checks bullet under Test Results"
else
  fail "the PR body template needs exactly one Static checks bullet under Test Results"
fi
for state in 'passed' 'failed: {tool}, {what remains}' 'not run: {tool}, {reason}'; do
  if printf '%s\n' "$bullet" | grep -qF -- "$state"; then
    pass "the bullet states '$state'"
  else
    fail "the bullet lacks the state '$state'"
  fi
done
has "$ROOT/skills/issue-resolver/references/report-templates.md" "$bullet" "the built template carries the same bullet"

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
