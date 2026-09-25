#!/usr/bin/env python3
"""Check and ratchet the per-skill bundle size budgets (issue #466).

Every skill under the committed `skills/` install surface is a bundle an agent
loads into its context. This script measures each bundle's *prompt surface* in
bytes, compares it with the ceiling recorded for that skill in
`scripts/skill-budgets.json`, and — in `--ratchet` mode — lowers the ceilings
as the bundles shrink, so a footprint win cannot be silently given back by the
next change.

CI-only tooling — deliberately *not* under `src/shared/scripts/`: nothing cites
it from any skill, so the shared-script rules would refuse to ship it
(tests/test-build-script.sh T8 requires every script there to ship into a
skill). It runs straight from this checkout, in CI and on a contributor's
machine, and nowhere else.

What is measured
  Every regular file under `skills/<name>/`, summed in bytes, EXCEPT:

  - `docs/README.md` — the skill package's human README. It carries the
    DO-NOT-READ notice and is never auto-loaded into agent context.
  - `references/scripts/**` — bundled helpers are executed, not read into
    context; their size is not prompt cost.
  - `*.json` — data files read by scripts, not prose read by the agent. The
    one that exists today, issue-creator's `templates/model-data.json`, is
    rewritten weekly by .github/workflows/model-data-refresh.yml, whose
    allowlist lets it commit only that seed — counting it would turn every
    bot PR red on a stale measurement it is not allowed to fix.
  - any path with a dot-prefixed component (`.DS_Store`, …) or a
    `__pycache__` component — local noise that must not make a contributor's
    machine and CI disagree.

  Symlinks are not followed and are never counted. The walk is sorted, so the
  measurement is deterministic.

  Only the emitted bundles under `skills/` are budgeted. The internal
  `idd-doctor` skill (`src/internal-skills/idd-doctor/`) has no built tree
  (issue #434), so it is not an emitted bundle and has no budget.

The budgets file (the single place budgets and measurements live)

    {
      "headroom_bytes": 1024,
      "skills": {
        "auto-pilot": {"budget": 101024, "measured": 100000},
        …
      }
    }

  `measured` is the bundle's size at the last ratchet; `budget` is its
  ceiling. A fresh entry is `measured + headroom_bytes`.

Modes
  --check (default)  Fail when ANY of these holds:
      - a skill directory has no entry (a new skill is unbudgeted);
      - an entry names a skill that no longer exists (stale entry);
      - actual > budget (the bundle grew past its ceiling);
      - recorded `measured` != actual (the measurement is out of date);
      - budget - actual > headroom_bytes (the bundle shrank and the ceiling
        was not lowered with it).
  --ratchet          Rewrite the budgets file: `measured` = actual, and
      `budget` = min(old budget, actual + headroom) — an existing budget is
      NEVER raised. New skills get actual + headroom; entries for removed
      skills are dropped. A skill already over its budget keeps its budget;
      every other update is still written, the skill is reported, and the
      exit is 1. Creates the file when it does not exist. Writes atomically.

  Raising a budget is a deliberate hand edit, never a side effect: set that
  skill's `budget` to a value at or above its actual size, run `--ratchet`
  (which refreshes `measured` and clamps the budget to actual + headroom),
  commit both, and justify the growth in the PR.

Output
  A table on stdout (skill │ measured │ budget │ slack) followed by one ✓/✗
  line per skill; every failure names the exact fix command. `--json` prints
  the same rows as one JSON object instead.

Exit codes
  0  every budget holds and every measurement is current (or the ratchet
     wrote a file with no skill over its budget)
  1  script-specific verdict: a bundle is over budget, unbudgeted, stale, or
     its recorded measurement is out of date. Not a runtime failure — the
     change must be fixed (usually by running --ratchet) before it merges
  2  usage error
  3  unusable input: the budgets file is missing (in --check), unreadable, or
     malformed, or the skills directory does not exist

Authored at scripts/skill-budget.py — CI-only; not bundled into skills.
"""

from __future__ import annotations

import argparse
import json
import os
import stat
import sys
import tempfile

_HERE = os.path.dirname(os.path.abspath(__file__))
_REPO = os.path.normpath(os.path.join(_HERE, os.pardir))
DEFAULT_SKILLS_DIR = os.path.join(_REPO, "skills")
DEFAULT_BUDGETS = os.path.join(_HERE, "skill-budgets.json")
DEFAULT_HEADROOM = 1024

