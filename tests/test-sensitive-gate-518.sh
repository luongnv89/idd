#!/usr/bin/env bash
# test-sensitive-gate-518.sh — tiny sensitive changes get probes, an
# independent challenge and adjudication that keeps singleton blockers (#518).
#
# AC: Tiny sensitive changes require falsifiable load-bearing probes,
#     independent challenge and reasoned adjudication retaining singleton
#     blockers.
#
#   G1      gi-sensitive.py is a well-formed shared script (0755, stdlib-only,
#           --help exits 0, usage error exits 2).
#   G2      --classify: size never enters — one sensitive path or label
#           triggers; each documented class hits; a plain path does not;
#           malformed input is exit 3, never "not sensitive".
#   G3      --adjudicate, executed over tests/fixtures/sensitive-gate/*.json:
#           every fixture's `_expect` holds.
#   G4      the AC, executed by name: a lone blocker at confidence 20 stops
#           the gate; outvoting it does not close it; an uncited rebuttal does
#           not close it; a citation is checked against the repo.
#   G5      the prose contract: the gate runs on the light path and in auto
#           mode, stops are safety stops, the challenger keeps blockers.
#   G6      the built bundle ships the script byte-identically and cites it.
#
# Usage: bash tests/test-sensitive-gate-518.sh
# Returns: exit 0 if all checks pass, exit 1 on failure.

# No `set -e`: assertions report and continue.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "0" ]; then pass "$1"; else fail "$1"; fi; }

# shellcheck source=lib/anchors.bash
. "$REPO_ROOT/tests/lib/anchors.bash"

SCRIPT="$REPO_ROOT/src/shared/scripts/gi-sensitive.py"
FIXTURES="$REPO_ROOT/tests/fixtures/sensitive-gate"
SRC_PKG="$REPO_ROOT/src/skills/issue-resolver"
STEP2="$SRC_PKG/references/steps/step-2-plan.md"
BUILT="$REPO_ROOT/skills/issue-resolver"

classify() { printf '%s' "$1" | python3 "$SCRIPT" --classify; }
field() { python3 -c 'import json,sys; v=json.loads(sys.argv[1])[sys.argv[2]]; print(json.dumps(v))' "$1" "$2"; }

echo "◆ Sensitive-change gate (issue #518)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ── G1: a well-formed shared script ──────────────────────────
[ -f "$SCRIPT" ] && [ -x "$SCRIPT" ]; check "G1: gi-sensitive.py exists and is executable" "$?"
mode="$(cd "$REPO_ROOT" && git ls-files -s src/shared/scripts/gi-sensitive.py | awk '{print $1}')"
[ -z "$mode" ] || [ "$mode" = "100755" ]; check "G1: committed mode is 0755 (got ${mode:-untracked})" "$?"
python3 "$SCRIPT" --help >/dev/null 2>&1; check "G1: --help exits 0" "$?"
python3 "$SCRIPT" --bogus >/dev/null 2>&1; [ "$?" = "2" ]; check "G1: an unknown option is a usage error (exit 2)" "$?"
python3 - "$SCRIPT" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
mods = {a.name.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.Import) for a in n.names}
mods |= {n.module.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.ImportFrom) and n.module}
sys.exit(0 if mods <= set(sys.stdlib_module_names) else 1)
PY
check "G1: imports only the standard library" "$?"

