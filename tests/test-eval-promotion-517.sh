#!/usr/bin/env bash
# test-eval-promotion-517.sh — blinded real-agent promotion lane (#517)
#
# Drives evals/harness/agent_eval.py end to end against a throwaway git repo
# (baseline commit with skills v1, candidate commit with skills v2), a private
# store outside that repo, and a stub agent. Covers: --help and mode, the CI /
# opt-in / EVAL_RECORD refusals, agent-config validation, lock enforcement,
# the clean-tree gate, pre-run held-out and staging leak checks, recorded
# provenance, blind packets, the verdict rule, artifact verification, and
# post-run leak detection.
#
# Offline and hermetic: no network, no gh auth, no sandbox required.
#
# Usage: bash tests/test-eval-promotion-517.sh

set -euo pipefail

# The throwaway repo has no .gitignore: a __pycache__ would dirty its tree and
# trip the driver's clean-tree gate for an unrelated reason.
export PYTHONDONTWRITEBYTECODE=1

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ eval promotion lane tests (#517)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ─── Fixture: throwaway repo, private store, stub agent ────
R="$TMP/repo"
STORE="$TMP/store"
DRIVER="$R/evals/harness/agent_eval.py"
CANARY="IDD-CANARY-517-not-a-secret-fixture"

mkdir -p "$R/evals/harness" "$R/skills/demo"
for f in agent_eval.py gh_shim.py grade.py; do
  cp "$REPO_ROOT/evals/harness/$f" "$R/evals/harness/$f"
done
git -C "$R" init -q
git -C "$R" config user.name "idd-test"
git -C "$R" config user.email "idd-test@example.invalid"
git -C "$R" config commit.gpgsign false

echo "behavior: v1" > "$R/skills/demo/SKILL.md"
git -C "$R" add -A && git -C "$R" commit -q -m "baseline"
BASE="$(git -C "$R" rev-parse HEAD)"
echo "behavior: v2" > "$R/skills/demo/SKILL.md"
git -C "$R" add -A && git -C "$R" commit -q -m "candidate"
CAND="$(git -C "$R" rev-parse HEAD)"

PROMPT="Open a pull request that records the demo behavior line from the skill file you were given."

mkdir -p "$STORE/tasks/demo-task/fixture_repo" "$STORE/rubrics"
python3 - "$STORE" "$PROMPT" "$CANARY" "$BASE" <<'PY'
import json, sys
from pathlib import Path
store, prompt, canary, base = Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]

def put(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2) + "\n")

cassettes = {"version": 1, "calls": [{
    "match": "prefix", "argv": ["pr", "create"],
    "stdout": "https://github.com/eval/harness/pull/1\n", "exit": 0}]}
criteria = [
    {"id": "opens-pr", "text": "The agent opens exactly one pull request whose body says the work is done"},
    {"id": "reports-behavior", "text": "The transcript reports the behavior line read from the provided skill file"},
]
checks = [
    {"tool": "file-exists", "file": "OUT/result.txt", "label": "agent wrote result.txt"},
    {"tool": "gh-calls", "expect_by_command": {"pr create": 1}, "label": "exactly one pr create"},
]
for tid, extra in (("demo-task", None), ("leak-task", canary)):
    put(store / "tasks" / tid / "task.json",
        {"version": 1, "id": tid, "skill": "demo", "prompt": prompt, "min_runs": 2})
    put(store / "tasks" / tid / "cassettes.json", cassettes)
    put(store / "rubrics" / f"{tid}.json",
        {"version": 1, "task_id": tid, "canary": canary, "criteria": criteria,
         "checks": checks, "pass_threshold": 1.0, "min_pass_rate": 0.5})
# The fixture carries the baseline SHA so T8 can prove the packets scrub it.
(store / "tasks" / "demo-task" / "fixture_repo" / "notes.txt").write_text(
    f"base {base} short {base[:7]}\n")
(store / "tasks" / "leak-task" / "fixture_repo").mkdir(parents=True, exist_ok=True)
(store / "tasks" / "leak-task" / "fixture_repo" / "leak.txt").write_text(f"hint: {canary}\n")
PY

cat > "$TMP/stub-agent.sh" <<'SH'
#!/usr/bin/env bash
set -u
echo "stub agent: starting in $(pwd)"
echo "skills at $EVAL_SKILLS_DIR, out at $EVAL_OUT"
echo "comparing baseline and Candidate wording"
echo "prompt: $(cat "$EVAL_PROMPT_FILE")"
grep -h 'behavior:' "$EVAL_SKILLS_DIR/demo/SKILL.md"
cat notes.txt
gh pr create --title "fix" --body "done"
echo "result" > "$EVAL_OUT/result.txt"
if [ -n "${STUB_LEAK:-}" ]; then echo "$STUB_LEAK"; fi
echo "stub agent: done" >&2
SH

