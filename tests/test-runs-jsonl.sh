#!/usr/bin/env bash
# test-runs-jsonl.sh — Validate the .gitissue/runs.jsonl run-log + idd-doctor
# run-log summary documentation (issue #141 / weakness W3).
#
# This is a documentation/contract test in the same style as
# tests/test-projects-sync.sh: it asserts that the run-log behavior is
# specified in the canonical schema doc, wired into the two writer skills, and
# summarized by /idd-doctor — in both the authored src/ sources and the
# generated skills/ install surface.
#
# Usage: bash tests/test-runs-jsonl.sh
# Returns: exit 0 if all tests pass, exit 1 on first failure summary.

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

# grep helper: assert a pattern (fixed string) exists in a file.
has() {
  # $1 = file, $2 = pattern, $3 = label
  if grep -qiF "$2" "$1" 2>/dev/null; then
    pass "$3"
  else
    fail "$3 (missing: '$2' in ${1#$REPO_ROOT/})"
  fi
}

echo "◆ Run-log (.gitissue/runs.jsonl) Tests"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

CONFIG="$REPO_ROOT/docs/config-schema.md"
RESOLVER="$REPO_ROOT/src/skills/issue-resolver/SKILL.source.md"
AUTOPILOT="$REPO_ROOT/src/skills/auto-pilot/SKILL.source.md"
DOCTOR="$REPO_ROOT/src/internal-skills/idd-doctor/SKILL.source.md"

# --- T1: canonical schema in config-schema.md -------------------------------
has "$CONFIG" ".gitissue/runs.jsonl" "T1: config-schema documents .gitissue/runs.jsonl"
has "$CONFIG" "append-only" "T1: config-schema documents append-only nature"
has "$CONFIG" "non-fatal" "T1: config-schema documents non-fatal write"
for field in "skipped_reason" "qa_cycles" "duration_s" "complexity" "outcome"; do
  has "$CONFIG" "$field" "T1: config-schema documents field '$field'"
done
# minimum required fields called out
for required in "ts" "issue" "mode" "outcome"; do
  has "$CONFIG" "\`$required\`" "T1: config-schema lists required field '$required'"
done
# an example jsonl line is present
if grep -q '"skill":"issue-resolver"' "$CONFIG" 2>/dev/null; then
  pass "T1: config-schema includes an example runs.jsonl line"
else
  fail "T1: config-schema missing example runs.jsonl line"
fi

# --- T2: issue-resolver writes one line per run -----------------------------
has "$RESOLVER" "runs.jsonl" "T2: issue-resolver source references runs.jsonl"
has "$RESOLVER" "one JSON line" "T2: issue-resolver appends one JSON line"
has "$RESOLVER" "already_resolved" "T2: issue-resolver logs already_resolved outcome"
has "$RESOLVER" "non-fatal" "T2: issue-resolver documents non-fatal write"
if grep -qi "mkdir -p .gitissue" "$RESOLVER" 2>/dev/null; then
  pass "T2: issue-resolver creates .gitissue dir before append"
else
  fail "T2: issue-resolver missing mkdir -p .gitissue"
fi

# --- T3: auto-pilot writes one line per processed issue incl. skips ---------
has "$AUTOPILOT" "runs.jsonl" "T3: auto-pilot source references runs.jsonl"
has "$AUTOPILOT" "Skipped issues are logged too" "T3: auto-pilot logs skipped issues too"
has "$AUTOPILOT" "skipped_reason" "T3: auto-pilot records skipped_reason on skips"
has "$AUTOPILOT" "non-fatal" "T3: auto-pilot documents non-fatal write"

# --- T4: idd-doctor run-log summary -----------------------------------------
has "$DOCTOR" "Run-log summary" "T4: idd-doctor has a Run-log summary section"
has "$DOCTOR" "non-gating" "T4: idd-doctor summary is informational/non-gating"
has "$DOCTOR" "runs.jsonl" "T4: idd-doctor reads runs.jsonl"
has "$DOCTOR" "Resolve rate" "T4: idd-doctor reports resolve rate"
has "$DOCTOR" "Median QA cycles" "T4: idd-doctor reports median QA cycles"
has "$DOCTOR" "skip reason" "T4: idd-doctor reports common skip reasons"
has "$DOCTOR" "no runs recorded yet" "T4: idd-doctor degrades gracefully when file absent"
# read-only guarantee still asserted near the summary
has "$DOCTOR" "read-only" "T4: idd-doctor summary preserves read-only guarantee"

# --- T5: generated install surface carries the behavior through -------------
GEN_RESOLVER="$REPO_ROOT/skills/issue-resolver/SKILL.md"
GEN_AUTOPILOT="$REPO_ROOT/skills/auto-pilot/SKILL.md"
GEN_CONFIG="$REPO_ROOT/skills/issue-resolver/references/docs/config-schema.md"

if [ -f "$GEN_RESOLVER" ]; then
  has "$GEN_RESOLVER" "runs.jsonl" "T5: generated issue-resolver SKILL.md has runs.jsonl"
else
  fail "T5: generated skills/issue-resolver/SKILL.md not found — run scripts/build.py"
fi
if [ -f "$GEN_AUTOPILOT" ]; then
  has "$GEN_AUTOPILOT" "runs.jsonl" "T5: generated auto-pilot SKILL.md has runs.jsonl"
else
  fail "T5: generated skills/auto-pilot/SKILL.md not found — run scripts/build.py"
fi
if [ -f "$GEN_CONFIG" ]; then
  has "$GEN_CONFIG" ".gitissue/runs.jsonl" "T5: bundled config-schema carries runs.jsonl schema"
else
  fail "T5: bundled config-schema.md not found in generated resolver references"
fi

echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
else
  echo "  ✓ All tests passed"
  exit 0
fi
