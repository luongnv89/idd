#!/usr/bin/env python3
"""Answer `/auto-pilot`'s four unattended timing questions, one per invocation.

A run with nobody watching has to decide, without asking: is there enough API
budget to start, how long to pause when there is not, how long to back off
after a transient failure, and whether the wall clock has run out. Every one of
those is arithmetic over a clock — and arithmetic over a clock is exactly what
prose cannot do reproducibly. It lives here instead, where a test can pin
"now" and get the same answer twice.

This script never touches the network and never shells out. The caller makes
the `gh api rate_limit` call and pipes the payload in; the script only decides
what the numbers mean.

Every mode prints exactly **one** line of JSON on stdout.

Modes
  --verdict  read a `gh api rate_limit` payload on stdin and decide whether the
             loop may run: `{"mode":"verdict","action":"proceed|warn|wait|stop",
             "remaining":N,"reset":EPOCH|null,"wait_s":N,"resume_at":ISO|null}`.
             `--threshold` is the remaining-call floor (default 200) and
             `--deadline` an epoch past which pausing is pointless (0 or
             omitted = no wall-clock deadline).

               proceed  remaining is comfortably clear of the floor
               warn     remaining is in the band just above the floor
                        (floor .. floor × 2.5 — 200..500 at the default,
                        the band `/auto-pilot`'s preflight has always used)
               wait     remaining is below the floor and the reset instant
                        fits inside the deadline. Sleep `wait_s`, then re-probe
               stop     remaining is below the floor and waiting would run past
                        the deadline, or the reset instant is unknown

             `wait_s` is 0 for proceed and warn; for `wait` it is the pause to
             take, and for `stop` the pause that did not fit (0 when `reset` is
             unknown). `action: "wait"` is never emitted with a `wait_s` of 0 or
             less — a `reset` already in the past means the payload predates the
             window rollover, which reads as `warn`: proceed, and the next probe
             sees the replenished budget.

  --wait     sleep **at most one chunk** toward `--until`, then return
             `{"mode":"wait","waited_s":N,"remaining_s":N,"done":bool}`. The
             caller loops these invocations and refreshes the run-lock heartbeat
             between chunks, so a pause longer than the lock TTL can never let
             another run reclaim a live lock — and `gi-state.py` stays the
             single writer of `run.lock`. `done` is true once `--until` has been
             reached. When a full further chunk would run past `--deadline`,
             nothing is slept and `waited_s` is 0 with `done` false, so the
             caller stops cleanly instead of overshooting a budget it never
             agreed to.

  --backoff  the next delay in the bounded exponential schedule:
             `{"mode":"backoff","attempt":N,"delay_s":N,"exhausted":bool}`.
             The schedule is fixed and total: attempt 1 → 2s, 2 → 4s, 3 → 8s,
             4 → 16s, and attempt 5 and beyond → `exhausted: true` with
             `delay_s: 0`. Four attempts, 30s of added latency at worst; past
             that a "transient" failure is not transient and the caller falls
             back to its documented degrade. Exhaustion is an **answer**, read
             from the JSON — the exit code stays 0.

  --budget   wall-clock budget against a run's `started_at`:
             `{"mode":"budget","elapsed_s":N,"remaining_s":N|null,
             "expired":bool}`. `--started-at` takes either a bare epoch or the
             `YYYY-MM-DDTHH:MM:SSZ` stamp `gi-state.py` writes into
             `.gitissue/run-state.json`. `--max-minutes 0` means unbounded:
             `remaining_s` is null and `expired` is always false. A
             `started_at` in the future clamps `elapsed_s` to 0 rather than
             going negative — a skewed clock must not manufacture an expiry.

Pinning the clock
  Every mode reads "now" from one place, and `--now` overrides it with either a
  bare epoch or a `YYYY-MM-DDTHH:MM:SSZ` stamp, so a test gets the same answer
  on every run. The same seam exists in-process: each mode function takes a
  `now` argument (and `wait_chunk` an injectable `sleep`), matching
  `gi-ci-wait.py`'s `sleep=time.sleep` parameter.

Exit codes
  0  an answer was computed and printed. `stop`, `expired`, and `exhausted` are
     answers, not errors — read the JSON, never the exit status, to decide.
  2  usage error
  3  invalid input — unparsable JSON on stdin, a payload with no numeric
     `.rate.remaining`, a negative `--max-minutes`, an `--attempt` below 1, or a
     malformed instant (stderr: `✗ gi-ratelimit: <why>`). Stop.
  4  cannot complete — stdin could not be read, or a sleep was interrupted
     before its chunk finished (stderr: `⚠ gi-ratelimit: <reason>`). Callers
     fall back to the documented prose procedure beside the call site.

There is deliberately **no** verdict exit code 1: every non-zero code keeps its
usual meaning at every call site.

Authored at src/shared/scripts/gi-ratelimit.py — do not edit installed copies;
edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from datetime import datetime, timezone

# `/auto-pilot`'s preflight has always stopped below 200 remaining calls and
# warned between 200 and 500. Those are one number and a ratio, not two magic
# constants: the warn band is the floor scaled by 2.5, so a caller that raises
# the floor for a heavier loop keeps a proportional band instead of a warn range
# that silently collapses.
DEFAULT_THRESHOLD = 200
WARN_MULTIPLIER = 2.5

# One chunk of a long pause. The run lock's default TTL is 3600s and its
# heartbeat is refreshed between chunks, so the chunk must stay well under the
# TTL: 300s gives twelve refreshes an hour, which no reasonable clock skew can
# stretch into a stale lock.
DEFAULT_CHUNK_S = 300

# Bounded exponential backoff for recoverable failures. Four attempts, doubling
# from 2s, capped at 16s — 30s of added latency at worst. The delay cap and the
# attempt cap are independent on purpose: raising the attempt count must not
# quietly grow a single sleep without end.
BACKOFF_BASE_S = 2
BACKOFF_MAX_DELAY_S = 16
BACKOFF_MAX_ATTEMPTS = 4

TS_FMT = "%Y-%m-%dT%H:%M:%SZ"
# The same instant format `gi-state.py` writes into `.gitissue/run-state.json`.
TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\Z")
EPOCH_RE = re.compile(r"^\d+\Z")


class InvalidInput(Exception):
    """Caller-supplied input is unusable — exit 3."""


class Unavailable(Exception):
    """The answer could not be computed; the caller falls back to prose — exit 4."""


def _is_int(value: object) -> bool:
    # bool is a subclass of int; a boolean remaining count is a caller bug.
    return isinstance(value, int) and not isinstance(value, bool)


def parse_instant(value: str, flag: str) -> int:
    """Epoch seconds from a bare epoch or a `YYYY-MM-DDTHH:MM:SSZ` stamp.

    Both forms appear in the caller's hands: `gh api rate_limit` reports `reset`
    as an epoch, while `gi-state.py` records `started_at` as an ISO instant.
    Accepting one and rejecting the other would push the conversion into prose.
    """
    text = value.strip()
    if EPOCH_RE.match(text):
        return int(text)
    if TS_RE.match(text):
        return int(
            datetime.strptime(text, TS_FMT).replace(tzinfo=timezone.utc).timestamp()
        )
    raise InvalidInput(
        f"{flag} must be an epoch or YYYY-MM-DDTHH:MM:SSZ, got {value!r}"
    )


def iso(epoch: int) -> str:
    """The repo's canonical UTC instant for an epoch second."""
    return datetime.fromtimestamp(epoch, timezone.utc).strftime(TS_FMT)