agent_config() {  # agent_config <file> <python-dict-edits>
  python3 - "$1" "$TMP/stub-agent.sh" "$2" <<'PY'
import json, sys
cfg = {"command": ["bash", sys.argv[2], "{prompt_file}", "{skills_dir}"],
       "model": "stub-model-1", "cli": "stub-cli", "cli_version": "0.0.1",
       "tools": ["bash", "gh"], "pass_env": ["STUB_LEAK"]}
exec(sys.argv[3])
open(sys.argv[1], "w").write(json.dumps(cfg))
PY
}
agent_config "$TMP/agent.json" "pass"

# The stub above stands in for a real agent CLI. The driver refuses to run in
# CI (CI / GITHUB_ACTIONS) so nobody starts paid model runs by accident; T2
# asserts that refusal on its own, so the positive runs unset those variables
# and opt in explicitly.
# TMPDIR points the driver's throwaway staging root at a directory T7 can
# inspect for leftovers.
SYSTMP="$TMP/systmp"
mkdir -p "$SYSTMP"
drive() {
  local sub="$1"
  shift
  env -u CI -u GITHUB_ACTIONS -u EVAL_RECORD -u IDD_PROMOTION_STORE IDD_EVAL_AGENT=1 \
    TMPDIR="$SYSTMP" python3 "$DRIVER" "$sub" --store "$STORE" "$@"
}
run_count() { find "$STORE/runs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '; }

drive lock --task-id demo-task >/dev/null 2>&1
drive lock --task-id leak-task >/dev/null 2>&1
git -C "$R" add -A && git -C "$R" commit -q -m "lock tasks"
# A side branch whose skills tree already holds the held-out prompt.
git -C "$R" checkout -q -b leaky
echo "$PROMPT" > "$R/skills/demo/NOTES.md"
git -C "$R" add -A && git -C "$R" commit -q -m "contaminated"
git -C "$R" checkout -q -
HEAD_SHA="$(git -C "$R" rev-parse HEAD)"

RUN_ARGS=(--task-id demo-task --baseline "$BASE" --candidate "$CAND" \
  --agent-config "$TMP/agent.json" --seed 7 --timeout 60)

# ─── T1: --help, py_compile, mode ──────────────────────────
HELP_OK=1
python3 "$REPO_ROOT/evals/harness/agent_eval.py" --help >/dev/null 2>&1 || HELP_OK=0
for sub in lock run verdict verify; do
  python3 "$REPO_ROOT/evals/harness/agent_eval.py" "$sub" --help >/dev/null 2>&1 || HELP_OK=0
done
python3 -c 'import py_compile, sys; py_compile.compile(sys.argv[1], cfile=sys.argv[2], doraise=True)' \
  "$REPO_ROOT/evals/harness/agent_eval.py" "$TMP/agent_eval.pyc" >/dev/null 2>&1 || HELP_OK=0
MODE="$(git -C "$REPO_ROOT" ls-files -s evals/harness/agent_eval.py | awk '{print $1}')"
if [ -n "$MODE" ]; then
  [ "$MODE" = "100755" ] || HELP_OK=0
else
  [ -x "$REPO_ROOT/evals/harness/agent_eval.py" ] || HELP_OK=0
fi
if [ "$HELP_OK" -eq 1 ]; then
  pass "T1: --help exits 0 (top level + 4 subcommands), compiles, mode 0755"
else
  fail "T1: --help / py_compile / mode 0755 (git mode: ${MODE:-untracked})"
fi

# ─── T2: refusals before anything runs ─────────────────────
refused() {  # refused <env args...> — run must exit 2 and create no run dir
  local before ec
  before="$(run_count)"
  set +e
  env -u CI -u GITHUB_ACTIONS -u EVAL_RECORD -u IDD_EVAL_AGENT "$@" \
    python3 "$DRIVER" run --store "$STORE" "${RUN_ARGS[@]}" >/dev/null 2>&1
  ec=$?
  set -e
  [ "$ec" -eq 2 ] && [ "$(run_count)" = "$before" ]
}
T2_OK=1
refused CI=true IDD_EVAL_AGENT=1 || T2_OK=0
refused GITHUB_ACTIONS=true IDD_EVAL_AGENT=1 || T2_OK=0
refused || T2_OK=0
refused IDD_EVAL_AGENT=1 EVAL_RECORD=1 || T2_OK=0
if [ "$T2_OK" -eq 1 ] && [ "$(run_count)" = "0" ]; then
  pass "T2: run refused (exit 2, no run dir) under CI, GITHUB_ACTIONS, no opt-in, EVAL_RECORD"
else
  fail "T2: CI / opt-in / EVAL_RECORD refusals"
fi

# ─── T3: agent config validation ───────────────────────────
expect_exit() {  # expect_exit <code> <drive args...>
  local want="$1" ec
  shift
  set +e
  drive "$@" >"$TMP/last.json" 2>"$TMP/last.err"
  ec=$?
  set -e
  [ "$ec" -eq "$want" ]
}
agent_config "$TMP/agent-token.json" "cfg['pass_env'] = ['GH_TOKEN']"
agent_config "$TMP/agent-nomodel.json" "del cfg['model']"
agent_config "$TMP/agent-notools.json" "cfg['tools'] = []"
T3_OK=1
for cfg in agent-token agent-nomodel agent-notools; do
  expect_exit 3 run --task-id demo-task --baseline "$BASE" --candidate "$CAND" \
    --agent-config "$TMP/$cfg.json" || T3_OK=0
done
if [ "$T3_OK" -eq 1 ] && [ "$(run_count)" = "0" ]; then
  pass "T3: agent config with GH_TOKEN pass_env / no model / empty tools exits 3"
else
  fail "T3: agent config validation"
fi

# ─── T4: lock enforcement ──────────────────────────────────
cp "$STORE/rubrics/demo-task.json" "$TMP/rubric.bak"
printf ' \n' >> "$STORE/rubrics/demo-task.json"
T4_OK=1
expect_exit 3 run "${RUN_ARGS[@]}" && grep -q "rubric changed" "$TMP/last.err" || T4_OK=0
cp "$TMP/rubric.bak" "$STORE/rubrics/demo-task.json"
mkdir -p "$STORE/tasks/other-task"
printf '{"version":1,"id":"other-task","skill":"demo","prompt":"other","min_runs":1}\n' \
  > "$STORE/tasks/other-task/task.json"
sed 's/"demo-task"/"other-task"/' "$TMP/rubric.bak" > "$STORE/rubrics/other-task.json"
expect_exit 3 run --task-id other-task --baseline "$BASE" --candidate "$CAND" \
  --agent-config "$TMP/agent.json" && grep -q "not locked" "$TMP/last.err" || T4_OK=0
rm -rf "$STORE/tasks/other-task" "$STORE/rubrics/other-task.json"
if [ "$T4_OK" -eq 1 ] && [ "$(run_count)" = "0" ]; then
  pass "T4: rubric edited after lock → 3; unlocked task → 3; no run dir"
else
  fail "T4: lock enforcement"
fi

# ─── T5: dirty tree ────────────────────────────────────────
touch "$R/untracked.txt"
if expect_exit 4 run "${RUN_ARGS[@]}" && grep -q "dirty tree" "$TMP/last.err"; then
  pass "T5: untracked file in the repo → exit 4 (dirty tree)"
else
  fail "T5: dirty tree gate"
fi
rm -f "$R/untracked.txt"

# ─── T6: pre-run leak checks ───────────────────────────────
T6_OK=1
expect_exit 3 run --task-id leak-task --baseline "$BASE" --candidate "$CAND" \
  --agent-config "$TMP/agent.json" || T6_OK=0
python3 - "$TMP/last.json" <<'PY' || T6_OK=0
import json, sys
r = json.load(open(sys.argv[1]))
assert r["stage"] == "pre" and not r["held_out"], r
assert any(o["reason"] == "canary" and o["path"].endswith("leak.txt") for o in r["staging"]), r
PY
expect_exit 3 run --task-id demo-task --baseline "$BASE" --candidate leaky \
  --agent-config "$TMP/agent.json" || T6_OK=0
python3 - "$TMP/last.json" <<'PY' || T6_OK=0
import json, sys
r = json.load(open(sys.argv[1]))
assert r["stage"] == "pre" and not r["staging"], r
assert [o["arm"] for o in r["held_out"]] == ["candidate"], r
assert r["held_out"][0]["path"].endswith("skills/demo/NOTES.md"), r
PY
if [ "$T6_OK" -eq 1 ] && [ "$(run_count)" = "0" ]; then
  pass "T6: fixture carrying the canary → 3 (staging); prompt in candidate skills → 3 (held-out); no run dir, no agent ran"
else
  fail "T6: pre-run leak checks"
fi

# ─── T7: end-to-end, n=2 per arm ───────────────────────────
set +e
drive run "${RUN_ARGS[@]}" --runs 2 >"$TMP/run.json" 2>"$TMP/run.err"
RUN_EC=$?
set -e
RUN_DIR="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("run_dir",""))' "$TMP/run.json" 2>/dev/null || true)"
if [ "$RUN_EC" -eq 0 ] && [ -n "$RUN_DIR" ] && python3 - "$RUN_DIR" "$R" "$BASE" "$CAND" "$HEAD_SHA" "$TMP/run.json" "$STORE" "$SYSTMP" <<'PY'
import hashlib, json, os, subprocess, sys
from pathlib import Path
run, repo, base, cand, head = Path(sys.argv[1]), Path(sys.argv[2]), *sys.argv[3:6]
out = json.load(open(sys.argv[6]))
store, systmp = Path(sys.argv[7]), Path(sys.argv[8])
# The agent worked outside the store (no private rubric a few `..` above its
# cwd), and the throwaway staging root is gone afterwards.
assert os.listdir(systmp) == [], os.listdir(systmp)
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
key = json.loads((run / "sealed/key.json").read_text())
prov = json.loads((run / "provenance.json").read_text())
assert out["runs"] == 4 and out["leaks"] == 0, out
assert sorted(r["arm"] for r in key.values()) == ["baseline"] * 2 + ["candidate"] * 2
for bid, rec in key.items():
    raw = run / rec["raw"]
    assert rec["raw"] == f"raw/{bid}", rec
    text = (raw / "transcript.txt").read_text()
    assert "stub agent: starting" in text, text
    cwd = text.splitlines()[0].split(" in ", 1)[1]
    assert "/idd-agent-" in cwd and cwd.endswith("/workspace"), cwd
    assert str(store) not in cwd and str(store.resolve()) not in cwd, cwd
    want, other = ("v1", "v2") if rec["arm"] == "baseline" else ("v2", "v1")
    assert f"behavior: {want}" in text and f"behavior: {other}" not in text, (rec, text)
    assert rec["exit"] == 0 and rec["checks_passed"] is True and rec["leak"] is False, rec
# Nothing the agent can see is named after its arm.
for p in run.rglob("*"):
    assert "baseline" not in p.name and "candidate" not in p.name, p
assert prov["sha"] == head and prov["clean_tree"] is True
for arm, want in (("baseline", base), ("candidate", cand)):
    a = prov["arms"][arm]
    tree = subprocess.check_output(["git", "-C", str(repo), "rev-parse", f"{want}:skills"], text=True).strip()
    assert a["sha"] == want and a["skills_tree"] == tree, a
d = prov["agent"]["declared"]
assert d["model"] == "stub-model-1" and d["tools"] == ["bash", "gh"] and d["cli_version"] == "0.0.1", d
lock = json.loads((repo / "evals/promotion/lock.json").read_text())["tasks"]["demo-task"]
t = prov["task"]
assert t["task_sha256"] == lock["task_sha256"] and t["rubric_sha256"] == lock["rubric_sha256"], t
assert t["lock_path"] == "evals/promotion/lock.json" and t["lock_sha256"] == sha(repo / "evals/promotion/lock.json")
assert [h["path"] for h in prov["harness"]] == [
    "evals/harness/agent_eval.py", "evals/harness/gh_shim.py", "evals/harness/grade.py"]
for h in prov["harness"]:
    assert h["sha256"] == sha(repo / h["path"]), h
assert prov["executor"].get("host") and "uid" in prov["executor"], prov["executor"]
assert prov["runs"] == {"per_arm": 2, "seed": 7, "timeout_s": 60, "min_runs": 2}, prov["runs"]
assert prov["verdict"] is None
paths = [a["path"] for a in prov["artifacts"]]
assert paths == sorted(paths) and "sealed/key.json" in paths
assert sum(p.endswith("/transcript.txt") and p.startswith("raw/") for p in paths) == 4
for a in prov["artifacts"]:
    assert a["sha256"] == sha(run / a["path"]) and a["bytes"] == (run / a["path"]).stat().st_size, a
PY
then
  pass "T7: 4 shuffled runs; v1/v2 per sealed arm; provenance records sha, clean tree, arms, model/tools, lock, harness, artifacts"
else
  fail "T7: end-to-end run (exit $RUN_EC)"
  sed 's/^/    │ /' "$TMP/run.err" | head -20
fi

# ─── T8: blinding ──────────────────────────────────────────
if [ -n "$RUN_DIR" ] && python3 - "$RUN_DIR" "$BASE" "$CAND" "$CANARY" <<'PY'
import hashlib, json, re, sys
from pathlib import Path
run, base, cand, canary = Path(sys.argv[1]), *sys.argv[2:5]
blind = run / "blind"
files = [p for p in blind.rglob("*") if p.is_file()]
assert files
forbidden = [base, cand, base[:7], cand[:7], str(run), str(run.resolve()), canary, "idd-agent-"]
for p in files:
    text = p.read_text()
    for token in forbidden:
        assert token not in text, (p, token)
    assert not re.search(r"\b(baseline|candidate)\b", text, re.I), p
key = json.loads((run / "sealed/key.json").read_text())
template = json.loads((blind / "scores.template.json").read_text())
assert set(template) == set(key)
for bid in key:
    packet = blind / bid
    assert (packet / "transcript.txt").read_text().count("[redacted]") >= 3
    assert (packet / "out/result.txt").read_text() == "result\n"
    criteria = (packet / "criteria.json").read_text()
    assert "canary" not in criteria and "checks" not in criteria
    assert [c["id"] for c in json.loads(criteria)] == ["opens-pr", "reports-behavior"]
prov = json.loads((run / "provenance.json").read_text())
assert prov["key_sha256"] == hashlib.sha256((run / "sealed/key.json").read_bytes()).hexdigest()
PY
then
  pass "T8: blind packets carry no arm SHA, arm word, run path or canary; template keys == sealed key; key_sha256 matches"
else
  fail "T8: blinding"
fi

# ─── T9: verdict + verify ──────────────────────────────────
scores() {  # scores <file> <candidate-value> <baseline-value> [drop-one]
  python3 - "$RUN_DIR" "$@" <<'PY'
import json, sys
from pathlib import Path
run, path, cv, bv = Path(sys.argv[1]), sys.argv[2], sys.argv[3] == "1", sys.argv[4] == "1"
key = json.loads((run / "sealed/key.json").read_text())
out = {bid: {"opens-pr": cv if r["arm"] == "candidate" else bv,
             "reports-behavior": cv if r["arm"] == "candidate" else bv}
       for bid, r in key.items()}
if len(sys.argv) > 5:
    out.pop(sorted(out)[0])
Path(path).write_text(json.dumps(out))
PY
}
verdict_of() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("result",""))' "$1" 2>/dev/null || true; }
verified_of() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("verified",""))' "$1" 2>/dev/null || true; }
T9_OK=1
if [ -n "$RUN_DIR" ]; then
  # A verdict is final per run, so the reject case runs on a copy (artifact
  # paths are run-dir-relative and the rubric comes from the store).
  cp -R "$RUN_DIR" "$TMP/run-reject"
  cp -R "$RUN_DIR" "$TMP/run-bad"
  scores "$TMP/scores-reject.json" 0 1
  drive verdict --run-dir "$TMP/run-reject" --scores "$TMP/scores-reject.json" >"$TMP/v.json" 2>/dev/null || T9_OK=0
  [ "$(verdict_of "$TMP/v.json")" = "reject" ] || T9_OK=0
  scores "$TMP/scores-short.json" 1 0 drop
  expect_exit 3 verdict --run-dir "$RUN_DIR" --scores "$TMP/scores-short.json" \
    && grep -q "exactly every blind id" "$TMP/last.err" || T9_OK=0
  scores "$TMP/scores.json" 1 0
  drive verdict --run-dir "$RUN_DIR" --scores "$TMP/scores.json" >"$TMP/v.json" 2>/dev/null || T9_OK=0
  [ "$(verdict_of "$TMP/v.json")" = "promote" ] || T9_OK=0
  python3 - "$RUN_DIR" <<'PY' || T9_OK=0
