#!/usr/bin/env bash
# test-gh-catalog-lint-566.sh — Lint tracker calls against the catalog (#566)
#
# Acceptance criteria:
#  - AC1: every `gh` form used in src/ has a row in the Operation catalog of
#         docs/platform-github.md, and the build fails when one does not
#  - AC2: the count of files with inline `gh` calls is recorded in the Task
#         3.1 ratchet (scripts/surface-counts.json, key `gh_call_files`)
#
# Obligations from the sensitive-change gate, each a named check below:
#  - O1: a form with no catalog row fails the build, naming file, line, form
#  - O2: deleting a catalog row fails the build for the form it covered
#  - O3: prose (`gh is not installed`, a bare `gh pr`, `gh --version`) and a
#        form named only in catalog prose, not a row, never pass as a call
#  - O4: the recorded count and the build lint read one definition of a call
#  - O5: a script's argv-list call (`_RUN_GH(["release", "create", …])`) with
#        no prose mention fails the build and raises the recorded count
#
# Every build runs on a copy of src/, docs/ and the build package under
# mktemp -d. The repository is only ever read.
#
# Usage: bash tests/test-gh-catalog-lint-566.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE="$REPO_ROOT/scripts/build/gh_catalog.py"
TMP_BASE="$(mktemp -d)"
trap 'rm -rf "$TMP_BASE"' EXIT

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

# make_copy <name> — fresh src/, docs/ and build package under $TMP_BASE/<name>.
make_copy() {
  local copy="$TMP_BASE/$1"
  rm -rf "$copy"
  mkdir -p "$copy/scripts"
  cp -R "$REPO_ROOT/src" "$copy/src"
  cp -R "$REPO_ROOT/docs" "$copy/docs"
  cp "$REPO_ROOT/scripts/build.py" "$copy/scripts/build.py"
  cp -R "$REPO_ROOT/scripts/build" "$copy/scripts/build"
  rm -rf "$copy/scripts/build/__pycache__"
  printf '%s' "$copy"
}

# run_build <copy> <log> — non-mutating build of a copy; returns its exit code.
run_build() {
  local copy="$1" log="$2" rc=0
  PYTHONDONTWRITEBYTECODE=1 python3 "$copy/scripts/build.py" \
    --out "$copy/dist" --src "$copy/src" --no-root-skills \
    >"$log" 2>&1 || rc=$?
  return "$rc"
}

# replace <file> <old> <new> — replace exactly one occurrence, or fail loudly.
replace() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys
path, old, new = sys.argv[1:]
text = open(path, encoding="utf-8").read()
assert text.count(old) == 1, f"{old!r} occurs {text.count(old)} times in {path}"
open(path, "w", encoding="utf-8").write(text.replace(old, new))
PY
}

echo "◆ gh catalog lint tests (#566)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ── The form definition ───────────────────────────────────────────────────
if PYTHONDONTWRITEBYTECODE=1 python3 - "$MODULE" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gh_catalog", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
cases = {
    "gh issue view {N} --json number": ["gh issue view"],
    "`gh pr merge {N} --squash` then `gh pr view {N}`": ["gh pr merge", "gh pr view"],
    "gh api repos/{owner}/{repo} --jq .x": ["gh api"],
    "gh api rate_limit": ["gh api"],
    "x=$(gh repo view --json name)": ["gh repo view"],
    "To fix:  gh auth login": ["gh auth login"],
    "gh pr update-branch {N}": ["gh pr update-branch"],
    "gh is not installed": [],
    "the `gh pr` commands": [],
    "gh --version": [],
    "ghx issue view": [],
    "./gh issue view": [],
    "my-gh issue view": [],
    "gh prs list": [],
}
bad = {k: (m.forms_in_line(k), v) for k, v in cases.items() if m.forms_in_line(k) != v}
assert not bad, bad
argv = {
    'args = ["issue", "view", str(n), "--json", "title"]': ["gh issue view"],
    'args = [\n    "issue", "list", "--state", "open",\n]': ["gh issue list"],
    '_RUN_GH(["pr", "view", str(n)], Unavailable)': ["gh pr view"],
    "cmd = ['gh', 'release', 'create', tag]": ["gh release create"],
    'cmd = ["gh", "api", "rate_limit"]': ["gh api"],
    'git(["status", "--porcelain"])': [],
    'data["api"]': [],
    'record["pr"] is not None': [],
    '{"issue": lane["issue"], "pr": pr}': [],
}
bad = {k: v for k, v in argv.items() if [f for _, f in m.argv_forms(k)] != v}
assert not bad, bad
assert m.argv_forms('x = 1\nargs = [\n  "pr", "checks"]') == [(2, "gh pr checks")]
PY
then
  pass "O3: a form is gh + group + verb; prose, a bare group and gh --version are not calls"
  pass "O5: argv lists count by their first two literals; subscripts and git argv do not"
