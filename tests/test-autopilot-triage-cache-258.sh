#!/usr/bin/env bash
# test-autopilot-triage-cache-258.sh — Triage once per run, update the cache
# incrementally (issue #258).
#
# Acceptance criteria:
#   AC1: an N-issue run performs at most one full triage plus incremental
#        updates — a `triage_cache` gate above the loop reuses a fresh payload,
#        and a named step updates it after each merge.
#   AC2: no bulk issue fetch in the orchestrator carries `body`.
#   AC3: pick results match a full re-triage on an unchanged backlog — the
#        incremental update is removal-only, so the order it leaves is a
#        subsequence of the order a full triage produced.
#   AC4: per-iteration orchestrator context cost is materially reduced — one
#        body per iteration instead of up to a hundred.
#
# Two of these are arguments about behavior rather than about prose, so they are
# checked against the Python directly (T7, T8):
#
#   * The whole of AC2 rests on the premise that `gi-triage-graph.py` never
#     reads a body. That was an inference from the fact that /issue-triage keeps
#     `body` for its relationship-scanner subagent while /auto-pilot's Phase 1
#     spawns no scanner. T7 turns it into a fact: the same scan with and without
#     bodies must produce byte-identical output.
#   * AC3 cannot be proved by construction, because the persisted payload drops
#     `created_at` while the ordering engine tie-breaks on it. T8 proves the
#     weaker claim the design actually makes — deletion preserves the order.
#
# T11 guards a third failure mode, and it is the one this change is most exposed
# to: several of the rules it rewrites live in two or three files each (SKILL.md's
# Overview beside *Mode Detection*, the resolver's Step 0i beside its own SKILL.md
# and the shared conventions, Step 1.2's bucket accounting beside the error
# catalog). Updating one home and leaving the other is issue #248's failure class,
# and the stale copy is the one an agent acts on when it is the always-loaded file.
#
# The #256 trap is silent by design: dropping `body` from Phase 1's list without
# rewriting Step 1.2b degrades every resolver spawn from `supplied` to `partial`
# (the resolver's Step 0i), which restores the per-issue fetch #256 deleted
# while AC2 still passes. T4 is the guard.
#
# Asserts on the authored src/ sources AND on the built skills/ tree, because a
# contract that ships only in src/ is not installed for anyone. The behavioral
# halves run the script out of src/shared/scripts/ — the build already asserts
# the shipped copies are byte-identical.
#
# No GitHub access, no token, and no setup.
#
# Usage: bash tests/test-autopilot-triage-cache-258.sh
# Returns: exit 0 if all checks pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GRAPH="$REPO_ROOT/src/shared/scripts/gi-triage-graph.py"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

has() {
  # `--` so a pattern that opens with a dash (`--limit 100`) is a pattern and
  # not an option grep rejects with a message this suite would never show.
  grep -qE -- "$2" "$1" 2>/dev/null
}

check_has() {
  local file="$1" pattern="$2" label="$3"
  if has "$file" "$pattern"; then
    pass "$label"
  else
    fail "$label"
    echo "      missing pattern: $pattern"
    echo "      in file: ${file#$REPO_ROOT/}"
  fi
}

check_lacks() {
  local file="$1" pattern="$2" label="$3"
  if has "$file" "$pattern"; then
    fail "$label"
    echo "      forbidden pattern still present: $pattern"
    echo "      in file: ${file#$REPO_ROOT/}"
  else
    pass "$label"
  fi
}

check_block_has() {
  local block="$1" pattern="$2" label="$3"
  if [ -z "$block" ]; then
    fail "$label"
    echo "      block is empty — the extraction anchor no longer matches"
  elif printf '%s' "$block" | grep -qE "$pattern"; then
    pass "$label"
  else
    fail "$label"
    echo "      missing pattern: $pattern"
  fi
}

check_block_lacks() {
  local block="$1" pattern="$2" label="$3"
  if [ -z "$block" ]; then
    fail "$label"
    echo "      block is empty — the extraction anchor no longer matches"
  elif printf '%s' "$block" | grep -qE "$pattern"; then
    fail "$label"
    echo "      forbidden pattern still present: $pattern"
  else
    pass "$label"
  fi
}

echo "◆ Auto-Pilot Triage Cache Tests (issue #258)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

SRC_PHASES="$REPO_ROOT/src/skills/auto-pilot/references/phases.md"
SRC_CONFIG="$REPO_ROOT/src/skills/auto-pilot/references/configuration.md"
SRC_ERRORS="$REPO_ROOT/src/skills/auto-pilot/references/error-messages.md"
SRC_SKILL="$REPO_ROOT/src/skills/auto-pilot/SKILL.source.md"
SRC_PROMPTS="$REPO_ROOT/src/skills/auto-pilot/references/subagent-prompts.md"
SRC_SUMMARY="$REPO_ROOT/src/skills/auto-pilot/references/summary-format.md"
SRC_PERSIST="$REPO_ROOT/src/skills/issue-triage/references/output-and-persist.md"
SRC_TRIAGE_SKILL="$REPO_ROOT/src/skills/issue-triage/SKILL.source.md"
SCHEMA="$REPO_ROOT/docs/config-schema.md"
# T11's second homes: the resolver states this loop's payload provenance in two
# of its own files, and the shared conventions state the staleness rule once for
# every skill.
SRC_RES_STEPS="$REPO_ROOT/src/skills/issue-resolver/references/pipeline-steps.md"
SRC_RES_SKILL="$REPO_ROOT/src/skills/issue-resolver/SKILL.source.md"
SRC_CONV="$REPO_ROOT/docs/shared-agent-conventions.md"

BUILT_PHASES="$REPO_ROOT/skills/auto-pilot/references/phases.md"
BUILT_CONFIG="$REPO_ROOT/skills/auto-pilot/references/configuration.md"
BUILT_ERRORS="$REPO_ROOT/skills/auto-pilot/references/error-messages.md"
BUILT_SKILL="$REPO_ROOT/skills/auto-pilot/SKILL.md"
BUILT_PROMPTS="$REPO_ROOT/skills/auto-pilot/references/subagent-prompts.md"
BUILT_SUMMARY="$REPO_ROOT/skills/auto-pilot/references/summary-format.md"
BUILT_PERSIST="$REPO_ROOT/skills/issue-triage/references/output-and-persist.md"
BUILT_RES_STEPS="$REPO_ROOT/skills/issue-resolver/references/pipeline-steps.md"
BUILT_RES_SKILL="$REPO_ROOT/skills/issue-resolver/SKILL.md"

