#!/usr/bin/env python3
"""Validate, normalize, and append one `.gitissue/runs.jsonl` telemetry record.

Reads a single JSON object on stdin — the record a skill wants to log — and
either appends it to the run log (`--append`, the default) or prints the
normalized form without writing anything (`--echo`). `--echo` is the machine
form of the `--no-run-log` contract: an inner `/issue-resolver` run suppressed
by `/auto-pilot` still wants its telemetry checked and normalized before it is
returned to the orchestrator, but must not create a second line for the issue.

Normalization is the part worth centralizing: the researcher's 5-value
complexity scale is collapsed to the run log's 3 values, optional keys whose
value is null are dropped rather than written, a missing `ts` is filled from the
UTC clock, and the keys are emitted in the canonical order so the file stays
greppable and diffable.

`--failure-streak N` is the one **read** mode. It scans the log backwards and
counts the issue's leading run of `failed` outcomes — the consecutive
most-recent records for that issue — stopping at the first record for that
issue whose outcome is anything else. Records for other issues are stepped over
and never reset the count. It prints one JSON line and writes nothing:

    {"mode":"failure_streak","issue":N,"streak":N,"threshold":F,"quarantine":bool}

`quarantine` is `streak >= threshold` and `threshold > 0`; `--threshold 0`
disables quarantine outright, so it is always false.

Rotation keeps the active log small (F-PERF-006). Before an append-mode write
(`--append` or `--append-once`) the active log is renamed to a timestamped
segment beside itself — `runs-<YYYYMMDDTHHMMSSZ>.jsonl` — when it has reached
`--rotate-max-bytes` or sat idle past `--rotate-max-days`; the new record then
starts a fresh active log. Rotation is best-effort like every other write: a
failed rename warns on stderr and the record still appends. Readers scan a
bounded tail — the newest `--tail-segments` segments plus the active log,
oldest first — so streaks and idempotency checks survive rotation.

The count is deliberately **soft**. The run log is gitignored, best-effort and
deletable, so it can only ever carry *progress toward* quarantine — the durable
state is the label `/auto-pilot` applies at the threshold. That asymmetry sets
the failure behavior: a log that cannot be opened at all is not an error that
stops a run, it is exit 4 with a `streak` of 0 and `quarantine` false, printed
anyway so a caller that ignores the exit code still cannot quarantine an issue
on evidence it never read. Losing the log loses progress toward a quarantine,
never an existing one. Malformed individual lines are skipped rather than
fatal, for the same reason a reader must tolerate unknown keys: this file has
no schema migration.

Exit codes
  0  record valid; appended (--append) or printed (--echo). With
     --failure-streak: the log was read and the streak printed
  2  usage error
  3  record invalid — nothing was written
  4  the append itself failed — the record was valid; writing the run log is
     best-effort and non-fatal, so a caller must not fail its run on this.
     With --failure-streak: the log is missing or unreadable — the fail-open
     `streak: 0` line is still printed

Authored at src/shared/scripts/gi-runlog.py — do not edit installed copies;
edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

try:
    import fcntl
except ImportError:  # pragma: no cover - non-POSIX hosts fail closed at runtime
    fcntl = None

DEFAULT_LOG_PATH = ".gitissue/runs.jsonl"

# Rotation (F-PERF-006): the active log never grows without bound. Before an
# append-mode write, a log at or above the byte ceiling — or idle past the day
# ceiling, measured from the file's mtime so backdated `ts` fields never
# trigger it — renames to a timestamped segment beside itself and the append
# lands in a fresh active log.
DEFAULT_ROTATE_MAX_BYTES = 1024 * 1024
DEFAULT_ROTATE_MAX_DAYS = 30

# How deep readers scan: the newest N rotated segments plus the active log,
# oldest first. A bound keeps every read O(window) after years of appends; a
# streak or event_id rotated out of the window has left its scope.
DEFAULT_TAIL_SEGMENTS = 10

# Rotated-segment stamp: compact UTC, sorts lexicographically in chronological
# order because every field is zero-padded and fixed-width.
SEGMENT_STAMP_FORMAT = "%Y%m%dT%H%M%SZ"

# Consecutive failed runs before `/auto-pilot` quarantines an issue. Mirrors the
# documented `autopilot.quarantine_after` default so an omitted --threshold
# answers exactly what the skill's default configuration would have asked for.
DEFAULT_QUARANTINE_AFTER = 3

# The one outcome that extends a streak. Every skill writes `failed` with the
# same meaning, so the count does not have to know which skill wrote the line.
FAILURE_OUTCOME = "failed"

# Canonical emission order. Every optional key that survives normalization is
# written in this position, so lines from different writers stay comparable.
KEY_ORDER = (
    "ts",
    "event_id",
    "issue",
    "mode",
    "skill",
    "complexity",
    "profile",
    "qa_cycles",
    "ceiling",
    "breach_reason",
    "outcome",
    "pr",
    "duration_s",
    "skipped_reason",
)

REQUIRED_KEYS = ("ts", "issue", "mode", "skill", "outcome", "pr")
OPTIONAL_KEYS = (
    "event_id",
    "complexity",
    "profile",
    "qa_cycles",
    "ceiling",
    "breach_reason",
    "duration_s",
    "skipped_reason",
)

# Policy QA-cycle ceiling by class (issue #308). Loop caps (`resolve.qa_max_cycles`
# default 5, `review.max_cycles` default 3) stay the hard bound. Missing
# profile/complexity fail-safe to full + medium → 2.
DEFAULT_HIGH_CEILING = 5

# `ts` is absent-or-valid: absent is filled from the clock, present must be an
# ISO-8601 UTC instant to the second, exactly as the schema's examples show.
TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
EVENT_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")

# Terminal outcomes, per writing skill. A resolver row can never carry an
# auto-pilot merge outcome and vice versa — that mix-up is what silently
# corrupts /idd-doctor's resolve-rate metric.
OUTCOMES_BY_SKILL = {
    "issue-resolver": frozenset({"success", "already_resolved", "failed"}),
    "auto-pilot": frozenset(
        {
            "merged",
            "left_open",
            "partial_followup",
            "blocked_by_dependency",
            "failed",
            "skipped",
        }
    ),
}

PROFILES = frozenset({"light", "full"})

# The researcher estimates on five values; the run log stores three.
COMPLEXITY_COLLAPSE = {
    "trivial": "low",
    "low": "low",
    "medium": "medium",
    "high": "high",
    "complex": "high",
}

INT_KEYS = ("issue", "qa_cycles", "ceiling", "duration_s")
STR_KEYS = (
    "ts",
    "event_id",
    "mode",
    "skill",
    "outcome",
    "profile",
    "complexity",
    "skipped_reason",
    "breach_reason",
)


def policy_ceiling(profile: object, complexity: object, *, high: int = DEFAULT_HIGH_CEILING) -> int:
    """Class ceiling: light=1, full+high=high (default 5), else 2."""
    if profile == "light":
        return 1
    if complexity == "high":
        return high
    return 2


class RecordError(ValueError):
    """The submitted record is not a valid run-log line."""


def _is_int(value: object) -> bool:
    # bool is a subclass of int; a boolean issue number is a caller bug.
    return isinstance(value, int) and not isinstance(value, bool)


def normalize_record(record: object, *, now: str | None = None) -> dict[str, object]:
    """Validate one submitted record and return its canonical form.

    Raises RecordError with a human-readable reason on any violation; the caller
    turns that into exit 3 without writing anything.
    """
    if not isinstance(record, dict):
        raise RecordError("stdin must be a single JSON object")

    unknown = sorted(set(record) - set(KEY_ORDER))
    if unknown:
        raise RecordError("unknown key(s): " + ", ".join(unknown))

    missing = [key for key in REQUIRED_KEYS if key not in record and key != "ts"]
    if missing:
        raise RecordError("missing required key(s): " + ", ".join(missing))

    # `pr` is the only documented nullable field, and `ts` treats an explicit
    # null as absent (filled from the clock below). A null anywhere else in the
    # required set used to sail straight through — the INT_KEYS/STR_KEYS loops
    # skip None and the null-drop pass covers OPTIONAL_KEYS only — so
    # `{"issue": null, ...}` was emitted verbatim as `"issue":null`, a line no
    # reader of this schema accepts.
    nulled = [
        key
        for key in REQUIRED_KEYS
        if key not in ("pr", "ts") and key in record and record[key] is None
    ]
    if nulled:
        raise RecordError(
            "null is not a valid value for: " + ", ".join(nulled) + " (only `pr` is nullable)"
        )

    for key in INT_KEYS:
        if key in record and record[key] is not None and not _is_int(record[key]):
            raise RecordError(f"{key} must be an integer")
    for key in STR_KEYS:
        if key in record and record[key] is not None and not isinstance(record[key], str):
            raise RecordError(f"{key} must be a string")

    if record["pr"] is not None and not _is_int(record["pr"]):
        raise RecordError("pr must be an integer or null")

    skill = record["skill"]
    if skill not in OUTCOMES_BY_SKILL:
        raise RecordError(
            "skill must be one of " + ", ".join(sorted(OUTCOMES_BY_SKILL))
        )
    allowed = OUTCOMES_BY_SKILL[skill]
    if record["outcome"] not in allowed:
        raise RecordError(
            f"outcome '{record['outcome']}' is not valid for skill '{skill}' "
            "(allowed: " + ", ".join(sorted(allowed)) + ")"
        )

    if not record["mode"]:
        raise RecordError("mode must be a non-empty string")

    out: dict[str, object] = dict(record)

    ts = out.get("ts")
    if ts is None:
        out["ts"] = now or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    elif not TS_RE.match(ts):
        raise RecordError(f"ts '{ts}' is not an ISO-8601 UTC instant (YYYY-MM-DDTHH:MM:SSZ)")

    complexity = out.get("complexity")
    if complexity is not None:
        if complexity not in COMPLEXITY_COLLAPSE:
            raise RecordError(
                f"complexity '{complexity}' is not one of "
                + ", ".join(sorted(COMPLEXITY_COLLAPSE))
            )
        out["complexity"] = COMPLEXITY_COLLAPSE[complexity]

    event_id = out.get("event_id")
    if event_id is not None and not EVENT_ID_RE.match(event_id):
        raise RecordError(
            "event_id must be 1-128 safe identifier characters "
            "([A-Za-z0-9._:-])"
        )

    profile = out.get("profile")
    if profile is not None and profile not in PROFILES:
        raise RecordError(
            f"profile '{profile}' is not one of " + ", ".join(sorted(PROFILES))
        )

    # Absent optional fields are omitted, never written as null. `pr` is the
    # single documented exception and is required, so it is never dropped.
    for key in OPTIONAL_KEYS:
        if key in out and out[key] is None:
            del out[key]

    qa_cycles = out.get("qa_cycles")
    if qa_cycles is not None and _is_int(qa_cycles) and qa_cycles < 0:
        raise RecordError("qa_cycles must be a non-negative integer")

    ceiling = out.get("ceiling")
    if ceiling is not None:
        if not _is_int(ceiling) or ceiling < 1:
            raise RecordError("ceiling must be a positive integer")
    else:
        ceiling = policy_ceiling(out.get("profile"), out.get("complexity"))

    if (
        qa_cycles is not None
        and _is_int(qa_cycles)
        and qa_cycles > ceiling
    ):
        reason = out.get("breach_reason")
        if not isinstance(reason, str) or not reason.strip():
            raise RecordError(
                f"qa_cycles {qa_cycles} exceeds class ceiling {ceiling}; "
                "breach_reason is required"
            )

    return {key: out[key] for key in KEY_ORDER if key in out}


def render(record: dict[str, object]) -> str:
    """One compact JSON line, key order preserved, no trailing newline."""
    return json.dumps(record, separators=(",", ":"), ensure_ascii=False)


def append_line(path: Path, line: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(line + "\n")
        fh.flush()
        os.fsync(fh.fileno())


@contextmanager
def _append_once_lock(path: Path):
    """Hold a portable POSIX advisory lock for an append-once transaction."""
    if fcntl is None:
        raise OSError("portable advisory locking is unavailable on this host")
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.with_name(path.name + ".lock")
    try:
        lock_fh = open(lock_path, "a", encoding="utf-8")
    except OSError as exc:
        raise OSError(f"cannot open append-once lock {lock_path} — {exc}") from exc
    locked = False
    try:
        try:
            fcntl.flock(lock_fh.fileno(), fcntl.LOCK_EX)
            locked = True
        except OSError as exc:
            raise OSError(f"cannot acquire append-once lock {lock_path} — {exc}") from exc
        yield
    finally:
        try:
            if locked:
                fcntl.flock(lock_fh.fileno(), fcntl.LOCK_UN)
        finally:
            lock_fh.close()


def append_once(
    path: Path,
    record: dict[str, object],
    *,
    ts_was_supplied: bool,
    rotate_max_bytes: int = DEFAULT_ROTATE_MAX_BYTES,
    rotate_max_days: int = DEFAULT_ROTATE_MAX_DAYS,
    tail: int = DEFAULT_TAIL_SEGMENTS,
) -> bool:
    """Atomically append by event_id; return False for an identical retry.

    The advisory lock covers the whole cross-process transaction: rotation
    check, read, identical/conflict decision, append, flush, and fsync. A lock
    failure is an OSError so the caller exits 4 and leaves the lane log_pending
    for resume. The dedup scan sees the same tail window as --failure-streak:
    an event_id rotated out of it is outside the idempotency scope.
    """
    event_id = record.get("event_id")
    if not isinstance(event_id, str):
        raise RecordError("--append-once requires event_id")

    with _append_once_lock(path):
        maybe_rotate(path, max_bytes=rotate_max_bytes, max_days=rotate_max_days)

        # An unreadable active log is fatal here — unlike the streak read,
        # appending without seeing it could double-write a parallel lane's
        # event, so exit 4 leaves the lane log_pending for resume instead.
        # A segment that cannot be read only narrows the dedup window.
        lines: list[str] = []
        for segment in segment_paths(path, tail):
            try:
                lines.extend(segment.read_text(encoding="utf-8").splitlines())
            except (OSError, UnicodeDecodeError):
                continue
        try:
            lines.extend(path.read_text(encoding="utf-8").splitlines())
        except FileNotFoundError:
            pass
        except (OSError, UnicodeDecodeError) as exc:
            raise OSError(f"cannot read existing log for append-once — {exc}") from exc

        for raw in lines:
            try:
                existing = json.loads(raw)
            except (json.JSONDecodeError, ValueError):
                continue
            if not isinstance(existing, dict) or existing.get("event_id") != event_id:
                continue
            candidate = dict(record)
            if not ts_was_supplied:
                candidate["ts"] = existing.get("ts")
            if existing == candidate:
                return False
            raise RecordError(
                f"event_id '{event_id}' already exists with a conflicting payload"
            )

        append_line(path, render(record))
        return True


def segment_paths(path: Path, limit: int = DEFAULT_TAIL_SEGMENTS) -> list[Path]:
    """This log's rotated segments, oldest first, at most `limit` of them.

    Segments are `<stem>-<stamp>.jsonl` siblings of the active file — a shape
    that cannot collide with the active log itself or with `runs.jsonl.lock`,
    and whose fixed-width stamps sort in chronological order without parsing.
    """
    try:
        segments = sorted(
            candidate
            for candidate in path.parent.glob(f"{path.stem}-*.jsonl")
            if candidate.is_file()
        )
    except OSError:
        return []
    # `[-0:]` would be `[:]` — every segment — so 0 needs its own branch.
    return segments[-limit:] if limit > 0 else []


def read_log_lines(path: Path, limit: int = DEFAULT_TAIL_SEGMENTS) -> tuple[list[str], bool]:
    """(lines, readable) across the tail window: segments then active, in order.

    The order matters — oldest to newest is append order, so both consumers can
    treat the concatenation exactly like the single file they used to read. A
    component that cannot be opened or decoded is skipped; `readable` is true
    when any component was read, which keeps the fail-open streak contract
    (`exit 4` only when there was nothing at all to read).
    """
    lines: list[str] = []
    readable = False
    for candidate in (*segment_paths(path, limit), path):
        try:
            lines.extend(candidate.read_text(encoding="utf-8").splitlines())
            readable = True
        except (OSError, UnicodeDecodeError):
            continue
    return lines, readable


def rotation_due(path: Path, *, max_bytes: int, max_days: int) -> bool:
    """Whether an append-mode write should rotate first.

    Size reads the byte count; age reads the mtime — how long since the last
    append, not the age of any record inside. Content-based aging would let a
    backdated `ts` field rotate a brand-new log on its second line, and it
    would cost a read on every append to check.
    """
    try:
        stat = path.stat()
    except OSError:
        return False  # missing or unreadable: nothing to rotate yet
    if max_bytes > 0 and stat.st_size >= max_bytes:
        return True
    if max_days > 0:
        idle_s = datetime.now(timezone.utc).timestamp() - stat.st_mtime
        if idle_s >= max_days * 86400:
            return True
    return False


def rotate_log(path: Path, *, now: datetime | None = None) -> Path:
    """Rename the active log to a timestamped segment; return the segment path.

    Same-second collisions get a numeric `-N` suffix rather than clobbering.
    OSError propagates — rotation is best-effort, so callers warn and append
    to the un-rotated file instead of failing the record.
    """
    stamp = (now or datetime.now(timezone.utc)).strftime(SEGMENT_STAMP_FORMAT)
    target = path.with_name(f"{path.stem}-{stamp}.jsonl")
    suffix = 0
    while target.exists():
        suffix += 1
        target = path.with_name(f"{path.stem}-{stamp}-{suffix}.jsonl")
    path.rename(target)
    return target


def maybe_rotate(path: Path, *, max_bytes: int, max_days: int) -> Path | None:
    """Rotate if due; return the segment written, or None. Never raises."""
    if max_bytes <= 0 and max_days <= 0:
        return None
    if not rotation_due(path, max_bytes=max_bytes, max_days=max_days):
        return None
    try:
        return rotate_log(path)
    except OSError as exc:
        print(
            f"⚠ gi-runlog: could not rotate {path} — appending anyway ({exc})",
            file=sys.stderr,
        )
        return None


def count_failure_streak(lines: list[str], issue: int) -> int:
    """Leading run of `failed` outcomes for `issue`, newest record first.

    Scanning backwards is what makes this a *streak* rather than a total: the
    first record for the issue that is not a failure ends the count, so a single
    success clears every failure before it. Lines for other issues are stepped
    over — an unrelated issue's success must not clear this one's streak — and a
    line that does not parse, or that parses to something other than an object,
    is skipped in the same way a reader of this file tolerates unknown keys.
    """
    streak = 0
    for raw in reversed(lines):
        raw = raw.strip()
        if not raw:
            continue
        try:
            record = json.loads(raw)
        except (json.JSONDecodeError, ValueError):
            continue
        if not isinstance(record, dict) or record.get("issue") != issue:
            continue
        if record.get("outcome") != FAILURE_OUTCOME:
            break
        streak += 1
    return streak


def failure_streak(
    path: Path, issue: int, threshold: int, *, tail: int = DEFAULT_TAIL_SEGMENTS
) -> tuple[dict[str, object], bool]:
    """Return the streak verdict for `issue` and whether the log was readable.

    The boolean is the exit code's business, not the verdict's: an unreadable
    log still produces a printable line, and that line says `streak: 0` so the
    caller cannot quarantine on evidence nobody read. The read spans the tail
    window (rotated segments plus the active log), so a streak survives the
    rotation that keeps the active file small.
    """
    lines, readable = read_log_lines(path, tail)

    streak = count_failure_streak(lines, issue) if readable else 0
    return (
        {
            "mode": "failure_streak",
            "issue": issue,
            "streak": streak,
            "threshold": threshold,
            "quarantine": threshold > 0 and streak >= threshold,
        },
        readable,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-runlog.py",
        description=(
            "Validate and normalize one run-log record read as JSON on stdin, "
            "then append it to .gitissue/runs.jsonl (--append) or print it "
            "without writing (--echo); or read the log back to count an issue's "
            "consecutive-failure streak (--failure-streak)."
        ),
        epilog=(
            "Exit codes: 0 ok; 2 usage; 3 invalid record (nothing written); "
            "4 append failed, or the log could not be read (non-fatal — "
            "telemetry is best-effort)."
        ),
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--append",
        action="store_true",
        help="append the normalized line to the run log (default)",
    )
    mode.add_argument(
        "--echo",
        action="store_true",
        help="print the normalized line to stdout and write nothing",
    )
    mode.add_argument(
        "--append-once",
        action="store_true",
        help=(
            "append once by required event_id; an identical retry succeeds "
            "without writing, while a conflicting reuse exits 3"
        ),
    )
    mode.add_argument(
        "--failure-streak",
        type=int,
        metavar="ISSUE",
        help=(
            "read the log and print this issue's leading run of failed "
            "outcomes; reads no stdin and writes nothing"
        ),
    )
    parser.add_argument(
        "--no-rotate",
        action="store_true",
        help=(
            "disable rotation: append to the active log however large or "
            "old it is"
        ),
    )
    parser.add_argument(
        "--path",
        "--log",
        default=DEFAULT_LOG_PATH,
        help=(
            f"run-log file to append to, or read with --failure-streak "
            f"(default: {DEFAULT_LOG_PATH})"
        ),
    )
    parser.add_argument(
        "--threshold",
        type=int,
        default=DEFAULT_QUARANTINE_AFTER,
        metavar="F",
        help=(
            f"--failure-streak: streak at which quarantine is true "
            f"(default {DEFAULT_QUARANTINE_AFTER}; 0 disables quarantine)"
        ),
    )
    parser.add_argument(
        "--rotate-max-bytes",
        type=int,
        default=DEFAULT_ROTATE_MAX_BYTES,
        metavar="N",
        help=(
            "append modes: rotate the active log before writing once it is at "
            f"least this size in bytes (default {DEFAULT_ROTATE_MAX_BYTES}); "
            "0 disables the size trigger"
        ),
    )
    parser.add_argument(
        "--rotate-max-days",
        type=int,
        default=DEFAULT_ROTATE_MAX_DAYS,
        metavar="D",
        help=(
            "append modes: rotate before writing when the log has sat idle "
            f"this many days (mtime-based, default {DEFAULT_ROTATE_MAX_DAYS}); "
            "0 disables the age trigger"
        ),
    )
    parser.add_argument(
        "--tail-segments",
        type=int,
        default=DEFAULT_TAIL_SEGMENTS,
        metavar="K",
        help=(
            "how many of the newest rotated segments reads and dedup scans "
            f"cover, oldest first (default {DEFAULT_TAIL_SEGMENTS})"
        ),
    )
    args = parser.parse_args(argv)

    for name in ("rotate_max_bytes", "rotate_max_days", "tail_segments"):
        if getattr(args, name) < 0:
            print(f"✗ gi-runlog: --{name.replace('_', '-')} must be >= 0", file=sys.stderr)
            return 2

    if args.failure_streak is not None:
        if args.threshold < 0:
            print("✗ gi-runlog: --threshold must be >= 0", file=sys.stderr)
            return 3
        result, readable = failure_streak(
            Path(args.path), args.failure_streak, args.threshold,
            tail=args.tail_segments,
        )
        # The line is printed either way. An exit-4 caller that reads stdout
        # anyway must land on "no streak", never on a stale or invented one.
        print(json.dumps(result, separators=(",", ":"), ensure_ascii=False))
        if not readable:
            print(
                f"⚠ gi-runlog: could not read {args.path} — "
                "reporting a streak of 0 (quarantine progress only, never an "
                "existing quarantine)",
                file=sys.stderr,
            )
            return 4
        return 0

    try:
        raw = sys.stdin.read()
    except UnicodeDecodeError as exc:
        # UnicodeDecodeError subclasses ValueError, not OSError, so nothing else
        # here would catch it and the interpreter would exit 1 with a traceback —
        # a code outside this script's 0/2/3/4 contract. Undecodable stdin can
        # never be a valid JSON record, so it is exit 3: nothing written.
        print(
            f"✗ gi-runlog: stdin is not valid UTF-8 — {exc.reason} at byte {exc.start}",
            file=sys.stderr,
        )
        return 3
    try:
        submitted = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"✗ gi-runlog: stdin is not valid JSON — {exc.msg}", file=sys.stderr)
        return 3

    ts_was_supplied = isinstance(submitted, dict) and submitted.get("ts") is not None
    try:
        record = normalize_record(submitted)
    except RecordError as exc:
        print(f"✗ gi-runlog: {exc}", file=sys.stderr)
        return 3

    line = render(record)
    if args.echo:
        print(line)
        return 0

    try:
        if args.append_once:
            written = append_once(
                Path(args.path),
                record,
                ts_was_supplied=ts_was_supplied,
                rotate_max_bytes=0 if args.no_rotate else args.rotate_max_bytes,
                rotate_max_days=0 if args.no_rotate else args.rotate_max_days,
                tail=args.tail_segments,
            )
            print(
                json.dumps(
                    {
                        "status": "appended" if written else "already_present",
                        "event_id": record["event_id"],
                    },
                    separators=(",", ":"),
                )
            )
        else:
            path = Path(args.path)
            # Plain --append has no lock of its own, so rotation races are
            # tolerated rather than serialized where fcntl is missing: the
            # rename is best-effort and a lost race just appends to the
            # segment instead of the fresh log.
            if not args.no_rotate:
                maybe_rotate(
                    path,
                    max_bytes=args.rotate_max_bytes,
                    max_days=args.rotate_max_days,
                )
            append_line(path, line)
    except RecordError as exc:
        print(f"✗ gi-runlog: {exc}", file=sys.stderr)
        return 3
    except OSError as exc:
        print(f"⚠ gi-runlog: could not append to {args.path} — {exc}", file=sys.stderr)
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
