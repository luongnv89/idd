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
SRC_PR_TEMPLATES="$REPO_ROOT/src/skills/issue-pr-review/references/report-templates.md"
SRC_VERIFY="$REPO_ROOT/src/skills/issue-pr-review/references/verification-checks.md"
SRC_PREPASS="$REPO_ROOT/src/skills/issue-pr-review/references/prepass-tests-ci-mechanics.md"
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
BUILT_PR_TEMPLATES="$REPO_ROOT/skills/issue-pr-review/references/report-templates.md"
BUILT_VERIFY="$REPO_ROOT/skills/issue-pr-review/references/verification-checks.md"
BUILT_PREPASS="$REPO_ROOT/skills/issue-pr-review/references/prepass-tests-ci-mechanics.md"

# Every file an assertion reads is proved to exist first. A check_lacks against a
# path that does not exist passes vacuously, so this loop is what makes the
# forbidden-pattern guards below mean anything.
for file in "$SRC_PR" "$SRC_LOOP" "$SRC_RESOLVER" "$SRC_TEMPLATES" "$SRC_PLATFORM" \
            "$SRC_TERMINAL" "$SRC_METHODOLOGY" "$SRC_PR_TEMPLATES" "$SRC_VERIFY" \
            "$SRC_PREPASS" "$BUILT_PR" "$BUILT_LOOP" \
            "$BUILT_RESOLVER" "$BUILT_TEMPLATES" "$BUILT_PR_TEMPLATES" \
            "$BUILT_VERIFY" "$BUILT_PREPASS"; do
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
  # SKILL.md is read before the mechanics and owns the fail-safe, so an
  # unknown-field entry on this list would silently kill forward compatibility —
  # every extended marker rejected — while the mechanics say the opposite
  # ("ignored, never fatal"). The list is unparsable + duplicated, nothing else.
  check_lacks "$f" 'unparsable, duplicated, or unknown-field' \
    "T4.2b ($tag): an unknown field is not on the stale fail-safe list"
  check_has "$f" 'unparsable or duplicated marker included' \
    "T4.2c ($tag): the fail-safe list is unparsable + duplicated only"
  check_has "$f" 'unknown extra field is \*not\* doubt' \
    "T4.2d ($tag): SKILL.md says so explicitly rather than leaving it ambiguous"
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
# 5a. The scan field the reporter asked for does not exist, anywhere. The grep is
#     deliberately wider than the single `scan=` spelling that was proposed:
#     `secrets=`, `security=`, `sec=`, `secscan=` or `audit=` would each be the
#     same field under another name, and the prose rule must not be defeated by a
#     rename. The rule in review-loop-mechanics.md is the real defense; this is
#     the tripwire that notices when it is broken.
SCAN_FIELD_RE='\b(scan|scanned|scanning|secscan|secrets?|security|sec|safety|audit|verified|signed)='
# A tripwire that matches nothing is worthless — prove the regex fires on every
# spelling it claims to cover, and stays off innocuous lookalikes.
TRIPWIRE_OK=1
for spelling in 'scan=clean' 'scanned=1' 'scanning=1' 'secscan=pass' 'secret=none' \
                'secrets=none' 'security=clean' 'sec=ok' 'safety=ok' 'audit=clean' \
                'verified=1' 'signed=1'; do
  if ! printf '%s\n' "$spelling" | grep -qE "$SCAN_FIELD_RE"; then
    TRIPWIRE_OK=0
    echo "      spelling not matched: $spelling"
  fi
done
for innocuous in 'exec=1' 'parsec=1' 'codec=h264'; do
  if printf '%s\n' "$innocuous" | grep -qE "$SCAN_FIELD_RE"; then
    TRIPWIRE_OK=0
    echo "      false positive: $innocuous"
  fi
done
if [ "$TRIPWIRE_OK" = "1" ]; then
  pass "T5.0: the security-field tripwire matches every spelling it claims to cover"
else
  fail "T5.0: the security-field tripwire is vacuous or over-broad"
fi

