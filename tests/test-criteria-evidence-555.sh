#!/usr/bin/env bash
# test-criteria-evidence-555.sh — criterion evidence is independent and
# reproducible (issue #555).
#
# /issue-pr-review no longer judges acceptance criteria itself: it has read the
# PR body, which carries the author's own criteria table. An isolated criteria
# judge sees the issue and the diff only, and gi-criteria.py keeps a `pass`
# only when a named test exited 0 at head or a command's observed output is
# recorded at head — anything else is downgraded to `unverified`.
#
#   T1  gi-criteria.py downgrades a pass without a test or command (behavioural);
#   T2  it keeps re-runnable passes, fail/unverified rows and deferred rows;
#   T3  agent output never stops it and never yields a pass; orchestrator
#       mistakes are exit 3;
#   T4  the judge is given the issue and the diff only (prose pins);
#   T5  the built bundles carry the judge and the script, pr-review only;
#   T6  the CI step exists.
#
# Usage: bash tests/test-criteria-evidence-555.sh
# Returns: exit 0 if all checks pass, exit 1 on failure
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CRIT="$ROOT/src/shared/scripts/gi-criteria.py"
JUDGE="$ROOT/src/shared/agents/criteria-judge.md"
RV="$ROOT/src/skills/issue-pr-review"
VC="$RV/references/verification-checks.md"
WORKFLOW="$ROOT/.github/workflows/dist-check.yml"

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
has() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3 (missing in ${1#"$ROOT"/})"; }
lacks() { grep -qF -- "$2" "$1" && fail "$3 (found in ${1#"$ROOT"/})" || pass "$3"; }
js() { python3 -c "import json,sys; d=json.load(sys.stdin); print(($1))"; }

echo "Criterion evidence tests (issue #555)"

HEAD_SHA="$(printf 'a%.0s' $(seq 40))"
OLD_SHA="$(printf 'b%.0s' $(seq 40))"

# judge <verdicts-json> [criteria-json] [deferred-json] — runs the script on
# one record, prints stdout, sets $ec.
judge() {
  local criteria="${2:-[\"one\"]}" deferred="${3:-[]}"
  set +e
  out="$(printf '%s' "{\"head\":\"$HEAD_SHA\",\"criteria\":$criteria,\"deferred\":$deferred,\"verdicts\":$1}" \
    | python3 "$CRIT" 2>/dev/null)"
  ec=$?
  set -e
}
# row1 <evidence-json> [status] — one-criterion verdict; sets $st to row 1's status.
row1() {
  judge "{\"criteria\":[{\"n\":1,\"status\":\"${2:-pass}\",\"evidence\":$1}]}"
  st="$(printf '%s' "$out" | js 'd["rows"][0]["status"]')"
}

# ── T1: a pass without a test or a command is downgraded ─────────────────
row1 '{"kind":"note","text":"the diff adds the check"}'; [ "$st" = unverified ] \
  && [ "$(printf '%s' "$out" | js 'd["rows"][0]["downgraded"], d["downgraded"], d["counts"]["pass"]')" = "(True, 1, 0)" ] \
  && pass "T1.1 a pass resting on a description is downgraded to unverified" \
  || fail "T1.1 description-only pass: $out"
row1 '"src/auth.ts:10-20"'; [ "$st" = unverified ] \
  && pass "T1.2 a pass resting on a file path is downgraded" || fail "T1.2 file-path pass: $out"
row1 'null'; [ "$st" = unverified ] \
  && pass "T1.3 a pass with no evidence is downgraded" || fail "T1.3 no-evidence pass: $out"
row1 "{\"kind\":\"test\",\"name\":\"rejects empty\",\"exit\":1,\"sha\":\"$HEAD_SHA\"}"; [ "$st" = unverified ] \
  && pass "T1.4 a test that did not exit 0 is not a pass" || fail "T1.4 red test: $out"
row1 "{\"kind\":\"test\",\"name\":\"\",\"exit\":0,\"sha\":\"$HEAD_SHA\"}"; [ "$st" = unverified ] \
  && pass "T1.5 a test with no name is not a pass" || fail "T1.5 nameless test: $out"
row1 "{\"kind\":\"test\",\"name\":\"rejects empty\",\"exit\":0,\"sha\":\"$OLD_SHA\"}"; [ "$st" = unverified ] \
  && printf '%s' "$out" | grep -q 'not head' \
  && pass "T1.6 a test green at another SHA is stale, not a pass" || fail "T1.6 stale SHA: $out"
row1 "{\"kind\":\"test\",\"name\":\"rejects empty\",\"exit\":0}"; [ "$st" = unverified ] \
  && pass "T1.7 a test with no SHA is not a pass" || fail "T1.7 missing SHA: $out"
row1 "{\"kind\":\"command\",\"command\":\"grep -n x f\",\"output\":\"  \",\"sha\":\"$HEAD_SHA\"}"; [ "$st" = unverified ] \
  && pass "T1.8 a command with no observed output is not a pass" || fail "T1.8 empty output: $out"
row1 "{\"kind\":\"command\",\"output\":\"f:1: x\",\"sha\":\"$HEAD_SHA\"}"; [ "$st" = unverified ] \
  && pass "T1.9 output with no command is not a pass" || fail "T1.9 no command: $out"
row1 "{\"kind\":\"test\",\"name\":\"t\",\"exit\":true,\"sha\":\"$HEAD_SHA\"}"; [ "$st" = unverified ] \
  && pass "T1.10 a boolean exit is not exit 0" || fail "T1.10 boolean exit: $out"

# ── T2: re-runnable passes and other statuses stand ──────────────────────
row1 "{\"kind\":\"test\",\"name\":\"rejects empty\",\"command\":\"npm test\",\"exit\":0,\"sha\":\"$HEAD_SHA\"}"; [ "$st" = pass ] \
  && [ "$(printf '%s' "$out" | js 'd["rows"][0]["evidence"]')" = 'test `rejects empty` green @ aaaaaaa' ] \
  && pass "T2.1 a named test green at head stays pass, rendered with its SHA" || fail "T2.1 green test: $out"
row1 "{\"kind\":\"command\",\"command\":\"grep -n x f\",\"output\":\"f:1: x\\nmore\",\"sha\":\"$HEAD_SHA\"}"; [ "$st" = pass ] \
  && [ "$(printf '%s' "$out" | js 'd["rows"][0]["evidence"]')" = '`grep -n x f` → f:1: x' ] \
  && pass "T2.2 a command with its observed output at head stays pass" || fail "T2.2 command: $out"
row1 '{"kind":"note","text":"still hard-codes /login"}' fail; [ "$st" = fail ] \
  && [ "$(printf '%s' "$out" | js 'd["rows"][0]["evidence"]')" = 'still hard-codes /login' ] \
  && pass "T2.3 a fail keeps its status and evidence" || fail "T2.3 fail: $out"
row1 '{"kind":"note","text":"needs a device"}' unverified; [ "$st" = unverified ] \
  && [ "$(printf '%s' "$out" | js 'd["downgraded"]')" = 0 ] \
  && pass "T2.4 an unverified row is not counted as a downgrade" || fail "T2.4 unverified: $out"
judge "{\"criteria\":[{\"n\":1,\"status\":\"pass\",\"evidence\":{\"kind\":\"test\",\"name\":\"t\",\"exit\":0,\"sha\":\"$HEAD_SHA\"}},{\"n\":2,\"status\":\"pass\",\"evidence\":{\"kind\":\"note\",\"text\":\"done\"}}]}" '["one","two","three"]' '[2]'
[ "$(printf '%s' "$out" | js '[r["status"] for r in d["rows"]], d["counts"]')" = "(['pass', 'deferred', 'unverified'], {'pass': 1, 'fail': 0, 'unverified': 1, 'deferred': 1})" ] \
  && pass "T2.5 a deferred row is reported deferred whatever the judge said, and counted apart" \
  || fail "T2.5 deferred: $out"

row1 "{\"kind\":\"test\",\"name\":\"rejects empty\",\"exit\":1,\"sha\":\"$HEAD_SHA\"}" fail; [ "$st" = fail ] \
  && [ "$(printf '%s' "$out" | js 'd["rows"][0]["evidence"]')" = 'test `rejects empty` exit 1 @ aaaaaaa' ] \
  && pass "T2.6 a fail row backed by a red test renders its exit code, never green" || fail "T2.6 red test row: $out"
row1 "{\"kind\":\"test\",\"name\":\"rejects empty\",\"sha\":\"$HEAD_SHA\"}" unverified; [ "$st" = unverified ] \
  && [ "$(printf '%s' "$out" | js 'd["rows"][0]["evidence"]')" = 'test `rejects empty` exit ? @ aaaaaaa' ] \
  && pass "T2.7 a test row with no integer exit renders exit ?, never green" || fail "T2.7 no exit: $out"
has "$VC" 'a body whose line 1 is `Refs #{N}`' "T2.8 deferral needs only a Refs #N line 1 — check 1 alone judges the form"

# ── T3: agent output never stops it; orchestrator mistakes do ────────────
judge '"I could not decide"' '["one","two"]'
[ "$ec" = 0 ] && [ "$(printf '%s' "$out" | js 'd["counts"]')" = "{'pass': 0, 'fail': 0, 'unverified': 2, 'deferred': 0}" ] \
  && pass "T3.1 unreadable judge output makes every criterion unverified, exit 0" || fail "T3.1 ec=$ec $out"
judge "[{\"n\":1,\"status\":\"pass\",\"evidence\":{\"kind\":\"test\",\"name\":\"t\",\"exit\":0,\"sha\":\"$HEAD_SHA\"}},{\"n\":1,\"status\":\"fail\"}]" '["one","two"]'
[ "$(printf '%s' "$out" | js '[r["status"] for r in d["rows"]], len(d["problems"])')" = "(['unverified', 'unverified'], 2)" ] \
  && pass "T3.2 a duplicated row and a missing row are unverified, each named" || fail "T3.2 $out"
row1 '{"kind":"note","text":"x"}' passed; [ "$st" = unverified ] \
  && pass "T3.3 an unknown status is unverified" || fail "T3.3 $out"
judge '[{"n":7,"status":"pass"},{"status":"pass"},"x"]'
[ "$ec" = 0 ] && [ "$(printf '%s' "$out" | js 'd["rows"][0]["status"], len(d["problems"])')" = "('unverified', 4)" ] \
  && pass "T3.4 rows with no valid criterion number are ignored and reported" || fail "T3.4 $out"
# T3.8 (#584): a lone surrogate (a JSON "\ud800" escape) in judge output used to
# crash the output encode with exit 1. The row is unreadable, so unverified.
row1 "{\"kind\":\"test\",\"name\":\"rejects empty\",\"exit\":0,\"sha\":\"$HEAD_SHA\",\"note\":\"\\ud800\"}"
[ "$ec" = 0 ] && [ "$st" = unverified ] \
  && pass "T3.8 a pass row carrying a lone surrogate exits 0 and is unverified" || fail "T3.8 ec=$ec st=$st $out"
judge "[{\"n\":1,\"status\":\"fail\",\"evidence\":\"x \\ud800\"}]" '["one \ud800"]'
[ "$ec" = 0 ] && [ "$(printf '%s' "$out" | js 'd["rows"][0]["status"]')" = fail ] \
  && pass "T3.9 a fail row carrying a lone surrogate stays fail and prints, exit 0" || fail "T3.9 ec=$ec $out"
bad() {
  set +e
  printf '%s' "$1" | python3 "$CRIT" >/dev/null 2>&1
  local code=$?
  set -e
  [ "$code" = 3 ] && pass "T3.5 exit 3: $2" || fail "T3.5 $2 (exit $code)"
}
bad "{\"head\":\"abc\",\"criteria\":[],\"deferred\":[],\"verdicts\":[]}" "a head that is not 40 hex"
bad "{\"head\":\"$HEAD_SHA\",\"criteria\":[],\"verdicts\":[]}" "a missing deferred key"
bad "{\"head\":\"$HEAD_SHA\",\"criteria\":[],\"deferred\":[],\"verdicts\":[],\"verdict\":1}" "an unknown key"
bad "{\"head\":\"$HEAD_SHA\",\"criteria\":[\"a\"],\"deferred\":[2],\"verdicts\":[]}" "a deferred number out of range"
bad "{\"head\":\"$HEAD_SHA\",\"criteria\":[1],\"deferred\":[],\"verdicts\":[]}" "criteria that are not strings"
bad "not json" "stdin that is not JSON"
python3 "$CRIT" --help >/dev/null && pass "T3.6 --help exits 0" || fail "T3.6 --help"
[ "$(git -C "$ROOT" ls-files -s src/shared/scripts/gi-criteria.py | cut -c1-6)" = 100755 ] \
  && pass "T3.7 committed mode is 0755" || fail "T3.7 gi-criteria.py is not committed 0755"

# ── T4: the judge sees the issue and the diff only ───────────────────────
lacks "$JUDGE" '{pr_context}' "T4.1 the judge prompt has no PR-context input"
has "$JUDGE" 'Do not read the PR title, body, comments or reviews' "T4.2 the judge is told never to read the PR"
has "$JUDGE" 'apart from the diff command in step 1, run no `gh` command' "T4.3 the judge runs no gh read but the diff"
has "$JUDGE" '"sha": "{head_sha}"' "T4.4 the judge records the SHA its evidence ran at"
has "$VC" 'a:rvc-criteria-judge' "T4.5 the judge spawn has one anchored home"
has "$VC" 'Nothing from the PR title, body or comments reaches it' "T4.6 the spawn binds nothing from the PR body"
has "$VC" '**Never judge them yourself:**' "T4.7 the orchestrator, which read the PR body, never judges"
has "$VC" 'after a push moves it, whoever pushed, spawn a fresh judge' "T4.8 a verdict holds for one head"
has "$VC" 'when the judged head is not `verified_head`' "T4.8b the floor never reads verdicts for another head"
has "$VC" '`run_tests` = `review.run_tests` and `test_timeout` = `review.test_timeout`' "T4.8c the judge honours review.run_tests and its timeout"
has "$VC" 'a row matching none defers nothing' "T4.8d a deferral is matched by criterion text, never by position"
has "$JUDGE" 'never the whole suite' "T4.8e the judge runs one covering test, not the suite"
has "$JUDGE" 'With neither, it is `unverified`, and an unattended merge waits for a human' "T4.8f a bug with no runnable check stays unverified"
has "$VC" 'never change a status it returns' "T4.9 the script's verdict is final"
lacks "$VC" 'one-line description' "T4.10 a one-line description no longer counts as pass evidence"
lacks "$VC" 'MUST cite the Decision Record' "T4.11 a bug pass no longer reads the PR body's Reproduction line"
has "$VC" 'the Decision Record **Reproduction** line is traceability check 3' "T4.12 the Reproduction line stays a traceability check"
has "$RV/SKILL.source.md" '**never the PR title, body or comments**' "T4.13 SKILL.md Step 3 isolates the judge"
spawn="$(grep -F '1. **Judge in isolation.**' "$VC")"
case "$spawn" in
  *pr_context*|*'PR body'*) fail "T4.14 the judge spawn line binds PR context" ;;
  *issue_context*diff_command*head_sha*) pass "T4.14 the judge spawn binds the issue, the diff and the head" ;;
  *) fail "T4.14 the judge spawn line lost a binding" ;;
