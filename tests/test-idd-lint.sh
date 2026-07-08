#!/usr/bin/env bash
# test-idd-lint.sh — Validate scripts/idd-lint.py against SPEC.md conformance
# fixtures (review R3: enforcement that needs no agent).
#
# Covers: issue L1 checks, PR L2/L3 checks, commit and branch grammar (§3),
# level relaxation (--level L2), and the git-based repo mode.
#
# Usage: bash tests/test-idd-lint.sh
# Returns: exit 0 if all tests pass, exit 1 on failure

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$REPO_ROOT/scripts/idd-lint.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

# expect <0|1> <label> <args...>  — run idd-lint, compare exit code
expect() {
  local want="$1" label="$2"
  shift 2
  local got=0
  python3 "$LINT" "$@" >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$want" ]; then
    pass "$label"
  else
    fail "$label (want exit $want, got $got)"
  fi
}

echo "◆ idd-lint Conformance Tests (review R3)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# Fixtures
# ───────────────────────────────────────────────────────────
cat > "$TMP/issue-good.md" <<'EOF'
<!-- gitissue:normalized v1 -->

## Type

Bug

## Description

**Current behavior:**
Mobile users hit a redirect loop.

**Expected behavior:**
Login completes.

> **Reporter Context**
> the login is broken on mobile.

## Acceptance Criteria

- [ ] Mobile login completes without a redirect loop
- [ ] Desktop login continues to work

## Metadata

**Priority:** P1
**Effort:** S
**Labels:** bug, auth
EOF

sed '1d' "$TMP/issue-good.md" > "$TMP/issue-no-marker.md"
sed 's/^- \[ \] .*$//' "$TMP/issue-good.md" > "$TMP/issue-no-checkboxes.md"
sed 's/\*\*Current behavior:\*\*//' "$TMP/issue-good.md" > "$TMP/issue-bug-no-fields.md"

cat > "$TMP/issue-feature.md" <<'EOF'
<!-- gitissue:normalized v1 -->

## Type

Feature (high confidence)

## Description

Add a dark mode toggle to settings.

> **Reporter Context**
> we need dark mode

## Acceptance Criteria

- [ ] Toggle appears in settings

## Metadata

**Priority:** P2
**Effort:** M
**Labels:** feature
EOF

cat > "$TMP/pr-good.md" <<'EOF'
Closes #42

## Summary

Fix the mobile redirect loop.

## Decision Record

- **Root cause:** session cookie rejected on cross-origin SSO redirects.
- **Options considered:** Option 1 — proxy; Option 2 — SameSite=None
- **Options rejected:** Option 1 — heavier infra change
- **Selected option:** Option 2 — SameSite=None
- **Residual risk:** none identified
- **Reproduction:** `npm test` confirmed red → regression test `tests/redirect.spec.ts`

Analyzed at: `fix/42-mobile-auth @ abc1234` (2026-07-08)

## Acceptance Criteria Verification

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Mobile login completes | pass | tests/redirect.spec.ts |
| Desktop login unchanged | unverified | manual review needed |
EOF

sed 's/^Closes #42$/This PR fixes things./' "$TMP/pr-good.md" > "$TMP/pr-no-closes.md"
sed 's/^## Decision Record$/## Notes/' "$TMP/pr-good.md" > "$TMP/pr-no-dr.md"
sed 's/- \*\*Reproduction:.*$//' "$TMP/pr-good.md" > "$TMP/pr-no-repro.md"

# ───────────────────────────────────────────────────────────
# T1–T5: issue linting (L1, §1)
# ───────────────────────────────────────────────────────────
expect 0 "T1: conforming bug issue passes" issue "$TMP/issue-good.md"
expect 1 "T2: issue without normalization marker fails" issue "$TMP/issue-no-marker.md"
expect 1 "T3: issue without acceptance checkboxes fails" issue "$TMP/issue-no-checkboxes.md"
expect 1 "T4: bug issue without Current/Expected behavior fails" issue "$TMP/issue-bug-no-fields.md"
expect 0 "T5: feature issue (no type-specific fields, confidence marker) passes" issue "$TMP/issue-feature.md"