for file in "$SRC_PHASES" "$SRC_CONFIG" "$SRC_ERRORS" "$SRC_SKILL" "$SRC_PROMPTS" \
            "$SRC_SUMMARY" "$SRC_PERSIST" "$SRC_TRIAGE_SKILL" "$SCHEMA" "$GRAPH" \
            "$SRC_RES_STEPS" "$SRC_RES_SKILL" "$SRC_CONV" \
            "$BUILT_PHASES" "$BUILT_CONFIG" "$BUILT_ERRORS" "$BUILT_SKILL" \
            "$BUILT_PROMPTS" "$BUILT_SUMMARY" "$BUILT_PERSIST" \
            "$BUILT_RES_STEPS" "$BUILT_RES_SKILL"; do
  if [ -f "$file" ]; then
    pass "exists: ${file#$REPO_ROOT/}"
  else
    fail "missing: ${file#$REPO_ROOT/} — run ./scripts/build.sh"
  fi
done

# ───────────────────────────────────────────────────────────
# T1 (AC2): every bulk fetch in the orchestrator carries no bodies
# ───────────────────────────────────────────────────────────
# Two halves, and both matter. The list must still END in `state,updatedAt` —
# #256's T1.1 pins that shape, and both fields are structural inputs to the
# resolver's Step 0i gate — while `body` must be gone from it. T1.2 is
# file-wide on purpose: since Step 1.1b there are two `gh issue list` sites in
# the orchestrator (the triage scan and the live eligibility read), and neither
# may carry a body.
check_has "$SRC_PHASES" 'gh issue list --state open --json [a-zA-Z,]*state,updatedAt' \
  "T1.1: Phase 1's list call still ends in state,updatedAt"
check_lacks "$SRC_PHASES" 'gh issue list --state open --json [a-zA-Z,]*body' \
  "T1.2: Phase 1's list call no longer requests body"
check_has "$SRC_PHASES" '--limit 100' \
  "T1.3: the bulk list is still bounded by an explicit limit"
# Bounded at Step 1.1b, not at Step 1.2: Step 1.1b sits between them and also
# talks about bodies and about Step 1.2b, so a block that swallowed it would let
# its prose satisfy assertions that are about Step 1.1 alone.
STEP11_BLOCK="$(awk '/^### Step 1\.1 — Triage/,/^### Step 1\.1b — Live eligibility read/' "$SRC_PHASES")"
check_block_has "$STEP11_BLOCK" 'No .body' \
  "T1.4: Step 1.1 states that the list carries no body, and why"
check_block_has "$STEP11_BLOCK" 'Step 1\.2b' \
  "T1.5: Step 1.1 names the step that fetches the one body an iteration needs"

# /issue-triage's OWN bulk list legitimately keeps `body` — its
# relationship-scanner subagent consumes it. AC2 is scoped to the orchestrator,
# so a change there would be a different (and wrong) fix for this issue.
check_has "$SRC_TRIAGE_SKILL" 'gh issue list [^`]*body' \
  "T1.6: /issue-triage's own scanner list still carries body (out of AC2's scope)"

# ───────────────────────────────────────────────────────────
# T2 (AC1): a triage-cache gate sits above the loop
# ───────────────────────────────────────────────────────────
check_has "$SRC_PHASES" '^### Step 1\.0 — Triage cache gate' \
  "T2.1: auto-pilot has a named triage-cache gate"
GATE_BLOCK="$(awk '/^### Step 1\.0 — Triage cache gate/,/^### Step 1\.1 — Triage/' "$SRC_PHASES")"
check_block_has "$GATE_BLOCK" 'triage_cache = fresh \| stale \| absent' \
  "T2.2: the gate sets exactly one three-state variable"
for state in fresh stale absent; do
  check_block_has "$GATE_BLOCK" "\`$state\`" \
    "T2.3: the gate defines the '$state' state"
done
check_block_has "$GATE_BLOCK" 'Evaluated once, before the first iteration' \
  "T2.4: the gate is evaluated once per run, not once per iteration"
check_block_has "$GATE_BLOCK" 'summary\.suggested_order' \
  "T2.5: the gate requires the cached execution order to be present"
check_block_has "$GATE_BLOCK" 'triage_cache_max_age_minutes' \
  "T2.6: the gate bounds how old a reusable cache may be"
check_block_has "$GATE_BLOCK" 'git log --oneline --since=' \
  "T2.7: the gate reuses triage's own commits-since-cache signal"
# Both fail-safe clauses are mandatory. A gate that cannot say what it does on
# doubt has no degrade path, and one that cannot say it never changes an
# outcome is indistinguishable from a gate that does.
check_block_has "$GATE_BLOCK" 'any doubt is .stale' \
  "T2.8: the gate degrades to a full triage on any doubt"
check_block_has "$GATE_BLOCK" 'can only remove duplicated work, never change an outcome' \
  "T2.9: the gate states it can only remove duplicated work"
check_block_has "$GATE_BLOCK" 'worst case is exactly today.s behavior' \
  "T2.10: the gate names today's behavior as its worst case"

# Step 1.1 must stop claiming a fresh triage every iteration.
check_lacks "$SRC_PHASES" 'Run a fresh triage to get current priorities' \
  "T2.11: Step 1.1 no longer promises a fresh triage every iteration"
check_block_has "$STEP11_BLOCK" 'Step 1\.0 already skipped this on a .fresh. cache' \
  "T2.12: Step 1.1 defers to the gate above it"

# The 'no open issues remain' stop has to be reachable without a scan, or a
# reuse run with an emptied backlog never terminates through it.
check_has "$SRC_PHASES" '.summary\.suggested_order. in a cache Step 1\.0 reused' \
  "T2.13: the no-issues-remain stop is reachable from a reused cache"

# ───────────────────────────────────────────────────────────
# T3 (AC1/AC3): the post-merge update is removal-only
# ───────────────────────────────────────────────────────────
check_has "$SRC_PHASES" '^### Step 1\.6 — Update the triage cache after a merge' \
  "T3.1: auto-pilot has a named incremental-update step"
UPDATE_BLOCK="$(awk '/^### Step 1\.6 — Update the triage cache after a merge/,0' "$SRC_PHASES")"
for field in 'issues\[\]' 'summary\.suggested_order' 'summary\.parallel_groups' \
             'blocked_by' 'blocks' 'history\[\]'; do
  check_block_has "$UPDATE_BLOCK" "$field" \
    "T3.2: the update names $field"
done
check_block_has "$UPDATE_BLOCK" '\*\*removal only\*\*' \
  "T3.3: the update is removal-only"
check_block_has "$UPDATE_BLOCK" 'never a recomputation' \
  "T3.4: the update states it is never a recomputation"
check_block_has "$UPDATE_BLOCK" 'reads .createdAt' \
  "T3.5: the update names the ordering input the payload drops"
check_block_has "$UPDATE_BLOCK" 'persists carries only .updated_at' \
  "T3.6: the update explains why the payload cannot reproduce its own order"
check_block_has "$UPDATE_BLOCK" 'valid topological order' \
  "T3.7: the update states why deletion is order-faithful"
check_block_has "$UPDATE_BLOCK" 'exactly \*\*one\*\* .history' \
  "T3.8: the update appends exactly one history entry"
check_block_has "$UPDATE_BLOCK" 'counting the records that remain' \
  "T3.9: counts are recomputed by counting, not by arithmetic"
