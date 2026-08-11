#!/usr/bin/env python3
"""PATH-fronted `gh` record/replay shim for hermetic behavioral evals.

When installed as the first `gh` on PATH (see run_eval.sh), this script
satisfies skill-shaped `gh` invocations without opening a network socket.

Environment
  EVAL_CASSETTES   path to cassettes.json (required in replay mode)
  EVAL_STATE_DIR   optional mutable state for issue create / sequential IDs
  EVAL_RECORD=1    local capture only: unmatched calls run real `gh` and
                   append to the cassette. NEVER enable in CI — tests fail
                   closed when this is set.

Cassette format (version 1)::

    {
      "version": 1,
      "calls": [
        {
          "argv": ["issue", "view", "1", "--json", "number,title"],
          "stdout": "{...}\\n",
          "stderr": "",
          "exit": 0
        },
        {
          "match": "prefix",
          "argv": ["auth", "status"],
          "stdout": "github.com\\n  ✓ Logged in\\n",
          "exit": 0
        }
      ]
    }

Matching: exact argv preferred; ``match: "prefix"`` matches a leading
prefix. Comma-separated field lists after ``--json`` are compared after
sorting field names so order does not matter.

Data-producing commands that skills use (``issue view/list``, ``pr view/list``,
``pr checks``, ``api``) require ``--json``; missing ``--json`` exits 2, matching
platform-github.md.

Never opens network sockets in replay mode. Stdlib only.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

# Commands that must carry --json when used for data retrieval.
JSON_REQUIRED_PREFIXES: tuple[tuple[str, ...], ...] = (
    ("issue", "view"),
    ("issue", "list"),
    ("pr", "view"),
    ("pr", "list"),
    ("pr", "checks"),
    ("api",),
)

HELP_TEXT = """\
gh — eval harness shim (record/replay)

Usage:
  gh <command> [flags]

This is not the real GitHub CLI. It replays canned responses from
EVAL_CASSETTES. Set EVAL_RECORD=1 only for local capture (never in CI).

