#!/usr/bin/env bash
# test-cost-counters-465.sh — deterministic cost counters for skill runs
# (issue #465, part of epic #464).
#
# Offline and hermetic: no network, no gh auth, no real GitHub repository.
# The only `gh` any test reaches is the eval shim, fronted on a PATH that
# holds nothing else.
#
#   T1  scripts/idd-cost-counters.py is committed 0755 and --help exits 0
#   T2  the shim call log counts the REAL gi-issue.py read pattern exactly,
#       and two runs in fresh workspaces write byte-identical logs (AC1/3/4)
#   T3  the counter is sensitive — a flow without --refresh counts one fewer
#   T4  help, version, refused and bare calls are logged; unset, the shim
#       writes nothing
#   T5  `calls` summarizes a log exactly and byte-identically across runs
#   T6  grade.py `gh-calls` passes the right count and fails an off-by-one,
#       a per-command mismatch, a missing log and a non-OUT path
#   T7  `evidence` on a synthetic transcript fixture: exact per-run numbers
#       (max-per-message-id token dedupe, nested child aggregation, the gh
#       regex, exclusion, selection) and byte-identical output per seed (AC2)
#   T8  `evidence` usage and input errors map onto the exit vocabulary; an
#       unreadable or non-UTF-8 file exits 4 without a traceback or its path
#   T9  run_eval.sh rejects an unsafe repo_scripts entry before any subject
#   T10 run_eval.sh on the gh-call-counter case, sandboxed — authoritative
#
# Usage: bash tests/test-cost-counters-465.sh
# Set IDD_EVAL_REQUIRE_SANDBOX=1 (CI does) to turn a T10 skip into a failure.
# Returns: exit 0 if all tests pass, exit 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$REPO_ROOT/scripts/idd-cost-counters.py"
SHIM="$REPO_ROOT/evals/harness/gh_shim.py"
GRADE="$REPO_ROOT/evals/harness/grade.py"
RUN="$REPO_ROOT/evals/harness/run_eval.sh"
GI_ISSUE="$REPO_ROOT/src/shared/scripts/gi-issue.py"
CASE="$REPO_ROOT/evals/cases/issue-resolver/gh-call-counter"

