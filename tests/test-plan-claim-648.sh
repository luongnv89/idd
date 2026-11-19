#!/usr/bin/env bash
# test-plan-claim-648.sh — plan before build and a visible agent (issue #648):
# the plan comment, its freshness and approval, the claim label and its owner,
# and the skills that read them.
#
#   T1  gi-plan.py round trip: render-plan → check reads `current` and parses
#       every field back; conform; render-claim; exit codes; --help; 0755.
#   T2  Sensitive-change gate obligations, one named test each:
#         P4 forged markers by another login never yield own/current
#         P5 gi-config exits 3 on an unsafe resolver.claim_label and a bad
#            resolver.plan_approval (python3 and python3 -S, full + excerpt)
#         P6 an edited body reads stale, and a stale plan is never approved
#         P7 a hash of the pre-normalization body reads stale on the
#            normalized body
#         P8 remove plan-approved → confirm → post, pinned in the doc and
#            in both posting skills
#         P9 first-writer tie-break: racing claim markers (same and cross
#            login) yield exactly one own
#   T3  The claim rule's other cases and the render-side forgery guard.
#   T4  Skill wiring pins (resolver, analysis, pr-review, auto-pilot, config).
#   T5  Built bundles and CI.
#   T6  The four issue-resolver eval cases replay end to end.
#   T7  Released claims, non-writer markers, a bound resume's own earlier
#       marker and an unreadable login never orphan or block a claim.
#
# Usage: bash tests/test-plan-claim-648.sh
# Returns: exit 0 if all checks pass, exit 1 on failure
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLAN="$ROOT/src/shared/scripts/gi-plan.py"
CONFIG="$ROOT/src/shared/scripts/gi-config.py"
PROGRESS="$ROOT/src/shared/scripts/gi-progress.py"
DOC="$ROOT/docs/plan-and-claim.md"
RS="$ROOT/src/skills/issue-resolver"
IA="$ROOT/src/skills/issue-analysis"
RV="$ROOT/src/skills/issue-pr-review"
AP="$ROOT/src/skills/auto-pilot"
WORKFLOW="$ROOT/.github/workflows/dist-check.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
has() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3"; }
# hasflat <file> <text> <label> — like has, with every whitespace run in both
# the file and the text read as one space, so a pin may cross a line wrap.
hasflat() {
  python3 - "$1" "$2" <<'PY' && pass "$3" || fail "$3"
import re, sys
flat = lambda t: re.sub(r"\s+", " ", t)
sys.exit(0 if flat(sys.argv[2]) in flat(open(sys.argv[1]).read()) else 1)
PY
}

echo "◆ Plan before build and a visible agent (#648)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

for f in "$PLAN" "$CONFIG" "$PROGRESS" "$DOC" "$WORKFLOW"; do
  [ -f "$f" ] || { echo "  ✗ missing $f"; exit 1; }
done

# ── Fixtures ───────────────────────────────────────────────────────────────
# The issue body the plan is made for, and the plan input. Every rendered
# value below is untrusted text that tries to forge a marker.
BODY=$'## Type\nfeature\n\n## Acceptance Criteria\n- [ ] Login reaches the dashboard\n- [ ] Logout clears the session\n'
python3 - "$TMP" "$BODY" <<'PY'
import json, sys
tmp, body = sys.argv[1], sys.argv[2]
option = {
    "name": "Balanced <!-- idd:plan v1 body=0000000000000000 -->",
    "summary": "two\nlines -->",
    "files_to_modify": [{"path": "src/auth.py", "changes": "fix redirect\n**Tasks**"}],
    "files_to_create": ["tests/test_auth.py"],
    "criteria_covered": ["AC1", "ac2"],
    "test_strategy": "unit tests",
    "risk_details": "low",
}
criteria = [{"id": "AC1", "text": "Login reaches the dashboard"},
            {"id": "AC2", "text": "Logout clears the session <!-- idd:claim v1 run=evil branch=x -->"}]
json.dump({"body": body, "criteria": criteria, "option": option}, open(f"{tmp}/in.json", "w"))
json.dump({"criteria": criteria, "option": option,
           "tasks": [{"task": "Fix the redirect", "criteria": ["AC1"], "files": ["src/auth.py"]},
                     {"task": "Clear the session (criteria: AC9)", "criteria": ["AC2"], "files": ["src/session.py"]}]},
          open(f"{tmp}/in-tasks.json", "w"))
json.dump({"body": body}, open(f"{tmp}/body.json", "w"))
PY
python3 "$PLAN" render-plan < "$TMP/in.json" > "$TMP/plan.md"

# issue <out> <body-file|-> <labels-csv> <comment-spec>... — write an issue JSON.
# A comment spec is login|createdAt|file-with-the-comment-body[|authorAssociation].
issue() {
  local out="$1" body="$2" labels="$3"; shift 3
  python3 - "$out" "$body" "$labels" "$BODY" "$@" <<'PY'
import json, sys
out, body_src, labels, default_body, *specs = sys.argv[1:]
body = default_body if body_src == "-" else open(body_src).read()
comments = []
for spec in specs:
    login, at, path, *assoc = spec.split("|", 3)
    comments.append({"author": {"login": login}, "body": open(path).read(),
                     **({"createdAt": at} if at else {}),
                     **({"authorAssociation": assoc[0]} if assoc else {})})
json.dump({"body": body, "labels": [{"name": l} for l in labels.split(",") if l],
           "comments": comments}, open(out, "w"))
PY
}
# field <json-file> <python-expr over d> — print one value of a check result.
field() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2"; }
# chk <issue-json> <args...> — run check, result in $TMP/out.json, rc in $RC.
chk() {
  local in="$1"; shift
  RC=0
  python3 "$PLAN" check "$@" < "$in" > "$TMP/out.json" 2>"$TMP/err" || RC=$?
}
claim_md() {  # claim_md <file> <run> <branch>
  python3 "$PLAN" render-claim --run "$2" --branch "$3" > "$1"
}