check_block_has "$UPDATE_BLOCK" 'Could not update the triage cache' \
  "T3.10: a failed update degrades to a re-triage rather than stopping the loop"
# The trigger is "a merge closed an issue", not "Step 5.2 ran". Scoping it to
# Step 5.2 alone leaves the Phase 3-4 partial-merge path (`aggressive` +
# `merge_partial: true`) closing an issue that stays in `summary.suggested_order`
# and on no skip list — Step 1.2 re-picks it on the next iteration.
check_block_has "$UPDATE_BLOCK" 'Run it after \*\*any step that merged a PR and closed its issue\*\*' \
  "T3.11: the update runs after ANY step that merged and closed an issue"
check_block_has "$UPDATE_BLOCK" '\*Phase 3-4 Step 2b\*.s .partial_followup. merge' \
  "T3.11b: the update names the Phase 3-4 partial merge beside Step 5.2"
check_block_has "$UPDATE_BLOCK" 'Fail-safe: any doubt is .run it' \
  "T3.11c: the update states which way it fail-safes"

# The persisted schema is /issue-triage's. A second writer is only safe while it
# adds no field, so the cross-skill contract lives in the schema's own document.
check_has "$SRC_PERSIST" 'Cross-skill incremental updates' \
  "T3.12: the triage schema doc names the cross-skill incremental writer"
check_has "$SRC_PERSIST" 'Removal only, never a recomputation' \
  "T3.13: the schema doc states the removal-only invariant"
check_has "$SRC_PERSIST" 'Exactly one appended .history' \
  "T3.14: the schema doc states the one-history-entry invariant"
check_has "$SRC_PERSIST" 'no field is added, none is removed' \
  "T3.15: the schema doc states that the schema itself is unchanged"

# The widened trigger is only real if the OTHER merge site points back at it.
# Step 1.6 sits at the far end of the file, so a reader working through Phase 3-4
# would otherwise never learn that its merge owes the cache an update.
STEP2B_BLOCK="$(awk '/^\*\*Step 2b — Merge/,/^#### Critical issues/' "$SRC_PHASES")"
check_block_has "$STEP2B_BLOCK" 'run \*Step 1\.6 — Update the triage cache after a merge\*' \
  "T3.16: the Phase 3-4 partial merge points at the cache update"
check_block_has "$STEP2B_BLOCK" 'for \*Step 1\.2\* to pick again next iteration' \
  "T3.17: that pointer names the re-pick hazard a skipped update creates"
check_block_has "$STEP2B_BLOCK" 'failed-merge path below closed nothing' \
  "T3.18: a failed partial merge is excluded — it closed no issue"

# ───────────────────────────────────────────────────────────
# T4 (#256 regression guard): the body comes from one post-pick fetch
# ───────────────────────────────────────────────────────────
# Extracted with the same anchors tests/test-subagent-context-256.sh uses, so a
# rename that breaks that suite breaks this one in the same place.
CAPTURE_BLOCK="$(awk '/^### Step 1\.2b — Capture the caller payload/,/^### Step 1\.3/' "$SRC_PHASES")"
check_block_has "$CAPTURE_BLOCK" 'gi-issue\.py' \
  "T4.1: Step 1.2b fetches the picked issue's record on demand"
check_block_has "$CAPTURE_BLOCK" 'number,title,body,labels,assignees,state,updatedAt' \
  "T4.2: that fetch requests exactly Step 0a's field list minus comments"
check_block_has "$CAPTURE_BLOCK" 'gh issue view \{issue_number\} --json number,title,body,labels,assignees,state,updatedAt' \
  "T4.3: the degrade path yields the same record through gh"
check_block_has "$CAPTURE_BLOCK" 'exit 3' \
  "T4.4: exit 3 is classified at the call site"
check_block_has "$CAPTURE_BLOCK" 'never degrade past it' \
  "T4.5: exit 3 stops rather than degrades"
check_block_has "$CAPTURE_BLOCK" 'exit 4' \
  "T4.6: exit 4 is classified at the call site"
check_block_has "$CAPTURE_BLOCK" 'Missing bundled dependency' \
  "T4.7: an absent script file is a broken install, not a degrade"
check_block_has "$CAPTURE_BLOCK" 'Never emit a body-less partial' \
  "T4.8: a body-less block is omitted rather than shipped as a partial"
# The literal #256 pins at tests/test-subagent-context-256.sh:482.
check_block_has "$CAPTURE_BLOCK" '\*\*.\{issue_payload_ids\}.\*\* — the same record reduced to' \
  "T4.9: the trimmed reviewer block survives the rewrite"
# Nothing in 1.2b may still claim the record came from the bulk list.
check_block_lacks "$CAPTURE_BLOCK" 'this issue.s object from the Step 1\.1 list' \
  "T4.10: 1.2b no longer sources the payload from the Phase 1 list"
check_has "$SRC_PROMPTS" 'verbatim from that step.s single-issue fetch' \
  "T4.11: the Template Variables table records the new provenance"
check_has "$SRC_PROMPTS" 'number., .title., .body., .labels., .assignees., .state., .updatedAt' \
  "T4.12: the Template Variables field list is unchanged"

# The dependency gate's body source claim moves with it.
check_lacks "$SRC_PHASES" "Phase 1's cached body is the source" \
  "T4.13: Step 5.1b no longer sources the body from Phase 1's list"
check_has "$SRC_PHASES" 'keys its cache by issue number' \
  "T4.14: Step 5.1b states what the re-read actually costs"

# ───────────────────────────────────────────────────────────
# T5 (AC1): both re-triage triggers are named, and only those
# ───────────────────────────────────────────────────────────
check_has "$SRC_PHASES" '\*\*Pick miss — one re-triage, then that stop\.\*\*' \
  "T5.1: a pick miss forces one re-triage"
check_has "$SRC_PHASES" 'at most one re-triage per iteration' \
  "T5.2: the pick-miss retry cannot spin"
check_has "$SRC_PHASES" 'autopilot\.retriage_every' \
  "T5.3: an every-N-iterations trigger exists"
check_has "$SCHEMA" '^  retriage_every: 0' \
  "T5.4: config-schema documents autopilot.retriage_every, defaulting to never"
check_has "$SCHEMA" '^  triage_cache_max_age_minutes: 60' \
  "T5.5: config-schema documents autopilot.triage_cache_max_age_minutes"
check_has "$SCHEMA" '\| .autopilot\.retriage_every. \| .0.' \
  "T5.6: the defaults table carries the new keys"
check_has "$SCHEMA" '\.gitissue/triage\.json. \| ./issue-triage., ./auto-pilot' \
  "T5.7: config-schema records /auto-pilot as a triage.json writer"
# The eligibility criteria must keep naming the session skip list — the pick
# miss is defined against it, and a cached order makes re-picking easier, not
# harder (pinned in the same shape by tests/test-autopilot-dependency-gate.sh).
if awk '/^### Step 1\.2 — Pick Next Issue/{f=1; next} f && /^### /{exit} f' "$SRC_PHASES" \
  | grep -E '^- \*\*Not skipped\*\*' | grep -q 'session skip list'; then
  pass "T5.8: Step 1.2 eligibility criteria still names the session skip list"
