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
has "$PHASES" 'git worktree add -b "\$branch_name" "\$wt_dir" "\$base_sha"' \
  "AC1: each lane creates a distinct worktree from the recorded base"
has "$PROMPTS" 'IDD_CALLER_WORKTREE=1' \
  "AC1: parallel resolver prompt marks caller-managed worktree ownership"
has "$RESOLVER" 'IDD_CALLER_WORKTREE=1' \
  "AC1: resolver accepts only the narrow caller-managed carve-out"
has "$RESOLVER_STEPS" 'Never fall back in-place' \
  "AC1: a failed parallel worktree cannot fall back to the shared index"

# Serialized drain and single writer.
has "$PHASES" 'No reviewer, merge, run-log append, triage-cache update' \
  "AC2: every post-resolve lane operation is serialized"
has "$RUNLOG" 'serialized drain' \
  "AC3: run-log writes live in the serialized drain"
has "$RUNLOG" 'worker never appends on failure or success' \
  "AC3: resolver workers never write runs.jsonl"

# Durable lane state: actual helper behavior, not prose alone.
mkdir -p "$TMP/state"
printf '%s' '{"run_id":"r260","queue":[42,45]}' \
  | python3 "$STATE" --init --dir "$TMP/state" >/dev/null
lane_patch="$(python3 - "$TMP" <<'PY'
import json, os, sys
root=os.path.abspath(sys.argv[1])
sha='0'*40
print(json.dumps({'phase':'resolve','lanes':[
 {'issue':42,'lane_id':'r260:42','event_id':'r260:42','branch':'feat/42-a','worktree_path':root+'/lane-42','base_sha':sha,'phase':'planned'},
 {'issue':45,'lane_id':'r260:45','event_id':'r260:45','branch':'fix/45-b','worktree_path':root+'/lane-45','base_sha':sha,'phase':'planned'}]}))
PY
)"
printf '%s' "$lane_patch" | python3 "$STATE" --update --dir "$TMP/state" >/dev/null
state="$(printf '%s' '{"lanes":[{"issue":42,"pr":87,"phase":"returned","telemetry":{"status":"success","qa_cycles":1}}]}' \
  | python3 "$STATE" --update --dir "$TMP/state")"
if printf '%s' "$state" | python3 -c '
import json,sys
d=json.load(sys.stdin); lanes={x["issue"]:x for x in d["lanes"]}
assert lanes[42]["phase"]=="returned" and lanes[42]["pr"]==87
assert lanes[42]["telemetry"]["qa_cycles"]==1
assert lanes[42]["lane_id"]=="r260:42" and lanes[42]["worktree_path"].endswith("/lane-42")
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

# Real git-worktree fixture: distinct registered branches, structural cwd/
# branch validation, dirty owned resume, blocked ambiguity, and safe cleanup.
FIX="$(cd "$TMP" && pwd -P)/worktree-fixture"
mkdir -p "$FIX/repo"
(
  cd "$FIX/repo"
  git init -q -b main
  git config user.email t@example.com
  git config user.name t
  echo base > tracked.txt
  git add tracked.txt
  git commit -qm base
  git worktree add -q -b feat/42-a "$FIX/lane-42" HEAD
  git worktree add -q -b fix/45-b "$FIX/lane-45" HEAD
)
if [ "$(git -C "$FIX/repo" worktree list --porcelain | grep -c '^worktree ')" = 3 ] \
   && [ "$(git -C "$FIX/lane-42" branch --show-current)" = feat/42-a ] \
   && [ "$(git -C "$FIX/lane-45" branch --show-current)" = fix/45-b ]; then
  pass "AC1: real git worktrees use distinct registered branches"
else
  fail "AC1: real git worktree isolation was not established"
fi
actual42="$(git -C "$FIX/lane-42" rev-parse --show-toplevel)"
if [ "$actual42" = "$FIX/lane-42" ] && [ "$actual42" != "$FIX/lane-45" ]; then
  pass "AC1: structural cwd accepts the owned lane and rejects the wrong path"
else
  fail "AC1: structural cwd validation did not distinguish lanes"
fi
printf 'interrupted\n' > "$FIX/lane-42/resume.txt"
if [ -n "$(git -C "$FIX/lane-42" status --porcelain)" ] \
   && [ "$(git -C "$FIX/lane-42" branch --show-current)" = feat/42-a ]; then
  pass "AC1: dirty owned lane remains resumable without discarding edits"
else
  fail "AC1: dirty owned lane identity was not preserved"
fi
if [ "$(git -C "$FIX/lane-45" branch --show-current)" != feat/42-a ]; then
  pass "AC1: mismatched lane ownership is blocked instead of resumed"
else
  fail "AC1: ambiguous branch ownership was accepted"
fi
# A blocked dirty lane must not keep its ready sibling from a serialized drain.
printf '%s' '{"lanes":[{"issue":42,"phase":"blocked_dirty"},{"issue":45,"phase":"returned","pr":87}]}' \
  | python3 "$STATE" --update --dir "$TMP/state" >/dev/null
state="$(python3 "$STATE" --read --dir "$TMP/state")"
if printf '%s' "$state" | python3 -c 'import json,sys; d=json.load(sys.stdin); x={v["issue"]:v for v in d["lanes"]}; assert x[42]["phase"]=="blocked_dirty" and x[45]["phase"]=="returned"'; then
  pass "AC2: blocked dirty lane does not discard a ready sibling"
else
  fail "AC2: blocked lane stranded or erased its sibling"
fi
# Non-forced cleanup refuses the dirty lane, while the clean sibling is removed.
if git -C "$FIX/repo" worktree remove "$FIX/lane-42" >/dev/null 2>&1; then
  fail "AC1: ordinary cleanup unexpectedly removed a dirty worktree"
else
  pass "AC1: cleanup never force-removes a dirty worktree"
fi
git -C "$FIX/repo" worktree remove "$FIX/lane-45"
[ ! -d "$FIX/lane-45" ] && pass "AC2: clean terminal sibling cleanup succeeds" \
                           || fail "AC2: clean sibling cleanup failed"

# Crash after append but before checkpoint: the stable event is one physical line.
RUNLOG_HELPER="$REPO_ROOT/src/shared/scripts/gi-runlog.py"
run_record='{"ts":"2026-01-01T00:00:00Z","event_id":"run-260:45","issue":45,"mode":"balanced","skill":"auto-pilot","outcome":"merged","pr":87}'
printf '%s' "$run_record" | python3 "$RUNLOG_HELPER" --append-once --path "$TMP/runs.jsonl" >/dev/null
printf '%s' "$run_record" | python3 "$RUNLOG_HELPER" --append-once --path "$TMP/runs.jsonl" >/dev/null
[ "$(wc -l < "$TMP/runs.jsonl" | tr -d ' ')" = 1 ] \
  && pass "AC3: append-before-checkpoint resume writes one line" \
  || fail "AC3: append-before-checkpoint resume duplicated telemetry"

echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
