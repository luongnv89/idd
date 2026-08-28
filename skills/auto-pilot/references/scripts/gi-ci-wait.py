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
     "interval_s": <int>, "timeout_s": <int>, "pr": <int or null>,
     "none_grace_s": <int>, "none_confirmed": <bool>,
     "settle_window_s": <int>, "settled": <bool>}

The four verdicts:

  pass     every check reported a terminal non-failing bucket
  fail     at least one check failed or was cancelled; `failing` lists them
  pending  the timeout elapsed with checks still running. Pending is **not**
           clean — a caller must not merge or soft-pass on it
  none     no check was reported for this PR

`none` and `none_confirmed`
---------------------------

"No checks" has two meanings and they are opposite. A repository that configures
no CI reports none forever, and blocking on that deadlocks every merge. A
repository that *does* configure CI also reports none for the first several
seconds after a push, before GitHub registers the workflow runs — and a caller
that merges on that verdict has merged a pull request whose checks had not
started. Asked immediately after a push, the two are indistinguishable from one
poll.

So an empty check list does not end the wait. It keeps polling until
`--none-grace` seconds have passed with no check ever appearing, and only then
is `none_confirmed` true. A `none` verdict with `none_confirmed: false` — the
grace window did not fit inside the timeout, or `--once` was passed — means
"nothing has registered *yet*", which is a pending answer wearing a `none`
label. **Callers must treat `none` as mergeable only when `none_confirmed` is
true.**

Correcting gh's bucket for terminal states
------------------------------------------

`gh pr checks` maps each check to a bucket, and its mapping has no case for
`STARTUP_FAILURE` or `STALE` — both fall to its default, `pending`. Those two
are terminal: nothing about the check will change again. Left as `pending` they
reset the settle window on every poll, so the wait burns the whole `--timeout`
and then answers `pending` — a ten-minute stall followed by a not-clean verdict,
on a check that finished before the first poll. `effective_bucket()` reclassifies
them as `fail`, which is what they are.

The correction is one-way by construction: it only ever promotes `pending` to
`fail`, never anything toward `pass`, and it never touches a bucket gh already
models. An *unmodelled* bucket with no recognized terminal state stays `pending`,
because guessing "done" about something we do not model is the direction that
merges a broken PR.

Non-empty terminal results use a separate settle window. Once a terminal
snapshot appears, its normalized check-name set must remain unchanged for
`--settle-window` seconds before `pass` or `fail` is returned. Additions and
removals reset that window; a pending snapshot also resets it. This catches a
check that registers after an initially green snapshot. Even with
`--settle-window 0`, at least two unchanged terminal observations are required;
`--once` is an explicit single-poll diagnostic escape hatch and therefore
reports the first snapshot without claiming that it settled.

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
import runpy
import sys
import time
from pathlib import Path

_RUN_GH = runpy.run_path(str(Path(__file__).with_name("gi-gh.py")))["run_gh"]

DEFAULT_INTERVAL_S = 30
DEFAULT_TIMEOUT_S = 600

# How long an empty check list has to stay empty before it is believed. Long
# enough to cover the gap between `git push` and GitHub registering a workflow
# run, short enough that a repository with no CI at all is not held up for long.
DEFAULT_NONE_GRACE_S = 60

# How long a terminal check-name set must remain unchanged before its verdict
# is trusted. This is intentionally one polling interval at the default cadence:
# a check that registers on the next poll is observed before merge callers see a
# terminal verdict.
DEFAULT_SETTLE_WINDOW_S = 30

# `gh pr checks --json` buckets. Anything unrecognized is treated as pending:
# guessing "done" about a state we do not model is the failure that merges a
# broken PR, while guessing "running" only costs a wait.
TERMINAL_OK = frozenset({"pass", "skipping"})
TERMINAL_BAD = frozenset({"fail", "cancel"})

# Conclusions GitHub reports as terminal but that `gh pr checks` buckets as
# `pending`: cli/cli's aggregate.go has no case for them, so they fall to its
# default. Left as `pending` they reset the settle window on every poll, so the
# wait burns the whole timeout and then reports `pending` — a stall on a check
# that will never change. Reclassify them as the terminal failures they are.
TERMINAL_BAD_STATES = frozenset({"STARTUP_FAILURE", "STALE"})