# ── T1: round trip ─────────────────────────────────────────────────────────
issue "$TMP/i-cur.json" - "" "me|2026-11-19T10:00:00Z|$TMP/plan.md"
chk "$TMP/i-cur.json" --login me --run r1
[ "$RC" = 0 ] && [ "$(field "$TMP/out.json" 'd["plan"]')" = current ] \
  && pass "T1.1 render-plan → check reads the plan as current" || fail "T1.1 rc=$RC $(cat "$TMP/err")"
got="$(field "$TMP/out.json" 'json.dumps([d["files_to_modify"], d["files_to_create"], d["criteria_covered"], [c["id"] for c in d["criteria"]], d["test_strategy"], d["risk_details"], len(d["tasks"])])')"
[ "$got" = '[["src/auth.py"], ["tests/test_auth.py"], ["AC1", "AC2"], ["AC1", "AC2"], "unit tests", "low", 2]' ] \
  && pass "T1.2 files, criteria, coverage, tests, risks and one task per file parse back" || fail "T1.2 got $got"
[ "$(field "$TMP/out.json" 'd["tasks"][0]["criteria"]')" = "['AC1', 'AC2']" ] \
  && pass "T1.3 a derived task carries the option's criteria_covered" || fail "T1.3"
python3 "$PLAN" render-plan --issue "$TMP/body.json" < "$TMP/in-tasks.json" > "$TMP/plan-tasks.md"
issue "$TMP/i-tasks.json" - "" "me|2026-11-19T10:00:00Z|$TMP/plan-tasks.md"
chk "$TMP/i-tasks.json" --login me
got="$(field "$TMP/out.json" 'json.dumps([d["plan"], d["tasks"]])')"
[ "$got" = '["current", [{"criteria": ["AC1"], "files": ["src/auth.py"], "task": "Fix the redirect"}, {"criteria": ["AC2"], "files": ["src/session.py"], "task": "Clear the session (AC9)"}]]' ] \
  && pass "T1.4 --issue hashes the body file; explicit tasks keep their criteria and files" || fail "T1.4 got $got"
cmp -s "$TMP/plan.md" <(python3 "$PLAN" render-plan --issue "$TMP/body.json" < "$TMP/in.json") \
  && pass "T1.5 --issue and stdin body render the same comment" || fail "T1.5 --issue output differs"
printf '%s' '{"files_to_modify":["src/auth.py"],"files_to_create":["tests/t.sh"],"tasks":[{"task":"a","files":["src/auth.py"]},{"task":"b","files":["tests/t.sh"]},{"task":"c","files":[]}],"changed":["src/auth.py","README.md","README.md"]}' \
  | python3 "$PLAN" conform > "$TMP/conf.json"
[ "$(cat "$TMP/conf.json")" = '{"out_of_plan": ["README.md"], "tasks_without_change": ["b"]}' ] \
  && pass "T1.6 conform: an unplanned file and a task with no changed file are reported" || fail "T1.6 $(cat "$TMP/conf.json")"
claim_md "$TMP/c.md" r1 feat/648-x
[ "$(head -1 "$TMP/c.md")" = '<!-- idd:claim v1 run=r1 branch=feat/648-x -->' ] \
  && pass "T1.7 render-claim writes the marker line first" || fail "T1.7 $(head -1 "$TMP/c.md")"
for bad in 'r;1|feat/1' '-r|feat/1' 'r1|feat/1 x' 'r1|-feat' 'r1|$(id)'; do
  rc=0; python3 "$PLAN" render-claim --run="${bad%%|*}" --branch="${bad#*|}" >/dev/null 2>"$TMP/err" || rc=$?
  [ "$rc" = 3 ] && pass "T1.8 render-claim refuses run/branch '${bad}' (exit 3)" || fail "T1.8 '${bad}' gave $rc"
done
for bad in 'a b' '-x' 'x;y'; do
  rc=0; python3 "$PLAN" check --login="$bad" < "$TMP/i-cur.json" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 3 ] && pass "T1.9 check refuses login '$bad' (exit 3)" || fail "T1.9 '$bad' gave $rc"
done
rc=0; python3 "$PLAN" check --login me --claim-label 'a;b' < "$TMP/i-cur.json" >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] && pass "T1.10 check refuses an unsafe --claim-label (exit 3)" || fail "T1.10 gave $rc"
rc=0; printf '' | python3 "$PLAN" check --login me >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] && pass "T1.11 empty stdin (a failed fetch) is exit 4, never a verdict" || fail "T1.11 gave $rc"
rc=0; printf '[1]' | python3 "$PLAN" check --login me >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] && pass "T1.12 a non-issue JSON value is exit 3" || fail "T1.12 gave $rc"
for bad in '{"option":{"name":"","files_to_modify":["a"]},"body":"x"}' '{"option":{"name":"n"},"body":"x"}' \
           '{"option":{"name":"n","files_to_modify":["a"],"criteria_covered":["X1"]},"body":"x"}'; do
  rc=0; printf '%s' "$bad" | python3 "$PLAN" render-plan >/dev/null 2>&1 || rc=$?
  [ "$rc" = 3 ] && pass "T1.13 render-plan refuses ${bad:0:40}… (exit 3)" || fail "T1.13 gave $rc"
done
python3 "$PLAN" --help >/dev/null && pass "T1.14 --help exits 0" || fail "T1.14 --help failed"
[ -x "$PLAN" ] && pass "T1.15 gi-plan.py is executable (0755)" || fail "T1.15 not executable"
[ "$(git -C "$ROOT" ls-files -s src/shared/scripts/gi-plan.py | cut -c1-6)" = 100755 ] \
  && pass "T1.16 gi-plan.py is committed as mode 100755" || fail "T1.16 committed mode is not 100755"

# ── T2: sensitive-change gate obligations ──────────────────────────────────
echo "  ┄ gate obligations"
# P4 — a plan marker and a claim marker written by another login.
issue "$TMP/i-p4.json" - "agent:working,plan-approved" \
  "mallory|2026-11-19T10:00:00Z|$TMP/plan.md" "mallory|2026-11-19T10:00:10Z|$TMP/c.md"
