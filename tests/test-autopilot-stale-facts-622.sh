#!/usr/bin/env bash
# test-autopilot-stale-facts-622.sh — auto-pilot's runtime text states facts
# that are true of the bundle it ships in (issue #622).
#
#   T1  the resolver and batch-resolver prompts cap QA at the class ceiling,
#       not a fixed 3 cycles.
#   T2  run-log.md calls runs.jsonl machine-local and gitignored, not committed.
#   T3  the quarantine-label note names review.merge_method as the other config
#       string on a command line, and gi-config.py really restricts it to
#       squash/merge/rebase.
#   T4  orchestration.md lists every lane phase gi-state.py's LANE_TRANSITIONS
#       defines, parsed from the script so the list cannot drift again.
#   T5  explicit-list mode points at a section that exists and its plan block
#       shows Merge mode, like the default plan block.
#   T6  phase-5 cites gi-ci-wait.py by its bare source token.
#   T7  SKILL.md's description does not promise an unbounded, prompt-free run.
#   T8  the built skill carries the changes, and the CI step exists.
#
# Usage: bash tests/test-autopilot-stale-facts-622.sh
# Returns: exit 0 if all checks pass, exit 1 on failure
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AP="$ROOT/src/skills/auto-pilot"
DIST="$ROOT/skills/auto-pilot"
GI_STATE="$ROOT/src/shared/scripts/gi-state.py"
GI_CONFIG="$ROOT/src/shared/scripts/gi-config.py"
WORKFLOW="$ROOT/.github/workflows/dist-check.yml"

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
has() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3 (missing in ${1#"$ROOT"/})"; }
lacks() { grep -qF -- "$2" "$1" && fail "$3 (found in ${1#"$ROOT"/})" || pass "$3"; }

echo "◆ Auto-pilot stale pointers and facts (#622)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ── T1 — QA cycles follow the class ceiling ─────────────────────────────────
for p in resolver batch-resolver; do
  f="$AP/references/prompts/$p.md"
  lacks "$f" 'up to 3 review-fix cycles' "T1: $p.md no longer fixes QA at 3 review-fix cycles"
  lacks "$f" 'fix — up to 3 cycles' "T1: $p.md no longer fixes the QA loop at 3 cycles"
  has "$f" 'up to the class ceiling the `ceiling` field below names' "T1: $p.md points at its ceiling field"
  has "$f" '- ceiling: the class QA-cycle policy ceiling' "T1: $p.md defines the ceiling field it points at"
done

# ── T2 — runs.jsonl lifetime ────────────────────────────────────────────────
RL="$AP/references/run-log.md"
lacks "$RL" 'committed history of what ran' "T2.1: run-log.md no longer calls runs.jsonl committed"
has "$RL" '| Lifetime | machine-local, gitignored history of what ran, kept across runs |' "T2.2: run-log.md calls runs.jsonl machine-local and gitignored"
grep -qxF '.idd/runs.jsonl' "$ROOT/.gitignore" \
  && pass "T2.3: .gitignore really ignores the run log" \
  || fail "T2.3: .gitignore does not ignore .idd/runs.jsonl"

# ── T3 — the quarantine label's command-line claim ──────────────────────────
P2="$AP/references/phases/phase-2-resolve.md"
lacks "$P2" 'it is the only config **string** in the distribution' "T3.1: the old 'only config string' claim is gone"
has "$P2" 'only free-form config **string** in the' "T3.2: the label is the only free-form config string"
has "$P2" 'shape-checks the other free-form values, `triage.route.label_prefix` and each' "T3.2b: the route label prefix is named as gi-config-checked"
has "$P2" '`triage.route.questions` id; every other substituted config value is an integer.' "T3.2c: the route question ids are named as gi-config-checked"
has "$P2" '`gi-config.py` accepts only `squash`, `merge` or `rebase` for it' "T3.3: merge_method is named with its enum"
has "$P2" '**Check the label before you substitute it**' "T3.4: the label check still leads the paragraph"
methods="$(python3 - "$GI_CONFIG" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
for node in tree.body:
    if isinstance(node, ast.Assign) and any(getattr(t, "id", "") == "_MERGE_METHODS" for t in node.targets):
        print(" ".join(ast.literal_eval(node.value)))
PY
)"
[ "$methods" = "squash merge rebase" ] \
  && pass "T3.5: gi-config.py restricts review.merge_method to squash, merge, rebase" \
  || fail "T3.5: gi-config.py _MERGE_METHODS is '${methods}', not 'squash merge rebase'"

# ── T4 — every lane phase is listed ─────────────────────────────────────────
ORCH="$AP/references/orchestration.md"
phases="$(python3 - "$GI_STATE" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
for node in tree.body:
    target = getattr(node, "target", None) or (node.targets[0] if isinstance(node, ast.Assign) else None)
    if getattr(target, "id", "") == "LANE_TRANSITIONS" and isinstance(node.value, ast.Dict):
        print(" ".join(k.value for k in node.value.keys))
PY
)"
lanes="$(awk '/run-state.json.lanes\[\]` persists the lane phases/{on=1} on{print} on&&/\.$/{exit}' "$ORCH" | tr '\n' ' ')"
if [ -z "$phases" ]; then
  fail "T4.1: could not parse LANE_TRANSITIONS from gi-state.py"
