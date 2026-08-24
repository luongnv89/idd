#!/usr/bin/env python3
"""Grade an eval case with deterministic tools (idd-lint, gi-runlog).

Usage:
  python3 evals/harness/grade.py --case <case-dir> --out <artifact-dir>

Reads case.json ``grade`` section. Substitutes OUT → artifact dir in args.
Prints ✓/✗ per assertion; exits 1 if any fail. Stdlib only.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any


def _repo_root() -> Path:
    env = os.environ.get("REPO_ROOT")
    if env:
        return Path(env).resolve()
    # evals/harness/grade.py → repo root is parents[2]
    return Path(__file__).resolve().parents[2]


def _sub_out(value: str, out_dir: Path) -> str:
    """Replace the OUT path token only as a path root, not as a bare substring.

    Matches ``OUT`` at the start of the string or after a non-identifier char,
    and only when followed by ``/``, end-of-string, or a path-ish boundary.
    Avoids corrupting tokens like ``OUTPUT.md`` or ``TIMEOUT``.
    """
    out = str(out_dir)
    # OUT/… or standalone OUT (not OUTPUTish, not embedded in identifiers)
    return re.sub(r"(?<![A-Za-z0-9_])OUT(?=/|$|[^A-Za-z0-9_])", out, value)


def _run(cmd: list[str], *, stdin_data: str | None = None, cwd: Path) -> int | None:
    try:
        proc = subprocess.run(  # noqa: S603
            cmd,
            input=stdin_data,
            text=True,
            capture_output=True,
            cwd=str(cwd),
        )
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"    │ unable to run grading tool: {exc}")
        return None
    # Surface tool output lightly for debugging failed grades.
    if proc.returncode != 0 and (proc.stdout or proc.stderr):
        for line in (proc.stdout + proc.stderr).splitlines()[:20]:
            print(f"    │ {line}")
    return proc.returncode


def _out_artifact(token: str, out_dir: Path) -> Path | None:
    """Resolve a constrained OUT-relative artifact without allowing traversal."""
    if not re.fullmatch(r"OUT/[A-Za-z0-9._/-]+", token):
        return None
    path = Path(_sub_out(token, out_dir)).resolve()
    try:
        path.relative_to(out_dir)
    except ValueError:
        return None
    if ".." in Path(token).parts:
        return None
    return path


def _read_shell_artifact_value(artifact: Path) -> tuple[str | None, str | None]:
    """Read a small UTF-8 artifact safely before placing it in an argv entry."""
    try:
        data = artifact.read_bytes()
    except OSError as exc:
        return None, f"cannot read OUT artifact: {exc}"
    if len(data) > 64 * 1024:
        return None, "OUT artifact exceeds the 64 KiB argv limit"
    try:
        value = data.decode("utf-8")
    except UnicodeDecodeError:
        return None, "OUT artifact is not valid UTF-8"
    if "\0" in value:
        return None, "OUT artifact contains a NUL byte"
    return value.replace("\n", ""), None


def _allowlisted_shell_command(
    args: Any,
    *,
    out_dir: Path,
    repo_root: Path,
) -> tuple[list[str] | None, str | None]:
    """Translate legacy shell assertions into fixed argv without running a shell."""
    if not isinstance(args, list) or len(args) != 1 or not isinstance(args[0], str):
        return None, "shell requires exactly one command string"
    try:
        tokens = shlex.split(args[0])
    except ValueError as exc:
        return None, f"invalid shell assertion: {exc}"

    prefix = ["python3", "scripts/idd-lint.py"]
    substitution = re.compile(r"\$\(tr -d '\\n' < (OUT/[A-Za-z0-9._/-]+)\)")
    lint = [sys.executable, str(repo_root / "scripts" / "idd-lint.py")]

    if len(tokens) == 4 and tokens[:2] == prefix and tokens[2] in {"branch", "commit"}:
        match = substitution.fullmatch(tokens[3])
        artifact = _out_artifact(match.group(1), out_dir) if match else None
        if artifact is None or not artifact.is_file():
            return None, "branch/commit assertion requires a readable OUT artifact"
        value, error = _read_shell_artifact_value(artifact)
        if value is None:
            return None, error
        return [*lint, tokens[2], value], None

    if len(tokens) == 6 and tokens[:3] == [*prefix, "pr"] and tokens[4] == "--title":
        body = _out_artifact(tokens[3], out_dir)
        match = substitution.fullmatch(tokens[5])
        title = _out_artifact(match.group(1), out_dir) if match else None
        if body is None or title is None or not body.is_file() or not title.is_file():
            return None, "PR assertion requires readable body and title OUT artifacts"
        title_value, error = _read_shell_artifact_value(title)
        if title_value is None:
            return None, error
        return [*lint, "pr", str(body), "--title", title_value], None

    return None, "command is not in the shell assertion allowlist"


def _grade_one(
    assertion: dict[str, Any],
    *,
    out_dir: Path,
    repo_root: Path,
) -> bool:
    tool = assertion.get("tool")
    expect = int(assertion.get("expect_exit", 0))
    label = assertion.get("label") or f"{tool} expect_exit={expect}"

    if tool == "idd-lint":
        args = assertion.get("args") or []
        if not isinstance(args, list):
            print(f"  ✗ {label} — args must be a list")
            return False
        resolved = [_sub_out(str(a), out_dir) for a in args]
        cmd = [sys.executable, str(repo_root / "scripts" / "idd-lint.py"), *resolved]
        got = _run(cmd, cwd=repo_root)
    elif tool == "gi-runlog-echo":
        file_rel = assertion.get("file")
        if not file_rel:
            print(f"  ✗ {label} — gi-runlog-echo requires 'file'")
            return False
        path = Path(_sub_out(str(file_rel), out_dir))
        if not path.is_file():
            print(f"  ✗ {label} — missing file {path}")
            return False
        payload = path.read_text(encoding="utf-8")
        cmd = [
            sys.executable,
            str(repo_root / "src" / "shared" / "scripts" / "gi-runlog.py"),
            "--echo",
        ]
        got = _run(cmd, stdin_data=payload, cwd=repo_root)
    elif tool == "file-exists":
        file_rel = assertion.get("file") or (assertion.get("args") or [None])[0]
        if not file_rel:
            print(f"  ✗ {label} — file-exists requires 'file'")
            return False
        path = Path(_sub_out(str(file_rel), out_dir))
        got = 0 if path.is_file() else 1
    elif tool == "red-green":
        file_rel = assertion.get("file")
        if not file_rel:
            print(f"  ✗ {label} — red-green requires 'file'")
            return False
        path = Path(_sub_out(str(file_rel), out_dir))
        try:
            evidence = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            print(f"  ✗ {label} — invalid red-green JSON: {exc}")
            return False
        if not isinstance(evidence, dict):
            print(f"  ✗ {label} — red-green evidence must be a JSON object")
            return False
        expected = {"red_exit": 1, "green_exit": 0}
        got_evidence = {
            "red_exit": evidence.get("red_exit"),
            "green_exit": evidence.get("green_exit"),
        }
        valid_types = all(type(evidence.get(key)) is int for key in expected)
        got = (
            0
            if valid_types
            and got_evidence == expected
            and set(evidence) == set(expected)
            else 1
        )
    elif tool == "shell":
        cmd, error = _allowlisted_shell_command(
            assertion.get("args"), out_dir=out_dir, repo_root=repo_root
        )
        if cmd is None:
            print(f"  ✗ {label} — rejected before execution: {error}")
            return False
        got = _run(cmd, cwd=repo_root)
    else:
        print(f"  ✗ {label} — unknown tool {tool!r}")
        return False

    if got == expect:
        print(f"  ✓ {label}")
        return True
    print(f"  ✗ {label} (want exit {expect}, got {got})")
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description="Grade a behavioral eval case")
    parser.add_argument("--case", required=True, help="case directory with case.json")
    parser.add_argument("--out", required=True, help="artifact/output directory")
    args = parser.parse_args()

    case_dir = Path(args.case).resolve()
    out_dir = Path(args.out).resolve()
    case_json = case_dir / "case.json"
    if not case_json.is_file():
        print(f"✗ missing case.json: {case_json}", file=sys.stderr)
        return 2

    case = json.loads(case_json.read_text(encoding="utf-8"))
    name = case.get("name") or case_dir.name
    grades = case.get("grade") or []
    if not isinstance(grades, list) or not grades:
        print(f"✗ case {name}: grade section missing or empty", file=sys.stderr)
        return 2

    repo_root = _repo_root()
    print(f"◆ grade {name}")
    print("┄" * 40)

    ok = 0
    bad = 0
    for assertion in grades:
        if not isinstance(assertion, dict):
            print("  ✗ non-object grade assertion")
            bad += 1
            continue
        if _grade_one(assertion, out_dir=out_dir, repo_root=repo_root):
            ok += 1
        else:
            bad += 1

    print("┄" * 40)
    if bad:
        print(f"✗ grade failed: {ok} passed, {bad} failed")
        return 1
    print(f"✓ grade passed: {ok} assertions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
