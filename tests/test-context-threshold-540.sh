#!/usr/bin/env bash
# test-context-threshold-540.sh — context-threshold compaction (issue #540).
#
# The `compaction` config section gives each skill a threshold — a percent of
# context *remaining* — at or below which it confirms its progress is
# checkpointed and prompts the user (or the host's auto-compact) to compact.
# Three long-running skills also carry a re-entry rule at the top of SKILL.md,
# the part the host re-injects after a compaction. This file pins:
#
#   T1  gi-config: defaults, per-skill override, enabled:false, the 1-99 guard
#       (in view and out of view), unknown keys, the PyYAML-less fallback;
#   T2  the schema fence, Section Map, Defaults Table and init template;
#   T3  every built skill bundles, prechecks, cites and configures the contract;
#   T4  the signal-only contract: in-band figure only, never estimated, no
#       transcript reads, no settings writes, no skill claims to compact;
#   T5  AC4: every new block is gated on `compaction.enabled` (obligation q2);
#   T6  auto-pilot's check warns and continues, with no new Result value;
#   T7  the ADR maps pi durable, and doc-to-doc links are full URLs;
#   T8  each re-entry rule sits before Prerequisites, inside the first 8,000
#       bytes of the built SKILL.md (obligation q3);
#   T9  no on-disk handoff record anywhere;
#   T10 auto-pilot re-entry: no re-spawn, no resume gate, pre-spawn checkpoints
#       that gi-state.py accepts, live checks before effectful repeats;
#   T11 bounded loops; T12 the resolver lane clause; T13 /compact line safety;
#   T14 the CI step is one plain name/run pair (obligation q1).
#
# Contract-critical prose is located by anchor (tests/lib/anchors.bash), so each
# assertion is scoped to the block that carries the rule.
#
# Usage: bash tests/test-context-threshold-540.sh
# Returns: exit 0 if all checks pass, exit 1 on failure
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GI_CONFIG="$ROOT/src/shared/scripts/gi-config.py"
GI_STATE="$ROOT/src/shared/scripts/gi-state.py"
SCHEMA="$ROOT/docs/config-schema.md"
DOC="$ROOT/docs/context-threshold.md"
ADR="$ROOT/docs/decisions/context-threshold-durable-handoff.md"
TEMPLATE="$ROOT/src/skills/init-idd/templates/idd-template.yml"
WORKFLOW="$ROOT/.github/workflows/dist-check.yml"
SKILLS="$ROOT/skills"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

# shellcheck source=lib/anchors.bash
. "$ROOT/tests/lib/anchors.bash"

echo "◆ Context-threshold compaction (#540)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

for f in "$GI_CONFIG" "$GI_STATE" "$SCHEMA" "$DOC" "$ADR" "$TEMPLATE" "$WORKFLOW"; do
  [ -f "$f" ] || { echo "  ✗ missing $f"; exit 1; }
done

ALL_SKILLS="auto-pilot issue-resolver issue-pr-review issue-analysis issue-creator issue-triage plan-to-issues init-idd"
LONG_RUNNING="auto-pilot issue-resolver issue-pr-review"
default_for() { [ "$1" = "auto-pilot" ] && echo 15 || echo 40; }

# run [--fallback] <fixture-or-empty> [schema]: sets RC; stdout → $TMP/out,
# stderr → $TMP/err. An empty fixture runs with no config file at all.
mkdir -p "$TMP/noyaml" "$TMP/empty"
echo 'raise ImportError("PyYAML hidden by test-context-threshold-540.sh")' > "$TMP/noyaml/yaml.py"
run() {
  local pypath=""
  if [ "$1" = "--fallback" ]; then pypath="$TMP/noyaml"; shift; fi
  local cfg="$1" schema="${2:-$SCHEMA}"
  RC=0
  if [ -z "$cfg" ]; then
    (cd "$TMP/empty" && PYTHONPATH="$pypath" python3 "$GI_CONFIG" --schema "$schema") \
      >"$TMP/out" 2>"$TMP/err" || RC=$?
  else
    PYTHONPATH="$pypath" python3 "$GI_CONFIG" --schema "$schema" --config "$cfg" \
      >"$TMP/out" 2>"$TMP/err" || RC=$?
  fi
}
get() {
  python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["config"][sys.argv[2]]))' \
    "$TMP/out" "$1"
}

