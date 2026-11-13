#!/usr/bin/env python3
"""Count the moving parts and hold each count to its record (issue #563).

A skill, a shared script, a config key, a flag and a gate are each a part
somebody has to learn, run and keep working. This script counts them in the
authored tree, compares every count with the number recorded in
`scripts/surface-counts.json`, and fails when one rose without that file
changing in the same PR. `--ratchet` lowers the records as parts are removed.

CI-only tooling — deliberately *not* under `src/shared/scripts/`: nothing cites
it from any skill, and it would count itself. It runs straight from this
checkout, in CI and on a contributor's machine, and nowhere else. It never
runs git and never starts another process: it compares the working tree with
the recorded file and nothing else, so it needs no repository and no base ref.

What is counted (each name is a key of the counts file)
  Every walk is sorted, skips a path with a dot-prefixed or `__pycache__`
  component, and never follows or counts a symlink.

  skills         Directories directly under `src/skills/` and
                 `src/internal-skills/` that hold a `SKILL.source.md`.
  scripts        `src/shared/scripts/*.py`.
  script_lines   Newline characters in those files, summed (`wc -l`).
  config_keys    Leaf keys of the Full Schema block of `docs/config-schema.md`,
                 as dotted keys (`resolve.max_commits` is one key). The block
                 is parsed by `load_schema()` of `src/shared/scripts/gi-config.py`
                 — the parser the skills use — loaded from the measured tree.
  flags          For each skill counted above: the distinct `--flag` tokens in
                 the inline-code spans of its `SKILL.source.md` that start with
                 that skill's own slash command (`` `/issue-triage --limit N` ``
                 in issue-triage's file). A span opens and closes on one line.
                 Summed over skills, so one flag name on two skills counts
                 twice. A flag named only in prose, or in a span that starts
                 with anything else, is not counted.
  gate_headings  Markdown ATX headings (`#` to `######`, then a space) outside
                 fenced code blocks, in every `.md` file under `src/`, whose
                 text holds the whole word `gate` or `gates` in any case.
                 `Gated` and `gateway` are not that word.
  gh_call_files  Files under `src/` that carry at least one `gh` call
                 (`gh issue view`, `gh api`, …), as the build's catalog lint
                 defines one (issue #566). The definition and the walk are
                 `scripts/build/gh_catalog.py`, loaded from this checkout —
                 not from --root — so the count and the lint never disagree.

The counts file (the single place the records live)

    {
      "counts": {
        "config_keys": 109,
        "flags": 26,
        …
      }
    }

Modes
  --check (default)  Fail when ANY of these holds:
      - a count is above its record (a part was added);
      - a count is below its record (a part was removed and the record was
        not lowered with it);
      - a count has no record, or a record names a count this script does
        not measure.
  --ratchet          Rewrite the counts file: every record above its count is
      lowered to it, a count with no record is added, and a record for a
      count that is no longer measured is dropped. A record is NEVER raised:
      a count above its record keeps the record, every other update is still
      written, the rise is reported, and the exit is 1. Writes atomically.

  Raising a record is a deliberate hand edit, never a side effect: set that
  number in `scripts/surface-counts.json` to the new count, commit it in the
  same PR, and say in the PR what the new part replaces or which step it
  removes (`docs/VALUES.md`, SI8).

Output
  A table on stdout (count │ measured │ recorded) followed by one ✓/✗ line
  per count; every failure names the exact fix. `--json` prints one JSON
  object instead: `mode`, `ok`, `measured`, `recorded`, `problems`.

Exit codes
  0  every count equals its record (or the ratchet wrote a file that does)
  1  script-specific verdict: a count rose, dropped, has no record, or a
     record is stale. Not a runtime failure — the change must be fixed (by
     the hand edit for a rise, by --ratchet for the rest) before it merges
  2  usage error
  3  unusable input: the counts file is missing, unreadable or malformed, or
     a directory or file the counts are taken from is missing under --root

Authored at scripts/surface-count.py — CI-only; not bundled into skills.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import pathlib
import re
import stat
import sys
import tempfile

# Loading gi-config.py from the measured tree must not leave a __pycache__ there.
sys.dont_write_bytecode = True

_HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_ROOT = os.path.normpath(os.path.join(_HERE, os.pardir))
COUNTS_REL = os.path.join("scripts", "surface-counts.json")

SKILL_ROOTS = (("src", "skills"), ("src", "internal-skills"))
SKILL_SOURCE = "SKILL.source.md"
SCRIPTS_REL = ("src", "shared", "scripts")
SCHEMA_REL = ("docs", "config-schema.md")
CONFIG_SCRIPT = "gi-config.py"
GH_CATALOG = os.path.join(_HERE, "build", "gh_catalog.py")

_CODE_SPAN = re.compile(r"`([^`\n]+)`")
_FLAG = re.compile(r"(?<![\w-])--[a-z][a-z0-9-]*")
_HEADING = re.compile(r"^ {0,3}#{1,6}[ \t]+(.*)$")
_FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
_GATE = re.compile(r"\bgates?\b", re.IGNORECASE)

FIX_RATCHET = "python3 scripts/surface-count.py --ratchet"
SEP = "┄" * 56


class InputError(Exception):
    """Unusable input — reported as exit 3."""


def _noise(name: str) -> bool:
    return name.startswith(".") or name == "__pycache__"


def _is_regular(path: str) -> bool:
    """True for a regular file; a symlink is never followed."""
    try:
        return stat.S_ISREG(os.lstat(path).st_mode)
    except OSError:
        return False


def _require_dir(path: str) -> str:
    if os.path.islink(path) or not os.path.isdir(path):
        raise InputError(f"directory not found: {path}")
    return path


def _read(path: str) -> str:
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError as exc:
        raise InputError(f"cannot read {path}: {exc}") from exc


def skill_dirs(root: str) -> list[tuple[str, str]]:
    """Sorted (name, path) of every directory that holds a SKILL.source.md."""
    _require_dir(os.path.join(root, *SKILL_ROOTS[0]))
    found = []
    for parts in SKILL_ROOTS:
        base = os.path.join(root, *parts)
        if os.path.islink(base) or not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            path = os.path.join(base, name)
            if _noise(name) or os.path.islink(path) or not os.path.isdir(path):
                continue
            if _is_regular(os.path.join(path, SKILL_SOURCE)):
                found.append((name, path))
    return found


def script_files(root: str) -> list[str]:
    """Sorted paths of the shared scripts."""
    base = _require_dir(os.path.join(root, *SCRIPTS_REL))
    return [
        os.path.join(base, name)
        for name in sorted(os.listdir(base))
        if name.endswith(".py") and not _noise(name)
        and _is_regular(os.path.join(base, name))
    ]


def count_skills(root: str) -> int:
    return len(skill_dirs(root))


def count_scripts(root: str) -> int:
    return len(script_files(root))


def count_script_lines(root: str) -> int:
    total = 0
    for path in script_files(root):
        try:
            with open(path, "rb") as fh:
                total += fh.read().count(b"\n")
        except OSError as exc:
            raise InputError(f"cannot read {path}: {exc}") from exc
    return total


def count_config_keys(root: str) -> int:
    """Leaf keys of the Full Schema block, read by gi-config.py's own parser."""
    script = os.path.join(root, *SCRIPTS_REL, CONFIG_SCRIPT)
    schema = os.path.join(root, *SCHEMA_REL)
    for path in (script, schema):
        if not _is_regular(path):
            raise InputError(f"file not found: {path}")
    try:
        spec = importlib.util.spec_from_file_location("_surface_gi_config", script)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        # load_schema() returns the defaults already flattened to dotted keys.
        defaults = module.load_schema(pathlib.Path(schema))[0]
    except Exception as exc:  # the loaded script's own errors are input errors
        raise InputError(
            f"cannot read the config schema {schema} with {script}: {exc}"
        ) from exc
    if not isinstance(defaults, dict):
        raise InputError(f"{script}: load_schema() did not return a mapping")
    return len(defaults)


