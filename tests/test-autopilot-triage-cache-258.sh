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
SRC_SKILL="$REPO_ROOT/src/skills/auto-pilot/SKILL.source.md"
SRC_PROMPTS="$REPO_ROOT/src/skills/auto-pilot/references/subagent-prompts.md"
SRC_SUMMARY="$REPO_ROOT/src/skills/auto-pilot/references/summary-format.md"
SRC_PERSIST="$REPO_ROOT/src/skills/issue-triage/references/output-and-persist.md"
SRC_TRIAGE_SKILL="$REPO_ROOT/src/skills/issue-triage/SKILL.source.md"
SCHEMA="$REPO_ROOT/docs/config-schema.md"

BUILT_PHASES="$REPO_ROOT/skills/auto-pilot/references/phases.md"
BUILT_SKILL="$REPO_ROOT/skills/auto-pilot/SKILL.md"
BUILT_PROMPTS="$REPO_ROOT/skills/auto-pilot/references/subagent-prompts.md"
BUILT_SUMMARY="$REPO_ROOT/skills/auto-pilot/references/summary-format.md"
BUILT_PERSIST="$REPO_ROOT/skills/issue-triage/references/output-and-persist.md"

for file in "$SRC_PHASES" "$SRC_SKILL" "$SRC_PROMPTS" "$SRC_SUMMARY" \
            "$SRC_PERSIST" "$SRC_TRIAGE_SKILL" "$SCHEMA" "$GRAPH" \
            "$BUILT_PHASES" "$BUILT_SKILL" "$BUILT_PROMPTS" "$BUILT_SUMMARY" \
            "$BUILT_PERSIST"; do
  if [ -f "$file" ]; then
    pass "exists: ${file#$REPO_ROOT/}"
  else
    fail "missing: ${file#$REPO_ROOT/} — run ./scripts/build.sh"
  fi
done

# ───────────────────────────────────────────────────────────
# T1 (AC2): the orchestrator's one bulk fetch carries no bodies
# ───────────────────────────────────────────────────────────
# Two halves, and both matter. The list must still END in `state,updatedAt` —
# #256's T1.1 pins that shape, and both fields are structural inputs to the
# resolver's Step 0i gate — while `body` must be gone from it.
check_has "$SRC_PHASES" 'gh issue list --state open --json [a-zA-Z,]*state,updatedAt' \
  "T1.1: Phase 1's list call still ends in state,updatedAt"
check_lacks "$SRC_PHASES" 'gh issue list --state open --json [a-zA-Z,]*body' \
  "T1.2: Phase 1's list call no longer requests body"
check_has "$SRC_PHASES" '--limit 100' \
  "T1.3: the bulk list is still bounded by an explicit limit"
STEP11_BLOCK="$(awk '/^### Step 1\.1 — Triage/,/^### Step 1\.2 — Pick Next Issue/' "$SRC_PHASES")"
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
check_block_has "$UPDATE_BLOCK" 'only after \*Step 5\.2\* merged' \
  "T3.11: the update runs only after a merge actually closed an issue"

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
check_has "$BUILT_PROMPTS" 'verbatim from that step.s single-issue fetch' \
  "T9.9: built subagent-prompts.md ships the new payload provenance"
check_has "$BUILT_SUMMARY" 'Triage current' \
  "T9.10: built summary-format.md ships the reuse-safe check name"
check_has "$BUILT_PERSIST" 'Cross-skill incremental updates' \
  "T9.11: built output-and-persist.md ships the cross-skill writer contract"

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