def read_rate(payload: object) -> tuple[int, int | None]:
    """Pull `(remaining, reset)` out of a `gh api rate_limit` payload.

    `gh api rate_limit` reports the core budget twice — as the legacy top-level
    `rate` object and as `resources.core`. Either is accepted, `rate` first,
    because a caller that trimmed the payload with `--jq` may have kept only one.
    `remaining` is required; `reset` is not, so a healthy budget still answers
    when the payload omits it.
    """
    if not isinstance(payload, dict):
        raise InvalidInput("stdin must be a single JSON object")

    block: object = payload.get("rate")
    if not isinstance(block, dict):
        resources = payload.get("resources")
        if isinstance(resources, dict):
            block = resources.get("core")
    if not isinstance(block, dict):
        # A payload trimmed all the way down to `{"remaining": …}` is still
        # answerable; anything else is not.
        block = payload

    remaining = block.get("remaining")
    if not _is_int(remaining):
        raise InvalidInput(
            "payload has no integer .rate.remaining (or .resources.core.remaining)"
        )

    reset = block.get("reset")
    return remaining, reset if _is_int(reset) else None


def verdict(
    remaining: int,
    reset: int | None,
    threshold: int,
    deadline: int,
    now: int,
) -> dict[str, object]:
    """Decide whether the loop may run, must warn, must pause, or must stop."""
    warn_below = int(threshold * WARN_MULTIPLIER)
    seconds_to_reset = (reset - now) if reset is not None else 0

    if remaining >= warn_below:
        action, wait_s = "proceed", 0
    elif remaining >= threshold:
        action, wait_s = "warn", 0
    elif seconds_to_reset <= 0:
        # Below the floor, but the reset instant is unknown or already past. An
        # unknown reset cannot be waited for, so it stops; a past reset means the
        # payload predates the window rollover, so warn and let the next probe
        # read the replenished budget. Either way a zero-length "wait" — which a
        # caller would loop on forever — is never emitted.
        action, wait_s = ("stop" if reset is None else "warn"), 0
    elif deadline > 0 and now + seconds_to_reset > deadline:
        # The budget will come back, but not before the run's wall clock runs
        # out. Stopping now leaves a clean, resumable run instead of a process
        # asleep past its own deadline.
        action, wait_s = "stop", seconds_to_reset
    else:
        action, wait_s = "wait", seconds_to_reset

    return {
        "mode": "verdict",
        "action": action,
        "remaining": remaining,
        "reset": reset,
        "wait_s": wait_s,
        "resume_at": iso(now + wait_s) if wait_s > 0 else None,
    }