SCAN_HITS="$(grep -rlE "$SCAN_FIELD_RE" "$REPO_ROOT/src" "$REPO_ROOT/skills" "$REPO_ROOT/docs" 2>/dev/null || true)"
if [ -z "$SCAN_HITS" ]; then
  pass "T5.1: no secret-scan field exists in src/, skills/ or docs/ (any spelling)"
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

# 5d. The blocks above only cover SKILL.md. The procedures they gate are written
#     down elsewhere: verification-checks.md holds the per-criterion AC check and
#     the four traceability checks, prepass-tests-ci-mechanics.md holds the Step
#     2/4 test runs and the Step 5 CI polling fallback. The gate decision belongs
#     in SKILL.md alone — neither delegated file may grow a marker conditional,
#     or the guard above becomes a guard over a pointer.
for pair in "src:$SRC_VERIFY" "src:$SRC_PREPASS" "built:$BUILT_VERIFY" "built:$BUILT_PREPASS"; do
  tag="${pair%%:*}"
  f="${pair#*:}"
  check_lacks "$f" 'qa_handoff' \
    "T5.25 ($tag): ${f##*/} carries no qa_handoff conditional"
done
# (guard) each delegated file is the one we think it is, so the check_lacks above
# cannot pass on an emptied or renamed file.
check_has "$SRC_VERIFY" '^## Acceptance-criteria verification \(per criterion\)' \
  "T5.26: (guard) verification-checks.md still owns the per-criterion AC check"
check_has "$SRC_VERIFY" '^## Traceability checks' \
  "T5.27: (guard) verification-checks.md still owns the traceability checks"
check_has "$SRC_PREPASS" '^## Step 5 — CI polling and failure extraction' \
  "T5.28: (guard) prepass-tests-ci-mechanics.md still owns the CI polling fallback"
check_has "$BUILT_VERIFY" '^## Traceability checks' \
  "T5.29: (guard) the built verification-checks.md is the same document"
check_has "$BUILT_PREPASS" '^## Step 5 — CI polling and failure extraction' \
  "T5.30: (guard) the built prepass-tests-ci-mechanics.md is the same document"

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
check_has "$SRC_PR" 'bounded \*\*relative to the ungated pipeline\*\*' \
  "T7.7: qa_handoff's power is bounded against the ungated pipeline"
check_has "$SRC_PR" 'may only \*\*narrow\*\*' \
  "T7.7b: it may only narrow what a stale/absent PR already gets"
check_has "$SRC_PR" 'per verdict, not monotonic across the run' \
  "T7.7c: the bound is per verdict, so re-evaluation is not a widening"
check_has "$SRC_PR" 'review collapse \*\*and\*\* the cycle cap' \
  "T7.8: profile=light against pr-review full refuses the collapse AND the cap"
check_has "$SRC_PR" 'duplicate-test skip still applies' \
  "T7.9: that same asymmetric case still allows the duplicate-test skip"
check_block_has "$SKIPS_BLOCK" 'the same carve-out as the reviewer-collapse row' \
  "T7.10: the skips table's cycle-cap row names the same carve-out, not 'always'"
check_block_has "$SKIPS_BLOCK" 'refuses the collapse \(\*Precedence\* in SKILL.md owns that rule' \
  "T7.11: the skips table points at SKILL.md instead of restating the rule"

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
# T13 (AC2): the verdict is recomputed after EVERY push this
# skill makes — Step 2's lint/format auto-fix commit as well as
# the fixer's. The loop re-enters at Step 3, so a once-computed
# `trusted` would survive the very commit that invalidates it,
# and both test legs would then be skipped on a commit no local
# suite has ever run.
# ───────────────────────────────────────────────────────────
check_has "$SRC_LOOP" '^### Re-evaluation after a push' \
  "T13.1: the mechanics own a re-evaluation section, scoped to any push"
check_has "$BUILT_LOOP" '^### Re-evaluation after a push' \
  "T13.2: the built mechanics ship it"
