#!/usr/bin/env python3
"""Check and ratchet the per-skill bundle size budgets (issues #466, #558).

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

  Only the public emitted bundles under `skills/` are budgeted. Local-only
  bundles under `internal-skills/` (including `idd-doctor`, issue #434) are
  deliberately outside this public install-surface budget.

The budgets file (the single place budgets and measurements live)

    {
      "headroom_bytes": 1024,
      "skills": {
        "auto-pilot": {
          "budget": 101024, "measured": 100000,
          "skill_md": {"budget": 21024, "measured": 20000},
          "always_read": {
            "files": ["references/summary-format.md"],
            "budget": 9024, "measured": 8000
          }
        },
        …
      }
    }

  `measured` is the bundle's size at the last ratchet; `budget` is its
  ceiling. A fresh entry is `measured + headroom_bytes`.

Two more budgets per skill (issue #558)
  Both follow the bundle rules exactly, with the same `headroom_bytes`: over
  budget fails, slack beyond the headroom fails, a stale `measured` fails,
  and --ratchet lowers a ceiling but never raises one.

  - `skill_md` — the bytes of the built `skills/<name>/SKILL.md`, the one
    file every invocation of the skill loads in full.
  - `always_read` — the summed bytes of the files SKILL.md tells the agent
    to read unconditionally. A line of SKILL.md names such a file when it
    says, case-insensitively, either "read `references/x.md` now" or
    "read `references/x.md` first" (an optional parenthesis may sit between
    the path and that word), or names a `references/….md` path and later on
    the same line says "read it now" (the nearest path before those words
    is the one meant). The first form may list several paths joined by
    commas or "and" ("read `references/a.md` and `references/b.md` now");
    every listed file counts. A plain "Read `references/x.md`", "First read
    …", "now reads" and "Sync now?" are not pointers. The match is on the
    wording only: a pointer inside a conditional sentence still counts, so
    the figure errs high. Each file counts once per skill; `files` records
    the sorted set. A pointer to a file that is not in the bundle fails, and a set
    that differs from the recorded `files` is stale until ratcheted. A
    skill with no pointer records `files: []` and `measured: 0`.

  An entry that lacks either field fails --check and names the ratchet
  command; a field that is present but malformed is unusable input (exit 3).

Growth cap against the last release tag (issue #558)
  With `--baseline FILE --baseline-tag TAG`, FILE is the budgets file as it
  was at that release tag (only `skills.<name>.measured` is read from it, so
  a file older than the two fields above still loads). A bundle more than
  2% larger than its `measured` at the tag fails, unless the change log
  exempts it. A skill the baseline does not name is new and uncapped.
  Exactly +2% passes.

  The change log is the `## Change log` section of `--changelog FILE`
  (default: <repo>/docs/VALUES.md): from that heading to the next heading of
  the same or a higher level. A table row in it (a line starting with `|`)
  exempts a skill for a tag when it holds both the skill name and the tag as
  whole tokens, for example

      | 2026-11-12 | issue-pr-review | v0.27.0 | reason |

  `issue-pr-review-x` does not name `issue-pr-review`, and `v0.27.01` or
  `v0.27.0.1` do not name `v0.27.0`. An absent, unreadable or section-less
  change log grants no exemption; it is never a pass and never an error.
  This script does not run git: the caller extracts the tagged file.

Modes
  --check (default)  Fail when ANY of these holds:
      - a skill directory has no entry (a new skill is unbudgeted);
      - an entry names a skill that no longer exists (stale entry);
      - actual > budget (the bundle grew past its ceiling);
      - recorded `measured` != actual (the measurement is out of date);
      - budget - actual > headroom_bytes (the bundle shrank and the ceiling
        was not lowered with it);
      - any of the three rules above holds for `skill_md` or `always_read`,
        either field is missing, an always-read file is missing from the
        bundle, or the recorded `files` is not the detected set;
      - with --baseline: the bundle is more than 2% above its size at the
        tag and the change log has no row for that skill and tag.
  --ratchet          Rewrite the budgets file: `measured` = actual, and
      `budget` = min(old budget, actual + headroom) — an existing budget is
      NEVER raised. New skills get actual + headroom; entries for removed
      skills are dropped. A skill already over its budget keeps its budget;
      every other update is still written, the skill is reported, and the
      exit is 1. `skill_md` and `always_read` are ratcheted the same way
      (a missing field is seeded at actual + headroom) and `files` is
      rewritten. Creates the file when it does not exist. Writes atomically.

  Raising a budget is a deliberate hand edit, never a side effect: set that
  skill's `budget` to a value at or above its actual size, run `--ratchet`
  (which refreshes `measured` and clamps the budget to actual + headroom),
  commit both, and justify the growth in the PR. The same hand edit raises
  `skill_md.budget` or `always_read.budget`.

Output
  A table on stdout (skill │ measured │ budget │ slack │ SKILL.md │ ceiling
  │ always-read │ budget, plus growth against the tag when --baseline is
  given) followed by one ✓/✗ line per skill; every failure names the exact
  fix. A growth the change log exempts prints a ⚠ line. `--json` prints the
  same rows as one JSON object instead.

Exit codes
  0  every budget holds and every measurement is current (or the ratchet
     wrote a file with no skill over its budget)
  1  script-specific verdict: a bundle, SKILL.md or always-read set is over
     budget, unbudgeted, stale, or its recorded measurement is out of date,
     or a bundle grew past the cap with no change-log row. Not a runtime
     failure — the change must be fixed (usually by running --ratchet)
     before it merges
  2  usage error (including --baseline without --baseline-tag)
  3  unusable input: the budgets file is missing (in --check), unreadable, or
     malformed, the baseline file is unreadable or malformed, or the skills
     directory does not exist

Authored at scripts/skill-budget.py — CI-only; not bundled into skills.
"""

