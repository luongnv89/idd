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
# T22–T25: stats mode (review R4 — evidence loop)
# ───────────────────────────────────────────────────────────
(
  cd "$SYN"
  git checkout -q main
  git commit -q --allow-empty \
    -m "feat(core): add widget (#3)" \
    -m "Closes #3" \
    -m "## Decision Record

- **Root cause:** widget was missing.
- **Options considered:** Option 1 — build it
- **Options rejected:** none
- **Selected option:** Option 1
- **Residual risk:** none identified"
  mkdir -p .gitissue
  printf '%s\n%s\n' \
    '{"ts":"2026-07-09T00:00:00Z","issue":3,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":4,"complexity":"low","qa_cycles":1}' \
    '{"ts":"2026-07-09T00:01:00Z","issue":9,"mode":"auto","skill":"issue-resolver","outcome":"failed","pr":null,"qa_cycles":3}' \
    > .gitissue/runs.jsonl
)
STATS_OUT="$(cd "$SYN" && python3 "$LINT" stats --no-github 2>&1)" && STATS_EXIT=0 || STATS_EXIT=$?
if [ "$STATS_EXIT" -eq 0 ]; then
  pass "T22: stats mode exits 0 on synthetic repo"
else
  fail "T22: stats mode exits 0 on synthetic repo (got $STATS_EXIT)"
fi
if printf '%s' "$STATS_OUT" | grep -qE "trace completeness.*100%.*2/2" \
   && printf '%s' "$STATS_OUT" | grep -qE "DR coverage \(local proxy\).*50%.*1/2"; then
  pass "T23: stats reports trace completeness and DR coverage from git"
else
  fail "T23: stats reports trace completeness and DR coverage from git"
fi
if printf '%s' "$STATS_OUT" | grep -qE "success rate.*50%.*1/2" \
   && printf '%s' "$STATS_OUT" | grep -qE "median QA cycles +2"; then
  pass "T24: stats aggregates runs.jsonl outcomes and QA cycles"
else
  fail "T24: stats aggregates runs.jsonl outcomes and QA cycles"
fi
if (cd "$SYN" && python3 "$LINT" stats --no-github --json) | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['git']['commits'] == 2, d['git']
# Both commits are PR-derived (both subjects carry a (#N) ref); only one of
# them carries a Decision Record. Asserting 100 here is what let the broken
# Closes-#N-only denominator survive — the misses were not in the sample.
assert d['git']['pr_derived_commits'] == 2, d['git']
assert d['git']['dr_pct'] == 50, d['git']
assert d['runs']['runs'] == 2 and d['runs']['success_pct'] == 50
assert d['github'] is None
" 2>/dev/null; then
  pass "T25: stats --json emits valid machine-readable metrics"
else
  fail "T25: stats --json emits valid machine-readable metrics"
fi

# ───────────────────────────────────────────────────────────
# T25b: bucket identity — the union is a real union (#180)
# ───────────────────────────────────────────────────────────
# subject_ref + closes_body - both == pr_derived. If this drifts, the
# DR denominator is counting some commits twice or dropping them.
if (cd "$SYN" && python3 "$LINT" stats --no-github --json) | python3 -c "
import json, sys
g = json.load(sys.stdin)['git']
assert g['subject_ref_commits'] + g['closes_body_commits'] \
       - g['subject_and_closes_commits'] == g['pr_derived_commits'], g
assert g['subject_ref_commits'] == 2 and g['closes_body_commits'] == 1, g
assert g['subject_and_closes_commits'] == 1 and g['pr_derived_commits'] == 2, g
assert g['dr_pct'] == round(100 * g['decision_records'] / g['pr_derived_commits']), g
" 2>/dev/null; then
  pass "T25b: DR denominator buckets satisfy the union identity"
else
  fail "T25b: DR denominator buckets violate the union identity"
fi

# ───────────────────────────────────────────────────────────
# T25c: --no-github never reaches the GitHub join (#180)
# ───────────────────────────────────────────────────────────
# The per-PR B1 join lives in collect_github_stats, so offline mode must
# emit no dr_binding key anywhere in the document.
OFFLINE_JSON="$(cd "$SYN" && python3 "$LINT" stats --no-github --json 2>/dev/null)"
if printf '%s' "$OFFLINE_JSON" | python3 -c "
import json, sys
raw = sys.stdin.read()
d = json.loads(raw)
assert d['github'] is None, d['github']
assert 'dr_binding' not in raw, 'dr_binding leaked into offline output'
" 2>/dev/null; then
  pass "T25c: --no-github emits github: null and no dr_binding"