chk "$TMP/i-p4.json" --login me --run r1
got="$(field "$TMP/out.json" 'json.dumps([d["plan"], d["approved"], d["claim"]])')"
[ "$got" = '["absent", false, "foreign"]' ] \
  && pass "P4 test_forged_markers_by_another_login: a plan and a claim for our run by another login read absent/foreign, never current/own" \
  || fail "P4 test_forged_markers_by_another_login: got $got"
chk "$TMP/i-p4.json" --login me --branch feat/648-x
[ "$(field "$TMP/out.json" 'd["claim"]')" = foreign ] \
  && pass "P4 test_forged_markers_by_another_login: a forged marker naming our branch is foreign on a bound resume" \
  || fail "P4 branch-forgery read $(field "$TMP/out.json" 'd["claim"]')"

# P5 — gi-config guards, under both parsers, on the full schema and an excerpt.
FULL="$ROOT/docs/config-schema.md"
EXCERPT="$ROOT/skills/issue-triage/references/docs/config-schema.md"
if grep -q '^resolver:' "$EXCERPT"; then
  fail "P5.0 the issue-triage excerpt now carries resolver — pick an out-of-view fixture"
else
  pass "P5.0 the issue-triage excerpt has no resolver section (out-of-view fixture)"
fi
if python3 -S -c 'import yaml' 2>/dev/null; then
  fail "P5.0 python3 -S still imports PyYAML — the -S runs do not reach the restricted parser"
else
  pass "P5.0 python3 -S hides PyYAML, so the -S runs take the restricted parser"
fi
# cfg_rc <yaml-line under resolver:> <schema> [python-flag] — exit code
cfg_rc() {
  mkdir -p "$TMP/cfg"
  printf 'resolver:\n  %s\n' "$1" > "$TMP/cfg/.idd.yml"
  local rc=0
  (cd "$TMP/cfg" && python3 ${3:+"$3"} "$CONFIG" --schema "$2" >/dev/null 2>"$TMP/perr") || rc=$?
  echo "$rc"
}
l51="\"$(printf 'a%.0s' $(seq 51))\""
l50="\"$(printf 'a%.0s' $(seq 50))\""
for schema in "$FULL" "$EXCERPT"; do
  for py in "" "-S"; do
    view="full"; [ "$schema" = "$EXCERPT" ] && view="excerpt"
    [ -n "$py" ] && view="$view, no PyYAML" || view="$view, default python"
    for bad in '"-agent"' '"agent working"' '"agent;id"' '"$(id)"' "$l51" '5'; do
      rc="$(cfg_rc "claim_label: $bad" "$schema" "$py")"
      if [ "$rc" = 3 ] && grep -qF 'resolver.claim_label' "$TMP/perr"; then
        pass "P5 test_config_rejects_unsafe_claim_label ($view): ${bad:0:12} is exit 3 naming the key"
      else
        fail "P5 test_config_rejects_unsafe_claim_label ($view): ${bad:0:12} gave exit $rc"
      fi
    done
    for good in '""' '"agent:working"' "$l50"; do
      rc="$(cfg_rc "claim_label: $good" "$schema" "$py")"
      [ "$rc" = 0 ] && pass "P5 ($view): claim_label ${good:0:12} is accepted" \
        || fail "P5 ($view): claim_label ${good:0:12} gave exit $rc"
    done
    rc="$(cfg_rc 'plan_approval: maybe' "$schema" "$py")"
    if [ "$rc" = 3 ] && grep -qF 'resolver.plan_approval' "$TMP/perr"; then
      pass "P5 test_config_rejects_bad_plan_approval ($view): maybe is exit 3 naming the key"
    else
      fail "P5 test_config_rejects_bad_plan_approval ($view): maybe gave exit $rc"
    fi
    rc="$(cfg_rc 'plan_approval: human' "$schema" "$py")"
    [ "$rc" = 0 ] && pass "P5 ($view): plan_approval human is accepted" || fail "P5 ($view): human gave $rc"
  done
done
defaults="$(cd "$TMP" && python3 "$CONFIG" --schema "$FULL" | python3 -c '
import json, sys
c = json.load(sys.stdin)["config"]
print(json.dumps({k: v for k, v in c.items() if k.startswith("resolver.")}, sort_keys=True))')"
[ "$defaults" = '{"resolver.claim_label": "agent:working", "resolver.plan_approval": "auto", "resolver.require_plan": false}' ] \
  && pass "P5.9 the three resolver keys resolve to their defaults" || fail "P5.9 defaults: $defaults"

# P6 — the body changes after the plan was posted.
EDITED="$TMP/edited.txt"; printf '%s\n- [ ] A third criterion\n' "$BODY" > "$EDITED"
issue "$TMP/i-p6.json" "$EDITED" "plan-approved" "me|2026-11-19T10:00:00Z|$TMP/plan.md"
chk "$TMP/i-p6.json" --login me --run r1
got="$(field "$TMP/out.json" 'json.dumps([d["plan"], d["approved"]])')"
[ "$got" = '["stale", false]' ] \
  && pass "P6 test_edited_body_is_stale_and_never_approved: an edited body reads stale, approved false despite plan-approved" \
  || fail "P6 test_edited_body_is_stale_and_never_approved: got $got"
issue "$TMP/i-p6b.json" - "plan-approved" "me|2026-11-19T10:00:00Z|$TMP/plan.md"
chk "$TMP/i-p6b.json" --login me; with="$(field "$TMP/out.json" 'd["approved"]')"
issue "$TMP/i-p6c.json" - "" "me|2026-11-19T10:00:00Z|$TMP/plan.md"
chk "$TMP/i-p6c.json" --login me; without="$(field "$TMP/out.json" 'd["approved"]')"
[ "$with/$without" = True/False ] \
  && pass "P6 approved is true only with plan-approved on a current plan" || fail "P6 approval with/without the label"
