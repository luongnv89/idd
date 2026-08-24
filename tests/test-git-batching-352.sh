#!/usr/bin/env bash
# Regression and fork-count coverage for issue #352.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export IDD_REPO_ROOT="$REPO_ROOT"

python3 - <<'PY'
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(os.environ["IDD_REPO_ROOT"])
SECSCAN = ROOT / "src/shared/scripts/gi-secscan.py"
LINT = ROOT / "scripts/idd-lint.py"
REAL_GIT = shutil.which("git")
assert REAL_GIT is not None

checks = 0


def check(condition, message):
    global checks
    if not condition:
        raise AssertionError(message)
    checks += 1
    print(f"  ✓ {message}")


def git(repo, *args, input_bytes=None):
    proc = subprocess.run(
        [REAL_GIT, *args],
        cwd=repo,
        input=input_bytes,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        raise AssertionError(proc.stderr.decode("utf-8", "replace"))
    return proc.stdout.decode("utf-8", "replace").strip()


def init_repo(path):
    path.mkdir()
    git(path, "init", "-q", "-b", "feature", ".")
    git(path, "config", "user.email", "test@example.invalid")
    git(path, "config", "user.name", "test")
    (path / "base.txt").write_text("base\n", encoding="utf-8")
    git(path, "add", "base.txt")
    git(path, "commit", "-qm", "base")


def tracing_env(root, trace):
    fakebin = root / "fakebin"
    fakebin.mkdir(exist_ok=True)
    wrapper = fakebin / "git"
    wrapper.write_text(
        "#!/bin/sh\n"
        "{ printf '%s\\t' \"$@\"; printf '\\n'; } >> \"$IDD_GIT_TRACE\"\n"
        "exec \"$IDD_REAL_GIT\" \"$@\"\n",
        encoding="utf-8",
    )
    wrapper.chmod(0o755)
    env = os.environ.copy()
    env.pop("IDD_AUTO_MODE", None)
    env.update({
        "PATH": str(fakebin) + os.pathsep + env["PATH"],
        "IDD_REAL_GIT": REAL_GIT,
        "IDD_GIT_TRACE": str(trace),
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_CONFIG_SYSTEM": os.devnull,
    })
    return env


def commands(trace):
    if not trace.exists():
        return []
    return [line.split("\t") for line in trace.read_text(encoding="utf-8").splitlines()]


def count_command(rows, subcommand, required):
    return sum(
        1 for row in rows
        if subcommand in row and all(flag in row for flag in required)
    )


def expected_clean(scanned):
    return json.dumps({
        "verdict": "clean",
        "blocking": [],
        "warnings": [],
        "scanned": scanned,
        "skipped": 0,
        "policy_source": "defaults",
        "branch": "feature",
        "mode": "interactive",
        "confirm_required": False,
    }) + "\n"


def run_staged(size):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        repo = root / "repo"
        init_repo(repo)
        for index in range(size):
            (repo / f"staged-{index:03}.txt").write_text(
                f"clean staged payload {index}\n", encoding="utf-8"
            )
        git(repo, "add", *[f"staged-{index:03}.txt" for index in range(size)])
        trace = root / "trace"
        proc = subprocess.run(
            [sys.executable, str(SECSCAN), "--staged", "--quiet", "--no-config"],
            cwd=repo,
            env=tracing_env(root, trace),
            capture_output=True,
            check=False,
        )
        rows = commands(trace)
        check(proc.returncode == 0, f"staged N={size} scan exits clean")
        check(
            proc.stdout.decode() == expected_clean(size) and proc.stderr == b"",
            f"staged N={size} preserves exact clean stdout/stderr",
        )
        check(
            count_command(rows, "cat-file", ["--batch"]) == 1,
            f"staged N={size} uses one persistent cat-file --batch process",
        )
        check(
            count_command(rows, "cat-file", ["--batch-check"]) == 1,
            f"staged N={size} uses one batched size probe",
        )


def run_range(size):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        repo = root / "repo"
        init_repo(repo)
        base = git(repo, "rev-parse", "HEAD")
        for index in range(size):
            name = f"range-{index:03}.txt"
            (repo / name).write_text(f"clean range payload {index}\n", encoding="utf-8")
            git(repo, "add", name)
            git(repo, "commit", "-qm", f"range {index}")
        trace = root / "trace"
        proc = subprocess.run(
            [
                sys.executable,
                str(SECSCAN),
                "--range",
                base,
                "--quiet",
                "--no-config",
            ],
            cwd=repo,
            env=tracing_env(root, trace),
            capture_output=True,
            check=False,
        )
        rows = commands(trace)
        check(proc.returncode == 0, f"range N={size} scan exits clean")
        check(
            proc.stdout.decode() == expected_clean(size) and proc.stderr == b"",
            f"range N={size} preserves exact clean stdout/stderr",
        )
        check(
            count_command(rows, "diff-tree", ["--stdin"]) == 1,
            f"range N={size} uses one diff-tree --stdin process",
        )
        check(
            count_command(rows, "cat-file", ["--batch"]) == 1,
            f"range N={size} uses one persistent cat-file --batch process",
        )


secscan_spec = importlib.util.spec_from_file_location("gi_secscan_batch_test", SECSCAN)
secscan = importlib.util.module_from_spec(secscan_spec)
assert secscan_spec.loader is not None
secscan_spec.loader.exec_module(secscan)


def check_blob_protocol_resync():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        repo = root / "repo"
        init_repo(repo)
        binary = b"\0" + b"x" * (2 * 1024 * 1024)
        secret = ("AKIA" + "IOSFODNN7EXAMPLE").encode()
        (repo / "a-binary.dat").write_bytes(binary)
        (repo / "b-secret.txt").write_bytes(b"key=" + secret + b"\n")
        (repo / "c-same-blob.txt").write_bytes(b"key=" + secret + b"\n")
        git(repo, "add", "a-binary.dat", "b-secret.txt", "c-same-blob.txt")
        trace = root / "trace"
        proc = subprocess.run(
            [
                sys.executable,
                str(SECSCAN),
                "--staged",
                "--quiet",
                "--no-config",
                "--emit-sources",
            ],
            cwd=repo,
            env=tracing_env(root, trace),
            capture_output=True,
            check=False,
        )
        verdict = json.loads(proc.stdout)
        sources = {item["path"]: item for item in verdict["sources"]}
        blocked = {
            item["path"]
            for item in verdict["blocking"]
            if item["rule"] == "secret-value"
        }
        check(
            proc.returncode == 1 and blocked == {"b-secret.txt", "c-same-blob.txt"},
            "batch protocol resynchronizes after an early binary decision",
        )
        check(
            sources["a-binary.dat"]["decided_early"]
            and sources["a-binary.dat"]["bytes_read"] == 8192,
            "protocol drain does not change emit-sources scan accounting",
        )
        check(
            sources["b-secret.txt"]["id"] == sources["c-same-blob.txt"]["id"],
            "duplicate blob ids under distinct paths are both scanned",
        )
        check(
            count_command(commands(trace), "cat-file", ["--batch"]) == 1,
            "early and duplicate blobs stay on one cat-file --batch process",
        )


def check_range_parity():
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp) / "repo"
        init_repo(repo)
        base = git(repo, "rev-parse", "HEAD")
        git(repo, "checkout", "-qb", "side", base)
        odd_name = "odd\nname.txt"
        (repo / odd_name).write_text("side\n", encoding="utf-8")
        git(repo, "add", odd_name)
        git(repo, "commit", "-qm", "side")
        git(repo, "checkout", "-q", "feature")
        (repo / "main.txt").write_text("main\n", encoding="utf-8")
        git(repo, "add", "main.txt")
        git(repo, "commit", "-qm", "main")
        git(repo, "merge", "--no-ff", "-qm", "merge", "side")
        old_cwd = os.getcwd()
        try:
            os.chdir(repo)
            commits = secscan._split_lines(
                secscan._git(["rev-list", f"{base}..HEAD", "--"])
            )
            sequential = []
            for commit in commits:
                sequential += secscan._raw_targets(
                    secscan._git([
                        "diff-tree", "-r", "-m", "--root", "--raw", "-z",
                        "--no-abbrev", "--no-commit-id", commit,
                    ]),
                    f"legacy {commit}",
                )
            sequential = secscan._dedupe_targets(sequential)
            batched = secscan._range_targets(base)
        finally:
            os.chdir(old_cwd)
        check(
            batched == sequential,
            "diff-tree --stdin preserves merge, unusual-path, order, and dedupe semantics",
        )


