#!/usr/bin/env bash
# test-intentional-refs-493.sh — the review traceability gate accepts an
# intentional partial `Refs #N` PR (issue #493).
#
#  AC1. A PR whose first line is `Refs #N` and whose AC table declares the
#       criteria that stay open passes traceability check 1 without a
#       `Type: refactor`/`chore` line.
#  AC2. A PR with neither `Closes #N` nor a valid intentional reference is
#       still blocked — and a failing `Refs #N` is never auto-rewritten to
#       `Closes #N`.
#  AC3. The accepted form is documented where the traceability check and the
#       `review.*` config are documented.
#
# Two layers: anchored prose assertions over the authored skill package (and
# its built copy), and behavioural assertions over scripts/idd-lint.py, which
# implements the same predicate as SPEC §5.1.
#
# Usage: bash tests/test-intentional-refs-493.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/anchors.bash
. "$ROOT/tests/lib/anchors.bash"

LINT="$ROOT/scripts/idd-lint.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

has() { # has <file> <ERE> <label>
  if grep -qE -- "$2" "$1"; then pass "$3"; else fail "$3"; fi
}

echo "◆ Intentional Refs #N PRs in the traceability gate (issue #493)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ── T1: the review skill (authored and built) carries the form ─────────────
for pkg in "$ROOT/src/skills/issue-pr-review" "$ROOT/skills/issue-pr-review"; do
  n="${pkg#"$ROOT/"}"
  anchor_check "$pkg" rvc-intentional-reference 'exactly `Refs #\{N\}`' "T1 the form keys off a first-line Refs #{N}: $n"
  anchor_check "$pkg" rvc-intentional-reference '\*\*Not\*\* an exemption' "T1 the form is not an exemption: $n"
  anchor_check "$pkg" rvc-intentional-reference 'Status exactly `unverified`, Evidence containing `deferred`' "T1 deferred rows are status-gated: $n"
  anchor_check "$pkg" rvc-intentional-reference 'at least one row that is not deferred' "T1 deferring every AC fails: $n"
  anchor_check "$pkg" rvc-intentional-reference 'No closing keyword names `#\{N\}`' "T1 a closing keyword for N voids the form: $n"
  anchor_check "$pkg" rvc-intentional-reference 'merge-effective surface' "T1 the keyword scan reuses check 1's surface: $n"
  anchor_check "$pkg" rvc-intentional-reference "PR title's \`\(#N\)\`" "T1 the Refs number is cross-checked against the title: $n"
  # AC2 polarity: a failing Refs line still blocks but is never auto-fixed.
  anchor_check "$pkg" rvc-intentional-reference 'still hard-blocks' "T2 a failing Refs line still blocks: $n"
  anchor_check "$pkg" rvc-intentional-reference '`action: note`, never `fix`' "T2 a failing Refs line is never a fixable finding: $n"
  anchor_check "$pkg" rv-closes-body-edit '\*\*never\*\* prepend when line 1 is `Refs #\{linked_issue\}`' "T2 Step 6 never prepends Closes onto a Refs PR: $n"
  anchor_check "$pkg" rv-traceability-outcomes '\*\*never\*\* auto-fixed' "T2 the gating rule keeps a failing Refs line un-fixable: $n"
  # The pinned #36 contract stays: Closes absent is still check 1's failure.
  anchor_check "$pkg" rvc-traceability-checks '`Closes #\{N\}` absent \| check 1 fails' "T2 Closes-absent still fails check 1: $n"
  anchor_check "$pkg" rvc-traceability-checks '○ traceability: pass — intentional reference' "T1 the outcome table renders the Refs pass: $n"
done
has "$ROOT/src/skills/issue-pr-review/SKILL.source.md" 'linked issue numbers \(from `Closes #N`, or a first-line `Refs #N`' \
  "T1 a Refs PR loads its linked issue's ACs"
has "$ROOT/src/skills/issue-pr-review/references/verification-checks.md" '○ deferred`, excluded from the rules above' \
  "T1 deferred criteria neither block nor count as delivered"

# ── T3: the fixer never turns an intentional reference into a closer ───────
for f in "$ROOT/src/shared/agents/fixer.md" "$ROOT/skills/issue-pr-review/references/agents/fixer.md"; do
  [ -f "$f" ] || continue
  has "$f" 'first line is `Refs #N` \(an intentional partial reference\), \*\*never\*\* suggest `Closes`' \
    "T3 fixer never suggests Closes on a Refs PR: ${f#"$ROOT/"}"
done

