#!/usr/bin/env bash
# test-model-suggestion-124.sh — Validate the skill-level model cache
# shipped for issue #124.
#
# Verifies issue #124 acceptance criteria against the authored sources and the
# build output. This is a documentation/skill repo: if the spec language and
# seed data are present and the build ships them, the agent following the skill
# produces the documented behavior.
#
#  AC1. Model-suggestion cache is stored at the skill installation level, not
#       per-repo under .gitissue/.
#  AC2. A new repo reuses the existing shared cache without creating a
#       project-local model-data.json copy.
#  AC3. Refreshing stale data updates the shared cache once for all repos.
#  AC4. Staleness detection and bundled-seed fallback operate against the
#       shared skill-level cache location.
#  AC5. The cache filename includes the update date (model-data-<date>.json).
#  AC6. Users can force a refresh at any time (--refresh-model-data),
#       independent of the staleness threshold.
#  AC7. A pre-existing per-repo cache is handled gracefully (ignored).
#
# Usage: bash tests/test-model-suggestion-124.sh
# Returns: exit 0 if all tests pass, exit 1 on first failure category.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_DIR="$REPO_ROOT/src/skills/issue-creator"
SKILL="$SKILL_DIR/SKILL.source.md"
REF="$SKILL_DIR/references/model-suggestion.md"
SEED="$SKILL_DIR/templates/model-data.json"
ERRORS="$SKILL_DIR/references/error-messages.md"
SCHEMA="$REPO_ROOT/docs/config-schema.md"
INIT_TEMPLATE="$REPO_ROOT/src/skills/init-gitissue/templates/gitissue-template.yml"

PASS=0
FAIL=0

pass() {
  echo "  ✓ $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  ✗ $1"
  FAIL=$((FAIL + 1))
}

echo "◆ Skill-Level Model Cache Tests (issue #124)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T0: Files exist
# ───────────────────────────────────────────────────────────
for f in "$SKILL" "$REF" "$SEED" "$ERRORS" "$SCHEMA" "$INIT_TEMPLATE"; do
  if [ -f "$f" ]; then
    pass "T0: ${f#"$REPO_ROOT"/} exists"
  else
    fail "T0: $f not found"
    exit 1
  fi
done

# ───────────────────────────────────────────────────────────
# T1: AC1/AC4 — cache lives at the skill level, not per-repo
# ───────────────────────────────────────────────────────────
if grep -qiE 'skill[ -]level' "$REF"; then
  pass "T1.AC1.1: reference describes a skill-level cache"
else
  fail "T1.AC1.1: reference does not describe a skill-level cache"
fi

# The reference must use the skill-dir placeholder for the cache, and must NOT
# instruct writing the live cache under .gitissue/ anymore.
if grep -qE '\{skill_dir\}/model-data' "$REF"; then
  pass "T1.AC1.2: cache path uses {skill_dir}/model-data-<date>.json"
else
  fail "T1.AC1.2: cache path not rooted at {skill_dir}"
fi

if grep -qE 'cp[^\n]*\.gitissue/model-data\.json' "$REF"; then
  fail "T1.AC1.3: reference still seeds the cache into .gitissue/ (per-repo)"
else
  pass "T1.AC1.3: reference no longer writes the cache under .gitissue/"
fi

# ───────────────────────────────────────────────────────────
# T2: AC5 — the cache filename carries the update date
# ───────────────────────────────────────────────────────────
if grep -qE 'model-data-\{?YYYY-MM-DD\}?\.json|model-data-<date>\.json' "$REF"; then
  pass "T2.AC5.1: reference documents the dated cache filename"
else
  fail "T2.AC5.1: reference does not document a dated cache filename"
fi

# Discovery via glob + newest-wins must be documented.
if grep -qE 'model-data-\*\.json' "$REF"; then
  pass "T2.AC5.2: reference documents glob discovery of dated caches"
else
  fail "T2.AC5.2: reference does not document glob discovery"
fi

# Refresh must prune older dated files (no accumulation).
if grep -qiE 'delete|prune|remove' "$REF" && grep -qiE 'older|other|prior' "$REF"; then
  pass "T2.AC5.3: refresh deletes prior dated cache files"
else
  fail "T2.AC5.3: refresh does not document pruning older dated files"
fi

