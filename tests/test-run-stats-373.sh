#!/usr/bin/env bash
# test-run-stats-373.sh — Run-stats footer on every skill final report (issue #373)
#
# Acceptance criteria:
#   AC1: every IDD skill's final report ends with a run-stats section.
#   AC2: the section always appears — including when the run failed, was paused,
#        hit a limit, or was aborted partway.
#   AC3: it reports at minimum total elapsed wall-clock time and tokens consumed.
#   AC4: it is compact and gathering it adds no perceptible time or token cost.
#   AC5: an undeterminable metric shows an explicit unavailable marker rather
#        than being omitted, guessed, or reported as zero.
#   AC6: shape and labels are consistent across skills.
#
# SUPERSEDED IN PART by issue #410: AC3's `tokens` clause is superseded, leaving
# AC3 binding on `elapsed` only; AC5 is generic, so it binds `elapsed` and
# `agents`. `tokens` is conditional — printed where the host reports a figure,
# left out of the line where it does not, because a host-agnostic skill cannot
# obtain a real count without the subprocess/summarization pass the contract's
# own Overhead section forbids. A permanent `tokens n/a` is the bug #410 fixed,
# so this suite now forbids that string in the contract.
#
# AC6 is enforced structurally: references/run-stats.md is byte-identical in
# every skill, so "consistent across skills" is a checksum, not a promise. The
# contract lives per skill rather than in docs/terminal-style.md because that
# doc ships to 7 bundles and test-bundled-doc-slimming-249.sh's byte ratchet
# (37 bytes of headroom) forbids growing it; references/ is not budget-covered.
#
# Asserts on the authored src/ sources AND on the built skills/ tree, because a
# contract that ships only in src/ is not installed for anyone.
#
# Usage: bash tests/test-run-stats-373.sh
# Returns: exit 0 if all checks pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

check_has() {
  local file="$1" pattern="$2" label="$3"
  if grep -qE "$pattern" "$file" 2>/dev/null; then
    pass "$label"
  else
    fail "$label (pattern not found in ${file#$REPO_ROOT/}: $pattern)"
  fi
}

# Prose assertions must survive re-wrapping: markdown hard-wraps at ~78 chars,
# so a sentence can straddle a line break. Collapse whitespace before matching.
check_flow() {
  local file="$1" pattern="$2" label="$3"
  if tr '\n' ' ' < "$file" 2>/dev/null | tr -s ' ' | grep -qE "$pattern"; then
    pass "$label"
  else
    fail "$label (prose not found in ${file#$REPO_ROOT/}: $pattern)"
  fi
}

check_lacks() {
  local file="$1" pattern="$2" label="$3"
  if grep -qE "$pattern" "$file" 2>/dev/null; then
    fail "$label (forbidden pattern present in ${file#$REPO_ROOT/}: $pattern)"
  else
    pass "$label"
  fi
}

# The negative twin of check_flow: a forbidden sentence must stay forbidden even
# if a reviving edit hard-wraps it across a line break, so collapse first.
check_flow_lacks() {
  local file="$1" pattern="$2" label="$3"
  if tr '\n' ' ' < "$file" 2>/dev/null | tr -s ' ' | grep -qE "$pattern"; then
    fail "$label (forbidden prose present in ${file#$REPO_ROOT/}: $pattern)"
  else
    pass "$label"
  fi
}

# Every skill that carries a final report — the six the issue names, plus
# init-gitissue and the repo-internal idd-doctor, which also print one.
SKILL_DIRS=(
  "src/skills/auto-pilot"
  "src/skills/init-gitissue"
  "src/skills/issue-analysis"
  "src/skills/issue-creator"
  "src/skills/issue-pr-review"
  "src/skills/issue-resolver"
  "src/skills/issue-triage"
  "src/internal-skills/idd-doctor"
)

echo "◆ Run-stats footer Tests (issue #373)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo ""

