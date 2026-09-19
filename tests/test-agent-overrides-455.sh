#!/usr/bin/env bash
# test-agent-overrides-455.sh — per-role spawn overrides wired into every
# spawn site (issue #455).
#
# docs/agent-overrides.md is the single home of the rule that applies
# `agents.model.<role>` / `agents.effort.<role>` when a skill spawns a
# subagent. Asserts:
#   1. the doc states the per-spawn rule, the fallback ladder, the
#      "spawn failure only" rule, the gate-untouched rule and the precedence
#      over the advisory tier;
#   2. each spawning skill bundles the doc, lists it in its precheck, and its
#      bundled config excerpt carries the `agents` section;
#   3. every listed spawn site cites the rule for its role, and auto-pilot's
#      four spawn blocks are keyed to the three autopilot-* roles;
#   4. with no `agents` section the bundled resolver yields null for every
#      role and no documented spawn call carries a `model` argument;
#   5. the "never set subagent_type" prohibition text is unchanged.
#
# Usage: bash tests/test-agent-overrides-455.sh
# Returns: exit 0 if all checks pass, exit 1 on failure
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="$ROOT/docs/agent-overrides.md"
WORKFLOW="$ROOT/.github/workflows/dist-check.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
# has <label> <file> <fixed-string>
has() { if grep -qF -- "$3" "$2"; then pass "$1"; else fail "$1 — missing: $3"; fi; }

echo "◆ per-role agent overrides at every spawn site (#455)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

[ -f "$DOC" ] || { echo "  ✗ missing $DOC"; exit 1; }

BUILD="$TMP/build"
if bash "$ROOT/scripts/build.sh" --out "$BUILD" --quiet >"$TMP/build.log" 2>&1; then
  pass "T0 build passes"
else
  fail "T0 build failed: $(tail -5 "$TMP/build.log")"
  echo ""; echo "  Passed: $PASS  Failed: $FAIL"; exit 1
fi
OUT="$BUILD/skills"

# ─── T1: the doc states every rule ──────────────────────────────────────────
has "T1a per-spawn rule: null passes nothing"   "$DOC" 'Pass nothing'
has "T1b per-spawn rule: verbatim value"        "$DOC" '**verbatim**'
has "T1c model unsupported line"                "$DOC" '○ {role}: model override not supported here — inheriting'
has "T1d effort prompt line"                    "$DOC" 'Thinking effort: {value}'
has "T1e fallback ladder: rejected spawn"       "$DOC" "⚠ {role}: spawn with model '{x}' failed — retrying with main agent config"
has "T1f fallback ladder: no Agent tool"        "$DOC" '○ agents: no subagent tool — overrides ignored'
has "T1g spawn failure only"                    "$DOC" '**Spawn failure only.**'
has "T1h never on output quality"               "$DOC" 'never on output quality'
has "T1i safety gates untouched"                "$DOC" '**Safety gates.**'
has "T1j precedence over the advisory tier"     "$DOC" 'A configured model **wins** over the advisory'
has "T1k tracker line"                          "$DOC" '· model: {x} → inherited'
# doc→doc references are full URLs: a bare token would add a bundling edge.
if grep -E '(^|[^/A-Za-z0-9_-])docs/[a-z-]+\.md' "$DOC" >/dev/null; then
  fail "T1l bare docs/X.md token in agent-overrides.md"
else
  pass "T1l no bare docs/X.md token (no extra bundling edge)"
fi

# ─── T2: bundling, precheck and config excerpt ──────────────────────────────
SKILLS="issue-resolver issue-pr-review issue-analysis issue-triage issue-creator auto-pilot"
for s in $SKILLS; do
  d="$OUT/$s"
  if grep -qF '## Fallback ladder' "$d/references/docs/agent-overrides.md" 2>/dev/null; then
    pass "T2a $s bundles agent-overrides.md"
  else
    fail "T2a $s does not bundle agent-overrides.md"
  fi
  has "T2b $s precheck lists the doc" "$d/SKILL.md" 'references/docs/agent-overrides.md'
  if grep -q '^agents:' "$d/references/docs/config-schema.md"; then
    pass "T2c $s config excerpt carries agents"
  else
    fail "T2c $s config excerpt lacks the agents section"
  fi
  if cmp -s "$d/references/docs/agent-overrides.md" "$ROOT/skills/$s/references/docs/agent-overrides.md"; then
    pass "T2d $s committed skills/ copy matches a fresh build"
  else
    fail "T2d $s committed skills/ copy is stale or missing"
  fi
done

# ─── T3: every spawn site cites the rule for its role ───────────────────────
# site <label> <built file> <role>...
site() {
  local label="$1" file="$2"; shift 2
  has "$label cites the rule" "$file" 'references/docs/agent-overrides.md'
  for role in "$@"; do
    has "$label names agents.model.$role" "$file" "agents.model.$role"
  done
}
site "T3a resolver SKILL.md"        "$OUT/issue-resolver/SKILL.md" '<role>'
site "T3b resolver pipeline-steps"  "$OUT/issue-resolver/references/pipeline-steps.md" '<role>'
site "T3c pr-review SKILL.md"       "$OUT/issue-pr-review/SKILL.md" '<role>'
site "T3d pr-review loop mechanics" "$OUT/issue-pr-review/references/review-loop-mechanics.md" code-reviewer fixer
site "T3e analysis subagent-steps"  "$OUT/issue-analysis/references/subagent-steps.md" codebase-researcher synthesizer
site "T3f triage detection"         "$OUT/issue-triage/references/detection.md" issue-relationship-scanner
site "T3g creator SKILL.md"         "$OUT/issue-creator/SKILL.md" duplicate-detector
for role in codebase-researcher synthesizer implementer code-reviewer ui-reviewer fixer; do
  has "T3h resolver names role $role" "$OUT/issue-resolver/SKILL.md" "\`$role\`"
