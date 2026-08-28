#!/usr/bin/env bash
# test-anchors-lib-358.sh — mutation-prove tests/lib/anchors.bash failure modes
# (issue #396, follow-up from #358 / PR #395).
#
# tests/lib/anchors.bash is sourced by the migrated suites but is itself never
# executed: git ls-files 'tests/*.sh' does not match a .bash file. A regression
# in anchor_region would silently defang every migrated assertion at once.
#
# This test asserts every listed failure mode fails loudly against the real
# library, then breaks the corresponding branch in a temp copy and asserts that
# the same check goes green — proving the assertion has teeth.
#
# Usage: bash tests/test-anchors-lib-358.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$REPO_ROOT/tests/lib/anchors.bash"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

# shellcheck source=lib/anchors.bash
. "$LIB"

echo "◆ Anchor library failure-mode tests (issue #396 / #358)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# Fixtures
# ───────────────────────────────────────────────────────────
FIX="$TMP/fixture.md"
cat >"$FIX" <<'EOF'
# Heading

<!-- a:alpha -->
alpha body
TOKEN_ALPHA
<!-- a:beta -->
beta body
TOKEN_BETA
<!-- a:gamma -->
gamma body
TOKEN_GAMMA

<!-- a:dup -->
first dup body
<!-- a:dup -->
second dup body

<!-- a:foo_bar -->
underscore-id body
TOKEN_UNDERSCORE

<!--a:nospace-->
malformed no-space body
TOKEN_MALFORMED
EOF

UNREAD="$TMP/unreadable.md"
cp "$FIX" "$UNREAD"
chmod a-r "$UNREAD"
trap 'chmod u+r "$UNREAD" 2>/dev/null || true; rm -rf "$TMP"' EXIT

MISSING="$TMP/no-such-file.md"

# capture CMD... — run CMD, set OUT and RC without tripping set -e.
capture() {
  RC=0
  OUT="$("$@" 2>/dev/null)" || RC=$?
}

# ───────────────────────────────────────────────────────────
# T0: happy path — unique region is non-empty and stops at the next anchor
# ───────────────────────────────────────────────────────────
capture anchor_region "$FIX" alpha
if [ "$RC" -eq 0 ] && [ -n "$OUT" ] \
   && printf '%s\n' "$OUT" | grep -q TOKEN_ALPHA \
   && ! printf '%s\n' "$OUT" | grep -q TOKEN_BETA; then
  pass "T0: unique region is non-empty and stops before the next anchor"
else
  fail "T0: unique region should succeed, include TOKEN_ALPHA, exclude TOKEN_BETA (rc=$RC)"
fi

# ───────────────────────────────────────────────────────────
# Failure modes against the real library
# ───────────────────────────────────────────────────────────
capture anchor_region "$FIX" no-such-id
if [ "$RC" -ne 0 ]; then
  pass "missing anchor: anchor_region fails loudly (rc=$RC)"
else
  fail "missing anchor: expected non-zero, got 0"
fi

capture anchor_region "$FIX" dup
if [ "$RC" -ne 0 ]; then
  pass "duplicated anchor: anchor_region fails loudly (rc=$RC)"
else
  fail "duplicated anchor: expected non-zero, got 0"
fi

capture anchor_region "$FIX" nospace
if [ "$RC" -ne 0 ]; then
  pass "malformed marker: exact <!-- a:id --> required, nospace form fails (rc=$RC)"
else
  fail "malformed marker: expected non-zero for <!--a:nospace-->, got 0"
fi

if [ -r "$UNREAD" ]; then
  fail "unreadable file: fixture is still readable after chmod a-r"
else
  capture anchor_region "$UNREAD" alpha
  if [ "$RC" -ne 0 ]; then
    pass "unreadable file: anchor_region fails loudly (rc=$RC)"
  else
    fail "unreadable file: expected non-zero, got 0"
  fi
fi

