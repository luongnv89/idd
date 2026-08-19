#!/usr/bin/env bash
# test-resolver-borrow-skills-309.sh — Borrow and release catalogued skills
# for one resolve task (issue #309).
#
# Acceptance:
#   Off by default (installed-only propose).
#   Opt-in classify installed vs available-to-borrow; install selected missing.
#   Persist {name, origin} via gi-state.py; teardown only origin: borrowed.
#   Never auto-install unless resolve.borrow_skills is true.
#   Leftover teardown after crash; preinstalled copies stay.
#
# Usage: bash tests/test-resolver-borrow-skills-309.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$REPO_ROOT/src/shared/scripts/gi-state.py"
SCHEMA="$REPO_ROOT/docs/config-schema.md"
TEMPLATE="$REPO_ROOT/src/skills/init-gitissue/templates/gitissue-template.yml"
RESOLVER="$REPO_ROOT/src/skills/issue-resolver/SKILL.source.md"
STEPS="$REPO_ROOT/src/skills/issue-resolver/references/pipeline-steps.md"
ERR="$REPO_ROOT/src/skills/issue-resolver/references/error-messages.md"
INDEX="$REPO_ROOT/src/skills/issue-resolver/references/skill-index.md"
AP_PHASES="$REPO_ROOT/src/skills/auto-pilot/references/phases.md"
DIST="$REPO_ROOT/.github/workflows/dist-check.yml"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

expect_grep() {
  local label="$1" pattern="$2" file="$3"
  if grep -qE -- "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label"
  fi
}

expect_no_grep() {
  local label="$1" pattern="$2" file="$3"
  if grep -qE -- "$pattern" "$file"; then
    fail "$label"
  else
    pass "$label"
  fi
}

# Extract a markdown section (start heading .. next heading at the same level)
# into a file, so an assertion is anchored to the RULE'S LOCATION, not to a word
# that could survive anywhere in the document.
section_file() {
  local src="$1" start="$2" end="$3" out="$TMP/section-$4.md"
  awk -v s="$start" -v e="$end" '
    BEGIN { on = 0 }
    { if (!on && $0 ~ s) { on = 1; print; next }
      if (on && $0 ~ e) { on = 0 }
      if (on) print }' "$src" > "$out"
  if [ ! -s "$out" ]; then
    fail "section extraction produced nothing for /$start/ in $(basename "$src")"
  fi
  printf '%s' "$out"
}

jkey() {
  python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
for part in sys.argv[1].split("."):
    d = d[int(part)] if part.isdigit() else d[part]
print(d)
' "$1"
}

