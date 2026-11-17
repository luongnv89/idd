#!/usr/bin/env bash
# test-runtime-text-history-628.sh — runtime skill text states rules and
# current behaviour, never ticket numbers or a phantom earlier version
# (issues #628 and #629, CLAUDE.md "Writing skill text").
#
#  #628  A rule is named for what it does, not by the ticket that added it:
#        no "(issue #N)" archaeology, no "#36 hard-block", no "#274 is the
#        standing proof", no "AC2 holds" / "(AC5)" / "criterion 5 forbids".
#  #629  Behaviour is described as the only behaviour: no "today's pipeline",
#        "as before", "no new config key is introduced", "Reduced from 10",
#        and no "legacy" for the shipped max_parallel = 1 path. `legacy` stays
#        right for the pre-rename config, marker and directory names and
#        autopilot.auto_merge,
#        so this test never bans the bare word.
#
# Scope: every Markdown file and YAML template a skill reads at run time — the
# authored sources
# (src/skills, src/internal-skills, src/shared/agents, src/shared/references,
# the bundled runtime docs) and the built skills/ tree. Human-only files are
# excluded: each skill's docs/README.md, skills/README.md and evals/.
#
# Usage: bash tests/test-runtime-text-history-628.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Runtime text names rules, not tickets or history (issues #628, #629)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# Runtime docs are the top-level docs a built skill bundles.
RUNTIME_DOCS=()
while IFS= read -r name; do
  [ -f "$ROOT/docs/$name" ] && RUNTIME_DOCS+=("$ROOT/docs/$name")
done < <(find "$ROOT/skills" -path '*/references/docs/*.md' -exec basename {} \; | sort -u)

if [ "${#RUNTIME_DOCS[@]}" -ge 10 ]; then
  pass "T0: found ${#RUNTIME_DOCS[@]} bundled runtime docs to scan"
else
  fail "T0: found only ${#RUNTIME_DOCS[@]} bundled runtime docs — is skills/ built?"
fi

TARGETS=(
  "$ROOT/src/skills" "$ROOT/src/internal-skills"
  "$ROOT/src/shared/agents" "$ROOT/src/shared/references"
  "$ROOT/skills" "${RUNTIME_DOCS[@]}"
)

# scan <ERE> — print every runtime-text line matching the pattern.
scan() {
  grep -rnE --include='*.md' --include='*.yml' -- "$1" "${TARGETS[@]}" 2>/dev/null \
    | grep -vE '/docs/README\.md:|/evals/|^'"$ROOT"'/skills/README\.md:' || true
}

# none <label> <ERE> — pass when no runtime line matches.
none() {
  local hits
  hits="$(scan "$2")"
  if [ -z "$hits" ]; then
    pass "$1"
  else
    fail "$1"
    printf '%s\n' "$hits" | sed "s|^$ROOT/|      |" | cut -c1-200
  fi
}

# ── #628: ticket numbers as rule names or authority ─────────────
none "T1: no '(issue #N)' archaeology in runtime text" \
  '\(issues? #[0-9]+'
none "T2: no rule named by a ticket number (#36 hard-block, #258's work, …)" \
  "#[0-9]+('s)? (\`?acceptance_criteria\`? )?(hard-blocks?|hard-fail|contract|canonical case|work\b|caller|CI verdict)"
none "T3: no ticket cited as the standing proof of a rule" \
  '#[0-9]+ is (the standing proof|what happens)|standing proof'
none "T4: no acceptance-criterion tags standing in for a reason" \
  '\bAC[0-9]+ (holds|work)\b|\(AC[0-9]+\)|criterion [0-9]+ forbids|acceptance criterion [0-9]+'
none "T5: no ticket numbers as merge-gate provenance (#516, #605, #564)" \
  '\(#(516|564|605|606|515|276|548|1541)[,)]'
none "T5b: no ticket cited as where a rule came from (adopted in #N, '; #N)')" \
  '\b(adopted|established|introduced|added|landed|decided) (per host |for [a-z ]+ )?in #[0-9]+|; #[0-9]+\)'

# ── #629: comparison with a version the reader never saw ────────
none "T6: no 'today's pipeline / behavior / path' comparisons" \
  "today's (full )?(pipeline|behavior|path|wait|ordering|0a fetch|guess)|exactly (as )?today|does today\b|as today\b|runs today\b|identical to today|as it (is|does|runs) today|[a-z]+ly today\b|\btoday:"
none "T7: no 'as before' comparisons" \
  '(behaves?|skips it,|result|scope|pipeline|--init.) (exactly )?as before|= (behave )?as before|as before this'
none "T8: no 'no new config key' asides" \
  '[Nn]o new config key'
none "T9: no 'before this gate/mechanism existed' or 'Reduced from N' history" \
  'before this (gate|mechanism|contract)|Reduced from [0-9]+|used to skip|now also requires'
none "T10: the shipped max_parallel = 1 path is never called legacy or original" \
  '[Ll]egacy (sequential|in-place|sequence|behavior|batch array|writers|callers|only)|[Ll]egacy .--append|original (path|in-place|sequential)|preserves the original|byte-for-byte (as before|today|legacy)|byte-identically'

# ── The renamed rules resolve at their homes ─────────────────────
has() { # has <file> <ERE> <label>
  if grep -qE -- "$2" "$1"; then pass "$3"; else fail "$3"; fi
}
has "$ROOT/docs/shared-agent-conventions.md" 'AC and traceability hard-blocks' \
  "T11: the payload exclusion list names the AC and traceability hard-blocks"
has "$ROOT/src/skills/issue-pr-review/SKILL.source.md" '\*\*Hard-block conditions:\*\*' \
  "T12: issue-pr-review states its hard-block conditions without a ticket tag"
has "$ROOT/src/skills/auto-pilot/references/phases/phase-2-resolve.md" '^#### Sequential path \(`max_parallel = 1`\)$' \
  "T13: auto-pilot names the max_parallel = 1 branch the sequential path"
has "$ROOT/src/skills/auto-pilot/references/orchestration.md" '^## Sequential branch \(`max_parallel = 1`\)$' \
  "T14: orchestration names the same branch the sequential branch"
# The compatibility paths that still run keep their legacy name.
has "$ROOT/src/skills/issue-resolver/SKILL.source.md" 'legacy `\.git[i]ssue\.yml`' \
  "T15: the pre-rename config file keeps its legacy name"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
