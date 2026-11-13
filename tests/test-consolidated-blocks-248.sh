#!/usr/bin/env bash
# test-consolidated-blocks-248.sh — guard issue #248's single-home consolidation.
#
# #248 gave each duplicated instruction block exactly one authoritative home and
# reduced every other occurrence to a one-line pointer. These assertions fail if
# a future edit re-introduces a second copy of one of those rules.
#
# Covers:
#   AC1 — each consolidated rule is stated once; other occurrences are pointers
#   #550 — `review.auto_merge` has one definition (T10)
#   #552 — the unattended *Merge floor* has one home (T11)
#   #560 — no authored file is byte-identical in two skills (T12); the
#          Self-Improve rules have one home and each skill keeps a pointer (T13)
#   AC2 — UI-review mechanics live in one shared doc bundled into BOTH
#         issue-resolver and issue-pr-review

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT" || exit 1

PASSED=0
FAILED=0

pass() { printf '  ✓ %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf '  ✗ %s\n' "$1"; FAILED=$((FAILED + 1)); }

# count_matches <pattern> <file...> — total matching lines across files
count_matches() {
  local pattern="$1"; shift
  grep -c -E "$pattern" "$@" 2>/dev/null | awk -F: '{ s += $NF } END { print s + 0 }'
}

# count_flat <pattern> <file...> — occurrences of a pattern with newlines
# collapsed to single spaces, so hard-wrapped prose still matches.
count_flat() {
  local pattern="$1"; shift
  local total=0 f n
  for f in "$@"; do
    n=$(tr '\n' ' ' < "$f" | tr -s ' ' | grep -o -E "$pattern" | wc -l | tr -d ' ')
    total=$((total + n))
  done
  printf '%s\n' "$total"
}

# has_flat <pattern> <file> — pattern present after newline flattening
has_flat() {
  tr '\n' ' ' < "$2" | tr -s ' ' | grep -q -E "$1"
}

SHARED_UI="docs/ui-review.md"
RESOLVER_SKILL="src/skills/issue-resolver/SKILL.source.md"
. "$(cd "$(dirname "$0")" && pwd)/lib/spec.bash"  # spec_concat — split reference specs read as one file (#323)
RESOLVER_PIPELINE="$(spec_concat "src/skills/issue-resolver/references/pipeline-steps.md")"
PR_SKILL="src/skills/issue-pr-review/SKILL.source.md"
PR_UI="src/skills/issue-pr-review/references/ui-review-mechanics.md"
PR_PREPASS="src/skills/issue-pr-review/references/prepass-tests-ci-mechanics.md"
AP_SKILL="src/skills/auto-pilot/SKILL.source.md"
AP_PHASES="$(spec_concat "src/skills/auto-pilot/references/phases.md")"
AP_CONFIG="src/skills/auto-pilot/references/configuration.md"
AP_LIST="src/skills/auto-pilot/references/explicit-list-mode.md"
CREATOR_SKILL="src/skills/issue-creator/SKILL.source.md"
CREATOR_MODEL="src/skills/issue-creator/references/model-suggestion.md"
TRIAGE_SKILL="src/skills/issue-triage/SKILL.source.md"
EFFORT_DOC="docs/agent-model-effort.md"

printf '◆ #248 — consolidated instruction blocks\n'
printf '┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n'

# ───────────────────────────────────────────────────────────
# T1 (AC2): shared UI-review doc exists and is the single home
# ───────────────────────────────────────────────────────────
if [ -f "$SHARED_UI" ]; then
  pass "T1.1: shared UI-review doc exists at $SHARED_UI"
else
  fail "T1.1: missing shared UI-review doc $SHARED_UI"
fi

# The headless display-environment probe is the most-copied UI snippet.
# It must appear exactly once across the whole src/ + docs/ tree: in the
# shared doc only.
ui_env_homes=$(count_matches 'ui_env="no-GUI server"' "$SHARED_UI" \
  "$RESOLVER_PIPELINE" "$PR_UI" "$RESOLVER_SKILL" "$PR_SKILL")
if [ "$ui_env_homes" -eq 1 ]; then
  pass "T1.2: display-environment probe stated once (shared doc only)"
else
  fail "T1.2: display-environment probe appears $ui_env_homes times — expected 1"
fi

# The UI keyword list is the other large duplicate.
kw_homes=$(count_matches 'dark mode.*button.*form' "$SHARED_UI" \
  "$RESOLVER_PIPELINE" "$PR_UI")
if [ "$kw_homes" -eq 1 ]; then
  pass "T1.3: UI keyword list stated once (shared doc only)"
else
  fail "T1.3: UI keyword list appears $kw_homes times — expected 1"
fi

# Both consuming skills must point at the shared doc.
for f in "$RESOLVER_PIPELINE" "$PR_UI"; do
  if grep -qF 'docs/ui-review.md' "$f"; then
    pass "T1.4: $(basename "$(dirname "$(dirname "$f")")")/$(basename "$f") points to the shared UI doc"
  else
    fail "T1.4: $f does not point to docs/ui-review.md"
  fi
done

# Skill-specific deltas must NOT move into the shared doc.
if ! grep -qF 'gh pr diff' "$SHARED_UI" && ! grep -qF 'resolve.ui_review' "$SHARED_UI"; then
  pass "T1.5: shared UI doc stays skill-agnostic (no per-skill diff cmd or config key)"
else
  fail "T1.5: shared UI doc leaked a per-skill delta"
fi

# ───────────────────────────────────────────────────────────
# T2 (AC2): the shared doc is bundled into BOTH skills
# ───────────────────────────────────────────────────────────
for skill in issue-resolver issue-pr-review; do
  if [ -f "skills/$skill/references/docs/ui-review.md" ]; then
    pass "T2.1: ui-review.md bundled into skills/$skill/references/docs/"
  else
    fail "T2.1: ui-review.md NOT bundled into skills/$skill — run ./scripts/build.sh"
  fi
done

for f in "$RESOLVER_SKILL" "$PR_SKILL"; do
  if grep -qF 'references/docs/ui-review.md' "$f"; then
    pass "T2.2: $(basename "$(dirname "$f")") precheck list includes references/docs/ui-review.md"
  else
    fail "T2.2: $f precheck list missing references/docs/ui-review.md"
  fi
done

# ───────────────────────────────────────────────────────────
# T3 (AC1): auto-pilot mode resolution has one home (SKILL.md)
# ───────────────────────────────────────────────────────────
if grep -qF 'Resolution rules' "$AP_SKILL"; then
  pass "T3.1: auto-pilot SKILL.md holds the mode *Resolution rules*"
else
  fail "T3.1: auto-pilot SKILL.md lost the mode *Resolution rules* home"
fi

# The legacy auto_merge → aggressive/conservative mapping must be spelled out
# only in SKILL.md; references point at it.
legacy_homes=$(count_matches 'auto_merge: true.*aggressive|auto_merge`?: `?true`? (→|≈) ?`?aggressive' \
  "$AP_SKILL" "$AP_PHASES" "$AP_CONFIG")
if [ "$legacy_homes" -eq 1 ]; then
  pass "T3.2: legacy auto_merge mapping stated exactly once"
else
  fail "T3.2: legacy auto_merge mapping appears $legacy_homes times — expected exactly 1"
fi

for f in "$AP_PHASES" "$AP_CONFIG"; do
  if grep -qF 'Merge Modes' "$f"; then
    pass "T3.3: $(basename "$f") points to *Merge Modes* in SKILL.md"
  else
    fail "T3.3: $(basename "$f") does not point to *Merge Modes*"
  fi
done

# ───────────────────────────────────────────────────────────
# T4 (AC1): --review-only has one authoritative home
# ───────────────────────────────────────────────────────────
if grep -qF 'Review-only mode (`--review-only`) — authoritative definition' "$PR_SKILL"; then
  pass "T4.1: issue-pr-review SKILL.md declares the --review-only home"
else
  fail "T4.1: issue-pr-review SKILL.md missing the authoritative --review-only definition"
fi

# The detection-only tool-flag detail belongs to that home only.
detect_homes=$(count_matches 'without .--fix.*--write|check mode' "$PR_SKILL" "$PR_PREPASS")
if [ "$detect_homes" -eq 1 ]; then
  pass "T4.2: --review-only detection-only detail stated exactly once"
else
  fail "T4.2: --review-only detection-only detail appears $detect_homes times — expected exactly 1"
fi

if grep -qF 'Review-only mode' "$PR_PREPASS"; then
  pass "T4.3: prepass mechanics point back to *Review-only mode*"
else
  fail "T4.3: prepass mechanics lost the pointer to *Review-only mode*"
fi

# ───────────────────────────────────────────────────────────
# T5 (AC1): batch run-log fan-out compressed but rule-complete
# ───────────────────────────────────────────────────────────
fanout_len=$(awk '/^#### Run-log fan-out for the batch/{f=1} f{n++} f&&/^For non-batched issues/{print n; exit}' "$AP_LIST")
if [ -n "$fanout_len" ] && [ "$fanout_len" -lt 60 ]; then
  pass "T5.1: fan-out section compressed to $fanout_len lines (was 86)"
else
  fail "T5.1: fan-out section is ${fanout_len:-?} lines — expected under 60"
fi

# Every rule the 86-line prose encoded must survive the compression.
declare -a FANOUT_RULES=(
  'attempted set'
  'never'
  'issues_resolved'
  'individual retry'
  'zero'
  'qa_cycles'
  'duration_s'
  'writes no run-log line'
)
missing_rule=0
for r in "${FANOUT_RULES[@]}"; do
  grep -qF "$r" "$AP_LIST" || { fail "T5.2: fan-out lost rule token '$r'"; missing_rule=1; }
done
[ "$missing_rule" -eq 0 ] && pass "T5.2: all fan-out rule tokens survive the compression"

if grep -qE '^\| Disposition of an attempted issue' "$AP_LIST"; then
  pass "T5.3: fan-out uses a disposition table as its single home"
else
  fail "T5.3: fan-out disposition table missing"
fi

# ───────────────────────────────────────────────────────────
# T6 (AC1): two-model rendering rule has one home
# ───────────────────────────────────────────────────────────
if grep -qF 'two-model rendering rule (single home)' "$CREATOR_MODEL"; then
  pass "T6.1: model-suggestion.md declares the two-model rendering home"
else
  fail "T6.1: model-suggestion.md missing the two-model rendering home marker"
fi

two_model_homes=$(count_flat 'one OpenAI model and one Anthropic model' \
  "$CREATOR_SKILL" "$CREATOR_MODEL")
if [ "$two_model_homes" -eq 1 ]; then
  pass "T6.2: two-model rule stated once (model-suggestion.md only)"
else
  fail "T6.2: two-model rule appears $two_model_homes times — expected 1"
fi

pointer_count=$(count_flat 'two-model rendering rule' "$CREATOR_SKILL")
if [ "$pointer_count" -ge 3 ]; then
  pass "T6.3: SKILL.md's $pointer_count mentions are all pointers to that home"
else
  fail "T6.3: expected >=3 pointers in SKILL.md, found $pointer_count"
fi

# ───────────────────────────────────────────────────────────
# T7 (AC1): resolver light-profile collapse list has one home
# ───────────────────────────────────────────────────────────
if grep -qF 'What `light` collapses — the single home for this rule' "$RESOLVER_SKILL"; then
  pass "T7.1: resolver Step 0g declares the light-profile home"
else
  fail "T7.1: resolver Step 0g missing the light-profile home marker"
fi

# Per-step blocks must be pointers, not restatements.
if [ "$(count_flat 'profile table in \*Step 0g\*' "$RESOLVER_SKILL")" -ge 4 ]; then
  pass "T7.2: per-step light blocks point back to the Step 0g table"
else
  fail "T7.2: fewer than 4 per-step pointers to the Step 0g profile table"
fi

# The shared doc must not restate any skill's per-step collapse list.
if has_flat 'do not restate any skill' "$EFFORT_DOC" \
   && ! grep -qE 'skips the 3-option synthesis|caps QA at' "$EFFORT_DOC"; then
  pass "T7.3: agent-model-effort.md defers per-step collapse lists to each skill"
else
  fail "T7.3: agent-model-effort.md still restates a skill's per-step collapse list"
fi

# ───────────────────────────────────────────────────────────
# T8 (AC1): triage cached-view rendering has one home
# ───────────────────────────────────────────────────────────
triage_tables=$(count_matches '───┼────' "$TRIAGE_SKILL")
if [ "$triage_tables" -eq 1 ]; then
  pass "T8.1: cached triage table rendered once in SKILL.md"
else
  fail "T8.1: cached triage table rendered $triage_tables times — expected 1"
fi

if grep -qF 'Render the cached report' "$TRIAGE_SKILL"; then
  pass "T8.2: *Step 3 — Render the cached report* is the rendering home"
else
  fail "T8.2: triage lost its cached-render home section"
fi

# ───────────────────────────────────────────────────────────
# T10 (#550): `review.auto_merge` has one definition
# ───────────────────────────────────────────────────────────
# The key was specified three ways ("auto mode overrides to true", "merges only
# when review.auto_merge is true", "Honored only in --auto mode"). One sentence
# in issue-pr-review Step 7 (*Merge rule*) now defines when the skill merges;
# the inline defaults, the config-key table and the schema comment point to it.
MERGE_RULE='`/issue-pr-review` merges a PR only when `review.auto_merge` is `true` and the PR is clean, in interactive and `--auto` runs alike, and never under `--no-merge` or `--review-only`.'
PR_LOOP="src/skills/issue-pr-review/references/review-loop-mechanics.md"
SCHEMA="docs/config-schema.md"
AP_PROMPTS="src/skills/auto-pilot/references/subagent-prompts.md"

rule_src=$(grep -rlF -- "$MERGE_RULE" src docs | wc -l | tr -d ' ')
rule_home=$(grep -cF -- "$MERGE_RULE" "$PR_SKILL")
if [ "$rule_src" -eq 1 ] && [ "$rule_home" -eq 1 ]; then
  pass "T10.1: the merge rule is stated exactly once, in issue-pr-review SKILL.md"
else
  fail "T10.1: merge rule found in $rule_src file(s), $rule_home time(s) in the home — expected 1/1"
fi

if grep -F -- "$MERGE_RULE" "$PR_SKILL" | grep -qF '<!-- a:rv-merge-rule -->'; then
  pass "T10.2: the merge rule carries its a:rv-merge-rule anchor"
else
  fail "T10.2: the merge rule lost its a:rv-merge-rule anchor"
fi

if [ -f skills/issue-pr-review/SKILL.md ] && [ "$(grep -cF -- "$MERGE_RULE" skills/issue-pr-review/SKILL.md)" -eq 1 ]; then
  pass "T10.3: the built issue-pr-review SKILL.md carries the merge rule once"
else
  fail "T10.3: the built issue-pr-review SKILL.md does not carry the merge rule exactly once"
fi

# Each of the three former definition sites now points to *Merge rule* and
# carries no rule of its own.
inline_defaults=$(grep -F 'Inline defaults:' "$PR_SKILL" | grep -F 'review.auto_merge')
loop_row=$(grep -F '| `review.auto_merge' "$PR_LOOP")
schema_comment=$(grep -B3 -E '^  auto_merge: false' "$SCHEMA")
for pair in "SKILL.md inline defaults:$inline_defaults" \
            "review-loop-mechanics.md key row:$loop_row" \
            "config-schema.md comment:$schema_comment"; do
  site="${pair%%:*}"; text="${pair#*:}"
  if printf '%s' "$text" | grep -qF 'Merge rule' \
     && ! printf '%s' "$text" | grep -qiE 'overrid|Honored only|only in `?--auto'; then
    pass "T10.4: $site points to *Merge rule* and restates no rule"
  else
    fail "T10.4: $site does not point to *Merge rule*, or still restates a rule"
  fi
done

# #584 widened this: alternative wordings (case-insensitive), and README.md.
# docs.html is regenerated at release, so it is not scanned.
stale_merge_re='auto mode overrides to `true`|overridden to true in --auto|Honored only in `--auto`|merge` fails \(auto mode only\)'
stale_merge_re="$stale_merge_re"'|auto-?merg(e|es|ing) (only )?(needs|requires) `?--auto|merg(e|es|ing) only (happens |runs )?(in|with|under) `?--auto|`?--auto`? (is )?required (to|for|before) (auto-?)?merg|only `?--auto`? (runs )?(auto-?)?merges'
stale_override=$( (cd "$REPO_ROOT" && grep -rniE "$stale_merge_re" src docs README.md \
  --include='*.md' --include='*.yml') | grep -v -e '^docs/release-notes/' -e '^docs/decisions/' | wc -l | tr -d ' ')
# The widened pattern must still catch the wordings it exists for.
for probe in 'auto-merge only happens with `--auto`' 'Auto-merge requires --auto' 'it merges only in `--auto` mode' '`--auto` is required to merge'; do
  if printf '%s\n' "$probe" | grep -qiE "$stale_merge_re"; then
    pass "T10.5b: the stale-merge pattern catches \"$probe\""
  else
    fail "T10.5b: the stale-merge pattern misses \"$probe\""
  fi
done
if [ "$stale_override" -eq 0 ]; then
  pass "T10.5: no source restates an --auto-only or overriding merge rule"
else
  fail "T10.5: $stale_override line(s) still restate an --auto-only or overriding merge rule"
fi

# The auto-pilot reviewer prompt carries no merge/exit rule the skill lacks.
if ! grep -qE '≤ ?2 medium|medium "note" issues allowed' "$AP_PROMPTS"; then
  pass "T10.6: auto-pilot reviewer prompt drops the '≤ 2 medium notes' rule"
else
  fail "T10.6: auto-pilot reviewer prompt still allows '≤ 2 medium notes'"
fi

# ───────────────────────────────────────────────────────────
# T11 (#552): the unattended *Merge floor* has one home
# ───────────────────────────────────────────────────────────
# The rule is stated once, in /issue-pr-review Step 7; /auto-pilot reads the
# reviewer's `merge_floor` verdict and never re-derives it from the counts.
AP_REVIEW="src/skills/auto-pilot/references/phases/phase-3-4-review.md"
AP_MERGE="src/skills/auto-pilot/references/phases/phase-5-merge.md"
PR_DIST="skills/issue-pr-review/SKILL.md"
floor_rule='at least one criterion is `pass` and none is `unverified`'

n=$(grep -c 'a:rv-merge-floor' "$PR_SKILL")
[ "$n" -eq 1 ] && pass "T11.1: issue-pr-review Step 7 carries exactly one *Merge floor* anchor" \
  || fail "T11.1: expected one a:rv-merge-floor anchor in $PR_SKILL, found $n"

homes=$(grep -rlF "$floor_rule" src docs --include='*.md' | grep -v -e '^docs/release-notes/' -e '^docs/decisions/')
if [ "$homes" = "$PR_SKILL" ] && [ "$(grep -cF "$floor_rule" "$PR_SKILL")" -eq 1 ]; then
  pass "T11.2: the floor rule is stated once, in $PR_SKILL"
else
  fail "T11.2: the floor rule must be stated once, in $PR_SKILL only (found in: ${homes:-nowhere})"
fi

line=$(grep -F 'a:rv-merge-floor' "$PR_SKILL")
if printf '%s' "$line" | grep -qF 'acceptance-criteria check enabled' \
   && printf '%s' "$line" | grep -qF 'deferred rows excluded' \
   && printf '%s' "$line" | grep -qE '`--auto` / `IDD_AUTO_MODE=1` run never merges `unmet`' \
   && printf '%s' "$line" | grep -qE '\? \[y/N\].*<!-- auto:no -->'; then
  pass "T11.3: the floor needs the AC check enabled, excludes deferred rows, never merges unmet in auto, asks interactively"
else
  fail "T11.3: the *Merge floor* line lost a condition (AC check enabled, deferred rows, auto never merges, interactive [y/N] with auto:no)"
fi

rule_ln=$(grep -nF 'a:rv-merge-rule' "$PR_SKILL" | cut -d: -f1)
floor_ln=$(grep -nF 'a:rv-merge-floor' "$PR_SKILL" | cut -d: -f1)
[ -n "$rule_ln" ] && [ -n "$floor_ln" ] && [ "$floor_ln" -eq $((rule_ln + 2)) ] \
  && pass "T11.4: the *Merge floor* sits directly after the *Merge rule* in Step 7" \
  || fail "T11.4: the *Merge floor* is not the paragraph after the *Merge rule*"

grep -qE '^- merge_floor: "met" or "unmet: \{reason\}"' "$AP_PROMPTS" \
  && pass "T11.5: the auto-pilot reviewer returns merge_floor" \
  || fail "T11.5: the auto-pilot reviewer prompt lacks the merge_floor report-back field"

if grep -qF '**Merge floor met** — Step 3.2'"'"'s `merge_floor` is `met`' "$AP_MERGE" \
   && grep -qF 'never re-derive it' "$AP_MERGE" \
   && grep -qF 'A missing `merge_floor` (no review ran this session) is `left_open` too' "$AP_MERGE" \
   && grep -qF '⚠ PR #{pr_number} left open — merge floor not derived (resumed run)' "$AP_MERGE"; then
  pass "T11.6: Phase 5.1 merges only on merge_floor: met, a missing verdict leaves the PR open"
else
  fail "T11.6: Phase 5.1 lacks the merge_floor check, or re-derives it"
fi

grep -qF "apply Step 5.1's merge-floor check" "$AP_REVIEW" \
  && pass "T11.7: the aggressive partial merge (Step 2a) applies the floor" \
  || fail "T11.7: Step 2a does not apply the merge floor"

if grep -rqF "$floor_rule" src/skills/auto-pilot; then
  fail "T11.8: auto-pilot restates the floor rule instead of reading merge_floor"
else
  pass "T11.8: auto-pilot never restates the floor rule"
fi

if [ -f "$PR_DIST" ] && grep -qF 'a:rv-merge-floor' "$PR_DIST" \
   && grep -rqF 'merge_floor' skills/auto-pilot/references/phases/phase-5-merge.md; then
  pass "T11.9: the built skills carry the floor and its reader"
else
  fail "T11.9: the built skills lack the floor or its reader — rebuild skills/"
fi

grep -qE '^run_case "unverified-only-auto"$' tests/test-eval-pr-review.sh \
  && pass "T11.10: the unverified-only auto-mode eval case is registered" \
  || fail "T11.10: tests/test-eval-pr-review.sh does not run unverified-only-auto"

# ───────────────────────────────────────────────────────────
# T12 (#560): no authored file is byte-identical in two skills
# ───────────────────────────────────────────────────────────
# A file two skills need unchanged belongs in src/shared/references/, where
# the build copies it from one source. The check keys on content alone, so a
# second copy under another name or path is caught too.

# cross_skill_duplicates <root> — stdin: file paths relative to <root>, each
# under src/skills/<s>/ or src/internal-skills/<s>/. Prints one line per
# content found in two different skill directories, listing its paths.
cross_skill_duplicates() {
  local root="$1" paths
  paths="$(cat)"
  paste <(printf '%s\n' "$paths" | (cd "$root" && git hash-object --stdin-paths)) \
        <(printf '%s\n' "$paths") |
    awk -F'\t' '
      { split($2, part, "/"); skill = part[1] "/" part[2] "/" part[3] }
      # The one exemption, by exact package-root path: every package ships
      # standalone, so each carries the licence text (and
      # tests/test-plan-to-issues-502.sh requires it).
      $2 == skill "/LICENSE" { next }
      { if (!(($1, skill) in seen)) { seen[$1, skill] = 1; owners[$1]++ }
        files[$1] = files[$1] " " $2 }
      END { for (h in owners) if (owners[h] > 1) print substr(files[h], 2) }' | sort
}

# Tracked files only; one deleted but not yet staged has no bytes to compare.
dups="$(git ls-files src/skills src/internal-skills |
  while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done |
  cross_skill_duplicates "$REPO_ROOT")"
