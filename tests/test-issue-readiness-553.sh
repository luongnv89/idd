#!/usr/bin/env bash
# test-issue-readiness-553.sh — a readiness gate before an unattended resolve
# (issue #553).
#
# An issue is ready when it has acceptance criteria and neither its type nor a
# criterion ends with `(needs review)`. Auto mode never resolves one that is
# not: triage marks it `unclear`, the auto-pilot pick and explicit-list loop
# skip it with `skipped_reason: needs_clarification`, the resolver's own gate
# takes its default No. A resolve of an issue that was not ready ends PARTIAL,
# and the merge floor stays unmet while a criterion carries the marker.
#
#   T1  gi-ready.py judges bodies (behavioural), including one shaped like this
#       issue's own, which only *discusses* the marker;
#       (incl. a marker on a wrapped line or under a sub-heading, #584);
#   T2  gi-triage-graph.py gives `unclear` and orders it after ready issues, above maybe-fixed;
#   T3  gi-runlog accepts the needs_clarification records both writers return;
#   T4  the one rule, and each consumer pointing to it (prose pins);
#   T5  the built bundles carry the script and the digest section where named;
#   T6  the CI step exists.
#
# Usage: bash tests/test-issue-readiness-553.sh
# Returns: exit 0 if all checks pass, exit 1 on failure
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
READY="$ROOT/src/shared/scripts/gi-ready.py"
GRAPH="$ROOT/src/shared/scripts/gi-triage-graph.py"
RUNLOG="$ROOT/src/shared/scripts/gi-runlog.py"
METHOD="$ROOT/docs/idd-methodology.md"
RS="$ROOT/src/skills/issue-resolver"
AP="$ROOT/src/skills/auto-pilot"
TR="$ROOT/src/skills/issue-triage"
PR="$ROOT/src/skills/issue-pr-review/SKILL.source.md"
WORKFLOW="$ROOT/.github/workflows/dist-check.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
has() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3"; }

echo "◆ Issue readiness gate (#553)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

for f in "$READY" "$GRAPH" "$RUNLOG" "$METHOD" "$WORKFLOW"; do
  [ -f "$f" ] || { echo "  ✗ missing $f"; exit 1; }
done

# judge <json> — prints "ready|reasons" for one issue
judge() {
  printf '%s' "$1" | python3 "$READY" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(str(d["ready"]).lower() + "|" + ",".join(d["reasons"]))'
}
# body <markdown> — wraps a body into an issue object
body() { python3 -c 'import json,sys; print(json.dumps({"number": 7, "body": sys.argv[1]}))' "$1"; }

# ── T1: the predicate ─────────────────────────────────────────────────────
discusses="$(cat <<'MD'
<!-- idd:normalized v1 -->

## Type

improvement (high confidence)

## Description

`(needs review)` on type or criteria is read by nothing downstream.

> **Reporter Context**
> Acceptance criteria:
> - [ ] something (needs review)

## Acceptance Criteria

- [ ] Auto-pilot skips an issue with a `(needs review)` type or criterion (high confidence)
- [ ] A run whose criteria were written by the resolver never ends `PASS` (high confidence)
MD
)"
[ "$(judge "$(body "$discusses")")" = "true|" ] \
  && pass "T1.1 a body that only discusses the marker (inline code, blockquote) is ready" \
  || fail "T1.1 a body that discusses the marker was judged not ready: $(judge "$(body "$discusses")")"

trailing=$'## Type\n\nbug (high confidence)\n\n## Acceptance Criteria\n\n- [ ] Login works (high)\n- [ ] Logout works (needs review)\n'
[ "$(judge "$(body "$trailing")")" = "false|criteria_need_review" ] \
  && pass "T1.2 a criterion ending with (needs review) is not ready" \
  || fail "T1.2 trailing criterion marker: $(judge "$(body "$trailing")")"

