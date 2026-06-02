#!/usr/bin/env bash
# test-issue-pr-review-fix-loop-deprecation.sh — Validate the /issue-pr-review-fix-loop deprecation
#
# This script verifies issue #37 and issue #54 acceptance criteria:
#   AC #1: Audit confirms no workflow depends on /issue-pr-review-fix-loop.
#   AC #2: skills/issue-pr-review-fix-loop/SKILL.md carries a deprecation
#          notice and redirect to /issue-pr-review.
#   AC #3: Tracking note added for removal from the public skill index after
#          one release cycle.
#   AC #54.1: Deprecated source remains under src/deprecated-skills/.
#   AC #54.2: Root README no longer advertises /issue-pr-review-fix-loop as a
#             public command or installable skill.
#   AC #54.3: Public distribution excludes /issue-pr-review-fix-loop unless a
#             future explicit distribution flag is added.
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
DIST_SKILL="$REPO_ROOT/dist/skills/issue-pr-review-fix-loop"
PLUGIN_MANIFEST="$REPO_ROOT/dist/plugin/.claude-plugin/plugin.json"

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

echo "◆ /issue-pr-review-fix-loop Deprecation Tests (issues #37, #54)"
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
# T7: Root README no longer advertises the skill publicly (issue #54)
# ───────────────────────────────────────────────────────────
if grep -qE '^\|[[:space:]]*`/issue-pr-review-fix-loop`' "$ROOT_README"; then
  fail "T7.1: AC #54 — Root README still has a public table row for /issue-pr-review-fix-loop"
else
  pass "T7.1: AC #54 — Root README has no public table row for /issue-pr-review-fix-loop"
fi

if grep -qE '^### /issue-pr-review-fix-loop' "$ROOT_README"; then
  fail "T7.2: AC #54 — Root README still has a command reference section for /issue-pr-review-fix-loop"
else
  pass "T7.2: AC #54 — Root README has no command reference section for /issue-pr-review-fix-loop"
fi

if grep -qE '^/issue-pr-review-fix-loop([[:space:]]|$)' "$ROOT_README"; then
  fail "T7.3: AC #54 — Root README still contains runnable /issue-pr-review-fix-loop examples"
else
  pass "T7.3: AC #54 — Root README has no runnable /issue-pr-review-fix-loop examples"
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
# T9: CHANGELOG documents the deprecation (#37) and removal (#54)
#     of /issue-pr-review-fix-loop (AC #2 + AC #3 + AC #54).
#
#     These are durable historical facts. Keep a Changelog files
#     finalize [Unreleased] entries into a dated release section when
#     a version is cut — here they live under [0.7.0]. Scanning only
#     [Unreleased] therefore reports the completed work as missing
#     (issue #100). Instead, extract the `### Deprecated` and
#     `### Removed` subsection bodies from anywhere in the file and
#     assert the /issue-pr-review-fix-loop content within them. This
#     stays content-anchored: a bare `### Removed` header from some
#     other release won't satisfy the checks.
# ───────────────────────────────────────────────────────────

# Body of every `### Deprecated` subsection in the changelog (lines
# until the next markdown header), concatenated. The reset matches any
# line starting with `#` rather than an interval like `^#{2,3} ` —
# CHANGELOG body lines are bullets (`-`) or blank, never `#`, so any
# `#` line is a header that ends the subsection. This avoids awk
# interval expressions, which older one-true-awk builds treat as
# literal characters (silently leaking the scan to EOF — issue #100).
deprecated_body="$(awk '
  /^### Deprecated[[:space:]]*$/ {grab=1; next}
  /^#/ {grab=0}
  grab
' "$CHANGELOG")"

# Body of every `### Removed` subsection.
removed_body="$(awk '
  /^### Removed[[:space:]]*$/ {grab=1; next}
  /^#/ {grab=0}
  grab
' "$CHANGELOG")"

if printf '%s\n' "$deprecated_body" | grep -qE '/issue-pr-review-fix-loop'; then
  pass "T9.1: AC #3 — CHANGELOG ### Deprecated documents /issue-pr-review-fix-loop"
else
  fail "T9.1: AC #3 — CHANGELOG ### Deprecated missing /issue-pr-review-fix-loop"
fi

if printf '%s\n' "$deprecated_body" | grep -qE '#37'; then
  pass "T9.2: AC #3 — CHANGELOG deprecation entry links tracking issue #37"
else
  fail "T9.2: AC #3 — CHANGELOG deprecation entry missing #37 tracking reference"
fi

if printf '%s\n%s\n' "$deprecated_body" "$removed_body" \
   | grep -qE 'src/deprecated-skills/issue-pr-review-fix-loop'; then
  pass "T9.3: AC #3/#54 — CHANGELOG documents retained deprecated source path"
else
  fail "T9.3: AC #3/#54 — CHANGELOG missing retained deprecated source path"
fi

if printf '%s\n' "$removed_body" | grep -qE '/issue-pr-review-fix-loop'; then
  pass "T9.4: AC #54 — CHANGELOG ### Removed documents /issue-pr-review-fix-loop"
else
  fail "T9.4: AC #54 — CHANGELOG ### Removed missing /issue-pr-review-fix-loop"
fi

if printf '%s\n' "$removed_body" | grep -qE '#54'; then
  pass "T9.5: AC #54 — CHANGELOG removal entry documents distribution decision (#54)"
else
  fail "T9.5: AC #54 — CHANGELOG removal entry missing issue #54 reference"
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
    "$REPO_ROOT/tests/test-sync-safety.sh") continue ;;
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
# T11: AC #54 — public distribution excludes the deprecated skill
# ───────────────────────────────────────────────────────────
if grep -qE '^[[:space:]]*distribute:' "$SKILL"; then
  fail "T11.1: AC #54 — deprecated SKILL.md has a distribute flag"
else
  pass "T11.1: AC #54 — deprecated SKILL.md has no distribute flag"
fi

if [ -e "$DIST_SKILL" ]; then
  fail "T11.2: AC #54 — dist/skills contains issue-pr-review-fix-loop"
else
  pass "T11.2: AC #54 — dist/skills excludes issue-pr-review-fix-loop"
fi

if [ -f "$PLUGIN_MANIFEST" ] && grep -q 'issue-pr-review-fix-loop' "$PLUGIN_MANIFEST"; then
  fail "T11.3: AC #54 — public plugin manifest includes issue-pr-review-fix-loop"
else
  pass "T11.3: AC #54 — public plugin manifest excludes issue-pr-review-fix-loop"
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

echo "  ✓ Deprecation spec for /issue-pr-review-fix-loop satisfies issue #37 and #54 ACs"
exit 0
