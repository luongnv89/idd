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
There is no verdict exit code 1.

Untrusted values — issue titles above all — arrive only as JSON on **stdin**,
never on a command line, and are never evaluated: this script does not `eval`,
does not `exec`, and never shells out.

Modes
  --init    read `{run_id, mode, invocation, queue, limit}` on stdin, write the
            run state, print the normalized state. Every key is optional; when
            `run_id` is omitted the id of the lock this run already holds is
            adopted, so the documented `--lock` → `--init` → `--unlock` sequence
            shares one run id instead of minting a second one that `--unlock`
            would then refuse
  --read    print the current state, or `{}` when absent. Never fails: absence
            and corruption are both answers, and both mean "start fresh"
  --update  read a patch on stdin, merge it into the state, write atomically.
            `current.branch` and every `lanes[].branch` are pattern-checked
            against the repo's branch naming convention because the resume
            gate can put them in shell words; phases and `run_id` are checked
            for the same reason. Free text — `title`, `outcome` — never reaches
            a command, so it is only length-bounded. `lanes` is the durable
            parallel-resolver queue: entries merge by issue, while `[]` clears
            the completed batch. `queue` is `--init` only: it is the run's
            recorded intent, and a patch that names it is refused
  --lock    create `.gitissue/run.lock` with O_CREAT|O_EXCL; refuse a lock held
            by a live run, reclaim one that is stale. Mints a fresh run id, so
            a leftover state file from a finished run cannot lend its id to an
            unrelated one; `--lock --resume` adopts the recorded id instead and
            *re-acquires in place* (`reacquired`, a heartbeat refresh) when the
            lock is this run's own — same run id, same known owner pid, same
            host — which is the common resume: the loop died, the agent process
            holding the lock did not. `--pid` records that owner and defaults
            to 0, "no liveness signal": such a lock is retired by `--ttl` (when
            the timestamp is readable) or `--force` only, never by the dead-pid
            rule. With no readable timestamp *and* no known owner, only
            `--force` retires it. Pass a pid outliving the single command
            (`--pid "$PPID"`) for the prompt post-crash reclaim.
            Defaulting to the invoking process would be worse than useless: a
            one-shot shell exits as the lock is written, so the next run would
            read its own lock as dead
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
import glob
import json
import os
import re
import socket
import sys
import tempfile
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

try:
    import fcntl
except ImportError:  # pragma: no cover - non-POSIX hosts fail closed at runtime
    fcntl = None

DEFAULT_DIR = ".gitissue"
STATE_NAME = "run-state.json"
LOCK_NAME = "run.lock"
REPORT_NAME = "last-run-report.md"

STATE_VERSION = 1
DEFAULT_TTL_S = 3600

# How many times a reclaim re-classifies and retries before giving up. A reclaim
# only ever loses its race to another reclaim of the same lock, and each loss
# leaves a *new* lock behind, so the retries converge; the bound is what turns a
# pathological contention loop into an ordinary exit 3.
RECLAIM_ATTEMPTS = 3

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
    "lanes",
    "current",
    "processed",
    "skip_list",
    "report_path",
    "borrowed_skills",
)

INIT_KEYS = frozenset({"run_id", "mode", "invocation", "queue", "limit"})
PATCH_SCALARS = ("phase", "mode", "invocation", "limit", "report_path")
PATCH_KEYS = frozenset(
    set(PATCH_SCALARS)
    | {"lanes", "current", "processed", "skip_list", "borrowed_skills"}
)
BORROWED_SKILL_KEYS = frozenset({"name", "origin"})
SKILL_NAME_RE = re.compile(r"^[a-z][a-z0-9-]{0,63}\Z")
BORROWED_ORIGIN = frozenset({"borrowed", "preinstalled"})
CURRENT_KEYS = frozenset(
    {"issue", "title", "branch", "pr", "phase", "outcome", "started_at"}
)
# Parallel lanes deliberately mirror `current`: the serialized drain copies one
# lane into `current` and then follows the established review/merge path. The
# optional `telemetry` object carries the resolver's result until that drain
# writes the single runs.jsonl line; it is JSON data and never shell input.
LANE_KEYS = frozenset(
    {
        "issue",
        "title",
        "lane_id",
        "branch",
        "worktree_path",
        "base_sha",
        "event_id",
        "pr",
        "phase",
        "outcome",
        "started_at",
        "telemetry",
    }
)
PROCESSED_KEYS = frozenset({"issue", "outcome", "pr"})
REPORT_KEYS = frozenset({"run_id", "markdown", "generated_at"})

