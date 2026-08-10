#!/usr/bin/env bash
# test-bundled-doc-slimming-249.sh — Bundled-doc slimming contract (issue #249)
#
# Acceptance criteria:
#  - AC1: no skill bundles a doc its runtime instructions never reference
#  - AC2: a resolver run no longer needs the full config schema to write a
#         run-log line (the run-log schema is its own runtime doc)
#  - AC3: total bundled-doc bytes across the built skills stay within budget
#  - AC4: init-template/config-schema parity + precheck drift guards still pass
#         (enforced by ./scripts/build.sh, which this test's fixtures assume ran)
#
# Usage: bash tests/test-bundled-doc-slimming-249.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

# Measured after the issue #249 build: 467,132 bytes across the 7 built skills,
# down from 780,400 before. AC3 asked for a >=300KB drop, i.e. <=480,400 bytes.
#
# Raised to 500,000 in issue #252, which added ~16KB: the pre-commit security
# document and the naming-conventions document each gained the runtime contract
# for a shipped script (exit codes, degrade path, invocation), and those two
# docs are bundled into 2 and 5 skills respectively. That is content the skills
# execute, not content they merely carry.
#
# Raised to 506,000 in issue #255, which added the QA handoff marker: +610 bytes
# to idd-methodology.md (the marker as a durable-memory field, inside the
# digested *Analysis Artifacts* section), +228 to terminal-style.md (one line of
# marker vocabulary beside `gitissue:normalized`), +11 to platform-github.md
# (`headRefOid` in the canonical `gh pr view` field list). All three are bundled
# into 7 skills, so 849 authored bytes cost 5,943 here — and 5,943 is what the
# raise is for, measured, not estimated. Two things paid for part of it first:
# the marker prose deliberately names no `resolve.*` key inside
# /issue-pr-review (one mention would have pulled that whole config-schema
# section into its per-skill excerpt: +4,298 bytes, five times the change
# itself), and the *Analysis Artifacts* paragraph that restated #254's
# freshness predicate — a predicate it points at as living in one place — was
# compressed to the pointer.
#
# The raise deliberately restores the headroom that existed before, ~2.1KB, and
# does not widen it: this line is a ratchet, and the next addition should have
# to justify itself exactly as hard as this one did.
#
# Raised to 508,900 in issue #256, which added the *Caller-supplied context
# payloads* section to shared-agent-conventions.md — the single home of the rule
# that a caller-supplied payload field may gate duplicated work but never a
# safety gate, plus that document's exclusion list. Measured, not estimated:
# 1,960 authored bytes, which land as 1,971 in each bundled copy — the section
# cites docs/terminal-style.md once and the build rewrites that token to
# references/docs/…, +11 — bundled into 2 skills (auto-pilot, issue-resolver)
# = +3,942. Two smaller rows ride along: +11 to platform-github.md, bundled into
# 7 skills = +77; and +123 to config-schema.md — the adaptive_effort row (+96,
# carried by 3 excerpts) and the adaptive_depth row (+27, carried by 3) now
# disclosing the four #256 behaviours they switch off — = +369.
# Total +4,388 measured, from 504,224 to 508,612. That is content
# the skills execute: every #256 injection site points at the conventions
# section instead of restating the rule, so the alternative was the same
# paragraph duplicated across five files and drifting.
#
# One trap paid for part of it first, in the same shape #255 documented: the
# resolver's new triage prose originally spelled the artifact path
# `.gitissue/triage.json`, and _config_sections_used in scripts/build.py reads
# `triage.json` as a `triage.<key>` config reference — pulling the entire
# `triage` config section into the resolver's per-skill excerpt for +1,194
# bytes, none of which the resolver reads. The prose now names the triage graph
# without its filename; the researcher agent, which performs the read, still
# carries the exact path.
#
# The raise leaves 288 bytes of headroom, against the 1,776 that existed on main
# under the 506,000 line — this ratchet is tighter than the one it replaces, not
# a restored margin. The next addition does not fit without compressing
# something first, which is the whole point of the line.
#
# What the guard is actually for is unchanged and still has a wide margin:
# reinstating one whole document across the skills that excerpt it costs on the
# order of 165KB (config-schema.md is 27.5KB x 6 non-init skills), so a
# regression of that shape fails this assertion by more than 3x the headroom.
BUDGET=508900

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Bundled-doc slimming tests (issue #249)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ── AC1: no bundled doc without a runtime reference ──────────────────────────
# The build prints a ⚠ for every bundled doc a skill mentions only in its
# *Additional Resources* index or *Bundled dependency precheck* fence. A clean
# build is the assertion.
BUILD_LOG="$(mktemp)"
trap 'rm -f "$BUILD_LOG"' EXIT
if python3 "$REPO_ROOT/scripts/build.py" --out "$(mktemp -d)" --no-root-skills \
    >"$BUILD_LOG" 2>&1; then
  pass "AC1: build succeeds (closure, parity, and precheck-drift guards pass)"
else
  fail "AC1: build failed"
  sed 's/^/    /' "$BUILD_LOG" | head -10
fi
if grep -q "but no runtime instruction references it" "$BUILD_LOG"; then
  fail "AC1: a skill bundles a doc no runtime instruction references"
  grep "but no runtime instruction references it" "$BUILD_LOG" | sed 's/^/    /'
else
  pass "AC1: every bundled doc is referenced by a runtime instruction"
fi

# A doc reachable only through a shared agent must not be bundled: emitted agent
# prompts render their references as absolute repo URLs (issue #245), so the
# bundled copy would be unreferenceable.
if [ -f "$REPO_ROOT/skills/issue-triage/references/docs/shared-agent-conventions.md" ]; then
  fail "AC1: issue-triage bundles an agent-only doc (shared-agent-conventions.md)"
else
  pass "AC1: agent-only docs are not bundled into skills that never cite them"
fi

# ── AC2: run-log schema is its own runtime doc ───────────────────────────────
RUNLOG="$REPO_ROOT/docs/run-log-schema.md"
if [ -f "$RUNLOG" ]; then
  pass "AC2: docs/run-log-schema.md exists"
else
  fail "AC2: docs/run-log-schema.md missing"
fi
for skill in issue-resolver auto-pilot; do
  if [ -f "$REPO_ROOT/skills/$skill/references/docs/run-log-schema.md" ]; then
    pass "AC2: $skill bundles the run-log schema"
  else
    fail "AC2: $skill does not bundle the run-log schema"
  fi
done
# The resolver's run-log instructions must point at the small doc, not the schema.
REPORTS="$REPO_ROOT/src/skills/issue-resolver/references/report-templates.md"
if grep -q 'docs/run-log-schema.md' "$REPORTS" && \
   ! grep -q 'docs/config-schema.md' "$REPORTS"; then
  pass "AC2: resolver run-log fields derive from run-log-schema.md, not config-schema.md"
else
  fail "AC2: resolver still routes run-log field derivation through config-schema.md"
fi

# ── AC3: bundled-doc byte budget ─────────────────────────────────────────────
TOTAL=0
while IFS= read -r f; do
  size=$(wc -c < "$f" | tr -d ' ')
  TOTAL=$((TOTAL + size))
done < <(find "$REPO_ROOT/skills" -path '*/references/docs/*.md')
if [ "$TOTAL" -le "$BUDGET" ]; then
  pass "AC3: bundled-doc bytes within budget ($TOTAL ≤ $BUDGET)"
else
  fail "AC3: bundled-doc bytes over budget ($TOTAL > $BUDGET) — a doc is being bundled whole again"
  echo "    Every byte added to a doc under docs/ is paid once per skill that"
  echo "    bundles it: config-schema.md ships to 7, naming-conventions.md to 5."
  echo "    One added line is therefore 5-7 added lines here. Raising BUDGET is"
  echo "    not the fix — issue #249's AC3 asked for a >=300,000-byte cumulative"
  echo "    reduction, and the line has already moved once (480,000 -> 500,000 in"
  echo "    #252). Compress prose in the doc you grew, or excerpt it per skill."
fi

# ── Per-skill config excerpts ────────────────────────────────────────────────
# /init-gitissue renders .gitissue.yml and keeps the whole schema; every other
# skill gets only the sections it names.
INIT_SCHEMA="$REPO_ROOT/skills/init-gitissue/references/docs/config-schema.md"
TRIAGE_SCHEMA="$REPO_ROOT/skills/issue-triage/references/docs/config-schema.md"
if grep -q '^autopilot:' "$INIT_SCHEMA"; then
  pass "excerpt: init-gitissue keeps the complete schema"
else
  fail "excerpt: init-gitissue lost a schema section it needs to render .gitissue.yml"
fi
if grep -q '^triage:' "$TRIAGE_SCHEMA" && ! grep -q '^autopilot:' "$TRIAGE_SCHEMA"; then
  pass "excerpt: issue-triage carries triage but not autopilot"
else
  fail "excerpt: issue-triage config excerpt is not scoped to the sections it reads"
fi
if grep -qF 'Per-skill excerpt (generated)' "$TRIAGE_SCHEMA"; then
  pass "excerpt: the excerpt links back to the complete schema"
else
  fail "excerpt: the excerpt does not tell the reader where the full schema is"
fi

# ── Methodology runtime digest ───────────────────────────────────────────────
DIGEST="$REPO_ROOT/skills/issue-resolver/references/docs/idd-methodology.md"
if grep -q '^## Analysis Artifacts and Durable Memory' "$DIGEST" && \
   ! grep -q '^## IDD vs Other Methodologies' "$DIGEST"; then
  pass "digest: idd-methodology keeps its normative sections and drops the narrative"
else
  fail "digest: idd-methodology digest content is wrong"
fi
# The authored documents are untouched — humans still read them whole.
if grep -q '^## IDD vs Other Methodologies' "$REPO_ROOT/docs/idd-methodology.md"; then
  pass "digest: the authored docs/idd-methodology.md is unchanged"
else
  fail "digest: the authored document lost content — only the bundled copy may be slimmed"
fi

echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Bundled-doc slimming tests failed"
  exit 1
fi
echo "  ✓ Bundled-doc slimming contract holds"
exit 0