check_has "$SRC_LOOP" 'per-cycle\*\* verdict, not a once-per-run constant' \
  "T13.3: qa_handoff is documented as a per-cycle verdict"
check_has "$SRC_LOOP" 're-enters at \*\*Step 3, not Step 1\*\*' \
  "T13.4: the mechanics name the re-entry point that makes this necessary"
for pair in "src:$SRC_PR" "built:$BUILT_PR"; do
  tag="${pair%%:*}"
  f="${pair#*:}"
  check_has "$f" 'Re-evaluate .qa_handoff. after any push this skill makes' \
    "T13.5 ($tag): the Review Loop re-evaluates after ANY push, not just the fixer's"
  check_lacks "$f" 'Re-evaluate .qa_handoff. after every fixer push' \
    "T13.5b ($tag): the trigger is no longer scoped to the fixer alone"
  check_has "$f" "Step 2's auto-fix commit as much as every fixer push" \
    "T13.5c ($tag): Step 2's own push is named as a re-evaluation trigger"
  check_has "$f" 're-read .headRefOid. and recompute' \
    "T13.6 ($tag): re-evaluation is spelled out as re-read headRefOid + recompute"
done

# Step 2 is where the missed trigger bit: it commits and pushes its lint/format
# auto-fix (the resolver runs no formatter, so this is the likely path), moving
# head off the marker before Step 3 or Step 4 ever consult the verdict.
REEVAL_BLOCK="$(awk '/^### Re-evaluation after a push/,/^### Never gated/' "$SRC_LOOP")"
check_block_has "$REEVAL_BLOCK" "Step 2's lint/format auto-fix commit" \
  "T13.5d: the mechanics enumerate Step 2's auto-fix commit as a trigger"
check_block_has "$REEVAL_BLOCK" '[Ee]very fixer push in the Review Loop' \
  "T13.5e: the mechanics enumerate the fixer push as the other trigger"
check_block_has "$REEVAL_BLOCK" 'any push this skill makes' \
  "T13.5f: (guard) the re-evaluation block was actually located"
for pair in "src:$SRC_PR" "built:$BUILT_PR"; do
  tag="${pair%%:*}"
  f="${pair#*:}"
  step2="$(awk '/^## Step 2 — Script Pre-pass/,/^## Step 3 — Analyze/' "$f")"
  check_block_has "$step2" 'recompute the verdict then, before Step 3' \
    "T13.5g ($tag): Step 2 instructs a recompute after its own auto-fix push"
done

# The producer template supplies the marker line itself — one marker, never two.
# Two markers read as `stale`, silently disabling the whole feature.
for pair in "src:$SRC_TEMPLATES" "built:$BUILT_TEMPLATES"; do
  tag="${pair%%:*}"
  f="${pair#*:}"
  check_has "$f" 'omit this entire line unless QA exited clean' \
    "T13.7 ($tag): the PR body template carries an inline omit conditional"
  check_has "$f" 'goes last, and exactly once' \
    "T13.8 ($tag): the producer states one-marker-only"
  check_has "$f" '[Nn]ever append a second copy' \
    "T13.9 ($tag): appending a second marker is forbidden"
done
check_has "$SRC_RESOLVER" 'never append a second copy' \
  "T13.10: the resolver SKILL does not instruct an append of the template's own line"
check_has "$BUILT_RESOLVER" 'never append a second copy' \
  "T13.11: the built resolver SKILL ships the same wording"

# A skipped Step 4 evaluated neither check, so it renders PARTIAL — never a
# silent pass — and {head7} was never a defined template variable.
BUILT_STEP4_BLOCK="$(awk '/^## Step 4 — Run Tests/,/^## Step 5 — Check CI/' "$BUILT_PR")"
check_block_has "$STEP4_BLOCK" 'Result: PARTIAL' \
  "T13.12: Step 4's trusted skip states its completion rendering"
check_block_has "$STEP4_BLOCK" '× Suite passed. / .× Build clean' \
  "T13.13: both Step 4 checks render × on the skip path"
