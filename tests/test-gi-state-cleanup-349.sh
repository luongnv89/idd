#!/usr/bin/env bash
# test-gi-state-cleanup-349.sh — structural and behavioral regression coverage
# for the gi-state lock/normalizer decomposition from issue #349.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$REPO_ROOT/src/shared/scripts/gi-state.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "◆ gi-state cleanup (issue #349)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

python3 - "$STATE" <<'PY'
import ast
import importlib.util
import inspect
import sys
from enum import Enum

path = sys.argv[1]
source = open(path, encoding="utf-8").read()
tree = ast.parse(source)
functions = {
    node.name: node
    for node in tree.body
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
}

required = {
    "_run_lock_locked",
    "_try_reacquire",
    "_try_reclaim",
    "_acquire_fresh",
    "_normalize_record_fields",
}
missing = sorted(required - functions.keys())
assert not missing, f"missing decomposition helpers: {missing}"

dispatcher = functions["_run_lock_locked"]
assert dispatcher.end_lineno - dispatcher.lineno + 1 <= 30, "lock dispatcher exceeds 30 lines"

controls = (ast.If, ast.For, ast.AsyncFor, ast.While, ast.Try, ast.With, ast.AsyncWith)
if hasattr(ast, "Match"):
    controls += (ast.Match,)

def max_control_depth(root):
    maximum = 0
    def visit(node, depth):
        nonlocal maximum
        if node is not root and isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda)):
            return
        next_depth = depth + 1 if isinstance(node, controls) else depth
        maximum = max(maximum, next_depth)
        for child in ast.iter_child_nodes(node):
            visit(child, next_depth)
    visit(root, 0)
    return maximum

for name in ("_try_reacquire", "_try_reclaim", "_acquire_fresh"):
    depth = max_control_depth(functions[name])
    assert depth <= 2, f"{name} nesting depth is {depth}, expected <= 2"

for name in ("_normalize_lane", "_normalize_lanes", "_touch_lock_heartbeat"):
    node = functions[name]
    params = node.args.posonlyargs + node.args.args + node.args.kwonlyargs
    assert all(not (isinstance(arg.annotation, ast.Name) and arg.annotation.id == "bool") for arg in params), (
        f"{name} still has a boolean flag annotation"
    )
    defaults = list(node.args.defaults) + [d for d in node.args.kw_defaults if d is not None]
    assert all(not (isinstance(default, ast.Constant) and isinstance(default.value, bool)) for default in defaults), (
        f"{name} still has a boolean flag default"
    )

def called_names(name):
    return {
        call.func.id
        for call in ast.walk(functions[name])
        if isinstance(call, ast.Call) and isinstance(call.func, ast.Name)
    }

for name in ("_normalize_current", "_normalize_lane"):
    assert "_normalize_record_fields" in called_names(name), f"{name} bypasses shared record validation"

spec = importlib.util.spec_from_file_location("gi_state", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert issubclass(module.LaneNormalizationMode, Enum)
assert issubclass(module.HeartbeatLockMode, Enum)
assert inspect.signature(module._normalize_lane).parameters["mode"].default is module.LaneNormalizationMode.COMPLETE
assert inspect.signature(module._touch_lock_heartbeat).parameters["lock_mode"].default is module.HeartbeatLockMode.ACQUIRE_GUARD
assert module._normalize_current({}) == {
    "branch": None,
    "issue": None,
    "outcome": None,
    "phase": None,
    "pr": None,
    "started_at": None,
    "title": None,
}
try:
    module._normalize_lane({"issue": 1}, mode="patch")
except module.InputError:
    pass
else:
    raise AssertionError("invalid lane normalization mode was accepted")
try:
    module._touch_lock_heartbeat(None, "run", lock_mode="held")
except module.InputError:
    pass
else:
    raise AssertionError("invalid heartbeat lock mode was accepted")
print("  ✓ lock dispatcher, helper nesting, enums, and shared validators")
PY

python3 "$STATE" --lock --dir "$TMP" --run-id run349 --pid $$ >/dev/null
printf '%s' '{"mode":"balanced","queue":[349]}' \
  | python3 "$STATE" --init --dir "$TMP" >/dev/null
patch="$(python3 - <<'PY'
import json
print(json.dumps({
    "phase": "resolve",
    "current": {
        "issue": 349,
        "title": "x" * 600,
        "branch": "refactor/349-decompose-gi-state-lock-paths",
        "phase": "research",
    },
    "lanes": [{
        "issue": 349,
        "title": "y" * 600,
        "branch": "refactor/349-decompose-gi-state-lock-paths",
        "phase": "planned",
    }],
}))
PY
)"
state="$(printf '%s' "$patch" | python3 "$STATE" --update --dir "$TMP" --pid $$)"
printf '%s' "$state" | python3 -c '
import json, sys
state = json.load(sys.stdin)
assert state["current"]["phase"] == "research"
assert state["lanes"][0]["phase"] == "planned"
assert len(state["current"]["title"]) == 500
assert len(state["lanes"][0]["title"]) == 500
'
state="$(printf '%s' '{"lanes":[{"issue":349,"title":null}]}' \
  | python3 "$STATE" --update --dir "$TMP" --pid $$)"
printf '%s' "$state" | python3 -c '
import json, sys
lane = json.load(sys.stdin)["lanes"][0]
assert lane["title"] is None
assert lane["phase"] == "planned"
assert lane["branch"] == "refactor/349-decompose-gi-state-lock-paths"
'

resume="$(python3 "$STATE" --lock --resume --dir "$TMP" --run-id run349 --pid $$)"
printf '%s' "$resume" | python3 -c 'import json,sys; assert json.load(sys.stdin)["status"] == "reacquired"'
status=0
python3 "$STATE" --lock --dir "$TMP" --run-id other349 --pid $$ >/dev/null 2>&1 || status=$?
[ "$status" -eq 3 ]
python3 "$STATE" --unlock --dir "$TMP" --run-id run349 >/dev/null

echo "  ✓ normalizer round-trip and acquire/reacquire/refuse/unlock behavior"
echo "✓ gi-state cleanup checks passed"