# ─── T1: gi-config ──────────────────────────────────────────────────────────
run ""
if [ "$RC" -eq 0 ] && [ "$(get compaction.enabled)" = "true" ]; then
  pass "T1a no config: exit 0, compaction.enabled true"
else
  fail "T1a rc=$RC err=$(cat "$TMP/err")"
fi
WRONG=""
for s in $ALL_SKILLS; do
  [ "$(get "compaction.threshold.$s" 2>/dev/null)" = "$(default_for "$s")" ] || WRONG="$WRONG $s"
done
COUNT="$(python3 -c 'import json,sys; c=json.load(open(sys.argv[1]))["config"]; print(sum(k.startswith("compaction.") for k in c))' "$TMP/out")"
[ -z "$WRONG" ] && [ "$COUNT" = "9" ] \
  && pass "T1b defaults: auto-pilot 15, every other skill 40, nine compaction keys" \
  || fail "T1b wrong default for:$WRONG (keys=$COUNT)"

printf 'compaction:\n  threshold:\n    issue-resolver: 25\n' > "$TMP/override.yml"
run "$TMP/override.yml"
[ "$RC" -eq 0 ] && [ "$(get compaction.threshold.issue-resolver)" = "25" ] \
  && [ "$(get compaction.threshold.auto-pilot)" = "15" ] && [ "$(get compaction.threshold.issue-triage)" = "40" ] \
  && pass "T1c per-skill override wins; siblings keep their defaults" \
  || fail "T1c rc=$RC err=$(cat "$TMP/err")"

printf 'compaction:\n  enabled: false\n' > "$TMP/off.yml"
run "$TMP/off.yml"
[ "$RC" -eq 0 ] && [ "$(get compaction.enabled)" = "false" ] && [ "$(get compaction.threshold.auto-pilot)" = "15" ] \
  && pass "T1d enabled: false round-trips" || fail "T1d rc=$RC err=$(cat "$TMP/err")"

# bad <label> <yaml-scalar>: the value goes under compaction.threshold.issue-triage.
bad() {
  printf 'compaction:\n  threshold:\n    issue-triage: %s\n' "$2" > "$TMP/bad.yml"
  run "$TMP/bad.yml" "${3:-$SCHEMA}"
  if [ "$RC" -eq 3 ] && grep -q 'compaction\.threshold\.issue-triage' "$TMP/err" && [ ! -s "$TMP/out" ]; then
    pass "T1e threshold $1: exit 3, key named${3:+ (out of view)}"
  else
    fail "T1e threshold $1${3:+ (out of view)}: rc=$RC err=$(cat "$TMP/err")"
  fi
}
bad "0"      '0'
bad "100"    '100'
bad "-5"     '-5'
bad "true"   'true'
bad "15.5"   '15.5'
bad "string" '"forty"'
for edge in 1 99; do
  printf 'compaction:\n  threshold:\n    issue-triage: %s\n' "$edge" > "$TMP/edge.yml"
  run "$TMP/edge.yml"
  [ "$RC" -eq 0 ] && [ "$(get compaction.threshold.issue-triage)" = "$edge" ] \
    && pass "T1f threshold $edge accepted (range bound)" || fail "T1f threshold $edge: rc=$RC err=$(cat "$TMP/err")"
done

printf 'compaction:\n  threshold:\n    issue-reslover: 30\n' > "$TMP/typo.yml"
run "$TMP/typo.yml"
[ "$RC" -eq 3 ] && grep -q 'compaction\.threshold\.issue-reslover' "$TMP/err" \
  && pass "T1g unknown skill key: exit 3, key named" || fail "T1g rc=$RC err=$(cat "$TMP/err")"

printf 'compaction:\n  enabled: "yes"\n' > "$TMP/enabled.yml"
run "$TMP/enabled.yml"
[ "$RC" -eq 3 ] && grep -q 'compaction\.enabled' "$TMP/err" \
  && pass "T1h non-boolean enabled: exit 3, key named" || fail "T1h rc=$RC err=$(cat "$TMP/err")"

