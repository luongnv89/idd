#!/usr/bin/env bash
# test-rename-idd-537.sh — legacy gitissue names stay readable after the idd rename (#537).
#
# The rename moves every identifier to `idd`; each reader keeps the pre-rename
# name as a fallback, so a repository (or a base branch) that predates the
# rename still supplies its config, its trusted policy, its recipe and its
# run state. Every check is effect-based: it asserts what the fallback *does*,
# never only what a verdict field claims.
#
#   Q1   gi-secscan --policy-ref: a base ref carrying only `.gitissue.yml`
#        still applies its security.* (a leak blocks); (a) both names at the
#        ref → `.idd.yml` governs; (b) a branch-planted `.idd.yml` with
#        `allow_pattern: "."` has no effect; (c) neither name → defaults;
#        (d) `.idd.yml` present at the ref but a tree → exit 4, never legacy.
#   Q2   gi-recipe: a base ref carrying only `.gitissue-recipe.json` loads it;
#        both → the new recipe wins; an invalid new recipe is exit 3 even with
#        a valid legacy one; neither → absent with `recipe: null`.
#   Q4   gi-config: legacy-only → read, first_run false, ⚠ on stderr, exit 0;
#        both → `.idd.yml` wins. (The four upward walkers are covered in
#        tests/test-config-search-ceiling-parity-339.sh.)
#   Q5   gi-sensitive --classify: all four config/recipe names are
#        security-config.
#   Q6   gi-state migrates a legacy `.gitissue/` run once: an ownerless legacy
#        lock is released by `--unlock --force`; a legacy run state accepts
#        the first `--update`; a live legacy lock refuses acquisition and
#        nothing moves. The borrowed-skill teardown prose accepts both markers.
#   B7   every by-hand config read, recipe gate and policy-ref rule in the
#        skill sources and runtime docs names the legacy file as well.
#   B5   the reviewer's config-change warning names both config files and the
#        supersede case.
#   Q3   HTML markers: writers emit only `idd:`, readers accept `gitissue:` as
#        well. The QA parse grep shipped in the built reviewer counts a legacy
#        marker, an idd marker, and one of each as two (stale); idd-lint I01
#        accepts either normalized marker and fails on neither.
#
# Usage: bash tests/test-rename-idd-537.sh
# Returns: exit 0 if all checks pass, exit 1 on failure.

# No `set -e`: assertions report and continue.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "0" ]; then pass "$1"; else fail "$1"; fi; }

SCRIPTS="$REPO_ROOT/src/shared/scripts"
SECSCAN="$SCRIPTS/gi-secscan.py"
SECSCAN_BUILT="$REPO_ROOT/skills/issue-pr-review/references/scripts/gi-secscan.py"
RECIPE="$SCRIPTS/gi-recipe.py"
CONFIG="$SCRIPTS/gi-config.py"
SENSITIVE="$SCRIPTS/gi-sensitive.py"
STATE="$SCRIPTS/gi-state.py"
SCHEMA="$REPO_ROOT/docs/config-schema.md"
PILOT="$REPO_ROOT/.idd-recipe.json"

# Fixture repos must not inherit the developer's git configuration.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
unset IDD_AUTO_MODE