# ───────────────────────────────────────────────────────────
# T3: AC6 — force refresh, independent of staleness
# ───────────────────────────────────────────────────────────
if grep -q -- '--refresh-model-data' "$SKILL"; then
  pass "T3.AC6.1: SKILL invocation table documents --refresh-model-data"
else
  fail "T3.AC6.1: SKILL does not document a force-refresh flag"
fi

if grep -q -- '--refresh-model-data' "$REF"; then
  pass "T3.AC6.2: reference documents the force-refresh procedure"
else
  fail "T3.AC6.2: reference does not document force refresh"
fi

# Force refresh must be explicitly independent of the staleness threshold.
if grep -qiE 'regardless of stale|independent of (the )?stale|unconditional' "$REF"; then
  pass "T3.AC6.3: force refresh is independent of staleness"
else
  fail "T3.AC6.3: force refresh not stated as staleness-independent"
fi

# ───────────────────────────────────────────────────────────
# T4: AC7 — legacy per-repo cache handled gracefully (ignored)
# ───────────────────────────────────────────────────────────
if grep -qiE '\.gitissue/model-data\.json' "$REF" && grep -qiE 'ignore|legacy' "$REF"; then
  pass "T4.AC7.1: reference states the legacy per-repo cache is ignored"
else
  fail "T4.AC7.1: reference does not address the legacy per-repo cache"
fi

# The durable docs (config-schema) must record that the cache is no longer in
# .gitissue/ and that a legacy file is ignored.
if grep -qiE 'skill-level' "$SCHEMA" && grep -qiE 'ignored|legacy' "$SCHEMA"; then
  pass "T4.AC7.2: config-schema documents the move + legacy handling"
else
  fail "T4.AC7.2: config-schema does not document the move + legacy handling"
fi

# ───────────────────────────────────────────────────────────
# T5: AC2 — no instruction to create a project-local copy remains
# ───────────────────────────────────────────────────────────
# The init template comment must no longer claim the cache lives in .gitissue/.
if grep -qE '\.gitissue/model-data\.json' "$INIT_TEMPLATE"; then
  fail "T5.AC2.1: init template still points cache at .gitissue/model-data.json"
else
  pass "T5.AC2.1: init template no longer points cache at .gitissue/"
fi

# Error catalog must reference the skill-level cache, not the per-repo path.
if grep -qiE 'skill-level `?model-data' "$ERRORS"; then
  pass "T5.AC2.2: error catalog references the skill-level cache"
else
  fail "T5.AC2.2: error catalog does not reference the skill-level cache"
fi

# ───────────────────────────────────────────────────────────
# T6: Build ships the updated sources into the flattened skill
# ───────────────────────────────────────────────────────────
BUILD_OUT="$(mktemp -d)"
trap 'rm -rf "$BUILD_OUT"' EXIT

if python3 "$REPO_ROOT/scripts/build.py" --out "$BUILD_OUT" >/dev/null 2>&1; then
  pass "T6.1: build.py succeeds"
else
  fail "T6.1: build.py failed"
  echo "" ; echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
  echo "  Passed: $PASS" ; echo "  Failed: $FAIL" ; echo "  Result: FAIL"
  exit 1
fi

BUILT_REF="$BUILD_OUT/skills/issue-creator/references/model-suggestion.md"
if grep -q -- '--refresh-model-data' "$BUILT_REF" 2>/dev/null && \
   grep -qiE 'skill[ -]level' "$BUILT_REF" 2>/dev/null; then
  pass "T6.2: skill-level cache + force refresh present in built reference"
else
  fail "T6.2: built reference missing skill-level cache / force refresh"
fi

# Seed still ships undated (the dated file is runtime-only, never shipped).
if [ -f "$BUILD_OUT/skills/issue-creator/templates/model-data.json" ]; then
  pass "T6.3: undated seed still ships in templates/"
else
  fail "T6.3: undated seed missing from built templates/"
fi

if ls "$BUILD_OUT"/skills/issue-creator/templates/model-data-*.json >/dev/null 2>&1; then
  fail "T6.4: a dated cache file leaked into shipped templates/"
else
  pass "T6.4: no dated cache file in shipped templates/ (runtime-only)"
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  Result: FAIL"
  exit 1
else
  echo "  Result: PASS"
  exit 0
fi
