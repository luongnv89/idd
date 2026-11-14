#!/usr/bin/env bash
# test-idd-lint-stats-project.sh — Validate that `idd-lint stats` reports the
# project being analyzed (name + filesystem location) in both text and JSON
# output, and resolves the name via the gh → remote-URL → dirname fallback
# chain without making a network call in --no-github mode.
#
# Behavioral test: it runs scripts/idd-lint.py against throwaway git repos in a
# temp dir, so it needs only python3 + git (no gh, no network).
#
# Usage: bash tests/test-idd-lint-stats-project.sh
# Returns: exit 0 if all tests pass, exit 1 on failure summary.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$REPO_ROOT/scripts/idd-lint.py"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ idd-lint stats — project identity Tests"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Build a throwaway repo with a known remote and a copy of the linter.
make_repo() {
  # $1 = dir name, $2 = optional remote URL
  local d="$TMP/$1"
  mkdir -p "$d/scripts"
  cp "$LINT" "$d/scripts/idd-lint.py"
  git -C "$d" init -q
  git -C "$d" config user.email t@t.co
  git -C "$d" config user.name t
  [ -n "${2:-}" ] && git -C "$d" remote add origin "$2"
  ( cd "$d" && git add -A && git commit -qm "chore: init (#1)" )
  echo "$d"
}

# ── T1: name from remote URL (offline, no gh) ──
R1="$(make_repo acme-app git@github.com:acme/widget.git)"
OUT1="$( cd "$R1" && python3 scripts/idd-lint.py stats --no-github 2>/dev/null )"
if printf '%s\n' "$OUT1" | grep -qF "project  acme/widget"; then
  pass "T1: project name derived from git remote (acme/widget)"
else
  fail "T1: expected 'project  acme/widget' in text output"
fi
# Assert on a 'location ...<basename>' line rather than the full path: git's
# --show-toplevel canonicalizes symlinks (macOS /var → /private/var), so the
# printed path may differ from $R1's literal mktemp path.
if printf '%s\n' "$OUT1" | grep -qE "location .*/acme-app$"; then
  pass "T1: project location shows the checkout path"
else
  fail "T1: expected a 'location .../acme-app' line in text output"
fi

# ── T2: HTTPS remote parses too ──
R2="$(make_repo beta-proj https://github.com/beta/thing.git)"
OUT2="$( cd "$R2" && python3 scripts/idd-lint.py stats --no-github 2>/dev/null )"
if printf '%s\n' "$OUT2" | grep -qF "project  beta/thing"; then
  pass "T2: project name parsed from HTTPS remote (beta/thing)"
else
  fail "T2: expected 'project  beta/thing'"
fi

# ── T3: no remote → falls back to directory basename ──
R3="$(make_repo lonely-repo)"
OUT3="$( cd "$R3" && python3 scripts/idd-lint.py stats --no-github 2>/dev/null )"
if printf '%s\n' "$OUT3" | grep -qF "project  lonely-repo"; then
  pass "T3: project name falls back to directory basename (lonely-repo)"
else
  fail "T3: expected 'project  lonely-repo'"
fi

# ── T4: JSON output carries a project block with name + location ──
JSON="$( cd "$R1" && python3 scripts/idd-lint.py stats --no-github --json 2>/dev/null )"
if printf '%s\n' "$JSON" | python3 -c '
import sys, json
d = json.load(sys.stdin)
p = d.get("project") or {}
assert p.get("name") == "acme/widget", p
assert p.get("location", "").endswith("acme-app"), p
'; then
  pass "T4: --json includes project.name and project.location"
else
  fail "T4: --json project block missing or wrong"
fi

# ── T5: --no-github makes NO gh call (fake failing gh must never be invoked) ──
FAKEBIN="$TMP/fakebin"
mkdir -p "$FAKEBIN"
printf '#!/bin/sh\necho GH_WAS_CALLED >&2\nexit 1\n' > "$FAKEBIN/gh"
chmod +x "$FAKEBIN/gh"
GHERR="$TMP/gh.err"
( cd "$R1" && PATH="$FAKEBIN:$PATH" python3 scripts/idd-lint.py stats --no-github 2>"$GHERR" >/dev/null )
if ! grep -q GH_WAS_CALLED "$GHERR"; then
  pass "T5: --no-github resolves project name without invoking gh"
