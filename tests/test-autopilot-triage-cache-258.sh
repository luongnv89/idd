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

# shellcheck source=lib/anchors.bash
. "$REPO_ROOT/tests/lib/anchors.bash"

echo "◆ Auto-Pilot Triage Cache Tests (issue #258)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

SRC_PHASES="$REPO_ROOT/src/skills/auto-pilot/references/phases.md"
SRC_CONFIG="$REPO_ROOT/src/skills/auto-pilot/references/configuration.md"
SRC_ERRORS="$REPO_ROOT/src/skills/auto-pilot/references/error-messages.md"
SRC_SKILL="$REPO_ROOT/src/skills/auto-pilot/SKILL.source.md"
SRC_PROMPTS="$REPO_ROOT/src/skills/auto-pilot/references/subagent-prompts.md"
SRC_EXPLICIT="$REPO_ROOT/src/skills/auto-pilot/references/explicit-list-mode.md"
SRC_EXAMPLES="$REPO_ROOT/src/skills/auto-pilot/references/examples.md"
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
BUILT_EXPLICIT="$REPO_ROOT/skills/auto-pilot/references/explicit-list-mode.md"
BUILT_EXAMPLES="$REPO_ROOT/skills/auto-pilot/references/examples.md"
BUILT_SUMMARY="$REPO_ROOT/skills/auto-pilot/references/summary-format.md"
BUILT_PERSIST="$REPO_ROOT/skills/issue-triage/references/output-and-persist.md"
BUILT_RES_STEPS="$REPO_ROOT/skills/issue-resolver/references/pipeline-steps.md"
BUILT_RES_SKILL="$REPO_ROOT/skills/issue-resolver/SKILL.md"

for file in "$SRC_PHASES" "$SRC_CONFIG" "$SRC_ERRORS" "$SRC_SKILL" "$SRC_PROMPTS" \
            "$SRC_EXPLICIT" "$SRC_EXAMPLES" \
            "$SRC_SUMMARY" "$SRC_PERSIST" "$SRC_TRIAGE_SKILL" "$SCHEMA" "$GRAPH" \
            "$SRC_RES_STEPS" "$SRC_RES_SKILL" "$SRC_CONV" \
            "$BUILT_PHASES" "$BUILT_CONFIG" "$BUILT_ERRORS" "$BUILT_SKILL" \
            "$BUILT_PROMPTS" "$BUILT_EXPLICIT" "$BUILT_EXAMPLES" \
            "$BUILT_SUMMARY" "$BUILT_PERSIST" \
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
STEP11_BLOCK="$(anchor_span "$SRC_PHASES" ap-step11-triage ap-step11b-live-read || true)"
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
anchor_present "$SRC_PHASES" ap-step11a-cache-gate \
  "T2.1: auto-pilot has a named triage-cache gate"
# Renamed from `Step 1.0` when #257's run-state work landed a *different*
# `Step 1.0 — Resume entry gate` in the new Phase 0. `1.1a` is the gate that
# decides whether `Step 1.1` runs, so it letters onto 1.1 beside `Step 1.1b`.
check_lacks "$SRC_PHASES" '^### Step 1\.0 — Triage cache gate' \
  "T2.1b: the old colliding heading is gone"
anchor_present "$SRC_PHASES" ap-step10-resume \
  "T2.1c: #257's Step 1.0 keeps its name"
GATE_BLOCK="$(anchor_span "$SRC_PHASES" ap-step11a-cache-gate ap-step11-triage || true)"
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
check_block_has "$STEP11_BLOCK" 'Step 1\.1a already skipped this on a .fresh. cache' \
  "T2.12: Step 1.1 defers to the gate above it"

# The 'no open issues remain' stop has to be reachable without a scan, or a
# reuse run with an emptied backlog never terminates through it.
check_has "$SRC_PHASES" '.summary\.suggested_order. in a cache Step 1\.1a reused' \
  "T2.13: the no-issues-remain stop is reachable from a reused cache"

# ───────────────────────────────────────────────────────────
# T3 (AC1/AC3): the post-merge update is removal-only
# ───────────────────────────────────────────────────────────
anchor_present "$SRC_PHASES" ap-step16-cache-update \
  "T3.1: auto-pilot has a named incremental-update step"
UPDATE_BLOCK="$(anchor_region "$SRC_PHASES" ap-step16-cache-update || true)"
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
check_block_has "$UPDATE_BLOCK" 'summary.circular_deps' \
  "T3.19: Step 1.6 handles circular_deps incrementally"
check_block_has "$UPDATE_BLOCK" 'Discard the entire .summary.circular_deps. chain when it contains the' \
  "T3.19b: Step 1.6 discards a chain containing the resolved issue"
check_block_has "$UPDATE_BLOCK" 'preserve unrelated valid closed cycles unchanged' \
  "T3.19c: Step 1.6 preserves unrelated valid cycles"
check_block_has "$UPDATE_BLOCK" 'middle node 2 from .\[1,2,3,1\].' \
  "T3.19d: Step 1.6 covers removing a middle node"
check_block_has "$UPDATE_BLOCK" 'resulting .\[1,3,1\].*not a recorded cycle' \
  "T3.19e: Step 1.6 identifies the fabricated middle-node cycle"
