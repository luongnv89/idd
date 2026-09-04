#!/usr/bin/env bash
# test-ci-billing-431.sh — Validate review.ignore_ci_billing_failures (issue #431).
#
# This script verifies issue #431 acceptance criteria:
#  AC1. /init-gitissue emits the key on a fresh install — it renders
#       templates/gitissue-template.yml wholesale, so the key must be there.
#  AC2. The default is `false`, identically in docs/config-schema.md and in the
#       init template (the build aborts if those two disagree, but a wrong
#       *shared* default would satisfy parity and still be wrong).
#  AC3. /issue-pr-review's Step 5 names the key and describes the non-blocking
#       path — reported, no Step 6 CI fixable, CI leg satisfied for soft-pass.
#  AC4. The blocking path survives: Step 5 still fails on CI with the flag off,
#       still refuses to treat pending as clean, and — on the ignore path —
#       still binds `ci_status` as `failed@<sha40>`, never `passed@`. Writing
#       `passed@` would bind a false claim to a commit.
#
# Plus the three safety invariants the narrow scope depends on:
#  I2. The review outcome is PARTIAL, never a clean pass.
#  I3. `ci_leg_runnable` is unaffected — an ignored CI leg must not also skip
#      the local test suite.
#  I4. The manual (no-script) fallback honors the flag on the same contract.
#  I5. /auto-pilot is out of scope and must not consume the key.
#  I6. The ignored-CI path is excluded from the auto-merge gate. The leg is
#      satisfied for *loop exit* only; "clean" at the merge gate must exclude
#      it the way it already excludes pending CI. Without this, standalone
#      /issue-pr-review --auto with review.auto_merge: true would squash-merge
#      a red PR — I2's PARTIAL means "continue", so it never blocked anything.
#
# The built skills/ tree is asserted alongside src/ so drift is caught here and
# not only by the CI drift check.
#
# Strategy: this is a documentation/skill repo — tests verify that the
# SKILL.md, template, and schema files contain the spec language that satisfies
# each AC. If the language is present, the agent following the skill produces
# the documented behavior.
#
# Usage: bash tests/test-ci-billing-431.sh
# Returns: exit 0 if all tests pass, exit 1 on any failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY='ignore_ci_billing_failures'

SCHEMA="$REPO_ROOT/docs/config-schema.md"
TEMPLATE="$REPO_ROOT/src/skills/init-gitissue/templates/gitissue-template.yml"
DIST_TEMPLATE="$REPO_ROOT/skills/init-gitissue/templates/gitissue-template.yml"
DIST_INIT_SCHEMA="$REPO_ROOT/skills/init-gitissue/references/docs/config-schema.md"

SRC_SKILL="$REPO_ROOT/src/skills/issue-pr-review/SKILL.source.md"
DIST_SKILL="$REPO_ROOT/skills/issue-pr-review/SKILL.md"
SRC_REF="$REPO_ROOT/src/skills/issue-pr-review/references"
DIST_REF="$REPO_ROOT/skills/issue-pr-review/references"

PASS=0
FAIL=0

pass() {
  echo "  ✓ $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  ✗ $1"
  FAIL=$((FAIL + 1))
}

echo "◆ CI billing-failure config tests (issue #431)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T0: files exist
# ───────────────────────────────────────────────────────────
for f in "$SCHEMA" "$TEMPLATE" "$DIST_TEMPLATE" "$DIST_INIT_SCHEMA" \
         "$SRC_SKILL" "$DIST_SKILL"; do
  if [ -f "$f" ]; then
    pass "T0: ${f#"$REPO_ROOT"/} exists"
  else
    fail "T0: $f not found"
    exit 1
  fi
done

# ───────────────────────────────────────────────────────────
# T1: AC2 — the default is false, in the schema and in the template
# ───────────────────────────────────────────────────────────
# The build's schema/template parity check aborts on a mismatch, so these two
# assertions are not redundant with it: they pin the shared value to `false`,
# which parity alone would happily let drift to `true` in both places at once.
if grep -qE "^\s*${KEY}:\s*false\s*$" "$SCHEMA"; then
  pass "T1.AC2.1: docs/config-schema.md Full Schema fence has '${KEY}: false'"