def skill_flags(name: str, text: str) -> set[str]:
    """Distinct flags in the code spans that start with the skill's command."""
    command = re.compile(r"/" + re.escape(name) + r"(?![\w-])")
    flags: set[str] = set()
    for line in text.splitlines():
        for span in _CODE_SPAN.findall(line):
            if command.match(span):
                flags.update(_FLAG.findall(span))
    return flags


def count_flags(root: str) -> int:
    return sum(
        len(skill_flags(name, _read(os.path.join(path, SKILL_SOURCE))))
        for name, path in skill_dirs(root)
    )


def gate_headings(text: str) -> int:
    """Headings outside fenced code blocks that hold the word gate or gates."""
    count = 0
    fence = ""  # the opening run of ` or ~ while inside a fenced block
    for line in text.splitlines():
        match = _FENCE.match(line)
        if fence:
            if (
                match
                and match.group(1)[0] == fence[0]
                and len(match.group(1)) >= len(fence)
                and not match.group(2).strip()
            ):
                fence = ""
            continue
        if match and not (match.group(1)[0] == "`" and "`" in match.group(2)):
            fence = match.group(1)
            continue
        heading = _HEADING.match(line)
        if heading and _GATE.search(heading.group(1)):
            count += 1
    return count


def count_gate_headings(root: str) -> int:
    total = 0
    top = _require_dir(os.path.join(root, "src"))
    for dirpath, dirs, files in os.walk(top, followlinks=False):
        dirs[:] = sorted(d for d in dirs if not _noise(d))
        for name in sorted(files):
            path = os.path.join(dirpath, name)
            if name.endswith(".md") and not _noise(name) and _is_regular(path):
                total += gate_headings(_read(path))
    return total