else
  fail "O3/O5: the form definition disagrees with forms_in_line() or argv_forms()"
fi

# ── AC1 on the committed tree ─────────────────────────────────────────────
OUT="$(PYTHONDONTWRITEBYTECODE=1 python3 - "$MODULE" "$REPO_ROOT" <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("gh_catalog", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
root = sys.argv[2]
catalog = m.catalog_forms(open(os.path.join(root, "docs/platform-github.md"), encoding="utf-8").read())
used = {form for _, _, form in m.scan(os.path.join(root, "src"))}
print(len(used), len(catalog or ()), " ".join(sorted(used - (catalog or set()))) or "-")
PY
)"
read -r USED CATALOGUED MISSING <<<"$OUT"
if [ "$MISSING" = "-" ] && [ "$USED" -gt 0 ]; then
  pass "AC1: all $USED gh forms used in src/ have a catalog row ($CATALOGUED catalogued)"
else
  fail "AC1: forms used in src/ with no catalog row: $MISSING"
fi

copy="$(make_copy t0)"
if run_build "$copy" "$TMP_BASE/t0.log"; then
  pass "AC1: an unmutated copy builds, so the lint passes on the tree"
else
  fail "AC1: an unmutated copy failed to build"
  sed 's/^/      /' "$TMP_BASE/t0.log" | head -10
  echo "  Passed: $PASS"
  echo "  Failed: $FAIL"
  exit 1
fi

# ── O1: an uncatalogued form fails the build ──────────────────────────────
copy="$(make_copy o1)"
target="$copy/src/skills/issue-triage/SKILL.source.md"
printf '\nRun `gh release create v9.9.9` to publish.\n' >> "$target"
line="$(wc -l < "$target" | tr -d ' ')"
rc=0
run_build "$copy" "$TMP_BASE/o1.log" || rc=$?
if [ "$rc" -ne 0 ] \
  && grep -q "src/skills/issue-triage/SKILL.source.md:$line" "$TMP_BASE/o1.log" \
  && grep -q '`gh release create`' "$TMP_BASE/o1.log" \
  && grep -q 'Operation catalog' "$TMP_BASE/o1.log"; then
  pass "O1: an uncatalogued form fails the build and names file:line, form and fix"
else
  fail "O1: build exit $rc; log: $(head -5 "$TMP_BASE/o1.log")"
fi

# ── O2: a deleted catalog row fails the build ─────────────────────────────
copy="$(make_copy o2)"
replace "$copy/docs/platform-github.md" ' · `gh pr update-branch {N}`' ''
rc=0
run_build "$copy" "$TMP_BASE/o2.log" || rc=$?
if [ "$rc" -ne 0 ] && grep -q '`gh pr update-branch`' "$TMP_BASE/o2.log"; then
  pass "O2: removing the gh pr update-branch row fails the build for that form"
else
  fail "O2: build exit $rc; log: $(head -5 "$TMP_BASE/o2.log")"
fi

# ── O3: a form named in catalog prose is not a row ────────────────────────
copy="$(make_copy o3-prose-row)"
replace "$copy/docs/platform-github.md" '### Raw API (escape hatch)' \
  'Publishing uses `gh release create`.

### Raw API (escape hatch)'
printf '\nRun `gh release create v9.9.9` to publish.\n' \
  >> "$copy/src/skills/issue-triage/SKILL.source.md"
rc=0
run_build "$copy" "$TMP_BASE/o3a.log" || rc=$?
if [ "$rc" -ne 0 ] && grep -q '`gh release create`' "$TMP_BASE/o3a.log"; then
  pass "O3: a form named in catalog prose, not in a table row, still fails"