# Every pattern below ends in `\Z`, never `$`: in Python `$` also matches just
# before a trailing newline, so `^…$` would accept `fix/1-x\n` — a value that
# reaches a shell as two words.
RUN_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}\Z")
# A phase name is an identifier the skill chooses, never reporter text.
PHASE_RE = re.compile(r"^[a-z][a-z0-9_.-]{0,31}\Z")
# A branch name is *not* an identifier the skill chooses: it can arrive from a
# PR someone else opened (`headRefName`), and git and GitHub both permit `$`,
# backticks, `;`, `&&`, `|`, spaces and newlines in a ref. The resume gate
# interpolates the recorded branch into a `gh pr list --head …` word, and double
# quotes do not neutralize `$(…)` or a backtick — so the write is the gate: a
# branch that does not match the repo's naming convention (see the
# naming-conventions reference) is refused here, at exit 3, and never reaches
# the state file.
BRANCH_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,200}\Z")
LANE_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}\Z")
SHA_RE = re.compile(r"^[0-9a-f]{40}\Z")
TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\Z")


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


def _pid_known(pid: object) -> bool:
    """True when `pid` is a usable liveness signal.

    Absent, non-integer, or zero means the caller could not name a durable
    owner process — liveness is *unknown*, which is not the same as dead.
    """
    return _is_int(pid) and pid > 0


def _pid_alive(pid: object) -> bool:
    """True when `pid` names a running process on this host.

    A permission error means the process exists and belongs to someone else, so
    it counts as alive — the fail-safe direction for a lock. Callers must screen
    the pid with `_pid_known` first: an unknown pid answers `False` here and
    that answer means "nothing to check", never "the owner is gone".
    """
    if not _pid_known(pid):
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


@contextmanager
def _lock_guard(lock_path: Path):
    """Serialize every lock-path mutation and its ownership read.

    The lock file is deliberately replaced by rename, so locking the file
    itself would not coordinate a process that has already replaced its inode.
    The stable parent directory is the mutex: reclaim, force, unlock, and
    heartbeat all take it before reading and publishing a lock.
    """
    if fcntl is None:
        raise OSError("portable advisory locking is unavailable on this host")
    _ensure_dir(lock_path.parent)
    fd = os.open(lock_path.parent, os.O_RDONLY)
    locked = False
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        locked = True
        yield
    finally:
        try:
            if locked:
                fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


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
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        return None, f"{path} is not valid JSON — {exc.msg}"
    # JSON `null` is valid JSON and parses to Python None — the same pair
    # `(None, None)` that means "file does not exist". A lock (or state) file
    # that is literally `null` therefore has to be an error of its own, or
    # `--lock` treats the path as empty, `_create_lock_exclusive` refuses the
    # existing file, and `--unlock --force` reports absent while leaving it.
    if parsed is None:
        return None, f"{path} is JSON null"
    return parsed, None


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
    if isinstance(out.get("branch"), str) and not BRANCH_RE.match(out["branch"]):
        # The one recorded field a later step puts in a shell word. Refusing the
        # write is what keeps `gh pr list --head "…"` from running `$(…)`.
        raise InputError(
            f"current.branch '{out['branch']}' is not a conventional branch "
            "name (see the naming-conventions reference)"
        )
    # `title` and `outcome` are display-only — they are truncated and escaped
    # into JSON, never interpolated into a command — so they stay unconstrained.
    title = out.get("title")
    if isinstance(title, str) and len(title) > TITLE_MAX:
        out["title"] = title[:TITLE_MAX]
    return {key: out[key] for key in sorted(out)}


