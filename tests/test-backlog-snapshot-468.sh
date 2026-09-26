#!/usr/bin/env bash
# test-backlog-snapshot-468.sh — shared cached backlog snapshot (issue #468).
#
# Offline and hermetic: no network, no gh auth, no GitHub repository. The only
# `gh` any case reaches is a stub on PATH that logs every call and prints a
# fixture backlog honoring --limit. Freshness is exercised by rewriting
# meta.fetched_at, never by sleeping.
#
#   T1  gi-backlog.py is committed 0755, --help exits 0, bad input exits 3,
#       gh failure exits 4
#   T2  (AC1) a read inside the TTL costs no gh call; an expired one refetches
#   T3  (AC1) the serve rule: field superset, limit, repo, future timestamp
#   T4  (AC2) triage-shaped read + the REAL gi-dup-score.py --snapshot share one
#       gh call, in both orders, with scores byte-equal to a live run
#   T5  (AC3) --status reports staleness; --refresh and --invalidate refetch
#   T6  (AC4) corrupt/garbage snapshots and an unwritable cache dir degrade to a
#       live fetch; dup-score without (or with a broken) gi-backlog still scores
#   T7  truncation rule, --out bare array <= limit, file mode 0600
#   T8  skill wiring: triage + creator cite and bundle gi-backlog, fallback kept
#
# Usage: bash tests/test-backlog-snapshot-468.sh
# Returns: exit 0 if all tests pass, exit 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$REPO_ROOT/src/shared/scripts"
BACKLOG="$SCRIPTS/gi-backlog.py"
DUP="$SCRIPTS/gi-dup-score.py"
SKILLS="$REPO_ROOT/skills"

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "◆ Shared backlog snapshot (issue #468)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ── stub gh: logs each call, prints GH_FIXTURE honoring --limit ──────────────
STUB="$TMP/bin"; mkdir -p "$STUB"
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env python3
import json, os, sys
with open(os.environ["GH_LOG"], "a", encoding="utf-8") as log:
    log.write(" ".join(sys.argv[1:]) + "\n")
if os.environ.get("GH_FAIL"):
    sys.stderr.write("HTTP 502: backend down\n")
    sys.exit(1)
rows = json.load(open(os.environ["GH_FIXTURE"], encoding="utf-8"))
args = sys.argv[1:]
limit = int(args[args.index("--limit") + 1]) if "--limit" in args else 30
fields = args[args.index("--json") + 1].split(",") if "--json" in args else []
print(json.dumps([{f: r[f] for f in fields if f in r} for r in rows[:limit]]))
STUBEOF
chmod +x "$STUB/gh"

