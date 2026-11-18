#!/usr/bin/env bash
# test-plan-to-issues-prd-fallback-643.sh — /plan-to-issues offers a
# requirements-document fallback when no plan file exists (issue #643).
#
#  AC1. Resolution rule 6 lists the document and asks once: draft from it,
#       run /tasks-generator first, or stop. Candidates are ordered, matched
#       case-insensitively, and several hits are listed, never guessed.
#  AC2. Drafting from the document takes the conversation path: the confirm
#       gate applies, criteria are copied word for word, a coverage check runs,
#       exit criteria persist as milestones and unplaced ones as **Unplaced**.
#  AC3. With no user present the rule is skipped and the run stops with
#       *No input to convert*.
#  AC4. The *No input to convert* fix block names /tasks-generator, and the
#       handoff re-runs the tasks.md beside the document (where
#       /tasks-generator writes it), never a bare root tasks.md.
#  AC5. Every restatement of the resolution order, the dependency tables, the
#       security boundary, the report contract and the built skills/ copy carry
#       the same rule. Drafted lines cannot break the ## Source fence.
#
# Usage: bash tests/test-plan-to-issues-prd-fallback-643.sh

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/src/skills/plan-to-issues"
REF="$SRC/references"
IR="$REF/input-resolution.md"
PRE="$REF/preflight.md"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
has() { # has <file> <fixed-string> <label>
  if grep -qF -- "$2" "$1"; then pass "$3"; else fail "$3 ($(basename "$1"): '$2')"; fi
}
lacks() { # lacks <file> <fixed-string> <label>
  if grep -qF -- "$2" "$1"; then fail "$3 ($(basename "$1") still has '$2')"; else pass "$3"; fi
}

echo "◆ plan-to-issues requirements-document fallback (issue #643)"

echo "┄ AC1 rule 6 and candidates"
has "$IR" "6. **Requirements-document fallback**" "rule 6 is the requirements-document fallback"
has "$IR" "7. **Neither**" "the stop moved to rule 7"
# Rule order: conversation fallback (5) precedes rule 6, which precedes the stop.
if awk '/^5\. \*\*Conversation fallback/{a=NR} /^6\. \*\*Requirements-document/{b=NR} /^7\. \*\*Neither/{c=NR} END{exit !(a && b && c && a<b && b<c)}' "$IR"; then
  pass "rule 6 sits between conversation fallback and the stop"
else
  fail "rule 6 sits between conversation fallback and the stop"
fi
has "$IR" "**ask once**" "rule 6 asks once"
has "$IR" "Choose [1/2/3]" "three options are offered"
has "$IR" "### Requirements-document candidates" "candidates section exists"
has "$IR" "case-insensitively" "candidate names match case-insensitively"
has "$IR" 'Exact names win: `prd.md`,' "exact names take precedence over globs"
has "$IR" "number them all in the one rule 6 prompt. Never guess." "several hits are listed, never guessed"

echo "┄ AC2 draft from the document"
has "$IR" "### Drafting from a requirements document" "drafting section exists"
has "$IR" 'gate still applies' "the confirm gate still applies"
has "$IR" "copied **word for word**" "criteria are copied word for word"
has "$IR" "never gets a \`(needs review)\` restatement" "stated criteria get no (needs review) line"
has "$IR" "One exception: a requirements document the user picked under rule 6 is endorsed intent." \
  "actionable-intent rule names the exception"
has "$IR" "**Coverage check, before the gate:**" "coverage check runs before the gate"
has "$IR" '**Milestone M<phase id>:**' "exit criteria persist as phase milestones"
has "$IR" '`**Unplaced**:`' "unplaced criteria persist in ## Source"
has "$IR" 'Stored `**Unplaced**:` criteria are each again' "resume restores unplaced criteria"
has "$REF/plan-parsing.md" '`**Unplaced**:` then `- [ ] <text>` lines; ends the last task' "parser grammar keeps unplaced criteria off the last task"

echo "┄ AC3 no user present"
has "$IR" "subagent, unattended, or test run), skip this rule." \
  "unattended runs skip rule 6"
has "$IR" 'stop with the *no input* failure block' "skipping falls through to the no-input stop"
has "$SRC/SKILL.source.md" "skipped with no user present" "SKILL.md Phase 0 states the skip"

echo "┄ AC4 fix block and handoff path"
has "$PRE" "/tasks-generator path/to/prd.md   (from a PRD)" "No input to convert fix block names /tasks-generator"
has "$PRE" "/tasks-generator {path}" "no-task-headings block hints /tasks-generator"
has "$IR" "re-run /plan-to-issues ./docs/tasks.md" "handoff re-runs the tasks.md beside the document"
lacks "$IR" "then re-run /plan-to-issues tasks.md" "handoff never names a bare root tasks.md"
has "$IR" "this skill never runs \`/tasks-generator\`" "the skill never runs /tasks-generator itself"

echo "┄ AC5 restatements, dependencies, boundary, report, fence"
has "$REF/phase-contracts.md" "requirements-document fallback" "phase-contracts names the step"
has "$SRC/SKILL.source.md" "requirements-document fallback" "SKILL.md Phase 0 names the step"
has "$REF/glossary.md" "requirements document" "glossary input names the document"
if grep -qF 'requirements document was picked' "$PRE"; then pass "No input at all names the document"; else fail "No input at all names the document"; fi
has "$PRE" '| `tasks-generator` | optional |' "preflight dependency table lists tasks-generator"
has "$SRC/SKILL.source.md" '| `tasks-generator` skill | skill, optional |' "SKILL.md dependency table lists tasks-generator"
has "$REF/security-boundary.md" "a requirements document chosen under the fallback" "security boundary lists the document"
has "$REF/reporting.md" "handoff to \`/tasks-generator\`" "report contract covers the handoff outcome"
has "$REF/reporting.md" "from docs/PRD.md" "report Source line names the document"
has "$IR" "**Fence safety.**" "drafted lines are made fence-safe"
has "$REF/epic-identity.md" "*Fence safety*" "epic-identity points at the fence-safety rule"

BUILT="$ROOT/skills/plan-to-issues"
if [ -d "$BUILT" ]; then
  for f in references/input-resolution.md references/preflight.md; do
    if cmp -s "$REF/${f#references/}" "$BUILT/$f"; then
      pass "built $f matches its source"
    else
      fail "built $f matches its source (rebuild: bash scripts/build.sh)"
    fi
  done
  has "$BUILT/SKILL.md" "requirements-document fallback" "built SKILL.md carries the rule"
else
  fail "built skills/plan-to-issues exists"
fi

echo ""
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