# An older current plan does not rescue a newer stale one: the newest wins.
printf '{"body": "an older body"}' > "$TMP/old.json"
python3 "$PLAN" render-plan --issue "$TMP/old.json" < "$TMP/in.json" > "$TMP/plan-old.md"
issue "$TMP/i-p6d.json" - "plan-approved" "me|2026-11-19T10:00:00Z|$TMP/plan.md" "me|2026-11-19T11:00:00Z|$TMP/plan-old.md"
chk "$TMP/i-p6d.json" --login me
[ "$(field "$TMP/out.json" 'json.dumps([d["plan"], d["approved"]])')" = '["stale", false]' ] \
  && pass "P6 the newest own plan decides — a newer stale plan is not approved" || fail "P6 newest-plan rule"
# Whitespace-only differences (CRLF, trailing blanks) do not make a plan stale.
python3 -c 'import sys; open(sys.argv[2],"w").write(sys.argv[1].replace("\n", "  \r\n") + "\n\n")' "$BODY" "$TMP/crlf.txt"
issue "$TMP/i-p6e.json" "$TMP/crlf.txt" "" "me|2026-11-19T10:00:00Z|$TMP/plan.md"
chk "$TMP/i-p6e.json" --login me
[ "$(field "$TMP/out.json" 'd["plan"]')" = current ] \
  && pass "P6 CRLF and trailing whitespace keep the plan current (the documented normalisation)" || fail "P6 normalisation"

# P7 — a plan made before /issue-resolver's 0d normalized the body.
RAW=$'Login is broken on mobile, please fix'
NORMALIZED=$'<!-- idd:normalized v1 -->\n## Type\nbug\n\n## Description\nLogin is broken on mobile.\n\n## Acceptance Criteria\n- [ ] Login works on mobile (needs review)\n\n> Reporter Context\n> Login is broken on mobile, please fix\n'
python3 -c 'import json,sys; json.dump({"body": sys.argv[1]}, open(sys.argv[2], "w"))' "$RAW" "$TMP/raw.json"
python3 "$PLAN" render-plan --issue "$TMP/raw.json" < "$TMP/in.json" > "$TMP/plan-raw.md"
printf '%s' "$NORMALIZED" > "$TMP/norm.txt"
issue "$TMP/i-p7.json" "$TMP/norm.txt" "plan-approved" "me|2026-11-19T10:00:00Z|$TMP/plan-raw.md"
chk "$TMP/i-p7.json" --login me
got="$(field "$TMP/out.json" 'json.dumps([d["plan"], d["approved"], d["plan_hash"] != d["body_hash"]])')"
[ "$got" = '["stale", false, true]' ] \
  && pass "P7 test_prenormalization_hash_is_stale: a pre-normalization plan reads stale on the normalized body" \
  || fail "P7 test_prenormalization_hash_is_stale: got $got"
has "$IA/SKILL.source.md" 'A body without `<!-- idd:normalized v1 -->` (a legacy `gitissue:normalized` one counts) prints *Plan refused — issue not normalized* and posts nothing.' \
  "P7 /issue-analysis --plan refuses an un-normalized body"

# P8 — remove plan-approved, confirm it is gone, only then post.
p8_order() {  # p8_order <file> — the three steps appear in this order
  python3 - "$1" <<'PY'
import sys
text = open(sys.argv[1]).read()
start = text.index("**Posting a plan**")
section = text[start:text.index("## Claim", start)]
steps = [section.index(s) for s in (
    "`gh issue edit {N} --remove-label plan-approved`, then read `gh issue view {N} --json labels`",
    "render-plan",
    "Add `planned`",
    "if `plan-approved` is back, repeat step 1's removal and confirm",
)]
assert steps == sorted(steps), steps
assert "**post nothing**" in section[: steps[1]]
PY
}
p8_order "$DOC" && pass "P8 test_remove_confirm_post_order (doc): remove → confirm → post → planned → re-check" \
  || fail "P8 test_remove_confirm_post_order (doc): the order moved"
p8_order "$ROOT/skills/issue-resolver/references/docs/plan-and-claim.md" \
  && pass "P8 test_remove_confirm_post_order: the resolver's bundled doc keeps the order" \
  || fail "P8 the resolver's bundled doc lost the order"
has "$IA/SKILL.source.md" '`plan-approved` removed and confirmed gone first, then the comment, then `planned`' \
  "P8 test_remove_confirm_post_order (analysis): the --plan post removes and confirms first"
has "$IA/SKILL.source.md" 'A removal that cannot be confirmed prints *Plan approval label not removed* and posts nothing' \
  "P8 (analysis): an unconfirmed removal posts nothing"
has "$IA/references/error-messages.md" 'gh issue edit N --remove-label plan-approved' \
  "P8 (analysis): the error names the exact removal command"
has "$RS/references/steps/step-2-plan.md" '`plan-approved` is removed and confirmed gone before the comment is posted' \
  "P8 test_remove_confirm_post_order (resolver): the plan post removes and confirms first"
hasflat "$RS/references/steps/step-2-plan.md" 'a `plan-approved` label that could not be confirmed removed' "P8 (resolver): an unconfirmed removal takes Plan awaiting approval (fail closed)"

# P9 — racing claim markers: exactly one run reads own.
claim_md "$TMP/c-r1.md" r1 feat/648-a
claim_md "$TMP/c-r2.md" r2 feat/648-b
claim_md "$TMP/c-r0.md" r0 feat/648-old
claim_of() {  # claim_of <issue-json> <login> <run>
  chk "$1" --login "$2" --run "$3"; field "$TMP/out.json" 'd["claim"]'
}
issue "$TMP/i-p9a.json" - "agent:working" "me|2026-11-19T10:00:00Z|$TMP/c-r1.md" "me|2026-11-19T10:00:30Z|$TMP/c-r2.md"
a="$(claim_of "$TMP/i-p9a.json" me r1)"; b="$(claim_of "$TMP/i-p9a.json" me r2)"
[ "$a/$b" = own/foreign ] \
  && pass "P9 test_first_writer_wins (same login): earlier r1 own, later r2 foreign — exactly one own" \
  || fail "P9 test_first_writer_wins (same login): r1=$a r2=$b"