def wait_chunk(
    until: int,
    deadline: int,
    chunk_s: int,
    now: int,
    sleep=time.sleep,
) -> dict[str, object]:
    """Sleep at most one chunk toward `until` and report what is left.

    One chunk, not the whole pause: between chunks the caller refreshes the run
    lock's heartbeat, which is what keeps a pause longer than the lock TTL from
    letting another run reclaim a lock that is still very much alive.
    """
    remaining_s = max(0, until - now)
    if remaining_s == 0:
        return {"mode": "wait", "waited_s": 0, "remaining_s": 0, "done": True}

    chunk = min(chunk_s, remaining_s)
    # Only sleep when the full chunk still fits inside the budget. Sleeping past
    # the deadline would burn wall clock the caller never agreed to spend, and
    # `done: false` with `waited_s: 0` is exactly the signal it needs to stop.
    if deadline > 0 and now + chunk > deadline:
        return {
            "mode": "wait",
            "waited_s": 0,
            "remaining_s": remaining_s,
            "done": False,
        }

    try:
        sleep(chunk)
    except OSError as exc:
        raise Unavailable(f"sleep was interrupted — {exc}") from exc

    left = max(0, remaining_s - chunk)
    return {
        "mode": "wait",
        # Reported from the chunk the caller agreed to, not from a second clock
        # read: the arithmetic is what makes the answer reproducible, and any
        # real drift is corrected by the next invocation's fresh `now`.
        "waited_s": chunk,
        "remaining_s": left,
        "done": left == 0,
    }


def backoff(attempt: int) -> dict[str, object]:
    """The delay for one attempt of the bounded exponential schedule."""
    if attempt > BACKOFF_MAX_ATTEMPTS:
        return {
            "mode": "backoff",
            "attempt": attempt,
            "delay_s": 0,
            "exhausted": True,
        }
    delay = min(BACKOFF_BASE_S * (2 ** (attempt - 1)), BACKOFF_MAX_DELAY_S)
    return {
        "mode": "backoff",
        "attempt": attempt,
        "delay_s": delay,
        "exhausted": False,
    }


