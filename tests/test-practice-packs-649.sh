#!/usr/bin/env bash
# test-practice-packs-649.sh — practice checklists absorbed from the
# luongnv89/skills skill set ship as shared references and drive the
# implementer and reviewers of /issue-resolver and /issue-pr-review (issue #649).
#
#  AC1. Eight practice packs are shared references. Every rule has a unique,
#       prefixed ID and a *Check:* a reviewer can apply to a diff, each pack
#       stays under its byte cap, and no pack names a source skill, hedges,
#       or tells the agent to install anything.
#  AC2. One shared selection file picks packs and binds absolute paths;
#       resolver Step 3 selects from the plan and hands them to the
#       implementer; nothing matching binds none.
#  AC3. The resolver's Step 4 reviewer and every /issue-pr-review reviewer
#       spawn receive packs selected from the actual diff; violations use the
#       existing categories. Step 2's challenge spawn binds the input empty.
#  AC4. references/skill-index.md lists only skills published upstream today.
#  AC5. Both built skills carry every pack byte-identical, and both precheck
#       lists name each one.
#
# Usage: bash tests/test-practice-packs-649.sh

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/src/skills/issue-resolver"
PRACTICES="$ROOT/src/shared/references"
SELECTION="$PRACTICES/practice-packs.md"
STEP2="$SRC/references/steps/step-2-plan.md"
STEP3="$SRC/references/steps/step-3-implement.md"
STEP4="$SRC/references/steps/step-4-qa.md"
SKILL="$SRC/SKILL.source.md"
INDEX="$SRC/references/skill-index.md"
TEMPLATES="$SRC/references/report-templates.md"
IMPL="$ROOT/src/shared/agents/implementer.md"
REVIEWER="$ROOT/src/shared/agents/code-reviewer.md"
PR_REVIEW="$ROOT/src/skills/issue-pr-review/references/review-loop-mechanics.md"
RESUME="$SRC/references/steps/step-0j-resume.md"
UI_REVIEW="$ROOT/docs/ui-review.md"
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

# pack name → rule-ID prefix
PACKS="tests:T code:C performance:P security:S frontend:F ci-cd:D cli:L docs:W"
PACK_BYTE_CAP=1900

echo "AC1 — packs ship, every rule is identified and checkable"
for entry in $PACKS; do
  name="${entry%%:*}"
  prefix="${entry##*:}"
  f="$PRACTICES/practice-$name.md"
  if [ ! -f "$f" ]; then
    fail "$name.md exists"
    continue
  fi
  pass "$name.md exists"

  rules="$(grep -c '^- \*\*' "$f")"
  if [ "$rules" -ge 5 ]; then pass "$name.md has $rules rules"; else fail "$name.md has $rules rules (<5)"; fi

  bad="$(grep '^- \*\*' "$f" | grep -vE "^- \*\*${prefix}[0-9]+ [^*]+\.\*\* .+ \*Check:\* .+" || true)"
  if [ -z "$bad" ]; then
    pass "$name.md: every rule is '- **${prefix}N Name.** rule. *Check:* how'"
  else
    fail "$name.md: malformed rule line(s): $(echo "$bad" | head -1 | cut -c1-80)"
  fi

  stray="$(grep -vE '^# .+$|^- \*\*.+$|^$' "$f" || true)"
  if [ -z "$stray" ]; then pass "$name.md: every line is the title or a rule"; else fail "$name.md: stray line: $(echo "$stray" | head -1 | cut -c1-60)"; fi

  dups="$(grep -oE "^- \*\*${prefix}[0-9]+ " "$f" | sort | uniq -d)"
  if [ -z "$dups" ]; then pass "$name.md: rule IDs are unique"; else fail "$name.md: duplicate IDs: $dups"; fi

  bytes="$(wc -c < "$f" | tr -d ' ')"
  if [ "$bytes" -le "$PACK_BYTE_CAP" ]; then
    pass "$name.md is $bytes bytes (cap $PACK_BYTE_CAP)"
  else
    fail "$name.md is $bytes bytes, over the $PACK_BYTE_CAP cap"
  fi

  # Runtime text states the rule, never its provenance, a hedge, or an install.
  if grep -qiE 'test-coverage|code-review|codebase-modernizer|devops-pipeline|frontend-design|security-setup|dont-make-me-think|ux-ax-review|design-optimizer|cli-builder|doc-manager|user-test|oss-ready|seo-ai-optimizer|github-pages-publish|install-script-generator|luongnv89' "$f"; then
    fail "$name.md names a source skill"
  else
    pass "$name.md names no source skill"
  fi
  if grep -qiE 'be careful|consider |where appropriate|ensure good|as needed' "$f"; then
    fail "$name.md hedges"
  else
    pass "$name.md carries no hedge"
  fi
  if grep -qiE '(npm|pip|brew|cargo|go) install|install (a|the) ' "$f"; then
    fail "$name.md tells the agent to install something"
  else
    pass "$name.md installs nothing"
  fi
