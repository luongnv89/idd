#!/usr/bin/env bash
# test-issue-constraints-557.sh — an optional Constraints section in the issue
# contract (issue #557, spec 1.2).
#
# An issue may state its boundaries — non-goals, invariants, non-functional
# limits — in `## Constraints`, after the Acceptance Criteria. The section is
# optional, so every issue normalized before it existed stays valid under the
# unchanged `v1` marker. /issue-creator fills it only from what the reporter
# said, and the code reviewer reports a diff that touches a stated invariant.
#
#   T1  idd-lint (behavioural): a v1 body without the section passes silently;
#       one with it passes and reports I10; malformed sections warn, never fail;
#   T2  gi-ready.py (behavioural): the criteria still end at the next heading
#       when Constraints follows them, and a constraint never counts as one;
#   T3  the spec, templates, creator rule and reviewer rule (prose pins);
#   T4  the built bundles carry them;
#   T5  the CI step exists.
#
# Usage: bash tests/test-issue-constraints-557.sh
# Returns: exit 0 if all checks pass, exit 1 on failure
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/scripts/idd-lint.py"
READY="$ROOT/src/shared/scripts/gi-ready.py"
SPEC="$ROOT/SPEC.md"
IC="$ROOT/src/skills/issue-creator"
REVIEWER="$ROOT/src/shared/agents/code-reviewer.md"
QA="$ROOT/src/skills/issue-resolver/references/steps/step-4-qa.md"
LOOP="$ROOT/src/skills/issue-pr-review/references/review-loop-mechanics.md"
WORKFLOW="$ROOT/.github/workflows/dist-check.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
has() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3"; }

echo "◆ Issue Constraints section (#557)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

for f in "$LINT" "$READY" "$SPEC" "$REVIEWER" "$QA" "$LOOP" "$WORKFLOW"; do
  [ -f "$f" ] || { echo "  ✗ missing $f"; exit 1; }
done

# A body normalized before spec 1.2: no Constraints section.
cat > "$TMP/legacy.md" <<'EOF'
<!-- idd:normalized v1 -->

## Type

feature (high confidence)

## Description

Users can download the reports table as a CSV file.

> **Reporter Context**
> Add CSV export to the reports page.

## Acceptance Criteria

- [ ] The reports page offers a CSV download (high confidence)
- [ ] The CSV holds one row per report (medium confidence)

## Metadata

**Priority:** P2 (medium confidence)
**Effort:** S (medium confidence)
**Labels:** feature (medium confidence)
EOF

# with_constraints <items> — the legacy body with a Constraints section
# inserted between the Acceptance Criteria and the Metadata.
with_constraints() {
  python3 - "$TMP/legacy.md" "$1" <<'PY'
import sys
body = open(sys.argv[1]).read()
print(body.replace("\n## Metadata\n", "\n## Constraints\n\n" + sys.argv[2] + "\n\n## Metadata\n"), end="")
PY
}

with_constraints '- **Invariant:** The existing JSON API does not change (high confidence)
- **Limit:** An export of 10,000 rows finishes in under 5 seconds (high confidence)
- **Non-goal:** PDF export (needs review)' > "$TMP/constraints.md"
with_constraints 'None stated.' > "$TMP/empty.md"
with_constraints '- [ ] **Invariant:** The JSON API does not change' > "$TMP/checkbox.md"
with_constraints '- The JSON API does not change' > "$TMP/unlabelled.md"

# lint <file> — prints "exit|output"
lint() {
  local out ec=0
  out="$(python3 "$LINT" issue "$1" 2>&1)" || ec=$?
  printf '%s|%s' "$ec" "$out"
}

# ── T1: idd-lint ──────────────────────────────────────────────────────────
r="$(lint "$TMP/legacy.md")"
[ "${r%%|*}" = 0 ] && pass "T1.1: a v1 body without Constraints still passes" \
  || fail "T1.1: a v1 body without Constraints still passes (${r%%|*})"
case "$r" in *I10*) fail "T1.2: an absent section reports nothing" ;;
  *) pass "T1.2: an absent section reports nothing" ;; esac
case "$r" in *"spec v1.2"*) pass "T1.3: idd-lint reports spec v1.2" ;;
  *) fail "T1.3: idd-lint reports spec v1.2" ;; esac

r="$(lint "$TMP/constraints.md")"
[ "${r%%|*}" = 0 ] && pass "T1.4: a body with Constraints after the criteria passes" \
  || fail "T1.4: a body with Constraints after the criteria passes (${r%%|*})"
case "$r" in *"[I10] constraints present (3 items)"*) pass "T1.5: I10 counts the stated constraints" ;;
  *) fail "T1.5: I10 counts the stated constraints" ;; esac
case "$r" in *"Warnings: 0"*) pass "T1.6: labelled items raise no warning" ;;
  *) fail "T1.6: labelled items raise no warning" ;; esac

for kind in empty checkbox unlabelled; do
  r="$(lint "$TMP/$kind.md")"
  if [ "${r%%|*}" = 0 ] && printf '%s' "$r" | grep -q '⚠ \[I10\]'; then
    pass "T1.7: the $kind section warns (I10) without failing"
  else
    fail "T1.7: the $kind section warns (I10) without failing"
  fi
done