TMP="$(mktemp -d "${TMPDIR:-/tmp}/rename-537.XXXXXX")"
LIVE=""
cleanup_tmp() {
  [ -n "$LIVE" ] && kill "$LIVE" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup_tmp EXIT

# jget <json> <python expression over v> — print one field of a verdict.
jget() { python3 -c 'import json,sys; v=json.loads(sys.argv[1]); print(eval(sys.argv[2]))' "$1" "$2" 2>/dev/null; }

# new_repo <dir> — an empty repository on `main`.
new_repo() {
  mkdir -p "$1" && (
    cd "$1" || exit 1
    git init -q -b main
    git config user.email t@example.invalid
    git config user.name t
    git config commit.gpgsign false
    printf 'fixture\n' > README.md
  )
}
commit_all() { (cd "$1" && git add -A && git commit -qm "$2"); }

LEGACY_POLICY='security:
  extra_secret_value_pattern: "ZZPROBESECRET[0-9]{6}"
'
NEW_POLICY='security:
  extra_secret_value_pattern: "ZZPROBENEWKEY[0-9]{6}"
'

# policy_repo <dir> <leak text> — `main` already committed by the caller;
# branch `feat` adds leak.txt carrying <leak text>.
leak_branch() {
  (cd "$1" && git checkout -qb feat && printf 'token=%s\n' "$2" > leak.txt && git add leak.txt && git commit -qm leak)
}
# scan <dir> <script> — the reviewer's branch-diff scan under the base policy.
scan() { (cd "$1" && python3 "$2" --range main --policy-ref main --quiet 2>"$1.err"); }

echo "◆ Legacy gitissue names after the idd rename (issue #537)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ── Q1: --policy-ref reads the legacy policy at the base ref ─────────────
R="$TMP/q1"; new_repo "$R"; printf '%s' "$LEGACY_POLICY" > "$R/.gitissue.yml"; commit_all "$R" base
leak_branch "$R" ZZPROBESECRET123456
out="$(scan "$R" "$SECSCAN")"; rc=$?
[ "$rc" = "1" ] && [ "$(jget "$out" 'v["verdict"]')" = "block" ] && [ "$(jget "$out" 'v["policy_source"]')" = "ref:main" ]
check "Q1: a base ref with only .gitissue.yml still applies its security.* — the leak blocks (exit $rc)" "$?"
grep -qF '⚠ legacy .gitissue.yml found at main — rename to .idd.yml' "$R.err"
check "Q1: the legacy policy read prints the ⚠ rename line" "$?"
if [ -f "$SECSCAN_BUILT" ]; then
  out="$(scan "$R" "$SECSCAN_BUILT")"; rc=$?
  [ "$rc" = "1" ]; check "Q1: the bundled issue-pr-review copy blocks the same leak (exit $rc)" "$?"
fi
out="$(cd "$R" && python3 "$SECSCAN" --range main --no-config --quiet 2>/dev/null)"; rc=$?
[ "$rc" = "0" ]; check "Q1: control — without the base policy the probe value is not a secret (exit $rc)" "$?"

# (a) both names at the ref: .idd.yml governs, the legacy pattern is ignored.
R="$TMP/q1a"; new_repo "$R"; printf '%s' "$LEGACY_POLICY" > "$R/.gitissue.yml"; printf '%s' "$NEW_POLICY" > "$R/.idd.yml"; commit_all "$R" base
leak_branch "$R" ZZPROBESECRET123456
out="$(scan "$R" "$SECSCAN")"; rc=$?
[ "$rc" = "0" ]; check "Q1a: both names at the ref — the legacy-only pattern is not applied (exit $rc)" "$?"
(cd "$R" && printf 'token=ZZPROBENEWKEY123456\n' >> leak.txt && git commit -qam leak2)
out="$(scan "$R" "$SECSCAN")"; rc=$?
[ "$rc" = "1" ]; check "Q1a: both names at the ref — .idd.yml's pattern governs (exit $rc)" "$?"

# (b) a branch-planted .idd.yml cannot switch the base's legacy policy off.
R="$TMP/q1b"; new_repo "$R"; printf '%s' "$LEGACY_POLICY" > "$R/.gitissue.yml"; commit_all "$R" base
leak_branch "$R" ZZPROBESECRET123456
(cd "$R" && printf 'security:\n  allow_pattern: "."\n' > .idd.yml && git add .idd.yml && git commit -qm plant)
printf 'security:\n  allow_pattern: "."\n' > "$R/.gitissue.yml"
out="$(scan "$R" "$SECSCAN")"; rc=$?
[ "$rc" = "1" ] && [ "$(jget "$out" 'v["policy_source"]')" = "ref:main" ]
check "Q1b: a branch-planted .idd.yml allow-all has no effect on the base's legacy policy (exit $rc)" "$?"

# (c) neither name at the ref: the built-in defaults, never the work tree.
R="$TMP/q1c"; new_repo "$R"; commit_all "$R" base
leak_branch "$R" ZZPROBESECRET123456
printf '%s' "$LEGACY_POLICY" > "$R/.gitissue.yml"
out="$(scan "$R" "$SECSCAN")"; rc=$?
[ "$rc" = "0" ] && [ "$(jget "$out" 'v["policy_source"]')" = "ref:main" ]
check "Q1c: neither name at the ref — defaults, the work-tree legacy file is not read (exit $rc)" "$?"

# (d) .idd.yml present at the ref but not a blob: exit 4, never legacy.
R="$TMP/q1d"; new_repo "$R"; printf '%s' "$LEGACY_POLICY" > "$R/.gitissue.yml"
mkdir "$R/.idd.yml"; printf 'x\n' > "$R/.idd.yml/inner"; commit_all "$R" base
leak_branch "$R" ZZPROBESECRET123456
out="$(scan "$R" "$SECSCAN")"; rc=$?
[ "$rc" = "4" ]; check "Q1d: a tree-shaped .idd.yml at the ref is Unavailable (exit $rc), not a legacy fallback" "$?"

# ── Q2: gi-recipe reads the legacy recipe at the base ref ────────────────
recipe_plan() { (cd "$1" && echo landing.html | python3 "$RECIPE" --ref HEAD --consumer resolve --changed - --plan 2>"$1.err"); }
R="$TMP/q2"; new_repo "$R"; cp "$PILOT" "$R/.gitissue-recipe.json"; commit_all "$R" base
out="$(recipe_plan "$R")"; rc=$?
[ "$rc" = "0" ] && [ "$(jget "$out" 'v["status"]')" = "planned" ] \
  && [ "$(jget "$out" '[c["name"] for c in v["capabilities"] if c["mapped"]]')" = "['landing']" ]
check "Q2: a base ref with only .gitissue-recipe.json is loaded — landing planned (exit $rc)" "$?"
[ "$(jget "$out" 'v["recipe"]')" = ".gitissue-recipe.json" ]
check "Q2: the verdict names the recipe file actually loaded" "$?"
grep -qF '⚠ legacy .gitissue-recipe.json found at HEAD' "$R.err"
check "Q2: the legacy recipe read prints the ⚠ rename line" "$?"

python3 - "$PILOT" "$R/new.json" <<'PY'
import json, sys
recipe = json.load(open(sys.argv[1], encoding="utf-8"))
first = dict(recipe["capabilities"][0], name="newcap", paths=["*.html"])
recipe["capabilities"] = [first]
json.dump(recipe, open(sys.argv[2], "w", encoding="utf-8"))
PY
mv "$R/new.json" "$R/.idd-recipe.json"; commit_all "$R" both
out="$(recipe_plan "$R")"; rc=$?
[ "$rc" = "0" ] && [ "$(jget "$out" '[c["name"] for c in v["capabilities"]]')" = "['newcap']" ] \
  && [ "$(jget "$out" 'v["recipe"]')" = ".idd-recipe.json" ]
check "Q2: both names at the ref — .idd-recipe.json wins (exit $rc)" "$?"

printf '{' > "$R/.idd-recipe.json"; commit_all "$R" invalid
out="$(recipe_plan "$R")"; rc=$?
[ "$rc" = "3" ]; check "Q2: an invalid .idd-recipe.json is exit 3 even beside a valid legacy recipe (exit $rc)" "$?"

R="$TMP/q2none"; new_repo "$R"; commit_all "$R" base
out="$(recipe_plan "$R")"; rc=$?
[ "$rc" = "0" ] && [ "$(jget "$out" 'v["status"]')" = "absent" ] && [ "$(jget "$out" 'v["recipe"]')" = "None" ]
check "Q2: neither recipe at the ref — absent with recipe null (exit $rc)" "$?"

# ── Q4: gi-config reads a legacy-only config ─────────────────────────────
C="$TMP/q4"; mkdir -p "$C"
printf 'resolve:\n  max_commits: 7\n' > "$C/.gitissue.yml"
out="$(cd "$C" && python3 "$CONFIG" --schema "$SCHEMA" 2>"$C.err")"; rc=$?
[ "$rc" = "0" ] && [ "$(jget "$out" 'v["first_run"]')" = "False" ] \
  && [ "$(jget "$out" 'v["config_file"]')" = ".gitissue.yml" ] \
  && [ "$(jget "$out" 'v["config"]["resolve.max_commits"]')" = "7" ]
check "Q4: legacy-only .gitissue.yml is read — first_run false, its value applied (exit $rc)" "$?"
grep -qF '⚠ legacy .gitissue.yml found — rename to .idd.yml' "$C.err"
check "Q4: the legacy config read prints the ⚠ rename line on stderr" "$?"
printf 'resolve:\n  max_commits: 5\n' > "$C/.idd.yml"
out="$(cd "$C" && python3 "$CONFIG" --schema "$SCHEMA" 2>"$C.err")"; rc=$?
[ "$rc" = "0" ] && [ "$(jget "$out" 'v["config_file"]')" = ".idd.yml" ] \
  && [ "$(jget "$out" 'v["config"]["resolve.max_commits"]')" = "5" ] \
  && grep -qF 'legacy .gitissue.yml ignored' "$C.err"
check "Q4: both names — .idd.yml wins and the legacy file is reported ignored (exit $rc)" "$?"
rm -f "$C/.idd.yml"; printf 'resolve:\n  max_commits: "ten"\n' > "$C/.gitissue.yml"
(cd "$C" && python3 "$CONFIG" --schema "$SCHEMA" >/dev/null 2>"$C.err"); rc=$?
[ "$rc" = "3" ] && grep -qF '✗ Invalid .gitissue.yml:' "$C.err"
check "Q4: an invalid legacy config is exit 3 naming the file parsed (exit $rc)" "$?"

# ── Q5: all four names are security-config ───────────────────────────────
out="$(printf '%s' '{"labels":[],"paths":[".idd.yml",".gitissue.yml",".idd-recipe.json",".gitissue-recipe.json"]}' \
  | python3 "$SENSITIVE" --classify)"
[ "$(jget "$out" 'sorted(r["value"] for r in v["reasons"] if r["class"] == "security-config")')" \
  = "['.gitissue-recipe.json', '.gitissue.yml', '.idd-recipe.json', '.idd.yml']" ]
check "Q5: gi-sensitive classifies .idd.yml, .gitissue.yml and both recipe names as security-config" "$?"

# ── Q6: gi-state migrates a legacy .gitissue/ run ────────────────────────
S="$TMP/q6-unlock"; mkdir -p "$S/.gitissue"
(cd "$S" && python3 "$STATE" --dir .gitissue --lock >/dev/null 2>&1)
out="$(cd "$S" && python3 "$STATE" --unlock --force 2>"$S.err")"; rc=$?
[ "$rc" = "0" ] && [ "$(jget "$out" 'v["status"]')" = "released" ] \
  && [ ! -e "$S/.gitissue/run.lock" ] && [ ! -e "$S/.idd/run.lock" ]
check "Q6: an ownerless legacy lock is migrated, then released by --unlock --force (exit $rc)" "$?"
grep -qF '⚠ migrated legacy .gitissue/run.lock → .idd/run.lock' "$S.err"
check "Q6: the migration prints one ⚠ line per moved file" "$?"

S="$TMP/q6-update"; mkdir -p "$S/.gitissue"
(cd "$S" && printf '{}' | python3 "$STATE" --dir .gitissue --init >/dev/null 2>&1)
legacy_id="$(jget "$(cat "$S/.gitissue/run-state.json")" 'v["run_id"]')"
CHK='{"phase":"review","current":{"issue":42,"title":"Fixture","branch":"fix/42-fixture","pr":87,"phase":"review"}}'
out="$(cd "$S" && printf '%s' "$CHK" | python3 "$STATE" --update 2>/dev/null)"; rc=$?
[ "$rc" = "0" ] && [ "$(jget "$out" 'v["run_id"]')" = "$legacy_id" ] \
  && [ -f "$S/.idd/run-state.json" ] && [ ! -e "$S/.gitissue/run-state.json" ]
check "Q6: a legacy run state accepts the first --update, now under .idd/ (exit $rc)" "$?"

S="$TMP/q6-live"; mkdir -p "$S/.gitissue"
sleep 300 & LIVE=$!
(cd "$S" && python3 "$STATE" --dir .gitissue --lock --pid "$LIVE" >/dev/null 2>&1)
out="$(cd "$S" && python3 "$STATE" --lock 2>/dev/null)"; rc=$?
[ "$rc" = "3" ] && [ "$(jget "$out" 'v["status"]')" = "held" ] \
  && [ -f "$S/.gitissue/run.lock" ] && [ ! -e "$S/.idd/run.lock" ]
check "Q6: a live legacy lock refuses acquisition and nothing is moved (exit $rc)" "$?"
kill "$LIVE" 2>/dev/null; wait "$LIVE" 2>/dev/null; LIVE=""

for f in src/skills/issue-resolver/references/steps/step-3-implement.md \
         src/skills/issue-resolver/references/error-messages.md \
         src/skills/auto-pilot/references/phases/phase-0-lock-resume.md; do
  grep -qF '.idd-borrowed' "$REPO_ROOT/$f" && grep -qF '.gitissue-borrowed' "$REPO_ROOT/$f"
  check "Q6: $f accepts both borrow markers" "$?"
done

# ── B7: prose degrade paths and gates name the legacy file ───────────────
for f in src/skills/auto-pilot/SKILL.source.md \
         src/skills/issue-analysis/SKILL.source.md \
         src/skills/issue-creator/SKILL.source.md \
         src/skills/issue-pr-review/SKILL.source.md \
         src/skills/issue-pr-review/references/review-loop-mechanics.md \
         src/skills/issue-resolver/SKILL.source.md \
         src/skills/issue-triage/SKILL.source.md \
         src/skills/plan-to-issues/SKILL.source.md \
         src/internal-skills/idd-doctor/SKILL.source.md \
         docs/pre-commit-security.md; do
  grep -qE '\.idd\.yml.*\.gitissue\.yml' "$REPO_ROOT/$f"
  check "B7: $f reads .idd.yml, else legacy .gitissue.yml" "$?"
done
for f in src/skills/issue-pr-review/SKILL.source.md \
         src/skills/issue-resolver/SKILL.source.md \
         src/skills/issue-resolver/references/report-templates.md \
         docs/ui-review.md; do
  grep -qF '.gitissue-recipe.json' "$REPO_ROOT/$f"
  check "B7: $f gates the recipe on .idd-recipe.json or legacy .gitissue-recipe.json" "$?"
done
grep -qF "awk '/^autopilot:/{f=1;next} /^[^[:space:]#]/{f=0} f' \"\$cfg\"" "$REPO_ROOT/src/internal-skills/idd-doctor/SKILL.source.md" \
  && grep -qF 'cfg=.idd.yml; [ -f "$cfg" ] || cfg=.gitissue.yml' "$REPO_ROOT/src/internal-skills/idd-doctor/SKILL.source.md"
check "B7: idd-doctor's awk reads .idd.yml, else the legacy file" "$?"

# File-level invariant: a read site for the config, the policy ref, or the
# recipe never names only the new file.
invariant="$(cd "$REPO_ROOT" && for f in $(git ls-files 'src/skills' 'src/internal-skills' | grep '\.md$') \
    docs/pre-commit-security.md docs/ui-review.md docs/config-schema.md docs/auto-mode.md docs/platform-github.md; do
  if grep -qF '.idd-recipe.json' "$f" && ! grep -qF '.gitissue-recipe.json' "$f"; then echo "$f (recipe)"; fi
  if grep -E '([Ll]oad|Read) `\.idd\.yml`|read it yourself|against by hand|--policy-ref.*\.idd\.yml|\.idd\.yml.*at the base ref' "$f" \
       | grep -qF '.idd.yml' && ! grep -qF '.gitissue.yml' "$f"; then echo "$f (config)"; fi
done)"
[ -z "$invariant" ]; check "B7: no config/policy/recipe read site names only the new file${invariant:+ — $invariant}" "$?"