from __future__ import annotations

import argparse
import json
import os
import posixpath
import re
import stat
import sys
import tempfile

_HERE = os.path.dirname(os.path.abspath(__file__))
_REPO = os.path.normpath(os.path.join(_HERE, os.pardir))
DEFAULT_SKILLS_DIR = os.path.join(_REPO, "skills")
DEFAULT_BUDGETS = os.path.join(_HERE, "skill-budgets.json")
DEFAULT_CHANGELOG = os.path.join(_REPO, "docs", "VALUES.md")
DEFAULT_HEADROOM = 1024
GROWTH_CAP_PCT = 2

# Always-read pointers in a built SKILL.md (see the module docstring).
_PTR_PATH = r"(references/[A-Za-z0-9_./-]+\.md)"
_PTR_PAREN = r"(?:\s*\([^)\n]*\))?"
_PTR_ITEM = r"`?references/[A-Za-z0-9_./-]+\.md`?" + _PTR_PAREN
# "read A now", "read A first", "read A, B and C now" — group 1 is the list.
_PTR_READ_NOW = re.compile(
    r"\bread\s+(" + _PTR_ITEM
    + r"(?:(?:\s*,\s*(?:and\s+)?|\s+and\s+)" + _PTR_ITEM + r")*)"
    + r"\s+(?:now|first)\b",
    re.IGNORECASE,
)
_PTR_PAREN_TEXT = re.compile(r"\([^)\n]*\)")
_PTR_READ_IT_NOW = re.compile(
    _PTR_PATH + r"(?:(?!references/)[^\n])*?\bread\s+it\s+now\b",
    re.IGNORECASE,
)
_CHANGELOG_HEADING = re.compile(r"^(#{2,})\s+change\s*log\s*#*\s*$", re.IGNORECASE)
_HEADING = re.compile(r"^(#+)\s")

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


def _regular_size(path: str) -> int | None:
    """Byte size of a regular file; None for anything else (never follows)."""
    try:
        st = os.lstat(path)
    except OSError:
        return None
    return st.st_size if stat.S_ISREG(st.st_mode) else None


def always_read_pointers(text: str) -> list[str]:
    """Sorted, de-duplicated `references/….md` paths SKILL.md says to read now."""
    found = set()
    for line in text.splitlines():
        for match in _PTR_READ_NOW.finditer(line):
            listed = _PTR_PAREN_TEXT.sub("", match.group(1))
            for path in re.findall(_PTR_PATH, listed):
                found.add(posixpath.normpath(path))
        for match in _PTR_READ_IT_NOW.finditer(line):
            found.add(posixpath.normpath(match.group(1)))
    return sorted(found)


def measure_surfaces(skills_dir: str, names) -> dict[str, dict]:
    """Per skill: SKILL.md bytes and the always-read files with their bytes."""
    out = {}
    for name in names:
        skill_dir = os.path.join(skills_dir, name)
        skill_md = os.path.join(skill_dir, "SKILL.md")
        size = _regular_size(skill_md)
        text = ""
        if size is not None:
            try:
                with open(skill_md, encoding="utf-8", errors="replace") as fh:
                    text = fh.read()
            except OSError:
                text = ""
        files = always_read_pointers(text)
        total = 0
        missing = []
        for rel in files:
            # A path that climbs out of references/ is not a bundled file.
            inside = rel.startswith("references/")
            fsize = _regular_size(os.path.join(skill_dir, *rel.split("/"))) if inside else None
            if fsize is None:
                missing.append(rel)
            else:
                total += fsize
        out[name] = {
            "skill_md": size or 0,
            "files": files,
            "always_read": total,
            "missing": missing,
        }
    return out


