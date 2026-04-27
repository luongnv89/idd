#!/usr/bin/env bash
# test-issue-pr-review-fix-loop-deprecation.sh — Validate the /issue-pr-review-fix-loop deprecation
#
# This script verifies issue #37 acceptance criteria:
#   AC #1: Audit confirms no workflow depends on /issue-pr-review-fix-loop.
#   AC #2: skills/issue-pr-review-fix-loop/SKILL.md carries a deprecation
#          notice and redirect to /issue-pr-review.
#   AC #3: Tracking note added for removal from the public skill index after
#          one release cycle.
#
# Usage: bash tests/test-issue-pr-review-fix-loop-deprecation.sh
# Returns: exit 0 if all tests pass, exit 1 on failure

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_DIR="$REPO_ROOT/src/deprecated-skills/issue-pr-review-fix-loop"
SKILL="$SKILL_DIR/SKILL.md"
README="$SKILL_DIR/README.md"
ROOT_README="$REPO_ROOT/README.md"
ROOT_CLAUDE="$REPO_ROOT/CLAUDE.md"
CHANGELOG="$REPO_ROOT/docs/CHANGELOG.md"

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

echo "◆ /issue-pr-review-fix-loop Deprecation Tests (issue #37)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T1: Files exist (deprecation keeps the file in place)
# ───────────────────────────────────────────────────────────
if [ -f "$SKILL" ]; then
  pass "T1.1: SKILL.md retained for backward-compat references"
else
  fail "T1.1: SKILL.md missing — deprecation must keep file present"
fi

if [ -f "$README" ]; then
  pass "T1.2: README.md retained for backward-compat references"
else
  fail "T1.2: README.md missing — deprecation must keep file present"
fi

# ───────────────────────────────────────────────────────────
# T2: SKILL.md frontmatter signals deprecation (AC #2)
# ───────────────────────────────────────────────────────────
if grep -qE '^[[:space:]]+deprecated:[[:space:]]+true[[:space:]]*$' "$SKILL"; then
  pass "T2.1: AC #2 — SKILL.md frontmatter has 'deprecated: true'"
else
  fail "T2.1: AC #2 — SKILL.md frontmatter missing 'deprecated: true'"
fi

if grep -qE '^[[:space:]]+deprecated_in:' "$SKILL"; then
  pass "T2.2: AC #2 — SKILL.md frontmatter has 'deprecated_in' version"
else
  fail "T2.2: AC #2 — SKILL.md frontmatter missing 'deprecated_in'"
fi

if grep -qE '^[[:space:]]+successor:[[:space:]]+/issue-pr-review[[:space:]]*$' "$SKILL"; then
  pass "T2.3: AC #2 — SKILL.md frontmatter names successor /issue-pr-review"
else
  fail "T2.3: AC #2 — SKILL.md frontmatter missing successor /issue-pr-review"
fi

if grep -qE '^[[:space:]]+removal_target:' "$SKILL"; then
  pass "T2.4: AC #3 — SKILL.md frontmatter has removal_target"
else
  fail "T2.4: AC #3 — SKILL.md frontmatter missing removal_target"
fi

# ───────────────────────────────────────────────────────────
# T3: SKILL.md description signals deprecation (AC #2)
# ───────────────────────────────────────────────────────────
desc_line="$(grep -m1 -E '^description:' "$SKILL" || true)"
desc_lower="$(printf '%s' "$desc_line" | tr '[:upper:]' '[:lower:]')"
case "$desc_lower" in
  *deprecated*)
    pass "T3.1: AC #2 — SKILL.md description starts with deprecation marker"
    ;;
  *)
    fail "T3.1: AC #2 — SKILL.md description does not mention deprecation"
    ;;
esac

case "$desc_lower" in
  *"/issue-pr-review"*)
    pass "T3.2: AC #2 — SKILL.md description redirects to /issue-pr-review"
    ;;
  *)
    fail "T3.2: AC #2 — SKILL.md description does not redirect to /issue-pr-review"
    ;;
esac

