#!/usr/bin/env python3
# gi-requires: references/docs/config-schema.md
"""Resolve the effective gitissue configuration and print it as one JSON line.

Every skill starts by merging the documented defaults with the repository's
`.gitissue.yml`. Doing that by reading prose is where drift creeps in: a default
gets restated in six skills and one of them goes stale. This script instead
*derives* the defaults from the canonical schema document at run time — there is
no defaults table in this file, on purpose — validates the user's overrides
against it, and emits the merged result.

Output on success is exactly one line of JSON on stdout:

    {"config": {"<dotted.key>": <value>, ...},
     "config_file": ".gitissue.yml" or null,
     "first_run": true or false}

Unknown-key policy. The schema handed to this script may be the complete
document or a per-skill excerpt carrying only the sections that skill reads, so
"this key is not in the schema" has two very different meanings:

  * a key inside a section the schema *does* document is a typo — exit 3;
  * a key in a section the schema never shows is simply out of view. It is
    passed through into `config` and reported on stderr, because refusing to
    start over a section the caller was never given would stop every skill.
    When the schema is the complete document (it still carries the Config
    Section Map, which the per-skill excerpt drops) an unknown section is a
    typo and does fail;
  * a key the schema tombstones as *(removed)* is dropped with a warning — the
    documentation deprecated it, so an untouched old `.gitissue.yml` must not
    become a hard stop.

Exit codes
  0  merged config printed
  2  usage error
  3  `.gitissue.yml` is invalid (stderr: `✗ Invalid .gitissue.yml: <key> — <why>`)
  4  cannot complete — schema missing/unparsable, or the config file could not
     be read (stderr: `⚠ gi-config: <reason>`). Callers fall back to their
     inline defaults rather than failing the run.

Authored at src/shared/scripts/gi-config.py — do not edit installed copies;
edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

SCHEMA_NAME = "config-schema.md"
DEFAULT_CONFIG_NAME = ".gitissue.yml"

# --- Vendored config parsing -------------------------------------------------
#
# These four definitions are a deliberate verbatim copy of the restricted-YAML
# parser in scripts/build.py. This script ships inside installed skills, where
# the build tree does not exist, so it cannot import from it; the copy is kept
# behavior-identical instead and a test asserts both parsers agree on the
# canonical schema and template files.

_FULL_SCHEMA_FENCE_RE = re.compile(
    r"^## Full Schema \(advanced reference\).*?^```yaml\n(.*?)^```",
    re.MULTILINE | re.DOTALL,
)
_YAML_MAPPING_RE = re.compile(r"^(?P<indent> *)(?P<key>[A-Za-z_][A-Za-z0-9_-]*):(?:[ ]+(?P<value>.*))?$")
_YAML_LIST_RE = re.compile(r"^(?P<indent> *)- (?P<value>.*)$")

# A Defaults Table row whose first cell tombstones the key, e.g.
# `| *(removed)* `resolve.pr_auto_link` | — | Deprecated; ... |`.
_REMOVED_ROW_RE = re.compile(
    r"^\|[^|]*\(removed\)[^|]*`([A-Za-z_][A-Za-z0-9_.]*)`",
    re.MULTILINE | re.IGNORECASE,
)

# The Config Section Map diagrams the *whole* schema, so the build strips it
# when it emits a per-skill excerpt. Its presence is therefore the document's
# own signal that the section list in front of us is complete.
_SECTION_MAP_RE = re.compile(r"^#{2,4}\s+Config Section Map\s*$", re.MULTILINE)


class ConfigError(Exception):
    """`.gitissue.yml` is invalid — exit 3."""


class Unavailable(Exception):
    """The script cannot complete; the caller should fall back — exit 4."""


class ParseError(Exception):
    """The restricted-YAML parser met syntax it does not support."""


def _parse_yaml_scalar(value: str) -> object:
    """Parse the restricted scalar syntax used by the canonical config files.

    This deliberately accepts mappings, block lists, quoted strings, booleans,
    integers, null, and init-template replacement tokens; unsupported YAML
    raises rather than silently producing a wrong value.
    """
    value = value.strip()
    if value.startswith('"'):
        try:
            return json.loads(value)
        except json.JSONDecodeError as exc:
            raise ParseError(f"invalid quoted YAML scalar: {value!r} ({exc.msg})") from exc
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1].replace("''", "'")
    if value == "true":
        return True
    if value == "false":
        return False
    if value == "null":
        return None
    if re.fullmatch(r"-?[0-9]+", value):
        return int(value)
    if re.fullmatch(r"\{[a-z_]+\}", value):
        return value
    if value and not any(char in value for char in "[]{}#,\t"):
        return value
    raise ParseError(f"unsupported YAML scalar: {value!r}")


def _parse_config_mapping(text: str, label: str) -> dict[str, object]:
    """Flatten the project's restricted YAML config syntax into dotted keys."""
    result: dict[str, object] = {}
    parents: list[tuple[int, str]] = []
    pending_lists: list[tuple[int, str]] = []

    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        if not raw_line.strip() or raw_line.lstrip().startswith("#"):
            continue
        mapping = _YAML_MAPPING_RE.fullmatch(raw_line)
        if mapping:
            indent = len(mapping.group("indent"))
            key = mapping.group("key")
            value = mapping.group("value")
            while parents and parents[-1][0] >= indent:
                parents.pop()
            while pending_lists and pending_lists[-1][0] >= indent:
                pending_lists.pop()
            path = ".".join([part for _, part in parents] + [key])
            if value is None:
                parents.append((indent, key))
                pending_lists.append((indent, path))
            else:
                result[path] = _parse_yaml_scalar(value)
            continue

        list_item = _YAML_LIST_RE.fullmatch(raw_line)
        if list_item:
            indent = len(list_item.group("indent"))
            candidates = [entry for entry in pending_lists if entry[0] < indent]
            if not candidates:
                raise ParseError(f"invalid YAML list item in {label}:{line_number}")
            path = candidates[-1][1]
            result.setdefault(path, [])
            if not isinstance(result[path], list):
                raise ParseError(
                    f"mixed YAML container types for {path} in {label}:{line_number}"
                )
            result[path].append(_parse_yaml_scalar(list_item.group("value")))
            continue

        raise ParseError(f"unsupported YAML syntax in {label}:{line_number}: {raw_line!r}")
    return result


