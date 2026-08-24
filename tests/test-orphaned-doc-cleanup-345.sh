#!/usr/bin/env bash
# Regression contract for the documentation cleanup and local artifact policy (#345).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
check() {
  local description="$1"
  shift
  if "$@"; then pass "$description"; else fail "$description"; fi
}

echo "◆ Orphaned Documentation Cleanup (issue #345)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

release_note="$REPO_ROOT/docs/release-notes/2026-03-lean-issues-architecture.md"
decision="$REPO_ROOT/docs/decisions/documentation-canon-and-release-note-policy.md"

check "orphaned TODO document is removed" test ! -e "$REPO_ROOT/docs/TODOS.md"
check "orphaned decisions log is removed" test ! -e "$REPO_ROOT/docs/DECISIONS.md"
check "historical release note is tracked" \
  git -C "$REPO_ROOT" ls-files --error-unmatch \
    docs/release-notes/2026-03-lean-issues-architecture.md
check "documentation policy ADR is tracked" \
  git -C "$REPO_ROOT" ls-files --error-unmatch \
    docs/decisions/documentation-canon-and-release-note-policy.md
check "completed lean-issue history is preserved as a release note" \
  grep -q "Lean Issues Architecture" "$release_note"
check "future-work context remains in the historical release note" \
  grep -q "Cross-skill triage updates" "$release_note"
check "documentation decisions are preserved as an accepted ADR" \
  grep -q "Status:.*Accepted (2026-07-09)" "$decision"
check "the ADR records the canonical root changelog" \
  grep -q 'root `CHANGELOG.md` is the only canonical version history' "$decision"
check "the ADR records the curated release-note policy" \
  grep -q 'curated collection, not a per-release ledger' "$decision"
check "local review artifacts have one ignored workspace" \
  git -C "$REPO_ROOT" check-ignore -q local/review-artifact.md

for artifact in \
  IDD-REVIEW-2026-07-09.md \
  IDD-REVIEW-2026-07-10-closing.md \
  fable-5-review-idd.md \
  competitor-analysis-projectalfred.md; do
  check "$artifact is absent from the repository root" \
    test ! -e "$REPO_ROOT/$artifact"
  check "local/$artifact is ignored" \
    git -C "$REPO_ROOT" check-ignore -q "local/$artifact"
  if git -C "$REPO_ROOT" check-ignore -q "$artifact"; then
    fail "$artifact is no longer allowed at the repository root"
  else
    pass "$artifact is no longer allowed at the repository root"
  fi
done

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
