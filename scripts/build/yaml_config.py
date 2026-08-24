#!/usr/bin/env python3
"""Restricted-YAML parsing and canonical config parity validation."""

from __future__ import annotations

import json
import re
from pathlib import Path

from .common import (
    _DYNAMIC_TEMPLATE_DEFAULTS,
    _FULL_SCHEMA_FENCE_RE,
    _YAML_LIST_RE,
    _YAML_MAPPING_RE,
    _abort,
    _read_text,
)


def _parse_yaml_scalar(value: str) -> object:
    """Parse the restricted scalar syntax used by the canonical config files.

    The build must not depend on a third-party YAML library. This deliberately
    accepts mappings, block lists, quoted strings, booleans, integers, null,
    and init-template replacement tokens; unsupported YAML is a build error
    rather than a silently incomplete parity check.
    """
    value = value.strip()
    if value.startswith('"'):
        try:
            return json.loads(value)
        except json.JSONDecodeError as exc:
            _abort(f"invalid quoted YAML scalar: {value!r} ({exc.msg})")
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
    _abort(f"unsupported YAML scalar in config parity validation: {value!r}")


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
                _abort(f"invalid YAML list item in {label}:{line_number}")
            path = candidates[-1][1]
            result.setdefault(path, [])
            if not isinstance(result[path], list):
                _abort(f"mixed YAML container types for {path} in {label}:{line_number}")
            result[path].append(_parse_yaml_scalar(list_item.group("value")))
            continue

        _abort(f"unsupported YAML syntax in {label}:{line_number}: {raw_line!r}")
    return result


def _documented_config_defaults(schema: Path) -> dict[str, object]:
    match = _FULL_SCHEMA_FENCE_RE.search(_read_text(schema))
    if match is None:
        _abort(f"config schema has no Full Schema YAML block: {schema}")
    return _parse_config_mapping(match.group(1), str(schema))


def _check_init_template_schema_parity(src: Path) -> None:
    """Ensure init's source template has every documented config default.

    The three replacement tokens are intentionally dynamic values selected by
    /init-gitissue after repository detection; every other key must exactly
    match the documented Full Schema default.
    """
    schema = src.parent / "docs" / "config-schema.md"
    template = src / "skills" / "init-gitissue" / "templates" / "gitissue-template.yml"
    schema_exists = schema.is_file()
    template_exists = template.is_file()
    if not schema_exists and not template_exists:
        # Self-contained synthetic source fixtures may intentionally omit the
        # entire init-gitissue contract surface.
        return
    if not schema_exists or not template_exists:
        missing = schema if not schema_exists else template
        _abort(
            "init-template/schema parity validation requires both inputs or neither; "
            f"missing: {missing}"
        )

    documented = _documented_config_defaults(schema)
    rendered_template = _parse_config_mapping(_read_text(template), str(template))
    documented_keys = set(documented)
    template_keys = set(rendered_template)
    missing = sorted(documented_keys - template_keys)
    extra = sorted(template_keys - documented_keys)
    mismatches = []
    for key in sorted(documented_keys & template_keys):
        expected = documented[key]
        actual = rendered_template[key]
        if _DYNAMIC_TEMPLATE_DEFAULTS.get(key) == actual:
            continue
        if actual != expected:
            mismatches.append(f"{key}: documented={expected!r}, template={actual!r}")

    if missing or extra or mismatches:
        details = []
        if missing:
            details.append("missing keys: " + ", ".join(missing))
        if extra:
            details.append("undocumented template keys: " + ", ".join(extra))
        if mismatches:
            details.append("default mismatches: " + "; ".join(mismatches))
        _abort("init-gitissue template/schema parity failed — " + " | ".join(details))
