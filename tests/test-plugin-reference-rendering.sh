#!/usr/bin/env bash
# test-plugin-reference-rendering.sh — Verify dist/plugin/ uses the
# §6.0 ADR-decided rendering (issue #58, §9 of refactor-plan-v10.md).
#
# Hardcoded ADR row: (A-fail, B-fail, C-1) per
# docs/decisions/cross-skill-invocation.md (2026-04-28). When the ADR is
# revised, update this test alongside scripts/build.py.
#
# Expected forms in dist/plugin/skills/<name>/**:
#   Cross-skill calls:    ../../<name>/SKILL.md
#   Shared agents:        ../../../shared/agents/<file>.md
#   Runtime docs:         ../../../docs/<file>.md
#
# Forbidden in dist/plugin/skills/<name>/**:
#   - Bare local references: shared/agents/X.md, docs/Y.md (must be rewritten)
#   - ${CLAUDE_PLUGIN_ROOT}/... — that form belongs to the B-1 row, not B-fail
#   - /<plugin-slug>:<name> — that form belongs to the A-1 row, not A-fail
#   - Any unresolved {{skill:...}} token
#
# "Same reference type, two forms" rule: if any single reference type appears
# in two distinct rendered forms anywhere in dist/plugin/, fail. Cross-type
# mixing within a single file is permitted (per §4 Phase E).
#
# Usage: bash tests/test-plugin-reference-rendering.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_PLUGIN="$REPO_ROOT/dist/plugin"
BUILD_SH="$REPO_ROOT/scripts/build.sh"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Plugin Reference Rendering Tests (issue #58)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# Build if dist/plugin/ is missing
if [ ! -d "$DIST_PLUGIN" ]; then
  echo "  ○ dist/plugin/ missing — running build..."
  "$BUILD_SH" >/dev/null 2>&1 || {
    fail "Pre-build failed — cannot scan plugin tree"
    exit 1
  }
fi

PLUGIN_SKILLS="$DIST_PLUGIN/skills"

# ───────────────────────────────────────────────────────────
# T1: forbidden — bare local references
# ───────────────────────────────────────────────────────────
if python3 - "$PLUGIN_SKILLS" <<'PY'
import re
import sys
from pathlib import Path

base = Path(sys.argv[1])
URL_RE = re.compile(r"https?://\S+")
SHARED_AGENT_RE = re.compile(r"(?<![\w/])shared/agents/([a-z][a-z0-9-]+\.md)")
RUNTIME_DOC_RE = re.compile(r"(?<![\w/])docs/([a-z][a-z0-9-]+\.md)")
PLUGIN_ROOT_RE = re.compile(r"\$\{CLAUDE_PLUGIN_ROOT\}")
SLASH_PLUGIN_RE = re.compile(r"/[a-z][a-z0-9-]*:[a-z][a-z0-9-]+")
SKILL_TOKEN_RE = re.compile(r"\{\{skill:[a-z][a-z0-9-]+\}\}")

EXTS = {".md", ".txt", ".yml", ".yaml", ".json", ".toml"}

bare_shared = []
bare_doc = []
plugin_root_hits = []
slash_plugin_hits = []
unresolved_tokens = []

for f in sorted(base.rglob("*")):
    if not f.is_file() or f.suffix not in EXTS:
        continue
    text = f.read_text(encoding="utf-8", errors="replace")
    masked = URL_RE.sub(lambda m: " " * len(m.group(0)), text)
    rel = f.relative_to(base)
    for m in SHARED_AGENT_RE.finditer(masked):
        line_no = masked[: m.start()].count("\n") + 1
        bare_shared.append(f"{rel}:{line_no}: shared/agents/{m.group(1)}")
    for m in RUNTIME_DOC_RE.finditer(masked):
        line_no = masked[: m.start()].count("\n") + 1
        bare_doc.append(f"{rel}:{line_no}: docs/{m.group(1)}")
    for m in PLUGIN_ROOT_RE.finditer(masked):
        line_no = masked[: m.start()].count("\n") + 1
        plugin_root_hits.append(f"{rel}:{line_no}: ${{CLAUDE_PLUGIN_ROOT}}")
    for m in SLASH_PLUGIN_RE.finditer(masked):
        line_no = masked[: m.start()].count("\n") + 1
        slash_plugin_hits.append(f"{rel}:{line_no}: {m.group(0)}")
    for m in SKILL_TOKEN_RE.finditer(masked):
        line_no = masked[: m.start()].count("\n") + 1
        unresolved_tokens.append(f"{rel}:{line_no}: {m.group(0)}")

failed = False
if bare_shared:
    print("FAIL: bare 'shared/agents/...' references found in plugin tree")
    for h in bare_shared[:20]:
        print(f"  {h}")
    failed = True
if bare_doc:
    print("FAIL: bare 'docs/...' references found in plugin tree")
    for h in bare_doc[:20]:
        print(f"  {h}")
    failed = True
if plugin_root_hits:
    print("FAIL: ${CLAUDE_PLUGIN_ROOT} found (B-fail row in use, must use ../../../...):")
    for h in plugin_root_hits[:20]:
        print(f"  {h}")
    failed = True
if slash_plugin_hits:
    print("FAIL: '/<plugin-slug>:<name>' found (A-fail row in use, must use ../../<name>/SKILL.md):")
    for h in slash_plugin_hits[:20]:
        print(f"  {h}")
    failed = True
if unresolved_tokens:
    print("FAIL: unresolved {{skill:...}} tokens in plugin tree:")
    for h in unresolved_tokens[:20]:
        print(f"  {h}")
    failed = True

sys.exit(1 if failed else 0)
PY
then
  pass "T1: no forbidden reference forms in dist/plugin/skills/"
else
  fail "T1: forbidden reference forms detected"
fi

# ───────────────────────────────────────────────────────────
# T2: expected ADR forms are present
# ───────────────────────────────────────────────────────────
# We assert that each public skill in the plugin tree contains references
# in the expected ADR forms whenever the source uses tokens. The strongest
# check is to scan a known consumer (auto-pilot) for the rendered form.
AUTOPILOT_PLUGIN_DIR="$PLUGIN_SKILLS/auto-pilot"
if [ -d "$AUTOPILOT_PLUGIN_DIR" ]; then
  if grep -rqE '\.\./\.\./issue-resolver/SKILL\.md' "$AUTOPILOT_PLUGIN_DIR"; then
    pass "T2.1: auto-pilot uses '../../<name>/SKILL.md' (A-fail rendering)"
  else
    fail "T2.1: auto-pilot missing expected '../../<name>/SKILL.md' rendering"
  fi
  if grep -rqE '\.\./\.\./\.\./docs/[a-z-]+\.md' "$AUTOPILOT_PLUGIN_DIR"; then
    pass "T2.2: auto-pilot uses '../../../docs/...' (C-1 rendering for runtime docs)"
  else
    pass "T2.2: auto-pilot has no runtime doc references — skipped (vacuously OK)"
  fi
fi

# Issue-resolver references shared agents — verify ADR-rendered form
RESOLVER_PLUGIN_DIR="$PLUGIN_SKILLS/issue-resolver"
if [ -d "$RESOLVER_PLUGIN_DIR" ]; then
  if grep -rqE '\.\./\.\./\.\./shared/agents/[a-z-]+\.md' "$RESOLVER_PLUGIN_DIR"; then
    pass "T2.3: issue-resolver uses '../../../shared/agents/...' (C-1 rendering for shared agents)"
  else
    fail "T2.3: issue-resolver missing expected '../../../shared/agents/...' rendering"
  fi
fi

# ───────────────────────────────────────────────────────────
# T3: same reference type does not appear in two forms across plugin tree
# ───────────────────────────────────────────────────────────
if python3 - "$PLUGIN_SKILLS" <<'PY'
import re
import sys
from pathlib import Path

base = Path(sys.argv[1])
URL_RE = re.compile(r"https?://\S+")
EXTS = {".md", ".txt", ".yml", ".yaml", ".json", ".toml"}

forms = {
    "cross_skill": set(),
    "shared_agent": set(),
    "runtime_doc": set(),
}

# Patterns per reference type. Each type has a set of "form keys" — if a type
# has more than one form key across the entire tree, fail.

for f in sorted(base.rglob("*")):
    if not f.is_file() or f.suffix not in EXTS:
        continue
    text = f.read_text(encoding="utf-8", errors="replace")
    masked = URL_RE.sub(lambda m: " " * len(m.group(0)), text)

    # Cross-skill forms
    if re.search(r"\.\./\.\./[a-z][a-z0-9-]*/SKILL\.md", masked):
        forms["cross_skill"].add("../../<name>/SKILL.md")
    if re.search(r"\$\{CLAUDE_PLUGIN_ROOT\}/skills/[a-z][a-z0-9-]*/SKILL\.md", masked):
        forms["cross_skill"].add("${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md")
    if re.search(r"(?<![\w])/[a-z][a-z0-9-]*:[a-z][a-z0-9-]+", masked):
        forms["cross_skill"].add("/<plugin-slug>:<name>")

    # Shared-agent forms
    if re.search(r"\.\./\.\./\.\./shared/agents/[a-z][a-z0-9-]+\.md", masked):
        forms["shared_agent"].add("../../../shared/agents/<file>.md")
    if re.search(r"\$\{CLAUDE_PLUGIN_ROOT\}/shared/agents/[a-z][a-z0-9-]+\.md", masked):
        forms["shared_agent"].add("${CLAUDE_PLUGIN_ROOT}/shared/agents/<file>.md")

    # Runtime-doc forms
    if re.search(r"\.\./\.\./\.\./docs/[a-z][a-z0-9-]+\.md", masked):
        forms["runtime_doc"].add("../../../docs/<file>.md")
    if re.search(r"\$\{CLAUDE_PLUGIN_ROOT\}/docs/[a-z][a-z0-9-]+\.md", masked):
        forms["runtime_doc"].add("${CLAUDE_PLUGIN_ROOT}/docs/<file>.md")

failed = False
for ref_type, found in forms.items():
    if len(found) > 1:
        print(f"FAIL: reference type '{ref_type}' appears in two forms: {sorted(found)}")
        failed = True

sys.exit(1 if failed else 0)
PY
then
  pass "T3: no reference type appears in two forms within dist/plugin/"
else
  fail "T3: at least one reference type appears in two forms"
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Plugin reference rendering tests failed"
  exit 1
fi

echo "  ✓ Plugin reference rendering matches ADR row (A-fail, B-fail, C-1)"
exit 0