run_status() {
  local __out_var="$1"; shift
  local __status_var="$1"; shift
  local __out __status=0
  __out="$("$@" 2>/dev/null)" || __status=$?
  printf -v "$__out_var" '%s' "$__out"
  printf -v "$__status_var" '%s' "$__status"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "◆ Resolver borrow/teardown catalogued skills (issue #309)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# T0: files
for f in "$STATE" "$SCHEMA" "$TEMPLATE" "$RESOLVER" "$STEPS" "$ERR" "$INDEX" "$AP_PHASES"; do
  if [ -f "$f" ]; then
    pass "T0: $(basename "$f") exists"
  else
    fail "T0: $f missing"
    exit 1
  fi
done

# T1: default false in schema + template + SKILL
expect_grep "T1: schema yaml borrow_skills: false" \
  'borrow_skills:\s*false' "$SCHEMA"
expect_grep "T1: defaults table resolve.borrow_skills false" \
  '\| `resolve\.borrow_skills` \| `false`' "$SCHEMA"
expect_grep "T1: template borrow_skills: false" \
  'borrow_skills:\s*false' "$TEMPLATE"
expect_grep "T1: SKILL default resolve.borrow_skills: false" \
  'resolve\.borrow_skills:\s*false' "$RESOLVER"

# T2: classify / leftover / teardown / auto never-install
expect_grep "T2: leftover teardown before detect" \
  'Leftover teardown' "$STEPS"
expect_grep "T2: available-to-borrow classification" \
  'available-to-borrow' "$STEPS"
expect_grep "T2: origin borrowed vs preinstalled" \
  'origin.*borrowed.*preinstalled|preinstalled.*borrowed' "$STEPS"
expect_grep "T2: uninstall only origin borrowed" \
  'Never remove' "$STEPS"
expect_grep "T2: auto never installs unless key true" \
  'never installs unless|Auto mode never installs' "$SCHEMA"
expect_grep "T2: auto path skipped when false" \
  'borrow_skills: false.*selected_skills|selected_skills = \[\]' "$STEPS"
expect_grep "T2: auto+borrow payload is not always empty" \
  'auto \+ `borrow_skills: true` passes the auto-selected set' "$STEPS"
expect_grep "T2: light still leftover teardown" \
  'still runs leftover teardown' "$STEPS"
expect_grep "T2: record intent before install" \
  'Accept, record, install' "$STEPS"
expect_grep "T2: teardown requires the borrow marker" \
  '\.gitissue-borrowed' "$STEPS"
expect_grep "T2: teardown carries back only the failed removals" \
  'entries whose `rm -rf` failed' "$STEPS"
expect_grep "T2: teardown re-screens read-back names" \
  '\^\[a-z\]\[a-z0-9-\]\{0,63\}\$' "$STEPS"
expect_grep "T2: gi-state --update records" \
  'gi-state.py --update' "$STEPS"
expect_grep "T2: standalone --init \{\} if read is empty" \
  '--init' "$STEPS"

# T3: error catalog
expect_grep "T3: borrow install failed" \
  'Borrow install failed' "$ERR"
expect_grep "T3: borrow teardown leftover" \
  'Borrow teardown leftover' "$ERR"
expect_grep "T3: borrow cleanup failed (partial install left behind)" \
  'Borrow cleanup failed' "$ERR"
expect_grep "T3: install failure removes the partial directory" \
  'rm -rf "\$HOME/\.claude/skills/<name>"' "$STEPS"
expect_grep "T3: install-failure removal cites Borrow cleanup failed" \
  'Borrow cleanup failed' "$STEPS"
expect_grep "T3: gi-state unavailable borrow" \
  'gi-state unavailable' "$ERR"
expect_grep "T3: borrow marker absent" \
  'Borrow marker absent' "$ERR"

# T3b: the bundled config-schema the resolver ships names it as a run-state writer
BUNDLED_SCHEMA="$REPO_ROOT/skills/issue-resolver/references/docs/config-schema.md"
for f in "$SCHEMA" "$BUNDLED_SCHEMA"; do
  if grep -qE '^\| `\.gitissue/run-state\.json`.*/issue-resolver' "$f"; then
    pass "T3b: run-state.json row names /issue-resolver (${f#$REPO_ROOT/})"
  else
    fail "T3b: run-state.json row omits /issue-resolver (${f#$REPO_ROOT/})"
  fi
done

# T4: skill-index catalog vs availability
expect_grep "T4: catalog vs filesystem" \
  'available to borrow' "$INDEX"
expect_grep "T4: index does not record installs" \
  'does \*\*not\*\* record which are installed' "$INDEX"

# T5: auto-pilot leftover teardown on resume
expect_grep "T5: auto-pilot leftover borrowed skills" \
  'Leftover borrowed skills' "$AP_PHASES"
expect_grep "T5: auto-pilot leftover teardown is dry-run safe" \
  'no uninstall, no `--update`' "$AP_PHASES"
expect_grep "T5: auto-pilot leftover teardown requires the marker" \
  '\.gitissue-borrowed' "$AP_PHASES"
expect_no_grep "T5: auto-pilot does not restate an unconditional write-back" \
  'borrowed_skills\": \[\]' "$AP_PHASES"

# T9/T10/T11: rules anchored to their own section, not to loose vocabulary.
BORROW_SEC="$(section_file "$STEPS" '^### Step 3 — Propose relevant skills' '^### ' borrow)"
ACCEPT_SEC="$(section_file "$STEPS" '^#### Accept, record, install' '^#### ' accept)"

# T9: a parallel lane never owns the global skills dir (finding A)
expect_grep "T9: borrow section carves out the parallel lane" \
  'IDD_CALLER_WORKTREE=1' "$BORROW_SEC"
expect_grep "T9: lane borrowing is disabled regardless of the config key" \
  'disabled for that lane regardless of `resolve\.borrow_skills`' "$BORROW_SEC"
expect_grep "T9: the per-checkout vs global scope mismatch is named" \
  'global.*but the borrow record is \*\*per-checkout\*\*' "$BORROW_SEC"
expect_grep "T9: the concurrent-run hazard is documented, not hidden" \
  'Residual hazard' "$BORROW_SEC"

# T10: corrupt state never stops the resolve (finding B)
expect_grep "T10: the record step handles a corrupt read at exit 0" \
  'corrupt.*true' "$ACCEPT_SEC"
expect_grep "T10: corrupt does not reach --update (which would exit 3)" \
  '`--update` \(that exits 3\)' "$ACCEPT_SEC"

# T11: the borrow marker carries no read-back value (finding C)
expect_grep "T11: the marker is written empty" \
  'create the \*\*empty\*\* file' "$ACCEPT_SEC"
expect_no_grep "T11: the marker never carries the run id" \
  'marker.*containing this run|containing this run.{0,4}s `run_id`' "$ACCEPT_SEC"
expect_grep "T11: teardown never reads the marker contents" \
  'never reads its contents' "$STEPS"

# T6: resolver precheck bundles gi-state
expect_grep "T6: precheck lists gi-state.py" \
  'references/scripts/gi-state.py' "$RESOLVER"

# T7: dist-check wires this test
expect_grep "T7: dist-check names this test" \
  'test-resolver-borrow-skills-309' "$DIST"

# T8: gi-state borrowed_skills contract
D="$TMP/state"
mkdir -p "$D"
printf '%s' '{}' | python3 "$STATE" --init --dir "$D" >/dev/null
read_out="$(python3 "$STATE" --read --dir "$D")"
if [ "$(printf '%s' "$read_out" | jkey borrowed_skills)" = "[]" ]; then
  pass "T8: --init defaults borrowed_skills to []"
else
  fail "T8: --init borrowed_skills default (got $(printf '%s' "$read_out" | jkey borrowed_skills))"
fi

PATCH='{"borrowed_skills":[{"name":"test-coverage","origin":"borrowed"},{"name":"code-review","origin":"preinstalled"}]}'
run_status out st bash -c "printf '%s' '$PATCH' | python3 '$STATE' --update --dir '$D'"
if [ "$st" = "0" ] \
  && [ "$(printf '%s' "$out" | jkey borrowed_skills.0.name)" = "test-coverage" ] \
  && [ "$(printf '%s' "$out" | jkey borrowed_skills.0.origin)" = "borrowed" ] \
  && [ "$(printf '%s' "$out" | jkey borrowed_skills.1.origin)" = "preinstalled" ]; then
  pass "T8: --update records borrowed and preinstalled origins"
else
  fail "T8: --update mixed origins (exit $st)"
fi

# replace, not append
PATCH2='{"borrowed_skills":[{"name":"frontend-design","origin":"borrowed"}]}'
run_status out st bash -c "printf '%s' '$PATCH2' | python3 '$STATE' --update --dir '$D'"
count="$(printf '%s' "$out" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["borrowed_skills"]))')"
if [ "$st" = "0" ] && [ "$count" = "1" ] \
  && [ "$(printf '%s' "$out" | jkey borrowed_skills.0.name)" = "frontend-design" ]; then
  pass "T8: --update replaces the whole borrowed_skills list"
else
  fail "T8: --update should replace, not append (count=$count exit=$st)"
fi

# empty list = teardown complete
PATCH3='{"borrowed_skills":[]}'
run_status out st bash -c "printf '%s' '$PATCH3' | python3 '$STATE' --update --dir '$D'"
if [ "$st" = "0" ] && [ "$(printf '%s' "$out" | jkey borrowed_skills)" = "[]" ]; then
  pass "T8: empty list clears borrowed_skills (teardown complete)"
else
  fail "T8: empty list did not clear (exit $st)"
fi

# invalid origin
run_status out st bash -c "printf '%s' '{\"borrowed_skills\":[{\"name\":\"x\",\"origin\":\"temp\"}]}' | python3 '$STATE' --update --dir '$D'"
if [ "$st" = "3" ]; then
  pass "T8: invalid origin exits 3"
else
  fail "T8: invalid origin should exit 3 (got $st)"
fi

# unhashable origin (array/object) must be an input error, not a traceback
run_status out st bash -c "printf '%s' '{\"borrowed_skills\":[{\"name\":\"x\",\"origin\":[]}]}' | python3 '$STATE' --update --dir '$D'"
if [ "$st" = "3" ]; then
  pass "T8: unhashable origin exits 3"
else
  fail "T8: unhashable origin should exit 3 (got $st)"
fi
run_status out st bash -c "printf '%s' '{\"borrowed_skills\":[{\"name\":\"x\",\"origin\":{\"k\":\"v\"}}]}' | python3 '$STATE' --update --dir '$D'"
if [ "$st" = "3" ]; then
  pass "T8: object origin exits 3"
else
  fail "T8: object origin should exit 3 (got $st)"
fi

# invalid name
run_status out st bash -c "printf '%s' '{\"borrowed_skills\":[{\"name\":\"Bad_Name\",\"origin\":\"borrowed\"}]}' | python3 '$STATE' --update --dir '$D'"
if [ "$st" = "3" ]; then
  pass "T8: invalid skill name exits 3"
else
  fail "T8: invalid skill name should exit 3 (got $st)"
fi

# duplicate names
run_status out st bash -c "printf '%s' '{\"borrowed_skills\":[{\"name\":\"a\",\"origin\":\"borrowed\"},{\"name\":\"a\",\"origin\":\"preinstalled\"}]}' | python3 '$STATE' --update --dir '$D'"
if [ "$st" = "3" ]; then
  pass "T8: duplicate names exit 3"
else
  fail "T8: duplicate names should exit 3 (got $st)"
fi

# unknown extra key on entry
run_status out st bash -c "printf '%s' '{\"borrowed_skills\":[{\"name\":\"a\",\"origin\":\"borrowed\",\"path\":\"/tmp\"}]}' | python3 '$STATE' --update --dir '$D'"
if [ "$st" = "3" ]; then
  pass "T8: unknown entry key exits 3"
else
  fail "T8: unknown entry key should exit 3 (got $st)"
fi

echo
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
