#!/usr/bin/env bash
# test-analysis-reuse-254.sh — Analysis reuse gate contract (issue #254)
#
# Acceptance criteria:
#   AC1: an analyze-then-resolve sequence on an unchanged tree performs codebase
#        research once — Step 1 runs a seeded verify-first pass instead of a
#        second full scan, and Step 2 skips the synthesizer entirely.
#   AC2: freshness is a checkable criterion (commit ancestry + issue update
#        time), stated once as literal commands — not a vibe, and not a word
#        used undefined.
#   AC3: stale or missing analysis produces exactly today's full pipeline, and
#        every doubt fails safe to stale.
#   AC4: /auto-pilot explicit-list mode benefits with no change to its own flow.
#
# Asserts on the authored src/ sources AND on the built skills/ tree, because a
# contract that ships only in src/ is not installed for anyone.
#
# Usage: bash tests/test-analysis-reuse-254.sh
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
  if printf '%s' "$block" | grep -qE "$pattern"; then
    fail "$label"
    echo "      forbidden pattern still present: $pattern"
  else
    pass "$label"
  fi
}

echo "◆ Analysis Reuse Gate Contract Tests (issue #254)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

SRC_SKILL="$REPO_ROOT/src/skills/issue-resolver/SKILL.source.md"
SRC_STEPS="$REPO_ROOT/src/skills/issue-resolver/references/pipeline-steps.md"
SRC_TEMPLATES="$REPO_ROOT/src/skills/issue-resolver/references/report-templates.md"
SRC_RESEARCHER="$REPO_ROOT/src/shared/agents/codebase-researcher.md"
SRC_METHODOLOGY="$REPO_ROOT/docs/idd-methodology.md"

BUILT_SKILL="$REPO_ROOT/skills/issue-resolver/SKILL.md"
BUILT_STEPS="$REPO_ROOT/skills/issue-resolver/references/pipeline-steps.md"
BUILT_TEMPLATES="$REPO_ROOT/skills/issue-resolver/references/report-templates.md"
BUILT_RESEARCHER="$REPO_ROOT/skills/issue-resolver/references/agents/codebase-researcher.md"

for file in "$SRC_SKILL" "$SRC_STEPS" "$SRC_TEMPLATES" "$SRC_RESEARCHER" \
            "$SRC_METHODOLOGY" "$BUILT_SKILL" "$BUILT_STEPS" "$BUILT_TEMPLATES" \
            "$BUILT_RESEARCHER"; do
  if [ -f "$file" ]; then
    pass "exists: ${file#$REPO_ROOT/}"
  else
    fail "missing: ${file#$REPO_ROOT/}"
  fi
done

# ───────────────────────────────────────────────────────────
# T1 (AC2): the predicate has exactly one home in src/.
# Two definitions drift apart; the stricter one silently wins.
# ───────────────────────────────────────────────────────────
ANCESTOR_HITS="$(grep -rlE 'merge-base --is-ancestor' "$REPO_ROOT/src" 2>/dev/null || true)"
ANCESTOR_COUNT="$(printf '%s\n' "$ANCESTOR_HITS" | grep -c . || true)"
if [ "$ANCESTOR_COUNT" = "1" ] && [ "$ANCESTOR_HITS" = "$SRC_STEPS" ]; then
  pass "T1.1: the ancestry test lives in exactly one src/ file (resolver pipeline-steps.md)"
else
  fail "T1.1: the ancestry test must live in exactly one src/ file — found $ANCESTOR_COUNT"
  printf '      %s\n' $ANCESTOR_HITS
fi

check_has "$SRC_STEPS" '^## Step 0h — Analysis reuse gate' \
  "T1.2: pipeline-steps.md defines the Step 0h section"
check_has "$SRC_STEPS" '[Ss]ingle home of the freshness predicate|single home' \
  "T1.3: Step 0h declares itself the single home of the definition"
check_has "$SRC_SKILL" '### 0h — Analysis reuse gate' \
  "T1.4: SKILL source adds the 0h sub-step"