import json, sys
from pathlib import Path
prov = json.loads((Path(sys.argv[1]) / "provenance.json").read_text())
v = prov["verdict"]
assert v["result"] == "promote", v
assert v["candidate"] == {"passed": 2, "n": 2, "pass_rate": 1.0}, v
assert v["baseline"] == {"passed": 0, "n": 2, "pass_rate": 0.0}, v
assert "scores.json" in [a["path"] for a in prov["artifacts"]]
PY
  drive verify --run-dir "$RUN_DIR" >"$TMP/verify.json" 2>/dev/null || T9_OK=0
  [ "$(verified_of "$TMP/verify.json")" = "True" ] || T9_OK=0
  # Re-scoring after unsealing would reveal arms: a second verdict is refused.
  cp "$RUN_DIR/provenance.json" "$TMP/prov-before.json"
  expect_exit 3 verdict --run-dir "$RUN_DIR" --scores "$TMP/scores-reject.json" \
    && grep -q "already recorded" "$TMP/last.err" || T9_OK=0
  cmp -s "$RUN_DIR/provenance.json" "$TMP/prov-before.json" || T9_OK=0
  # A malformed record is invalid input (3), never a traceback (1).
  python3 - "$TMP/run-bad/provenance.json" <<'PY' || T9_OK=0
