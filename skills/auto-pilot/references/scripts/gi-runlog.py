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

Exit codes
  0  record valid; appended (--append) or printed (--echo)
  2  usage error
  3  record invalid — nothing was written
  4  the append itself failed — the record was valid; writing the run log is
     best-effort and non-fatal, so a caller must not fail its run on this

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


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-runlog.py",
        description=(
            "Validate and normalize one run-log record read as JSON on stdin, "
            "then append it to .gitissue/runs.jsonl (--append) or print it "
            "without writing (--echo)."
        ),
        epilog=(
            "Exit codes: 0 ok; 2 usage; 3 invalid record (nothing written); "
            "4 append failed (non-fatal — telemetry is best-effort)."
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
    parser.add_argument(
        "--path",
        default=DEFAULT_LOG_PATH,
        help=f"run-log file to append to (default: {DEFAULT_LOG_PATH})",
    )
    args = parser.parse_args(argv)

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
