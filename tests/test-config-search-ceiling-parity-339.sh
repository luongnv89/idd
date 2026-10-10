#!/usr/bin/env bash
# test-config-search-ceiling-parity-339.sh — bounded config discovery (#339).
#
# Verifies that gi-branch, gi-triage-graph, and gi-model-cache ignore a hostile
# ancestor config outside the working tree while still finding the repo-root
# config from a nested directory. It also guards the behavioral equivalence of
# gi-config's and gi-secscan's independently shipped cdup ceiling functions.
# Issue #537 adds the legacy `.gitissue.yml` fallback: all four walkers
# (gi-branch, gi-triage-graph, gi-model-cache, gi-secscan) read it only where a
# level has no `.idd.yml`, and never above the git root.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$REPO_ROOT" <<'PY'
from __future__ import annotations

import importlib.util
import json
import os
from datetime import date, timedelta
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(sys.argv[1])
SCRIPTS = ROOT / "src" / "shared" / "scripts"
BRANCH = SCRIPTS / "gi-branch.py"
GRAPH = SCRIPTS / "gi-triage-graph.py"
MODEL = SCRIPTS / "gi-model-cache.py"
GI_CONFIG = SCRIPTS / "gi-config.py"
SECSCAN = SCRIPTS / "gi-secscan.py"
SCHEMA = ROOT / "docs" / "config-schema.md"
SEED = ROOT / "src" / "skills" / "issue-creator" / "templates" / "model-data.json"

passed = 0
failed = 0


def emit(ok: bool, label: str) -> None:
    global passed, failed
    if ok:
        passed += 1
        print(f"  ✓ {label}")
    else:
        failed += 1
        print(f"  ✗ {label}")


def run(argv: list[str], cwd: Path, *, stdin: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=cwd,
        input=stdin,
        text=True,
        capture_output=True,
        check=False,
    )


def payload(
    proc: subprocess.CompletedProcess[str],
    label: str,
    expected_exits: tuple[int, ...] = (0,),
) -> dict[str, object]:
    if proc.returncode not in expected_exits:
        expected = "/".join(str(code) for code in expected_exits)
        emit(False, f"{label} exits {expected} (got {proc.returncode}: {proc.stderr.strip()})")
        return {}
    try:
        value = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        emit(False, f"{label} emits JSON ({exc.msg})")
        return {}
    if not isinstance(value, dict):
        emit(False, f"{label} emits one JSON object")
        return {}
    return value


def init_repo(path: Path) -> None:
    path.mkdir(parents=True)
    subprocess.run(["git", "init", "-q", str(path)], check=True)
    subprocess.run(["git", "-C", str(path), "config", "user.email", "test@example.com"], check=True)
    subprocess.run(["git", "-C", str(path), "config", "user.name", "Test"], check=True)


def graph_input() -> str:
    return json.dumps(
        {
            "issues": [
                {
                    "number": 1,
                    "title": "Fix fixture",
                    "type": "bug",
                    "createdAt": "2026-01-01T00:00:00Z",
                    "updatedAt": "2026-03-01T00:00:00Z",
                }
            ],
            "edges": [],
        }
    )


def make_skill_dir(path: Path) -> None:
    (path / "templates").mkdir(parents=True)
    shutil.copyfile(SEED, path / "templates" / "model-data.json")


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


print("◆ Config-search ceiling and parity (#339)")
print("┄" * 58)

