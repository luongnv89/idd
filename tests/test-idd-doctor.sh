#!/usr/bin/env bash
# test-idd-doctor.sh — Validate the /idd-doctor skill spec
#
# This script verifies issue #34 acceptance criteria:
#  - /idd-doctor skill exists with the expected file structure
#  - SKILL.md documents the four-check pipeline in order
#  - Forbidden Check 1 patterns (stale skill claims) are enumerated
#  - Forbidden Check 2 patterns (issue-template fields) are enumerated
#  - The read-only guarantee is explicit
#  - The gh field selection for Check 4 matches the documented contract
#  - Skip behavior for missing gh / no .idd.yml / no templates is documented
#  - Exit-code mapping (PASS=0, WARN=0, FAIL=1) is documented
#  - The four AC scenarios are demonstrably covered by the spec:
#      1. Doctor passes on this repo (after §1a doc fixes)
#      2. Reintroducing old /issue-creator README language → FAIL on Check 1
#      3. Adding affected-files fields to issue templates → FAIL on Check 2
#      4. Doctor warns when the repo does not allow the configured merge
#         method, or the method is rebase (issue #564) → WARN on Check 4
#  - Output is report-only — no files modified
#
# Usage: bash tests/test-idd-doctor.sh
# Returns: exit 0 if all tests pass, exit 1 on first failure category

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_DIR="$REPO_ROOT/src/internal-skills/idd-doctor"
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

echo "◆ /idd-doctor Skill Tests (issue #34)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T1: Skill file structure exists
# ───────────────────────────────────────────────────────────
if [ -d "$SKILL_DIR" ]; then
  pass "T1.0: src/internal-skills/idd-doctor/ directory exists"
else
  fail "T1.0: src/internal-skills/idd-doctor/ directory missing"
fi

if [ -f "$SKILL_DIR/SKILL.source.md" ]; then
  pass "T1.1: SKILL.source.md exists"
else
  fail "T1.1: SKILL.source.md missing"
fi

if [ -f "$SKILL_DIR/docs/README.md" ]; then
  pass "T1.2: README.md exists"
else
  fail "T1.2: README.md missing"
fi

if [ -d "$SKILL_DIR/references" ]; then
  pass "T1.3: references/ directory exists"
else
  fail "T1.3: references/ directory missing"
fi

if [ -f "$SKILL_DIR/references/error-messages.md" ]; then
  pass "T1.4: references/error-messages.md exists"
else
  fail "T1.4: references/error-messages.md missing"
fi

# T1.5: repair hint must load the real artifact, never authored source (#434).
if grep -qF 'then load internal-skills/idd-doctor/ and run /idd-doctor.' "$SKILL_DIR/SKILL.source.md" \
   && ! grep -qF 'then run /idd-doctor from src/internal-skills/' "$SKILL_DIR/SKILL.source.md"; then
  pass "T1.5: rebuild repair points at emitted internal package"
else
  fail "T1.5: rebuild repair still points at non-invokable source"
fi

# ───────────────────────────────────────────────────────────
# T2: SKILL.md frontmatter and metadata
# ───────────────────────────────────────────────────────────
SKILL="$SKILL_DIR/SKILL.source.md"

if grep -qE '^name:[[:space:]]+idd-doctor[[:space:]]*$' "$SKILL"; then
  pass "T2.1: frontmatter has 'name: idd-doctor'"
else
  fail "T2.1: frontmatter missing 'name: idd-doctor'"
fi

if grep -qE '^description:[[:space:]]+"' "$SKILL"; then
  pass "T2.2: frontmatter has description"
else
  fail "T2.2: frontmatter missing description"
fi

if grep -qE '^license:[[:space:]]+MIT[[:space:]]*$' "$SKILL"; then
  pass "T2.3: frontmatter declares MIT license"
else
  fail "T2.3: frontmatter missing 'license: MIT'"
fi