# ───────────────────────────────────────────────────────────
# T4: SKILL.md body has a deprecation banner (AC #2)
# ───────────────────────────────────────────────────────────
if grep -qE '^>[[:space:]]*##[[:space:]]+Deprecated' "$SKILL"; then
  pass "T4.1: AC #2 — SKILL.md body has a Deprecated banner header"
else
  fail "T4.1: AC #2 — SKILL.md body missing Deprecated banner header"
fi

if grep -qE 'Migration' "$SKILL"; then
  pass "T4.2: AC #2 — SKILL.md banner has a Migration section"
else
  fail "T4.2: AC #2 — SKILL.md banner missing Migration section"
fi

if grep -qE '/issue-pr-review-fix-loop[[:space:]]\|[[:space:]]\`?/issue-pr-review' "$SKILL" \
   || grep -qE '\`/issue-pr-review-fix-loop\`' "$SKILL"; then
  pass "T4.3: AC #2 — SKILL.md banner names the deprecated invocation explicitly"
else
  fail "T4.3: AC #2 — SKILL.md banner missing explicit invocation reference"
fi

# ───────────────────────────────────────────────────────────
# T5: SKILL.md tracking note for one-release-cycle removal (AC #3)
# ───────────────────────────────────────────────────────────
skill_lower="$(tr '[:upper:]' '[:lower:]' < "$SKILL")"
case "$skill_lower" in
  *"one release cycle"*|*"one-release-cycle"*)
    pass "T5.1: AC #3 — SKILL.md notes 'one release cycle' retention window"
    ;;
  *)
    fail "T5.1: AC #3 — SKILL.md missing 'one release cycle' retention note"
    ;;
esac

case "$skill_lower" in
  *"public skill index"*|*"removed from"*"index"*)
    pass "T5.2: AC #3 — SKILL.md states removal from public skill index"
    ;;
  *)
    fail "T5.2: AC #3 — SKILL.md missing public-skill-index removal note"
    ;;
esac

# ───────────────────────────────────────────────────────────
# T6: README.md (skill-local) has deprecation banner (AC #2)
# ───────────────────────────────────────────────────────────
readme_lower="$(tr '[:upper:]' '[:lower:]' < "$README")"
case "$readme_lower" in
  *deprecated*)
    pass "T6.1: AC #2 — skills/issue-pr-review-fix-loop/README.md mentions deprecation"
    ;;
  *)
    fail "T6.1: AC #2 — skills/issue-pr-review-fix-loop/README.md missing deprecation note"
    ;;
esac

case "$readme_lower" in
  *"/issue-pr-review"*)
    pass "T6.2: AC #2 — skill README redirects to /issue-pr-review"
    ;;
  *)
    fail "T6.2: AC #2 — skill README missing /issue-pr-review redirect"
    ;;
esac

# ───────────────────────────────────────────────────────────
# T7: Root README marks the skill as deprecated (AC #2 + AC #3)
# ───────────────────────────────────────────────────────────
if grep -qE '^\|.*\`/issue-pr-review-fix-loop\`.*[Dd]eprecated' "$ROOT_README"; then
  pass "T7.1: AC #2 — Root README skill table marks /issue-pr-review-fix-loop deprecated"
else
  fail "T7.1: AC #2 — Root README skill table does not mark /issue-pr-review-fix-loop deprecated"
fi

if grep -qE '^### /issue-pr-review-fix-loop.*[Dd]eprecated' "$ROOT_README"; then
  pass "T7.2: AC #2 — Root README section header marks skill deprecated"
else
  fail "T7.2: AC #2 — Root README section header missing deprecation marker"
fi

# ───────────────────────────────────────────────────────────
# T8: Root CLAUDE.md marks skill deprecated (AC #2)
# ───────────────────────────────────────────────────────────
if grep -qE 'issue-pr-review-fix-loop/.*DEPRECATED' "$ROOT_CLAUDE"; then
  pass "T8.1: AC #2 — Root CLAUDE.md project structure marks skill DEPRECATED"
else
  fail "T8.1: AC #2 — Root CLAUDE.md project structure missing DEPRECATED marker"
fi

# ───────────────────────────────────────────────────────────
# T9: CHANGELOG has Deprecated entry (AC #2 + AC #3)
# ───────────────────────────────────────────────────────────
if awk '
  /^## \[Unreleased\]/ {in_unrel=1; next}
  /^## \[/ && in_unrel {exit}
  in_unrel