check_block_has "$BUILT_STEP4_BLOCK" 'Result: PARTIAL' \
  "T13.14: the built SKILL.md ships the PARTIAL rendering"
check_has "$SRC_PR_TEMPLATES" 'qa_handoff = trusted' \
  "T13.15: the PARTIAL enumeration lists Step 4's qa-handoff skip"
check_has "$BUILT_PR_TEMPLATES" 'qa_handoff = trusted' \
  "T13.16: the built templates ship that enumeration entry"
for pair in "src:$SRC_PR" "built:$BUILT_PR"; do
  tag="${pair%%:*}"
  f="${pair#*:}"
  check_lacks "$f" '\{head7\}' \
    "T13.17 ($tag): the undefined {head7} template variable is gone"
  check_has "$f" 'tests skipped \(qa handoff @ \{commit_sha_short\}\)' \
    "T13.18 ($tag): the skip line uses the defined {commit_sha_short} variable"
done

# ───────────────────────────────────────────────────────────
# T14 (AC1 accuracy): the claims a reader acts on must match what
# the pipeline actually does.
#   a) `trusted` reaches the CODE UI leg only. The browser leg is
#      opt-in and fail-soft on both sides, and `ui=` exists to keep
#      the two legs apart — a `trusted` browser skip would flatten
#      exactly the split that field was added for.
#   b) the collapse saves no reviewer spawn: the confirmation pass
#      is fix-conditional, so an unmarked clean PR already gets
#      exactly one cold-start pass and no confirmation.
#   c) Step 4's trusted skip states the soft-pass clause both of
#      its sibling skips state — without it the conjunction has no
#      satisfied branch and a clean resolver PR could never be
#      reported clean, defeating AC1.
# ───────────────────────────────────────────────────────────
for pair in "src:$SRC_PR" "built:$BUILT_PR"; do
  tag="${pair%%:*}"
  f="${pair#*:}"
  # (a) the browser-UI skip belongs to the light profile alone.
  check_has "$f" 'The .light. profile also skips the optional browser UI review; .trusted. never does' \
    "T14.1 ($tag): only the light profile skips the browser UI review"
  check_lacks "$f" 'and skip the optional browser UI review' \
    "T14.2 ($tag): the loop bullet no longer distributes that skip over both subjects"
  # (b) no reviewer spawn is saved on the clean path.
  check_has "$f" 'saves no reviewer spawn' \
    "T14.3 ($tag): SKILL.md states the collapse saves no reviewer spawn"
  check_has "$f" 'confirmation pass is itself fix-conditional' \
    "T14.4 ($tag): it states why — the confirmation pass only runs after a fix"
  check_lacks "$f" 'just not two|instead of two|rather than two' \
    "T14.5 ($tag): the false one-review-instead-of-two claim is gone"
  # (c) Step 4's trusted skip carries the soft-pass clause.
  trusted_skip="$(grep -E 'Under .qa_handoff = trusted., skip this step' "$f" | head -1 || true)"
  check_block_has "$trusted_skip" 'soft-pass conjunction therefore treats the test leg as satisfied' \
    "T14.6 ($tag): Step 4's trusted skip states the soft-pass clause"
  check_block_has "$trusted_skip" 'only against the \*\*live\*\* head' \
    "T14.7 ($tag): and binds it to the live head, not the marker's own head="
done

check_has "$SRC_LOOP" 'no browser-UI row, deliberately' \
  "T14.8: the skips table's browser omission is documented as deliberate"
SKIPS_TABLE_ROWS="$(printf '%s\n' "$SKIPS_BLOCK" | grep -E '^\|' || true)"
check_block_has "$SKIPS_TABLE_ROWS" '^\|[^|]*code UI review[^|]*\|' \
  "T14.9: (guard) the skips table rows were located and still hold the code UI leg"
check_block_lacks "$SKIPS_TABLE_ROWS" '^\|[^|]*browser[^|]*\|' \
  "T14.10: no table row skips a browser review under trusted"