# --- Schema ------------------------------------------------------------------


def find_schema(explicit: str | None) -> Path:
    """Locate the schema document: explicit path, bundled copy, then repo tree."""
    if explicit:
        path = Path(explicit)
        if not path.is_file():
            raise Unavailable(f"schema not found: {explicit}")
        return path
    # Installed layout: this script sits at references/scripts/, the schema at
    # references/docs/ of the same skill.
    bundled = Path(__file__).resolve().parent.parent / "docs" / SCHEMA_NAME
    if bundled.is_file():
        return bundled
    # Source tree: walk up from the working directory.
    cwd = Path.cwd().resolve()
    for base in (cwd, *cwd.parents):
        candidate = base / "docs" / SCHEMA_NAME
        if candidate.is_file():
            return candidate
    raise Unavailable(
        f"no {SCHEMA_NAME} beside this script or above the working directory "
        "(pass --schema)"
    )


def load_schema(path: Path) -> tuple[dict[str, object], frozenset[str], bool]:
    """Return (documented defaults, tombstoned keys, schema-is-complete)."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise Unavailable(f"cannot read {path}: {exc}") from exc
    except UnicodeDecodeError as exc:
        # UnicodeDecodeError subclasses ValueError, not OSError, so it escapes
        # the clause above. The schema is a bundled dependency, not user input:
        # an undecodable one is a broken install, so the caller falls back.
        raise Unavailable(f"{path} is not valid UTF-8 — {exc.reason}") from exc
    match = _FULL_SCHEMA_FENCE_RE.search(text)
    if match is None:
        raise Unavailable(f"{path} has no Full Schema YAML block")
    try:
        defaults = _parse_config_mapping(match.group(1), str(path))
    except ParseError as exc:
        raise Unavailable(f"cannot parse the schema defaults — {exc}") from exc
    removed = frozenset(_REMOVED_ROW_RE.findall(text))
    return defaults, removed, _SECTION_MAP_RE.search(text) is not None


# --- User configuration ------------------------------------------------------


def _flatten(mapping: dict, prefix: str = "") -> dict[str, object]:
    """Flatten a nested mapping into dotted keys, matching the schema's form."""
    out: dict[str, object] = {}
    for key, value in mapping.items():
        dotted = f"{prefix}{key}"
        if isinstance(value, dict):
            out.update(_flatten(value, dotted + "."))
        else:
            out[dotted] = value
    return out


def load_user_config(path: Path) -> dict[str, object]:
    """Parse the user's config file into dotted keys.

    PyYAML is used when the interpreter has it and the restricted parser is the
    fallback, so a config using YAML this project's own parser does not model
    still loads wherever possible. When neither can read it the caller degrades
    (exit 4) rather than declaring the file invalid — a parser limitation is not
    a user error.
    """
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise Unavailable(f"cannot read {path}: {exc}") from exc
    except UnicodeDecodeError as exc:
        # UnicodeDecodeError subclasses ValueError, not OSError, so it escapes
        # the clause above and would leave the interpreter to print a traceback
        # and exit 1 — a code outside this script's 0/2/3/4 contract, which
        # callers read as "degrade", silently discarding the repo's real config.
        # The file was found and read: its *bytes* are wrong, which is a user
        # error (an editor saving cp1252), so it is exit 3, stop and report.
        raise ConfigError(
            f"{path} is not valid UTF-8 — {exc.reason} at byte {exc.start}; "
            "re-save the file as UTF-8"
        ) from exc
    try:
        import yaml  # type: ignore[import-not-found]
    except ImportError:
        pass
    else:
        try:
            loaded = yaml.safe_load(text)
        except yaml.YAMLError as exc:
            raise ConfigError(f"{path} is not valid YAML — {exc}") from exc
        if loaded is None:
            return {}
        if not isinstance(loaded, dict):
            raise ConfigError(f"{path} must contain a mapping at the top level")
        return _flatten(loaded)
    try:
        return _parse_config_mapping(text, str(path))
    except ParseError as exc:
        raise Unavailable(
            f"cannot parse {path} without PyYAML — {exc}"
        ) from exc


