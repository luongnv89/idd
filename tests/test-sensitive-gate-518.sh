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
#   G7      one risk tier from the actual diff (#569): `tier` tracks
#           `sensitive`; an Effort key is refused, never read (AC2); a `diff`
#           range is classified from git in a temp repo (renames list both
#           sides, non-ASCII paths are not quoted), a bad range is exit 3, a
#           git failure or a shadowed (ambiguous) base ref exit 4, and `diff.relative` cannot hide a path;
#           the base must be a remote-tracking ref and the head HEAD or a commit
#           id (#605), so a branch named origin/<base> in a single-branch clone,
#           a branch-name head, an empty diff or a head inside the base is exit
#           4, git runs under LC_ALL=C, and a gitlink is listed whatever
#           the submodule ignore settings; the
#           resolver's Deliver (any delivered sensitive path Step 2 did not
#           mark) and pr-review's Depth gate and Merge floor read it (AC1, AC3).
#   G8      verification-config (#661): test-runner, lint, type-check and
#           coverage config is reported as its own class, checked last; a PR
#           that lowers a coverage threshold is reported, never an empty
#           answer. A release tripwire reads CHANGELOG.md: while the entry sits
#           under [Unreleased] the class must be report-only (`observed`, tier
#           unchanged); while its section is the newest release either state
#           passes, so an ordinary PR can make the switch; once a newer release
#           heading sits above it the class must be in `reasons`. An enforced
#           class always needs the changelog to record the switch. A missing
#           entry fails.
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
  "config/initializers/devise.rb:auth" \
  "config/passport.js:auth" \
  "app/models/ability.rb:auth" \
  "config/initializers/omniauth.rb:auth" \
  ".envrc:secrets" \
  ".env.production:secrets" \
  "deploy/server.pem:secrets" \
  "config/credentials.yml:secrets" \
  "app/permissions/rbac.py:auth" \
  "CODEOWNERS:access-policy" \
  ".idd.yml:security-config" \
  ".pre-commit-config.yaml:security-config" \
  "package.json:dependency-manifest" \
  "services/api/requirements-dev.txt:dependency-manifest" \
  "go.sum:dependency-manifest" \
  "Cargo.lock:dependency-manifest" \
  "app.gemspec:dependency-manifest" \
  "web/pnpm-lock.yaml:dependency-manifest" \
  "Dockerfile:infrastructure" \
  "docker/Dockerfile.prod:infrastructure" \
  "docker-compose.override.yml:infrastructure" \
  "modules/vpc/main.tf:infrastructure" \
  "infra/main.go:infrastructure" \
  "deploy/k8s/app.yaml:infrastructure" \
  "charts/web/Chart.yaml:infrastructure" \
  "db/migrations/0001_init.sql:migration" \
  "db/migrate/20260101_add_index.rb:migration" \
  "alembic/versions/abc.py:migration"; do
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

# ── G7: one risk tier from the actual diff (#569) ────────────
tier_of() { python3 -c 'import json,sys; r=json.loads(sys.argv[1]); print(r["tier"] if r["sensitive"] == (r["tier"] == "sensitive") else "mismatch")' "$1"; }
[ "$(tier_of "$(classify '{"labels":[],"paths":["src/auth/session.py"]}')")" = "sensitive" ] \
  && [ "$(tier_of "$(classify '{"labels":["bug"],"paths":["README.md"]}')")" = "standard" ]
check "G7: tier is sensitive exactly when sensitive is true, else standard" "$?"
classify '{"labels":[],"paths":["src/auth/session.py"],"effort":"XS"}' >/dev/null 2>&1; [ "$?" = "3" ]
check "G7: an effort key is exit 3 — Effort is never an input (AC2)" "$?"
[ "$(tier_of "$(classify '{"labels":[],"paths":["src/auth/session.py"],"_effort":"XS"}')")" = "sensitive" ]
check "G7: a stated XS Effort leaves the tier of the same labels and paths unchanged (AC2)" "$?"