issue "$TMP/i-p9b.json" - "agent:working" "you|2026-11-19T10:00:00Z|$TMP/c-r2.md" "me|2026-11-19T10:00:30Z|$TMP/c-r1.md"
a="$(claim_of "$TMP/i-p9b.json" me r1)"; b="$(claim_of "$TMP/i-p9b.json" you r2)"
[ "$a/$b" = foreign/own ] \
  && pass "P9 test_first_writer_wins (cross login, racer earlier): we yield; the other login owns it" \
  || fail "P9 test_first_writer_wins (cross login, racer earlier): me=$a you=$b"
issue "$TMP/i-p9c.json" - "agent:working" "me|2026-11-19T10:00:00Z|$TMP/c-r1.md" "you|2026-11-19T10:00:30Z|$TMP/c-r2.md"
a="$(claim_of "$TMP/i-p9c.json" me r1)"; b="$(claim_of "$TMP/i-p9c.json" you r2)"
[ "$a/$b" = own/foreign ] \
  && pass "P9 test_first_writer_wins (cross login, racer later): we own it; the later login yields" \
  || fail "P9 test_first_writer_wins (cross login, racer later): me=$a you=$b"
issue "$TMP/i-p9d.json" - "agent:working" "me|2026-11-19T10:00:00Z|$TMP/c-r1.md" "me|2026-11-19T10:00:00Z|$TMP/c-r2.md"
a="$(claim_of "$TMP/i-p9d.json" me r1)"; b="$(claim_of "$TMP/i-p9d.json" me r2)"
[ "$a/$b" = own/foreign ] \
  && pass "P9 test_first_writer_wins (same timestamp): list order breaks the tie — exactly one own" \
  || fail "P9 test_first_writer_wins (same timestamp): r1=$a r2=$b"
issue "$TMP/i-p9e.json" - "agent:working" "you|2026-11-19T08:00:00Z|$TMP/c-r0.md" "me|2026-11-19T10:00:00Z|$TMP/c-r1.md"
[ "$(claim_of "$TMP/i-p9e.json" me r1)" = own ] \
  && pass "P9 an old marker beyond the race window (a released claim) does not block" || fail "P9 old marker blocked"
chk "$TMP/i-p9e.json" --login me --run r1 --race-window 9000
[ "$(field "$TMP/out.json" 'd["claim"]')" = foreign ] \
  && pass "P9 the same marker inside --race-window blocks" || fail "P9 --race-window not honoured"
issue "$TMP/i-p9f.json" - "agent:working" "you|2026-11-19T10:00:00Z|$TMP/c-r1.md" "me||$TMP/c-r1.md"
[ "$(claim_of "$TMP/i-p9f.json" me r1)" = own ] \
  && pass "P9 a racer with the same run id (another login copying it) never makes us yield" || fail "P9 same-run racer"
issue "$TMP/i-p9g.json" - "agent:working" "you||$TMP/c-r2.md" "me||$TMP/c-r1.md"
[ "$(claim_of "$TMP/i-p9g.json" me r1)" = foreign ] \
  && pass "P9 without timestamps an earlier other-run marker still makes us yield (fail closed)" || fail "P9 no-timestamp race"

# ── T3: the claim rule and the forgery guard ───────────────────────────────
echo "  ┄ claim rule"
issue "$TMP/i-c1.json" - "" "me|2026-11-19T10:00:00Z|$TMP/c-r1.md"
[ "$(claim_of "$TMP/i-c1.json" me r1)" = none ] && pass "T3.1 no label + own marker → none (a marker alone claims nothing)" || fail "T3.1"
issue "$TMP/i-c2.json" - "agent:working"
[ "$(claim_of "$TMP/i-c2.json" me r1)" = foreign ] && pass "T3.2 label + no marker → foreign" || fail "T3.2"
issue "$TMP/i-c3.json" - "agent:working" "me|2026-11-19T10:00:00Z|$TMP/c-r2.md"
[ "$(claim_of "$TMP/i-c3.json" me r1)" = foreign ] && pass "T3.3 label + own-login marker for another run → foreign" || fail "T3.3"
chk "$TMP/i-c3.json" --login me --run r1 --branch feat/648-b
[ "$(field "$TMP/out.json" 'd["claim"]')" = own ] && pass "T3.4 a bound resume (--branch) reads its own branch's claim as own" || fail "T3.4"
chk "$TMP/i-c3.json" --login me --run r1 --claim-label ""
[ "$(field "$TMP/out.json" 'd["claim"]')" = none ] && pass "T3.5 --claim-label \"\" turns the claim off (none)" || fail "T3.5"
chk "$TMP/i-c3.json" --login me --run r1 --claim-label other:label
[ "$(field "$TMP/out.json" 'd["claim"]')" = none ] && pass "T3.6 the configured claim label is the one read" || fail "T3.6"
chk "$TMP/i-c3.json" --login me --run r1
got="$(field "$TMP/out.json" 'json.dumps([d["claim_run"], d["claim_branch"], isinstance(d["claim_age_s"], int) and d["claim_age_s"] >= 0])')"
[ "$got" = '["r2", "feat/648-b", true]' ] && pass "T3.7 a foreign claim names its run, branch and age" || fail "T3.7 $got"
printf '{"issue": %s}' "$(cat "$TMP/i-c3.json")" > "$TMP/i-env.json"
[ "$(claim_of "$TMP/i-env.json" me r2)" = own ] && pass "T3.8 a gi-issue.py envelope is read like a bare issue" || fail "T3.8"
n="$(grep -c -- '<!--' "$TMP/plan.md")"
[ "$n" = 1 ] && [ "$(grep -c -- '-->' "$TMP/plan.md")" = 1 ] && head -1 "$TMP/plan.md" | grep -qE '^<!-- idd:plan v1 body=[0-9a-f]{16} -->$' \
  && pass "T3.9 rendered values cannot forge a marker: the only comment delimiter is line 1" || fail "T3.9 $n delimiters"