check_block_has "$UPDATE_BLOCK" 'discard the whole chain' \
  "T3.19f: Step 1.6 discards the broken middle-node chain"
check_block_has "$UPDATE_BLOCK" 'summary.co_dependent' \
  "T3.20: Step 1.6 drops the resolved number from co_dependent"
check_block_has "$UPDATE_BLOCK" 'potentially_fixed_by.target_issue' \
  "T3.21: Step 1.6 clears potentially_fixed_by aimed at the resolved issue"

# The widened trigger is only real if the OTHER merge site points back at it.
# Step 1.6 sits at the far end of the file, so a reader working through Phase 3-4
# would otherwise never learn that its merge owes the cache an update.
STEP2B_BLOCK="$(anchor_span "$SRC_PHASES" ap-step2b-merge ap-critical-issues || true)"
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
CAPTURE_BLOCK="$(anchor_span "$SRC_PHASES" ap-step12b-capture ap-step13-plan || true)"
check_block_has "$CAPTURE_BLOCK" 'gi-issue\.py' \
  "T4.1: Step 1.2b fetches the picked issue's record on demand"
check_block_has "$CAPTURE_BLOCK" 'python3 shared/scripts/gi-issue\.py \{issue_number\}' \
  "T4.1b: src prose cites the bare shared/scripts token, not the built path"
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
check_has "$SRC_PROMPTS" 'captured in mode-neutral .Step 1.2b.' \
  "T4.11: the Template Variables table records mode-neutral provenance"
check_has "$SRC_PROMPTS" 'number., .title., .body., .labels., .assignees., .state., .updatedAt' \
  "T4.12: the Template Variables field list is unchanged"

# The dependency gate's body source claim moves with it.
check_lacks "$SRC_PHASES" "Phase 1's cached body is the source" \
  "T4.13: Step 5.1b no longer sources the body from Phase 1's list"
check_has "$SRC_PHASES" 'make \*\*no\*\* extra GitHub read' \
  "T4.14: Step 5.1b reuses the held resolution snapshot"

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
# Capture the section before matching it — an `awk … | grep -q` pipeline lets
# grep exit on the first match and leaves awk writing into a closed pipe, which
# under `set -o pipefail` fails the assertion on a match that succeeded.
pick_block="$(anchor_span "$SRC_PHASES" ap-step12-pick ap-step12b-capture || true)"
if grep -E '^- \*\*Not skipped\*\*' <<< "$pick_block" | grep -q 'session skip list'; then
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
check_block_has "$STEP11_BLOCK" 'Set in three places' \
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

# The `0` off-switch configuration.md used to advertise does not exist: Step 1.1a
# is evaluated once per run, so `0` only forces a full triage on iteration 1.
check_lacks "$SRC_CONFIG" 'disable reuse and triage on every iteration' \
  "T5.17: configuration.md dropped the per-iteration off-switch that never existed"
check_has "$SRC_CONFIG" 'refuse any pre-existing cache' \
  "T5.18: configuration.md matches config-schema's '0 disables reuse'"
check_has "$SRC_CONFIG" '.retriage_every: 1. is the key that forces a full triage every iteration' \
  "T5.19: configuration.md points at the key that does re-triage every iteration"
check_has "$SRC_PHASES" 'The counter is the same 1-based' \
  "T5.21: retriage_every names {i} as its counter"
check_block_has "$UPDATE_BLOCK" 'does \*\*not\*\* live here' \
  "T5.22: Step 1.6 no longer owns the retriage_every trigger"
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
# Do NOT re-implement Step 1.6 here and then assert the filter — that is
# tautological. AC3's independent oracle is T7's full-triage order: dropping
# the resolved number from it must leave a subsequence. A remaining-only
# re-triage is the *wrong* oracle — it can legally reorder survivors (that
# is why Step 1.6 is removal-only, already pinned by T3.4–T3.7).
printf '%s' "$WITH_BODY" > "$TMP/payload.json"
python3 - "$TMP/payload.json" 12 > "$TMP/removal-report" <<'PY'
import json, sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
removed = int(sys.argv[2])
before_order = list(payload["summary"]["suggested_order"])
after_order = [n for n in before_order if n != removed]
results = []

def check(name, ok, detail=""):
    results.append(f"{'OK' if ok else 'NO'}|{name}|{detail}")

it = iter(before_order)
subsequence = all(any(x == n for x in it) for n in after_order)
check("subsequence", subsequence, f"{before_order} -> {after_order}")
check("removed-gone", removed not in after_order, str(after_order))
check("shrunk-by-one", len(after_order) == len(before_order) - 1,
      f"{len(before_order)} -> {len(after_order)}")
print("\n".join(results))
PY
while IFS='|' read -r status name detail; do
  case "$name" in
    subsequence)   label="T8.1: dropping the resolved issue leaves a subsequence of the full-triage order" ;;
    removed-gone)  label="T8.2: the resolved issue is gone from suggested_order" ;;
    shrunk-by-one) label="T8.3: exactly one entry left the order" ;;
    *)             label="T8.x: $name" ;;
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

anchor_present "$SRC_PHASES" ap-step11b-live-read \
  "T10.1: a named step supplies the live open-issue set the pick needs"