check_has "$SRC_SKILL" 'Step 0h — Analysis reuse gate' \
  "T1.5: SKILL source points 0h at the pipeline-steps home"

# ───────────────────────────────────────────────────────────
# T2 (AC2): all five conditions are stated as checkable commands,
# and they are evaluated against this run's synced base, not HEAD.
# ───────────────────────────────────────────────────────────
check_has "$SRC_STEPS" 'analysis-\$\{N\}\.json|analysis-<N>\.json' \
  "T2.1: condition 1 names the analysis artifact"
check_has "$SRC_STEPS" 'json\.load' \
  "T2.2: condition 1 requires the file to parse as JSON"
check_has "$SRC_STEPS" '\-eq 40' \
  "T2.3: condition 2 requires a full 40-character commit_sha"
check_has "$SRC_STEPS" '\[!0-9a-f\]' \
  "T2.3b: condition 2 requires the SHA to be hex"
check_has "$SRC_STEPS" 'never commit_sha_short|commit_sha_short. is display-only' \
  "T2.3c: the display-only short SHA is explicitly rejected"
check_has "$SRC_STEPS" 'git_state.*commit_sha|commit_sha.*git_state' \
  "T2.4: condition 2 reads git_state.commit_sha"
check_has "$SRC_STEPS" 'git cat-file -e' \
  "T2.5: condition 2 verifies the repo actually knows the commit"
check_has "$SRC_STEPS" 'git merge-base --is-ancestor' \
  "T2.6: condition 3 is a commit-ancestry test"
check_has "$SRC_STEPS" 'git diff --name-only' \
  "T2.7: condition 4 diffs the changed paths since the analysis"
check_has "$SRC_STEPS" 'affected_files' \
  "T2.8: condition 4 intersects those paths with the analysis affected_files"
check_has "$SRC_STEPS" 'updatedAt' \
  "T2.9: condition 5 compares the issue updatedAt"
check_has "$SRC_STEPS" 'analysis `timestamp`|analysis .timestamp' \
  "T2.10: condition 5 compares updatedAt against the analysis timestamp"
check_has "$SRC_STEPS" "base_ref=\"origin/\\\$\{base\}\"" \
  "T2.11: the predicate evaluates against this run's synced base ref"
check_has "$SRC_STEPS" '[Nn]ever a bare .?HEAD' \
  "T2.12: a bare HEAD is explicitly forbidden as the base (parallel worktrees)"

# ───────────────────────────────────────────────────────────
# T3 (AC3): fail-safe default and the three-state variable.
# ───────────────────────────────────────────────────────────
check_has "$SRC_STEPS" 'analysis_reuse = fresh \| stale \| absent' \
  "T3.1: the gate declares one three-state variable"
for state in fresh stale absent; do
  check_has "$SRC_STEPS" "\`$state\`" "T3.2: state \`$state\` is documented"
done
check_has "$SRC_STEPS" '[Ff]ail-safe' \
  "T3.3: the fail-safe rule is named as such"
check_has "$SRC_STEPS" 'any (condition that )?cannot be evaluated|any doubt' \
  "T3.4: any doubt resolves to stale"
check_has "$SRC_STEPS" "stale.*today's full pipeline, unchanged" \
  "T3.5: stale/absent run today's full pipeline unchanged"
check_has "$SRC_STEPS" 'resolve\.adaptive_effort. is .false|resolve\.adaptive_effort` is `false' \
  "T3.6: resolve.adaptive_effort=false disables reuse (no new config key)"
check_has "$SRC_STEPS" '[Nn]o new config key is introduced' \
  "T3.7: the gate states it introduces no new config key"
check_has "$SRC_SKILL" 'fail-safe|Any doubt' \
  "T3.8: the SKILL pointer carries the fail-safe default"

# ───────────────────────────────────────────────────────────
# T4 (AC2): the 0d normalization trap is defused — updatedAt is
# captured in 0a, before 0d rewrites the body, in BOTH calls.
# ───────────────────────────────────────────────────────────
GI_ISSUE_LINE="$(grep -nE 'gi-issue\.py \{N\} --fields' "$SRC_SKILL" | head -1 || true)"
if printf '%s' "$GI_ISSUE_LINE" | grep -q 'updatedAt'; then
  pass "T4.1: 0a's gi-issue.py --fields list includes updatedAt"
