#!/usr/bin/env bash
# test-subagent-context-256.sh — Caller-supplied subagent context (issue #256)
#
# Acceptance criteria:
#   AC1: /auto-pilot passes the issue payload it already holds to the subagents
#        it spawns, and the resolver consumes it in place of Step 0a's fetch —
#        that read only, and only when the payload is complete.
#   AC2: the triage graph reaches the researcher as a `triage_context` payload
#        key with an explicit trust profile: no commit pin, so it may reorder a
#        scan and never authorise skipping a phase.
#   AC3: /auto-pilot consumes the SHA-bound `ci_status` /issue-pr-review already
#        returns instead of re-polling CI — without loosening the rule that a
#        PR-body marker never skips a CI wait.
#   AC4: the resolver's last-green test state has one home and two consumers,
#        layered under `resolve.auto_test`, never over it.
#
# Every gate here may gate duplicated work and never a safety gate; the boundary
# block (T5) is the group that must not be weakened.
#
# Asserts on the authored src/ sources AND on the built skills/ tree, because a
# contract that ships only in src/ is not installed for anyone.
#
# Usage: bash tests/test-subagent-context-256.sh
# Returns: exit 0 if all checks pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

has() {
  local file="$1"
  local pattern="$2"
  grep -qE "$pattern" "$file" 2>/dev/null
}

check_has() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if has "$file" "$pattern"; then
    pass "$label"
  else
    fail "$label"
    echo "      missing pattern: $pattern"
    echo "      in file: ${file#$REPO_ROOT/}"
  fi
}

check_lacks() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if has "$file" "$pattern"; then
    fail "$label"
    echo "      forbidden pattern still present: $pattern"
    echo "      in file: ${file#$REPO_ROOT/}"
  else
    pass "$label"
  fi
}

check_block_has() {
  local block="$1"
  local pattern="$2"
  local label="$3"
  if printf '%s' "$block" | grep -qE "$pattern"; then
    pass "$label"
  else
    fail "$label"
    echo "      missing pattern: $pattern"
  fi
}

echo "◆ Subagent Context Passing Contract Tests (issue #256)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

SRC_CONV="$REPO_ROOT/docs/shared-agent-conventions.md"
SRC_RESEARCHER="$REPO_ROOT/src/shared/agents/codebase-researcher.md"
SRC_AP_SKILL="$REPO_ROOT/src/skills/auto-pilot/SKILL.source.md"
SRC_AP_PHASES="$REPO_ROOT/src/skills/auto-pilot/references/phases.md"
SRC_AP_PROMPTS="$REPO_ROOT/src/skills/auto-pilot/references/subagent-prompts.md"
SRC_AP_EXAMPLES="$REPO_ROOT/src/skills/auto-pilot/references/examples.md"
SRC_RES_SKILL="$REPO_ROOT/src/skills/issue-resolver/SKILL.source.md"
SRC_RES_STEPS="$REPO_ROOT/src/skills/issue-resolver/references/pipeline-steps.md"
SRC_PR_SKILL="$REPO_ROOT/src/skills/issue-pr-review/SKILL.source.md"
SRC_PR_CI="$REPO_ROOT/src/skills/issue-pr-review/references/prepass-tests-ci-mechanics.md"

BUILT_CONV="$REPO_ROOT/skills/auto-pilot/references/docs/shared-agent-conventions.md"
BUILT_RESEARCHER="$REPO_ROOT/skills/issue-resolver/references/agents/codebase-researcher.md"
BUILT_AP_SKILL="$REPO_ROOT/skills/auto-pilot/SKILL.md"
BUILT_AP_PHASES="$REPO_ROOT/skills/auto-pilot/references/phases.md"
BUILT_AP_PROMPTS="$REPO_ROOT/skills/auto-pilot/references/subagent-prompts.md"
BUILT_AP_EXAMPLES="$REPO_ROOT/skills/auto-pilot/references/examples.md"
BUILT_RES_SKILL="$REPO_ROOT/skills/issue-resolver/SKILL.md"
BUILT_RES_STEPS="$REPO_ROOT/skills/issue-resolver/references/pipeline-steps.md"
BUILT_PR_SKILL="$REPO_ROOT/skills/issue-pr-review/SKILL.md"
BUILT_PR_CI="$REPO_ROOT/skills/issue-pr-review/references/prepass-tests-ci-mechanics.md"