GITREPO="$(mktemp -d)"
AMBREPO="$(mktemp -d)"
R3REPO="$(mktemp -d)"
STUBDIR="$(mktemp -d)"
trap 'rm -rf "$GITREPO" "$AMBREPO" "$R3REPO" "$STUBDIR"' EXIT
g() { git -C "$GITREPO" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
dclassify() { (cd "$GITREPO" && printf '%s' "{\"labels\":[],\"paths\":[],\"diff\":\"$1\"}" | python3 "$SCRIPT" --classify); }
# The callers pass origin/<base>...HEAD or ...<head sha> (#605): point the
# remote-tracking ref at the base branch now, and name the head by its commit id.
rng() { g update-ref "refs/remotes/origin/$1" "$1" && printf 'origin/%s...%s' "$1" "$(g rev-parse "$2")"; }
g init -q -b main && mkdir -p "$GITREPO/.github/workflows" "$GITREPO/docs" \
  && echo 'on: push' > "$GITREPO/.github/workflows/ci.yml" && echo '# guide' > "$GITREPO/docs/guide.md" \
  && echo '{}' > "$GITREPO/package.json" && g add -A && g commit -q -m base
check "G7: temp git repo for the diff cases" "$?"
g checkout -q -b rename main && g mv .github/workflows/ci.yml docs/ci.yml && g commit -q -m mv
out="$(dclassify "$(rng main rename)")"
[ "$(field "$out" tier)" = '"sensitive"' ]
check "G7: renaming .github/workflows/ci.yml to docs/ci.yml is sensitive — both sides are listed" "$?"
g checkout -q -b unicode main && echo 'on: push' > "$GITREPO/.github/workflows/déploy.yml" && g add -A && g commit -q -m u
out="$(dclassify "$(rng main unicode)")"
python3 -c 'import json,sys; r=json.loads(sys.argv[1]); sys.exit(0 if r["tier"] == "sensitive" and r["reasons"][0]["class"] == "ci-workflow" and r["reasons"][0]["source"] == "diff" else 1)' "$out"
check "G7: a non-ASCII file under .github/workflows/ is sensitive (ci-workflow), never a quoted miss" "$?"
g checkout -q -b deps main && echo '{"dependencies":{}}' > "$GITREPO/package.json" && g commit -q -am d
out="$(dclassify "$(rng main deps)")"
python3 -c 'import json,sys; r=json.loads(sys.argv[1]); sys.exit(0 if r["tier"] == "sensitive" and r["reasons"][0]["class"] == "dependency-manifest" else 1)' "$out"
check "G7: a dependency manifest change is sensitive" "$?"
g checkout -q -b plain main && echo 'more' >> "$GITREPO/docs/guide.md" && g commit -q -am p
out="$(dclassify "$(rng main plain)")"; ec=$?
[ "$ec" = "0" ] && [ "$(field "$out" tier)" = '"standard"' ]; check "G7: a plain docs change at a 40-hex head is standard (exit 0)" "$?"
dclassify 'origin/main...plain' >/dev/null 2>&1; [ "$?" = "4" ]
check "G7: a head named by a branch, never HEAD or a commit id, is exit 4 (#605)" "$?"
dclassify 'main...HEAD' >/dev/null 2>&1; [ "$?" = "4" ]
check "G7: a base that is a local branch, not a remote-tracking ref, is exit 4 (#605)" "$?"
dclassify "$(rng main main)" >/dev/null 2>&1; [ "$?" = "4" ]
check "G7: an empty diff (head = base) is exit 4, never tier standard (#605)" "$?"
g checkout -q -b empty main && g commit -q --allow-empty -m e
dclassify "$(rng main empty)" >/dev/null 2>&1; [ "$?" = "4" ]
check "G7: a head with commits but no changed path is exit 4 (#605)" "$?"
# A PR into `rel` whose head carries default-branch commits `rel` lacks: the
# manifest change drops out of main...feat yet still lands in rel, so the range
# must use the PR's own base, never the default branch.
g branch rel main && g checkout -q main && echo '{"dependencies":{"x":"1"}}' > "$GITREPO/package.json" \
  && g commit -q -am dep && g checkout -q -b feat && echo 'feat' >> "$GITREPO/docs/guide.md" && g commit -q -am f
[ "$(field "$(dclassify "$(rng rel feat)")" tier)" = '"sensitive"' ] && [ "$(field "$(dclassify "$(rng main feat)")" tier)" = '"standard"' ]
check "G7: a PR into rel classifies origin/rel...feat (sensitive), not origin/main...feat (standard) — the PR's base is the range" "$?"
dclassify "$(rng main rel)" >/dev/null 2>&1; [ "$?" = "4" ]
check "G7: a head already contained in the base (rel inside main) is exit 4 (#605)" "$?"
for bad in '-p...main' 'main..plain' 'main...plain...x' 'main....plain' 'main...' 'main...pl;ain' 'main~1...plain' 'origin/main...HEAD\n'; do
  dclassify "$bad" >/dev/null 2>&1; [ "$?" = "3" ]; check "G7: the range '$bad' is exit 3" "$?"
done
dclassify 'origin/no-such-ref...HEAD' >/dev/null 2>&1; [ "$?" = "4" ]
check "G7: an unknown base ref is exit 4 (cannot complete), never 'not sensitive'" "$?"
dclassify "origin/main...$(printf 'de%.0s' $(seq 20))" >/dev/null 2>&1; [ "$?" = "4" ]
check "G7: an unknown 40-hex head is exit 4 (cannot complete), never 'not sensitive'" "$?"
g config diff.relative true
urng="$(rng main unicode)"
out="$(cd "$GITREPO/docs" && printf '%s' "{\"labels\":[],\"paths\":[],\"diff\":\"$urng\"}" | python3 "$SCRIPT" --classify)"
[ "$(field "$out" tier)" = '"sensitive"' ]
check "G7: diff.relative=true and a subdirectory cwd still list a .github/workflows change (sensitive)" "$?"
# R4 (#605): a gitlink the PR adds under .github/actions/ must be listed even
# when the head's own .gitmodules says `ignore = all` or diff.ignoreSubmodules=all.
g checkout -q -b submod main && printf '[submodule "evil"]\n\tpath = .github/actions/evil\n\turl = https://example.invalid/evil.git\n\tignore = all\n' > "$GITREPO/.gitmodules" \
  && echo n > "$GITREPO/notes.txt" && g update-index --add --cacheinfo "160000,$(g rev-parse main),.github/actions/evil" \
  && g add .gitmodules notes.txt && g commit -q -m sub
check "G7: a branch adding a gitlink at .github/actions/evil with .gitmodules ignore = all" "$?"
out="$(dclassify "$(rng main submod)")"; ec=$?
[ "$ec" = "0" ] && python3 -c 'import json,sys; r=json.loads(sys.argv[1]); sys.exit(0 if r["tier"] == "sensitive" and {"source": "diff", "value": ".github/actions/evil", "class": "ci-workflow"} in r["reasons"] else 1)' "$out"
check "G7: a gitlink added under .github/actions/ with .gitmodules ignore = all is sensitive (exit 0, #605)" "$?"
g config diff.ignoreSubmodules all
out="$(dclassify "$(rng main submod)")"; ec=$?
[ "$ec" = "0" ] && [ "$(field "$out" tier)" = '"sensitive"' ]
check "G7: diff.ignoreSubmodules=all still lists the gitlink (sensitive, exit 0, #605)" "$?"
g config --unset diff.ignoreSubmodules
# `gh pr checkout` names the local branch after the PR's head branch, so a fork
# head called `origin/main` creates refs/heads/origin/main, which shadows the
# remote-tracking ref: origin/main...HEAD would diff the PR against itself.
a() { git -C "$AMBREPO" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
aclassify() { (cd "$AMBREPO" && printf '%s' '{"labels":[],"paths":[],"diff":"origin/main...HEAD"}' | python3 "$SCRIPT" --classify); }
git clone -q -b main "$GITREPO" "$AMBREPO" && a checkout -q -b pr && echo 'on: push' > "$AMBREPO/.github/workflows/pr.yml" \
  && a add -A && a commit -q -m pr
check "G7: temp clone with a local origin for the ref-shadowing case" "$?"
amb_err="$(a -c core.warnAmbiguousRefs=true diff --name-only origin/main...HEAD 2>&1 >/dev/null)"
out="$(aclassify)"; ec=$?
[ "$ec" = "0" ] && [ "$(field "$out" tier)" = '"sensitive"' ] && ! printf '%s' "$amb_err" | grep -q ambiguous
check "G7: an unambiguous origin/main...HEAD classifies normally (sensitive, exit 0, no ambiguity warning)" "$?"
a checkout -q -b origin/main
out="$(aclassify 2>/dev/null)"; ec=$?
[ "$ec" = "4" ] && ! { [ "$ec" = "0" ] && [ "$(field "$out" tier)" = '"standard"' ]; }
check "G7: a local branch named origin/main shadowing the base is exit 4, never tier standard with exit 0" "$?"
# R3 (#605): a single-branch clone fetching a non-default base writes only
# FETCH_HEAD, so a fork head branch named origin/rel is the only match — no
# ambiguity warning — and origin/rel...HEAD would diff the PR against itself.
r() { git -C "$R3REPO" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
git clone -q --single-branch -b main "$GITREPO" "$R3REPO" && r fetch -q origin -- rel \
  && ! r rev-parse --verify -q refs/remotes/origin/rel >/dev/null && r checkout -q -b origin/rel FETCH_HEAD \
  && mkdir -p "$R3REPO/.github/workflows" && echo 'on: push' > "$R3REPO/.github/workflows/x.yml" && r add -A && r commit -q -m x
check "G7: single-branch clone where only FETCH_HEAD holds rel and a local branch origin/rel is checked out" "$?"
r3_err="$(LC_ALL=C r -c core.warnAmbiguousRefs=true diff --name-only origin/rel...HEAD 2>&1 >/dev/null)"
out="$(cd "$R3REPO" && printf '%s' '{"labels":[],"paths":[],"diff":"origin/rel...HEAD"}' | python3 "$SCRIPT" --classify 2>/dev/null)"; ec=$?
[ "$ec" = "4" ] && ! { [ "$ec" = "0" ] && [ "$(field "$out" tier)" = '"standard"' ]; } && ! printf '%s' "$r3_err" | grep -q ambiguous
check "G7: an unambiguous local branch origin/rel standing in for a missing base is exit 4, never tier standard (#605)" "$?"
# N3 (#605): every git call runs under LC_ALL=C, so the `ambiguous` check
# reads git's English stderr whatever the caller's locale.
printf '#!/bin/sh\necho "$LC_ALL" >> "%s/log"\nexit 1\n' "$STUBDIR" > "$STUBDIR/git" && chmod +x "$STUBDIR/git"
(cd "$GITREPO" && printf '%s' '{"labels":[],"paths":[],"diff":"origin/main...HEAD"}' \
  | PATH="$STUBDIR:$PATH" LC_ALL=fr_FR.UTF-8 LANGUAGE=fr python3 "$SCRIPT" --classify >/dev/null 2>&1); ec=$?
[ "$ec" = "4" ] && [ -s "$STUBDIR/log" ] && ! grep -qvx C "$STUBDIR/log"
check "G7: git runs with LC_ALL=C whatever the caller's locale (#605)" "$?"

DELIVER="$SRC_PKG/references/steps/step-5-deliver.md"
PR_SRC="$REPO_ROOT/src/skills/issue-pr-review/SKILL.source.md"
PR_RVM="$REPO_ROOT/src/skills/issue-pr-review/references/review-loop-mechanics.md"
anchor_check "$DELIVER" rs-deliver-tier 'gi-sensitive\.py --classify' \
  "G7: the resolver's Deliver classifies the delivered diff (AC1)"
anchor_check "$DELIVER" rs-deliver-tier '"diff": "origin/\$\{base\}\.\.\.HEAD"' \
  "G7: the Deliver record carries the diff range"
anchor_check_flat "$DELIVER" rs-deliver-tier 'is `tier: sensitive` \(fail closed\)' \
  "G7: a Deliver classify that cannot run is sensitive"
anchor_check_flat "$DELIVER" rs-deliver-tier 'Any non-zero exit, unparsable output, or no `python3` is `tier: sensitive`' \
  "G7: any Deliver classify failure, exit 2 and unparsable output included, is sensitive"
anchor_check_flat "$DELIVER" rs-deliver-tier '`reasons` name any path Step 2.s classify did not mark sensitive' \
  "G7: Deliver gates a delivered sensitive path Step 2 did not plan, even when Step 2 was sensitive"
anchor_check_flat "$DELIVER" rs-deliver-tier 'or the classify could not run' \
  "G7: a Deliver classify that cannot run triggers the gate whatever Step 2 found"
grep -q 'Deliver-time risk tier' "$SRC_PKG/SKILL.source.md"
check "G7: resolver SKILL.md Step 5 points at the Deliver-time risk tier" "$?"
anchor_check "$PR_SRC" rv-depth-gate-refresh 'gi-sensitive\.py --classify' \
  "G7: pr-review's Depth gate classifies the PR diff (AC1)"
grep -E 'gi-sensitive\.py --classify' "$PR_SRC" | grep -F -e 'origin/${base_ref}...HEAD' | grep -qE '^4\. .*review\.adaptive_depth` is `false`.*skip step 5'
check "G7: the Depth gate classify runs in step 4, outside the adaptive_depth-skippable step 5 (AC2)" "$?"
grep -E '^4\. ' "$PR_SRC" | grep -qF 'base_ref="$(gh pr view {N} --json baseRefName --jq .baseRefName)"' \
  && ! grep -E 'gi-sensitive\.py --classify' "$PR_SRC" | grep -qF 'origin/${base}...'
check "G7: pr-review classifies against the PR's own baseRefName, never the default branch (AC3)" "$?"
! grep -E '^5\. ' "$PR_SRC" | grep -qE 'gi-sensitive|CVE'
check "G7: step 5 weighs no label list and runs no classify of its own" "$?"
floor="$(grep -F 'a:rv-merge-floor' "$PR_SRC")"
printf '%s' "$floor" | grep -qF 'gi-sensitive.py --classify' \
  && printf '%s' "$floor" | grep -qF 'origin/${base_ref}...${verified_head}' \
  && printf '%s' "$floor" | grep -qF '`sensitive` is `sensitive change ({classes})`' \
  && printf '%s' "$floor" | grep -qF '`risk tier unknown`'
check "G7: the Merge floor is unmet on a sensitive or unknown tier of the verified head (AC3)" "$?"
anchor_check "$PR_RVM" rvm-depth-gate '\*\*Risk tier\*\*' "G7: the review-loop Depth gate weighs the risk tier"
anchor_lacks "$PR_RVM" rvm-depth-gate 'CVE' "G7: the review-loop Depth gate re-lists no label words"
anchor_lacks "$STEP2" rs-sensitive-gate 'classifying by hand' "G7: no hand classification fallback in Step 2"
anchor_lacks "$STEP2" rs-sensitive-gate 'pundit' "G7: Step 2 re-lists no class names"
anchor_check_flat "$STEP2" rs-sensitive-gate '`tier: sensitive` also revises the profile to `full`' \
  "G7: a sensitive tier revises the resolver profile to full"

# ── G8: verification-config, report-only for one release (#661) ──
VC=verification-config
CHANGELOG="$REPO_ROOT/CHANGELOG.md"
# The two changelog phrases the tripwire anchors on. Rewording either entry
# without updating these fails the test: it never passes on a missing phrase.
VC_OBSERVE_PHRASE='the report-only `verification-config` class'
VC_SWITCH_PHRASE='`verification-config` now makes the merge floor unmet'
# hit_class JSON → the class of the first hit in `reasons` or `observed`.
hit_class() { python3 -c 'import json,sys; r=json.loads(sys.argv[1]); h=r["reasons"]+r["observed"]; print(h[0]["class"] if h else "none")' "$1"; }
for pair in \
  "pytest.ini:$VC" \
  "tests/conftest.py:$VC" \
  "tox.ini:$VC" \
  "jest.config.js:$VC" \
  "web/vitest.config.ts:$VC" \
  "e2e/playwright.config.ts:$VC" \
  ".eslintrc:$VC" \
  ".eslintrc.json:$VC" \
  "eslint.config.mjs:$VC" \
  "ruff.toml:$VC" \
  ".ruff.toml:$VC" \
  ".flake8:$VC" \
  "mypy.ini:$VC" \
  "tsconfig.json:$VC" \
  "packages/web/tsconfig.build.json:$VC" \
  "TSConfig.json:$VC" \
  ".coveragerc:$VC" \
  "codecov.yml:$VC" \
  ".codecov.yml:$VC" \
  ".nycrc:$VC" \
  ".nycrc.json:$VC" \
  "src/auth/tsconfig.json:auth" \
  "infra/pytest.ini:infrastructure" \
  "pyproject.toml:dependency-manifest" \
  ".github/workflows/codecov.yml:ci-workflow" \
  "docs/pytest.ini.md:none" \
  "src/tsconfig.ts:none" \
  "tsconfig.yaml:none" \
  "eslint.config:none" \
  "jest.setup.js:none" \
  "docs/coverage.md:none"; do
  path="${pair%%:*}"; want="${pair##*:}"
  got="$(hit_class "$(classify "{\"labels\":[],\"paths\":[\"$path\"]}")")"
  [ "$got" = "$want" ]; check "G8: $path → $want" "$?"
done
[ "$(field "$(classify '{"labels":["bug"],"paths":["README.md"]}')" observed)" = '[]' ]
check "G8: observed is present and empty when nothing is report-only" "$?"

# changelog_mode FILE → the mode the changelog requires: `observe` while the
# entry's section is [Unreleased], `either` while it is the newest release (the
# window in which a PR makes the switch), `enforce` once a newer release heading
# sits above that section, `missing` (exit 1) when the entry is absent or sits
# under no such heading.
changelog_mode() {
  python3 - "$1" "$VC_OBSERVE_PHRASE" <<'PY'
import re, sys
release = re.compile(r"^## v([0-9]+\.[0-9]+\.[0-9]+)\b")
releases_above = 0   # release sections that ended before the current one
section = None       # "unreleased" | "release" | None
with open(sys.argv[1], encoding="utf-8") as fh:
    for line in fh:
        if line.startswith("## "):
            if section == "release":
                releases_above += 1
            if release.match(line):
                section = "release"
            elif line.startswith("## [Unreleased]"):
                section = "unreleased"
            else:
                section = None
        elif sys.argv[2] in line:
            if section is None:
                break
            if section == "unreleased":
                print("observe")
            else:
                print("enforce" if releases_above else "either")
            sys.exit(0)
print("missing")
sys.exit(1)
PY
}
# tripwire FILE STATE → 0 when the changelog allows the script state (`observe`
# or `enforce`), and the changelog records the switch for an enforced class.
tripwire() {
  local mode
  mode="$(changelog_mode "$1")" || return 1
  case "$2" in observe|enforce) ;; *) return 1 ;; esac
  [ "$mode" = either ] || [ "$mode" = "$2" ] || return 1
  [ "$2" = observe ] || grep -qF -- "$VC_SWITCH_PHRASE" "$1"
}
# The script's own state, read from the constant that holds it.
vc_state="$(python3 - "$SCRIPT" "$VC" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gi_sensitive", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print("observe" if sys.argv[2] in mod.OBSERVE_ONLY else "enforce")
PY
)"