PASS=0
FAIL=0
SKIP=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  ○ $1"; SKIP=$((SKIP + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "◆ deterministic cost counters (#465)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

if [ "${EVAL_RECORD:-}" = "1" ]; then
  echo "✗ EVAL_RECORD must be unset — record mode would open the network" >&2
  exit 1
fi

PYTHON_BIN="$(command -v python3 || true)"
if [ -z "$PYTHON_BIN" ]; then
  echo "✗ python3 is required" >&2
  exit 1
fi

# ─── T1: tool is committed executable and documents itself ─
mode="$(cd "$REPO_ROOT" && git ls-files -s scripts/idd-cost-counters.py | awk '{print $1}')"
if [ "$mode" = "100755" ]; then
  pass "T1: scripts/idd-cost-counters.py is committed mode 100755"
else
  fail "T1: scripts/idd-cost-counters.py mode is '${mode:-untracked}', want 100755"
fi
help_ok=0
for args in "--help" "calls --help" "evidence --help"; do
  # shellcheck disable=SC2086
  "$PYTHON_BIN" "$TOOL" $args >/dev/null 2>&1 || help_ok=1
done
if [ "$help_ok" -eq 0 ]; then
  pass "T1: --help exits 0 for the tool and both subcommands"
else
  fail "T1: a --help invocation exited non-zero"
fi

# ─── Shim workspace: PATH holds ONLY the shim, as `gh` ─────
# new_ws <dir> — a fresh workspace whose bin/gh execs the shim.
new_ws() {
  local ws="$1"
  mkdir -p "$ws/bin" "$ws/home"
  printf '#!/bin/sh\nexec "%s" "%s" "$@"\n' "$PYTHON_BIN" "$SHIM" > "$ws/bin/gh"
  chmod 755 "$ws/bin/gh"
}

# shim_env <ws> <log-or-empty> <cmd...> — run with a scrubbed environment.
shim_env() {
  local ws="$1" log="$2"
  shift 2
  if [ -n "$log" ]; then
    (cd "$ws" && env -i PATH="$ws/bin" HOME="$ws/home" GH_TOKEN= \
      EVAL_CASSETTES="$CASE/cassettes.json" EVAL_GH_CALL_LOG="$log" "$@")
  else
    (cd "$ws" && env -i PATH="$ws/bin" HOME="$ws/home" GH_TOKEN= \
      EVAL_CASSETTES="$CASE/cassettes.json" "$@")
  fi
}

# read_flow <ws> <log-or-empty> <with-refresh 0|1> — the resolver's read
# pattern against the REAL gi-issue.py: miss, TTL hit, invalidate, miss, and
# (optionally) a --refresh read. Prints one cache outcome per read.
read_flow() {
  local ws="$1" log="$2" refresh="$3"
  local base=("$PYTHON_BIN" "$GI_ISSUE" 7 --fields number,title,body,labels,state
    --ttl 86400 --cache-dir "$ws/cache")
  shim_env "$ws" "$log" "${base[@]}" | "$PYTHON_BIN" -c 'import json,sys; print(json.load(sys.stdin)["cached"])'
  shim_env "$ws" "$log" "${base[@]}" | "$PYTHON_BIN" -c 'import json,sys; print(json.load(sys.stdin)["cached"])'
  shim_env "$ws" "$log" "$PYTHON_BIN" "$GI_ISSUE" 7 --invalidate --cache-dir "$ws/cache" >/dev/null
  shim_env "$ws" "$log" "${base[@]}" | "$PYTHON_BIN" -c 'import json,sys; print(json.load(sys.stdin)["cached"])'
  if [ "$refresh" = "1" ]; then
    shim_env "$ws" "$log" "${base[@]}" --refresh | "$PYTHON_BIN" -c 'import json,sys; print(json.load(sys.stdin)["cached"])'
  fi
}

count_lines() { if [ -f "$1" ]; then grep -c . "$1"; else echo missing; fi; }

# ─── T2: exact, reproducible count of the real read pattern ─
for run in 1 2; do
  new_ws "$TMP/flow$run"
  read_flow "$TMP/flow$run" "$TMP/flow$run/gh-calls.jsonl" 1 > "$TMP/flow$run/outcomes"
done
outcomes="$(tr '\n' ' ' < "$TMP/flow1/outcomes")"
if [ "$outcomes" = "False True False False " ]; then
  pass "T2: gi-issue.py served miss, hit, miss, refresh through the shim"
else
  fail "T2: unexpected cache outcomes: '$outcomes'"
fi
n1="$(count_lines "$TMP/flow1/gh-calls.jsonl")"
if [ "$n1" = "3" ]; then
  pass "T2: the read pattern costs exactly 3 gh calls (count > 0)"
else
  fail "T2: expected 3 logged gh calls, got $n1"
fi
if cmp -s "$TMP/flow1/gh-calls.jsonl" "$TMP/flow2/gh-calls.jsonl"; then
  pass "T2: two runs in fresh workspaces wrote byte-identical call logs"
else
  fail "T2: call logs differ between identical runs"
fi
want_line='{"argv": ["issue", "view", "7", "--json", "body,labels,number,state,title"]}'
if [ "$(sort -u "$TMP/flow1/gh-calls.jsonl")" = "$want_line" ]; then
  pass "T2: each record is the normalized argv only — no time, pid or path"
else
  fail "T2: a log record carries more than the normalized argv"
fi

# ─── T3: the counter moves when the flow does ──────────────
new_ws "$TMP/variant"
read_flow "$TMP/variant" "$TMP/variant/gh-calls.jsonl" 0 >/dev/null
nv="$(count_lines "$TMP/variant/gh-calls.jsonl")"
if [ "$nv" = "2" ]; then
  pass "T3: dropping the --refresh read counts 2 calls, not 3"
else
  fail "T3: variant flow expected 2 gh calls, got $nv"
fi

# ─── T4: every invocation counts; unset writes nothing ─────
new_ws "$TMP/misc"
log="$TMP/misc/gh-calls.jsonl"
shim_env "$TMP/misc" "$log" gh --version >/dev/null 2>&1
shim_env "$TMP/misc" "$log" gh issue view 1 >/dev/null 2>&1
refused=$?
shim_env "$TMP/misc" "$log" gh >/dev/null 2>&1
if [ "$refused" -eq 2 ] && [ "$(count_lines "$log")" = "3" ]; then
  pass "T4: version, a refused call (exit 2) and a bare call are each logged"
else
  fail "T4: expected 3 logged calls incl. a refused exit 2 (got $(count_lines "$log"), exit $refused)"
fi
new_ws "$TMP/unset"
read_flow "$TMP/unset" "" 1 >/dev/null
if [ -z "$(find "$TMP/unset" -name '*.jsonl' -print)" ]; then
  pass "T4: EVAL_GH_CALL_LOG unset — the shim writes no log"
else
  fail "T4: the shim wrote a log with EVAL_GH_CALL_LOG unset"
fi

# ─── T5: calls summary is exact and byte-stable ────────────
"$PYTHON_BIN" "$TOOL" calls --json "$TMP/flow1/gh-calls.jsonl" > "$TMP/sum1" 2>&1
"$PYTHON_BIN" "$TOOL" calls --json "$TMP/flow2/gh-calls.jsonl" > "$TMP/sum2" 2>&1
if "$PYTHON_BIN" - "$TMP/sum1" "$log" "$TOOL" <<'PY'
import json, subprocess, sys
got = json.load(open(sys.argv[1]))
assert got == {"total": 3, "by_command": {"issue view": 3}}, got
misc = subprocess.run([sys.executable, sys.argv[3], "calls", "--json", sys.argv[2]],
                      capture_output=True, text=True, check=True)
assert json.loads(misc.stdout) == {
    "total": 3, "by_command": {"": 1, "--version": 1, "issue view": 1}
}, misc.stdout
PY
then
  pass "T5: calls reports total and per-command tallies exactly"
else
  fail "T5: calls summary is wrong"
fi
if cmp -s "$TMP/sum1" "$TMP/sum2"; then
  pass "T5: calls --json output is byte-identical across runs"
else
  fail "T5: calls --json output differs across runs"
fi
"$PYTHON_BIN" "$TOOL" calls "$TMP/nope.jsonl" >/dev/null 2>&1
ec=$?
printf 'not json\n' > "$TMP/bad.jsonl"
"$PYTHON_BIN" "$TOOL" calls "$TMP/bad.jsonl" >/dev/null 2>&1
ec_bad=$?
if [ "$ec" -eq 3 ] && [ "$ec_bad" -eq 3 ]; then
  pass "T5: a missing or malformed log exits 3 (invalid input)"
else
  fail "T5: missing/malformed log exited $ec/$ec_bad, want 3/3"
fi
printf '{"argv":["issue","view"]}\n\377\376\n' > "$TMP/nonutf8.jsonl"
"$PYTHON_BIN" "$TOOL" calls "$TMP/nonutf8.jsonl" >/dev/null 2>"$TMP/nonutf8.err"
ec_nonutf8=$?
if [ "$ec_nonutf8" -eq 4 ] && ! grep -q "Traceback" "$TMP/nonutf8.err" && ! grep -q "$TMP" "$TMP/nonutf8.err"; then
  pass "T5: a non-UTF-8 log exits 4 (cannot complete) — no traceback, no path"
else
  fail "T5: non-UTF-8 log exited $ec_nonutf8, want 4 with no traceback or path"; sed 's/^/      /' "$TMP/nonutf8.err"
fi

# ─── T6: grade.py gh-calls handler ─────────────────────────
# grade_case <name> <out-has-log 0|1> <assertion-json> — prints grade exit.
grade_case() {
  local name="$1" with_log="$2" assertion="$3"
  local dir="$TMP/grade-$name"
  mkdir -p "$dir/case" "$dir/out"
  printf '{"name":"t6/%s","grade":[%s]}\n' "$name" "$assertion" > "$dir/case/case.json"
  [ "$with_log" = "1" ] && cp "$TMP/flow1/gh-calls.jsonl" "$dir/out/gh-calls.jsonl"
  "$PYTHON_BIN" "$GRADE" --case "$dir/case" --out "$dir/out" >"$dir/log" 2>&1
  echo $?
}
argv_json='["issue","view","7","--json","body,labels,number,state,title"]'
ok="$(grade_case ok 1 "{\"tool\":\"gh-calls\",\"expect_count\":3,\"expect_by_command\":{\"issue view\":3},\"expect_argv\":[$argv_json,$argv_json,$argv_json]}")"
off="$(grade_case off 1 '{"tool":"gh-calls","expect_count":2}')"
cmd="$(grade_case cmd 1 '{"tool":"gh-calls","expect_by_command":{"pr view":1}}')"
seq="$(grade_case seq 1 "{\"tool\":\"gh-calls\",\"expect_argv\":[$argv_json]}")"
neg="$(grade_case neg 1 '{"tool":"gh-calls","expect_count":4,"expect_exit":1}')"
missing="$(grade_case missing 0 '{"tool":"gh-calls","expect_count":0}')"
missing_neg="$(grade_case missingneg 0 '{"tool":"gh-calls","expect_count":1,"expect_exit":1}')"
escape="$(grade_case escape 1 '{"tool":"gh-calls","file":"OUT/../gh-calls.jsonl","expect_count":3}')"
none="$(grade_case none 1 '{"tool":"gh-calls"}')"
if [ "$ok" = "0" ]; then
  pass "T6: gh-calls passes the exact count, per-command tally and argv sequence"
else
  fail "T6: gh-calls failed a correct expectation"; sed 's/^/      /' "$TMP/grade-ok/log"
fi
if [ "$off" = "1" ] && [ "$neg" = "0" ]; then
  pass "T6: an off-by-one count fails (and passes when expect_exit is 1)"
else
  fail "T6: off-by-one handling wrong (grade exits $off / $neg, want 1 / 0)"
fi
if [ "$cmd" = "1" ] && [ "$seq" = "1" ]; then
  pass "T6: a per-command or argv-sequence mismatch fails"
else
  fail "T6: mismatch not caught (grade exits $cmd / $seq, want 1 / 1)"
fi
if [ "$missing" = "1" ] && [ "$missing_neg" = "1" ]; then
  pass "T6: a missing call log always fails, whatever expect_exit says"
else
  fail "T6: missing log did not fail (grade exits $missing / $missing_neg)"
fi
if [ "$escape" = "1" ] && [ "$none" = "1" ]; then
  pass "T6: a non-OUT path or an assertion with no expectation is rejected"
else
  fail "T6: unsafe/empty assertion accepted (grade exits $escape / $none)"
fi

# ─── T7: evidence on a synthetic transcript fixture ────────
FIX="$TMP/transcripts"
"$PYTHON_BIN" - "$FIX" "$TMP/runs.jsonl" <<'PY'
import json, os, sys

root, runs_log = sys.argv[1], sys.argv[2]

def ts(s):
    return f"2026-01-01T00:{s // 60:02d}:{s % 60:02d}Z"

def asst(mid, t, usage, *uses):
    return {"type": "assistant", "timestamp": ts(t),
            "message": {"id": mid, "usage": usage, "content": list(uses)}}

def bash(tid, command):
    return {"type": "tool_use", "id": tid, "name": "Bash", "input": {"command": command}}

def result(t, tid, content):
    return {"type": "user", "timestamp": ts(t),
            "message": {"content": [{"type": "tool_result", "tool_use_id": tid, "content": content}]}}

def write(session, agent, meta, rows, garbage=False):
    d = os.path.join(root, session, "subagents")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, agent + ".meta.json"), "w") as fh:
        json.dump(meta, fh)
    with open(os.path.join(d, agent + ".jsonl"), "w") as fh:
        for row in rows:
            fh.write(json.dumps(row) + "\n")
        if garbage:
            fh.write("not json\n")