with tempfile.TemporaryDirectory() as raw_tmp:
    tmp = Path(raw_tmp)
    ancestor = tmp / "ancestor"
    repo = ancestor / "repo"
    nested = repo / "nested" / "deep"
    init_repo(repo)
    nested.mkdir(parents=True)

    hostile = ancestor / ".idd.yml"
    hostile.write_text(
        "resolve:\n"
        "  branch_prefix: hostile/\n"
        "triage:\n"
        "  stale_threshold_days: 999\n"
        "  auto_priority: false\n"
        "model_suggestion:\n"
        "  cache_ttl_days: 999\n"
        "security:\n"
        "  allow_pattern: .*\n",
        encoding="utf-8",
    )

    branch = payload(
        run([sys.executable, str(BRANCH), "42", "--title", "Fix fixture", "--type", "bug"], nested),
        "gi-branch hostile-ancestor fixture",
    )
    emit(
        branch.get("branch") == "fix/42-fixture",
        "gi-branch ignores resolve.branch_prefix above the repo root",
    )

    graph = payload(
        run(
            [sys.executable, str(GRAPH), "--now", "2026-03-20T00:00:00Z"],
            nested,
            stdin=graph_input(),
        ),
        "gi-triage-graph hostile-ancestor fixture",
    )
    summary = graph.get("summary", {})
    first_issue = graph.get("issues", [{}])[0] if graph.get("issues") else {}
    emit(
        isinstance(summary, dict)
        and summary.get("stale_threshold_days") == 14
        and isinstance(first_issue, dict)
        and first_issue.get("priority") == "P1",
        "gi-triage-graph ignores triage settings above the repo root",
    )

    skill_dir = tmp / "skill"
    make_skill_dir(skill_dir)
    seed_day = date.fromisoformat(
        json.loads(SEED.read_text(encoding="utf-8"))["last_fetched"][:10]
    )
    fixture_now = (seed_day + timedelta(days=30)).isoformat()
    model = payload(
        run(
            [sys.executable, str(MODEL), "--skill-dir", str(skill_dir),
             "--cache-dir", str(tmp / "model-cache"), "--now", fixture_now],
            nested,
        ),
        "gi-model-cache hostile-ancestor fixture",
    )
    emit(
        model.get("stale") is True and model.get("ttl_days") == 7,
        "gi-model-cache ignores model_suggestion settings above the repo root",
    )

    root_config = repo / ".idd.yml"
    root_config.write_text(
        "resolve:\n"
        "  branch_prefix: team/\n"
        "triage:\n"
        "  stale_threshold_days: 60\n"
        "  auto_priority: false\n"
        "model_suggestion:\n"
        "  cache_ttl_days: 60\n",
        encoding="utf-8",
    )

    branch = payload(
        run([sys.executable, str(BRANCH), "42", "--title", "Fix fixture", "--type", "bug"], nested),
        "gi-branch repo-root fixture",
    )
    graph = payload(
        run(
            [sys.executable, str(GRAPH), "--now", "2026-03-20T00:00:00Z"],
            nested,
            stdin=graph_input(),
        ),
        "gi-triage-graph repo-root fixture",
    )
    model = payload(
        run(
            [sys.executable, str(MODEL), "--skill-dir", str(skill_dir),
             "--cache-dir", str(tmp / "model-cache"), "--now", fixture_now],
            nested,
        ),
        "gi-model-cache repo-root fixture",
    )
    graph_summary = graph.get("summary", {})
    graph_issue = graph.get("issues", [{}])[0] if graph.get("issues") else {}
    emit(
        branch.get("branch") == "team/42-fix-fixture",
        "gi-branch includes the repo-root config from a nested directory",
    )
    emit(
        isinstance(graph_summary, dict)
        and graph_summary.get("stale_threshold_days") == 60
        and isinstance(graph_issue, dict)
        and graph_issue.get("priority") is None,
        "gi-triage-graph includes the repo-root config from a nested directory",
    )
    emit(
        model.get("stale") is False and model.get("ttl_days") == 60,
        "gi-model-cache includes the repo-root config from a nested directory",
    )

    # The two independently shipped security-sensitive ceiling implementations
    # must answer identically for the same working directory. Cover nested/root
    # worktree positions and git's unavailable fallback.
    gi_config = load("idd_test_gi_config", GI_CONFIG)
    gi_secscan = load("idd_test_gi_secscan", SECSCAN)
    outside = tmp / "outside"
    outside.mkdir()
    cases = [(nested, repo), (repo, repo), (outside, outside)]
    old_cwd = Path.cwd()
    try:
        for cwd, expected in cases:
            os.chdir(cwd)
            config_ceiling = Path(gi_config.search_ceiling()).resolve()
            secscan_ceiling = Path(gi_secscan.config_search_ceiling()).resolve()
            emit(
                config_ceiling == secscan_ceiling == expected.resolve(),
                f"gi-config and gi-secscan ceilings agree at {cwd.name}",
            )
    finally:
        os.chdir(old_cwd)

    # Compare observable config behavior at the repository root on the same
    # fixture tree: an ancestor-only allow rule is ignored by both, while the
    # same rule inside the repo is honored by both.
    (repo / "docs").mkdir()
    shutil.copyfile(SCHEMA, repo / "docs" / "config-schema.md")
    root_config.unlink()
    (repo / ".env").write_text("fixture\n", encoding="utf-8")
    subprocess.run(["git", "-C", str(repo), "add", ".env"], check=True)

    config = payload(run([sys.executable, str(GI_CONFIG)], repo), "gi-config ancestor-only parity fixture")
    scan = payload(
        run([sys.executable, str(SECSCAN), "--staged", "--quiet"], repo),
        "gi-secscan ancestor-only parity fixture",
        (0, 1),
    )
    effective = config.get("config", {})
    emit(
        isinstance(effective, dict)
        and effective.get("security.allow_pattern") == ""
        and scan.get("verdict") == "block",
        "gi-config and gi-secscan both reject an ancestor-only allow rule",
    )

    root_config.write_text("security:\n  allow_pattern: ^\\.env$\n", encoding="utf-8")
    config = payload(run([sys.executable, str(GI_CONFIG)], repo), "gi-config repo-root parity fixture")
    scan = payload(
        run([sys.executable, str(SECSCAN), "--staged", "--quiet"], repo),
        "gi-secscan repo-root parity fixture",
    )
    effective = config.get("config", {})
    emit(
        isinstance(effective, dict)
        and effective.get("security.allow_pattern") == "^\\.env$"
        and scan.get("verdict") != "block"
        and scan.get("skipped", 0) >= 1,
        "gi-config and gi-secscan both honor the repo-root allow rule",
    )