if [ -z "$dups" ]; then
  pass "T12.1: no authored file is byte-identical in two skills"
else
  fail "T12.1: authored content repeats across skills — move it to src/shared/references/:"
  printf '%s\n' "$dups" | sed 's/^/      /'
fi

# The same function must fail on a tree that does repeat a file.
T12_TMP="$(mktemp -d)"
mkdir -p "$T12_TMP/src/skills/a/references" "$T12_TMP/src/skills/a/docs" \
         "$T12_TMP/src/skills/b/references" "$T12_TMP/src/internal-skills/c/docs"
printf 'same body\n' > "$T12_TMP/src/skills/a/references/x.md"
printf 'same body\n' > "$T12_TMP/src/skills/b/references/x.md"
printf 'licence\n'   > "$T12_TMP/src/skills/a/LICENSE"
printf 'licence\n'   > "$T12_TMP/src/skills/b/LICENSE"
printf 'renamed\n'   > "$T12_TMP/src/skills/a/references/one.md"
printf 'renamed\n'   > "$T12_TMP/src/internal-skills/c/docs/other.md"
printf 'nested\n'    > "$T12_TMP/src/skills/a/docs/LICENSE"
printf 'nested\n'    > "$T12_TMP/src/skills/b/references/LICENSE"
printf 'only a\n'    > "$T12_TMP/src/skills/a/references/unique.md"
printf 'twice in a\n' > "$T12_TMP/src/skills/a/references/t1.md"
printf 'twice in a\n' > "$T12_TMP/src/skills/a/references/t2.md"
fixture_dups="$( (cd "$T12_TMP" && find src -type f | sort) | cross_skill_duplicates "$T12_TMP")"
rm -rf "$T12_TMP"
[ -n "$fixture_dups" ] \
  && pass "T12.2: the check fails on a tree where two skills author the same bytes" \
  || fail "T12.2: the check passes a tree where two skills author the same bytes"
