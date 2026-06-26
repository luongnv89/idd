#!/usr/bin/env bash
# test-landing-structure.sh — Validate landing.html structure for the batched
# landing-page fixes (issues #147, #148, #149, #150).
#
# Asserts:
#   #147 — hero terminal is compact; redundant second eyebrow pill removed
#   #148 — .feat-grid is explicitly closed before .model-highlight so the
#          "Cost-aware by default" panel is full-width (balanced <div> count)
#   #149 — screenshots render as a single slideshow (track + 5 slides + nav/dots)
#   #150 — install section shows only the single full-pack command; the multi-tab
#          UI and partial/source/first-run commands are gone
#
# This is a static HTML page — there is no JS test runner — so this test does
# structural string + tag-balance checks only.
#
# Usage: bash tests/test-landing-structure.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LANDING="$REPO_ROOT/landing.html"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Landing Structure Tests (issues #147 #148 #149 #150)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# T0: file exists
if [ -f "$LANDING" ]; then
  pass "T0: landing.html exists"
else
  fail "T0: landing.html missing"
  echo "Result: $PASS passed, $FAIL failed"
  exit 1
fi

# ── Tag balance (overall integrity; #148 root cause was an unclosed grid) ──
opens=$(grep -o '<div\b' "$LANDING" | wc -l | tr -d ' ')
closes=$(grep -o '</div>' "$LANDING" | wc -l | tr -d ' ')
if [ "$opens" = "$closes" ]; then
  pass "T1: <div> tags balanced ($opens open / $closes close)"
else
  fail "T1: <div> imbalance — $opens open vs $closes close"
fi

# ── #147: hero terminal compact + single eyebrow ──
if grep -q 'class="terminal compact reveal"' "$LANDING"; then
  pass "T2 (#147): hero terminal uses compact sizing"
else
  fail "T2 (#147): hero terminal not marked compact"
fi
eyebrows=$(grep -c 'class="eyebrow' "$LANDING" || true)
if [ "$eyebrows" -le 1 ]; then
  pass "T3 (#147): redundant hero eyebrow pill removed ($eyebrows remaining)"
else
  fail "T3 (#147): expected <=1 hero eyebrow, found $eyebrows"
fi

# ── #148: model-highlight sits OUTSIDE feat-grid ──
# The feat-grid must close (</div>) before .model-highlight opens.
if grep -Pzoq '</div>\s*\n\s*<div class="model-highlight' "$LANDING"; then
  pass "T4 (#148): .model-highlight is a sibling of .feat-grid (panel full-width)"
else
  fail "T4 (#148): .model-highlight still nested inside .feat-grid"
fi

# ── #149: slideshow markup present ──
if grep -q 'id="shots-track"' "$LANDING" \
   && grep -q 'id="shots-prev"' "$LANDING" \
   && grep -q 'id="shots-next"' "$LANDING" \
   && grep -q 'id="shots-dots"' "$LANDING"; then
  pass "T5 (#149): slideshow track + prev/next + dots present"
else
  fail "T5 (#149): slideshow controls missing"
fi
slides=$(grep -c 'aria-roledescription="slide"' "$LANDING" || true)
if [ "$slides" = "5" ]; then
  pass "T6 (#149): all 5 screenshots preserved as slides"
else
  fail "T6 (#149): expected 5 slides, found $slides"
fi
if ! grep -q 'class="shot wide' "$LANDING"; then
  pass "T7 (#149): old static grid layout removed (no .shot.wide)"
else
  fail "T7 (#149): leftover static grid markup (.shot.wide)"
fi

# ── #150: single full-pack install command only ──
if grep -q 'asm install https://github.com/luongnv89/idd' "$LANDING"; then
  pass "T8 (#150): full-pack install command present"
else
  fail "T8 (#150): full-pack install command missing"
fi
if ! grep -q 'install-tabs' "$LANDING" \
   && ! grep -q 'install-pane' "$LANDING" \
   && ! grep -q '#main:skills/issue-resolver' "$LANDING" \
   && ! grep -q './scripts/install.sh' "$LANDING"; then
  pass "T9 (#150): tabs + partial/source/first-run install commands removed"
else
  fail "T9 (#150): leftover partial install commands or tab UI"
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