# Both directions of the tripwire, on fixtures: no tag, clock or network.
CLDIR="$(mktemp -d)"
trap 'rm -rf "$GITREPO" "$AMBREPO" "$R3REPO" "$STUBDIR" "$CLDIR"' EXIT
entry="- **scripts:** adds $VC_OBSERVE_PHRASE (#661)."
switch="- **scripts:** $VC_SWITCH_PHRASE (#661)."
printf '# Changelog\n\n## [Unreleased]\n\n### Refactoring\n%s\n\n## v9.1.0 — 2030-01-01\n\n- older\n' "$entry" > "$CLDIR/unreleased.md"
printf '# Changelog\n\n## [Unreleased]\n\n## v9.1.0 — 2030-01-01\n\n### Refactoring\n%s\n\n## v9.0.0 — 2029-01-01\n\n- older\n' "$entry" > "$CLDIR/newest.md"
printf '# Changelog\n\n## [Unreleased]\n\n## v9.2.0 — 2030-02-01\n\n- other\n\n## v9.1.0 — 2030-01-01\n\n### Refactoring\n%s\n' "$entry" > "$CLDIR/passed.md"
printf '# Changelog\n\n## [Unreleased]\n\n## v9.2.0 — 2030-02-01\n\n%s\n\n## v9.1.0 — 2030-01-01\n\n### Refactoring\n%s\n' "$switch" "$entry" > "$CLDIR/switched.md"
printf '# Changelog\n\n## [Unreleased]\n\n%s\n\n## v9.1.0 — 2030-01-01\n\n### Refactoring\n%s\n\n## v9.0.0 — 2029-01-01\n\n- older\n' "$switch" "$entry" > "$CLDIR/newest-switched.md"
printf '# Changelog\n\n## [Unreleased]\n\n%s\n%s\n\n## v9.1.0 — 2030-01-01\n\n- older\n' "$entry" "$switch" > "$CLDIR/unreleased-switched.md"
printf '# Changelog\n\n## [Unreleased]\n\n- other\n\n## v9.1.0 — 2030-01-01\n\n- older\n' > "$CLDIR/absent.md"
printf '# Changelog\n\n%s\n\n## [Unreleased]\n\n## v9.1.0 — 2030-01-01\n' "$entry" > "$CLDIR/unplaced.md"
[ "$(changelog_mode "$CLDIR/unreleased.md")" = observe ]; check "G8: an entry under [Unreleased] requires report-only" "$?"
[ "$(changelog_mode "$CLDIR/newest.md")" = either ] && [ "$(changelog_mode "$CLDIR/newest-switched.md")" = either ]
check "G8: an entry under the newest release heading allows either state" "$?"
[ "$(changelog_mode "$CLDIR/passed.md")" = enforce ]; check "G8: a newer release heading above the entry's section requires enforcing" "$?"
out="$(changelog_mode "$CLDIR/absent.md")"; ec=$?
[ "$ec" = "1" ] && [ "$out" = missing ]; check "G8: a changelog without the entry is 'missing' (exit 1), never a mode" "$?"
out="$(changelog_mode "$CLDIR/unplaced.md")"; ec=$?
[ "$ec" = "1" ] && [ "$out" = missing ]; check "G8: an entry above every release section is 'missing' (exit 1)" "$?"
tripwire "$CLDIR/unreleased.md" observe
check "G8: tripwire passes a report-only class whose entry is under [Unreleased]" "$?"
! tripwire "$CLDIR/unreleased.md" enforce && ! tripwire "$CLDIR/unreleased-switched.md" enforce
check "G8: tripwire fails a class enforced while its entry is under [Unreleased], switch recorded or not" "$?"
tripwire "$CLDIR/newest.md" observe && tripwire "$CLDIR/newest-switched.md" observe
check "G8: tripwire passes a report-only class whose entry is under the newest release" "$?"
tripwire "$CLDIR/newest-switched.md" enforce
check "G8: tripwire passes a class enforced under the newest release with the switch recorded" "$?"
! tripwire "$CLDIR/newest.md" enforce
check "G8: tripwire fails a class enforced under the newest release without the switch recorded" "$?"
! tripwire "$CLDIR/passed.md" observe && ! tripwire "$CLDIR/switched.md" observe
check "G8: tripwire fails a class still report-only after a newer release" "$?"
! tripwire "$CLDIR/passed.md" enforce
check "G8: tripwire fails an enforced class whose switch the changelog does not record" "$?"
tripwire "$CLDIR/switched.md" enforce
check "G8: tripwire passes an enforced class with the switch recorded" "$?"
! tripwire "$CLDIR/absent.md" observe && ! tripwire "$CLDIR/absent.md" enforce \
  && ! tripwire "$CLDIR/unplaced.md" observe && ! tripwire "$CLDIR/unplaced.md" enforce