Common skill commands: issue view/list/create, pr view/list/create/checks, auth status, api.
"""


def _eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def _normalize_argv(argv: list[str]) -> list[str]:
    """Normalize argv for comparison: sort --json field lists."""
    out: list[str] = []
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--json" and i + 1 < len(argv):
            fields = argv[i + 1]
            sorted_fields = ",".join(sorted(f.strip() for f in fields.split(",") if f.strip()))
            out.append("--json")
            out.append(sorted_fields)
            i += 2
            continue
        if arg.startswith("--json="):
            fields = arg.split("=", 1)[1]
            sorted_fields = ",".join(sorted(f.strip() for f in fields.split(",") if f.strip()))
            out.append(f"--json={sorted_fields}")
            i += 1
            continue
        out.append(arg)
        i += 1
    return out


def _has_json_flag(argv: list[str]) -> bool:
    for i, arg in enumerate(argv):
        if arg == "--json" and i + 1 < len(argv):
            return True
        if arg.startswith("--json="):
            return True
    return False


def _requires_json(argv: list[str]) -> bool:
    for prefix in JSON_REQUIRED_PREFIXES:
        if len(argv) >= len(prefix) and tuple(argv[: len(prefix)]) == prefix:
            return True
    return False


def _load_cassettes(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise SystemExit("cassette root must be a JSON object")
    if data.get("version") not in (1, None):
        raise SystemExit(f"unsupported cassette version: {data.get('version')!r}")
    calls = data.get("calls")
    if not isinstance(calls, list):
        raise SystemExit("cassette.calls must be a list")
    return data


def _match_call(argv: list[str], calls: list[dict[str, Any]]) -> dict[str, Any] | None:
    """Match argv against cassettes — exact entries always beat prefix entries.

    Two-pass on purpose: a leading ``match: "prefix"`` cassette must not steal a
    later exact match for a longer command (e.g. prefix ``["pr"]`` vs exact
    ``["pr", "view", "1", ...]``).
    """
    norm = _normalize_argv(argv)
    # Pass 1: exact matches only.
    for call in calls:
        if not isinstance(call, dict):
            continue
        c_argv = call.get("argv")
        if not isinstance(c_argv, list):
            continue
        c_norm = _normalize_argv([str(x) for x in c_argv])
        match_mode = call.get("match", "exact")
        if match_mode == "prefix":
            continue
        if norm == c_norm:
            return call
    # Pass 2: prefix matches (longest-prefix wins among prefix entries).
    best: dict[str, Any] | None = None
    best_len = -1
    for call in calls:
        if not isinstance(call, dict):
            continue
        c_argv = call.get("argv")
        if not isinstance(c_argv, list):
            continue
        c_norm = _normalize_argv([str(x) for x in c_argv])
        if call.get("match", "exact") != "prefix":
            continue
        if len(norm) >= len(c_norm) and norm[: len(c_norm)] == c_norm:
            if len(c_norm) > best_len:
                best = call
                best_len = len(c_norm)
    return best


def _state_dir() -> Path | None:
    raw = os.environ.get("EVAL_STATE_DIR")
    if not raw:
        return None
    p = Path(raw)
    p.mkdir(parents=True, exist_ok=True)
    return p


def _next_issue_number(state: Path) -> int:
    counter = state / "issue_counter"
    if counter.exists():
        n = int(counter.read_text(encoding="utf-8").strip() or "0") + 1
    else:
        n = 1
    counter.write_text(str(n), encoding="utf-8")
    return n


def _handle_issue_create(argv: list[str]) -> int:
    """Synthetic issue create using EVAL_STATE_DIR or cassette fallback."""
    state = _state_dir()
    title = "untitled"
    body = ""
    i = 0
    while i < len(argv):
        if argv[i] == "--title" and i + 1 < len(argv):
            title = argv[i + 1]
            i += 2
            continue
        if argv[i].startswith("--title="):
            title = argv[i].split("=", 1)[1]
            i += 1
            continue
        if argv[i] == "--body" and i + 1 < len(argv):
            body = argv[i + 1]
            i += 2
            continue
        if argv[i].startswith("--body="):
            body = argv[i].split("=", 1)[1]
            i += 1
            continue
        if argv[i] == "--body-file" and i + 1 < len(argv):
            body = Path(argv[i + 1]).read_text(encoding="utf-8")
            i += 2
            continue
        if argv[i].startswith("--body-file="):
            body = Path(argv[i].split("=", 1)[1]).read_text(encoding="utf-8")
            i += 1
            continue
        i += 1

    if state is not None:
        n = _next_issue_number(state)
        issue_path = state / f"issue_{n}.json"
        issue_path.write_text(
            json.dumps(
                {
                    "number": n,
                    "title": title,
                    "body": body,
                    "state": "OPEN",
                    "url": f"https://github.com/eval/harness/issues/{n}",
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        # Also dump body for graders that look for issue.md
        (state / f"issue_{n}.md").write_text(body, encoding="utf-8")
        url = f"https://github.com/eval/harness/issues/{n}"
        print(url)
        return 0

    # No state dir: still emit a deterministic URL so subjects don't hang.
    print("https://github.com/eval/harness/issues/1")
    return 0


def _try_state_issue_view(argv: list[str]) -> int | None:
    """Serve issue view from EVAL_STATE_DIR when present. Return exit or None."""
    state = _state_dir()
    if state is None:
        return None
    if len(argv) < 3 or argv[0] != "issue" or argv[1] != "view":
        return None
    # Find issue number (first non-flag arg after view).
    num: str | None = None
    for a in argv[2:]:
        if a.startswith("-"):
            continue
        if re.fullmatch(r"\d+", a):
            num = a
            break
    if num is None:
        return None
    issue_path = state / f"issue_{num}.json"
    if not issue_path.exists():
        return None
    data = json.loads(issue_path.read_text(encoding="utf-8"))
    # Respect --json field selection when present.
    fields: list[str] | None = None
    for i, a in enumerate(argv):
        if a == "--json" and i + 1 < len(argv):
            fields = [f.strip() for f in argv[i + 1].split(",") if f.strip()]
            break
        if a.startswith("--json="):
            fields = [f.strip() for f in a.split("=", 1)[1].split(",") if f.strip()]
            break
    if fields:
        payload = {k: data.get(k) for k in fields}
    else:
        payload = data
    print(json.dumps(payload, separators=(",", ":")))
    return 0


def _find_real_gh() -> str | None:
    """Locate a real gh binary that is not this shim."""
    shim = Path(__file__).resolve()
    path = os.environ.get("PATH", "")
    for entry in path.split(os.pathsep):
        candidate = Path(entry) / "gh"
        if not candidate.exists():
            continue
        try:
            resolved = candidate.resolve()
        except OSError:
            continue
        # Skip our wrapper / this script.
        if resolved == shim:
            continue
        # Skip temp wrappers that exec this script.
        try:
            text = candidate.read_text(encoding="utf-8", errors="ignore")
            if "gh_shim.py" in text:
                continue
        except OSError:
            pass
        if os.access(candidate, os.X_OK):
            return str(candidate)
    # shutil.which after temporarily dropping shim dir is unreliable; try bare.
    which = shutil.which("gh")
    if which:
        try:
            text = Path(which).read_text(encoding="utf-8", errors="ignore")
            if "gh_shim.py" not in text:
                return which
        except OSError:
            return which
    return None


def _record_and_replay(argv: list[str], cassette_path: Path) -> int:
    real = _find_real_gh()
    if real is None:
        _eprint("✗ EVAL_RECORD=1 but no real gh found on PATH")
        return 1
    proc = subprocess.run(  # noqa: S603 — intentional local capture only
        [real, *argv],
        capture_output=True,
        text=True,
    )
    sys.stdout.write(proc.stdout)
    sys.stderr.write(proc.stderr)
    data = _load_cassettes(cassette_path) if cassette_path.exists() else {"version": 1, "calls": []}
    data.setdefault("version", 1)
    data.setdefault("calls", [])
    data["calls"].append(
        {
            "argv": argv,
            "stdout": proc.stdout,
            "stderr": proc.stderr,
            "exit": proc.returncode,
        }
    )
    cassette_path.parent.mkdir(parents=True, exist_ok=True)
    cassette_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return proc.returncode


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]

    # Help / bare invocation — no cassette required.
    if not argv or argv[0] in ("--help", "-h", "help"):
        print(HELP_TEXT, end="")
        return 0
    if argv[0] == "--version":
        print("gh version eval-shim-1.0.0 (record/replay)")
        return 0

    # Enforce --json for data-producing commands (platform-github.md).
    if _requires_json(argv) and not _has_json_flag(argv):
        _eprint(
            "✗ gh shim: data-producing command requires --json with explicit fields "
            f"(got: gh {' '.join(argv)}). See docs/platform-github.md."
        )
        return 2

    record = os.environ.get("EVAL_RECORD", "") == "1"
    cassette_raw = os.environ.get("EVAL_CASSETTES")
    if not cassette_raw:
        if record:
            _eprint("✗ EVAL_CASSETTES is required even in record mode")
            return 2
        _eprint("✗ EVAL_CASSETTES is not set — cannot replay")
        return 2

    cassette_path = Path(cassette_raw)

    # Synthetic mutations first (state-backed), then cassette match.
    if len(argv) >= 2 and argv[0] == "issue" and argv[1] == "create":
        # Prefer cassette if it has an exact/prefix match for create.
        if cassette_path.exists():
            data = _load_cassettes(cassette_path)
            hit = _match_call(argv, data.get("calls", []))
            if hit is not None:
                sys.stdout.write(hit.get("stdout", ""))
                sys.stderr.write(hit.get("stderr", ""))
                return int(hit.get("exit", 0))
        return _handle_issue_create(argv)

    state_hit = _try_state_issue_view(argv)
    if state_hit is not None:
        return state_hit

    if not cassette_path.exists():
        if record:
            return _record_and_replay(argv, cassette_path)
        _eprint(f"✗ cassette not found: {cassette_path}")
        return 1

    data = _load_cassettes(cassette_path)
    hit = _match_call(argv, data.get("calls", []))
    if hit is not None:
        sys.stdout.write(hit.get("stdout", ""))
        sys.stderr.write(hit.get("stderr", ""))
        return int(hit.get("exit", 0))

    if record:
        return _record_and_replay(argv, cassette_path)

    _eprint(
        "✗ unmatched gh call (no cassette entry):\n"
        f"  argv: {argv!r}\n"
        f"  cassette: {cassette_path}"
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