done

AP="$OUT/auto-pilot/references/subagent-prompts.md"
has "T3i auto-pilot prompts cite the rule" "$AP" 'references/docs/agent-overrides.md'
count() { grep -cF -- "$1" "$AP" || true; }
[ "$(count '- `model` / effort: role `autopilot-resolver`')" -eq 2 ] \
  && pass "T3j resolver + batch resolver keyed to autopilot-resolver" \
  || fail "T3j expected 2 autopilot-resolver blocks, got $(count '- `model` / effort: role `autopilot-resolver`')"
[ "$(count '- `model` / effort: role `autopilot-reviewer`')" -eq 1 ] \
  && pass "T3k reviewer keyed to autopilot-reviewer" || fail "T3k autopilot-reviewer block count"
[ "$(count '- `model` / effort: role `autopilot-analyzer`')" -eq 1 ] \
  && pass "T3l analyzer keyed to autopilot-analyzer" || fail "T3l autopilot-analyzer block count"
[ "$(count '- `model` / effort: role')" -eq "$(count '- `subagent_type`: omit')" ] \
  && pass "T3m every spawn block carries a role line" || fail "T3m a spawn block has no role line"

# ─── T4: nothing configured → the same call as before ───────────────────────
mkdir -p "$TMP/repo"
for s in $SKILLS; do
  if (cd "$TMP/repo" && python3 "$OUT/$s/references/scripts/gi-config.py") >"$TMP/cfg.json" 2>"$TMP/cfg.err" \
     && python3 - "$TMP/cfg.json" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))["config"]
keys = [k for k in cfg if k.startswith("agents.")]
sys.exit(0 if len(keys) == 24 and all(cfg[k] is None for k in keys) else 1)
PY
  then pass "T4a $s bundled resolver: all 24 agents.* keys null by default"
  else fail "T4a $s bundled resolver did not yield 24 null agents.* keys: $(head -3 "$TMP/cfg.err")"
  fi
done
# No documented spawn call passes a model: the override is prose beside it.
if grep -rnE '^\s*(model|effort)\s*=' "$ROOT/src/skills" --include='*.md' >"$TMP/modelargs" 2>/dev/null; then
  fail "T4b a documented Agent() call carries a model/effort argument: $(head -2 "$TMP/modelargs")"
else
  pass "T4b no documented Agent() call carries a model/effort argument"
fi
has "T4c doc: null is byte-for-byte today's call" "$DOC" 'byte-for-byte'

# ─── T5: the subagent_type prohibition text is unchanged ────────────────────
has "T5a resolver prohibition"       "$OUT/issue-resolver/SKILL.md" 'Role, description and prompt file change per step. **Do NOT set `subagent_type`**:'
has "T5b resolver call comment"      "$OUT/issue-resolver/SKILL.md" '  # never subagent_type — the default general-purpose agent, not "code-reviewer"'
has "T5c pr-review prohibition"      "$OUT/issue-pr-review/SKILL.md" 'both spawn with the default general-purpose agent (do NOT set `subagent_type`)'
RLM="$OUT/issue-pr-review/references/review-loop-mechanics.md"
[ "$(grep -cF -- '# do NOT set subagent_type — default general-purpose agent, not a custom "code-reviewer" type' "$RLM")" -eq 2 ] \
  && pass "T5d loop mechanics: both reviewer comments" || fail "T5d reviewer prohibition comments changed"
has "T5e loop mechanics: fixer comment" "$RLM" '# do NOT set subagent_type — default general-purpose agent, not a custom "fixer" type'
has "T5f auto-pilot CRITICAL paragraph" "$AP" '**CRITICAL — never set `subagent_type`:** Every subagent below is spawned with the **default general-purpose agent**. Do NOT pass a `subagent_type` parameter to the Agent tool.'
[ "$(count '- `subagent_type`: omit (use the default general-purpose agent')" -eq 4 ] \
  && pass "T5g auto-pilot: four omit lines" || fail "T5g auto-pilot omit lines changed"
has "T5h phase-2 prohibition" "$OUT/auto-pilot/references/phases/phase-2-resolve.md" 'do NOT set `subagent_type`'
has "T5i conventions prohibition" "$ROOT/docs/shared-agent-conventions.md" '**Do NOT set `subagent_type`** — always use the default general-purpose agent.'

# ─── T6: registration and doc count ─────────────────────────────────────────
has "T6a registered in dist-check.yml" "$WORKFLOW" 'bash tests/test-agent-overrides-455.sh'
has "T6b CLAUDE.md counts 14 runtime docs" "$ROOT/CLAUDE.md" 'all 14 bundled by the closure'
has "T6c CLAUDE.md lists the doc" "$ROOT/CLAUDE.md" '`agent-overrides.md`'

echo ""
echo "  Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