else
  fail "T5: gh was called in --no-github mode (should be offline)"
fi

# ── T6: unexplained QA ceiling breach is a distinct stats failure (#308) ──
R6="$(make_repo ceil-repo git@github.com:acme/ceil.git)"
mkdir -p "$R6/.idd"
printf '%s\n' \
  '{"ts":"2026-07-09T00:00:00Z","issue":10,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":1,"complexity":"medium","qa_cycles":3}' \
  > "$R6/.idd/runs.jsonl"
set +e
( cd "$R6" && python3 scripts/idd-lint.py stats --no-github >/dev/null 2>&1 )
RC6=$?
set -e
if [ "$RC6" -eq 1 ]; then
  pass "T6: unexplained class-ceiling breach exits 1"
else
  fail "T6: expected exit 1 for unexplained qa_cycles>2, got $RC6"
fi
printf '%s\n' \
  '{"ts":"2026-07-09T00:00:00Z","issue":260,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":1,"complexity":"high","qa_cycles":5}' \
  > "$R6/.idd/runs.jsonl"
if ( cd "$R6" && python3 scripts/idd-lint.py stats --no-github >/dev/null 2>&1 ); then
  pass "T6b: high-class qa_cycles=5 without reason still passes"
else
  fail "T6b: high-class within qa_max should pass"
fi

# ── T7–T8: look back after the merge (#568, VW19) ──
# History, oldest first: PR 11 (tag v0.1.0), PR 13, PR 15 (tags v0.2.0 and a
# non-version `latest`), PR 17, a real `git revert` of PR 13, then PR 19 whose
# message says "revert" without git's footer. PR 99 is logged but landed
# nowhere. PR 11 is logged twice (resolver success + auto-pilot merged) and
# PR 13's row records skill_version 0.2.0, which must key the same release as
# the v0.2.0 tag rather than splitting into a "0.2.0" bucket.
R7="$(make_repo look-repo git@github.com:acme/look.git)"
land() {  # $1 = file, $2 = subject, $3 = optional body
  echo "$1" > "$R7/$1.txt"
  git -C "$R7" add "$1.txt"
  if [ -n "${3:-}" ]; then git -C "$R7" commit -qm "$2" -m "$3"; else git -C "$R7" commit -qm "$2"; fi
  git -C "$R7" rev-parse HEAD
}
SHA11="$(land a 'feat(a): add a (#10) (#11)')"
git -C "$R7" tag v0.1.0
SHA13="$(land b 'feat(b): add b (#12) (#13)')"
SHA15="$(land c 'feat(c): add c (#14) (#15)')"
git -C "$R7" tag v0.2.0
git -C "$R7" tag latest
SHA17="$(land d 'feat(d): add d (#16) (#17)')"
git -C "$R7" revert --no-edit "$SHA13" >/dev/null
SHA19="$(land e 'fix(e): revert the widget default (#18) (#19)' \
  'Reverts the timeout tweak; this reverts the approach from #17 and #15.')"
mkdir -p "$R7/.idd"
printf '%s\n' \
  '{"ts":"2026-03-01T12:00:00Z","issue":10,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":11}' \
  '{"ts":"2026-03-01T13:00:00Z","issue":10,"mode":"auto","skill":"auto-pilot","outcome":"merged","pr":11}' \
  '{"ts":"2026-03-02T12:00:00Z","issue":12,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":13,"skill_version":"0.2.0"}' \
  '{"ts":"2026-03-03T12:00:00Z","issue":14,"mode":"auto","skill":"auto-pilot","outcome":"merged","pr":15}' \
  '{"ts":"2026-03-04T12:00:00Z","issue":16,"mode":"auto","skill":"auto-pilot","outcome":"merged","pr":17}' \
  '{"ts":"2026-03-05T12:00:00Z","issue":18,"mode":"auto","skill":"auto-pilot","outcome":"merged","pr":19}' \
  '{"ts":"2026-03-06T12:00:00Z","issue":98,"mode":"auto","skill":"auto-pilot","outcome":"failed","pr":99}' \
  '{"ts":"2026-03-07T12:00:00Z","issue":50,"mode":"auto","skill":"auto-pilot","outcome":"skipped","pr":null}' \
  > "$R7/.idd/runs.jsonl"

