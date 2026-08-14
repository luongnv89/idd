#!/usr/bin/env bash
# test-squash-binding-295.sh — Issue #295 acceptance checks for the B1
# durable-memory binding (squash-merge body).
#
# The defect: three prose sites stated "GitHub copies the PR body verbatim into
# the commit message" as unconditional platform behavior. On GitHub that copy
# happens only when the repo's `squash_merge_commit_message` is `PR_BODY`; the
# default (`COMMIT_MESSAGES`) writes the list of commit subjects and drops the
# Decision Record at the merge boundary. `/issue-pr-review` traceability check 4
# treated the assumption as its own evidence and reported `pass` on a binding
# that had never landed in this repo.
#
# Acceptance criteria covered:
#   AC1  Repo setting is PR_BODY — a repository setting, not a file, so this
#        suite cannot assert it (tests run with no GitHub repo and no token, per
#        CLAUDE.md → Testing). What it *can* pin, and does, is that the exact
#        remedy command is documented where an operator will meet the warning.
#   AC2  Traceability check 4 reads the setting instead of assuming it, and
#        reports a non-pass status when the binding is defeated.
#   AC3  The claim sites state the copy as conditional on the repo setting.
#   AC4  /init-gitissue's warning covers the squash_merge_commit_* sub-settings,
#        not merge strategy alone.
#   AC5  The backfill decision is recorded, explicitly as "no backfill".
#   AC6  This file is the pin — the assumption cannot silently regress.
#
# Assertions run against `src/` and `docs/` (what is authored) *and* the built
# `skills/` tree (what actually ships and runs). A fix that lands in src/ but is
# never rebuilt is not a fix.
#
# Usage: bash tests/test-squash-binding-295.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_ROOT/src"
DOCS="$REPO_ROOT/docs"
SKILLS="$REPO_ROOT/skills"

VERIFICATION_CHECKS="$SRC/skills/issue-pr-review/references/verification-checks.md"
PR_REVIEW_TEMPLATES="$SRC/skills/issue-pr-review/references/report-templates.md"
RESOLVER_TEMPLATES="$SRC/skills/issue-resolver/references/report-templates.md"
INIT_SKILL="$SRC/skills/init-gitissue/SKILL.source.md"
METHODOLOGY="$DOCS/idd-methodology.md"
PLATFORM="$DOCS/platform-github.md"
SPEC="$REPO_ROOT/SPEC.md"
ADR="$DOCS/decisions/no-backfill-merged-decision-records.md"

# The canonical setting name and value. Every site that describes the binding
# must name both — a site that describes it without them is describing an
# assumption, which is the defect.
SETTING="squash_merge_commit_message"
VALUE="PR_BODY"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

# expect_grep <label> <extended-regex> <file...>
expect_grep() {
  local label="$1" pattern="$2"; shift 2
  if grep -qiE -- "$pattern" "$@"; then pass "$label"; else fail "$label"; fi
}

# expect_fixed <label> <literal> <file...>
expect_fixed() {
  local label="$1" needle="$2"; shift 2
  if grep -qF -- "$needle" "$@"; then pass "$label"; else fail "$label"; fi
}

# refute_fixed <label> <literal> <file...> — the literal must be gone.
refute_fixed() {
  local label="$1" needle="$2"; shift 2
  if grep -qF -- "$needle" "$@"; then fail "$label"; else pass "$label"; fi
}

echo "◆ B1 squash-merge binding tests (issue #295)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T0: Files exist
# ───────────────────────────────────────────────────────────
echo "T0: Files exist"
for f in "$VERIFICATION_CHECKS" "$PR_REVIEW_TEMPLATES" "$RESOLVER_TEMPLATES" \
         "$INIT_SKILL" "$METHODOLOGY" "$PLATFORM" "$SPEC" "$ADR"; do
  if [ -f "$f" ]; then
    pass "T0: exists ${f#"$REPO_ROOT"/}"
  else
    fail "T0: missing ${f#"$REPO_ROOT"/}"
  fi
done