for file in "$SRC_CONV" "$SRC_RESEARCHER" "$SRC_AP_SKILL" "$SRC_AP_PHASES" \
            "$SRC_AP_PROMPTS" "$SRC_AP_EXAMPLES" "$SRC_RES_SKILL" \
            "$SRC_RES_STEPS" "$SRC_PR_SKILL" "$SRC_PR_CI" "$BUILT_CONV" \
            "$BUILT_RESEARCHER" "$BUILT_AP_SKILL" "$BUILT_AP_PHASES" \
            "$BUILT_AP_PROMPTS" "$BUILT_AP_EXAMPLES" "$BUILT_RES_SKILL" \
            "$BUILT_RES_STEPS" "$BUILT_PR_SKILL" "$BUILT_PR_CI"; do
  if [ -f "$file" ]; then
    pass "exists: ${file#$REPO_ROOT/}"
  else
    fail "missing: ${file#$REPO_ROOT/} — run ./scripts/build.sh"
  fi
done

# ───────────────────────────────────────────────────────────
# T1 (AC1): the payload is injected from the call that already
# happens, and it substitutes for 0a's read — nothing else.
# ───────────────────────────────────────────────────────────
# Phase 1's list call must carry `state` and `updatedAt`. Without updatedAt a
# caller-supplied payload cannot feed #254's Step 0h condition 5, and that gate
# fail-safes to `stale` on every /auto-pilot run — a silent regression against a
# merged sibling, with the whole suite green.
check_has "$SRC_AP_PHASES" 'gh issue list --state open --json [a-zA-Z,]*state,updatedAt' \
  "T1.1: Phase 1's list call requests state and updatedAt"
check_has "$SRC_AP_PHASES" '^### Step 1\.2b — Capture the caller payload' \
  "T1.2: auto-pilot has a named step that captures the payload"
check_has "$SRC_AP_PROMPTS" '\{issue_payload\}' \
  "T1.3: the spawn prompts substitute an {issue_payload} variable"
check_has "$SRC_AP_PROMPTS" '\| .\{issue_payload\}. \|' \
  "T1.4: {issue_payload} is declared in the Template Variables table"
check_has "$SRC_RES_STEPS" '^## Step 0i — Caller payload gate' \
  "T1.5: the resolver owns a named gate for the caller payload"
check_has "$SRC_RES_STEPS" 'issue_payload = supplied \| partial \| absent' \
  "T1.6: the gate sets exactly one three-state variable"
check_has "$SRC_RES_STEPS" '^### Scope — 0a.s read only' \
  "T1.7: the gate scopes the substitution to 0a's read"

PAYLOAD_BLOCK="$(awk '/^## Step 0i — Caller payload gate/,/^## Step 1 — Research/' "$SRC_RES_STEPS")"
check_block_has "$PAYLOAD_BLOCK" '0d still rewrites the body' \
  "T1.8: 0d still rewrites the body and still invalidates the cache"
check_block_has "$PAYLOAD_BLOCK" 'updatedAt. is \*\*required, not decorative\*\*' \
  "T1.9: updatedAt is required, and the reason (0h condition 5) is stated"
check_block_has "$PAYLOAD_BLOCK" 'Step 0h' \
  "T1.10: the gate names the sibling gate that consumes updatedAt"
check_has "$SRC_RES_SKILL" 'issue_payload = supplied \| partial \| absent' \
  "T1.11: the SKILL pointer carries the three states, first read wins"

