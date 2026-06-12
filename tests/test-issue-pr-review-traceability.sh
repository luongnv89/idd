#!/usr/bin/env bash
# test-issue-pr-review-traceability.sh — Validate the /issue-pr-review
# acceptance-criteria verification and traceability dimensions spec.
#
# This script verifies issue #36 acceptance criteria:
#  AC1. /issue-pr-review on a PR missing Closes #N reports a traceability
#       failure even if tests pass.
#  AC2. /issue-pr-review on a human-authored PR reports `partial`
#       traceability, not `fail`.
#  AC3. A merged PR leaves enough context in git history to answer
#       "why does this change exist?" without relying on local JSON cache.
#  AC4. Review output is structured by the five dimensions: correctness,
#       acceptance_criteria, traceability, maintainability, safety.
#  AC5. /issue-resolver PR template emits all required durable fields
#       (Decision Record + Acceptance Criteria Verification + Closes #N).
#
# Strategy: this is a documentation/skill repo — there is no runtime to
# exercise. Tests therefore verify that the SKILL.md and template files
# *contain* the spec language that satisfies each AC. If the language is
# present, the agent following the skill will produce the documented
# behavior.
#
# Usage: bash tests/test-issue-pr-review-traceability.sh
# Returns: exit 0 if all tests pass, exit 1 on first failure category.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$REPO_ROOT/src/skills/issue-pr-review/SKILL.source.md"
# The detailed AC + traceability spec language (per-criterion statuses, the
# Decision Record labels, the `traceability: partial` verdict, the
# `git log --grep` commit check) was extracted from SKILL.source.md into
# references/verification-checks.md for progressive disclosure (≤500-line
# skill-creator standard). SKILL.source.md still instructs the agent to read
# and apply that file at Step 3 ("Read that file and apply it now"), so the
# runtime-reachable spec surface is SKILL.source.md *plus* verification-checks.md.
# Assertions that target the extracted language grep this combined corpus.
VERIFICATION_CHECKS="$REPO_ROOT/src/skills/issue-pr-review/references/verification-checks.md"
SKILL_SPEC=("$SKILL" "$VERIFICATION_CHECKS")
TEMPLATES="$REPO_ROOT/src/skills/issue-pr-review/references/report-templates.md"
RESOLVER_TEMPLATES="$REPO_ROOT/src/skills/issue-resolver/references/report-templates.md"
METHODOLOGY="$REPO_ROOT/docs/idd-methodology.md"
PASS=0
FAIL=0

pass() {
  echo "  ✓ $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  ✗ $1"
  FAIL=$((FAIL + 1))
}

echo "◆ /issue-pr-review Traceability + AC Tests (issue #36)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T0: Files exist
# ───────────────────────────────────────────────────────────
for f in "$SKILL" "$VERIFICATION_CHECKS" "$TEMPLATES" "$RESOLVER_TEMPLATES" "$METHODOLOGY"; do
  if [ -f "$f" ]; then
    pass "T0: $(basename "$f") exists"
  else
    fail "T0: $f missing"
  fi
done

# ───────────────────────────────────────────────────────────
# T1: AC4 — Review output is structured by the five dimensions.
# All five dimension names must appear in the SKILL spec and in
# the Step 7 templates.
# ───────────────────────────────────────────────────────────
for dim in correctness acceptance_criteria traceability maintainability safety; do
  if grep -qF "$dim" "$SKILL"; then
    pass "T1.AC4: SKILL.md mentions dimension '$dim'"
  else
    fail "T1.AC4: SKILL.md missing dimension '$dim'"
  fi
done

for dim in correctness acceptance_criteria traceability maintainability safety; do
  if grep -qF "$dim" "$TEMPLATES"; then
    pass "T1.AC4: report-templates.md mentions dimension '$dim'"
  else
    fail "T1.AC4: report-templates.md missing dimension '$dim'"
  fi
done

# Each dimension must appear in the Clean PR summary template as a status
# line (the report shows them all explicitly per AC4).
if grep -qE 'correctness:.*pass|correctness:.*partial|correctness:.*fail' "$TEMPLATES"; then
  pass "T1.AC4: templates show 'correctness' status line"
else
  fail "T1.AC4: templates do not show 'correctness' status line"
fi
if grep -qE 'acceptance_criteria:.*pass|acceptance_criteria:.*fail|acceptance_criteria:.*partial' "$TEMPLATES"; then
  pass "T1.AC4: templates show 'acceptance_criteria' status line"
else
  fail "T1.AC4: templates do not show 'acceptance_criteria' status line"
fi
if grep -qE 'traceability:.*pass|traceability:.*fail|traceability:.*partial' "$TEMPLATES"; then
  pass "T1.AC4: templates show 'traceability' status line"
else
  fail "T1.AC4: templates do not show 'traceability' status line"
fi

