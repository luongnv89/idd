#!/usr/bin/env bash
# test-stats-573.sh — `/auto-pilot --stats` ships the run-log stats in an
# installed skill (issue #573).
#
#   T1  read-only: the built gi-stats.py leaves a seeded repo byte-identical
#       (.idd/ and .git/ included) with gh and with --no-github, and creates no
#       lock, run state or cache.
#   T2  the only gh calls are the two look-back pages.
#   T3  one source: every mirrored definition is byte-identical to
#       scripts/idd-lint.py, and both reports agree on `runs` and `lookback`.
#   AC1 the report's outcome counts and look-back rates, with and without gh.
#   T4  .github/workflows/dist-check.yml only gains lines.
#   P   prose pins: the --stats row, the precheck line, stats.md's guarantees.
#
# Hermetic: throwaway git repos and a stub `gh` on PATH. No network, no token,
# and the repository itself is never modified.
#
# Usage: bash tests/test-stats-573.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$REPO_ROOT/scripts/idd-lint.py"
SRC_STATS="$REPO_ROOT/src/shared/scripts/gi-stats.py"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ /auto-pilot --stats — read-only run stats (#573)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── Build to a temp dir and run the installed copy ──
BUILD="$TMP/build"
if bash "$REPO_ROOT/scripts/build.sh" --out "$BUILD" --quiet >"$TMP/build.log" 2>&1; then
  pass "build: scripts/build.sh --out <tmp> succeeds"
else
  fail "build: scripts/build.sh --out <tmp> failed"
  sed 's/^/      /' "$TMP/build.log"
  echo "  Passed: $PASS  Failed: $FAIL"
  exit 1
fi
SKILL="$BUILD/skills/auto-pilot"
GS="$SKILL/references/scripts/gi-stats.py"
if [ -f "$GS" ] && [ -f "$SKILL/references/scripts/gi-gh.py" ] \
   && cmp -s "$GS" "$SRC_STATS"; then
  pass "build: auto-pilot bundles gi-stats.py byte-identical, beside gi-gh.py"
else
  fail "build: auto-pilot does not bundle gi-stats.py (and gi-gh.py) intact"
fi

# ── Fixture repo ──
# History, oldest first: PR 11 (tag v0.1.0), PR 13, PR 15 (tag v0.2.0), PR 17,
# a real `git revert` of PR 13, PR 19. origin/main is a remote-tracking ref
# frozen at PR 15, so the default walk is behind both main and GitHub.
R="$TMP/look"
git init -q -b main "$R"
git -C "$R" config user.email t@t.co
git -C "$R" config user.name t
git -C "$R" remote add origin git@github.com:acme/look.git
echo init > "$R/README.md"
git -C "$R" add README.md && git -C "$R" commit -qm "chore: init (#1)"
land() {  # $1 = file, $2 = subject
  echo "$1" > "$R/$1.txt"
  git -C "$R" add "$1.txt"
  git -C "$R" commit -qm "$2"
  git -C "$R" rev-parse HEAD
}
SHA11="$(land a 'feat(a): add a (#10) (#11)')"
git -C "$R" tag v0.1.0
SHA13="$(land b 'feat(b): add b (#12) (#13)')"
SHA15="$(land c 'feat(c): add c (#14) (#15)')"
git -C "$R" tag v0.2.0
git -C "$R" update-ref refs/remotes/origin/main "$SHA15"
git -C "$R" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
SHA17="$(land d 'feat(d): add d (#16) (#17)')"
git -C "$R" revert --no-edit "$SHA13" >/dev/null
SHA19="$(land e 'fix(e): tune e (#18) (#19)')"

mkdir -p "$R/.idd"
# A rotated segment holds the oldest rows; the active log the rest.
printf '%s\n' \
  '{"ts":"2026-03-01T12:00:00Z","issue":10,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":11}' \
  '{"ts":"2026-03-01T13:00:00Z","issue":10,"mode":"auto","skill":"auto-pilot","outcome":"merged","pr":11}' \
  > "$R/.idd/runs-20260302T000000Z.jsonl"
printf '%s\n' \
  '{"ts":"2026-03-02T12:00:00Z","issue":12,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":13,"skill_version":"0.2.0","phases":{"qa":300,"implement":120}}' \
  '{"ts":"2026-03-03T12:00:00Z","issue":14,"mode":"auto","skill":"auto-pilot","outcome":"merged","pr":15,"qa_cycles":3}' \
  '{"ts":"2026-03-04T12:00:00Z","issue":16,"mode":"auto","skill":"auto-pilot","outcome":"merged","pr":17}' \
  '{"ts":"2026-03-05T12:00:00Z","issue":18,"mode":"auto","skill":"auto-pilot","outcome":"merged","pr":19}' \
  '{"ts":"2026-03-06T12:00:00Z","issue":98,"mode":"auto","skill":"auto-pilot","outcome":"failed","pr":99}' \
  '{"ts":"2026-03-07T12:00:00Z","issue":50,"mode":"auto","skill":"auto-pilot","outcome":"skipped","pr":null}' \
  'not json' \
  > "$R/.idd/runs.jsonl"

# Stub gh: answers the two look-back pages plus idd-lint's extra reads, logs
# its argv one call per line to $GH_LOG, and fails anything else.
FIX="$TMP/fixtures"
FAKEBIN="$TMP/bin"
mkdir -p "$FIX" "$FAKEBIN"
python3 - "$FIX" "$SHA11" "$SHA13" "$SHA15" "$SHA17" "$SHA19" <<'PY'
import json, sys
fix, s11, s13, s15, s17, s19 = sys.argv[1:]
MERGED, BEFORE, AFTER = "2026-03-01T12:00:00Z", "2026-02-01T12:00:00Z", "2026-03-09T12:00:00Z"
prs = [
    {"number": 11, "body": "Closes #10", "mergedAt": MERGED, "mergeCommit": {"oid": s11}},
    {"number": 13, "body": "Closes #12", "mergedAt": MERGED, "mergeCommit": {"oid": s13}},
    {"number": 15, "body": "Closes #14", "mergedAt": MERGED, "mergeCommit": {"oid": s15}},
    {"number": 17, "body": "Fixes #16", "mergedAt": MERGED, "mergeCommit": {"oid": s17}},
    {"number": 19, "body": "Resolves #18", "mergedAt": MERGED, "mergeCommit": {"oid": s19}},
]
def issue(number, state="CLOSED", created=BEFORE, body="", labels=(), title="t"):
    return {"number": number, "state": state, "stateReason": None, "createdAt": created,
            "body": body, "title": title, "labels": [{"name": n} for n in labels]}
issues = [
    issue(10), issue(12, state="OPEN"), issue(14), issue(16), issue(18), issue(98),
    issue(30, created=AFTER, body="Broke after #17 landed", labels=["bug"]),
    issue(34, created=AFTER, body="See https://github.com/acme/look/pull/19",
          labels=["auto-pilot-followup"]),
]
json.dump(prs, open(f"{fix}/prs.json", "w"))
json.dump(issues, open(f"{fix}/issues.json", "w"))
PY
cat > "$FAKEBIN/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\${GH_LOG:-/dev/null}"
case "\$1 \$2" in
  "pr list") cat "$FIX/prs.json" ;;
  "issue list")
    case " \$* " in
      *" --state all "*) cat "$FIX/issues.json" ;;
      *) echo '[]' ;;
    esac ;;
  "repo view") echo '{"nameWithOwner":"acme/look"}' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$FAKEBIN/gh"

