#!/usr/bin/env bash
# test-issue-creator-modes.sh — Validate the /issue-creator normalize, batch,
# and dry-run mode surfaces (issue #200, epic #182 Phase 2).
#
# This is a documentation/contract test in the same style as
# tests/test-runs-jsonl.sh: it greps the authored src/ sources
# (SKILL.source.md + references/modes.md) and asserts the documented behavior
# of the Normalize, Batch, and dry-run surfaces is present and consistent. It
# does NOT call the GitHub API or run the skill (no network).
#
# Scope note: the existing tests/test-issue-creator-confidence-191.sh already
# covers the confidence-marker placeholders and confidence-scoring.md — this
# suite covers the MODE surfaces it does not (invocation table, normalize
# safety steps, batch pipeline, dry-run stop). Batch mode gained optional epic
# support in #198 (`--parent`, `Part of #{parent}`, parent checklist); a few
# assertions confirm that surface exists but stay on STABLE documented
# behavior — no illustrative example values that #201 may churn.
#
# Usage: bash tests/test-issue-creator-modes.sh
# Returns: exit 0 if all tests pass, exit 1 on any failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

has_near() {
  # Proximity assertion: $3 must appear within $4 lines AFTER the first
  # occurrence of anchor $2. Used for the #244 gate carve-outs — a plain
  # whole-file grep would pass on a doc that mentions auto mode somewhere else
  # entirely, which is exactly the bug (a gate with no defined auto behavior).
  # $1 = file, $2 = anchor, $3 = needle, $4 = window (lines), $5 = label
  local f="$1" anchor="$2" needle="$3" win="$4" label="$5" ln
  # `|| true` is required: under `set -euo pipefail` a missing anchor makes
  # grep exit 1, which would kill the whole suite before the check below runs.
  ln="$(grep -nF -e "$anchor" "$f" 2>/dev/null | head -1 | cut -d: -f1 || true)"
  if [ -z "$ln" ]; then
    fail "$label (anchor not found: '$anchor' in ${f#$REPO_ROOT/})"
    return
  fi
  if sed -n "${ln},$((ln + win))p" "$f" | grep -qF -e "$needle"; then
    pass "$label"
  else
    fail "$label (no '$needle' within $win lines of '$anchor' in ${f#$REPO_ROOT/})"
  fi
}

has() {
  # $1 = file, $2 = pattern, $3 = label
  if grep -qF -e "$2" "$1" 2>/dev/null; then
    pass "$3"
  else
    fail "$3 (missing: '$2' in ${1#$REPO_ROOT/})"
  fi
}

echo "◆ /issue-creator mode surfaces Tests (issue #200)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

SKILL="$REPO_ROOT/src/skills/issue-creator/SKILL.source.md"
MODES="$REPO_ROOT/src/skills/issue-creator/references/modes.md"

# --- T1: both sources exist -------------------------------------------------
if [ -f "$SKILL" ]; then
  pass "T1: issue-creator SKILL.source.md exists"
else
  fail "T1: issue-creator SKILL.source.md missing"
fi
if [ -f "$MODES" ]; then
  pass "T1: references/modes.md exists"
else
  fail "T1: references/modes.md missing"
fi

# --- T2: the three modes are declared ---------------------------------------
# The SKILL front-matter/body names Create, Normalize, and Batch.
has "$SKILL" "Create"    "T2: SKILL declares Create mode"
has "$SKILL" "Normalize" "T2: SKILL declares Normalize mode"
has "$SKILL" "Batch"     "T2: SKILL declares Batch mode"

# --- T3: mode-detection / invocation table ----------------------------------
# A bare number → Normalize; multi-item text → Batch; a number is NEVER a
# parent (that guards the #198 epic surface against mis-routing).
has "$SKILL" "/issue-creator <N>"             "T3: invocation table has bare-N normalize"
has "$SKILL" "/issue-creator <N> --dry-run"   "T3: invocation table has --dry-run preview"
has "$SKILL" "argument is a number → Normalize" "T3: mode detection routes a number to Normalize"

