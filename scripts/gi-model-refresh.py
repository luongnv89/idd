#!/usr/bin/env python3
"""Refresh the bundled CursorBench model-data seed when it is older than the TTL.

The issue-creator skill ships an undated seed of CursorBench model data
(`src/skills/issue-creator/templates/model-data.json`) whose `last_fetched`
ages while the repo sits still. This script is the weekly freshness gate
behind `.github/workflows/model-data-refresh.yml`: it reads the seed's
`last_fetched`, applies the same staleness math gi-model-cache.py uses at
skill runtime, and only when the seed is past the TTL does it fetch the
source URL, push the payload through the same validation boundary, and
rewrite the seed atomically.

CI-only tooling — deliberately *not* under `src/shared/scripts/`: nothing
cites it from any skill, so the shared-script rules would refuse to ship it
(tests/test-build-script.sh T8 requires every script there to ship into a
skill). It runs straight from this checkout in the scheduled workflow and
nowhere else.

Output on stdout, one JSON object:

    {"updated": false, "reason": "fresh",
     "last_fetched": "2026-08-20T00:00:00Z", "age_days": 3, "ttl_days": 7}

    {"updated": true, "previous_last_fetched": "2026-06-12T00:00:00Z",
     "last_fetched": "2026-08-22T00:00:00Z", "data_url": "…",
     "age_days": 71, "ttl_days": 7}

Exit codes
  0  the seed is in a good state — either fresher than the TTL (update
     skipped) or a fetched replacement passed validation and was written
  2  usage error
  3  caller-supplied input is unusable — a missing, unreadable, or corrupt
     seed, a negative `--ttl-days`, or a malformed `--now` / `--from-file`
     path (stderr: `✗ …`). Stop; the old seed is untouched. Unlike
     gi-model-cache, these are exit 3 rather than 4: here the seed is an
     explicit argument of this very invocation, not ambient state the caller
     asked the script to find.
  4  cannot complete — the fetch failed, or the fetched payload did not
     parse or validate (stderr: `⚠ …`). Degrade: keep the current seed and
     let CI report a warning. A bad fetch never corrupts the seed, exactly
     as gi-model-cache refuses to let a bad `--install` payload clobber a
     good cache.

CursorBench publishes an HTML page, not a documented JSON API — so the fetch
is expected to fail validation most weeks. That is the designed degrade, not
a defect: the workflow logs the warning and keeps the last good snapshot.

TTL math, size caps, parsing, and whole-tree validation are imported from
`gi_model_cache` (the authored source of the shipped gi-model-cache.py)
rather than duplicated, so the two can never drift apart.

Authored at scripts/gi-model-refresh.py — CI-only; not bundled into skills.
"""

from __future__ import annotations

import argparse
import datetime as dt
import importlib.util
import json
import os
import re
import sys
import tempfile
import urllib.request

_HERE = os.path.dirname(os.path.abspath(__file__))
# gi-model-cache.py carries hyphens, so it cannot be a plain `import`; load it
# by path instead. Same authored source the build ships into issue-creator.
_CACHE_SOURCE = os.path.normpath(
    os.path.join(
        _HERE, os.pardir, "src", "shared", "scripts", "gi-model-cache.py"
    )
)
_SPEC = importlib.util.spec_from_file_location("gi_model_cache", _CACHE_SOURCE)
if _SPEC is None or _SPEC.loader is None:  # pragma: no cover - missing source
    raise SystemExit(f"✗ gi-model-cache source not found at {_CACHE_SOURCE}")
cache = importlib.util.module_from_spec(_SPEC)
sys.modules["gi_model_cache"] = cache
_SPEC.loader.exec_module(cache)

DEFAULT_SEED = os.path.normpath(
    os.path.join(
        _HERE, os.pardir, "src", "skills", "issue-creator", "templates", "model-data.json"
    )
)
DEFAULT_DATA_URL = "https://cursor.com/cursorbench"
FETCH_TIMEOUT_S = 30


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="gi-model-refresh.py",
        description=(
            "Refresh the bundled CursorBench model-data seed when its "
            "last_fetched is older than the TTL. Prints one JSON object on "
            "stdout."
        ),
        epilog=(
            "Example: python3 scripts/gi-model-refresh.py "
            "--seed src/skills/issue-creator/templates/model-data.json"
        ),
    )
    parser.add_argument(
        "--seed", metavar="PATH", default=DEFAULT_SEED,
        help=f"model-data seed to inspect and rewrite (default: {os.path.relpath(DEFAULT_SEED, os.path.dirname(_HERE))})",
    )
    parser.add_argument(
        "--data-url", metavar="URL", default=DEFAULT_DATA_URL,
        help=f"source fetched when the seed is stale (default: {DEFAULT_DATA_URL})",
    )
    parser.add_argument(
        "--ttl-days", type=int, metavar="N", default=cache.DEFAULT_TTL_DAYS,
        help=f"staleness threshold in days (default {cache.DEFAULT_TTL_DAYS}, matching model_suggestion.cache_ttl_days)",
    )
    parser.add_argument(
        "--now", metavar="YYYY-MM-DD", help="treat this day as today (tests)"
    )
    parser.add_argument(
        "--from-file", metavar="PATH",
        help="use the local file as the would-be-fetched payload instead of "
             "the network (test hook — never used outside tests)",
    )
    return parser