# ───────────────────────────────────────────────────────────
# T2 (AC2): triage_context is a sibling payload key with a
# WEAKER guarantee than prior_analysis, and the difference is
# stated in ONE extended contract block — never a second block
# repeating #254's words, which would drift from them.
# ───────────────────────────────────────────────────────────
check_has "$SRC_RES_STEPS" '"triage_context": null' \
  "T2.1: the Step 1 delegation payload carries a triage_context key"
check_has "$SRC_RES_STEPS" '^### .triage_context. \(when supplied\)' \
  "T2.2: pipeline-steps documents when triage_context is populated"
check_has "$SRC_RESEARCHER" '^### .prior_analysis. and .triage_context. \(when supplied\)' \
  "T2.3: the researcher contract block covers BOTH artifacts under one heading"
SUPPLIED_HEADINGS="$(grep -cE '^### .*\(when supplied\)' "$SRC_RESEARCHER" || true)"
if [ "$SUPPLIED_HEADINGS" = "1" ]; then
  pass "T2.4: exactly one 'when supplied' contract block exists (extended, not duplicated)"
else
  fail "T2.4: expected 1 'when supplied' contract block, found $SUPPLIED_HEADINGS — a second block drifts from #254's wording"
fi
check_has "$SRC_RESEARCHER" 'no commit pin at all' \
  "T2.5: the researcher states triage_context carries no commit pin"
check_has "$SRC_RESEARCHER" '\*\*reorder\*\* a scan and never authorises' \
  "T2.6: triage_context may reorder a scan, never authorise skipping a phase"
check_has "$SRC_RES_STEPS" 'only \*\*reorder\*\* a scan' \
  "T2.7: the caller side states the same reorder-never-skip limit"
check_has "$SRC_RESEARCHER" 'If .triage_context. was supplied, use it and \*\*do not read the file\*\*' \
  "T2.8: Phase 5's own triage read is moved to the caller, not duplicated"
# #254's pinned literals must survive verbatim — the block was extended above
# and below them, never rewritten.
check_has "$SRC_RESEARCHER" 'verify-first hints to confirm or refute, never assertions to trust' \
  "T2.9: #254's verify-first literal survives the extension"
check_has "$SRC_RESEARCHER" 'Phase 0 .*runs \*\*in full\*\*' \
  "T2.10: #254's 'Phase 0 runs in full' literal survives the extension"

# ───────────────────────────────────────────────────────────
# T3 (AC3): the CI verdict is commit-bound and re-verified, and
# the marker rule it sits beside is NOT loosened. A reader who
# mistakes an in-process return value for a PR-body marker would
# read this as permission to skip a CI wait on author-written
# evidence — which is exactly what #255 forbids.
# ───────────────────────────────────────────────────────────
check_has "$SRC_AP_PROMPTS" 'ci_status: "passed@<sha40>", "failed@<sha40>", or "no_ci"' \
  "T3.1: the reviewer's ci_status return value is commit-bound"
check_has "$SRC_AP_PHASES" '^### Step 5\.1a — CI verdict gate' \
  "T3.2: auto-pilot owns a named gate for the returned verdict"
check_has "$SRC_AP_PHASES" 'ci_verdict = trusted \| stale \| absent' \
  "T3.3: the gate sets exactly one three-state variable"
check_has "$SRC_AP_PHASES" 'gh pr view \{pr_number\} --json headRefOid' \
  "T3.4: the gate re-verifies with one cheap read, not a second poll"

CI_GATE_BLOCK="$(awk '/^### Step 5\.1a — CI verdict gate/,/^### Step 5\.1b — Dependency Gate/' "$SRC_AP_PHASES")"
check_block_has "$CI_GATE_BLOCK" 'subagent return value, not a PR-body marker' \
  "T3.5: the gate distinguishes an in-process return value from a PR-body marker"
check_block_has "$CI_GATE_BLOCK" '.failed@<sha40>. is never .trusted.' \
  "T3.6: a failing verdict is never trusted — it can only leave the PR open"
