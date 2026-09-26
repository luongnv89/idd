#!/usr/bin/env python3
# gi-requires: references/scripts/gi-gh.py
"""Serve the open-issue list from one short-lived snapshot shared across skills.

`/issue-triage` and `/issue-creator`'s duplicate scorer each read the open
backlog, and each used to pay for its own `gh issue list`. This script fetches
the list once — always the full field superset, so any consumer's projection is
a subset of what is on disk — and writes it to
`.gitissue/cache/backlog-open-<sha12(repo)>.json`. The next consumer inside the
TTL reads the file instead of the network.

Freshness rule. A snapshot is served only when *all* of these hold:

  (a) caching is on (`--ttl` > 0, no `--refresh`) and the snapshot's age,
      `now - meta.fetched_at`, is between 0 and the TTL (default 300 s);
  (b) the requested fields are a subset of `meta.fields`;
  (c) the snapshot holds enough rows: the requested limit + 1 is at most
      `meta.fetch_limit`, or `meta.row_count < meta.fetch_limit` (the whole
      backlog was captured, so any limit is answerable);
  (d) `meta.repo` equals the requested `--repo`.

Anything else — no file, unparsable JSON, a wrong shape, mismatched meta, a
timestamp in the future — is a **miss**: fetch live, overwrite the snapshot,
answer. A bad snapshot is never an error, because the authoritative copy is one
network call away. A snapshot that cannot be written is not an error either.

Every fetch asks gh for `limit + 1` rows. The extra row is the truncation probe
and never leaves this script: callers receive at most `limit` rows and a
`truncated` flag (`row_count > limit`).

`--ttl 0` bypasses the cached *read* but still writes the fresh snapshot, so an
automated caller that must see a live list still leaves one behind for the next
reader. (`gi-issue.py`'s `--ttl 0` skips the write as well — the difference is
deliberate.) `--refresh` does the same for one call; `--status` reports a
snapshot's age and freshness without fetching; `--invalidate` deletes every
snapshot in the cache directory — anything that creates or edits an issue runs
it so the next dedup scan sees the change.

Output on success is one JSON line on stdout:

    {"issues": [...], "cached": true|false, "age_s": <int>, "ttl": <int>,
     "truncated": true|false, "limit": <int>, "fields": [...]}

With `--out FILE` the bare issue array is written to FILE instead and the
envelope is printed without `issues`.

Exit codes
  0  list printed (from the snapshot or a fresh fetch); also --status/--invalidate
  2  usage error
  3  invalid input — a field outside the superset, a limit < 1, or a negative
     TTL (stderr: `✗ gi-backlog: <why>`). Stop.
  4  cannot complete — `gh` is missing or failed, or printed unparsable JSON
     (stderr: `⚠ gi-backlog: <reason>`). Callers fall back to `gh issue list`.

Authored at src/shared/scripts/gi-backlog.py — do not edit installed copies;
edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import runpy
import sys
import tempfile
import time
from pathlib import Path

_RUN_GH = runpy.run_path(str(Path(__file__).with_name("gi-gh.py")))["run_gh"]

DEFAULT_TTL_S = 300
DEFAULT_LIMIT = 100
CACHE_DIRNAME = Path(".gitissue") / "cache"
SUPERSET = (
    "number", "title", "body", "labels", "assignees", "state", "createdAt",
    "updatedAt",
)
# Same 0600 rule as gi-issue.py: bodies may carry an embargoed security report.
_CACHE_MODE = 0o600


class InvalidInput(Exception):
    """Caller-supplied arguments are unusable — exit 3."""


class Unavailable(Exception):
    """The fetch could not run; the caller falls back to gh — exit 4."""


def parse_fields(raw: str) -> list[str]:
    """Split a comma-separated field list; every field must be in SUPERSET."""
    fields = [part.strip() for part in raw.split(",") if part.strip()]
    if not fields:
        raise InvalidInput("--fields must name at least one field")
    unknown = [field for field in fields if field not in SUPERSET]
    if unknown:
        raise InvalidInput(
            "field(s) outside the snapshot superset: " + ", ".join(unknown)
            + " (allowed: " + ",".join(SUPERSET) + ")"
        )
    return list(dict.fromkeys(fields))


def snapshot_path(root: Path, repo: str | None) -> Path:
    digest = hashlib.sha256((repo or "").encode("utf-8")).hexdigest()[:12]
    return root / f"backlog-open-{digest}.json"


def _parse_gh_json(raw: str) -> object:
    """Parse gh stdout, skipping leading non-JSON banner lines (e.g. mise)."""
    lines = raw.splitlines(keepends=True)
    for index, line in enumerate(lines):
        if line.lstrip()[:1] in "{[":
            return json.loads("".join(lines[index:]))
    raise json.JSONDecodeError("Expecting value", raw, 0)


def fetch(limit: int, repo: str | None) -> list[dict]:
    """One live `gh issue list` for the superset, `limit` rows. No cache."""
    args = [
        "issue", "list", "--state", "open", "--json", ",".join(SUPERSET),
        "--limit", str(limit),
    ]
    if repo:
        args += ["--repo", repo]
    proc = _RUN_GH(args, Unavailable)
    if proc.returncode != 0:
        detail = proc.stderr.strip().splitlines()
        raise Unavailable(
            "gh issue list failed: "
            + (detail[-1] if detail else f"exit {proc.returncode}")
        )
    try:
        loaded = _parse_gh_json(proc.stdout)
    except json.JSONDecodeError as exc:
        raise Unavailable(f"gh printed unparsable JSON — {exc.msg}") from exc
    if not isinstance(loaded, list):
        raise Unavailable("gh issue list did not return a JSON array")
    return [row for row in loaded if isinstance(row, dict)]


def _is_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def read_snapshot(path: Path) -> dict | None:
    """The snapshot, or None when it is absent or not the documented shape.

    Every meta key is type-checked, so a snapshot that passes can be compared
    by servable() and reported by status() without raising.
    """
    try:
        loaded = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    if not isinstance(loaded, dict):
        return None
    meta, issues = loaded.get("meta"), loaded.get("issues")
    if not isinstance(meta, dict) or not isinstance(issues, list):
        return None
    fetched_at, fields = meta.get("fetched_at"), meta.get("fields")
    if (
        not isinstance(fetched_at, (int, float)) or isinstance(fetched_at, bool)
        or not math.isfinite(fetched_at)
        or not _is_int(meta.get("fetch_limit"))
        or not _is_int(meta.get("row_count"))
        or meta["row_count"] != len(issues)
        or not isinstance(fields, list)
        or not all(isinstance(field, str) for field in fields)
        or not isinstance(meta.get("repo"), (str, type(None)))
        or not all(isinstance(row, dict) for row in issues)
    ):
        return None
    return loaded


def servable(
    snap: dict, limit: int, fields: list[str], repo: str | None, ttl: int,
    now: float,
) -> bool:
    """Freshness rule (a)-(d) from the module docstring."""
    meta = snap["meta"]
    age = now - meta["fetched_at"]
    return (
        ttl > 0
        and 0 <= age <= ttl
        and set(fields) <= set(meta["fields"])
        and (limit + 1 <= meta["fetch_limit"] or meta["row_count"] < meta["fetch_limit"])
        and meta.get("repo") == repo
    )


def write_snapshot(path: Path, snap: dict) -> None:
    """Best-effort atomic write; failure leaves the answer unaffected."""
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, temp = tempfile.mkstemp(
            prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent)
        )
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(snap, handle)
            os.chmod(temp, _CACHE_MODE)
            os.replace(temp, path)
        except BaseException:
            try:
                os.close(fd)
            except OSError:
                pass
            try:
                os.unlink(temp)
            except OSError:
                pass
            raise
    except OSError:
        return


def load(
    limit: int = DEFAULT_LIMIT,
    fields: list[str] | tuple[str, ...] = SUPERSET,
    repo: str | None = None,
    ttl: int = DEFAULT_TTL_S,
    refresh: bool = False,
    cache_dir: str | os.PathLike[str] | None = None,
) -> tuple[list[dict], bool, dict]:
    """Return (rows, truncated, info) — the API runpy consumers call.

    `rows` holds at most `limit` issues projected to `fields`; `info` carries
    `cached` and `age_s`. Raises InvalidInput or Unavailable like the CLI.
    """
    if not isinstance(limit, int) or isinstance(limit, bool) or limit < 1:
        raise InvalidInput("--limit must be an integer >= 1")
    if not isinstance(ttl, int) or isinstance(ttl, bool) or ttl < 0:
        raise InvalidInput("--ttl must be an integer >= 0")
    fields = parse_fields(",".join(fields))
    root = Path(cache_dir) if cache_dir else Path.cwd() / CACHE_DIRNAME
    path = snapshot_path(root, repo)
    now = time.time()

    cached = False
    if not refresh and ttl > 0:
        # A snapshot is an optimization: anything unexpected on the cached
        # path is a miss, never an exit — the live fetch below answers.
        try:
            snap = read_snapshot(path)
            if snap is not None and servable(snap, limit, fields, repo, ttl, now):
                issues = snap["issues"]
                age = int(now - snap["meta"]["fetched_at"])
                cached = True
        except Exception:
            cached = False
    if not cached:
        issues = fetch(limit + 1, repo)
        age = 0
        write_snapshot(path, {
            "meta": {
                "fetched_at": now,
                "fetch_limit": limit + 1,
                "fields": list(SUPERSET),
                "repo": repo,
                "row_count": len(issues),
            },
            "issues": issues,
        })
    rows = [{f: row[f] for f in fields if f in row} for row in issues[:limit]]
    return rows, len(issues) > limit, {"cached": cached, "age_s": age}


def status(root: Path, repo: str | None, ttl: int) -> dict:
    snap = read_snapshot(snapshot_path(root, repo))
    if snap is None:
        return {"exists": False, "age_s": None, "fresh": False, "ttl": ttl,
                "fetch_limit": None, "row_count": None}
    meta = snap["meta"]
    age = time.time() - meta["fetched_at"]
    return {
        "exists": True,
        "age_s": int(age),
        "fresh": ttl > 0 and 0 <= age <= ttl and meta.get("repo") == repo,
        "ttl": ttl,
        "fetch_limit": meta["fetch_limit"],
        "row_count": meta["row_count"],
    }


def invalidate(root: Path) -> int:
    dropped = 0
    for stale in root.glob("backlog-open-*.json"):
        try:
            stale.unlink()
            dropped += 1
        except OSError:
            continue
    return dropped


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-backlog.py",
        description=(
            "Print the open-issue list, served from a short-lived snapshot "
            "shared across skills when one is fresh."
        ),
        epilog=(
            "Example: python3 gi-backlog.py --limit 100 "
            "--fields number,title,body,labels"
        ),
    )
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT, metavar="N",
                        help=f"rows to return (default {DEFAULT_LIMIT})")
    parser.add_argument("--fields", default=",".join(SUPERSET),
                        help="comma-separated subset of the superset (default: all)")
    parser.add_argument("--repo", metavar="OWNER/NAME")
    parser.add_argument(
        "--ttl", type=int, default=DEFAULT_TTL_S, metavar="S",
        help=f"serve a snapshot younger than S seconds (default {DEFAULT_TTL_S}; "
        "0 always fetches, still writing the snapshot)",
    )
    parser.add_argument("--refresh", action="store_true",
                        help="ignore the snapshot, fetch, and rewrite it")
    parser.add_argument("--out", metavar="FILE",
                        help="write the issue array to FILE; omit it from stdout")
    parser.add_argument("--cache-dir", metavar="DIR",
                        help=f"snapshot location (default {CACHE_DIRNAME})")
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--status", action="store_true",
                        help="report the snapshot's age and freshness; no fetch")
    action.add_argument("--invalidate", action="store_true",
                        help="delete every snapshot in the cache dir; no fetch")
    args = parser.parse_args(argv)

    root = Path(args.cache_dir) if args.cache_dir else Path.cwd() / CACHE_DIRNAME
    try:
        if args.invalidate:
            print(json.dumps({"invalidated": True, "dropped": invalidate(root)}))
            return 0
        if args.ttl < 0:
            raise InvalidInput("--ttl must be >= 0")
        if args.status:
            print(json.dumps(status(root, args.repo, args.ttl)))
            return 0
        fields = parse_fields(args.fields)
        rows, truncated, info = load(
            args.limit, fields, args.repo, args.ttl, args.refresh, root
        )
        envelope = {
            "issues": rows, "cached": info["cached"], "age_s": info["age_s"],
            "ttl": args.ttl, "truncated": truncated, "limit": args.limit,
            "fields": fields,
        }
        if args.out:
            try:
                Path(args.out).write_text(json.dumps(rows), encoding="utf-8")
            except OSError as exc:
                raise Unavailable(f"cannot write {args.out} — {exc}") from exc
            del envelope["issues"]
    except InvalidInput as exc:
        sys.stderr.write(f"✗ gi-backlog: {exc}\n")
        return 3
    except Unavailable as exc:
        sys.stderr.write(f"⚠ gi-backlog: {exc}\n")
        return 4

    print(json.dumps(envelope))
    return 0


if __name__ == "__main__":
    sys.exit(main())