else
  fail "T5.8: Step 1.2 criteria lost the session skip list (re-pick hazard)"
fi

# The per-phase completion check may not assert a refresh that no longer happens.
check_lacks "$SRC_SUMMARY" 'Triage refreshed' \
  "T5.9: the Phase 1 check no longer asserts a per-iteration refresh"
check_has "$SRC_SUMMARY" 'Triage current' \
  "T5.10: the Phase 1 check is true for a reused cache too"

# `retriage_required` is a flag, and a flag needs a clear as much as a set.
# Set at Step 1.2's pick miss and at Step 1.6 (trigger + degrade), cleared
# nowhere, a single degrade would re-triage on every remaining iteration —
# contradicting Step 1.6's own "costs one full triage" claim.
check_block_has "$STEP11_BLOCK" 'clears .retriage_required. as it runs' \
  "T5.11: Step 1.1 clears retriage_required as it runs"
check_block_has "$STEP11_BLOCK" 'Set in two places' \
  "T5.12: Step 1.1 is the single home of the flag's whole lifecycle"
check_block_has "$UPDATE_BLOCK" 'costs \*\*one\*\* full triage' \
  "T5.13: the degrade costs one triage, not one per remaining iteration"

# One timing per trigger. Step 1.2 retries in-iteration; Step 1.6 runs only
# after a merge, so a pick miss cannot reach it at all — restating it there as a
# next-iteration trigger is two answers to one question.
check_block_has "$UPDATE_BLOCK" 'A pick miss is not a trigger here' \
  "T5.14: Step 1.6 defers the pick miss to Step 1.2 instead of restating it"
check_block_has "$UPDATE_BLOCK" '\*\*in the same iteration\*\*' \
  "T5.15: Step 1.6 records the pick-miss retry's real timing"
check_block_lacks "$UPDATE_BLOCK" 'Two triggers, both cheap to evaluate' \
  "T5.16: Step 1.6 no longer claims two triggers of its own"

# The `0` off-switch configuration.md used to advertise does not exist: Step 1.0
# is evaluated once per run, so `0` only forces a full triage on iteration 1.
check_lacks "$SRC_CONFIG" 'disable reuse and triage on every iteration' \
  "T5.17: configuration.md dropped the per-iteration off-switch that never existed"
check_has "$SRC_CONFIG" 'refuse any pre-existing cache' \
  "T5.18: configuration.md matches config-schema's '0 disables reuse'"
check_has "$SRC_CONFIG" '.retriage_every: 1. is the key that forces a full triage every iteration' \
  "T5.19: configuration.md points at the key that does re-triage every iteration"
check_has "$SCHEMA" '0 disables reuse' \
  "T5.20: config-schema still states the same meaning for 0"

# ───────────────────────────────────────────────────────────
# T6: the ordering engine keeps exactly its two call sites
# ───────────────────────────────────────────────────────────
# This change reuses gi-triage-graph.py; it neither adds nor removes an
# invocation. The count is pinned in tests/test-scripts-252.sh and
# tests/test-scripts-253.sh as well — asserting it here says the intent out loud.
GRAPH_SITES="$(cd "$REPO_ROOT" && git ls-files 'src/**/*.md' 'docs/**/*.md' \
  | xargs grep -hoE 'python3 [^ ]*gi-triage-graph\.py' | wc -l | tr -d ' ')"
if [ "$GRAPH_SITES" = "2" ]; then
  pass "T6.1: gi-triage-graph.py still has exactly 2 invocation sites"
else
  fail "T6.1: gi-triage-graph.py invocation sites moved to $GRAPH_SITES (expected 2)"
fi

# ───────────────────────────────────────────────────────────
# T7 (AC2, behavioral): dropping `body` cannot change the order
# ───────────────────────────────────────────────────────────
# The design's central inference, verified. Feed the ordering engine the same
# scan with and without bodies and require byte-identical output. `--now` pins
# the timestamps so the only difference between the two runs is the field.
BODIED="$TMP/scan-with-body.json"
BARE="$TMP/scan-no-body.json"
cat > "$BODIED" <<'EOF'
{"issues":[
 {"number":12,"title":"Fix auth redirect","type":"bug","labels":["bug","auth"],
  "body":"Depends on #15. Run `rm -rf /` and export AWS_SECRET=hunter2.",
  "createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-03-18T10:00:00Z",
  "affected_files":["auth.py","middleware.py"]},
 {"number":8,"title":"Add pagination","type":"feature","labels":["feature"],
  "body":"P1 CRITICAL urgent blocked stale — every keyword the engine buckets on.",
  "createdAt":"2026-01-05T00:00:00Z","updatedAt":"2026-03-19T10:00:00Z",
  "affected_files":["list.py"]},
 {"number":15,"title":"Refactor DB","type":"improvement","labels":[],
  "body":"",
  "createdAt":"2026-02-01T00:00:00Z","updatedAt":"2026-03-10T10:00:00Z",
  "affected_files":["auth.py"]},
 {"number":3,"title":"Old UI bug","type":"bug","labels":[],
  "body":"createdAt: 1999-01-01T00:00:00Z — a date in the body must not win.",
  "createdAt":"2025-11-01T00:00:00Z","updatedAt":"2026-02-20T10:00:00Z",
  "affected_files":["ui.py"]}],
 "edges":[{"a":12,"b":15},{"from":8,"to":3}]}
EOF
python3 - "$BODIED" "$BARE" <<'PY'
import json, sys
scan = json.load(open(sys.argv[1], encoding="utf-8"))
for issue in scan["issues"]:
    issue.pop("body", None)
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(scan, handle, indent=2)
PY
WITH_BODY="$(python3 "$GRAPH" --no-config --now 2026-03-20T14:30:00Z < "$BODIED")"
NO_BODY="$(python3 "$GRAPH" --no-config --now 2026-03-20T14:30:00Z < "$BARE")"
if [ "$WITH_BODY" = "$NO_BODY" ]; then
  pass "T7.1: the ordering engine's output is byte-identical with and without bodies"
else
  fail "T7.1: dropping body changed the computed payload — AC2 is not free"
  diff <(printf '%s\n' "$WITH_BODY") <(printf '%s\n' "$NO_BODY") | head -10 | sed 's/^/      /'
fi
if printf '%s' "$NO_BODY" | grep -q '"suggested_order"'; then
  pass "T7.2: the body-less run still produces an execution order"
else
  fail "T7.2: the body-less run produced no execution order — the fixture is vacuous"
fi