# The guard holds when a per-skill excerpt hides the section: an out-of-view
# key is passed through unvalidated *except* for this range check.
python3 - "$SCHEMA" "$TMP/excerpt.md" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
text = re.sub(r"^# Context-threshold check.*?(?=^# Per-role subagent overrides)", "", text, flags=re.M | re.S)
text = re.sub(r"^### Config Section Map\n.*?(?=^## )", "", text, flags=re.M | re.S)
assert "\ncompaction:\n" not in text
open(sys.argv[2], "w", encoding="utf-8").write(text)
PY
bad "0"    '0'    "$TMP/excerpt.md"
bad "true" 'true' "$TMP/excerpt.md"
printf 'compaction:\n  enabled: 1\n' > "$TMP/enabled.yml"
run "$TMP/enabled.yml" "$TMP/excerpt.md"
[ "$RC" -eq 3 ] && pass "T1i non-boolean enabled is refused out of view too" || fail "T1i rc=$RC err=$(cat "$TMP/err")"
run "$TMP/override.yml" "$TMP/excerpt.md"
[ "$RC" -eq 0 ] && [ "$(get compaction.threshold.issue-resolver)" = "25" ] \
  && pass "T1j a valid out-of-view threshold still passes through" || fail "T1j rc=$RC err=$(cat "$TMP/err")"

# The restricted fallback parser (no PyYAML) reads the same section.
printf 'compaction:\n  enabled: false\n  threshold:\n    auto-pilot: 20\n    init-idd: 55\n' > "$TMP/block.yml"
run --fallback "$TMP/block.yml"
[ "$RC" -eq 0 ] && [ "$(get compaction.enabled)" = "false" ] && [ "$(get compaction.threshold.auto-pilot)" = "20" ] \
  && [ "$(get compaction.threshold.init-idd)" = "55" ] && [ "$(get compaction.threshold.issue-analysis)" = "40" ] \
  && pass "T1k PyYAML-less fallback parses the section" || fail "T1k rc=$RC err=$(cat "$TMP/err")"
bad_fallback() {
  printf 'compaction:\n  threshold:\n    auto-pilot: 0\n' > "$TMP/bad.yml"
  run --fallback "$TMP/bad.yml"
  [ "$RC" -eq 3 ] && pass "T1l fallback parser: the range guard still applies" || fail "T1l rc=$RC err=$(cat "$TMP/err")"
}
bad_fallback

# ─── T2: schema document and init template ──────────────────────────────────
grep -q '^compaction:$' "$SCHEMA" && pass "T2a Full Schema fence has the compaction section" || fail "T2a"
grep -q 'R --> CP\["compaction"\]' "$SCHEMA" && grep -q 'CP --> CP2\["threshold' "$SCHEMA" \
  && pass "T2b Config Section Map has the compaction node and its keys" || fail "T2b"
grep -q '^| `compaction\.enabled` | `true` |' "$SCHEMA" \
  && grep -q '^| `compaction\.threshold` · `auto-pilot` | `15` |' "$SCHEMA" \
  && grep -q '^| `compaction\.threshold` · every other skill | `40` |' "$SCHEMA" \
  && pass "T2c Defaults Table documents enabled and both threshold defaults" || fail "T2c"
grep -q 'compaction\.threshold\.<skill>` must be an integer from 1 to 99' "$SCHEMA" \
  && pass "T2d Validation states the 1-99 rule" || fail "T2d"
