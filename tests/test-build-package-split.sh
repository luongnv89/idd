#!/usr/bin/env bash
# test-build-package-split.sh — focused contract checks for issue #347.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0

pass() { printf '  ✓ %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  ✗ %s\n' "$1"; FAIL=$((FAIL + 1)); }

printf '◆ Build Package Split Tests (issue #347)\n'
printf '┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n'

required=(
  __init__.py __main__.py agents.py cli.py closure.py common.py
  doc_slimming.py emit.py inventory.py pipeline.py rewriting.py
  validation.py yaml_config.py
)
missing=0
for name in "${required[@]}"; do
  if [ ! -f "$REPO_ROOT/scripts/build/$name" ]; then
    fail "package module missing: scripts/build/$name"
    missing=1
  fi
done
if [ "$missing" -eq 0 ]; then
  pass "phase-oriented scripts/build/ package is complete"
fi

if PYTHONDONTWRITEBYTECODE=1 python3 - "$REPO_ROOT" >"$TMP/structure" <<'PY'
import ast
import importlib
import importlib.util
import sys
import types
from pathlib import Path

root = Path(sys.argv[1])
pipeline = ast.parse((root / "scripts/build/pipeline.py").read_text(encoding="utf-8"))
closure = ast.parse((root / "scripts/build/closure.py").read_text(encoding="utf-8"))

build = next(
    node for node in pipeline.body
    if isinstance(node, ast.FunctionDef) and node.name == "build"
)
assert build.end_lineno - build.lineno + 1 <= 50, "build() exceeds 50 lines"

compute = next(
    node for node in closure.body
    if isinstance(node, ast.FunctionDef) and node.name == "_compute_closure"
)
assert not any(
    isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    for node in ast.walk(compute)
    if node is not compute
), "_compute_closure still contains a recursive inner function"
walker = next(
    node for node in closure.body
    if isinstance(node, ast.ClassDef) and node.name == "ClosureWalker"
)
visit = next(
    node for node in walker.body
    if isinstance(node, ast.FunctionDef) and node.name == "visit"
)
assert [arg.arg for arg in visit.args.args] == [
    "self", "kind", "name", "path_chain", "bundle"
], "closure walker inputs are not explicit"

# A third-party top-level `build` module must not hijack the compatibility shim.
sys.modules["build"] = types.ModuleType("build")
sys.modules["build"].foreign = True
spec = importlib.util.spec_from_file_location(
    "idd_build_package_contract", root / "scripts/build.py"
)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
assert callable(module.build)
assert callable(module._parse_config_mapping)
assert module._FULL_SCHEMA_FENCE_RE.pattern
package = importlib.import_module("scripts.build")
for polluted in ("_module", "_name", "_value", "dataclass", "field", "Path"):
    assert not hasattr(package, polluted), f"compatibility facade leaked {polluted}"
PY
then
  pass "build() is short, closure traversal is explicit, and legacy imports work"
else
  fail "package structure or legacy import contract failed"
  cat "$TMP/structure"
fi

if PYTHONDONTWRITEBYTECODE=1 python3 "$REPO_ROOT/scripts/build.py" \
    --src "$REPO_ROOT/src" --out "$TMP/direct" --no-root-skills >/dev/null 2>&1; then
  pass "scripts/build.py compatibility entry point builds a custom output"
else
  fail "scripts/build.py compatibility entry point failed"
fi

if (
  cd "$REPO_ROOT"
  PYTHONDONTWRITEBYTECODE=1 python3 -m scripts.build \
    --out "$TMP/module" --no-root-skills >/dev/null 2>&1
); then
  pass "python -m scripts.build uses the same package entry point"
else
  fail "python -m scripts.build failed"
fi

if [ -d "$TMP/direct/skills" ] && [ -d "$TMP/module/skills" ] && \
   diff -r --brief "$TMP/direct" "$TMP/module" >/dev/null; then
  pass "direct and package invocations emit byte-identical trees"
else
  fail "direct and package invocation outputs differ"
fi

printf '┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n'
printf '  Passed: %s\n  Failed: %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