def _display_path(path: str) -> str:
    """Repo-relative when the path is inside this checkout, else as given."""
    full = os.path.abspath(path)
    if full.startswith(_REPO + os.sep):
        return os.path.relpath(full, _REPO)
    return path


def load_baseline(path: str) -> dict[str, int]:
    """Read `skills.<name>.measured` from a release-tag budgets file.

    Lenient on purpose: a tagged file may predate every other field.
    """
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise InputError(f"cannot read baseline file {path}: {exc}") from exc
    skills = data.get("skills") if isinstance(data, dict) else None
    if not isinstance(skills, dict):
        raise InputError(f"baseline file {path}: skills must be an object")
    out = {}
    for name, entry in skills.items():
        if not isinstance(entry, dict) or not _is_count(entry.get("measured")):
            raise InputError(
                f"baseline file {path}: skills.{name} needs a non-negative "
                "integer measured"
            )
        out[name] = entry["measured"]
    return out


def changelog_rows(path: str) -> list[str]:
    """Table rows of the `## Change log` section; [] when there is none.

    An absent or unreadable file, or one without the section, yields no rows
    and therefore no exemption — never a pass and never an error.
    """
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return []
    rows = []
    level = None
    for line in lines:
        if level is None:
            match = _CHANGELOG_HEADING.match(line)
            if match:
                level = len(match.group(1))
            continue
        heading = _HEADING.match(line)
        if heading and len(heading.group(1)) <= level:
            level = None
            match = _CHANGELOG_HEADING.match(line)
            if match:
                level = len(match.group(1))
            continue
        if line.lstrip().startswith("|"):
            rows.append(line)
    return rows


def is_exempt(rows: list[str], skill: str, tag: str) -> bool:
    """True when one change-log row names both the skill and the tag."""
    skill_re = re.compile(
        r"(?<![A-Za-z0-9_-])" + re.escape(skill) + r"(?![A-Za-z0-9_-])"
    )
    # A trailing "." is sentence punctuation unless more of a version follows.
    tag_re = re.compile(
        r"(?<![A-Za-z0-9_.-])" + re.escape(tag)
        + r"(?![A-Za-z0-9_-])(?!\.[A-Za-z0-9])"
    )
    return any(skill_re.search(row) and tag_re.search(row) for row in rows)


def _pct(delta: int, base: int) -> str:
    """Signed growth as a percentage with two decimals (integer math)."""
    if base <= 0:
        return "n/a"
    hundredths = abs(delta) * 10000 // base
    sign = "-" if delta < 0 else "+"
    return f"{sign}{hundredths // 100}.{hundredths % 100:02d}%"


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
        # Absent is a --check verdict (the ratchet seeds it); malformed is not.
        for key in SUB_BUDGETS:
            sub = entry.get(key)
            if sub is None and key not in entry:
                continue
            ok = (
                isinstance(sub, dict)
                and _is_count(sub.get("budget"))
                and _is_count(sub.get("measured"))
            )
            if ok and key == "always_read":
                files = sub.get("files")
                ok = isinstance(files, list) and all(
                    isinstance(f, str) for f in files
                )
            if not ok:
                raise InputError(
                    f"budgets file {path}: skills.{name}.{key} needs "
                    "non-negative integer budget and measured"
                    + (" and a files list of strings"
                       if key == "always_read" else "")
                )
    return data


# key in a skill's entry → (label in messages, key in measure_surfaces()).
SUB_BUDGETS = {
    "skill_md": ("SKILL.md", "skill_md"),
    "always_read": ("always-read files", "always_read"),
}


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


def _check_sub(name: str, key: str, actual: int, sub: dict | None,
               headroom: int) -> tuple[dict, list[str]]:
    """Apply the three bundle rules to one sub-budget (skill_md, always_read)."""
    label = SUB_BUDGETS[key][0]
    cell = {"actual": actual, "measured": None, "budget": None, "slack": None}
    if sub is None:
        return cell, [
            f"{label} budget not recorded — skills.{name}.{key} is missing. "
            f"To fix:  {FIX_RATCHET}"
        ]
    budget = sub["budget"]
    cell.update(measured=sub["measured"], budget=budget, slack=budget - actual)
    problems = []
    if actual > budget:
        problems.append(
            f"{label} over budget by {actual - budget} bytes "
            f"({actual} > {budget}). --ratchet never raises a budget: "
            f"shrink it, or raise it deliberately — set "
            f"skills.{name}.{key}.budget >= {actual} by hand, run "
            f"{FIX_RATCHET}, commit both, and justify the growth in the PR"
        )
    elif budget - actual > headroom:
        problems.append(
            f"{label} unratcheted slack — {budget - actual} bytes under "
            f"budget, more than the {headroom}-byte headroom; lower the "
            f"ceiling. To fix:  {FIX_RATCHET}"
        )
    if sub["measured"] != actual and actual <= budget:
        problems.append(
            f"{label} measurement out of date — recorded {sub['measured']}, "
            f"actual {actual}. To fix:  {FIX_RATCHET}"
        )
    return cell, problems