u = lambda i=0, cc=0, cr=0, o=0: {"input_tokens": i, "cache_creation_input_tokens": cc,
                                  "cache_read_input_tokens": cr, "output_tokens": o}
# Run 101: two gh hits in one command, a spawned child, a streamed message whose
# usage repeats (max per id: 10 + 0 + 100 + 20 = 130), a garbage line.
write("sessA", "agent-r1", {"description": "Resolve issue #101", "toolUseId": "top1", "spawnDepth": 1}, [
    asst("m1", 0, u(10, 0, 100, 5),
         bash("b1", "gh issue view 101 --json number && gh pr list --json number")),
    asst("m1", 10, u(10, 0, 100, 20),
         {"type": "tool_use", "id": "a1", "name": "Agent", "input": {}}),
    result(60, "b1", "abcé"),                               # 5 UTF-8 bytes
    result(120, "a1", [{"type": "text", "text": "ok"}]),   # 32 JSON chars
], garbage=True)
# Its child (depth 2): one gh hit, one non-gh Bash, 3 tokens.
write("sessA", "agent-c1", {"description": "child work", "toolUseId": "a1", "spawnDepth": 2}, [
    asst("m2", 30, u(1, 0, 0, 2),
         bash("c1", "cd x && gh api repos/o/r --jq .x"),
         bash("c2", "echo nothing; git log --oneline")),
    result(40, "c1", "xyz"),
    result(41, "c2", "12"),
])
write("sessB", "agent-r2", {"description": "Resolve issue #102", "toolUseId": "top2", "spawnDepth": 1}, [
    asst("m3", 0, u(50), bash("d1", "gh auth status")),
    result(30, "d1", "ok"),
])
write("sessB", "agent-r3", {"description": "Resolve issue #103", "toolUseId": "top3", "spawnDepth": 1}, [
    asst("m4", 0, u(70, o=10), bash("e1", "gh issue list --json n; gh label list --json n")),
    result(90, "e1", ""),
])
# Excluded (in progress), not selected (other flow / depth), and a review run.
write("sessB", "agent-x", {"description": "Resolve issue #465", "toolUseId": "top4", "spawnDepth": 1}, [
    asst("m5", 0, u(9), bash("f1", "gh issue view 465 --json n")),
])
write("sessB", "agent-e", {"description": "Explore stuff", "toolUseId": "top5", "spawnDepth": 1}, [
    asst("m6", 0, u(9), bash("g1", "gh pr view 1 --json n")),
])
write("sessB", "agent-d2", {"description": "Resolve issue #104", "toolUseId": "top6", "spawnDepth": 2}, [])
write("sessA", "agent-rv", {"description": "Review PR #9", "toolUseId": "top7", "spawnDepth": 1}, [
    asst("m7", 0, u(4), bash("h1", "echo gh-free")),
])
with open(runs_log, "w") as fh:
    for rec in ({"issue": 101, "duration_s": 300}, {"issue": 101, "outcome": "success"},
                {"issue": 102, "duration_s": 100}, {"issue": 103, "duration_s": 200},
                {"issue": 465, "duration_s": 5}):
        fh.write(json.dumps(rec) + "\n")