# Snapshot of every path under the repo: type, size, mtime and content hash.
snapshot() {
  python3 - "$1" <<'PY'
import hashlib, os, sys
root = sys.argv[1]
for dirpath, dirnames, filenames in os.walk(root):
    dirnames.sort()
    st = os.lstat(dirpath)
    print("d", os.path.relpath(dirpath, root), st.st_mtime_ns)
    for name in sorted(filenames):
        path = os.path.join(dirpath, name)
        st = os.lstat(path)
        with open(path, "rb") as fh:
            digest = hashlib.sha256(fh.read()).hexdigest()
        print("f", os.path.relpath(path, root), st.st_size, st.st_mtime_ns, oct(st.st_mode), digest)
PY
}

# ── T1 / T2 / AC1: run the installed copy every way a user can ──
BEFORE="$(snapshot "$R")"
run_gs() {  # $1 = log name, rest = args; prints stdout, records rc
  local log="$1"; shift
  set +e
  ( cd "$R" && GH_LOG="$TMP/$log.gh" PATH="$FAKEBIN:$PATH" python3 "$GS" "$@" ) \
    >"$TMP/$log.out" 2>"$TMP/$log.err"
  echo $? > "$TMP/$log.rc"
  set -e
}
for log in online online_text offline offline_text default_ref default_text; do : > "$TMP/$log.gh"; done
run_gs online --branch main --json
run_gs online_text --branch main
run_gs offline --branch main --no-github --json
run_gs offline_text --branch main --no-github
run_gs default_ref --json
run_gs default_text
AFTER="$(snapshot "$R")"

