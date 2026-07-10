#!/usr/bin/env bash
# test-issue-analysis.sh — Validate the /issue-analysis persisted JSON schema
# and view-mode contract (issue #200, epic #182 Phase 2).
#
# This is a documentation/contract test in the same style as
# tests/test-runs-jsonl.sh: it greps the authored src/ sources
# (SKILL.source.md + references/output-and-persist.md) and asserts the
# documented `.gitissue/analysis-<N>.json` schema is internally consistent and
# that the view-mode prerequisites match the corrected contract (#207
# corrected the analysis JSON `summary` key placement and the view-mode
# prerequisites). It does NOT call the GitHub API or run the skill (no network).
#
# Usage: bash tests/test-issue-analysis.sh
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

has() {
  # $1 = file, $2 = pattern, $3 = label
  if grep -qF -e "$2" "$1" 2>/dev/null; then
    pass "$3"
  else
    fail "$3 (missing: '$2' in ${1#$REPO_ROOT/})"
  fi
}

echo "◆ /issue-analysis analysis-<N>.json Tests (issue #200)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

SKILL="$REPO_ROOT/src/skills/issue-analysis/SKILL.source.md"
PERSIST="$REPO_ROOT/src/skills/issue-analysis/references/output-and-persist.md"

# --- T1: both sources exist -------------------------------------------------
if [ -f "$SKILL" ]; then
  pass "T1: issue-analysis SKILL.source.md exists"
else
  fail "T1: issue-analysis SKILL.source.md missing"
fi
if [ -f "$PERSIST" ]; then
  pass "T1: output-and-persist.md reference exists"
else
  fail "T1: output-and-persist.md reference missing"
fi

# --- T2: canonical persistence target (per-issue filename) ------------------
# Both the SKILL and its persist reference name the same per-issue output file.
has "$SKILL"   ".gitissue/analysis-" "T2: SKILL persists to .gitissue/analysis-<N>.json"
has "$PERSIST" ".gitissue/analysis-" "T2: persist reference names .gitissue/analysis-<N>.json"

# --- T3: top-level schema keys ----------------------------------------------
# These live in the schema body + field-reference table (stable contract; not
# illustrative values, so #201 example churn does not touch them).
for key in version timestamp source issue research_status extraction \
           affected_files analysis options recommended_option \
           overall_complexity overall_risk history cross_references \
           scan_stats git_state decision_record; do
  has "$PERSIST" "$key" "T3: schema names top-level key '$key'"
done

# --- T4: analysis.summary key (#207 corrected the summary key) --------------
# The one-paragraph analysis summary lives under `analysis.summary`. Assert
# both the SKILL (which lifts analysis.summary into the decision record) and
# the schema field table define it, so the corrected key placement is pinned.
has "$PERSIST" "analysis.summary" "T4: schema field table defines analysis.summary"
has "$PERSIST" "One-paragraph analysis summary" "T4: schema documents the analysis.summary field"
# The SKILL owns the decision-record lift that reads analysis.summary; the
# field itself is defined in the persist reference (#207 corrected its
# placement there). Assert the SKILL names the `analysis` structure and the
# `root_cause` field it lifts FROM analysis.summary — the stable cross-skill
# contract — rather than re-stating the dotted field path.
has "$SKILL"   "root_cause"       "T4: SKILL documents the root_cause lift (from analysis.summary)"
has "$SKILL"   "\`analysis\`"      "T4: SKILL names the analysis result structure"

# --- T5: decision_record contract (stable five labels) ----------------------
# The five core decision-record fields are string-matched downstream, so their
# names are a stable cross-skill contract. Assert all five in both sources.
for dr in root_cause options_considered options_rejected \
          selected_option residual_risk; do
  has "$PERSIST" "$dr" "T5: schema defines decision_record.$dr"
  has "$SKILL"   "$dr" "T5: SKILL names decision_record field '$dr'"
done

# --- T6: git_state pins the analysis to a commit ----------------------------
for gs in branch commit_sha commit_sha_short captured_at; do
  has "$PERSIST" "$gs" "T6: schema defines git_state.$gs"
done
has "$SKILL" "git_state" "T6: SKILL documents git_state pinning"

# --- T7: view-mode prerequisites (#207 corrected the view-mode contract) ----
# View mode reads ONLY the local cached JSON — no gh, no API calls, no writes.
# These are the corrected prerequisites the test must pin.
has "$SKILL" "view"                  "T7: SKILL documents view mode"
has "$SKILL" "no gh required"        "T7: view mode needs only local file access (no gh)"
has "$SKILL" "skip the entire analysis pipeline" "T7: view mode skips the analysis pipeline"
has "$SKILL" "never writes"          "T7: view mode never writes to the file"
has "$SKILL" "makes API calls"       "T7: view mode makes no API calls"
# View mode re-reads the cached per-issue JSON.
has "$SKILL" "cached analysis"       "T7: view mode renders the cached analysis"

# --- T8: full analysis overwrites the cache silently ------------------------
has "$SKILL" "overwrite it silently" "T8: a fresh full analysis overwrites the cache silently"

echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
else
  echo "  ✓ All tests passed"
  exit 0
fi
