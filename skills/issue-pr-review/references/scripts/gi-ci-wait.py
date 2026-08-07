#!/usr/bin/env python3
"""Wait for a pull request's CI checks to settle and print one JSON verdict.

Polling is a loop, and a loop expressed as prose costs one agent tool call per
iteration: a ten-minute wait at a thirty-second interval is twenty round trips
through the main agent's context to learn one fact. This script performs the
whole wait in a single invocation and returns the answer once.

Output on success is exactly one line of JSON on stdout:

    {"verdict": "pass" | "fail" | "pending" | "none",
     "checks": [{"name": ..., "state": ..., "bucket": ...}, ...],
     "failing": [{"name": ..., "state": ..., "bucket": ..., "link": ...}, ...],
     "counts": {"pass": n, "fail": n, "pending": n, "skipping": n, "cancel": n},
     "elapsed_s": <int>, "polls": <int>,
     "interval_s": <int>, "timeout_s": <int>, "pr": <int or null>}

The four verdicts:

  pass     every check reported a terminal non-failing bucket
  fail     at least one check failed or was cancelled; `failing` lists them
  pending  the timeout elapsed with checks still running. Pending is **not**
           clean — a caller must not merge or soft-pass on it
  none     the repository reports no checks for this PR at all

Exit codes
  0  a verdict was reached and printed — including `fail` and `pending`, which
     are answers, not errors. Read `verdict`, never the exit status, to decide.
  2  usage error
  3  invalid input — a non-numeric PR number, or a non-positive interval or
     timeout (stderr: `✗ gi-ci-wait: <why>`). Stop.
  4  cannot complete — `gh` is missing, unauthenticated, or the PR cannot be
     resolved (stderr: `⚠ gi-ci-wait: <reason>`). Callers fall back to the
     documented manual polling procedure.

Authored at src/shared/scripts/gi-ci-wait.py — do not edit installed copies;
edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time

DEFAULT_INTERVAL_S = 30
DEFAULT_TIMEOUT_S = 600

# `gh pr checks --json` buckets. Anything unrecognized is treated as pending:
# guessing "done" about a state we do not model is the failure that merges a
# broken PR, while guessing "running" only costs a wait.
TERMINAL_OK = frozenset({"pass", "skipping"})
TERMINAL_BAD = frozenset({"fail", "cancel"})

# gh exits non-zero to *report* check status: 8 = still pending, 1 = failing or
# "no checks". Those are verdicts, so the exit status alone cannot distinguish
# them from a real error — the payload on stdout is what decides, and an empty
# payload from a non-zero exit is treated as an error rather than as "none".
_NO_CHECKS_MARKERS = ("no checks reported", "no check runs")


class InvalidInput(Exception):
    """Caller-supplied arguments are unusable — exit 3."""


class Unavailable(Exception):
    """The wait could not run; the caller falls back to prose — exit 4."""


def _run_gh(args: list[str]) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(
            ["gh", *args], capture_output=True, text=True, check=False
        )
    except FileNotFoundError as exc:
        raise Unavailable("gh is not installed or not on PATH") from exc
    except OSError as exc:
        raise Unavailable(f"cannot run gh — {exc}") from exc
    return proc.returncode, proc.stdout, proc.stderr


def poll_once(pr: str | None, repo: str | None) -> list[dict[str, object]] | None:
    """Return the current check list, or None when the PR reports no checks."""
    args = ["pr", "checks"]
    if pr:
        args.append(pr)
    if repo:
        args += ["--repo", repo]
    args += ["--json", "name,state,bucket,link"]

    code, out, err = _run_gh(args)
    stripped = out.strip()
    if stripped:
        try:
            loaded = json.loads(stripped)
        except json.JSONDecodeError as exc:
            raise Unavailable(f"gh printed unparsable JSON — {exc}") from exc
        if not isinstance(loaded, list):
            raise Unavailable("gh pr checks did not return a JSON array")
        return [item for item in loaded if isinstance(item, dict)]

    lowered = err.lower()
    if any(marker in lowered for marker in _NO_CHECKS_MARKERS):
        return None
    if code == 0:
        # gh succeeded and printed nothing: there are genuinely no checks.
        return None
    # Everything else is an error, including exits 1 and 8. Those two carry
    # check *status* when there is a payload, but with empty stdout and no
    # "no checks" marker they are how gh reports an API 502, a rate limit, or
    # an unresolvable PR. Reading that as "no CI configured" would let a caller
    # merge a PR whose checks it never saw — so it degrades instead.
    detail = err.strip().splitlines()
    raise Unavailable(
        "gh pr checks failed: " + (detail[-1] if detail else f"exit {code}")
    )


def classify(checks: list[dict[str, object]]) -> tuple[str, dict[str, int]]:
    """Reduce a check list to (verdict, per-bucket counts)."""
    counts = {"pass": 0, "fail": 0, "pending": 0, "skipping": 0, "cancel": 0}
    pending = 0
    failing = 0
    for check in checks:
        bucket = str(check.get("bucket") or "pending").lower()
        counts[bucket] = counts.get(bucket, 0) + 1
        if bucket in TERMINAL_BAD:
            failing += 1
        elif bucket not in TERMINAL_OK:
            pending += 1
    if not checks:
        return "none", counts
    if pending:
        return "pending", counts
    return ("fail" if failing else "pass"), counts


def wait(
    pr: str | None,
    repo: str | None,
    interval: int,
    timeout: int,
    once: bool = False,
    sleep=time.sleep,
    clock=time.monotonic,
) -> dict[str, object]:
    """Poll until the checks settle, the timeout elapses, or none exist."""
    started = clock()
    polls = 0
    checks: list[dict[str, object]] = []
    verdict = "none"
    counts = {"pass": 0, "fail": 0, "pending": 0, "skipping": 0, "cancel": 0}

    while True:
        polled = poll_once(pr, repo)
        polls += 1
        checks = polled or []
        verdict, counts = classify(checks)
        if polled is None:
            verdict = "none"
        if verdict != "pending" or once:
            break
        elapsed = clock() - started
        # Only sleep when a full further interval still fits inside the budget.
        # Sleeping past the deadline would report an elapsed time the caller
        # never agreed to wait.
        if elapsed + interval > timeout:
            break
        sleep(interval)

    return {
        "verdict": verdict,
        "checks": checks,
        "failing": [
            check
            for check in checks
            if str(check.get("bucket") or "").lower() in TERMINAL_BAD
        ],
        "counts": counts,
        "elapsed_s": int(clock() - started),
        "polls": polls,
        "interval_s": interval,
        "timeout_s": timeout,
        "pr": int(pr) if pr and pr.isdecimal() else None,
    }


def report(result: dict[str, object]) -> None:
    """Write the human-readable half of the verdict to stderr."""
    verdict = result["verdict"]
    counts = result["counts"]
    total = len(result["checks"])  # type: ignore[arg-type]
    if verdict == "pass":
        sys.stderr.write(f"✓ CI passed — {total} checks green\n")
    elif verdict == "fail":
        sys.stderr.write(f"✗ CI failed — {counts['fail'] + counts['cancel']} of {total} checks\n")
        for check in result["failing"]:  # type: ignore[union-attr]
            sys.stderr.write(f"  ✗ {check.get('name')} ({check.get('bucket')})\n")
            link = check.get("link")
            if link:
                sys.stderr.write(f"    {link}\n")
    elif verdict == "pending":
        sys.stderr.write(
            f"⚠ CI still running after {result['elapsed_s']}s "
            f"(budget {result['timeout_s']}s) — pending is not clean; "
            "do not merge on it\n"
        )
    else:
        sys.stderr.write("○ No CI checks configured for this PR\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-ci-wait.py",
        description=(
            "Poll a pull request's CI checks until they settle or the timeout "
            "elapses; print one JSON verdict on stdout."
        ),
        epilog="Example: python3 gi-ci-wait.py 42 --interval 30 --timeout 600",
    )
    parser.add_argument("pr", nargs="?", help="PR number (default: current branch)")
    parser.add_argument("--repo", metavar="OWNER/NAME")
    parser.add_argument(
        "--interval",
        type=int,
        default=DEFAULT_INTERVAL_S,
        metavar="S",
        help=f"seconds between polls (default {DEFAULT_INTERVAL_S})",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=DEFAULT_TIMEOUT_S,
        metavar="S",
        help=f"give up after S seconds (default {DEFAULT_TIMEOUT_S})",
    )
    parser.add_argument(
        "--once", action="store_true", help="poll a single time and report"
    )
    parser.add_argument("--quiet", action="store_true", help="suppress the stderr report")
    args = parser.parse_args(argv)

    try:
        if args.pr is not None and not args.pr.isdecimal():
            # isdecimal(), not isdigit(): the latter accepts Unicode digits that
            # int() rejects, and the ValueError would escape main().
            raise InvalidInput(f"PR must be a number, got {args.pr!r}")
        if args.interval < 1:
            raise InvalidInput("--interval must be >= 1")
        if args.timeout < 1:
            raise InvalidInput("--timeout must be >= 1")
        result = wait(
            args.pr, args.repo, args.interval, args.timeout, once=args.once
        )
    except InvalidInput as exc:
        sys.stderr.write(f"✗ gi-ci-wait: {exc}\n")
        return 3
    except Unavailable as exc:
        sys.stderr.write(f"⚠ gi-ci-wait: {exc}\n")
        return 4

    print(json.dumps(result))
    if not args.quiet:
        report(result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