# Verdicts that end the wait the moment they are seen. `pending` and `none` are
# both "ask again": the first because a run is still going, the second because
# nothing has registered yet — and until the grace window closes those are the
# same situation.
TERMINAL_VERDICTS = frozenset({"pass", "fail"})

# Without `--json`, gh exits non-zero to *report* check status: 8 = still
# pending, 1 = failing. With `--json` the exporter short-circuits that: whenever
# any check exists gh prints the array and exits 0, so in this script's mode the
# exit status carries no verdict. A non-zero exit here is either a real error or
# the one remaining status answer — "this PR has no checks", which gh reports on
# stderr with one of the markers below. So the payload on stdout is what decides,
# and an empty payload from a non-zero exit with no marker is treated as an error
# rather than as "none".
_NO_CHECKS_MARKERS = ("no checks reported", "no check runs")


class InvalidInput(Exception):
    """Caller-supplied arguments are unusable — exit 3."""


class Unavailable(Exception):
    """The wait could not run; the caller falls back to prose — exit 4."""


def poll_once(pr: str | None, repo: str | None) -> list[dict[str, object]] | None:
    """Return the current check list, or None when the PR reports no checks."""
    args = ["pr", "checks"]
    if pr:
        args.append(pr)
    if repo:
        args += ["--repo", repo]
    args += ["--json", "name,state,bucket,link"]

    proc = _RUN_GH(args, Unavailable)
    code, out, err = proc.returncode, proc.stdout, proc.stderr
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
    # check *status* in gh's non-JSON mode, but with empty stdout and no
    # "no checks" marker they are how gh reports an API 502, a rate limit, or
    # an unresolvable PR. Reading that as "no CI configured" would let a caller
    # merge a PR whose checks it never saw — so it degrades instead.
    detail = err.strip().splitlines()
    raise Unavailable(
        "gh pr checks failed: " + (detail[-1] if detail else f"exit {code}")
    )


def effective_bucket(check: dict[str, object]) -> str:
    """The bucket to classify by, correcting gh's mapping for terminal states.

    One-way only: it promotes `pending` to `fail` for a state gh does not bucket,
    and never moves anything toward `pass`. A bucket gh already models is
    returned untouched, and an unmodelled bucket with no recognized terminal
    state stays exactly as gh reported it — still pending.
    """
    bucket = str(check.get("bucket") or "pending").lower()
    if bucket in TERMINAL_OK or bucket in TERMINAL_BAD:
        return bucket          # never override a bucket gh already models
    if str(check.get("state") or "").upper() in TERMINAL_BAD_STATES:
        return "fail"
    return bucket