capture anchor_region "$FIX" foo_bar
if [ "$RC" -eq 2 ]; then
  pass "bad id: underscore id is rejected with exit 2"
else
  fail "bad id: expected exit 2 for foo_bar, got $RC"
fi

capture anchor_region "$FIX" '-leading'
if [ "$RC" -eq 2 ]; then
  pass "bad id: leading hyphen is rejected with exit 2"
else
  fail "bad id: expected exit 2 for -leading, got $RC"
fi

capture anchor_span "$FIX" gamma alpha
if [ "$RC" -ne 0 ]; then
  pass "reversed span: end-before-start fails loudly (rc=$RC)"
else
  fail "reversed span: expected non-zero, got 0"
fi

capture anchor_region "$FIX" alpha
if printf '%s\n' "$OUT" | grep -q TOKEN_BETA; then
  fail "region past next anchor: alpha region leaked TOKEN_BETA"
else
  pass "region past next anchor: alpha region does not include TOKEN_BETA"
fi

# ───────────────────────────────────────────────────────────
# Package resolution (issue #426) — the governed artifact is the
# skill package, so a package directory resolves the anchor across
# the skill's own files. ADR: docs/decisions/shared-contract-pin-artifact.md
# ───────────────────────────────────────────────────────────
PKG="$TMP/pkg"
mkdir -p "$PKG/references" "$PKG/references/agents" "$PKG/references/docs"

cat >"$PKG/SKILL.source.md" <<'EOF'
# Fixture skill

<!-- a:pkg-body -->
body contract
TOKEN_PKG_BODY
<!-- a:pkg-body-end -->
after the body span

<!-- a:pkg-shared -->
body copy of a duplicated contract
EOF

cat >"$PKG/references/mechanics.md" <<'EOF'
# Mechanics

<!-- a:pkg-ref -->
relocated contract
TOKEN_PKG_REF

<!-- a:pkg-shared -->
reference copy of a duplicated contract
EOF

cat >"$PKG/references/agents/some-agent.md" <<'EOF'
# Bundled shared agent

<!-- a:pkg-agent-only -->
bundled agent copy — governed by src/shared/agents/, not by this package
EOF

cat >"$PKG/references/docs/some-doc.md" <<'EOF'
# Bundled runtime doc

<!-- a:pkg-doc-only -->
bundled doc copy — governed by docs/, not by this package
EOF

# P1: a body anchor resolves through the package root.
capture anchor_region "$PKG" pkg-body
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q TOKEN_PKG_BODY; then
  pass "P1: package root resolves an anchor in the SKILL body"
else
  fail "P1: package root should resolve a body anchor (rc=$RC)"
fi

# P2: the same call finds a contract that has been relocated into references/.
capture anchor_region "$PKG" pkg-ref
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q TOKEN_PKG_REF; then
  pass "P2: package root resolves an anchor relocated into references/"
else
  fail "P2: package root should resolve a relocated anchor (rc=$RC)"
fi

# P3: teeth — a contract duplicated across two package files is ambiguous.
capture anchor_region "$PKG" pkg-shared
if [ "$RC" -ne 0 ]; then
  pass "P3: anchor duplicated across two package files fails loudly (rc=$RC)"
else
  fail "P3: expected non-zero for an anchor in two package files, got 0"
fi

# P4: teeth — a deleted contract still fails.
capture anchor_region "$PKG" pkg-no-such
if [ "$RC" -ne 0 ]; then
  pass "P4: anchor absent from the package fails loudly (rc=$RC)"
else
  fail "P4: expected non-zero for an anchor absent from the package, got 0"
fi

# P5: bundled shared agents and docs are NOT package contract sites — they are
# copies of sources under src/shared/ and docs/ (ADR D1).
capture anchor_region "$PKG" pkg-agent-only
if [ "$RC" -ne 0 ]; then
  pass "P5.1: references/agents/ is outside the package (rc=$RC)"
else
  fail "P5.1: references/agents/ must not resolve as a package contract site"
