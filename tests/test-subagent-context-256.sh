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

check_block_lacks() {
  local block="$1"
  local pattern="$2"
  local label="$3"
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

echo "◆ Subagent Context Passing Contract Tests (issue #256)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

SRC_CONV="$REPO_ROOT/docs/shared-agent-conventions.md"
SRC_RESEARCHER="$REPO_ROOT/src/shared/agents/codebase-researcher.md"
SRC_AP_SKILL="$REPO_ROOT/src/skills/auto-pilot/SKILL.source.md"
. "$(cd "$(dirname "$0")" && pwd)/lib/spec.bash"  # spec_concat — split reference specs read as one file (#323)
SRC_AP_PHASES="$(spec_concat "$REPO_ROOT/src/skills/auto-pilot/references/phases.md")"
SRC_AP_PROMPTS="$REPO_ROOT/src/skills/auto-pilot/references/subagent-prompts.md"
SRC_AP_EXAMPLES="$REPO_ROOT/src/skills/auto-pilot/references/examples.md"
SRC_RES_SKILL="$REPO_ROOT/src/skills/issue-resolver/SKILL.source.md"
SRC_RES_STEPS="$(spec_concat "$REPO_ROOT/src/skills/issue-resolver/references/pipeline-steps.md")"
SRC_PR_SKILL="$REPO_ROOT/src/skills/issue-pr-review/SKILL.source.md"
SRC_PR_CI="$REPO_ROOT/src/skills/issue-pr-review/references/prepass-tests-ci-mechanics.md"

BUILT_CONV="$REPO_ROOT/skills/auto-pilot/references/docs/shared-agent-conventions.md"
BUILT_RESEARCHER="$REPO_ROOT/skills/issue-resolver/references/agents/codebase-researcher.md"
BUILT_AP_SKILL="$REPO_ROOT/skills/auto-pilot/SKILL.md"
BUILT_AP_PHASES="$(spec_concat "$REPO_ROOT/skills/auto-pilot/references/phases.md")"
BUILT_AP_PROMPTS="$REPO_ROOT/skills/auto-pilot/references/subagent-prompts.md"
BUILT_AP_EXAMPLES="$REPO_ROOT/skills/auto-pilot/references/examples.md"
BUILT_RES_SKILL="$REPO_ROOT/skills/issue-resolver/SKILL.md"
BUILT_RES_STEPS="$(spec_concat "$REPO_ROOT/skills/issue-resolver/references/pipeline-steps.md")"
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
anchor_present "$SRC_AP_PHASES" ap-step12b-capture \
  "T1.2: auto-pilot has a named step that captures the payload"
anchor_check "$SRC_AP_PROMPTS" ap-resolver-spawn '\{issue_payload\}' \
  "T1.3: the spawn prompts substitute an {issue_payload} variable"
anchor_check "$SRC_AP_PROMPTS" ap-template-vars '\| .\{issue_payload\}. \|' \
  "T1.4: {issue_payload} is declared in the Template Variables table"
anchor_present "$SRC_RES_STEPS" rs-step0i-gate \
  "T1.5: the resolver owns a named gate for the caller payload"
anchor_check "$SRC_RES_STEPS" rs-step0i-ordering 'issue_payload = supplied \| partial \| absent' \
  "T1.6: the gate sets exactly one three-state variable"
anchor_present "$SRC_RES_STEPS" rs-step0i-scope \
  "T1.7: the gate scopes the substitution to 0a's read"

PAYLOAD_BLOCK="$(anchor_span "$SRC_RES_STEPS" rs-step0i-gate rs-step1-research || true)"
check_block_has "$PAYLOAD_BLOCK" '0d still rewrites the body' \
  "T1.8: 0d still rewrites the body and still invalidates the cache"
check_block_has "$PAYLOAD_BLOCK" 'updatedAt. is \*\*required and load-bearing\*\*' \
  "T1.9: updatedAt is required, and the concurrency/0h reason is stated"
check_block_has "$PAYLOAD_BLOCK" 'Step 0h' \
  "T1.10: the gate names the sibling gate that consumes updatedAt"
anchor_check "$SRC_RES_SKILL" rs-0a-payload-concurrency 'issue_payload = supplied \| partial \| absent' \
  "T1.11: the SKILL pointer carries the three states, first read wins"
# 0a ends "if not found: stop; if closed: stop". Both are freshness judgements,
# and a payload's `state` is only as fresh as the caller's list — an issue closed
# externally between that list and this spawn still reads `open`, and 0b/0c do
# not catch it, so the resolve would open a PR for a closed issue.
check_block_has "$PAYLOAD_BLOCK" '0a.s own two stops are never decided from the payload' \
  "T1.12: the closed / not-found stops are never decided from the payload"
check_block_has "$PAYLOAD_BLOCK" 'gh issue view N --json state' \
  "T1.13: the gate names the one live read that keeps those stops at full strength"
check_has "$SRC_CONV" 'Step 0a closed / not-found stops' \
  "T1.14: the exclusion list's home names 0a's two stops"

# The payload is Phase 1's list record, which does NOT carry `comments` — while
# 0a's own fetch does, and Step 1 hands `comments` to the researcher, whose
# Phase 1 parses them for error text and file paths. And a payload's `updatedAt`
# has exactly the staleness window the gate already refuses to trust for `state`:
# an issue edited between the caller's list and this spawn would read as unedited
# and #254's Step 0h would call a superseded analysis `fresh`. One widened live
# read covers both at no extra call.
check_block_has "$PAYLOAD_BLOCK" 'gh issue view N --json state,comments,updatedAt' \
  "T1.15: the live re-verify covers state, comments AND updatedAt in one call"
check_block_has "$PAYLOAD_BLOCK" '0h condition 5.s live pre-normalization value' \
  "T1.16: Step 0h's condition 5 receives the live updatedAt after the match gate"
check_block_has "$PAYLOAD_BLOCK" 'except .comments.' \
  "T1.17: the supplied row states the payload carries 0a's fields except comments"
anchor_check "$SRC_RES_SKILL" rs-0a-payload-concurrency 'gh issue view N --json state,comments,updatedAt' \
  "T1.18: the SKILL clause names the same widened live read, first read wins"
# The batch spawn hands over one record per batched issue, which can never parse
# as the single object the `supplied` row describes. Without a per-issue reading
# rule the gate is unreachable for every batch, and the batch prompt's claim to
# use the block contradicts it.
check_block_has "$PAYLOAD_BLOCK" 'Batched spawns carry one record per issue' \
  "T1.19: the gate says how a multi-record batch block is read — per issue"

# ───────────────────────────────────────────────────────────
# T2 (AC2): triage_context is a sibling payload key with a
# WEAKER guarantee than prior_analysis, and the difference is
# stated in ONE extended contract block — never a second block
# repeating #254's words, which would drift from them.
# ───────────────────────────────────────────────────────────
anchor_check "$SRC_RES_STEPS" rs-step1-delegation-payload '"triage_context": null' \
  "T2.1: the Step 1 delegation payload carries a triage_context key"
anchor_present "$SRC_RES_STEPS" rs-triage-context \
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
anchor_check "$SRC_RES_STEPS" rs-triage-context 'only \*\*reorder\*\* a scan' \
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
anchor_check "$SRC_AP_PROMPTS" ap-reviewer-spawn 'ci_status: "passed@<sha40>", "failed@<sha40>", or "no_ci"' \
  "T3.1: the reviewer's ci_status return value is commit-bound"
anchor_present "$SRC_AP_PHASES" ap-ci-verdict-gate \
  "T3.2: auto-pilot owns a named gate for the returned verdict"
anchor_check "$SRC_AP_PHASES" ap-ci-verdict-gate 'ci_verdict = trusted \| stale \| absent' \
  "T3.3: the gate sets exactly one three-state variable"
# One widened --json read serves both the pre-merge checks and the gate. A
# separate `gh pr view --json headRefOid` three lines after Step 5.1's own read
# is two calls where the gate's selling point is one.
anchor_check "$SRC_AP_PHASES" ap-premerge-checks 'gh pr view \{pr_number\} --json mergeable,reviewDecision,statusCheckRollup,headRefOid' \
  "T3.4: one widened --json read serves the pre-merge checks and the gate"
GATE_EXTRA_READS="$(grep -cE '^gh pr view \{pr_number\} --json headRefOid$' "$SRC_AP_PHASES" || true)"
if [ "$GATE_EXTRA_READS" = "0" ]; then
  pass "T3.4b: the gate issues no second gh pr view of its own"
else
  fail "T3.4b: the gate still issues a standalone headRefOid read ($GATE_EXTRA_READS)"
fi

CI_GATE_BLOCK="$(anchor_span "$SRC_AP_PHASES" ap-ci-verdict-gate ap-dependency-gate || true)"
check_block_has "$CI_GATE_BLOCK" 'subagent return value, not a PR-body marker' \
  "T3.5: the gate distinguishes an in-process return value from a PR-body marker"
check_block_has "$CI_GATE_BLOCK" '.failed@<sha40>. is never .trusted.' \
  "T3.6: a failing verdict is never trusted — it can only leave the PR open"

# T3.6 above asserts the *paragraph*. Widening the state table's `trusted` row
# while leaving that paragraph in place would pass it, so pin the rows too: the
# `trusted` row must require live-head SHA equality and must not mention a
# failed verdict, and the `absent` row is where a failed verdict lands.
TRUSTED_ROW="$(printf '%s\n' "$CI_GATE_BLOCK" | grep -E '^\| .trusted. \|' || true)"
ABSENT_ROW="$(printf '%s\n' "$CI_GATE_BLOCK" | grep -E '^\| .absent. \|' || true)"
check_block_has  "$TRUSTED_ROW" 'passed@<sha40>.*equals the PR.s live head' \
  "T3.4c: the trusted row itself requires SHA equality against the live head"
check_block_lacks "$TRUSTED_ROW" 'failed@' \
  "T3.6b: the trusted row itself excludes a failed verdict"
check_block_has  "$ABSENT_ROW" 'failed@' \
  "T3.6c: the absent row is where a failed verdict lands"
check_block_has "$CI_GATE_BLOCK" 'Head-SHA equality does not cover a moved base' \
  "T3.6d: the gate scopes its claim to this head and names the moved-base gap"
# The corroboration must be POSITIVE. "no red check in the rollup" is satisfied by
# a rollup that shows NOTHING — empty, absent, or unreadable — and that is exactly
# the case the wait it replaces treats as not-clean (`gi-ci-wait.py`'s `none`
# counts as clean only when `none_confirmed` is true). A negative reading fails
# OPEN on a merge decision; every other gate in #256 fails toward more work.
check_block_has "$TRUSTED_ROW" 'statusCheckRollup. is non-empty with every check in it green' \
  "T3.6e: the trusted row itself requires a non-empty, all-green rollup"
check_block_has "$CI_GATE_BLOCK" 'empty, absent from the reply, or unreadable' \
  "T3.6f: an empty or unreadable rollup is absent, not trusted"
check_block_has "$CI_GATE_BLOCK" 'harder to forge than a PR-body marker' \
  "T3.6g: the provenance claim is bounded — harder to forge, not attacker-free"
check_block_has "$CI_GATE_BLOCK" 'review\.adaptive_depth: false. disables this gate' \
  "T3.7: the existing adaptive switch is the off-switch — no new config key"
# #255's literal must survive: CI is never skipped by the QA handoff marker.
anchor_check "$SRC_AP_PHASES" ap-ci-verdict-gate 'never skipped by the marker' \
  "T3.8: auto-pilot still states CI is never skipped by the QA handoff marker"
check_has "$SRC_PR_CI" '^### Binding the verdict to a commit' \
  "T3.9: pr-review documents how the verdict is bound to a commit"
check_has "$SRC_PR_SKILL" 'ci_sha' \
  "T3.10: pr-review's Step 5 records the head SHA it waited on"
# phases.md and examples.md narrate the same wait; updated apart, they drift and
# the narration claims a poll the pipeline no longer performs.
anchor_check "$SRC_AP_EXAMPLES" ap-ex-merge-requires-ci 'Step 5\.1a — CI verdict gate' \
  "T3.11: the examples narration is updated in lockstep with phases.md"

# A gate whose only input is never captured is inert. Step 2.3 enumerates the
# resolver fields it keeps; Step 3.2 must do the same for the reviewer, because
# `ci_status` is the one returned field nothing in that step prints — an
# un-enumerated field is a plausible drop, and dropping it forces `absent` on
# every iteration while the gate appears to be in force.
STEP32_BLOCK="$(anchor_span "$SRC_AP_PHASES" ap-step32-review-result ap-phase5-merge || true)"
check_block_has "$STEP32_BLOCK" 'Extract: .result., .review_cycles.' \
  "T3.12: Step 3.2 enumerates the reviewer fields it keeps, like Step 2.3"
check_block_has "$STEP32_BLOCK" '\*\*Retain .ci_status. verbatim\*\*' \
  "T3.13: Step 3.2 retains ci_status verbatim for the CI verdict gate"
check_block_has "$STEP32_BLOCK" 'Step 5\.1a — CI verdict gate' \
  "T3.14: Step 3.2 names the consumer that reads the field it retains"
# `mergeable` is MERGEABLE / CONFLICTING / UNKNOWN — a textual-conflict answer. It
# cannot see a clean base advance that changes a merge-result check on an
# unchanged head, so naming it as the check that catches a moved base would tell
# a reader the residual is covered when nothing covers it.
check_block_has "$CI_GATE_BLOCK" 'that moved \*\*into conflict\*\*, and nothing else' \
  "T3.15: the moved-base residual is scoped to what mergeable actually detects"
check_block_has "$CI_GATE_BLOCK" 'this gate neither widens nor closes it' \
  "T3.16: the section states the residual is open, not mitigated"

# SIBLING PARITY. The home above is not the only place this gate is narrated:
# examples.md walks the merge path and SKILL.md summarises it in the phase table.
# A correction that lands in the home and not in its siblings leaves the OLD,
# looser condition standing where an agent reads it — and here the looser form
# ("SHA equality alone") fails OPEN on a merge decision. Pin both siblings.
EXAMPLES_CI_BLOCK="$(anchor_span "$SRC_AP_EXAMPLES" ap-ex-merge-requires-ci ap-ex-interrupted-run || true)"
check_block_has "$EXAMPLES_CI_BLOCK" 'non-empty with every check in it green' \
  "T3.17: the examples narration carries the rollup conjunct, not SHA equality alone"
check_block_has "$EXAMPLES_CI_BLOCK" 'unreadable — is .absent., not .trusted.' \
  "T3.18: the examples narration says an empty rollup is absent, not trusted"
check_block_has "$EXAMPLES_CI_BLOCK" 'does not cover a clean base advance' \
  "T3.19: the examples narration no longer claims mergeable catches a moved base"
anchor_lacks "$SRC_AP_SKILL" ap-snapshot-budget 'ci_status. when the head has not moved' \
  "T3.20: the SKILL phase table states no half-condition for the CI verdict gate"
check_lacks "$SRC_AP_SKILL" 'ci_status. when the head has not moved' \
  "T3.20b: no half-condition for the CI verdict gate anywhere in the SKILL (file-wide)"
anchor_check "$SRC_AP_SKILL" ap-snapshot-budget 'gh issue view N --json state,comments,updatedAt' \
  "T3.21: the SKILL names the widened live re-verify, not the old single-field read"
anchor_lacks "$SRC_AP_SKILL" ap-snapshot-budget 'single-field .gh issue view' \
  "T3.22: no site still calls the Step 0i re-verify single-field"
check_lacks "$SRC_AP_SKILL" 'single-field .gh issue view' \
  "T3.22b: no site anywhere in the SKILL calls the re-verify single-field (file-wide)"

# ───────────────────────────────────────────────────────────
# T4 (AC4): last-green test state has ONE home and TWO consumers,
# and it layers UNDER resolve.auto_test. Over it, a `false` config
# would be silently overridden by a recorded run.
# ───────────────────────────────────────────────────────────
anchor_present "$SRC_RES_STEPS" rs-last-green-state \
  "T4.1: steps/step-4-qa.md owns the last-green test state section"
anchor_check "$SRC_RES_STEPS" rs-clean-tree 'Single home of .tests_state.' \
  "T4.2: that section declares itself the single home"
STATE_HITS="$(grep -rlE 'tests_state = ' "$REPO_ROOT/src" 2>/dev/null || true)"
STATE_COUNT="$(printf '%s\n' "$STATE_HITS" | grep -c . || true)"
if [ "$STATE_COUNT" = "1" ] && [ "$STATE_HITS" = "$REPO_ROOT/src/skills/issue-resolver/references/steps/step-4-qa.md" ]; then
  pass "T4.3: tests_state is defined in exactly one src/ file"
else
  fail "T4.3: tests_state must be defined in exactly one src/ file — found $STATE_COUNT"
  printf '      %s\n' $STATE_HITS
fi

QA_BLOCK="$(anchor_span "$SRC_RES_STEPS" rs-step4-qa rs-step4-ui-review || true)"
QA_BLOCK_CAPTURE="$(anchor_span "$SRC_RES_STEPS" rs-qa-run-tests rs-qa-evaluate || true)"
STATE_BLOCK="$(anchor_span "$SRC_RES_STEPS" rs-last-green-state rs-qa-loop-controls || true)"
check_block_has "$STATE_BLOCK" 'Step 4, cycle N\+1' \
  "T4.4: consumer 1 is Step 4's next cycle after a no-commit fixer"
# Consumer 1 sits exactly where the previous run is USUALLY red — cycle N+1 only
# exists when the reviewer or the suite failed. `tests_state` stores a count with
# no pass/fail flag, so a carried red state is not representable: an agent told
# to carry it into an "all tests pass" evaluation can exit QA on a red suite, and
# Step 5's Verify then skips on the same HEAD and ships the PR.
CONSUMER_1="$(printf '%s\n' "$STATE_BLOCK" | awk '/^1\. \*\*Step 4, cycle N\+1/,/^2\. \*\*Step 5/')"
check_block_has "$CONSUMER_1" 'recorded green run' \
  "T4.4b: consumer 1 is conditioned on a recorded GREEN run, like consumer 2"
check_block_has "$CONSUMER_1" 'a red run recorded nothing' \
  "T4.4c: consumer 1 states that a red run left nothing to carry"
# The capture rule is the single normative home of the green predicate — a
# consumer-side condition alone would leave a red state recorded and reachable.
check_block_has "$QA_BLOCK_CAPTURE" 'Record it only for a green run on a clean tree' \
  "T4.4d: the capture rule records nothing for a red or dirty run"
check_block_has "$QA_BLOCK_CAPTURE" 'no pass/fail flag' \
  "T4.4e: the capture rule says why a red state is not representable"
# HEAD equality does not imply an identical tree: fixer.md's real-secret block
# leaves HEAD unchanged and the working tree dirty.
check_block_has "$STATE_BLOCK" 'Both sides require a commit-relevant clean tree' \
  "T4.4f: capture and comparison both require a commit-relevant clean tree"
check_block_has "$STATE_BLOCK" 'git status --porcelain=v1 --untracked-files=all' \
  "T4.4g: the canonical clean-tree command binds capture AND comparison"
check_block_has "$STATE_BLOCK" 'Step 5, \*Verify all tests pass\*' \
  "T4.5: consumer 2 is Step 5's final verification run"
check_block_has "$STATE_BLOCK" 'under .resolve\.auto_test.\*\*, never over it' \
  "T4.6: both consumers layer under resolve.auto_test, never over it"
check_block_has "$STATE_BLOCK" 'Fail-safe is .run.' \
  "T4.7: nothing recorded, or any doubt, runs the suite"
check_block_has "$STATE_BLOCK" 'new config key is introduced' \
  "T4.8: the existing adaptive switch is the off-switch — no new config key"
anchor_check "$SRC_RES_SKILL" rs-deliver-clean-tree 'Under .auto_test., not over it' \
  "T4.9: the SKILL's Step 5 clause states the layering, first read wins"
# The single home above declares itself the only place either definition is
# stated, then SKILL.md restates the comparison inline — and SKILL.md is the
# always-loaded file while pipeline-steps.md is progressive disclosure, so the
# restatement is the copy an agent acts on. A restatement that gives only SHA
# equality IS the looser second definition the home exists to prevent.
anchor_check "$SRC_RES_SKILL" rs-deliver-clean-tree 'equals .git rev-parse HEAD. \*\*and .git status --porcelain=v1 --untracked-files=all. is empty\*\*' \
  "T4.9b: the SKILL's restatement carries the canonical clean-tree rule"
# #255 captures tests_sha where the suite runs; promoting it to run state must
# not move or soften that capture.
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
RESOLVER_PROMPT="$(anchor_span "$SRC_AP_PROMPTS" ap-resolver-spawn ap-reviewer-spawn || true)"
REVIEWER_PROMPT="$(anchor_span "$SRC_AP_PROMPTS" ap-reviewer-spawn ap-analyzer-spawn || true)"
BATCH_PROMPT="$(anchor_span "$SRC_AP_PROMPTS" ap-batch-spawn ap-template-vars || true)"
CAPTURE_BLOCK="$(anchor_span "$SRC_AP_PHASES" ap-step12b-capture ap-step13-plan || true)"
TRIAGE_BLOCK="$(anchor_span "$SRC_RES_STEPS" rs-triage-context rs-researcher-scope || true)"

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
anchor_check "$SRC_AP_SKILL" ap-snapshot-budget "$SAFETY" \
  "T5.17: auto-pilot's SKILL states the rule where an agent reads it first"

# The reviewer is spawned in Phase 3-4, STRICTLY AFTER Phase 2's resolver ran
# Step 0d (`gh issue edit` + normalize). Step 1.2b's payload is therefore the
# PRE-normalization body — and on an unnormalized backlog issue 0d is what
# CREATES the structured Acceptance Criteria section. Reading acceptance criteria
# from it evaluates the #36 hard-block against superseded evidence, which is
# "running a gate in full" on the wrong input.
# These three must pin instruction 6 ITSELF, not the reviewer block around it.
# Two mutations proved the wider form vacuous: `identifying fields only` also
# occurs in the block's own header (so rewriting the instruction to include the
# body still matched), and the old lacks-assertion pinned `acceptance criteria
# from it` — a string the text has never contained and no weakening would
# introduce. Extract instruction 6 and assert both clauses inside it, positively.
REVIEWER_INSTR6="$(printf '%s\n' "$REVIEWER_PROMPT" | awk '/^6\. When an issue_payload/,/^CRITICAL:/')"
check_block_has "$REVIEWER_INSTR6" 'identifying fields only' \
  "T5.19: instruction 6 itself scopes the reviewer payload to identifying fields"
check_block_has "$REVIEWER_INSTR6" 'never take acceptance criteria out of it' \
  "T5.20: instruction 6 itself forbids taking acceptance criteria from the payload"
check_block_has "$REVIEWER_INSTR6" 'always re-fetches the live issue body' \
  "T5.21: the #36 acceptance_criteria hard-block always re-fetches the live body"
# An instruction is only as good as the reader. The reviewer's block is TRIMMED
# to number/title/labels at the spawn site, so "identifying fields only" is a
# property of the data, not a rule an agent has to keep — and no untrusted issue
# body reaches that prompt to be misread in the first place.
check_block_has  "$REVIEWER_PROMPT" '\{issue_payload_ids\}' \
  "T5.19b: the reviewer prompt substitutes the trimmed identifying-fields block"
check_block_lacks "$REVIEWER_PROMPT" '\{issue_payload\}' \
  "T5.19c: the reviewer prompt never substitutes the full verbatim payload"
check_has "$SRC_AP_PHASES" '\*\*.\{issue_payload_ids\}.\*\* — the same record reduced to' \
  "T5.19d: Step 1.2b builds the trimmed reviewer block, separately from the full one"
check_has "$SRC_AP_PHASES" 'reviewer reads identifying fields from that payload only' \
  "T5.22: the spawn site states the same scope as the prompt it substitutes into"

# The batch prompt restates Step 0i for N issues at once. "use it and fetch
# nothing" is a BROADER licence than the gate grants: it reads as permission to
# skip the live state re-verify the gate makes mandatory under `supplied`, which
# is what keeps 0a's closed / not-found stops — named by exclusion in the home —
# at full strength. Restatement is downward only.
check_block_has "$BATCH_PROMPT" 'gh issue view <number> --json state,comments,updatedAt' \
  "T5.23: the batch prompt carries the same live-state re-verify as the resolver"
check_block_lacks "$BATCH_PROMPT" 'use it and fetch nothing' \
  "T5.24: the batch prompt no longer licenses fetching nothing at all"
check_block_has "$RESOLVER_PROMPT" 'gh issue view N --json state,comments,updatedAt' \
  "T5.25: the resolver prompt names the widened live read the gate mandates"

# T5.4 pins one string that no paraphrase would ever trip. The home now
# authorises SUBSET restatement, so also assert (a) that authorisation exists and
# (b) that no spawn prompt names a safety term the home does not state.
check_has "$SRC_CONV" 'may carry the subset that applies to their consumer, never a different rule' \
  "T5.4b: the home authorises subset restatement and forbids a divergent rule"
# The home permits FEWER items, never weaker words. The previous form of this
# check iterated the same five terms T5.3 has just asserted are present in the
# home, so its `! grep ... "$SRC_CONV"` half could never be true — it could not
# fail. What can fail, and is the real risk, is a prompt that names one of the
# home's safety items and then licenses skipping it.
# Match against a WHITESPACE-FLATTENED copy: these prompts are hard-wrapped, so a
# line-oriented grep misses any weakening whose verb and object land on different
# lines ("skip the already-resolved\ncheck") — the one guard protecting this
# boundary must not be defeatable by reflowing a paragraph.
WEAKEN='(skip|skips|skipped|bypass|bypasses|omit|omits|shorten|shortens|soften|softens|relax|relaxes) (the |both |either )?(Repo Sync|gi-secscan|already-resolved check|Step 5 CI wait|#36 hard-block)'
for pair in "resolver:$RESOLVER_PROMPT" "reviewer:$REVIEWER_PROMPT" "batch:$BATCH_PROMPT"; do
  tag="${pair%%:*}"
  blk="${pair#*:}"
  blk_flat="$(printf '%s' "$blk" | tr '\n' ' ' | tr -s ' ')"
  if [ -z "$blk" ]; then
    fail "T5.4c ($tag): block is empty — the extraction anchor no longer matches"
  elif printf '%s' "$blk_flat" | grep -qEi "$WEAKEN"; then
    fail "T5.4c ($tag): prompt licenses skipping a safety item the home excludes"
    printf '%s' "$blk_flat" | grep -oEi "$WEAKEN" | sed 's/^/      /'
  else
    pass "T5.4c ($tag): the prompt restates a subset of the home, never a weaker rule"
  fi
done

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
anchor_present "$BUILT_AP_PHASES" ap-ci-verdict-gate \
  "T7.2: built phases.md ships the CI verdict gate"
anchor_check "$BUILT_AP_PHASES" ap-ci-verdict-gate 'never skipped by the marker' \
  "T7.3: built phases.md still ships #255's marker rule"
anchor_check "$BUILT_AP_PROMPTS" ap-resolver-spawn '\{issue_payload\}' \
  "T7.4: built subagent-prompts.md ships the payload variable"
anchor_check "$BUILT_AP_PROMPTS" ap-reviewer-spawn 'ci_status: "passed@<sha40>"' \
  "T7.5: built subagent-prompts.md ships the commit-bound ci_status"
anchor_present "$BUILT_RES_STEPS" rs-step0i-gate \
  "T7.6: built pipeline-steps.md ships the payload gate"
anchor_present "$BUILT_RES_STEPS" rs-last-green-state \
  "T7.7: built pipeline-steps.md ships the last-green test state home"
anchor_check "$BUILT_RES_STEPS" rs-step1-delegation-payload '"triage_context": null' \
  "T7.8: built pipeline-steps.md ships the triage_context payload key"
check_has "$BUILT_RESEARCHER" '^### .prior_analysis. and .triage_context. \(when supplied\)' \
  "T7.9: the bundled researcher prompt ships the single extended contract block"
check_has "$BUILT_RESEARCHER" 'no commit pin at all' \
  "T7.10: the bundled researcher prompt ships the weaker trust profile"
check_has "$BUILT_CONV" '^## Caller-supplied context payloads' \
  "T7.11: the bundled conventions doc ships the caller-payload rules"
check_has "$BUILT_CONV" "$SAFETY" \
  "T7.12: the bundled conventions doc ships the never-a-safety-gate rule"
anchor_check "$BUILT_RES_SKILL" rs-0a-payload-concurrency 'issue_payload = supplied \| partial \| absent' \
  "T7.13: built resolver SKILL.md ships the payload states"
check_has "$BUILT_PR_CI" '^### Binding the verdict to a commit' \
  "T7.14: built pr-review mechanics ship the verdict binding"
anchor_check "$BUILT_AP_EXAMPLES" ap-ex-merge-requires-ci 'Step 5\.1a — CI verdict gate' \
  "T7.15: built examples.md ships the updated narration"

# The twins below are the groups that shipped only in src/ before: the
# untrusted-data boundary (T5.5-T5.7, the security-critical group), every
# fail-safe clause (T6.1-T6.5), the tests_state layering (T4.6-T4.8), and the
# reviewer payload scope. A boundary that ships only in src/ protects nobody.
B_RESOLVER_PROMPT="$(anchor_span "$BUILT_AP_PROMPTS" ap-resolver-spawn ap-reviewer-spawn || true)"
B_REVIEWER_PROMPT="$(anchor_span "$BUILT_AP_PROMPTS" ap-reviewer-spawn ap-analyzer-spawn || true)"
B_BATCH_PROMPT="$(anchor_span "$BUILT_AP_PROMPTS" ap-batch-spawn ap-template-vars || true)"
B_CAPTURE_BLOCK="$(anchor_span "$BUILT_AP_PHASES" ap-step12b-capture ap-step13-plan || true)"
B_PAYLOAD_BLOCK="$(anchor_span "$BUILT_RES_STEPS" rs-step0i-gate rs-step1-research || true)"
B_TRIAGE_BLOCK="$(anchor_span "$BUILT_RES_STEPS" rs-triage-context rs-researcher-scope || true)"
B_STATE_BLOCK="$(anchor_span "$BUILT_RES_STEPS" rs-last-green-state rs-qa-loop-controls || true)"
B_QA_CAPTURE="$(anchor_span "$BUILT_RES_STEPS" rs-qa-run-tests rs-qa-evaluate || true)"
B_CI_GATE_BLOCK="$(anchor_span "$BUILT_AP_PHASES" ap-ci-verdict-gate ap-dependency-gate || true)"

check_block_has "$B_RESOLVER_PROMPT" "$UNTRUSTED" "T7.16: built resolver prompt marks its payloads untrusted"
check_block_has "$B_REVIEWER_PROMPT" "$UNTRUSTED" "T7.17: built reviewer prompt marks its payload untrusted"
check_block_has "$B_BATCH_PROMPT"    "$UNTRUSTED" "T7.18: built batch prompt marks its payloads untrusted"
check_block_has "$B_CAPTURE_BLOCK"   "$UNTRUSTED" "T7.19: built capture step marks both blocks untrusted"
check_block_has "$B_PAYLOAD_BLOCK"   "$UNTRUSTED" "T7.20: built Step 0i marks the payload untrusted"
check_block_has "$B_TRIAGE_BLOCK"    "$UNTRUSTED" "T7.21: built triage_context section marks the row untrusted"
check_block_has "$B_RESOLVER_PROMPT" "$SAFETY"    "T7.22: built resolver prompt carries the never-a-safety-gate rule"
check_block_has "$B_REVIEWER_PROMPT" "$SAFETY"    "T7.23: built reviewer prompt carries the never-a-safety-gate rule"
check_block_has "$B_BATCH_PROMPT"    "$SAFETY"    "T7.24: built batch prompt carries the never-a-safety-gate rule"

check_block_has "$B_PAYLOAD_BLOCK" 'Any doubt is .absent.' \
  "T7.25: built payload gate degrades to today's 0a fetch on any doubt"
check_block_has "$B_PAYLOAD_BLOCK" '0a.s own two stops are never decided from the payload' \
  "T7.26: built payload gate keeps 0a's closed / not-found stops live"
check_block_has "$B_TRIAGE_BLOCK" '^Degrade:' \
  "T7.27: built triage_context key names its degrade path"
check_block_has "$B_CI_GATE_BLOCK" 'Fail-safe: any doubt is .absent.' \
  "T7.28: built CI verdict gate degrades to today's full wait on any doubt"
check_block_has "$B_CAPTURE_BLOCK" 'omit that block entirely and spawn without it' \
  "T7.29: built capture step omits an uncapturable payload"

check_block_has "$B_STATE_BLOCK" 'under .resolve\.auto_test.\*\*, never over it' \
  "T7.30: built last-green state layers under resolve.auto_test"
check_block_has "$B_STATE_BLOCK" 'Fail-safe is .run.' \
  "T7.31: built last-green state fail-safes to running the suite"
check_block_has "$B_STATE_BLOCK" 'new config key is introduced' \
  "T7.32: built last-green state introduces no new config key"
check_block_has "$B_STATE_BLOCK" 'Both sides require a commit-relevant clean tree' \
  "T7.33: built last-green state requires a commit-relevant clean tree"
check_block_has "$B_STATE_BLOCK" 'recorded green run' \
  "T7.34: built consumer 1 is conditioned on a recorded green run"
check_block_has "$B_QA_CAPTURE" 'Record it only for a green run on a clean tree' \
  "T7.35: built capture rule records nothing for a red or dirty run"

B_REVIEWER_INSTR6="$(printf '%s\n' "$B_REVIEWER_PROMPT" | awk '/^6\. When an issue_payload/,/^CRITICAL:/')"
check_block_has "$B_REVIEWER_INSTR6" 'identifying fields only' \
  "T7.36: built instruction 6 scopes the payload to identifying fields"
check_block_has "$B_REVIEWER_INSTR6" 'never take acceptance criteria out of it' \
  "T7.37: built instruction 6 forbids taking acceptance criteria from the payload"
check_block_has "$B_REVIEWER_INSTR6" 'always re-fetches the live issue body' \
  "T7.38: built reviewer prompt re-fetches the live body for the #36 hard-block"
check_block_has  "$B_REVIEWER_PROMPT" '\{issue_payload_ids\}' \
  "T7.36b: built reviewer prompt substitutes the trimmed identifying-fields block"
check_block_lacks "$B_REVIEWER_PROMPT" '\{issue_payload\}' \
  "T7.36c: built reviewer prompt never substitutes the full verbatim payload"
anchor_check "$BUILT_AP_PHASES" ap-premerge-checks 'gh pr view \{pr_number\} --json mergeable,reviewDecision,statusCheckRollup,headRefOid' \
  "T7.39: built phases.md ships the single widened --json read"
check_has "$BUILT_CONV" 'may carry the subset that applies to their consumer, never a different rule' \
  "T7.40: the bundled conventions doc ships the subset-restatement rule"

# Built-tree twins of the corrections above: the widened live read (comments +
# updatedAt), the per-issue batch reading rule, the clean-tree restatement in the
# always-loaded SKILL, and the positive rollup corroboration.
check_block_has "$B_PAYLOAD_BLOCK" 'gh issue view N --json state,comments,updatedAt' \
  "T7.41: built payload gate ships the widened live re-verify"
check_block_has "$B_PAYLOAD_BLOCK" '0h condition 5.s live pre-normalization value' \
  "T7.42: built payload gate feeds Step 0h's condition 5 the live updatedAt"
check_block_has "$B_PAYLOAD_BLOCK" 'Batched spawns carry one record per issue' \
  "T7.43: built payload gate ships the per-issue rule for batch blocks"
anchor_check "$BUILT_RES_SKILL" rs-deliver-clean-tree 'equals .git rev-parse HEAD. \*\*and .git status --porcelain=v1 --untracked-files=all. is empty\*\*' \
  "T7.44: built resolver SKILL.md ships the canonical clean-tree rule"
anchor_check "$BUILT_RES_SKILL" rs-0a-payload-concurrency 'gh issue view N --json state,comments,updatedAt' \
  "T7.45: built resolver SKILL.md ships the widened live re-verify"
check_block_has "$B_CI_GATE_BLOCK" 'statusCheckRollup. is non-empty with every check in it green' \
  "T7.46: built CI verdict gate requires a non-empty, all-green rollup"
check_block_has "$B_CI_GATE_BLOCK" 'empty, absent from the reply, or unreadable' \
  "T7.47: built CI verdict gate treats an empty or unreadable rollup as absent"
check_block_has "$B_CI_GATE_BLOCK" 'harder to forge than a PR-body marker' \
  "T7.48: built CI verdict gate bounds its provenance claim"
check_block_has "$B_BATCH_PROMPT" 'gh issue view <number> --json state,comments,updatedAt' \
  "T7.49: built batch prompt carries the live-state re-verify"
check_block_lacks "$B_BATCH_PROMPT" 'use it and fetch nothing' \
  "T7.50: built batch prompt no longer licenses fetching nothing at all"

B_STEP32_BLOCK="$(anchor_span "$BUILT_AP_PHASES" ap-step32-review-result ap-phase5-merge || true)"
check_block_has "$B_STEP32_BLOCK" '\*\*Retain .ci_status. verbatim\*\*' \
  "T7.51: built Step 3.2 retains ci_status verbatim — the gate's only input"
check_block_has "$B_STEP32_BLOCK" 'Step 5\.1a — CI verdict gate' \
  "T7.52: built Step 3.2 names the gate that consumes it"
check_block_has "$B_CI_GATE_BLOCK" 'that moved \*\*into conflict\*\*, and nothing else' \
  "T7.53: built CI verdict gate scopes the moved-base residual to mergeable's real answer"
check_block_has "$B_CI_GATE_BLOCK" 'this gate neither widens nor closes it' \
  "T7.54: built CI verdict gate states the residual is open, not mitigated"

B_EXAMPLES_CI_BLOCK="$(anchor_span "$BUILT_AP_EXAMPLES" ap-ex-merge-requires-ci ap-ex-interrupted-run || true)"
check_block_has "$B_EXAMPLES_CI_BLOCK" 'non-empty with every check in it green' \
  "T7.55: built examples narration carries the rollup conjunct"
check_block_has "$B_EXAMPLES_CI_BLOCK" 'does not cover a clean base advance' \
  "T7.56: built examples narration no longer claims mergeable catches a moved base"
anchor_check "$BUILT_AP_SKILL" ap-snapshot-budget 'gh issue view N --json state,comments,updatedAt' \
  "T7.57: built auto-pilot SKILL.md names the widened live re-verify"
anchor_lacks "$BUILT_AP_SKILL" ap-snapshot-budget 'ci_status. when the head has not moved' \
  "T7.58: built auto-pilot SKILL.md states no half-condition for the CI verdict gate"
check_lacks "$BUILT_AP_SKILL" 'ci_status. when the head has not moved' \
  "T7.58b: built auto-pilot SKILL.md has no half-condition anywhere (file-wide)"

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
