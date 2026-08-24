#!/usr/bin/env bash
# dup-score tokenization caching — pre-tokenize once, cache n-grams,
# dedupe pair directions (issue #353, F-PERF-003/F-PERF-004).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/src/shared/scripts/gi-dup-score.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
pass(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
fail(){ echo "  ✗ $1"; FAIL=$((FAIL+1)); }

echo "◆ dup-score tokenization caching (#353)"

python3 - "$SCRIPT" <<'PY' && pass "pair stage >=2x faster with identical scores" || fail "speedup/score parity (F-PERF-003/004)"
import importlib.util, json, random, sys, time, unicodedata
spec = importlib.util.spec_from_file_location("dup", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

random.seed(353)
words = ("fix auth login crash mobile redirect loop add dark mode toggle settings "
         "update deps express refactor db extract connection pool implement oauth "
         "docs readme installation steps test unit coverage ci chore release version "
         "bump perf cache tokenize dup score issue triage batch pair").split()
def title(i):
    return " ".join(random.choices(words, k=random.randint(4, 10))) + f" v{i % 7}"
items_raw = [{"index": i + 1, "title": title(i),
              "keywords": random.sample(words, k=3),
              "type": random.choice(["bug", "feature", "improvement"])}
             for i in range(100)]
issues = [{"number": n + 1, "title": title(n + 1000),
           "body": " ".join(random.choices(words, k=60)),
           "labels": [{"name": "feature"}]} for n in range(100)]

cfg = m.resolve_config({}, type("A", (), {"limit": None, "high": None, "medium": None})())
items = m.normalize_items({"mode": "batch", "items": items_raw}, cfg["max_items"])

# Faithful pre-#353 reference: rebuild stop words, re-tokenize both sides, and
# reconstruct target n-grams on every single call.
def naive_canonical(text):
    normalized = unicodedata.normalize("NFKC", text).casefold()
    tokens, current = [], []
    for char in normalized:
        if char.isalnum():
            current.append(char)
        elif current:
            tokens.append("".join(current)); current = []
    if current:
        tokens.append("".join(current))
    return tokens
def naive_active(text, stop, minimum):
    return [t for t in naive_canonical(text) if len(t) >= minimum and t not in stop]
def naive_evidence(text, stop, minimum):
    return [t if len(t) >= minimum and t not in stop else None
            for t in naive_canonical(text)]
def naive_phrase(item_tokens, target_tokens, minimum):
    if len(item_tokens) < minimum or len(target_tokens) < minimum:
        return []
    for size in range(min(len(item_tokens), len(target_tokens)), minimum - 1, -1):
        runs = {tuple(target_tokens[s:s + size])
                for s in range(len(target_tokens) - size + 1)
                if None not in target_tokens[s:s + size]}
        for s in range(len(item_tokens) - size + 1):
            run = item_tokens[s:s + size]
            if None not in run and tuple(run) in runs:
                return list(run)
    return []
def naive_score_pair(item, target, config):
    minimum = config["min_token_length"]
    extra = {t for w in config["extra_stop_words"] for t in naive_canonical(w)}
    stop = frozenset(m.STOP_WORDS | extra)
    item_title = naive_active(item["title"], stop, minimum)
    target_title = naive_active(str(target.get("title") or ""), stop, minimum)
    item_seq = naive_evidence(item["title"], stop, minimum)
    target_seq = naive_evidence(str(target.get("title") or ""), stop, minimum)
    target_body = naive_active(str(target.get("body") or ""), stop, minimum)
    target_all = set(target_title) | set(target_body)
    keywords = {t for k in item.get("keywords", [])
                for t in naive_active(str(k), stop, minimum)}
    consumed, payments, score = set(), [], 0
    phrase = naive_phrase(item_seq, target_seq, config["phrase_min_tokens"])
    if phrase:
        novel = sorted(set(phrase) - consumed)
        amount = len(novel) * config["weights.phrase"]
        if amount:
            score += amount; consumed.update(novel)
            payments.append({"signal": "phrase", "tokens": novel, "amount": amount})
    shared_title = sorted((set(item_title) & set(target_title)) - consumed)
    if shared_title:
        amount = len(shared_title) * config["weights.title_overlap"]
        if amount:
            score += amount; consumed.update(shared_title)
            payments.append({"signal": "title_overlap", "tokens": shared_title, "amount": amount})
    shared_kw = sorted((keywords & target_all) - consumed)
    if shared_kw:
        amount = len(shared_kw) * config["weights.keyword"]
        if amount:
            score += amount; consumed.update(shared_kw)
            payments.append({"signal": "keyword", "tokens": shared_kw, "amount": amount})
    item_type = m.normalize_type(item.get("type"))
    target_type = m.normalize_type(target.get("type")) or m.issue_type(target.get("labels"))
    if item_type and item_type == target_type and config["weights.same_type"]:
        score += config["weights.same_type"]
        payments.append({"signal": "same_type", "tokens": [], "amount": config["weights.same_type"]})
    return {"score": score, "payments": payments}

def optimized_stage():
    start = time.perf_counter()
    got = {}
    for item in items:
        for issue in issues:
            got[(item["index"], issue["number"])] = m.score_pair(item, issue, cfg)
    for pos, left in enumerate(items):
        for right in items[pos + 1:]:
            got[(left["index"], right["index"], "f")] = m.score_pair(left, right, cfg)
            got[(left["index"], right["index"], "r")] = m.score_pair(right, left, cfg)
    return time.perf_counter() - start, got

def naive_stage():
    start = time.perf_counter()
    got = {}
    for item in items:
        for issue in issues:
            got[(item["index"], issue["number"])] = naive_score_pair(item, issue, cfg)
    for pos, left in enumerate(items):
        for right in items[pos + 1:]:
            got[(left["index"], right["index"], "f")] = naive_score_pair(left, right, cfg)
            got[(left["index"], right["index"], "r")] = naive_score_pair(right, left, cfg)
    return time.perf_counter() - start, got

naive_stage()          # warm both paths once
optimized_stage()
naive_best = min(naive_stage()[0] for _ in range(2))
opt_seconds, opt_scores = optimized_stage()
_, naive_scores = naive_stage()

assert opt_scores.keys() == naive_scores.keys()
for key, scored in opt_scores.items():
    ref = naive_scores[key]
    assert scored["score"] == ref["score"], (key, scored["score"], ref["score"])
    assert scored["payments"] == ref["payments"], (key, scored["payments"], ref["payments"])

speedup = naive_best / opt_seconds
assert speedup >= 2.0, f"speedup only {speedup:.2f}x ({naive_best:.3f}s -> {opt_seconds:.3f}s)"
print(json.dumps({"naive_s": round(naive_best, 3), "cached_s": round(opt_seconds, 3),
                  "pairs_scored": len(opt_scores), "speedup": round(speedup, 1)}))
PY

python3 - "$SCRIPT" "$TMP" <<'PY' && pass "tokenization happens once per item per run" || fail "tokenization call count not bounded by distinct texts"
import functools, importlib.util, json, sys
spec = importlib.util.spec_from_file_location("dup", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
issues = [{"number": n + 1, "title": f"shared backlog title {n}", "body": "body text " + str(n),
           "labels": []} for n in range(50)]
request = {"mode": "create", "items": [{"index": n + 1, "title": f"proposed issue title {n}",
          "keywords": ["shared"], "type": "bug"} for n in range(50)]}
request_path = sys.argv[2] + "/request.json"
with open(request_path, "w") as handle:
    json.dump(request, handle)
issues_path = sys.argv[2] + "/issues.json"
with open(issues_path, "w") as handle:
    json.dump(issues, handle)

raw_tokenizer = m._canonical_cached.__wrapped__
tokenizations = [0]
def counted_tokenizer(text):
    tokenizations[0] += 1
    return raw_tokenizer(text)
replacement = functools.lru_cache(maxsize=8192)(counted_tokenizer)
for cache in (m._stop_words, m._active_cached, m._evidence_cached,
              m._keyword_set, m._token_union, m._target_runs):
    cache.cache_clear()
original = m._canonical_cached
stdout = sys.stdout
try:
    m._canonical_cached = replacement
    sys.stdin = open(request_path)
    sys.stdout = open(sys.argv[2] + "/stdout.json", "w")
    code = m.main(["--issues-from", issues_path])
finally:
    sys.stdout.close(); sys.stdout = stdout
    m._canonical_cached = original
assert code == 0, f"main exited {code}"
# Distinct strings: 50 item titles + 50 issue titles + 50 bodies + 1 keyword +
# stop-word fragments. Uncached behaviour would be ~6 calls x 2500 pairs ~=
# 15000 tokenizations; caching must stay within a small multiple of the
# distinct-text count.
distinct = 50 + 50 + 50 + 1 + 10
assert tokenizations[0] <= 8 * distinct, (
    f"tokenizer ran {tokenizations[0]} times for ~{distinct} distinct texts")
print(json.dumps({"tokenize_calls": tokenizations[0], "pairs": 2500,
                  "distinct_texts": distinct}))
PY

cat >"$TMP/issues.json" <<'EOF'
[{"number":1,"title":"Ship duplicate scorer","body":"duplicate scorer runtime","labels":[{"name":"feature"}]}]
EOF
printf '%s' '{"mode":"create","items":[{"index":1,"title":"Ship duplicate scorer","keywords":["runtime"],"type":"feature"}]}' \
  | python3 "$SCRIPT" --issues-from "$TMP/issues.json" >"$TMP/out.json"
cmp -s "$ROOT/tests/fixtures/gi-dup-score-expected.json" "$TMP/out.json" \
  && pass "fixed-fixture output stays byte-identical" || fail "fixed-fixture output changed"

echo "  Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