check_has "$SRC_LOOP" 'saves no reviewer spawn' \
  "T14.11: the mechanics state the collapse saves no reviewer spawn"
check_has "$BUILT_LOOP" 'saves no reviewer spawn' \
  "T14.12: the built mechanics ship it"
check_has "$AP_PHASES" 'no reviewer spawn is saved' \
  "T14.13: auto-pilot's narration does not promise a saved spawn"
check_lacks "$AP_PHASES" 'full-strength review instead of two' \
  "T14.14: auto-pilot's old instead-of-two claim is gone"

# ───────────────────────────────────────────────────────────
# T15 (AC1/AC2): `ui=` is commit-bound exactly like `tests=`.
# The resolver's UI review runs BEFORE its QA cycles, so every QA
# fix commit — and the later documentation commit — lands after
# the diff that review saw. Without its own SHA, a `trusted`
# marker would skip pr-review's code UI review on a diff no
# ui-reviewer ever read. An unsuffixed `ui=` (an older marker) is
# well-formed, never malformed — it simply never permits the skip.
# ───────────────────────────────────────────────────────────
# Consumer: the field vocabulary and the skips table both require the SHA.
VOCAB_ROW="$(grep -E '^\| .ui=<none' "$SRC_LOOP" || true)"
check_block_has "$VOCAB_ROW" 'ui=<none\\\|code\\\|code\+browser>:<clean\\\|noted>@<sha40>' \
  "T15.1: the field vocabulary grammar for ui= carries an @<sha40>"
check_block_has "$VOCAB_ROW" '@<sha40>. equal to .head' \
  "T15.2: the skip requires that SHA to equal head"
check_block_has "$VOCAB_ROW" 'no .@<sha40>. suffix is well-formed but not commit-bound' \
  "T15.3: an unsuffixed ui= is well-formed, not malformed (back-compat)"
UI_SKIP_ROW="$(printf '%s\n' "$SKIPS_BLOCK" | grep -E '^\|[^|]*code UI review' || true)"
check_block_has "$UI_SKIP_ROW" '@<sha40>. present and equal to .head' \
  "T15.4: the skips table's code-UI row is conditioned on the ui= SHA"
check_block_has "$UI_SKIP_ROW" 'never on an unsuffixed .ui=' \
  "T15.5: an unsuffixed ui= never permits the code UI skip"
check_has "$SRC_LOOP" '\*before\* its QA cycles' \
  "T15.6: the rationale names the drift the SHA closes"
# The built consumer ships the same binding — a src-only contract installs nothing.
BUILT_UI_SKIP_ROW="$(awk '/^### What .trusted. skips/,/^### Never gated/' "$BUILT_LOOP" | grep -E '^\|[^|]*code UI review' || true)"
check_block_has "$BUILT_UI_SKIP_ROW" '@<sha40>. present and equal to .head' \
  "T15.7: the built mechanics ship the commit-bound code-UI condition"
# SKILL.md is read first and must carry the same condition, in src and built.
for pair in "src:$SRC_PR" "built:$BUILT_PR"; do
  tag="${pair%%:*}"
  f="${pair#*:}"
  ui_clause="$(grep -E 'the \*\*code\*\* UI review is skipped only when' "$f" | head -1 || true)"
  check_block_has "$ui_clause" 'carries an .@<sha40>. equal to .head' \
    "T15.8 ($tag): SKILL.md gates the code UI skip on the ui= SHA"
  check_block_has "$ui_clause" 'never on an unsuffixed .ui=' \
    "T15.9 ($tag): SKILL.md keeps an unsuffixed ui= unskippable"