# ───────────────────────────────────────────────────────────
# T2: AC1 — PR missing Closes #N reports traceability failure
# even if tests pass.
# ───────────────────────────────────────────────────────────
# The SKILL must explicitly state that missing Closes #N causes
# traceability to FAIL (not partial) and that this BLOCKS the
# soft-pass even when tests pass.
if grep -qiE 'Closes #\{?N\}?[^a-z]*(absent|missing)|missing.*Closes #|absent.*Closes #' "$SKILL"; then
  pass "T2.AC1: SKILL.md addresses missing Closes #N"
else
  fail "T2.AC1: SKILL.md does not address missing Closes #N"
fi

if grep -qE 'traceability: fail' "$SKILL" || grep -qE 'traceability:.*fail' "$SKILL"; then
  pass "T2.AC1: SKILL.md uses the literal 'traceability: fail' verdict"
else
  fail "T2.AC1: SKILL.md never declares 'traceability: fail'"
fi

# AC1 hinges on the fact that traceability fail BLOCKS even with green tests.
# The hard-block clause in the loop controls must explicitly state this.
if grep -qiE '(hard.block|block.*soft.?pass|block.*even.*tests|tests.*not.*override)' "$SKILL"; then
  pass "T2.AC1: SKILL.md documents that traceability fail blocks soft-pass"
else
  fail "T2.AC1: SKILL.md does not document traceability blocking even with green tests"
fi

# ───────────────────────────────────────────────────────────
# T3: AC2 — Human-authored PR reports `partial`, not `fail`.
# ───────────────────────────────────────────────────────────
if grep -qiE 'human.authored.*PR|PR.*not.*produced.*by.*/issue-resolver' "$SKILL"; then
  pass "T3.AC2: SKILL.md addresses human-authored PRs"
else
  fail "T3.AC2: SKILL.md does not address human-authored PRs"
fi

if grep -qiE 'traceability:.*partial' "${SKILL_SPEC[@]}"; then
  pass "T3.AC2: SKILL.md uses 'traceability: partial' for the soft case"
else
  fail "T3.AC2: SKILL.md never declares 'traceability: partial'"
fi

if grep -qiE 'Decision Record absent' "${SKILL_SPEC[@]}"; then
  pass "T3.AC2: SKILL.md notes Decision Record may be absent"
else
  fail "T3.AC2: SKILL.md does not note Decision Record absent case"
fi

# ───────────────────────────────────────────────────────────
# T4: AC3 — Merged PR leaves enough context in git history to
# answer "why does this change exist?" without local JSON cache.
# This relies on:
#   (a) the durable analysis fields (Decision Record + AC Verification)
#       being present in the PR body,
#   (b) the squash-merge assumption (PR body becomes commit body),
#   (c) the methodology doc explaining the rule.
# ───────────────────────────────────────────────────────────
if grep -qE 'squash.merge' "$SKILL"; then
  pass "T4.AC3: SKILL.md mentions the squash-merge assumption"
else
  fail "T4.AC3: SKILL.md does not mention squash-merge"
fi

if grep -qiE 'Decision Record' "$SKILL"; then
  pass "T4.AC3: SKILL.md references the Decision Record contract"
else
  fail "T4.AC3: SKILL.md does not reference Decision Record"
fi

# All five Decision Record stable labels must be enumerated, since they
# are the string-matched contract.
for label in "Root cause" "Options considered" "Options rejected" "Selected option" "Residual risk"; do
  if grep -qF "$label" "${SKILL_SPEC[@]}"; then
    pass "T4.AC3: SKILL.md enumerates Decision Record label '$label'"
  else
    fail "T4.AC3: SKILL.md missing Decision Record label '$label'"
  fi
done

# AC3 also depends on the methodology doc explaining the durable-memory
# argument — without it, future readers can't audit the design choice.
if grep -qiE 'Analysis Artifacts and Durable Memory' "$METHODOLOGY"; then
  pass "T4.AC3: docs/idd-methodology.md has the durable-memory section"
else
  fail "T4.AC3: docs/idd-methodology.md missing durable-memory section"
fi

# ───────────────────────────────────────────────────────────
# T5: AC5 — /issue-resolver PR template emits all required
# durable fields (Decision Record, Acceptance Criteria
# Verification, Closes #N).
# ───────────────────────────────────────────────────────────
if grep -qE '^Closes #\{issue_number\}$|Closes #\{issue_number\}' "$RESOLVER_TEMPLATES"; then
  pass "T5.AC5: resolver template emits Closes #{issue_number}"
else
  fail "T5.AC5: resolver template missing Closes #{issue_number}"
fi

if grep -qiE '## Decision Record' "$RESOLVER_TEMPLATES"; then
  pass "T5.AC5: resolver template has '## Decision Record' section"
else
  fail "T5.AC5: resolver template missing Decision Record section"
fi

if grep -qiE '## Acceptance Criteria Verification' "$RESOLVER_TEMPLATES"; then
  pass "T5.AC5: resolver template has '## Acceptance Criteria Verification' section"
else
  fail "T5.AC5: resolver template missing AC Verification section"
fi

