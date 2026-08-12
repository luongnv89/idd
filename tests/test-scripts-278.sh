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
# Every invariant below has a distinct mutation and a reverse-axis application.
# `check_equal` proves the mutation differs from its baseline before comparing
# payment evidence; `check_delta` proves added evidence pays exactly once.
applied={k:{"forward":0,"reverse":0} for k in ("permutation","grouping","duplicates","overlap","short","unicode","outside","body")}
def swapped(item,tgt):
    return ({"index":2,"title":tgt["title"],"keywords":item.get("keywords",[]),"type":tgt.get("type")},
            {"title":item["title"],"body":tgt.get("body",""),"type":item.get("type")})
def check_equal(name,baseline_item,mutant_item,tgt,direction):
    assert mutant_item != baseline_item, (name,"vacuous mutation")
    want=m.score_pair(baseline_item,tgt,cfg); got=m.score_pair(mutant_item,tgt,cfg)
    assert (got["score"],got["payments"]) == (want["score"],want["payments"]), (name,direction,got,want)
    applied[name][direction]+=1
for kws in itertools.permutations(base["keywords"]):
    mutant={**base,"keywords":list(kws)}
    if mutant != base:
        check_equal("permutation",base,mutant,target,"forward")
        rb,rt=swapped(base,target); rm,_=swapped(mutant,target)
        check_equal("permutation",rb,rm,rt,"reverse")
for name,kws in (("grouping",["python","3 café","outside"]),
                 ("duplicates",base["keywords"]*2),
                 ("overlap",["python 3 café","python","3","café","outside"])):
    mutant={**base,"keywords":kws}
    check_equal(name,base,mutant,target,"forward")
    rb,rt=swapped(base,target); rm,_=swapped(mutant,target)
    check_equal(name,rb,rm,rt,"reverse")
# One-character evidence is a real newly-paid keyword, not an unchanged list.
short_base={"index":1,"title":"Python runtime","keywords":["python"],"type":"feature"}
short_mut={**short_base,"keywords":["python 3"]}
short_target={"title":"Runtime guide","body":"python 3","type":"feature"}
for direction in ("forward","reverse"):
    bi,mi,tg=short_base,short_mut,short_target
    if direction=="reverse":
        bi,tg=swapped(short_base,short_target); mi,_=swapped(short_mut,short_target)
    before=m.score_pair(bi,tg,cfg); after=m.score_pair(mi,tg,cfg)
    assert "3" not in before["consumed_tokens"] and "3" in after["shared_keywords"]
    assert after["score"]-before["score"]==cfg["weights.keyword"]
    applied["short"][direction]+=1
# Compatibility Unicode/case is a distinct title mutation on both axes.
unicode_mut={**base,"title":"ＳＨＩＰ PYTHON 3 CAFE\u0301 DUPLICATE SCORER"}
check_equal("unicode",base,unicode_mut,target,"forward")
rb,rt=swapped(base,target)
rmut_target={**rt,"title":unicode_mut["title"]}
assert rmut_target != rt
before=m.score_pair(rb,rt,cfg); after=m.score_pair(rb,rmut_target,cfg)
assert (after["score"],after["payments"]) == (before["score"],before["payments"])
applied["unicode"]["reverse"]+=1
# A keyword absent from the item title must still pay from target-body evidence.
out_base={"index":1,"title":"Build account view","keywords":[],"type":"feature"}
out_mut={**out_base,"keywords":["dashboard"]}
out_target={"title":"Create profile page","body":"dashboard account","type":"feature"}
for direction in ("forward","reverse"):
    bi,mi,tg=out_base,out_mut,out_target
    if direction=="reverse":
        bi,tg=swapped(out_base,out_target); mi,_=swapped(out_mut,out_target)
    before=m.score_pair(bi,tg,cfg); after=m.score_pair(mi,tg,cfg)
    assert "dashboard" not in m.active_tokens(bi["title"],m.STOP_WORDS,cfg["min_token_length"])
    assert after["shared_keywords"]==["dashboard"] and after["score"]-before["score"]==cfg["weights.keyword"]
    applied["outside"][direction]+=1
