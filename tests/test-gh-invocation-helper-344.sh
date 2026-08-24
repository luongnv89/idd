#!/usr/bin/env bash
# test-gh-invocation-helper-344.sh — shared GitHub CLI subprocess boundary (#344).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$ROOT/src/shared/scripts"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "◆ GitHub invocation helper (issue #344)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

python3 - "$ROOT" >"$TMP/results" <<'PY'
import importlib.util
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

root = Path(sys.argv[1])
scripts = root / "src" / "shared" / "scripts"


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


modules = {
    "gi-issue": load("gi_issue_344", scripts / "gi-issue.py"),
    "gi-branch": load("gi_branch_344", scripts / "gi-branch.py"),
    "gi-dup-score": load("gi_dup_score_344", scripts / "gi-dup-score.py"),
    "gi-ci-wait": load("gi_ci_wait_344", scripts / "gi-ci-wait.py"),
}


def invoke(name: str):
    module = modules[name]
    if name == "gi-issue":
        return module.fetch(344, ["number"], None)
    if name == "gi-branch":
        return module.fetch_issue(344, None)
    if name == "gi-dup-score":
        return module._gh_issue_list(1, None, "number")
    return module.poll_once("344", None)


def result(returncode=0, stdout="", stderr=""):
    return subprocess.CompletedProcess([], returncode, stdout, stderr)


def emit(ok: bool, label: str):
    print(("PASS" if ok else "FAIL") + "|" + label)


# Structural guard: the process-start block has exactly one implementation.
consumer_text = {
    name: (scripts / f"{name}.py").read_text(encoding="utf-8") for name in modules
}
helper_text = (scripts / "gi-gh.py").read_text(encoding="utf-8")
emit(
    all('_RUN_GH(' in text for text in consumer_text.values())
    and all('subprocess.run(\n            ["gh"' not in text for text in consumer_text.values())
    and helper_text.count("subprocess.run(") == 1,
    "T1: all four consumers use the one gi-gh subprocess implementation",
)

# The helper owns identical process-start failure translation for every caller.
for label, effect, expected in (
    ("missing gh", FileNotFoundError(), "gh is not installed or not on PATH"),
    ("OS error", OSError("denied"), "cannot run gh — denied"),
):
    seen = []
    with patch.object(subprocess, "run", side_effect=effect):
        for name in modules:
            try:
                invoke(name)
            except modules[name].Unavailable as exc:
                seen.append(str(exc))
            else:
                seen.append("NO ERROR")
    emit(
        seen == [expected] * len(modules),
        f"T2: {label} maps to the same unavailable contract in all four scripts",
    )

# Successful calls remain shell-free, capture text, and preserve each parser's
# command-specific result after the shared boundary returns.
calls = []


def fake_success(command, **kwargs):
    calls.append((command, kwargs))
    if command[1:3] == ["issue", "view"]:
        return result(stdout='{"number":344,"title":"Title","labels":[]}')
    if command[1:3] == ["issue", "list"]:
        return result(stdout='[{"number":1}]')
    if command[1:3] == ["pr", "checks"]:
        return result(stdout='[{"name":"ci","state":"SUCCESS","bucket":"pass","link":""}]')
    raise AssertionError(command)


with patch.object(subprocess, "run", side_effect=fake_success):
    values = {name: invoke(name) for name in modules}
emit(
    values["gi-issue"]["number"] == 344
    and values["gi-branch"] == ("Title", [])
    and values["gi-dup-score"] == [{"number": 1}]
    and values["gi-ci-wait"][0]["bucket"] == "pass",
    "T3: all four command-specific parsers receive successful helper output",
)
emit(
    len(calls) == 4
    and all(call[0][0] == "gh" for call in calls)
    and all(
        kwargs == {"capture_output": True, "text": True, "check": False}
        for _, kwargs in calls
    ),
    "T3.1: helper invokes gh without a shell and captures explicit text output",
)

# Non-zero exits and malformed payloads still degrade through each script's
# existing command-specific Unavailable path rather than escaping as tracebacks.
for label, fake in (
    ("non-zero gh exit", result(1, stderr="first line\nbackend down\n")),
    ("malformed JSON", result(stdout="not-json")),
):
    caught = []
    with patch.object(subprocess, "run", return_value=fake):
        for name in modules:
            try:
                invoke(name)
            except modules[name].Unavailable:
                caught.append(name)
    emit(
        caught == list(modules),
        f"T4: {label} remains an unavailable result in all four scripts",
    )

# Every installed consumer must carry its sibling helper. This proves the
# existing closure mechanism bundles the import dependency, not only the source.
missing = []
for skill_dir in sorted((root / "skills").iterdir()):
    installed = skill_dir / "references" / "scripts"
    if not installed.is_dir():
        continue
    if any((installed / f"{name}.py").is_file() for name in modules):
        helper_copy = installed / "gi-gh.py"
        if not helper_copy.is_file() or helper_copy.read_bytes() != (scripts / "gi-gh.py").read_bytes():
            missing.append(skill_dir.name)
emit(
    not missing,
    "T5: every skill bundling a consumer carries a byte-identical gi-gh.py",
)
PY

while IFS='|' read -r status label; do
  if [ "$status" = PASS ]; then pass "$label"; else fail "$label"; fi
done <"$TMP/results"

echo "  Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