fi
capture anchor_region "$PKG" pkg-doc-only
if [ "$RC" -ne 0 ]; then
  pass "P5.2: references/docs/ is outside the package (rc=$RC)"
else
  fail "P5.2: references/docs/ must not resolve as a package contract site"
fi

# P6: a span stays inside one document — an end anchor in another file fails.
capture anchor_span "$PKG" pkg-body pkg-body-end
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q TOKEN_PKG_BODY; then
  pass "P6.1: package span resolves within one file"
else
  fail "P6.1: package span should resolve within one file (rc=$RC)"
fi
capture anchor_span "$PKG" pkg-body pkg-ref
if [ "$RC" -ne 0 ]; then
  pass "P6.2: a span whose end anchor is in another package file fails (rc=$RC)"
else
  fail "P6.2: expected non-zero for a cross-file span, got 0"
fi

# P7: bad ids are still rejected before any package lookup.
capture anchor_region "$PKG" foo_bar
if [ "$RC" -eq 2 ]; then
  pass "P7: bad id is rejected with exit 2 even for a package root"
else
  fail "P7: expected exit 2 for foo_bar against a package root, got $RC"
fi

# P8: against the real repo — a package root resolves both trees.
capture anchor_package_file "$REPO_ROOT/src/skills/issue-pr-review" rv-step5-ci
if [ "$RC" -eq 0 ] && [ "$OUT" = "$REPO_ROOT/src/skills/issue-pr-review/SKILL.source.md" ]; then
  pass "P8.1: real src package resolves rv-step5-ci to SKILL.source.md"
else
  fail "P8.1: real src package should resolve rv-step5-ci to the body (rc=$RC, out=$OUT)"
fi
capture anchor_package_file "$REPO_ROOT/skills/issue-pr-review" rvm-trusted-skips
if [ "$RC" -eq 0 ] && [ "$OUT" = "$REPO_ROOT/skills/issue-pr-review/references/review-loop-mechanics.md" ]; then
  pass "P8.2: real built package resolves rvm-trusted-skips to its reference file"
else
  fail "P8.2: real built package should resolve rvm-trusted-skips (rc=$RC, out=$OUT)"
fi

# ───────────────────────────────────────────────────────────
# Mutation harness — each needle must occur exactly once
# ───────────────────────────────────────────────────────────
apply_mut() {
  local name="$1" old="$2" new="$3"
  python3 - "$LIB" "$TMP/$name.bash" "$old" "$new" <<'PY'
import sys
from pathlib import Path

src, dst, old, new = sys.argv[1:5]
text = Path(src).read_text()
count = text.count(old)
if count != 1:
    sys.stderr.write(f"mutation needle count {count} != 1\n")
    sys.exit(2)
Path(dst).write_text(text.replace(old, new, 1))
PY
}

# prove_defanged NAME OLD NEW LABEL CHECK
# CHECK is a bash snippet sourced after the mutant. It must exit 0 when the
# broken branch has been defanged (the original assertion would now be red).
prove_defanged() {
  local name="$1" old="$2" new="$3" label="$4" check="$5"
  if ! apply_mut "$name" "$old" "$new"; then
    fail "$label: mutation needle was not unique — harness cannot prove teeth"
    return
  fi
  if bash -c '
    set -euo pipefail
    # shellcheck disable=SC1090
    . "$1"
    FIX="$2"
    UNREAD="$3"
    PKG="$4"
    eval "$5"
  ' _ "$TMP/$name.bash" "$FIX" "$UNREAD" "$PKG" "$check"; then
    pass "$label: breaking the branch defangs the assertion"
  else
    fail "$label: mutant still fails — assertion would stay green (vacuous)"
  fi
}

# missing: drop the uniqueness/presence check in anchor_region
prove_defanged missing \
  '[ "${hits:-0}" = "1" ] || return 1' \
  ': # hits check removed' \
  "mutation/missing" \
  'capture(){ RC=0; OUT="$("$@" 2>/dev/null)" || RC=$?; }
   capture anchor_region "$FIX" no-such-id
   [ "$RC" -eq 0 ]'

