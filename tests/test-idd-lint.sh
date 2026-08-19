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
    '{"ts":"2026-07-09T00:01:00Z","issue":9,"mode":"auto","skill":"issue-resolver","outcome":"failed","pr":null,"complexity":"high","qa_cycles":3}' \
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
# T26: class QA-cycle ceiling (#308)
# ───────────────────────────────────────────────────────────
# High-class qa_cycles=5 without breach_reason stays inside the high ceiling.
# Medium qa_cycles=3 without reason is an unexplained breach (exit 1).
# High qa_cycles=7 without reason exceeds default qa_max (5) → fail.
# Medium qa_cycles=3 with breach_reason → pass.
(
  cd "$SYN"
  mkdir -p .gitissue
  printf '%s\n' \
    '{"ts":"2026-07-09T00:00:00Z","issue":260,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":1,"complexity":"high","qa_cycles":5}' \
    '{"ts":"2026-07-09T00:01:00Z","issue":253,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":2,"complexity":"high","qa_cycles":5}' \
    '{"ts":"2026-07-09T00:02:00Z","issue":295,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":3,"complexity":"medium","qa_cycles":3}' \
    > .gitissue/runs.jsonl
)
if (cd "$SYN" && python3 "$LINT" stats --no-github >/dev/null 2>&1); then
  fail "T26: unexplained medium>2 must fail stats"
else
  pass "T26: unexplained medium>2 fails stats (exit 1)"
fi
(
  cd "$SYN"
  printf '%s\n' \
    '{"ts":"2026-07-09T00:00:00Z","issue":260,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":1,"complexity":"high","qa_cycles":5}' \
    '{"ts":"2026-07-09T00:01:00Z","issue":273,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":2,"complexity":"high","qa_cycles":7}' \
    > .gitissue/runs.jsonl
)
if (cd "$SYN" && python3 "$LINT" stats --no-github >/dev/null 2>&1); then
  fail "T26b: high qa_cycles=7 without reason must fail"
else
  pass "T26b: high qa_cycles=7 without reason fails (exceeds default 5)"
fi
(
  cd "$SYN"
  printf '%s\n' \
    '{"ts":"2026-07-09T00:00:00Z","issue":260,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":1,"complexity":"high","qa_cycles":5}' \
    '{"ts":"2026-07-09T00:01:00Z","issue":273,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":2,"complexity":"high","qa_cycles":7,"breach_reason":"stagnation plus CI flake"}' \
    '{"ts":"2026-07-09T00:02:00Z","issue":295,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":3,"complexity":"medium","qa_cycles":3,"breach_reason":"reviewer loop on squash-binding"}' \
    > .gitissue/runs.jsonl
)
if (cd "$SYN" && python3 "$LINT" stats --no-github >/dev/null 2>&1); then
  pass "T26c: explained over-ceiling rows do not fail stats"
else
  fail "T26c: explained over-ceiling rows should pass"
fi
(
  cd "$SYN"
  printf '%s\n' \
    '{"ts":"2026-07-09T00:00:00Z","issue":3,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":4,"complexity":"low","qa_cycles":1}' \
    '{"ts":"2026-07-09T00:01:00Z","issue":9,"mode":"auto","skill":"issue-resolver","outcome":"failed","pr":null,"complexity":"high","qa_cycles":3}' \
    > .gitissue/runs.jsonl
)
# Light profile qa_cycles=2 without reason is an unexplained breach
# (light ceiling is 1) → exit 1.
(
  cd "$SYN"
  printf '%s\n' \
    '{"ts":"2026-07-09T00:00:00Z","issue":260,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":1,"profile":"light","qa_cycles":2}' \
    > .gitissue/runs.jsonl
)
if (cd "$SYN" && python3 "$LINT" stats --no-github >/dev/null 2>&1); then
  fail "T26d: unexplained light-profile qa_cycles=2 must fail stats"
else
  pass "T26d: light ceiling is 1; qa_cycles=2 without reason fails (exit 1)"
fi
# A recorded ceiling override wins over the computed policy ceiling: a high
# row with ceiling=7 sits at qa_cycles=6, inside the recorded ceiling → pass.
(
  cd "$SYN"
  printf '%s\n' \
    '{"ts":"2026-07-09T00:00:00Z","issue":260,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":1,"complexity":"high","ceiling":7,"qa_cycles":6}' \
    > .gitissue/runs.jsonl
)
if (cd "$SYN" && python3 "$LINT" stats --no-github >/dev/null 2>&1); then
  pass "T26e: recorded ceiling=7 allows qa_cycles=6 without breach_reason"