if python3 - "$GI_CONFIG" "$SCHEMA" "$TEMPLATE" <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("gi_config", sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
schema, _, _ = mod.load_schema(Path(sys.argv[2]))
template = mod._parse_config_mapping(Path(sys.argv[3]).read_text(encoding="utf-8"), "template")
pick = lambda d: {k: v for k, v in d.items() if k.startswith("compaction.")}
sys.exit(0 if pick(schema) == pick(template) and len(pick(schema)) == 9 else 1)
PY
then pass "T2e init template mirrors every compaction key and default"; else fail "T2e template/schema drift"; fi

# ─── T3: every built skill carries the contract ─────────────────────────────
for s in $ALL_SKILLS; do
  pkg="$SKILLS/$s"
  bundled="$pkg/references/docs/context-threshold.md"
  # The build prepends one generated-from header line and copies the rest verbatim.
  if [ -f "$bundled" ] && tail -n +2 "$bundled" | cmp -s - "$DOC"; then
    pass "T3a $s bundles context-threshold.md verbatim"
  else
    fail "T3a $s: references/docs/context-threshold.md missing or drifted"
  fi
  grep -qF -- '`references/docs/context-threshold.md`' "$pkg/SKILL.md" \
    || grep -qxF 'references/docs/context-threshold.md' "$pkg/SKILL.md" \
    && pass "T3b $s prechecks the bundled doc" || fail "T3b $s precheck list lacks it"
  anchor_check_flat "$pkg" ctx-check "compaction\.threshold\.$s" "T3c $s check names its own compaction.threshold.$s"
  anchor_check_flat "$pkg" ctx-check 'references/docs/context-threshold\.md' "T3d $s check cites the runtime doc"
  grep -q '^compaction:$' "$pkg/references/docs/config-schema.md" \
    && pass "T3e $s config excerpt carries compaction:" || fail "T3e $s excerpt lacks compaction:"
  # init-idd generates the config and ships no gi-config.py: resolve its full
  # bundled schema with the source script instead.
  script="$pkg/references/scripts/gi-config.py"
  [ -f "$script" ] || script="$GI_CONFIG"
  RC=0
  (cd "$TMP/empty" && python3 "$script" --schema "$pkg/references/docs/config-schema.md" \
    --key "compaction.threshold.$s") >"$TMP/out" 2>"$TMP/err" || RC=$?
  [ "$RC" -eq 0 ] && [ "$(cat "$TMP/out")" = "$(default_for "$s")" ] \
    && pass "T3f $s bundled gi-config + excerpt resolve compaction.threshold.$s = $(default_for "$s")" \
    || fail "T3f $s: rc=$RC out=$(cat "$TMP/out") err=$(cat "$TMP/err")"
done

# ─── T4: signal-only contract ───────────────────────────────────────────────
grep -qF 'floor(Z*100/Y)' "$DOC" && pass "T4a remaining percent is floor(Z*100/Y)" || fail "T4a"
grep -qE 'skip the check silently' "$DOC" && pass "T4b no in-context figure: skip silently" || fail "T4b"
grep -qE '[Nn]ever estimate the figure' "$DOC" && pass "T4c never estimate the figure" || fail "T4c"
# Every mention of a transcript, session file or log is a prohibition.
HITS="$(grep -ciE 'transcript|session file|[^-]logs?\b' "$DOC" || true)"
BAD="$(grep -iE 'transcript|session file|[^-]logs?\b' "$DOC" | grep -vE '[Nn]ever' || true)"
[ "${HITS:-0}" -ge 1 ] && [ -z "$BAD" ] && pass "T4d transcript/session/log appear only as prohibitions" \
  || fail "T4d hits=$HITS non-prohibited: $BAD"
# The line-level check above is satisfied by any other "never" on the same line,
# so the prohibition itself is pinned by its polarity-bearing stem as well.
grep -qF 'never read host transcripts, session files or logs' "$DOC" \
  && pass "T4d2 the doc forbids reading host transcripts, session files or logs" || fail "T4d2"
grep -qE 'skill never changes your settings, environment or CLAUDE\.md' "$DOC" \
  && pass "T4e the skill never changes settings, environment or CLAUDE.md" || fail "T4e"
WRITES="$(grep -nE '(^|[^A-Za-z])export [A-Z_]+=|>>|settings\.json|\.claude/settings|/config\b' "$DOC" || true)"
[ -z "$WRITES" ] && pass "T4f the doc carries no settings/env/CLAUDE.md write command" || fail "T4f: $WRITES"
grep -qE 'A skill never triggers compaction and never claims to' "$DOC" \
  && pass "T4g the doc says a skill never triggers compaction" || fail "T4g"
CLAIMS="$(for s in $ALL_SKILLS; do
  find "$SKILLS/$s" -name '*.md' -print0 | xargs -0 grep -HniE \
    '(compacts? (the|this|your) (session|context|conversation)|triggers? (a |the )?compaction|starts? (the )?compaction|performs? (the )?compaction)' \
    2>/dev/null | grep -vE "never|cannot|can't|\bnot\b" || true
done)"
[ -z "$CLAIMS" ] && pass "T4h no built skill claims to compact the session" || fail "T4h claims: $CLAIMS"