# ── B5: the reviewer's config-change warning ─────────────────────────────
MECH="$REPO_ROOT/src/skills/issue-pr-review/references/prepass-tests-ci-mechanics.md"
grep -qF 'adds or modifies `.idd.yml` or `.gitissue.yml`' "$MECH" && grep -qF 'supersedes that file' "$MECH"
check "B5: the review warns on either config file and on .idd.yml superseding .gitissue.yml" "$?"

# ── Q3: HTML markers — write idd:, read both ─────────────────────────────
# The QA parse grep, exactly as the BUILT reviewer ships it, located by its
# anchor rather than a line number, then run on fixture bodies.
BUILT_LOOP="$REPO_ROOT/skills/issue-pr-review/references/review-loop-mechanics.md"
Q3_LINE="$(awk '/a:rvm-parse-marker/{f=1} f && /^grep -oE /{print; exit}' "$BUILT_LOOP")"
[ -n "$Q3_LINE" ]; check "Q3: the built reviewer ships a QA-marker parse grep" "$?"
# q3_count <body> — how many markers the shipped grep finds in a PR body.
q3_count() { local body="$1"; eval "$Q3_LINE" | grep -c . ; }
HEAD40="0123456789abcdef0123456789abcdef01234567"
LEGACY_QA="<!-- gitissue:qa v1 head=$HEAD40 profile=full cycles=1 review=clean -->"
IDD_QA="<!-- idd:qa v1 head=$HEAD40 profile=full cycles=1 review=clean -->"
[ "$(q3_count "$(printf 'Closes #1\n\nbody\n%s' "$LEGACY_QA")")" = "1" ]
check "Q3: a legacy-only gitissue:qa marker is one match (parsed, not absent)" "$?"
[ "$(q3_count "$(printf 'Closes #1\n\nbody\n%s' "$IDD_QA")")" = "1" ]
check "Q3: an idd-only marker is one match" "$?"
[ "$(q3_count "$(printf 'Closes #1\n%s\nbody\n%s' "$LEGACY_QA" "$IDD_QA")")" = "2" ]
check "Q3: one marker of each namespace is two matches — stale by the >1 rule" "$?"
[ "$(q3_count "$(printf '<!-- idd:normalized v1 -->\n<!-- gitissue:normalized v1 -->\n')")" = "0" ]
check "Q3: normalized markers are not QA markers (vacuity guard)" "$?"