# ── AC6: one contract, byte-identical everywhere ─────────────────────────────
echo "  AC6 — one contract, byte-identical in every skill"
SUMS=""
missing=0
for d in "${SKILL_DIRS[@]}"; do
  f="$REPO_ROOT/$d/references/run-stats.md"
  if [ -f "$f" ]; then
    SUMS="$SUMS$(cksum < "$f" | awk '{print $1"-"$2}')\n"
  else
    fail "AC6: $d/references/run-stats.md missing"
    missing=$((missing + 1))
  fi
done
if [ "$missing" -eq 0 ]; then
  pass "AC1: all ${#SKILL_DIRS[@]} skills carry references/run-stats.md"
  distinct=$(printf "$SUMS" | sort -u | grep -c .)
  if [ "$distinct" -eq 1 ]; then
    pass "AC6: every copy is byte-identical (1 distinct checksum) — labels cannot drift"
  else
    fail "AC6: $distinct distinct checksums across the copies — the shape has drifted"
  fi
fi
SPEC="$REPO_ROOT/src/skills/issue-resolver/references/run-stats.md"
echo ""

# ── AC3 + AC6: the footer's shape and fields ────────────────────────────────
echo "  AC3/AC6 — footer shape and fields"
check_has  "$SPEC" 'Run stats   elapsed .* · tokens .* · agents ' \
  "AC6: the contract shows the canonical one-line footer"
check_has  "$SPEC" '^\| .elapsed. \|' "AC3: elapsed is a defined field"
check_has  "$SPEC" '^\| .tokens. \|'  "AC3: tokens is a defined field"
check_has  "$SPEC" '^\| .agents. \|'  "AC6: agents is a defined field"
check_flow "$SPEC" 'Fixed, in this order' "AC6: field order is pinned"
check_flow "$SPEC" 'No skill adds, reorders, or renames one' \
  "AC6: adding, reordering, or renaming a field is forbidden"
check_flow "$SPEC" 'byte-identical in every skill' \
  "AC6: the contract states its own byte-identity rule"
check_flow "$SPEC" 'the leading unit is unpadded and every unit after it is zero-padded' \
  "AC6: the elapsed rendering is pinned, so two skills cannot format one duration differently"
check_flow "$SPEC" 'Drop zero-valued \*leading\* units, never interior or trailing ones' \
  "AC6: which units may be dropped is stated, not left to judgement"
echo ""

# ── AC5: explicit unavailable marker, and 0 is not that marker ──────────────
echo "  AC5 — unavailable marker"
check_has  "$SPEC" '^## Unavailable values' "AC5: the contract has an Unavailable values section"
check_flow "$SPEC" 'prints the literal .n/a. — never a guess' \
  "AC5: undeterminable metrics print the literal n/a"
check_flow "$SPEC" 'never an omitted field, never .0.' \
  "AC5: elapsed and agents require n/a instead of omitting or zeroing"
check_flow "$SPEC" '.elapsed. and .agents. are unconditional' \
  "AC5: the n/a rule is scoped to the unconditional fields"
check_flow "$SPEC" 'Never estimate from output length' \
  "AC5: guessing a token count is forbidden"
check_flow "$SPEC" 'is a \*\*determined\*\* value' \
  "AC5: a true zero is still reported as 0, not n/a"
check_flow "$SPEC" 'between .nothing happened. and .we do not know.' \
  "AC5: the 0-vs-n/a distinction is stated, not implied"
echo ""

# ── #410: tokens is conditional, never a permanent n/a ──────────────────────
echo "  #410 — tokens is a conditional field"
check_lacks "$SPEC" 'tokens n/a' \
  "#410/AC1: the contract never shows tokens as a permanent n/a"
check_has  "$SPEC" 'Run stats   elapsed [^·]* · agents ' \
  "#410/AC3: the omitted rendering is shown as canonical"
check_flow "$SPEC" 'the field is left out, not marked' \
  "#410/AC3: an unreported token count omits the field rather than marking it"
check_flow "$SPEC" 'If you would have to go and find it' \
  "#410/AC2: what counts as a reported figure is a stated decision procedure"