else
  fail "T26e: recorded ceiling override should pass stats (exit 0)"
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
#
# The fixture is what makes this a test rather than a tautology: it needs a
# commit *earlier today* than the moment the test runs. A repo whose commits are
# all made at `now` gives the same count either way, so the assertion would hold
# with `normalize_since` reverted to `return since`. Dates are all local — git
# reads both GIT_COMMITTER_DATE and `--since` in the local zone, so `date -u`
# here would misplace the commit relative to the window near midnight.
#
# 00:00:01, not 00:30:00: the backdated commit only exercises the bug while the
# unnormalized bare date resolves *later in the day* than it. At 00:30 the test
# tautologized for the first half-hour of every local day; at 00:00:01 the blind
# spot is one second wide.
SINCE_REPO="$TMP/since"
mkdir -p "$SINCE_REPO"
TODAY="$(date '+%Y-%m-%d')"
(
  cd "$SINCE_REPO"
  git init -q -b main
  git config user.email t@t
  git config user.name t
  GIT_COMMITTER_DATE="$TODAY 00:00:01" GIT_AUTHOR_DATE="$TODAY 00:00:01" \
    git commit -q --allow-empty -m "chore(init): scaffold repo (#1)"
  git commit -q --allow-empty -m "fix(core): repair broken thing (#2)"
)
BARE="$( (cd "$SINCE_REPO" && python3 "$LINT" stats --no-github --since "$TODAY" --json) \
         | python3 -c "import json,sys; print(json.load(sys.stdin)['git']['commits'])" )"
EXPLICIT="$( (cd "$SINCE_REPO" && python3 "$LINT" stats --no-github --since "$TODAY 00:00:00" --json) \
         | python3 -c "import json,sys; print(json.load(sys.stdin)['git']['commits'])" )"
# The counts alone stopped being able to see this regression once an
# unresolvable window began degrading to lifetime: a *today* bare date always
# resolves to within a second of now, so with `normalize_since` reverted the
# now-detection in `_since_epoch` reads it as a typo, drops the window, and
# reports the same lifetime 2 the correct midnight window reports. The window
# error is the signal that survives — so compare the two forms on that too.
#
# Compared, not asserted absent: for the two seconds after local midnight the
# normalized `$TODAY 00:00:00` is itself within the ±2s now-band and both forms
# warn. That is the documented `NOW_TOKENS` residual, not a normalization bug.
# Equality is the real claim: a bare date must behave like explicit midnight.
BARE_TEXT="$( cd "$SINCE_REPO" && python3 "$LINT" stats --no-github --since "$TODAY" )"
EXPLICIT_TEXT="$( cd "$SINCE_REPO" && python3 "$LINT" stats --no-github --since "$TODAY 00:00:00" )"
BARE_WARN="$( printf '%s\n' "$BARE_TEXT" | grep -cF "⚠ --since" || true )"
EXPLICIT_WARN="$( printf '%s\n' "$EXPLICIT_TEXT" | grep -cF "⚠ --since" || true )"
# 2, not just "equal": the 00:00:01 commit is the one an unnormalized bare date
# drops, so an equal-but-short pair is the regression, not a pass.
if [ "$BARE" = "$EXPLICIT" ] && [ "$BARE" = "2" ] \
   && [ "$BARE_WARN" = "$EXPLICIT_WARN" ]; then
  pass "T25d: bare --since $TODAY matches '$TODAY 00:00:00' ($BARE commits)"
else
  fail "T25d: bare --since gave $BARE commits, explicit midnight gave $EXPLICIT (want 2/2)"
  echo "      window warnings — bare $BARE_WARN, explicit midnight $EXPLICIT_WARN"
  printf '%s\n' "$BARE_TEXT" | grep -F "⚠ --since" | sed 's/^/      /' || true
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

