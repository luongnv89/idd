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

check_not_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -qE "$pattern" "$file"; then
    fail "$label"
  else
    pass "$label"
  fi
}

RESOLVER="$REPO_ROOT/src/skills/issue-resolver/references/pipeline-steps.md"
ANALYSIS="$REPO_ROOT/src/skills/issue-analysis/SKILL.source.md"
ANALYSIS_STEPS="$REPO_ROOT/src/skills/issue-analysis/references/subagent-steps.md"
ANALYSIS_OUTPUT="$REPO_ROOT/src/skills/issue-analysis/references/output-and-persist.md"
REVIEW="$REPO_ROOT/src/skills/issue-pr-review/SKILL.source.md"
REVIEW_REPORTS="$REPO_ROOT/src/skills/issue-pr-review/references/report-templates.md"
CONFIG="$REPO_ROOT/docs/config-schema.md"
TRIAGE_SKILL="$REPO_ROOT/src/skills/issue-triage/SKILL.source.md"
TRIAGE="$REPO_ROOT/src/skills/issue-triage/references/detection.md"
SCANNER="$REPO_ROOT/src/shared/agents/issue-relationship-scanner.md"
TEMPLATE="$REPO_ROOT/src/skills/init-gitissue/templates/gitissue-template.yml"
DIST_RESOLVER="$REPO_ROOT/skills/issue-resolver/references/pipeline-steps.md"
DIST_ANALYSIS="$REPO_ROOT/skills/issue-analysis/SKILL.md"
DIST_ANALYSIS_STEPS="$REPO_ROOT/skills/issue-analysis/references/subagent-steps.md"
DIST_REVIEW="$REPO_ROOT/skills/issue-pr-review/SKILL.md"
DIST_TRIAGE="$REPO_ROOT/skills/issue-triage/references/detection.md"
DIST_TRIAGE_SCANNER="$REPO_ROOT/skills/issue-triage/references/agents/issue-relationship-scanner.md"
DIST_TEMPLATE="$REPO_ROOT/skills/init-gitissue/templates/gitissue-template.yml"

for file in "$RESOLVER" "$ANALYSIS" "$ANALYSIS_STEPS" "$ANALYSIS_OUTPUT" \
            "$REVIEW" "$REVIEW_REPORTS" "$CONFIG" "$TRIAGE_SKILL" "$TRIAGE" \
            "$SCANNER" "$TEMPLATE" "$DIST_RESOLVER" "$DIST_ANALYSIS" \
            "$DIST_ANALYSIS_STEPS" "$DIST_REVIEW" "$DIST_TRIAGE" \
            "$DIST_TRIAGE_SCANNER" "$DIST_TEMPLATE"; do
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
check_contains "$RESOLVER" 'git branch -D "\$branch_name"' \
  "F1 source cleanup deletes the derived worktree branch"
check_contains "$DIST_RESOLVER" 'git branch -D "\$branch_name"' \
  "F1 generated cleanup deletes the derived worktree branch"

check_contains "$ANALYSIS" 'IDD_AUTO_MODE=1.*auto-pilot|auto-pilot.*IDD_AUTO_MODE=1' \
  "F2 source identifies automated empty-body analysis"
check_contains "$ANALYSIS" 'Continuing with title-only analysis \(limited confidence\)' \
  "F2 source continues title-only without an automated prompt"
check_contains "$DIST_ANALYSIS" 'Continuing with title-only analysis \(limited confidence\)' \
  "F2 generated analysis preserves title-only continuation"
check_contains "$ANALYSIS_STEPS" '`"auto"` when `IDD_AUTO_MODE=1` or the analysis was delegated by `/auto-pilot`' \
  "F2 source sends noninteractive synthesis mode under auto delegation"
check_contains "$ANALYSIS_STEPS" 'otherwise set it to `"interactive"`' \
  "F2 source retains interactive synthesis mode outside auto delegation"
check_contains "$DIST_ANALYSIS_STEPS" 'synthesizer must run noninteractively' \
  "F2 generated analysis preserves noninteractive synthesis behavior"

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
check_contains "$SCANNER" '`references` preserves each reference' \
  "F3 scanner retains reference-source metadata"