# ───────────────────────────────────────────────────────────
# T1: AC2 — check 4 reads the setting instead of assuming it
# ───────────────────────────────────────────────────────────
echo "T1: AC2 — traceability check 4 is a real read"

expect_fixed "T1: check 4 names $SETTING" "$SETTING" "$VERIFICATION_CHECKS"
expect_grep "T1: check 4 reads it via the REST endpoint" \
  'gh api repos/\{owner\}/\{repo\}' "$VERIFICATION_CHECKS"
expect_grep "T1: check 4 records why gh repo view --json cannot answer" \
  'Unknown JSON field' "$VERIFICATION_CHECKS"
expect_grep "T1: check 4 forbids inferring the binding" \
  'never (assume|infer) it|never infer it' "$VERIFICATION_CHECKS"

# The exact sentences that encoded the assumption must be gone. These are the
# regression tripwires: restoring either one restores the defect.
refute_fixed "T1: 'no separate check is needed pre-merge' is gone" \
  "no separate check is needed pre-merge" "$VERIFICATION_CHECKS"
refute_fixed "T1: 'Squash-commit-body assumption' heading is gone" \
  "Squash-commit-body assumption" "$VERIFICATION_CHECKS"

# ───────────────────────────────────────────────────────────
# T2: AC2 — a defeated binding produces a non-pass status
# ───────────────────────────────────────────────────────────
echo "T2: AC2 — defeated binding reports non-pass"

expect_grep "T2: outcome table carries a binding-defeated row" \
  'traceability: partial .*binding defeated|binding defeated' "$VERIFICATION_CHECKS"
expect_grep "T2: the defeated row is partial, not pass" \
  '⚠ traceability: partial — "squash-merge binding defeated' "$VERIFICATION_CHECKS"
expect_grep "T2: the defeated status names the observed value" \
  '\{value\}' "$VERIFICATION_CHECKS"

# A read that cannot answer must not fall back to pass — that fallback is the
# original defect wearing a different hat.
expect_grep "T2: an unanswerable read reports 'unverified', not pass" \
  'binding unverified' "$VERIFICATION_CHECKS"
expect_grep "T2: check 4 explicitly forbids degrading to pass" \
  'never (degrade|fall back) to .?pass' "$VERIFICATION_CHECKS"

# Neither outcome may be handed to the autonomous fixer: no edit to a PR can
# change a repo setting, and the remedy is an admin API mutation.
expect_grep "T2: the outcomes are note-only, never fixer findings" \
  'never emit them as .action: fix. findings|never handed to the fixer' \
  "$VERIFICATION_CHECKS" "$PR_REVIEW_TEMPLATES"

# The report must be able to render both outcomes.
expect_grep "T2: report template renders the defeated line" \
  'squash-merge binding defeated' "$PR_REVIEW_TEMPLATES"
expect_grep "T2: report template renders the unverified line" \
  'squash-merge binding unverified' "$PR_REVIEW_TEMPLATES"

# The refactor/chore exemption relaxes check 1 only. If it could also swallow a
# non-pass check 4, an exempt PR would render `pass` over a defeated binding —
# the exact "report pass on an unread binding" this issue is about.
expect_grep "T2: check 4 is not swallowed by the refactor/chore exemption" \
  'non-.?pass.? check 4 keeps the dimension at .?partial.? even on an exempt PR|not exempt-able' \
  "$VERIFICATION_CHECKS"
expect_grep "T2: the exempt outcome row says so too" \
  'not exempt-able and holds the dimension at' "$VERIFICATION_CHECKS"

# Check 4 tests B1. A repo that declared B2 or B3 is not defeated by a
# non-PR_BODY value, so it must not collect a permanent, factually wrong partial.
expect_grep "T2: a declared B2/B3 binding is not reported as defeated" \
  'B2 \(merge-commit body\) or B3 \(git notes\)' "$VERIFICATION_CHECKS"

# ───────────────────────────────────────────────────────────
# T3: AC3 — the claim sites are conditional
# ───────────────────────────────────────────────────────────
echo "T3: AC3 — claim sites state the copy as conditional"