done
# Producer: the grammar, the template line, and the derivation row all agree.
for pair in "src:$SRC_TEMPLATES" "built:$BUILT_TEMPLATES"; do
  tag="${pair%%:*}"
  f="${pair#*:}"
  check_has "$f" 'ui=<none\|code\|code\+browser>:<clean\|noted>@<sha40>' \
    "T15.10 ($tag): the producer grammar binds ui= to a SHA"
  check_has "$f" 'ui=\{ui_legs\}:\{ui_result\}@\{ui_sha\}' \
    "T15.11 ($tag): the PR body template emits that SHA"
  ui_row="$(grep -E '^\| .ui. \|' "$f" | head -1 || true)"
  check_block_has "$ui_row" '<legs>:<result>@<sha40>' \
    "T15.12 ($tag): the derivation row's value column carries the SHA"
  check_block_has "$ui_row" 'git rev-parse HEAD. at the moment it ran' \
    "T15.13 ($tag): derived from the commit the UI review actually ran against"
  check_block_has "$ui_row" 'never .head. by assumption' \
    "T15.14 ($tag): and never head by assumption"
done

# ───────────────────────────────────────────────────────────
# T16 (AC2): the parse grep matches any marker version, so the
# documented "a version other than v1 ⇒ stale" rule is reachable.
# A grep hard-pinned to v1 would make a v2 marker yield zero
# matches — i.e. `absent` — and that rule dead prose.
# ───────────────────────────────────────────────────────────
for pair in "src:$SRC_LOOP" "built:$BUILT_LOOP"; do
  tag="${pair%%:*}"
  f="${pair#*:}"
  grep_line="$(grep -E "grep -oE .<!-- gitissue:qa" "$f" | head -1 || true)"
  check_block_has "$grep_line" 'gitissue:qa v\[0-9\]\+ ' \
    "T16.1 ($tag): the parse grep matches any version, not just v1"
  check_has "$f" 'version other than .v1.' \
    "T16.2 ($tag): the version rule the wider grep feeds is still stated"
done
# The regexes must actually behave that way: v2 reaches the parser, v1 matches,
# and a non-marker comment does not.
PARSE_RE='<!-- gitissue:qa v[0-9]+ [^>]*-->'
V_OK=1
printf '%s\n' '<!-- gitissue:qa v2 head=abc review=clean -->' | grep -qE "$PARSE_RE" || V_OK=0
printf '%s\n' '<!-- gitissue:qa v1 head=abc review=clean -->' | grep -qE "$PARSE_RE" || V_OK=0
printf '%s\n' '<!-- gitissue:normalized v1 -->' | grep -qE "$PARSE_RE" && V_OK=0
if [ "$V_OK" = "1" ]; then
  pass "T16.3: the documented grep reaches a v2 marker and ignores other markers"
else
  fail "T16.3: the documented grep does not behave as the version rule requires"
fi

# ───────────────────────────────────────────────────────────
# T17 (F3/F4 narration + schema): auto-pilot's pre-pass line and
# the config schema tell the truth about what the marker changes.
# ───────────────────────────────────────────────────────────
check_has "$AP_PHASES" '^1\. \*\*Script pre-pass\*\*.*QA handoff marker' \
  "T17.1: auto-pilot's pre-pass narration qualifies its test run"
check_has "$AP_PROMPTS" 'script pre-pass first.*QA handoff marker' \
  "T17.2: the reviewer prompt qualifies the pre-pass test run too"
check_has "$SRC_CONFIG_SCHEMA" 'QA handoff gate' \
  "T17.3: the schema tells an operator adaptive_depth=false also disables the gate"

# ───────────────────────────────────────────────────────────
# T18 (producer, AC1/AC2): each SHA the marker carries has an
# anchored capture instruction at the step that produces it. A
# contract that says "write the SHA the suite actually ran
# against" without telling the agent to record it at that moment
# is unimplementable: by Deliver, HEAD has moved past both, and
# the only value still in reach is `head` — the exact assumption
# the contract forbids. Every capture therefore states the
# omit-rather-than-default fail-safe too.
# ───────────────────────────────────────────────────────────
SRC_PIPELINE="$REPO_ROOT/src/skills/issue-resolver/references/pipeline-steps.md"
BUILT_PIPELINE="$REPO_ROOT/skills/issue-resolver/references/pipeline-steps.md"
for f in "$SRC_PIPELINE" "$BUILT_PIPELINE"; do
  if [ -f "$f" ]; then
    pass "T18.0: exists: ${f#$REPO_ROOT/}"
  else
    fail "T18.0: missing: ${f#$REPO_ROOT/}"
  fi
