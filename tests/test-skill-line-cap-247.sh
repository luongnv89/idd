#!/usr/bin/env bash
# test-skill-line-cap-247.sh — Enforce the skill-creator 500-line SKILL.md cap (issue #247)
#
# Acceptance criteria:
#  - Every built skills/<name>/SKILL.md is ≤ 500 lines (skill-creator standard)
#  - issue-resolver specifically, which regressed to 598 lines, stays under the cap
#  - Material moved out of issue-resolver's SKILL.md is still reachable via a
#    one-line pointer to the reference file that now owns it
#
# Usage: bash tests/test-skill-line-cap-247.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
CAP=500

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ SKILL.md Line-Cap Tests (issue #247)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ── T1: every built SKILL.md is within the cap ────────────────────────────────
shopt -s nullglob
built_any=0
for skill_md in "$REPO_ROOT"/skills/*/SKILL.md; do
  built_any=1
  name="$(basename "$(dirname "$skill_md")")"
  lines=$(wc -l < "$skill_md" | tr -d ' ')
  if [ "$lines" -le "$CAP" ]; then
    pass "T1: skills/$name/SKILL.md within cap ($lines ≤ $CAP lines)"
  else
    fail "T1: skills/$name/SKILL.md exceeds cap ($lines > $CAP lines) — move non-universal material into references/ behind a one-line pointer"
  fi
done
shopt -u nullglob

if [ "$built_any" -eq 0 ]; then
  fail "T1: no built skills/*/SKILL.md found — run ./scripts/build.sh first"
fi

# ── T2: the source the build compiles from is within the cap too ──────────────
for source_md in "$REPO_ROOT"/src/skills/*/SKILL.source.md "$REPO_ROOT"/src/internal-skills/*/SKILL.source.md; do
  [ -f "$source_md" ] || continue
  name="$(basename "$(dirname "$source_md")")"
  lines=$(wc -l < "$source_md" | tr -d ' ')
  if [ "$lines" -le "$CAP" ]; then
    pass "T2: $name SKILL.source.md within cap ($lines ≤ $CAP lines)"
  else
    fail "T2: $name SKILL.source.md exceeds cap ($lines > $CAP lines)"
  fi
done

# ── T3: issue-resolver — the regression this test was written for ─────────────
RESOLVER_BUILT="$REPO_ROOT/skills/issue-resolver/SKILL.md"
if [ -f "$RESOLVER_BUILT" ]; then
  lines=$(wc -l < "$RESOLVER_BUILT" | tr -d ' ')
  if [ "$lines" -le "$CAP" ]; then
    pass "T3.1: issue-resolver built SKILL.md is $lines lines (was 598 before #247)"
  else
    fail "T3.1: issue-resolver built SKILL.md regressed to $lines lines"
  fi
else
  fail "T3.1: skills/issue-resolver/SKILL.md missing — run ./scripts/build.sh"
fi

# ── T4: moved material stays reachable via a one-line pointer ─────────────────
# Each entry is "<label>|<pointer regex in SKILL.source.md>|<file that must own it>|<heading regex in that file>"
RESOLVER_SRC="$REPO_ROOT/src/skills/issue-resolver/SKILL.source.md"
RESOLVER_REFS="$REPO_ROOT/src/skills/issue-resolver/references"

check_pointer() {
  local label="$1" pointer="$2" owner="$3" heading="$4"
  if ! grep -qE "$pointer" "$RESOLVER_SRC"; then
    fail "T4: $label — SKILL.source.md lost its pointer (/$pointer/)"
    return
  fi
  if ! grep -qE "$heading" "$RESOLVER_REFS/$owner"; then
    fail "T4: $label — references/$owner does not own it (/$heading/)"
    return
  fi
  pass "T4: $label — pointer in SKILL.md, content in references/$owner"
}

check_pointer "run-log field derivation + suppression rule" \
  'references/report-templates\.md.*Run-log entry' \
  "report-templates.md" \
  '^## Run-log entry — field derivation and suppression'

check_pointer "missing-bundled-dependency error block" \
  'Missing bundled dependency.*references/error-messages\.md' \
  "error-messages.md" \
  '^### Missing bundled dependency'

check_pointer "PR-already-targets-issue guard block" \
  'PR already targets issue.*references/error-messages\.md' \
  "error-messages.md" \
  '^### PR already targets issue'

check_pointer "security-label skip warning" \
  'Skipping auto-normalization.*references/error-messages\.md' \
  "error-messages.md" \
  '^### Security-labeled issue \(skip\)'

check_pointer "expected inline pipeline output" \
  'references/report-templates\.md.*Expected Inline Pipeline Output' \
  "report-templates.md" \
  '^## Expected Inline Pipeline Output'

check_pointer "propose-relevant-skills procedure" \
  'references/pipeline-steps\.md.*Step 3 — Propose relevant skills' \
  "pipeline-steps.md" \
  'Propose relevant skills'

# The stash-first sync snippet moved to the bundled runtime doc, not a reference.
if grep -qE 'docs/sync-conventions\.md.*Quick Reference' "$RESOLVER_SRC"; then
  pass "T4: stash-first sync snippet — pointer in SKILL.md, content in docs/sync-conventions.md"
else
  fail "T4: stash-first sync snippet — SKILL.source.md lost its sync-conventions pointer"
fi

echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ SKILL.md line-cap tests failed ($PASS passed, $FAIL failed)"
  exit 1
fi
echo "  ✓ All SKILL.md line-cap checks passed ($PASS)"