for f in "$METHODOLOGY" "$RESOLVER_TEMPLATES" "$VERIFICATION_CHECKS"; do
  rel="${f#"$REPO_ROOT"/}"
  if grep -qF -- "$SETTING" "$f" && grep -qF -- "$VALUE" "$f"; then
    pass "T3: $rel conditions the copy on $SETTING == $VALUE"
  else
    fail "T3: $rel describes the copy without naming the setting"
  fi
done

expect_grep "T3: methodology calls the assumption conditional, not platform behavior" \
  'conditional on a repo setting' "$METHODOLOGY"
expect_grep "T3: methodology names GitHub's defeating default" \
  'COMMIT_MESSAGES' "$METHODOLOGY"
expect_grep "T3: methodology widens the /init-gitissue warning to the sub-settings" \
  'squash_merge_commit_\*' "$METHODOLOGY"
expect_grep "T3: resolver template still tells the resolver to write the body anyway" \
  'Write the template in full regardless' "$RESOLVER_TEMPLATES"

# Secondary restatements. A file fixed in one paragraph and left unconditional
# 100 lines down teaches an agent reading top-to-bottom the defect, not the fix.
# Each of these carried the unconditional claim before issue #295.
refute_fixed "T3: no leftover 'squash-merge will carry it into git history'" \
  "where squash-merge will carry it into git history" "$RESOLVER_TEMPLATES"
expect_grep "T3: bug-verification conditions its git-history claim" \
  'when the repo.?s squash commit message is .?PR_BODY' \
  "$SRC/skills/issue-resolver/references/bug-verification.md"
expect_fixed "T3: pipeline-steps conditions its durable-memory claim" \
  "$SETTING" "$SRC/skills/issue-resolver/references/pipeline-steps.md"
expect_fixed "T3: README stops inferring the binding from the strategy alone" \
  "$SETTING" "$REPO_ROOT/README.md"
expect_fixed "T3: ARCHITECTURE's dual-write item names the setting" \
  "$SETTING" "$DOCS/ARCHITECTURE.md"

# SPEC.md is the normative source the methodology doc cites; leaving it
# unconditional would leave the authority wrong.
expect_fixed "T3: SPEC.md §4.3 B1 names the message-source condition" \
  "$SETTING" "$SPEC"
expect_grep "T3: SPEC.md forbids reporting B1 satisfied on strategy alone" \
  'MUST NOT report the binding as satisfied on the strength of the strategy alone' "$SPEC"

# ───────────────────────────────────────────────────────────
# T4: AC4 — /init-gitissue warns on the sub-setting
# ───────────────────────────────────────────────────────────
echo "T4: AC4 — init-gitissue covers the squash_merge_commit_* sub-settings"

expect_fixed "T4: init-gitissue names $SETTING" "$SETTING" "$INIT_SKILL"
expect_grep "T4: init-gitissue reads it via the REST endpoint" \
  'gh api repos/\{owner\}/\{repo\}' "$INIT_SKILL"
expect_grep "T4: init-gitissue keeps the strategy warning as well" \
  'Merge strategy is not squash-only' "$INIT_SKILL"
expect_grep "T4: init-gitissue adds a distinct sub-setting warning" \
  'Squash commit message is \{value\}, not PR_BODY' "$INIT_SKILL"
expect_grep "T4: init-gitissue warns on each condition independently" \
  'independently' "$INIT_SKILL"
expect_grep "T4: an unreadable setting is skipped, never reported satisfied" \
  'never report it satisfied' "$INIT_SKILL"

# ───────────────────────────────────────────────────────────
# T5: AC1 — the remedy is documented where an operator meets it
# ───────────────────────────────────────────────────────────
echo "T5: AC1 — the repo-settings remedy is documented"