check_block_has "$CI_GATE_BLOCK" 'review\.adaptive_depth: false. disables this gate' \
  "T3.7: the existing adaptive switch is the off-switch — no new config key"
# #255's literal must survive: CI is never skipped by the QA handoff marker.
check_has "$SRC_AP_PHASES" 'never skipped by the marker' \
  "T3.8: auto-pilot still states CI is never skipped by the QA handoff marker"
check_has "$SRC_PR_CI" '^### Binding the verdict to a commit' \
  "T3.9: pr-review documents how the verdict is bound to a commit"
check_has "$SRC_PR_SKILL" 'ci_sha' \
  "T3.10: pr-review's Step 5 records the head SHA it waited on"
# phases.md and examples.md narrate the same wait; updated apart, they drift and
# the narration claims a poll the pipeline no longer performs.
check_has "$SRC_AP_EXAMPLES" 'Step 5\.1a — CI verdict gate' \
  "T3.11: the examples narration is updated in lockstep with phases.md"

# ───────────────────────────────────────────────────────────
# T4 (AC4): last-green test state has ONE home and TWO consumers,
# and it layers UNDER resolve.auto_test. Over it, a `false` config
# would be silently overridden by a recorded run.
# ───────────────────────────────────────────────────────────
check_has "$SRC_RES_STEPS" '^### Last-green test state' \
  "T4.1: pipeline-steps.md owns the last-green test state section"
check_has "$SRC_RES_STEPS" 'Single home of .tests_state. and of both its consumers' \
  "T4.2: that section declares itself the single home"
STATE_HITS="$(grep -rlE 'tests_state = ' "$REPO_ROOT/src" 2>/dev/null || true)"
STATE_COUNT="$(printf '%s\n' "$STATE_HITS" | grep -c . || true)"
if [ "$STATE_COUNT" = "1" ] && [ "$STATE_HITS" = "$SRC_RES_STEPS" ]; then
  pass "T4.3: tests_state is defined in exactly one src/ file"
else
  fail "T4.3: tests_state must be defined in exactly one src/ file — found $STATE_COUNT"
  printf '      %s\n' $STATE_HITS
fi

STATE_BLOCK="$(awk '/^### Last-green test state/,/^### Loop controls/' "$SRC_RES_STEPS")"
check_block_has "$STATE_BLOCK" 'Step 4, cycle N\+1' \
  "T4.4: consumer 1 is Step 4's next cycle after a no-commit fixer"
check_block_has "$STATE_BLOCK" 'Step 5, \*Verify all tests pass\*' \
  "T4.5: consumer 2 is Step 5's final verification run"
check_block_has "$STATE_BLOCK" 'under .resolve\.auto_test.\*\*, never over it' \
  "T4.6: both consumers layer under resolve.auto_test, never over it"
check_block_has "$STATE_BLOCK" 'Fail-safe is .run.' \
  "T4.7: nothing recorded, or any doubt, runs the suite"
check_block_has "$STATE_BLOCK" 'new config key is introduced' \
  "T4.8: the existing adaptive switch is the off-switch — no new config key"
check_has "$SRC_RES_SKILL" 'Under .auto_test., not over it' \
  "T4.9: the SKILL's Step 5 clause states the layering, first read wins"
# #255 captures tests_sha where the suite runs; promoting it to run state must
# not move or soften that capture.
QA_BLOCK="$(awk '/^## Step 4 — QA/,/^### Step 4 — UI\/UX review/' "$SRC_RES_STEPS")"
check_block_has "$QA_BLOCK" 'tests_sha. = .git rev-parse HEAD' \
  "T4.10: the capture command #255 pinned is unchanged"

# ───────────────────────────────────────────────────────────
# T5 (boundary, security-critical): every injection site marks
# its payload untrusted and states what it may not gate, and the
# normative exclusion list exists exactly ONCE. Two copies drift,
# and the looser copy is the one an agent will read.
# ───────────────────────────────────────────────────────────
check_has "$SRC_CONV" '^## Caller-supplied context payloads' \
  "T5.1: the shared conventions own the caller-payload rules"