else
  fail "T25c: --no-github leaked GitHub-only metrics"
fi

# ───────────────────────────────────────────────────────────
# T25d: --since normalization — a bare date means midnight (#180)
# ───────────────────────────────────────────────────────────
# git approxidate fills an unstated time of day from the current wall clock,
# so `--since 2026-08-15` used to mean "2026-08-15 at whatever o'clock it is
# now" and the same command returned different windows through the day.
SINCE_DAY="$(date -u -d '1 day ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-1d '+%Y-%m-%d')"
BARE="$( (cd "$SYN" && python3 "$LINT" stats --no-github --since "$SINCE_DAY" --json) \
         | python3 -c "import json,sys; print(json.load(sys.stdin)['git']['commits'])" )"
EXPLICIT="$( (cd "$SYN" && python3 "$LINT" stats --no-github --since "$SINCE_DAY 00:00:00" --json) \
         | python3 -c "import json,sys; print(json.load(sys.stdin)['git']['commits'])" )"
if [ "$BARE" = "$EXPLICIT" ] && [ "$BARE" -gt 0 ]; then
  pass "T25d: bare --since $SINCE_DAY matches '$SINCE_DAY 00:00:00' ($BARE commits)"
else
  fail "T25d: bare --since gave $BARE commits, explicit midnight gave $EXPLICIT"
fi

# ───────────────────────────────────────────────────────────
# T25e: merge-commit join predicate (#180)
# ───────────────────────────────────────────────────────────
# The full join needs GitHub; these tests run with no repo and no token. What
# is testable offline is the half that decides the verdict: given a merge
# commit oid, did the Decision Record actually land in git?
JOIN="$TMP/join"
mkdir -p "$JOIN"
(
  cd "$JOIN"
  git init -q
  git config user.email t@t
  git config user.name t
  git commit -q --allow-empty \
    -m "feat(core): landed (#10)" \
    -m "Closes #10" \
    -m "## Decision Record

- **Root cause:** none."
  git commit -q --allow-empty \
    -m "feat(core): lost (#11) (#12)" \
    -m "* feat(core): lost (#11)
* fix(core): review note (#11)"
)
LANDED_OID="$(git -C "$JOIN" rev-list --max-parents=0 HEAD)"
LOST_OID="$(git -C "$JOIN" rev-parse HEAD)"
if (cd "$JOIN" && python3 -c "
import importlib.util, sys
spec = importlib.util.spec_from_file_location('idd_lint', '$LINT')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
assert m.classify_merge_commit('$LANDED_OID') == 'landed'
assert m.classify_merge_commit('$LOST_OID') == 'lost'
assert m.classify_merge_commit(None) == 'no_sha'
assert m.classify_merge_commit('') == 'no_sha'
assert m.classify_merge_commit('0' * 40) == 'not_in_clone'
") 2>/dev/null; then
  pass "T25e: classify_merge_commit sorts landed/lost/no_sha/not_in_clone"
else
  fail "T25e: classify_merge_commit misclassified a merge commit"
fi

# stats degrades gracefully outside a git repo
mkdir -p "$TMP/plain"
if (cd "$TMP/plain" && python3 "$LINT" stats --no-github 2>&1 | grep -q "not a git repository"); then
  pass "T26: stats degrades gracefully outside a git repo"
else
  fail "T26: stats degrades gracefully outside a git repo"
fi

# ───────────────────────────────────────────────────────────
# T27: hierarchy marker Part of #N is reported (spec §2.1)
# ───────────────────────────────────────────────────────────
printf '%s\n\nPart of #7\n' "$(cat "$TMP/issue-good.md")" > "$TMP/issue-child.md"
if python3 "$LINT" issue "$TMP/issue-child.md" 2>&1 | grep -q "Part of #7"; then
  pass "T27: 'Part of #N' hierarchy marker reported (§2.1)"
else
  fail "T27: 'Part of #N' hierarchy marker reported (§2.1)"
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