else
  fail "T4.1: 0a's gi-issue.py --fields list is missing updatedAt"
fi
if printf '%s' "$GI_ISSUE_LINE" | grep -qE 'gh issue view \{N\} --json [a-zA-Z,]*updatedAt'; then
  pass "T4.2: the gh issue view degrade twin also requests updatedAt"
else
  fail "T4.2: the gh issue view degrade twin does not request updatedAt"
fi
check_has "$SRC_SKILL" 'Capture .updatedAt. here|pre-normalization' \
  "T4.3: 0a states the value is captured pre-normalization"
check_has "$SRC_STEPS" 'pre-normalization' \
  "T4.4: Step 0h evaluates condition 5 against the pre-normalization value"
check_has "$SRC_STEPS" '0d.*bumps `updatedAt`|bumps `updatedAt`' \
  "T4.5: the 0d-bumps-updatedAt trap is documented, not just avoided"

# ───────────────────────────────────────────────────────────
# T5 (AC1/safety): the seeded research pass never skips the
# already-resolved verification, and never trusts stale hints.
# ───────────────────────────────────────────────────────────
check_has "$SRC_STEPS" '^### .reuse. — seeded, verify-first research' \
  "T5.1: Step 1 has a reuse sub-section"
check_has "$SRC_STEPS" 'prior_analysis' \
  "T5.2: the Step 1 delegation payload carries prior_analysis"
REUSE_BLOCK="$(awk '/^### .reuse. — seeded, verify-first research/,/^### Inline fallback/' "$SRC_STEPS")"
if printf '%s' "$REUSE_BLOCK" | grep -qE '\*\*Keep\*\* the \*Verify not already resolved\* phase \*\*in full\*\*'; then
  pass "T5.3: the reuse pass keeps the already-resolved check in full"
else
  fail "T5.3: the reuse pass must keep the already-resolved safety check in full"
fi
if printf '%s' "$REUSE_BLOCK" | grep -qE 'verify-first hints to confirm or refute, never assertions to trust'; then
  pass "T5.4: persisted hints are verify-first, never assertions to trust"
else
  fail "T5.4: the reuse pass must treat persisted hints as verify-first hints"
fi
if printf '%s' "$REUSE_BLOCK" | grep -qE '\*\*Skip\*\* the broad dependency trace'; then
  pass "T5.5: the reuse pass skips the broad dependency trace / history / external research"
else
  fail "T5.5: the reuse pass must state what it skips"
fi
if printf '%s' "$REUSE_BLOCK" | grep -qE 'Upgrade, never downgrade'; then
  pass "T5.6: refuted hints downgrade the run to stale, never the reverse"
else
  fail "T5.6: the reuse pass must state the upgrade-never-downgrade rule"
fi
check_has "$SRC_RESEARCHER" 'prior_analysis' \
  "T5.7: the shared researcher contract accepts optional prior_analysis"
check_has "$SRC_RESEARCHER" 'verify-first hints to confirm or refute, never assertions to trust' \
  "T5.8: the shared researcher treats prior_analysis as verify-first hints"
check_has "$SRC_RESEARCHER" 'Phase 0 .*runs \*\*in full\*\*|Phase 0.*in full' \
  "T5.9: the shared researcher runs Phase 0 in full on every path"

# ───────────────────────────────────────────────────────────
# T6 (AC1): Step 2 skips the synthesizer and still produces a
# complete Decision Record.
# ───────────────────────────────────────────────────────────
check_has "$SRC_STEPS" '^### .reuse. — lift the options, skip the synthesis' \
  "T6.1: Step 2 has a reuse sub-section"
PLAN_BLOCK="$(awk '/^### .reuse. — lift the options, skip the synthesis/,/^### Plan selection/' "$SRC_STEPS")"
if printf '%s' "$PLAN_BLOCK" | grep -qE 'do \*\*not\*\* spawn the synthesizer'; then
  pass "T6.2: the reuse path does not spawn the synthesizer"