check_has "$SRC_CONV" 'may gate duplicated work, never a safety gate' \
  "T5.2: the rule is stated in its home"
for excl in 'Repo Sync' 'gi-secscan' 'already-resolved check' 'Step 5 CI wait' '#36 hard-blocks'; do
  check_has "$SRC_CONV" "$excl" \
    "T5.3: the exclusion list names $excl"
done
# The list itself must not be restated anywhere else.
LIST_HITS="$(grep -rlE 'either .gi-secscan. pass' "$REPO_ROOT/src" "$REPO_ROOT/docs" 2>/dev/null || true)"
LIST_COUNT="$(printf '%s\n' "$LIST_HITS" | grep -c . || true)"
if [ "$LIST_COUNT" = "1" ] && [ "$LIST_HITS" = "$SRC_CONV" ]; then
  pass "T5.4: the exclusion list has exactly one home in src/ + docs/"
else
  fail "T5.4: the exclusion list must have exactly one home — found $LIST_COUNT"
  printf '      %s\n' $LIST_HITS
fi

UNTRUSTED='untrusted local data with exactly the status of issue text'
SAFETY='may gate duplicated work, never a safety gate'
RESOLVER_PROMPT="$(awk '/^## Resolver Subagent/,/^## PR Reviewer Subagent/' "$SRC_AP_PROMPTS")"
REVIEWER_PROMPT="$(awk '/^## PR Reviewer Subagent/,/^## Analyzer Subagent/' "$SRC_AP_PROMPTS")"
BATCH_PROMPT="$(awk '/^## Batch Resolver Subagent/,/^## Template Variables/' "$SRC_AP_PROMPTS")"
CAPTURE_BLOCK="$(awk '/^### Step 1\.2b — Capture the caller payload/,/^### Step 1\.3/' "$SRC_AP_PHASES")"
TRIAGE_BLOCK="$(awk '/^### .triage_context. \(when supplied\)/,/^### What the researcher does/' "$SRC_RES_STEPS")"

check_block_has "$RESOLVER_PROMPT" "$UNTRUSTED" "T5.5: the resolver prompt marks its payloads untrusted"
check_block_has "$REVIEWER_PROMPT" "$UNTRUSTED" "T5.6: the reviewer prompt marks its payload untrusted"
check_block_has "$BATCH_PROMPT"    "$UNTRUSTED" "T5.7: the batch prompt marks its payloads untrusted"
check_block_has "$CAPTURE_BLOCK"   "$UNTRUSTED" "T5.8: the capture step marks both blocks untrusted"
check_block_has "$PAYLOAD_BLOCK"   "$UNTRUSTED" "T5.9: the resolver's Step 0i marks the payload untrusted"
check_block_has "$TRIAGE_BLOCK"    "$UNTRUSTED" "T5.10: the triage_context section marks the row untrusted"

check_block_has "$RESOLVER_PROMPT" "$SAFETY" "T5.11: the resolver prompt carries the never-a-safety-gate rule"
check_block_has "$REVIEWER_PROMPT" "$SAFETY" "T5.12: the reviewer prompt carries the never-a-safety-gate rule"
check_block_has "$BATCH_PROMPT"    "$SAFETY" "T5.13: the batch prompt carries the never-a-safety-gate rule"
check_block_has "$CAPTURE_BLOCK"   "$SAFETY" "T5.14: the capture step carries the never-a-safety-gate rule"
check_block_has "$PAYLOAD_BLOCK"   "$SAFETY" "T5.15: the resolver's Step 0i carries the never-a-safety-gate rule"
check_block_has "$TRIAGE_BLOCK"    "$SAFETY" "T5.16: the triage_context section carries the never-a-safety-gate rule"
check_has "$SRC_AP_SKILL"          "$SAFETY" \
  "T5.17: auto-pilot's SKILL states the rule where an agent reads it first"

