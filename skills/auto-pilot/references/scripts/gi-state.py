#!/usr/bin/env python3
"""Own `/auto-pilot`'s resumable run state, its run lock, and its final report.

Every write to `.gitissue/run-state.json`, `.gitissue/run.lock`, and
`.gitissue/last-run-report.md` goes through this one script. That is the point:
a single choke point is what makes `--dry-run` enforceable ("a dry run leaves no
state mutation" is a property of one file, not of a dozen prose call sites) and
what keeps a half-written state file from ever existing (every state write is a
temp file in the same directory followed by `os.replace`).

The three artifacts are machine-local and gitignored. They are **not** the run
log: `.gitissue/runs.jsonl` is append-only cross-run telemetry written once per
processed issue, while the run state is mutable, single-run, and deleted or
overwritten by the next run. Neither substitutes for the other.

Untrusted values — issue titles above all — arrive only as JSON on **stdin**,
never on a command line, and are never evaluated: this script does not `eval`,
does not `exec`, and never shells out.

Modes
  --init    read `{run_id, mode, invocation, queue, limit}` on stdin, write the
            run state, print the normalized state
  --read    print the current state, or `{}` when absent. Never fails: absence
            and corruption are both answers, and both mean "start fresh"
  --update  read a patch on stdin, merge it into the state, write atomically
  --lock    create `.gitissue/run.lock` with O_CREAT|O_EXCL; refuse a lock held
            by a live run, reclaim one that is stale
  --unlock  release the lock (only this run's, unless --force)
  --report  read `{run_id, markdown}` on stdin, write the final run report

Exit codes
  0  ok
  2  usage error
  3  invalid input, corrupt run state, or the lock is held by a live run —
     a stop, never a degrade: do not perform the refused write by hand
  4  cannot complete — the write itself failed, or the directory is unwritable.
     Degrade to the documented prose procedure; the run is unaffected

There is deliberately **no** verdict exit code 1: "the lock is held" is a stop
(3), so every non-zero code keeps its usual meaning at every call site.

Authored at src/shared/scripts/gi-state.py — do not edit installed copies;
edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import socket
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_DIR = ".gitissue"
STATE_NAME = "run-state.json"
LOCK_NAME = "run.lock"
REPORT_NAME = "last-run-report.md"

STATE_VERSION = 1
DEFAULT_TTL_S = 3600

# An issue title is unbounded reporter-authored text; the state file only needs
# enough of it to name the issue in a resume line.
TITLE_MAX = 500

# Canonical emission order, so the file stays diffable between checkpoints.
STATE_KEYS = (
    "version",
    "run_id",
    "started_at",
    "updated_at",
    "invocation",
    "mode",
    "limit",
    "queue",
    "phase",
    "current",
    "processed",
    "skip_list",
    "report_path",
)

INIT_KEYS = frozenset({"run_id", "mode", "invocation", "queue", "limit"})
PATCH_SCALARS = ("phase", "mode", "invocation", "limit", "queue", "report_path")
PATCH_KEYS = frozenset(set(PATCH_SCALARS) | {"current", "processed", "skip_list"})
CURRENT_KEYS = frozenset(
    {"issue", "title", "branch", "pr", "phase", "outcome", "started_at"}
)
PROCESSED_KEYS = frozenset({"issue", "outcome", "pr"})
REPORT_KEYS = frozenset({"run_id", "markdown", "generated_at"})

RUN_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
# A phase name is an identifier the skill chooses, never reporter text.
PHASE_RE = re.compile(r"^[a-z][a-z0-9_.-]{0,31}$")
TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")


class InputError(ValueError):
    """The submitted input, or the state on disk, is not usable."""


class WriteError(OSError):
    """The write itself failed — the input was fine."""


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _parse_ts(value: object) -> datetime | None:
    if not isinstance(value, str) or not TS_RE.match(value):
        return None
    try:
        return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=timezone.utc
        )
    except ValueError:
        return None


def _is_int(value: object) -> bool:
    # bool is a subclass of int; a boolean issue number is a caller bug.
    return isinstance(value, int) and not isinstance(value, bool)


def _new_run_id() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + f"-{os.getpid()}"


def _pid_alive(pid: object) -> bool:
    """True when `pid` names a running process on this host.

    A permission error means the process exists and belongs to someone else, so
    it counts as alive — the fail-safe direction for a lock.
    """
    if not _is_int(pid) or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return True
    return True


# --- file helpers -----------------------------------------------------------


def _ensure_dir(directory: Path) -> None:
    try:
        os.makedirs(directory, exist_ok=True)
    except OSError as exc:
        raise WriteError(f"cannot create {directory} — {exc}") from exc


def _atomic_write(path: Path, text: str) -> None:
    """Write `text` to `path` via a temp file in the same directory + replace.

    A checkpoint that is interrupted mid-write must leave the previous state
    readable, never a truncated file that the next run would call corrupt.
    """
    _ensure_dir(path.parent)
    tmp_name = None
    try:
        fd, tmp_name = tempfile.mkstemp(
            prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent)
        )
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp_name, path)
        tmp_name = None
    except OSError as exc:
        raise WriteError(f"cannot write {path} — {exc}") from exc
    finally:
        if tmp_name is not None:
            try:
                os.unlink(tmp_name)
            except OSError:
                pass


def _render_json(obj: object) -> str:
    """Indented JSON with a trailing newline — the `.gitissue/` house format."""
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


def _read_json_file(path: Path) -> tuple[object | None, str | None]:
    """(parsed, error). `(None, None)` when the file does not exist."""
    try:
        raw = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return None, None
    except OSError as exc:
        return None, f"cannot read {path} — {exc}"
    except UnicodeDecodeError as exc:
        return None, f"{path} is not valid UTF-8 — {exc.reason}"
    try:
        return json.loads(raw), None
    except json.JSONDecodeError as exc:
        return None, f"{path} is not valid JSON — {exc.msg}"


def _read_stdin_json() -> object:
    try:
        raw = sys.stdin.read()
    except UnicodeDecodeError as exc:
        raise InputError(
            f"stdin is not valid UTF-8 — {exc.reason} at byte {exc.start}"
        ) from exc
    if not raw.strip():
        raise InputError("stdin is empty — this mode reads a JSON object on stdin")
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise InputError(f"stdin is not valid JSON — {exc.msg}") from exc


# --- validation -------------------------------------------------------------


def _check_str(record: dict, key: str, *, pattern: re.Pattern | None = None) -> None:
    value = record.get(key)
    if value is None:
        return
    if not isinstance(value, str):
        raise InputError(f"{key} must be a string")
    if pattern is not None and not pattern.match(value):
        raise InputError(f"{key} '{value}' is not a valid {key}")


def _check_int_list(record: dict, key: str) -> None:
    value = record.get(key)
    if value is None:
        return
    if not isinstance(value, list) or not all(_is_int(v) for v in value):
        raise InputError(f"{key} must be a list of integers")


def _normalize_current(value: object) -> dict[str, object] | None:
    if value is None:
        return None
    if not isinstance(value, dict):
        raise InputError("current must be an object or null")
    unknown = sorted(set(value) - CURRENT_KEYS)
    if unknown:
        raise InputError("unknown key(s) in current: " + ", ".join(unknown))
    out: dict[str, object] = {}
    for key in ("issue", "pr"):
        if key in value and value[key] is not None:
            if not _is_int(value[key]):
                raise InputError(f"current.{key} must be an integer or null")
        out[key] = value.get(key)
    for key in ("title", "branch", "phase", "outcome", "started_at"):
        if key in value and value[key] is not None:
            if not isinstance(value[key], str):
                raise InputError(f"current.{key} must be a string or null")
        out[key] = value.get(key)
    if isinstance(out.get("phase"), str) and not PHASE_RE.match(out["phase"]):
        raise InputError(f"current.phase '{out['phase']}' is not a phase name")
    title = out.get("title")
    if isinstance(title, str) and len(title) > TITLE_MAX:
        out["title"] = title[:TITLE_MAX]
    return {key: out[key] for key in sorted(out)}


def _normalize_processed(value: object) -> list[dict[str, object]]:
    if not isinstance(value, list):
        raise InputError("processed must be a list of objects")
    out = []
    for entry in value:
        if not isinstance(entry, dict):
            raise InputError("each processed entry must be an object")
        unknown = sorted(set(entry) - PROCESSED_KEYS)
        if unknown:
            raise InputError("unknown key(s) in processed: " + ", ".join(unknown))
        if not _is_int(entry.get("issue")):
            raise InputError("processed entries need an integer issue")
        outcome = entry.get("outcome")
        if outcome is not None and not isinstance(outcome, str):
            raise InputError("processed.outcome must be a string or null")
        pr = entry.get("pr")
        if pr is not None and not _is_int(pr):
            raise InputError("processed.pr must be an integer or null")
        out.append({"issue": entry["issue"], "outcome": outcome, "pr": pr})
    return out


def normalize_init(submitted: object, *, now: str | None = None) -> dict[str, object]:
    """Build a fresh run state from the `--init` payload."""
    if not isinstance(submitted, dict):
        raise InputError("stdin must be a single JSON object")
    unknown = sorted(set(submitted) - INIT_KEYS)
    if unknown:
        raise InputError("unknown key(s): " + ", ".join(unknown))
    _check_str(submitted, "run_id", pattern=RUN_ID_RE)
    _check_str(submitted, "mode")
    _check_str(submitted, "invocation")
    _check_int_list(submitted, "queue")
    limit = submitted.get("limit")
    if limit is not None and not _is_int(limit):
        raise InputError("limit must be an integer or null")
    stamp = now or _now()
    return {
        "version": STATE_VERSION,
        "run_id": submitted.get("run_id") or _new_run_id(),
        "started_at": stamp,
        "updated_at": stamp,
        "invocation": submitted.get("invocation"),
        "mode": submitted.get("mode"),
        "limit": limit,
        "queue": list(submitted.get("queue") or []),
        "phase": "init",
        "current": None,
        "processed": [],
        "skip_list": [],
        "report_path": None,
    }


def load_state(path: Path) -> dict[str, object]:
    """The state on disk, validated. Raises InputError when it is unusable."""
    parsed, error = _read_json_file(path)
    if error is not None:
        raise InputError(error)
    if parsed is None:
        raise InputError(f"{path} does not exist — run --init first")
    if not isinstance(parsed, dict) or "run_id" not in parsed:
        raise InputError(f"{path} is not a run-state object")
    return parsed


def merge_patch(
    state: dict[str, object], patch: object, *, now: str | None = None
) -> dict[str, object]:
    """Apply one `--update` patch to `state` and return the merged result.

    `current` merges key-by-key (an explicit null clears it), `processed` and
    `skip_list` append de-duplicated, and every other key is replaced.
    """
    if not isinstance(patch, dict):
        raise InputError("stdin must be a single JSON object")
    unknown = sorted(set(patch) - PATCH_KEYS)
    if unknown:
        raise InputError("unknown key(s): " + ", ".join(unknown))
    if not patch:
        raise InputError("patch is empty — nothing to update")

    out = dict(state)
    _check_str(patch, "phase", pattern=PHASE_RE)
    _check_str(patch, "mode")
    _check_str(patch, "invocation")
    _check_str(patch, "report_path")
    _check_int_list(patch, "queue")
    if "limit" in patch and patch["limit"] is not None and not _is_int(patch["limit"]):
        raise InputError("limit must be an integer or null")
    for key in PATCH_SCALARS:
        if key in patch:
            out[key] = patch[key]

    if "current" in patch:
        incoming = _normalize_current(patch["current"])
        if incoming is None:
            out["current"] = None
        else:
            base = out.get("current")
            merged = dict(base) if isinstance(base, dict) else {}
            merged.update({k: v for k, v in incoming.items() if k in patch["current"]})
            out["current"] = {key: merged[key] for key in sorted(merged)}

    if "processed" in patch:
        existing = _normalize_processed(out.get("processed") or [])
        by_issue = {entry["issue"]: entry for entry in existing}
        order = [entry["issue"] for entry in existing]
        for entry in _normalize_processed(patch["processed"]):
            if entry["issue"] not in by_issue:
                order.append(entry["issue"])
            by_issue[entry["issue"]] = entry
        out["processed"] = [by_issue[num] for num in order]

    if "skip_list" in patch:
        _check_int_list(patch, "skip_list")
        if patch["skip_list"] is None:
            raise InputError("skip_list must be a list of integers")
        merged_skips = list(out.get("skip_list") or [])
        for number in patch["skip_list"]:
            if number not in merged_skips:
                merged_skips.append(number)
        out["skip_list"] = merged_skips

    out["version"] = STATE_VERSION
    out["updated_at"] = now or _now()
    ordered = {key: out[key] for key in STATE_KEYS if key in out}
    ordered.update({k: v for k, v in out.items() if k not in STATE_KEYS})
    return ordered


# --- lock -------------------------------------------------------------------


def lock_status(lock: dict[str, object], ttl: int, *, now: str | None = None) -> dict:
    """Classify an existing lock as `held` or `stale`, with the reason."""
    started = _parse_ts(lock.get("heartbeat")) or _parse_ts(lock.get("started_at"))
    stamp = _parse_ts(now or _now())
    age = None
    if started is not None and stamp is not None:
        age = max(0, int((stamp - started).total_seconds()))
    same_host = lock.get("host") == socket.gethostname()
    alive = _pid_alive(lock.get("pid"))
    if age is None:
        # A lock with no readable timestamp cannot be aged; only a dead pid on
        # this host can retire it, or --force.
        reason = "dead-pid" if (same_host and not alive) else None
    elif age >= ttl:
        reason = "ttl"
    elif same_host and not alive:
        reason = "dead-pid"
    else:
        reason = None
    return {
        "age_s": age,
        "same_host": same_host,
        "pid_alive": alive,
        "stale": reason is not None,
        "stale_reason": reason,
    }


def _lock_payload(run_id: str, pid: int, *, now: str | None = None) -> dict:
    stamp = now or _now()
    return {
        "run_id": run_id,
        "pid": pid,
        "host": socket.gethostname(),
        "started_at": stamp,
        "heartbeat": stamp,
    }


def _create_lock_exclusive(path: Path, payload: dict) -> bool:
    """True when the lock was created, False when it already existed."""
    _ensure_dir(path.parent)
    try:
        fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
    except FileExistsError:
        return False
    except OSError as exc:
        raise WriteError(f"cannot create {path} — {exc}") from exc
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(_render_json(payload))
    except OSError as exc:
        raise WriteError(f"cannot write {path} — {exc}") from exc
    return True


# --- modes ------------------------------------------------------------------


def _emit(obj: object) -> None:
    print(json.dumps(obj, ensure_ascii=False))


def run_init(args, paths) -> int:
    state = normalize_init(_read_stdin_json())
    if args.dry_run:
        _emit({"dry_run": True, "would_write": str(paths["state"]), "state": state})
        return 0
    _atomic_write(paths["state"], _render_json(state))
    _emit(state)
    return 0


def run_read(args, paths) -> int:
    parsed, error = _read_json_file(paths["state"])
    if error is not None:
        # Never a failure: a corrupt state file is an answer ("start fresh"),
        # and making it a stop would strand a run that has done nothing wrong.
        print(f"⚠ gi-state: {error}", file=sys.stderr)
        _emit({"corrupt": True, "reason": error})
        return 0
    if parsed is None:
        _emit({})
        return 0
    if not isinstance(parsed, dict) or "run_id" not in parsed:
        print(f"⚠ gi-state: {paths['state']} is not a run-state object", file=sys.stderr)
        _emit({"corrupt": True, "reason": "not a run-state object"})
        return 0
    _emit(parsed)
    return 0


def run_update(args, paths) -> int:
    patch = _read_stdin_json()
    state = load_state(paths["state"])
    merged = merge_patch(state, patch)
    if args.dry_run:
        _emit({"dry_run": True, "would_write": str(paths["state"]), "state": merged})
        return 0
    _atomic_write(paths["state"], _render_json(merged))
    _touch_lock_heartbeat(paths["lock"], merged.get("run_id"))
    _emit(merged)
    return 0


def _touch_lock_heartbeat(lock_path: Path, run_id: object) -> None:
    """Refresh this run's lock timestamp so a long run never ages itself out.

    Best-effort by design: a missing or foreign lock is left alone, and a write
    failure here is not worth failing a checkpoint that already succeeded.
    """
    parsed, error = _read_json_file(lock_path)
    if error is not None or not isinstance(parsed, dict):
        return
    if parsed.get("run_id") != run_id:
        return
    parsed["heartbeat"] = _now()
    try:
        _atomic_write(lock_path, _render_json(parsed))
    except OSError:
        pass


def _resolve_run_id(args, paths) -> str | None:
    if args.run_id:
        return args.run_id
    parsed, error = _read_json_file(paths["state"])
    if error is None and isinstance(parsed, dict):
        run_id = parsed.get("run_id")
        if isinstance(run_id, str):
            return run_id
    return None


def run_lock(args, paths) -> int:
    run_id = _resolve_run_id(args, paths) or _new_run_id()
    if not RUN_ID_RE.match(run_id):
        raise InputError(f"run_id '{run_id}' is not a valid run id")
    payload = _lock_payload(run_id, args.pid)

    existing, error = _read_json_file(paths["lock"])
    if existing is not None or error is not None:
        if error is not None or not isinstance(existing, dict):
            # An unreadable lock cannot name a live run, and leaving it in place
            # would block every future run forever. Reclaim it, loudly.
            status = {"stale": True, "stale_reason": "corrupt", "age_s": None}
            holder: dict[str, object] = {}
        else:
            status = lock_status(existing, args.ttl)
            holder = existing
        if not status["stale"] and not args.force:
            print(
                "✗ gi-state: the run lock is held by run "
                f"{holder.get('run_id')} (pid {holder.get('pid')} on "
                f"{holder.get('host')})",
                file=sys.stderr,
            )
            _emit({"status": "held", "holder": holder, **status})
            return 3
        if args.dry_run:
            _emit(
                {
                    "dry_run": True,
                    "status": "would_reclaim",
                    "holder": holder,
                    "lock": payload,
                    **status,
                }
            )
            return 0
        _atomic_write(paths["lock"], _render_json(payload))
        print(
            f"⚠ gi-state: reclaimed a {status['stale_reason'] or 'forced'} lock "
            f"from run {holder.get('run_id')}",
            file=sys.stderr,
        )
        _emit({"status": "reclaimed", "previous": holder, "lock": payload, **status})
        return 0

    if args.dry_run:
        _emit({"dry_run": True, "status": "would_acquire", "lock": payload})
        return 0
    if not _create_lock_exclusive(paths["lock"], payload):
        # Another process won the race between the read above and this create.
        existing, _ = _read_json_file(paths["lock"])
        print("✗ gi-state: the run lock was taken concurrently", file=sys.stderr)
        _emit({"status": "held", "holder": existing if isinstance(existing, dict) else {}})
        return 3
    _emit({"status": "acquired", "lock": payload})
    return 0


def run_unlock(args, paths) -> int:
    existing, error = _read_json_file(paths["lock"])
    if existing is None and error is None:
        _emit({"status": "absent"})
        return 0
    holder = existing if isinstance(existing, dict) else {}
    if not args.force:
        if error is not None:
            raise InputError(f"{error} — rerun with --force to release it anyway")
        run_id = _resolve_run_id(args, paths)
        if run_id is None:
            raise InputError(
                "no --run-id and no run state to take one from — rerun with --force"
            )
        if holder.get("run_id") != run_id:
            raise InputError(
                f"the lock belongs to run {holder.get('run_id')}, not {run_id} — "
                "rerun with --force to release it anyway"
            )
    if args.dry_run:
        _emit({"dry_run": True, "status": "would_release", "holder": holder})
        return 0
    try:
        os.unlink(paths["lock"])
    except FileNotFoundError:
        _emit({"status": "absent"})
        return 0
    except OSError as exc:
        raise WriteError(f"cannot remove {paths['lock']} — {exc}") from exc
    _emit({"status": "released", "holder": holder})
    return 0


def run_report(args, paths) -> int:
    submitted = _read_stdin_json()
    if not isinstance(submitted, dict):
        raise InputError("stdin must be a single JSON object")
    unknown = sorted(set(submitted) - REPORT_KEYS)
    if unknown:
        raise InputError("unknown key(s): " + ", ".join(unknown))
    markdown = submitted.get("markdown")
    if not isinstance(markdown, str) or not markdown.strip():
        raise InputError("markdown must be a non-empty string")
    _check_str(submitted, "run_id", pattern=RUN_ID_RE)
    header = {
        "run_id": submitted.get("run_id") or _resolve_run_id(args, paths),
        "generated_at": submitted.get("generated_at") or _now(),
    }
    body = (
        "<!-- gitissue:run-report v1 "
        + json.dumps(header, ensure_ascii=False, sort_keys=True)
        + " -->\n\n"
        + markdown.rstrip("\n")
        + "\n"
    )
    path = paths["report"]
    if args.dry_run:
        _emit({"dry_run": True, "would_write": str(path), "bytes": len(body)})
        return 0
    _atomic_write(path, body)
    _emit({"status": "written", "path": str(path), "bytes": len(body)})
    return 0


MODES = {
    "init": run_init,
    "read": run_read,
    "update": run_update,
    "lock": run_lock,
    "unlock": run_unlock,
    "report": run_report,
}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-state.py",
        description=(
            "Persist, read, and update /auto-pilot's resumable run state, and "
            "own the run lock and the final-run report. Untrusted values reach "
            "this script only as JSON on stdin, never on a command line."
        ),
        epilog=(
            "Exit codes: 0 ok; 2 usage; 3 invalid input, corrupt state, or the "
            "lock is held by a live run (a stop — never perform the refused "
            "write by hand); 4 the write failed (degrade to prose). There is no "
            "verdict code 1."
        ),
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--init", action="store_true", help="write a fresh run state from stdin")
    mode.add_argument("--read", action="store_true", help="print the state, or {} when absent")
    mode.add_argument("--update", action="store_true", help="merge a patch from stdin into the state")
    mode.add_argument("--lock", action="store_true", help="acquire the run lock")
    mode.add_argument("--unlock", action="store_true", help="release the run lock")
    mode.add_argument("--report", action="store_true", help="write the final run report from stdin")
    parser.add_argument(
        "--dir",
        default=DEFAULT_DIR,
        help=f"directory holding the run artifacts (default: {DEFAULT_DIR})",
    )
    parser.add_argument(
        "--run-id",
        default=None,
        help="run id for --lock/--unlock (default: the id in the run state)",
    )
    parser.add_argument(
        "--ttl",
        type=int,
        default=DEFAULT_TTL_S,
        help=f"seconds after which a held lock is stale (default: {DEFAULT_TTL_S})",
    )
    parser.add_argument(
        "--pid",
        type=int,
        default=os.getppid(),
        help="pid recorded in the lock (default: the invoking process)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="reclaim or release a lock unconditionally",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="validate and print what would be written, but write nothing",
    )
    args = parser.parse_args(argv)

    if args.ttl < 0:
        print("✗ gi-state: --ttl must be zero or greater", file=sys.stderr)
        return 3
    if args.pid < 0:
        print("✗ gi-state: --pid must be zero or greater", file=sys.stderr)
        return 3
    if args.run_id is not None and not RUN_ID_RE.match(args.run_id):
        print(f"✗ gi-state: --run-id '{args.run_id}' is not a valid run id", file=sys.stderr)
        return 3

    base = Path(args.dir)
    paths = {
        "state": base / STATE_NAME,
        "lock": base / LOCK_NAME,
        "report": base / REPORT_NAME,
    }
    selected = next(name for name in MODES if getattr(args, name))

    try:
        return MODES[selected](args, paths)
    except InputError as exc:
        print(f"✗ gi-state: {exc}", file=sys.stderr)
        return 3
    except WriteError as exc:
        print(f"⚠ gi-state: {exc}", file=sys.stderr)
        return 4
    except OSError as exc:
        print(f"⚠ gi-state: {exc}", file=sys.stderr)
        return 4


if __name__ == "__main__":
    sys.exit(main())