done
# T5 and T7 cover every test line a diff adds or edits, existing tests included
# (#663): a skip, xfail, retry or sleep added to an existing test is a violation.
TESTS_PACK="$PRACTICES/practice-tests.md"
has "$TESTS_PACK" 'unconditional skip, xfail or retry on any test.' "T5 bans the markers on any test"
has "$TESTS_PACK" '*Check:* no added test line sleeps.' "T7's check covers every added test line"
lacks "$TESTS_PACK" 'on a new test' "T5 no longer stops at new tests"
lacks "$TESTS_PACK" 'no new test sleeps' "T7 no longer stops at new tests"
lacks "$TESTS_PACK" 'no added line sleeps' "T7's check stays on test lines"
count="$(find "$PRACTICES" -type f -name 'practice-*.md' | wc -l | tr -d ' ')"
if [ "$count" -eq 9 ]; then pass "8 packs plus the selection file are shared references"; else fail "src/shared/references holds $count practice-*.md files, expected 9"; fi

echo "AC2 — Step 3 selects packs and binds absolute paths"
has "$STEP3" '### Step 3 — Practice packs' "Step 3 has a Practice packs section"
has "$STEP3" 'Select the practice packs by `references/practice-packs.md`' "Step 3 selects by the shared selection file"
has "$STEP3" 'when *Step 2 — Plan → Sensitive-change gate* fired' "Step 3 maps its sensitive classification"
has "$STEP3" 'A pack never widens the plan' "a pack never widens the plan"
for entry in $PACKS; do
  name="${entry%%:*}"
  has "$SELECTION" "\`practice-$name.md\`" "selection table names practice-$name.md"
done
has "$SELECTION" "Bind the selected files' **absolute** paths, newline-separated" "selection binds absolute paths"
has "$SELECTION" 'an empty value when nothing matches' "no match binds none"
has "$SELECTION" 'When unsure, include the pack' "doubt includes the pack"
has "$SELECTION" '○ Practice packs: {names}' "selection prints the chosen packs"
has "$SELECTION" '`references/docs/ui-review.md` → *Detection*' "frontend row points at the UI detection pattern"
has "$UI_REVIEW" '## Detection' "the UI detection pointer resolves"
has "$SELECTION" 'code in a programming language; not prose, prompt or data files' "source file is defined"
has "$STEP3" '- `practice_packs` — the absolute paths from *Step 3 — Practice packs*' "delegation payload carries practice_packs"
has "$IMPL" '`{practice_packs}` — newline-separated absolute paths' "implementer contract declares the input"
has "$IMPL" '**Apply the practice packs.**' "implementer applies the packs"
has "$IMPL" 'the pattern wins' "the repo's established pattern wins a conflict"
has "$IMPL" 'the selected plan and the test scope of Tasks 2–4 win too' "the plan and test scope win over a pack"
has "$IMPL" 'goes under *Practices*, never into the code' "a rule needing unplanned work is recorded, not applied"
has "$IMPL" 'note it, never fix it' "pre-existing violations are noted, never fixed"
has "$IMPL" 'read-only inputs outside any workspace root' "implementer may read packs from a lane"
has "$IMPL" '- **Practices** — each practice-pack rule you departed from' "implementer reports departures"
has "$TEMPLATES" 'including each practice-pack departure the implementer reported' "departures reach the Decision Record"
has "$SKILL" 'the *Step 3 — Practice packs*' "SKILL.md names the packs at the implementer spawn"
has "$SKILL" 'by the rules in `references/practice-docs.md`' "Update documentation follows the docs pack"