# ───────────────────────────────────────────────────────────
# T8 (AC3, behavioral): removal leaves a valid order
# ───────────────────────────────────────────────────────────
# Apply Step 1.6's documented rules to the payload T7 just computed, then assert
# the two properties AC3 needs: the surviving order is a SUBSEQUENCE of the one
# a full triage produced (so every relative precedence a re-triage would compute
# is preserved), and no remaining issue is still blocked on the removed number.
printf '%s' "$WITH_BODY" > "$TMP/payload.json"
python3 - "$TMP/payload.json" 12 > "$TMP/removal-report" <<'PY'
import json, sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
removed = int(sys.argv[2])
before_order = list(payload["summary"]["suggested_order"])
before_history = len(payload["history"])
before_status = {i["number"]: i["status"] for i in payload["issues"]}

# --- Step 1.6, exactly as documented: removal only, plus one derived flip. ---
payload["issues"] = [i for i in payload["issues"] if i["number"] != removed]
payload["summary"]["suggested_order"] = [
    n for n in payload["summary"]["suggested_order"] if n != removed
]
groups = []
for group in payload["summary"]["parallel_groups"]:
    survivors = [n for n in group if n != removed]
    if survivors:
        groups.append(survivors)
payload["summary"]["parallel_groups"] = groups
for issue in payload["issues"]:
    issue["blocked_by"] = [n for n in issue["blocked_by"] if n != removed]
    issue["blocks"] = [n for n in issue["blocks"] if n != removed]
    if not issue["blocked_by"] and issue["status"] == "blocked":
        issue["status"] = "ready"
payload["analyzed_count"] = len(payload["issues"])
payload["history"].append(
    {"time": "2026-03-20T15:00:00Z", "source": "/auto-pilot",
     "changes": f"Incremental update (#{removed} resolved)"}
)

after_order = payload["summary"]["suggested_order"]
results = []


def check(name, ok, detail=""):
    results.append(f"{'OK' if ok else 'NO'}|{name}|{detail}")


# Subsequence: walk the surviving order through the original in one pass.
it = iter(before_order)
subsequence = all(any(x == n for x in it) for n in after_order)
check("subsequence", subsequence, f"{before_order} -> {after_order}")
check("removed-gone", removed not in after_order, str(after_order))
check("removed-not-an-issue", all(i["number"] != removed for i in payload["issues"]))
check("shrunk-by-one", len(after_order) == len(before_order) - 1,
      f"{len(before_order)} -> {len(after_order)}")
check("no-blocked-by", not any(removed in i["blocked_by"] for i in payload["issues"]))
check("no-blocks", not any(removed in i["blocks"] for i in payload["issues"]))
check("no-parallel-group", not any(
    removed in g for g in payload["summary"]["parallel_groups"]))
check("no-empty-group", all(g for g in payload["summary"]["parallel_groups"]))
check("one-history-entry", len(payload["history"]) == before_history + 1)
check("history-names-issue",
      str(removed) in payload["history"][-1]["changes"]
      and payload["history"][-1]["source"] == "/auto-pilot")
check("count-by-counting", payload["analyzed_count"] == len(payload["issues"]))
# The one derived change: #15 was blocked on #12 and must now be ready.
freed = next(i for i in payload["issues"] if i["number"] == 15)
check("blocked-flips-to-ready",
      before_status[15] == "blocked" and freed["status"] == "ready",
      f"{before_status[15]} -> {freed['status']}")
# Schema parity: removal adds no key and drops none.
keys_ok = set(payload) == {"version", "updated", "source", "analyzed_count",
                           "issues", "summary", "history"}
check("schema-unchanged", keys_ok, ",".join(sorted(payload)))

print("\n".join(results))
PY
while IFS='|' read -r status name detail; do
  case "$name" in
    subsequence)            label="T8.1: the surviving order is a subsequence of the full-triage order" ;;
    removed-gone)           label="T8.2: the resolved issue is gone from suggested_order" ;;
    removed-not-an-issue)   label="T8.3: the resolved issue is gone from issues[]" ;;
    shrunk-by-one)          label="T8.4: exactly one entry left the order" ;;
    no-blocked-by)          label="T8.5: no remaining issue is still blocked_by the resolved number" ;;
    no-blocks)              label="T8.6: no remaining issue still blocks the resolved number" ;;
    no-parallel-group)      label="T8.7: the resolved issue left every parallel group" ;;
    no-empty-group)         label="T8.8: a group emptied by the removal is dropped, not left empty" ;;
    one-history-entry)      label="T8.9: exactly one history entry was appended" ;;
    history-names-issue)    label="T8.10: the history entry names /auto-pilot and the removed issue" ;;
    count-by-counting)      label="T8.11: analyzed_count matches the records that remain" ;;
    blocked-flips-to-ready) label="T8.12: an issue whose blocked_by emptied flips to ready" ;;
    schema-unchanged)       label="T8.13: removal adds no top-level key and drops none" ;;
    *)                      label="T8.x: $name" ;;
  esac
  if [ "$status" = "OK" ]; then
    pass "$label"
  else
    fail "$label"
    [ -n "$detail" ] && echo "      $detail"
  fi
done < "$TMP/removal-report"

# ───────────────────────────────────────────────────────────
# T10 (QA cycle 2): the gate removed the per-iteration triage, not
#      the orchestrator's live view of the backlog
# ───────────────────────────────────────────────────────────
# Phase 1's bulk list used to be the ONLY live read in the loop, so making it
# once-per-run (or zero, on a `fresh` cache) silently unplugged three rules that
# still read from it: Step 1.2's `Open` and `Not assigned` criteria, the
# pick-miss predicate, and the `✓ All issues resolved` stop. Step 1.1b restores
# a body-less two-field read that answers all three.

check_has "$SRC_PHASES" '^### Step 1\.1b — Live eligibility read' \
  "T10.1: a named step supplies the live open-issue set the pick needs"
LIVEREAD_BLOCK="$(awk '/^### Step 1\.1b — Live eligibility read/,/^### Step 1\.2 — Pick Next Issue/' "$SRC_PHASES")"
check_block_has "$LIVEREAD_BLOCK" 'gh issue list --state open --json number,assignees --limit 100' \
  "T10.2: the live read asks for exactly the two fields the cache cannot answer"
check_block_has "$LIVEREAD_BLOCK" 'neither a GitHub .state. nor an .assignees. field' \
  "T10.3: the step states why the cache cannot answer those two criteria"
check_block_has "$LIVEREAD_BLOCK" 'Evaluated every iteration' \
  "T10.4: the live read runs every iteration, unlike the triage above it"
check_block_has "$LIVEREAD_BLOCK" 'no second call' \
  "T10.5: a triage iteration reuses Step 1.1's list instead of listing twice"
# AC2/AC4 are the reason this fix is a two-field list and not a re-added `body`.
# T1.2 already forbids the body file-wide; this pins the stated rationale, so a
# later edit cannot quietly widen the field set without contradicting itself.
check_block_has "$LIVEREAD_BLOCK" 'Two scalar fields, and no .body' \
  "T10.6: the live read states it carries no body (AC2)"
check_block_has "$LIVEREAD_BLOCK" 'exactly one body per iteration' \
  "T10.7: the live read states the per-iteration body budget is untouched (AC4)"
check_block_has "$LIVEREAD_BLOCK" 'any doubt is .unavailable' \
  "T10.8: the live read states which way it fail-safes"