PR_SKILL="$REPO_ROOT/src/skills/issue-pr-review/SKILL.source.md"
grep -F 'ends a clean QA loop by writing' "$PR_SKILL" | grep -qF 'gitissue:qa'
check "Q3: the QA handoff gate names the legacy gitissue:qa marker" "$?"
grep -F 'any trailing `<!-- idd:qa v1' "$PR_SKILL" | grep -qF 'gitissue:qa'
check "Q3: the Closes-body re-check accepts a legacy gitissue:qa marker" "$?"

# idd-lint I01 accepts either normalized marker; neither fails I01 itself.
LINT="$REPO_ROOT/scripts/idd-lint.py"
cat > "$TMP/q3-idd.md" <<'EOF'
<!-- idd:normalized v1 -->

## Type

Feature

## Description

Add a dark mode toggle.

## Acceptance Criteria

- [ ] Toggle appears in settings

## Metadata

**Priority:** P2
**Effort:** M
**Labels:** feature
EOF
sed '1s/idd:normalized/gitissue:normalized/' "$TMP/q3-idd.md" > "$TMP/q3-legacy.md"
sed '1d' "$TMP/q3-idd.md" > "$TMP/q3-none.md"
for kind in idd legacy; do
  out="$(python3 "$LINT" issue "$TMP/q3-$kind.md" 2>&1)"; st=$?
  [ "$st" = "0" ] && printf '%s' "$out" | grep -qF '✓ [I01] normalization marker present (v1)'
  check "Q3: idd-lint I01 accepts the $kind normalized marker" "$?"