# T7: offline — reverts and releases come from git alone, no gh call is made,
# and the GitHub-only counts are null, not a measured 0.
GHERR7="$TMP/gh7.err"
JSON7="$( cd "$R7" && PATH="$FAKEBIN:$PATH" python3 scripts/idd-lint.py stats --no-github --json 2>"$GHERR7" )"
if printf '%s\n' "$JSON7" | python3 -c '
import sys, json
lb = json.load(sys.stdin)["lookback"]
t = lb["total"]
assert lb["github"] is False, lb
assert t["merged_runs"] == 5, t            # PR 11 counted once; 99 is not merged
assert t["unconfirmed"] == 1 and lb["prs"]["unconfirmed"] == [99], lb
assert t["reverted"] == 1 and lb["prs"]["reverted"] == [13], lb  # decoy PR 19 is not
for key in ("reopened", "followed_up", "planned_followups", "flagged", "flagged_pct"):
    assert t[key] is None, (key, t)
assert lb["prs"]["reopened"] is None and lb["prs"]["followed_up"] is None, lb
rel = lb["by_release"]
assert sorted(rel) == ["unreleased", "v0.1.0", "v0.2.0"], sorted(rel)
assert rel["v0.1.0"]["merged_runs"] == 1 and rel["v0.1.0"]["reverted"] == 0, rel
assert rel["v0.2.0"]["merged_runs"] == 2 and rel["v0.2.0"]["reverted"] == 1, rel
assert rel["v0.2.0"]["keyed_by"] == {"skill_version": 1, "history": 1, "none": 0}, rel
assert rel["unreleased"]["merged_runs"] == 2 and rel["unreleased"]["unconfirmed"] == 1, rel
assert rel["unreleased"]["reverted"] == 0, rel
'; then
  pass "T7: offline look-back counts the real revert, not the decoy, per normalized release"
else
  fail "T7: offline look-back JSON is wrong"
fi
if ! grep -q GH_WAS_CALLED "$GHERR7"; then
  pass "T7b: offline look-back makes no gh call"
else
  fail "T7b: gh was called by the offline look-back"
fi
set +e
TEXT7="$( cd "$R7" && python3 scripts/idd-lint.py stats --no-github 2>/dev/null )"
RC7=$?
set -e
if [ "$RC7" -eq 0 ] \
   && printf '%s\n' "$TEXT7" | grep -qF "Look back after merge" \
   && printf '%s\n' "$TEXT7" | grep -qE "reverted +1 of 5 \(#13\)" \
   && printf '%s\n' "$TEXT7" | grep -qE "release v0\.2\.0 +2 merged" \
   && printf '%s\n' "$TEXT7" | grep -qE "reopened +— needs GitHub"; then
  pass "T7c: text report carries the look-back section and a revert does not fail the run"
else
  fail "T7c: look-back text section missing or exit $RC7"
  printf '%s\n' "$TEXT7" | sed 's/^/      /'
fi