PY
evidence() {
  "$PYTHON_BIN" "$TOOL" evidence "$FIX" --exclude '#465' --runs-log "$TMP/runs.jsonl" "$@"
}
evidence --json > "$TMP/ev1.json" 2>"$TMP/ev1.err"
ev_ec=$?
evidence --json > "$TMP/ev2.json" 2>/dev/null
if [ "$ev_ec" -eq 0 ] && "$PYTHON_BIN" - "$TMP/ev1.json" <<'PY'
import json, sys
ev = json.load(open(sys.argv[1]))
res = ev["flows"]["resolver"]
rows = {r["description"]: r for r in res["runs"]}
assert list(rows) == ["Resolve issue #101", "Resolve issue #102", "Resolve issue #103"], list(rows)
r1 = rows["Resolve issue #101"]
want = {"gh": 3, "gh_bytes": 8, "result_bytes": 42, "spawns": 1, "tools": 4,
        "tokens": 133, "wall_s": 120, "children": 1, "session": "sessA"}
assert {k: r1[k] for k in want} == want, r1
assert rows["Resolve issue #102"]["gh"] == 1 and rows["Resolve issue #102"]["tokens"] == 50
assert rows["Resolve issue #103"]["gh"] == 2 and rows["Resolve issue #103"]["tokens"] == 80
assert res["n"] == 3
assert res["counters"]["gh"]["rho_tokens"] == 1.0, res["counters"]["gh"]
assert 0 < res["counters"]["gh"]["p_tokens"] <= 1
join = res["duration_join"]
assert join["n"] == 3 and join["gh"]["rho"] == 1.0, join
rv = ev["flows"]["review"]
assert [r["description"] for r in rv["runs"]] == ["Review PR #9"] and rv["n"] == 1
assert rv["counters"]["gh"]["rho_tokens"] is None  # n < 3 → no statistic
assert "duration_join" not in rv
PY
then
  pass "T7: exact per-run numbers — token dedupe, child aggregation, gh regex, selection"