import json, sys
prov = json.load(open(sys.argv[1]))
prov["task"] = "demo-task"
open(sys.argv[1], "w").write(json.dumps(prov))
PY
  expect_exit 3 verdict --run-dir "$TMP/run-bad" --scores "$TMP/scores.json" || T9_OK=0
  expect_exit 3 verify --run-dir "$TMP/run-bad" || T9_OK=0
  ! grep -q Traceback "$TMP/last.err" || T9_OK=0
  FIRST_RAW="$(ls "$RUN_DIR"/raw/*/transcript.txt | head -1)"
  echo "tampered" >> "$FIRST_RAW"
  drive verify --run-dir "$RUN_DIR" >"$TMP/verify.json" 2>/dev/null || T9_OK=0
  [ "$(verified_of "$TMP/verify.json")" = "False" ] || T9_OK=0
else
  T9_OK=0
fi
if [ "$T9_OK" -eq 1 ]; then
  pass "T9: verdict reject/promote by the rule, final once recorded; verify true, then false after tampering; short scores / malformed provenance → 3"
else
  fail "T9: verdict + verify"
fi

# ─── T10: post-run leak invalidates the run ────────────────
T10_OK=1
set +e
STUB_LEAK="$CANARY" drive run "${RUN_ARGS[@]}" --runs 1 >"$TMP/run2.json" 2>/dev/null
EC10=$?
set -e
RUN2="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("run_dir",""))' "$TMP/run2.json" 2>/dev/null || true)"
if [ "$EC10" -eq 0 ] && [ -n "$RUN2" ]; then
  python3 - "$RUN2" <<'PY' || T10_OK=0
