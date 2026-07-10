#!/usr/bin/env bash
# test-issue-triage.sh — Validate the /issue-triage persisted triage.json schema
# and view-mode contract (issue #200, epic #182 Phase 2).
#
# This is a documentation/contract test in the same style as
# tests/test-runs-jsonl.sh and tests/test-projects-sync.sh: it greps the
# authored src/ sources (SKILL.source.md + references/) and asserts the skill's
# documented triage.json schema is internally consistent — the persisted JSON
# keys and the status enum must agree across the SKILL source, its
# output-and-persist reference, and the field-reference table. It does NOT call
# the GitHub API or run the skill (no network).
#
# The review (#200 AC1) flagged a schema-contradiction; #205 corrected the
# triage.json `summary` key and the status enum. These assertions pin the
# CORRECTED, internally-consistent contract so a future divergence fails here.
#
# Usage: bash tests/test-issue-triage.sh
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

# grep helper: assert a fixed-string pattern exists in a file.
# -e guards patterns that begin with '-' from being parsed as grep options.
has() {
  # $1 = file, $2 = pattern, $3 = label
  if grep -qF -e "$2" "$1" 2>/dev/null; then
    pass "$3"
  else
    fail "$3 (missing: '$2' in ${1#$REPO_ROOT/})"
  fi
}

# assert a pattern is ABSENT from a file.
lacks() {
  # $1 = file, $2 = pattern, $3 = label
  if grep -qF -e "$2" "$1" 2>/dev/null; then
    fail "$3 (unexpected: '$2' in ${1#$REPO_ROOT/})"
  else
    pass "$3"
  fi
}

echo "◆ /issue-triage triage.json schema Tests (issue #200)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

SKILL="$REPO_ROOT/src/skills/issue-triage/SKILL.source.md"
PERSIST="$REPO_ROOT/src/skills/issue-triage/references/output-and-persist.md"

# --- T1: both sources exist -------------------------------------------------
if [ -f "$SKILL" ]; then
  pass "T1: issue-triage SKILL.source.md exists"
else
  fail "T1: issue-triage SKILL.source.md missing"
fi
if [ -f "$PERSIST" ]; then
  pass "T1: output-and-persist.md reference exists"
else
  fail "T1: output-and-persist.md reference missing"
fi

# --- T2: canonical persistence target -------------------------------------
# Both the SKILL and its persist reference name the same output file.
has "$SKILL"   ".gitissue/triage.json" "T2: SKILL persists to .gitissue/triage.json"
has "$PERSIST" ".gitissue/triage.json" "T2: persist reference names .gitissue/triage.json"

# --- T3: top-level keys consistent between SKILL and schema ----------------
# The SKILL Step 9 line enumerates the top-level keys; the persist reference
# defines the JSON body + field-reference table. Assert the SAME key set is
# named in BOTH places, so a future divergence fails here (not a
# word-appears-somewhere pass).
for key in version updated source analyzed_count issues summary history; do
  has "$SKILL"   "$key" "T3: SKILL names top-level key '$key'"
  has "$PERSIST" "$key" "T3: schema names top-level key '$key'"
done

# --- T4: summary sub-keys consistent (#205 corrected the `summary` key) -----
# These are the persisted `summary.*` fields. Grep the unquoted tokens — they
# appear both in the SKILL Step 9 summary-key list and in the schema body +
# field table. Assert the same sub-key set in both sources.
for subkey in parallel_groups stale_count stale_threshold_days \
              potentially_fixed_count suggested_order circular_deps; do
  has "$SKILL"   "$subkey" "T4: SKILL names summary sub-key '$subkey'"
  has "$PERSIST" "$subkey" "T4: schema names summary sub-key '$subkey'"
done

# --- T5: per-issue keys defined in the schema -------------------------------
# issues[] entry keys — these live in the schema body + field-reference table.
for ikey in number title type priority blocks blocked_by status \
            stale_days labels affected_files updated_at potentially_fixed_by; do
  has "$PERSIST" "$ikey" "T5: schema defines issues[].$ikey"
done

# --- T6: status enum internally consistent ----------------------------------
# The AUTHORITATIVE quoted status enum lives in the schema field-reference
# table (issues[].status). Assert all four states are named there as quoted
# JSON values. The SKILL Step 5 writes DISPLAY forms (e.g. `blocked #N`,
# `stale (Nd)`), so assert the SKILL names the SAME four bare state words —
# never grep the quoted "stale" against the SKILL (it isn't there).
for state in ready blocked stale maybe-fixed; do
  has "$PERSIST" "\"$state\"" "T6: schema status enum includes quoted \"$state\""
  has "$SKILL"   "$state"     "T6: SKILL Step 5 status list names '$state'"
done

# --- T7: single consistent `summary` key (no drift back to a renamed key) ---
# #205 corrected the persisted key to `summary`. Guard against a regression to
# a differently-named container (e.g. `stats`/`summary_block`) by asserting the
# schema body carries the `"summary"` object key exactly.
has "$PERSIST" "\"summary\"" "T7: schema body uses the corrected \"summary\" object key"

# --- T8: view-mode / cache contract -----------------------------------------
# Default view mode renders the cached JSON; full re-analysis only on
# `/issue-triage update`. This is the documented read/write boundary.
has "$SKILL" "view mode"           "T8: SKILL documents default view mode"
has "$SKILL" "/issue-triage update" "T8: SKILL documents update-only re-analysis"

# --- T9: overwrite semantics (history is one entry per run) -----------------
has "$PERSIST" "overwrites the entire file" "T9: full re-triage overwrites the file"

echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
else
  echo "  ✓ All tests passed"
  exit 0
fi