def _normalize_lane(value: object, *, partial: bool = False) -> dict[str, object]:
    if not isinstance(value, dict):
        raise InputError("each lanes entry must be an object")
    unknown = sorted(set(value) - LANE_KEYS)
    if unknown:
        raise InputError("unknown key(s) in lanes: " + ", ".join(unknown))
    if not _is_int(value.get("issue")):
        raise InputError("lanes entries need an integer issue")

    out: dict[str, object] = {"issue": value["issue"]}
    if "pr" in value:
        if value["pr"] is not None and not _is_int(value["pr"]):
            raise InputError("lanes.pr must be an integer or null")
        out["pr"] = value["pr"]
    for key in (
        "title",
        "lane_id",
        "branch",
        "worktree_path",
        "base_sha",
        "event_id",
        "phase",
        "outcome",
        "started_at",
    ):
        if key not in value:
            continue
        if value[key] is not None and not isinstance(value[key], str):
            raise InputError(f"lanes.{key} must be a string or null")
        out[key] = value[key]
    if isinstance(out.get("phase"), str) and not PHASE_RE.match(out["phase"]):
        raise InputError(f"lanes.phase '{out['phase']}' is not a phase name")
    if isinstance(out.get("branch"), str) and not BRANCH_RE.match(out["branch"]):
        raise InputError(
            f"lanes.branch '{out['branch']}' is not a conventional branch "
            "name (see the naming-conventions reference)"
        )
    for key in ("lane_id", "event_id"):
        if isinstance(out.get(key), str) and not LANE_ID_RE.match(out[key]):
            raise InputError(f"lanes.{key} '{out[key]}' is not a safe identifier")
    if isinstance(out.get("base_sha"), str) and not SHA_RE.match(out["base_sha"]):
        raise InputError("lanes.base_sha must be a full lowercase commit SHA")
    if isinstance(out.get("worktree_path"), str):
        path = out["worktree_path"]
        if not Path(path).is_absolute() or "\x00" in path or "\n" in path or "\r" in path:
            raise InputError("lanes.worktree_path must be a canonical absolute path")
        if str(Path(path)) != path:
            raise InputError("lanes.worktree_path must be normalized")
    title = out.get("title")
    if isinstance(title, str) and len(title) > TITLE_MAX:
        out["title"] = title[:TITLE_MAX]
    if "telemetry" in value:
        if value["telemetry"] is not None and not isinstance(value["telemetry"], dict):
            raise InputError("lanes.telemetry must be an object or null")
        out["telemetry"] = value["telemetry"]
    if not partial:
        # Full records may omit every optional field. Keeping absent fields
        # absent makes a v1 singleton state and a v1+lanes state coexist.
        return {key: out[key] for key in sorted(out)}
    return out


def _normalize_lanes(value: object, *, partial: bool = False) -> list[dict[str, object]]:
    if not isinstance(value, list):
        raise InputError("lanes must be a list of objects")
    out = []
    seen = set()
    for entry in value:
        lane = _normalize_lane(entry, partial=partial)
        if lane["issue"] in seen:
            raise InputError(f"lanes contains duplicate issue {lane['issue']}")
        seen.add(lane["issue"])
        out.append(lane)
    return out


