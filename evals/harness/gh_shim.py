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

import atexit
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
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

MAX_ISSUE_NUMBER = 2**63 - 1
ISSUE_URL_BASE = "https://github.com/eval/harness/issues"

VALUE_FLAG_DESTINATIONS = {
    "--json": "json",
    "--title": "title",
    "--body": "body",
    "--body-file": "body_file",
}


@dataclass(frozen=True)
class ParsedValueFlag:
    index: int
    option: str
    destination: str
    value: str
    joined: bool
    width: int


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


def issue_url(number: int | str) -> str:
    """Return the deterministic URL emitted for a synthetic issue."""
    return f"{ISSUE_URL_BASE}/{number}"


def _parse_value_flags(argv: list[str]) -> list[ParsedValueFlag]:
    """Parse supported ``--flag value`` and ``--flag=value`` forms once."""
    parsed: list[ParsedValueFlag] = []
    i = 0
    while i < len(argv):
        arg = argv[i]
        destination = VALUE_FLAG_DESTINATIONS.get(arg)
        if destination is not None and i + 1 < len(argv):
            parsed.append(ParsedValueFlag(i, arg, destination, argv[i + 1], False, 2))
            i += 2
            continue
        option, separator, value = arg.partition("=")
        destination = VALUE_FLAG_DESTINATIONS.get(option)
        if separator and destination is not None:
            parsed.append(ParsedValueFlag(i, option, destination, value, True, 1))
        i += 1
    return parsed


def _normalize_json_fields(fields: str) -> str:
    return ",".join(sorted(field.strip() for field in fields.split(",") if field.strip()))


def _normalize_argv(argv: list[str]) -> list[str]:
    """Normalize argv for comparison: sort --json field lists."""
    json_flags = {
        flag.index: flag
        for flag in _parse_value_flags(argv)
        if flag.destination == "json"
    }
    out: list[str] = []
    i = 0
    while i < len(argv):
        flag = json_flags.get(i)
        if flag is None:
            out.append(argv[i])
            i += 1
            continue
        fields = _normalize_json_fields(flag.value)
        if flag.joined:
            out.append(f"{flag.option}={fields}")
        else:
            out.extend((flag.option, fields))
        i += flag.width
    return out


def _has_json_flag(argv: list[str]) -> bool:
    return any(flag.destination == "json" for flag in _parse_value_flags(argv))


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


@dataclass(frozen=True)
class PreparedCalls:
    """Cassette entries with every argv normalized once, at load time.

    Matching used to normalize the whole cassette twice per lookup — pass 1
    normalized every entry before discarding the prefix ones, then pass 2
    normalized every entry again before discarding the exact ones — so a miss
    over n entries cost 2n normalizations of work that never changes. Doing it
    at load makes it n, once, and turns the exact pass into a dict lookup.

    `frozen` here means the two fields are never rebound after construction —
    not that `exact` is immutable, since it is an ordinary dict. Nothing
    mutates or hashes an instance; `_prepare_calls` builds one and hands it
    straight to `match`.
    """

    exact: dict[tuple[str, ...], dict[str, Any]]
    prefixes: tuple[tuple[tuple[str, ...], dict[str, Any]], ...]

    def match(self, argv: list[str]) -> dict[str, Any] | None:
        """Exact entries always beat prefix entries.

        Two ranks on purpose: a leading ``match: "prefix"`` cassette must not
        steal a later exact match for a longer command (e.g. prefix ``["pr"]``
        vs exact ``["pr", "view", "1", ...]``).
        """
        norm = tuple(_normalize_argv(argv))
        exact_hit = self.exact.get(norm)
        if exact_hit is not None:
            return exact_hit
        # `prefixes` is ordered longest-first, so the first hit is the longest
        # prefix; a stable sort left equal lengths in cassette order.
        for c_norm, call in self.prefixes:
            if len(norm) >= len(c_norm) and norm[: len(c_norm)] == c_norm:
                return call
        return None