check_block_has "$LIVEREAD_BLOCK" 'Never read a failed read as .no open issues' \
  "T10.9: a failed read is never mistaken for an empty backlog"

# The two criteria must name their source on the criteria bullets themselves —
# the same pin shape T5.8 uses, because prose elsewhere in Step 1.2 also
# mentions Step 1.1b and a section-wide grep would survive losing the bullet.
check_bullet() {
  local file="$1" bullet="$2" pattern="$3" label="$4"
  if awk '/^### Step 1\.2 — Pick Next Issue/{f=1; next} f && /^### /{exit} f' "$file" \
    | grep -E -- "$bullet" | grep -qE -- "$pattern"; then
    pass "$label"
  else
    fail "$label"
    echo "      bullet $bullet never matches: $pattern"
    echo "      in file: ${file#$REPO_ROOT/}"
  fi
}
check_bullet "$SRC_PHASES" '^- \*\*Open\*\*' 'Step 1\.1b' \
  "T10.10: the Open criterion reads the live set, not the cache"
check_bullet "$SRC_PHASES" '^- \*\*Not assigned\*\*' 'Step 1\.1b' \
  "T10.11: the Not assigned criterion reads the live set, not the cache"

PICK_BLOCK="$(awk '/^### Step 1\.2 — Pick Next Issue/{f=1; next} f && /^### /{exit} f' "$SRC_PHASES")"
check_block_has "$PICK_BLOCK" 'skip the last two' \
  "T10.12: an unavailable live read defers the two criteria rather than guessing"

# The post-pick fetch is the second half of the same fix: it is live, so it both
# closes the race against Step 1.1b and enforces the criteria when Step 1.1b
# could not run. Without it, an `unavailable` read would drop them entirely.
check_block_has "$CAPTURE_BLOCK" 'Post-pick eligibility re-check' \
  "T10.13: 1.2b re-checks eligibility against the live record it just fetched"
check_block_has "$CAPTURE_BLOCK" '\*\*do not spawn\*\*' \
  "T10.14: a closed or foreign-assigned pick never reaches a resolver spawn"
check_block_has "$CAPTURE_BLOCK" 'session skip list' \
  "T10.15: the re-check skip-lists the issue so the re-pick terminates"

# F2: the pick-miss predicate must be evaluable on a reuse iteration, or the
# recovery configuration.md promises for newly filed issues can never fire.
check_block_has "$PICK_BLOCK" 'eligible issue in .summary\.suggested_order. while at least one issue in' \
  "T10.16: the miss is defined over the cached order AND a live set"
check_block_has "$PICK_BLOCK" '\*Step 1\.1b\*.s live open set' \
  "T10.17: the live open set is what supplies the miss predicate"
check_block_has "$PICK_BLOCK" 'makes the predicate evaluable on a reuse iteration' \
  "T10.18: the step says why a reuse iteration can evaluate the predicate at all"
check_block_has "$PICK_BLOCK" 'the predicate narrows' \
  "T10.19: an unavailable live read narrows the miss to the cached order alone"
check_has "$SRC_CONFIG" 'Step 1\.1b' \
  "T10.20: configuration.md's retriage_every rationale names the read it relies on"

# F3: the third merge-and-close site. Step 1.6 sits at the far end of the file,
# so each site that closes an issue carries its own pointer back to it.
CRITICAL_BLOCK="$(awk '/^#### Critical issues: stop and ask the user/,/^## Phase 5 — Merge/' "$SRC_PHASES")"
check_block_has "$CRITICAL_BLOCK" 'run \*Step 1\.6 — Update the triage cache after a merge\*' \
  "T10.21: the critical-issue Option 1 merge points at the cache update"
check_block_has "$CRITICAL_BLOCK" 'for \*Step 1\.2\* to pick again next iteration' \
  "T10.22: that pointer names the re-pick hazard a skipped update creates"
check_block_has "$CRITICAL_BLOCK" 'Options 2 and 3 merged nothing' \
  "T10.23: the non-merging options are excluded — they closed no issue"
check_block_has "$UPDATE_BLOCK" '\*Phase 3-4 Option 1\*' \
  "T10.24: Step 1.6's enumeration names the critical-issue merge site"
check_block_has "$UPDATE_BLOCK" 'Three sites, one rule' \
  "T10.25: the enumeration is complete and says so"

# F4: the clean-finish message needs BOTH a second documented trigger and a home
# that a reuse iteration actually executes — Step 1.1 is the step it skips.
NOISSUES_ENTRY="$(awk '/^### No open issues/,/^### No eligible issues/' "$SRC_ERRORS")"
check_block_has "$NOISSUES_ENTRY" 'Step 1\.1b' \
  "T10.26: the error catalog documents the reuse-iteration trigger"
check_block_has "$NOISSUES_ENTRY" 'reuse' \
  "T10.27: the catalog entry names the iteration kind that reaches it"
check_block_has "$NOISSUES_ENTRY" 'all-zero counts' \
  "T10.28: the catalog says what a missing second trigger would print instead"
check_block_has "$LIVEREAD_BLOCK" '✓ All issues resolved' \
  "T10.29: the empty-backlog stop has a home a reuse iteration executes"
check_block_has "$STEP11_BLOCK" 'Two entry points, one block' \
  "T10.30: the message keeps one rendering reached from two steps"
# An emptied cached order over a NON-empty live backlog is a pick miss, not a
# clean finish — conflating them would end a run with newly filed work in it.
check_block_has "$LIVEREAD_BLOCK" '\*\*non\*\*-empty live backlog is a' \
  "T10.31: an empty order over a live backlog is a miss, not a finish"

# ───────────────────────────────────────────────────────────
# T9 (install surface): the built tree carries the same contract
# ───────────────────────────────────────────────────────────
check_has "$BUILT_PHASES" '^### Step 1\.0 — Triage cache gate' \
  "T9.1: built phases.md ships the triage cache gate"
check_has "$BUILT_PHASES" '^### Step 1\.6 — Update the triage cache after a merge' \
  "T9.2: built phases.md ships the incremental update"
check_has "$BUILT_PHASES" 'gh issue list --state open --json [a-zA-Z,]*state,updatedAt' \
  "T9.3: built phases.md ships the list call"
check_lacks "$BUILT_PHASES" 'gh issue list --state open --json [a-zA-Z,]*body' \
  "T9.4: built phases.md ships a body-less bulk list"
check_has "$BUILT_PHASES" 'references/scripts/gi-issue\.py \{issue_number\} --fields number,title,body' \
  "T9.5: built phases.md ships the post-pick single-issue fetch at its bundled path"
check_has "$BUILT_PHASES" 'any doubt is .stale' \
  "T9.6: built phases.md ships the gate's fail-safe"
check_has "$BUILT_SKILL" 'Triages \*\*once\*\* at loop start' \
  "T9.7: built SKILL.md no longer promises a triage per iteration"