check_flow "$SPEC" 'never read the host.s transcript, session files, or logs' \
  "#410: reconstructing a count from host internals is forbidden"
echo ""

# ── AC2: bound to every terminal outcome, not just the happy path ───────────
echo "  AC2 — every terminal outcome"
check_has  "$SPEC" '^## Every terminal outcome' \
  "AC2: the contract has an Every terminal outcome section"
check_flow "$SPEC" 'not only where it succeeds' \
  "AC2: the footer is not gated on success"
check_flow "$SPEC" 'a failed step, an aborted or paused loop' \
  "AC2: failed, aborted, and paused runs are enumerated"
check_flow "$SPEC" 'rate-limit or runtime-budget stop' \
  "AC2: a run that hit a limit is enumerated"
check_flow "$SPEC" 'invalid-config stop' \
  "AC2: a stop before the pipeline began is enumerated"
check_flow "$SPEC" 'it prints it on the paths that never reach a run-log write' \
  "AC2: coverage exceeds the run-log's own write points"
check_flow "$SPEC" 'elapsed n/a. when no start time was captured' \
  "AC2/AC5: a stop before the clock was captured still prints a footer"
echo ""

# ── AC4: compact, and cheap to gather ──────────────────────────────────────
echo "  AC4 — compact and cheap"
check_flow "$SPEC" 'Two lines, printed last' "AC4: the footer is capped at two lines"
check_has  "$SPEC" '^## Overhead' "AC4: the contract has an Overhead section"
check_flow "$SPEC" 'one epoch read at start, one at the end' \
  "AC4: measuring costs two clock reads"
check_flow "$SPEC" 'Never add a timing call per step' \
  "AC4: per-step timing, tally files, and subprocesses are forbidden"
check_flow "$SPEC" 'never become a measurable share of what it measures' \
  "AC4: the overhead rule is stated normatively"
echo ""

# ── #165 — run cost only, never a metric the run already printed ───────────
echo "  #165 — no duplicated metrics"
check_has  "$SPEC" '^## What the footer must not carry' \
  "#165: the contract forbids repeating already-printed metrics"
check_flow "$SPEC" 'the duplication issue #165 removed' \
  "#165: the contract cites the issue the rule comes from"
echo ""

# ── AC1 + AC2: every skill points at the contract at its report site ───────
echo "  AC1 — every skill's final report"
for d in "${SKILL_DIRS[@]}"; do
  f="$REPO_ROOT/$d/SKILL.source.md"
  name="$(basename "$d")"
  if [ ! -f "$f" ]; then
    fail "AC1: $d/SKILL.source.md missing"
    continue
  fi
  check_has  "$f" 'Run Stats Footer' "AC1: $name names the Run Stats Footer"
  check_has  "$f" 'references/run-stats\.md' \
    "AC6: $name points at the contract rather than restating it"
  check_flow "$f" 'every\*\* terminal outcome' \
    "AC2: $name binds the footer to every terminal outcome"
  # #410: the call-site clause is what the agent reads *before* it opens the
  # contract, so a silent revert here reinstates the bug in the operative
  # instruction while references/run-stats.md still says otherwise.
  check_flow "$f" 'only where the host reported a count' \
    "#410: $name's call site states the conditional rule"
  check_flow_lacks "$f" '`elapsed`, `tokens`, `agents`' \
    "#410: $name's call site does not list tokens as an unconditional field"
  # The precheck list is this repo's authoritative bundle guard — a contract the
  # precheck does not name is a file whose absence nobody notices at run time.
  check_has  "$f" '(^|`)references/run-stats\.md' \
    "AC1: $name's bundled dependency precheck names the contract"
  # AC2's real exposure: the error catalog holds the exact output blocks for the
  # stops, and an agent that prints one and exits would otherwise skip the footer.
  cat="$REPO_ROOT/$d/references/error-messages.md"
  check_flow "$cat" 'block here that stops the run is followed by the run-stats footer' \
    "AC2: $name's error catalog binds every stopping block to the footer"
  check_flow "$cat" 'prints .elapsed n/a., which is the contract working' \
    "AC2/AC5: $name's error catalog covers a stop before the clock was captured"
  check_flow "$cat" 'warns and continues is not a terminal outcome' \
    "AC2: $name's error catalog excludes non-terminal warnings"
