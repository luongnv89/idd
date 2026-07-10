#!/usr/bin/env bash
# test-idd-lint-stats-project.sh — Validate that `idd-lint stats` reports the
# project being analyzed (name + filesystem location) in both text and JSON
# output, and resolves the name via the gh → remote-URL → dirname fallback
# chain without making a network call in --no-github mode.
#
# Behavioral test: it runs scripts/idd-lint.py against throwaway git repos in a
# temp dir, so it needs only python3 + git (no gh, no network).
#
# Usage: bash tests/test-idd-lint-stats-project.sh
# Returns: exit 0 if all tests pass, exit 1 on failure summary.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$REPO_ROOT/scripts/idd-lint.py"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ idd-lint stats — project identity Tests"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Build a throwaway repo with a known remote and a copy of the linter.
make_repo() {
  # $1 = dir name, $2 = optional remote URL
  local d="$TMP/$1"
  mkdir -p "$d/scripts"
  cp "$LINT" "$d/scripts/idd-lint.py"
  git -C "$d" init -q
  git -C "$d" config user.email t@t.co
  git -C "$d" config user.name t
  [ -n "${2:-}" ] && git -C "$d" remote add origin "$2"
  ( cd "$d" && git add -A && git commit -qm "chore: init (#1)" )
  echo "$d"
}

# ── T1: name from remote URL (offline, no gh) ──
R1="$(make_repo acme-app git@github.com:acme/widget.git)"
OUT1="$( cd "$R1" && python3 scripts/idd-lint.py stats --no-github 2>/dev/null )"
if printf '%s\n' "$OUT1" | grep -qF "project  acme/widget"; then
  pass "T1: project name derived from git remote (acme/widget)"
else
  fail "T1: expected 'project  acme/widget' in text output"
fi
# Assert on a 'location ...<basename>' line rather than the full path: git's
# --show-toplevel canonicalizes symlinks (macOS /var → /private/var), so the
# printed path may differ from $R1's literal mktemp path.
if printf '%s\n' "$OUT1" | grep -qE "location .*/acme-app$"; then
  pass "T1: project location shows the checkout path"
else
  fail "T1: expected a 'location .../acme-app' line in text output"
fi

# ── T2: HTTPS remote parses too ──
R2="$(make_repo beta-proj https://github.com/beta/thing.git)"
OUT2="$( cd "$R2" && python3 scripts/idd-lint.py stats --no-github 2>/dev/null )"
if printf '%s\n' "$OUT2" | grep -qF "project  beta/thing"; then
  pass "T2: project name parsed from HTTPS remote (beta/thing)"
else
  fail "T2: expected 'project  beta/thing'"
fi

# ── T3: no remote → falls back to directory basename ──
R3="$(make_repo lonely-repo)"
OUT3="$( cd "$R3" && python3 scripts/idd-lint.py stats --no-github 2>/dev/null )"
if printf '%s\n' "$OUT3" | grep -qF "project  lonely-repo"; then
  pass "T3: project name falls back to directory basename (lonely-repo)"
else
  fail "T3: expected 'project  lonely-repo'"
fi

# ── T4: JSON output carries a project block with name + location ──
JSON="$( cd "$R1" && python3 scripts/idd-lint.py stats --no-github --json 2>/dev/null )"
if printf '%s\n' "$JSON" | python3 -c '
import sys, json
d = json.load(sys.stdin)
p = d.get("project") or {}
assert p.get("name") == "acme/widget", p
assert p.get("location", "").endswith("acme-app"), p
'; then
  pass "T4: --json includes project.name and project.location"
else
  fail "T4: --json project block missing or wrong"
fi

# ── T5: --no-github makes NO gh call (fake failing gh must never be invoked) ──
FAKEBIN="$TMP/fakebin"
mkdir -p "$FAKEBIN"
printf '#!/bin/sh\necho GH_WAS_CALLED >&2\nexit 1\n' > "$FAKEBIN/gh"
chmod +x "$FAKEBIN/gh"
GHERR="$TMP/gh.err"
( cd "$R1" && PATH="$FAKEBIN:$PATH" python3 scripts/idd-lint.py stats --no-github 2>"$GHERR" >/dev/null )
if ! grep -q GH_WAS_CALLED "$GHERR"; then
  pass "T5: --no-github resolves project name without invoking gh"
else
  fail "T5: gh was called in --no-github mode (should be offline)"
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