typed=$'## Type\n\nbug (needs review)\n\n## Acceptance Criteria\n\n1. Login works\n'
[ "$(judge "$(body "$typed")")" = "false|type_needs_review" ] \
  && pass "T1.3 a type ending with (needs review) is not ready; numbered criteria count" \
  || fail "T1.3 type marker: $(judge "$(body "$typed")")"

for case in "prose only" "" $'## Acceptance Criteria\n\nTBD\n' \
            $'> ## Acceptance Criteria\n> - [ ] quoted\n' \
            $'```\n## Acceptance Criteria\n- [ ] fenced\n```\n'; do
  got="$(judge "$(body "$case")")"
  [ "$got" = "false|no_criteria" ] \
    && pass "T1.4 no criteria is not ready ($(printf '%s' "$case" | head -c 24 | tr '\n' ' ')…)" \
    || fail "T1.4 no-criteria case judged $got: $(printf '%s' "$case" | head -c 40)"
done

[ "$(judge '{"number":7,"body":null}')" = "false|no_criteria" ] \
  && pass "T1.5 a null body reads as empty" || fail "T1.5 null body"
lower=$'### acceptance criteria:\n* [x] done\n'
[ "$(judge "$(body "$lower")")" = "true|" ] \
  && pass "T1.6 any heading level and case, a trailing colon, a checked item" \
  || fail "T1.6 heading variants: $(judge "$(body "$lower")")"