def budget(started_at: int, max_minutes: int, now: int) -> dict[str, object]:
    """Wall-clock elapsed/remaining against a run's `started_at`."""
    # A `started_at` in the future is clock skew, not a negative elapsed time. A
    # negative elapsed would make `remaining_s` exceed the budget and, on the
    # other side of a skew, manufacture an expiry the run never earned.
    elapsed_s = max(0, now - started_at)
    if max_minutes == 0:
        return {
            "mode": "budget",
            "elapsed_s": elapsed_s,
            "remaining_s": None,
            "expired": False,
        }
    remaining_s = max(0, max_minutes * 60 - elapsed_s)
    return {
        "mode": "budget",
        "elapsed_s": elapsed_s,
        "remaining_s": remaining_s,
        "expired": remaining_s == 0,
    }


def report(result: dict[str, object]) -> None:
    """Write the human-readable half of the answer to stderr."""
    mode = result["mode"]
    if mode == "verdict":
        action = result["action"]
        if action == "proceed":
            sys.stderr.write(f"✓ API budget ok — {result['remaining']} calls remaining\n")
        elif action == "warn":
            sys.stderr.write(
                f"⚠ API budget low — {result['remaining']} calls remaining\n"
            )
        elif action == "wait":
            sys.stderr.write(
                f"○ API budget exhausted — pausing {result['wait_s']}s "
                f"until {result['resume_at']}\n"
            )
        else:
            why = (
                "the reset instant is unknown"
                if result["reset"] is None
                else "the reset does not fit the run budget"
            )
            sys.stderr.write(
                f"✗ API budget exhausted — {why} "
                f"({result['remaining']} calls remaining)\n"
            )
    elif mode == "wait":
        if result["done"] and result["waited_s"] == 0:
            sys.stderr.write("✓ Pause complete — nothing left to wait\n")
        elif result["done"]:
            sys.stderr.write(f"✓ Pause complete — slept {result['waited_s']}s\n")
        elif result["waited_s"] == 0:
            sys.stderr.write(
                f"⚠ Pause abandoned — {result['remaining_s']}s left would run past "
                "the run budget\n"
            )
        else:
            sys.stderr.write(
                f"○ Paused {result['waited_s']}s — {result['remaining_s']}s to go\n"
            )
    elif mode == "backoff":
        if result["exhausted"]:
            sys.stderr.write(
                f"✗ Retries exhausted after {BACKOFF_MAX_ATTEMPTS} attempts\n"
            )
        else:
            sys.stderr.write(
                f"○ Retry {result['attempt']}/{BACKOFF_MAX_ATTEMPTS} "
                f"in {result['delay_s']}s\n"
            )
    elif mode == "budget":
        if result["expired"]:
            sys.stderr.write(
                f"⚠ Run budget reached — {result['elapsed_s']}s elapsed\n"
            )
        elif result["remaining_s"] is None:
            sys.stderr.write(
                f"○ Run budget unbounded — {result['elapsed_s']}s elapsed\n"
            )
        else:
            sys.stderr.write(
                f"✓ Run budget ok — {result['remaining_s']}s left "
                f"of {result['elapsed_s'] + result['remaining_s']}s\n"
            )


def _read_stdin() -> str:
    try:
        return sys.stdin.read()
    except UnicodeDecodeError as exc:
        # UnicodeDecodeError subclasses ValueError, not OSError, so nothing else
        # would catch it and the interpreter would exit 1 with a traceback — a
        # code outside this script's 0/2/3/4 contract. Undecodable stdin can
        # never be a rate-limit payload, so it is invalid input, not a degrade.
        raise InvalidInput(
            f"stdin is not valid UTF-8 — {exc.reason} at byte {exc.start}"
        ) from exc
    except OSError as exc:
        raise Unavailable(f"cannot read stdin — {exc}") from exc