# Matched as a normalized pattern rather than a byte-exact string: the command
# must be present and complete, but a reflowed line or a reordered flag is not a
# regression and should not break CI in three files at once.
REMEDY_RE='gh api .*-X PATCH .*repos/.*-f *'"${SETTING}"'='"${VALUE}"
for f in "$INIT_SKILL" "$VERIFICATION_CHECKS" "$PR_REVIEW_TEMPLATES"; do
  rel="${f#"$REPO_ROOT"/}"
  if grep -qE -- "$REMEDY_RE" "$f"; then
    pass "T5: $rel documents the fix command"
  else
    fail "T5: $rel warns without stating the fix command"
  fi
done

# ───────────────────────────────────────────────────────────
# T6: platform-github.md is the one catalog both call sites cite
# ───────────────────────────────────────────────────────────
echo "T6: platform driver catalog carries the read"

expect_grep "T6: catalog has a squash-commit message source row" \
  '\| Squash-commit message source \|' "$PLATFORM"
expect_fixed "T6: the row uses the REST endpoint" \
  "gh api repos/{owner}/{repo} --jq '{squash_merge_commit_title, ${SETTING}}'" "$PLATFORM"
expect_grep "T6: the REST exception to driver rule 1 is justified" \
  'Unknown JSON field' "$PLATFORM"
expect_grep "T6: the catalog distinguishes the two reads" \
  '\*{0,2}not\*{0,2} interchangeable' "$PLATFORM"

# ───────────────────────────────────────────────────────────
# T7: AC5 — the backfill decision is recorded, explicitly
# ───────────────────────────────────────────────────────────
echo "T7: AC5 — backfill decision recorded"

expect_grep "T7: the ADR states the decision explicitly as no backfill" \
  '\*\*No backfill\.\*\*' "$ADR"
expect_grep "T7: the ADR cites issue #295" 'issues/295' "$ADR"
# Anchored on the rewrite option and its substantive objection. A bare
# "Rejected" would also be satisfied by the git-notes option, and would pass on
# an ADR that never considered rewriting history at all.
expect_fixed "T7: the ADR weighs rewriting history as an option" "filter-repo" "$ADR"
expect_grep "T7: the ADR records the SHA-stability objection to rewriting" \
  'changes the SHA of every' "$ADR"
expect_grep "T7: the ADR is linked from the methodology doc" \
  'no-backfill-merged-decision-records' "$METHODOLOGY"

# ───────────────────────────────────────────────────────────
# T8: What ships is what runs — the built skills carry the fix
# ───────────────────────────────────────────────────────────
echo "T8: built skills carry the fix"

BUILT_CHECKS="$SKILLS/issue-pr-review/references/verification-checks.md"
BUILT_INIT="$SKILLS/init-gitissue/SKILL.md"
BUILT_RESOLVER_TPL="$SKILLS/issue-resolver/references/report-templates.md"

for f in "$BUILT_CHECKS" "$BUILT_INIT" "$BUILT_RESOLVER_TPL"; do
  rel="${f#"$REPO_ROOT"/}"
  if [ ! -f "$f" ]; then
    fail "T8: built file missing — $rel (run ./scripts/build.sh)"
  elif grep -qF -- "$SETTING" "$f"; then
    pass "T8: $rel ships the setting-aware wording"
  else
    fail "T8: $rel is stale — rebuild and commit skills/"
  fi
done

# The two digest-bundled docs reach every skill that bundles them; a digest that
# drops the new wording would ship the old assumption to every skill.
for doc in idd-methodology platform-github; do
  found=0; stale=0
  for f in "$SKILLS"/*/references/docs/"$doc".md; do
    [ -f "$f" ] || continue
    found=$((found + 1))
    grep -qF -- "$SETTING" "$f" || stale=$((stale + 1))
  done
  if [ "$found" -eq 0 ]; then
    fail "T8: no built copy of $doc.md found"
  elif [ "$stale" -eq 0 ]; then
    pass "T8: all $found built copies of $doc.md carry the setting"
  else
    fail "T8: $stale of $found built copies of $doc.md are stale"
  fi
done

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ B1 squash-merge binding tests failed"
  exit 1
fi
echo "  ✓ All B1 squash-merge binding checks passed"