spec = importlib.util.spec_from_file_location("idd_lint_batch_test", LINT)
lint = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(lint)


def run_lint(size):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        repo = root / "repo"
        init_repo(repo)
        prs = []
        landed = 0
        lost = 0
        for index in range(size):
            has_dr = index % 2 == 0
            message = f"change {index}\n\n" + ("## Decision Record\n" if has_dr else "plain\n")
            (repo / "history.txt").write_text(f"{index}\n", encoding="utf-8")
            git(repo, "add", "history.txt")
            git(repo, "commit", "-qm", message)
            oid = git(repo, "rev-parse", "HEAD")
            prs.append({
                "number": index + 1,
                "body": "Closes #1\n\n## Decision Record",
                "mergedAt": "2026-08-24T00:00:00Z",
                "mergeCommit": {"oid": oid},
            })
            if has_dr:
                landed += 1
            else:
                lost += 1
        first_oid = prs[0]["mergeCommit"]["oid"]
        prs.extend((
            {
                "number": size + 1,
                "body": "Closes #1\n\n## Decision Record",
                "mergedAt": "2026-08-24T00:00:00Z",
                "mergeCommit": None,
            },
            {
                "number": size + 2,
                "body": "Closes #1\n\n## Decision Record",
                "mergedAt": "2026-08-24T00:00:00Z",
                "mergeCommit": {"oid": "0" * 40},
            },
            {
                "number": size + 3,
                "body": "Closes #1\n\n## Decision Record",
                "mergedAt": "2026-08-24T00:00:00Z",
                "mergeCommit": {"oid": first_oid},
            },
        ))
        landed += 1
        trace = root / "trace"
        old_cwd = os.getcwd()
        old_path = os.environ.get("PATH")
        old_real = os.environ.get("IDD_REAL_GIT")
        old_trace = os.environ.get("IDD_GIT_TRACE")
        env = tracing_env(root, trace)
        try:
            os.chdir(repo)
            os.environ.update({
                "PATH": env["PATH"],
                "IDD_REAL_GIT": env["IDD_REAL_GIT"],
                "IDD_GIT_TRACE": env["IDD_GIT_TRACE"],
            })
            result = lint.collect_dr_binding(prs, 200, None)
        finally:
            os.chdir(old_cwd)
            if old_path is not None:
                os.environ["PATH"] = old_path
            for key, value in (("IDD_REAL_GIT", old_real), ("IDD_GIT_TRACE", old_trace)):
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
        rows = commands(trace)
        old_cwd = os.getcwd()
        try:
            os.chdir(repo)
            compatibility = (
                lint.classify_merge_commit("HEAD"),
                lint.classify_merge_commit(first_oid[:8]),
                lint.classify_merge_commit(None),
            )
        finally:
            os.chdir(old_cwd)
        check(
            compatibility
            == (
                "landed" if (size - 1) % 2 == 0 else "lost",
                "landed",
                "no_sha",
            ),
            f"single-commit compatibility keeps HEAD and abbreviated oid support",
        )
        check(
            (result["dr_landed"], result["dr_lost"]) == (landed, lost)
            and result["unresolved_no_sha"] == 1
            and result["unresolved_not_in_clone"] == 1,
            f"lint N={size} preserves landed/lost/unresolved buckets: {result}",
        )
        check(
            count_command(rows, "log", ["--no-walk=unsorted", "--stdin"]) == 1,
            f"lint N={size} uses one git log --no-walk=unsorted --stdin process",
        )


for n in (1, 50):
    run_staged(n)
    run_range(n)
    run_lint(n)
check_blob_protocol_resync()
check_range_parity()

print(f"✓ {checks} batching and behavior checks passed")
PY
