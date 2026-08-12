#!/usr/bin/env bash
# Canonical duplicate scorer regression suite — issue #253 / follow-up #278.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/src/shared/scripts/gi-dup-score.py"
FIXTURE="$ROOT/tests/fixtures/gi-dup-score-backlog.json"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
pass(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
fail(){ echo "  ✗ $1"; FAIL=$((FAIL+1)); }

echo "◆ Canonical duplicate scorer (issue #253)"

python3 - "$SCRIPT" "$FIXTURE" <<'PY' && pass "calibrated fixture and metamorphic invariants" || fail "calibrated fixture or metamorphic invariants"
import importlib.util, itertools, json, sys
spec=importlib.util.spec_from_file_location("dup",sys.argv[1]); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
cfg=m.resolve_config({}, type("A",(),{"limit":None,"high":None,"medium":None})())
data=json.load(open(sys.argv[2]))
# Labels are fixture data independent of output; defaults must realize them.
for case in data["cases"]:
    got=m.band(m.score_pair(case["item"],case["target"],cfg)["score"],cfg)
    assert got==case["label"], (case["id"],got,case["label"])

base={"index":1,"title":"Ship Python 3 café duplicate scorer","keywords":["python 3","café","outside"],"type":"feature"}
target={"title":"Ship python 3 CAFÉ duplicate scorer","body":"outside; Ship python 3 café duplicate scorer","type":"feature"}
expected=m.score_pair(base,target,cfg)
# Each guard proves its trigger and is applied in both item->target and reverse
# target->item directions. A count alone cannot pass: each mutation is asserted.
applied={k:0 for k in ("permutation","grouping","duplicates","overlap","short","unicode","outside","body","reverse")}
def check(name,item,tgt,want=expected):
    assert item["title"] and tgt["title"]
    got=m.score_pair(item,tgt,cfg)
    assert got["score"]==want["score"], (name,got,want)
    assert got["payments"]==want["payments"], (name,got,want)
    applied[name]+=1
for kws in itertools.permutations(base["keywords"]):
    check("permutation",{**base,"keywords":list(kws)},target)
check("grouping",{**base,"keywords":["python","3 café","outside"]},target)
check("duplicates",{**base,"keywords":base["keywords"]*2},target)
check("overlap",{**base,"keywords":["python 3 café","python","3","café","outside"]},target)
check("short",{**base,"keywords":["python 3","café","outside"]},target)
check("unicode",{**base,"title":"ＳＨＩＰ PYTHON 3 CAFE\u0301 DUPLICATE SCORER"},target)
check("outside",base,target)
check("body",base,{**target,"body":"outside"})
# Reverse proof uses a symmetric pair without item-only keyword evidence.
sym_item={"index":1,"title":"CI cache","keywords":[],"type":"feature"}
sym_target={"title":"CI cache","body":"","type":"feature"}
f=m.score_pair(sym_item,sym_target,cfg); r=m.score_pair({**sym_item,"title":sym_target["title"]},{"title":sym_item["title"],"body":"","type":"feature"},cfg)
assert f==r and f["score"]>0; applied["reverse"]+=1
assert all(value>0 for value in applied.values()), applied
# Every paid token is unique across token-bearing payments.
paid=[t for p in expected["payments"] for t in p["tokens"]]
assert len(paid)==len(set(paid)), paid
# Additional stop words are additive and cannot raise a score.
for extra in ("python", "python,café", "outside", "3"):
    lowered=m.resolve_config({"duplicate_detection":{"extra_stop_words":extra}},type("A",(),{"limit":None,"high":None,"medium":None})())
    assert m.score_pair(base,target,lowered)["score"] <= expected["score"]
# Removing a middle token must not splice its neighbours into a new phrase.
splice_item={"index":1,"title":"alpha bridge beta gamma","keywords":[],"type":"feature"}
splice_target={"title":"alpha other beta gamma","body":"","type":"feature"}
normal=m.score_pair(splice_item,splice_target,cfg)["score"]
bridge=m.resolve_config({"duplicate_detection":{"extra_stop_words":"bridge,other"}},type("A",(),{"limit":None,"high":None,"medium":None})())
assert m.score_pair(splice_item,splice_target,bridge)["score"] <= normal
# <=2 significant words still score high when identical.
assert m.band(m.score_pair(sym_item,sym_target,cfg)["score"],cfg)=="high"
print(json.dumps({"applied":applied,"calibration_cases":len(data["cases"])}))
PY

cat >"$TMP/issues.json" <<'EOF'
[{"number":1,"title":"Ship duplicate scorer","body":"duplicate scorer runtime","labels":[{"name":"feature"}]}]
EOF
request='{"mode":"create","items":[{"index":1,"title":"Ship duplicate scorer","keywords":["runtime"],"type":"feature"}]}'
out1="$(printf '%s' "$request" | python3 "$SCRIPT" --issues-from "$TMP/issues.json")"
out2="$(printf '%s' "$request" | python3 "$SCRIPT" --issues-from "$TMP/issues.json")"
[ "$out1" = "$out2" ] && pass "identical input produces identical JSON bytes" || fail "output is nondeterministic"
printf '%s' "$out1" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["duplicates"] and d["medium_band"]==[]' \
  && pass "high band is deterministic and medium band is empty" || fail "high/medium routing"

# Bidirectional batch: only the second item's keywords contain body-only evidence.
cat >"$TMP/empty.json" <<'EOF'
[]
EOF
batch='{"mode":"batch","items":[{"index":1,"title":"Document releases","keywords":[],"type":"feature"},{"index":2,"title":"Release docs","keywords":["document"],"type":"feature"}]}'
printf '%s' "$batch" | python3 "$SCRIPT" --issues-from "$TMP/empty.json" --medium 1 --high 99 >"$TMP/batch.json"
python3 - "$TMP/batch.json" <<'PY' && pass "batch pair retains both directional scores once" || fail "batch symmetry/determinism"
import json,sys
d=json.load(open(sys.argv[1])); rows=[r for r in d["medium_band"] if r["match_type"]=="batch_internal"]
assert len(rows)==1, rows
assert set(rows[0]["directional_scores"])=={"1","2"}
assert rows[0]["pair"]==[1,2]
PY

# Config override and malformed/unavailable exit vocabulary.
printf '%s' "$request" | python3 "$SCRIPT" --issues-from "$TMP/issues.json" --high 99 --medium 1 >"$TMP/override.json"
python3 - "$TMP/override.json" <<'PY' && pass "threshold flags override resolved defaults" || fail "threshold overrides"
import json,sys
d=json.load(open(sys.argv[1])); assert d["duplicates"]==[] and d["medium_band"]
PY
set +e
printf '[]' | python3 "$SCRIPT" --issues-from "$TMP/issues.json" >/dev/null 2>"$TMP/e"; s=$?
[ "$s" = 3 ] && grep -q '^✗ gi-dup-score:' "$TMP/e"; a=$?
printf '%s' "$request" | PATH=/nonexistent /usr/bin/python3 "$SCRIPT" >/dev/null 2>"$TMP/e4"; s4=$?
[ "$s4" = 4 ] && grep -q '^⚠ gi-dup-score:' "$TMP/e4"; b=$?
python3 "$SCRIPT" --not-a-flag >/dev/null 2>&1; s2=$?
set -e
[ "$a" = 0 ] && [ "$b" = 0 ] && [ "$s2" = 2 ] \
  && pass "invalid/unavailable/usage map to exits 3/4/2" || fail "exit vocabulary (got $s2/$s/$s4)"

# Untrusted issue text stays data; no shell is used and no text-carrying flag exists.
mkdir "$TMP/inject"
python3 - "$TMP/inject/issues.json" "$TMP/inject/request.json" <<'PY'
import json,sys
text='x"; touch PWNED; echo "'
json.dump([{"number":9,"title":text,"body":"","labels":[]}],open(sys.argv[1],"w"))
json.dump({"mode":"create","items":[{"index":1,"title":text,"keywords":[],"type":"feature"}]},open(sys.argv[2],"w"))
PY
(cd "$TMP/inject" && python3 "$SCRIPT" --issues-from issues.json < request.json >/dev/null)
[ ! -e "$TMP/inject/PWNED" ] && ! grep -qE 'add_argument\("--(title|body|keyword)' "$SCRIPT" \
  && pass "issue strings are stdin/file data, never shell arguments" || fail "command injection boundary"

echo "  Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