else
  fail "T1.AC2.1: docs/config-schema.md Full Schema fence missing '${KEY}: false'"
fi

if grep -qE "\| \`review\.${KEY}\` \| \`false\`" "$SCHEMA"; then
  pass "T1.AC2.2: defaults table lists review.${KEY} = false"
else
  fail "T1.AC2.2: defaults table missing review.${KEY} = false"
fi

if grep -qE "RV[0-9]+\[\"${KEY}\"\]" "$SCHEMA"; then
  pass "T1.AC2.3: Config Section Map mermaid carries ${KEY} under review"
else
  fail "T1.AC2.3: Config Section Map mermaid missing ${KEY}"
fi

# The honest doc comment is the point of the key name: no API field identifies
# a billing failure, so the flag ignores ANY terminal CI failure. A comment
# that dropped that would make the key name a lie.
if grep -qiE 'No GitHub API field identifies a billing-related CI failure' "$SCHEMA" \
   && grep -qE 'ignores ANY terminal CI failure' "$SCHEMA"; then
  pass "T1.AC2.4: the schema comment states that billing is undetectable and ANY failure is ignored"
else
  fail "T1.AC2.4: the schema comment omits the billing-undetectable caveat"
fi

# ───────────────────────────────────────────────────────────
# T2: AC1 — /init-gitissue renders the key on a fresh install
# ───────────────────────────────────────────────────────────
# /init-gitissue names no review.* key in its own prose; it emits
# templates/gitissue-template.yml wholesale. So the template is the AC.
for t in "$TEMPLATE" "$DIST_TEMPLATE"; do
  if grep -qE "^\s*${KEY}:\s*false\s*$" "$t"; then
    pass "T2.AC1: ${t#"$REPO_ROOT"/} emits '${KEY}: false'"
  else
    fail "T2.AC1: ${t#"$REPO_ROOT"/} does not emit '${KEY}: false'"
  fi
done

# The key must sit inside the review: block, not some other section.
if awk '/^review:/{inblock=1;next} /^[a-z_]+:/{inblock=0} inblock' "$TEMPLATE" \
     | grep -qE "^\s*${KEY}:"; then
  pass "T2.AC1: the template places ${KEY} inside the review: block"
else
  fail "T2.AC1: ${KEY} is not inside the template's review: block"
fi

# The bundled schema /init-gitissue reads keeps the whole doc, so the key is
# reachable at run time too.
if grep -qE "^\s*${KEY}:\s*false\s*$" "$DIST_INIT_SCHEMA"; then
  pass "T2.AC1: init-gitissue's bundled config-schema.md carries the key"
else
  fail "T2.AC1: init-gitissue's bundled config-schema.md is missing the key"
fi

# ───────────────────────────────────────────────────────────
# T3: AC3 — /issue-pr-review Step 5 names the key and the non-blocking path
# ───────────────────────────────────────────────────────────
step5_of() {
  awk '/^## Step 5 — Check CI Status/{s=1} /^## Step 6/{s=0} s' "$1"
}