check "G8: tripwire fails in either state when the entry is missing or unplaced" "$?"
! tripwire "$CLDIR/newest-switched.md" other
check "G8: tripwire fails a state that is neither observe nor enforce" "$?"

# The real changelog decides which states this checkout may be in; the script's
# own state decides where a hit must land.
vc_mode="$(changelog_mode "$CHANGELOG")"; ec=$?
[ "$ec" = "0" ]; check "G8: CHANGELOG.md carries the entry '$VC_OBSERVE_PHRASE' under [Unreleased] or a release (got ${vc_mode:-nothing})" "$?"
tripwire "$CHANGELOG" "$vc_state"
check "G8: release tripwire — CHANGELOG.md requires '$vc_mode', OBSERVE_ONLY is in '$vc_state' (to switch, once the entry is under a release: drop $VC from OBSERVE_ONLY and add a changelog line holding '$VC_SWITCH_PHRASE')" "$?"
if [ "$vc_state" = enforce ]; then vc_key=reasons; vc_tier=sensitive; else vc_key=observed; vc_tier=standard; fi
# vc_reported JSON SOURCE PATH → 0 when that hit sits in the list the script
# state requires and nowhere else, with the tier that state requires.
vc_reported() {
  python3 -c '
import json, sys
r = json.loads(sys.argv[1]); key, tier = sys.argv[4], sys.argv[5]
hit = {"source": sys.argv[2], "value": sys.argv[3], "class": "verification-config"}
other = "reasons" if key == "observed" else "observed"
ok = (hit in r[key] and hit not in r[other] and r["tier"] == tier
      and r["sensitive"] == (tier == "sensitive"))
sys.exit(0 if ok else 1)' "$1" "$2" "$3" "$vc_key" "$vc_tier"
}
out="$(classify '{"labels":[],"paths":["tox.ini"]}')"
vc_reported "$out" path tox.ini
check "G8: a planned tox.ini edit is reported in '$vc_key' with tier $vc_tier — the state the tripwire checks against CHANGELOG.md (AC1, AC2)" "$?"
out="$(classify '{"labels":[],"paths":["src/auth/login.py",".eslintrc.json"]}')"
python3 -c 'import json,sys; r=json.loads(sys.argv[1]); sys.exit(0 if r["tier"] == "sensitive" and r["reasons"][0]["class"] == "auth" and len(r["reasons"]) + len(r["observed"]) == 2 else 1)' "$out"
check "G8: an auth path beside a lint config stays sensitive, and both paths are reported" "$?"

