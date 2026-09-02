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

    {"state": "fresh", "cache_file": "…/model-data-2026-09-02.json",
     "last_fetched": "2026-09-02T00:00:00Z", "data_date": "2026-09-02",
     "data_version": "3.2", "source": "CursorBench 3.2",
     "age_days": 3, "stale": false, "ttl_days": 7, "pruned": [],
     "bands": {"M": {"openai": "GPT-5.6 Sol High", "openai_cost": 2.79,
                     "anthropic": "Opus 5 Medium", "anthropic_cost": 3.29}}}

`state` is one of `fresh`, `stale`, `seeded`, or `installed`. `stale` is also
returned as its own boolean, because a freshly *seeded* cache can be stale too —
the bundled snapshot carries the date it was built, never today's date, so the
filename date and `last_fetched` can never disagree.

Refreshed data comes from the network (a WebFetch the agent performs), so it is
untrusted: pass it as a **file path or on stdin** via `--install`, never
interpolated into this command line. Every document — installed, cached, or
seeded — goes through one validation boundary (`parse_model_data`) before it is
used or written: over the size cap, or any control/escape byte, over-long
string, non-finite number, or negative number anywhere in the tree, and the
document is refused rather than repaired. The cache stores fetched bytes across
runs, so anything let in once re-enters on every later run without a refetch.

Exit codes
  0  the cache is in a usable state (`fresh`, `stale`, `seeded`, `installed`)
  2  usage error
  3  invalid input — `--skill-dir` is not a directory, a negative `--ttl-days`,
     or an `--install` payload that is not a model-data object or fails
     validation (stderr: `✗ gi-model-cache: …`). Stop; the old cache is
     untouched.
  4  cannot complete — no readable cache *and* no readable bundled seed, or the
     newest cache is corrupt or fails validation (stderr:
     `⚠ gi-model-cache: …`). Degrade: disable
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
import math
import os
import re
import subprocess
import sys
import tempfile

DEFAULT_TTL_DAYS = 7
CACHE_GLOB_RE = re.compile(r"^model-data-(\d{4}-\d{2}-\d{2})\.json$")
SEED_REL = os.path.join("templates", "model-data.json")

# --- the validation boundary --------------------------------------------------
#
# Every document this script reads is fetched web content or a stored copy of
# one: the cache persists the fetch across runs with no refetch, so a payload
# that got in once keeps re-entering. Its strings are rendered into the terminal
# *and* into created issue bodies that `/auto-pilot` later reads back, so an
# escape sequence forges output the user just saw and an injected instruction
# survives in the cache. There is therefore exactly one check, applied to every
# document at the moment it is parsed, and it walks the **whole tree** rather
# than a list of fields — a field added to the schema tomorrow is covered the
# same day, which a per-field list would not be.
MAX_PAYLOAD_BYTES = 256 * 1024
MAX_TEXT_CHARS = 512
MAX_NUMBER = 1e9
# Deeper than any model-data document is, and shallower than the C parser
# needs to blow the stack.
MAX_DEPTH = 64

# Control and escape bytes, in every notation that reaches a terminal or a
# markdown body: C0 (including ESC, CR and LF), DEL and C1, the Unicode line and
# paragraph separators, and the bidi overrides/isolates that reorder rendered
# text. No model name, label, source or timestamp needs any of them.
_UNSAFE_TEXT_RE = re.compile(
    "[\\x00-\\x1f\\x7f-\\x9f]"           # C0 controls incl. ESC/CR/LF, DEL, C1
    "|[\\u2028\\u2029]"                  # line and paragraph separators
    "|[\\u202a-\\u202e\\u2066-\\u2069]"  # bidi embeddings, overrides, isolates
    # Zero-width and directional marks. They render as nothing at all, which is
    # worse than an escape sequence, not better: a model name that reads
    # identically to a real one in the terminal and in a created issue body is
    # exactly the payload this boundary exists to refuse. ZWSP/ZWNJ/ZWJ, LRM,
    # RLM, the Arabic letter mark, the word joiner and its invisible operators,
    # and the BOM wherever it is not the first byte of a file.
    "|[\\u200b-\\u200f\\u061c]"
    "|[\\u2060-\\u2064\\ufeff]"
)