for f in "$SRC_SKILL" "$DIST_SKILL"; do
  label="${f#"$REPO_ROOT"/}"
  section="$(step5_of "$f")"

  if printf '%s' "$section" | grep -q "review\.${KEY}"; then
    pass "T3.AC3: $label Step 5 names review.${KEY}"
  else
    fail "T3.AC3: $label Step 5 does not name review.${KEY}"
  fi

  if printf '%s' "$section" | grep -qi 'non-blocking'; then
    pass "T3.AC3: $label Step 5 describes the failure as non-blocking"
  else
    fail "T3.AC3: $label Step 5 never calls the failure non-blocking"
  fi

  # Reported, not silenced: CI is still polled and the failure is still shown.
  if printf '%s' "$section" | grep -qiE 'still polled'; then
    pass "T3.AC3: $label Step 5 keeps polling CI (this is not check_ci: false)"
  else
    fail "T3.AC3: $label Step 5 does not say CI is still polled"
  fi

  # No Step 6 CI fixable, and the soft-pass conjunction sees the leg satisfied.
  if printf '%s' "$section" | grep -qiE 'no.{0,3}\*{0,2} ?CI fixable|raises \*\*no\*\*'; then
    pass "T3.AC3: $label Step 5 raises no Step 6 CI fixable"
  else
    fail "T3.AC3: $label Step 5 does not suppress the Step 6 CI fixable"
  fi

  if printf '%s' "$section" | grep -qi 'soft-pass conjunction treats the CI leg as satisfied'; then
    pass "T3.AC3: $label Step 5 lets soft-pass treat the CI leg as satisfied"
  else
    fail "T3.AC3: $label Step 5 does not satisfy the soft-pass CI leg"
  fi

  if printf '%s' "$section" \
       | grep -qF "not blocking (review.${KEY}: true)"; then
    pass "T3.AC3: $label Step 5 prints a distinct tracker line for the ignored path"
  else
    fail "T3.AC3: $label Step 5 has no distinct tracker line for the ignored path"
  fi
done

# ───────────────────────────────────────────────────────────
# T4: AC4 — the blocking path survives, and never claims passed@
# ───────────────────────────────────────────────────────────
# The ignore-flag block only. A file-wide grep for `passed@` would hit the two
# legitimate existing uses (the trusted-acceptance sentence and the commit
# binding sentence), so the negative assertion is scoped to the new text.
ignore_block_of() {
  awk "/\\*\\*\`review\\.${KEY}: true\`\\*\\*/,/^\`\`\`\$/" "$1"
}

for f in "$SRC_SKILL" "$DIST_SKILL"; do
  label="${f#"$REPO_ROOT"/}"
  section="$(step5_of "$f")"
  block="$(ignore_block_of "$f")"

  if [ -n "$block" ]; then
    pass "T4.AC4: $label carries an identifiable ${KEY} block"
  else
    fail "T4.AC4: $label has no identifiable ${KEY} block"
    continue
  fi

  # The blocking path is still documented: the ✗ tracker line and the
  # pending-is-not-clean rule are both untouched.
  if printf '%s' "$section" | grep -qF '[5/7] CI Status    ✗ {N} checks failed'; then
    pass "T4.AC4: $label Step 5 still prints the blocking ✗ CI line (flag off)"
  else
    fail "T4.AC4: $label Step 5 lost the blocking ✗ CI line"
  fi

  if printf '%s' "$section" | grep -qi 'Pending CI is \*\*not clean\*\*'; then
    pass "T4.AC4: $label Step 5 still refuses to treat pending CI as clean"
  else
    fail "T4.AC4: $label Step 5 no longer refuses pending CI"
  fi

  # ci_status binding: failed@, and an explicit refusal of passed@.
  if printf '%s' "$block" | grep -qF 'failed@'; then
    pass "T4.AC4: $label binds ci_status as failed@<sha40> on the ignored path"
  else
    fail "T4.AC4: $label does not bind ci_status as failed@ on the ignored path"
  fi

  # Every mention of passed@ inside the block must be a refusal. A bare absence
  # check would be defeated by the very sentence that states the invariant.
  bad="$(printf '%s\n' "$block" | grep -F 'passed@' | grep -vi 'never' || true)"
  if [ -z "$bad" ]; then
    pass "T4.AC4: $label never claims passed@ on the ignored path"
  else
    fail "T4.AC4: $label claims passed@ on the ignored path: $bad"
  fi
done

# ───────────────────────────────────────────────────────────
# T5: I2 — the outcome is PARTIAL, never a clean pass
# ───────────────────────────────────────────────────────────
for r in "$SRC_REF" "$DIST_REF"; do
  rt="$r/report-templates.md"
  label="${rt#"$REPO_ROOT"/}"
  if [ ! -f "$rt" ]; then
    fail "T5.I2: $label not found"
    continue
  fi
  if grep -q "review\.${KEY}" "$rt" && grep -qE 'PARTIAL' "$rt"; then
    pass "T5.I2: $label documents the ignored-CI PARTIAL variant"
  else
    fail "T5.I2: $label does not document the ignored-CI PARTIAL variant"
  fi
  if grep -qF '× Required checks green' "$rt"; then
    pass "T5.I2: $label keeps 'Required checks green' as a failed check"
  else
    fail "T5.I2: $label does not mark 'Required checks green' as failed"
  fi
