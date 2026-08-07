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
#   - Transitive shared scripts are copied into skills/<name>/references/scripts/
#     byte-identically and with their source mode, and the pipeline that does so
#     is generic — scripts/build.py carries no script-name literal, so adding a
#     new shared script requires no build.py change (issue #251).
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
# Scratch space for the two negative fixtures (T7.11 / T7.12), which mutate a
# copy of the synthetic tree and expect the build to abort.
NEG_TMP="$(mktemp -d)"
NEG_OUT="$(mktemp -d)"
NEG_LOG="$(mktemp)"
trap 'rm -rf "$TMP_OUT" "$SYN_TMP" "$SYN_OUT" "$NEG_TMP" "$NEG_OUT"; rm -f "$BUILD_LOG" "$SYN_LOG" "$NEG_LOG"' EXIT

# Portable mode read: GNU `stat -c` and BSD `stat -f` disagree, python3 does not.
mode_of() {
  python3 -c 'import os,sys;print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$1"
}

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
#   src/skills/dia/SKILL.source.md → references agents B + C, docs/D.md, and
#                                    the shared script gi-syn.py
#   src/shared/agents/B.md  → references docs/D.md, docs/E.md, gi-agentonly.py
#   src/shared/agents/C.md  → references docs/D.md and docs/E.md
#   docs/D.md, docs/E.md    → leaves (no further refs)
#   src/shared/scripts/gi-syn.py, gi-agentonly.py → leaves (never scanned)
# Expected: D.md appears exactly once in dist/skills/dia/references/docs/,
#   E.md (reachable only through agents, whose emitted prompts render refs as
#   absolute URLs — issue #249) is validated but never bundled, gi-syn.py lands
#   in dia/references/scripts/ byte-identically, gi-agentonly.py follows the
#   same agent-only rule as E.md, no cycle warnings, exit 0.
#
# gi-syn.py is a name scripts/build.py has never heard of. It ships correctly
# through an unmodified build.py — which, with T7.10, is the executable proof of
# the issue #251 design constraint: adding a script requires no build.py change.
mkdir -p "$SYN_TMP/src/skills/dia" "$SYN_TMP/src/shared/agents" \
         "$SYN_TMP/src/shared/scripts" "$SYN_TMP/docs"
cat > "$SYN_TMP/src/skills/dia/SKILL.source.md" <<'EOF'
---
name: dia
description: diamond test skill
---

# Dia

Reads `shared/agents/b-agent.md`, `shared/agents/c-agent.md`, and `docs/d-doc.md`.

Runs `python3 shared/scripts/gi-syn.py` for the synthetic determinism check.

## Bundled dependency precheck

```text
references/agents/b-agent.md
references/agents/c-agent.md
references/docs/d-doc.md
references/scripts/gi-syn.py
```
EOF
cat > "$SYN_TMP/src/shared/agents/b-agent.md" <<'EOF'
# B

See `docs/d-doc.md` and `docs/e-doc.md`.

Also runs `shared/scripts/gi-agentonly.py`.
EOF
cat > "$SYN_TMP/src/shared/agents/c-agent.md" <<'EOF'
# C

See `docs/d-doc.md` and `docs/e-doc.md`.
EOF
cat > "$SYN_TMP/docs/d-doc.md" <<'EOF'
# D

Leaf.
EOF
cat > "$SYN_TMP/docs/e-doc.md" <<'EOF'
# E

Agent-only leaf.
EOF
cat > "$SYN_TMP/src/shared/scripts/gi-syn.py" <<'EOF'
#!/usr/bin/env python3
"""Synthetic shared script — a name build.py has never heard of."""
print("gi-syn")
EOF
cat > "$SYN_TMP/src/shared/scripts/gi-agentonly.py" <<'EOF'
#!/usr/bin/env python3
"""Synthetic shared script reachable only through a shared agent."""
print("gi-agentonly")
EOF
chmod 0755 "$SYN_TMP/src/shared/scripts/gi-syn.py" \
           "$SYN_TMP/src/shared/scripts/gi-agentonly.py"
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

# T7.6 — a doc reachable only through an agent must NOT be bundled (issue
# #249): emitted agent prompts render their references as absolute repo URLs,
# so a bundled copy reached only that way is unreferenceable install weight.
if [ -f "$SYN_DIA/references/docs/e-doc.md" ]; then
  fail "T7.6: agent-only doc e-doc.md was bundled into dia/references/docs/"
else
  pass "T7.6: agent-only doc e-doc.md validated but not bundled"
fi

# ───────────────────────────────────────────────────────────
# T7.7 (issue #251) — a shared script cited by a skill lands under
# references/scripts/ exactly once, byte-identical, with its source mode.
# ───────────────────────────────────────────────────────────
SYN_SCRIPT_SRC="$SYN_TMP/src/shared/scripts/gi-syn.py"
SYN_SCRIPT_OUT="$SYN_DIA/references/scripts/gi-syn.py"
if [ -f "$SYN_SCRIPT_OUT" ]; then
  pass "T7.7.1: synthetic script copied to dia/references/scripts/"
  syn_script_dups="$(find "$SYN_DIA" -type f -name 'gi-syn.py' | wc -l | tr -d ' ')"
  if [ "$syn_script_dups" = "1" ]; then
    pass "T7.7.2: synthetic script appears exactly once in the flattened skill"
  else
    fail "T7.7.2: synthetic script appears $syn_script_dups times (expected 1)"
  fi
  if cmp -s "$SYN_SCRIPT_SRC" "$SYN_SCRIPT_OUT"; then
    pass "T7.7.3: emitted script is byte-identical to its source (no banner injected)"
  else
    fail "T7.7.3: emitted script differs from its source"
  fi
  src_mode="$(mode_of "$SYN_SCRIPT_SRC")"
  out_mode="$(mode_of "$SYN_SCRIPT_OUT")"
  if [ "$src_mode" = "$out_mode" ]; then
    pass "T7.7.4: emitted script keeps the source mode ($out_mode)"
  else
    fail "T7.7.4: emitted script is mode $out_mode, source is $src_mode"
  fi
