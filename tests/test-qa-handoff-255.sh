#!/usr/bin/env bash
# test-qa-handoff-255.sh — QA handoff marker contract (issue #255)
#
# Acceptance criteria:
#   AC1: a clean resolver-authored PR gets exactly one confirmation review pass
#        in /issue-pr-review and no duplicate local test run.
#   AC2: any head-SHA mismatch, or an absent marker, produces today's full
#        pipeline — and every doubt fails safe to `stale`.
#   AC3: CI, acceptance-criteria verification, and the traceability checks still
#        run at full strength on a marked PR. Nothing security-shaped is ever
#        gated on a value the PR author can write.
#   AC4: human-authored PRs are completely unaffected.
#
# Asserts on the authored src/ sources AND on the built skills/ tree, because a
# contract that ships only in src/ is not installed for anyone.
#
# Usage: bash tests/test-qa-handoff-255.sh
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

echo "◆ QA Handoff Marker Contract Tests (issue #255)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

SRC_PR="$REPO_ROOT/src/skills/issue-pr-review/SKILL.source.md"
SRC_LOOP="$REPO_ROOT/src/skills/issue-pr-review/references/review-loop-mechanics.md"
SRC_RESOLVER="$REPO_ROOT/src/skills/issue-resolver/SKILL.source.md"
SRC_TEMPLATES="$REPO_ROOT/src/skills/issue-resolver/references/report-templates.md"
SRC_PLATFORM="$REPO_ROOT/docs/platform-github.md"
SRC_TERMINAL="$REPO_ROOT/docs/terminal-style.md"
SRC_METHODOLOGY="$REPO_ROOT/docs/idd-methodology.md"
SRC_CONFIG_SCHEMA="$REPO_ROOT/docs/config-schema.md"
SRC_CONFIG_TEMPLATE="$REPO_ROOT/src/skills/init-gitissue/templates/gitissue-template.yml"

BUILT_PR="$REPO_ROOT/skills/issue-pr-review/SKILL.md"
BUILT_LOOP="$REPO_ROOT/skills/issue-pr-review/references/review-loop-mechanics.md"
BUILT_RESOLVER="$REPO_ROOT/skills/issue-resolver/SKILL.md"
BUILT_TEMPLATES="$REPO_ROOT/skills/issue-resolver/references/report-templates.md"

for file in "$SRC_PR" "$SRC_LOOP" "$SRC_RESOLVER" "$SRC_TEMPLATES" "$SRC_PLATFORM" \
            "$SRC_TERMINAL" "$SRC_METHODOLOGY" "$BUILT_PR" "$BUILT_LOOP" \
            "$BUILT_RESOLVER" "$BUILT_TEMPLATES"; do
  if [ -f "$file" ]; then
    pass "exists: ${file#$REPO_ROOT/}"
  else
    fail "missing: ${file#$REPO_ROOT/}"
  fi
done

# ───────────────────────────────────────────────────────────
# T1 (AC1): the gate exists as one named state variable with a
# three-value verdict, in the source and in the built skill.
# ───────────────────────────────────────────────────────────
for pair in "src:$SRC_PR" "built:$BUILT_PR"; do
  tag="${pair%%:*}"
  f="${pair#*:}"
  check_has "$f" '^### QA handoff gate' \
    "T1.1 ($tag): SKILL.md declares the QA handoff gate"
  check_has "$f" 'qa_handoff = trusted \| stale \| absent' \
    "T1.2 ($tag): the gate sets one three-state variable"
  for state in trusted stale absent; do
    check_has "$f" "\`$state\`" "T1.3 ($tag): state \`$state\` is documented"
  done
done

# ───────────────────────────────────────────────────────────
# T2 (AC1): the reviewer collapse is a MERGE into the existing
# fresh confirmation pass, not a deleted review. One independent
# full-strength review still happens.
# ───────────────────────────────────────────────────────────
check_has "$SRC_PR" 'collapsed into.*confirmation pass|confirmation pass.*collapsed' \
  "T2.1: Step 3 collapses cycle 1 into the fresh confirmation pass"