grep -qx '\*\*Tasks\*\*' "$TMP/plan.md" && [ "$(grep -cx '\*\*Tasks\*\*' "$TMP/plan.md")" = 1 ] \
  && pass "T3.10 a value cannot start a section (newlines are flattened)" || fail "T3.10"

# ── T7: no orphaned or blocked claim ───────────────────────────────────────
echo "  ┄ released claims, non-writers, resume, unreadable login"
python3 "$PLAN" render-release --run r0 --branch feat/648-old > "$TMP/rel-r0.md"
[ "$(head -1 "$TMP/rel-r0.md")" = '<!-- idd:claim-released v1 run=r0 branch=feat/648-old -->' ] \
  && pass "T7.1 render-release writes the release marker line first" || fail "T7.1 $(head -1 "$TMP/rel-r0.md")"
rc=0; python3 "$PLAN" render-release --run 'r;0' --branch feat/1 >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] && pass "T7.2 render-release refuses a bad run (exit 3)" || fail "T7.2 gave $rc"
# The plan-approval loop: r0 claimed, stopped and released at 10:05; r1 claims at 10:07.
issue "$TMP/i-r1.json" - "agent:working" "me|2026-11-19T10:00:00Z|$TMP/c-r0.md" \
  "me|2026-11-19T10:05:00Z|$TMP/rel-r0.md" "me|2026-11-19T10:07:00Z|$TMP/c-r1.md"
[ "$(claim_of "$TMP/i-r1.json" me r1)" = own ] \
  && pass "T7.3 test_released_marker_never_races: a claim released inside the race window does not orphan the next claim" \
  || fail "T7.3 test_released_marker_never_races: a released marker still blocks"
[ "$(claim_of "$TMP/i-r1.json" me r9)" = foreign ] && [ "$(field "$TMP/out.json" 'd["claim_run"]')" = r1 ] \
  && pass "T7.4 a later run yields to the live claim, never to the released one" || fail "T7.4 claim_run=$(field "$TMP/out.json" 'd["claim_run"]')"
issue "$TMP/i-r2.json" - "agent:working" "me|2026-11-19T10:00:00Z|$TMP/c-r0.md" \
  "mallory|2026-11-19T10:05:00Z|$TMP/rel-r0.md" "me|2026-11-19T10:07:00Z|$TMP/c-r1.md"
[ "$(claim_of "$TMP/i-r2.json" me r1)" = foreign ] \
  && pass "T7.5 a release comment by another login closes nothing" || fail "T7.5 a forged release closed our marker"
issue "$TMP/i-r3.json" - "agent:working" "me|2026-11-19T10:05:00Z|$TMP/rel-r0.md" \
  "me|2026-11-19T10:06:00Z|$TMP/c-r0.md" "me|2026-11-19T10:07:00Z|$TMP/c-r1.md"
[ "$(claim_of "$TMP/i-r3.json" me r1)" = foreign ] \
  && pass "T7.6 a release closes only the markers before it" || fail "T7.6 an earlier release closed a later marker"
# Markers by accounts that cannot add the label.
for assoc in NONE CONTRIBUTOR FIRST_TIME_CONTRIBUTOR; do
  issue "$TMP/i-a.json" - "agent:working" "mallory|2026-11-19T10:00:00Z|$TMP/c-r2.md|$assoc" "me|2026-11-19T10:00:30Z|$TMP/c-r1.md|OWNER"
  [ "$(claim_of "$TMP/i-a.json" me r1)" = own ] \
    && pass "T7.7 test_non_writer_marker_never_races: an earlier $assoc marker cannot orphan our label" \
    || fail "T7.7 test_non_writer_marker_never_races: $assoc marker blocked"
done
for assoc in OWNER MEMBER COLLABORATOR; do
  issue "$TMP/i-a.json" - "agent:working" "you|2026-11-19T10:00:00Z|$TMP/c-r2.md|$assoc" "me|2026-11-19T10:00:30Z|$TMP/c-r1.md|OWNER"
  [ "$(claim_of "$TMP/i-a.json" me r1)" = foreign ] \
    && pass "T7.8 an earlier $assoc racer still wins (first writer)" || fail "T7.8 $assoc racer ignored"
done
issue "$TMP/i-a2.json" - "agent:working" "mallory|2026-11-19T10:00:00Z|$TMP/c-r1.md|NONE"
[ "$(claim_of "$TMP/i-a2.json" me r9)" = foreign ] && [ "$(field "$TMP/out.json" 'd["claim_run"]')" = None ] \
  && pass "T7.9 a non-writer's marker is never named as the holder" || fail "T7.9"
# A bound resume after a crash between the claim comment and the label: the
# crashed attempt r1 and the resume r2 both wrote markers for feat/648-b.
claim_md "$TMP/c-r1b.md" r1 feat/648-b
issue "$TMP/i-b.json" - "agent:working" "me|2026-11-19T10:00:00Z|$TMP/c-r1b.md" "me|2026-11-19T10:01:00Z|$TMP/c-r2.md"
chk "$TMP/i-b.json" --login me --run r2 --branch feat/648-b
a="$(field "$TMP/out.json" 'd["claim"]')"
chk "$TMP/i-b.json" --login me --run r2
b="$(field "$TMP/out.json" 'd["claim"]')"
[ "$a/$b" = own/foreign ] \
  && pass "T7.10 test_bound_resume_own_marker: a bound resume's earlier marker on its branch is not a racer; a fresh run still yields" \
  || fail "T7.10 test_bound_resume_own_marker: --branch=$a, fresh=$b"
