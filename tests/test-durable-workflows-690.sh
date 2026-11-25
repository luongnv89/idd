#!/usr/bin/env bash
# test-durable-workflows-690.sh — a cut-off run resumes instead of starting over (issue #690).
#
# Every skill was reviewed for cut-off resume. Five gained rules; the pins below
# hold each rule to the built skill that ships it.
#
#   T1  each resume rule is in its built skill, located by anchor;
#   T2  the two shared references are bundled byte-identical into exactly the
#       skills that cite them, each listed in that skill's precheck, and the
#       three unchanged long-running skills carry neither;
#   T3  the shared references stay closure leaves with no tracker call and no
#       gate heading;
#   T4  the ADR amendment names all nine skills and the decisions kept;
#   T5  mutation: the T1 pins fail when an anchor's region is emptied in a copy
#       of the built skills, once per anchor, and when a shared reference is gone;
#   T6  a stage file under <git common dir>/idd/stage/ is invisible to
#       git status and git stash, from a linked worktree too;
#   T7  the CI step exists.
#
# Usage: bash tests/test-durable-workflows-690.sh
# Returns: exit 0 if all checks pass, exit 1 on failure
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS="$ROOT/skills"
SHARED="$ROOT/src/shared/references"
ADR="$ROOT/docs/decisions/context-threshold-durable-handoff.md"
WORKFLOW="$ROOT/.github/workflows/dist-check.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

# shellcheck source=lib/anchors.bash
. "$ROOT/tests/lib/anchors.bash"

echo "◆ Cut-off resume in every skill (#690)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

for f in "$ADR" "$WORKFLOW" "$SHARED/resume-cut-off.md" "$SHARED/stage-file.md"; do
  [ -f "$f" ] || { echo "  ✗ missing $f"; exit 1; }
done

RESUME_SKILLS="issue-analysis issue-triage issue-creator plan-to-issues"
STAGE_SKILLS="issue-analysis issue-triage"
ALL_SHIPPED="auto-pilot init-idd issue-analysis issue-creator issue-pr-review issue-resolver issue-triage plan-to-issues"