check_has "$SRC_PR" 'exactly one independent, full-strength review' \
  "T2.2: SKILL.md states one independent full-strength review still runs"
check_has "$SRC_PR" 'min\(1, configured_cap\)' \
  "T2.3: the loop cap reuses the existing min(1, configured_cap) ceiling idiom"
check_has "$BUILT_PR" 'collapsed into' \
  "T2.4: the built SKILL.md ships the collapse, not a skip"

SKIPS_BLOCK="$(awk '/^### What .trusted. skips/,/^### Never gated/' "$SRC_LOOP")"
check_block_has "$SKIPS_BLOCK" 'collapsed into.*fresh confirmation pass' \
  "T2.5: the skips table describes the reviewer as collapsed, never removed"
check_block_has "$SKIPS_BLOCK" 'min\(1, configured_cap\)' \
  "T2.6: the skips table caps the loop with the same ceiling idiom"
check_has "$SRC_LOOP" 'merge, not a deletion' \
  "T2.7: review-loop-mechanics states the collapse is a merge, not a deletion"

# ───────────────────────────────────────────────────────────
# T3 (AC1): the duplicate local test runs are skipped — at BOTH
# Step 2 and Step 4 — and only when the marker's tests= SHA
# equals head. No tests= field ⇒ nothing is skipped.
# ───────────────────────────────────────────────────────────
STEP2_BLOCK="$(awk '/^## Step 2 — Script Pre-pass/,/^## Step 3 — Analyze/' "$SRC_PR")"
STEP4_BLOCK="$(awk '/^## Step 4 — Run Tests/,/^## Step 5 — Check CI/' "$SRC_PR")"

check_block_has "$STEP2_BLOCK" 'qa_handoff = trusted' \
  "T3.1: Step 2's test leg names the trusted verdict"
check_block_has "$STEP2_BLOCK" 'skip only the test run|skip .*only the test run' \
  "T3.2: Step 2 skips only the test run, not the whole pre-pass"
check_block_has "$STEP2_BLOCK" 'tests=. field whose SHA equals .head|tests=.*SHA equals' \
  "T3.3: Step 2's skip is conditioned on the tests= SHA equalling head"
check_block_has "$STEP4_BLOCK" 'qa_handoff = trusted' \
  "T3.4: Step 4 names the trusted verdict"
check_block_has "$STEP4_BLOCK" 'tests=. field whose SHA equals .head|tests=.*SHA equals' \
  "T3.5: Step 4's skip is conditioned on the tests= SHA equalling head"
check_block_has "$STEP4_BLOCK" 'with no .tests=. field, or a SHA that differs, run the step in full' \
  "T3.6: a missing or mismatched tests= field runs Step 4 in full"
check_has "$SRC_LOOP" 'Absent .tests=. ⇒ run both test legs' \
  "T3.7: review-loop-mechanics states absent tests= skips nothing"

# The code UI review is gated on its own leg, never on ui=none.
check_has "$SRC_PR" 'never on .ui=none' \
  "T3.8: the code UI review is never skipped on ui=none"
check_has "$SRC_LOOP" 'never on .ui=none' \
  "T3.9: the mechanics repeat the ui=none carve-out in the skips table"

# ───────────────────────────────────────────────────────────
# T4 (AC2): `trusted` iff the marker parses AND head= equals the
# PR's headRefOid — a literal, checkable predicate.
# ───────────────────────────────────────────────────────────
for pair in "src:$SRC_PR" "built:$BUILT_PR"; do
  tag="${pair%%:*}"
  f="${pair#*:}"
  check_has "$f" 'head=. equals.*headRefOid|head=.*headRefOid' \
    "T4.1 ($tag): the trusted predicate is head= equals headRefOid"
  check_has "$f" '[Ff]ail-safe: any doubt is .stale' \
    "T4.2 ($tag): the fail-safe rule is stated verbatim"
  check_has "$f" "today's full pipeline, unchanged" \
    "T4.3 ($tag): stale and absent run today's full pipeline unchanged"
done

check_has "$SRC_LOOP" 'trusted\*\* \*\*iff\*\*|`trusted` \*\*iff\*\*' \
  "T4.4: the mechanics state the predicate as an iff"
