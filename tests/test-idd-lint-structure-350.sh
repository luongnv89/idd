#!/usr/bin/env bash
# Regression coverage for issue #350: idd-lint structure without behavior drift.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$REPO_ROOT/scripts/idd-lint.py"

python3 - "$LINT" <<'PY'
import ast
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile

lint_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("idd_lint", lint_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

checks = 0


def check(condition, message):
    global checks
    if not condition:
        raise AssertionError(message)
    checks += 1
    print(f"  ✓ {message}")


expected_checks = (
    "_check_issue_marker",
    "_check_issue_type",
    "_check_issue_description",
    "_check_issue_type_fields",
    "_check_reporter_context",
    "_check_acceptance_criteria",
    "_check_issue_metadata",
    "_check_issue_dependencies",
    "_check_issue_hierarchy",
)
check(tuple(fn.__name__ for fn in module.ISSUE_CHECKS) == expected_checks,
      "lint_issue exposes the nine ordered per-check functions")

original_checks = module.ISSUE_CHECKS
called = []

def first(context):
    called.append(("first", context))
    return [module.ok("T01", "first")]

def second(context):
    called.append(("second", context))
    return [module.warn("T02", "second")]

module.ISSUE_CHECKS = (first, second)
dispatched = module.lint_issue("body")
module.ISSUE_CHECKS = original_checks
check([name for name, _ in called] == ["first", "second"],
      "lint_issue dispatches through ISSUE_CHECKS in table order")
check(called[0][1] is called[1][1],
      "all issue checks share one parsed context")
check([(f.code, f.severity) for f in dispatched] == [("T01", "ok"), ("T02", "warn")],
      "lint_issue preserves flattened finding order")

fixture = """<!-- gitissue:normalized v1 -->

## Type

Feature

## Description

Example.

## Acceptance Criteria

- [ ] Works

## Metadata

**Priority:** P2
**Effort:** S
**Labels:** feature
"""
check([(f.code, f.severity) for f in module.lint_issue(fixture)] == [
    ("I01", "ok"), ("I02", "ok"), ("I03", "ok"), ("I05", "warn"),
    ("I06", "ok"), ("I07", "ok"), ("I07", "ok"), ("I07", "ok"),
], "table-driven issue lint keeps the established finding sequence")

original_gh = module._gh_json
module._gh_json = lambda *args: [
    {"number": 1, "body": "<!-- gitissue:normalized v1 -->"},
    {"number": 2, "body": "plain"},
]
issue_stats = module.collect_issue_normalization_stats(20)
check(issue_stats == {
    "open_issues": 2,
    "open_normalized": 1,
    "open_normalized_pct": 50,
}, "issue-normalization collector is independently callable")

module._gh_json = lambda *args: [{
    "number": 7,
    "body": "Closes #7\n\n## Decision Record",
    "mergedAt": "2026-01-10T12:00:00Z",
    "mergeCommit": None,
}]
merged_stats = module.collect_merged_pr_stats(20, None)
check(merged_stats["merged_prs"] == 1
      and merged_stats["merged_with_closes"] == 1
      and merged_stats["merged_with_dr"] == 1
      and merged_stats["dr_binding"]["unresolved_no_sha"] == 1,
      "merged-PR collector preserves linkage and binding metrics")

with tempfile.TemporaryDirectory() as tmp:
    runs = Path(tmp) / "runs.jsonl"
    runs.write_text("\n".join((
        json.dumps({"issue": 1, "outcome": "success", "qa_cycles": 1}),
        json.dumps({"issue": 2, "outcome": "failed", "qa_cycles": 3}),
    )) + "\n", encoding="utf-8")
    module._gh_json = lambda *args: [
        {"number": 1, "body": "<!-- gitissue:normalized v1 -->"},
        {"number": 2, "body": "plain"},
    ]
    tier_stats = module.collect_run_tier_stats(20, runs)
check(tier_stats["tiers"]["normalized"] == {
    "runs": 1, "success_pct": 100, "median_qa": 1,
} and tier_stats["tiers"]["unnormalized"] == {
    "runs": 1, "success_pct": 0, "median_qa": 3,
} and tier_stats["qa_cycles_saved"] == 2,
      "run-tier collector preserves normalized outcome joins")
module._gh_json = original_gh

collector_calls = []
original_collectors = (
    module.collect_issue_normalization_stats,
    module.collect_merged_pr_stats,
    module.collect_run_tier_stats,
)
module.collect_issue_normalization_stats = lambda limit: collector_calls.append("issues") or {"open_issues": 0}
module.collect_merged_pr_stats = lambda limit, window: collector_calls.append("prs") or {"merged_prs": 0}
module.collect_run_tier_stats = lambda limit, path: collector_calls.append("tiers") or {"tiers": {}}
combined = module.collect_github_stats(20, Path("unused"))
(module.collect_issue_normalization_stats,
 module.collect_merged_pr_stats,
 module.collect_run_tier_stats) = original_collectors
check(collector_calls == ["issues", "prs", "tiers"],
      "collect_github_stats orchestrates all three collectors in order")
check(combined == {"open_issues": 0, "merged_prs": 0, "tiers": {}},
      "collect_github_stats combines collector results without reshaping")

render_calls = []
original_renderers = (
    module._render_stats_header,
    module._render_window_warning,
    module._render_git_history_stats,
    module._render_run_log_stats,
    module._render_github_stats,
)
module._render_stats_header = lambda project: render_calls.append("header") or ["header", ""]
module._render_window_warning = lambda window: render_calls.append("window") or ["window", ""]
module._render_git_history_stats = lambda stats: render_calls.append("git") or ["git"]
module._render_run_log_stats = lambda stats: render_calls.append("runs") or ["runs"]
module._render_github_stats = lambda stats, skipped: render_calls.append("github") or ["github"]
stream = io.StringIO()
with contextlib.redirect_stdout(stream):
    module.render_stats(None, None, None, None)
(module._render_stats_header,
 module._render_window_warning,
 module._render_git_history_stats,
 module._render_run_log_stats,
 module._render_github_stats) = original_renderers
check(render_calls == ["header", "window", "git", "runs", "github"],
      "render_stats delegates every report section to a render helper")
check(stream.getvalue() == "header\n\nwindow\n\ngit\n\nruns\n\ngithub\n\n" + "┄" * 59 + "\n",
      "render_stats retains section separators and newline ownership")

source = lint_path.read_text(encoding="utf-8")
tree = ast.parse(source)
old_literals = {40, 50, 57, 60, 72, 80, 200, 500}
violations = []
for node in ast.walk(tree):
    if isinstance(node, ast.Constant) and type(node.value) is int and node.value in old_literals:
        line = source.splitlines()[node.lineno - 1]
        if " = " not in line:
            violations.append((node.lineno, node.value, line.strip()))
check(not violations, f"old magic thresholds occur only in named constants: {violations}")

print(f"✓ {checks} checks passed")
PY