# T8: online — the join reads the gh pages the report already fetched. PR 13 is
# both reverted and reopened (flagged once); PR 15's issue is open but its PR
# never closed it (not reopened); PR 17 has a bug-labelled follow-up and PR 15
# a `Bug:`-titled one; PR 19's cross-links are a non-bug, a bug filed before
# the merge, and a planned auto-pilot follow-up; PR 11's own issue is skipped.
T8_ERR="$TMP/t8.err"
if (cd "$R7" && python3 - <<PY
import contextlib, importlib.util, io, json
spec = importlib.util.spec_from_file_location("idd_lint", "scripts/idd-lint.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

MERGED, BEFORE, AFTER = "2026-03-01T12:00:00Z", "2026-02-01T12:00:00Z", "2026-03-09T12:00:00Z"
prs = [
    {"number": 11, "body": "Closes #10", "mergedAt": MERGED, "mergeCommit": {"oid": "$SHA11"}},
    {"number": 13, "body": "Closes #12", "mergedAt": MERGED, "mergeCommit": {"oid": "$SHA13"}},
    {"number": 15, "body": "Implements the thing", "mergedAt": MERGED, "mergeCommit": {"oid": "$SHA15"}},
    {"number": 17, "body": "Fixes #16", "mergedAt": MERGED, "mergeCommit": {"oid": "$SHA17"}},
    {"number": 19, "body": "Resolves #18", "mergedAt": MERGED, "mergeCommit": {"oid": "$SHA19"}},
]
def issue(number, state="CLOSED", created=BEFORE, body="", labels=(), title="t"):
    return {"number": number, "state": state, "stateReason": None, "createdAt": created,
            "body": body, "title": title, "labels": [{"name": n} for n in labels]}
issues = [
    issue(10, created=AFTER, body="Regression of #11", labels=["bug"]),
    issue(12, state="OPEN"),
    issue(14, state="OPEN"),
    issue(16), issue(18),
    issue(30, created=AFTER, body="Broke after #17 landed", labels=["bug"]),
    issue(31, created=AFTER, body="Bug: after #15", title="Bug: crash after merge"),
    issue(32, created=AFTER, body="Docs for #19", labels=["enhancement"]),
    issue(33, created=BEFORE, body="See #19", labels=["bug"]),
    issue(34, created=AFTER, body="From https://github.com/acme/look/pull/19",
          labels=["auto-pilot-followup", "bug"]),
]
calls = []
def fake_gh(*args):
    calls.append(args)
    if args[:2] == ("repo", "view"):
        return {"nameWithOwner": "acme/look"}
    if args[:2] == ("pr", "list"):
        return prs
    if args[:2] == ("issue", "list"):
        return issues if "all" in args else []
    return None
m._gh_json = fake_gh

out = io.StringIO()
with contextlib.redirect_stdout(out):
    rc = m.main(["stats", "--json"])
assert rc == 0, rc
lb = json.loads(out.getvalue())["lookback"]
t, listed = lb["total"], lb["prs"]
assert lb["github"] is True, lb
assert sum(a[:2] == ("pr", "list") for a in calls) == 1, calls
assert sum(a[:2] == ("issue", "list") and "all" in a for a in calls) == 1, calls
assert listed["reverted"] == [13], listed
assert listed["reopened"] == [13], listed            # 15: open, but never closed by its PR
assert listed["followed_up"] == [15, 17], listed     # not 11 (own issue), not 19
assert t["planned_followups"] == 1, t                # issue 34 against PR 19
assert t["unconfirmed"] == 1 and listed["unconfirmed"] == [99], t
assert t["merged_runs"] == 5, t
assert t["flagged"] == 3 and t["flagged_pct"] == 60, t   # 13 counted once
rel = lb["by_release"]
assert (rel["v0.2.0"]["flagged"], rel["v0.2.0"]["flagged_pct"]) == (2, 100), rel
assert (rel["v0.1.0"]["flagged"], rel["v0.1.0"]["merged_runs"]) == (0, 1), rel
assert (rel["unreleased"]["flagged"], rel["unreleased"]["flagged_pct"]) == (1, 50), rel
assert rel["unreleased"]["planned_followups"] == 1, rel
assert "_page" not in out.getvalue(), "a private page leaked into the report"
PY
) 2>"$T8_ERR"; then
  pass "T8: online look-back joins reopened issues and follow-up bugs from the shared gh pages"
else
  fail "T8: online look-back join is wrong"
  sed 's/^/      /' "$T8_ERR"
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
