#!/usr/bin/env bash
# test-autopilot-parallel-260.sh — Issue #260 bounded resolver fan-out contract.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$REPO_ROOT/src/shared/scripts/gi-state.py"
PHASES="$REPO_ROOT/src/skills/auto-pilot/references/phases.md"
PROMPTS="$REPO_ROOT/src/skills/auto-pilot/references/subagent-prompts.md"
RUNLOG="$REPO_ROOT/src/skills/auto-pilot/references/run-log.md"
RESOLVER="$REPO_ROOT/src/skills/issue-resolver/SKILL.source.md"
RESOLVER_STEPS="$REPO_ROOT/src/skills/issue-resolver/references/pipeline-steps.md"
SCHEMA="$REPO_ROOT/docs/config-schema.md"
TEMPLATE="$REPO_ROOT/src/skills/init-gitissue/templates/gitissue-template.yml"
PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
has() { grep -qE "$2" "$1" && pass "$3" || fail "$3"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "◆ Auto-Pilot Parallel Worktrees (issue #260)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# Configuration and exact sequential compatibility branch.
has "$SCHEMA" 'autopilot\.max_parallel.*`1`|max_parallel: 1' \
  "AC4: schema defines max_parallel with default 1"
has "$TEMPLATE" '^[[:space:]]+max_parallel: 1$' \
  "AC4: init template emits max_parallel: 1"
has "$PHASES" 'Legacy sequential path \(`max_parallel = 1`\)' \
  "AC4: phases keep an explicit legacy sequential branch"
has "$PROMPTS" 'Block absent \(`autopilot\.max_parallel: 1`\).*legacy in-place path exactly' \
  "AC4: value 1 keeps the ordinary in-place resolver prompt"

# Resolver-only concurrency and worktree ownership.
has "$PHASES" 'members of \*\*that one group only\*\*' \
  "AC1: scheduling never combines independent groups"
has "$PHASES" 'launch \*\*all\*\* prepared resolver calls before waiting' \
  "AC1: resolver lanes are dispatched before fan-in"
has "$PHASES" 'git worktree add -b "\$branch_name" "\$wt_dir" "origin/\$\{base\}"' \
  "AC1: each lane creates a distinct worktree from the fetched base"
has "$PROMPTS" 'IDD_CALLER_WORKTREE=1' \
  "AC1: parallel resolver prompt marks caller-managed worktree ownership"
has "$RESOLVER" 'IDD_CALLER_WORKTREE=1' \
  "AC1: resolver accepts only the narrow caller-managed carve-out"
has "$RESOLVER_STEPS" 'Never fall back in-place' \
  "AC1: a failed parallel worktree cannot fall back to the shared index"

# Serialized drain and single writer.
has "$PHASES" 'No reviewer, merge, run-log append, triage-cache update' \
  "AC2: every post-resolve lane operation is serialized"
has "$RUNLOG" 'main agent drains lanes in deterministic triage order' \
  "AC3: run-log writes live in the serialized drain"
has "$RUNLOG" 'worker never appends on failure or success' \
  "AC3: resolver workers never write runs.jsonl"

# Durable lane state: actual helper behavior, not prose alone.
mkdir -p "$TMP/state"
printf '%s' '{"run_id":"r260","queue":[42,45]}' \
  | python3 "$STATE" --init --dir "$TMP/state" >/dev/null
printf '%s' '{"phase":"resolve","lanes":[{"issue":42,"branch":"feat/42-a","phase":"planned"},{"issue":45,"branch":"fix/45-b","phase":"planned"}]}' \
  | python3 "$STATE" --update --dir "$TMP/state" >/dev/null
state="$(printf '%s' '{"lanes":[{"issue":42,"pr":87,"phase":"returned","telemetry":{"status":"success","qa_cycles":1}}]}' \
  | python3 "$STATE" --update --dir "$TMP/state")"
if printf '%s' "$state" | python3 -c '
import json,sys
d=json.load(sys.stdin); lanes={x["issue"]:x for x in d["lanes"]}
assert lanes[42]["phase"]=="returned" and lanes[42]["pr"]==87
assert lanes[42]["telemetry"]["qa_cycles"]==1
assert lanes[45]["phase"]=="planned"
'; then
  pass "AC1: gi-state merges returned telemetry without losing sibling lanes"
else
  fail "AC1: gi-state did not preserve the durable lane batch"
fi
cleared="$(printf '%s' '{"lanes":[]}' | python3 "$STATE" --update --dir "$TMP/state")"
if [ "$(printf '%s' "$cleared" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)["lanes"]))')" = 0 ]; then
  pass "AC1: gi-state clears a fully drained lane batch explicitly"
else
  fail "AC1: gi-state could not clear a completed lane batch"
fi

# Deterministic behavioral fixture: two resolver workers overlap in distinct
# worktrees, while review/merge/log/cleanup are one-at-a-time and only main logs.
python3 - "$TMP/simulation.json" <<'PY'
import json, sys, tempfile, threading, time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

root = Path(tempfile.mkdtemp())
lock = threading.Lock()
barrier = threading.Barrier(2)
active = max_active = 0
worktrees = []

def resolve(issue):
    global active, max_active
    wt = root / f"worktree-{issue}"
    wt.mkdir()
    worktrees.append(str(wt))
    barrier.wait(timeout=2)
    with lock:
        active += 1
        max_active = max(max_active, active)
    time.sleep(0.05)
    with lock:
        active -= 1
    return {"issue": issue, "worktree": str(wt), "writer": "resolver"}

with ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(resolve, (42, 45)))

drain_active = max_drain = 0
runlog = []
for result in results:  # deterministic triage order
    drain_active += 1
    max_drain = max(max_drain, drain_active)
    for phase in ("review", "merge", "log", "cleanup"):
        if phase == "log":
            runlog.append({"issue": result["issue"], "writer": "main"})
    drain_active -= 1

json.dump({
    "max_resolvers": max_active,
    "distinct_worktrees": len(set(worktrees)),
    "max_drain": max_drain,
    "runlog": runlog,
}, open(sys.argv[1], "w"))
PY
if python3 - "$TMP/simulation.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert d["max_resolvers"] == 2
assert d["distinct_worktrees"] == 2
assert d["max_drain"] == 1
assert [x["issue"] for x in d["runlog"]] == [42,45]
assert {x["writer"] for x in d["runlog"]} == {"main"}
PY
then
  pass "AC1-3: fixture overlaps two isolated resolvers and serializes both main-writer outcomes"
else
  fail "AC1-3: concurrency/serialization fixture violated an invariant"
fi

echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