CONFIG_NAME = ".gitissue.yml"
CONFIG_SECTION = "model_suggestion"
CONFIG_KEYS = ("cache_ttl_days", "enabled")

# `git rev-parse --show-cdup` is empty at the working-tree root and otherwise
# consists only of `../` segments. Refuse to resolve any other output as a path.
_CDUP_RE = re.compile(r"^(\.\./)*$")

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


def config_search_ceiling() -> str:
    """Return the working-tree root, or cwd when git cannot identify one."""
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "--show-cdup"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return os.path.abspath(os.getcwd())
    cdup = proc.stdout.rstrip("\n")
    if proc.returncode != 0 or not _CDUP_RE.match(cdup):
        return os.path.abspath(os.getcwd())
    return (
        os.path.normpath(os.path.join(os.getcwd(), cdup))
        if cdup
        else os.path.abspath(os.getcwd())
    )


def find_config(explicit: str | None) -> str | None:
    """The explicit file, else search upward to the working-tree root."""
    if explicit:
        return explicit if os.path.isfile(explicit) else None
    here = os.path.abspath(os.getcwd())
    ceiling = os.path.abspath(config_search_ceiling())
    while True:
        candidate = os.path.join(here, CONFIG_NAME)
        if os.path.isfile(candidate):
            return candidate
        parent = os.path.dirname(here)
        if here == ceiling or parent == here:
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


def _reject_constant(name: str) -> float:
    """`json` accepts bare `NaN`/`Infinity` by default; this refuses them.

    Refusing them at the parser means a non-RFC-8259 token can never reach the
    document at all, rather than being caught by a check someone can forget to
    call on a new path.
    """
    raise ValueError(f"{name} is not a JSON number (RFC 8259 has no {name})")


def _check_text(value: str, where: str) -> None:
    hit = _UNSAFE_TEXT_RE.search(value)
    if hit:
        raise ValueError(
            f"{where} carries a control or escape character (U+{ord(hit.group(0)):04X}) "
            f"— it would forge terminal output and persist into issue bodies"
        )
    if len(value) > MAX_TEXT_CHARS:
        raise ValueError(
            f"{where} is {len(value)} characters, over the {MAX_TEXT_CHARS} cap"
        )


def _check_number(value: float, where: str) -> None:
    if isinstance(value, float) and not math.isfinite(value):
        raise ValueError(f"{where} is not a finite number ({value!r})")
    if value < 0:
        raise ValueError(f"{where} is negative ({value!r}); no field in this schema is")
    if value > MAX_NUMBER:
        raise ValueError(f"{where} is out of range ({value!r})")


def validate_payload(loaded: object, label: str) -> dict:
    """Validate one model-data document. The single boundary — see the header.

    The walk is iterative rather than recursive so a deeply nested payload
    cannot exhaust the stack, and it visits dict *keys* as well as values: a key
    is rendered the moment anything iterates the document.
    """
    if not isinstance(loaded, dict) or "complexity_mapping" not in loaded:
        raise ValueError(f"the {label} is not a model-data document")
    stack: list[tuple[str, object, int]] = [(label, loaded, 0)]
    while stack:
        where, node, depth = stack.pop()
        if depth > MAX_DEPTH:
            raise ValueError(f"{where} is nested deeper than {MAX_DEPTH} levels")
        if isinstance(node, dict):
            for key, value in node.items():
                _check_text(str(key), f"{where}.{key!r} (key)")
                stack.append((f"{where}.{key}", value, depth + 1))
        elif isinstance(node, list):
            for position, value in enumerate(node):
                stack.append((f"{where}[{position}]", value, depth + 1))
        elif isinstance(node, str):
            _check_text(node, where)
        elif isinstance(node, bool) or node is None:
            continue
        elif isinstance(node, (int, float)):
            _check_number(node, where)
        else:  # unreachable from json.loads, kept so a future loader cannot slip
            raise ValueError(f"{where} is not a JSON value ({type(node).__name__})")
    return loaded