printf '%s\n' "$fixture_dups" | grep -qxF 'src/skills/a/references/x.md src/skills/b/references/x.md' \
  && pass "T12.3: a file repeated at the same relative path is reported" \
  || fail "T12.3: a file repeated at the same relative path is not reported"
printf '%s\n' "$fixture_dups" | grep -qxF 'src/internal-skills/c/docs/other.md src/skills/a/references/one.md' \
  && pass "T12.4: the same bytes under another name, in an internal skill, are reported" \
  || fail "T12.4: the same bytes under another name are not reported"
printf '%s\n' "$fixture_dups" | grep -qxF 'src/skills/a/docs/LICENSE src/skills/b/references/LICENSE' \
  && pass "T12.5: a LICENSE outside the package root is not exempt" \
  || fail "T12.5: a nested LICENSE duplicate is not reported"
if printf '%s\n' "$fixture_dups" | grep -qE '/[ab]/LICENSE|unique\.md|t[12]\.md'; then
  fail "T12.6: a root LICENSE, a unique file or a repeat inside one skill was reported"
else
  pass "T12.6: root LICENSE, unique files and repeats inside one skill are not reported"
fi

# ───────────────────────────────────────────────────────────
# T13 (#560): the Self-Improve rules have one home
# ───────────────────────────────────────────────────────────
# Each SKILL.md keeps a short pointer and its own three examples; the eight
# rules live once in src/shared/references/self-improve.md.
SI_RULES="src/shared/references/self-improve.md"
SI_CAP=720
n=$(grep -cE '^[1-8]\. ' "$SI_RULES" 2>/dev/null)
[ "${n:-0}" -eq 8 ] && pass "T13.1: $SI_RULES carries the eight rules" \
  || fail "T13.1: $SI_RULES should carry eight numbered rules, found ${n:-0}"