else
  fail "T6.2: the reuse path must state the synthesizer spawn is skipped"
fi
for field in 'options\[\]' 'recommended_option' 'overall_complexity' 'overall_risk'; do
  if printf '%s' "$PLAN_BLOCK" | grep -qE "$field"; then
    pass "T6.3: the reuse path lifts $field from the analysis"
  else
    fail "T6.3: the reuse path must lift $field from the analysis"
  fi
done
if printf '%s' "$PLAN_BLOCK" | grep -qE 'decision_record\.options_rejected'; then
  pass "T6.4: rejection_reason is derived from decision_record.options_rejected"
else
  fail "T6.4: rejection_reason must be derived from decision_record.options_rejected"
fi
if printf '%s' "$PLAN_BLOCK" | grep -qE 'rejection_reason'; then
  pass "T6.5: the mandatory synthesizer field rejection_reason is accounted for"
else
  fail "T6.5: the reuse path must account for the mandatory rejection_reason field"
fi
check_has "$SRC_TEMPLATES" 'Options produced' \
  "T6.6: the Step 2 completion check is reconciled with option-less synthesis"
check_has "$SRC_TEMPLATES" 'analysis_reuse = fresh' \
  "T6.7: the completion-report rule names the reuse state"

# ───────────────────────────────────────────────────────────
# T7 (AC2): report-templates.md carries no second definition.
# ───────────────────────────────────────────────────────────
check_lacks "$SRC_TEMPLATES" 'equals the synced base SHA' \
  "T7.1: the old stricter freshness definition is gone from report-templates.md"
check_has "$SRC_TEMPLATES" 'Step 0h — Analysis reuse gate' \
  "T7.2: report-templates.md points at the single home"
check_has "$SRC_TEMPLATES" 'selected_option. and .options_rejected. MUST always reflect this run' \
  "T7.3: the this-run rule for selected_option/options_rejected is preserved"

# ───────────────────────────────────────────────────────────
# T8 (install surface): the built tree carries the same contract.
# ───────────────────────────────────────────────────────────
check_has "$BUILT_STEPS" '^## Step 0h — Analysis reuse gate' \
  "T8.1: built pipeline-steps.md ships the Step 0h home"
check_has "$BUILT_STEPS" 'git merge-base --is-ancestor' \
  "T8.2: built pipeline-steps.md ships the ancestry test"
check_has "$BUILT_STEPS" 'analysis_reuse = fresh \| stale \| absent' \
  "T8.3: built pipeline-steps.md ships the three-state variable"
check_has "$BUILT_STEPS" 'verify-first hints to confirm or refute, never assertions to trust' \
  "T8.4: built pipeline-steps.md ships the verify-first semantics"
check_has "$BUILT_STEPS" 'decision_record\.options_rejected' \
  "T8.5: built pipeline-steps.md ships the rejection_reason derivation"
check_has "$BUILT_SKILL" '### 0h — Analysis reuse gate' \
  "T8.6: built SKILL.md ships the 0h sub-step"
check_has "$BUILT_SKILL" 'gi-issue\.py \{N\} --fields [a-zA-Z,]*updatedAt' \
  "T8.7: built SKILL.md ships the widened 0a field list"
check_lacks "$BUILT_TEMPLATES" 'equals the synced base SHA' \
  "T8.8: built report-templates.md carries no second freshness definition"
check_has "$BUILT_RESEARCHER" 'prior_analysis' \
  "T8.9: the bundled researcher prompt ships the prior_analysis contract"

# The methodology doc is the cross-skill statement of the same rule.
check_has "$SRC_METHODOLOGY" 'ancestor of this run|Step 0h — Analysis reuse gate' \
  "T8.10: idd-methodology.md names the reuse condition and its home"
BUILT_METHODOLOGY="$REPO_ROOT/skills/issue-resolver/references/docs/idd-methodology.md"
if [ -f "$BUILT_METHODOLOGY" ]; then
  check_has "$BUILT_METHODOLOGY" 'Step 0h — Analysis reuse gate' \
    "T8.11: the bundled methodology digest ships the reuse sentence"