done

# ───────────────────────────────────────────────────────────
# T6: I3 — ci_leg_runnable is unaffected
# ───────────────────────────────────────────────────────────
for r in "$SRC_REF" "$DIST_REF"; do
  rl="$r/review-loop-mechanics.md"
  label="${rl#"$REPO_ROOT"/}"
  if [ ! -f "$rl" ]; then
    fail "T6.I3: $label not found"
    continue
  fi
  if grep -q "review\.${KEY}" "$rl"; then
    pass "T6.I3: $label config table names review.${KEY}"
  else
    fail "T6.I3: $label config table does not name review.${KEY}"
  fi
  # The direction must be stated explicitly, not left to inference: an ignored
  # CI leg must not silently also skip the local suite.
  if grep -qiE "${KEY} does not enter this predicate|does not touch \`ci_leg_runnable\`" "$rl"; then
    pass "T6.I3: $label states that ${KEY} leaves ci_leg_runnable unchanged"
  else
    fail "T6.I3: $label does not state ci_leg_runnable is unchanged"
  fi
done

# ───────────────────────────────────────────────────────────
# T7: I4 — the manual fallback honors the flag on the same contract
# ───────────────────────────────────────────────────────────
for r in "$SRC_REF" "$DIST_REF"; do
  pc="$r/prepass-tests-ci-mechanics.md"
  label="${pc#"$REPO_ROOT"/}"
  if [ ! -f "$pc" ]; then
    fail "T7.I4: $label not found"
    continue
  fi
  if grep -q "review\.${KEY}" "$pc"; then
    pass "T7.I4: $label names review.${KEY}"
  else
    fail "T7.I4: $label does not name review.${KEY}"
  fi
  if grep -qiE 'fallback must honor the flag exactly as the script path does' "$pc"; then
    pass "T7.I4: $label holds the manual fallback to the same contract"
  else
    fail "T7.I4: $label does not hold the manual fallback to the same contract"
  fi
  # Only an observed terminal failure is ignored — never a timeout, a pending
  # result, or an unavailable fallback, none of which observed a failure.
  if grep -qiE 'the flag ignores only a' "$pc" \
     && grep -qiE 'unconfirmed-empty, head change, and fallback error' "$pc"; then
    pass "T7.I4: $label ignores only an observed terminal failure"
  else
    fail "T7.I4: $label does not restrict the flag to an observed terminal failure"
  fi
  # The commit binding stays failed@, and says why passed@ is refused.
  if grep -qiE 'is not a fourth case, and it is not' "$pc"; then
    pass "T7.I4: $label keeps ci_status bound as failed@ on the ignored path"
  else
    fail "T7.I4: $label does not address the ci_status binding for the ignored path"
  fi
done

# ───────────────────────────────────────────────────────────
# T8: I5 — /auto-pilot is out of scope and does not consume the key
# ───────────────────────────────────────────────────────────
# Scoped to auto-pilot's own authored files: its bundled config-schema.md
# excerpt legitimately carries the review section, so a tree-wide grep would
# report a false positive.
ap_hits=""
for f in "$REPO_ROOT/src/skills/auto-pilot/SKILL.source.md" \
         "$REPO_ROOT/skills/auto-pilot/SKILL.md"; do
  [ -f "$f" ] && grep -q "$KEY" "$f" && ap_hits="$ap_hits ${f#"$REPO_ROOT"/}"
