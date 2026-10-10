#!/usr/bin/env bash
# test-correction-guards-524.sh — Reproducing negatives and behavior contract
# for `idd-lint corrections` (issue #524): recurring corrections are detected
# from git history and runs.jsonl, proposals are deduplicated in the ledger,
# status transitions are approval-gated, and the command never edits anything
# outside the proposals ledger (skills/src/docs stay untouched).
#
# Behavioral test: it runs scripts/idd-lint.py against throwaway git repos in a
# temp dir, so it needs only python3 + git (no gh, no network). Portable to
# GNU coreutils (Linux CI) and macOS.
#
# Usage: bash tests/test-correction-guards-524.sh
# Returns: exit 0 if all tests pass, exit 1 on failure summary.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$REPO_ROOT/scripts/idd-lint.py"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ idd-lint corrections — recurring corrections → enforcement guards (#524)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Throwaway repo whose history carries two review-feedback fix cycles on one
# scope and one on another, plus a runs.jsonl with a repeated skip reason.
R="$TMP/repo"
mkdir -p "$R/.idd"
git -C "$R" init -q
git -C "$R" config user.email t@t.co
git -C "$R" config user.name t
(
  cd "$R"
  echo a > a.txt && git add a.txt && git commit -qm "feat(auth): add login (#1)"
  echo b > b.txt && git add b.txt && git commit -qm "fix(auth): address review feedback (#1)"
  echo c > c.txt && git add c.txt && git commit -qm "fix(auth): address review feedback (#1)"
  echo d > d.txt && git add d.txt && git commit -qm "fix(docs): address review feedback (#2)"
  echo e > e.txt && git add e.txt && git commit -qm "chore(deps): bump x (#3)"
)
printf '%s\n' \
  '{"ts":"2026-07-09T00:00:00Z","issue":10,"mode":"auto","skill":"auto-pilot","outcome":"skipped","pr":null,"skipped_reason":"blocked_label"}' \
  '{"ts":"2026-07-10T00:00:00Z","issue":11,"mode":"auto","skill":"auto-pilot","outcome":"skipped","pr":null,"skipped_reason":"blocked_label"}' \
  'not json at all' \
  > "$R/.idd/runs.jsonl"
LEDGER="$R/.idd/improvement-proposals.jsonl"
run_lint() { ( cd "$R" && python3 "$LINT" corrections "$@" ); }

# ── T1: recurring review-fix scope is detected; one-off scope is not ──
OUT="$(run_lint)" || true
if printf '%s\n' "$OUT" | grep -qF "review-fix:auth — 2 review-feedback fix cycles"; then
  pass "T1: recurring review-fix:auth detected (2 cycles)"
else
  fail "T1: expected review-fix:auth recurrence in report"
fi
if ! printf '%s\n' "$OUT" | grep -qF "review-fix:docs"; then
  pass "T1b: one-off review-fix:docs below threshold, not reported"
else
  fail "T1b: single fix cycle must not count as recurring"
fi

# ── T2: repeated skip reason in runs.jsonl is a correction signal ──
if printf '%s\n' "$OUT" | grep -qF "skip:blocked_label — 2 runs skipped"; then
  pass "T2: recurring skip:blocked_label detected from runs.jsonl"
else
  fail "T2: expected skip:blocked_label recurrence in report"
fi

# ── T3: unproposed recurring corrections exit 1 (the lint contract) ──
set +e
run_lint >/dev/null 2>&1
RC=$?
set -e
if [ "$RC" -eq 1 ]; then
  pass "T3: unproposed recurring corrections exit 1"
else
  fail "T3: expected exit 1, got $RC"
fi

# ── T4: --record appends one proposal per recurring key, deduplicated ──
OUT="$(run_lint --record)"
LINES_AFTER_FIRST="$(wc -l < "$LEDGER" | tr -d ' ')"
if [ "$LINES_AFTER_FIRST" -eq 2 ]; then
  pass "T4: --record wrote one proposal per recurring key (2)"
else
  fail "T4: expected 2 ledger lines, got $LINES_AFTER_FIRST"
fi
OUT2="$(run_lint --record)"
LINES_AFTER_SECOND="$(wc -l < "$LEDGER" | tr -d ' ')"
if [ "$LINES_AFTER_SECOND" -eq 2 ] && printf '%s\n' "$OUT2" | grep -qF "no new proposals"; then
  pass "T4b: second --record deduplicates — nothing appended"
else
  fail "T4b: dedup broken (lines=$LINES_AFTER_SECOND)"
fi
if printf '%s\n' "$OUT2" | grep -qF "proposal proposed"; then
  pass "T4c: recorded keys report status proposed"
else
  fail "T4c: expected 'proposal proposed' status in report"
fi

# ── T5: malformed ledger lines are tolerated, never fatal ──
printf '%s\n' 'garbage{' '{"key":"x"}' >> "$LEDGER"
if run_lint --json | python3 -c '
import sys, json
d = json.load(sys.stdin)
assert d["malformed"] == 2, d
assert d["ledger"]["review-fix:auth"] == "proposed", d
'; then
  pass "T5: malformed ledger lines skipped and counted"