# ─── T5: AC4 — every new block is gated on compaction.enabled (q2) ───────────
GATE='[Oo]nly when .compaction\.enabled. is true'
expected_anchors() {
  case "$1" in
    auto-pilot) echo "ctx-check ctx-prespawn-resolve ctx-prespawn-review ctx-reentry" ;;
    issue-resolver|issue-pr-review) echo "ctx-check ctx-reentry" ;;
    *) echo "ctx-check" ;;
  esac
}
for s in $ALL_SKILLS; do
  pkg="$SKILLS/$s"
  found="$(cat "$pkg/SKILL.md" "$pkg"/references/*.md "$pkg"/references/steps/*.md "$pkg"/references/phases/*.md 2>/dev/null \
    | grep -oE '<!-- a:ctx-[a-z0-9-]+ -->' | sed -E 's/<!-- a:(.*) -->/\1/' | sort | tr '\n' ' ' | sed 's/ $//' || true)"
  [ "$found" = "$(expected_anchors "$s")" ] \
    && pass "T5a $s carries exactly the expected ctx-* blocks ($found)" \
    || fail "T5a $s ctx-* blocks: got '$found', want '$(expected_anchors "$s")'"
  for id in $(expected_anchors "$s"); do
    anchor_check_flat "$pkg" "$id" "$GATE" "T5b $s a:$id opens with the compaction.enabled gate"
  done
done
DISABLED="$(awk '/^## Disabled$/{on=1; next} on && /^## /{exit} on' "$DOC")"
printf '%s\n' "$DISABLED" | grep -qF '`compaction.enabled: false` turns every rule below off' \
  && printf '%s\n' "$DISABLED" | grep -qF 'behaves exactly as before' \
  && pass "T5c runtime doc's Disabled clause: false turns everything off, behavior as before" \
  || fail "T5c Disabled clause missing or weakened"

# ─── T6: auto-pilot threshold check ─────────────────────────────────────────
AP="$SKILLS/auto-pilot"
P0="$AP/references/phases/phase-0-lock-resume.md"
anchor_check_flat "$P0" ctx-check 'top of every iteration\*\* only' "T6a evaluated at the top of every iteration only"
anchor_check "$P0" ctx-check '^⚠ Context threshold: \{remaining\}% left ≤ \{threshold\}% — checkpoint current; continuing' \
  "T6b prints the one ⚠ line"
anchor_check_flat "$P0" ctx-check '\*\*continue\*\* the loop' "T6c then continues the loop"
anchor_check_flat "$P0" ctx-check 'never stops the loop, never prompts' "T6d never stops, never prompts"
anchor_check_flat "$P0" ctx-check 'adds no .Result:. value and no \*Stop Conditions\* row' "T6e adds no Result value and no Stop Conditions row"
BUDGET_LINE="$(grep -n '^### Runtime budget check$' "$P0" | cut -d: -f1)"
CHECK_LINE="$(grep -n '^### Context threshold check <!-- a:ctx-check -->$' "$P0" | cut -d: -f1)"
[ -n "$BUDGET_LINE" ] && [ -n "$CHECK_LINE" ] && [ "$CHECK_LINE" -gt "$BUDGET_LINE" ] \
  && pass "T6f the check is a sibling after Runtime budget check" || fail "T6f budget=$BUDGET_LINE check=$CHECK_LINE"
STOPS="$(awk '/^## Stop Conditions$/{on=1; next} on && /^## /{exit} on' "$AP/SKILL.md")"
if [ -n "$STOPS" ] && ! printf '%s\n' "$STOPS" | grep -qiE 'context|compact'; then
  pass "T6g Stop Conditions has no context-threshold row"
