#!/usr/bin/env bash
# Misc perf batch — build read cache, shim buffering + prepared cassettes,
# stack-detect index, blocking-degree sets, skip-set
# (issue #355, F-PERF-008/009/010/011/012/013).
#
# Every check is either an output-parity check against a faithful in-test
# reproduction of the pre-change algorithm, or a work-count bound. Wall-clock
# ratios are used only where the asymptotic gap is orders of magnitude, so the
# suite does not become a CI-runner speed test.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_COMMON="$ROOT/scripts/build/common.py"
SHIM="$ROOT/evals/harness/gh_shim.py"
STACK="$ROOT/src/shared/scripts/gi-stack-detect.py"
GRAPH="$ROOT/src/shared/scripts/gi-triage-graph.py"
STATE="$ROOT/src/shared/scripts/gi-state.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
pass(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
fail(){ echo "  ✗ $1"; FAIL=$((FAIL+1)); }

echo "◆ misc perf batch (#355)"

# ─── F-PERF-008: build read cache + listing memo ────────────
python3 - "$ROOT" "$TMP" <<'PY' && pass "F-PERF-008: repeated build reads decode once, rewrites are not served stale" || fail "F-PERF-008: build read cache"
import importlib.util, json, sys, time
from pathlib import Path

root, tmp = Path(sys.argv[1]), Path(sys.argv[2])
sys.path.insert(0, str(root / "scripts"))
from build import common  # noqa: E402

work = tmp / "readcache"
work.mkdir(parents=True, exist_ok=True)
target = work / "doc.md"
target.write_text("one", encoding="utf-8")

decodes = [0]
real_read_text = Path.read_text
def counting(self, *args, **kwargs):
    decodes[0] += 1
    return real_read_text(self, *args, **kwargs)

common._reset_io_caches()
Path.read_text = counting
try:
    # 1. Repeated reads of an unchanged file decode exactly once.
    assert [common._read_text(target) for _ in range(25)] == ["one"] * 25
    assert decodes[0] == 1, f"{decodes[0]} decodes for 25 reads of one unchanged file"

    # 2. A rewrite through the build's own writer is never served stale, even
    #    when it lands inside the same filesystem timestamp tick.
    for i in range(20):
        common._write_text(target, f"v{i}")
        assert common._read_text(target) == f"v{i}", "stale text after _write_text"

    # 3. Same for a file replaced behind the cache's back: the (mtime, size)
    #    stamp, not the path, is the key.
    time.sleep(0.01)
    target.write_text("out-of-band-and-longer", encoding="utf-8")
    assert common._read_text(target) == "out-of-band-and-longer"

    # 4. A missing file still raises at the call site, and leaves no entry.
    target.unlink()
    try:
        common._read_text(target)
    except FileNotFoundError:
        pass
    else:
        raise AssertionError("a missing file must still raise FileNotFoundError")

    # 5. The directory listing memo tracks the entry set, not a snapshot.
    listing_dir = work / "listing"
    listing_dir.mkdir()
    assert common._sorted_iterdir(listing_dir) == []
    for name in ("b.md", "a.md"):
        common._write_text(listing_dir / name, "x")
    assert [p.name for p in common._sorted_iterdir(listing_dir)] == ["a.md", "b.md"]
    # The returned list is a copy — mutating it must not poison the cache.
    got = common._sorted_iterdir(listing_dir)
    got.clear()
    assert [p.name for p in common._sorted_iterdir(listing_dir)] == ["a.md", "b.md"]
finally:
    Path.read_text = real_read_text
    common._reset_io_caches()

# 6. On a whole real build, decodes must fall far below _read_text calls.
calls, decodes[0] = [0], 0
import contextlib, io, pkgutil
import build  # noqa: E402
for module in pkgutil.iter_modules(build.__path__):
    importlib.import_module("build." + module.name)
original = common._read_text
def counted(path, *args, **kwargs):
    calls[0] += 1
    return original(path, *args, **kwargs)
for name, module in list(sys.modules.items()):
    if name.startswith("build") and getattr(module, "_read_text", None) is original:
        setattr(module, "_read_text", counted)
Path.read_text = counting
try:
    from build import cli  # noqa: E402
    with contextlib.redirect_stdout(io.StringIO()):
        code = cli.main(["--out", str(tmp / "buildout"), "--no-root-skills"])
finally:
    Path.read_text = real_read_text
assert code == 0, f"build exited {code}"
assert calls[0] > 500, f"only {calls[0]} _read_text calls — corpus too small to judge"
assert decodes[0] < calls[0] / 2, (
    f"{decodes[0]} decodes for {calls[0]} reads — the memo is not taking effect")
print(json.dumps({"read_text_calls": calls[0], "decodes": decodes[0],
                  "saved": calls[0] - decodes[0]}))
PY

# ─── F-PERF-009: record mode buffers, then flushes once ─────
python3 - "$SHIM" "$TMP" <<'PY' && pass "F-PERF-009: record mode writes the cassette once, not once per call" || fail "F-PERF-009: record buffering"
import importlib.util, json, sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("gh_shim", sys.argv[1])
shim = importlib.util.module_from_spec(spec); sys.modules[spec.name] = shim
spec.loader.exec_module(shim)

work = Path(sys.argv[2]) / "record"; work.mkdir(parents=True, exist_ok=True)
cassette = work / "cassettes.json"
records = [{"argv": ["issue", "view", str(i), "--json", "number"],
            "stdout": "y" * 400, "stderr": "", "exit": 0} for i in range(200)]

# Pre-change reference: reload, append, rewrite the whole file per call.
cassette.write_text(json.dumps({"version": 1, "calls": []}) + "\n", encoding="utf-8")
naive_bytes = 0
for record in records:
    data = json.loads(cassette.read_text(encoding="utf-8"))
    data["calls"].append(record)
    blob = json.dumps(data, indent=2) + "\n"
    naive_bytes += len(blob)
    cassette.write_text(blob, encoding="utf-8")
naive_final = cassette.read_text(encoding="utf-8")

# Buffered: one rewrite, byte-identical result.
cassette.write_text(json.dumps({"version": 1, "calls": []}) + "\n", encoding="utf-8")
shim._PENDING_RECORDS.clear()
writes = [0]
real_replace = shim.os.replace
def counting_replace(src, dst, *args, **kwargs):
    writes[0] += 1
    return real_replace(src, dst, *args, **kwargs)
shim.os.replace = counting_replace
try:
    for record in records:
        shim._buffer_record(cassette, record)
    assert writes[0] == 0, "buffering must not touch the cassette before the flush"
    assert len(shim._PENDING_RECORDS[str(cassette)]) == len(records)
    shim._flush_records()
finally:
    shim.os.replace = real_replace
    shim._PENDING_RECORDS.clear()

assert writes[0] == 1, f"{writes[0]} cassette writes for {len(records)} recorded calls"
buffered_final = cassette.read_text(encoding="utf-8")
assert buffered_final == naive_final, "buffered cassette differs from the per-call rewrite"
buffered_bytes = len(buffered_final)
assert naive_bytes > 20 * buffered_bytes, (
    f"expected large write amplification to remove; naive={naive_bytes} new={buffered_bytes}")
print(json.dumps({"records": len(records), "naive_bytes": naive_bytes,
                  "buffered_bytes": buffered_bytes, "cassette_writes": writes[0],
                  "amplification_removed": round(naive_bytes / buffered_bytes, 1)}))
PY

# ─── F-PERF-010: normalized argv precomputed at load ────────
python3 - "$SHIM" <<'PY' && pass "F-PERF-010: cassette argv normalized once at load, matches unchanged" || fail "F-PERF-010: prepared cassette parity"
import importlib.util, json, sys

spec = importlib.util.spec_from_file_location("gh_shim", sys.argv[1])
shim = importlib.util.module_from_spec(spec); sys.modules[spec.name] = shim
spec.loader.exec_module(shim)

# Faithful pre-change reference: two passes, normalizing every entry each time.
def naive_match(argv, calls):
    norm = shim._normalize_argv(argv)
    for call in calls:
        if not isinstance(call, dict):
            continue
        c_argv = call.get("argv")
        if not isinstance(c_argv, list):
            continue
        c_norm = shim._normalize_argv([str(x) for x in c_argv])
        if call.get("match", "exact") == "prefix":
            continue
        if norm == c_norm:
            return call
    best, best_len = None, -1
    for call in calls:
        if not isinstance(call, dict):
            continue
        c_argv = call.get("argv")
        if not isinstance(c_argv, list):
            continue
        c_norm = shim._normalize_argv([str(x) for x in c_argv])
        if call.get("match", "exact") != "prefix":
            continue
        if len(norm) >= len(c_norm) and norm[: len(c_norm)] == c_norm:
            if len(c_norm) > best_len:
                best, best_len = call, len(c_norm)
    return best

calls = [
    {"match": "prefix", "argv": ["pr"], "id": "prefix-pr"},
    {"argv": ["issue", "view", 1, "--json", "title,number"], "id": "exact-1"},
    {"argv": ["issue", "view", "1", "--json", "number,title"], "id": "exact-1-dupe"},
    {"match": "prefix", "argv": ["pr", "view"], "id": "prefix-pr-view"},
    {"match": "prefix", "argv": ["pr", "view"], "id": "prefix-pr-view-dupe"},
    {"argv": ["pr", "view", "7", "--json=number,title"], "id": "exact-pr-7"},
    {"match": "prefix", "argv": ["auth", "status"], "id": "prefix-auth"},
    "not-a-dict",
    {"argv": "not-a-list", "id": "bad-argv"},
    {"id": "no-argv"},
]
probes = [
    ["issue", "view", "1", "--json", "number,title"],
    ["issue", "view", "1", "--json=title,number"],
    ["issue", "view", "1", "--json", "title , number ,"],
    ["pr", "view", "7", "--json", "title,number"],
    ["pr", "view", "9", "--json", "number"],
    ["pr", "list", "--json", "number"],
    ["pr"],
    ["auth", "status", "--hostname", "github.com"],
    ["repo", "view"],
    [],
]
prepared = shim._prepare_calls(calls)
for probe in probes:
    want, got = naive_match(probe, calls), prepared.match(probe)
    assert want is got, (probe, want, got)
    assert shim._match_call(probe, calls) is want, probe

# Work count: preparing once must normalize each entry once, and a lookup must
# normalize only the incoming argv — the old shape did 2n per lookup.
counted = [0]
real = shim._normalize_argv
def counting(argv):
    counted[0] += 1
    return real(argv)
shim._normalize_argv = counting
try:
    prepared = shim._prepare_calls(calls)
    at_load = counted[0]
    counted[0] = 0
    for probe in probes:
        prepared.match(probe)
    per_lookup = counted[0]
finally:
    shim._normalize_argv = real

usable = sum(1 for c in calls if isinstance(c, dict) and isinstance(c.get("argv"), list))
assert at_load == usable, f"load normalized {at_load} entries, expected {usable}"
assert per_lookup == len(probes), (
    f"{per_lookup} normalizations for {len(probes)} lookups — entries are still being renormalized")
print(json.dumps({"entries": len(calls), "normalized_at_load": at_load,
                  "normalized_per_lookup": per_lookup, "probes": len(probes)}))
PY

# ─── F-PERF-011: stack-detect pattern index + read memo ─────
python3 - "$STACK" "$TMP" <<'PY' && pass "F-PERF-011: pattern index matches match_paths and reads each file once" || fail "F-PERF-011: stack-detect index"
import importlib.util, json, os, sys, time
from pathlib import Path

spec = importlib.util.spec_from_file_location("stack", sys.argv[1])
sd = importlib.util.module_from_spec(spec); spec.loader.exec_module(sd)

# A corpus with root-level files, repeated basenames at depth, a duplicated
# path (git lists conflicted paths more than once), case variants and literal
# brackets — every shape the literal fast path must not mis-answer.
files = []
for prefix in ("", "a/", "a/b/", "c/", "c/d/e/"):
    for name in ("package.json", "requirements.txt", "go.mod", "Cargo.toml",
                 "jest.config.js", "pytest.ini", "conftest.py", "main.py",
                 "app.rs", "x_test.go", "Weird[1].txt", "UPPER.JSON",
                 "setup.cfg", "Gemfile", "build.gradle.kts", "a.csproj"):
        files.append(prefix + name)
files += ["dup.txt", "dup.txt", "src/test/Foo.java", ".github/ISSUE_TEMPLATE/bug.md"]

patterns = {p for p, _ in sd.LANGUAGE_MARKERS}
patterns |= set(sd.DEPENDENCY_FILES)
patterns |= {(p if k == "file" else p.partition("::")[0]) for k, p, _ in sd.TEST_RUNNER_MARKERS}
patterns |= {"dup.txt", "*.json", "?ain.py", "Weird[1].txt", "Weird*.txt", "UPPER.JSON",
             "upper.json", "src/test/*", "a/b/package.json", "nonexistent.xyz", "", "*"}

index = sd.RepoIndex(".", files)
for pattern in sorted(patterns):
    assert index.match(pattern) == sd.match_paths(files, pattern), pattern

# Randomized parity: the literal fast path answers from a name index where
# `match_paths` globbed, so assert the two agree on generated patterns too, not
# only on the marker tables.
import random
random.seed(355)
alphabet = ["package", "json", "go", "mod", "a", "b", "Weird", "[1]", "*", "?", ".", "/",
            "UPPER", "JSON", "src", "test", "dup", "txt", "py", "-", "_"]
for _ in range(1500):
    pattern = "".join(random.choices(alphabet, k=random.randint(0, 5)))
    assert sd.RepoIndex(".", files).match(pattern) == sd.match_paths(files, pattern), pattern

# The memo answers a repeated glob without redoing the scan, and hands back a
# copy so a caller trimming the result in place cannot poison it.
globs = [0]
real_match_paths = sd.match_paths
def counting_match_paths(all_files, pattern):
    globs[0] += 1
    return real_match_paths(all_files, pattern)
sd.match_paths = counting_match_paths
try:
    memo_index = sd.RepoIndex(".", files)
    for _ in range(6):
        memo_index.match("*.json")
        memo_index.match("package.json")
    assert globs[0] == 1, f"{globs[0]} scans for one repeated glob (literals need none)"
    first = memo_index.match("package.json")
    first.clear()
    assert memo_index.match("package.json") == sd.match_paths(files, "package.json")
finally:
    sd.match_paths = real_match_paths

# Reads are memoized: one decode per distinct path, error results included.
work = Path(sys.argv[2]) / "stackread"; work.mkdir(parents=True, exist_ok=True)
(work / "package.json").write_text('{"dependencies":{"next":"1"},"devDependencies":{"jest":"1"}}')
reads = [0]
real_read = sd.read_file
def counting(root, rel):
    reads[0] += 1
    return real_read(root, rel)
sd.read_file = counting
try:
    memo = sd.RepoIndex(str(work), ["package.json", "missing.json"])
    for _ in range(10):
        assert memo.read("package.json").startswith("{")
        assert memo.read("missing.json") == ""
finally:
    sd.read_file = real_read
assert reads[0] == 2, f"{reads[0]} reads for 2 distinct paths over 20 requests"

# Whole-detector parity on a fixture tree, including a --rules override.
tree = Path(sys.argv[2]) / "tree"
for sub in ("a/b", "c", "src/test", ".github/ISSUE_TEMPLATE"):
    (tree / sub).mkdir(parents=True, exist_ok=True)
(tree / "package.json").write_text('{"dependencies":{"next":"1","react":"1"},"devDependencies":{"jest":"1"}}')
(tree / "a/b/package.json").write_text('{"dependencies":{"vue":"1"}}')
(tree / "requirements.txt").write_text("django\n")
(tree / "pyproject.toml").write_text("[tool.pytest]\n")
(tree / "Gemfile").write_text("rspec\n")
(tree / "test_x.py").write_text("import unittest\n")
(tree / "src/test/Foo.java").write_text("")
(tree / ".github/ISSUE_TEMPLATE/bug.md").write_text("")

tracked, _ = sd.list_files(str(tree))
index = sd.RepoIndex(str(tree), tracked)
got = (sd.detect_language(index, sd.LANGUAGE_MARKERS),
       sd.detect_framework(index, sd.FRAMEWORK_MARKERS),
       sd.detect_test_runner(index, sd.TEST_RUNNER_MARKERS))
assert got[0][0] == "JavaScript" and got[0][1] == "package.json", got[0]
assert got[1] == ("Next.js", "package.json"), got[1]
assert got[2] == ("Jest", "package.json"), got[2]

# --rules must still replace the table outright — the index is built from the
# effective markers, never from the module constants.
override = sd.RepoIndex(str(tree), tracked)
assert sd.detect_test_runner(override, [("file", "test_*.py", "custom")]) == ("custom", "test_x.py")
try:
    sd.detect_test_runner(sd.RepoIndex(str(tree), tracked), [("bogus", "x", "y")])
except sd.InvalidInput:
    pass
else:
    raise AssertionError("an unknown marker kind must still raise InvalidInput")

# Glob work: 39 markers over a wide tree must cost far less than a scan each.
wide = [f"d{i % 40}/s{i % 9}/f{i}.py" for i in range(3000)]
wide += ["package.json", "requirements.txt", "pyproject.toml", "Gemfile", "go.mod"]
markers = ([p for p, _ in sd.LANGUAGE_MARKERS] + list(sd.DEPENDENCY_FILES)
           + [(p if k == "file" else p.partition("::")[0]) for k, p, _ in sd.TEST_RUNNER_MARKERS])
for _ in range(2):
    start = time.perf_counter()
    for pattern in markers:
        sd.match_paths(wide, pattern)
    naive = time.perf_counter() - start
    start = time.perf_counter()
    wide_index = sd.RepoIndex(".", wide)
    for pattern in markers:
        wide_index.match(pattern)
    fast = time.perf_counter() - start
assert naive / fast >= 1.5, f"index only {naive / fast:.2f}x faster ({naive:.4f}s -> {fast:.4f}s)"
print(json.dumps({"patterns": len(patterns), "files": len(wide),
                  "naive_s": round(naive, 4), "indexed_s": round(fast, 4),
                  "speedup": round(naive / fast, 1)}))
PY

# ─── F-PERF-012: blocking degree in one pass ────────────────
python3 - "$GRAPH" <<'PY' && pass "F-PERF-012: one-pass degrees equal the per-issue scan, including edge cases" || fail "F-PERF-012: blocking-degree map"
import importlib.util, json, random, sys, time

spec = importlib.util.spec_from_file_location("graph", sys.argv[1])
tg = importlib.util.module_from_spec(spec); spec.loader.exec_module(tg)

# Faithful pre-change reference.
def naive_degree(edges, number):
    total = 0
    for edge in edges:
        if number in (edge.get("a"), edge.get("b"), edge.get("from")):
            total += 1
    return total

random.seed(355)
edges = []
for i in range(1, 60):
    for j in range(i + 1, 60):
        roll = random.random()
        if roll < 0.2:
            edges.append({"a": i, "b": j})
        elif roll < 0.25:
            edges.append({"from": i, "to": j})
# The traps: an edge naming one issue at both ends counts once; `to` never
# counts; bool/float ends compare equal to an int; unhashable ends must not
# raise where the scan tolerated them.
edges += [{"a": 5, "b": 5}, {"from": 6, "to": 6}, {"to": 3}, {"a": True, "b": 2},
          {"a": 1.0, "b": 3}, {"a": [9, 9], "b": 3}, {"a": {"k": "v"}, "b": 4}, {}]

# Randomized parity over every JSON value shape an edge end can hold. The map
# is keyed by hash where the scan compared by `==`, and the two only agree
# everywhere if bool/int/float aliasing, NaN, -0.0, dicts differing only in key
# order, and unhashable values are all handled — so assert it rather than argue
# it. `blocking_degree` must be exact for *every* input, including the
# unhashable numbers no caller can produce but the old scan still answered.
VALUES = [0, 1, 2, 3, True, False, 1.0, 2.0, None, "1", (1,), [1], {"k": 1},
          float("nan"), -0.0, [1, 2], {"b": 2, "a": 1}, {"a": 1, "b": 2}]
KEYS = ["a", "b", "from", "to"]
for _ in range(1500):
    fuzz = []
    for _ in range(random.randint(0, 5)):
        fuzz.append({k: random.choice(VALUES)
                     for k in random.sample(KEYS, random.randint(0, 4))})
    fuzz_degrees = tg.blocking_degrees(fuzz)
    for probe in VALUES:
        want = naive_degree(fuzz, probe)
        assert tg.blocking_degree(fuzz, probe) == want, (fuzz, probe)
        try:
            hash(probe)
        except TypeError:
            continue
        assert fuzz_degrees.get(probe, 0) == want, (fuzz, probe)

degrees = tg.blocking_degrees(edges)
# `None`, `True`/`False` and floats are looked up too: membership was `==`, so
# an absent end and an int-equal end have to keep answering exactly as before.
for number in list(range(0, 62)) + [None, True, False, 1.0, 5.0]:
    assert degrees.get(number, 0) == naive_degree(edges, number), number
    assert tg.blocking_degree(edges, number) == naive_degree(edges, number), number
assert tg.blocking_degrees([{"a": 5, "b": 5}]).get(5) == 1, "an edge must count once per issue"
assert tg.blocking_degrees([{"from": 3, "to": 4}]).get(4, 0) == 0, "`to` must never count"
# An unhashable end is skipped rather than raising — the scan tolerated it so
# that `known()` could report it as this script's exit 3, not a bare TypeError.
assert tg.blocking_degrees([{"a": [1]}]).get(1, 0) == 0
assert tg.blocking_degrees([{"a": {"k": [1]}, "b": 2}]).get(2) == 1

# direct_edges must produce the same graph as it did with per-pair scanning.
def ties(n):
    index = {k: {"number": k, "created": None, "type": "bug"} for k in range(1, n + 1)}
    return index, [{"a": i, "b": j} for i in range(1, n + 1) for j in range(i + 1, n + 1)]

index, tie_edges = ties(24)
directed, co_dependent = tg.direct_edges(list(tie_edges), index)
assert directed == [] and co_dependent == sorted([i, j] for i in range(1, 25)
                                                 for j in range(i + 1, 25)), "tie graph changed"

index, tie_edges = ties(70)
start = time.perf_counter(); tg.direct_edges(list(tie_edges), index)
fast = time.perf_counter() - start
start = time.perf_counter()
for i in range(1, 71):
    for j in range(i + 1, 71):
        naive_degree(tie_edges, i); naive_degree(tie_edges, j)
naive = time.perf_counter() - start
assert naive / fast >= 4.0, f"only {naive / fast:.2f}x ({naive:.3f}s -> {fast:.3f}s)"
print(json.dumps({"edges": len(tie_edges), "naive_s": round(naive, 3),
                  "one_pass_s": round(fast, 3), "speedup": round(naive / fast, 1)}))
PY

# ─── F-PERF-013: skip_list parallel set ─────────────────────
python3 - "$STATE" <<'PY' && pass "F-PERF-013: skip_list merge keeps order and dedup with set membership" || fail "F-PERF-013: skip-set merge"
import importlib.util, json, sys, time

spec = importlib.util.spec_from_file_location("state", sys.argv[1])
gs = importlib.util.module_from_spec(spec); spec.loader.exec_module(gs)

def naive_merge(existing, incoming):
    merged = list(existing)
    for number in incoming:
        if number not in merged:
            merged.append(number)
    return merged

cases = [
    ([], [45, 45, 7, 45, 9]),
    ([45, 7, 9], [9, 11, 7, 45]),
    ([1, 2, 3], []),
    ([], []),
    ([5], [5, 5, 5]),
    (list(range(20)), list(range(10, 30))),
]
for existing, incoming in cases:
    got = gs.merge_patch({"run_id": "r", "skip_list": list(existing)},
                         {"skip_list": list(incoming)}, now="X")
    assert got["skip_list"] == naive_merge(existing, incoming), (existing, incoming, got["skip_list"])
    assert "skip_set" not in got and set(got) <= set(gs.STATE_KEYS) | {"run_id"}, sorted(got)

# The caller's list is never mutated.
original = [1, 2]
gs.merge_patch({"run_id": "r", "skip_list": original}, {"skip_list": [3]}, now="X")
assert original == [1, 2], "merge_patch mutated the caller's skip_list"

# A state file is not element-checked on load; an unhashable leftover must be
# preserved and must not raise where the list scan tolerated it.
got = gs.merge_patch({"run_id": "r", "skip_list": [1, [2, 3], 4]},
                     {"skip_list": [4, 5]}, now="X")
assert got["skip_list"] == [1, [2, 3], 4, 5], got["skip_list"]

# `None` is still an error, not a clear.
for bad in (None, ["x"], "nope"):
    try:
        gs.merge_patch({"run_id": "r", "skip_list": []}, {"skip_list": bad}, now="X")
    except gs.InputError:
        continue
    raise AssertionError(f"skip_list={bad!r} must raise InputError")

existing, incoming = list(range(4000)), list(range(4000, 8000))
start = time.perf_counter()
gs.merge_patch({"run_id": "r", "skip_list": list(existing)}, {"skip_list": list(incoming)}, now="X")
fast = time.perf_counter() - start
start = time.perf_counter(); naive_merge(existing, incoming)
naive = time.perf_counter() - start
assert naive / fast >= 5.0, f"only {naive / fast:.2f}x ({naive:.4f}s -> {fast:.4f}s)"
print(json.dumps({"existing": len(existing), "incoming": len(incoming),
                  "naive_s": round(naive, 4), "set_s": round(fast, 4),
                  "speedup": round(naive / fast, 1)}))
PY

# ─── Bundled copies stay byte-identical to their sources ────
DRIFT=0
for pair in \
  "init-gitissue/references/scripts/gi-stack-detect.py:$STACK" \
  "issue-triage/references/scripts/gi-triage-graph.py:$GRAPH" \
  "auto-pilot/references/scripts/gi-triage-graph.py:$GRAPH" \
  "issue-resolver/references/scripts/gi-state.py:$STATE" \
  "auto-pilot/references/scripts/gi-state.py:$STATE"; do
  built="$ROOT/skills/${pair%%:*}"
  source="${pair#*:}"
  cmp -s "$built" "$source" || { DRIFT=1; echo "    drift: $built"; }
done
[ "$DRIFT" -eq 0 ] && pass "bundled shared scripts match their sources byte-for-byte" \
                   || fail "bundled shared scripts drifted — run ./scripts/build.sh"

echo "  Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