check_has "$SRC_LOOP" '40 lowercase hex' \
  "T4.5: head= must be a full 40-char lowercase hex SHA"
check_has "$SRC_LOOP" '[Mm]ore than one match.*stale|two markers is ambiguous' \
  "T4.6: more than one marker resolves to stale, never first-match-wins"
check_has "$SRC_LOOP" 'or extra keys are \*\*ignored, never fatal\*\*' \
  "T4.7: unknown/extra fields are ignored rather than fatal"
check_has "$SRC_LOOP" 'byte-identical' \
  "T4.8: stale/absent are documented as byte-identical to today's pipeline"

# The verdict must be self-invalidating: a pushed fix moves head.
check_has "$SRC_LOOP" 'self-invalidat' \
  "T4.9: the head binding is documented as self-invalidating"
check_has "$SRC_LOOP" 'binding is on code, not on prose' \
  "T4.10: a body edit does not move head, so the marker survives it"

# ───────────────────────────────────────────────────────────
# T5 (AC3, security-critical): nothing safety-shaped is gated.
# This is the group that must never be weakened.
# ───────────────────────────────────────────────────────────
# 5a. The scan field the reporter asked for does not exist, anywhere.
SCAN_HITS="$(grep -rlE 'scan=' "$REPO_ROOT/src" "$REPO_ROOT/skills" "$REPO_ROOT/docs" 2>/dev/null || true)"
if [ -z "$SCAN_HITS" ]; then
  pass "T5.1: no secret-scan field exists in src/, skills/ or docs/"
else
  fail "T5.1: a secret-scan marker field appeared — its only consumer would be a safety gate"
  printf '      %s\n' $SCAN_HITS
fi
check_has "$SRC_TEMPLATES" '[Nn]o secret-scan field, ever' \
  "T5.2: the producer states the omission as a deliberate rule"
check_has "$SRC_LOOP" 'no security-scan field, in any spelling, and none may be added' \
  "T5.3: the consumer forbids adding one later"
check_has "$SRC_TEMPLATES" '#274' \
  "T5.4: the producer cites #274 as the standing proof"
check_has "$SRC_LOOP" '#274' \
  "T5.5: the consumer cites #274 as the standing proof"
check_has "$SRC_LOOP" 'forgery is worthless, not impossible|worthless, not impossible' \
  "T5.6: the trust model says forgery is made worthless, not impossible"
check_has "$SRC_LOOP" 'attacker-controlled' \
  "T5.7: the PR body is named attacker-controlled"
check_has "$SRC_LOOP" 'does\s*\n?\*\*not\*\* authenticate|not.*authenticate it either|never authentication' \
  "T5.8: head= is explicitly not authentication"
check_has "$SRC_PR" 'never authentication' \
  "T5.9: SKILL.md carries the not-authentication rule where it is read first"

# 5b. The Never-gated list exists and names every protected check.
check_has "$SRC_LOOP" '^### Never gated' \
  "T5.10: the mechanics carry an explicit Never gated section"
NEVER_BLOCK="$(awk '/^### Never gated/,0' "$SRC_LOOP")"
for entry in 'gi-secscan' 'lint/format auto-fix' 'CI wait' 'acceptance-criteria verification' 'four traceability checks'; do
  check_block_has "$NEVER_BLOCK" "$entry" \
    "T5.11: Never gated names: $entry"
done
check_block_has "$NEVER_BLOCK" 'there is no diff-confirm mode' \
  "T5.12: the reporter's diff-confirm AC mode is explicitly refused"
check_block_has "$NEVER_BLOCK" 'marking your own homework' \
  "T5.13: the refusal states why — the resolver authored the table being trusted"
check_block_has "$NEVER_BLOCK" 'hard-blocks' \
  "T5.14: both #36 hard-blocks keep blocking under trusted"

# 5c. The protected call sites carry NO marker conditional. Read each block and
#     assert the gate variable never appears inside it.
SECSCAN_BLOCK="$(awk '/^### Commit auto-fixes/,/^## Step 3 — Analyze/' "$SRC_PR")"
CI_BLOCK="$(awk '/^## Step 5 — Check CI Status/,/^## Step 6 — Fix Issues/' "$SRC_PR")"
VERIFY_BLOCK="$(awk '/^### Verification gates and the AC \+ traceability checks/,/^## Step 4 — Run Tests/' "$SRC_PR")"