[ "$(judge "{\"issue\": $(body "$trailing")}")" = "false|criteria_need_review" ] \
  && pass "T1.7 a gi-issue.py envelope is read" || fail "T1.7 gi-issue envelope"

list="$(printf '{"issues":[%s,%s]}' "$(body "$lower" | sed 's/"number": 7/"number": 1/')" \
  "$(body "prose" | sed 's/"number": 7/"number": 2/')" | python3 "$READY")"
printf '%s' "$list" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["not_ready"] == [2], d
assert [i["ready"] for i in d["issues"]] == [True, False], d' \
  && pass "T1.8 a gi-backlog.py envelope returns per-issue verdicts and not_ready" \
  || fail "T1.8 backlog envelope: $list"

for input in "" "not json" '{"number":1}' '{"issues":[{"number":1,"body":3}]}'; do
  rc=0; printf '%s' "$input" | python3 "$READY" >/dev/null 2>"$TMP/err" || rc=$?
  [ "$rc" -eq 4 ] && grep -q '^⚠ gi-ready:' "$TMP/err" \
    && pass "T1.9 cannot judge '${input:0:12}' → exit 4 with a ⚠ line" \
    || fail "T1.9 '${input:0:12}' exited $rc"
done
python3 "$READY" --help >/dev/null && pass "T1.10 --help exits 0" || fail "T1.10 --help"
[ -x "$READY" ] && pass "T1.11 the script is executable" || fail "T1.11 gi-ready.py not 0755"

# T1.12-T1.15 (#584): a marker on a wrapped line, or under a sub-heading of the
# Acceptance Criteria section, used to be missed.
# crit <markdown> — prints the --criteria texts, joined by '|'
crit() { body "$1" | python3 "$READY" --criteria | python3 -c 'import json,sys; print("|".join(c["id"] + "=" + c["text"] for c in json.load(sys.stdin)["criteria"]))'; }
wrapped=$'## Acceptance Criteria\n\n- [ ] Login works on every device we\n  support today (needs review)\n- [ ] Logout works\n'
[ "$(judge "$(body "$wrapped")")" = "false|criteria_need_review" ] \
  && pass "T1.12 a (needs review) on a criterion's wrapped continuation line counts" \
  || fail "T1.12 wrapped marker: $(judge "$(body "$wrapped")")"
[ "$(crit "$wrapped")" = "AC1=Login works on every device we|AC2=Logout works" ] \
  && pass "T1.13 a wrapped line keeps the numbering and the first-line text" \
  || fail "T1.13 wrapped numbering: $(crit "$wrapped")"
subhead=$'## Acceptance Criteria\n\n- [ ] Login works\n\n### Edge cases\n\n- [ ] Expired tokens redirect (needs review)\n\n## Metadata\n\n- [ ] not a criterion (needs review)\n'
[ "$(judge "$(body "$subhead")")" = "false|criteria_need_review" ] \
  && [ "$(crit "$subhead")" = "AC1=Login works|AC2=Expired tokens redirect (needs review)" ] \
  && pass "T1.14 items under a deeper sub-heading are criteria; a same-level heading ends the section" \
  || fail "T1.14 sub-heading: $(judge "$(body "$subhead")") / $(crit "$subhead")"
firstline=$'## Acceptance Criteria\n\n- [ ] Login works (needs review)\n  on mobile and desktop\n'
[ "$(judge "$(body "$firstline")")" = "false|criteria_need_review" ] \
  && pass "T1.16 a marker ending the first line still counts when the item wraps" \
  || fail "T1.16 first-line marker before a continuation: $(judge "$(body "$firstline")")"
sibling=$'## Acceptance Criteria\n\n- [ ] Login works\n\n## Notes\n\n- [ ] aside (needs review)\n'
[ "$(judge "$(body "$sibling")")" = "true|" ] && [ "$(crit "$sibling")" = "AC1=Login works" ] \
  && pass "T1.15 a marker under a sibling heading is not a criterion" \
  || fail "T1.15 sibling heading: $(judge "$(body "$sibling")") / $(crit "$sibling")"


# ── T2: triage status `unclear` ───────────────────────────────────────────
cat > "$TMP/scan.json" <<'EOF'
{"issues":[
 {"number":1,"type":"bug","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-04T00:00:00Z","needs_clarification":true},
 {"number":2,"type":"bug","createdAt":"2026-01-02T00:00:00Z","updatedAt":"2026-01-04T00:00:00Z"},
 {"number":3,"type":"bug","createdAt":"2026-01-03T00:00:00Z","updatedAt":"2026-01-04T00:00:00Z","potentially_fixed_by":{"pr":9},"needs_clarification":true},
 {"number":4,"type":"bug","createdAt":"2026-01-03T00:00:00Z","updatedAt":"2026-01-04T00:00:00Z","needs_clarification":"yes"}],
 "edges":[]}
EOF
graph_out="$(python3 "$GRAPH" --no-config --now 2026-01-05T00:00:00Z < "$TMP/scan.json")"
printf '%s' "$graph_out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
status = {i["number"]: i["status"] for i in d["issues"]}
assert d["summary"]["suggested_order"] == [2, 4, 1, 3], d["summary"]["suggested_order"]
assert status == {1: "unclear", 2: "ready", 3: "maybe-fixed", 4: "ready"}, status' \
  && pass "T2.1 unclear sorts after ready issues, above maybe-fixed; only true counts" \
  || fail "T2.1 triage graph: $(printf '%s' "$graph_out" | head -c 300)"

# ── T3: the run log accepts the reason ────────────────────────────────────
printf '%s' '{"issue":553,"mode":"auto","skill":"issue-resolver","outcome":"failed","pr":null,"skipped_reason":"needs_clarification"}' \
  | python3 "$RUNLOG" --echo >/dev/null \
  && pass "T3.1 a resolver gate decline with needs_clarification validates" \
  || fail "T3.1 gi-runlog rejected the resolver record"
printf '%s' '{"issue":553,"mode":"balanced","skill":"auto-pilot","outcome":"skipped","pr":null,"skipped_reason":"needs_clarification"}' \
  | python3 "$RUNLOG" --echo >/dev/null \
  && pass "T3.2 an auto-pilot skipped line with needs_clarification validates" \
  || fail "T3.2 gi-runlog rejected the auto-pilot record"
has "$ROOT/docs/run-log-schema.md" '`needs_clarification`' "T3.3 run-log-schema.md lists needs_clarification"

# ── T4: one rule, consumers point to it ──────────────────────────────────
n="$(grep -c '^## Issue Readiness$' "$METHOD")"
[ "$n" -eq 1 ] && pass "T4.1 idd-methodology.md has one *Issue Readiness* section" \
  || fail "T4.1 expected one '## Issue Readiness' heading, found $n"
has "$METHOD" 'skipped_reason: needs_clarification' "T4.2 the rule names the skip reason"
has "$METHOD" 'ends `PARTIAL`, and the merge floor stays unmet' "T4.3 the rule caps the run and holds the merge"
has "$ROOT/scripts/build/common.py" '"Issue Readiness"' "T4.4 the section is an optional digest section"
for f in "$RS/SKILL.source.md" "$AP/references/phases/phase-1-triage-pick.md" \
         "$AP/references/explicit-list-mode.md" "$TR/SKILL.source.md"; do
  grep -qF '*Issue Readiness*' "$f" && grep -qF 'shared/scripts/gi-ready.py' "$f" \
    && pass "T4.5 ${f#"$ROOT"/} points to the rule and runs the script" \
    || fail "T4.5 ${f#"$ROOT"/} does not point to *Issue Readiness* and gi-ready.py"
done
has "$RS/references/error-messages.md" 'skipped_reason: needs_clarification`. <!-- auto:no -->' \
  "T4.6 the resolver's readiness gate takes No in auto"
has "$RS/SKILL.source.md" 'ends with `(needs review)`' "T4.7 0d marks the criteria it writes"
has "$RS/SKILL.source.md" 'or any criterion 0d writes, prints `×`' \
  "T4.15 a criterion 0d writes fails Criteria confirmed, so the run never ends PASS"
has "$METHOD" 'or with criteria the resolver wrote, ends `PARTIAL`' \
  "T4.16 the rule caps a run whose criteria the resolver wrote"
has "$RS/references/step-reports.md" '`Criteria confirmed`' "T4.8 Step 0 carries the Criteria confirmed check"
has "$RS/references/step-reports.md" 'legitimate in exactly three places: *Step 0 — Preflight*' \
  "T4.9 Step 0 PARTIAL is a listed legitimate place"
has "$AP/references/phases/phase-1-triage-pick.md" '| `needs_clarification` | *Step 1.2b*' \
  "T4.10 the pick's bucket table maps needs_clarification"
has "$AP/references/phases/phase-1-triage-pick.md" '| the body is not ready | `needs_clarification` |' \
  "T4.11 Step 1.2b rejects a body that is not ready"
has "$AP/references/explicit-list-mode.md" 'Readiness rides this gate' \
  "T4.12 explicit-list mode reuses the quarantine gate"
has "$PR" 'none is `unverified` or ends with `(needs review)`' "T4.13 the merge floor is unmet on an unconfirmed criterion"
has "$TR/references/output-and-persist.md" '`"unclear"`' "T4.14 the triage schema lists unclear"

# ── T5: built bundles ─────────────────────────────────────────────────────
for skill in issue-resolver auto-pilot issue-triage; do
  shipped="$ROOT/skills/$skill/references/scripts/gi-ready.py"
  cmp -s "$READY" "$shipped" && pass "T5.1 $skill ships gi-ready.py byte-identical" \
    || fail "T5.1 $skill: gi-ready.py missing or differs"
  grep -q '^## Issue Readiness$' "$ROOT/skills/$skill/references/docs/idd-methodology.md" \
    && pass "T5.2 $skill's methodology digest carries *Issue Readiness*" \
    || fail "T5.2 $skill's digest lacks *Issue Readiness*"
done
for skill in issue-creator issue-pr-review init-idd issue-analysis; do
  if grep -q '^## Issue Readiness$' "$ROOT/skills/$skill/references/docs/idd-methodology.md"; then
    fail "T5.3 $skill bundles *Issue Readiness* without naming it"
  else
    pass "T5.3 $skill does not pay for *Issue Readiness*"
  fi
done

# ── T6: CI ────────────────────────────────────────────────────────────────
has "$WORKFLOW" 'bash tests/test-issue-readiness-553.sh' "T6.1 dist-check runs this test"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || { echo "  ✗ Issue readiness tests failed"; exit 1; }
echo "  ✓ Issue readiness tests passed"