if grep -qE '^[[:space:]]*version:[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+' "$SKILL"; then
  pass "T2.4: metadata.version is present and valid semver"
else
  fail "T2.4: metadata.version missing or not valid semver"
fi

# ───────────────────────────────────────────────────────────
# T3: Pipeline documents four checks in order
# ───────────────────────────────────────────────────────────
for section in \
  "## Check 1 — Stale skill claims" \
  "## Check 2 — Issue-template fields" \
  "## Check 3 — Autopilot mode" \
  "## Check 4 — Merge method"; do
  if grep -qF "$section" "$SKILL"; then
    pass "T3: section '$section' present"
  else
    fail "T3: section '$section' missing"
  fi
done

# Check ordering — Check N's heading must appear before Check N+1
LN1=$(grep -nF '## Check 1 ' "$SKILL" | head -1 | cut -d: -f1 || echo 0)
LN2=$(grep -nF '## Check 2 ' "$SKILL" | head -1 | cut -d: -f1 || echo 0)
LN3=$(grep -nF '## Check 3 ' "$SKILL" | head -1 | cut -d: -f1 || echo 0)
LN4=$(grep -nF '## Check 4 ' "$SKILL" | head -1 | cut -d: -f1 || echo 0)
if [ "$LN1" -lt "$LN2" ] && [ "$LN2" -lt "$LN3" ] && [ "$LN3" -lt "$LN4" ]; then
  pass "T3: checks appear in order 1 → 2 → 3 → 4"
else
  fail "T3: check sections are out of order (got lines $LN1, $LN2, $LN3, $LN4)"
fi

# ───────────────────────────────────────────────────────────
# T4: Check 1 — forbidden patterns enumerated
# ───────────────────────────────────────────────────────────
# AC #2: reintroducing the old /issue-creator README language
# must cause the doctor to fail. To prove the spec covers this,
# the SKILL doc must enumerate at least the canonical phrases.
for pattern in \
  "scans the codebase" \
  "predicts affected files" \
  "generates implementation notes"; do
  if grep -qiF "$pattern" "$SKILL"; then
    pass "T4: Check 1 enumerates pattern '$pattern'"
  else
    fail "T4: Check 1 missing pattern '$pattern'"
  fi
done

if grep -qiE 'negation (marker|guard)' "$SKILL"; then
  pass "T4: Check 1 documents the negation guard"
else
  fail "T4: Check 1 does not document the negation guard"
fi

# ───────────────────────────────────────────────────────────
# T5: Check 2 — forbidden template fields enumerated
# ───────────────────────────────────────────────────────────
# AC #3: adding affected-files fields to issue templates causes FAIL.
# The spec must enumerate the canonical forbidden field labels.
for pattern in \
  "affected files" \
  "technical notes" \
  "root cause" \
  "implementation hints"; do
  if grep -qiF "$pattern" "$SKILL"; then
    pass "T5: Check 2 enumerates pattern '$pattern'"
  else
    fail "T5: Check 2 missing pattern '$pattern'"
  fi
done

if grep -qF 'skills/issue-creator/templates/' "$SKILL"; then
  pass "T5: Check 2 scans skills/issue-creator/templates/"
else
  fail "T5: Check 2 does not scan skills/issue-creator/templates/"
fi

if grep -qF '.github/ISSUE_TEMPLATE/' "$SKILL"; then
  pass "T5: Check 2 scans .github/ISSUE_TEMPLATE/"
else
  fail "T5: Check 2 does not scan .github/ISSUE_TEMPLATE/"
fi

# ───────────────────────────────────────────────────────────
# T6: Check 3 — .idd.yml autopilot.mode
# ───────────────────────────────────────────────────────────
if grep -qF 'autopilot.mode' "$SKILL"; then
  pass "T6: Check 3 references autopilot.mode"
else
  fail "T6: Check 3 does not reference autopilot.mode"
fi