FIX_RATCHET = "./scripts/build.sh && python3 scripts/skill-budget.py --ratchet"
SEP = "┄" * 56


class InputError(Exception):
    """Unusable input — reported as exit 3."""


def _excluded(rel_parts: tuple[str, ...]) -> bool:
    """True when a path (relative to the skill root) is not prompt surface."""
    if any(p.startswith(".") or p == "__pycache__" for p in rel_parts):
        return True
    if rel_parts == ("docs", "README.md"):
        return True
    if rel_parts[:2] == ("references", "scripts"):
        return True
    return rel_parts[-1].endswith(".json")


def measure_skill(skill_dir: str) -> int:
    """Sum the byte sizes of a skill's prompt-surface files."""
    total = 0
    for root, dirs, files in os.walk(skill_dir, followlinks=False):
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(root, name)
            rel = os.path.relpath(path, skill_dir)
            if _excluded(tuple(rel.split(os.sep))):
                continue
            st = os.lstat(path)
            if stat.S_ISREG(st.st_mode):
                total += st.st_size
    return total


def measure_all(skills_dir: str) -> dict[str, int]:
    """Measure every skill directory directly under `skills_dir`."""
    if not os.path.isdir(skills_dir):
        raise InputError(f"skills directory not found: {skills_dir}")
    sizes = {}
    for name in sorted(os.listdir(skills_dir)):
        path = os.path.join(skills_dir, name)
        if name.startswith(".") or name == "__pycache__":
            continue
        if os.path.islink(path) or not os.path.isdir(path):
            continue
        sizes[name] = measure_skill(path)
    return sizes