check_block_lacks "$SECSCAN_BLOCK" 'qa_handoff' \
  "T5.15: the gi-secscan invocation carries no qa_handoff conditional"
check_block_has "$SECSCAN_BLOCK" 'gi-secscan\.py --working-tree' \
  "T5.16: (guard) the gi-secscan block was actually located"
check_block_lacks "$CI_BLOCK" 'qa_handoff' \
  "T5.17: Step 5's CI wait carries no qa_handoff conditional"
check_block_has "$CI_BLOCK" 'gi-ci-wait\.py' \
  "T5.18: (guard) the CI block was actually located"
check_block_lacks "$VERIFY_BLOCK" 'qa_handoff' \
  "T5.19: the AC + traceability verification gates carry no qa_handoff conditional"
check_block_has "$VERIFY_BLOCK" 'require_acceptance_criteria_check' \
  "T5.20: (guard) the verification block was actually located"

# The same must hold on the installed copy — a src-only guarantee ships nothing.
BUILT_SECSCAN_BLOCK="$(awk '/^### Commit auto-fixes/,/^## Step 3 — Analyze/' "$BUILT_PR")"
BUILT_CI_BLOCK="$(awk '/^## Step 5 — Check CI Status/,/^## Step 6 — Fix Issues/' "$BUILT_PR")"
BUILT_VERIFY_BLOCK="$(awk '/^### Verification gates and the AC \+ traceability checks/,/^## Step 4 — Run Tests/' "$BUILT_PR")"
check_block_lacks "$BUILT_SECSCAN_BLOCK" 'qa_handoff' \
  "T5.21: built SKILL.md keeps gi-secscan unconditional"
check_block_lacks "$BUILT_CI_BLOCK" 'qa_handoff' \
  "T5.22: built SKILL.md keeps the CI wait unconditional"
check_block_lacks "$BUILT_VERIFY_BLOCK" 'qa_handoff' \
  "T5.23: built SKILL.md keeps AC + traceability unconditional"
check_has "$BUILT_LOOP" '^### Never gated' \
  "T5.24: the built mechanics ship the Never gated list"

# ───────────────────────────────────────────────────────────
# T6 (AC4): a human-authored PR carries no marker, so the gate
# answers `absent` and changes nothing about its review.
# ───────────────────────────────────────────────────────────
check_has "$SRC_PR" 'the body carries no marker' \
  "T6.1: an absent marker is a first-class documented state"
check_has "$SRC_LOOP" 'human-authored PR never' \
  "T6.2: human-authored PRs are named as always absent"
check_has "$SRC_LOOP" 'unaffected by this gate' \
  "T6.3: the mechanics state human PRs are unaffected"
check_has "$BUILT_LOOP" 'human-authored PR never' \
  "T6.4: the built mechanics ship the human-PR carve-out"

# ───────────────────────────────────────────────────────────
# T7 (AC2/AC3): no new config key. review.adaptive_depth is the
# off-switch, and the schema ↔ template pair is untouched.
# ───────────────────────────────────────────────────────────
check_has "$SRC_PR" 'review\.adaptive_depth. is .false., skip this gate' \
  "T7.1: review.adaptive_depth=false disables the gate"
check_has "$SRC_PR" '[Nn]o new config key is introduced' \
  "T7.2: SKILL.md states no new config key is introduced"
check_lacks "$SRC_CONFIG_SCHEMA" 'qa_handoff|qa_trust|handoff_' \
  "T7.3: docs/config-schema.md gained no qa-handoff key"
check_lacks "$SRC_CONFIG_TEMPLATE" 'qa_handoff|qa_trust|handoff_' \
  "T7.4: the /init-gitissue template gained no qa-handoff key"
check_has "$BUILT_PR" '[Nn]o new config key is introduced' \
  "T7.5: the built SKILL.md ships the no-new-key rule"