def _prepare_calls(calls: list[Any]) -> PreparedCalls:
    """Index one cassette's calls by their normalized argv."""
    exact: dict[tuple[str, ...], dict[str, Any]] = {}
    prefixes: list[tuple[tuple[str, ...], dict[str, Any]]] = []
    for call in calls:
        # Malformed entries are skipped, not rejected: a cassette is a fixture
        # and one unusable row must not take the whole replay down.
        if not isinstance(call, dict):
            continue
        c_argv = call.get("argv")
        if not isinstance(c_argv, list):
            continue
        c_norm = tuple(_normalize_argv([str(x) for x in c_argv]))
        if call.get("match", "exact") == "prefix":
            prefixes.append((c_norm, call))
        else:
            # First entry wins, exactly as the in-order scan did.
            exact.setdefault(c_norm, call)
    prefixes.sort(key=lambda entry: len(entry[0]), reverse=True)
    return PreparedCalls(exact, tuple(prefixes))


def _match_call(argv: list[str], calls: list[dict[str, Any]]) -> dict[str, Any] | None:
    """Match argv against an unprepared list of cassette entries."""
    return _prepare_calls(calls).match(argv)


def _load_prepared(path: Path) -> PreparedCalls:
    """Load a cassette and normalize its argv once, at load.

    Buffered-but-unflushed records join the index so a call recorded earlier in
    this process still replays, exactly as it did when every record was written
    to disk the instant it was captured. `_load_cassettes` still validates the
    file, so an unusable cassette exits here as it always did.
    """
    data = _load_cassettes(path)
    calls = list(data.get("calls", []))
    calls.extend(_PENDING_RECORDS.get(str(path), ()))
    return _prepare_calls(calls)


def _state_dir() -> Path | None:
    raw = os.environ.get("EVAL_STATE_DIR")
    if not raw:
        return None
    p = Path(raw)
    p.mkdir(parents=True, exist_ok=True)
    return p


def _read_issue_counter(counter: Path) -> int:
    if not counter.exists():
        return 0
    try:
        with counter.open("rb") as fh:
            data = fh.read(65)
        if len(data) > 64:
            raise ValueError("counter exceeds 64 bytes")
        value = int(data.decode("utf-8").strip())
        if not 0 <= value <= MAX_ISSUE_NUMBER:
            raise ValueError("counter is outside the supported range")
        return value
    except (OSError, UnicodeError, ValueError) as exc:
        _eprint(f"⚠ gh shim: invalid issue counter {counter}: {exc}; resetting to 0")
        return 0


def _write_issue_counter(counter: Path, value: int) -> None:
    """Publish the counter atomically while the caller holds its sidecar lock."""
    tmp_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=counter.parent,
            prefix=".issue_counter.",
            delete=False,
        ) as tmp:
            tmp.write(str(value))
            tmp_name = tmp.name
        os.replace(tmp_name, counter)
    finally:
        if tmp_name is not None:
            Path(tmp_name).unlink(missing_ok=True)


def _next_issue_number(state: Path) -> int:
    counter = state / "issue_counter"
    lock_path = state / "issue_counter.lock"
    with lock_path.open("a+b") as lock_fh:
        fcntl.flock(lock_fh.fileno(), fcntl.LOCK_EX)
        current = _read_issue_counter(counter)
        if current >= MAX_ISSUE_NUMBER:
            _eprint(f"✗ gh shim: issue counter exhausted at {MAX_ISSUE_NUMBER}")
            raise SystemExit(1)
        n = current + 1
        _write_issue_counter(counter, n)
        return n


def _handle_issue_create(argv: list[str]) -> int:
    """Synthetic issue create using EVAL_STATE_DIR or cassette fallback."""
    state = _state_dir()
    values = {"title": "untitled", "body": ""}
    for flag in _parse_value_flags(argv):
        if flag.destination == "title":
            values["title"] = flag.value
        elif flag.destination == "body":
            values["body"] = flag.value
        elif flag.destination == "body_file":
            values["body"] = Path(flag.value).read_text(encoding="utf-8")
    title = values["title"]
    body = values["body"]

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
                    "url": issue_url(n),
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        # Also dump body for graders that look for issue.md
        (state / f"issue_{n}.md").write_text(body, encoding="utf-8")
        print(issue_url(n))
        return 0

    # No state dir: still emit a deterministic URL so subjects don't hang.
    print(issue_url(1))
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
    json_flag = next(
        (flag for flag in _parse_value_flags(argv) if flag.destination == "json"),
        None,
    )
    if json_flag is not None:
        fields = [field.strip() for field in json_flag.value.split(",") if field.strip()]
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


