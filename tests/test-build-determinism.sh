#!/usr/bin/env bash
# test-build-determinism.sh — Verify build is byte-deterministic
# (issue #58, §9 of refactor-plan-v10.md, §4.1).
#
# Strategy:
#   Run `./scripts/build.sh --out <tmp-a>` and `./scripts/build.sh --out <tmp-b>`
#   into two distinct directories, then assert byte-identical trees via
#   `diff -r --brief`. Catches non-determinism early (filesystem ordering,
#   timestamps in banners, dict iteration order, etc.).
#
# Usage: bash tests/test-build-determinism.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SH="$REPO_ROOT/scripts/build.sh"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Build Determinism Tests (issue #58)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

OUT_A="$(mktemp -d)"
OUT_B="$(mktemp -d)"
trap 'rm -rf "$OUT_A" "$OUT_B"' EXIT

# ───────────────────────────────────────────────────────────
# T1: build twice into distinct directories
# ───────────────────────────────────────────────────────────
if "$BUILD_SH" --out "$OUT_A" >/dev/null 2>&1; then
  pass "T1.a: first build into $OUT_A succeeds"
else
  fail "T1.a: first build failed"
  exit 1
fi

if "$BUILD_SH" --out "$OUT_B" >/dev/null 2>&1; then
  pass "T1.b: second build into $OUT_B succeeds"
else
  fail "T1.b: second build failed"
  exit 1
fi

# ───────────────────────────────────────────────────────────
# T2: byte-identical trees
# ───────────────────────────────────────────────────────────
diff_output="$(diff -r --brief "$OUT_A" "$OUT_B" 2>&1 || true)"
if [ -z "$diff_output" ]; then
  pass "T2: builds produce byte-identical trees"
else
  fail "T2: builds differ"
  printf '%s\n' "$diff_output" | head -20 | sed 's/^/    /'
fi

# ───────────────────────────────────────────────────────────
# T3: SHA-256 of all files matches between trees (defense-in-depth).
# diff -r in T2 is the authoritative gate; this is a redundant cross-check.
# Use Python so the aggregate is invariant to xargs batching: a naive
# `find | xargs $HASH_CMD | $HASH_CMD` would split into multiple xargs
# invocations once file count exceeds ARG_MAX, and the outer hash would
# depend on batch count rather than just content.
# ───────────────────────────────────────────────────────────
hash_tree() {
  python3 - "$1" <<'PY'
import hashlib
import os
import sys

root = sys.argv[1]
agg = hashlib.sha256()
files = []
for dirpath, _, filenames in os.walk(root):
    for f in filenames:
        files.append(os.path.relpath(os.path.join(dirpath, f), root))
files.sort()
for rel in files:
    full = os.path.join(root, rel)
    with open(full, "rb") as fh:
        agg.update(fh.read())
print(agg.hexdigest())
PY
}

hash_a="$(hash_tree "$OUT_A")"
hash_b="$(hash_tree "$OUT_B")"
if [ "$hash_a" = "$hash_b" ]; then
  pass "T3: SHA-256 of file contents matches across builds ($hash_a)"
else
  fail "T3: SHA-256 differs ($hash_a vs $hash_b)"
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Build is not deterministic"
  exit 1
fi

echo "  ✓ Build is byte-deterministic"
exit 0