else
  fail "T7: evidence numbers are wrong (exit $ev_ec)"; sed 's/^/      /' "$TMP/ev1.err"
fi
if [ -s "$TMP/ev1.json" ] && cmp -s "$TMP/ev1.json" "$TMP/ev2.json"; then
  pass "T7: evidence --json is byte-identical across runs with the same seed"
else
  fail "T7: evidence output differs across identical runs"
fi
evidence > "$TMP/ev.txt" 2>/dev/null
if [ -s "$TMP/ev.txt" ] && ! grep -q "$FIX" "$TMP/ev.txt" "$TMP/ev1.json" && ! grep -q "abc\|nothing" "$TMP/ev.txt" "$TMP/ev1.json"; then
  pass "T7: output carries neither the transcripts path nor transcript text"
else
  fail "T7: evidence output leaks the transcripts path or transcript text"
fi

# ─── T8: evidence exit vocabulary ──────────────────────────
"$PYTHON_BIN" "$TOOL" evidence >/dev/null 2>&1
ec_usage=$?
"$PYTHON_BIN" "$TOOL" evidence "$TMP/no-such-dir" >/dev/null 2>&1
ec_missing=$?
"$PYTHON_BIN" "$TOOL" evidence "$FIX" --exclude '(' >/dev/null 2>&1
ec_regex=$?
if [ "$ec_usage" -eq 2 ] && [ "$ec_missing" -eq 3 ] && [ "$ec_regex" -eq 3 ]; then
  pass "T8: no dir → 2 (usage); missing dir or bad --exclude → 3 (invalid input)"