# --- T4: Normalize mode documented behavior (modes.md) ----------------------
# Idempotency marker, security-label skip, backup-before-edit safety, and the
# normalized marker are the stable documented contract of Normalize mode.
has "$MODES" "gitissue:normalized v1"          "T4: normalize checks/writes the normalized marker"
has "$MODES" "already normalized"              "T4: normalize is idempotent (already-normalized skip)"
has "$MODES" "security label"                  "T4: normalize skips security-labeled issues"
has "$MODES" "Backup Original Body"            "T4: normalize backs up the original body before edit"
has "$MODES" "Reporter Context"                "T4: normalize preserves original text in Reporter Context"

# --- T5: dry-run surface -----------------------------------------------------
# --dry-run (or the [Y/n/dry-run] prompt selection) previews and stops without
# applying any change. This is the documented no-mutation guarantee.
has "$SKILL" "--dry-run"                        "T5: SKILL documents the --dry-run flag"
has "$MODES" "Dry Run Check"                    "T5: modes.md has a Dry Run Check step"
has "$MODES" "Dry run complete. No changes applied." "T5: dry-run stops with no changes applied"

# --- T6: Batch mode pipeline (modes.md) -------------------------------------
# Detect items → preview → duplicate check → approval → create sequentially,
# with per-item success/failure tracking. Stable documented pipeline.
has "$MODES" "Batch Create"                     "T6: modes.md documents Batch Create mode"
has "$MODES" "Detect Items"                     "T6: batch detects distinct items"
has "$MODES" "Preview Table"                    "T6: batch previews parsed items before creating"
has "$MODES" "Duplicate Check"                  "T6: batch runs a duplicate check"
has "$MODES" "fall through to single Create mode" "T6: single-item batch falls back to Create"
has "$MODES" "Partial failure"                  "T6: batch tracks per-item partial failure"

# --- T7: Batch epic surface (#198 — additive, do not over-assert values) ----
# Confirm the epic-binding surface EXISTS without pinning illustrative numbers.
has "$SKILL" "--parent <N>"                     "T7: SKILL documents the --parent epic flag"
has "$MODES" "Part of #{parent}"                "T7: batch appends the Part of #{parent} child marker"
has "$MODES" "Epic Binding"                     "T7: modes.md has the optional Epic Binding step"
# Additive guarantee: a batch without --parent behaves as before.
has "$MODES" "without a parent"                 "T7: epic step is skipped when no parent is bound"

# --- T8: reporter-text-as-untrusted-data boundary ---------------------------
# Normalize/Batch treat issue bodies + pasted docs as data, never instructions.
has "$SKILL" "untrusted data"                   "T8: SKILL declares reporter text is untrusted data"

# --- T9: auto-mode carve-outs at every interactive gate (#244) --------------
# Every interactive gate must have a DEFINED non-interactive behavior stated AT
# the gate, citing the single authoritative convention doc rather than
# restating detection logic per gate. Interactive prompts must stay unchanged.
AUTOMODE="$REPO_ROOT/docs/auto-mode.md"

# T9.0 — the one authoritative place exists and defines detection + the rule.
if [ -f "$AUTOMODE" ]; then
  pass "T9.0: docs/auto-mode.md (single authoritative convention) exists"
else
  fail "T9.0: docs/auto-mode.md missing"
fi
has "$AUTOMODE" '`--auto` flag'           "T9.0: auto-mode doc defines the --auto signal"
has "$AUTOMODE" "IDD_AUTO_MODE=1"          "T9.0: auto-mode doc defines the IDD_AUTO_MODE=1 signal"
has "$AUTOMODE" "caller provenance"         "T9.0: doc rules on caller-provenance detection"
has "$AUTOMODE" "Never block."             "T9.0: auto-mode doc states gates must never block"

# T9.1 — the skill exposes the flag, cites the doc, and bundles it.
has "$SKILL" "--auto"                       "T9.1: SKILL documents the --auto modifier"
has "$SKILL" "docs/auto-mode.md"            "T9.1: SKILL cites the authoritative auto-mode doc"
has "$SKILL" "references/docs/auto-mode.md" "T9.1: auto-mode doc is in the precheck list"

# T9.2 — gate 1: duplicate warning (SKILL Step 3).
has_near "$SKILL" "Continue creating? [Y/n]" "Auto mode" 20 \
  "T9.2: duplicate-warning gate has an auto-mode carve-out"
has_near "$SKILL" "Continue creating? [Y/n]" \
  "⚠ Auto mode: duplicate confirmation skipped" 20 \
  "T9.2: duplicate carve-out logs a ⚠ naming the suspected duplicate"