done
echo ""

# ── AC3/AC4: each skill has a named clock anchor to measure elapsed from ───
echo "  AC3 — the run clock anchor"
for name in issue-analysis issue-creator issue-pr-review issue-resolver issue-triage; do
  f="$REPO_ROOT/src/skills/$name/SKILL.source.md"
  check_flow "$f" 'that same .python3. invocation.*ec=\$\?; date \+%s >&2; exit "\$ec"' \
    "AC4: $name captures the clock in the config load — no extra round trip, exit and stdout preserved"
  check_has  "$f" 'run_started_epoch' "AC3: $name names the run_started_epoch anchor"
done
check_flow "$REPO_ROOT/src/skills/auto-pilot/SKILL.source.md" \
  'The run clock is .run_state\.started_at.' \
  "AC4: auto-pilot reuses its recorded started_at instead of a second clock"
check_lacks "$REPO_ROOT/src/skills/auto-pilot/SKILL.source.md" \
  'captures a second start time' \
  "AC4: auto-pilot does not capture a second start time"
check_has "$REPO_ROOT/src/skills/init-gitissue/SKILL.source.md" \
  'run_started_epoch' "AC3: init-gitissue names the run_started_epoch anchor"
check_has "$REPO_ROOT/src/internal-skills/idd-doctor/SKILL.source.md" \
  'run_started_epoch' "AC3: idd-doctor names the run_started_epoch anchor"
check_flow "$REPO_ROOT/src/internal-skills/idd-doctor/SKILL.source.md" \
  'not a repo mutation' \
  "AC3: idd-doctor's clock read is reconciled with its read-only guarantee"
check_flow "$REPO_ROOT/src/skills/init-gitissue/SKILL.source.md" \
  'agents 0. is the determined value here' \
  "AC5: init-gitissue spawns none, so it reports 0 rather than n/a"
echo ""

# ── The contract has to ship, not just live in src/ ───────────────────────
echo "  Install surface — the built skills/ tree"
built=0
for s in "$REPO_ROOT"/skills/*/SKILL.md; do
  skill="$(basename "$(dirname "$s")")"
  built=$((built + 1))
  check_has "$s" 'Run Stats Footer' "AC1: built $skill/SKILL.md names the footer"
  contract="$REPO_ROOT/skills/$skill/references/run-stats.md"
  if [ -f "$contract" ]; then
    if cmp -s "$contract" "$REPO_ROOT/src/skills/$skill/references/run-stats.md"; then
      pass "AC6: built $skill ships the contract byte-for-byte"
    else
      fail "AC6: built $skill/references/run-stats.md differs from its source — run ./scripts/build.sh"
    fi
  else
    fail "AC1: built $skill does not bundle references/run-stats.md — run ./scripts/build.sh"
  fi
done
if [ "$built" -eq 7 ]; then
  pass "AC1: all 7 distributed skills were checked"
else
  fail "AC1: found $built built skills, expected 7"
fi
echo ""

# ── The byte ratchet that shaped this layout must still hold ──────────────
echo "  Byte ratchet — the contract stayed out of the bundled docs"
if [ ! -f "$REPO_ROOT/docs/run-stats.md" ]; then
  pass "AC4: no docs/run-stats.md — a 14th doc bundled 7x would breach test-bundled-doc-slimming-249.sh"
else
  fail "AC4: docs/run-stats.md exists — it ships to 7 bundles and breaks the byte ratchet"
fi
check_lacks "$REPO_ROOT/docs/terminal-style.md" 'Run Stats Footer' \
  "AC4: the contract did not grow docs/terminal-style.md, which 7 skills bundle"
echo ""

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Run-stats footer tests failed ($PASS passed, $FAIL failed)"
  exit 1
fi
echo "  ✓ All run-stats footer checks passed ($PASS)"