# One row per pinned rule: skill|anchor|ERE matched against the flattened region.
# Each ERE turns on the polarity-bearing words of its rule.
PINS='init-idd|init-recheck|first run \*Validate the written config\* on it.*a failure prints only
issue-analysis|ia-resume|.commit_sha. equals .git rev-parse HEAD.*Pin broken: print the stale notice and run every step
issue-analysis|ia-resume|View mode never reads it
issue-analysis|ia-resume|references/resume-cut-off\.md
issue-analysis|ia-stage-write|passes these checks, write.*references/stage-file\.md.*validated return as .synthesis.
issue-analysis|ia-plan-resume|Only when the stage file read after Step 1 carried .plan: "pending"., pin broken or not.*skip step 2.*Otherwise, and on every run with no such stage, post
issue-analysis|ia-persist|Remove the stage file.*once the plan post is verified
issue-triage|tr-resume|reuse a batch only when its HEAD equals the current one.*same .updatedAt. string
issue-triage|tr-resume|scan only the issues no reused batch covers
issue-triage|tr-resume|Auto mode reuses a batch under the same pin
issue-triage|tr-resume|written, remove the stage file
issue-creator|ic-normalize-tail|Only when .issue\.normalize_comment. is true.*viewerDidAuthor.*no later comment
issue-creator|ic-normalize-tail|--json state,comments.*When the issue is open, the latest comment.*created in the last 24 hours.*no later comment
issue-creator|ic-normalize-tail|closed issue or an older backup is a finished normalization.*never post it there
issue-creator|ic-normalize-tail|are not recovered: they are the one step lost
issue-creator|ic-backup-reuse|--json body,comments.*only when a backup comment with .viewerDidAuthor. true already contains that body byte for byte.*Any difference posts a new backup
issue-creator|ic-batch-recover|never the backlog snapshot
issue-creator|ic-batch-recover|gh issue list --author @me --state all --limit 200 --json number,title,createdAt,body,state
issue-creator|ic-batch-recover|--jq .*part_of: .*scan\(.*with a parent bound, .\{parent\}. in its .part_of.
issue-creator|ic-batch-recover|Never create it again.*recovered — already created as
issue-creator|ic-batch-recover|A reworded title is not recovered
plan-to-issues|pti-resume|references/resume-cut-off\.md.*stale notice only for a filed task.*report-only.*\*\*never\*\* re-file, edit or close a filed child
plan-to-issues|pti-resume|same id and title is not detected
plan-to-issues|pti-resume|added to the worklist since is one of those and is filed
plan-to-issues|pti-adopt-restore|neither source marker.*Ask the adoption question once.*\*\*otherwise\*\* take the \*Cannot restore worklist\* stop
plan-to-issues|pti-dep-guard|only when the body lacks that exact line'

ANCHORS="$(printf '%s\n' "$PINS" | cut -d'|' -f1,2 | sort -u)"

# pins <skills-root> — run every T1 pin against a built skills tree.
pins() {
  local root="$1" skill id pattern name
  while IFS='|' read -r skill id pattern; do
    anchor_check_flat "$root/$skill" "$id" "$pattern" "T1: $skill a:$id — $(printf '%s' "$pattern" | cut -c1-48)"
  done <<EOF
$PINS
EOF
  for skill in $RESUME_SKILLS; do
    name="$root/$skill/references/resume-cut-off.md"
    if grep -q 'hint, never an authority' "$name" 2>/dev/null \
      && grep -q 'Read live before repeating an effect' "$name" \
      && grep -q 'Stale means redo' "$name" \
      && grep -q '^○ Resuming {task}' "$name" \
      && grep -q '^⚠ Saved progress is stale' "$name"; then
      pass "T1: $skill ships the resume contract and both output shapes"
    else
      fail "T1: $skill ships the resume contract and both output shapes"
    fi
  done
  for skill in $STAGE_SKILLS; do
    name="$root/$skill/references/stage-file.md"
    if grep -qF 'git rev-parse --git-common-dir)/idd/stage/' "$name" 2>/dev/null \
      && grep -q 'Never write through a symlinked' "$name" \
      && grep -q 'atomic rename' "$name" \
      && grep -q 'Untrusted data' "$name" \
      && grep -q 'put no value from it on a command line' "$name" \
      && grep -q 'delete it, run the steps again' "$name" \
      && grep -q "At the skill's terminal persist" "$name"; then
      pass "T1: $skill ships the stage-file contract"
    else
      fail "T1: $skill ships the stage-file contract"
    fi
  done
}

# ── T1: the rules, on the built skills ───────────────────────────
pins "$SKILLS"

# ── T2: bundling ─────────────────────────────────────────────────
bundled() { # bundled <leaf> — the shipped skills that carry it, space-joined
  local s out=""
  for s in $ALL_SHIPPED; do
    if [ -f "$SKILLS/$s/references/$1" ]; then out="$out $s"; fi
  done
  printf '%s\n' "$out" | sed 's/^ //'
}
[ "$(bundled resume-cut-off.md)" = "issue-analysis issue-creator issue-triage plan-to-issues" ] \
  && pass "T2: resume-cut-off.md is bundled into exactly its four citing skills" \
  || fail "T2: resume-cut-off.md is bundled into: $(bundled resume-cut-off.md)"
[ "$(bundled stage-file.md)" = "issue-analysis issue-triage" ] \
  && pass "T2: stage-file.md is bundled into exactly the two skills that write a stage" \
  || fail "T2: stage-file.md is bundled into: $(bundled stage-file.md)"
for s in $RESUME_SKILLS; do
  cmp -s "$SHARED/resume-cut-off.md" "$SKILLS/$s/references/resume-cut-off.md" \
    && pass "T2: $s carries resume-cut-off.md byte-identical" \
    || fail "T2: $s carries resume-cut-off.md byte-identical"
  grep -qF 'references/resume-cut-off.md' "$SKILLS/$s/SKILL.md" \
    && pass "T2: $s lists resume-cut-off.md in SKILL.md" \
    || fail "T2: $s lists resume-cut-off.md in SKILL.md"
done
for s in $STAGE_SKILLS; do
  cmp -s "$SHARED/stage-file.md" "$SKILLS/$s/references/stage-file.md" \
    && pass "T2: $s carries stage-file.md byte-identical" \
    || fail "T2: $s carries stage-file.md byte-identical"
  grep -qF 'references/stage-file.md' "$SKILLS/$s/SKILL.md" \
    && pass "T2: $s lists stage-file.md in SKILL.md" \
    || fail "T2: $s lists stage-file.md in SKILL.md"
done
if grep -rqE 'idd/stage|resume-cut-off|stage-file\.md' \
  "$SKILLS/auto-pilot" "$SKILLS/issue-resolver" "$SKILLS/issue-pr-review" 2>/dev/null; then
  fail "T2: auto-pilot, issue-resolver and issue-pr-review name no stage file or resume leaf"
else
  pass "T2: auto-pilot, issue-resolver and issue-pr-review name no stage file or resume leaf"
fi

# ── T3: the leaves stay leaves ───────────────────────────────────
for leaf in resume-cut-off.md stage-file.md; do
  if grep -qE '(^|[^[:alnum:]_./-])gh[[:space:]]+(issue|pr|api|label|repo)' "$SHARED/$leaf"; then
    fail "T3: $leaf makes no tracker call"
  else
    pass "T3: $leaf makes no tracker call"
  fi
  if grep -qiE '^#+ .*gates?([^[:alnum:]]|$)' "$SHARED/$leaf"; then
    fail "T3: $leaf has no gate heading"
  else
    pass "T3: $leaf has no gate heading"
  fi
  if grep -qE 'docs/[a-z-]+\.md|shared/(agents|scripts)/' "$SHARED/$leaf"; then
    fail "T3: $leaf carries no rewritable token"
  else
    pass "T3: $leaf carries no rewritable token"
  fi
done

# ── T4: the ADR amendment ────────────────────────────────────────
AMEND="$(awk '/^## Amendment — every skill reviewed for cut-off resume/{on=1; next} on && /^## /{exit} on' "$ADR")"
[ -n "$AMEND" ] && pass "T4: the ADR carries the #690 amendment section" \
  || fail "T4: the ADR carries the #690 amendment section"
for s in auto-pilot issue-resolver issue-pr-review issue-analysis issue-triage issue-creator plan-to-issues init-idd idd-doctor; do
  printf '%s\n' "$AMEND" | grep -qE "^\| ./$s. \| (Reviewed, no change|Changed)" \
    && pass "T4: the review table has a row for /$s" \
    || fail "T4: the review table has a row for /$s"
done
ROWS="$(printf '%s\n' "$AMEND" | grep -cE '^\| ./[a-z-]+. \| (Reviewed|Changed)' || true)"
[ "$ROWS" = "9" ] && pass "T4: the review table has nine skill rows" \
  || fail "T4: the review table has $ROWS skill rows, not nine"
FLAT_AMEND="$(printf '%s\n' "$AMEND" | tr '\n' ' ')"
printf '%s\n' "$FLAT_AMEND" | grep -qE 're-run without .--resume. starts over' \
  && pass "T4: the auto-mode --resume decision is recorded" \
  || fail "T4: the auto-mode --resume decision is recorded"
printf '%s\n' "$FLAT_AMEND" | grep -qE '.--review-only. reads and writes no record' \
  && pass "T4: the --review-only decision is recorded" \
  || fail "T4: the --review-only decision is recorded"
printf '%s\n' "$FLAT_AMEND" | grep -qE 'between the draft +confirm and the epic create call' \
  && pass "T4: the conversation-path residual loss is recorded" \
  || fail "T4: the conversation-path residual loss is recorded"

# ── T5: mutation — the pins have teeth ───────────────────────────
# pins_ok <skills-root> — exit 0 only when every T1 pin passes there.
pins_ok() ( FAIL=0; pins "$1" >/dev/null 2>&1; [ "$FAIL" -eq 0 ] )

MUT="$TMP/skills"
fresh_copy() {
  rm -rf "$MUT"; mkdir -p "$MUT"
  local s
  for s in init-idd $RESUME_SKILLS; do cp -R "$SKILLS/$s" "$MUT/$s"; done
}
fresh_copy
pins_ok "$MUT" && pass "T5: the pins pass on an unmodified copy" \
  || fail "T5: the pins pass on an unmodified copy"

while IFS='|' read -r skill id; do
  fresh_copy
  target="$(anchor_package_file "$MUT/$skill" "$id" || true)"
  if [ -z "$target" ]; then
    fail "T5: a:$id located in the copy of $skill"
    continue
  fi
  # Keep the anchor, delete the rule: the anchor line is cut down to its marker
  # and the rest of its region (to the next heading or anchor) is dropped.
  awk -v m="<!-- a:$id -->" '
    { if ($0 ~ /^[[:space:]]*(```|~~~)/) fence = !fence }
    !seen && index($0, m) { seen = 1; cut = 1; print m; next }
    cut && !fence && ($0 ~ /^#+ / || $0 ~ /<!-- a:[a-z0-9-]+ -->/) { cut = 0 }
    !cut { print }
  ' "$target" > "$target.new" && mv "$target.new" "$target"
  if pins_ok "$MUT"; then
    fail "T5: deleting the a:$id rule from $skill turns the pins red"
  else
    pass "T5: deleting the a:$id rule from $skill turns the pins red"
  fi
done <<EOF
$ANCHORS
EOF

for pair in "issue-creator/references/resume-cut-off.md" "issue-triage/references/stage-file.md"; do
  fresh_copy
  rm -f "$MUT/$pair"
  if pins_ok "$MUT"; then
    fail "T5: removing $pair turns the pins red"
  else
    pass "T5: removing $pair turns the pins red"
  fi
done

# ── T6: the stage location never reaches the worktree ────────────
REPO="$TMP/repo"
mkdir -p "$REPO"
(
  cd "$REPO"
  git init -q .
  git config user.email t@example.com
  git config user.name t
  git config commit.gpgsign false
  echo x > f.txt
  git add f.txt
  git commit -q -m init
  git worktree add -q "$TMP/wt" -b lane >/dev/null 2>&1
)
stage_of() { ( cd "$1" && printf '%s\n' "$(cd "$(git rev-parse --git-common-dir)" && pwd -P)/idd/stage" ); }
STAGE_MAIN="$(stage_of "$REPO")"
STAGE_WT="$(stage_of "$TMP/wt")"
[ "$STAGE_MAIN" = "$STAGE_WT" ] && pass "T6: a linked worktree resolves the same stage directory" \
  || fail "T6: a linked worktree resolves the same stage directory ($STAGE_MAIN vs $STAGE_WT)"
case "$STAGE_MAIN" in
  */.git/idd/stage) pass "T6: the stage directory is inside the git directory" ;;
  *) fail "T6: the stage directory is inside the git directory ($STAGE_MAIN)" ;;
esac
mkdir -p "$STAGE_MAIN"
printf '{"issue": 7}\n' > "$STAGE_MAIN/analysis-7.json"
for tree in "$REPO" "$TMP/wt"; do
  [ -z "$(cd "$tree" && git status --porcelain)" ] \
    && pass "T6: git status is clean with a stage file present ($(basename "$tree"))" \
    || fail "T6: git status is clean with a stage file present ($(basename "$tree"))"
done
(cd "$REPO" && git stash push -u -q >/dev/null 2>&1 || true)
[ -z "$(cd "$REPO" && git stash list)" ] && [ -f "$STAGE_MAIN/analysis-7.json" ] \
  && pass "T6: git stash -u takes nothing and leaves the stage file" \
  || fail "T6: git stash -u takes nothing and leaves the stage file"

# ── T7: CI wiring ────────────────────────────────────────────────
STEP="$(grep -A1 -- '- name: test-durable-workflows-690$' "$WORKFLOW" | tail -1 | sed 's/^ *//' || true)"
[ "$STEP" = "run: bash tests/test-durable-workflows-690.sh" ] \
  && pass "T7: dist-check.yml runs this test as one plain name/run step" \
  || fail "T7: dist-check.yml runs this test as one plain name/run step"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