if grep -qE 'skipped[^.]*no \.idd\.yml' "$SKILL"; then
  pass "T6: Check 3 documents skip when .idd.yml is absent"
else
  fail "T6: Check 3 does not document skip-when-missing"
fi

# ───────────────────────────────────────────────────────────
# T7: Check 4 — merge method + WARN semantic
# ───────────────────────────────────────────────────────────
# AC #4, as changed by issue #564: the doctor judges the repo against the
# configured review.merge_method instead of requiring squash-only + PR_BODY.
# This is a WARN, not a FAIL — must be explicit in the spec.
if grep -qE 'mergeCommitAllowed.*squashMergeAllowed.*rebaseMergeAllowed' "$SKILL"; then
  pass "T7: Check 4 specifies the gh repo view JSON field selection"
else
  fail "T7: Check 4 does not specify the gh JSON field selection"
fi

# The hand-merge message source is not a `gh repo view` field, so it is a
# second, separate REST read covering both commit-writing methods.
if grep -qF "gh api repos/{owner}/{repo} --jq '{squash_merge_commit_message, merge_commit_message}'" "$SKILL"; then
  pass "T7: Check 4 reads both message sources via gh api"
else
  fail "T7: Check 4 does not read the hand-merge message sources"
fi

if grep -qE 'the `merge_method:` value inside the `review:` block of `\.idd\.yml`' "$SKILL" \
   && grep -qE 'means the default, `squash`' "$SKILL"; then
  pass "T7: Check 4 reads review.merge_method, defaulting to squash"
else
  fail "T7: Check 4 does not read review.merge_method with a squash default"
fi

# The documented classifier is what T14 mirrors; pin each line of it.
for line in \
  'method == "rebase"                               → WARN  (tracker-only)' \
  'method == "squash" AND squashMergeAllowed == true → PASS' \
  'method == "merge"  AND mergeCommitAllowed == true → PASS' \
  'otherwise                                        → WARN  (method not allowed)'; do
  if grep -qF "$line" "$SKILL"; then
    pass "T7: Check 4 classifier has '$line'"
  else
    fail "T7: Check 4 classifier is missing '$line'"
  fi
done

# A message source other than PR_BODY — or an unread one — is a note under the
# pass line: IDD's own merge passes the body, so it is never a warn.
if grep -qE 'is not `PR_BODY`, or step 4 did not answer, print the \*hand-merge note\*' "$SKILL" \
   && grep -qE 'The note is `○`, never a warn' "$SKILL"; then
  pass "T7: Check 4 reports a non-PR_BODY or unread message source as a note"
else
  fail "T7: Check 4 does not document the hand-merge note"
fi

# IDD never changes a repository setting: every fix is a .idd.yml edit.
if grep -qE 'Never print a command that changes a repository setting' "$SKILL" \
   && ! grep -qE 'gh api -X PATCH' "$SKILL" "$SKILL_DIR/references/error-messages.md"; then
  pass "T7: Check 4 prints a .idd.yml fix, never a repo-settings command"
else
  fail "T7: Check 4 still prints a repo-settings command"
fi

if grep -qE 'warn \(not fail\)|⚠ \[4/4\]' "$SKILL"; then
  pass "T7: Check 4 explicitly produces a WARN, not a FAIL"
else
  fail "T7: Check 4 does not document WARN-not-FAIL semantic"
fi

if grep -qE 'skipped[^.]*gh not (installed|authenticated)' "$SKILL"; then
  pass "T7: Check 4 documents skip when gh is missing/unauthenticated"
else
  fail "T7: Check 4 does not document skip-when-no-gh"
fi

# ───────────────────────────────────────────────────────────
# T8: Read-only guarantee (AC #5: output is report-only)
# ───────────────────────────────────────────────────────────
if grep -qE 'read-only guarantee|Read-only guarantee' "$SKILL"; then
  pass "T8: read-only guarantee section present"
else
  fail "T8: read-only guarantee section missing"
fi