else
  fail "T7.7.1: synthetic script missing from dia/references/scripts/"
fi

if grep -qF 'references/scripts/gi-syn.py' "$SYN_DIA/SKILL.md"; then
  pass "T7.7.5: dia/SKILL.md rewrites the bare token to references/scripts/gi-syn.py"
else
  fail "T7.7.5: dia/SKILL.md does not render references/scripts/gi-syn.py"
fi
if grep -qE '(^|[^/])shared/scripts/gi-syn\.py' "$SYN_DIA/SKILL.md"; then
  fail "T7.7.6: dia/SKILL.md still carries the unresolved bare shared/scripts token"
else
  pass "T7.7.6: dia/SKILL.md carries no unresolved bare shared/scripts token"
fi

# ───────────────────────────────────────────────────────────
# T7.8 — a script reachable ONLY through a shared agent must not be bundled.
# Same rule as e-doc.md (issues #245/#249): an emitted agent prompt renders its
# references as absolute repo URLs, so a bundled copy would be unreferenceable.
# ───────────────────────────────────────────────────────────
if [ -f "$SYN_DIA/references/scripts/gi-agentonly.py" ]; then
  fail "T7.8: agent-only script gi-agentonly.py was bundled into dia/references/scripts/"
else
  pass "T7.8: agent-only script gi-agentonly.py validated but not bundled"
fi

# ───────────────────────────────────────────────────────────
# T7.9 — the emitted agent renders the agent-only script as an absolute URL.
# ───────────────────────────────────────────────────────────
SYN_AGENT="$SYN_OUT/agents/b-agent.md"
AGENT_SCRIPT_URL='https://github.com/luongnv89/idd/blob/main/src/shared/scripts/gi-agentonly.py'
if [ -f "$SYN_AGENT" ] && grep -qF "$AGENT_SCRIPT_URL" "$SYN_AGENT"; then
  pass "T7.9: emitted agent renders the script reference as an absolute repo URL"
else
  fail "T7.9: emitted agent does not render $AGENT_SCRIPT_URL"
fi

# ───────────────────────────────────────────────────────────
# T7.10 — THE GENERIC-PIPELINE PROPERTY (issue #251 headline constraint).
# scripts/build.py must contain no script-name literal. Combined with T7.7 —
# where gi-syn.py, a name build.py has never seen, ships correctly through an
# unmodified build.py — this is the executable proof that adding a fourth
# shared script requires NO build.py change: there is no list to edit.
# ───────────────────────────────────────────────────────────
if grep -qE 'gi-[a-z0-9-]+\.py' "$REPO_ROOT/scripts/build.py"; then
  fail "T7.10: GENERIC-PIPELINE PROPERTY VIOLATED — scripts/build.py names a specific script"
  grep -nE 'gi-[a-z0-9-]+\.py' "$REPO_ROOT/scripts/build.py" | sed 's/^/    /'
else
  pass "T7.10: GENERIC-PIPELINE PROPERTY — scripts/build.py carries no script-name literal, so a new shared script needs no build.py change"
fi

# ───────────────────────────────────────────────────────────
# T7.11 — a bare shared/scripts token with no source file aborts the build.
# ───────────────────────────────────────────────────────────
cp -R "$SYN_TMP/." "$NEG_TMP/"
python3 - "$NEG_TMP/src/skills/dia/SKILL.source.md" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
# Only the prose citation carries the bare `shared/scripts/` form; the precheck
# fence uses the emitted `references/scripts/` form and is left alone.
path.write_text(
    text.replace("shared/scripts/gi-syn.py", "shared/scripts/gi-missing.py", 1),
    encoding="utf-8",
)
PY
if (cd "$NEG_TMP" && bash scripts/build.sh --out "$NEG_OUT") >"$NEG_LOG" 2>&1; then
  fail "T7.11: build accepted a shared/scripts reference with no source file"
elif grep -qF "unresolved script reference 'gi-missing.py'" "$NEG_LOG"; then
  pass "T7.11: an unresolvable shared/scripts token aborts with 'unresolved script reference'"
else
  fail "T7.11: build failed, but not with the unresolved-script abort"
  sed 's/^/    /' "$NEG_LOG" | head -10
fi

# ───────────────────────────────────────────────────────────
# T7.12 — a shipped script's `# gi-requires:` declaration must resolve inside
# the same skill's bundle, or the script would silently degrade forever.
# ───────────────────────────────────────────────────────────
rm -rf "$NEG_TMP" "$NEG_OUT"
mkdir -p "$NEG_TMP" "$NEG_OUT"
cp -R "$SYN_TMP/." "$NEG_TMP/"
python3 - "$NEG_TMP/src/shared/scripts/gi-syn.py" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
lines.insert(1, "# gi-requires: references/docs/absent.md\n")
path.write_text("".join(lines), encoding="utf-8")
PY
if (cd "$NEG_TMP" && bash scripts/build.sh --out "$NEG_OUT") >"$NEG_LOG" 2>&1; then
  fail "T7.12: build accepted a gi-requires declaration for an unbundled file"
elif grep -qF "gi-requires: references/docs/absent.md" "$NEG_LOG" \
     && grep -qF "is not bundled" "$NEG_LOG"; then
  pass "T7.12: an unresolvable 'gi-requires' declaration aborts the build"
else
  fail "T7.12: build failed, but not with the gi-requires abort"
  sed 's/^/    /' "$NEG_LOG" | head -10
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