else
  fail "T8.11: bundled idd-methodology.md missing from the resolver skill"
fi

# ───────────────────────────────────────────────────────────
# T9 (AC1/AC3): the artifact is resolved against the ORIGINAL
# checkout, not this run's workspace. `.gitissue/` is gitignored,
# so a Step 0e worktree never has it — a bare relative path there
# answers `absent` forever and the gate silently never fires.
# ───────────────────────────────────────────────────────────
PREDICATE_BLOCK="$(awk '/^### The predicate/,/^### Fail-safe/' "$SRC_STEPS")"
BUILT_PREDICATE_BLOCK="$(awk '/^### The predicate/,/^### Fail-safe/' "$BUILT_STEPS")"

check_block_has "$PREDICATE_BLOCK" 'git rev-parse --git-common-dir' \
  "T9.1: the predicate resolves the original checkout via --git-common-dir"
check_block_has "$PREDICATE_BLOCK" 'analysis="\$origin_root/\.gitissue/analysis-[{]N[}]\.json"' \
  "T9.2: the artifact path is anchored to that original checkout"
check_block_lacks "$PREDICATE_BLOCK" 'analysis="\.gitissue/' \
  "T9.3: the artifact is never read from a bare workspace-relative path"
check_has "$SRC_STEPS" 'gitignored, so a .*worktree never contains' \
  "T9.4: the gitignored-in-a-worktree reason is documented, not just avoided"
check_block_has "$PREDICATE_BLOCK" 'base_ref="origin/\$\{base\}"' \
  "T9.5: anchoring the artifact leaves the base ref this run's synced base"
check_block_has "$BUILT_PREDICATE_BLOCK" 'git rev-parse --git-common-dir' \
  "T9.6: built pipeline-steps.md ships the original-checkout resolution"
check_block_lacks "$BUILT_PREDICATE_BLOCK" 'analysis="\.gitissue/' \
  "T9.7: built pipeline-steps.md ships no workspace-relative artifact path"

# ───────────────────────────────────────────────────────────
# T10 (AC2): the predicate block contains no live expansion of an
# UNSET shell variable. `${N}` next to a real `${base}` reads as a
# shell variable and expands to nothing ⇒ a permanent `absent`.
# ───────────────────────────────────────────────────────────
check_lacks "$SRC_STEPS" '\$\{N\}' \
  "T10.1: no \${N} expansion of an unset variable in the resolver pipeline"
check_lacks "$BUILT_STEPS" '\$\{N\}' \
  "T10.2: the built pipeline-steps.md ships no \${N} expansion either"
check_block_has "$PREDICATE_BLOCK" 'substituted by the caller' \
  "T10.3: the block says which tokens are substitutions, not shell variables"

# ───────────────────────────────────────────────────────────
# T11 (AC1): `light` + `fresh` has one stated precedence. Both
# skip the synthesizer but produce different plans and different
# `Options rejected` content, so the composition must not be left
# to whichever sub-section is read first.
# ───────────────────────────────────────────────────────────
UNLOCKS_BLOCK="$(awk '/^### What .fresh. unlocks/,/^## Step 1 — Research/' "$SRC_STEPS")"
PLAN_LIGHT_BLOCK="$(awk '/^### .light. profile — skip the synthesis/,/^### .reuse. — lift the options/' "$SRC_STEPS")"

check_block_has "$UNLOCKS_BLOCK" '.reuse. wins Step 2' \
  "T11.1: Step 0h states the light+fresh precedence — reuse wins Step 2"
check_block_has "$UNLOCKS_BLOCK" 'presents all three options|present all three options' \
  "T11.2: the precedence restores the comment-and-wait option prompt"
check_block_has "$PLAN_LIGHT_BLOCK" 'analysis_reuse = fresh' \
  "T11.3: Step 2's light skip is conditioned on the analysis not being fresh"
check_block_has "$PLAN_LIGHT_BLOCK" '.reuse. wins Step 2' \
  "T11.4: Step 2's light sub-section defers to the same precedence rule"
