#!/usr/bin/env bash
# test-build-negative-mutations.sh — Negative tests against mutated src copies
# (issue #334, F-TEST-002 from MODERNIZATION_REPORT.md, plan task 0.2).
#
# Strategy:
#   Every build.py validator is tested positively only elsewhere; a refactor
#   neutering validators would pass while shipping corrupt dist output. This
#   script copies the real src/ + docs/ into a temp tree per mutation, applies
#   one mutation, runs the non-mutating build form against the copy, and
#   asserts the build fails (exit != 0) with a non-empty error message:
#
#     M1  broken docs/X.md token reference   → unresolved doc reference
#     M2  dropped digest section             → missing digest section(s)
#     M3  drifted config default (init's
#         .gitissue.yml template vs schema)  → template/schema parity failed
#     M4  perturbed digest byte-size budget  → measured size drift
#
#   A T0 baseline first builds an unmutated copy so a broken main-branch tree
#   is reported as such instead of as four bogus validator failures.
#
# Usage: bash tests/test-build-negative-mutations.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_BASE="$(mktemp -d)"
trap 'rm -rf "$TMP_BASE"' EXIT

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

# make_copy <name> — fresh src/, docs/, and build entry point/package under
# $TMP_BASE/<name>. Mutations run through the scratch public entry point so they
# can safely change build implementation constants as well as build inputs.
make_copy() {
  local copy="$TMP_BASE/$1"
  rm -rf "$copy"
  mkdir -p "$copy/scripts"
  cp -R "$REPO_ROOT/src" "$copy/src"
  cp -R "$REPO_ROOT/docs" "$copy/docs"
  cp "$REPO_ROOT/scripts/build.py" "$copy/scripts/build.py"
  cp -R "$REPO_ROOT/scripts/build" "$copy/scripts/build"
  printf '%s' "$copy"
}

# run_build <copy> <logfile> — non-mutating build form against a copied tree.
# Returns the build's exit code; never trips set -e.
run_build() {
  local copy="$1" log="$2" rc=0
  PYTHONDONTWRITEBYTECODE=1 python3 "$copy/scripts/build.py" \
    --out "$copy/dist" --src "$copy/src" --no-root-skills \
    >"$log.stdout" 2>"$log.stderr" || rc=$?
  cat "$log.stdout" "$log.stderr" >"$log"
  return "$rc"
}

echo "◆ Build Negative Mutation Tests (issue #334)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T0: unmutated copy still builds clean
# ───────────────────────────────────────────────────────────
copy="$(make_copy t0-baseline)"
if run_build "$copy" "$TMP_BASE/t0.log"; then
  pass "T0: unmutated src/+docs/ copy builds clean"
else
  fail "T0: unmutated copy failed to build — validators or tree are broken upstream"
  sed 's/^/      /' "$TMP_BASE/t0.log" | head -10
  echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
  echo "  Passed: $PASS"
  echo "  Failed: $FAIL"
  exit 1
fi

# assert_build_fails <id> <label> <copy> — the core negative assertion: the
# mutated copy must fail the build AND capture a non-empty error message.
assert_build_fails() {
  local id="$1" label="$2" copy="$3"
  local log="$TMP_BASE/$id.log" rc=0
  run_build "$copy" "$log" || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "$label: build exited 0 — validator did not catch the mutation"
    return
  fi
  if [ ! -s "$log" ]; then
    fail "$label: build failed (exit $rc) but captured no error message"
    return
  fi
  pass "$label: build rejected the mutation (exit $rc, error captured)"
}

# ───────────────────────────────────────────────────────────
# M1: broken docs/X.md token reference
# A skill source citing a docs/*.md that does not exist must abort the
# closure walk ("unresolved doc reference").
# ───────────────────────────────────────────────────────────
copy="$(make_copy m1-doc-token)"
printf '\nSee also docs/no-such-negative-mutation-doc-334.md for details.\n' \
  >>"$copy/src/skills/issue-triage/SKILL.source.md"
assert_build_fails m1 "M1: broken docs/X.md token reference" "$copy"

# ───────────────────────────────────────────────────────────
# M2: dropped digest section
# Deleting a DOC_SECTION_DIGESTS heading from a digested doc must abort at
# emission time ("missing digest section(s)") rather than silently emit a
# truncated runtime document.
# ───────────────────────────────────────────────────────────
copy="$(make_copy m2-digest-section)"
python3 - "$copy/docs/platform-github.md" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
new, n = re.subn(r"^## Driver rules\n.*?(?=^## )", "", text, flags=re.S | re.M)
if n != 1:
    sys.exit(f"mutation failed: expected exactly one '## Driver rules' section, found {n}")
path.write_text(new, encoding="utf-8")
PY
assert_build_fails m2 "M2: dropped digest section" "$copy"

# ───────────────────────────────────────────────────────────
# M3: drifted config excerpt vs .gitissue.yml defaults
# init-gitissue renders .gitissue.yml field by field from its template; one
# drifted documented default must abort parity validation.
# ───────────────────────────────────────────────────────────
copy="$(make_copy m3-config-drift)"
template="$copy/src/skills/init-gitissue/templates/gitissue-template.yml"
if ! grep -q '^  max_commits: 10$' "$template"; then
  fail "M3: fixture drift — 'max_commits: 10' not found in gitissue-template.yml"
elif ! sed -i.bak 's/^  max_commits: 10$/  max_commits: 99/' "$template"; then
  fail "M3: could not apply config drift to gitissue-template.yml"
else
  rm -f "$template.bak"
  assert_build_fails m3 "M3: drifted config excerpt vs .gitissue.yml" "$copy"
fi

# ───────────────────────────────────────────────────────────
# M4: perturbed digest byte-size budget
# Changing a reviewed digest size in the scratch build package must fail with a
# clear measured-vs-expected diagnostic from the real build entry point.
# ───────────────────────────────────────────────────────────
copy="$(make_copy m4-digest-size)"
common="$copy/scripts/build/common.py"
python3 - "$common" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
pattern = r'("platform-github\.md": \(\d+, )(\d+)(\),)'
new, count = re.subn(
    pattern,
    lambda match: match.group(1) + str(int(match.group(2)) + 1) + match.group(3),
    text,
)
if count != 1:
    sys.exit(f"mutation failed: expected exactly one digest budget, found {count}")
path.write_text(new, encoding="utf-8")
PY
log="$TMP_BASE/m4.log"
rc=0
run_build "$copy" "$log" || rc=$?
if [ "$rc" -eq 0 ]; then
  fail "M4: perturbed digest byte-size budget: build exited 0"
elif grep -q "platform-github.md digest byte-size drift" "$log" && \
     grep -q "expected source=.*bytes and digest=.*bytes; measured source=.*bytes and digest=.*bytes" "$log"; then
  pass "M4: perturbed digest byte-size budget: build reported expected and measured bytes"
else
  fail "M4: perturbed digest byte-size budget: build failed without a clear size diagnostic"
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Negative build mutations are not all caught"
  exit 1
fi

echo "  ✓ Every validator mutation fails the build with a captured error"
exit 0