def check(sizes: dict[str, int], data: dict, surfaces: dict[str, dict],
          growth: dict | None = None) -> list[dict]:
    """One row per skill (actual or budgeted) with its verdict problems.

    `growth` is None, or {"tag", "baseline": {skill: bytes}, "rows": [...],
    "changelog": path} to apply the release-tag growth cap as well.
    """
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
            "skill_md": None,
            "always_read": None,
            "growth": None,
            "problems": [],
            "notes": [],
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
        if actual is not None:
            surface = surfaces[name]
            if entry is not None:
                for key, (_label, skey) in SUB_BUDGETS.items():
                    cell, problems = _check_sub(
                        name, key, surface[skey], entry.get(key), headroom
                    )
                    row[key] = cell
                    row["problems"].extend(problems)
                row["always_read"]["files"] = surface["files"]
                recorded = (entry.get("always_read") or {}).get("files")
                if recorded is not None and sorted(recorded) != surface["files"]:
                    row["problems"].append(
                        "always-read files out of date — SKILL.md now points "
                        f"at [{', '.join(surface['files']) or 'none'}], "
                        f"recorded [{', '.join(sorted(recorded)) or 'none'}]. "
                        f"To fix:  {FIX_RATCHET}"
                    )
            for rel in surface["missing"]:
                row["problems"].append(
                    f"always-read file missing — SKILL.md says to read {rel} "
                    f"up front, and skills/{name}/{rel} is not in the bundle. "
                    "Restore the file or remove the pointer, then rebuild"
                )
            if growth is not None and name in growth["baseline"]:
                base = growth["baseline"][name]
                over = actual * 100 > base * (100 + GROWTH_CAP_PCT)
                exempt = over and is_exempt(growth["rows"], name, growth["tag"])
                pct = _pct(actual - base, base)
                row["growth"] = {
                    "tag": growth["tag"],
                    "baseline": base,
                    "bytes": actual - base,
                    "pct": pct,
                    "over_cap": over,
                    "exempt": exempt,
                }
                if over and exempt:
                    row["notes"].append(
                        f"grew {actual - base} bytes ({pct}) since "
                        f"{growth['tag']}, over the {GROWTH_CAP_PCT}% cap — "
                        f"exempted by a change-log row in {growth['changelog']}"
                    )
                elif over:
                    row["problems"].append(
                        f"grew {actual - base} bytes ({pct}) since "
                        f"{growth['tag']} ({base} → {actual}), over the "
                        f"{GROWTH_CAP_PCT}% growth cap. Shrink the bundle, or "
                        f"add a row naming {name} and {growth['tag']} to the "
                        f"`## Change log` table of {growth['changelog']} — "
                        "that file changes only on the maintainer's request"
                    )
        rows.append(row)
    return rows


def _ratchet_one(old: dict | None, actual: int, headroom: int) -> tuple[int, bool]:
    """New budget for one figure and whether it is over its old budget."""
    ceiling = actual + headroom
    if old is None:
        return ceiling, False
    if actual > old["budget"]:
        return old["budget"], True
    return min(old["budget"], ceiling), False


def ratchet(sizes: dict[str, int], data: dict,
            surfaces: dict[str, dict]) -> tuple[dict, list[str]]:
    """Return the ratcheted budgets file and the skills still over budget."""
    headroom = data["headroom_bytes"]
    old = data["skills"]
    new = {}
    over = []
    for name, actual in sorted(sizes.items()):
        prev = old.get(name)
        surface = surfaces[name]
        budget, is_over = _ratchet_one(prev, actual, headroom)
        entry = {"budget": budget, "measured": actual}
        for key, (_label, skey) in SUB_BUDGETS.items():
            sub_budget, sub_over = _ratchet_one(
                prev.get(key) if prev else None, surface[skey], headroom
            )
            entry[key] = {"budget": sub_budget, "measured": surface[skey]}
            is_over = is_over or sub_over
        entry["always_read"]["files"] = surface["files"]
        if is_over:
            over.append(name)
        new[name] = entry
    return {"headroom_bytes": headroom, "skills": new}, over


