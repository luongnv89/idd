#!/usr/bin/env bash
# test-model-suggestion-117.sh — Validate the model-suggestion feature
# shipped for issue #117.
#
# Verifies issue #117 acceptance criteria against the authored sources and the
# build output. This is a documentation/skill repo: if the spec language and
# seed data are present and the build ships them, the agent following the skill
# produces the documented behavior.
#
#  AC1. Model scoring data is shipped as a seed and cached at
#       .gitissue/model-data.json (seed at templates/model-data.json).
#  AC2. On skill start the cache is checked; if missing, the bundled seed is
#       used / a fetch is offered.
#  AC3. A cache older than 7 days triggers a staleness warning + refresh prompt.
#  AC4. Task complexity is classified on the XS/S/M/L/XL effort scale.
#  AC5. Each complexity maps to exactly one OpenAI + one Anthropic model.
#  AC6. The suggestion appears in BOTH the Step 5 preview AND the body
#       ## Metadata section (all three templates).
#  AC7. .gitissue.yml supports an optional model_suggestion section, generated
#       by /init-gitissue.
#
# Also guards the cross-cutting constraints: SKILL.source.md stays within the
# 500-line skill-creator budget, the Output Contract admits the suggestion, the
# seed ships through the build into both dist/skills and the repo-root skills/
# mirror, and the build remains deterministic with the new seed present.
#
# Usage: bash tests/test-model-suggestion-117.sh
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
BUG="$SKILL_DIR/templates/bug.md"
FEATURE="$SKILL_DIR/templates/feature.md"
IMPROVEMENT="$SKILL_DIR/templates/improvement.md"

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

echo "◆ Model Suggestion Tests (issue #117)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T0: Files exist
# ───────────────────────────────────────────────────────────
for f in "$SKILL" "$REF" "$SEED" "$ERRORS" "$SCHEMA" "$INIT_TEMPLATE" \
         "$BUG" "$FEATURE" "$IMPROVEMENT"; do
  if [ -f "$f" ]; then
    pass "T0: ${f#"$REPO_ROOT"/} exists"
  else
    fail "T0: $f not found"
    exit 1
  fi
done

# ───────────────────────────────────────────────────────────
# T1: AC1 — seed data file is valid JSON with the expected shape
# ───────────────────────────────────────────────────────────
if python3 -c "import json,sys; json.load(open('$SEED'))" 2>/dev/null; then
  pass "T1.AC1.1: model-data.json seed is valid JSON"
else
  fail "T1.AC1.1: model-data.json seed is not valid JSON"
fi

if python3 - "$SEED" <<'PY' 2>/dev/null; then
import json, sys
d = json.load(open(sys.argv[1]))
assert "last_fetched" in d, "missing last_fetched"
assert d["providers"]["openai"]["models"], "no openai models"
assert d["providers"]["anthropic"]["models"], "no anthropic models"
assert set(d["complexity_mapping"]) == {"XS", "S", "M", "L", "XL"}, "bad complexity keys"
for band, m in d["complexity_mapping"].items():
    assert m["openai"] and m["anthropic"], f"{band} missing a provider"
PY
  pass "T1.AC1.2: seed has last_fetched, both providers, and XS/S/M/L/XL mapping"
else
  fail "T1.AC1.2: seed missing required keys (last_fetched / providers / mapping)"
fi

# ───────────────────────────────────────────────────────────
# T2: AC2/AC3 — cache lifecycle documented (check / seed / staleness)
# ───────────────────────────────────────────────────────────
if grep -q '.gitissue/model-data.json' "$REF"; then
  pass "T2.AC2.1: reference documents the .gitissue/model-data.json cache"
else
  fail "T2.AC2.1: reference does not mention the cache file"
fi

if grep -qiE 'seed|bundled' "$REF" && grep -q 'cp ' "$REF"; then
  pass "T2.AC2.2: reference documents seeding from the bundled snapshot"
else
  fail "T2.AC2.2: reference does not document seeding the cache"
fi

if grep -qiE '7[ -]day|cache_ttl_days|stale' "$REF"; then
  pass "T2.AC3.1: reference documents the 7-day staleness threshold"
else
  fail "T2.AC3.1: reference does not document staleness"
fi

# ───────────────────────────────────────────────────────────
# T3: AC4/AC5 — complexity scale + one-model-per-provider mapping
# ───────────────────────────────────────────────────────────
if grep -qE 'XS\b' "$REF" && grep -qE 'XL\b' "$REF"; then
  pass "T3.AC4.1: reference uses the XS/S/M/L/XL effort scale"
else
  fail "T3.AC4.1: reference does not use the XS/S/M/L/XL scale"
fi

if grep -qE 'GPT-5\.5' "$REF" && grep -qE 'Opus|Fable 5' "$REF"; then
  pass "T3.AC5.1: reference maps to one OpenAI + one Anthropic model"
else
  fail "T3.AC5.1: reference mapping incomplete"
fi

# ───────────────────────────────────────────────────────────
# T4: AC6 — suggestion in BOTH the preview AND the body (3 templates)
# ───────────────────────────────────────────────────────────
if grep -qE '⚡ Model:' "$SKILL"; then
  pass "T4.AC6.1: Step 5 preview block renders the model line"
