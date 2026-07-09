#!/usr/bin/env bash
# Regression coverage for issue #213: init template/schema parity is a build gate.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

run_python_check() {
  REPO_ROOT="$REPO_ROOT" python3 - <<'PY'
import importlib.util
import os
import shutil
import tempfile
from pathlib import Path

root = Path(os.environ["REPO_ROOT"])
spec = importlib.util.spec_from_file_location("idd_build", root / "scripts" / "build.py")
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

# The checked-in documentation and source template must pass the same validator
# that build() invokes before emitting any output.
module._check_init_template_schema_parity(root / "src")

# A copied source tree with one changed default must be rejected. This proves the
# gate compares parsed keys/defaults rather than merely grepping for prose.
with tempfile.TemporaryDirectory() as temporary:
    fixture = Path(temporary)
    (fixture / "src" / "skills" / "init-gitissue" / "templates").mkdir(parents=True)
    (fixture / "docs").mkdir()
    schema = fixture / "docs" / "config-schema.md"
    template = fixture / "src" / "skills" / "init-gitissue" / "templates" / "gitissue-template.yml"
    shutil.copyfile(root / "docs" / "config-schema.md", schema)
    template_text = (root / "src" / "skills" / "init-gitissue" / "templates" / "gitissue-template.yml").read_text(encoding="utf-8")
    template.write_text(template_text.replace("  max_commits: 10", "  max_commits: 11", 1), encoding="utf-8")
    try:
        module._check_init_template_schema_parity(fixture / "src")
    except module.BuildError:
        pass
    else:
        raise AssertionError("divergent init template was accepted")

# Self-contained synthetic source fixtures without either parity input must
# remain buildable, while a partial init contract must still fail clearly.
with tempfile.TemporaryDirectory() as temporary:
    fixture = Path(temporary)
    source = fixture / "src"
    module._check_init_template_schema_parity(source)

    schema = fixture / "docs" / "config-schema.md"
    schema.parent.mkdir(parents=True)
    schema.write_text("# Schema\n", encoding="utf-8")
    expected_template = source / "skills" / "init-gitissue" / "templates" / "gitissue-template.yml"
    try:
        module._check_init_template_schema_parity(source)
    except module.BuildError as exc:
        assert "both inputs or neither" in str(exc)
        assert str(expected_template) in str(exc)
    else:
        raise AssertionError("schema-only parity input was accepted")

    schema.unlink()
    template = expected_template
    template.parent.mkdir(parents=True)
    template.write_text("# Template\n", encoding="utf-8")
    try:
        module._check_init_template_schema_parity(source)
    except module.BuildError as exc:
        assert "both inputs or neither" in str(exc)
        assert str(schema) in str(exc)
    else:
        raise AssertionError("template-only parity input was accepted")
PY
}

TMP_OUT="$(mktemp -d)"
trap 'rm -rf "$TMP_OUT"' EXIT

echo "◆ Init Template Schema Parity Tests (issue #213)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

if run_python_check; then
  pass "T1: build validator accepts current schema/template and rejects a divergent default"
else
  fail "T1: build validator did not enforce schema/template parity"
fi

if "$REPO_ROOT/scripts/build.sh" --out "$TMP_OUT" --quiet; then
  pass "T2: build.sh runs the parity validator"
else
  fail "T2: build.sh parity validation failed for current inputs"
fi

echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"

[ "$FAIL" -eq 0 ]