else
  fail "T6g Stop Conditions mentions the context threshold (or the section is gone)"
fi
grep -qF 'Outcome:  {merged | left_open | partial_followup | blocked_by_dependency | failed | skipped}' "$AP/SKILL.md" \
  && pass "T6h the six-outcome vocabulary is unchanged" || fail "T6h outcome vocabulary changed"
NEWRESULT="$(grep -rhoE 'Result: [A-Z][A-Z ]*(CONTEXT|COMPACT)[A-Z ]*' "$AP" || true)"
[ -z "$NEWRESULT" ] && pass "T6i no context/compaction Result value anywhere in auto-pilot" || fail "T6i $NEWRESULT"

# ─── T7: ADR and full-URL doc links ─────────────────────────────────────────
for concept in 'Checkpoint at every step' 'Transcript vs. work' 'Lossy compaction' \
               'settings.compaction{enabled, reserveTokens}' 'compact(instructions)' 'beforeCompact' \
               'reset(handoffNote)' 'Idempotency / reconcile'; do
  grep -qF -- "$concept" "$ADR" && pass "T7a ADR maps pi durable: $concept" || fail "T7a ADR lacks: $concept"
done
grep -qF -- '`/auto-pilot --resume`' "$ADR" && grep -qF 'https://github.com/earendil-works/pi/tree/main/packages/durable' "$ADR" \
  && pass "T7b ADR maps reset to --resume and cites the pi durable source" || fail "T7b"
grep -qiE 'AC1 and AC3 were reframed' "$ADR" && grep -qF 'backup comment' "$ADR" \
  && pass "T7c ADR records the AC1/AC3 reframing and the backup comment" || fail "T7c"
BARE="$(grep -noE '(^|[^/A-Za-z])docs/[A-Za-z0-9_./-]+\.md' "$DOC" || true)"
[ -z "$BARE" ] && pass "T7d runtime doc has no bare docs/ token (full URLs only)" || fail "T7d bare: $BARE"
grep -qE '(^|[^/A-Za-z])shared/scripts/' "$DOC" && fail "T7e runtime doc names a shared script token" \
  || pass "T7e runtime doc carries no shared/scripts/ token"
URL='https://github.com/luongnv89/idd/blob/main/docs/context-threshold.md'
[ "$(grep -c "context-threshold\.md" "$SCHEMA")" = "$(grep -cF "$URL" "$SCHEMA")" ] && grep -qF "$URL" "$SCHEMA" \
  && pass "T7f config-schema links the runtime doc only by full URL" || fail "T7f config-schema has a bare context-threshold.md link"
grep -qF "$URL" "$TEMPLATE" && pass "T7g init template links the runtime doc by full URL" || fail "T7g"

# ─── T8: re-entry placement (q3) ────────────────────────────────────────────
for s in $LONG_RUNNING; do
  if python3 - "$SKILLS/$s/SKILL.md" <<'PY'
import sys
data = open(sys.argv[1], "rb").read()
anchor = data.find(b"<!-- a:ctx-reentry -->")
prereq = data.find(b"\n## Prerequisites\n")
block_end = data.find(b"\n## ", anchor + 1)
ok = 0 <= anchor and anchor < prereq and block_end == prereq and prereq + 1 <= 8000
sys.exit(0 if ok else 1)
PY
  then pass "T8 $s: a:ctx-reentry block ends at ## Prerequisites, within 8,000 bytes"
  else fail "T8 $s: a:ctx-reentry not before Prerequisites / beyond 8,000 bytes"
  fi
done

# ─── T9: no on-disk handoff record ──────────────────────────────────────────
REC="$(grep -rlF '.idd/cache/handoff' "$SKILLS" "$DOC" "$ROOT/src" 2>/dev/null || true)"
[ -z "$REC" ] && pass "T9 no built skill, source or runtime doc mentions .idd/cache/handoff" || fail "T9 found in: $REC"