LIVEREAD_BLOCK="$(anchor_span "$SRC_PHASES" ap-step11b-live-read ap-step12-pick || true)"
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
  local block
  # Same reason as T5.8: capture, then match — never pipe awk into `grep -q`.
  block="$(anchor_span "$file" ap-step12-pick ap-step12b-capture || true)"
  if grep -E -- "$bullet" <<< "$block" | grep -qE -- "$pattern"; then
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

PICK_BLOCK="$(anchor_span "$SRC_PHASES" ap-step12-pick ap-step12b-capture || true)"
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
CRITICAL_BLOCK="$(anchor_span "$SRC_PHASES" ap-critical-issues ap-phase5-merge || true)"
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
NOISSUES_ENTRY="$(anchor_span "$SRC_ERRORS" ape-no-open-issues ape-no-eligible-issues || true)"
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
anchor_present "$BUILT_PHASES" ap-step11a-cache-gate \
  "T9.1: built phases.md ships the triage cache gate"
check_lacks "$BUILT_PHASES" '^### Step 1\.0 — Triage cache gate' \
  "T9.1b: built phases.md ships no colliding Step 1.0 heading"
anchor_present "$BUILT_PHASES" ap-step16-cache-update \
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
check_has "$BUILT_PROMPTS" 'captured in mode-neutral .Step 1.2b.' \
  "T9.9: built subagent-prompts.md ships mode-neutral payload provenance"
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
anchor_present "$BUILT_PHASES" ap-step11b-live-read \
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
B_CRITICAL_BLOCK="$(anchor_span "$BUILT_PHASES" ap-critical-issues ap-phase5-merge || true)"
check_block_has "$B_CRITICAL_BLOCK" 'run \*Step 1\.6 — Update the triage cache after a merge\*' \
  "T9.25: built phases.md ships Option 1's pointer at the cache update"
B_NOISSUES_ENTRY="$(anchor_span "$BUILT_ERRORS" ape-no-open-issues ape-no-eligible-issues || true)"
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
OVERVIEW="$(anchor_span "$SRC_SKILL" ap-skill-title ap-autonomy || true)"
check_block_lacks "$OVERVIEW" 'Each iteration: triage the backlog' \
  "T11.1: the Overview no longer promises a triage per iteration"
check_block_has "$OVERVIEW" 'triages \*\*once\*\* at loop start' \
  "T11.2: the Overview states the triage-once rule *Mode Detection* owns"
check_block_has "$OVERVIEW" 'update the cached order in place' \
  "T11.3: the Overview names the incremental update as the per-merge work"
# The phase summary table's own restatement of the same rule.
check_lacks "$SRC_SKILL" 'a full triage on the first iteration' \
  "T11.4: the Phase 1 table row no longer asserts a triage on iteration 1"
check_has "$SRC_SKILL" '\*Step 1\.1a\* reuses a .fresh. one' \
  "T11.5: the Phase 1 table row defers to the cache gate"
# ...and the loop diagram, which labels the phase an iteration repeats.
check_lacks "$SRC_SKILL" '^  Phase 1 — Triage +\(skipped in explicit list mode\)' \
  "T11.6: the loop diagram no longer labels the repeated phase 'Triage'"
check_has "$SRC_SKILL" '^  Phase 1 — Triage/Pick  \(triage once at start;' \
  "T11.7: the loop diagram separates the once-per-run triage from the pick"

# G2 — the resolver's Step 0i is the second home of THIS loop's payload
# provenance. It described a bulk Phase 1 list that no longer exists, including
# the comments rationale auto-pilot's own Step 1.2b deliberately dropped.
PAYLOAD_GATE="$(anchor_span "$SRC_RES_STEPS" rs-step0i-gate rs-step1-research || true)"
check_block_lacks "$PAYLOAD_GATE" 'Phase 1 lists every open issue' \
  "T11.8: Step 0i no longer sources the payload from a bulk open-issue list"
check_block_lacks "$PAYLOAD_GATE" 'lists up to 100 open issues' \
  "T11.9: Step 0i dropped the hundred-issue list the caller no longer makes"
check_block_lacks "$PAYLOAD_GATE" 'than the fetch it saves' \
  "T11.10: Step 0i dropped the comments rationale that argued against that list"
check_block_lacks "$PAYLOAD_GATE" 'Phase 1.s widened list call' \
  "T11.11: Step 0i no longer calls the payload a widened list record"
check_block_has "$PAYLOAD_GATE" 'captures it in its' \
  "T11.12: Step 0i sources the payload from mode-neutral capture"
check_block_has "$PAYLOAD_GATE" 'caller.s single-issue fetch deliberately does not request it' \
  "T11.13: the comments rationale is now the fetch's own field choice"
# The staleness argument gets STRONGER under the new provenance, not weaker:
# gi-issue.py is TTL-cached, so the payload may have been old before the caller
# ever held it. A gate that dropped this would read as newly safe and is not.
check_block_lacks "$PAYLOAD_GATE" 'only as fresh as the caller.s list' \
  "T11.14: Step 0i no longer measures staleness against a list"
check_block_has "$PAYLOAD_GATE" 'only as fresh as the caller.s fetch that' \
  "T11.15: 0a's two stops measure staleness against the caller's fetch"
