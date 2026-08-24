#!/usr/bin/env bash
# test-eval-triage-autopilot-357.sh — behavioral evals for issue-triage
# ordering and auto-pilot merge gating (issue #357 / F-TEST-005).
#
# The authoritative runner for a case is evals/harness/run_eval.sh, which
# refuses to execute a subject without an OS-level network sandbox. That gate
# is deliberate (#342) and is neither weakened nor bypassed here: T6 invokes
# run_eval.sh unchanged, and skips only when the host cannot sandbox at all.
#
# Everything before T6 is host-independent, so the two new cases stay guarded
# on a developer machine that has no user+network namespaces:
#   T1  case manifests are well formed and only name tools the grader has
#   T2  cassettes are replayable — every recorded argv matched by the shim
#   T3  subjects follow the hermetic-subject contract
#   T4  the expected triage order agrees with gi-triage-graph.py, and the
#       expected dependency gate agrees with gi-deps.py (repo oracles)
#   T5  subject + grade.py run end to end, without the OS network sandbox
#   T6  run_eval.sh, sandboxed — the authoritative run
#
# Usage: bash tests/test-eval-triage-autopilot-357.sh
# Set IDD_EVAL_REQUIRE_SANDBOX=1 (CI does) to turn a T6 skip into a failure.
# Returns: exit 0 if all tests pass, exit 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN="$REPO_ROOT/evals/harness/run_eval.sh"
SHIM="$REPO_ROOT/evals/harness/gh_shim.py"
GRADE="$REPO_ROOT/evals/harness/grade.py"
TRIAGE_CASE="$REPO_ROOT/evals/cases/issue-triage/ordering"
AUTOPILOT_CASE="$REPO_ROOT/evals/cases/auto-pilot/merge-gating"
CASES=("$TRIAGE_CASE" "$AUTOPILOT_CASE")