def _normalize_borrowed_skills(value: object) -> list[dict[str, object]]:
    """Replace-on-patch list of per-skill borrow records (issue #309).

    `origin` is recorded at install time and is the only teardown signal:
    `borrowed` may be uninstalled; `preinstalled` must never be removed.
    An empty list clears leftover records after teardown.
    """
    if not isinstance(value, list):
        raise InputError("borrowed_skills must be a list of objects")
    out: list[dict[str, object]] = []
    seen: set[str] = set()
    for entry in value:
        if not isinstance(entry, dict):
            raise InputError("each borrowed_skills entry must be an object")
        unknown = sorted(set(entry) - BORROWED_SKILL_KEYS)
        if unknown:
            raise InputError(
                "unknown key(s) in borrowed_skills: " + ", ".join(unknown)
            )
        name = entry.get("name")
        origin = entry.get("origin")
        if not isinstance(name, str) or not SKILL_NAME_RE.match(name):
            raise InputError(
                "borrowed_skills.name must be a lowercase skill identifier"
            )
        if not isinstance(origin, str) or origin not in BORROWED_ORIGIN:
            raise InputError(
                "borrowed_skills.origin must be 'borrowed' or 'preinstalled'"
            )
        if name in seen:
            raise InputError(f"borrowed_skills contains duplicate name {name}")
        seen.add(name)
        out.append({"name": name, "origin": origin})
    return out


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