check_block_has "$PAYLOAD_GATE" 'caller.s fetch may be' \
  "T11.16: condition 5's argument names the TTL cache that makes it stronger"
check_block_has "$PAYLOAD_GATE" 'a TTL-cached read, so an issue closed externally' \
  "T11.17: the closed-issue argument names the same cache"
# The resolver restates the gate in its always-loaded SKILL.md, and the shared
# conventions own the rule for every skill — three homes, one claim.
check_lacks "$SRC_RES_SKILL" 'already listed it' \
  "T11.18: the resolver SKILL clause no longer says the caller listed the record"
check_has "$SRC_RES_SKILL" 'captured it in mode-neutral \*Step 1\.2b\*' \
  "T11.19: the resolver SKILL clause names mode-neutral capture"
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
check_block_has "$PICK_BLOCK" '^\| .closed. \|.*\| .Skipped. \|$' \
  "T11.27: the table maps a closed post-pick rejection → Skipped"
check_block_has "$PICK_BLOCK" '^\| .assigned. \|.*\| .Assigned. \|$' \
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
NOELIGIBLE_ENTRY="$(anchor_span "$SRC_ERRORS" ape-no-eligible-issues ape-api-rate-limit || true)"
for reason in 'blocked_by_dependency' 'failed' 'closed' 'assigned'; do
  check_block_has "$NOELIGIBLE_ENTRY" "\`$reason\`" \
    "T11.34: the catalog trigger names the $reason writer"
done
check_block_has "$NOELIGIBLE_ENTRY" 'single home of that mapping, never restated here' \
  "T11.35: the catalog defers the bucket mapping instead of copying it"
check_block_has "$NOELIGIBLE_ENTRY" 'skip labels, --skip, failed, or ineligible' \
  "T11.36: the catalog's rendered block matches phases.md byte-for-byte"

# T11 on the installed surface — a drift fix that ships only in src/ is not
# installed for anyone, which is the whole reason T9 exists.
B_OVERVIEW="$(anchor_span "$BUILT_SKILL" ap-skill-title ap-autonomy || true)"
check_block_has "$B_OVERVIEW" 'triages \*\*once\*\* at loop start' \
  "T11.37: built SKILL.md's Overview ships the triage-once rule"
check_lacks "$BUILT_SKILL" 'a full triage on the first iteration' \
  "T11.38: built SKILL.md's Phase 1 table row ships the corrected wording"
B_PAYLOAD_GATE="$(anchor_span "$BUILT_RES_STEPS" rs-step0i-gate rs-step1-research || true)"
check_block_lacks "$B_PAYLOAD_GATE" 'Phase 1 lists every open issue' \
  "T11.39: built pipeline-steps.md ships the corrected payload provenance"
check_block_lacks "$B_PAYLOAD_GATE" 'than the fetch it saves' \
  "T11.40: built pipeline-steps.md ships the corrected comments rationale"
check_block_has "$B_PAYLOAD_GATE" 'caller.s fetch may be' \
  "T11.41: built pipeline-steps.md ships the stronger staleness argument"
check_has "$BUILT_RES_SKILL" 'captured it in mode-neutral \*Step 1\.2b\*' \
  "T11.42: built resolver SKILL.md ships mode-neutral provenance"
check_has "$BUILT_PHASES" '^\| .assigned. \|.*\| .Assigned. \|$' \
  "T11.43: built phases.md ships the reason-to-bucket table"
check_has "$BUILT_ERRORS" 'single home of that mapping, never restated here' \
  "T11.44: built error-messages.md ships the deferred bucket mapping"

# ───────────────────────────────────────────────────────────
# T12 (QA cycle 4): the four surviving findings, each a claim
#      that had two homes and only one of them updated
# ───────────────────────────────────────────────────────────