def _parse_json(raw: str) -> object:
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise InvalidInput(f"stdin is not valid JSON — {exc.msg}") from exc


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-ratelimit.py",
        description=(
            "Compute one unattended timing answer — rate-limit verdict, chunked "
            "pause, retry backoff, or wall-clock budget — as a single JSON line."
        ),
        epilog=(
            "Example: gh api rate_limit | python3 gi-ratelimit.py --verdict "
            "--threshold 200 --deadline 0"
        ),
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--verdict",
        action="store_true",
        help="decide proceed/warn/wait/stop from a rate_limit payload on stdin",
    )
    mode.add_argument(
        "--wait",
        action="store_true",
        help="sleep at most one chunk toward --until and report what is left",
    )
    mode.add_argument(
        "--backoff",
        action="store_true",
        help="print the delay for one attempt of the bounded backoff schedule",
    )
    mode.add_argument(
        "--budget",
        action="store_true",
        help="report elapsed/remaining wall clock against --started-at",
    )

    parser.add_argument(
        "--threshold",
        type=int,
        default=DEFAULT_THRESHOLD,
        metavar="N",
        help=(
            f"--verdict: remaining-call floor (default {DEFAULT_THRESHOLD}); the "
            f"warn band is the floor up to {WARN_MULTIPLIER}x it"
        ),
    )
    parser.add_argument(
        "--deadline",
        default="0",
        metavar="EPOCH",
        help=(
            "--verdict/--wait: instant past which pausing is pointless "
            "(0 or omitted = no wall-clock deadline)"
        ),
    )
    parser.add_argument(
        "--until",
        metavar="EPOCH",
        help="--wait: the instant to pause until (required with --wait)",
    )
    parser.add_argument(
        "--chunk-s",
        type=int,
        default=DEFAULT_CHUNK_S,
        metavar="S",
        help=(
            f"--wait: longest single sleep (default {DEFAULT_CHUNK_S}); the "
            "caller refreshes the run-lock heartbeat between chunks"
        ),
    )
    parser.add_argument(
        "--attempt",
        type=int,
        metavar="N",
        help="--backoff: 1-based attempt number (required with --backoff)",
    )
    parser.add_argument(
        "--started-at",
        metavar="INSTANT",
        help=(
            "--budget: the run's start, as an epoch or a YYYY-MM-DDTHH:MM:SSZ "
            "stamp (required with --budget)"
        ),
    )
    parser.add_argument(
        "--max-minutes",
        type=int,
        metavar="M",
        default=0,
        help="--budget: wall-clock budget in minutes (0 = unbounded)",
    )
    parser.add_argument(
        "--now",
        metavar="INSTANT",
        help="treat this epoch or YYYY-MM-DDTHH:MM:SSZ instant as now (tests)",
    )
    parser.add_argument(
        "--quiet", action="store_true", help="suppress the stderr report"
    )
    args = parser.parse_args(argv)

    try:
        now = parse_instant(args.now, "--now") if args.now else int(time.time())
        deadline = parse_instant(args.deadline, "--deadline")

        if args.verdict:
            if args.threshold < 0:
                raise InvalidInput("--threshold must be >= 0")
            remaining, reset = read_rate(_parse_json(_read_stdin()))
            result = verdict(remaining, reset, args.threshold, deadline, now)
        elif args.wait:
            if args.until is None:
                raise InvalidInput("--wait requires --until")
            if args.chunk_s < 1:
                raise InvalidInput("--chunk-s must be >= 1")
            until = parse_instant(args.until, "--until")
            result = wait_chunk(until, deadline, args.chunk_s, now)
        elif args.backoff:
            if args.attempt is None:
                raise InvalidInput("--backoff requires --attempt")
            if args.attempt < 1:
                raise InvalidInput("--attempt must be >= 1")
            result = backoff(args.attempt)
        else:
            if args.started_at is None:
                raise InvalidInput("--budget requires --started-at")
            if args.max_minutes < 0:
                raise InvalidInput("--max-minutes must be >= 0 (0 = unbounded)")
            started_at = parse_instant(args.started_at, "--started-at")
            result = budget(started_at, args.max_minutes, now)
    except InvalidInput as exc:
        sys.stderr.write(f"✗ gi-ratelimit: {exc}\n")
        return 3
    except Unavailable as exc:
        sys.stderr.write(f"⚠ gi-ratelimit: {exc}\n")
        return 4

    print(json.dumps(result))
    if not args.quiet:
        report(result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
