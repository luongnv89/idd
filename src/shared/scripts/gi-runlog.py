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
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_LOG_PATH = ".gitissue/runs.jsonl"

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
    "issue",
    "mode",
    "skill",
    "complexity",
    "profile",
    "qa_cycles",
    "outcome",
    "pr",
    "duration_s",
    "skipped_reason",
)

REQUIRED_KEYS = ("ts", "issue", "mode", "skill", "outcome", "pr")
OPTIONAL_KEYS = ("complexity", "profile", "qa_cycles", "duration_s", "skipped_reason")

# `ts` is absent-or-valid: absent is filled from the clock, present must be an
# ISO-8601 UTC instant to the second, exactly as the schema's examples show.
TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")

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

INT_KEYS = ("issue", "qa_cycles", "duration_s")
STR_KEYS = (
    "ts",
    "mode",
    "skill",
    "outcome",
    "profile",
    "complexity",
    "skipped_reason",
)


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

    return {key: out[key] for key in KEY_ORDER if key in out}


def render(record: dict[str, object]) -> str:
    """One compact JSON line, key order preserved, no trailing newline."""
    return json.dumps(record, separators=(",", ":"), ensure_ascii=False)


def append_line(path: Path, line: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(line + "\n")


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


def failure_streak(path: Path, issue: int, threshold: int) -> tuple[dict[str, object], bool]:
    """Return the streak verdict for `issue` and whether the log was readable.

    The boolean is the exit code's business, not the verdict's: an unreadable
    log still produces a printable line, and that line says `streak: 0` so the
    caller cannot quarantine on evidence nobody read.
    """
    readable = True
    lines: list[str] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        readable = False

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
        "--failure-streak",
        type=int,
        metavar="ISSUE",
        help=(
            "read the log and print this issue's leading run of failed "
            "outcomes; reads no stdin and writes nothing"
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
    args = parser.parse_args(argv)

    if args.failure_streak is not None:
        if args.threshold < 0:
            print("✗ gi-runlog: --threshold must be >= 0", file=sys.stderr)
            return 3
        result, readable = failure_streak(
            Path(args.path), args.failure_streak, args.threshold
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
        append_line(Path(args.path), line)
    except OSError as exc:
        print(f"⚠ gi-runlog: could not append to {args.path} — {exc}", file=sys.stderr)
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