def _fmt(value: int | None) -> str:
    return "—" if value is None else f"{value:,}"


def render_table(rows: list[dict], headroom: int) -> str:
    with_growth = any(r["growth"] for r in rows)
    heads = [("measured", 9), ("budget", 9), ("slack", 7), ("SKILL.md", 8),
             ("ceiling", 8), ("always-read", 11), ("budget", 8)]
    if with_growth:
        heads.append(("growth", 8))
    lines = [
        f"  {'skill':<18} │ " + " │ ".join(f"{h:>{w}}" for h, w in heads),
        f"  {'─' * 18}─┼─" + "─┼─".join("─" * w for _h, w in heads),
    ]
    for r in rows:
        md = r["skill_md"] or {}
        ar = r["always_read"] or {}
        cells = [
            _fmt(r["actual"]), _fmt(r["budget"]), _fmt(r["slack"]),
            _fmt(md.get("actual")), _fmt(md.get("budget")),
            _fmt(ar.get("actual")), _fmt(ar.get("budget")),
        ]
        if with_growth:
            cells.append(r["growth"]["pct"] if r["growth"] else "—")
        lines.append(
            f"  {r['skill']:<18} │ "
            + " │ ".join(f"{c:>{w}}" for c, (_h, w) in zip(cells, heads))
        )
    lines.append("")
    for r in rows:
        if r["problems"]:
            for p in r["problems"]:
                lines.append(f"  ✗ {r['skill']}: {p}")
        else:
            lines.append(f"  ✓ {r['skill']}: within budget")
        for n in r["notes"]:
            lines.append(f"  ⚠ {r['skill']}: {n}")
    lines.append("")
    lines.append(f"  ○ headroom: {headroom} bytes per budget")
    if with_growth:
        lines.append(
            f"  ○ growth cap: {GROWTH_CAP_PCT}% over {rows_tag(rows)}"
        )
    return "\n".join(lines)


def rows_tag(rows: list[dict]) -> str:
    return next(r["growth"]["tag"] for r in rows if r["growth"])


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
    parser.add_argument(
        "--baseline",
        metavar="FILE",
        help=(
            "budgets file as of the last release tag; enables the "
            f"{GROWTH_CAP_PCT}%% growth cap (needs --baseline-tag)"
        ),
    )
    parser.add_argument(
        "--baseline-tag",
        metavar="TAG",
        help="the release tag --baseline was taken from, e.g. v0.27.0",
    )
    parser.add_argument(
        "--changelog",
        metavar="FILE",
        default=DEFAULT_CHANGELOG,
        help=(
            "file whose `## Change log` table exempts a skill from the "
            "growth cap (default: <repo>/docs/VALUES.md)"
        ),
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.baseline is not None and not args.baseline_tag:
        parser.error("--baseline requires a non-empty --baseline-tag")
    try:
        sizes = measure_all(args.skills_dir)
        surfaces = measure_surfaces(args.skills_dir, sizes)
        data = load_budgets(args.budgets, required=not args.ratchet)
        growth = None
        if args.baseline is not None:
            growth = {
                "tag": args.baseline_tag,
                "baseline": load_baseline(args.baseline),
                "rows": changelog_rows(args.changelog),
                "changelog": _display_path(args.changelog),
            }
    except InputError as exc:
        print(f"✗ {exc}", file=sys.stderr)
        return 3

    if args.ratchet:
        data, over = ratchet(sizes, data, surfaces)
        try:
            write_budgets(args.budgets, data)
        except OSError as exc:
            print(f"✗ cannot write budgets file {args.budgets}: {exc}",
                  file=sys.stderr)
            return 3
        rows = check(sizes, data, surfaces, growth)
        # After a ratchet the only problems left are the ones it cannot fix:
        # an over-budget figure, a missing always-read file, the growth cap.
        failed = bool(over) or any(r["problems"] for r in rows)
        title = "◆ Skill bundle budgets — ratchet"
    else:
        rows = check(sizes, data, surfaces, growth)
        failed = any(r["problems"] for r in rows)
        title = "◆ Skill bundle budgets — check"

    if args.json:
        print(json.dumps(
            {
                "mode": "ratchet" if args.ratchet else "check",
                "ok": not failed,
                "headroom_bytes": data["headroom_bytes"],
                "growth_cap_pct": GROWTH_CAP_PCT,
                "baseline_tag": args.baseline_tag if growth else None,
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