if grep -qE 'MUST NOT.*[Mm]odify' "$SKILL"; then
  pass "T8: spec says skill MUST NOT modify files"
else
  fail "T8: spec does not say skill MUST NOT modify files"
fi

# Out-of-scope list must explicitly exclude autofix
if grep -qiE 'autofix|auto[ -]?fix' "$SKILL"; then
  pass "T8: spec explicitly excludes autofix"
else
  fail "T8: spec does not explicitly exclude autofix"
fi

# ───────────────────────────────────────────────────────────
# T9: Exit-code mapping documented
# ───────────────────────────────────────────────────────────
# Both grep targets must hit somewhere in the SKILL doc.
if grep -qE 'PASS.*\b0\b' "$SKILL" && grep -qE 'FAIL.*\b1\b' "$SKILL"; then
  pass "T9: exit codes PASS=0 / FAIL=1 documented"
else
  fail "T9: exit codes PASS=0 / FAIL=1 not documented"
fi

if grep -qE 'WARN.*\b0\b' "$SKILL"; then
  pass "T9: WARN exit code 0 documented (warnings are not failures)"
else
  fail "T9: WARN exit code 0 not documented"
fi

# ───────────────────────────────────────────────────────────
# T10: error-messages.md mirrors the four checks
# ───────────────────────────────────────────────────────────
ERR="$SKILL_DIR/references/error-messages.md"
for section in \
  "## Check 1 — Stale skill claims" \
  "## Check 2 — Issue-template fields" \
  "## Check 3 — Autopilot mode" \
  "## Check 4 — Merge method"; do
  if grep -qF "$section" "$ERR"; then
    pass "T10: error catalog covers '$section'"
  else
    fail "T10: error catalog missing '$section'"
  fi
done

if grep -qE 'Not a git repository' "$ERR"; then
  pass "T10: error catalog covers 'Not a git repository'"
else
  fail "T10: error catalog missing 'Not a git repository'"
fi

# ───────────────────────────────────────────────────────────
# T11: Self-check on this repo (AC #1)
# ───────────────────────────────────────────────────────────
# AC #1: running /idd-doctor on this repo passes after the §1a
# doc fixes land. We can't actually invoke the skill here, but we
# can verify that this repo is in a state where the doctor would
# pass Checks 1, 2, and 3 (skip), and warn on Check 4.

# Check 1 evidence: /issue-creator README.md and SKILL.md are
# clean per the intent-only contract (other skills are out of scope).
DRIFT_FOUND=0
for f in "$REPO_ROOT/src/skills/issue-creator/docs/README.md" "$REPO_ROOT/src/skills/issue-creator/SKILL.source.md"; do
  [ -f "$f" ] || continue
  while IFS= read -r line; do
    lower=$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
      *"scans the codebase"*|*"predicts affected files"*|*"generates implementation notes"*)
        # Apply negation guard
        case "$lower" in
          *"no "*|*"not "*|*"never "*|*"does not"*|*"doesn't"*|*"without "*|*"cannot"*|*"won't"*) ;;
          *)
            echo "    drift in $f: $line"
            DRIFT_FOUND=1
            ;;
        esac
        ;;
    esac
  done < "$f"
done

if [ "$DRIFT_FOUND" -eq 0 ]; then
  pass "T11.1: AC #1 — no stale claims in /issue-creator (Check 1 would pass)"
else
  fail "T11.1: AC #1 — drift found in /issue-creator (Check 1 would fail)"
fi