PASS=0
FAIL=0
SKIP=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  ○ $1"; SKIP=$((SKIP + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "◆ issue-triage / auto-pilot behavioral evals (#357)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# Fail closed: record mode would open the network.
if [ "${EVAL_RECORD:-}" = "1" ]; then
  echo "✗ EVAL_RECORD must be unset in CI" >&2
  exit 1
fi

PYTHON_BIN="$(command -v python3 || true)"
if [ -z "$PYTHON_BIN" ]; then
  echo "✗ python3 is required" >&2
  exit 1
fi

# ───────────────────────────────────────────────────────────
# T1: case manifests are well formed
# ───────────────────────────────────────────────────────────
for case_dir in "${CASES[@]}"; do
  name="$(basename "$(dirname "$case_dir")")/$(basename "$case_dir")"
  if "$PYTHON_BIN" - "$case_dir" "$GRADE" <<'PY'
import importlib.util
import json
import re
import sys
from pathlib import Path

case_dir = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("grade", sys.argv[2])
grade = importlib.util.module_from_spec(spec)
spec.loader.exec_module(grade)

for required in ("case.json", "cassettes.json", "subject.sh"):
    assert (case_dir / required).is_file(), f"missing {required}"

case = json.loads((case_dir / "case.json").read_text(encoding="utf-8"))
assert case.get("name") == f"{case_dir.parent.name}/{case_dir.name}", "name must be <skill>/<case>"
assert case.get("skill") == case_dir.parent.name, "skill must match the parent directory"
assert isinstance(case.get("prompt"), str) and case["prompt"].strip(), "prompt must be non-empty"

grades = case.get("grade")
assert isinstance(grades, list) and grades, "grade must be a non-empty list"
seen_labels = set()
for assertion in grades:
    assert isinstance(assertion, dict), "each assertion must be an object"
    tool = assertion.get("tool")
    assert tool in grade.GRADE_HANDLERS, f"unknown grade tool {tool!r}"
    assert isinstance(assertion.get("expect_exit"), int), "expect_exit must be an integer"
    label = assertion.get("label")
    assert isinstance(label, str) and label.strip(), "each assertion needs a label"
    assert label not in seen_labels, f"duplicate label {label!r}"
    seen_labels.add(label)
    # Every artifact this case grades must be OUT-relative and traversal-free.
    tokens = [assertion["file"]] if assertion.get("file") else []
    tokens += [str(a) for a in assertion.get("args") or []]
    for token in tokens:
        if not token.startswith("OUT"):
            continue
        assert re.fullmatch(r"OUT/[A-Za-z0-9._/-]+", token), f"bad OUT token {token!r}"
        assert ".." not in token, f"traversal in {token!r}"

# At least one negative assertion — a case that can only pass is not an eval.
assert any(a.get("expect_exit", 0) != 0 for a in grades), "case has no negative assertion"
PY
  then
    pass "T1: $name manifest is well formed and names only known grade tools"
  else
    fail "T1: $name manifest is malformed"
  fi
done

# ───────────────────────────────────────────────────────────
# T2: every recorded cassette call replays through the shim
# ───────────────────────────────────────────────────────────
for case_dir in "${CASES[@]}"; do
  name="$(basename "$(dirname "$case_dir")")/$(basename "$case_dir")"
  if EVAL_CASSETTES="$case_dir/cassettes.json" "$PYTHON_BIN" - "$case_dir" "$SHIM" <<'PY'
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

case_dir = Path(sys.argv[1])
shim = sys.argv[2]
cassettes = json.loads((case_dir / "cassettes.json").read_text(encoding="utf-8"))

assert cassettes.get("version") == 1, "cassette version must be 1"
calls = cassettes.get("calls")
assert isinstance(calls, list) and calls, "cassettes.calls must be a non-empty list"

spec = importlib.util.spec_from_file_location("gh_shim", shim)
gh_shim = importlib.util.module_from_spec(spec)
# Register before exec: the shim defines dataclasses, and @dataclass resolves
# annotations through sys.modules[cls.__module__].
sys.modules["gh_shim"] = gh_shim
spec.loader.exec_module(gh_shim)

seen = set()
for call in calls:
    argv = call.get("argv")
    assert isinstance(argv, list) and argv, "each call needs a non-empty argv"
    assert call.get("exit", 0) == 0, "fixture cassettes record successful calls only"
    key = (call.get("match", "exact"), tuple(argv))
    assert key not in seen, f"duplicate cassette entry {argv!r}"
    seen.add(key)
    # A data-producing call without --json is rejected by the shim at runtime.
    if gh_shim._requires_json(argv):
        assert gh_shim._has_json_flag(argv), f"{argv!r} must carry --json"
    if call.get("match") == "prefix":
        continue  # a prefix entry is replayed via the call that extends it
    proc = subprocess.run(
        [sys.executable, shim, *argv],
        capture_output=True,
        text=True,
        env={**os.environ, "EVAL_CASSETTES": str(case_dir / "cassettes.json")},
    )
    assert proc.returncode == 0, f"replay of {argv!r} exited {proc.returncode}: {proc.stderr}"
    assert proc.stdout == call.get("stdout", ""), f"replay of {argv!r} returned other stdout"
    if "--json" in argv:
        json.loads(proc.stdout)  # recorded payloads must be parseable JSON
PY
  then
    pass "T2: $name cassettes replay through the shim byte-for-byte"
  else
    fail "T2: $name cassettes do not replay cleanly"
  fi
done

# ───────────────────────────────────────────────────────────
# T3: subjects follow the hermetic-subject contract
# ───────────────────────────────────────────────────────────
for case_dir in "${CASES[@]}"; do
  name="$(basename "$(dirname "$case_dir")")/$(basename "$case_dir")"
  subject="$case_dir/subject.sh"
  errors=""
  head -1 "$subject" | grep -q '^#!/usr/bin/env bash$' || errors="$errors shebang"
  grep -q '^set -euo pipefail$' "$subject" || errors="$errors set-euo-pipefail"
  grep -q '"${EVAL_OUT:?EVAL_OUT is required}"' "$subject" || errors="$errors eval-out-guard"
  bash -n "$subject" 2>/dev/null || errors="$errors syntax"
  # Hermeticity: no network reach, no record mode, no path back into the checkout.
  grep -qE '\b(curl|wget|nc|ssh|pip|npm)\b' "$subject" && errors="$errors network-tool"
  grep -q 'EVAL_RECORD' "$subject" && errors="$errors record-mode"
  grep -qE '(REPO_ROOT|\.\./\.\./|src/shared/scripts)' "$subject" && errors="$errors checkout-reach"
  if [ -z "$errors" ]; then
    pass "T3: $name subject is hermetic and follows the subject contract"
  else
    fail "T3: $name subject violates:$errors"
  fi
done

# ───────────────────────────────────────────────────────────
# T4: expected answers agree with the repo's own deterministic tools
# ───────────────────────────────────────────────────────────
if "$PYTHON_BIN" - "$TRIAGE_CASE" "$REPO_ROOT" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

case_dir = Path(sys.argv[1])
repo_root = Path(sys.argv[2])

case = json.loads((case_dir / "case.json").read_text(encoding="utf-8"))
cassettes = json.loads((case_dir / "cassettes.json").read_text(encoding="utf-8"))

# The order the case asserts, read back off its rank-<r>-issue-<n> artifacts.
expected = []
for assertion in case["grade"]:
    token = assertion.get("file") or ""
    name = token.rsplit("/", 1)[-1]
    if name.startswith("rank-"):
        rank, number = name[len("rank-"):-len(".txt")].split("-issue-")
        expected.append((int(rank), int(number)))
expected = [number for _, number in sorted(expected)]
assert expected, "case asserts no ranks"
assert [r for r, _ in sorted(zip(range(1, len(expected) + 1), expected))] == list(
    range(1, len(expected) + 1)
), "ranks must be contiguous from 1"

# Rebuild the scanned graph the subject derives from the same cassette.
issues, prs = None, None
for call in cassettes["calls"]:
    if call["argv"][:2] == ["issue", "list"]:
        issues = json.loads(call["stdout"])
    elif call["argv"][:2] == ["pr", "list"]:
        prs = json.loads(call["stdout"])
assert issues and prs is not None, "cassette must record an issue list and a pr list"

import re

fixed_by = {}
for pr in prs:
    for ref in re.findall(r"(?im)\bcloses\s+#(\d+)", pr["body"]):
        fixed_by.setdefault(int(ref), f"PR #{pr['number']}")

scan = {"issues": [], "edges": []}
for entry in issues:
    labels = [label["name"] for label in entry["labels"]]
    scan["issues"].append(
        {
            "number": entry["number"],
            "title": entry["title"],
            "type": next((lab for lab in labels if lab in ("bug", "feature", "improvement")), None),
            "labels": labels,
            "createdAt": entry["createdAt"],
            "updatedAt": entry["updatedAt"],
            "affected_files": [],
            "potentially_fixed_by": fixed_by.get(entry["number"]),
        }
    )
    for ref in re.findall(r"(?im)^(?:depends on|blocked by)[^\n]*?#(\d+)", entry["body"]):
        scan["edges"].append({"from": int(ref), "to": entry["number"]})

proc = subprocess.run(
    [
        sys.executable,
        str(repo_root / "src" / "shared" / "scripts" / "gi-triage-graph.py"),
        "--source", "/issue-triage",
        "--now", "2026-08-24T12:00:00Z",
        "--no-config",
        "--stale-days", "14",
    ],
    input=json.dumps(scan),
    capture_output=True,
    text=True,
)
assert proc.returncode == 0, f"gi-triage-graph exited {proc.returncode}: {proc.stderr}"
actual = json.loads(proc.stdout)["summary"]["suggested_order"]
assert actual == expected, f"case expects {expected}, gi-triage-graph computes {actual}"
PY
then
  pass "T4a: the expected triage order is what gi-triage-graph.py computes"
else
  fail "T4a: the expected triage order disagrees with gi-triage-graph.py"
fi

if "$PYTHON_BIN" - "$AUTOPILOT_CASE" "$REPO_ROOT" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

case_dir = Path(sys.argv[1])
repo_root = Path(sys.argv[2])
deps_script = repo_root / "src" / "shared" / "scripts" / "gi-deps.py"

cassettes = json.loads((case_dir / "cassettes.json").read_text(encoding="utf-8"))
bodies = {}
for call in cassettes["calls"]:
    if call["argv"][:2] != ["issue", "view"]:
        continue
    payload = json.loads(call["stdout"])
    if "body" in payload:
        bodies[payload["number"]] = payload["body"]

# The subject gates #50 on #12 and #51 on #40 only (the cross-repo ref in #51
# must be ignored). gi-deps.py is the repo's own parser for that grammar.
expected = {50: ["12"], 51: ["40"]}
for number, want in expected.items():
    proc = subprocess.run(
        [sys.executable, str(deps_script)],
        input=bodies[number],
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, f"gi-deps exited {proc.returncode}: {proc.stderr}"
    got = proc.stdout.split()
    assert got == want, f"issue #{number}: gi-deps says {got}, the case gates on {want}"

# The gate table must reach every outcome the run-log vocabulary allows here.
case = json.loads((case_dir / "case.json").read_text(encoding="utf-8"))
decisions = set()
for assertion in case["grade"]:
    name = (assertion.get("file") or "").rsplit("/", 1)[-1]
    if name.startswith("gate-"):
        decisions.add(name[:-len(".txt")].rsplit("-", 1)[-1])
for outcome in ("merged", "left_open", "partial_followup", "blocked_by_dependency", "stop"):
    assert outcome in decisions, f"gate table never reaches {outcome}"
PY
then
  pass "T4b: the expected dependency gate is what gi-deps.py parses"
else
  fail "T4b: the expected dependency gate disagrees with gi-deps.py"
fi

# ───────────────────────────────────────────────────────────
# T5: subject + grade run end to end (no OS network sandbox)
#
# This is the same subject-then-grade path run_eval.sh drives, minus its
# sandbox. run_eval.sh is untouched and still refuses to run unsandboxed; this
# replay exists so the two cases stay covered on a host without namespaces.
# It is not a substitute for T6 — only T6 proves the isolated run.
# ───────────────────────────────────────────────────────────
replay_case() {
  local case_dir="$1" work="$2"
  local bin="$work/bin" out="$work/out"
  mkdir -p "$bin" "$out" "$work/state" "$work/repo" "$work/home" "$work/case"
  cp -R "$case_dir"/. "$work/case"/
  {
    echo '#!/usr/bin/env bash'
    echo "exec \"$PYTHON_BIN\" \"$SHIM\" \"\$@\""
  } > "$bin/gh"
  {
    echo '#!/usr/bin/env bash'
    echo "exec \"$PYTHON_BIN\" \"\$@\""
  } > "$bin/python3"
  chmod 755 "$bin/gh" "$bin/python3"
  # Cassette input lives under $work, as run_eval.sh arranges it, so a subject
  # can never write back into the checkout.
  cp "$case_dir/cassettes.json" "$work/cassettes.json"
  ( cd "$work/repo" && env -i \
      HOME="$work/home" \
      PATH="$bin:/usr/bin:/bin" \
      EVAL_CASSETTES="$work/cassettes.json" \
      EVAL_STATE_DIR="$work/state" \
      EVAL_OUT="$out" \
      EVAL_CASE_DIR="$work/case" \
      EVAL_WORK="$work" \
      bash "$work/case/subject.sh" ) >"$work/subject.log" 2>&1 || return 1
  REPO_ROOT="$REPO_ROOT" "$PYTHON_BIN" "$GRADE" \
    --case "$case_dir" --out "$out" >"$work/grade.log" 2>&1
}

for case_dir in "${CASES[@]}"; do
  name="$(basename "$(dirname "$case_dir")")/$(basename "$case_dir")"
  work="$TMP/replay-$(basename "$(dirname "$case_dir")")-$(basename "$case_dir")"
  if replay_case "$case_dir" "$work"; then
    pass "T5: $name — subject artifacts satisfy every grade assertion"
  else
    fail "T5: $name — subject or grade failed"
    # One sed per log: GNU sed without -s treats several files as one stream,
    # which would truncate grade.log away whenever subject.log is long.
    for log in subject grade; do
      [ -s "$work/$log.log" ] || continue
      echo "      ── $log.log ──"
      sed -n '1,25p' "$work/$log.log" | sed 's/^/      /'
    done
  fi
done

# ───────────────────────────────────────────────────────────
# T6: run_eval.sh, sandboxed — the authoritative run
# ───────────────────────────────────────────────────────────
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

# No root special case on purpose: run_eval.sh refuses to run a subject as
# root and says so itself, which is a more accurate message than a skip line
# claiming the host cannot sandbox.
if sandbox_available; then
  can_sandbox=0
else
  can_sandbox=1
fi

for case_dir in "${CASES[@]}"; do
  name="$(basename "$(dirname "$case_dir")")/$(basename "$case_dir")"
  if [ "$can_sandbox" -ne 0 ]; then
    if [ "${IDD_EVAL_REQUIRE_SANDBOX:-}" = "1" ]; then
      fail "T6: $name — no OS network sandbox and IDD_EVAL_REQUIRE_SANDBOX=1"
    else
      skip "T6: $name — no OS network sandbox on this host; run_eval.sh not run"
    fi
    continue
  fi
  if bash "$RUN" "$case_dir" >"$TMP/run.log" 2>&1; then
    pass "T6: $name — run_eval.sh passed (sandboxed)"
  else
    fail "T6: $name — run_eval.sh failed"
    sed -n '1,25p' "$TMP/run.log" | sed 's/^/      /'
  fi
done

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ triage/auto-pilot eval cases failed"
  exit 1
fi

if [ "$SKIP" -gt 0 ]; then
  echo "  ⚠ $SKIP sandboxed run(s) skipped — structural coverage only"
fi

echo "  ✓ triage ordering and auto-pilot gating cases behave as specified (#357)"
exit 0