# Precedence with the pre-existing light|full depth gate, stated once.
PRECEDENCE_HITS="$(grep -rlE 'Precedence, stated once' "$REPO_ROOT/src" 2>/dev/null || true)"
PRECEDENCE_COUNT="$(printf '%s\n' "$PRECEDENCE_HITS" | grep -c . || true)"
if [ "$PRECEDENCE_COUNT" = "1" ] && [ "$PRECEDENCE_HITS" = "$SRC_PR" ]; then
  pass "T7.6: the depth ↔ handoff precedence is stated in exactly one src/ file"
else
  fail "T7.6: the precedence rule must live in exactly one src/ file — found $PRECEDENCE_COUNT"
  printf '      %s\n' $PRECEDENCE_HITS
fi
check_has "$SRC_PR" '\*\*narrow\*\* work and never widen it' \
  "T7.7: qa_handoff may only narrow work, never widen it"
check_has "$SRC_PR" 'review collapse is \*\*refused\*\*' \
  "T7.8: marker profile=light against pr-review full refuses the review collapse"
check_has "$SRC_PR" 'duplicate-test skip still applies' \
  "T7.9: that same asymmetric case still allows the duplicate-test skip"

# ───────────────────────────────────────────────────────────
# T8 (AC1/AC2): headRefOid is actually fetched — the predicate is
# unevaluable without it — and the platform catalog agrees.
# ───────────────────────────────────────────────────────────
for pair in "src:$SRC_PR" "built:$BUILT_PR"; do
  tag="${pair%%:*}"
  f="${pair#*:}"
  fetch_line="$(grep -E '^gh pr view \{N\} --json ' "$f" | head -1 || true)"
  check_block_has "$fetch_line" 'headRefOid' \
    "T8.1 ($tag): Step 1's gh pr view field list requests headRefOid"
done
check_has "$SRC_PLATFORM" '^\| Read one PR \|.*headRefOid' \
  "T8.2: docs/platform-github.md lists headRefOid on the canonical PR read"
check_has "$REPO_ROOT/skills/issue-pr-review/references/docs/platform-github.md" 'headRefOid' \
  "T8.3: the bundled platform driver ships headRefOid"

# ───────────────────────────────────────────────────────────
# T9 (producer): the resolver emits the marker LAST, only on a
# clean QA exit, with the documented grammar.
# ───────────────────────────────────────────────────────────
for pair in "src:$SRC_TEMPLATES" "built:$BUILT_TEMPLATES"; do
  tag="${pair%%:*}"
  f="${pair#*:}"
  check_has "$f" '^### QA handoff marker' \
    "T9.1 ($tag): report-templates.md owns the producer contract"
  check_has "$f" '<!-- gitissue:qa v1 head=<sha40> profile=<light\|full> cycles=<n> review=clean' \
    "T9.2 ($tag): the grammar is written out in full"
  check_has "$f" 'tests=<count>@<sha40>' \
    "T9.3 ($tag): tests= carries the SHA the suite actually ran against"
  check_has "$f" 'ui=<none\|code\|code\+browser>' \
    "T9.4 ($tag): ui= is split into legs"
  check_has "$f" '[Tt]he marker goes last|last line of the body' \
    "T9.5 ($tag): the marker-goes-last rule is stated"
  check_has "$f" 'emit \*\*no marker line\*\*|[Nn]o marker on a non-clean exit' \
    "T9.6 ($tag): a non-clean QA exit emits no marker at all"
  check_has "$f" 'resolve\.auto_test' \
    "T9.7 ($tag): tests= is omitted when the resolver ran no final suite"
done

# The marker must be the LAST line inside the PR body template fence.
TEMPLATE_FENCE="$(awk '/^## PR Body Template/,/^The PR title follows/' "$SRC_TEMPLATES")"
LAST_IN_FENCE="$(printf '%s\n' "$TEMPLATE_FENCE" | grep -vE '^\s*$' | awk '/^```$/{last=prev} {prev=$0} END {print last}')"
if printf '%s' "$LAST_IN_FENCE" | grep -q 'gitissue:qa v1'; then
  pass "T9.8: the marker is the last content line of the PR body template"