import json, sys
from pathlib import Path
prov = json.loads((Path(sys.argv[1]) / "provenance.json").read_text())
assert prov["leakcheck"]["post_leaks"] == 2, prov["leakcheck"]
PY
  RUN_DIR="$RUN2" scores "$TMP/scores-leak.json" 1 1
  drive verdict --run-dir "$RUN2" --scores "$TMP/scores-leak.json" >"$TMP/v2.json" 2>/dev/null || T10_OK=0
  [ "$(verdict_of "$TMP/v2.json")" = "invalid" ] || T10_OK=0
else
  T10_OK=0
fi
if [ "$T10_OK" -eq 1 ]; then
  pass "T10: canary in the transcript → post_leaks > 0, verdict invalid even with all-true scores"
else
  fail "T10: post-run leak detection (exit $EC10)"
fi

# ─── T11: repo wiring ──────────────────────────────────────
T11_OK=1
python3 - "$REPO_ROOT" <<'PY' || T11_OK=0
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
lock = json.loads((root / "evals/promotion/lock.json").read_text())
assert lock["version"] == 1 and isinstance(lock["tasks"], dict)
sys.path.insert(0, str(root / "evals/harness"))
import grade
assert sorted(grade.GRADE_HANDLERS) == sorted(
    ["idd-lint", "gi-runlog-echo", "file-exists", "red-green", "shell", "gh-calls"])
PY
grep -qx 'evals/promotion/private/' "$REPO_ROOT/.gitignore" || T11_OK=0
grep -q 'run: bash tests/test-eval-promotion-517.sh' "$REPO_ROOT/.github/workflows/dist-check.yml" || T11_OK=0
grep -q '^## Promotion lane' "$REPO_ROOT/evals/README.md" || T11_OK=0
if [ "$T11_OK" -eq 1 ]; then
  pass "T11: lock.json shape, .gitignore store, dist-check step, README section, 6 grade handlers"
else
  fail "T11: repo wiring"
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