# duplicated: accept any non-zero hit count (presence without uniqueness)
prove_defanged duplicated \
  '[ "${hits:-0}" = "1" ] || return 1' \
  '[ "${hits:-0}" != "0" ] || return 1' \
  "mutation/duplicated" \
  'capture(){ RC=0; OUT="$("$@" 2>/dev/null)" || RC=$?; }
   capture anchor_region "$FIX" dup
   [ "$RC" -eq 0 ]'

# malformed: accept the no-space comment form <!--a:id-->
prove_defanged malformed \
  'hits="$(grep -cF -- "<!-- a:${id} -->" "$file" 2>/dev/null || true)"' \
  'hits="$(grep -cE -- "<!-- *a:${id} *-->" "$file" 2>/dev/null || true)"' \
  "mutation/malformed" \
  'capture(){ RC=0; OUT="$("$@" 2>/dev/null)" || RC=$?; }
   capture anchor_region "$FIX" nospace
   [ "$RC" -eq 0 ]'

# unreadable: treat an unreadable file as success (return 0 before grep).
# Needle includes the following hits= line so it matches only anchor_region.
prove_defanged unreadable \
  '[ -r "$file" ] || return 1

  hits="$(grep -cF -- "<!-- a:${id} -->" "$file" 2>/dev/null || true)"' \
  '[ -r "$file" ] || return 0

  hits="$(grep -cF -- "<!-- a:${id} -->" "$file" 2>/dev/null || true)"' \
  "mutation/unreadable" \
  'capture(){ RC=0; OUT="$("$@" 2>/dev/null)" || RC=$?; }
   capture anchor_region "$UNREAD" alpha
   [ "$RC" -eq 0 ]'

# bad id: drop the grammar gate in anchor_region so foo_bar proceeds.
# The two-space `case "$id"` is unique to anchor_region (span indents more).
prove_defanged badid \
  $'  case "$id" in\n    *[!a-z0-9-]* | \'\' | -* | *-) return 2 ;;\n  esac' \
  $'  case "$id" in\n    *[!a-z0-9-]* | \'\' | -* | *-) : ;;\n  esac' \
  "mutation/bad-id" \
  'capture(){ RC=0; OUT="$("$@" 2>/dev/null)" || RC=$?; }
   capture anchor_region "$FIX" foo_bar
   [ "$RC" -eq 0 ]'

# reversed span: always accept the awk END status
prove_defanged reversed \
  'END { exit ok ? 0 : 1 }' \
  'END { exit 0 }' \
  "mutation/reversed-span" \
  'capture(){ RC=0; OUT="$("$@" 2>/dev/null)" || RC=$?; }
   capture anchor_span "$FIX" gamma alpha
   [ "$RC" -eq 0 ]'

# past the next anchor: stop only at headings, not at the next <!-- a: -->
prove_defanged pastnext \
  'seen && !fence && ($0 ~ /^#+ / || $0 ~ /<!-- a:[a-z0-9-]+ -->/) { exit }' \
  'seen && !fence && ($0 ~ /^#+ /) { exit }' \
  "mutation/past-next-anchor" \
  'capture(){ RC=0; OUT="$("$@" 2>/dev/null)" || RC=$?; }
   capture anchor_region "$FIX" alpha
   [ "$RC" -eq 0 ] && printf "%s\n" "$OUT" | grep -q TOKEN_BETA'

# package resolution: accept an anchor found in two package files
prove_defanged pkgdup \
    '[ -z "$found" ] || return 1' \
    '[ -z "$found" ] || found="$found"' \
  "mutation/package-cross-file-duplicate" \
  'capture(){ RC=0; OUT="$("$@" 2>/dev/null)" || RC=$?; }
   capture anchor_region "$PKG" pkg-shared
   [ "$RC" -eq 0 ]'

echo
echo "  Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
