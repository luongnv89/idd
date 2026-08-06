#!/usr/bin/env bash
# test-disclosure-gates-250.sh — Disclosure gates + checkable step completion (issue #250)
#
# Acceptance criteria:
#   AC1: Every-run-mandatory material sits behind "read now" pointers; the
#        no-Agent-tool inline fallback is a separate file, gated on the Agent
#        tool being unavailable.
#   AC2: /init-gitissue validates the generated config (YAML parse + no leftover
#        placeholders) before reporting success.
#   AC3: resolver, pr-review, auto-pilot and triage emit Step Completion Reports
#        with √/× checks and a Result line.
#   AC4: /issue-creator no longer runs a mandatory local rebase for its
#        remote-only operations.
#   AC5: skill READMEs live at the skill-creator standard location (docs/README.md)
#        and carry the AI-skip notice.
#
# Usage: bash tests/test-disclosure-gates-250.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_ROOT/src/skills"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Disclosure Gates & Step Completion Tests (issue #250)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ── AC1: disclosure gates ─────────────────────────────────────────────────────
ANALYSIS_SRC="$SRC/issue-analysis/SKILL.source.md"
FALLBACK="$SRC/issue-analysis/references/inline-fallback.md"
SUBAGENT="$SRC/issue-analysis/references/subagent-steps.md"

if [ -f "$FALLBACK" ]; then
  pass "AC1.1: issue-analysis ships a separate references/inline-fallback.md"
else
  fail "AC1.1: references/inline-fallback.md missing — the inline fallback must be its own file"
fi

if grep -qiE 'only when the Agent tool is unavailable|read this file only when the Agent tool is unavailable' "$FALLBACK" 2>/dev/null; then
  pass "AC1.2: inline-fallback.md is gated on the Agent tool being unavailable"
else
  fail "AC1.2: inline-fallback.md carries no Agent-tool-unavailable gate"
fi

# The delegation spec must no longer carry the fallback body.
if grep -qE '^### Step 3 — Research \(Deep Codebase Scan\)' "$SUBAGENT" 2>/dev/null; then
  fail "AC1.3: subagent-steps.md still contains the inline fallback body"
else
  pass "AC1.3: subagent-steps.md is the delegation spec only"
fi

# Every-run-mandatory references are "read now", not "read when tuning/debugging".
for ref in subagent-steps output-and-persist; do
  if grep -qE "Read \`references/$ref\.md\` now" "$ANALYSIS_SRC"; then
    pass "AC1.4: issue-analysis gates references/$ref.md as read-now"
  else
    fail "AC1.4: references/$ref.md is not behind a read-now pointer"
  fi
done

if grep -nE 'references/(subagent-steps|output-and-persist)\.md` — read that file when (tuning|implementing|debugging)' "$ANALYSIS_SRC" >/dev/null; then
  fail "AC1.5: issue-analysis still uses an inverted 'read when tuning/debugging' gate"
else
  pass "AC1.5: no inverted gate left over mandatory issue-analysis material"
fi

if grep -qE 'Read `references/detection\.md`\s*$|\*\*Read `references/detection\.md`' "$SRC/issue-triage/SKILL.source.md"; then
  pass "AC1.6: issue-triage gates references/detection.md as read-now"
else
  fail "AC1.6: issue-triage still defers references/detection.md to tuning time"
fi

# ── AC2: init-gitissue completion bar ─────────────────────────────────────────
INIT_SRC="$SRC/init-gitissue/SKILL.source.md"
if grep -qE 'yaml\.safe_load|YAML\.load_file' "$INIT_SRC"; then
  pass "AC2.1: init-gitissue parses the written config as YAML"
else
  fail "AC2.1: init-gitissue never parses the generated config"
fi

if grep -qE 'placeholder' "$INIT_SRC"; then
  pass "AC2.2: init-gitissue checks for leftover placeholder tokens"
else
  fail "AC2.2: init-gitissue has no leftover-placeholder check"
fi

if grep -qE '^  Validation: ' "$INIT_SRC"; then
  pass "AC2.3: the completion report carries a Validation row"
else
  fail "AC2.3: the completion report has no Validation row"
fi

if grep -qE '^### Generated config failed validation' "$SRC/init-gitissue/references/error-messages.md"; then
  pass "AC2.4: validation failure has a rich error message"
else
  fail "AC2.4: no error-message entry for a failed config validation"
fi

# ── AC3: step completion reports ──────────────────────────────────────────────
# "<skill>|<reference file that owns the format>"
for entry in \
  "issue-resolver|report-templates.md" \
  "issue-pr-review|report-templates.md" \
  "auto-pilot|summary-format.md" \
  "issue-triage|output-and-persist.md" \