def resolve_today(raw: str | None) -> dt.date:
    if raw is None:
        return dt.datetime.now(dt.timezone.utc).date()
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", raw):
        raise cache.InvalidInput(f"--now must be YYYY-MM-DD, got {raw!r}")
    try:
        return cache.parse_day(raw)
    except ValueError as exc:
        raise cache.InvalidInput(f"--now is not a real calendar date: {raw}") from exc


def load_seed(path: str) -> tuple[dict, str]:
    """Load and validate the seed. Every seed problem is exit 3 — see header."""
    if not os.path.isfile(path):
        raise cache.InvalidInput(f"--seed is not a file: {path}")
    try:
        payload = cache.load_payload(path, "bundled model-data seed")
        date = cache.last_fetched_date(payload, "bundled model-data seed")
    except cache.Unavailable as exc:
        raise cache.InvalidInput(str(exc)) from exc
    return payload, date


def fetch(url: str) -> str:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": (
                "idd-gi-model-refresh/1.0 (+https://github.com/luongnv89/idd)"
            )
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=FETCH_TIMEOUT_S) as response:
            raw = response.read(cache.MAX_PAYLOAD_BYTES + 1)
    except OSError as exc:  # URLError, socket timeouts, HTTPError all land here
        raise cache.Unavailable(f"fetching {url} failed — {exc}") from exc
    if len(raw) > cache.MAX_PAYLOAD_BYTES:
        raise cache.Unavailable(
            f"the fetched payload exceeds the {cache.MAX_PAYLOAD_BYTES}-byte cap"
        )
    return raw.decode("utf-8", errors="replace")


def fetch_payload_text(args: argparse.Namespace) -> str:
    if args.from_file:
        try:
            return cache.read_capped(args.from_file, "--from-file payload")
        except OSError as exc:
            raise cache.InvalidInput(
                f"cannot read --from-file {args.from_file} — {exc}"
            ) from exc
        except ValueError as exc:
            raise cache.Unavailable(str(exc)) from exc
    return fetch(args.data_url)


def build_refreshed(old: dict, fetched_text: str, today: dt.date, url: str) -> dict:
    """Validate the fetch and stamp it. Any payload problem is exit 4."""
    try:
        fetched = cache.parse_model_data(fetched_text, "fetched CursorBench payload")
    except ValueError as exc:
        raise cache.Unavailable(str(exc)) from exc
    refreshed = dict(fetched)
    refreshed.setdefault("schema_version", old.get("schema_version", 1))
    refreshed.setdefault("source_url", url)
    refreshed["last_fetched"] = f"{today.isoformat()}T00:00:00Z"
    # The merge above touched the document after the boundary walked it, so
    # walk the final form too — the bytes written are the bytes validated.
    try:
        return cache.validate_payload(refreshed, "refreshed model-data payload")
    except ValueError as exc:
        raise cache.Unavailable(f"the refreshed payload fails validation — {exc}") from exc


def atomic_write(path: str, payload: dict) -> None:
    """Replace `path` atomically, keeping its mode (mirrors gi-model-cache's
    write_cache discipline: unpredictable O_EXCL temp name, explicit mode,
    same-directory rename)."""
    directory = os.path.dirname(os.path.abspath(path))
    mode = os.stat(path).st_mode & 0o777
    temp = None
    try:
        fd, temp = tempfile.mkstemp(dir=directory, prefix=".model-data.", suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            # allow_nan=False keeps the seed RFC 8259 even though validate
            # already refused non-finite numbers — defence at the writer.
            handle.write(json.dumps(payload, indent=2, allow_nan=False))
            handle.write("\n")
            os.fchmod(handle.fileno(), mode)
        os.replace(temp, path)
        temp = None
    except (OSError, ValueError, RecursionError) as exc:
        raise cache.Unavailable(f"cannot write {path} — {exc}") from exc
    finally:
        if temp is not None:
            try:
                os.remove(temp)
            except OSError:
                pass


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        seed_path = os.path.abspath(args.seed)
        if args.ttl_days < 0:
            raise cache.InvalidInput(
                f"--ttl-days must be >= 0, got {args.ttl_days}"
            )
        today = resolve_today(args.now)
        old, date = load_seed(seed_path)

        age_days = (today - cache.parse_day(date)).days
        stale = args.ttl_days > 0 and age_days > args.ttl_days
        if not stale:
            print(
                json.dumps(
                    {
                        "updated": False,
                        "reason": "fresh",
                        "last_fetched": old.get("last_fetched"),
                        "age_days": age_days,
                        "ttl_days": args.ttl_days,
                    }
                )
            )
            sys.stderr.write(
                f"✓ model data fresher than {args.ttl_days} days — skipping "
                f"update (age {age_days}, last_fetched {date})\n"
            )
            return 0

        fetched_text = fetch_payload_text(args)
        refreshed = build_refreshed(old, fetched_text, today, args.data_url)
        atomic_write(seed_path, refreshed)
        print(
            json.dumps(
                {
                    "updated": True,
                    "previous_last_fetched": old.get("last_fetched"),
                    "last_fetched": refreshed.get("last_fetched"),
                    "data_url": args.data_url,
                    "age_days": age_days,
                    "ttl_days": args.ttl_days,
                }
            )
        )
        sys.stderr.write(
            f"✓ model data refreshed from {args.data_url} "
            f"(was {age_days} days old) — seed rewritten\n"
        )
        return 0
    except cache.InvalidInput as exc:
        sys.stderr.write(f"✗ gi-model-refresh: {exc}\n")
        return 3
    except cache.Unavailable as exc:
        sys.stderr.write(f"⚠ gi-model-refresh: {exc}\n")
        return 4


if __name__ == "__main__":
    sys.exit(main())