# ── T4: AC3 — documented where review.* and the check are documented ───────
has "$ROOT/docs/config-schema.md" 'unless line 1 is `Refs #N`' "T4 config-schema documents the Refs form"
has "$ROOT/docs/config-schema.md" 'Not an exemption, always on' "T4 config-schema says emptying the exempt keys does not disable it"
if grep -q 'restores strict issue #36 behavior' "$ROOT/docs/config-schema.md"; then
  fail "T4 config-schema no longer claims empty exempt keys restore strict #36"
else
  pass "T4 config-schema no longer claims empty exempt keys restore strict #36"
fi
has "$ROOT/SPEC.md" '\*\*Intentional partial delivery\.\*\*' "T4 SPEC §5.1 defines the intentional partial delivery"
has "$ROOT/SPEC.md" 'MUST NOT rewrite it to `Closes #N` automatically' "T4 SPEC forbids auto-rewriting Refs to Closes"

# ── T5: idd-lint P02 implements the same predicate ─────────────────────────
pr_body() { # pr_body <first-line> <extra-summary> <rows…>
  local first="$1" extra="$2"
  shift 2
  printf '%s\n\n## Summary\n\nPartial delivery. %s\n\n' "$first" "$extra"
  printf '## Decision Record\n\n'
  printf -- '- **Root cause:** r\n- **Options considered:** a; b\n- **Options rejected:** a\n'
  printf -- '- **Selected option:** b\n- **Residual risk:** none\n\nAnalyzed at: `feat/42-x @ abc1234` (2026-10-01)\n\n'
  printf '## Acceptance Criteria Verification\n\n| Criterion | Status | Evidence |\n|-----------|--------|----------|\n'
  printf '%s\n' "$@"
}
TITLE="feat(plugin): ship the claude code plugin (#42)"
DELIVERED='| A | pass | tests/a.sh |'
DEFERRED='| B | unverified | Deferred to a later PR; #42 stays open |'

lint() { # lint <want-exit> <label> <body-file> [title]
  local want="$1" label="$2" file="$3" got=0
  if [ "$#" -ge 4 ]; then
    python3 "$LINT" pr "$file" --title "$4" >"$TMP/out" 2>&1 || got=$?
  else
    python3 "$LINT" pr "$file" >"$TMP/out" 2>&1 || got=$?
  fi
  if [ "$got" -eq "$want" ]; then pass "$label"; else fail "$label (want exit $want, got $got)"; sed 's/^/      /' "$TMP/out"; fi
}

pr_body 'Refs #42' '' "$DELIVERED" "$DEFERRED" > "$TMP/ok.md"
lint 0 "T5 AC1: Refs #N with a declared deferred AC passes, no Type: line" "$TMP/ok.md" "$TITLE"
if grep -qiE '^\s*Type:' "$TMP/ok.md"; then fail "T5 fixture carries no Type: line"; else pass "T5 fixture carries no Type: line"; fi

pr_body 'Refs #42' 'See #420 and fixes #4200.' "$DELIVERED" "$DEFERRED" > "$TMP/boundary.md"
lint 0 "T5 a closer for #4200 is not a closer for #42 (word boundary)" "$TMP/boundary.md" "$TITLE"

pr_body 'Refs #42' '' "$DELIVERED" '| B | unverified | manual review needed |' > "$TMP/no-deferred.md"
lint 1 "T5 AC2: Refs #N without a declared deferred AC fails" "$TMP/no-deferred.md" "$TITLE"

pr_body 'Refs #42' '' '| A | unverified | deferred |' "$DEFERRED" > "$TMP/all-deferred.md"
lint 1 "T5 AC2: Refs #N deferring every AC fails" "$TMP/all-deferred.md" "$TITLE"

pr_body 'Refs #42' '' '| A | fail | deferred |' "$DELIVERED" > "$TMP/status-gated.md"
lint 1 "T5 AC2: 'deferred' evidence on a non-unverified row declares nothing" "$TMP/status-gated.md" "$TITLE"

pr_body 'Refs #42' 'Also `Fixes #42` in a code span.' "$DELIVERED" "$DEFERRED" > "$TMP/code-span.md"
lint 1 "T5 AC2: a closing keyword for N in a code span voids the form" "$TMP/code-span.md" "$TITLE"

lint 1 "T5 AC2: Refs #N whose number differs from the title's fails" "$TMP/ok.md" "feat(plugin): ship the claude code plugin (#43)"

pr_body 'This PR fixes things.' '' "$DELIVERED" "$DEFERRED" > "$TMP/neither.md"
lint 1 "T5 AC2: neither Closes #N nor Refs #N still fails" "$TMP/neither.md" "$TITLE"

pr_body 'Closes #42' '' "$DELIVERED" '| B | pass | tests/b.sh |' > "$TMP/closes.md"
lint 0 "T5 Closes #N is unchanged" "$TMP/closes.md" "$TITLE"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