check_contains "$SCANNER" '`target_issues` identifies the PR' \
  "F3 scanner retains PR target metadata"
check_contains "$TRIAGE" 'Never promote a title or branch reference' \
  "F3 triage rejects title and branch evidence"
check_contains "$TRIAGE" 'never promote an issue that is itself a PR target' \
  "F3 triage rejects PR-target self-promotion"
check_contains "$TRIAGE" 'source: "body"' \
  "F3 triage permits body evidence only with a distinct target"
check_contains "$DIST_TRIAGE" 'Never promote a title or branch reference' \
  "F3 generated triage preserves safe overlap promotion"

for file in "$TEMPLATE" "$DIST_TEMPLATE"; do
  check_contains "$file" '^projects:' "F4 $(basename "$(dirname "$file")") template has projects section"
  check_contains "$file" '^  sync_enabled: false$' "F4 $(basename "$(dirname "$file")") has sync_enabled default"
  check_contains "$file" '^  project_number: null$' "F4 $(basename "$(dirname "$file")") has project_number default"
  check_contains "$file" '^  status_field: "Status"$' "F4 $(basename "$(dirname "$file")") has status_field default"
  check_contains "$file" '^  status_map:$' "F4 $(basename "$(dirname "$file")") has status_map defaults"
done

check_contains "$REVIEW" 'review\.soft_pass: false.*strict mode' \
  "F5 review soft_pass false defines strict mode"
check_contains "$REVIEW" 'zero remaining `action: "note"` findings' \
  "F5 strict mode blocks note findings"
check_contains "$REVIEW" '`partial` dimension.*strict blocker' \
  "F5 strict mode blocks partial dimensions"
check_contains "$REVIEW_REPORTS" 'strict pass not reached' \
  "F5 report template renders strict blockers"
check_contains "$CONFIG" 'partial/note findings remain blockers' \
  "F5 config schema documents strict false behavior"
check_contains "$DIST_REVIEW" 'zero remaining `action: "note"` findings' \
  "F5 generated review preserves strict notes gate"

check_contains "$SCANNER" '"dependency".*"history".*"both"' \
  "F6 scanner accepts dependency history both scope"
check_contains "$SCANNER" 'Run this part only when `scope` is `"dependency"` or `"both"`' \
  "F6 scanner gates dependency work by scope"
check_contains "$SCANNER" 'Run this part only when `scope` is `"history"` or `"both"`' \
  "F6 scanner gates history work by scope"
check_contains "$TRIAGE_SKILL" 'one issue-relationship-scanner subagent per batch' \
  "F6 triage uses one scanner per batch"
check_contains "$TRIAGE" 'scope: "both"' \
  "F6 triage passes full scanner scope"
check_not_contains "$TRIAGE_SKILL" 'two parallel scans per batch|paired\*\* history' \
  "F6 triage no longer duplicates scanner work per batch"
check_contains "$DIST_TRIAGE_SCANNER" 'scope.*"both"' \
  "F6 generated scanner preserves scope contract"

for status in already_resolved pr_in_progress possibly_already_fixed; do
  check_contains "$ANALYSIS_STEPS" "status\\.${status}" \
    "F7 analysis handles researcher status ${status}"
  check_contains "$ANALYSIS_OUTPUT" "research_status\\.${status}" \
    "F7 analysis persists researcher status ${status}"
done
check_contains "$ANALYSIS_STEPS" 'scan_stats\.scan_timed_out' \
  "F7 analysis persists and warns on scan timeout"
check_contains "$ANALYSIS_STEPS" 'docs/agent-model-effort\.md' \
  "F7 analysis selects synthesizer tier from researcher complexity"
check_contains "$ANALYSIS_OUTPUT" 'scan_timed_out' \
  "F7 persisted schema includes timeout flag"
check_contains "$DIST_ANALYSIS_STEPS" 'status\.already_resolved' \
  "F7 generated analysis preserves status handling"

echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"

[ "$FAIL" -eq 0 ]