# Fixture: n open issues with every superset field.
make_fixture() { # make_fixture <file> <n>
  python3 - "$1" "$2" <<'PY'
import json, sys
n = int(sys.argv[2])
rows = [{"number": i, "title": f"Ship duplicate scorer {i}" if i == 1 else f"Unrelated task {i}",
         "body": "duplicate scorer runtime" if i == 1 else f"body {i}",
         "labels": [{"name": "feature"}], "assignees": [], "state": "OPEN",
         "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "2026-01-02T00:00:00Z"}
        for i in range(1, n + 1)]
json.dump(rows, open(sys.argv[1], "w"))
PY
}
FIX="$TMP/fixture.json"; make_fixture "$FIX" 5
LOG="$TMP/gh.log"
export GH_FIXTURE="$FIX" GH_LOG="$LOG"
export PATH="$STUB:$PATH"

calls() { [ -f "$LOG" ] && wc -l < "$LOG" | tr -d ' ' || echo 0; }
reset_log() { : > "$LOG"; }
jkey() { python3 -c 'import json,sys; v=json.load(sys.stdin)
for k in sys.argv[1].split("."): v=v[k]
print(json.dumps(v))' "$1"; }
# backdate <cache-dir> <seconds>: move every snapshot's fetched_at into the past
backdate() {
  python3 - "$1" "$2" <<'PY'
import json, pathlib, sys, time
for p in pathlib.Path(sys.argv[1]).glob("backlog-open-*.json"):
    d = json.loads(p.read_text())
    d["meta"]["fetched_at"] = time.time() - float(sys.argv[2])
    p.write_text(json.dumps(d))
PY
}
TRIAGE_FIELDS="number,title,body,labels,assignees,state,createdAt,updatedAt"

# ───────────────────────────────────────────────────────────
# T1: script contract
# ───────────────────────────────────────────────────────────
mode="$(cd "$REPO_ROOT" && git ls-files -s src/shared/scripts/gi-backlog.py | awk '{print $1}')"
[ "$mode" = "100755" ] && pass "T1: gi-backlog.py is committed 100755" \
  || fail "T1: gi-backlog.py git mode is '$mode', want 100755"
python3 "$BACKLOG" --help >/dev/null 2>&1 && pass "T1: --help exits 0" || fail "T1: --help failed"
python3 "$BACKLOG" --fields number,bogus --cache-dir "$TMP/c1" >/dev/null 2>"$TMP/e"; s=$?
[ "$s" = 3 ] && grep -q '^✗ gi-backlog:' "$TMP/e" && pass "T1: a field outside the superset exits 3" \
  || fail "T1: bad --fields exit $s"
python3 "$BACKLOG" --ttl -1 --cache-dir "$TMP/c1" >/dev/null 2>&1; s=$?
[ "$s" = 3 ] && pass "T1: a negative --ttl exits 3" || fail "T1: --ttl -1 exit $s"
python3 "$BACKLOG" --limit 0 --cache-dir "$TMP/c1" >/dev/null 2>&1; s=$?
[ "$s" = 3 ] && pass "T1: --limit 0 exits 3" || fail "T1: --limit 0 exit $s"
GH_FAIL=1 python3 "$BACKLOG" --cache-dir "$TMP/c1" >/dev/null 2>"$TMP/e"; s=$?
[ "$s" = 4 ] && grep -q '^⚠ gi-backlog:' "$TMP/e" && pass "T1: a gh failure exits 4" \
  || fail "T1: gh failure exit $s"
python3 "$BACKLOG" --status --invalidate >/dev/null 2>&1; s=$?
[ "$s" = 2 ] && pass "T1: --status and --invalidate are mutually exclusive (exit 2)" \
  || fail "T1: --status --invalidate exit $s"

# ───────────────────────────────────────────────────────────
# T2 (AC1): TTL hit costs zero gh calls; expiry refetches
# ───────────────────────────────────────────────────────────
C="$TMP/c2"; reset_log
o1="$(python3 "$BACKLOG" --limit 3 --cache-dir "$C")"
o2="$(python3 "$BACKLOG" --limit 3 --cache-dir "$C")"
if [ "$(printf '%s' "$o1" | jkey cached)" = false ] && [ "$(printf '%s' "$o2" | jkey cached)" = true ] \
   && [ "$(calls)" = 1 ] && [ "$(printf '%s' "$o1" | jkey issues)" = "$(printf '%s' "$o2" | jkey issues)" ]; then
  pass "AC1: a second read inside the TTL is served from the snapshot (1 gh call, same rows)"
else
  fail "AC1: TTL hit (calls=$(calls))"
fi
grep -q -- "--limit 4" "$LOG" && grep -q -- "--json $TRIAGE_FIELDS" "$LOG" \
  && pass "AC1: the fetch asks for the full superset at limit + 1 (truncation probe)" \
  || fail "AC1: fetch shape: $(cat "$LOG")"
backdate "$C" 301; reset_log
o3="$(python3 "$BACKLOG" --limit 3 --cache-dir "$C")"
[ "$(printf '%s' "$o3" | jkey cached)" = false ] && [ "$(calls)" = 1 ] \
  && pass "AC1: a snapshot older than the TTL is refetched" || fail "AC1: expiry (calls=$(calls))"
backdate "$C" 30; reset_log
o4="$(python3 "$BACKLOG" --limit 3 --ttl 20 --cache-dir "$C")"
[ "$(printf '%s' "$o4" | jkey cached)" = false ] && [ "$(calls)" = 1 ] \
  && pass "AC1: --ttl narrows the freshness window" || fail "AC1: --ttl 20 on a 30s snapshot"
reset_log
o5="$(python3 "$BACKLOG" --limit 3 --ttl 0 --cache-dir "$C")"
o6="$(python3 "$BACKLOG" --limit 3 --cache-dir "$C")"
[ "$(printf '%s' "$o5" | jkey cached)" = false ] && [ "$(printf '%s' "$o6" | jkey cached)" = true ] \
  && [ "$(calls)" = 1 ] \
  && pass "AC1: --ttl 0 always fetches live, yet still leaves a snapshot for the next reader" \
  || fail "AC1: --ttl 0 (calls=$(calls))"

# ───────────────────────────────────────────────────────────
# T3 (AC1): serve rule — subset, limit, repo, clock
# ───────────────────────────────────────────────────────────
C="$TMP/c3"; reset_log
python3 "$BACKLOG" --limit 3 --cache-dir "$C" >/dev/null
o="$(python3 "$BACKLOG" --limit 2 --fields number,title --cache-dir "$C")"
[ "$(calls)" = 1 ] && [ "$(printf '%s' "$o" | jkey issues)" = '[{"number": 1, "title": "Ship duplicate scorer 1"}, {"number": 2, "title": "Unrelated task 2"}]' ] \
  && pass "AC1: a smaller limit and a field subset are served and projected from the snapshot" \
  || fail "AC1: subset projection: $o"
reset_log
o="$(python3 "$BACKLOG" --limit 4 --cache-dir "$C")"
[ "$(printf '%s' "$o" | jkey cached)" = false ] && [ "$(calls)" = 1 ] \
  && pass "AC1: a larger limit than the snapshot captured is a miss" || fail "AC1: larger limit hit"
C="$TMP/c3b"; reset_log
python3 "$BACKLOG" --limit 10 --cache-dir "$C" >/dev/null   # 5 rows < fetch_limit 11: whole backlog
o="$(python3 "$BACKLOG" --limit 50 --cache-dir "$C")"
[ "$(printf '%s' "$o" | jkey cached)" = true ] && [ "$(calls)" = 1 ] \
  && pass "AC1: a snapshot that captured the whole backlog answers any limit" \
  || fail "AC1: whole-backlog snapshot missed"
reset_log
o="$(python3 "$BACKLOG" --limit 3 --repo other/repo --cache-dir "$C")"
[ "$(printf '%s' "$o" | jkey cached)" = false ] && grep -q -- "--repo other/repo" "$LOG" \
  && pass "AC1: a snapshot is scoped to its repo" || fail "AC1: repo scoping"
backdate "$C" -600; reset_log
o="$(python3 "$BACKLOG" --limit 3 --cache-dir "$C")"
[ "$(printf '%s' "$o" | jkey cached)" = false ] && [ "$(calls)" = 1 ] \
  && pass "AC1: a snapshot stamped in the future is a miss" || fail "AC1: future timestamp served"

# ───────────────────────────────────────────────────────────
# T4 (AC2): two consumers, one fetch — the REAL dup-score, default cache dir
# ───────────────────────────────────────────────────────────
REQ='{"mode":"create","items":[{"index":1,"title":"Ship duplicate scorer","keywords":["runtime"],"type":"feature"}]}'
LIVE_DIR="$TMP/live"; mkdir -p "$LIVE_DIR"; reset_log
live="$(cd "$LIVE_DIR" && printf '%s' "$REQ" | python3 "$DUP")"
live_calls="$(calls)"
[ -d "$LIVE_DIR/.gitissue" ] && fail "AC2: dup-score without --snapshot wrote a snapshot" \
  || pass "AC2: dup-score without --snapshot never touches the snapshot (opt-in)"

W="$TMP/ws-a"; mkdir -p "$W"; reset_log
(cd "$W" && python3 "$BACKLOG" --limit 100 --fields "$TRIAGE_FIELDS" >/dev/null)
shared="$(cd "$W" && printf '%s' "$REQ" | python3 "$DUP" --snapshot)"
if [ "$(calls)" = 1 ] && [ "$shared" = "$live" ]; then
  pass "AC2: triage read then dup-score --snapshot share ONE gh call; scores byte-equal a live run"
else
  fail "AC2: triage→dup-score (calls=$(calls), live calls=$live_calls, equal=$([ "$shared" = "$live" ] && echo y || echo n))"
fi

W="$TMP/ws-b"; mkdir -p "$W"; reset_log
shared="$(cd "$W" && printf '%s' "$REQ" | python3 "$DUP" --snapshot)"
o="$(cd "$W" && python3 "$BACKLOG" --limit 100 --fields "$TRIAGE_FIELDS")"
if [ "$(calls)" = 1 ] && [ "$shared" = "$live" ] && [ "$(printf '%s' "$o" | jkey cached)" = true ] \
   && [ "$(printf '%s' "$o" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["issues"][0]))')" = 8 ]; then
  pass "AC2: dup-score --snapshot then a triage read share ONE gh call with every triage field"
else
  fail "AC2: dup-score→triage (calls=$(calls))"
fi

# Truncation parity: a backlog above the limit reports scan_truncated either way.
make_fixture "$TMP/big.json" 7
W="$TMP/ws-c"; mkdir -p "$W"; reset_log
live_t="$(cd "$LIVE_DIR" && printf '%s' "$REQ" | GH_FIXTURE="$TMP/big.json" python3 "$DUP" --limit 5)"
snap_t="$(cd "$W" && printf '%s' "$REQ" | GH_FIXTURE="$TMP/big.json" python3 "$DUP" --limit 5 --snapshot)"
[ "$live_t" = "$snap_t" ] && [ "$(printf '%s' "$snap_t" | jkey scan_truncated)" = true ] \
  && pass "AC2: scan_truncated and scores match the live path on an over-limit backlog" \
  || fail "AC2: truncation parity"

# ───────────────────────────────────────────────────────────
# T5 (AC3): stale snapshot detectable and refreshable on demand
# ───────────────────────────────────────────────────────────
C="$TMP/c5"
st="$(python3 "$BACKLOG" --status --cache-dir "$C")"
[ "$(printf '%s' "$st" | jkey exists)" = false ] && [ "$(printf '%s' "$st" | jkey fresh)" = false ] \
  && pass "AC3: --status on no snapshot reports exists:false" || fail "AC3: status/no snapshot: $st"
reset_log
python3 "$BACKLOG" --limit 3 --cache-dir "$C" >/dev/null
st="$(python3 "$BACKLOG" --status --cache-dir "$C")"
[ "$(printf '%s' "$st" | jkey fresh)" = true ] && [ "$(printf '%s' "$st" | jkey row_count)" = 4 ] \
  && pass "AC3: --status on a new snapshot reports fresh:true" || fail "AC3: status fresh: $st"
backdate "$C" 400
st="$(python3 "$BACKLOG" --status --cache-dir "$C")"
[ "$(printf '%s' "$st" | jkey fresh)" = false ] && [ "$(printf '%s' "$st" | jkey age_s)" -ge 400 ] && [ "$(calls)" = 1 ] \
  && pass "AC3: a backdated snapshot is detectable as stale, without a fetch" || fail "AC3: stale status: $st"
backdate "$C" 10; reset_log
o="$(python3 "$BACKLOG" --limit 3 --refresh --cache-dir "$C")"
[ "$(printf '%s' "$o" | jkey cached)" = false ] && [ "$(calls)" = 1 ] \
  && [ "$(python3 "$BACKLOG" --status --cache-dir "$C" | jkey age_s)" -lt 10 ] \
  && pass "AC3: --refresh refetches a fresh snapshot and rewrites it" || fail "AC3: --refresh"
reset_log
inv="$(python3 "$BACKLOG" --invalidate --cache-dir "$C")"
[ "$inv" = '{"invalidated": true, "dropped": 1}' ] && [ "$(calls)" = 0 ] \
  && [ -z "$(ls "$C"/backlog-open-*.json 2>/dev/null)" ] \
  && pass "AC3: --invalidate drops the snapshot without a fetch" || fail "AC3: --invalidate: $inv"
o="$(python3 "$BACKLOG" --limit 3 --cache-dir "$C")"
[ "$(printf '%s' "$o" | jkey cached)" = false ] && [ "$(calls)" = 1 ] \
  && pass "AC3: the read after --invalidate refetches" || fail "AC3: post-invalidate read"

# ───────────────────────────────────────────────────────────
# T6 (AC4): misses and corruption degrade, never fail
# ───────────────────────────────────────────────────────────
C="$TMP/c6"
python3 "$BACKLOG" --limit 3 --cache-dir "$C" >/dev/null
SNAP="$(ls "$C"/backlog-open-*.json)"
# Fresh-stamped snapshots with one wrong-typed meta key: each must still miss,
# not crash (a list-of-lists `fields` used to raise TypeError -> exit 1).
NOW="$(date +%s)"
fresh() { # fresh <fields> <fetch_limit> <repo> <row_count> <issues> [fetched_at]
  printf '{"meta":{"fetched_at":%s,"fetch_limit":%s,"fields":%s,"repo":%s,"row_count":%s},"issues":%s}' \
    "${6:-$NOW}" "$2" "$1" "$3" "$4" "$5"
}
i=0
for garbage in 'not json at all' '{"meta":{}}' '[1,2,3]' '{"meta":{"fetched_at":"x","fetch_limit":4,"fields":[],"repo":null,"row_count":0},"issues":[]}' \
               '{"meta":{"fetched_at":9e18,"fetch_limit":4,"fields":["number"],"repo":null,"row_count":9},"issues":[]}' '' \
               "$(fresh '[["number"]]' 4 null 0 '[]')" "$(fresh '["number",1]' 4 null 0 '[]')" \
               "$(fresh '["number"]' true null 0 '[]')" "$(fresh '["number"]' 4 5 0 '[]')" \
               "$(fresh '["number"]' 4 null 1 '[1]')" "$(fresh '["number"]' 4 null 0 '[]' Infinity)" \
               "$(fresh '["number"]' 4 null 0 '[]' "1$(printf '0%.0s' $(seq 400))")"; do
  i=$((i + 1))
  printf '%s' "$garbage" > "$SNAP"; reset_log
  python3 "$BACKLOG" --status --cache-dir "$C" >/dev/null 2>&1; st=$?
  o="$(python3 "$BACKLOG" --limit 3 --cache-dir "$C" 2>/dev/null)"; s=$?
  if [ "$st" = 0 ] && [ "$s" = 0 ] && [ "$(printf '%s' "$o" | jkey cached)" = false ] && [ "$(calls)" = 1 ] \
     && [ "$(jkey meta.fields < "$SNAP")" = '["number", "title", "body", "labels", "assignees", "state", "createdAt", "updatedAt"]' ]; then
    pass "AC4: corrupt snapshot #$i: --status exits 0; a read degrades to a live fetch and rewrites it"
  else
    fail "AC4: corrupt snapshot #$i (status exit $st, exit $s, calls=$(calls))"
  fi
done
head -c 40 "$SNAP" > "$SNAP.cut" && mv "$SNAP.cut" "$SNAP"; reset_log
python3 "$BACKLOG" --limit 3 --cache-dir "$C" >/dev/null 2>&1; s=$?
[ "$s" = 0 ] && [ "$(calls)" = 1 ] && pass "AC4: a half-written snapshot degrades to a live fetch" \
  || fail "AC4: truncated snapshot exit $s"

printf 'x' > "$TMP/notadir"
o="$(python3 "$BACKLOG" --limit 3 --cache-dir "$TMP/notadir/cache" 2>/dev/null)"; s=$?
[ "$s" = 0 ] && [ "$(printf '%s' "$o" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["issues"]))')" = 3 ] \
  && pass "AC4: an unwritable cache dir still answers (exit 0)" || fail "AC4: unwritable cache dir exit $s"

# dup-score with gi-backlog.py absent, and with a broken one, still scores live.
for variant in missing broken exits3; do
  D="$TMP/dup-$variant"; mkdir -p "$D/w"
  cp "$DUP" "$SCRIPTS/gi-gh.py" "$D/"
  case "$variant" in
    broken) printf 'raise RuntimeError("boom")\n' > "$D/gi-backlog.py" ;;
    exits3) printf 'import sys\nsys.exit(3)\n' > "$D/gi-backlog.py" ;;
  esac
  reset_log
  out="$(cd "$D/w" && printf '%s' "$REQ" | python3 "$D/gi-dup-score.py" --snapshot 2>/dev/null)"; s=$?
  if [ "$s" = 0 ] && [ "$out" = "$live" ]; then
    pass "AC4: dup-score --snapshot with gi-backlog.py $variant falls back to its own fetch"
  else
    fail "AC4: dup-score with gi-backlog.py $variant (exit $s)"
  fi
