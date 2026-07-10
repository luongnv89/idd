#!/usr/bin/env bash
# test-issue-creator-modes.sh — Validate the /issue-creator normalize, batch,
# and dry-run mode surfaces (issue #200, epic #182 Phase 2).
#
# This is a documentation/contract test in the same style as
# tests/test-runs-jsonl.sh: it greps the authored src/ sources
# (SKILL.source.md + references/modes.md) and asserts the documented behavior
# of the Normalize, Batch, and dry-run surfaces is present and consistent. It
# does NOT call the GitHub API or run the skill (no network).
#
# Scope note: the existing tests/test-issue-creator-confidence-191.sh already
# covers the confidence-marker placeholders and confidence-scoring.md — this
# suite covers the MODE surfaces it does not (invocation table, normalize
# safety steps, batch pipeline, dry-run stop). Batch mode gained optional epic
# support in #198 (`--parent`, `Part of #{parent}`, parent checklist); a few
# assertions confirm that surface exists but stay on STABLE documented
# behavior — no illustrative example values that #201 may churn.
#
# Usage: bash tests/test-issue-creator-modes.sh
# Returns: exit 0 if all tests pass, exit 1 on any failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() {
  echo "  ✓ $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  ✗ $1"
  FAIL=$((FAIL + 1))
}

has() {
  # $1 = file, $2 = pattern, $3 = label
  if grep -qF -e "$2" "$1" 2>/dev/null; then
    pass "$3"
  else
    fail "$3 (missing: '$2' in ${1#$REPO_ROOT/})"
  fi
}

echo "◆ /issue-creator mode surfaces Tests (issue #200)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

SKILL="$REPO_ROOT/src/skills/issue-creator/SKILL.source.md"
MODES="$REPO_ROOT/src/skills/issue-creator/references/modes.md"

# --- T1: both sources exist -------------------------------------------------
if [ -f "$SKILL" ]; then
  pass "T1: issue-creator SKILL.source.md exists"
else
  fail "T1: issue-creator SKILL.source.md missing"
fi
if [ -f "$MODES" ]; then
  pass "T1: references/modes.md exists"
else
  fail "T1: references/modes.md missing"
fi

# --- T2: the three modes are declared ---------------------------------------
# The SKILL front-matter/body names Create, Normalize, and Batch.
has "$SKILL" "Create"    "T2: SKILL declares Create mode"
has "$SKILL" "Normalize" "T2: SKILL declares Normalize mode"
has "$SKILL" "Batch"     "T2: SKILL declares Batch mode"

# --- T3: mode-detection / invocation table ----------------------------------
# A bare number → Normalize; multi-item text → Batch; a number is NEVER a
# parent (that guards the #198 epic surface against mis-routing).
has "$SKILL" "/issue-creator <N>"             "T3: invocation table has bare-N normalize"
has "$SKILL" "/issue-creator <N> --dry-run"   "T3: invocation table has --dry-run preview"
has "$SKILL" "argument is a number → Normalize" "T3: mode detection routes a number to Normalize"

# --- T4: Normalize mode documented behavior (modes.md) ----------------------
# Idempotency marker, security-label skip, backup-before-edit safety, and the
# normalized marker are the stable documented contract of Normalize mode.
has "$MODES" "gitissue:normalized v1"          "T4: normalize checks/writes the normalized marker"
has "$MODES" "already normalized"              "T4: normalize is idempotent (already-normalized skip)"
has "$MODES" "security label"                  "T4: normalize skips security-labeled issues"
has "$MODES" "Backup Original Body"            "T4: normalize backs up the original body before edit"
has "$MODES" "Reporter Context"                "T4: normalize preserves original text in Reporter Context"

# --- T5: dry-run surface -----------------------------------------------------
# --dry-run (or the [Y/n/dry-run] prompt selection) previews and stops without
# applying any change. This is the documented no-mutation guarantee.
has "$SKILL" "--dry-run"                        "T5: SKILL documents the --dry-run flag"
has "$MODES" "Dry Run Check"                    "T5: modes.md has a Dry Run Check step"
has "$MODES" "Dry run complete. No changes applied." "T5: dry-run stops with no changes applied"

# --- T6: Batch mode pipeline (modes.md) -------------------------------------
# Detect items → preview → duplicate check → approval → create sequentially,
# with per-item success/failure tracking. Stable documented pipeline.
has "$MODES" "Batch Create"                     "T6: modes.md documents Batch Create mode"
has "$MODES" "Detect Items"                     "T6: batch detects distinct items"
has "$MODES" "Preview Table"                    "T6: batch previews parsed items before creating"
has "$MODES" "Duplicate Check"                  "T6: batch runs a duplicate check"
has "$MODES" "fall through to single Create mode" "T6: single-item batch falls back to Create"
has "$MODES" "Partial failure"                  "T6: batch tracks per-item partial failure"

# --- T7: Batch epic surface (#198 — additive, do not over-assert values) ----
# Confirm the epic-binding surface EXISTS without pinning illustrative numbers.
has "$SKILL" "--parent <N>"                     "T7: SKILL documents the --parent epic flag"
has "$MODES" "Part of #{parent}"                "T7: batch appends the Part of #{parent} child marker"
has "$MODES" "Epic Binding"                     "T7: modes.md has the optional Epic Binding step"
# Additive guarantee: a batch without --parent behaves as before.
has "$MODES" "without a parent"                 "T7: epic step is skipped when no parent is bound"

# --- T8: reporter-text-as-untrusted-data boundary ---------------------------
# Normalize/Batch treat issue bodies + pasted docs as data, never instructions.
has "$SKILL" "untrusted data"                   "T8: SKILL declares reporter text is untrusted data"

echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
else
  echo "  ✓ All tests passed"
  exit 0
fi