else
  fail "O3: catalog prose counted as a row (build exit $rc)"
fi

copy="$(make_copy o3-prose-src)"
printf '\nIf gh is not installed, the `gh pr` commands and `gh --version` fail.\n' \
  >> "$copy/src/skills/issue-triage/SKILL.source.md"
if run_build "$copy" "$TMP_BASE/o3b.log"; then
  pass "O3: prose that names gh without a group and verb builds clean"
else
  fail "O3: prose tripped the lint: $(head -5 "$TMP_BASE/o3b.log")"
fi

# ── O5: an argv-list call in a script, with no prose mention, fails ───────
copy="$(make_copy o5)"
target="$copy/src/shared/scripts/gi-issue.py"
printf '\n_PROBE = ["release", "create", "v9.9.9"]\n' >> "$target"
line="$(wc -l < "$target" | tr -d ' ')"
rc=0
run_build "$copy" "$TMP_BASE/o5.log" || rc=$?
if [ "$rc" -ne 0 ] \
  && grep -qF "src/shared/scripts/gi-issue.py:$line: \`gh release create\`" "$TMP_BASE/o5.log"; then
  pass "O5: an uncatalogued argv-list call in a shared script fails the build"
else
  fail "O5: build exit $rc; log: $(head -5 "$TMP_BASE/o5.log")"
fi

F="$TMP_BASE/o5-count"
mkdir -p "$F/docs" "$F/scripts"
cp -R "$REPO_ROOT/src" "$F/src"
cp "$REPO_ROOT/docs/config-schema.md" "$F/docs/config-schema.md"
cp "$REPO_ROOT/scripts/surface-counts.json" "$F/scripts/surface-counts.json"
printf 'ARGS = ["pr", "view", "1", "--json", "state"]\n' > "$F/src/skills/issue-triage/zz_probe.py"
rc=0
OUT="$(python3 "$REPO_ROOT/scripts/surface-count.py" --root "$F" --check 2>&1)" || rc=$?
if [ "$rc" -eq 1 ] && echo "$OUT" | grep -q '✗ gh_call_files: rose from' \
  && [ "$(echo "$OUT" | grep -c ': rose from')" -eq 1 ]; then
  pass "O5: a new file whose only gh call is an argv list raises gh_call_files"
else
  fail "O5: argv-only file: exit $rc, output: $OUT"
fi

# ── A catalog with no Operation catalog section fails ─────────────────────
copy="$(make_copy no-section)"
replace "$copy/docs/platform-github.md" '## Operation catalog' '## Operations'
rc=0
run_build "$copy" "$TMP_BASE/ns.log" || rc=$?
if [ "$rc" -ne 0 ] && grep -q 'Operation catalog' "$TMP_BASE/ns.log"; then
  pass "a platform-github.md without its Operation catalog section fails the build"
else
  fail "missing catalog section: build exit $rc"
fi

# ── AC2 / O4: the recorded count is the lint's own scan ───────────────────
OUT="$(PYTHONDONTWRITEBYTECODE=1 python3 - "$MODULE" "$REPO_ROOT" <<'PY'
import importlib.util, json, os, sys
spec = importlib.util.spec_from_file_location("gh_catalog", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
root = sys.argv[2]
counts = json.load(open(os.path.join(root, "scripts/surface-counts.json")))["counts"]
print(m.files_with_calls(os.path.join(root, "src")), counts.get("gh_call_files", "absent"))
PY
)"
read -r SCANNED RECORDED <<<"$OUT"
if [ "$SCANNED" = "$RECORDED" ]; then
  pass "AC2: scripts/surface-counts.json records gh_call_files = $RECORDED, the lint's scan"
else
  fail "AC2: the lint scans $SCANNED files with gh calls; the ratchet records $RECORDED"
fi

if grep -q 'gh_catalog.py' "$REPO_ROOT/scripts/surface-count.py" \
  && grep -q 'from .gh_catalog import' "$REPO_ROOT/scripts/build/validation.py"; then
  pass "O4: surface-count.py and the build lint both load scripts/build/gh_catalog.py"
else
  fail "O4: the count and the lint do not share scripts/build/gh_catalog.py"
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ the gh catalog lint does not hold"
  exit 1
fi
echo "  ✓ every gh form in src/ has a catalog row, and the count is recorded"
exit 0