def read_capped(path: str | None, label: str) -> str:
    """Read at most MAX_PAYLOAD_BYTES from `path` (or stdin when None).

    The cap is taken before parsing, so an oversized document costs one read
    rather than a parse, a whole-tree walk, and a permanent place in the cache.
    """
    if path is None:
        buffer = getattr(sys.stdin, "buffer", None)
        raw = (
            buffer.read(MAX_PAYLOAD_BYTES + 1)
            if buffer
            else sys.stdin.read(MAX_PAYLOAD_BYTES + 1).encode("utf-8", "replace")
        )
    else:
        with open(path, "rb") as handle:
            raw = handle.read(MAX_PAYLOAD_BYTES + 1)
    if len(raw) > MAX_PAYLOAD_BYTES:
        raise ValueError(
            f"the {label} is larger than the {MAX_PAYLOAD_BYTES}-byte cap"
        )
    return raw.decode("utf-8", errors="replace")


def parse_model_data(text: str, label: str) -> dict:
    """Parse and validate — the only way a document enters this script.

    `RecursionError` is caught beside `ValueError` because it is a
    `RuntimeError`, not one: a payload nested a few hundred deep is well inside
    the size cap, blows the parser's stack, and would leave main() as **exit 1**
    — a code no call site classifies, so a degrade path reads it as "some other
    failure" and a stop path never runs. That is the same defect the impossible
    `last_fetched` date had; it is fixed here for the whole parse rather than
    for one more field.
    """
    try:
        loaded = json.loads(text, parse_constant=_reject_constant)
    except ValueError as exc:  # JSONDecodeError and _reject_constant alike
        raise ValueError(f"the {label} is corrupt — {exc}") from exc
    except RecursionError as exc:
        raise ValueError(
            f"the {label} is nested too deeply to parse"
        ) from exc
    return validate_payload(loaded, label)


def load_payload(path: str, label: str) -> dict:
    """Read a model-data document, or raise Unavailable.

    A file that exists but cannot be parsed *or does not validate* is not
    treated as absent. Falling through to the seed there would report `seeded`
    while the user's refreshed data sits unreadable on disk — a silent
    substitution of one data source for another, which this contract forbids.
    """
    try:
        text = read_capped(path, f"{label} at {path}")
    except OSError as exc:
        raise Unavailable(f"cannot read the {label} at {path} — {exc}") from exc
    except ValueError as exc:
        raise Unavailable(str(exc)) from exc
    try:
        return parse_model_data(text, f"{label} at {path}")
    except ValueError as exc:
        raise Unavailable(str(exc)) from exc


def last_fetched_date(payload: dict, label: str) -> str:
    raw = payload.get("last_fetched")
    if not isinstance(raw, str) or len(raw) < 10 or not re.match(r"^\d{4}-\d{2}-\d{2}", raw):
        raise Unavailable(f"the {label} has no usable last_fetched timestamp")
    day = raw[:10]
    try:
        parse_day(day)
    except ValueError as exc:
        # `2026-02-30` matches the shape and is not a date. It has to be
        # rejected here, because the `age_days` subtraction in main() runs
        # *outside* the exit-code guard and would exit 1 over it — a code no
        # call site classifies.
        raise Unavailable(
            f"the {label} has an impossible last_fetched date ({day})"
        ) from exc
    return day