check_block_has "$PLAN_BLOCK" '.light. profile too|precedence over the .light. skip' \
  "T11.5: Step 2's reuse sub-section states it governs on the light profile too"
check_has "$BUILT_STEPS" '.reuse. wins Step 2' \
  "T11.6: the built pipeline-steps.md ships the precedence rule"

# SKILL.md is the file an agent reads FIRST, and its Step 0g profile table
# self-declares as "the single home" for what `light` collapses. If that table's
# Step 2 row still says the design-confirm checkpoint never applies, a reader who
# stops there gets the opposite of the rule pipeline-steps.md states. Assert the
# carve-out in the row itself, on the source AND on the installed copy.
for pair in "src:$SRC_SKILL" "built:$BUILT_SKILL"; do
  tag="${pair%%:*}"
  skill_file="${pair#*:}"
  plan_row="$(grep -E '^\| 2 — Plan \|' "$skill_file" 2>/dev/null || true)"

  check_block_has "$plan_row" 'analysis_reuse = fresh' \
    "T11.7 ($tag): the Step 0g light table's Step 2 row carries the fresh carve-out"
  check_block_has "$plan_row" 'Step 2 — Plan → .reuse.' \
    "T11.8 ($tag): that row names the reuse sub-section that governs instead"
  check_block_has "$plan_row" '[Ll]ifted' \
    "T11.9 ($tag): that row says the options are lifted, not derived"
  check_block_has "$plan_row" 'design-confirm checkpoint \*\*does\*\* apply' \
    "T11.10 ($tag): that row states the design-confirm checkpoint does apply under fresh"
  check_has "$skill_file" '.?wins Step 2' \
    "T11.11 ($tag): the SKILL's Step 2 pointer states precedence, not addition"
done

# ───────────────────────────────────────────────────────────
# T12 (security): the analysis artifact is a NEW untrusted input
# channel — it is derived from issue text and its options become
# the plan the implementer executes. The prompt-injection boundary
# must demonstrably cover it.
# ───────────────────────────────────────────────────────────
check_block_has "$PLAN_BLOCK" 'untrusted local data' \
  "T12.1: Step 2's reuse path marks the analysis artifact untrusted"
check_block_has "$PLAN_BLOCK" 'never run a command it contains|never a command to run' \
  "T12.2: Step 2's reuse path forbids executing anything found in the artifact"
check_has "$SRC_RESEARCHER" 'untrusted local data' \
  "T12.3: the shared researcher marks prior_analysis untrusted"
check_has "$SRC_RESEARCHER" 'never instructions, never a command to run' \
  "T12.4: the shared researcher takes identifiers only, never instructions"
check_has "$BUILT_STEPS" 'untrusted local data' \
  "T12.5: the built pipeline-steps.md ships the untrusted-artifact rule"
check_has "$BUILT_RESEARCHER" 'untrusted local data' \
  "T12.6: the bundled researcher prompt ships the untrusted-artifact rule"

# ───────────────────────────────────────────────────────────
# T13 (AC1): producer ↔ consumer key contract. The gate can only
# answer `fresh` if /issue-analysis writes the exact keys it reads.
# Artifacts written before this contract carried `git_state.sha`,
# no `issue.updatedAt`, and a midnight-rounded invented timestamp —
# so conditions 2 and 5 failed on every real file and AC1's saving
# never materialised. The producer is where that is fixed: bind
# every captured value to its exact key, and capture the clock.
# ───────────────────────────────────────────────────────────
SRC_PERSIST="$REPO_ROOT/src/skills/issue-analysis/references/output-and-persist.md"
BUILT_PERSIST="$REPO_ROOT/skills/issue-analysis/references/output-and-persist.md"
SRC_ANALYSIS_SKILL="$REPO_ROOT/src/skills/issue-analysis/SKILL.source.md"
BUILT_ANALYSIS_SKILL="$REPO_ROOT/skills/issue-analysis/SKILL.md"