# T9.3 — gate 2: create preview confirmation (SKILL Step 5).
has_near "$SKILL" "Create issue? [Y/n]" "Auto mode" 25 \
  "T9.3: create-preview gate has an auto-mode carve-out"
has_near "$SKILL" "Create issue? [Y/n]" \
  "⚠ Auto mode: create confirmation skipped" 25 \
  "T9.3: create-preview carve-out auto-approves and logs a ⚠"

# T9.4 — gate 3: batch approval (modes.md Step 4).
# Window must stop short of Step 4.5, whose epic-offer guard also says
# "⚠ Auto mode: …". At 30 this assertion stayed GREEN when the batch carve-out
# was deleted — the epic offer slid into the window and satisfied it, so the
# assertion did not test what its label claims. 15 reaches the batch carve-out
# and nothing past it.
has_near "$MODES" "[A]ll / [e]dit / [c]ancel" "Auto mode" 15 \
  "T9.4: batch approval gate has an auto-mode carve-out"
has "$MODES" "issues auto-approved and created" \
  "T9.4: batch carve-out logs how many issues were auto-approved"
has "$MODES" "Never take \`[e]dit\` or \`[c]ancel\` in auto mode" \
  "T9.4: batch auto path rules out [e]dit / [c]ancel"

# T9.5 — gate 4: normalize apply (modes.md Step 6) — the auto-pilot deadlock.
has_near "$MODES" "Apply normalization? [Y/n/dry-run]" "Auto mode" 25 \
  "T9.5: normalize apply gate has an auto-mode carve-out"
has_near "$MODES" "Apply normalization? [Y/n/dry-run]" "never \`dry-run\`" 25 \
  "T9.5: normalize auto path always applies (never dry-run)"
has "$MODES" "backup remains mandatory" \
  "T9.5: auto-apply does not weaken the mandatory backup safety stop"

# T9.6 — interactive behavior unchanged (#244 AC4). Anchor on the DISPLAY BLOCK
# that precedes each prompt, not on the prompt string itself: every prompt now
# also appears quoted inside its own carve-out ("Do not show the `…` prompt"),
# so a bare whole-file grep would stay green even if the interactive gate were
# deleted. Anchoring on the block header proves the prompt still lives in the
# interactive flow.
# Windows are deliberately TIGHT — just past the prompt, stopping short of the
# carve-out paragraph that quotes the same prompt string. A looser window is
# satisfied by that quote alone and stays green when the real prompt is
# deleted, which is the regression these assertions exist to catch.
has_near "$SKILL" "⚠ Possible duplicate:" "Continue creating? [Y/n]" 5 \
  "T9.6: interactive duplicate prompt still in its warning block"
has_near "$SKILL" "◆ Issue Preview" "Create issue? [Y/n]" 12 \
  "T9.6: interactive create prompt still in the preview block"
has_near "$MODES" "◆ Normalization Preview" "Apply normalization? [Y/n/dry-run]" 10 \
  "T9.6: interactive normalize prompt still in the preview block"
has "$MODES" "Create 3 issues? [A]ll / [e]dit / [c]ancel" \
  "T9.6: interactive batch prompt unchanged"
# The batch gate displays TWICE — once up front, once after an [e]dit round.
# The re-prompt needs its own guard or deleting it leaves the suite green.
has_near "$MODES" "show the approval prompt again" \
  "Create {N} issues? [A]ll / [e]dit / [c]ancel" 4 \
  "T9.6: interactive batch re-prompt after [e]dit unchanged"
# The declined paths must survive too — auto mode adds a branch, it never
# removes the interactive one.
has "$SKILL" "If declined, stop without creating." "T9.6: interactive decline still stops"
has "$MODES" "\`n\` → stop."                       "T9.6: interactive normalize decline still stops"

# T9.7 — the SKILL claims EVERY gate has a defined non-interactive behavior;
# pin the two pre-existing guards that claim depends on, so deleting one makes
# the claim false AND fails here.
MODELSUG="$REPO_ROOT/src/skills/issue-creator/references/model-suggestion.md"
has "$MODES" "Non-interactive contexts never block" \
  "T9.7: batch epic offer keeps its non-interactive guard"
has "$MODELSUG" "never prompt" \
  "T9.7: model-cache refresh keeps its non-interactive guard"

echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
else
  echo "  ✓ All tests passed"
  exit 0
fi
