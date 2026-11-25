#!/usr/bin/env bash
# test-durable-workflows-690.sh — a cut-off run resumes instead of starting over (issue #690).
#
# Every skill was reviewed for cut-off resume. Eight gained rules; the pins below
# hold each rule to the built skill that ships it.
#
#   T1  each resume rule is in its built skill, located by anchor;
#   T2  the two shared references are bundled byte-identical into exactly the
#       skills that cite them, each listed in that skill's precheck, and the
#       three long-running skills, which resume from gi-progress.py and
#       gi-state.py, carry neither;
#   T3  the shared references stay closure leaves with no tracker call and no
#       gate heading;
#   T4  the ADR amendment names all nine skills and the reversed decisions;
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
STAGE_SKILLS="issue-analysis issue-triage issue-creator plan-to-issues"
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
issue-creator|ic-normalize-tail|Staged labels.*under 24 hours old, apply its labels.*only names that the live .gh label list --json name --limit 200. holds and the live issue lacks.*never the stage.s
issue-creator|ic-create-stage|.git hash-object. of the user.s input text.*never passed on a command line
issue-creator|ic-create-stage|first read this login.s newest issues live.*remove the stage and stop
issue-creator|ic-create-stage|Step 3.s duplicate check and Step 5.s preview run live
issue-creator|ic-create-stage|--body-file., never pasted into .--body.
issue-analysis|ia-inline-stage|A step is finished only once its .\[k/8\]. line has printed.*A partial .inline_steps. is never .findings.
issue-analysis|ia-resume|an inline run also reuses each step in .inline_steps.
plan-to-issues|pti-staged-draft|.created_at. under 24 hours old.*hashes to.*.draft_sha.
plan-to-issues|pti-staged-draft|Phase 3.s epic identity still runs live.*never created twice
issue-resolver|rs-0j-resume-entry|Without it, resume only when the record is the owner.s and idle.*age_s. is over 600.*Otherwise the record is ignored
issue-resolver|rs-0j-resume-entry|--no-resume.:\*\* never resume
issue-pr-review|rvm-progress-resume|Without it, resume only when the record is the owner.s and idle.*age_s. is over 600
issue-pr-review|rvm-progress-review-only|--mode review-only.*never reads, replaces or clears a fix-mode record.*never edits, commits, pushes or merges
auto-pilot|ap-implicit-resume|--issues. \(an issue.*would_reclaim. with .stale: true. and .same_host: true.*holder\.run_id.*would_reacquire.*lock\.run_id.*equals the .run_id. the first printed.*no lock at all
auto-pilot|ap-step10-skill-resume|whose .mode. is not .review-only.
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
      && grep -q 'A dry run writes none' "$name" \
      && grep -q 'Never write through a symlinked' "$name" \
      && grep -q 'atomic rename' "$name" \
      && grep -q 'Untrusted data' "$name" \
      && grep -q 'put no value from it on a command line' "$name" \
      && grep -q 'delete it, run the steps again' "$name" \
      && grep -q 'once its results are durable elsewhere, else at the terminal persist' "$name"; then
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
[ "$(bundled stage-file.md)" = "issue-analysis issue-creator issue-triage plan-to-issues" ] \
  && pass "T2: stage-file.md is bundled into exactly the four skills that write a stage" \
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
printf '%s\n' "$FLAT_AMEND" | grep -qE 'Decision reversed \(maintainer, 2026-11-25\):\*\* an auto run without .--resume. resumes by default' \
  && pass "T4: the reversed auto-mode --resume decision is recorded" \
  || fail "T4: the reversed auto-mode --resume decision is recorded"
printf '%s\n' "$FLAT_AMEND" | grep -qE '.--review-only. keeps a record of its own' \
  && pass "T4: the reversed --review-only decision is recorded" \
  || fail "T4: the reversed --review-only decision is recorded"
printf '%s\n' "$FLAT_AMEND" | grep -qE 'a bare run first runs two read-only probes' \
  && pass "T4: the reversed auto-pilot bare-run decision is recorded" \
  || fail "T4: the reversed auto-pilot bare-run decision is recorded"
printf '%s\n' "$FLAT_AMEND" | grep -qE 'A staged draft older than +24 hours is dropped' \
  && pass "T4: the conversation-path residual loss is recorded" \
  || fail "T4: the conversation-path residual loss is recorded"
if printf '%s\n' "$FLAT_AMEND" | grep -qE 'inline path \(no Agent tool\) writes no stage|keeps no record of the answers|are not recovered: they are the one step lost'; then
  fail "T4: the still-lost list drops the losses this change closed"
else
  pass "T4: the still-lost list drops the losses this change closed"
fi

# ── T5: mutation — the pins have teeth ───────────────────────────
# pins_ok <skills-root> — exit 0 only when every T1 pin passes there.
pins_ok() ( FAIL=0; pins "$1" >/dev/null 2>&1; [ "$FAIL" -eq 0 ] )

MUT="$TMP/skills"
fresh_copy() {
  rm -rf "$MUT"; mkdir -p "$MUT"
  local s
  for s in init-idd $RESUME_SKILLS auto-pilot issue-resolver issue-pr-review; do cp -R "$SKILLS/$s" "$MUT/$s"; done
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

for pair in "issue-creator/references/resume-cut-off.md" "issue-triage/references/stage-file.md" "plan-to-issues/references/stage-file.md"; do
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

# ── T8: the auto-pilot implicit-resume probes, run for real ──────
# A bare /auto-pilot resumes only when the dry-run lock probe would reclaim a
# stale lock (or re-acquire its own) whose run_id is the recorded state's. A
# finished run releases its lock, so its leftover state must read as no resume.
ST="$ROOT/src/shared/scripts/gi-state.py"
PD="$TMP/ap/.idd"; mkdir -p "$PD"
sh -c 'exit 0' & DEADPID=$!; wait "$DEADPID" || true
python3 "$ST" --lock --pid "$DEADPID" --dir "$PD" >/dev/null 2>&1
echo '{}' | python3 "$ST" --init --dir "$PD" >/dev/null 2>&1
probe() { # probe — prints "<status> <stale> <lock run_id> <state run_id>"
  local st lk
  st="$(python3 "$ST" --read --dry-run --dir "$PD" 2>/dev/null)"
  lk="$(python3 "$ST" --lock --resume --dry-run --pid $$ --dir "$PD" 2>/dev/null)"
  python3 -c 'import json,sys; s=json.loads(sys.argv[1] or "{}"); l=json.loads(sys.argv[2]); h=l.get("holder") if l.get("status")=="would_reclaim" else l.get("lock"); h=h or {}; print(l.get("status"), l.get("stale") and l.get("same_host"), h.get("run_id"), s.get("run_id"))' "$st" "$lk"
}
LOCK_BEFORE="$(cat "$PD/run.lock" 2>/dev/null)"; STATE_BEFORE="$(cat "$PD/run-state.json" 2>/dev/null)"
read -r P_STATUS P_STALE P_LOCK P_STATE <<<"$(probe)"
[ "$P_STATUS" = would_reclaim ] && [ "$P_STALE" = True ] && [ -n "$P_STATE" ] && [ "$P_LOCK" = "$P_STATE" ] \
  && pass "T8: a dead-pid lock naming the recorded run reads as an implicit resume" \
  || fail "T8: a dead-pid lock naming the recorded run reads as an implicit resume ($P_STATUS $P_STALE $P_LOCK $P_STATE)"
[ -n "$LOCK_BEFORE" ] && [ "$(cat "$PD/run.lock")" = "$LOCK_BEFORE" ] && [ "$(cat "$PD/run-state.json")" = "$STATE_BEFORE" ] \
  && pass "T8: the probes write nothing" || fail "T8: the probes write nothing"
python3 "$ST" --unlock --force --dir "$PD" >/dev/null 2>&1
# A finished run's leftover state plus a dead lock left by a different run: the
# probe's would-be payload carries the state's id, but the holder's id differs.
python3 - "$PD/run.lock" "$DEADPID" <<'PY'
import json, socket, sys, datetime
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
json.dump({"run_id": "20200101T000000Z-1", "pid": int(sys.argv[2]), "host": socket.gethostname(),
           "started_at": now, "heartbeat": now}, open(sys.argv[1], "w"))
PY
read -r P_STATUS P_STALE P_LOCK P_STATE <<<"$(probe)"
[ "$P_STATUS" = would_reclaim ] && [ "$P_LOCK" = 20200101T000000Z-1 ] && [ "$P_LOCK" != "$P_STATE" ] \
  && pass "T8: a dead lock from another run is no implicit resume (holder id differs)" \
  || fail "T8: a dead lock from another run is no implicit resume ($P_STATUS $P_LOCK $P_STATE)"
rm -f "$PD/run.lock"
read -r P_STATUS P_STALE P_LOCK P_STATE <<<"$(probe)"
[ "$P_STATUS" = would_acquire ] && [ -n "$P_STATE" ] \
  && pass "T8: no lock with a leftover state is no implicit resume (would_acquire)" \
  || fail "T8: no lock with a leftover state is no implicit resume ($P_STATUS)"
grep -qF 'no lock at all (a finished run releases its lock' "$SKILLS/auto-pilot/references/preflight.md" \
  && pass "T8: preflight.md names the released-lock case" || fail "T8: preflight.md names the released-lock case"

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