# An unreadable login (an app token): nothing is trusted, nothing is own.
issue "$TMP/i-l.json" - "agent:working,plan-approved" "me|2026-11-19T10:00:00Z|$TMP/plan.md" "me|2026-11-19T10:00:30Z|$TMP/c-r1.md"
chk "$TMP/i-l.json" --login "" --run r1
got="$RC $(field "$TMP/out.json" 'json.dumps([d["plan"], d["approved"], d["claim"]])')"
[ "$got" = '0 ["absent", false, "foreign"]' ] \
  && pass "T7.11 test_unreadable_login: --login \"\" reads the plan absent and a labelled claim foreign" \
  || fail "T7.11 test_unreadable_login: got $got"
issue "$TMP/i-l2.json" - "" "me|2026-11-19T10:00:30Z|$TMP/c-r1.md"
chk "$TMP/i-l2.json" --login "" --run r1
[ "$RC/$(field "$TMP/out.json" 'd["claim"]')" = 0/none ] \
  && pass "T7.12 test_unreadable_login: no label reads none" || fail "T7.12 rc=$RC"
hasflat "$DOC" 'For the rest of that run the claim is off as with `resolver.claim_label: ""` — never written, never released — except that a label already on the issue still stops with *Claimed elsewhere*' \
  "T7.13 an unreadable login turns the claim off but still stops on a present label"
hasflat "$DOC" 'a resolver plan step that must post a plan takes *Plan awaiting approval* instead of posting' \
  "T7.14 an unreadable login never reposts a plan"
hasflat "$RS/references/steps/step-2-plan.md" 'empty `$login` posts nothing and takes the same stop' \
  "T7.15 the resolver's plan step stops on an unreadable login"
has "$DOC" 'A non-zero exit claimed nothing: print `⚠ Claim not written — continuing unclaimed`, skip steps 4–5 (no label is added), and never release.' \
  "T7.16 a failed claim comment adds no label"
python3 - "$DOC" <<'PY' && pass "T7.17 Release posts the release comment before it removes the label" || fail "T7.17 release order"
import sys
t = open(sys.argv[1]).read()
r = t[t.index("**Release** —"):]
assert r.index("post the *Release comment*") < r.index("--remove-label")
PY
hasflat "$DOC" "post this run's *Release comment* (its marker lost, so it must not race a later claim)" \
  "T7.18 a run that lost the race closes its own marker"
grep -qF 'or wait' "$DOC" && fail "T7.19 the doc still offers waiting out a claim" || pass "T7.19 the doc no longer offers waiting as a remedy"

# ── T4: wiring pins ────────────────────────────────────────────────────────
echo "  ┄ wiring"
has "$DOC" 'Post the claim comment first — a marker without the label claims nothing' "T4.1 the claim comment is posted before the label"
has "$DOC" 'it must read `own`' "T4.2 the claim write re-reads live and must read own"
has "$DOC" 'leave the label — it belongs to the winner' "T4.3 a lost race never removes the winner's label"
has "$DOC" 'Never remove a claim that does not read `own`' "T4.4 release touches only an own claim"
has "$DOC" 'Every read is live, never the issue cache' "T4.5 claim and plan reads are live"
has "$DOC" '`foreign` → *Claimed elsewhere*' "T4.6 a foreign pre-check stops"
has "$DOC" 'nothing takes one over automatically' "T4.7 no automatic expiry"
has "$RS/references/error-messages.md" 'skipped_reason: claimed_elsewhere`. <!-- auto:no -->' "T4.8 Claimed elsewhere takes No in auto"
has "$RS/references/error-messages.md" 'skipped_reason: plan_awaiting_approval`. <!-- auto:no -->' "T4.9 Plan awaiting approval takes No in auto"
has "$RS/references/error-messages.md" 'gh issue edit N --remove-label "{claim_label}"' "T4.10 the foreign-claim stop prints the fix command"
has "$RS/SKILL.source.md" '`claimed_elsewhere`' "T4.11 the 0c guard lists claimed_elsewhere"
has "$RS/SKILL.source.md" 'run the *Claim write* in `docs/plan-and-claim.md` before *0g*' "T4.12 the claim is written after the branch, before 0g"
has "$RS/SKILL.source.md" 'Right after `gh pr create` succeeds, run the claim'"'"'s *Release*' "T4.13 the claim is released on PR open"
has "$RS/SKILL.source.md" 'An outcome without a PR first runs the claim'"'"'s *Release*' "T4.14 the claim is released at every no-PR outcome"
has "$RS/references/steps/step-0j-resume.md" '| `label_edit` (claim, release) | `gh issue view {N} --json labels` |' "T4.15 label_edit has a Reconciling row"
has "$RS/references/run-log-fields.md" '`claimed_elsewhere`, `plan_awaiting_approval`' "T4.16 run-log-fields lists both skip reasons"
has "$ROOT/docs/run-log-schema.md" '`claimed_elsewhere`, `plan_awaiting_approval`' "T4.17 run-log-schema lists both skip reasons"
hasflat "$RS/references/steps/step-2-plan.md" 'The *Criteria coverage gate* treats it as `reuse`' "T4.18 a current plan goes through the coverage gate like reuse"
python3 - "$RS/references/steps/step-2-plan.md" <<'PY' \
  && pass "T4.19 the plan post runs after the sensitive-change gate" || fail "T4.19 order"
import sys
t = open(sys.argv[1]).read()
assert t.index("### Sensitive-change gate") < t.index("### Plan comment") < t.index("### Design-confirm checkpoint")
PY
printf '%s' '{"effect": {"kind": "label_edit", "state": "intent", "key": {"label": "agent:working", "op": "remove"}}}' > "$TMP/patch.json"
REPO="$TMP/repo"; git init -q "$REPO" && git -C "$REPO" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init
git -C "$REPO" checkout -q -b feat/648-x
rc=0; (cd "$REPO" && printf '{"step": 0}' | python3 "$PROGRESS" --start --skill issue-resolver --number 648 >/dev/null 2>&1 \
  && python3 "$PROGRESS" --write --skill issue-resolver --number 648 < "$TMP/patch.json" >/dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] && pass "T4.20 gi-progress records a label_edit release intent" || fail "T4.20 rc=$rc"
