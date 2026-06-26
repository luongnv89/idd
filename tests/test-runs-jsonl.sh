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
  # -e guards patterns that begin with '-' (e.g. flag names like --no-run-log)
  # from being parsed as grep options.
  if grep -qiF -e "$2" "$1" 2>/dev/null; then
    pass "$3"
  else
    fail "$3 (missing: '$2' in ${1#$REPO_ROOT/})"
  fi
}

# has_n: assert a fixed pattern appears at least N times in a file. Used where a
# single match would let a regression slip through (e.g. the flag must be in
# BOTH the Resolver Subagent and the Batch Resolver prompt).
has_n() {
  # $1 = file, $2 = pattern, $3 = min count, $4 = label
  local n
  # grep -c prints '0' and exits 1 on zero matches, so `|| echo 0` would append a
  # second line; assign then default-to-0 to keep a clean single integer.
  n=$(grep -ciF -e "$2" "$1" 2>/dev/null); n=${n:-0}
  if [ "$n" -ge "$3" ]; then
    pass "$4"
  else
    fail "$4 (found ${n}×, need ≥$3: '$2' in ${1#$REPO_ROOT/})"
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

# --- T6: single-writer under auto-pilot (issue #156 — double-write fix) ------
# Under /auto-pilot the resolver runs as a subagent in --auto mode. Without a
# suppression contract, BOTH the resolver and auto-pilot append to runs.jsonl —
# two lines per processed issue, corrupting idd-doctor's resolve-rate and
# median-QA metrics (which count over all lines). The fix: auto-pilot passes a
# dedicated --no-run-log flag (independent of --auto, so standalone
# `/issue-resolver N --auto` still logs); the suppressed resolver returns its
# telemetry instead, and auto-pilot writes the single enriched line.
SUBAGENT="$REPO_ROOT/src/skills/auto-pilot/references/subagent-prompts.md"

# Resolver documents the suppression flag and that it returns (not appends)
# telemetry when suppressed.
has "$RESOLVER" "--no-run-log" "T6: resolver documents the --no-run-log suppression flag"
has "$RESOLVER" "single writer" "T6: resolver explains the single-writer-under-auto-pilot rule"
# The flag must NOT be gated on --auto / IDD_AUTO_MODE — standalone --auto logs.
has "$RESOLVER" "standalone" "T6: resolver clarifies standalone --auto still logs (flag != --auto)"

# Auto-pilot passes --no-run-log to the (single-issue) resolver subagent and
# expects telemetry back so it can write the one enriched line.
has "$SUBAGENT" "--no-run-log" "T6: auto-pilot subagent prompt passes --no-run-log to the resolver"
has "$SUBAGENT" "complexity" "T6: auto-pilot subagent prompt collects complexity for the enriched line"
has "$SUBAGENT" "duration_s" "T6: auto-pilot subagent prompt collects duration_s for the enriched line"

# Auto-pilot SKILL documents that it is the single writer and enriches its line.
has "$AUTOPILOT" "--no-run-log" "T6: auto-pilot documents suppressing the resolver via --no-run-log"
has "$AUTOPILOT" "single line" "T6: auto-pilot documents writing the single enriched line per issue"

# The batch path is explicitly out of scope for #156 (tracked separately), so the
# fix must NOT silence the Batch Resolver — only the single-issue resolver. Pin
# that boundary: --no-run-log appears exactly once in the subagent prompts.
has_n "$SUBAGENT" "--no-run-log" 1 "T6: --no-run-log present in subagent prompts (single-issue path)"
if [ "$(grep -ciF -e '--no-run-log' "$SUBAGENT")" -eq 1 ]; then
  pass "T6: --no-run-log scoped to the single-issue resolver only (batch path deferred, not silenced)"
else
  fail "T6: --no-run-log should appear exactly once (only the single-issue resolver); batch is out of scope for #156"
fi

# config-schema documents the single-writer / suppression convention.
has "$CONFIG" "--no-run-log" "T6: config-schema documents the --no-run-log suppression convention"
has "$CONFIG" "single writer" "T6: config-schema documents the single-writer rule under auto-pilot"

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
  has "$GEN_AUTOPILOT" "--no-run-log" "T5: generated auto-pilot SKILL.md carries the --no-run-log suppression"
else
  fail "T5: generated skills/auto-pilot/SKILL.md not found — run scripts/build.py"
fi
GEN_SUBAGENT="$REPO_ROOT/skills/auto-pilot/references/subagent-prompts.md"
if [ -f "$GEN_SUBAGENT" ]; then
  has "$GEN_SUBAGENT" "--no-run-log" "T5: generated auto-pilot subagent prompt passes --no-run-log"
fi
if [ -f "$GEN_RESOLVER" ]; then
  has "$GEN_RESOLVER" "--no-run-log" "T5: generated issue-resolver SKILL.md documents --no-run-log"
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