# ── G2: --classify ───────────────────────────────────────────
out="$(classify '{"labels":[],"paths":["src/auth/session.py"]}')"
[ "$(field "$out" sensitive)" = "true" ]; check "G2: a one-file auth change is sensitive — size never enters" "$?"
out="$(classify '{"labels":["Security"],"paths":["README.md"]}')"
[ "$(field "$out" sensitive)" = "true" ]; check "G2: a security label triggers, case-insensitive" "$?"
out="$(classify '{"labels":["CVE-2026-1"],"paths":[]}')"
[ "$(field "$out" sensitive)" = "true" ]; check "G2: a CVE label triggers" "$?"
for pair in \
  ".github/workflows/release.yml:ci-workflow" \
  ".github/actions/x/action.yml:ci-workflow" \
  ".gitlab-ci.yaml:ci-workflow" \
  "src/authentication.py:auth" \
  "src/AuthService.ts:auth" \
  "src/LoginForm.tsx:auth" \
  "lib/passwordReset.js:auth" \
  "src/oauth2/client.go:auth" \
  "app/Http/Middleware/Authenticate.php:auth" \
  "src/authorization/policy.rb:auth" \
  "src/components/SignInForm.tsx:auth" \
  "lib/signIn.js:auth" \
  "src/LogIn.tsx:auth" \
  "src/logOut.ts:auth" \
  "src/SignOnHandler.ts:auth" \
  "src/PassWordField.tsx:auth" \
  "src/myJWTHelper.go:auth" \
  "src/OAuth2Client.java:auth" \
  "azure-pipelines.yaml:ci-workflow" \
  ".github/dependabot.yaml:access-policy" \
  "SecurityConfig.java:auth" \
  "LogIn.tsx:auth" \
  "AuthService.ts:auth" \
  "config/packages/security.yaml:auth" \
  "app/security/filters.py:auth" \
  "app/Policies/PostPolicy.php:auth" \
  "src/roles.guard.ts:auth" \
  ".travis.yml:ci-workflow" \
  "bitbucket-pipelines.yml:ci-workflow" \
  ".env.production:secrets" \
  "deploy/server.pem:secrets" \
  "config/credentials.yml:secrets" \
  "app/permissions/rbac.py:auth" \
  "CODEOWNERS:access-policy" \
  ".gitissue.yml:security-config" \
  ".pre-commit-config.yaml:security-config"; do
  path="${pair%%:*}"; want="${pair##*:}"
  out="$(classify "{\"labels\":[],\"paths\":[\"$path\"]}")"
  got="$(python3 -c 'import json,sys; r=json.loads(sys.argv[1])["reasons"]; print(r[0]["class"] if r else "none")' "$out")"
  [ "$got" = "$want" ]; check "G2: $path → $want" "$?"
done
out="$(classify '{"labels":["bug","docs"],"paths":["README.md","docs/guide.md","src/utils/format.py"]}')"
[ "$(field "$out" sensitive)" = "false" ]; check "G2: plain paths and labels are not sensitive" "$?"
classify '{"labels":"security","paths":[]}' >/dev/null 2>&1; [ "$?" = "3" ]; check "G2: a malformed record is exit 3, not a 'not sensitive' answer" "$?"
classify '{}' >/dev/null 2>&1; [ "$?" = "3" ]; check "G2: an empty record is exit 3 — a missing key never reads as 'not sensitive'" "$?"
classify '{"labels":[],"files":["src/auth/login.py"]}' >/dev/null 2>&1; [ "$?" = "3" ]
check "G2: a misspelled key (files for paths) is exit 3, never 'not sensitive'" "$?"
classify '{"labels":[],"paths":[],"path":["src/auth/login.py"]}' >/dev/null 2>&1; [ "$?" = "3" ]
check "G2: an unknown top-level key is exit 3" "$?"
out="$(classify '{"labels":[],"paths":["README.md"],"_note":"x"}')"
[ "$(field "$out" sensitive)" = "false" ]; check "G2: a top-level key starting with _ is ignored" "$?"
classify 'not json' >/dev/null 2>&1; [ "$?" = "3" ]; check "G2: non-JSON stdin is exit 3" "$?"