done
out="$(python3 "$LINT" issue "$TMP/q3-none.md" 2>&1)"; st=$?
[ "$st" = "1" ] && printf '%s' "$out" | grep -qF '✗ [I01] normalization marker'
check "Q3: idd-lint I01 fails a body carrying neither marker" "$?"

# Writers emit only idd:.
for tpl in bug feature improvement; do
  [ "$(head -1 "$REPO_ROOT/src/skills/issue-creator/templates/$tpl.md")" = '<!-- idd:normalized v1 -->' ]
  check "Q3: the $tpl template's first line is the idd normalized marker" "$?"
done
for f in src/skills/issue-resolver/SKILL.source.md src/skills/issue-resolver/references/report-templates.md; do
  grep -qF '<!-- idd:qa v1 head={head_sha} ' "$REPO_ROOT/$f" && ! grep -qF 'gitissue:qa' "$REPO_ROOT/$f"
  check "Q3: $f writes the QA marker as idd:qa only" "$?"
done
RPT="$TMP/q3-report"; mkdir -p "$RPT"
printf '{"run_id":"r537"}' | python3 "$STATE" --init --dir "$RPT" >/dev/null 2>&1
printf '%s' '{"run_id":"r537","markdown":"summary\n"}' | python3 "$STATE" --report --dir "$RPT" >/dev/null 2>&1
head -1 "$RPT/last-run-report.md" 2>/dev/null | grep -q '^<!-- idd:run-report v1 ' && ! grep -q 'gitissue' "$RPT/last-run-report.md"
check "Q3: gi-state --report opens the report with an idd:run-report marker" "$?"
# No writer anywhere in src/ emits a legacy marker: every `<!-- gitissue:`
# literal sits on a line that also names the idd form (a dual-read mention).
legacy_writers="$(cd "$REPO_ROOT" && git grep -nF '<!-- gitissue:' -- src | grep -vF 'idd:' || true)"
[ -z "$legacy_writers" ]; check "Q3: no source line emits a gitissue: marker on its own${legacy_writers:+ — $legacy_writers}" "$?"