if [ "$BEFORE" = "$AFTER" ]; then
  pass "T1: the worktree, .idd/ and .git/ are byte-identical after six runs"
else
  fail "T1: gi-stats changed the repository"
  diff <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER") | sed 's/^/      /' | head -20 || true
fi
created=""
for p in .idd/run.lock .idd/run-state.json .idd/cache .idd/last-run-report.md .git/index.lock; do
  [ -e "$R/$p" ] && created="$created $p"
done
if [ -z "$created" ]; then
  pass "T1: no lock, run state, report or cache file appears"
else
  fail "T1: gi-stats created:$created"
fi

all_rc_zero=1
for log in online online_text offline offline_text default_ref default_text; do
  [ "$(cat "$TMP/$log.rc")" = 0 ] || { all_rc_zero=0; echo "      $log exited $(cat "$TMP/$log.rc"): $(cat "$TMP/$log.err")"; }
done
if [ "$all_rc_zero" = 1 ]; then
  pass "AC1: every run exits 0, the unexplained ceiling breach included"
else
  fail "AC1: a report run exited non-zero"
fi

if python3 - "$TMP/online.gh" "$TMP/offline.gh" "$TMP/offline_text.gh" <<'PY'
import sys
online = [l.split() for l in open(sys.argv[1]) if l.strip()]
assert online == [
    "pr list --state merged --limit 200 --json number,body,mergedAt,mergeCommit".split(),
    "issue list --state all --limit 500 --json number,body,state,stateReason,createdAt,labels,title".split(),
], online
for path in sys.argv[2:]:
    assert not open(path).read().strip(), open(path).read()
PY
then
  pass "T2: gh is called only for the two look-back pages, and never offline"
else
  fail "T2: unexpected gh calls"
fi

if python3 - "$TMP/online.out" "$TMP/offline.out" <<'PY'
import json, sys
online, offline = (json.load(open(p)) for p in sys.argv[1:])
assert set(online) == {"github_skipped", "lookback", "runs", "walked", "warnings"}, online.keys()
runs = online["runs"]
assert runs["runs"] == 8, runs
assert runs["outcomes"] == {"failed": 1, "merged": 4, "skipped": 1, "success": 2}, runs["outcomes"]
assert (runs["attempted"], runs["succeeded"], runs["success_pct"]) == (7, 6, 86), runs
assert runs["unexplained_ceiling_breaches"] == 1 and runs["ceiling_breach_issues"] == [14], runs
assert runs["slowest_phase"] == "qa", runs
lb = online["lookback"]
t = lb["total"]
assert online["github_skipped"] is None and lb["github"] is True, online
assert t["merged_runs"] == 5 and t["unconfirmed"] == 1, t
assert t["reverted"] >= 1 and lb["prs"]["reverted"] == [13], lb
assert lb["prs"]["reopened"] == [13] and lb["prs"]["followed_up"] == [17], lb
for key in ("reopened", "followed_up", "planned_followups", "flagged", "flagged_pct"):
    assert isinstance(t[key], int), (key, t)
assert (t["flagged"], t["flagged_pct"], t["planned_followups"]) == (2, 40, 1), t
assert sorted(lb["by_release"]) == ["unreleased", "v0.1.0", "v0.2.0"], lb["by_release"]
assert online["walked"]["ref"] == "main" and len(online["walked"]["sha"]) == 40, online
assert online["warnings"] == [], online["warnings"]
off = offline["lookback"]["total"]
assert offline["github_skipped"] == "--no-github", offline
assert offline["runs"] == runs, "the run outcomes do not depend on gh"
assert off["reverted"] == 1 and offline["lookback"]["prs"]["reverted"] == [13], off
for key in ("reopened", "followed_up", "planned_followups", "flagged", "flagged_pct"):
    assert off[key] is None, (key, off)
PY
then
  pass "AC1: outcomes, success rate, reverts and the gh-backed rates are reported; null offline"
else
  fail "AC1: the JSON report is wrong"
fi

if grep -qF "walked main @ " "$TMP/online_text.out" \
   && grep -qF "Look back after merge" "$TMP/online_text.out" \
   && grep -qE "^  ✓ success +6 of 7 attempted \(86%\)" "$TMP/online_text.out" \
   && grep -qE "^  ✗ unexplained QA ceiling breaches +1 \(#14\)" "$TMP/online_text.out" \
   && grep -qE "^    total +5 +1 +1 +1 +1 +1  2 \(40%\)" "$TMP/online_text.out" \
   && grep -qF "○ needs GitHub" "$TMP/offline_text.out" \
   && ! grep -qF "○ needs GitHub" "$TMP/online_text.out" \
   && python3 -c 'import sys; assert all(len(l) <= 80 for l in open(sys.argv[1], encoding="utf-8").read().splitlines())' "$TMP/online_text.out"; then
  pass "AC1: the text report names the walked ref and the rates within 80 columns"