# ───────────────────────────────────────────────────────────
# T25f: the per-PR B1 join — buckets, window, denominator (#180)
# ───────────────────────────────────────────────────────────
# T25e pins the verdict for a single oid; this pins what collect_dr_binding
# does with a whole page of them. It runs inside $JOIN because the window
# resolves its --since through `git rev-parse`, which needs a repository —
# outside one the window would never apply and the assertions below would
# quietly test nothing.
T25F_ERR="$TMP/t25f.err"
if (cd "$JOIN" && python3 - <<PY
import importlib.util
spec = importlib.util.spec_from_file_location('idd_lint', '$LINT')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

DR = "## Decision Record\n\n- **Root cause:** none."
# mergedAt values sit months apart at midday UTC, so no local-timezone offset
# on the \`git rev-parse --since\` side can move a PR across the boundary. The
# two unresolvable PRs (3: no sha, 4: not in this clone) sit in *different*
# quarters on purpose — a window that catches only one of them is what makes
# the rendered caveat differ between the window and lifetime populations.
merged = [
    {"number": 1, "body": DR, "mergedAt": "2026-01-10T12:00:00Z",
     "mergeCommit": {"oid": "$LANDED_OID"}},
    {"number": 2, "body": DR, "mergedAt": "2026-01-11T12:00:00Z",
     "mergeCommit": {"oid": "$LOST_OID"}},
    {"number": 3, "body": DR, "mergedAt": "2026-06-10T12:00:00Z",
     "mergeCommit": None},
    {"number": 4, "body": DR, "mergedAt": "2026-09-11T12:00:00Z",
     "mergeCommit": {"oid": "0" * 40}},
    {"number": 5, "body": "no decision record here",
     "mergedAt": "2026-06-12T12:00:00Z", "mergeCommit": {"oid": "$LANDED_OID"}},
]

b = m.collect_dr_binding(merged, 200, None)
assert b["prs_with_dr"] == 4, b
assert (b["dr_landed"], b["dr_lost"]) == (1, 1), b
assert b["merge_commit_resolved"] == 2, b
assert (b["unresolved_no_sha"], b["unresolved_not_in_clone"]) == (1, 1), b
assert b["landed_pct"] == 50, b
assert b["truncated"] is False, b
# Both window keys are present on every binding: a consumer subscripting
# b["window_error"] must not raise on the success path while b["window"] is safe.
assert b["window"] is None, b
assert "window_error" in b and b["window_error"] is None, b
assert m.collect_dr_binding(merged, 5, None)["truncated"] is True

# A window holding only unresolvable PRs. The denominator is landed+lost, so it
# is 0 — "unknown" — and _ratio_row renders a dim dash. Using prs_with_dr would
# print a red 0% built from data nobody has: in a shallow clone every oid is
# not_in_clone, so that is the CI default, not a corner case.
b6 = m.collect_dr_binding(merged, 200, m.resolve_since("2026-06-01 00:00:00"))
w = b6["window"]
assert w is not None, "window did not resolve — is this a git repo?"
assert w["prs_with_dr"] == 2, w
assert w["merge_commit_resolved"] == 0, w
assert (w["dr_landed"], w["dr_lost"]) == (0, 0), w
assert (w["unresolved_no_sha"], w["unresolved_not_in_clone"]) == (1, 1), w
head = m._render_dr_binding(b6)[0]
assert "✗" not in head and "0%" not in head, head

# A wider window holds every PR, so it must mirror the lifetime numbers.
w2 = m.collect_dr_binding(merged, 200, m.resolve_since("2026-01-01 00:00:00"))["window"]
assert (w2["prs_with_dr"], w2["merge_commit_resolved"]) == (4, 2), w2
assert (w2["dr_landed"], w2["dr_lost"]) == (1, 1), w2

# The unresolved caveat must count the population the row above counted. This
# window holds PR 4 alone, so its caveat reads 0 no-sha / 1 not-in-clone against
# a lifetime of 1 / 1 — reading the lifetime numbers here would describe a
# different set of PRs than the ratio directly above them.
b7 = m.collect_dr_binding(merged, 200, m.resolve_since("2026-08-01 00:00:00"))
assert b7["window"]["prs_with_dr"] == 1, b7["window"]
assert (b7["window"]["unresolved_no_sha"],
        b7["window"]["unresolved_not_in_clone"]) == (0, 1), b7["window"]
win_lines = "\n".join(m._render_dr_binding(b7))
assert "1 unresolved (0 no merge sha, 1 not in this clone)" in win_lines, win_lines
assert "2 unresolved" not in win_lines, win_lines
assert "excluded from the ratio, not counted as misses" in win_lines, win_lines

# An unparsable --since resolves to *now* in git's approxidate, which would
# otherwise report an empty-and-therefore-clean window to a JSON consumer.
bad = m.collect_dr_binding(merged, 200, m.resolve_since("garbage-typo"))
assert bad["window"] is None, bad
assert bad["window_error"]["since"] == "garbage-typo", bad

# The lifetime row must not then print the "run with --since" hint: the reader
# just did that. The ⚠ itself lives at the top of the report (T25h), not here.
bad_lines = "\n".join(m._render_dr_binding(bad))
assert "window not applied — see the note at the top" in bad_lines, bad_lines
assert "run with --since" not in bad_lines, bad_lines
assert "⚠" not in bad_lines, bad_lines
PY
) 2>"$T25F_ERR"; then
  pass "T25f: collect_dr_binding buckets, windows, and excludes unresolved PRs"