' "$CHANGELOG" | grep -qE '^### Deprecated[[:space:]]*$'; then
  pass "T9.1: AC #3 — CHANGELOG [Unreleased] has Deprecated subsection"
else
  fail "T9.1: AC #3 — CHANGELOG [Unreleased] missing Deprecated subsection"
fi

if awk '
  /^## \[Unreleased\]/ {in_unrel=1; next}
  /^## \[/ && in_unrel {exit}
  in_unrel
' "$CHANGELOG" | grep -qE '/issue-pr-review-fix-loop'; then
  pass "T9.2: AC #2 — CHANGELOG [Unreleased] mentions /issue-pr-review-fix-loop"
else
  fail "T9.2: AC #2 — CHANGELOG [Unreleased] missing /issue-pr-review-fix-loop entry"
fi

if awk '
  /^## \[Unreleased\]/ {in_unrel=1; next}
  /^## \[/ && in_unrel {exit}
  in_unrel
' "$CHANGELOG" | grep -qiE 'one release cycle'; then
  pass "T9.3: AC #3 — CHANGELOG entry references one-release-cycle window"
else
  fail "T9.3: AC #3 — CHANGELOG entry missing one-release-cycle reference"
fi

if awk '
  /^## \[Unreleased\]/ {in_unrel=1; next}
  /^## \[/ && in_unrel {exit}
  in_unrel
' "$CHANGELOG" | grep -qE '#37'; then
  pass "T9.4: AC #3 — CHANGELOG entry links tracking issue #37"
else
  fail "T9.4: AC #3 — CHANGELOG entry missing #37 tracking reference"
fi

# ───────────────────────────────────────────────────────────
# T10: AC #1 — no workflow depends on /issue-pr-review-fix-loop
# ───────────────────────────────────────────────────────────
# Audit: scan every other skill SKILL.md, the shared agents, and tests for
# runtime references that would cause /issue-pr-review-fix-loop to be invoked
# transitively. The deprecated skill itself, its README, the CHANGELOG, and
# this test file are excluded — those are documentation references, not
# workflow dependencies.

DEP_HITS=0
DEP_MATCHES=""
while IFS= read -r match; do
  [ -z "$match" ] && continue
  src="${match%%:*}"
  rest="${match#*:}"
  case "$src" in
    "$SKILL_DIR/"*) continue ;;
    "$CHANGELOG") continue ;;
    "$ROOT_README") continue ;;
    "$ROOT_CLAUDE") continue ;;
    "$REPO_ROOT/tests/test-issue-pr-review-fix-loop-deprecation.sh") continue ;;
    "$REPO_ROOT/improvement-plan"*".md") continue ;;
    "$REPO_ROOT/docs/"*) continue ;;
  esac
  DEP_HITS=$((DEP_HITS + 1))
  DEP_MATCHES="${DEP_MATCHES}    ${src}: ${rest}\n"
done < <(grep -rn "issue-pr-review-fix-loop" \
  "$REPO_ROOT/src/skills" \
  "$REPO_ROOT/src/shared" \
  "$REPO_ROOT/tests" \
  2>/dev/null || true)

if [ "$DEP_HITS" -eq 0 ]; then
  pass "T10.1: AC #1 — no skill/shared/test workflow references /issue-pr-review-fix-loop"
else
  printf "%b" "$DEP_MATCHES"
  fail "T10.1: AC #1 — found $DEP_HITS workflow reference(s) to /issue-pr-review-fix-loop"
fi

# Bonus: confirm /issue-pr-review is the redirect target and exists.
if [ -f "$REPO_ROOT/src/skills/issue-pr-review/SKILL.md" ]; then
  pass "T10.2: AC #1 — successor /issue-pr-review skill exists"
else
  fail "T10.2: AC #1 — successor /issue-pr-review skill missing"
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Deprecation spec for /issue-pr-review-fix-loop is incomplete"
  exit 1
fi

echo "  ✓ Deprecation spec for /issue-pr-review-fix-loop satisfies issue #37 ACs"
exit 0