# stdin variant
if python3 "$LINT" issue - < "$TMP/issue-good.md" >/dev/null 2>&1; then
  pass "T6: issue linting reads from stdin"
else
  fail "T6: issue linting reads from stdin"
fi

# ───────────────────────────────────────────────────────────
# T7–T11: PR linting (L2 §5, L3 §4)
# ───────────────────────────────────────────────────────────
expect 0 "T7: conforming PR passes at L3" pr "$TMP/pr-good.md" --title "fix(auth): resolve mobile redirect loop (#42)"
expect 1 "T8: PR without 'Closes #N' first line fails" pr "$TMP/pr-no-closes.md"
expect 1 "T9: PR without Decision Record fails at L3" pr "$TMP/pr-no-dr.md"
expect 0 "T10: PR without Decision Record passes at --level L2" --level L2 pr "$TMP/pr-no-dr.md"
expect 1 "T11: fix-typed PR without Reproduction fails at L3" pr "$TMP/pr-no-repro.md" --title "fix(auth): resolve mobile redirect loop (#42)"

# ───────────────────────────────────────────────────────────
# T12–T15: commit grammar (L2, §3.2)
# ───────────────────────────────────────────────────────────
expect 0 "T12: conventional commit with issue ref passes" commit "fix(auth): resolve redirect loop (#42)"
expect 1 "T13: commit without issue ref fails" commit "fix(auth): resolve redirect loop"
expect 1 "T14: commit with uppercase description fails" commit "feat(auth): Add OAuth login (#42)"
expect 0 "T15: merge commits are skipped" commit "Merge pull request #50 from fork/branch"

# ───────────────────────────────────────────────────────────
# T16–T18: branch grammar (L2, §3.1)
# ───────────────────────────────────────────────────────────
expect 0 "T16: 'fix/42-mobile-auth-redirect' passes" branch "fix/42-mobile-auth-redirect"
expect 1 "T17: 'Fix/42_bad' fails (case + underscore)" branch "Fix/42_bad"
expect 0 "T18: 'release/v1.2.0' exempt from issue number" branch "release/v1.2.0"

# ───────────────────────────────────────────────────────────
# T19: repo mode against a synthetic git repo
# ───────────────────────────────────────────────────────────
SYN="$TMP/repo"
mkdir -p "$SYN"
(
  cd "$SYN"
  git init -q -b main
  git -c user.name=t -c user.email=t@t config user.name t
  git config user.email t@t
  echo a > a.txt && git add a.txt && git commit -qm "chore(init): scaffold repo (#1)"
  git checkout -qb fix/2-broken-thing
  echo b > b.txt && git add b.txt && git commit -qm "fix(core): repair broken thing (#2)"
)
if (cd "$SYN" && python3 "$LINT" repo --base main >/dev/null 2>&1); then
  pass "T19: repo mode passes on conforming branch + commits"
else
  fail "T19: repo mode passes on conforming branch + commits"
fi
(
  cd "$SYN"
  echo c > c.txt && git add c.txt && git commit -qm "did some stuff"
)
if (cd "$SYN" && python3 "$LINT" repo --base main >/dev/null 2>&1); then
  fail "T20: repo mode fails on non-conforming commit"
else
  pass "T20: repo mode fails on non-conforming commit"
fi

# ───────────────────────────────────────────────────────────
# T21: the repo's own sample issue passes L1 (docs/sample-normalized-issue.md)
# ───────────────────────────────────────────────────────────
# Strip the doc's explanatory header (everything before the marker line).
awk '/<!-- gitissue:normalized/{found=1} found' "$REPO_ROOT/docs/sample-normalized-issue.md" > "$TMP/sample.md"
expect 0 "T21: docs/sample-normalized-issue.md body passes L1" issue "$TMP/sample.md"

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ idd-lint conformance tests failed"
  exit 1
fi

echo "  ✓ idd-lint validates SPEC.md conformance from plain data"
exit 0