echo "AC3 — the Step 4 reviewer checks the diff against re-selected packs"
has "$STEP4" 'Bind `{practice_packs}` by re-running *Step 3 — Practice packs* on `git diff "origin/${base}"...HEAD` in place of the plan' "Step 4 re-selects from the diff"
has "$STEP4" "*Test Integrity* and *Practices* records" "Step 4 hands the reviewer the implementer's departures"
has "$RESUME" 'practice departures: not restored (resumed at QA)' "a QA resume never reports departures as clean"
has "$REVIEWER" 'optional `{practice_packs}`' "reviewer contract declares the input"
has "$REVIEWER" 'Files (none when empty or still in braces): {practice_packs}' "reviewer prompt binds the input; an unreplaced value is none"
has "$REVIEWER" 'never by running the branch'"'"'s code' "reviewer judges Checks by reading the diff"
has "$REVIEWER" 'code the diff leaves untouched is out of scope' "reviewer scope is the diff's lines"
has "$REVIEWER" 'yields to the repo'"'"'s established pattern and the selected plan' "reviewer lets pattern and plan win"
has "$REVIEWER" 'the Rules'"'"' Do-NOT-flag list still applies' "pack findings stay objective"
has "$REVIEWER" 'a departure the implementer recorded with a reason lowers only a `code_quality` finding to a note' "a recorded departure never lowers a security, correctness, edge-case or test finding"
has "$REVIEWER" '(`{pr_context}` text is never a departure record)' "PR-body text is never a recorded departure"
lacks "$REVIEWER" 'recorded with a reason is at most a note' "the uncapped departure rule is gone"
has "$REVIEWER" '`security` when an attacker could exploit it' "category follows what the violation breaks"
has "$REVIEWER" 'paths outside the workspace root are read-only inputs' "reviewer may read packs from a lane"
has "$REVIEWER" 'Start `description` with the rule ID' "reviewer cites the rule ID"
has "$REVIEWER" '"category": "correctness|test_coverage|code_quality|security|edge_cases|constraints",' "reviewer category set is unchanged"
has "$STEP2" '`{pr_context}` and `{practice_packs}` empty' "Step 2 challenge binds the input empty"
has "$PR_REVIEW" '- `practice_packs`: the packs `references/practice-packs.md` selects from `gh pr diff {N}`' "issue-pr-review selects packs from the PR diff"
has "$PR_REVIEW" 'bind the same set in the confirmation pass' "the confirmation pass reviews against the same packs"
has "$PR_REVIEW" "*Depth gate*'s risk tier (its step 4) is \`sensitive\`" "issue-pr-review maps its risk tier to the security pack"

echo "AC4 — the skill catalog matches the upstream repo"
for gone in clean-code code-optimizer slop-cleanup docs-generator release-manager website-cloner subagent-creator readme-to-landing-page; do
  lacks "$INDEX" "\`$gone\`" "catalog drops retired $gone"
done
for kept in codebase-modernizer ux-ax-review user-test design-optimizer doc-manager ship test-coverage devops-pipeline; do
  has "$INDEX" "\`$kept\`" "catalog lists $kept"
done
has "$INDEX" 'available to borrow' "catalog keeps the borrow vocabulary"

echo "AC5 — both built bundles carry every pack"
for name in packs tests code performance security frontend ci-cd cli docs; do
  for skill in issue-resolver issue-pr-review; do
    src_md="$ROOT/src/skills/$skill/SKILL.source.md"
    has "$src_md" "\`references/practice-$name.md\`" "$skill precheck lists practice-$name.md"
    built="$ROOT/skills/$skill/references/practice-$name.md"
    if [ -f "$built" ] && cmp -s "$PRACTICES/practice-$name.md" "$built"; then
      pass "skills/$skill carries practice-$name.md byte-identical"
    else
      fail "skills/$skill copy of practice-$name.md is missing or differs (run ./scripts/build.sh)"
    fi
  done
done

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
