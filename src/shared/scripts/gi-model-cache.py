#!/usr/bin/env python3
"""Run the model-suggestion data cache lifecycle for /issue-creator.

The lifecycle is `ls`, `cp`, a date subtraction, and a few `jq` lookups — locate
the newest `model-data-<date>.json` in the installed skill folder, seed it from
the bundled snapshot when there is none, compare `last_fetched` against the TTL,
and read the effort band's two model names and their per-task costs. Shipped as
prose it is a 12.3 KB reference document read on every default run, to compute
an answer that has exactly one correct value.

This script computes it and hands back everything the rendering rule needs, so
the reference document becomes refresh- and debug-only reading.

Output on stdout, one JSON object:

    {"state": "fresh", "cache_file": "…/model-data-2026-06-12.json",
     "last_fetched": "2026-06-12T00:00:00Z", "data_date": "2026-06-12",
     "data_version": "3.1", "source": "CursorBench 3.1",
     "age_days": 3, "stale": false, "ttl_days": 7, "pruned": [],
     "bands": {"M": {"openai": "GPT-5.5 High", "openai_cost": 3.59,
                     "anthropic": "Opus 4.8 Medium", "anthropic_cost": 3.83}}}

`state` is one of `fresh`, `stale`, `seeded`, or `installed`. `stale` is also
returned as its own boolean, because a freshly *seeded* cache can be stale too —
the bundled snapshot carries the date it was built, never today's date, so the
filename date and `last_fetched` can never disagree.

Refreshed data comes from the network (a WebFetch the agent performs), so it is
untrusted: pass it as a **file path or on stdin** via `--install`, never
interpolated into this command line.

Exit codes
  0  the cache is in a usable state (`fresh`, `stale`, `seeded`, `installed`)
  2  usage error
  3  invalid input — `--skill-dir` is not a directory, a negative `--ttl-days`,
     or an `--install` payload that is not a model-data object (stderr:
     `✗ gi-model-cache: …`). Stop.
  4  cannot complete — no readable cache *and* no readable bundled seed, or the
     newest cache is corrupt (stderr: `⚠ gi-model-cache: …`). Degrade: disable
     model suggestions for this run and continue creating the issue, exactly as
     the prose lifecycle's *Bundled seed also missing* state already says. A
     corrupt cache is never silently replaced by the seed — that would report a
     refresh the user never got.

Authored at src/shared/scripts/gi-model-cache.py — do not edit installed copies;
edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys

DEFAULT_TTL_DAYS = 7
CACHE_GLOB_RE = re.compile(r"^model-data-(\d{4}-\d{2}-\d{2})\.json$")
SEED_REL = os.path.join("templates", "model-data.json")

CONFIG_NAME = ".gitissue.yml"
CONFIG_SECTION = "model_suggestion"
CONFIG_KEYS = ("cache_ttl_days", "enabled")

_SECTION_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):\s*$")
_ENTRY_RE = re.compile(r"^\s+([a-z_][a-z0-9_]*):[ \t]+(.*?)\s*$")


class InvalidInput(Exception):
    """Caller-supplied arguments are unusable — exit 3."""


class Unavailable(Exception):
    """No usable model data — exit 4, caller disables suggestions."""


# --- configuration -----------------------------------------------------------


def _parse_scalar(raw: str) -> object:
    if raw.startswith('"'):
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return raw.strip('"')
    if raw.startswith("'") and raw.endswith("'") and len(raw) >= 2:
        return raw[1:-1].replace("''", "'")
    if raw == "true":
        return True
    if raw == "false":
        return False
    if re.fullmatch(r"-?[0-9]+", raw):
        return int(raw)
    return raw


def read_config(path: str) -> dict[str, object]:
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return {}
    values: dict[str, object] = {}
    inside = False
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        section = _SECTION_RE.match(line)
        if section:
            inside = section.group(1) == CONFIG_SECTION
            continue
        if not inside:
            continue
        entry = _ENTRY_RE.match(line)
        if entry and entry.group(1) in CONFIG_KEYS:
            values[entry.group(1)] = _parse_scalar(entry.group(2))
    return values


def find_config(explicit: str | None) -> str | None:
    """The explicit path (only when it is a file), else the upward search."""
    if explicit:
        return explicit if os.path.isfile(explicit) else None
    here = os.path.abspath(os.getcwd())
    while True:
        candidate = os.path.join(here, CONFIG_NAME)
        if os.path.isfile(candidate):
            return candidate
        parent = os.path.dirname(here)
        if parent == here:
            return None
        here = parent


def resolve_ttl(args: argparse.Namespace) -> int:
    ttl: object = DEFAULT_TTL_DAYS
    if not args.no_config:
        path = find_config(args.config)
        if path is None and args.config:
            raise InvalidInput(f"config file not found: {args.config}")
        if path is not None:
            ttl = read_config(path).get("cache_ttl_days", DEFAULT_TTL_DAYS)
    if args.ttl_days is not None:
        ttl = args.ttl_days
    if not isinstance(ttl, int) or isinstance(ttl, bool) or ttl < 0:
        raise InvalidInput(
            f"{CONFIG_SECTION}.cache_ttl_days must be an integer >= 0, got {ttl!r}"
        )
    return ttl


# --- cache -------------------------------------------------------------------


def dated_caches(skill_dir: str) -> list[tuple[str, str]]:
    """(date, path) for every `model-data-<date>.json`, newest first."""
    try:
        names = os.listdir(skill_dir)
    except OSError as exc:
        raise Unavailable(f"cannot list {skill_dir} — {exc}") from exc
    found = []
    for name in names:
        match = CACHE_GLOB_RE.match(name)
        if match:
            found.append((match.group(1), os.path.join(skill_dir, name)))
    return sorted(found, reverse=True)


def load_payload(path: str, label: str) -> dict:
    """Read a model-data document, or raise Unavailable.

    A file that exists but cannot be parsed is *not* treated as absent. Falling
    through to the seed there would report `seeded` while the user's refreshed
    data sits unreadable on disk — a silent substitution of one data source for
    another, which is exactly what this contract forbids.
    """
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError as exc:
        raise Unavailable(f"cannot read the {label} at {path} — {exc}") from exc
    try:
        loaded = json.loads(text)
    except json.JSONDecodeError as exc:
        raise Unavailable(f"the {label} at {path} is corrupt — {exc}") from exc
    if not isinstance(loaded, dict) or "complexity_mapping" not in loaded:
        raise Unavailable(f"the {label} at {path} is not a model-data document")
    return loaded


def last_fetched_date(payload: dict, label: str) -> str:
    raw = payload.get("last_fetched")
    if not isinstance(raw, str) or len(raw) < 10 or not re.match(r"^\d{4}-\d{2}-\d{2}", raw):
        raise Unavailable(f"the {label} has no usable last_fetched timestamp")
    return raw[:10]


def parse_day(text: str) -> dt.date:
    return dt.date(int(text[0:4]), int(text[5:7]), int(text[8:10]))


def costs_by_name(payload: dict) -> dict[str, float]:
    """Model name → per-task cost, across both provider blocks."""
    out: dict[str, float] = {}
    providers = payload.get("providers")
    if not isinstance(providers, dict):
        return out
    for provider in providers.values():
        if not isinstance(provider, dict):
            continue
        for model in provider.get("models") or []:
            if isinstance(model, dict) and isinstance(model.get("name"), str):
                cost = model.get("cost_per_task_usd")
                if isinstance(cost, (int, float)):
                    out[model["name"]] = float(cost)
    return out


def render_bands(payload: dict) -> dict[str, dict]:
    """The effort → (openai, anthropic) mapping with each pick's own cost.

    The two picks are alternatives, so their costs stay independent fields and
    are never summed.
    """
    costs = costs_by_name(payload)
    bands: dict[str, dict] = {}
    mapping = payload.get("complexity_mapping")
    if not isinstance(mapping, dict):
        return bands
    for band, entry in mapping.items():
        if not isinstance(entry, dict):
            continue
        openai = entry.get("openai")
        anthropic = entry.get("anthropic")
        bands[str(band)] = {
            "label": entry.get("label"),
            "openai": openai,
            "openai_cost": costs.get(openai) if isinstance(openai, str) else None,
            "anthropic": anthropic,
            "anthropic_cost": costs.get(anthropic) if isinstance(anthropic, str) else None,
        }
    return bands


def data_version(payload: dict) -> str | None:
    """The version portion of `source` — `3.1` from `CursorBench 3.1`."""
    source = payload.get("source")
    if not isinstance(source, str):
        return None
    match = re.search(r"([0-9]+(?:\.[0-9]+)*)\s*$", source.strip())
    return match.group(1) if match else None


def write_cache(skill_dir: str, payload: dict, date: str) -> tuple[str, list[str]]:
    """Write the dated cache and prune every other dated copy."""
    target = os.path.join(skill_dir, f"model-data-{date}.json")
    temp = target + ".tmp"
    try:
        with open(temp, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2)
            handle.write("\n")
        os.replace(temp, target)
    except OSError as exc:
        raise Unavailable(f"cannot write {target} — {exc}") from exc
    pruned = []
    for _, path in dated_caches(skill_dir):
        if os.path.abspath(path) == os.path.abspath(target):
            continue
        try:
            os.remove(path)
            pruned.append(os.path.basename(path))
        except OSError:
            continue
    return target, sorted(pruned)


def read_install_payload(source: str) -> dict:
    if source == "-":
        buffer = getattr(sys.stdin, "buffer", None)
        text = buffer.read().decode("utf-8", errors="replace") if buffer else sys.stdin.read()
    else:
        try:
            text = open(source, encoding="utf-8", errors="replace").read()
        except OSError as exc:
            raise InvalidInput(f"cannot read --install {source} — {exc}") from exc
    try:
        loaded = json.loads(text)
    except json.JSONDecodeError as exc:
        raise InvalidInput(f"--install payload is not valid JSON — {exc}") from exc
    if not isinstance(loaded, dict) or "complexity_mapping" not in loaded:
        raise InvalidInput("--install payload is not a model-data document")
    if not isinstance(loaded.get("last_fetched"), str):
        raise InvalidInput("--install payload has no last_fetched timestamp")
    return loaded


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-model-cache.py",
        description=(
            "Locate, seed, age, and read the skill-level model-data cache. "
            "Prints one JSON object on stdout."
        ),
        epilog="Example: python3 gi-model-cache.py --skill-dir \"$skill_dir\"",
    )
    parser.add_argument(
        "--skill-dir", required=True, metavar="DIR", help="installed issue-creator skill folder"
    )
    parser.add_argument(
        "--ttl-days", type=int, metavar="N",
        help=f"staleness threshold (default {CONFIG_SECTION}.cache_ttl_days, else {DEFAULT_TTL_DAYS})",
    )
    parser.add_argument("--now", metavar="YYYY-MM-DD", help="treat this day as today (tests)")
    parser.add_argument(
        "--install",
        metavar="FILE",
        help="install refreshed model data from FILE (or '-' for stdin) and prune older copies",
    )
    parser.add_argument(
        "--no-seed",
        action="store_true",
        help="report the cache state without seeding from the bundled snapshot",
    )
    parser.add_argument("--config", metavar="PATH", help=f"{CONFIG_NAME} to read")
    parser.add_argument("--no-config", action="store_true", help="ignore any config file")
    args = parser.parse_args(argv)

    pruned: list[str] = []
    try:
        skill_dir = os.path.abspath(args.skill_dir)
        if not os.path.isdir(skill_dir):
            raise InvalidInput(f"--skill-dir is not a directory: {args.skill_dir}")
        ttl = resolve_ttl(args)
        if args.now:
            if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", args.now):
                raise InvalidInput(f"--now must be YYYY-MM-DD, got {args.now!r}")
            today = parse_day(args.now)
        else:
            today = dt.datetime.now(dt.timezone.utc).date()

        if args.install:
            payload = read_install_payload(args.install)
            date = last_fetched_date(payload, "installed payload")
            cache_file, pruned = write_cache(skill_dir, payload, date)
            state = "installed"
        else:
            caches = dated_caches(skill_dir)
            if caches:
                date, cache_file = caches[0]
                payload = load_payload(cache_file, "model-data cache")
                date = last_fetched_date(payload, "model-data cache")
                state = "fresh"
            elif args.no_seed:
                raise Unavailable("no model-data cache present and --no-seed was given")
            else:
                seed = os.path.join(skill_dir, SEED_REL)
                payload = load_payload(seed, "bundled model-data seed")
                date = last_fetched_date(payload, "bundled model-data seed")
                cache_file, pruned = write_cache(skill_dir, payload, date)
                state = "seeded"
    except InvalidInput as exc:
        sys.stderr.write(f"✗ gi-model-cache: {exc}\n")
        return 3
    except Unavailable as exc:
        sys.stderr.write(f"⚠ gi-model-cache: {exc}\n")
        return 4

    age_days = (today - parse_day(date)).days
    stale = ttl > 0 and age_days > ttl
    if state == "fresh" and stale:
        state = "stale"

    print(
        json.dumps(
            {
                "state": state,
                "cache_file": cache_file,
                "last_fetched": payload.get("last_fetched"),
                "data_date": date,
                "data_version": data_version(payload),
                "source": payload.get("source"),
                "age_days": age_days,
                "stale": stale,
                "ttl_days": ttl,
                "pruned": pruned,
                "bands": render_bands(payload),
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