# ─── T10: auto-pilot re-entry ───────────────────────────────────────────────
anchor_check_flat "$AP" ctx-reentry '\*\*[Nn]ever re-spawn a lane or subagent this run spawned that has not returned\*\*' \
  "T10a never re-spawns an in-flight lane or subagent"
anchor_check_flat "$AP" ctx-reentry "\*\*never run Step 1\.0's resume gate\*\*" "T10b never runs Step 1.0's resume gate"
anchor_check_flat "$AP" ctx-reentry 'never re-take or re-validate it' "T10c never re-takes the lock"
anchor_check_flat "$AP" ctx-reentry '\(1\) this conversation.s spawn record.*\(2\) else the pre-spawn checkpoint.*\(3\) any doubt counts as in flight' \
  "T10d explicit evidence order ending in 'any doubt counts as in flight'"
anchor_check_flat "$AP" ctx-reentry 'only after a live .gh … --json. read shows the recorded step did not happen' \
  "T10e live --json check before any effectful repeat"
anchor_check_flat "$AP" ctx-reentry 'gi-state\.py --read' "T10f reads the run state first"
P2="$AP/references/phases/phase-2-resolve.md"
P3="$AP/references/phases/phase-3-4-review.md"
anchor_check_flat "$P2" ctx-prespawn-resolve 'Before this spawn' "T10g resolver pre-spawn checkpoint precedes the spawn"
anchor_check_flat "$P2" ctx-prespawn-resolve 'treats? as a doubt \(.absent.\)' "T10h a dead run after it falls back to absent"
RESOLVE_PATCH="$(anchor_region "$P2" ctx-prespawn-resolve | grep -E '^\{"phase": "resolve"' || true)"
REVIEW_PATCH="$(anchor_region "$P3" ctx-prespawn-review | grep -oE '\{"phase": "review", "current": \{[^}]*\}\}' || true)"
POST_RESOLVE="$(grep -E '^\{"phase": "review", "current": \{"issue": 42' "$P2" | head -1 | sed 's/"…"/"t"/; s/"fix\/42-…"/"fix\/42-a"/')"
END_ITER="$(grep -E '^\{"phase": "triage", "current": null' "$AP/references/phases/phase-5-merge.md" | head -1)"
if [ -n "$RESOLVE_PATCH" ] && [ -n "$REVIEW_PATCH" ] && [ -n "$POST_RESOLVE" ] && [ -n "$END_ITER" ]; then
  pass "T10i the documented checkpoint payloads were extracted"
  STATE_DIR="$TMP/state"
  mkdir -p "$STATE_DIR"
  st() { printf '%s' "$1" | python3 "$GI_STATE" --dir "$STATE_DIR" "${@:2}" >/dev/null 2>"$TMP/st.err"; }
  if st '' --lock --pid 0 && st '{}' --init \
     && st "$RESOLVE_PATCH" --update && st "$POST_RESOLVE" --update \
     && st "$REVIEW_PATCH" --update && st "$END_ITER" --update \
     && st "$(printf '%s' "$RESOLVE_PATCH" | sed 's/"issue": 42/"issue": 43/')" --update; then
    pass "T10j gi-state accepts the pre-spawn checkpoints (from init, after post-resolve, from triage)"
  else
    fail "T10j gi-state refused a documented checkpoint: $(cat "$TMP/st.err")"
  fi
  RC=0; st '{"phase": "merge", "current": {"issue": 44, "phase": "merge"}}' --update || RC=$?
  [ "$RC" -eq 3 ] && pass "T10k control: gi-state still refuses an illegal fresh merge" || fail "T10k control rc=$RC"
else
  fail "T10i could not extract checkpoint payloads (resolve='$RESOLVE_PATCH' review='$REVIEW_PATCH')"
fi

# ─── T11: bounded loops ─────────────────────────────────────────────────────
RS="$SKILLS/issue-resolver"
RV="$SKILLS/issue-pr-review"
anchor_check_flat "$RS" ctx-reentry '\*\*either\*\* the cycle count \*\*or\*\* the premise-reset ledger cannot be read' \
  "T11a resolver: either the cycle count or the premise ledger"