else
  fail "T9.8: the PR body template does not end with the qa marker (got: ${LAST_IN_FENCE:0:60})"
fi

for pair in "src:$SRC_RESOLVER" "built:$BUILT_RESOLVER"; do
  tag="${pair%%:*}"
  f="${pair#*:}"
  check_has "$f" 'gitissue:qa v1' \
    "T9.9 ($tag): the resolver SKILL points at the marker"
  check_has "$f" 'only when QA exited clean' \
    "T9.10 ($tag): the resolver SKILL gates emission on a clean QA exit"
  check_has "$f" 'QA handoff marker' \
    "T9.11 ($tag): the resolver SKILL names the owning subsection"
done

# ───────────────────────────────────────────────────────────
# T10 (cross-skill): the methodology and style docs carry the
# marker so it is not a private convention of two skills.
# ───────────────────────────────────────────────────────────
check_has "$SRC_METHODOLOGY" 'QA handoff marker' \
  "T10.1: idd-methodology.md documents the marker as durable memory"
METHOD_SECTION="$(awk '/^## Analysis Artifacts and Durable Memory/,/^## Issue Dependencies/' "$SRC_METHODOLOGY")"
check_block_has "$METHOD_SECTION" 'QA handoff marker' \
  "T10.2: it sits inside the digested Analysis Artifacts section (a new ## would be dropped)"
check_block_has "$METHOD_SECTION" 'not\*\* authentication|deliberately \*\*not\*\* authentication' \
  "T10.3: the methodology states the marker is not authentication"
BUILT_METHODOLOGY="$REPO_ROOT/skills/issue-pr-review/references/docs/idd-methodology.md"
if [ -f "$BUILT_METHODOLOGY" ]; then
  check_has "$BUILT_METHODOLOGY" 'QA handoff marker' \
    "T10.4: the bundled methodology digest ships the marker sentence"
else
  fail "T10.4: bundled idd-methodology.md missing from issue-pr-review"
fi
check_has "$SRC_TERMINAL" 'QA handoff marker: .<!-- gitissue:qa v1' \
  "T10.5: terminal-style.md lists the marker in the marker vocabulary"
check_has "$REPO_ROOT/skills/issue-resolver/references/docs/terminal-style.md" 'gitissue:qa v1' \
  "T10.6: the bundled terminal-style doc ships the marker vocabulary"

# ───────────────────────────────────────────────────────────
# T11 (AC3): Step 6's PR-body edit preserves the marker, and the
# auto-pilot narration does not go stale about skipped tests.
# ───────────────────────────────────────────────────────────
check_has "$SRC_PR" 'gitissue:qa v1 … -->. marker are still present' \
  "T11.1: Step 6's post-edit re-read confirms the marker survived"
check_has "$BUILT_PR" 'gitissue:qa v1' \
  "T11.2: the built SKILL.md ships the preserved-content confirmation"

AP_PROMPTS="$REPO_ROOT/src/skills/auto-pilot/references/subagent-prompts.md"
AP_PHASES="$REPO_ROOT/src/skills/auto-pilot/references/phases.md"
check_has "$AP_PROMPTS" 'QA handoff marker' \
  "T11.3: the auto-pilot reviewer prompt qualifies its run-tests narration"
check_has "$AP_PHASES" 'QA handoff marker' \
  "T11.4: auto-pilot phases.md qualifies its run-tests narration"
check_has "$AP_PHASES" 'never skipped by the marker' \
  "T11.5: auto-pilot states CI is never skipped by the marker"

# ───────────────────────────────────────────────────────────
# T12 (install surface): both capped SKILL.md files stay inside
# the skill-creator 500-line cap after this change.
# ───────────────────────────────────────────────────────────
for f in "$SRC_PR" "$BUILT_PR" "$SRC_RESOLVER" "$BUILT_RESOLVER"; do
  lines=$(wc -l < "$f" | tr -d ' ')
  if [ "$lines" -le 500 ]; then
    pass "T12: ${f#$REPO_ROOT/} is $lines lines (≤ 500)"
  else
    fail "T12: ${f#$REPO_ROOT/} is $lines lines (> 500)"
  fi
done

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