has "$AP/SKILL.source.md" '**Claim label:** add `resolver.claim_label` (default `agent:working`; nothing when `""`) to the effective `skip_labels` at config load' \
  "T4.21 auto-pilot appends the claim label to skip_labels"
has "$AP/SKILL.source.md" 'An issue in *Step 1.0*'"'"'s resume set is exempt' "T4.22 the resume set is exempt from the claim skip"
hasflat "$AP/references/phases/phase-1-triage-pick.md" 'The claim label (`resolver.claim_label`) is appended at the same load' "T4.23 the pick phase reads the claim label through skip_labels"
has "$AP/references/explicit-list-mode.md" 'The claim label (`resolver.claim_label`) is kept only for an issue in' "T4.24 explicit lists keep only a resumed claim"
has "$RV/SKILL.source.md" '--fields number,title,body,labels,comments --refresh' "T4.25 pr-review's Step 1 snapshot carries comments"
has "$RV/references/verification-checks.md" 'Findings only: each is `action: note`' "T4.26 plan conformance never blocks"
has "$RV/references/verification-checks.md" 'python3 shared/scripts/gi-plan.py check --login "$login" --claim-label ""' "T4.27 pr-review reads the plan without a claim"
has "$IA/SKILL.source.md" '| `/issue-analysis <N> --plan` |' "T4.28 /issue-analysis documents --plan"
has "$ROOT/src/skills/init-idd/templates/idd-template.yml" 'claim_label: "agent:working"' "T4.29 the init template carries resolver.*"
for f in "$DOC" "$RS/references/steps/step-2-plan.md"; do
  grep -qE '#[0-9]{3}' "$f" && fail "T4.30 ${f#"$ROOT"/} cites a ticket number" || pass "T4.30 ${f#"$ROOT"/} cites no ticket number"
done

# ── T5: bundles and CI ─────────────────────────────────────────────────────
echo "  ┄ bundles and CI"
for skill in issue-resolver issue-analysis issue-pr-review; do
  cmp -s "$PLAN" "$ROOT/skills/$skill/references/scripts/gi-plan.py" \
    && pass "T5.1 $skill ships gi-plan.py byte-identical" || fail "T5.1 $skill gi-plan.py missing or differs"
  grep -qF 'references/scripts/gi-plan.py' "$ROOT/skills/$skill/SKILL.md" \
    && pass "T5.2 $skill's precheck lists gi-plan.py" || fail "T5.2 $skill precheck"
done
for skill in issue-resolver issue-analysis; do
  [ -f "$ROOT/skills/$skill/references/docs/plan-and-claim.md" ] \
    && pass "T5.3 $skill bundles plan-and-claim.md" || fail "T5.3 $skill lacks the doc"
done
[ ! -e "$ROOT/skills/auto-pilot/references/scripts/gi-plan.py" ] \
  && pass "T5.4 auto-pilot reads the label only and does not bundle gi-plan.py" || fail "T5.4 auto-pilot bundles gi-plan.py"
grep -q '^resolver:' "$ROOT/skills/auto-pilot/references/docs/config-schema.md" \
  && pass "T5.5 auto-pilot's config excerpt carries the resolver section" || fail "T5.5"
grep -qE '^      - name: test-plan-claim-648$' "$WORKFLOW" && has "$WORKFLOW" 'run: bash tests/test-plan-claim-648.sh' \
  "T5.6 dist-check runs this test as a named step" || fail "T5.6 no named step for this test"

# ── T6: the four eval cases replay end to end (subject + grade) ───────────
# The same subject-then-grade path evals/harness/run_eval.sh drives, minus its
# OS sandbox (tests/test-eval-resolver.sh runs them sandboxed in CI).
echo "  ┄ eval cases"
SHIM="$ROOT/evals/harness/gh_shim.py"
GRADE="$ROOT/evals/harness/grade.py"
PY="$(command -v python3)"
for name in plan-required replan-after-edit foreign-claim claim-release; do
  case_dir="$ROOT/evals/cases/issue-resolver/$name"
  work="$TMP/eval-$name"
  mkdir -p "$work/bin" "$work/out" "$work/state" "$work/repo" "$work/home" "$work/case" "$work/scripts"
  cp -R "$case_dir"/. "$work/case"/
  cp "$PLAN" "$work/scripts/"
  printf '#!/usr/bin/env bash\nexec "%s" "%s" "$@"\n' "$PY" "$SHIM" > "$work/bin/gh"
  printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$PY" > "$work/bin/python3"
  chmod 755 "$work/bin/gh" "$work/bin/python3"
  cp "$case_dir/cassettes.json" "$work/cassettes.json"
  if ( cd "$work/repo" && env -i HOME="$work/home" PATH="$work/bin:/usr/bin:/bin" \
         EVAL_CASSETTES="$work/cassettes.json" EVAL_STATE_DIR="$work/state" EVAL_OUT="$work/out" \
         EVAL_CASE_DIR="$work/case" EVAL_WORK="$work" EVAL_SCRIPTS_DIR="$work/scripts" \
         bash "$work/case/subject.sh" ) >"$work/subject.log" 2>&1 \
     && REPO_ROOT="$ROOT" "$PY" "$GRADE" --case "$case_dir" --out "$work/out" >"$work/grade.log" 2>&1; then
    pass "T6 eval issue-resolver/$name: subject artifacts satisfy every grade assertion"
  else
    fail "T6 eval issue-resolver/$name: subject or grade failed"
    sed -n '1,15p' "$work/subject.log" "$work/grade.log" 2>/dev/null | sed 's/^/      /'
  fi
  grep -qx "run_case \"$name\"" "$ROOT/tests/test-eval-resolver.sh" \
    && pass "T6 test-eval-resolver.sh runs $name sandboxed" || fail "T6 test-eval-resolver.sh misses $name"
done

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || { echo "  ✗ Plan and claim tests failed"; exit 1; }
echo "  ✓ Plan and claim tests passed"