# The spec's rendered sample (no Constraints section) still passes.
awk '/<!-- idd:normalized/{found=1} found' "$ROOT/docs/sample-normalized-issue.md" > "$TMP/sample.md"
r="$(lint "$TMP/sample.md")"
[ "${r%%|*}" = 0 ] && pass "T1.8: docs/sample-normalized-issue.md still passes" \
  || fail "T1.8: docs/sample-normalized-issue.md still passes"

# ── T2: gi-ready.py ───────────────────────────────────────────────────────
# ready_json <file> [flag] — gi-ready on the body as an issue object
ready_json() {
  python3 -c 'import json,sys; print(json.dumps({"number": 7, "body": open(sys.argv[1]).read()}))' "$1" \
    | python3 "$READY" ${2:-}
}
got="$(ready_json "$TMP/constraints.md" --criteria | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(len(d["criteria"]), "|".join(c["text"] for c in d["criteria"]))')"
want="2 The reports page offers a CSV download (high confidence)|The CSV holds one row per report (medium confidence)"
[ "$got" = "$want" ] && pass "T2.1: --criteria stops at the Constraints heading" \
  || fail "T2.1: --criteria stops at the Constraints heading (got: $got)"

got="$(ready_json "$TMP/constraints.md" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(str(d["ready"]).lower() + "|" + ",".join(d["reasons"]))')"
[ "$got" = "true|" ] && pass "T2.2: a constraint marked (needs review) is not a criterion" \
  || fail "T2.2: a constraint marked (needs review) is not a criterion (got: $got)"

# ── T3: prose pins ────────────────────────────────────────────────────────
has "$SPEC" "- **Spec version:** 1.2" "T3.1: SPEC is version 1.2"
has "$SPEC" "- **Marker version:** \`v1\`" "T3.2: the normalization marker stays v1"
has "$SPEC" "7. **\`## Constraints\`** — optional; omit when the reporter stated none." "T3.3: SPEC §1.1 defines the optional section"
has "$SPEC" "A tool MUST NOT add a constraint the reporter did not state." "T3.4: SPEC §1.2 bars an invented constraint"
has "$SPEC" "issues without it remain conforming" "T3.5: the changelog line keeps old issues valid"
grep -q '^SPEC_VERSION = "1.2"$' "$LINT" && pass "T3.6: idd-lint SPEC_VERSION is 1.2" \
  || fail "T3.6: idd-lint SPEC_VERSION is 1.2"
for t in bug feature improvement; do
  order="$(grep -n '^## ' "$IC/templates/$t.md" | cut -d: -f2- | tr '\n' ',')"
  case "$order" in
    *"## Acceptance Criteria,## Constraints,## Metadata,"*) pass "T3.7: $t template places Constraints between criteria and metadata" ;;
    *) fail "T3.7: $t template places Constraints between criteria and metadata ($order)" ;;
  esac
  has "$IC/templates/$t.md" "{constraints}" "T3.8: $t template declares {constraints}"
done
has "$IC/SKILL.source.md" "6. **Constraints** — only non-goals, invariants and non-functional limits the reporter stated" "T3.9: the creator fills it only from the reporter"
has "$IC/SKILL.source.md" "item each with its confidence; never inferred. None stated: omit the section" "T3.10: each item is confidence-marked, and an empty section is omitted"
has "$IC/references/modes.md" "constraints per Create Step 4 item 6" "T3.10b: Normalize mode applies the same Constraints rule"
has "$IC/references/confidence-scoring.md" "| **Constraints** | high = the reporter's words" "T3.11: confidence-scoring has a Constraints row"
has "$REVIEWER" "**Stated constraints** (category \`constraints\`)" "T3.12: the reviewer checks stated constraints"
has "$REVIEWER" "is always reported, at any confidence" "T3.13: an invariant touch is never dropped by the threshold"
has "$REVIEWER" "edge_cases|constraints" "T3.14: the output shape carries the constraints category"
has "$QA" "plus the issue's \`## Constraints\` section verbatim" "T3.15: the resolver's reviewer gets the issue's Constraints"
has "$LOOP" "plus the linked issue's \`## Constraints\` section, verbatim" "T3.16: the PR reviewer gets the issue's Constraints"

# ── T4: built bundles ─────────────────────────────────────────────────────
has "$ROOT/skills/issue-creator/templates/feature.md" "## Constraints" "T4.1: the built creator template carries the section"
has "$ROOT/skills/issue-creator/SKILL.md" "6. **Constraints** —" "T4.2: the built creator skill carries the fill rule"
has "$ROOT/skills/issue-creator/references/modes.md" "constraints per Create Step 4 item 6" "T4.2b: the built creator bundle carries the Normalize rule"
for s in issue-resolver issue-pr-review; do
  has "$ROOT/skills/$s/references/agents/code-reviewer.md" "**Stated constraints**" "T4.3: $s bundles the reviewer rule"
done
has "$ROOT/.pi/agents/code-reviewer.md" "**Stated constraints**" "T4.4: the pi agent carries the reviewer rule"

# ── T5: CI ────────────────────────────────────────────────────────────────
has "$WORKFLOW" "bash tests/test-issue-constraints-557.sh" "T5.1: the CI workflow runs this test"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || { echo "  ✗ issue Constraints checks failed"; exit 1; }
echo "  ✓ the Constraints section is optional, reporter-only, and reviewed"
exit 0
