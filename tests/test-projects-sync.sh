#!/usr/bin/env bash
# test-projects-sync.sh — Validate the GitHub Projects sync reference document
#
# This script checks the structural integrity of the projects sync utility
# and verifies that all skill integration points are documented correctly.
#
# Usage: bash tests/test-projects-sync.sh
# Returns: exit 0 if all tests pass, exit 1 on first failure

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

echo "◆ Projects Sync Utility Tests"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# T1: Shared reference document exists
if [ -f "$REPO_ROOT/docs/github-projects-sync.md" ]; then
  pass "T1: docs/github-projects-sync.md exists"
else
  fail "T1: docs/github-projects-sync.md not found"
fi

# T2: Reference document contains required sections
DOC="$REPO_ROOT/docs/github-projects-sync.md"
for section in "## Overview" "## Configuration" "## Procedures" "### 1. Discover Project" "### 2. Get Status Field" "### 3. Add Issue to Project" "### 4. Update Status" "## Graceful Degradation" "## Skill Integration Reference" "## Error Messages"; do
  if grep -q "$section" "$DOC" 2>/dev/null; then
    pass "T2: Section '$section' found in reference doc"
  else
    fail "T2: Section '$section' missing from reference doc"
  fi
done

# T3: Reference document contains GraphQL queries
for query in "addProjectV2ItemById" "updateProjectV2ItemFieldValue" "projectsV2" "ProjectV2SingleSelectField"; do
  if grep -q "$query" "$DOC" 2>/dev/null; then
    pass "T3: GraphQL reference '$query' found"
  else
    fail "T3: GraphQL reference '$query' missing"
  fi
done

# T4: Config schema includes projects section
CONFIG_DOC="$REPO_ROOT/docs/config-schema.md"
for field in "projects:" "sync_enabled:" "project_number:" "status_field:" "status_map:"; do
  if grep -q "$field" "$CONFIG_DOC" 2>/dev/null; then
    pass "T4: Config field '$field' found in config-schema.md"
  else
    fail "T4: Config field '$field' missing from config-schema.md"
  fi
done

# T5: Config defaults table includes projects entries
for entry in "projects.sync_enabled" "projects.project_number" "projects.status_field" "projects.status_map.todo" "projects.status_map.in_progress" "projects.status_map.done"; do
  if grep -q "$entry" "$CONFIG_DOC" 2>/dev/null; then
    pass "T5: Default entry '$entry' found in config-schema.md"
  else
    fail "T5: Default entry '$entry' missing from config-schema.md"
  fi
done

# T6: issue-creator SKILL.md references the projects sync utility
CREATOR="$REPO_ROOT/skills/issue-creator/SKILL.md"
if grep -q "github-projects-sync.md" "$CREATOR" 2>/dev/null; then
  pass "T6: issue-creator references github-projects-sync.md"
else
  fail "T6: issue-creator does not reference github-projects-sync.md"
fi

if grep -q "status_map.todo" "$CREATOR" 2>/dev/null; then
  pass "T6: issue-creator documents Todo status transition"
else
  fail "T6: issue-creator does not document Todo status transition"
fi

# T7: issue-resolver SKILL.md references the projects sync utility
RESOLVER="$REPO_ROOT/skills/issue-resolver/SKILL.md"
if grep -q "github-projects-sync.md" "$RESOLVER" 2>/dev/null; then
  pass "T7: issue-resolver references github-projects-sync.md"
else
  fail "T7: issue-resolver does not reference github-projects-sync.md"
fi

if grep -q "status_map.in_progress" "$RESOLVER" 2>/dev/null; then
  pass "T7: issue-resolver documents In Progress status transition"
else
  fail "T7: issue-resolver does not document In Progress transition"
fi

if grep -q "status_map.done" "$RESOLVER" 2>/dev/null; then
  pass "T7: issue-resolver documents Done status transition"
else
  fail "T7: issue-resolver does not document Done transition"
fi

# T8: issue-triage SKILL.md references the projects sync utility
TRIAGE="$REPO_ROOT/skills/issue-triage/SKILL.md"
if grep -q "github-projects-sync.md" "$TRIAGE" 2>/dev/null; then
  pass "T8: issue-triage references github-projects-sync.md"
else
  fail "T8: issue-triage does not reference github-projects-sync.md"
fi

if grep -q "read-only" "$TRIAGE" 2>/dev/null; then
  pass "T8: issue-triage documents read-only stance"
else
  fail "T8: issue-triage does not document read-only stance"
fi

# T9: Architecture doc references the shared utility
ARCH="$REPO_ROOT/docs/ARCHITECTURE.md"
if grep -q "github-projects-sync.md" "$ARCH" 2>/dev/null; then
  pass "T9: ARCHITECTURE.md references github-projects-sync.md"
else
  fail "T9: ARCHITECTURE.md does not reference github-projects-sync.md"
fi

if grep -q "Shared References" "$ARCH" 2>/dev/null; then
  pass "T9: ARCHITECTURE.md has Shared References section"
else
  fail "T9: ARCHITECTURE.md missing Shared References section"
fi

# T10: Graceful degradation is documented
if grep -q "sync_enabled.*false" "$DOC" 2>/dev/null; then
  pass "T10: Default sync_enabled is false (opt-in)"
else
  fail "T10: Default sync_enabled should be false"
fi

if grep -q "Non-fatal\|non-fatal\|non-blocking\|Non-blocking" "$DOC" 2>/dev/null; then
  pass "T10: Non-blocking behavior documented"
else
  fail "T10: Non-blocking behavior not documented"
fi

# T11: DESIGN.md symbols used in reference doc
for symbol in "●" "✓" "⚠" "○"; do
  if grep -q "$symbol" "$DOC" 2>/dev/null; then
    pass "T11: DESIGN.md symbol '$symbol' used in reference doc"
  else
    fail "T11: DESIGN.md symbol '$symbol' not found in reference doc"
  fi
done

# T12: Config section map in config-schema.md includes projects
if grep -q 'PR\["projects"\]' "$CONFIG_DOC" 2>/dev/null; then
  pass "T12: Config section map includes projects node"
else
  fail "T12: Config section map missing projects node"
fi

echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
else
  echo "  ✓ All tests passed"
  exit 0
fi
