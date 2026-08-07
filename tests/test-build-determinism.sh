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
MODE_REPORT="$(mktemp)"
trap 'rm -rf "$OUT_A" "$OUT_B"; rm -f "$MODE_REPORT"' EXIT

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
# The mode is folded into the digest as well (issue #251). `diff -r --brief` and
# a content-only hash are both blind to permissions, so a build that emitted a
# shipped script as 0755 once and 0644 the next time would look deterministic
# while shipping a script the installer cannot run.
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
    agg.update(rel.encode("utf-8"))
    agg.update(oct(os.stat(full).st_mode & 0o777).encode("ascii"))
    with open(full, "rb") as fh:
        agg.update(fh.read())
print(agg.hexdigest())
PY
}

hash_a="$(hash_tree "$OUT_A")"
hash_b="$(hash_tree "$OUT_B")"
if [ "$hash_a" = "$hash_b" ]; then
  pass "T3: SHA-256 of file contents + modes matches across builds ($hash_a)"
else
  fail "T3: SHA-256 differs ($hash_a vs $hash_b)"
fi

# ───────────────────────────────────────────────────────────
# T4: shipped scripts keep a stable, executable mode across builds (issue
# #251). This names the failure T3's aggregate can only report as "the digest
# changed", and it fails the same way whichever build lost the exec bit.
# ───────────────────────────────────────────────────────────
python3 - "$OUT_A" "$OUT_B" > "$MODE_REPORT" <<'PY'
import os
import sys
from pathlib import Path

roots = [Path(a) for a in sys.argv[1:3]]
lines = []


def emit(ok, label):
    lines.append(("PASS" if ok else "FAIL") + "|" + label)


def scripts(root):
    return {
        p.relative_to(root).as_posix(): oct(os.stat(p).st_mode & 0o777)
        for p in root.rglob("*")
        if p.is_file() and "/references/scripts/" in "/" + p.relative_to(root).as_posix()
    }


a, b = (scripts(root) for root in roots)
emit(bool(a), f"T4: build A emitted {len(a)} references/scripts/ file(s)")
emit(
    sorted(a) == sorted(b),
    "T4: both builds emit the same references/scripts/ file set",
)
for rel in sorted(set(a) & set(b)):
    emit(a[rel] == b[rel], f"T4: {rel} has the same mode in both builds ({a[rel]} vs {b[rel]})")
    # Exec bit only. Git stores nothing else, so a checkout materialises the
    # source as 0777 & ~umask (0o775 under umask 002, 0o755 under 022) and the
    # build's copy2 faithfully carries that through. Asserting "0o755" would
    # fail every clone made under a non-022 umask on a perfectly correct build.
    emit(int(a[rel], 8) & 0o111 != 0, f"T4: {rel} is executable (mode {a[rel]})")
print("\n".join(lines))
PY

mode_checks=0
while IFS='|' read -r verdict label; do
  [ -n "$verdict" ] || continue
  mode_checks=$((mode_checks + 1))
  if [ "$verdict" = "PASS" ]; then pass "$label"; else fail "$label"; fi
done < "$MODE_REPORT"
if [ "$mode_checks" -eq 0 ]; then
  fail "T4: no references/scripts/ modes were compared — vacuous check"
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