done
W="$TMP/ws-corrupt"; mkdir -p "$W/.gitissue/cache"
(cd "$W" && python3 "$BACKLOG" --limit 3 >/dev/null)
for f in "$W"/.gitissue/cache/backlog-open-*.json; do printf '{{{' > "$f"; done
out="$(cd "$W" && printf '%s' "$REQ" | python3 "$DUP" --snapshot)"; s=$?
[ "$s" = 0 ] && [ "$out" = "$live" ] && pass "AC4: dup-score over a corrupt snapshot scores from a live fetch" \
  || fail "AC4: dup-score over corrupt snapshot (exit $s)"
(cd "$W" && python3 "$BACKLOG" --invalidate >/dev/null)
out="$(cd "$W" && printf '%s' "$REQ" | GH_FAIL=1 python3 "$DUP" --snapshot 2>/dev/null)"; s=$?
[ "$s" = 4 ] && pass "AC4: an unreadable backlog is still exit 4 for dup-score, never 3" \
  || fail "AC4: dup-score gh failure exit $s"

# ───────────────────────────────────────────────────────────
# T7: truncation, --out, file mode
# ───────────────────────────────────────────────────────────
C="$TMP/c7"
o="$(python3 "$BACKLOG" --limit 5 --cache-dir "$C")"
[ "$(printf '%s' "$o" | jkey truncated)" = false ] && pass "T7: exactly-limit backlog is not truncated" \
  || fail "T7: 5 rows at limit 5 flagged truncated"