done
for f in "$REPO_ROOT"/src/skills/auto-pilot/references/*.md \
         "$REPO_ROOT"/skills/auto-pilot/references/*.md \
         "$REPO_ROOT"/src/skills/auto-pilot/references/phases/*.md \
         "$REPO_ROOT"/skills/auto-pilot/references/phases/*.md; do
  [ -f "$f" ] || continue
  grep -q "$KEY" "$f" && ap_hits="$ap_hits ${f#"$REPO_ROOT"/}"
done
if [ -z "$ap_hits" ]; then
  pass "T8.I5: /auto-pilot's own files do not consume ${KEY} (out of scope)"
else
  fail "T8.I5: /auto-pilot consumes ${KEY} in:$ap_hits"
fi

# The boundary must be stated where a reader of /issue-pr-review will find it.
if grep -qi "auto-pilot" "$SRC_SKILL" \
   && printf '%s' "$(ignore_block_of "$SRC_SKILL")" | grep -qi 'auto-pilot'; then
  pass "T8.I5: the ${KEY} block states the /auto-pilot boundary"
else
  fail "T8.I5: the ${KEY} block does not state the /auto-pilot boundary"
fi

# ───────────────────────────────────────────────────────────
# T9: the error-messages catalog carries the ignored-CI entry
# ───────────────────────────────────────────────────────────
for r in "$SRC_REF" "$DIST_REF"; do
  em="$r/error-messages.md"
  label="${em#"$REPO_ROOT"/}"
  if [ -f "$em" ] && grep -q "review\.${KEY}" "$em"; then
    pass "T9: $label documents the ignored-CI path"
  else
    fail "T9: $label does not document the ignored-CI path"
  fi
done

# ───────────────────────────────────────────────────────────
# T10: I6 — the ignored-CI path is excluded from the auto-merge gate
# ───────────────────────────────────────────────────────────
# I2 ("the outcome is PARTIAL") is *not* protective: a step-level PARTIAL means
# "continue" (report-templates.md → Step Completion Reports), and the ignored
# path deliberately satisfies the soft-pass CI leg. So the only thing standing
# between `--auto` + `review.auto_merge: true` and a squash-merged red PR is an
# explicit carve-out at each gate site, worded the way `pending CI is never
# clean` already is. Assert all three sites, in src and dist.

for f in "$SRC_SKILL" "$DIST_SKILL"; do
  label="${f#"$REPO_ROOT"/}"

  # Site 1 — Step 7's merge parenthetical. The sentence that already excludes
  # pending CI must exclude the ignored CI failure on the same line: two
  # distinct "never clean" carve-outs, one of them naming the key.
  merge_gate="$(grep -F 'pending CI is never clean' "$f" || true)"
  never_clean_count="$(printf '%s\n' "$merge_gate" | grep -o 'never clean' | wc -l | tr -d ' ')"
  if printf '%s' "$merge_gate" | grep -qF "review.${KEY}" \
     && [ "${never_clean_count:-0}" -ge 2 ]; then
    pass "T10.I6: $label Step 7 merge gate excludes an ignored CI failure (never clean)"
  else
    fail "T10.I6: $label Step 7 merge gate does not exclude an ignored CI failure"
  fi

  # Site 2 — the soft-pass Review Loop bullet. Its CI-leg enumeration is what
  # "clean" resolves to; it must name the new alternative AND scope it to loop
  # exit, or the enumeration silently hands the merge gate a red PR.
  soft_bullet="$(grep -F 'Soft pass (`review.soft_pass: true`, default)' "$f" || true)"
  if printf '%s' "$soft_bullet" | grep -qF "review.${KEY}" \
     && printf '%s' "$soft_bullet" | grep -qF 'never clean at the auto-merge gate'; then
    pass "T10.I6: $label soft-pass bullet enumerates the ignored CI leg as loop-exit-only"
  else
    fail "T10.I6: $label soft-pass bullet does not scope the ignored CI leg to loop exit"
  fi

  # Site 3 — the strict-pass bullet inherits the same tests/CI gates, so it
  # inherits the same hole unless it states the carve-out too.
  strict_bullet="$(grep -F 'Strict pass (`review.soft_pass: false`)' "$f" || true)"
  if printf '%s' "$strict_bullet" | grep -qF "review.${KEY}" \
     && printf '%s' "$strict_bullet" | grep -qF 'never clean at the auto-merge gate'; then
    pass "T10.I6: $label strict-pass bullet enumerates the ignored CI leg as loop-exit-only"
  else
    fail "T10.I6: $label strict-pass bullet does not scope the ignored CI leg to loop exit"
  fi
done

# Site 4 — report-templates.md's auto-merge paragraph. "The same configured
# pass condition as the loop exit" is exactly the sentence the carve-out
# falsifies, so it must state the exclusion itself, not defer to it.
for r in "$SRC_REF" "$DIST_REF"; do
  rt="$r/report-templates.md"
  label="${rt#"$REPO_ROOT"/}"
  if [ ! -f "$rt" ]; then
    fail "T10.I6: $label not found"
    continue
  fi
  gate_para="$(grep -F 'Auto-merge is gated on' "$rt" || true)"
  if printf '%s' "$gate_para" | grep -qF "review.${KEY}" \
     && printf '%s' "$gate_para" | grep -qF 'never clean'; then
    pass "T10.I6: $label auto-merge paragraph carves the ignored CI failure out of the merge gate"
  else
    fail "T10.I6: $label auto-merge paragraph does not exclude the ignored CI failure"
  fi
done

# ───────────────────────────────────────────────────────────
# T11: a failing check renders {bucket}/{state}, never a bare {bucket}
# ───────────────────────────────────────────────────────────
# gh's `bucket` is raw: a terminal STARTUP_FAILURE or STALE still carries
# `bucket: pending`, so printing it alone under a "checks failed" heading
# contradicts the heading. Nothing else in the suite pins this —
# test-scripts-252.sh exercises gi-ci-wait.py's classifier, not the skill's
# render string — so a revert to a bare {bucket} would otherwise pass silently.

# True when the text carries a {bucket} token not immediately followed by `/`.
has_bare_bucket() {
  printf '%s\n' "$1" | grep -qE '\{bucket\}([^/]|$)'
}

for f in "$SRC_SKILL" "$DIST_SKILL"; do
  label="${f#"$REPO_ROOT"/}"
  tracker="$(step5_of "$f" | grep -F '[5/7] CI Status' | grep -F '✗' || true)"

  if printf '%s' "$tracker" | grep -qF '{bucket}/{state}'; then
    pass "T11: $label Step 5 failing-check tracker renders {bucket}/{state}"
  else
    fail "T11: $label Step 5 failing-check tracker does not render {bucket}/{state}"
  fi

  if [ -n "$tracker" ] && ! has_bare_bucket "$tracker"; then
    pass "T11: $label Step 5 failing-check tracker never renders a bare {bucket}"
  else
    fail "T11: $label Step 5 failing-check tracker renders a bare {bucket}"
  fi
done

for r in "$SRC_REF" "$DIST_REF"; do
  em="$r/error-messages.md"
  label="${em#"$REPO_ROOT"/}"
  if [ ! -f "$em" ]; then
    fail "T11: $label not found"
    continue
  fi
  # The fenced sample output inside the ignored-CI entry only: the prose that
  # follows it legitimately names `{bucket}` alone while explaining the rule.
  em_fence="$(awk '/^### CI failed but was not blocking/{s=1;next}
                   /^### /{s=0}
                   s && /^```/{f=!f;next}
                   s && f' "$em")"

  if printf '%s\n' "$em_fence" | grep -qF 'Failing: {check_name} ({bucket}/{state})'; then
    pass "T11: $label ignored-CI block prints ({bucket}/{state})"
  else
    fail "T11: $label ignored-CI block does not print ({bucket}/{state})"
  fi

  if [ -n "$em_fence" ] && ! has_bare_bucket "$em_fence"; then
    pass "T11: $label ignored-CI block never prints a bare {bucket}"
  else
    fail "T11: $label ignored-CI block prints a bare {bucket}"
  fi
done

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  Result: FAIL"
  exit 1
else
  echo "  Result: PASS"
  exit 0
fi
