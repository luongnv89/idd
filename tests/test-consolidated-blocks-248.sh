#!/usr/bin/env bash
# test-consolidated-blocks-248.sh — guard issue #248's single-home consolidation.
#
# #248 gave each duplicated instruction block exactly one authoritative home and
# reduced every other occurrence to a one-line pointer. These assertions fail if
# a future edit re-introduces a second copy of one of those rules.
#
# Covers:
#   AC1 — each consolidated rule is stated once; other occurrences are pointers
#   AC2 — UI-review mechanics live in one shared doc bundled into BOTH
#         issue-resolver and issue-pr-review

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT" || exit 1

PASSED=0
FAILED=0

pass() { printf '  ✓ %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf '  ✗ %s\n' "$1"; FAILED=$((FAILED + 1)); }

# count_matches <pattern> <file...> — total matching lines across files
count_matches() {
  local pattern="$1"; shift
  grep -c -E "$pattern" "$@" 2>/dev/null | awk -F: '{ s += $NF } END { print s + 0 }'
}

# count_flat <pattern> <file...> — occurrences of a pattern with newlines
# collapsed to single spaces, so hard-wrapped prose still matches.
count_flat() {
  local pattern="$1"; shift
  local total=0 f n
  for f in "$@"; do
    n=$(tr '\n' ' ' < "$f" | tr -s ' ' | grep -o -E "$pattern" | wc -l | tr -d ' ')
    total=$((total + n))
  done
  printf '%s\n' "$total"
}

# has_flat <pattern> <file> — pattern present after newline flattening
has_flat() {
  tr '\n' ' ' < "$2" | tr -s ' ' | grep -q -E "$1"
}

SHARED_UI="docs/ui-review.md"
RESOLVER_SKILL="src/skills/issue-resolver/SKILL.source.md"
. "$(cd "$(dirname "$0")" && pwd)/lib/spec.bash"  # spec_concat — split reference specs read as one file (#323)
RESOLVER_PIPELINE="$(spec_concat "src/skills/issue-resolver/references/pipeline-steps.md")"
PR_SKILL="src/skills/issue-pr-review/SKILL.source.md"
PR_UI="src/skills/issue-pr-review/references/ui-review-mechanics.md"
PR_PREPASS="src/skills/issue-pr-review/references/prepass-tests-ci-mechanics.md"
AP_SKILL="src/skills/auto-pilot/SKILL.source.md"
AP_PHASES="$(spec_concat "src/skills/auto-pilot/references/phases.md")"
AP_CONFIG="src/skills/auto-pilot/references/configuration.md"
AP_LIST="src/skills/auto-pilot/references/explicit-list-mode.md"
CREATOR_SKILL="src/skills/issue-creator/SKILL.source.md"
CREATOR_MODEL="src/skills/issue-creator/references/model-suggestion.md"
TRIAGE_SKILL="src/skills/issue-triage/SKILL.source.md"
EFFORT_DOC="docs/agent-model-effort.md"

printf '◆ #248 — consolidated instruction blocks\n'
printf '┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n'

# ───────────────────────────────────────────────────────────
# T1 (AC2): shared UI-review doc exists and is the single home
# ───────────────────────────────────────────────────────────
if [ -f "$SHARED_UI" ]; then
  pass "T1.1: shared UI-review doc exists at $SHARED_UI"
else
  fail "T1.1: missing shared UI-review doc $SHARED_UI"
fi

# The headless display-environment probe is the most-copied UI snippet.
# It must appear exactly once across the whole src/ + docs/ tree: in the
# shared doc only.
ui_env_homes=$(count_matches 'ui_env="no-GUI server"' "$SHARED_UI" \
  "$RESOLVER_PIPELINE" "$PR_UI" "$RESOLVER_SKILL" "$PR_SKILL")
if [ "$ui_env_homes" -eq 1 ]; then
  pass "T1.2: display-environment probe stated once (shared doc only)"
else
  fail "T1.2: display-environment probe appears $ui_env_homes times — expected 1"
fi

# The UI keyword list is the other large duplicate.
kw_homes=$(count_matches 'dark mode.*button.*form' "$SHARED_UI" \
  "$RESOLVER_PIPELINE" "$PR_UI")
if [ "$kw_homes" -eq 1 ]; then
  pass "T1.3: UI keyword list stated once (shared doc only)"
else
  fail "T1.3: UI keyword list appears $kw_homes times — expected 1"
fi

# Both consuming skills must point at the shared doc.
for f in "$RESOLVER_PIPELINE" "$PR_UI"; do
  if grep -qF 'docs/ui-review.md' "$f"; then
    pass "T1.4: $(basename "$(dirname "$(dirname "$f")")")/$(basename "$f") points to the shared UI doc"
  else
    fail "T1.4: $f does not point to docs/ui-review.md"
  fi
done

# Skill-specific deltas must NOT move into the shared doc.
if ! grep -qF 'gh pr diff' "$SHARED_UI" && ! grep -qF 'resolve.ui_review' "$SHARED_UI"; then
  pass "T1.5: shared UI doc stays skill-agnostic (no per-skill diff cmd or config key)"
else
  fail "T1.5: shared UI doc leaked a per-skill delta"
fi

# ───────────────────────────────────────────────────────────
# T2 (AC2): the shared doc is bundled into BOTH skills
# ───────────────────────────────────────────────────────────
for skill in issue-resolver issue-pr-review; do
  if [ -f "skills/$skill/references/docs/ui-review.md" ]; then
    pass "T2.1: ui-review.md bundled into skills/$skill/references/docs/"
  else
    fail "T2.1: ui-review.md NOT bundled into skills/$skill — run ./scripts/build.sh"
  fi
done

for f in "$RESOLVER_SKILL" "$PR_SKILL"; do
  if grep -qF 'references/docs/ui-review.md' "$f"; then
    pass "T2.2: $(basename "$(dirname "$f")") precheck list includes references/docs/ui-review.md"
  else
    fail "T2.2: $f precheck list missing references/docs/ui-review.md"
  fi
done

# ───────────────────────────────────────────────────────────
# T3 (AC1): auto-pilot mode resolution has one home (SKILL.md)
# ───────────────────────────────────────────────────────────
if grep -qF 'Resolution rules' "$AP_SKILL"; then
  pass "T3.1: auto-pilot SKILL.md holds the mode *Resolution rules*"
else
  fail "T3.1: auto-pilot SKILL.md lost the mode *Resolution rules* home"
fi

# The legacy auto_merge → aggressive/conservative mapping must be spelled out
# only in SKILL.md; references point at it.
legacy_homes=$(count_matches 'auto_merge: true.*aggressive|auto_merge`?: `?true`? (→|≈) ?`?aggressive' \
  "$AP_SKILL" "$AP_PHASES" "$AP_CONFIG")
if [ "$legacy_homes" -eq 1 ]; then
  pass "T3.2: legacy auto_merge mapping stated exactly once"
else
  fail "T3.2: legacy auto_merge mapping appears $legacy_homes times — expected exactly 1"
fi

for f in "$AP_PHASES" "$AP_CONFIG"; do
  if grep -qF 'Merge Modes' "$f"; then
    pass "T3.3: $(basename "$f") points to *Merge Modes* in SKILL.md"
  else
    fail "T3.3: $(basename "$f") does not point to *Merge Modes*"
  fi
done

# ───────────────────────────────────────────────────────────
# T4 (AC1): --review-only has one authoritative home
# ───────────────────────────────────────────────────────────
if grep -qF 'Review-only mode (`--review-only`) — authoritative definition' "$PR_SKILL"; then
  pass "T4.1: issue-pr-review SKILL.md declares the --review-only home"
else
  fail "T4.1: issue-pr-review SKILL.md missing the authoritative --review-only definition"
fi

# The detection-only tool-flag detail belongs to that home only.
detect_homes=$(count_matches 'without .--fix.*--write|check mode' "$PR_SKILL" "$PR_PREPASS")
if [ "$detect_homes" -eq 1 ]; then
  pass "T4.2: --review-only detection-only detail stated exactly once"
else
  fail "T4.2: --review-only detection-only detail appears $detect_homes times — expected exactly 1"
fi

if grep -qF 'Review-only mode' "$PR_PREPASS"; then
  pass "T4.3: prepass mechanics point back to *Review-only mode*"
else
  fail "T4.3: prepass mechanics lost the pointer to *Review-only mode*"
fi

# ───────────────────────────────────────────────────────────
# T5 (AC1): batch run-log fan-out compressed but rule-complete
# ───────────────────────────────────────────────────────────
fanout_len=$(awk '/^#### Run-log fan-out for the batch/{f=1} f{n++} f&&/^For non-batched issues/{print n; exit}' "$AP_LIST")
if [ -n "$fanout_len" ] && [ "$fanout_len" -lt 60 ]; then
  pass "T5.1: fan-out section compressed to $fanout_len lines (was 86)"
else
  fail "T5.1: fan-out section is ${fanout_len:-?} lines — expected under 60"
fi

# Every rule the 86-line prose encoded must survive the compression.
declare -a FANOUT_RULES=(
  'attempted set'
  'never'
  'issues_resolved'
  'individual retry'
  'zero'
  'qa_cycles'
  'duration_s'
  'writes no run-log line'
)
missing_rule=0
for r in "${FANOUT_RULES[@]}"; do
  grep -qF "$r" "$AP_LIST" || { fail "T5.2: fan-out lost rule token '$r'"; missing_rule=1; }
done
[ "$missing_rule" -eq 0 ] && pass "T5.2: all fan-out rule tokens survive the compression"

if grep -qE '^\| Disposition of an attempted issue' "$AP_LIST"; then
  pass "T5.3: fan-out uses a disposition table as its single home"
else
  fail "T5.3: fan-out disposition table missing"
fi

# ───────────────────────────────────────────────────────────
# T6 (AC1): two-model rendering rule has one home
# ───────────────────────────────────────────────────────────
if grep -qF 'two-model rendering rule (single home)' "$CREATOR_MODEL"; then
  pass "T6.1: model-suggestion.md declares the two-model rendering home"
else
  fail "T6.1: model-suggestion.md missing the two-model rendering home marker"
fi

two_model_homes=$(count_flat 'one OpenAI model and one Anthropic model' \
  "$CREATOR_SKILL" "$CREATOR_MODEL")
if [ "$two_model_homes" -eq 1 ]; then
  pass "T6.2: two-model rule stated once (model-suggestion.md only)"
else
  fail "T6.2: two-model rule appears $two_model_homes times — expected 1"
fi

pointer_count=$(count_flat 'two-model rendering rule' "$CREATOR_SKILL")
if [ "$pointer_count" -ge 3 ]; then
  pass "T6.3: SKILL.md's $pointer_count mentions are all pointers to that home"
else
  fail "T6.3: expected >=3 pointers in SKILL.md, found $pointer_count"
fi

# ───────────────────────────────────────────────────────────
# T7 (AC1): resolver light-profile collapse list has one home
# ───────────────────────────────────────────────────────────
if grep -qF 'What `light` collapses — the single home for this rule' "$RESOLVER_SKILL"; then
  pass "T7.1: resolver Step 0g declares the light-profile home"
else
  fail "T7.1: resolver Step 0g missing the light-profile home marker"
fi

# Per-step blocks must be pointers, not restatements.
if [ "$(count_flat 'profile table in \*Step 0g\*' "$RESOLVER_SKILL")" -ge 4 ]; then
  pass "T7.2: per-step light blocks point back to the Step 0g table"
else
  fail "T7.2: fewer than 4 per-step pointers to the Step 0g profile table"
fi

# The shared doc must not restate any skill's per-step collapse list.
if has_flat 'do not restate any skill' "$EFFORT_DOC" \
   && ! grep -qE 'skips the 3-option synthesis|caps QA at' "$EFFORT_DOC"; then
  pass "T7.3: agent-model-effort.md defers per-step collapse lists to each skill"
else
  fail "T7.3: agent-model-effort.md still restates a skill's per-step collapse list"
fi

# ───────────────────────────────────────────────────────────
# T8 (AC1): triage cached-view rendering has one home
# ───────────────────────────────────────────────────────────
triage_tables=$(count_matches '───┼────' "$TRIAGE_SKILL")
if [ "$triage_tables" -eq 1 ]; then
  pass "T8.1: cached triage table rendered once in SKILL.md"
else
  fail "T8.1: cached triage table rendered $triage_tables times — expected 1"
fi

if grep -qF 'Render the cached report' "$TRIAGE_SKILL"; then
  pass "T8.2: *Step 3 — Render the cached report* is the rendering home"
else
  fail "T8.2: triage lost its cached-render home section"
fi

# ───────────────────────────────────────────────────────────
# T9 (AC3): no skill regressed past the 500-line cap
# ───────────────────────────────────────────────────────────
over=0
for f in src/skills/*/SKILL.source.md skills/*/SKILL.md; do
  n=$(wc -l < "$f")
  if [ "$n" -gt 500 ]; then
    fail "T9: $f is $n lines (cap 500)"
    over=1
  fi
done
[ "$over" -eq 0 ] && pass "T9: every source and built SKILL.md stays within the 500-line cap"

printf '\n┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n'
printf '  Results: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