; do
  skill="${entry%%|*}"
  owner="${entry##*|}"
  skill_src="$SRC/$skill/SKILL.source.md"
  owner_file="$SRC/$skill/references/$owner"

  if grep -qE 'Result: PASS \| PARTIAL \| FAIL' "$skill_src"; then
    pass "AC3.1: $skill SKILL.md states the Result line contract"
  else
    fail "AC3.1: $skill SKILL.md has no Result: PASS|PARTIAL|FAIL contract"
  fi

  if grep -qE "references/$owner.*Step Completion Reports|Step Completion Reports.*references/$owner" "$skill_src" \
     || grep -qE "\`references/$owner\`" "$skill_src"; then
    pass "AC3.2: $skill points at references/$owner for the format"
  else
    fail "AC3.2: $skill has no pointer to references/$owner"
  fi

  if grep -qE '^## Step Completion Reports' "$owner_file"; then
    pass "AC3.3: references/$owner owns the Step Completion Reports format"
  else
    fail "AC3.3: references/$owner does not own the format"
  fi

  if grep -q '√' "$owner_file" && grep -q '×' "$owner_file"; then
    pass "AC3.4: $skill's report format uses √/× check glyphs"
  else
    fail "AC3.4: $skill's report format is missing the √/× glyphs"
  fi

  if grep -qE '^### Per-(step|phase) checks' "$owner_file"; then
    pass "AC3.5: $skill enumerates per-step check names"
  else
    fail "AC3.5: $skill has no per-step check table"
  fi
done

if grep -q '`√`' "$REPO_ROOT/docs/terminal-style.md" && grep -q '`×`' "$REPO_ROOT/docs/terminal-style.md"; then
  pass "AC3.6: docs/terminal-style.md defines the √/× check glyphs"
else
  fail "AC3.6: √/× are not in the documented symbol vocabulary"
fi

# ── AC4: creator sync is scoped to real local writes ──────────────────────────
CREATOR_SRC="$SRC/issue-creator/SKILL.source.md"
if grep -qE '^## Repo Sync Before Edits \(mandatory\)' "$CREATOR_SRC"; then
  fail "AC4.1: issue-creator still mandates a repo sync before remote-only edits"
else
  pass "AC4.1: issue-creator no longer mandates a pre-edit repo sync"
fi

# Only *executable* instructions count: a fenced block containing the rebase.
# Prose explaining why the sync is not run is exactly what this AC asked for.
if awk '/^```/ { fence = !fence; next } fence && /git pull --rebase/ { found = 1 } END { exit !found }' "$CREATOR_SRC"; then
  fail "AC4.2: issue-creator still executes a local rebase in a fenced block"
else
  pass "AC4.2: no executable local rebase left in issue-creator"
fi

if grep -qE 'docs/sync-conventions\.md' "$CREATOR_SRC"; then
  pass "AC4.3: the stash-first convention stays reachable for real local writes"
else
  fail "AC4.3: issue-creator dropped the sync convention entirely"
fi

# ── AC5: README location + AI-skip notice ─────────────────────────────────────
for readme in "$SRC"/*/docs/README.md "$REPO_ROOT"/src/internal-skills/*/docs/README.md; do
  [ -f "$readme" ] || continue
  name="$(basename "$(dirname "$(dirname "$readme")")")"
  if head -5 "$readme" | grep -q 'DO NOT READ THIS FILE'; then
    pass "AC5.1: $name docs/README.md carries the AI-skip notice"
  else
    fail "AC5.1: $name docs/README.md is missing the AI-skip notice"
  fi
done

shopt -s nullglob
stragglers=("$SRC"/*/README.md "$REPO_ROOT"/src/internal-skills/*/README.md)
shopt -u nullglob
if [ "${#stragglers[@]}" -eq 0 ]; then
  pass "AC5.2: no skill README left at the skill root"
else
  fail "AC5.2: README still at skill root: ${stragglers[*]}"
fi

# Built packages must ship the README at the same standard location.
for built in "$REPO_ROOT"/skills/*/; do
  name="$(basename "$built")"
  if [ -f "$built/docs/README.md" ]; then
    pass "AC5.3: built skills/$name ships docs/README.md"
  else
    fail "AC5.3: built skills/$name has no docs/README.md"
  fi
done

echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Disclosure-gate tests failed ($PASS passed, $FAIL failed)"
  exit 1
fi
echo "  ✓ All disclosure-gate and step-completion checks passed ($PASS)"