o="$(python3 "$BACKLOG" --limit 4 --cache-dir "$C")"
[ "$(printf '%s' "$o" | jkey truncated)" = true ] \
  && [ "$(printf '%s' "$o" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["issues"]))')" = 4 ] \
  && pass "T7: row_count > limit is truncated, and the probe row never leaks" || fail "T7: truncation at limit 4"
o="$(python3 "$BACKLOG" --limit 2 --fields number --out "$TMP/out.json" --cache-dir "$C")"
if [ "$(cat "$TMP/out.json")" = '[{"number": 1}, {"number": 2}]' ] \
   && printf '%s' "$o" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "issues" not in d and d["truncated"] is True'; then
  pass "T7: --out writes the bare array (<= limit rows) and omits issues from stdout"
else
  fail "T7: --out: $o / $(cat "$TMP/out.json")"
fi
perm="$(python3 -c 'import os,sys,glob,stat; print(oct(stat.S_IMODE(os.stat(glob.glob(sys.argv[1]+"/backlog-open-*.json")[0]).st_mode)))' "$C")"
[ "$perm" = "0o600" ] && pass "T7: the snapshot is written 0600" || fail "T7: snapshot mode $perm"

# ───────────────────────────────────────────────────────────
# T8: skill wiring (source + built tree)
# ───────────────────────────────────────────────────────────
TRI="$REPO_ROOT/src/skills/issue-triage/SKILL.source.md"
CRE="$REPO_ROOT/src/skills/issue-creator/SKILL.source.md"
grep -q 'python3 shared/scripts/gi-backlog.py --limit 100' "$TRI" \
  && grep -q 'gh issue list --state open --json number,title,body,labels,assignees,state,createdAt,updatedAt --limit 100' "$TRI" \
  && pass "T8: triage Step 1 reads the snapshot and keeps the live gh fallback" \
  || fail "T8: triage Step 1 wiring"
grep -q 'appends `--refresh`' "$TRI" && grep -q 'auto mode appends `--ttl 0`' "$TRI" \
  && pass "T8: triage update refreshes and auto mode never reads a cached list" \
  || fail "T8: triage refresh/auto freshness rule"
grep -q 'gi-dup-score.py --snapshot' "$CRE" && grep -q 'python3 shared/scripts/gi-backlog.py --invalidate' "$CRE" \
  && pass "T8: creator scores through the snapshot and invalidates it after create" \
  || fail "T8: creator wiring"
for skill in issue-triage issue-creator; do
  for f in gi-backlog.py gi-gh.py; do
    src="$SCRIPTS/$f"; dst="$SKILLS/$skill/references/scripts/$f"
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
      pass "T8: $skill bundles a byte-identical $f"
    else
      fail "T8: $skill does not bundle $f"
    fi
  done
done

echo "  Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