else
  fail "T5: malformed ledger lines not tolerated"
fi

# ── T6: approval gate — transitions are enforced ──
set +e
run_lint --approve "no-such-key" >/dev/null 2>&1; RC_UNKNOWN=$?
run_lint --landed "review-fix:auth" >/dev/null 2>&1; RC_LANDED=$?
set -e
[ "$RC_UNKNOWN" -eq 2 ] && pass "T6: approving an unknown key exits 2" || fail "T6: unknown key approve gave $RC_UNKNOWN"
[ "$RC_LANDED" -eq 2 ] && pass "T6b: landing a merely proposed key exits 2" || fail "T6b: premature landed gave $RC_LANDED"
OUT="$(run_lint --approve "review-fix:auth" --note "ok")"
run_lint --landed "review-fix:auth" >/dev/null
if printf '%s\n' "$OUT" | grep -qF "review-fix:auth: proposed → approved" \
  && tail -n 1 "$LEDGER" | grep -qF '"event": "landed"'; then
  pass "T6c: proposed → approved → landed recorded in order"
else
  fail "T6c: approval transition chain broken"
fi

# ── T7: a rejected key may be re-proposed when the signal recurs ──
run_lint --reject "skip:blocked_label" >/dev/null
set +e
run_lint >/dev/null 2>&1; RC_REJ=$?
set -e
run_lint --record >/dev/null
LAST="$(tail -n 1 "$LEDGER")"
if [ "$RC_REJ" -eq 0 ] && printf '%s\n' "$LAST" | grep -qF '"key": "skip:blocked_label"' \
  && printf '%s\n' "$LAST" | grep -qF '"event": "proposed"'; then
  pass "T7: rejected key exits 0 (handled) and can be re-proposed"
else
  fail "T7: rejected-key semantics broken (rc=$RC_REJ, last=$LAST)"
fi

# ── T8: the command never edits anything outside the proposals ledger ──
BEFORE="$( cd "$R" && git status --porcelain && git log --format=%H -1 )"
run_lint --record >/dev/null
run_lint >/dev/null || true
AFTER="$( cd "$R" && git status --porcelain && git log --format=%H -1 )"
if [ "$BEFORE" = "$AFTER" ] && [ ! -e "$R/src" ] && [ ! -e "$R/skills" ]; then
  pass "T8: working tree and history untouched — no skill/src edits"
else
  fail "T8: corrections mutated the repo beyond the (ignored) ledger"
fi

# ── T9: threshold flag reclassifies recurrence ──
OUT="$(run_lint --threshold 3 --json)"
if printf '%s\n' "$OUT" | python3 -c '
import sys, json
d = json.load(sys.stdin)
keys = [r["key"] for r in d["recurring"]]
assert keys == [], keys
'; then
  pass "T9: --threshold 3 reclassifies 2-cycle scopes as non-recurring"
else
  fail "T9: threshold flag not honored"
fi

# ── T10: --json report shape ──
if run_lint --json | python3 -c '
import sys, json
d = json.load(sys.stdin)
keys = {r["key"]: r for r in d["recurring"]}
assert keys["review-fix:auth"]["count"] == 2, d
assert keys["review-fix:auth"]["status"] == "landed", d
assert keys["skip:blocked_label"]["status"] == "proposed", d
assert set(keys["review-fix:auth"]) >= {"key", "count", "kind", "summary", "evidence", "status"}, d
'; then
  pass "T10: --json carries recurring keys, counts, and ledger statuses"
else
  fail "T10: --json shape wrong"
fi

# ── T12: --record --json keeps stdout pure JSON and the ledger view fresh ──
R3="$TMP/jsonrepo"
mkdir -p "$R3"
git -C "$R3" init -q
git -C "$R3" config user.email t@t.co
git -C "$R3" config user.name t
(
  cd "$R3"
  echo a > a.txt && git add a.txt && git commit -qm "feat(api): init (#1)"
  echo b > b.txt && git add b.txt && git commit -qm "fix(api): address review feedback (#1)"
  echo c > c.txt && git add c.txt && git commit -qm "fix(api): address review feedback (#1)"
)
if ( cd "$R3" && python3 "$LINT" corrections --record --json 2>/dev/null ) | python3 -c '
import sys, json
d = json.load(sys.stdin)
assert d["ledger"]["review-fix:api"] == "proposed", d
assert d["recurring"][0]["status"] == "proposed", d
'; then
  pass "T12: --record --json stdout is pure JSON with fresh ledger state"
else
  fail "T12: --record --json polluted stdout or stale ledger view"
fi

# ── T11: no signals → clean pass, exit 0 ──
R2="$TMP/clean"
mkdir -p "$R2"
git -C "$R2" init -q
git -C "$R2" config user.email t@t.co
git -C "$R2" config user.name t
( cd "$R2" && echo a > a.txt && git add a.txt && git commit -qm "feat(app): init (#1)" )
if OUT="$( cd "$R2" && python3 "$LINT" corrections )" && printf '%s\n' "$OUT" | grep -qF "no recurring corrections found"; then
  pass "T11: repo without corrections passes with exit 0"
else
  fail "T11: clean repo should exit 0"
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
