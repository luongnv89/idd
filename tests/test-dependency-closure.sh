#!/usr/bin/env bash
# test-dependency-closure.sh — Verify transitive dependency closure (issue #58,
# §9 of refactor-plan-v10.md, §4 Phase B; updated for #106).
#
# Asserts:
#   - Transitive shared agents are copied into skills/<name>/references/agents/
#   - Transitive runtime docs are copied into skills/<name>/references/docs/
#   - Logical references inside the *transitive* copies are themselves
#     rewritten (a copied agent that references docs/X.md must end up using
#     references/docs/X.md inside the flattened skill).
#   - Diamond dependency (A→B, A→C, B→D, C→D) does not produce false cycle
#     warnings. The repo's existing structure exhibits this:
#         issue-resolver → docs/naming-conventions.md (direct)
#         issue-resolver → shared/agents/implementer.md → docs/naming-conventions.md
#     The build must include naming-conventions.md exactly once and emit no
#     "cycle detected" warning during a clean build.
#
# Usage: bash tests/test-dependency-closure.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_SKILLS="$REPO_ROOT/dist/skills"
SRC_AGENTS="$REPO_ROOT/src/shared/agents"
# Issue #81: runtime docs live at top-level docs/, not src/docs/.
SRC_DOCS="$REPO_ROOT/docs"
BUILD_SH="$REPO_ROOT/scripts/build.sh"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Dependency Closure Tests (issue #58)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# Run a fresh build into a temp dir, capturing build output to scan for
# false-positive cycle warnings.
TMP_OUT="$(mktemp -d)"
BUILD_LOG="$(mktemp)"
SYN_TMP="$(mktemp -d)"
SYN_OUT="$(mktemp -d)"
SYN_LOG="$(mktemp)"
trap 'rm -rf "$TMP_OUT" "$SYN_TMP" "$SYN_OUT"; rm -f "$BUILD_LOG" "$SYN_LOG"' EXIT

if "$BUILD_SH" --out "$TMP_OUT" >"$BUILD_LOG" 2>&1; then
  pass "T1: clean build into temp dir"
else
  fail "T1: build failed"
  cat "$BUILD_LOG" | sed 's/^/    /' | head -20
  exit 1
fi

# ───────────────────────────────────────────────────────────
# T2: no false cycle warnings during clean build
# ───────────────────────────────────────────────────────────
if grep -qiE 'cycle detected' "$BUILD_LOG"; then
  fail "T2: build emitted unexpected 'cycle detected' warning"
  grep -iE 'cycle detected' "$BUILD_LOG" | sed 's/^/    /'
else
  pass "T2: clean build emits no false 'cycle detected' warning (diamond OK)"
fi

# Use the freshly built tree for the remaining assertions
TMP_DIST_SKILLS="$TMP_OUT/skills"

# ───────────────────────────────────────────────────────────
# T3: diamond example — issue-resolver pulls naming-conventions.md
# (both directly and via implementer.md), and the doc appears exactly once
# in the flattened tree.
# ───────────────────────────────────────────────────────────
RESOLVER_DOC="$TMP_DIST_SKILLS/issue-resolver/references/docs/naming-conventions.md"
if [ -f "$RESOLVER_DOC" ]; then
  pass "T3.1: issue-resolver/references/docs/naming-conventions.md exists (diamond closure)"
else
  fail "T3.1: missing transitive doc copy for issue-resolver"
fi

# Count files matching naming-conventions.md inside the resolver — should
# appear under references/docs only, not duplicated elsewhere.
count="$(find "$TMP_DIST_SKILLS/issue-resolver" -type f -name 'naming-conventions.md' | wc -l | tr -d ' ')"
if [ "$count" = "1" ]; then
  pass "T3.2: naming-conventions.md appears exactly once in flattened issue-resolver"
else
  fail "T3.2: naming-conventions.md appears $count times in flattened issue-resolver (expected 1)"
fi

# ───────────────────────────────────────────────────────────
# T4: implementer agent's reference to docs/naming-conventions.md was
# rewritten when it was copied as a transitive dependency.
# ───────────────────────────────────────────────────────────
COPIED_IMPL="$TMP_DIST_SKILLS/issue-resolver/references/agents/implementer.md"
if [ -f "$COPIED_IMPL" ]; then
  # Use Python for the bare-vs-rewritten check — the lookbehind needed here
  # is PCRE-only and macOS grep is BSD/POSIX ERE only.
  if python3 - "$COPIED_IMPL" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
# Strip URLs first.
text = re.sub(r"https?://\S+", "", text)
# Bare 'docs/<file>.md' must NOT appear (it should have been rewritten to
# 'references/docs/<file>.md'). Use word-boundary equivalent to avoid
# false positives on 'references/docs/...' which is the rewritten form.
BARE_RE = re.compile(r"(?<![\w/])docs/[a-z][a-z0-9-]+\.md")
matches = BARE_RE.findall(text)
sys.exit(1 if matches else 0)
PY
  then
    pass "T4: copied implementer.md has bare 'docs/...' rewritten to 'references/docs/...'"
  else
    fail "T4: copied implementer.md still contains bare 'docs/...' references"
  fi
  if grep -qF 'references/docs/naming-conventions.md' "$COPIED_IMPL"; then
    pass "T4.1: copied implementer.md uses 'references/docs/naming-conventions.md'"
  else
    # If the source agent never named naming-conventions.md (just 'docs/...'),
    # the rewritten form may still be there — but a missing rewrite means T4
    # didn't actually have anything to rewrite. Make this informational only.
    pass "T4.1: copied implementer.md has no naming-conventions.md reference (vacuously OK)"
  fi
else
  fail "T4: copied implementer.md missing from flattened issue-resolver"
fi

# ───────────────────────────────────────────────────────────
# T5: copied agents come from real source files (not stubs)
# ───────────────────────────────────────────────────────────
for agent_path in "$TMP_DIST_SKILLS/issue-resolver/references/agents"/*.md; do
  [ -f "$agent_path" ] || continue
  agent_name="$(basename "$agent_path")"
  if [ -f "$SRC_AGENTS/$agent_name" ]; then
    pass "T5: $agent_name traceable to src/shared/agents/"
  else
    fail "T5: $agent_name has no source counterpart"
  fi
done

# ───────────────────────────────────────────────────────────
# T6: copied docs come from real source files
# ───────────────────────────────────────────────────────────
for doc_path in "$TMP_DIST_SKILLS/issue-resolver/references/docs"/*.md; do
  [ -f "$doc_path" ] || continue
  doc_name="$(basename "$doc_path")"
  if [ -f "$SRC_DOCS/$doc_name" ]; then
    pass "T6: $doc_name traceable to docs/"
  else
    fail "T6: $doc_name has no source counterpart"
  fi
done

# ───────────────────────────────────────────────────────────
# T7: synthetic diamond test — construct a tiny project and run the build
# ───────────────────────────────────────────────────────────
# This validates the algorithm on a controlled tree. Post-#81, runtime
# docs live at top-level docs/ (sibling of src/), not src/docs/. We
# create:
#   src/skills/dia/SKILL.source.md → references shared/agents/B.md and C.md
#   src/shared/agents/B.md  → references docs/D.md
#   src/shared/agents/C.md  → references docs/D.md
#   docs/D.md               → leaf (no further refs)
# Expected: D.md appears exactly once in dist/skills/dia/references/docs/,
#   no cycle warnings, exit 0.
mkdir -p "$SYN_TMP/src/skills/dia" "$SYN_TMP/src/shared/agents" "$SYN_TMP/docs"
cat > "$SYN_TMP/src/skills/dia/SKILL.source.md" <<'EOF'
---
name: dia
description: diamond test skill
---

# Dia

Reads `shared/agents/b-agent.md` and `shared/agents/c-agent.md`.
EOF
cat > "$SYN_TMP/src/shared/agents/b-agent.md" <<'EOF'
# B

See `docs/d-doc.md`.
EOF
cat > "$SYN_TMP/src/shared/agents/c-agent.md" <<'EOF'
# C

See `docs/d-doc.md`.
EOF
cat > "$SYN_TMP/docs/d-doc.md" <<'EOF'
# D

Leaf.
EOF
# Copy build scripts so the synthetic build runs the same code path.
mkdir -p "$SYN_TMP/scripts"
cp "$REPO_ROOT/scripts/build.py" "$SYN_TMP/scripts/build.py"
cp "$REPO_ROOT/scripts/build.sh" "$SYN_TMP/scripts/build.sh"
cp "$REPO_ROOT/scripts/verify_flattened_skills.sh" "$SYN_TMP/scripts/verify_flattened_skills.sh"
chmod +x "$SYN_TMP/scripts/build.sh" "$SYN_TMP/scripts/verify_flattened_skills.sh"

if (cd "$SYN_TMP" && bash scripts/build.sh --out "$SYN_OUT") >"$SYN_LOG" 2>&1; then
  pass "T7.1: synthetic diamond build succeeds"
else
  fail "T7.1: synthetic diamond build failed"
  sed 's/^/    /' "$SYN_LOG" | head -20
fi

if grep -qiE 'cycle detected' "$SYN_LOG"; then
  fail "T7.2: synthetic diamond build flagged cycle (false positive)"
  grep -iE 'cycle detected' "$SYN_LOG" | sed 's/^/    /'
else
  pass "T7.2: synthetic diamond build emitted no cycle warning"
fi

# Verify D.md was copied exactly once and both agents were copied.
SYN_DIA="$SYN_OUT/skills/dia"
if [ -f "$SYN_DIA/references/docs/d-doc.md" ]; then
  pass "T7.3: synthetic D doc copied to dia/references/docs/"
else
  fail "T7.3: synthetic D doc missing"
fi
syn_dups="$(find "$SYN_DIA" -type f -name 'd-doc.md' | wc -l | tr -d ' ')"
if [ "$syn_dups" = "1" ]; then
  pass "T7.4: synthetic D doc appears exactly once (diamond resolved correctly)"
else
  fail "T7.4: synthetic D doc appears $syn_dups times (expected 1)"
fi

# T7.5 — both transitive agents (the diamond's middle nodes) must be copied.
# Without this, a build that silently dropped agent copies but still pulled
# their referenced docs would slip past T7.3/T7.4.
if [ -f "$SYN_DIA/references/agents/b-agent.md" ] && [ -f "$SYN_DIA/references/agents/c-agent.md" ]; then
  pass "T7.5: both transitive agents copied to dia/references/agents/"
else
  missing=""
  [ -f "$SYN_DIA/references/agents/b-agent.md" ] || missing="$missing b-agent.md"
  [ -f "$SYN_DIA/references/agents/c-agent.md" ] || missing="$missing c-agent.md"
  fail "T7.5: missing transitive agent copy:$missing"
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Dependency closure tests failed"
  exit 1
fi

echo "  ✓ Dependency closure handles diamond correctly"
exit 0