si_checked=0
for f in src/skills/*/SKILL.source.md src/internal-skills/*/SKILL.source.md; do
  si_checked=$((si_checked + 1))
  section="$(awk '/^## Self-Improve$/ { on = 1; print; next } on && (/^## / || /^---[ \t]*$/) { exit } on' "$f")"
  bytes=$(printf '%s\n' "$section" | wc -c | tr -d ' ')
  if [ -n "$section" ] && [ "$bytes" -le "$SI_CAP" ] \
     && printf '%s' "$section" | grep -qF '`references/self-improve.md`' \
     && [ "$(printf '%s\n' "$section" | grep -cE '^- \*\*(Style|Environment|Behavior)\*\* — ')" -eq 3 ] \
     && [ "$(printf '%s\n' "$section" | grep -cE '^([0-9]+\.|[[:space:]]*-) ')" -eq 3 ]; then
    pass "T13.2: $f — Self-Improve is a pointer and three examples ($bytes B, cap $SI_CAP)"
  else
    fail "T13.2: $f — Self-Improve must cite references/self-improve.md and hold only three examples within $SI_CAP B (is $bytes B)"
  fi
done
[ "$si_checked" -eq 9 ] && pass "T13.3: all nine skills were checked" \
  || fail "T13.3: checked $si_checked SKILL.source.md files, expected 9"