elif [ -z "$lanes" ]; then
  fail "T4.1: orchestration.md has no lane-phase list"
else
  missing=""
  for ph in $phases; do
    grep -qF -- "\`$ph\`" <<<"$lanes" || missing="$missing $ph"
  done
  [ -z "$missing" ] && pass "T4.1: orchestration.md lists all $(echo "$phases" | wc -w | tr -d ' ') LANE_TRANSITIONS phases" \
    || fail "T4.1: orchestration.md omits lane phase(s):$missing"
fi
grep -qF 'shared/scripts/gi-state.py' <<<"$lanes" \
  && pass "T4.2: the lane-phase list points at gi-state.py as their home" \
  || fail "T4.2: the lane-phase list does not point at gi-state.py"
grep -qF -- '- `references/scripts/gi-state.py`' "$AP/SKILL.source.md" \
  && pass "T4.3: gi-state.py is in auto-pilot's bundled dependency precheck" \
  || fail "T4.3: gi-state.py is not bundled in auto-pilot"

# ── T5 — explicit-list mode pointer and plan block ──────────────────────────
EL="$AP/references/explicit-list-mode.md"
lacks "$EL" 'proceed to Confirmation' "T5.1: no pointer to a nonexistent Confirmation section"
has "$EL" 'proceed to the *Execution Plan (auto-start)* section' "T5.2: the fallback points at the Execution Plan section"
has "$EL" '### Execution Plan (auto-start)' "T5.3: the pointed-at section exists"
lacks "$EL" 'Auto-merge:         {yes/no}' "T5.4: the plan block no longer shows Auto-merge yes/no"
has "$EL" '  Merge mode:         {conservative | balanced | aggressive}' "T5.5: the plan block shows Merge mode"
has "$AP/references/phases/phase-1-triage-pick.md" '  Merge mode:         {conservative | balanced | aggressive}' "T5.6: the default plan block shows the same line"

# ── T6 — gi-ci-wait.py by its source token ──────────────────────────────────
P5="$AP/references/phases/phase-5-merge.md"
lacks "$P5" 'python3 references/scripts/gi-ci-wait.py' "T6.1: phase-5 source no longer cites the built path"
has "$P5" 'python3 shared/scripts/gi-ci-wait.py {pr_number}' "T6.2: phase-5 source cites the bare shared-script token"

# ── T7 — the description is bounded ─────────────────────────────────────────
desc="$(grep -m1 '^description:' "$AP/SKILL.source.md" || true)"
for stale in 'resolving everything' 'zero prompts'; do
  grep -qF -- "$stale" <<<"$desc" \
    && fail "T7: the description still says '$stale'" || pass "T7: the description no longer says '$stale'"
done
grep -qF 'until none remain or a stop condition fires, with no routine prompts' <<<"$desc" \
  && pass "T7: the description names the stop conditions and routine prompts" \
  || fail "T7: the description does not state the bounded loop"
grep -qF "\"Run an autonomous triage-resolve-review-merge loop to auto-pilot the GitHub issue backlog," <<<"$desc" \
  && pass "T7: the description keeps its opening phrase" || fail "T7: the description's opening phrase changed"
grep -qF "Don't use for single-issue work (/issue-resolver), triage (/issue-triage), or PR review (/issue-pr-review).\"" <<<"$desc" \
  && pass "T7: the description keeps its Don't-use clause" || fail "T7: the description's Don't-use clause changed"
has "$AP/SKILL.source.md" '## Stop Conditions' "T7: the Stop Conditions section exists"

# ── T8 — built skill and CI ─────────────────────────────────────────────────
lacks "$DIST/references/prompts/resolver.md" 'up to 3 review-fix cycles' "T8.1: the built resolver prompt carries the ceiling"
lacks "$DIST/references/run-log.md" 'committed history of what ran' "T8.2: the built run-log.md carries the lifetime fix"
has "$DIST/references/orchestration.md" '`log_pending`, `logged`' "T8.3: the built orchestration.md lists the logging phases"
has "$DIST/references/orchestration.md" 'references/scripts/gi-state.py' "T8.4: the build rewrote the gi-state.py token"
has "$DIST/references/phases/phase-5-merge.md" 'python3 references/scripts/gi-ci-wait.py {pr_number}' "T8.5: the build rewrote the gi-ci-wait.py token"
lacks "$DIST/SKILL.md" 'zero prompts' "T8.6: the built description is bounded"
grep -qF 'run: bash tests/test-autopilot-stale-facts-622.sh' "$WORKFLOW" \
  && pass "T8.7: the CI step exists" || fail "T8.7: dist-check.yml lacks this test"

echo ""
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || { echo "  ✗ Auto-pilot stale-fact tests failed"; exit 1; }
echo "  ✓ Auto-pilot stale-fact tests passed"