def load_budgets(path: str, *, required: bool) -> dict:
    """Read and validate the budgets file. Missing + not required → empty."""
    if not os.path.exists(path):
        if required:
            raise InputError(
                f"budgets file not found: {path}\n"
                f"  To fix:  {FIX_RATCHET}"
            )
        return {"headroom_bytes": DEFAULT_HEADROOM, "skills": {}}
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise InputError(f"cannot read budgets file {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise InputError(f"budgets file {path}: top level must be an object")
    headroom = data.get("headroom_bytes")
    if not _is_count(headroom):
        raise InputError(
            f"budgets file {path}: headroom_bytes must be a non-negative integer"
        )
    skills = data.get("skills")
    if not isinstance(skills, dict):
        raise InputError(f"budgets file {path}: skills must be an object")
    for name, entry in skills.items():
        if (
            not isinstance(entry, dict)
            or not _is_count(entry.get("budget"))
            or not _is_count(entry.get("measured"))
        ):
            raise InputError(
                f"budgets file {path}: skills.{name} needs non-negative "
                "integer budget and measured"
            )
    return data


def _is_count(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def write_budgets(path: str, data: dict) -> None:
    """Write the budgets file atomically (temp file in place + os.replace)."""
    text = json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    fd, tmp = tempfile.mkstemp(
        dir=os.path.dirname(os.path.abspath(path)), prefix=".skill-budgets."
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def check(sizes: dict[str, int], data: dict) -> list[dict]:
    """One row per skill (actual or budgeted) with its verdict problems."""
    headroom = data["headroom_bytes"]
    entries = data["skills"]
    rows = []
    for name in sorted(set(sizes) | set(entries)):
        actual = sizes.get(name)
        entry = entries.get(name)
        row = {
            "skill": name,
            "actual": actual,
            "measured": entry["measured"] if entry else None,
            "budget": entry["budget"] if entry else None,
            "slack": None,
            "problems": [],
        }
        if entry is None:
            row["problems"].append(
                f"unbudgeted skill — no entry in the budgets file. "
                f"To fix:  {FIX_RATCHET}"
            )
        elif actual is None:
            row["problems"].append(
                f"stale entry — skills/{name} no longer exists. "
                f"To fix:  {FIX_RATCHET}"
            )
        else:
            budget = entry["budget"]
            row["slack"] = budget - actual
            if actual > budget:
                row["problems"].append(
                    f"over budget by {actual - budget} bytes "
                    f"({actual} > {budget}). --ratchet never raises a budget: "
                    "shrink the bundle, or raise it deliberately — set "
                    f"skills.{name}.budget >= {actual} by hand, run "
                    f"{FIX_RATCHET}, commit both, and justify the growth in "
                    "the PR"
                )
            elif budget - actual > headroom:
                row["problems"].append(
                    f"unratcheted slack — {budget - actual} bytes under budget, "
                    f"more than the {headroom}-byte headroom; lower the "
                    f"ceiling. To fix:  {FIX_RATCHET}"
                )
            if entry["measured"] != actual and actual <= budget:
                row["problems"].append(
                    f"measurement out of date — recorded {entry['measured']}, "
                    f"actual {actual}. To fix:  {FIX_RATCHET}"
                )
        rows.append(row)
    return rows


def ratchet(sizes: dict[str, int], data: dict) -> tuple[dict, list[str]]:
    """Return the ratcheted budgets file and the skills still over budget."""
    headroom = data["headroom_bytes"]
    old = data["skills"]
    new = {}
    over = []
    for name, actual in sorted(sizes.items()):
        ceiling = actual + headroom
        if name in old:
            budget = old[name]["budget"]
            if actual > budget:
                over.append(name)
            else:
                budget = min(budget, ceiling)
        else:
            budget = ceiling
        new[name] = {"budget": budget, "measured": actual}
    return {"headroom_bytes": headroom, "skills": new}, over


def _fmt(value: int | None) -> str:
    return "—" if value is None else f"{value:,}"


def render_table(rows: list[dict], headroom: int) -> str:
    lines = [
        f"  {'skill':<18} │ {'measured':>9} │ {'budget':>9} │ {'slack':>7}",
        f"  {'─' * 18}─┼─{'─' * 9}─┼─{'─' * 9}─┼─{'─' * 7}",
    ]
    for r in rows:
        lines.append(
            f"  {r['skill']:<18} │ {_fmt(r['actual']):>9} │ "
            f"{_fmt(r['budget']):>9} │ {_fmt(r['slack']):>7}"
        )
    lines.append("")
    for r in rows:
        if r["problems"]:
            for p in r["problems"]:
                lines.append(f"  ✗ {r['skill']}: {p}")
        else:
            lines.append(f"  ✓ {r['skill']}: within budget")
    lines.append("")
    lines.append(f"  ○ headroom: {headroom} bytes per skill")
    return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="skill-budget.py",
        description=(
            "Check (default) or ratchet the per-skill bundle size budgets "
            "recorded in scripts/skill-budgets.json."
        ),
        epilog=(
            "Exit codes: 0 ok · 1 over budget or out of date (verdict) · "
            "2 usage · 3 unusable budgets file or skills dir. "
            f"Refresh after a build:  {FIX_RATCHET}"
        ),
    )
    parser.add_argument(
        "--skills-dir",
        default=DEFAULT_SKILLS_DIR,
        help="built skills tree to measure (default: <repo>/skills)",
    )
    parser.add_argument(
        "--budgets",
        default=DEFAULT_BUDGETS,
        help="budgets file (default: <repo>/scripts/skill-budgets.json)",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--check",
        action="store_true",
        help="verify every bundle against its budget (default)",
    )
    mode.add_argument(
        "--ratchet",
        action="store_true",
        help="refresh measurements and lower budgets; never raises one",
    )
    parser.add_argument(
        "--json", action="store_true", help="print the rows as JSON"
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        sizes = measure_all(args.skills_dir)
        data = load_budgets(args.budgets, required=not args.ratchet)
    except InputError as exc:
        print(f"✗ {exc}", file=sys.stderr)
        return 3

    if args.ratchet:
        data, over = ratchet(sizes, data)
        try:
            write_budgets(args.budgets, data)
        except OSError as exc:
            print(f"✗ cannot write budgets file {args.budgets}: {exc}",
                  file=sys.stderr)
            return 3
        rows = check(sizes, data)
        failed = bool(over)
        title = "◆ Skill bundle budgets — ratchet"
    else:
        rows = check(sizes, data)
        failed = any(r["problems"] for r in rows)
        title = "◆ Skill bundle budgets — check"

    if args.json:
        print(json.dumps(
            {
                "mode": "ratchet" if args.ratchet else "check",
                "ok": not failed,
                "headroom_bytes": data["headroom_bytes"],
                "skills": rows,
            },
            indent=2,
            ensure_ascii=False,
        ))
    else:
        print(title)
        print(SEP)
        print(render_table(rows, data["headroom_bytes"]))
        print(SEP)
        if args.ratchet:
            print(f"  ✓ wrote {os.path.relpath(args.budgets)}")
        if failed:
            print("  ✗ skill bundle budgets do not hold")
        else:
            print("  ✓ every skill bundle is within its budget")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