def count_gh_call_files(root: str) -> int:
    """Files under src/ with a gh call, by the build lint's own definition."""
    top = _require_dir(os.path.join(root, "src"))
    if not _is_regular(GH_CATALOG):
        raise InputError(f"file not found: {GH_CATALOG}")
    try:
        spec = importlib.util.spec_from_file_location("_surface_gh_catalog", GH_CATALOG)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module.files_with_calls(top)
    except Exception as exc:  # the loaded module's own errors are input errors
        raise InputError(f"cannot count gh calls with {GH_CATALOG}: {exc}") from exc


# The registry: a new count is one function above and one entry here.
MEASURES = {
    "skills": count_skills,
    "scripts": count_scripts,
    "script_lines": count_script_lines,
    "config_keys": count_config_keys,
    "flags": count_flags,
    "gate_headings": count_gate_headings,
    "gh_call_files": count_gh_call_files,
}


def measure_all(root: str) -> dict[str, int]:
    _require_dir(root)
    return {name: measure(root) for name, measure in MEASURES.items()}


def _is_count(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def load_counts(path: str) -> dict[str, int]:
    """Read and validate the counts file."""
    if not os.path.exists(path):
        raise InputError(
            f"counts file not found: {path}\n"
            "  To fix:  restore it from the base branch. To start a new one, "
            'write {"counts": {}} to it and run ' + FIX_RATCHET
        )
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise InputError(f"cannot read counts file {path}: {exc}") from exc
    counts = data.get("counts") if isinstance(data, dict) else None
    if not isinstance(counts, dict) or set(data) != {"counts"}:
        raise InputError(
            f'counts file {path}: top level must be {{"counts": {{…}}}} and '
            "nothing else"
        )
    for name, value in counts.items():
        if not _is_count(value):
            raise InputError(
                f"counts file {path}: counts.{name} must be a non-negative "
                "integer"
            )
    return counts


def write_counts(path: str, counts: dict[str, int]) -> None:
    """Write the counts file atomically (temp file in place + os.replace)."""
    text = json.dumps(
        {"counts": counts}, indent=2, sort_keys=True, ensure_ascii=False
    ) + "\n"
    fd, tmp = tempfile.mkstemp(
        dir=os.path.dirname(os.path.abspath(path)), prefix=".surface-counts."
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def check(measured: dict[str, int], recorded: dict[str, int],
          counts_file: str) -> list[dict]:
    """One row per count (measured or recorded) with its verdict problems."""
    rows = []
    for name in sorted(set(measured) | set(recorded)):
        actual = measured.get(name)
        record = recorded.get(name)
        row = {"count": name, "measured": actual, "recorded": record,
               "kind": None, "problem": None}
        if record is None:
            row["kind"] = "unrecorded"
            row["problem"] = (
                f"not recorded — counts.{name} is missing from {counts_file}. "
                f"To fix:  {FIX_RATCHET}"
            )
        elif actual is None:
            row["kind"] = "stale"
            row["problem"] = (
                "stale record — this script measures no such count. "
                f"To fix:  {FIX_RATCHET}"
            )
        elif actual > record:
            row["kind"] = "rise"
            row["problem"] = (
                f"rose from {record} to {actual}. --ratchet never raises a "
                "count: remove the new part, or raise it deliberately — set "
                f"counts.{name} to {actual} by hand in {counts_file} in the "
                "same PR, and say in the PR what the new part replaces or "
                "which step it removes (docs/VALUES.md, SI8)"
            )
        elif actual < record:
            row["kind"] = "drop"
            row["problem"] = (
                f"dropped from {record} to {actual} and the record was not "
                f"lowered. To fix:  {FIX_RATCHET}"
            )
        rows.append(row)
    return rows


def ratchet(measured: dict[str, int], recorded: dict[str, int]) -> dict[str, int]:
    """The counts to record: lowered, added or dropped — never raised."""
    return {
        name: min(actual, recorded.get(name, actual))
        for name, actual in measured.items()
    }


def _fmt(value: int | None) -> str:
    return "—" if value is None else f"{value:,}"


def render_table(rows: list[dict]) -> str:
    width = max([len("count")] + [len(r["count"]) for r in rows])
    lines = [
        f"  {'count':<{width}} │ {'measured':>9} │ {'recorded':>9}",
        f"  {'─' * width}─┼─{'─' * 9}─┼─{'─' * 9}",
    ]
    for r in rows:
        lines.append(
            f"  {r['count']:<{width}} │ {_fmt(r['measured']):>9} │ "
            f"{_fmt(r['recorded']):>9}"
        )
    lines.append("")
    for r in rows:
        if r["problem"]:
            lines.append(f"  ✗ {r['count']}: {r['problem']}")
        else:
            lines.append(f"  ✓ {r['count']}: matches its record")
    return "\n".join(lines)


def _display_path(path: str, root: str) -> str:
    """Root-relative when the path is inside the measured tree, else as given."""
    full = os.path.abspath(path)
    base = os.path.abspath(root)
    if full.startswith(base + os.sep):
        return os.path.relpath(full, base)
    return path


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="surface-count.py",
        description=(
            "Check (default) or ratchet the counts of skills, shared scripts, "
            "script lines, config keys, flags, gate headings and files with gh "
            "calls recorded in scripts/surface-counts.json."
        ),
        epilog=(
            "Exit codes: 0 ok · 1 a count rose, dropped or is unrecorded "
            "(verdict) · 2 usage · 3 unusable counts file or tree. "
            f"After removing a part:  {FIX_RATCHET}"
        ),
    )
    parser.add_argument(
        "--root",
        default=DEFAULT_ROOT,
        metavar="DIR",
        help="tree to measure (default: the checkout that holds this script)",
    )
    parser.add_argument(
        "--counts",
        metavar="FILE",
        help="counts file (default: <root>/scripts/surface-counts.json)",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--check",
        action="store_true",
        help="verify every count against its record (default)",
    )
    mode.add_argument(
        "--ratchet",
        action="store_true",
        help="lower the records to the counts; never raises one",
    )
    parser.add_argument(
        "--json", action="store_true", help="print the result as JSON"
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    counts_path = args.counts or os.path.join(args.root, COUNTS_REL)
    try:
        measured = measure_all(args.root)
        recorded = load_counts(counts_path)
    except InputError as exc:
        print(f"✗ {exc}", file=sys.stderr)
        return 3

    if args.ratchet:
        recorded = ratchet(measured, recorded)
        try:
            write_counts(counts_path, recorded)
        except OSError as exc:
            print(f"✗ cannot write counts file {counts_path}: {exc}",
                  file=sys.stderr)
            return 3
    # After a ratchet the only problem left is the one it cannot fix: a rise.
    rows = check(measured, recorded, _display_path(counts_path, args.root))
    failed = any(r["problem"] for r in rows)
    mode = "ratchet" if args.ratchet else "check"

    if args.json:
        print(json.dumps(
            {
                "mode": mode,
                "ok": not failed,
                "measured": measured,
                "recorded": recorded,
                "problems": [
                    {"count": r["count"], "kind": r["kind"],
                     "message": r["problem"]}
                    for r in rows if r["problem"]
                ],
            },
            indent=2,
            sort_keys=True,
            ensure_ascii=False,
        ))
    else:
        print(f"◆ Surface counts — {mode}")
        print(SEP)
        print(render_table(rows))
        print(SEP)
        if args.ratchet:
            print(f"  ✓ wrote {_display_path(counts_path, args.root)}")
        if failed:
            print("  ✗ the surface counts do not match their records")
        else:
            print("  ✓ every surface count matches its record")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