def parse_day(text: str) -> dt.date:
    """Parse the `YYYY-MM-DD` prefix of `text`.

    Raises ValueError on a shape-valid but impossible date. Every caller turns
    that into the exit code its own path documents; letting it escape exits 1.
    """
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
    """The version portion of `source` — `3.2` from `CursorBench 3.2`.

    Scanned backwards in one pass instead of matched with
    `([0-9]+(?:\\.[0-9]+)*)\\s*$`. That pattern is nested quantification against
    a right anchor, so a `source` of digits and dots backtracks quadratically —
    ~13 s at 32 KB, and `source` is attacker-controlled fetched content read on
    *every* run. This loop is O(len(source)) and returns the same string.
    """
    source = payload.get("source")
    if not isinstance(source, str):
        return None
    text = source.rstrip()
    end = len(text)
    # `str.isdigit()` is true for U+00B2 and every Unicode decimal; the pattern
    # this replaces was `[0-9]`, so the test stays ASCII.
    digit = "0123456789".__contains__
    if end == 0 or not digit(text[end - 1]):
        return None
    start = end
    while True:
        cut = start
        while cut > 0 and digit(text[cut - 1]):
            cut -= 1
        if cut == start:  # no digit run here — the version began at `start`
            break
        start = cut
        # A dot only continues the version when a digit run precedes it.
        if start > 1 and text[start - 1] == "." and digit(text[start - 2]):
            start -= 1
        else:
            break
    return text[start:end]


def write_cache(skill_dir: str, payload: dict, date: str) -> tuple[str, list[str]]:
    """Write the dated cache and prune every other dated copy."""
    target = os.path.join(skill_dir, f"model-data-{date}.json")
    # `target + ".tmp"` opened with plain `open()` is a predictable path that
    # follows a symlink planted there, and inherits whatever the umask allows.
    # `mkstemp` is O_CREAT|O_EXCL|O_RDWR on an unpredictable name at mode 0600
    # by construction; the mode is then set explicitly rather than left to the
    # umask. Same directory, so `os.replace` stays atomic.
    temp = None
    try:
        handle_fd, temp = tempfile.mkstemp(
            dir=skill_dir, prefix=f".model-data-{date}.", suffix=".tmp"
        )
        with os.fdopen(handle_fd, "w", encoding="utf-8") as handle:
            # `allow_nan=False` keeps the cache RFC 8259 even if a future path
            # reaches here without going through the validation boundary.
            json.dump(payload, handle, indent=2, allow_nan=False)
            handle.write("\n")
            # Through the descriptor, not the path: a path-based chmod names
            # whatever sits there at that instant, and the point of O_EXCL was
            # to stop caring what sits there.
            os.fchmod(handle.fileno(), 0o644)
        os.replace(temp, target)
        temp = None
    except (OSError, ValueError, RecursionError) as exc:
        raise Unavailable(f"cannot write {target} — {exc}") from exc
    finally:
        if temp is not None:
            try:
                os.remove(temp)
            except OSError:
                pass
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
    try:
        text = read_capped(None if source == "-" else source, "--install payload")
    except OSError as exc:
        raise InvalidInput(f"cannot read --install {source} — {exc}") from exc
    except ValueError as exc:
        raise InvalidInput(str(exc)) from exc
    # The same boundary the on-disk documents go through — this is where the
    # bytes are freshest off the network, so it is the one that matters most.
    try:
        loaded = parse_model_data(text, "--install payload")
    except ValueError as exc:
        raise InvalidInput(str(exc)) from exc
    raw = loaded.get("last_fetched")
    if not isinstance(raw, str):
        raise InvalidInput("--install payload has no last_fetched timestamp")
    # The payload is fetched web content. Its date names the cache file and is
    # subtracted from today's date, so it is validated *here* — before
    # write_cache() prunes the existing cache — to keep the documented
    # "exit 3 … the old cache is untouched" contract true for a bad date too.
    if len(raw) < 10 or not re.match(r"^\d{4}-\d{2}-\d{2}", raw):
        raise InvalidInput("--install payload has no usable last_fetched timestamp")
    try:
        parse_day(raw[:10])
    except ValueError as exc:
        raise InvalidInput(
            f"--install payload's last_fetched is not a real date ({raw[:10]})"
        ) from exc
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
            try:
                today = parse_day(args.now)
            except ValueError as exc:
                raise InvalidInput(
                    f"--now is not a real calendar date: {args.now}"
                ) from exc
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
