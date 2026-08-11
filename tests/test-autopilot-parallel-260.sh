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
RESEARCHER="$REPO_ROOT/src/shared/agents/codebase-researcher.md"
SYNTHESIZER="$REPO_ROOT/src/shared/agents/synthesizer.md"
IMPLEMENTER="$REPO_ROOT/src/shared/agents/implementer.md"
REVIEWER="$REPO_ROOT/src/shared/agents/code-reviewer.md"
UI_REVIEWER="$REPO_ROOT/src/shared/agents/ui-reviewer.md"
FIXER="$REPO_ROOT/src/shared/agents/fixer.md"
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
has "$RESOLVER_STEPS" 'structured input to every nested spawn' \
  "AC1: resolver propagates one validated workspace contract to nested agents"
has "$RESOLVER_STEPS" 'Agent\(description, prompt\)' \
  "AC1: nested isolation does not invent unsupported Agent cwd/env arguments"
for entry in \
  "$RESEARCHER:researcher" \
  "$IMPLEMENTER:implementer" \
  "$REVIEWER:reviewer" \
  "$UI_REVIEWER:ui reviewer" \
  "$FIXER:fixer"; do
  file="${entry%%:*}"; role="${entry#*:}"
  has "$file" 'workspace_contract' \
    "AC1: nested $role receives the workspace contract"
  has "$file" 'cd -- "\$canonical_root"|git -C "\$canonical_root"' \
    "AC1: nested $role rejects ambient-root repository operations"
done
has "$SYNTHESIZER" 'workspace_contract.*structural lane context' \
  "AC1: data-only synthesizer preserves structural lane context"

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

# Real git-worktree fixture executes the documented caller-managed validation:
# registered path/branch/base/lane identity, fresh cleanliness, safe dirty resume,
# and rejection of active Git state or any mismatched identity.
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
base_sha="$(git -C "$FIX/repo" rev-parse HEAD)"
validate_lane() {
  lane_root=$1 expected_branch=$2 expected_base=$3 lane_id=$4 event_id=$5 resume=$6
  actual_root="$(git -C "$lane_root" rev-parse --show-toplevel 2>/dev/null)" || return 1
  actual_branch="$(git -C "$lane_root" branch --show-current 2>/dev/null)" || return 1
  git_dir="$(cd "$(git -C "$lane_root" rev-parse --git-dir)" && pwd)" || return 1
  common_dir="$(cd "$(git -C "$lane_root" rev-parse --git-common-dir)" && pwd)" || return 1
  [ "$actual_root" = "$lane_root" ] || return 1
  [ "$actual_branch" = "$expected_branch" ] || return 1
  [ "$git_dir" != "$common_dir" ] || return 1
  [ -n "$lane_id" ] && [ "$lane_id" = "$event_id" ] || return 1
  git -C "$lane_root" cat-file -e "${expected_base}^{commit}" 2>/dev/null || return 1
  git -C "$lane_root" merge-base --is-ancestor "$expected_base" HEAD || return 1
  git -C "$FIX/repo" worktree list --porcelain | awk -v p="$lane_root" -v b="refs/heads/$expected_branch" '
    $1=="worktree" {path=$2; branch=""}
    $1=="branch" {branch=$2}
    path==p && branch==b {found=1}
    END {exit !found}
  ' || return 1
  for marker in MERGE_HEAD REBASE_HEAD CHERRY_PICK_HEAD BISECT_LOG; do
    [ ! -e "$git_dir/$marker" ] || return 1
  done
  [ ! -d "$git_dir/rebase-merge" ] && [ ! -d "$git_dir/rebase-apply" ] || return 1
  [ -z "$(git -C "$lane_root" status --porcelain)" ] || [ "$resume" = 1 ]
}

validate_lane "$FIX/lane-42" feat/42-a "$base_sha" r260:42 r260:42 0 \
  && pass "AC1: exact validation accepts a fresh owned worktree" \
  || fail "AC1: exact validation rejected a fresh owned worktree"