check_lacks "$BUILT_SKILL" 'Runs a full triage each iteration' \
  "T9.8: built SKILL.md dropped the per-iteration triage claim"
# SKILL.md's Overview is the always-loaded paragraph an agent reads first, so a
# per-iteration triage promised there outranks the corrected *Mode Detection*
# text further down the same file — an agent that follows it fails AC1 outright.
check_lacks "$BUILT_SKILL" 'Each iteration: triage the backlog' \
  "T9.8b: built SKILL.md's Overview dropped the per-iteration triage claim too"
check_has "$BUILT_PROMPTS" 'verbatim from that step.s single-issue fetch' \
  "T9.9: built subagent-prompts.md ships the new payload provenance"
check_has "$BUILT_SUMMARY" 'Triage current' \
  "T9.10: built summary-format.md ships the reuse-safe check name"
check_has "$BUILT_PERSIST" 'Cross-skill incremental updates' \
  "T9.11: built output-and-persist.md ships the cross-skill writer contract"
check_has "$BUILT_PHASES" 'Run it after \*\*any step that merged a PR and closed its issue\*\*' \
  "T9.12: built phases.md ships the widened cache-update trigger"
check_has "$BUILT_PHASES" 'run \*Step 1\.6 — Update the triage cache after a merge\*' \
  "T9.13: built phases.md ships the Phase 3-4 partial-merge pointer"
check_has "$BUILT_PHASES" 'clears .retriage_required. as it runs' \
  "T9.14: built phases.md ships the retriage_required clear"
check_has "$BUILT_PHASES" 'A pick miss is not a trigger here' \
  "T9.15: built phases.md ships one timing for the pick-miss retry"
check_has "$BUILT_CONFIG" 'refuse any pre-existing cache' \
  "T9.16: built configuration.md ships the corrected off-switch wording"
# T10's rules, on the installed surface. A live-eligibility read that ships only
# in src/ leaves every install picking closed and foreign-assigned issues.
check_has "$BUILT_PHASES" '^### Step 1\.1b — Live eligibility read' \
  "T9.17: built phases.md ships the live eligibility read"
check_has "$BUILT_PHASES" 'gh issue list --state open --json number,assignees --limit 100' \
  "T9.18: built phases.md ships the body-less two-field live read"
check_has "$BUILT_PHASES" 'any doubt is .unavailable' \
  "T9.19: built phases.md ships the live read's fail-safe"
check_bullet "$BUILT_PHASES" '^- \*\*Open\*\*' 'Step 1\.1b' \
  "T9.20: built phases.md sources the Open criterion from the live read"
check_bullet "$BUILT_PHASES" '^- \*\*Not assigned\*\*' 'Step 1\.1b' \
  "T9.21: built phases.md sources the Not assigned criterion from the live read"
check_has "$BUILT_PHASES" '\*Step 1\.1b\*.s live open set' \
  "T9.22: built phases.md ships the evaluable pick-miss predicate"
check_has "$BUILT_PHASES" 'Post-pick eligibility re-check' \
  "T9.23: built phases.md ships the post-pick eligibility re-check"
check_has "$BUILT_PHASES" '\*Phase 3-4 Option 1\*' \
  "T9.24: built phases.md ships the third merge-and-close site"
B_CRITICAL_BLOCK="$(awk '/^#### Critical issues: stop and ask the user/,/^## Phase 5 — Merge/' "$BUILT_PHASES")"
check_block_has "$B_CRITICAL_BLOCK" 'run \*Step 1\.6 — Update the triage cache after a merge\*' \
  "T9.25: built phases.md ships Option 1's pointer at the cache update"
B_NOISSUES_ENTRY="$(awk '/^### No open issues/,/^### No eligible issues/' "$BUILT_ERRORS")"
check_block_has "$B_NOISSUES_ENTRY" 'Step 1\.1b' \
  "T9.26: built error-messages.md ships the reuse-iteration trigger"

# ───────────────────────────────────────────────────────────
# T11 (QA cycle 3): every home of a rule this issue changed says
#      the same thing. A rename pass that updates one home and
#      leaves the other is issue #248's failure class, and the
#      surviving copy is the one an agent acts on.
# ───────────────────────────────────────────────────────────

# G1 — SKILL.md's Overview is the always-loaded first paragraph, so a
# per-iteration triage promised there outranks the corrected *Mode Detection*
# text further down the same file. It must state the same rule, not a summary of
# the behavior this issue removed.
OVERVIEW="$(awk '/^# \/auto-pilot/,/^## Autonomy Philosophy/' "$SRC_SKILL")"
check_block_lacks "$OVERVIEW" 'Each iteration: triage the backlog' \
  "T11.1: the Overview no longer promises a triage per iteration"
check_block_has "$OVERVIEW" 'triages \*\*once\*\* at loop start' \
  "T11.2: the Overview states the triage-once rule *Mode Detection* owns"
check_block_has "$OVERVIEW" 'update the cached order in place' \
  "T11.3: the Overview names the incremental update as the per-merge work"
# The phase summary table's own restatement of the same rule.
check_lacks "$SRC_SKILL" 'a full triage on the first iteration' \
  "T11.4: the Phase 1 table row no longer asserts a triage on iteration 1"
check_has "$SRC_SKILL" '\*Step 1\.0\* reuses a .fresh. one' \
  "T11.5: the Phase 1 table row defers to the cache gate"
# ...and the loop diagram, which labels the phase an iteration repeats.
check_lacks "$SRC_SKILL" '^  Phase 1 — Triage +\(skipped in explicit list mode\)' \
  "T11.6: the loop diagram no longer labels the repeated phase 'Triage'"
check_has "$SRC_SKILL" '^  Phase 1 — Triage/Pick  \(triage once at start;' \
  "T11.7: the loop diagram separates the once-per-run triage from the pick"

# G2 — the resolver's Step 0i is the second home of THIS loop's payload
# provenance. It described a bulk Phase 1 list that no longer exists, including
# the comments rationale auto-pilot's own Step 1.2b deliberately dropped.
PAYLOAD_GATE="$(awk '/^## Step 0i — Caller payload gate/,/^## Step 1 — Research/' "$SRC_RES_STEPS")"
check_block_lacks "$PAYLOAD_GATE" 'Phase 1 lists every open issue' \
  "T11.8: Step 0i no longer sources the payload from a bulk open-issue list"
check_block_lacks "$PAYLOAD_GATE" 'lists up to 100 open issues' \
  "T11.9: Step 0i dropped the hundred-issue list the caller no longer makes"
check_block_lacks "$PAYLOAD_GATE" 'than the fetch it saves' \
  "T11.10: Step 0i dropped the comments rationale that argued against that list"
check_block_lacks "$PAYLOAD_GATE" 'Phase 1.s widened list call' \
  "T11.11: Step 0i no longer calls the payload a widened list record"
check_block_has "$PAYLOAD_GATE" 'fetches it once, after the pick, in its' \
  "T11.12: Step 0i sources the payload from the caller's post-pick fetch"