# --- Validation and merge ----------------------------------------------------


def _type_problem(value: object, default: object) -> str | None:
    """Describe how `value` violates the documented default's type, or None."""
    if isinstance(default, bool):
        return None if isinstance(value, bool) else "must be true or false"
    if isinstance(default, int):
        ok = isinstance(value, int) and not isinstance(value, bool)
        return None if ok else "must be an integer"
    if isinstance(default, str):
        return None if isinstance(value, str) else "must be a string"
    if isinstance(default, list):
        return None if isinstance(value, list) else "must be a list"
    if default is None:
        # A documented `null` default pins no type — it means "unset" (a board
        # number or nothing). Only a container is clearly wrong.
        ok = value is None or isinstance(value, (int, float, str))
        return None if ok else "must be a scalar or null"
    return None


def merge(
    defaults: dict[str, object],
    overrides: dict[str, object],
    removed: frozenset[str],
    complete: bool,
) -> tuple[dict[str, object], list[str]]:
    """Validate overrides against the schema and merge them onto the defaults.

    Returns (merged config, warnings). Raises ConfigError listing every problem
    at once, so a user fixes one round of errors rather than one error.
    """
    sections = {key.split(".", 1)[0] for key in defaults}
    accepted: dict[str, object] = {}
    warnings: list[str] = []
    errors: list[str] = []
    out_of_view: dict[str, int] = {}

    for key in sorted(overrides):
        value = overrides[key]
        section = key.split(".", 1)[0]
        if key in removed:
            warnings.append(f"{key} was removed from the schema — ignoring it")
            continue
        if key in defaults:
            problem = _type_problem(value, defaults[key])
            if problem is None:
                accepted[key] = value
            else:
                errors.append(f"{key} — {problem}")
            continue
        if section not in sections:
            if complete:
                errors.append(f"{key} — unknown configuration section '{section}'")
            else:
                # Grouped into one line: a per-skill excerpt legitimately hides
                # most of the file, and one warning per hidden key would bury
                # the warnings that matter.
                out_of_view[section] = out_of_view.get(section, 0) + 1
                accepted[key] = value
            continue
        errors.append(f"{key} — not a documented key of section '{section}'")

    if out_of_view:
        listed = ", ".join(f"{name} ({n})" for name, n in sorted(out_of_view.items()))
        warnings.append(
            "section(s) outside this schema view, passed through unvalidated: " + listed
        )
    if errors:
        raise ConfigError("\n".join(errors))
    return {**defaults, **accepted}, warnings


# --- CLI ---------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-config.py",
        description=(
            "Merge the documented gitissue defaults with the repository's "
            f"{DEFAULT_CONFIG_NAME} and print the result as one JSON line."
        ),
        epilog=(
            "Exit codes: 0 ok; 2 usage; 3 invalid config; 4 cannot complete "
            "(caller falls back to its inline defaults)."
        ),
    )
    parser.add_argument(
        "--config",
        default=DEFAULT_CONFIG_NAME,
        help=f"config file to read (default: {DEFAULT_CONFIG_NAME}, relative to cwd)",
    )
    parser.add_argument(
        "--schema",
        default=None,
        help=(
            f"{SCHEMA_NAME} to derive defaults from (default: the copy bundled "
            "beside this script, then the nearest one above the working directory)"
        ),
    )
    parser.add_argument(
        "--key",
        default=None,
        metavar="DOTTED",
        help="print only this dotted key's value, as raw JSON",
    )
    args = parser.parse_args(argv)

    explicit_config = args.config != DEFAULT_CONFIG_NAME
    try:
        defaults, removed, complete = load_schema(find_schema(args.schema))
        config_path = Path(args.config)
        if config_path.is_file():
            overrides = load_user_config(config_path)
        elif explicit_config:
            raise Unavailable(f"config file not found: {args.config}")
        else:
            overrides = {}
        config, warnings = merge(defaults, overrides, removed, complete)
    except ConfigError as exc:
        for line in str(exc).splitlines():
            print(f"✗ Invalid {DEFAULT_CONFIG_NAME}: {line}", file=sys.stderr)
        return 3
    except Unavailable as exc:
        print(f"⚠ gi-config: {exc}", file=sys.stderr)
        return 4

    for warning in warnings:
        print(f"⚠ gi-config: {warning}", file=sys.stderr)

    if args.key is not None:
        if args.key not in config:
            print(f"✗ gi-config: unknown key '{args.key}'", file=sys.stderr)
            return 2
        print(json.dumps(config[args.key], sort_keys=True))
        return 0

    payload = {
        "config": config,
        "config_file": str(config_path) if config_path.is_file() else None,
        "first_run": not config_path.is_file(),
    }
    sys.stdout.write(json.dumps(payload, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