for pair in "src:$SRC_PERSIST" "built:$BUILT_PERSIST"; do
  tag="${pair%%:*}"
  persist_file="${pair#*:}"
  if [ ! -f "$persist_file" ]; then
    fail "T13 ($tag): missing ${persist_file#$REPO_ROOT/}"
    continue
  fi
  # Only the Persist step — the schema example below it is illustrative.
  persist_block="$(awk '/^## Persist/,/^### JSON Schema/' "$persist_file")"

  check_block_has "$persist_block" 'git rev-parse HEAD.*git_state\.commit_sha' \
    "T13.1 ($tag): the capture binds \`git rev-parse HEAD\` to git_state.commit_sha"
  check_block_has "$persist_block" 'git rev-parse --short=7 HEAD.*git_state\.commit_sha_short' \
    "T13.2 ($tag): the short SHA is bound to its own display-only key"
  check_block_has "$persist_block" 'never write it as .sha.' \
    "T13.3 ($tag): the drifted key name git_state.sha is explicitly forbidden"
  check_block_has "$persist_block" 'date -u \+%Y-%m-%dT%H:%M:%SZ' \
    "T13.4 ($tag): the Persist step carries a deterministic clock command"
  check_block_has "$persist_block" 'git_state\.captured_at AND the top-level' \
    "T13.5 ($tag): that one clock feeds captured_at and the top-level timestamp"
  check_block_has "$persist_block" 'never invented' \
    "T13.6 ($tag): both timestamps are captured by command, never invented"
  check_block_has "$persist_block" 'issue\.updatedAt.*(\*\*required\*\*|verbatim)' \
    "T13.7 ($tag): issue.updatedAt is required and copied verbatim from the fetch"
  check_block_has "$persist_block" 'Step 0h — Analysis reuse gate' \
    "T13.8 ($tag): the Persist step names the resolver gate as the consumer"
done

# The two sides must name the SAME key — read it out of each file rather than
# trusting a literal repeated in this test.
GATE_KEY="$(grep -oE 'get\("git_state",\{\}\)\.get\("[a-z_]+"' "$SRC_STEPS" \
  | head -1 | grep -oE '[a-z_]+"$' | tr -d '"' || true)"
PRODUCER_KEY="$(grep -oE 'git rev-parse HEAD[^|]*git_state\.[a-z_]+' "$SRC_PERSIST" \
  | head -1 | grep -oE 'git_state\.[a-z_]+' | sed 's/^git_state\.//' || true)"
if [ -n "$GATE_KEY" ] && [ "$GATE_KEY" = "$PRODUCER_KEY" ]; then
  pass "T13.9: the gate reads git_state.$GATE_KEY and the producer writes git_state.$PRODUCER_KEY"
else
  fail "T13.9: producer/consumer key drift — the gate reads 'git_state.${GATE_KEY:-<none>}' but the producer binds 'git_state.${PRODUCER_KEY:-<none>}'"
fi

check_has "$SRC_PERSIST" '\| .timestamp. \| ISO 8601 string \|.*never invented' \
  "T13.10: the schema field table pins timestamp to the captured clock"
check_has "$SRC_PERSIST" '\| .issue\.updatedAt. \|.*\*\*required\*\*' \
  "T13.11: the schema field table marks issue.updatedAt required"
check_has "$SRC_ANALYSIS_SKILL" 'git_state\.commit_sha. \(never .sha.\)' \
  "T13.12: the analysis SKILL source names the exact key, first read wins"
check_has "$SRC_ANALYSIS_SKILL" 'Step 0h — Analysis reuse gate' \
  "T13.13: the analysis SKILL source names the downstream consumer of the pin"
if [ -f "$BUILT_ANALYSIS_SKILL" ]; then
  check_has "$BUILT_ANALYSIS_SKILL" 'git_state\.commit_sha. \(never .sha.\)' \
    "T13.14: the built analysis SKILL.md ships the exact-key rule"
  check_has "$BUILT_ANALYSIS_SKILL" 'Step 0h — Analysis reuse gate' \
    "T13.15: the built analysis SKILL.md ships the consumer reference"
else
  fail "T13.14: missing skills/issue-analysis/SKILL.md — run ./scripts/build.sh"
fi

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
