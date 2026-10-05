#!/usr/bin/env bash
# test-plan-to-issues-502.sh — /plan-to-issues lives in idd and follows the
# skill conventions every other public skill does (issue #502).
#
# The skill moved in from luongnv89/skills, where it shipped skill-local
# agents/ and scripts/ directories, a top-level `effort:` key, a mandatory
# repo sync, and asm install lines pointing at a path-qualified
# `--skill skills/issue-creator`. Each of those is a convention break here.
#
#  AC1. Package shape: SKILL.source.md + LICENSE + docs/README.md +
#       references/{error-messages,run-stats}.md; no SKILL.md, agents/,
#       scripts/ or evals/ in the source package (evals/ would ship).
#  AC2. Prose alignment: sibling issue-creator check (no $HOME probes, no
#       `skills/issue-creator` path), no repo sync, gi-config load with the
#       run clock, review contract + Closing Summary + run-stats footer.
#  AC3. gi-plan-map.py honours the shared-script contract: --help exits 0,
#       a bad argument exits 2, every invalid input exits 3 with a ✗ line,
#       never a traceback.
#  AC4. The render is deterministic, sentinel-bounded, asserts no status, and
#       flattens/escapes untrusted plan text.
#  AC5. The built skill ships the renderer byte-identical and the skill is
#       listed in the plugin README and the landing page.
#
# Usage: bash tests/test-plan-to-issues-502.sh

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/src/skills/plan-to-issues"
SKILL="$SRC/SKILL.source.md"
SCRIPT="$ROOT/src/shared/scripts/gi-plan-map.py"
FIXTURE="$ROOT/tests/fixtures/plan-map/input.json"
PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
has()  { if grep -qE -- "$2" "$1"; then pass "$3"; else fail "$3 (missing in ${1#$ROOT/}: $2)"; fi; }
lacks() { if grep -qE -- "$2" "$1"; then fail "$3 (found in ${1#$ROOT/}: $2)"; else pass "$3"; fi; }
# Collapse line wraps first, so a hard-wrapped sentence still matches.
flows() { if tr '\n' ' ' < "$1" | tr -s ' ' | grep -qE -- "$2"; then pass "$3"; else fail "$3 (missing in ${1#$ROOT/}: $2)"; fi; }

echo "◆ /plan-to-issues in idd (issue #502)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ── AC1: package shape ───────────────────────────────────────────────────────
for f in SKILL.source.md LICENSE docs/README.md references/error-messages.md references/run-stats.md references/plan-parser.md; do
  if [ -f "$SRC/$f" ]; then pass "AC1: $f present"; else fail "AC1: $f missing"; fi
done
for d in agents scripts evals; do
  if [ -e "$SRC/$d" ]; then fail "AC1: skill-local $d/ must not exist (use shared/ or references/)"; else pass "AC1: no skill-local $d/"; fi
done
if [ -e "$SRC/SKILL.md" ]; then fail "AC1: src package carries a SKILL.md"; else pass "AC1: no SKILL.md under src/"; fi
has "$SKILL" '^name: "plan-to-issues"$' "AC1: frontmatter name"
has "$SKILL" '^  effort: high$' "AC1: effort lives under metadata"
lacks "$SKILL" '^effort:' "AC1: no top-level effort key"