else
  fail "AC1: the text report is wrong"
  sed 's/^/      /' "$TMP/online_text.out"
fi

# The default walk is origin/main (frozen at PR 15): it says so and warns.
if python3 - "$TMP/default_ref.out" "$SHA15" <<'PY'
import json, sys
report, sha15 = json.load(open(sys.argv[1])), sys.argv[2]
assert report["walked"]["ref"] == "origin/main" and report["walked"]["sha"] == sha15, report["walked"]
warnings = " | ".join(report["warnings"])
assert "local main" in warnings and "differ" in warnings and "git fetch" in warnings, warnings
assert "#17, #19" in warnings and "behind GitHub" in warnings, warnings
PY
then
  pass "AC1: the default walk is origin/<default>, with stale-ref warnings naming git fetch"
else
  fail "AC1: default ref choice or freshness warnings wrong"
fi
if grep -qF "walked origin/main @ " "$TMP/default_text.out" && grep -qF "⚠ local main" "$TMP/default_text.out"; then
  pass "AC1: the text report shows the walked ref and the ⚠ warning"
else
  fail "AC1: default text report lacks the walked ref or the warning"
fi

# ── T3: one source ──
if python3 - "$LINT" "$SRC_STATS" <<'PY'
import ast, sys
NAMES = """SECTION_RE CONFIDENCE_RE SOFT_COMMAND_TIMEOUT_SECONDS MIN_ISSUE_FETCH_LIMIT
DEFAULT_GITHUB_FETCH_LIMIT MAX_RUN_SEGMENTS split_sections strip_confidence first_content_line
CLOSING_KEYWORD_RE SUCCESS_OUTCOMES SKIP_OUTCOMES ISSUE_PAGE_FIELDS _run_soft _merged_at_epoch
_pct _median detect_default_branch DEFAULT_HIGH_CEILING policy_ceiling row_ceiling
_unexplained_ceiling_breach load_run_rows collect_phase_stats slowest_phase collect_skill_costs
collect_run_stats REVERT_FOOTER_RE REVERT_PR_RE SUBJECT_PR_RE RELEASE_TAG_RE SHA_RE
PLANNED_FOLLOWUP_LABEL UNRELEASED HISTORY_FIELDS parse_merge_history collect_merge_history
_release_name _release_sort_key _HistoryIndex _index_history _label_names _is_bug_issue
_new_bucket collect_lookback_stats""".split()

def definitions(path):
    src = open(path, encoding="utf-8").read()
    out = {}
    for node in ast.parse(src).body:
        if isinstance(node, (ast.FunctionDef, ast.ClassDef)):
            name = node.name
        elif (isinstance(node, ast.Assign) and len(node.targets) == 1
              and isinstance(node.targets[0], ast.Name)):
            name = node.targets[0].id
        else:
            continue
        out.setdefault(name, []).append(ast.get_source_segment(src, node))
    return out

lint, stats = definitions(sys.argv[1]), definitions(sys.argv[2])
bad = [n for n in NAMES if n not in lint or n not in stats
       or len(stats[n]) != 1 or lint[n] != stats[n]]
assert not bad, f"mirror drift: {bad}"
PY
then
  pass "T3: all 45 mirrored definitions are byte-identical to scripts/idd-lint.py"
else
  fail "T3: gi-stats.py's mirror drifted from scripts/idd-lint.py"
fi

set +e
( cd "$R" && GH_LOG="$TMP/lint.gh" PATH="$FAKEBIN:$PATH" python3 "$LINT" stats --branch main --json ) \
  >"$TMP/lint.out" 2>"$TMP/lint.err"
LINT_RC=$?
set -e
if [ "$LINT_RC" -le 1 ] && python3 - "$TMP/lint.out" "$TMP/online.out" <<'PY'
import json, sys
lint, stats = (json.load(open(p)) for p in sys.argv[1:])
assert lint["lookback"]["github"] is True, "idd-lint never reached the gh pages"
assert lint["runs"] == stats["runs"], "runs differ"
assert lint["lookback"] == stats["lookback"], "lookback differs"
PY
then
  pass "T3: idd-lint stats and gi-stats agree on runs and lookback (one fixture, same branch)"
else
  fail "T3: idd-lint stats (exit $LINT_RC) and gi-stats disagree"
