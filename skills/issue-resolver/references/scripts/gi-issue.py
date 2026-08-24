#!/usr/bin/env python3
"""Fetch a GitHub issue through a short-lived on-disk cache.

One issue is read four or five times across a single resolve lifecycle —
preflight, normalization, the researcher's scan, acceptance-criteria
verification, the closing report — and every read is a network round trip whose
answer has not changed. This script serves those repeat reads from
`.gitissue/cache/`, so the first call pays for the fetch and the rest do not.

The cache is deliberately *short*-lived and per-repository. An issue's body can
change mid-run (the resolver normalizes it), so a stale read is a real hazard;
the TTL exists to collapse a burst of reads inside one step, not to remember an
issue between sessions. Anything that edits an issue must pass `--refresh` on
its next read, or call `--invalidate` after the edit.

Output on success is exactly one line of JSON on stdout: the `gh issue view
--json` payload, unmodified, wrapped in an envelope that records where it came
from:

    {"issue": {<the gh payload>}, "cached": true|false,
     "age_s": <int>, "fields": [...], "number": <int>}

Field lists are the caller's choice — this script never invents them. A cache
entry is keyed by issue number *and* the exact field set, so asking for
`number,title` never returns a payload fetched for `body` alone and silently
missing the field the caller wanted.

Exit codes
  0  payload printed (from cache or from a fresh fetch)
  2  usage error
  3  invalid input — a non-numeric issue number, a malformed field list, or a
     negative TTL (stderr: `✗ gi-issue: <why>`). Stop.
  4  cannot complete — `gh` is missing or unauthenticated, the issue does not
     exist, or the payload is unparsable (stderr: `⚠ gi-issue: <reason>`).
     Callers fall back to calling `gh issue view` directly.

Authored at src/shared/scripts/gi-issue.py — do not edit installed copies; edit
the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import runpy
import sys
import tempfile
import time
from pathlib import Path

_RUN_GH = runpy.run_path(str(Path(__file__).with_name("gi-gh.py")))["run_gh"]

DEFAULT_TTL_S = 300
CACHE_DIRNAME = Path(".gitissue") / "cache"

# gh's own field vocabulary is lowerCamelCase; anything else is a typo that
# would otherwise surface as an opaque gh error several layers away.
FIELD_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9]*$")

# Cache files are written 0600: an issue body can carry a security report long
# before the issue is public, and a world-readable copy under the repo is a
# quieter leak than the issue itself.
_CACHE_MODE = 0o600


class InvalidInput(Exception):
    """Caller-supplied arguments are unusable — exit 3."""


class Unavailable(Exception):
    """The fetch could not run; the caller falls back to prose — exit 4."""


def parse_fields(raw: str) -> list[str]:
    """Split and validate a comma-separated gh field list."""
    fields = [part.strip() for part in raw.split(",")]
    fields = [field for field in fields if field]
    if not fields:
        raise InvalidInput("--fields must name at least one field")
    for field in fields:
        if not FIELD_RE.match(field):
            raise InvalidInput(f"not a valid gh field name: {field!r}")
    # Sorted for the cache key only; gh is handed the caller's own order.
    return fields


def cache_path(root: Path, number: int, fields: list[str], repo: str | None) -> Path:
    """Where this (issue, field set, repo) triple is cached."""
    key = ",".join(sorted(fields))
    # A short digest keeps the filename bounded whatever the field list is;
    # the issue number stays in the clear so a human can find and delete one.
    scope = f"{repo or ''}|{key}"
    digest = hashlib.sha256(scope.encode("utf-8")).hexdigest()[:12]
    return root / f"issue-{number}-{digest}.json"


def read_cache(path: Path, ttl: int) -> tuple[dict | None, int]:
    """Return (payload, age) when a fresh entry exists, else (None, 0)."""
    if ttl <= 0:
        return None, 0
    try:
        age = int(time.time() - path.stat().st_mtime)
    except OSError:
        return None, 0
    if age > ttl:
        return None, age
    try:
        loaded = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        # A truncated or half-written entry is a miss, never an error: the
        # authoritative copy is one network call away.
        return None, age
    return (loaded if isinstance(loaded, dict) else None), age


def write_cache(path: Path, payload: dict) -> None:
    """Best-effort cache write — a cache that cannot be written is still a hit
    ratio of zero, not a failure."""
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        # mkstemp gives every writer its own temp name: two concurrent fetches
        # writing the same entry can no longer tear each other's temp file the
        # way a shared fixed `.tmp` name let them. Written then renamed so a
        # concurrent reader never sees half a file.
        fd, temp = tempfile.mkstemp(
            prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent)
        )
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(payload, handle)
            # mkstemp creates 0600; keep the documented _CACHE_MODE.
            os.chmod(temp, _CACHE_MODE)
            os.replace(temp, path)
        except BaseException:
            try:
                os.close(fd)  # no-op if fdopen already took ownership
            except OSError:
                pass
            try:
                os.unlink(temp)
            except OSError:
                pass
            raise
    except OSError:
        return


def fetch(number: int, fields: list[str], repo: str | None) -> dict:
    """Call `gh issue view` with an explicit field selection."""
    args = ["issue", "view", str(number), "--json", ",".join(fields)]
    if repo:
        args += ["--repo", repo]
    proc = _RUN_GH(args, Unavailable)
    if proc.returncode != 0:
        detail = proc.stderr.strip().splitlines()
        raise Unavailable(
            f"gh issue view {number} failed: "
            + (detail[-1] if detail else f"exit {proc.returncode}")
        )
    try:
        loaded = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise Unavailable(f"gh printed unparsable JSON — {exc}") from exc
    if not isinstance(loaded, dict):
        raise Unavailable("gh issue view did not return a JSON object")
    return loaded


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-issue.py",
        description=(
            "Fetch a GitHub issue with an explicit --json field selection, "
            "serving repeat reads from a short-lived on-disk cache."
        ),
        epilog=(
            "Example: python3 gi-issue.py 42 --fields number,title,body,labels,state"
        ),
    )
    parser.add_argument("number", help="issue number")
    parser.add_argument(
        "--fields",
        default="number,title,body,labels,state",
        help="comma-separated gh field list (caller's choice)",
    )
    parser.add_argument("--repo", metavar="OWNER/NAME")
    parser.add_argument(
        "--ttl",
        type=int,
        default=DEFAULT_TTL_S,
        metavar="S",
        help=f"serve a cache entry younger than S seconds (default {DEFAULT_TTL_S}; 0 disables)",
    )
    parser.add_argument(
        "--refresh", action="store_true", help="ignore any cache entry and refetch"
    )
    parser.add_argument(
        "--invalidate",
        action="store_true",
        help="drop every cache entry for this issue and exit without fetching",
    )
    parser.add_argument(
        "--cache-dir",
        metavar="DIR",
        help=f"cache location (default {CACHE_DIRNAME} under the working directory)",
    )
    args = parser.parse_args(argv)

    try:
        if not args.number.isdecimal():
            # isdigit() accepts superscripts and other Unicode digits that int()
            # then rejects, raising out of main() as exit 1 with a traceback.
            raise InvalidInput(f"issue must be a number, got {args.number!r}")
        number = int(args.number)
        if args.ttl < 0:
            raise InvalidInput("--ttl must be >= 0")
        fields = parse_fields(args.fields)
        root = Path(args.cache_dir) if args.cache_dir else Path.cwd() / CACHE_DIRNAME

        if args.invalidate:
            dropped = 0
            for stale in root.glob(f"issue-{number}-*.json"):
                try:
                    stale.unlink()
                    dropped += 1
                except OSError:
                    continue
            print(json.dumps({"invalidated": number, "dropped": dropped}))
            return 0

        path = cache_path(root, number, fields, args.repo)
        payload, age = (None, 0) if args.refresh else read_cache(path, args.ttl)
        cached = payload is not None
        if payload is None:
            payload = fetch(number, fields, args.repo)
            age = 0
            if args.ttl > 0:
                write_cache(path, payload)
    except InvalidInput as exc:
        sys.stderr.write(f"✗ gi-issue: {exc}\n")
        return 3
    except Unavailable as exc:
        sys.stderr.write(f"⚠ gi-issue: {exc}\n")
        return 4

    print(
        json.dumps(
            {
                "issue": payload,
                "cached": cached,
                "age_s": age if cached else 0,
                "fields": fields,
                "number": number,
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