# ── AC2: prose alignment ─────────────────────────────────────────────────────
has   "$SKILL" '\$SKILL_DIR/\.\./issue-creator/SKILL\.md' "AC2: sibling issue-creator check"
lacks "$SKILL" '\$HOME/\.claude' "AC2: no host-specific \$HOME probes"
for f in "$SKILL" "$SRC"/references/*.md "$SRC/docs/README.md"; do
  lacks "$f" 'skills/issue-creator|skills:skills/plan-to-issues' "AC2: ${f#$SRC/} uses bare --skill names"
done
lacks "$SKILL" 'git pull --rebase origin' "AC2: no mandatory repo sync"
lacks "$SKILL" 'mandatory sync' "AC2: no stale mandatory-sync wording"
lacks "$SRC/references/acceptance-criteria.md" 'mandatory sync' "AC2: no stale mandatory-sync wording in acceptance-criteria.md"
flows "$SKILL" 'python3 shared/scripts/gi-config\.py' "AC2: config loads through gi-config"
flows "$SKILL" 'ec=\$\?; date \+%s >&2; exit "\$ec"' "AC2: run clock chained onto the config load"
has   "$SKILL" '^## Closing Summary$' "AC2: Closing Summary section"
has   "$SKILL" 'references/run-stats\.md' "AC2: run-stats footer cited"
has   "$SRC/references/reporting.md" '^## Review contract$' "AC2: review contract defined"
flows "$SKILL" 'gi-plan-map unavailable|degrades to rendering' "AC2: renderer has a prose fallback"
has   "$SRC/references/error-messages.md" 'Plugin:  claude plugin marketplace add luongnv89/idd' "AC2: missing-skill block carries the plugin path"

# ── AC3: shared-script contract ──────────────────────────────────────────────
if [ -x "$SCRIPT" ]; then pass "AC3: gi-plan-map.py is executable"; else fail "AC3: gi-plan-map.py not mode 0755"; fi
python3 "$SCRIPT" --help >/dev/null 2>&1; [ $? -eq 0 ] && pass "AC3: --help exits 0" || fail "AC3: --help did not exit 0"
python3 "$SCRIPT" --bogus </dev/null >/dev/null 2>&1; [ $? -eq 2 ] && pass "AC3: bad argument exits 2" || fail "AC3: bad argument did not exit 2"

expect3() {
  # $3 is a regex the stderr must match, naming the field or condition that
  # failed — so each case is proven to reach its intended check.
  local label="$1" input="$2" want="$3" rc
  printf '%b' "$input" | python3 "$SCRIPT" >"$TMP/out" 2>"$TMP/err"; rc=$?
  if [ "$rc" -eq 3 ] && grep -q '^✗ gi-plan-map:' "$TMP/err" && grep -qE -- "$want" "$TMP/err" \
     && ! grep -q 'Traceback' "$TMP/err" && [ ! -s "$TMP/out" ]; then
    pass "AC3: $label exits 3 naming the failure"
  else
    fail "AC3: $label → exit $rc ($(head -1 "$TMP/err")), want /$want/"
  fi
}
P0='"phases":[{"id":"P0","title":"t","tasks":[]}]'
expect3 "empty stdin" '' 'no input on stdin'
expect3 "non-UTF-8 input" '\xff\xfe' 'not valid UTF-8'
expect3 "malformed JSON" '{not json' 'not valid JSON'
expect3 "non-object JSON" '[1, 2]' 'must be a JSON object'
expect3 "missing key" '{"plan_path":"p.md","synced":"2026-01-01","epic":1}' 'missing required key: phases'
expect3 "empty phases" '{"plan_path":"p.md","synced":"2026-01-01","epic":1,"phases":[]}' 'phases. must be a non-empty list'
expect3 "string epic number" '{"plan_path":"p.md","synced":"2026-01-01","epic":"1 --> x",'"$P0"'}' 'epic must be'
expect3 "boolean title" '{"plan_path":true,"synced":"2026-01-01","epic":1,'"$P0"'}' 'plan_path must be'

# ── AC4: render properties ───────────────────────────────────────────────────
python3 "$SCRIPT" < "$FIXTURE" > "$TMP/a.md"; rc=$?
python3 "$SCRIPT" < "$FIXTURE" > "$TMP/b.md"
[ "$rc" -eq 0 ] && pass "AC4: fixture renders (exit 0)" || fail "AC4: fixture render exit $rc"
cmp -s "$TMP/a.md" "$TMP/b.md" && pass "AC4: deterministic — same input, same bytes" || fail "AC4: two renders differ"
[ "$(head -1 "$TMP/a.md")" = '<!-- plan-dashboard:start -->' ] && pass "AC4: opens on the start sentinel" || fail "AC4: first line is not the start sentinel"
[ "$(tail -1 "$TMP/a.md")" = '<!-- plan-dashboard:end -->' ] && pass "AC4: closes on the end sentinel" || fail "AC4: last line is not the end sentinel"
[ "$(grep -cFx -e '<!-- plan-dashboard:start -->' -e '<!-- plan-dashboard:end -->' "$TMP/a.md")" -eq 2 ] \
  && pass "AC4: each sentinel exactly once" || fail "AC4: sentinel count is not 2"
lacks "$TMP/a.md" '- \[[ x]\]|█|[0-9]%' "AC4: asserts no status (no checkbox, bar, percent)"
# The fixture marks #101 closed and #102 open; a status-free map renders both alike.
has "$TMP/a.md" '^- #101 — Pre\.1 ' "AC4: closed child listed like any other"
has "$TMP/a.md" '^- #102 — 0\.1 Commit the lockfile and restore the build' "AC4: newline in a title is flattened"
has "$TMP/a.md" 'upstream v4 \\\| unreleased' "AC4: pipe escaped inside a table cell"
has "$TMP/a.md" '^### P1 — Secure · not filed$' "AC4: an unfiled phase is kept, never dropped"
has "$TMP/a.md" '⚠ unknown dep Z\.9' "AC4: unknown dependency flagged, never guessed"
has "$TMP/a.md" '/plan-to-issues sync 100' "AC4: sync hint names the epic"

# ── R1: sub-issue reads paginate ─────────────────────────────────────────────
# The sub_issues list endpoint returns 30 per page; an unpaginated read silently
# drops children 31+ (sync would then unlink them). Every GET read must carry
# --paginate. Exempt: the POST registration and the preflight existence probe.
unpaged="$(grep -rnE 'gh api[^`]*sub_issues' "$ROOT/src/skills/plan-to-issues" \
  | grep -vE -- '--method POST|issues/1/sub_issues' | grep -v -- 'gh api --paginate' || true)"
if [ -z "$unpaged" ]; then
  pass "R1: every sub_issues GET read uses --paginate"
else
  fail "R1: sub_issues read without --paginate: ${unpaged//$ROOT\//}"
fi
# --paginate applies --jq per page, so an aggregate (length, [...]) prints one
# value per page; counts must use one-number-per-line output instead.
aggr="$(grep -rnE 'sub_issues.*--jq .(length|\[)' "$ROOT/src/skills/plan-to-issues" || true)"
if [ -z "$aggr" ]; then
  pass "R1: no per-page jq aggregate on a sub_issues read"
else
  fail "R1: per-page jq aggregate on a sub_issues read: ${aggr//$ROOT\//}"
fi

# ── R2: epic and child lookups read every issue ──────────────────────────────
# `gh issue list` lists newest first, so a --limit window misses an epic (or its
# children) once that many newer issues exist, and a re-run duplicates them.
# The lookups must page through every issue with `gh api --paginate`.
windowed="$(grep -rnE 'gh issue list[^`]*--limit' "$ROOT/src/skills/plan-to-issues" \
  | grep -vE 'gh issue list --limit N' || true)"
if [ -z "$windowed" ]; then
  pass "R2: no windowed gh issue list lookup"
else
  fail "R2: windowed gh issue list lookup: ${windowed//$ROOT\//}"
fi
for f in references/epic-identity.md references/issue-creator-bridge.md references/phase-contracts.md SKILL.source.md; do
  has "$ROOT/src/skills/plan-to-issues/$f" 'gh api --paginate "?repos/[^"]*/issues\?state=all' \
    "R2: $f pages through every issue"
done

# ── AC5: shipped and listed ──────────────────────────────────────────────────
BUILT="$ROOT/skills/plan-to-issues"
if cmp -s "$BUILT/references/scripts/gi-plan-map.py" "$SCRIPT"; then
  pass "AC5: built skill ships gi-plan-map.py byte-identical"
else
  fail "AC5: skills/plan-to-issues lacks an identical gi-plan-map.py — run ./scripts/build.sh"
fi
has "$BUILT/SKILL.md" 'python3 references/scripts/gi-plan-map\.py' "AC5: built prose invokes the bundled renderer"
has "$ROOT/src/plugin/README.md" 'plan-to-issues' "AC5: plugin README lists the skill"
has "$ROOT/landing.html" '/plan-to-issues' "AC5: landing page lists the command"
has "$ROOT/docs.html" 'id="plan-to-issues"' "AC5: docs page has a section"

echo ""
echo "  Passed: $PASS  Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ /plan-to-issues checks failed"
  exit 1
fi
echo "  ✓ /plan-to-issues checks passed"