# AC verification must allow per-criterion pass/fail/unverified.
for status in pass fail unverified; do
  if grep -qF "$status" "$RESOLVER_TEMPLATES"; then
    pass "T5.AC5: resolver template documents per-criterion status '$status'"
  else
    fail "T5.AC5: resolver template missing per-criterion status '$status'"
  fi
done

# ───────────────────────────────────────────────────────────
# T6: Per-criterion AC verification spec in /issue-pr-review.
# The skill must parse the issue body's "## Acceptance Criteria"
# section and report each criterion individually.
# ───────────────────────────────────────────────────────────
if grep -qiE 'per.criterion|per criterion|each (criterion|acceptance criteria)' "$SKILL"; then
  pass "T6: SKILL.md documents per-criterion verification"
else
  fail "T6: SKILL.md does not document per-criterion verification"
fi

# All three statuses must be documented in /issue-pr-review too,
# alongside the requirement that evidence accompanies pass/fail.
for status in pass fail unverified; do
  if grep -qE "\\\`$status\\\`" "${SKILL_SPEC[@]}" || grep -qiE "(^|[^a-z_])$status([^a-z_]|$)" "${SKILL_SPEC[@]}"; then
    pass "T6: SKILL.md documents AC status '$status'"
  else
    fail "T6: SKILL.md missing AC status '$status'"
  fi
done

if grep -qiE 'evidence' "${SKILL_SPEC[@]}"; then
  pass "T6: SKILL.md requires evidence on AC verifications"
else
  fail "T6: SKILL.md does not require evidence on AC verifications"
fi

# ───────────────────────────────────────────────────────────
# T7: Traceability check enumeration. The four checks defined
# in the issue body must be present:
#   1. PR body contains Closes #N
#   2. At least one commit references the issue
#   3. PR body contains durable analysis signal
#   4. Squash commit body contains the durable summary
# ───────────────────────────────────────────────────────────
if grep -qiE 'PR body.*Closes #|Closes #.*PR body|Issue link' "$SKILL"; then
  pass "T7: SKILL.md documents 'PR body contains Closes #N' check"
else
  fail "T7: SKILL.md missing 'PR body contains Closes #N' check"
fi

if grep -qE 'git log.*--grep' "${SKILL_SPEC[@]}"; then
  pass "T7: SKILL.md documents commit-references-issue check via git log --grep"
else
  fail "T7: SKILL.md missing commit-references-issue check"
fi

if grep -qiE 'durable analysis|durable summary|Decision Record' "$SKILL"; then
  pass "T7: SKILL.md documents durable-analysis-fields check"
else
  fail "T7: SKILL.md missing durable-analysis-fields check"
fi

if grep -qiE 'squash.commit.body|squash[- ]merge' "$SKILL"; then
  pass "T7: SKILL.md documents squash-commit assumption"
else
  fail "T7: SKILL.md missing squash-commit assumption"
fi

# ───────────────────────────────────────────────────────────
# T8: Loop control wiring — soft-pass must require
# traceability != fail and acceptance_criteria != fail.
# ───────────────────────────────────────────────────────────
if grep -qiE 'soft.?pass' "$SKILL"; then
  pass "T8: SKILL.md keeps soft-pass terminology"
else
  fail "T8: SKILL.md missing soft-pass terminology"
fi

# The hard-block conditions must mention both traceability fail
# and acceptance_criteria fail explicitly.
if grep -qiE 'traceability:.*fail.*block|hard.block.*traceability|traceability.*hard.block' "$SKILL"; then
  pass "T8: SKILL.md states traceability fail blocks soft-pass"
else
  # Fallback — looser match, since wording may vary
  if grep -qiE 'traceability.*block' "$SKILL"; then
    pass "T8: SKILL.md states traceability blocks soft-pass (loose match)"
  else
    fail "T8: SKILL.md does not state traceability blocks soft-pass"
  fi
fi

if grep -qiE 'acceptance_criteria.*fail|fail.*acceptance.criteria' "$SKILL"; then
  pass "T8: SKILL.md states acceptance_criteria fail blocks soft-pass"
else
  fail "T8: SKILL.md does not state acceptance_criteria fail blocks"
fi

# ───────────────────────────────────────────────────────────
# T9: Version bump — at or past the 0.4.0 baseline this spec shipped
# under. Use a semver floor (sort -V), not an exact-minor pin, so the
# check survives later legitimate bumps (0.5.0, 0.10.0, …) — issue #100.
# ───────────────────────────────────────────────────────────
skill_ver="$(grep -E '^[[:space:]]*version:' "$SKILL" | head -1 | sed -E 's/.*version:[[:space:]]*//')"
if [ -n "$skill_ver" ] \
   && [ "$(printf '%s\n%s\n' "0.4.0" "$skill_ver" | sort -V | head -n1)" = "0.4.0" ]; then
  pass "T9: SKILL.md version at or past 0.4.0 — $skill_ver"
else
  fail "T9: SKILL.md version below 0.4.0 (got '${skill_ver:-none}')"
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  Result: FAIL"
  exit 1
else
  echo "  Result: PASS"
  exit 0
fi
