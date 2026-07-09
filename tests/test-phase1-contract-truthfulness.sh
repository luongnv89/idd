#!/usr/bin/env bash
# Regression coverage for review findings fixed under issue #182.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

check_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -qE "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label"
  fi
}

RESOLVER="$REPO_ROOT/src/skills/issue-resolver/references/pipeline-steps.md"
ANALYSIS="$REPO_ROOT/src/skills/issue-analysis/SKILL.source.md"
TRIAGE="$REPO_ROOT/src/skills/issue-triage/references/detection.md"
SCANNER="$REPO_ROOT/src/shared/agents/issue-relationship-scanner.md"
TEMPLATE="$REPO_ROOT/src/skills/init-gitissue/templates/gitissue-template.yml"
DIST_RESOLVER="$REPO_ROOT/skills/issue-resolver/references/pipeline-steps.md"
DIST_ANALYSIS="$REPO_ROOT/skills/issue-analysis/SKILL.md"
DIST_TRIAGE="$REPO_ROOT/skills/issue-triage/references/detection.md"
DIST_TEMPLATE="$REPO_ROOT/skills/init-gitissue/templates/gitissue-template.yml"

for file in "$RESOLVER" "$ANALYSIS" "$TRIAGE" "$SCANNER" "$TEMPLATE" \
            "$DIST_RESOLVER" "$DIST_ANALYSIS" "$DIST_TRIAGE" "$DIST_TEMPLATE"; do
  if [ -f "$file" ]; then
    pass "exists: ${file#$REPO_ROOT/}"
  else
    fail "missing: ${file#$REPO_ROOT/}"
  fi
done

check_contains "$RESOLVER" 'resolve\.branch_prefix' \
  "F1 source derives worktree branch from resolve.branch_prefix"
check_contains "$RESOLVER" 'git worktree add -b "\$branch_name"' \
  "F1 source uses the derived branch for git worktree add"
check_contains "$DIST_RESOLVER" 'git worktree add -b "\$branch_name"' \
  "F1 generated resolver preserves derived worktree branch"

check_contains "$ANALYSIS" 'IDD_AUTO_MODE=1.*auto-pilot|auto-pilot.*IDD_AUTO_MODE=1' \
  "F2 source identifies automated empty-body analysis"
check_contains "$ANALYSIS" 'Continuing with title-only analysis \(limited confidence\)' \
  "F2 source continues title-only without an automated prompt"
check_contains "$DIST_ANALYSIS" 'Continuing with title-only analysis \(limited confidence\)' \
  "F2 generated analysis preserves title-only continuation"

check_contains "$SCANNER" 'gh pr view <N> --json files' \
  "F3 scanner fetches candidate merged-PR files"
check_contains "$SCANNER" '"merged_prs"' \
  "F3 scanner returns merged PR records"
check_contains "$SCANNER" '"changed_files"' \
  "F3 scanner returns changed-file mapping"
check_contains "$TRIAGE" 'history_scan\.merged_prs\[\]\.changed_files' \
  "F3 triage consumes changed-file mapping in post-merge"
check_contains "$DIST_TRIAGE" 'gh pr view <N> --json files' \
  "F3 generated triage preserves changed-file fetch"

for file in "$TEMPLATE" "$DIST_TEMPLATE"; do
  check_contains "$file" '^projects:' "F4 $(basename "$(dirname "$file")") template has projects section"
  check_contains "$file" '^  sync_enabled: false$' "F4 $(basename "$(dirname "$file")") has sync_enabled default"
  check_contains "$file" '^  project_number: null$' "F4 $(basename "$(dirname "$file")") has project_number default"
  check_contains "$file" '^  status_field: "Status"$' "F4 $(basename "$(dirname "$file")") has status_field default"
  check_contains "$file" '^  status_map:$' "F4 $(basename "$(dirname "$file")") has status_map defaults"
done

echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"

[ "$FAIL" -eq 0 ]