fi

# ── Edge exits ──
mkdir -p "$TMP/empty" && git init -q -b main "$TMP/empty"
git -C "$TMP/empty" -c user.email=t@t.co -c user.name=t commit -q --allow-empty -m "chore: init"
set +e
( cd "$TMP/empty" && python3 "$GS" --no-github --json ) >"$TMP/empty.out" 2>/dev/null; EMPTY_RC=$?
( cd "$TMP" && python3 "$GS" --no-github ) >/dev/null 2>"$TMP/nogit.err"; NOGIT_RC=$?
( cd "$R" && python3 "$GS" --no-github --branch no-such-ref ) >/dev/null 2>&1; BADREF_RC=$?
python3 "$GS" --help >/dev/null 2>&1; HELP_RC=$?
set -e
if [ "$EMPTY_RC" = 0 ] && python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); assert r["runs"] is None and r["lookback"] is None' "$TMP/empty.out" \
   && [ "$NOGIT_RC" = 4 ] && grep -qF "⚠ gi-stats:" "$TMP/nogit.err" \
   && [ "$BADREF_RC" = 2 ] && [ "$HELP_RC" = 0 ]; then
  pass "exits: empty log 0, outside git 4, bad --branch 2, --help 0"
else
  fail "exits: empty=$EMPTY_RC nogit=$NOGIT_RC badref=$BADREF_RC help=$HELP_RC"
fi

# ── T4: the workflow only gains lines ──
WF=.github/workflows/dist-check.yml
BASE=""
if git -C "$REPO_ROOT" rev-parse --verify --quiet origin/main >/dev/null; then
  BASE="$(git -C "$REPO_ROOT" merge-base HEAD origin/main 2>/dev/null || true)"
fi
if [ -z "$BASE" ]; then
  pass "T4: base ref unavailable (shallow checkout) — removed-line check skipped"
elif git -C "$REPO_ROOT" diff "$BASE" -- "$WF" | grep -E '^-' | grep -vqE '^--- '; then
  fail "T4: $WF lost lines against $BASE"
else
  pass "T4: $WF has no removed lines against the merge base"
fi
if grep -qF "run: bash tests/test-stats-573.sh" "$REPO_ROOT/$WF"; then
  pass "T4: dist-check.yml runs this test as a named step"
else
  fail "T4: dist-check.yml does not run tests/test-stats-573.sh"
fi

# ── P: prose pins on the built skill ──
SKILL_MD="$SKILL/SKILL.md"
STATS_MD="$SKILL/references/stats.md"
if grep -qF '| `/auto-pilot --stats` |' "$SKILL_MD" \
   && grep -qF -- '- `references/scripts/gi-stats.py`' "$SKILL_MD" \
   && grep -qF -- '- `references/stats.md`' "$SKILL_MD"; then
  pass "P: SKILL.md has the --stats row and precheck lines for gi-stats.py and stats.md"
else
  fail "P: SKILL.md lacks the --stats row or its precheck lines"
fi
if [ -f "$STATS_MD" ] \
   && grep -qF "Self-Improve included" "$STATS_MD" \
   && grep -qF "creates no run state, takes no lock" "$STATS_MD" \
   && grep -qF "python3 references/scripts/gi-stats.py" "$STATS_MD" \
   && grep -qF '.idd/runs-*.jsonl` segments (up to 10)' "$STATS_MD" \
   && grep -qF "elapsed n/a" "$STATS_MD"; then
  pass "P: stats.md skips Self-Improve, takes no lock, and keeps the rotated-segment fallback"
else
  fail "P: stats.md lacks a read-only guarantee or the fallback"
fi
# A missing gi-stats.py or gi-gh.py is a broken install (stop), not a degrade;
# any other non-zero exit, exit 1 included, degrades to the hand count.
if [ -f "$STATS_MD" ] && python3 - "$STATS_MD" <<'PY'
import sys
text = " ".join(open(sys.argv[1], encoding="utf-8").read().split())
assert ("check, read-only, that `references/scripts/gi-stats.py` and "
        "`references/scripts/gi-gh.py` exist relative to SKILL.md. Either one "
        "missing is a broken install: stop with the `✗ Missing bundled "
        "dependency` block from `references/preflight.md`") in text
assert "**Any other exit (1 included), no `python3`, or unparsable output**" in text
PY
then
  pass "P: stats.md stops on a missing gi-stats.py or gi-gh.py; other exits degrade"
else
  fail "P: stats.md lacks the missing-dependency stop or the exit-1 degrade"
fi

echo "  ┄"
echo "  Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