else
  fail "T25f: collect_dr_binding mis-bucketed or mis-windowed the B1 join"
  # Print what actually broke. Swallowing this made an unset LANDED_OID or a
  # missing python3 indistinguishable from a real mis-bucketing.
  sed 's/^/      /' "$T25F_ERR"
fi

# ───────────────────────────────────────────────────────────
# T25g: dr_binding is wired into collect_github_stats (#180)
# ───────────────────────────────────────────────────────────
# Deleting the `"dr_binding": collect_dr_binding(...)` line left the whole
# suite green, because every other B1 test called the collector directly.
# Stubbing the gh boundary is what makes the wiring itself assertable.
T25G_ERR="$TMP/t25g.err"
if (cd "$JOIN" && python3 - <<PY
import importlib.util, pathlib
spec = importlib.util.spec_from_file_location('idd_lint', '$LINT')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

DR = "## Decision Record\n\n- **Root cause:** none."
def fake_gh(*args):
    if args[0] == "issue":
        return [{"number": 1, "body": "<!-- gitissue:normalized v1 -->"}]
    return [{"number": 9, "body": "Closes #9\n\n" + DR,
             "mergedAt": "2026-01-10T12:00:00Z",
             "mergeCommit": {"oid": "$LANDED_OID"}}]
m._gh_json = fake_gh

r = m.collect_github_stats(200, pathlib.Path("no-such-runs.jsonl"))
assert r is not None and "dr_binding" in r, r
assert r["dr_binding"]["dr_landed"] == 1, r["dr_binding"]
assert r["dr_binding"]["merge_commit_resolved"] == 1, r["dr_binding"]
PY
) 2>"$T25G_ERR"; then
  pass "T25g: collect_github_stats carries dr_binding into the report"
else
  fail "T25g: collect_github_stats dropped the dr_binding join"
  sed 's/^/      /' "$T25G_ERR"
fi

# ───────────────────────────────────────────────────────────
# T25h: an unresolvable --since degrades both sections (#180)
# ───────────────────────────────────────────────────────────
# `--since` feeds two consumers: the local git history and the PR-side B1 join.
# Validating it for the join alone left git's approxidate to read the same
# string as *now*, so the report showed "0 non-merge commits" — a window that
# WAS applied — directly above a warning saying the window was not applied.
# One resolution, one verdict: both sections fall back to lifetime, and the ⚠
# is printed once, at the top, where it also covers --no-github (which has no
# dr_binding row to carry it).
LIFETIME="$( (cd "$SINCE_REPO" && python3 "$LINT" stats --no-github --json) \
             | python3 -c "import json,sys; print(json.load(sys.stdin)['git']['commits'])" )"
BAD_SINCE="$( (cd "$SINCE_REPO" && python3 "$LINT" stats --no-github --since garbage-typo --json) \
             | python3 -c "import json,sys; print(json.load(sys.stdin)['git']['commits'])" )"
BAD_TEXT="$( cd "$SINCE_REPO" && python3 "$LINT" stats --no-github --since garbage-typo )"
BAD_EXIT=0
(cd "$SINCE_REPO" && python3 "$LINT" stats --no-github --since garbage-typo >/dev/null) || BAD_EXIT=$?
if [ "$BAD_SINCE" = "$LIFETIME" ] && [ "$LIFETIME" != "0" ] \
   && printf '%s\n' "$BAD_TEXT" | grep -qF "⚠ --since 'garbage-typo' did not parse as a date" \
   && printf '%s\n' "$BAD_TEXT" | grep -qF "window not applied — every section below is lifetime" \
   && [ "$BAD_EXIT" -eq 0 ]; then
  pass "T25h: unresolvable --since degrades to lifetime with one ⚠ (exit 0)"
else
  fail "T25h: unresolvable --since gave $BAD_SINCE commits (lifetime $LIFETIME), exit $BAD_EXIT"
  printf '%s\n' "$BAD_TEXT" | sed 's/^/      /'
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