anchor_check_flat "$RS" ctx-reentry "take Step 4's cap-reached path: deliver with known issues and \*\*no\*\* QA marker" \
  "T11b resolver: takes the existing cap path, no QA marker"
anchor_check_flat "$RS" ctx-reentry 'treats the premise gate as blocked' "T11c resolver: interactive premise gate blocked"
anchor_check_flat "$RS" ctx-reentry '\*\*[Nn]ever restart the loop at cycle 1\.\*\*' "T11d resolver: never restarts at cycle 1"
anchor_check_flat "$RV" ctx-reentry 'treat .review\.max_cycles. as reached and take the existing max-cycles path' \
  "T11e pr-review: takes the existing max-cycles path"
anchor_check_flat "$RV" ctx-reentry '\*\*[Nn]ever restart the loop at cycle 1\.\*\*' "T11f pr-review: never restarts at cycle 1"
anchor_lacks "$RV" ctx-reentry 'premise' "T11g pr-review: the cycle count alone (no premise ledger)"

# ─── T12: resolver lane clause ──────────────────────────────────────────────
anchor_check_flat "$RS" ctx-reentry 'starts .cd -- "\$IDD_WORKTREE_PATH" && ….' "T12a re-validates from cd -- \"\$IDD_WORKTREE_PATH\""
anchor_check_flat "$RS" ctx-reentry 'Bind the branch and PR only inside that validated root' "T12b binds branch and PR inside the validated root"
anchor_check_flat "$RS" ctx-reentry '.failure_step: preflight., .status: blocked_dirty.' "T12c an unrecoverable lane record stops blocked_dirty"
anchor_check_flat "$RS" ctx-reentry '\*\*[Nn]ever fall back to the ambient checkout\.\*\*' "T12d never falls back to the ambient checkout"
anchor_check_flat "$RS" ctx-reentry 'never a branch name pasted from the compaction summary' "T12e never pastes a branch name from the summary"
anchor_check_flat "$RV" ctx-reentry 'never paste the literal' "T12f pr-review keeps headRefName behind command substitution"

# ─── T13: /compact line safety ──────────────────────────────────────────────
COMPACT="$(awk '/^## The `\/compact <focus>` line$/{on=1; next} on && /^## /{exit} on' "$DOC")"
printf '%s\n' "$COMPACT" | grep -qF 'only from skill-authored literals and integers' \
  && pass "T13a composed only from skill-authored literals and integers" || fail "T13a"
printf '%s\n' "$COMPACT" | grep -qF 'Never put a branch name, an issue or PR title, or any issue/PR text in it' \
  && pass "T13b never a branch name, title, or issue/PR text" || fail "T13b"
for s in issue-resolver issue-pr-review issue-analysis issue-creator issue-triage plan-to-issues init-idd; do
  anchor_check_flat "$SKILLS/$s" ctx-check '/compact <focus>. line \([^)]* only\)' "T13c $s restricts its /compact line to literals"
done

# ─── T14: CI step (q1) ──────────────────────────────────────────────────────
if python3 - "$WORKFLOW" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
hits = [i for i, l in enumerate(lines) if l.strip() == "- name: test-context-threshold-540"]
runs = [l for l in lines if "tests/test-context-threshold-540.sh" in l]
build = [i for i, l in enumerate(lines) if l.strip() == "run: ./scripts/build.sh"]
if len(hits) != 1 or len(runs) != 1 or not build or hits[0] < build[0]:
    sys.exit(1)
start = hits[0]
indent = len(lines[start]) - len(lines[start].lstrip())
block = [lines[start]]
for line in lines[start + 1:]:
    if line.strip() and len(line) - len(line.lstrip()) <= indent:
        break
    block.append(line)
keys = [l.strip().split(":", 1)[0] for l in block if l.strip()]
sys.exit(0 if keys == ["- name", "run"] and block[1].strip() == "run: bash tests/test-context-threshold-540.sh" else 1)
PY
then pass "T14 dist-check.yml: one plain name/run step after the build, no if/continue-on-error/env/uses"
else fail "T14 dist-check.yml step missing, duplicated, misplaced, or carries extra keys"
fi

echo ""
echo "  Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