# Issue #537: one observation per walker, from a nested directory — branch
# prefix (gi-branch), stale threshold (gi-triage-graph), cache TTL
# (gi-model-cache), and whether a probe value blocks (gi-secscan: only the
# legacy file's extra_secret_value_pattern makes it a secret; the fixture is on
# `main`, so a non-blocking verdict is `warn` for the protected branch).
print("┄ legacy .gitissue.yml fallback (#537)")
with tempfile.TemporaryDirectory() as raw_tmp:
    tmp = Path(raw_tmp)
    ancestor = tmp / "ancestor"
    repo = ancestor / "repo"
    nested = repo / "nested" / "deep"
    init_repo(repo)
    nested.mkdir(parents=True)
    skill_dir = tmp / "skill"
    make_skill_dir(skill_dir)
    seed_day = date.fromisoformat(
        json.loads(SEED.read_text(encoding="utf-8"))["last_fetched"][:10]
    )
    fixture_now = (seed_day + timedelta(days=30)).isoformat()
    (repo / "probe.txt").write_text("token=ZZPROBESECRET123456\n", encoding="utf-8")
    subprocess.run(["git", "-C", str(repo), "add", "probe.txt"], check=True)

    hostile_text = (
        "resolve:\n  branch_prefix: hostile/\n"
        "triage:\n  stale_threshold_days: 999\n"
        "model_suggestion:\n  cache_ttl_days: 999\n"
        "security:\n  allow_pattern: .*\n"
    )
    legacy_text = (
        "resolve:\n  branch_prefix: legacy/\n"
        "triage:\n  stale_threshold_days: 30\n"
        "model_suggestion:\n  cache_ttl_days: 30\n"
        "security:\n  extra_secret_value_pattern: \"ZZPROBESECRET[0-9]{6}\"\n"
    )
    new_text = (
        "resolve:\n  branch_prefix: team/\n"
        "triage:\n  stale_threshold_days: 60\n"
        "model_suggestion:\n  cache_ttl_days: 60\n"
    )

    def observe(label: str) -> tuple[tuple[object, ...], str]:
        procs = [
            run([sys.executable, str(BRANCH), "42", "--title", "Fix fixture", "--type", "bug"], nested),
            run([sys.executable, str(GRAPH), "--now", "2026-03-20T00:00:00Z"], nested, stdin=graph_input()),
            run([sys.executable, str(MODEL), "--skill-dir", str(skill_dir),
                 "--cache-dir", str(tmp / "model-cache"), "--now", fixture_now], nested),
            run([sys.executable, str(SECSCAN), "--staged", "--quiet"], nested),
        ]
        branch = payload(procs[0], f"gi-branch {label}")
        graph = payload(procs[1], f"gi-triage-graph {label}")
        model = payload(procs[2], f"gi-model-cache {label}")
        scan = payload(procs[3], f"gi-secscan {label}", (0, 1))
        summary = graph.get("summary", {})
        stale = summary.get("stale_threshold_days") if isinstance(summary, dict) else None
        seen = (branch.get("branch"), stale, model.get("ttl_days"), scan.get("verdict") == "block")
        return seen, "".join(proc.stderr for proc in procs)

    # Hostile config of BOTH names above the git root, nothing in the repo:
    # the ceiling applies to the legacy name exactly as to the new one.
    (ancestor / ".idd.yml").write_text(hostile_text, encoding="utf-8")
    (ancestor / ".gitissue.yml").write_text(hostile_text, encoding="utf-8")
    seen, _ = observe("hostile-ancestor (both names)")
    emit(
        seen == ("fix/42-fixture", 14, 7, False),
        f"all four walkers ignore .idd.yml and .gitissue.yml above the repo root {seen}",
    )

    # Repo-root legacy only, hostile `.idd.yml` above the root: the repo-root
    # legacy file wins — a new name outside the repo never outranks it.
    (ancestor / ".gitissue.yml").unlink()
    (repo / ".gitissue.yml").write_text(legacy_text, encoding="utf-8")
    seen, err = observe("repo-root legacy + hostile ancestor .idd.yml")
    emit(
        seen == ("legacy/42-fix-fixture", 30, 30, True),
        f"all four walkers read the repo-root .gitissue.yml over an ancestor .idd.yml {seen}",
    )
    emit(
        err.count("⚠ legacy .gitissue.yml found — rename to .idd.yml") == 4,
        "each walker prints the ⚠ legacy rename line once",
    )

    # Both names at the repo root: `.idd.yml` wins in every walker, so the
    # legacy file's secret pattern no longer applies.
    (repo / ".idd.yml").write_text(new_text, encoding="utf-8")
    seen, err = observe("both names at the repo root")
    emit(
        seen == ("team/42-fix-fixture", 60, 60, False),
        f"all four walkers prefer .idd.yml over .gitissue.yml at the same level {seen}",
    )
    emit(
        err.count("⚠ legacy .gitissue.yml ignored — .idd.yml takes precedence") == 4,
        "each walker reports the shadowed legacy file as ignored",
    )

    # New name only: unchanged behavior, no legacy warning.
    (repo / ".gitissue.yml").unlink()
    seen, err = observe("repo-root .idd.yml only")
    emit(
        seen == ("team/42-fix-fixture", 60, 60, False) and "legacy" not in err,
        f"all four walkers read a repo-root .idd.yml with no legacy warning {seen}",
    )

print(f"Result: {passed} passed, {failed} failed")
raise SystemExit(1 if failed else 0)
PY