# Simulate the nested-agent contract: validate the lane, then perform its edit
# through an absolute path rooted in that worktree. The original checkout must
# stay byte-identical and clean.
original_before="$(cat "$FIX/repo/tracked.txt")"
if validate_lane "$FIX/lane-42" feat/42-a "$base_sha" r260:42 r260:42 0; then
  canonical_root="$(cd "$FIX/lane-42" && pwd -P)"
  (cd -- "$canonical_root" && printf 'nested lane edit\n' > nested-output.txt)
fi
if [ -f "$FIX/lane-42/nested-output.txt" ] \
   && [ ! -e "$FIX/repo/nested-output.txt" ] \
   && [ "$(cat "$FIX/repo/tracked.txt")" = "$original_before" ] \
   && [ -z "$(git -C "$FIX/repo" status --porcelain)" ]; then
  pass "AC1: nested mutation is confined to the validated real worktree"
else
  fail "AC1: nested mutation reached or dirtied the original checkout"
fi
if validate_lane "$FIX/lane-45" feat/42-a "$base_sha" r260:42 r260:42 0 \
   || validate_lane "$FIX/lane-42" feat/42-a 0000000000000000000000000000000000000000 r260:42 r260:42 0 \
   || validate_lane "$FIX/lane-42" feat/42-a "$base_sha" r260:42 wrong:event 0; then
  fail "AC1: exact validation accepted wrong path/branch, base, or lane identity"
else
  pass "AC1: exact validation rejects wrong path/branch, base, and lane identity"
fi
printf 'interrupted\n' > "$FIX/lane-42/resume.txt"
if ! validate_lane "$FIX/lane-42" feat/42-a "$base_sha" r260:42 r260:42 0 \
   && validate_lane "$FIX/lane-42" feat/42-a "$base_sha" r260:42 r260:42 1; then
  pass "AC1: only an identity-owned resume preserves dirty edits"
else
  fail "AC1: dirty fresh/resume validation did not follow the contract"
fi
git_dir42="$(cd "$(git -C "$FIX/lane-42" rev-parse --git-dir)" && pwd)"
touch "$git_dir42/MERGE_HEAD"
if validate_lane "$FIX/lane-42" feat/42-a "$base_sha" r260:42 r260:42 1; then
  fail "AC1: exact validation accepted an active Git operation"
else
  pass "AC1: exact validation blocks active Git operations"
fi
rm -f "$git_dir42/MERGE_HEAD"
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

# Concurrent crash retries: all processes race on one stable event, but the
# advisory lock makes the read/check/append/fsync transaction one physical line.
RUNLOG_HELPER="$REPO_ROOT/src/shared/scripts/gi-runlog.py"
run_record='{"ts":"2026-01-01T00:00:00Z","event_id":"run-260:45","issue":45,"mode":"balanced","skill":"auto-pilot","outcome":"merged","pr":87}'
pids=""
for _ in 1 2 3 4 5 6 7 8; do
  (printf '%s' "$run_record" | python3 "$RUNLOG_HELPER" --append-once --path "$TMP/runs.jsonl" >/dev/null) &
  pids="$pids $!"
done
race_ok=1
for pid in $pids; do wait "$pid" || race_ok=0; done
if [ "$race_ok" = 1 ] && [ "$(wc -l < "$TMP/runs.jsonl" | tr -d ' ')" = 1 ]; then
  pass "AC3: concurrent append-before-checkpoint retries write one line"
else
  fail "AC3: concurrent append-once retries duplicated or rejected telemetry"
fi
conflict='{"ts":"2026-01-01T00:00:00Z","event_id":"run-260:45","issue":45,"mode":"balanced","skill":"auto-pilot","outcome":"failed","pr":87}'
set +e
printf '%s' "$conflict" | python3 "$RUNLOG_HELPER" --append-once --path "$TMP/runs.jsonl" >/dev/null 2>&1
conflict_rc=$?
set -e
[ "$conflict_rc" = 3 ] \
  && pass "AC3: concurrent event identity rejects conflicting payload" \
  || fail "AC3: conflicting event payload exited $conflict_rc instead of 3"

echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