esac

# ── T5: built bundles ────────────────────────────────────────────────────
B="$ROOT/skills/issue-pr-review"
cmp -s "$CRIT" "$B/references/scripts/gi-criteria.py" \
  && pass "T5.1 pr-review bundles gi-criteria.py byte-identical" || fail "T5.1 bundled gi-criteria.py missing or stale"
[ -f "$B/references/agents/criteria-judge.md" ] && [ -f "$ROOT/.pi/agents/criteria-judge.md" ] \
  && pass "T5.2 the judge is emitted into pr-review and .pi/agents" || fail "T5.2 the judge is not emitted"
for s in issue-resolver auto-pilot; do
  [ ! -e "$ROOT/skills/$s/references/agents/criteria-judge.md" ] \
    && pass "T5.3 $s does not carry the judge" || fail "T5.3 $s carries the judge"
done
grep -qF "and to run the repository's own tests" "$ROOT/.pi/agents/criteria-judge.md" \
  && ! grep -qF "and to run the repository's own tests" "$ROOT/.pi/agents/code-reviewer.md" \
  && pass "T5.5 only the judge's pi preamble allows running tests" || fail "T5.5 pi test-runner preamble"
grep -qF 'references/scripts/gi-criteria.py' "$B/SKILL.md" \
  && pass "T5.4 the built SKILL.md precheck names the script" || fail "T5.4 precheck lacks the script"

# ── T6: CI ───────────────────────────────────────────────────────────────
has "$WORKFLOW" 'run: bash tests/test-criteria-evidence-555.sh' "T6.1 dist-check runs this test"

echo ""
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
if [ "$FAIL" -ne 0 ]; then
  echo "  ✗ Criterion evidence tests failed"
  exit 1
fi
echo "  ✓ Criterion evidence tests passed"