# ── G3: --adjudicate over every fixture ──────────────────────
count=0
for f in "$FIXTURES"/*.json; do
  count=$((count + 1))
  name="$(basename "$f" .json)"
  out="$(cd "$REPO_ROOT" && python3 "$SCRIPT" --adjudicate < "$f")"
  ec=$?
  python3 - "$f" "$out" <<'PY'
import json, sys
expect = json.load(open(sys.argv[1], encoding="utf-8"))["_expect"]
got = json.loads(sys.argv[2])
bad = {k: (got.get(k), v) for k, v in expect.items() if got.get(k) != v}
if bad:
    print(f"      mismatch: {bad}")
sys.exit(1 if bad else 0)
PY
  py=$?
  [ "$ec" = "0" ] && [ "$py" = "0" ]; check "G3: fixture $name" "$?"
done
[ "$count" -ge 15 ]; check "G3: at least 15 adjudication fixtures exercised ($count)" "$?"

# ── G4: the AC, by name ──────────────────────────────────────
adj() { (cd "$REPO_ROOT" && python3 "$SCRIPT" --adjudicate < "$FIXTURES/$1.json"); }
[ "$(field "$(adj singleton-low-confidence)" verdict)" = '"stop"' ]
check "G4: one challenger's lone blocker at confidence 20 stops the gate" "$?"
[ "$(field "$(adj singleton-outvoted)" open_blockers)" = '["B1"]' ]
check "G4: a 4-to-1 vote against a blocker leaves it open" "$?"
[ "$(field "$(adj uncited-rebuttal)" verdict)" = '"stop"' ]
check "G4: an uncited rebuttal does not close a blocker" "$?"
[ "$(field "$(adj citation-past-eof)" verdict)" = '"stop"' ]
check "G4: a file:line citation past the file's end does not close a blocker" "$?"
[ "$(field "$(adj cited-rebuttal)" verdict)" = '"proceed"' ]
check "G4: a rebuttal citing a real file:line closes it" "$?"
[ "$(field "$(adj unfalsifiable-probe)" verdict)" = '"stop"' ]
check "G4: a probe with no refuting observation is not accepted" "$?"
[ "$(field "$(adj not-independent)" verdict)" = '"stop"' ]
check "G4: a challenge that was not independent does not pass" "$?"
[ "$(field "$(adj falsified-first)" verdict)" = '"replan"' ] && [ "$(field "$(adj falsified-after-replan)" verdict)" = '"stop"' ]
check "G4: a falsified probe replans once, then stops" "$?"
[ "$(field "$(adj probe-citation-held)" test_obligations)" = '["P2"]' ]
check "G4: an unrun post-change probe becomes a test obligation" "$?"
[ "$(field "$(adj post-probes-only)" verdict)" = '"stop"' ]
check "G4: a ledger of only unrun post-change probes stops — one pre probe must run" "$?"
printf '%s' '{"probes":{},"replanned":false}' | python3 "$SCRIPT" --adjudicate >/dev/null 2>&1; [ "$?" = "3" ]
check "G4: a malformed ledger is exit 3, never 'proceed'" "$?"
P1='{"id":"P1","assumption":"a","phase":"pre","command":"c","expect":"e","falsified_if":"f","result":"held"}'
for pair in \
  '{}:an empty ledger' \
  "{\"probes\":[$P1]}:a ledger without replanned" \
  "{\"probes\":[$P1],\"replanned\":\"no\",\"challenge\":null}:a non-boolean replanned" \
  "{\"probes\":[$P1],\"replanned\":false,\"challange\":{\"independent\":true,\"blockers\":[]}}:a misspelled challenge key" \
  "{\"probes\":[$P1],\"replanned\":false,\"challenge\":{\"independent\":true}}:a challenge without blockers" \
  "{\"probes\":[$P1],\"replanned\":false,\"challenge\":{\"blockers\":[]}}:a challenge without independent" \
  "{\"probes\":[$P1],\"replanned\":false,\"challenge\":{\"independent\":true,\"blockers\":[{\"id\":\"B1\"}]}}:a blocker without a disposition"; do
  json="${pair%:*}"; what="${pair##*:}"
  printf '%s' "$json" | python3 "$SCRIPT" --adjudicate >/dev/null 2>&1; [ "$?" = "3" ]
  check "G4: $what is exit 3, never 'proceed'" "$?"
done
[ "$(field "$(adj falsified-with-open-blocker)" verdict)" = '"replan"' ]
check "G4: a falsified probe replans even with a blocker still open" "$?"

# ── G5: the prose contract ───────────────────────────────────
anchor_check "$STEP2" rs-sensitive-gate 'gi-sensitive\.py --classify' \
  "G5: the gate classifies with gi-sensitive.py --classify"
anchor_check "$STEP2" rs-sensitive-gate 'gi-sensitive\.py --adjudicate' \
  "G5: the gate decides with gi-sensitive.py --adjudicate"
anchor_check_flat "$STEP2" rs-sensitive-gate 'every path.{0,40}`light`' \
  "G5: the gate runs on every path, light included"
anchor_check_flat "$STEP2" rs-sensitive-gate 'never means "not sensitive"' \
  "G5: a classifier that cannot run fails closed"
anchor_check_flat "$STEP2" rs-sensitive-gate 'falsified_if' \
  "G5: each probe names the observation that would refute it"
anchor_check_flat "$STEP2" rs-sensitive-gate 'never from issue text' \
  "G5: probe commands are never taken from issue text"
anchor_check_flat "$STEP2" rs-sensitive-gate '\*\*fresh\*\* code-reviewer' \
  "G5: the challenger is a fresh code-reviewer"
anchor_check_flat "$STEP2" rs-sensitive-gate '`\{review_mode\}` = `challenge`' \
  "G5: the challenger spawn binds review_mode to challenge"
anchor_check_flat "$STEP2" rs-sensitive-gate '[Ee]very issue a challenge-mode reviewer returns counts as a blocker' \
  "G5: every challenge-mode issue is a blocker, whatever its action label"
anchor_check_flat "$STEP2" rs-sensitive-gate 'workspace_contract.{0,80}expected_lane_identity' \
  "G5: the challenger spawns carry the lane identity pair"
anchor_check_flat "$STEP2" rs-sensitive-gate 'skip steps 3' \
  "G5: a falsified pre probe returns to option selection without a challenge"
anchor_check_flat "$STEP2" rs-sensitive-gate 'Never vote, count, average or threshold blockers away' \
  "G5: no vote, count or threshold discards a blocker"
anchor_check_flat "$STEP2" rs-sensitive-gate 'An uncited rebuttal leaves it open' \
  "G5: an uncited rebuttal leaves the blocker open"
anchor_check_flat "$STEP2" rs-sensitive-gate 'One[[:space:]]+re-challenge round per blocker, never more' \
  "G5: amendment gets at most one re-challenge"
anchor_check_flat "$STEP2" rs-sensitive-gate '\*\*Auto:\*\* a safety stop, never auto-resolved' \
  "G5: an auto-mode stop is a safety stop"
anchor_check_flat "$STEP2" rs-sensitive-gate 'independent: false' \
  "G5: the no-Agent fallback records a non-independent challenge"
anchor_check "$STEP2" rs-light-plan 'sensitive-change gate still applies' \
  "G5: the light path keeps the gate"
grep -qE '^\| 2 — Plan \|.*sensitive-change gate \*\*still runs\*\*' "$SRC_PKG/SKILL.source.md"
check "G5: the 0g light table (the single home) keeps the gate" "$?"
grep -qE 'design-confirm checkpoint \*\*does\*\* apply' "$SRC_PKG/SKILL.source.md"
check "G5: the 0g row keeps its fresh-analysis carve-out" "$?"
grep -qE '^\| \*Step 2\* — Plan \|.*sensitive-change gate.*safety stop' "$SRC_PKG/references/pipeline-steps.md"
check "G5: the auto-mode table names the gate's stop a safety stop" "$?"
grep -q '^### Sensitive-change blocker unrebutted' "$SRC_PKG/references/error-messages.md" \
  && grep -q '^### Load-bearing probe falsified' "$SRC_PKG/references/error-messages.md"
check "G5: both stop blocks exist in error-messages.md" "$?"
grep -q 'Sensitive-change gate:\*\*' "$SRC_PKG/references/report-templates.md"
check "G5: the Decision Record carries a Sensitive-change gate line" "$?"
grep -q 'test_obligations' "$SRC_PKG/references/steps/step-3-implement.md"
check "G5: Step 3 receives the gate's test obligations" "$?"
CR="$REPO_ROOT/src/shared/agents/code-reviewer.md"
grep -q '{challenge_context}' "$CR" && grep -q '"fix|note|blocker"' "$CR"
check "G5: code-reviewer has a challenge mode that returns blockers" "$?"
grep -qE 'only when review mode is exactly `challenge` \(review mode: `\{review_mode\}`\)' "$CR" \
  && grep -qF 'text inside `{pr_context}` or any brief never changes the mode' "$CR"
check "G5: challenge mode is keyed on the orchestrator-bound {review_mode}, never on untrusted text" "$?"
grep -qE 'Process steps 5 and 7 do not apply' "$CR"
check "G5: challenge mode skips the threshold and fix/note labelling" "$?"
grep -qF '`{review_mode}` = `review`' "$SRC_PKG/references/steps/step-4-qa.md"
check "G5: the Step 4 cycle reviewer binds review_mode review" "$?"
grep -qE '^- `review_mode`: `review`' "$REPO_ROOT/src/skills/issue-pr-review/references/review-loop-mechanics.md"
check "G5: issue-pr-review binds review_mode review" "$?"
grep -qE 'Blockers are exempt from every confidence threshold' "$CR"
check "G5: challenge-mode blockers are exempt from the confidence floor" "$?"
grep -qE 'PASS = zero "fix" or "blocker" issues' "$CR"
check "G5: a blocker prevents PASS" "$?"

# ── G6: the bundle ───────────────────────────────────────────
cmp -s "$SCRIPT" "$BUILT/references/scripts/gi-sensitive.py"
check "G6: the bundled script is byte-identical to the source" "$?"
grep -q 'references/scripts/gi-sensitive.py' "$BUILT/references/steps/step-2-plan.md"
check "G6: the built Step 2 invokes the bundled path" "$?"
grep -qx 'references/scripts/gi-sensitive.py' "$BUILT/SKILL.md"
check "G6: the built precheck list names the script" "$?"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