else
  fail "T8: exits were $ec_usage/$ec_missing/$ec_regex, want 2/3/3"
fi
BAD="$TMP/bad-transcripts"
mkdir -p "$BAD/s/subagents"
printf '{"description":"Resolve issue #1","spawnDepth":1}\n' > "$BAD/s/subagents/a.meta.json"
printf '\377\n' > "$BAD/s/subagents/a.jsonl"
"$PYTHON_BIN" "$TOOL" evidence "$BAD" >/dev/null 2>"$TMP/bad-ev.err"
ec_undecodable=$?
if [ "$ec_undecodable" -eq 4 ] && ! grep -q "Traceback" "$TMP/bad-ev.err" && ! grep -q "$BAD" "$TMP/bad-ev.err"; then
  pass "T8: a non-UTF-8 transcript exits 4 — no traceback, DIR not echoed"
else
  fail "T8: non-UTF-8 transcript exited $ec_undecodable, want 4 with no traceback or DIR"; sed 's/^/      /' "$TMP/bad-ev.err"
fi

# ─── T9: run_eval.sh validates repo_scripts before any subject ─
for bad in '"../../etc/passwd"' '"src/shared/scripts/no-such-script.py"' '"scripts/idd-lint.py"'; do
  bad_case="$TMP/bad-case"
  rm -rf "$bad_case"
  cp -R "$CASE" "$bad_case"
  printf '{"name":"t9","repo_scripts":[%s],"grade":[{"tool":"gh-calls","expect_count":0}]}\n' \
    "$bad" > "$bad_case/case.json"
  # A subject that would leave a marker proves it never ran.
  printf '#!/usr/bin/env bash\ntouch "%s/ran"\n' "$TMP" > "$bad_case/subject.sh"
  bash "$RUN" "$bad_case" >"$TMP/t9.log" 2>&1
  ec=$?
  if [ "$ec" -eq 2 ] && [ ! -e "$TMP/ran" ] && grep -q "invalid repo_scripts" "$TMP/t9.log"; then
    pass "T9: repo_scripts $bad rejected (exit 2) before the subject ran"
  else
    fail "T9: repo_scripts $bad not rejected (exit $ec)"
  fi
  rm -f "$TMP/ran"