# H1 — the spawn prompt BODIES, not just the table that documents them.
# `subagent-prompts.md` states the payload's provenance twice: in the
# `## Template Variables` table (pinned by T4.11/T9.9) and inside the fenced
# prompt each subagent is actually handed. Cycle 4 found the table updated and
# the resolver BODY still telling the subagent its record was "as GitHub
# returned it to Phase 1's list call" — a list that has not requested `body`
# since T1.2. The injected text is the one an agent acts on, so pin it directly.
#
# The fenced block inside a `## <Name> Subagent` section is that injected text,
# as distinct from the prose around it. Matched whitespace-FLATTENED, so a
# reflow of the hard-wrapped prompt cannot silently un-assert this the way it
# would defeat a line-oriented grep.
prompt_body() {
  awk -v s="$2" -v e="$3" '
    $0 ~ s { sec = 1; next }
    sec && $0 ~ e { exit }
    sec && /^```/ { fence = !fence; next }
    sec && fence { print }
  ' "$1"
}

# Every way the prompts used to attribute the payload to the bulk list. None may
# survive in a prompt body — the record comes from Step 1.2b's single-issue fetch.
STALE_PROVENANCE='returned it to Phase 1|as Phase 1 listed them|Phase 1.s list call'

for pair in "src:$SRC_PROMPTS" "built:$BUILT_PROMPTS"; do
  tag="${pair%%:*}"
  file="${pair#*:}"

  RES_BODY="$(prompt_body "$file" '^## Resolver Subagent' '^## PR Reviewer Subagent')"
  REV_BODY="$(prompt_body "$file" '^## PR Reviewer Subagent' '^## Analyzer Subagent')"
  RES_FLAT="$(printf '%s' "$RES_BODY" | tr '\n' ' ' | tr -s ' ')"
  REV_FLAT="$(printf '%s' "$REV_BODY" | tr '\n' ' ' | tr -s ' ')"

  # Non-vacuity: an anchor that stopped matching would make every check below
  # trivially pass, so prove each body was extracted and is the right one first.
  check_block_has "$RES_FLAT" 'issue_payload' \
    "T12.1 ($tag): the resolver prompt body was extracted from its fenced block"
  check_block_has "$REV_FLAT" 'issue_payload_ids' \
    "T12.2 ($tag): the reviewer prompt body was extracted from its fenced block"

  check_block_has "$RES_FLAT" "compact-JSON resolution snapshot" \
    "T12.3 ($tag): the resolver prompt BODY sources the mode-neutral snapshot"
  check_block_has "$RES_FLAT" 'complete with updatedAt but WITHOUT comments' \
    "T12.4 ($tag): the resolver body keeps the field-set clause the rewrite sits on"
  check_block_has "$RES_FLAT" "mode-neutral capture" \
    "T12.5 ($tag): the resolver body names mode-neutral capture"
  check_block_lacks "$RES_FLAT" "$STALE_PROVENANCE" \
    "T12.6 ($tag): the resolver body never attributes the payload to the bulk list"

  check_block_has "$REV_FLAT" "BEGIN_UNTRUSTED_issue_payload_ids" \
    "T12.7 ($tag): the reviewer prompt BODY carries the framed trimmed block"
  check_block_has "$REV_FLAT" "resolution-boundary snapshot captured BEFORE" \
    "T12.8 ($tag): instruction 6 names the mode-neutral freshness boundary"
  check_block_lacks "$REV_FLAT" "$STALE_PROVENANCE" \
    "T12.9 ($tag): the reviewer body never attributes its block to the bulk list"
done

# H2 — Step 1.6 in explicit list mode. `explicit-list-mode.md` says the other
# phases "run identically", Step 1.6 executes in Phase 5, and its own fail-safe
# says any doubt is "run it" — so a `--issues` run on a never-triaged repo would
# print `⚠ Could not update the triage cache` after EVERY merge and set a flag
# that mode has no Step 1.1 to clear. Three homes, one rule.
check_block_has "$UPDATE_BLOCK" 'Skipped in explicit list mode \(.--issues.\)' \
  "T12.10: Step 1.6 states it is skipped in explicit list mode"
check_block_has "$UPDATE_BLOCK" 'not a degrade' \
  "T12.11: Step 1.6 says a missing cache in that mode is not a degrade"
check_block_has "$UPDATE_BLOCK" 'no .retriage_required., which that mode has no' \
  "T12.12: Step 1.6 says why the flag must not be set in that mode"
check_block_has "$UPDATE_BLOCK" 'explicit-list skip above is the one thing this does not cover' \
  "T12.13: the fail-safe is scoped so the skip is not read as a doubt"
check_has "$SRC_EXPLICIT" '\*Step 1\.6 — Update the triage cache after a merge\* is skipped here' \
  "T12.14: explicit-list-mode.md points at the skip instead of implying the step runs"
check_has "$SRC_EXPLICIT" 'run identically to triage mode,' \
  "T12.15: the run-identically claim now carries its one exception"
check_lacks "$SRC_EXPLICIT" 'run identically to triage mode\.$' \
  "T12.16: the unqualified run-identically claim is gone"
check_has "$BUILT_EXPLICIT" '\*Step 1\.6 — Update the triage cache after a merge\* is skipped here' \
  "T12.17: built explicit-list-mode.md ships the skip"
check_lacks "$BUILT_EXPLICIT" 'run identically to triage mode\.$' \
  "T12.18: built explicit-list-mode.md ships the qualified claim"
check_has "$BUILT_PHASES" 'Skipped in explicit list mode \(.--issues.\)' \
  "T12.19: built phases.md ships Step 1.6's mode note"

# H3 — Step 1.1b suppresses its own `○ Live backlog` line on a triage iteration
# because Step 1.1 "already reported the count". Step 1.1 specified no such
# line: `/issue-triage` prints `✓ Triage saved to …` instead, and
# `✓ Triage updated — {n} open issues` existed only in examples.md. Give the
# suppressed-for line a home in the step that is supposed to print it.
check_block_has "$STEP11_BLOCK" '^✓ Triage updated — \{n\} open issues$' \
  "T12.20: Step 1.1 prints the count line Step 1.1b suppresses itself for"
check_block_has "$STEP11_BLOCK" 'why \*Step 1\.1b\* prints no .○ Live backlog. line' \
  "T12.21: Step 1.1 names the suppression its line pays for"
check_block_has "$LIVEREAD_BLOCK" '\*Step 1\.1\*.s own .✓ Triage updated. line' \
  "T12.22: Step 1.1b still defers to that line rather than printing a second count"
check_has "$SRC_EXAMPLES" '^✓ Triage updated — [0-9]+ open issues$' \
  "T12.23: the examples narration renders the line phases.md now specifies"
check_has "$BUILT_PHASES" '^✓ Triage updated — \{n\} open issues$' \
  "T12.24: built phases.md ships the count line"
check_has "$BUILT_EXAMPLES" '^✓ Triage updated — [0-9]+ open issues$' \
  "T12.25: built examples.md still renders it"

# H4 — Step 1.2b called its record "live". It is fetched through `gi-issue.py`,
# whose TTL cache the resolver's Step 0i (T11.16) and Step 5.1b both name. When
# Step 1.1b is `unavailable` this re-check is the ONLY place Open/Not-assigned
# are enforced, so the claim has to match what the read can promise — and the
# real last word on `state` has to be named. Accuracy, not a new call site: T6.1
# and tests/test-scripts-252.sh's pinned gi-issue.py count both still hold.
check_block_lacks "$CAPTURE_BLOCK" 'This record is live' \
  "T12.26: 1.2b no longer calls a TTL-cached read live"
check_block_has "$CAPTURE_BLOCK" 'as fresh as .gi-issue\.py' \
  "T12.27: 1.2b bounds the record's freshness by the fetcher's TTL"
check_block_has "$CAPTURE_BLOCK" 'never "live"' \
  "T12.28: 1.2b says outright that the record is not live"
check_block_has "$CAPTURE_BLOCK" 'gh issue view N --json state,comments,updatedAt' \
  "T12.29: 1.2b names the resolver's live re-verify as the backstop"
check_block_has "$CAPTURE_BLOCK" 'last word on .state.' \
  "T12.30: 1.2b says which read is the last word on state, and it is not this one"
B_CAPTURE_BLOCK="$(anchor_span "$BUILT_PHASES" ap-step12b-capture ap-step13-plan || true)"
check_block_lacks "$B_CAPTURE_BLOCK" 'This record is live' \
  "T12.31: built phases.md ships the corrected freshness claim"
check_block_has "$B_CAPTURE_BLOCK" 'gh issue view N --json state,comments,updatedAt' \
  "T12.32: built phases.md ships the named backstop"

# ───────────────────────────────────────────────────────────
# T13 (#257 merge reconciliation): the two features coexist
# ───────────────────────────────────────────────────────────
# #257 landed a run-state Phase 0 carrying its own `Step 1.0 — Resume entry
# gate` and `Step 1.0b — Checkpoint procedure`. Four things had to be settled
# where the two features touch, and every one of them is prose that no other
# assertion would notice rotting:
#   R1 the name collision (this file's T2.1/T2.1b/T2.1c above, plus the
#      cross-file references below),
#   R2 `queue` in run-state.json vs `summary.suggested_order` in triage.json,
#   R3 what a `--resume` does to the cached order and to the pick filter,
#   R4 `--dry-run` for the two steps #258 added that touch a file.

# --- R1: every cross-file reference to the cache gate moved with it. ---
# `Step 1.0` still exists and still means #257's resume gate, so a blanket
# rename would have been wrong in both directions. Each file is pinned to the
# reference it should now carry.
check_has "$SRC_SKILL" '\*Step 1\.1a\*.s cache gate reads .fresh.' \
  "T13.1: SKILL.md's Mode Detection points at the renamed gate"
check_has "$SRC_CONFIG" 'reused by \*Step 1\.1a\*.s cache gate' \
  "T13.2: configuration.md points at the renamed gate"
check_has "$SRC_CONFIG" '\*Step 1\.1a\* is evaluated once' \
  "T13.3: configuration.md's off-switch note points at the renamed gate"
check_has "$SRC_ERRORS" 'because \*Step 1\.1a\* read the cache as .fresh.' \
  "T13.4: the error catalog points at the renamed gate"
check_has "$SRC_EXAMPLES" 'its own \*Step 1\.1a\* gate' \
  "T13.5: the examples narration points at the renamed gate"
check_has "$SRC_PROMPTS" 'mode-neutral .Step 1.2b.' \
  "T13.6: subagent-prompts.md points at mode-neutral capture"
check_has "$SRC_SUMMARY" 'a cache \*Step 1\.1a\* read as .fresh.' \
  "T13.7: summary-format.md points at the renamed gate"
# #257's own references must NOT have been renamed with it.
check_has "$SRC_ERRORS" '\*Step 1\.0\*.s gate resolved to .resumable.' \
  "T13.8: #257's resume-gate reference is untouched"
check_has "$SRC_SKILL" 'The resume entry gate, the run lock, and the checkpoints' \
  "T13.9: SKILL.md still points at Step 1.0 for the resume gate"
# Exactly one `### Step 1.0` heading in the file — the collision is what R1 fixed.
STEP10_HEADINGS="$(grep -cE '^### Step 1\.0 — ' "$SRC_PHASES" || true)"
if [ "$STEP10_HEADINGS" = "1" ]; then
  pass "T13.10: phases.md has exactly one '### Step 1.0 — ' heading"
else
  fail "T13.10: phases.md has $STEP10_HEADINGS '### Step 1.0 — ' headings, expected 1"
fi
# The rename has to explain itself where the step is defined, or the next reader
# renumbers it back.
check_block_has "$GATE_BLOCK" 'Lettered onto \*Step 1\.1\*' \
  "T13.11: the gate says why it is lettered onto 1.1"
check_block_has "$GATE_BLOCK" 'are a different thing entirely' \
  "T13.12: the gate disambiguates itself from Phase 0's Step 1.0"
check_block_has "$GATE_BLOCK" 'run-state\.json., not .\.gitissue/triage\.json' \
  "T13.13: the gate names the file each feature owns"

# --- R2: `queue` and `summary.suggested_order` are two facts, not two copies. ---
# #257's `--init` writes `queue` from `summary.suggested_order`; #258's Step 1.6
# mutates `summary.suggested_order` after every merge. Nothing syncs them, and
# nothing should: the fix is a declared authority, not a second writer.
check_block_has "$UPDATE_BLOCK" 'Two lists, two facts — never sync them' \
  "T13.14: Step 1.6 declares the two-list rule"
check_block_has "$UPDATE_BLOCK" 'live pick order' \
  "T13.15: Step 1.6 names summary.suggested_order as the live pick order"
check_block_has "$UPDATE_BLOCK" 'recorded intent at' \
  "T13.16: Step 1.6 names queue as the run's recorded intent"
check_block_has "$UPDATE_BLOCK" 'deliberately \*\*not\*\* re-derived here' \
  "T13.17: Step 1.6 states that it does not re-derive queue"
check_block_has "$UPDATE_BLOCK" 'this step never patches the run state' \
  "T13.18: Step 1.6 states that it never writes run-state.json"
check_block_has "$UPDATE_BLOCK" 'that difference is correct, not drift' \
  "T13.19: Step 1.6 says the divergence is expected"
check_block_has "$UPDATE_BLOCK" 'divergence by writing one into the other' \
  "T13.20: Step 1.6 forbids the sync a reader would otherwise add"
check_block_has "$UPDATE_BLOCK" 'never from .queue., so re-deriving' \
  "T13.21: Step 1.6 names what a resume actually reads instead"
# The cross-reference has to exist at the OTHER home too, or a reader of
# Step 1.0's payload table never learns the rule.
RESUME_BLOCK="$(anchor_span "$SRC_PHASES" ap-step10-resume ap-step10b-checkpoint || true)"
check_block_has "$RESUME_BLOCK" '\| .queue. \|' \
  "T13.22: Step 1.0 still documents the queue key"
check_block_has "$RESUME_BLOCK" 'Two lists, two facts' \
  "T13.23: Step 1.0's queue row points at Step 1.6's rule"
check_block_has "$RESUME_BLOCK" 're-derived when \*Step 1\.6\*' \
  "T13.24: Step 1.0's queue row states it is not re-derived per merge"
check_has "$REPO_ROOT/src/shared/scripts/gi-state.py" \
  'queue is recorded at --init and cannot be patched' \
  "T13.24b: gi-state.py refuses a queue patch (executable two-lists invariant)"

# --- R3: a resume still runs the gate, and the pick filters the seeded lists. ---
# A resumed run needs an order, so Step 1.1a runs on that path too; and the
# cached order it judges may predate merges the interrupted run already made, so
# only the seeded processed[]/skip_list[] keep those from being re-picked.
check_block_has "$GATE_BLOCK" 'every path into Phase 1, including .--resume.' \
  "T13.25: the gate runs on the resume path too"
check_block_has "$GATE_BLOCK" 'never the order itself' \
  "T13.26: the gate says the run state does not record the pick order"
STEP12_BLOCK="$(anchor_span "$SRC_PHASES" ap-step12-pick ap-step12b-capture || true)"
check_block_has "$STEP12_BLOCK" 'resume-seeded' \
  "T13.27: Step 1.2 names the resume-seeded lists"
check_block_has "$STEP12_BLOCK" '.skip_list\[\]. is seeded straight into the session skip list' \
  "T13.28: Step 1.2 says the seeded skip list IS the session skip list"
check_block_has "$STEP12_BLOCK" 'seeded .processed\[\]. rejects an issue the interrupted run already finished' \
  "T13.29: Step 1.2 states the re-pick hazard the seeding closes"
check_block_has "$STEP12_BLOCK" 'still four — a resume changes' \
  "T13.30: the resume clause does not invent a fifth eligibility criterion"
# tests/test-autopilot-dependency-gate.sh T13.15 pins `session skip list` to the
# `- **Not skipped**` bullet itself. Mirror that here so a rewrite of the bullet
# fails in this suite too, not only in the other one.
if printf '%s' "$STEP12_BLOCK" | grep -E '^- \*\*Not skipped\*\*' | grep -q 'session skip list'; then
  pass "T13.31: the Not-skipped bullet still names the session skip list"
else
  fail "T13.31: the Not-skipped bullet lost the session skip list"
fi
# Four buckets, and the resume seeding folds into one of them rather than adding
# a fifth — the sum is the property the table exists to hold.
check_block_has "$STEP12_BLOCK" '\| .resumed. \|.*\| .Skipped. \|' \
  "T13.32: the reason table maps resume seeding to the Skipped bucket"
check_block_has "$STEP12_BLOCK" 'adds no fifth bucket \*\*on purpose\*\*' \
  "T13.33: the table says why resume seeding gets no bucket of its own"
check_block_has "$STEP12_BLOCK" 'counts sum to the candidates' \
  "T13.34: the bucket sum is still stated as the invariant"

# --- R4: --dry-run for the two steps #258 added. ---
# #257's convention: every state-mutating call takes `--dry-run`, and Step 1.1
# drops `--out` so nothing is persisted ahead of the dry-run stop. Step 1.6
# writes `.gitissue/triage.json`, so it owes the same rule; Step 1.1a only reads.
check_block_has "$UPDATE_BLOCK" 'Under .--dry-run., compute the removal and print it, but write nothing' \
  "T13.35: Step 1.6 states the dry-run rule"
check_block_has "$UPDATE_BLOCK" 'never write .\.gitissue/triage\.json' \
  "T13.36: Step 1.6 names the file it must not write under --dry-run"
check_block_has "$GATE_BLOCK" 'read-only, so .--dry-run. does not change it' \
  "T13.37: Step 1.1a states that it is unaffected by --dry-run"
check_block_has "$GATE_BLOCK" 'writes nothing at all' \
  "T13.38: Step 1.1a states that it writes nothing"

# --- Verification: Step 1.6 and Step 5.3's checkpoint own different files. ---
# My conflict resolution put #257's end-of-iteration checkpoint at the end of
# Step 5.3 and Step 1.6 immediately after it. Two adjacent post-merge writers is
# exactly the shape a reader collapses into one.
check_block_has "$UPDATE_BLOCK" 'End-of-iteration checkpoint' \
  "T13.39: Step 1.6 names the checkpoint it runs alongside"
check_block_has "$UPDATE_BLOCK" 'different files' \
  "T13.40: Step 1.6 says the two own different files"
CLEANUP_BLOCK="$(anchor_span "$SRC_PHASES" ap-step53-cleanup ap-step16-cache-update || true)"
check_block_has "$CLEANUP_BLOCK" 'append this issue to .processed\[\]. with its final' \
  "T13.41: Step 5.3 still carries #257's end-of-iteration checkpoint"
check_block_lacks "$CLEANUP_BLOCK" 'summary\.suggested_order' \
  "T13.42: that checkpoint does not duplicate Step 1.6's job"

# --- The built tree ships all of it. ---
B_GATE_BLOCK="$(anchor_span "$BUILT_PHASES" ap-step11a-cache-gate ap-step11-triage || true)"
B_UPDATE_BLOCK="$(anchor_region "$BUILT_PHASES" ap-step16-cache-update || true)"
B_STEP12_BLOCK="$(anchor_span "$BUILT_PHASES" ap-step12-pick ap-step12b-capture || true)"
check_block_has "$B_GATE_BLOCK" 'every path into Phase 1, including .--resume.' \
  "T13.43: built phases.md ships the resume clause"
check_block_has "$B_GATE_BLOCK" 'read-only, so .--dry-run. does not change it' \
  "T13.44: built phases.md ships the gate's dry-run clause"
check_block_has "$B_UPDATE_BLOCK" 'Two lists, two facts — never sync them' \
  "T13.45: built phases.md ships the two-list rule"
check_block_has "$B_UPDATE_BLOCK" 'Under .--dry-run., compute the removal and print it, but write nothing' \
  "T13.46: built phases.md ships Step 1.6's dry-run rule"
check_block_has "$B_UPDATE_BLOCK" 'Discard the entire .summary.circular_deps. chain when it contains the' \
  "T13.47a: built phases.md discards cycles containing the resolved issue"
check_block_has "$B_UPDATE_BLOCK" 'preserve unrelated valid closed cycles unchanged' \
  "T13.47b: built phases.md preserves unrelated valid cycles"
check_block_has "$B_STEP12_BLOCK" 'resume-seeded' \
  "T13.47: built phases.md ships the resume-seeded pick filter"
check_has "$BUILT_CONFIG" 'reused by \*Step 1\.1a\*.s cache gate' \
  "T13.48: built configuration.md ships the renamed reference"
check_has "$BUILT_SKILL" '\*Step 1\.1a\*.s cache gate reads .fresh.' \
  "T13.49: built SKILL.md ships the renamed reference"
check_has "$BUILT_SUMMARY" 'a cache \*Step 1\.1a\* read as .fresh.' \
  "T13.50: built summary-format.md ships the renamed reference"

# Issue #260 consumes, rather than recomputes, the independent groups this
# payload already persists. The priority anchor stays first and one fan-out may
# draw from one group only.
check_block_has "$STEP12_BLOCK" 'first eligible issue remains the priority anchor' \
  "T14.1 (#260): parallel selection keeps the triage priority anchor"
check_block_has "$STEP12_BLOCK" 'members of \*\*that one group only\*\*' \
  "T14.2 (#260): a fan-out cannot combine parallel groups"
check_block_has "$STEP12_BLOCK" 'summary\.suggested_order' \
  "T14.3 (#260): lane order still derives from the persisted suggested order"
check_block_has "$STEP12_BLOCK" 'remaining .max_iterations. budget' \
  "T14.4 (#260): lane selection cannot exceed the run iteration budget"
check_block_has "$B_STEP12_BLOCK" 'members of \*\*that one group only\*\*' \
  "T14.5 (#260): built phases ship the one-group selection rule"

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