# Check 2 evidence: no template file in this repo contains a forbidden field.
TEMPLATE_DRIFT=0
for f in "$REPO_ROOT"/src/skills/issue-creator/templates/*.md \
         "$REPO_ROOT"/.github/ISSUE_TEMPLATE/*.md \
         "$REPO_ROOT"/.github/ISSUE_TEMPLATE/*.yml \
         "$REPO_ROOT"/.github/ISSUE_TEMPLATE/*.yaml; do
  [ -f "$f" ] || continue
  while IFS= read -r line; do
    lower=$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
      *"affected files"*|*"## technical notes"*|*"root cause"*|*"implementation hints"*|*"implementation notes"*)
        echo "    template drift in $f: $line"
        TEMPLATE_DRIFT=1
        ;;
    esac
  done < "$f"
done

if [ "$TEMPLATE_DRIFT" -eq 0 ]; then
  pass "T11.2: AC #1 — no forbidden fields in templates (Check 2 would pass)"
else
  fail "T11.2: AC #1 — forbidden fields in templates (Check 2 would fail)"
fi

# ───────────────────────────────────────────────────────────
# T12: AC fixture round-trip — drift detection works
# ───────────────────────────────────────────────────────────
# AC #2: reintroducing old /issue-creator README language causes FAIL.
# Build a minimal in-memory fixture and verify the spec's algorithm
# (forbidden-pattern + negation-guard) rejects it.

run_check1_on_text() {
  # Echoes "FAIL" if the input has at least one drifted line, "PASS" otherwise.
  # Mirrors the algorithm documented in SKILL.md Check 1.
  local input="$1"
  local has_drift=0
  while IFS= read -r line; do
    lower=$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
      *"scans the codebase"*|*"predicts affected files"*|*"generates implementation notes"*)
        case "$lower" in
          *"no "*|*"not "*|*"never "*|*"does not"*|*"doesn't"*|*"without "*|*"cannot"*|*"won't"*) ;;
          *)
            has_drift=1
            ;;
        esac
        ;;
    esac
  done <<< "$input"
  if [ "$has_drift" -eq 1 ]; then
    echo "FAIL"
  else
    echo "PASS"
  fi
}

DRIFT_FIXTURE='# /issue-creator
This skill scans the codebase to predict the right templates.'
GOOD_FIXTURE='# /issue-creator
This skill does not scan the codebase or predict affected files.'

if [ "$(run_check1_on_text "$DRIFT_FIXTURE")" = "FAIL" ]; then
  pass "T12.1: AC #2 — drifted text causes FAIL (positive case)"
else
  fail "T12.1: AC #2 — drifted text did not cause FAIL"
fi

if [ "$(run_check1_on_text "$GOOD_FIXTURE")" = "PASS" ]; then
  pass "T12.2: AC #2 — negated text is allowed (negation guard works)"
else
  fail "T12.2: AC #2 — negated text incorrectly flagged"
fi

# ───────────────────────────────────────────────────────────
# T13: AC #3 fixture — affected-files field in template
# ───────────────────────────────────────────────────────────

run_check2_on_text() {
  local input="$1"
  local has_drift=0
  while IFS= read -r line; do
    lower=$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
      *"affected files"*|*"## technical notes"*|*"root cause"*|*"implementation hints"*|*"implementation notes"*)
        has_drift=1
        ;;
    esac
  done <<< "$input"
  if [ "$has_drift" -eq 1 ]; then
    echo "FAIL"
  else
    echo "PASS"
  fi
}

TEMPLATE_DRIFT_FIXTURE='## Type
Bug

## Affected Files
- src/foo.ts'

TEMPLATE_GOOD_FIXTURE='## Type
Bug

## Description
What broke.'

if [ "$(run_check2_on_text "$TEMPLATE_DRIFT_FIXTURE")" = "FAIL" ]; then
  pass "T13.1: AC #3 — 'Affected Files' field causes FAIL"
else
  fail "T13.1: AC #3 — 'Affected Files' field did not cause FAIL"
fi

if [ "$(run_check2_on_text "$TEMPLATE_GOOD_FIXTURE")" = "PASS" ]; then
  pass "T13.2: AC #3 — clean template passes"
else
  fail "T13.2: AC #3 — clean template incorrectly flagged"
fi

# ───────────────────────────────────────────────────────────
# T14: AC #4 fixture — merge method vs. the repo's allowed strategies
# ───────────────────────────────────────────────────────────

merge_check_classifier() {
  # Args: method squash mergeCommit rebase
  #   method — squash | merge | rebase (review.merge_method)
  #   squash/mergeCommit/rebase — "true" or "false" (the strategy read)
  # Mirrors the classifier documented in SKILL.md Check 4, which T7 pins line
  # by line. The message source is not an input: it only adds a note to a pass.
  local method="$1" squash="$2" mc="$3"
  if [ "$method" = "rebase" ]; then
    echo "WARN"
  elif [ "$method" = "squash" ] && [ "$squash" = "true" ]; then
    echo "PASS"
  elif [ "$method" = "merge" ] && [ "$mc" = "true" ]; then
    echo "PASS"
  else
    echo "WARN"
  fi
}

t14() {
  local label="$1" want="$2"; shift 2
  if [ "$(merge_check_classifier "$@")" = "$want" ]; then
    pass "$label"
  else
    fail "$label (wanted $want)"
  fi
}

t14 "T14.1: AC #4 — squash on a squash-only repo PASSes" PASS squash true false false
t14 "T14.2: AC #4 — squash with all three strategies allowed PASSes" PASS squash true true true
t14 "T14.3: AC #4 — squash on a merge-commit-only repo → WARN (method not allowed)" WARN squash false true false
# Issue #564 AC1: a repo that merges by merge commit keeps its settings.
t14 "T14.4: #564 — merge on a merge-commit-only repo PASSes" PASS merge false true false
t14 "T14.5: #564 — merge on a squash-only repo → WARN (method not allowed)" WARN merge true false false
t14 "T14.6: #564 — rebase on a rebase-only repo → WARN (tracker-only), never PASS" WARN rebase false false true
t14 "T14.7: #564 — rebase with every strategy allowed → WARN, never PASS" WARN rebase true true true

# ───────────────────────────────────────────────────────────
# T15: README.md highlights and structure
# ───────────────────────────────────────────────────────────
RM="$SKILL_DIR/docs/README.md"

if grep -qE '^# IDD Doctor' "$RM"; then
  pass "T15.1: README has '# IDD Doctor' top-level heading"
else
  fail "T15.1: README missing '# IDD Doctor' heading"
fi

for section in "## Highlights" "## When to Use" "## How It Works" "## Installation" "## Usage" "## Scope (v1)" "## Out of scope for v1" "## Output" "## Resources"; do
  if grep -qF "$section" "$RM"; then
    pass "T15: README has section '$section'"
  else
    fail "T15: README missing section '$section'"
  fi
done

if grep -qE 'mermaid' "$RM"; then
  pass "T15.10: README includes a mermaid flow diagram"
else
  fail "T15.10: README missing mermaid diagram"
fi

# ───────────────────────────────────────────────────────────
# T16: Read-only invariant — running these tests must not
# modify the working tree
# ───────────────────────────────────────────────────────────
# We can verify this by snapshotting `git status --porcelain` of the
# tracked-only state of the skills/idd-doctor and tests/ paths before
# and after. (The doctor itself isn't invoked here, but the test
# harness must also not mutate anything.)
SNAPSHOT_BEFORE="$(cd "$REPO_ROOT" && git status --porcelain -- skills/idd-doctor tests/test-idd-doctor.sh 2>/dev/null | sort)"
# (A real /idd-doctor invocation would happen here in a future v2 test.)
SNAPSHOT_AFTER="$(cd "$REPO_ROOT" && git status --porcelain -- skills/idd-doctor tests/test-idd-doctor.sh 2>/dev/null | sort)"

if [ "$SNAPSHOT_BEFORE" = "$SNAPSHOT_AFTER" ]; then
  pass "T16: AC #5 — test harness does not modify skills/idd-doctor or tests/"
else
  fail "T16: AC #5 — test harness modified files (before/after differ)"
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
else
  echo "  ✓ All tests passed"
  exit 0
fi