done

# ─── T10: run_eval.sh, sandboxed — the authoritative run ───
sandbox_available() {
  local unshare sudo_bin setpriv
  case "$(uname -s)" in
    Darwin)
      command -v sandbox-exec >/dev/null 2>&1
      return $?
      ;;
    Linux) ;;
    *) return 1 ;;
  esac
  unshare="$(command -v unshare || true)"
  [ -n "$unshare" ] || return 1
  "$unshare" --user --map-current-user --net true >/dev/null 2>&1 && return 0
  sudo_bin="$(command -v sudo || true)"
  setpriv="$(command -v setpriv || true)"
  [ -n "$sudo_bin" ] && [ -n "$setpriv" ] || return 1
  "$sudo_bin" -n "$unshare" --net --fork "$setpriv" \
    --reuid="$(id -u)" --regid="$(id -g)" --clear-groups true >/dev/null 2>&1
}

if ! sandbox_available; then
  if [ "${IDD_EVAL_REQUIRE_SANDBOX:-}" = "1" ]; then
    fail "T10: no OS network sandbox and IDD_EVAL_REQUIRE_SANDBOX=1"
  else
    skip "T10: no OS network sandbox on this host; run_eval.sh not run"
  fi
elif bash "$RUN" "$CASE" >"$TMP/t10.log" 2>&1; then
  pass "T10: issue-resolver/gh-call-counter passed run_eval.sh (sandboxed)"
else
  fail "T10: issue-resolver/gh-call-counter failed run_eval.sh"
  sed -n '1,30p' "$TMP/t10.log" | sed 's/^/      /'
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ cost counters are not deterministic or not exact"
  exit 1
fi
if [ "$SKIP" -gt 0 ]; then
  echo "  ⚠ $SKIP sandboxed run(s) skipped — host-independent coverage only"
fi
echo "  ✓ gh-call counts are exact, reproducible and offline (#465)"
exit 0