# A new freshness check must use SHA equality, never ancestry: #254's T1.1 pins
# `merge-base --is-ancestor` to exactly one src/ file, and a second predicate
# both fails that test and creates a looser second definition of "current".
check_lacks "$SRC_AP_PHASES" 'merge-base --is-ancestor' \
  "T5.18: the CI verdict gate uses SHA equality, not a second ancestry predicate"

# ───────────────────────────────────────────────────────────
# T6 (fail-safe): each gate names its degrade path. A gate that
# cannot say what it does on doubt has no degrade path at all.
# ───────────────────────────────────────────────────────────
check_block_has "$PAYLOAD_BLOCK" 'Any doubt is .absent.' \
  "T6.1: the payload gate degrades to today's 0a fetch on any doubt"
check_block_has "$PAYLOAD_BLOCK" "today's 0a fetch,\s*byte-for-byte" \
  "T6.2: that degrade is today's pipeline byte-for-byte"
check_block_has "$TRIAGE_BLOCK" '^Degrade:' \
  "T6.3: the triage_context key names its degrade path"
check_block_has "$CI_GATE_BLOCK" 'Fail-safe: any doubt is .absent.' \
  "T6.4: the CI verdict gate degrades to today's full wait on any doubt"
check_block_has "$CAPTURE_BLOCK" 'omit that block entirely and spawn without it' \
  "T6.5: an uncapturable payload is omitted, never spawned half-formed"

# ───────────────────────────────────────────────────────────
# T7 (install surface): the built tree carries the same contract.
# A rule that ships only in src/ is installed for nobody.
# ───────────────────────────────────────────────────────────
check_has "$BUILT_AP_PHASES" 'gh issue list --state open --json [a-zA-Z,]*state,updatedAt' \
  "T7.1: built phases.md ships the widened list call"
check_has "$BUILT_AP_PHASES" '^### Step 5\.1a — CI verdict gate' \
  "T7.2: built phases.md ships the CI verdict gate"
check_has "$BUILT_AP_PHASES" 'never skipped by the marker' \
  "T7.3: built phases.md still ships #255's marker rule"
check_has "$BUILT_AP_PROMPTS" '\{issue_payload\}' \
  "T7.4: built subagent-prompts.md ships the payload variable"
check_has "$BUILT_AP_PROMPTS" 'ci_status: "passed@<sha40>"' \
  "T7.5: built subagent-prompts.md ships the commit-bound ci_status"
check_has "$BUILT_RES_STEPS" '^## Step 0i — Caller payload gate' \
  "T7.6: built pipeline-steps.md ships the payload gate"
check_has "$BUILT_RES_STEPS" '^### Last-green test state' \
  "T7.7: built pipeline-steps.md ships the last-green test state home"
check_has "$BUILT_RES_STEPS" '"triage_context": null' \
  "T7.8: built pipeline-steps.md ships the triage_context payload key"
check_has "$BUILT_RESEARCHER" '^### .prior_analysis. and .triage_context. \(when supplied\)' \
  "T7.9: the bundled researcher prompt ships the single extended contract block"
check_has "$BUILT_RESEARCHER" 'no commit pin at all' \
  "T7.10: the bundled researcher prompt ships the weaker trust profile"
check_has "$BUILT_CONV" '^## Caller-supplied context payloads' \
  "T7.11: the bundled conventions doc ships the caller-payload rules"
check_has "$BUILT_CONV" "$SAFETY" \
  "T7.12: the bundled conventions doc ships the never-a-safety-gate rule"
check_has "$BUILT_RES_SKILL" 'issue_payload = supplied \| partial \| absent' \
  "T7.13: built resolver SKILL.md ships the payload states"
check_has "$BUILT_PR_CI" '^### Binding the verdict to a commit' \
  "T7.14: built pr-review mechanics ship the verdict binding"
check_has "$BUILT_AP_EXAMPLES" 'Step 5\.1a — CI verdict gate' \
  "T7.15: built examples.md ships the updated narration"

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
