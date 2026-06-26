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

# --no-run-log now applies to BOTH the single-issue Resolver Subagent AND the Batch
# Resolver Subagent (#158 made auto-pilot the single writer on the batch path too).
# So it must appear exactly TWICE in the subagent prompts — one per resolver.
# (Was exactly 1 before #158; the #156 tripwire here intentionally flipped.)
if [ "$(grep -ciF -e '--no-run-log' "$SUBAGENT")" -eq 2 ]; then
  pass "T6: --no-run-log appears twice — single-issue AND batch resolver both suppressed"
else
  fail "T6: --no-run-log should appear exactly twice (single-issue + batch resolver)"
fi

# config-schema documents the single-writer / suppression convention.
has "$CONFIG" "--no-run-log" "T6: config-schema documents the --no-run-log suppression convention"
has "$CONFIG" "single writer" "T6: config-schema documents the single-writer rule under auto-pilot"

# --- T7: batch-resolver run-log fan-out (issue #158) ------------------------
# A batch resolves N issues in ONE PR. The single-writer contract is one line per
# PROCESSED (attempted) issue, not per PR — so auto-pilot must fan the batch's one
# result into N lines. This is unverifiable instruction prose, so pin the contract
# concretely: per-attempted-issue count, failed-batch coverage, telemetry attributed
# once. The authoritative spec lives in explicit-list-mode.md (batching only happens
# in explicit-list mode); config-schema mirrors the convention; the Batch Resolver
# prompt carries --no-run-log + returns the telemetry.
EXPLICIT="$REPO_ROOT/src/skills/auto-pilot/references/explicit-list-mode.md"

# (a) The Batch Resolver prompt is suppressed AND located in the batch section.
#     Assert --no-run-log lives specifically inside the Batch Resolver Subagent
#     section (not just somewhere in the file) so the count check above can't pass
#     on the single-issue occurrence alone.
if awk '/^## Batch Resolver Subagent/,/^## Template Variables/' "$SUBAGENT" \
     | grep -qiF -e '--no-run-log'; then
  pass "T7: Batch Resolver prompt passes --no-run-log (suppressed like single-issue)"
else
  fail "T7: Batch Resolver prompt missing --no-run-log in its section"
fi
# Batch Resolver returns the telemetry auto-pilot needs to enrich the lines.
has "$SUBAGENT" "complexity" "T7: Batch Resolver returns complexity for the fanned-out lines"
has "$SUBAGENT" "duration_s" "T7: Batch Resolver returns duration_s (attributed once)"

# (b) Per-attempted-issue contract: one line per ATTEMPTED issue, keyed on the
#     attempted set — NOT issues_resolved (success-only).
has "$EXPLICIT" "one line per attempted issue" "T7: spec writes one line per attempted issue"
has "$EXPLICIT" "attempted set" "T7: spec keys the fan-out on the attempted set"
has "$EXPLICIT" "Run-log fan-out for the batch" "T7: explicit-list-mode has the fan-out section"

# (c) Per-issue outcome derives from issues_resolved (success vs failed).
has "$EXPLICIT" "issues_resolved" "T7: per-issue outcome derives from issues_resolved"

# (d) Failed/partial batch coverage: no inverse under-count, no re-resolve
#     double-count. The unresolved issues are re-resolved individually and logged
#     there — not double-logged as a batch 'failed' line.
has "$EXPLICIT" "double-count this fix removes" "T7: spec guards the re-resolve double-count"
has "$EXPLICIT" "individual" "T7: failed/partial batch issues re-resolved (and logged) individually"
has "$CONFIG"   "no inverse under-count" "T7: config-schema documents no inverse under-count"
# (d.0) Discriminates the batch-TIME write rule: an unresolved attempted issue is
#       NEVER written a 'failed' line at batch time (it is re-queued and logged at
#       its retry). Without this, prose that says "iterate the attempted set, absent
#       -> failed" at batch time would reintroduce the exact per-issue double-count
#       this fix removes — and the looser greps above would still pass.
has "$EXPLICIT" "written a \`failed\` line at batch time" "T7: spec forbids a 'failed' batch-time line for unresolved issues"
has "$CONFIG"   "No \`failed\` line is written at batch" "T7: config-schema forbids a 'failed' batch-time line"
# (d.1) The spawn-position (primary) unresolved issue MUST be re-queued, else it is
#       dropped (zero lines) — the inverse under-count criterion 5 forbids. This is
#       the subtle hole: the primary's optimized_order slot is already consumed.
has "$EXPLICIT" "re-queue the primary too" "T7: full-failure path re-queues the primary too"
has "$EXPLICIT" "Re-queuing the primary is" "T7: fan-out spec mandates re-queuing the primary"
has "$CONFIG"   "including the batch's primary" "T7: config-schema mandates re-queuing the primary"
# (d.2) An in-batch 'already resolved in batch' skip writes NO run-log line (the
#       member was already logged at batch time) — else the resolved members get two
#       lines. The one exception to 'log every processed issue including skips'.
has "$EXPLICIT" "writes no run-log line" "T7: in-batch skip writes no run-log line (no double-count)"
has "$CONFIG"   "writes no run-log line" "T7: config-schema notes the in-batch skip writes no line"

# (e) Scalar telemetry attributed ONCE (primary line), shared fields on every line.
has "$EXPLICIT" "one line only" "T7: qa_cycles/duration_s attributed to one line only"
has "$SUBAGENT" "primary issue's run-log line only" "T7: subagent prompt notes once-only attribution"

# (f) The auto-pilot SKILL points to the authoritative fan-out spec.
has "$AUTOPILOT" "fan" "T7: auto-pilot SKILL describes fanning the batch result out"
has "$AUTOPILOT" "explicit-list-mode" "T7: auto-pilot SKILL points to the explicit-list-mode spec"

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
  # #158: the batch fan-out must survive the build into the generated mirror too.
  if [ "$(grep -ciF -e '--no-run-log' "$GEN_SUBAGENT")" -eq 2 ]; then
    pass "T5: generated subagent prompt carries --no-run-log twice (single-issue + batch)"
  else
    fail "T5: generated subagent prompt should carry --no-run-log twice — run scripts/build.py"
  fi
fi
GEN_EXPLICIT="$REPO_ROOT/skills/auto-pilot/references/explicit-list-mode.md"
if [ -f "$GEN_EXPLICIT" ]; then
  has "$GEN_EXPLICIT" "Run-log fan-out for the batch" "T5: generated explicit-list-mode carries the batch fan-out spec"
  has "$GEN_EXPLICIT" "one line per attempted issue" "T5: generated explicit-list-mode keeps the per-attempted-issue contract"
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