# AC4, the negative case: a PR that lowers a coverage threshold is reported.
g checkout -q -b covbase main && printf '[report]\nfail_under = 40\n' > "$GITREPO/.coveragerc" && g add .coveragerc && g commit -q -m cov \
  && g checkout -q -b covlow && printf '[report]\nfail_under = 10\n' > "$GITREPO/.coveragerc" && g commit -q -am lower
check "G8: a branch lowering fail_under in .coveragerc from 40 to 10" "$?"
out="$(dclassify "$(rng covbase covlow)")"; ec=$?
[ "$ec" = "0" ] && vc_reported "$out" diff .coveragerc
check "G8: a PR that lowers a coverage threshold is reported as verification-config in '$vc_key' (exit 0), never an empty answer (AC4)" "$?"
g checkout -q -b covdocs covbase && echo 'more' >> "$GITREPO/docs/guide.md" && g commit -q -am docs
out="$(dclassify "$(rng covbase covdocs)")"
[ "$(field "$out" observed)" = '[]' ] && [ "$(field "$out" reasons)" = '[]' ]
check "G8: a PR that leaves the threshold file alone reports no verification-config change" "$?"

# The enforcing path, exercised with the constant emptied: the class joins
# `reasons` and the tier follows, through the same code a release switch uses.
python3 - "$SCRIPT" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gi_sensitive", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
record = {"labels": [], "paths": [".coveragerc", "README.md"]}
hit = {"source": "path", "value": ".coveragerc", "class": "verification-config"}
mod.OBSERVE_ONLY = frozenset({"verification-config"})
watching = mod.classify(record)
mod.OBSERVE_ONLY = frozenset()
enforcing = mod.classify(record)
ok = (watching == {"sensitive": False, "tier": "standard", "reasons": [], "observed": [hit]}
      and enforcing == {"sensitive": True, "tier": "sensitive", "reasons": [hit], "observed": []})