# Captured-but-unwritten calls, per cassette path. Flushed once, at exit.
_PENDING_RECORDS: dict[str, list[dict[str, Any]]] = {}
_FLUSH_REGISTERED = False


def _default_file_mode() -> int:
    """What `open(path, "w")` would have created a new file as.

    The flush publishes through a temp file, and `NamedTemporaryFile` is 0600.
    A cassette recorded into a new path used to be created by `write_text`, so
    it landed at 0666 filtered by the umask; reading the umask back keeps that
    unchanged rather than silently tightening every freshly captured cassette.
    """
    umask = os.umask(0)
    os.umask(umask)
    return 0o666 & ~umask


def _buffer_record(cassette_path: Path, record: dict[str, Any]) -> None:
    """Queue one captured call; the cassette is rewritten once, at exit.

    Recording used to reload, append to, and rewrite the entire cassette for
    every captured call — O(n^2) bytes for n calls in one process, 74 MB of
    writes to produce a 294 KB cassette at n=500. Buffering makes that one
    rewrite however many calls the process captures.

    Read that bound literally. ``run_eval.sh`` fronts this script on PATH as
    ``gh``, so a normal capture run is one process per call, each buffering
    exactly one record: the amplification *across* processes is unchanged and
    cannot be fixed from inside one of them. What this does fix is the
    in-process case — ``main()`` is importable and callable in a loop — and it
    is what lets the flush publish atomically, below, instead of truncating a
    committed fixture mid-write.

    A process that dies on a signal now loses its buffer where it used to have
    written each call already. Normal return, ``sys.exit``, an uncaught
    exception and SIGINT all still flush; SIGTERM, SIGKILL and ``os._exit`` do
    not. That is an accepted trade: ``EVAL_RECORD=1`` is local capture only —
    ``run_eval.sh`` and CI fail closed on it — and the session is re-runnable.
    """
    global _FLUSH_REGISTERED
    _PENDING_RECORDS.setdefault(str(cassette_path), []).append(record)
    if not _FLUSH_REGISTERED:
        atexit.register(_flush_records)
        _FLUSH_REGISTERED = True


def _flush_records() -> None:
    """Write every buffered call back to its cassette, one rewrite each.

    Published via ``os.replace`` over a sibling temp file — the same idiom the
    issue counter uses — because buffering concentrates the whole session into
    a single write, and a truncated cassette is worse than a short one.
    """
    for raw, records in _PENDING_RECORDS.items():
        if not records:
            continue
        path = Path(raw)
        data = _load_cassettes(path) if path.exists() else {"version": 1, "calls": []}
        data.setdefault("version", 1)
        data.setdefault("calls", [])
        data["calls"].extend(records)
        path.parent.mkdir(parents=True, exist_ok=True)
        mode = path.stat().st_mode & 0o777 if path.exists() else _default_file_mode()
        tmp_name: str | None = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                dir=path.parent,
                prefix=f".{path.name}.",
                delete=False,
            ) as tmp:
                # Name first: the write is what can fail, and the `finally`
                # below can only clean up a temp file it has been told about.
                tmp_name = tmp.name
                tmp.write(json.dumps(data, indent=2) + "\n")
            # NamedTemporaryFile is 0600; a cassette is a committed fixture, so
            # replacing one must not quietly narrow who can read it.
            os.chmod(tmp_name, mode)
            os.replace(tmp_name, path)
            tmp_name = None
        finally:
            if tmp_name is not None:
                Path(tmp_name).unlink(missing_ok=True)
        records.clear()


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
    _buffer_record(
        cassette_path,
        {
            "argv": argv,
            "stdout": proc.stdout,
            "stderr": proc.stderr,
            "exit": proc.returncode,
        },
    )
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
            prepared = _load_prepared(cassette_path)
            hit = prepared.match(argv)
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

    prepared = _load_prepared(cassette_path)
    hit = prepared.match(argv)
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