# Readers name both namespaces.
grep -F 'Look for `<!-- idd:normalized v1 -->`' "$REPO_ROOT/src/skills/issue-creator/references/modes.md" | grep -qF 'gitissue:normalized'
check "Q3: issue-creator's already-normalized detection accepts the legacy marker" "$?"
grep -F '**Trigger:** Issue body contains `<!-- idd:normalized v1 -->`' "$REPO_ROOT/src/skills/issue-creator/references/error-messages.md" | grep -qF 'gitissue:normalized'
check "Q3: issue-creator's already-normalized message triggers on the legacy marker" "$?"
grep -F 'the body lacks a `<!-- idd:normalized v1 -->` marker' "$REPO_ROOT/src/skills/issue-resolver/SKILL.source.md" | grep -qF 'gitissue:normalized'
check "Q3: the resolver's auto_normalize check counts a legacy marker as normalized" "$?"
for f in src/skills/plan-to-issues/SKILL.source.md \
         src/skills/plan-to-issues/references/phase-contracts.md \
         src/skills/plan-to-issues/references/epic-dashboard.md; do
  grep -F '<!-- idd:normalized v1 -->' "$REPO_ROOT/$f" | grep -qF 'legacy `gitissue:`'
  check "Q3: $f preserves either normalized marker byte-for-byte" "$?"
done

grep -q 'test-rename-idd-537' "$REPO_ROOT/.github/workflows/dist-check.yml"
check "the suite is registered in dist-check.yml" "$?"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