restated=0
while IFS= read -r rule; do
  hits="$(grep -lF -- "$rule" src/skills/*/SKILL.source.md src/internal-skills/*/SKILL.source.md 2>/dev/null)"
  if [ -n "$hits" ]; then
    fail "T13.4: a Self-Improve rule is restated in: $(printf '%s' "$hits" | tr '\n' ' ')"
    restated=1
  fi
done < <(grep -E '^[1-8]\. ' "$SI_RULES" 2>/dev/null | sed -E 's/^[1-8]\. //; s/\. .*$/./')
[ "$restated" -eq 0 ] && pass "T13.4: no SKILL.source.md restates a shared rule"
si_built=0
for d in skills/*/; do
  cmp -s "$SI_RULES" "${d}references/self-improve.md" && si_built=$((si_built + 1))
done
[ "$si_built" -eq 8 ] && pass "T13.5: all eight built skills bundle the rules byte-identical" \
  || fail "T13.5: $si_built of 8 built skills bundle $SI_RULES byte-identical — rebuild skills/"

# ───────────────────────────────────────────────────────────
# T9 (AC3): no skill regressed past the 500-line cap
# ───────────────────────────────────────────────────────────
over=0
for f in src/skills/*/SKILL.source.md skills/*/SKILL.md; do
  n=$(wc -l < "$f")
  if [ "$n" -gt 500 ]; then
    fail "T9: $f is $n lines (cap 500)"
    over=1
  fi
done
[ "$over" -eq 0 ] && pass "T9: every source and built SKILL.md stays within the 500-line cap"

printf '\n┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\n'
printf '  Results: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