sys.exit(0 if ok else 1)
PY
check "G8: with the class out of OBSERVE_ONLY the same hit is in reasons and the tier is sensitive; inside it, observed and standard (AC2, AC3)" "$?"

# The Evidence row is where the review prints an observed class.
for tpl in "$REPO_ROOT/src/skills/issue-pr-review/references/report-templates.md" "$REPO_ROOT/skills/issue-pr-review/references/report-templates.md"; do
  where="${tpl#"$REPO_ROOT"/}"; where="${where%%/issue-pr-review/*}"
  tr '\n' ' ' < "$tpl" | tr -s ' ' | grep -qF 'Each class in the *Merge floor* classify'"'"'s `observed` list prints as `{class} change ({paths})` and never changes the floor; an empty list prints nothing.'
  check "G8: the Evidence contract prints each observed class, nothing for an empty list, and leaves the floor alone ($where)" "$?"
  [ "$(grep -cE '^  Evidence: .*; \{class\} change \(\{paths\}\)$' "$tpl")" = "1" ] \
    && [ "$(grep -c '^  Evidence: ' "$tpl")" -gt 1 ]
  check "G8: one Evidence example shows the observed-class segment and another shows the row without it ($where)" "$?"
done

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
[ "$(field "$(adj post-probe-held-at-plan)" verdict)" = '"stop"' ] && [ "$(field "$(adj post-probe-held-at-plan)" open_blockers)" = '["B1"]' ]
check "G4: a post probe 'held' at plan time is no evidence — citing it leaves the blocker open" "$?"
[ "$(field "$(adj post-probe-falsified-at-plan)" verdict)" = '"stop"' ] && [ "$(field "$(adj post-probe-falsified-at-plan)" falsified)" = '[]' ]
check "G4: a post probe 'falsified' at plan time is a malformed record — stop, never replan" "$?"
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
PR_BUILT="$REPO_ROOT/skills/issue-pr-review"
cmp -s "$SCRIPT" "$PR_BUILT/references/scripts/gi-sensitive.py"
check "G6: issue-pr-review ships the script byte-identically" "$?"
grep -qx 'references/scripts/gi-sensitive.py' "$PR_BUILT/SKILL.md"
check "G6: issue-pr-review's precheck list names the script" "$?"
grep -q 'python3 references/scripts/gi-sensitive.py --classify' "$PR_BUILT/SKILL.md"
check "G6: the built pr-review Depth gate invokes the bundled path" "$?"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