def normalize_init(
    submitted: object,
    *,
    now: str | None = None,
    default_run_id: str | None = None,
) -> dict[str, object]:
    """Build a fresh run state from the `--init` payload.

    `default_run_id` is the id of a lock this run already holds. A fresh run
    takes the lock *before* the first mutation, which is before any state file
    exists, so `--lock` has to mint the id; adopting it here is what makes the
    documented lock → init → unlock sequence one run rather than two.
    """
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
        "run_id": submitted.get("run_id") or default_run_id or _new_run_id(),
        "started_at": stamp,
        "updated_at": stamp,
        "invocation": submitted.get("invocation"),
        "mode": submitted.get("mode"),
        "limit": limit,
        "queue": list(submitted.get("queue") or []),
        "phase": "init",
        "lanes": [],
        "current": None,
        "processed": [],
        "skip_list": [],
        "report_path": None,
        "borrowed_skills": [],
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

    `current` merges key-by-key (an explicit null clears it), `lanes` merges
    key-by-key per issue (an empty list clears a completed batch), `processed`
    and `skip_list` append de-duplicated, `borrowed_skills` replaces the whole
    list (empty list = teardown complete), and every other key is replaced.
    """
    if not isinstance(patch, dict):
        raise InputError("stdin must be a single JSON object")
    if "queue" in patch:
        # Recorded intent at `--init` (*Two lists, two facts* in phases.md).
        # Accepting a patch here would let a caller silently rewrite the run's
        # original scope, which is the one fact `queue` exists to keep.
        raise InputError("queue is recorded at --init and cannot be patched")
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
    if "limit" in patch and patch["limit"] is not None and not _is_int(patch["limit"]):
        raise InputError("limit must be an integer or null")
    for key in PATCH_SCALARS:
        if key in patch:
            out[key] = patch[key]

    if "lanes" in patch:
        incoming_lanes = _normalize_lanes(patch["lanes"], partial=True)
        if not incoming_lanes:
            out["lanes"] = []
        else:
            existing_lanes = _normalize_lanes(out.get("lanes") or [])
            by_issue = {entry["issue"]: entry for entry in existing_lanes}
            order = [entry["issue"] for entry in existing_lanes]
            for lane in incoming_lanes:
                issue = lane["issue"]
                if issue not in by_issue:
                    by_issue[issue] = {}
                    order.append(issue)
                merged_lane = dict(by_issue[issue])
                merged_lane.update(lane)
                by_issue[issue] = _normalize_lane(merged_lane)
            out["lanes"] = [by_issue[number] for number in order]

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

    if "borrowed_skills" in patch:
        out["borrowed_skills"] = _normalize_borrowed_skills(patch["borrowed_skills"])

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
    # A lock whose owner pid is unknown — absent, unparsable, or the 0 recorded
    # when the caller could not name a durable process — carries no liveness
    # signal: `pid_alive` is null and the dead-pid rule never retires it.
    # The TTL still can, but only when the timestamp is readable; with neither
    # a known owner nor a parseable timestamp, only --force retires it.
    # Reading "unknown" as "dead" is what lets a run reclaim the lock it took
    # moments ago from a shell that has since exited, and that is no mutual
    # exclusion at all. When in doubt the lock is held.
    known = _pid_known(lock.get("pid"))
    alive = _pid_alive(lock.get("pid")) if known else None
    dead_here = same_host and known and not alive
    if age is None:
        # A lock with no readable timestamp cannot be aged; only a dead pid on
        # this host can retire it, or --force. An ownerless lock in this
        # state is held until --force.
        reason = "dead-pid" if dead_here else None
    elif age >= ttl:
        reason = "ttl"
    elif dead_here:
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


def _lock_identity(lock: object) -> tuple | None:
    """What makes one lock file a *different* lock from another.

    `None` for anything unreadable — an unreadable lock is never "the same lock"
    as a readable one, which is what keeps a reclaim from retiring a file it
    never classified.
    """
    if not isinstance(lock, dict):
        return None
    return (
        lock.get("run_id"),
        lock.get("started_at"),
        lock.get("pid"),
        lock.get("host"),
    )


def _pid_owns(lock: object, pid: int) -> bool:
    """True when `lock` records `pid`, on this host, as its owner.

    This is the half of the ownership test that carries exclusivity across
    processes: a different agent process passes a different pid and fails it.
    An unknown owner (`pid 0`) never satisfies it — otherwise every ownerless
    lock would answer to every ownerless caller, which is exactly the
    self-reclaim the run lock exists to prevent.

    The host must match for the same reason `lock_status` checks it before
    believing a dead pid: a pid only means something on the machine that
    recorded it, and two machines hand out the same numbers. Without this,
    `--resume` would be *weaker* than a plain `--lock`, which already refuses
    a foreign-host lock — a pid collision would hand one lock to two runs.
    """
    if not isinstance(lock, dict):
        return False
    recorded = lock.get("pid")
    return (
        lock.get("host") == socket.gethostname()
        and _pid_known(pid)
        and _pid_known(recorded)
        and recorded == pid
    )


def _owns_lock(lock: object, run_id: str, pid: int) -> bool:
    """True when `lock` is *this* run's own lock, resumable in place.

    Both halves are required: an unrelated run resuming in the same tree
    carries a different run id, and a different agent process carries a
    different owner pid, so neither passes.
    """
    return (
        isinstance(lock, dict)
        and lock.get("run_id") == run_id
        and _pid_owns(lock, pid)
    )


def _retire_lock(path: Path, observed: tuple | None) -> str:
    """Take the *observed* stale lock out of the way, atomically.

    `os.rename` is the exclusion primitive: of two processes racing to retire
    one stale lock, exactly one rename can find the path, so exactly one of them
    goes on to create the replacement. Returns `retired` (this process removed
    the lock it classified), `gone` (another process got there first), or
    `changed` (the file was somebody else's newer lock — it is put back, and the
    caller must re-classify rather than reclaim on a stale verdict).
    """
    retired = path.with_name(f"{path.name}.retired-{os.getpid()}")
    try:
        os.rename(path, retired)
    except FileNotFoundError:
        return "gone"
    except OSError as exc:
        raise WriteError(f"cannot retire {path} — {exc}") from exc
    parsed, _ = _read_json_file(retired)
    if _lock_identity(parsed) != observed:
        # Put it back — but never *over* whatever is at the path now. A third
        # process can find the path empty in the window since the rename and
        # take the lock legitimately; `os.replace` would silently overwrite that
        # fresh holder. `os.link` refuses an existing destination, exactly like
        # the publish path in `_create_lock_exclusive`, so the newer lock wins
        # and this stray copy is simply dropped.
        try:
            os.link(retired, path)
        except OSError:
            pass
        try:
            os.unlink(retired)
        except OSError:
            pass
        return "changed"
    try:
        os.unlink(retired)
    except OSError:
        pass
    return "retired"


def _sweep_retired_strays(lock_path: Path) -> None:
    """Remove orphaned `<lock>.retired-<pid>` strays under the dir guard.

    A crash between `_retire_lock`'s rename and its unlink strands the retired
    copy on disk forever — nothing reads it again. Sweeping runs only inside
    `_lock_guard`, whose stable-directory flock guarantees no concurrent retire
    is mid-rename on these names.
    """
    try:
        strays = sorted(
            lock_path.parent.glob(f"{glob.escape(lock_path.name)}.retired-*")
        )
    except OSError:
        return
    for stray in strays:
        try:
            stray.unlink()
        except OSError:
            pass


def _create_lock_exclusive(path: Path, payload: dict) -> bool:
    """True when the lock was created, False when it already existed.

    The payload is written in full under a private name and then hard-linked
    into place. `os.link` refuses an existing destination, so it excludes
    exactly like `O_EXCL` — and unlike an empty `O_EXCL` create followed by a
    write, it publishes a **complete** file. That window is not theoretical: a
    concurrent run that read the half-written lock would parse it as corrupt and
    reclaim a lock that was in the middle of being taken.
    """
    _ensure_dir(path.parent)
    staged = None
    try:
        fd, staged = tempfile.mkstemp(
            prefix=f".{path.name}.", suffix=".new", dir=str(path.parent)
        )
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(_render_json(payload))
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(staged, 0o644)
        try:
            os.link(staged, path)
        except FileExistsError:
            return False
        return True
    except OSError as exc:
        raise WriteError(f"cannot create {path} — {exc}") from exc
    finally:
        if staged is not None:
            try:
                os.unlink(staged)
            except OSError:
                pass


# --- modes ------------------------------------------------------------------


def _emit(obj: object) -> None:
    print(json.dumps(obj, ensure_ascii=False))


def run_init(args, paths) -> int:
    state = normalize_init(
        _read_stdin_json(), default_run_id=_lock_run_id(paths["lock"])
    )
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
    _touch_lock_heartbeat(paths["lock"], merged.get("run_id"), pid=args.pid)
    _emit(merged)
    return 0


def _touch_lock_heartbeat(
    lock_path: Path,
    run_id: object,
    pid: int | None = None,
    *,
    _lock_held: bool = False,
) -> None:
    """Refresh this run's lock timestamp so a long run never ages itself out.

    Best-effort by design: a missing or foreign lock is left alone, and a write
    failure here is not worth failing a checkpoint that already succeeded. A
    valid owner pid is required; without one the heartbeat is a no-op. The write
    also requires ownership on this host, so a `--lock --force` that published a
    new lock with the same run id is not overwritten by a stale heartbeat. The
    identity is compared again immediately before publishing while the stable
    directory guard is held, so a replacement cannot be overwritten by this
    stale heartbeat.
    """
    if not _pid_known(pid):
        return

    def refresh() -> None:
        parsed, error = _read_json_file(lock_path)
        if error is not None or not isinstance(parsed, dict):
            return
        if not _owns_lock(parsed, run_id, pid):
            return
        observed = _lock_identity(parsed)
        current, current_error = _read_json_file(lock_path)
        if current_error is not None or _lock_identity(current) != observed:
            return
        parsed["heartbeat"] = _now()
        _atomic_write(lock_path, _render_json(parsed))

    try:
        if _lock_held:
            refresh()
        else:
            with _lock_guard(lock_path):
                refresh()
    except OSError:
        pass


def _screen_run_id(value: object) -> str | None:
    """`value` when it is a conformant run id, else None.

    The single screen every **disk-sourced** id goes through. A file on disk is
    still input: it can hold a number where a string belongs (an unscreened id
    reaching `RUN_ID_RE.match` is a `TypeError`, and an uncaught one exits 1 —
    the code this script reserves for a verdict), or a string carrying `-->`
    that would end the report marker early. Non-conformant is dropped, never
    repaired, so the caller falls back to minting a fresh id.
    """
    if isinstance(value, str) and RUN_ID_RE.match(value):
        return value
    return None


def _lock_run_id(lock_path: Path) -> str | None:
    """The run id recorded in an existing lock, when it is readable and valid.

    The mirror image of `_resolve_run_id`: that one reads the state to serve the
    lock, this one reads the lock to serve the state. Only one of the two can
    answer on a fresh run, and on a fresh run it is always this one.
    """
    parsed, error = _read_json_file(lock_path)
    if error is not None or not isinstance(parsed, dict):
        return None
    return _screen_run_id(parsed.get("run_id"))


def _resolve_run_id(args, paths) -> str | None:
    """This run's id: the submitted one, else the one the state file records.

    The disk-sourced fallback is pattern-checked exactly like the submitted one.
    It reaches the report marker, and a state file carrying `run_id: "x --> y"`
    would end that `<!-- … -->` marker early — the file is machine-local, but it
    is still input, and "it came off disk" is not a reason to trust it less
    carefully than stdin. A non-conformant id is dropped, not repaired.
    """
    if args.run_id:
        return args.run_id
    parsed, error = _read_json_file(paths["state"])
    if error is None and isinstance(parsed, dict):
        return _screen_run_id(parsed.get("run_id"))
    return None


def _classify_lock(args, paths) -> tuple[dict, dict, tuple | None]:
    """(holder, status, identity) for whatever is at the lock path right now."""
    existing, error = _read_json_file(paths["lock"])
    if error is not None or not isinstance(existing, dict):
        # An unreadable lock cannot name a live run, and leaving it in place
        # would block every future run forever. Reclaim it, loudly.
        return {}, {"stale": True, "stale_reason": "corrupt", "age_s": None}, None
    return existing, lock_status(existing, args.ttl), _lock_identity(existing)


def _emit_held(holder: dict, status: dict) -> int:
    pid = holder.get("pid")
    owner = f"pid {pid}" if _pid_known(pid) else "pid unknown"
    print(
        "✗ gi-state: the run lock is held by run "
        f"{holder.get('run_id')} ({owner} on {holder.get('host')})",
        file=sys.stderr,
    )
    _emit({"status": "held", "holder": holder, **status})
    return 3


def run_lock(args, paths) -> int:
    if args.dry_run:
        return _run_lock_locked(args, paths)
    with _lock_guard(paths["lock"]):
        _sweep_retired_strays(paths["lock"])
        return _run_lock_locked(args, paths)


def _run_lock_locked(args, paths) -> int:
    # A plain `--lock` starts a *new* run, so it mints a new id even when a
    # previous run left its state file behind: adopting that id would give two
    # unrelated runs one id in both the report marker and `runs.jsonl`. Only
    # `--lock --resume` — the caller saying "I am continuing the recorded run" —
    # takes the id off disk. `--init` then adopts whichever id this lock holds,
    # so the documented lock → init → unlock sequence stays one run either way.
    existing, error = _read_json_file(paths["lock"])
    own_lock = args.resume and error is None and _pid_owns(existing, args.pid)
    run_id = args.run_id or (
        (_resolve_run_id(args, paths) if args.resume else None)
        # A resume that finds no recorded id but does find a lock this very
        # process owns adopts the lock's id: the interrupted run died before
        # `--init` ever wrote a state, and minting a second id here would orphan
        # the lock this run is holding — the id would then disagree with the
        # `--unlock` that ends the run. Screened like every other disk-sourced
        # id: a lock carrying a non-string id falls through to a fresh one
        # (and so to the ordinary held/reclaim paths), never to a crash.
        or (_screen_run_id(existing.get("run_id")) if own_lock else None)
        or _new_run_id()
    )
    if not RUN_ID_RE.match(run_id):
        raise InputError(f"run_id '{run_id}' is not a valid run id")
    payload = _lock_payload(run_id, args.pid)

    if own_lock and _owns_lock(existing, run_id, args.pid):
        # A genuine `--resume` usually finds its OWN lock still there and still
        # live: what was interrupted is the loop, inside an agent process that
        # is itself alive, so the owner pid recorded in that lock is the very
        # pid this call passes. Refusing it would deny a run its own lock and
        # make `--resume` unusable in the common case. Re-acquiring is a
        # heartbeat refresh, not a reclaim: the file is never taken out of the
        # way, so no window opens for a third run.
        if args.dry_run:
            _emit({"dry_run": True, "status": "would_reacquire", "lock": existing})
            return 0
        _touch_lock_heartbeat(
            paths["lock"], run_id, pid=args.pid, _lock_held=True
        )
        refreshed, _ = _read_json_file(paths["lock"])
        # The heartbeat is a best-effort write. A concurrent TTL reclaim or
        # `--lock --force` in that window can replace the file; reporting
        # `reacquired` from the re-read without re-checking ownership would
        # publish someone else's lock as this run's success.
        if not _owns_lock(refreshed, run_id, args.pid):
            holder, status, _ = _classify_lock(args, paths)
            if not holder and isinstance(refreshed, dict):
                holder = refreshed
            return _emit_held(holder, status)
        _emit({"status": "reacquired", "lock": refreshed})
        return 0

    if existing is not None or error is not None:
        holder, status, observed = _classify_lock(args, paths)
        if not status["stale"] and not args.force:
            return _emit_held(holder, status)
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
        # Reclaiming is not a plain write. `_atomic_write` here would let two
        # runs that both classified the same stale lock both "win", because
        # os.replace never refuses an existing file: retire the exact lock this
        # run classified, then create the replacement with O_CREAT|O_EXCL, and
        # re-classify whenever either step loses the race.
        for _ in range(RECLAIM_ATTEMPTS):
            if not status["stale"] and not args.force:
                break
            if _retire_lock(paths["lock"], observed) != "changed":
                if _create_lock_exclusive(paths["lock"], payload):
                    print(
                        f"⚠ gi-state: reclaimed a "
                        f"{status['stale_reason'] or 'forced'} lock from run "
                        f"{holder.get('run_id')}",
                        file=sys.stderr,
                    )
                    _emit(
                        {
                            "status": "reclaimed",
                            "previous": holder,
                            "lock": payload,
                            **status,
                        }
                    )
                    return 0
            holder, status, current = _classify_lock(args, paths)
            if current != observed:
                # A *different* lock is at the path now. This invocation
                # classified the one it was asked to reclaim, and a stale
                # verdict about that file says nothing about this one, so it
                # stops instead of reclaiming on somebody else's evidence. At
                # the default TTL that leaves exactly one winner: the run that
                # published the replacement. At `--ttl 0`, where every lock is
                # stale the instant it is written, contended reclaimers can all
                # stop and the round has *no* winner — the fail-safe direction,
                # and no shipped prose passes `--ttl`.
                break
        return _emit_held(holder, status)

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
    if args.dry_run:
        return _run_unlock_locked(args, paths)
    with _lock_guard(paths["lock"]):
        _sweep_retired_strays(paths["lock"])
        return _run_unlock_locked(args, paths)


def _run_unlock_locked(args, paths) -> int:
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
    # Both header values are interpolated into the `<!-- … -->` marker below, so
    # every path that can produce one is pattern-checked — the submitted value
    # here, and equally the state-file fallback inside `_resolve_run_id`, which
    # drops a non-conformant id rather than passing it through. A `run_id` or
    # `generated_at` carrying `-->` would end the marker early and leave the
    # rest of it as visible report text.
    _check_str(submitted, "generated_at", pattern=TS_RE)
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
        default=0,
        help=(
            "pid of the process that owns the run, recorded in the lock; pass a "
            "durable one (\"$PPID\" in an agent shell) so a crashed run's lock "
            "retires on the dead-pid path (default: 0 — no liveness signal, the "
            "lock is retired by --ttl when the timestamp is readable, or --force; "
            "with no readable timestamp, only --force)"
        ),
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="reclaim or release a lock unconditionally",
    )
    parser.add_argument(
        "--resume",
        action="store_true",
        help=(
            "--lock only: continue the recorded run, adopting its run id and "
            "re-acquiring the lock in place when this run already owns it"
        ),
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
    if args.resume and not args.lock:
        print("✗ gi-state: --resume applies to --lock only", file=sys.stderr)
        return 2
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