# Repeating title evidence in the target body must not create another payment.
body_sparse={**target,"body":"outside"}
for direction in ("forward","reverse"):
    bi,tg=base,body_sparse; repeated=target
    if direction=="reverse":
        bi,tg=swapped(base,body_sparse); _,repeated=swapped(base,target)
    before=m.score_pair(bi,tg,cfg); after=m.score_pair(bi,repeated,cfg)
    assert repeated["body"] != tg["body"]
    assert (after["score"],after["payments"]) == (before["score"],before["payments"])
    applied["body"][direction]+=1
assert all(counts[axis]>0 for counts in applied.values() for axis in ("forward","reverse")), applied
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
# The historical counterexample is invalid by contract: otherwise stopping
# "beta" moves two tokens from phrase=1 to overlap=2 and raises 3 -> 4.
try:
    m.resolve_config({"duplicate_detection":{"weights":{"phrase":1,"title_overlap":2}}},type("A",(),{"limit":None,"high":None,"medium":None})())
except m.InvalidInput as exc:
    assert "weights.phrase must be >= weights.title_overlap" in str(exc)
else:
    raise AssertionError("phrase=1/title_overlap=2 counterexample was accepted")
# A non-default valid ordering remains monotone for the same concrete pair.
custom=m.resolve_config({"duplicate_detection":{"weights":{"phrase":3,"title_overlap":2}}},type("A",(),{"limit":None,"high":None,"medium":None})())
concrete_item={"index":1,"title":"alpha beta gamma","keywords":[],"type":None}
concrete_target={"title":"alpha beta gamma","body":"","type":None}
custom_before=m.score_pair(concrete_item,concrete_target,custom)["score"]
custom_stopped=m.resolve_config({"duplicate_detection":{"weights":{"phrase":3,"title_overlap":2},"extra_stop_words":"beta"}},type("A",(),{"limit":None,"high":None,"medium":None})())
assert custom_before==9
assert m.score_pair(concrete_item,concrete_target,custom_stopped)["score"]==4 <= custom_before
# <=2 significant words still score high when identical.
sym_item={"index":1,"title":"CI cache","keywords":[],"type":"feature"}
sym_target={"title":"CI cache","body":"","type":"feature"}
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

# Worst supported 100x100 medium set: bodies are deduplicated, truncated, and
# the judgement slice is bounded without silently discarding the other warnings.
python3 - "$TMP/worst-issues.json" "$TMP/worst-request.json" <<'PY'
import json,sys
body="x"*10000
json.dump([{"number":n,"title":"shared","body":body,"labels":[{"name":"feature"}]} for n in range(1,101)],open(sys.argv[1],"w"))
json.dump({"mode":"batch","items":[{"index":n,"title":"shared","keywords":[],"type":"feature"} for n in range(1,101)]},open(sys.argv[2],"w"))
PY
python3 "$SCRIPT" --issues-from "$TMP/worst-issues.json" --high 99 <"$TMP/worst-request.json" >"$TMP/worst-output.json"
python3 - "$TMP/worst-output.json" <<'PY' && pass "worst-case medium prompt input is deduplicated and bounded" || fail "worst-case medium prompt bound"
import json,sys
d=json.load(open(sys.argv[1]))
existing=[row for row in d["medium_band"] if row["match_type"]=="existing_issue"]
assert len(existing)==10000, len(existing)
assert d["medium_judgement"]=={"batch_size":20,"body_char_limit":1000,"deferred_count":len(d["medium_band"])-200,"selected_count":200}
assert len(d["medium_issue_context"])==100
assert all(len(row["body"])==1000 and row["body_truncated"] for row in d["medium_issue_context"])
assert all("match_body" not in row and "match_title" not in row for row in existing)
# The bounded semantic prompt (one 20-candidate chunk plus referenced context)
# is small even though all 10,000 ambiguous matches remain visible as warnings.
first=d["medium_band"][:20]; refs={row["match_number"] for row in first}
prompt={"candidates":first,"issue_context":[row for row in d["medium_issue_context"] if row["number"] in refs]}
assert len(json.dumps(prompt)) < 50000
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