else
  fail "T4.AC6.1: Step 5 preview block missing the model line"
fi

for t in "$BUG" "$FEATURE" "$IMPROVEMENT"; do
  if grep -q '\*\*Suggested model:\*\*' "$t"; then
    pass "T4.AC6.2: $(basename "$t") ## Metadata has Suggested model line"
  else
    fail "T4.AC6.2: $(basename "$t") missing Suggested model line"
  fi
done

# ───────────────────────────────────────────────────────────
# T5: AC7 — config schema + init template carry model_suggestion
# ───────────────────────────────────────────────────────────
# Schema yaml block
if grep -qE '^model_suggestion:' "$SCHEMA"; then
  pass "T5.AC7.1: schema yaml block has model_suggestion:"
else
  fail "T5.AC7.1: schema yaml block missing model_suggestion:"
fi
# Mermaid section map
if grep -qE 'MS\["model_suggestion"\]' "$SCHEMA"; then
  pass "T5.AC7.2: Config Section Map lists model_suggestion"
else
  fail "T5.AC7.2: Config Section Map missing model_suggestion"
fi
# Defaults table
if grep -qE '\| \`model_suggestion\.enabled\` \| \`true\`' "$SCHEMA"; then
  pass "T5.AC7.3: defaults table lists model_suggestion.enabled = true"
else
  fail "T5.AC7.3: defaults table missing model_suggestion.enabled"
fi
# init template
if grep -qE '^model_suggestion:' "$INIT_TEMPLATE"; then
  pass "T5.AC7.4: init-gitissue template generates model_suggestion"
else
  fail "T5.AC7.4: init-gitissue template missing model_suggestion"
fi

# ───────────────────────────────────────────────────────────
# T6: Output Contract self-consistency + line budget + errors
# ───────────────────────────────────────────────────────────
if grep -qi 'Suggested model' "$SKILL" && \
   awk '/^## Output Contract$/{f=1} f&&/Suggested model/{print; exit}' "$SKILL" | grep -q .; then
  pass "T6.1: Output Contract admits the advisory model suggestion"
else
  fail "T6.1: Output Contract not updated to admit the model suggestion"
fi

LINES=$(wc -l < "$SKILL")
if [ "$LINES" -le 500 ]; then
  pass "T6.2: SKILL.source.md within 500-line budget ($LINES lines)"
else
  fail "T6.2: SKILL.source.md exceeds 500 lines ($LINES lines)"
fi

if grep -q 'Model data unavailable' "$ERRORS" && \
   grep -q 'Model data refresh failed' "$ERRORS"; then
  pass "T6.3: error catalog documents non-fatal model-data failures"
else
  fail "T6.3: error catalog missing model-data failure entries"
fi

# Default-on: feature is enabled by default (opt-out toggle)
if grep -qE '^\s*enabled:\s*true' "$INIT_TEMPLATE"; then
  pass "T6.4: model_suggestion defaults to enabled (opt-out)"
else
  fail "T6.4: model_suggestion not default-enabled"
fi

# ───────────────────────────────────────────────────────────
# T7: Build ships the seed and stays deterministic
# ───────────────────────────────────────────────────────────
BUILD_OUT="$(mktemp -d)"
trap 'rm -rf "$BUILD_OUT"' EXIT

if python3 "$REPO_ROOT/scripts/build.py" --out "$BUILD_OUT" >/dev/null 2>&1; then
  pass "T7.1: build.py succeeds with the new seed present"
else
  fail "T7.1: build.py failed with the new seed present"
  echo "" ; echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
  echo "  Passed: $PASS" ; echo "  Failed: $FAIL" ; echo "  Result: FAIL"
  exit 1
fi

BUILT_SEED="$BUILD_OUT/skills/issue-creator/templates/model-data.json"
if [ -f "$BUILT_SEED" ]; then
  pass "T7.2: seed propagates into dist/skills/issue-creator/templates/"
else
  fail "T7.2: seed missing from build output"
fi

# Suggested model line propagates into the built (flattened) templates
if grep -q '\*\*Suggested model:\*\*' "$BUILD_OUT/skills/issue-creator/templates/feature.md" 2>/dev/null; then
  pass "T7.3: Suggested model line present in built feature template"
else
  fail "T7.3: Suggested model line missing from built template"
fi

# Repo-root committed mirror also carries the seed
if [ -f "$REPO_ROOT/skills/issue-creator/templates/model-data.json" ]; then
  pass "T7.4: seed present in committed repo-root skills/ mirror"
else
  fail "T7.4: seed missing from repo-root skills/ mirror (run ./scripts/build.sh)"
fi

# Determinism: a second build into a fresh dir produces identical issue-creator output
BUILD_OUT2="$(mktemp -d)"
trap 'rm -rf "$BUILD_OUT" "$BUILD_OUT2"' EXIT
if python3 "$REPO_ROOT/scripts/build.py" --out "$BUILD_OUT2" >/dev/null 2>&1 && \
   diff -r "$BUILD_OUT/skills/issue-creator" "$BUILD_OUT2/skills/issue-creator" >/dev/null 2>&1; then
  pass "T7.5: build is deterministic for issue-creator with the seed"
else
  fail "T7.5: build is non-deterministic for issue-creator"
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