def classify(checks: list[dict[str, object]]) -> tuple[str, dict[str, int]]:
    """Reduce a check list to (verdict, per-bucket counts)."""
    counts = {"pass": 0, "fail": 0, "pending": 0, "skipping": 0, "cancel": 0}
    pending = 0
    failing = 0
    for check in checks:
        bucket = effective_bucket(check)
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
    none_grace: int = DEFAULT_NONE_GRACE_S,
    settle_window: int = DEFAULT_SETTLE_WINDOW_S,
    sleep=time.sleep,
    clock=time.monotonic,
) -> dict[str, object]:
    """Poll until the checks settle, the timeout elapses, or none exist.

    An empty check list is not an answer on its own — see `none_confirmed` in
    the module docstring. It is re-polled for `none_grace` seconds, and the
    verdict says whether that window actually elapsed, so a caller can tell "no
    CI is configured" from "the checks have not registered yet".
    """
    started = clock()
    polls = 0
    checks: list[dict[str, object]] = []
    verdict = "none"
    counts = {"pass": 0, "fail": 0, "pending": 0, "skipping": 0, "cancel": 0}
    checks_ever_seen = False
    stable_membership: tuple[str, ...] | None = None
    stable_since: float | None = None
    terminal_observations = 0
    settled = False

    while True:
        polled = poll_once(pr, repo)
        polls += 1
        checks = polled or []
        if checks:
            checks_ever_seen = True
        verdict, counts = classify(checks)
        if polled is None:
            verdict = "none"

        if once:
            # --once is intentionally a diagnostic escape hatch. It cannot
            # establish that the returned snapshot has settled.
            break

        # Re-read the clock after the poll returns and before considering any
        # terminal verdict. A slow gh call may cross the deadline; timeout wins
        # over settlement so a late snapshot can never authorize a merge.
        elapsed = clock() - started
        if elapsed >= timeout:
            verdict = "pending"
            settled = False
            break

        if verdict in TERMINAL_VERDICTS:
            membership = tuple(
                sorted(str(check.get("name") or "") for check in checks)
            )
            if membership != stable_membership:
                stable_membership = membership
                stable_since = clock()
                terminal_observations = 1
            else:
                terminal_observations += 1
            assert stable_since is not None
            stable_elapsed = clock() - stable_since
            if terminal_observations >= 2 and stable_elapsed >= settle_window:
                settled = True
                break
        else:
            # Pending and empty snapshots are not terminal evidence. A later
            # terminal snapshot must establish a fresh settle window.
            stable_membership = None
            stable_since = None
            terminal_observations = 0

        # Only sleep when a full further interval still fits inside the budget.
        # Sleeping past the deadline would report an elapsed time the caller
        # never agreed to wait. A terminal set that has not settled is reported
        # as pending at the deadline, never as an early pass/fail.
        if elapsed + interval > timeout:
            verdict = "pending"
            break
        # An empty list is re-polled only until the grace window closes; a
        # pending or terminal list is re-polled for the whole timeout.
        if verdict == "none" and elapsed >= none_grace:
            break
        sleep(interval)

    elapsed_s = clock() - started
    return {
        "verdict": verdict,
        "checks": checks,
        # Same classifier as `counts` and `verdict`, so the three cannot
        # disagree: a check counted as failing is always listed here.
        "failing": [
            check for check in checks if effective_bucket(check) in TERMINAL_BAD
        ],
        "counts": counts,
        "elapsed_s": int(elapsed_s),
        "polls": polls,
        "interval_s": interval,
        "timeout_s": timeout,
        "pr": int(pr) if pr and pr.isdecimal() else None,
        "none_grace_s": none_grace,
        # False unless the grace window genuinely elapsed with nothing ever
        # registering. `--once` can never confirm it: one poll cannot tell a
        # repository without CI from a push whose checks are seconds away.
        "none_confirmed": bool(
            verdict == "none"
            and not once
            and not checks_ever_seen
            and elapsed_s >= none_grace
        ),
        "settle_window_s": settle_window,
        "settled": settled,
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
            # The effective bucket, not the raw one: a STARTUP_FAILURE entry
            # still carries gh's `bucket: pending`, and printing that under a
            # "CI failed" heading reads as a contradiction.
            sys.stderr.write(f"  ✗ {check.get('name')} ({effective_bucket(check)})\n")
            link = check.get("link")
            if link:
                sys.stderr.write(f"    {link}\n")
    elif verdict == "pending":
        sys.stderr.write(
            f"⚠ CI still running after {result['elapsed_s']}s "
            f"(budget {result['timeout_s']}s) — pending is not clean; "
            "do not merge on it\n"
        )
    elif result["none_confirmed"]:
        sys.stderr.write(
            f"○ No CI checks configured for this PR "
            f"(none seen in {result['none_grace_s']}s)\n"
        )
    else:
        sys.stderr.write(
            "⚠ No checks reported yet, and the grace window did not elapse — "
            "this is 'not registered yet', not 'no CI'; do not merge on it\n"
        )


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
        "--none-grace",
        type=int,
        default=DEFAULT_NONE_GRACE_S,
        metavar="S",
        help=(
            f"seconds an empty check list must stay empty before it counts as "
            f"'no CI configured' (default {DEFAULT_NONE_GRACE_S}); until then "
            "the verdict is none with none_confirmed false"
        ),
    )
    parser.add_argument(
        "--settle-window",
        type=int,
        default=DEFAULT_SETTLE_WINDOW_S,
        metavar="S",
        help=(
            f"seconds a terminal check-name set must remain unchanged before "
            f"its verdict is trusted (default {DEFAULT_SETTLE_WINDOW_S}); "
            "even zero requires two observations"
        ),
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
        if args.none_grace < 0:
            raise InvalidInput("--none-grace must be >= 0")
        if args.settle_window < 0:
            raise InvalidInput("--settle-window must be >= 0")
        result = wait(
            args.pr,
            args.repo,
            args.interval,
            args.timeout,
            once=args.once,
            none_grace=args.none_grace,
            settle_window=args.settle_window,
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