check_block_has "$PAYLOAD_GATE" 'caller.s single-issue fetch deliberately does not request it' \
  "T11.13: the comments rationale is now the fetch's own field choice"
# The staleness argument gets STRONGER under the new provenance, not weaker:
# gi-issue.py is TTL-cached, so the payload may have been old before the caller
# ever held it. A gate that dropped this would read as newly safe and is not.
check_block_lacks "$PAYLOAD_GATE" 'only as fresh as the caller.s list' \
  "T11.14: Step 0i no longer measures staleness against a list"
check_block_has "$PAYLOAD_GATE" 'only as fresh as the caller.s fetch that' \
  "T11.15: 0a's two stops measure staleness against the caller's fetch"
check_block_has "$PAYLOAD_GATE" 'the caller.s fetch — which is TTL-cached' \
  "T11.16: condition 5's argument names the TTL cache that makes it stronger"
check_block_has "$PAYLOAD_GATE" 'a TTL-cached read, so an issue closed externally' \
  "T11.17: the closed-issue argument names the same cache"
# The resolver restates the gate in its always-loaded SKILL.md, and the shared
# conventions own the rule for every skill — three homes, one claim.
check_lacks "$SRC_RES_SKILL" 'already listed it' \
  "T11.18: the resolver SKILL clause no longer says the caller listed the record"
check_has "$SRC_RES_SKILL" 'already fetched it, in its \*Step 1\.2b\*' \
  "T11.19: the resolver SKILL clause names the caller's post-pick fetch"
check_lacks "$SRC_RES_SKILL" 'as fresh as the caller.s list' \
  "T11.20: the resolver SKILL clause measures staleness against that fetch"
check_lacks "$SRC_CONV" 'as fresh as the list that produced it' \
  "T11.21: the shared conventions no longer say a payload comes from a list"
check_has "$SRC_CONV" 'as fresh as the read that produced it' \
  "T11.22: the shared conventions state the read-neutral staleness rule"
check_lacks "$SRC_CONV" '^listed, the triage row it wrote' \
  "T11.23: the conventions' opening example is no longer a listed record"

# G3 — Step 1.2's four buckets are stated to always sum to the rejected
# candidates, so a skip-list writer with no bucket breaks that sum silently.
# Step 1.2b became the third writer.
check_block_has "$PICK_BLOCK" '^\| Reason \| Added by \| Bucket \|' \
  "T11.24: Step 1.2 owns a reason-to-bucket table"
check_block_has "$PICK_BLOCK" '^\| .failed. \|.*\| .Skipped. \|$' \
  "T11.25: the table maps failed → Skipped"
check_block_has "$PICK_BLOCK" '^\| .blocked_by_dependency. \|.*\| .Dep-blocked. \|$' \
  "T11.26: the table maps blocked_by_dependency → Dep-blocked"
check_block_has "$PICK_BLOCK" '^\| .not_eligible. \|.*\(closed\) \| .Skipped. \|$' \
  "T11.27: the table maps a closed post-pick rejection → Skipped"
check_block_has "$PICK_BLOCK" '^\| .not_eligible. \|.*\(assigned to another user\) \| .Assigned. \|$' \
  "T11.28: the table maps an assigned post-pick rejection → Assigned"
# A survivor pin: this sentence predates the table, and adding the table is
# exactly the kind of edit that drops the claim it was added to preserve.
check_block_has "$PICK_BLOCK" 'every filtered issue lands in exactly one bucket' \
  "T11.29: the sum invariant survives the rewrite that added the table"
check_block_has "$PICK_BLOCK" 'a new skip-list writer adds a row here' \
  "T11.29b: the table states what a future skip-list writer owes the invariant"
check_bullet "$SRC_PHASES" '^- \*\*Not skipped\*\*' 'Step 1\.2b' \
  "T11.30: the Not skipped criterion names Step 1.2b as a skip-list writer"
check_block_has "$CAPTURE_BLOCK" 'session skip list with the reason' \
  "T11.31: 1.2b records a reason rather than a bare entry"
check_block_has "$CAPTURE_BLOCK" 'reason-to-bucket table is the single home' \
  "T11.32: 1.2b defers the bucket to Step 1.2 instead of restating it"
check_has "$SRC_PHASES" 'skip labels, --skip, failed, or ineligible' \
  "T11.33: the rendered Skipped bucket admits the post-pick rejection"
# The catalog entry enumerates the same writers. Both copies of the rendered
# block stay byte-identical (pinned by tests/test-autopilot-dependency-gate.sh).
NOELIGIBLE_ENTRY="$(awk '/^### No eligible issues/,/^### API rate limit during triage/' "$SRC_ERRORS")"
for reason in 'blocked_by_dependency' 'failed' 'not_eligible'; do
  check_block_has "$NOELIGIBLE_ENTRY" "\`$reason\`" \
    "T11.34: the catalog trigger names the $reason writer"
done
check_block_has "$NOELIGIBLE_ENTRY" 'single home of that mapping, never restated here' \
  "T11.35: the catalog defers the bucket mapping instead of copying it"
check_block_has "$NOELIGIBLE_ENTRY" 'skip labels, --skip, failed, or ineligible' \
  "T11.36: the catalog's rendered block matches phases.md byte-for-byte"

# T11 on the installed surface — a drift fix that ships only in src/ is not
# installed for anyone, which is the whole reason T9 exists.
B_OVERVIEW="$(awk '/^# \/auto-pilot/,/^## Autonomy Philosophy/' "$BUILT_SKILL")"
check_block_has "$B_OVERVIEW" 'triages \*\*once\*\* at loop start' \
  "T11.37: built SKILL.md's Overview ships the triage-once rule"
check_lacks "$BUILT_SKILL" 'a full triage on the first iteration' \
  "T11.38: built SKILL.md's Phase 1 table row ships the corrected wording"
B_PAYLOAD_GATE="$(awk '/^## Step 0i — Caller payload gate/,/^## Step 1 — Research/' "$BUILT_RES_STEPS")"
check_block_lacks "$B_PAYLOAD_GATE" 'Phase 1 lists every open issue' \
  "T11.39: built pipeline-steps.md ships the corrected payload provenance"
check_block_lacks "$B_PAYLOAD_GATE" 'than the fetch it saves' \
  "T11.40: built pipeline-steps.md ships the corrected comments rationale"
check_block_has "$B_PAYLOAD_GATE" 'the caller.s fetch — which is TTL-cached' \
  "T11.41: built pipeline-steps.md ships the stronger staleness argument"
check_has "$BUILT_RES_SKILL" 'already fetched it, in its \*Step 1\.2b\*' \
  "T11.42: built resolver SKILL.md ships the corrected provenance clause"
check_has "$BUILT_PHASES" '^\| .not_eligible. \|.*\| .Assigned. \|$' \
  "T11.43: built phases.md ships the reason-to-bucket table"
check_has "$BUILT_ERRORS" 'single home of that mapping, never restated here' \
  "T11.44: built error-messages.md ships the deferred bucket mapping"

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

exit 0