done

for pair in "src:$SRC_PIPELINE" "built:$BUILT_PIPELINE"; do
  tag="${pair%%:*}"
  f="${pair#*:}"
  # tests_sha — captured in the QA loop's Run tests item, before the
  # documentation commit that would otherwise make it unrecoverable.
  qa_block="$(awk '/^## Step 4 — QA/,/^### Step 4 — UI\/UX review/' "$f")"
  check_block_has "$qa_block" 'tests_sha. = .git rev-parse HEAD' \
    "T18.1 ($tag): the QA loop captures tests_sha with an explicit command"
  check_block_has "$qa_block" 'at the moment the suite runs' \
    "T18.2 ($tag): the capture is anchored to when the suite runs"
  check_block_has "$qa_block" 'omit the whole .tests=. field; never substitute' \
    "T18.3 ($tag): an uncaptured tests_sha omits the field instead of defaulting"
  # ui_sha — captured where the ui-reviewer is spawned, which precedes the QA
  # cycles, so every fix commit those cycles produce lands after it.
  ui_block="$(awk '/^### Step 4 — UI\/UX review/,/^## Edge Cases/' "$f")"
  check_block_has "$ui_block" 'ui_sha. = .git rev-parse HEAD' \
    "T18.4 ($tag): the UI review sub-step captures ui_sha with an explicit command"
  check_block_has "$ui_block" 'ui-reviewer is spawned\*\*' \
    "T18.5 ($tag): the capture is anchored to the ui-reviewer spawn"
  check_block_has "$ui_block" 'omit the .@<sha40>. suffix; never' \
    "T18.6 ($tag): an uncaptured ui_sha omits the suffix instead of defaulting"
  check_block_has "$ui_block" 'Browser gate config key' \
    "T18.7 ($tag): (guard) the UI review sub-step block was actually located"
done

# The producer contract points at both capture sites rather than restating them,
# and repeats the fail-safe where the value is written.
for pair in "src:$SRC_TEMPLATES" "built:$BUILT_TEMPLATES"; do
  tag="${pair%%:*}"
  f="${pair#*:}"
  tests_row="$(grep -E '^\| .tests. \|' "$f" | head -1 || true)"
  ui_row="$(grep -E '^\| .ui. \|' "$f" | head -1 || true)"
  check_block_has "$tests_row" 'references/pipeline-steps\.md' \
    "T18.8 ($tag): the tests= row points at its capture site"
  check_block_has "$tests_row" 'when no capture was recorded' \
    "T18.9 ($tag): and omits the field when nothing was captured"
  check_block_has "$ui_row" 'references/pipeline-steps\.md' \
    "T18.10 ($tag): the ui= row points at its capture site"
  check_block_has "$ui_row" 'whenever no capture was recorded' \
    "T18.11 ($tag): and omits the suffix when nothing was captured"
done

# ───────────────────────────────────────────────────────────
# T19 (release record): the CHANGELOG entry documents the grammar
# that actually ships, SHA binding included.
# ───────────────────────────────────────────────────────────
CHANGELOG="$REPO_ROOT/CHANGELOG.md"
CL_ENTRY="$(grep -E 'add a QA handoff marker so' "$CHANGELOG" | head -1 || true)"
check_block_has "$CL_ENTRY" 'ui=<none\|code\|code\+browser>:<clean\|noted>@<sha40>' \
  "T19.1: the changelog grammar carries the ui= SHA"
check_block_has "$CL_ENTRY" 'its own .@<sha40>. equals .head' \
  "T19.2: it states the code-UI skip requires that SHA to equal head"
check_block_has "$CL_ENTRY" 'unsuffixed .ui=. stays parsable but is never skippable' \
  "T19.3: and that an unsuffixed ui= is parsable but never skippable"

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
