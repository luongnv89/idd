#!/usr/bin/env python3
"""Find the `gh` command forms in src/ and the forms the catalog lists (#566).

`docs/platform-github.md` calls its *Operation catalog* the contract every
tracker call must match. This module is the one definition of a "gh call" that
holds the skills to it: the build's `_check_gh_catalog` fails on a form with no
catalog row, and `scripts/surface-count.py` records how many files carry one
(`gh_call_files`). Both load this file, so the two can never disagree.

What a form is
  `gh` at a word boundary, then one of gh's own top-level command groups, then
  the verb: `gh issue view`, `gh pr merge`, `gh label create`. Flags and
  arguments are not part of the form. `gh api`, `gh status` and `gh browse`
  take no verb, so the group alone is the form. A group with no verb after it
  (`the gh pr commands`) is a mention, not a call, and is skipped; so is prose
  such as `gh is not installed` (no group) and a flag-only call such as
  `gh --version`, which reaches no tracker.

  A Python file is also read for argv lists, the way the shared scripts hand a
  call to `gi-gh.py`: a `[` then the group and verb as the list's first two
  string items, optionally after `"gh"` (`["issue", "view", str(n)]`,
  `["gh", "pr", "checks"]`). The list may span lines. `api`, `status` and
  `browse` count only after `"gh"`, since `["status", "--porcelain"]` is a
  git argv, and a subscript such as `data["pr"]` has no verb, so neither is
  a call.

What is scanned
  Every regular file under the given directory whose suffix is in
  SCANNED_SUFFIXES, walked in sorted order. A path with a dot-prefixed or
  `__pycache__` component is skipped, and a symlink is never followed. An argv
  list assembled piece by piece (`args = [group]; args.append(verb)`) is not
  seen; write the group and verb as the list's first two literals.

Standard library only, and no relative imports: `scripts/surface-count.py`
loads this file by path.
"""

from __future__ import annotations

import os
import re

# gh's own top-level commands (`gh help`). A closed list keeps prose out.
GH_GROUPS = (
    "alias", "api", "attestation", "auth", "browse", "cache", "co",
    "codespace", "completion", "config", "extension", "gist", "gpg-key",
    "issue", "label", "org", "pr", "project", "release", "repo", "ruleset",
    "run", "search", "secret", "ssh-key", "status", "variable", "workflow",
)
# Commands that take no verb: the group alone is the form.
SOLO_GROUPS = frozenset({"api", "browse", "status"})

GH_CALL_RE = re.compile(
    r"(?<![\w./-])gh[ \t]+("
    + "|".join(re.escape(g) for g in GH_GROUPS)
    + r")(?![\w-])(?:[ \t]+([a-z][a-z0-9-]*))?"
)

_Q = r"[\"']"
ARGV_RE = re.compile(
    r"\[\s*(" + _Q + r"gh" + _Q + r"\s*,\s*)?" + _Q + r"("
    + "|".join(re.escape(g) for g in GH_GROUPS)
    + r")" + _Q + r"\s*,(?:\s*" + _Q + r"([a-z][a-z0-9-]*)" + _Q + r")?"
)

SCANNED_SUFFIXES = frozenset(
    {".md", ".py", ".sh", ".txt", ".yml", ".yaml", ".json", ".toml"}
)

CATALOG_HEADING = "## Operation catalog"


def forms_in_line(line: str) -> list[str]:
    """The gh forms on one line, in order of appearance."""
    forms = []
    for match in GH_CALL_RE.finditer(line):
        form = _form(match.group(1), match.group(2))
        if form:
            forms.append(form)
    return forms


def _form(group: str, verb: str | None) -> str | None:
    if group in SOLO_GROUPS:
        return f"gh {group}"
    return f"gh {group} {verb}" if verb else None


def argv_forms(text: str) -> list[tuple[int, str]]:
    """(1-based line, form) for every argv-list call in Python source text."""
    hits = []
    for match in ARGV_RE.finditer(text):
        prefixed, group, verb = match.groups()
        if group in SOLO_GROUPS and not prefixed:
            continue  # `["status", "--porcelain"]` is git's argv, not gh's
        form = _form(group, verb)
        if form:
            hits.append((text.count("\n", 0, match.start()) + 1, form))
    return hits


def catalog_forms(doc_text: str) -> set[str] | None:
    """Forms named in the table rows of the Operation catalog section.

    The section runs from its `## Operation catalog` heading to the next `## `
    heading. Only table rows (lines starting with `|`) count: a form named in
    prose there is not a row. None when the section is missing.
    """
    lines = doc_text.splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == CATALOG_HEADING)
    except StopIteration:
        return None
    forms: set[str] = set()
    for line in lines[start + 1:]:
        if line.startswith("## "):
            break
        if line.lstrip().startswith("|"):
            forms.update(forms_in_line(line))
    return forms


def _noise(name: str) -> bool:
    return name.startswith(".") or name == "__pycache__"


def scan(root: str) -> list[tuple[str, int, str]]:
    """(path relative to root, 1-based line, form) for every call under root."""
    hits: list[tuple[str, int, str]] = []
    if not os.path.isdir(root):
        return hits
    for dirpath, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if not _noise(d))
        for name in sorted(files):
            path = os.path.join(dirpath, name)
            if (
                _noise(name)
                or os.path.splitext(name)[1] not in SCANNED_SUFFIXES
                or os.path.islink(path)
                or not os.path.isfile(path)
            ):
                continue
            with open(path, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
            rel = os.path.relpath(path, root)
            for number, line in enumerate(text.splitlines(), 1):
                for form in forms_in_line(line):
                    hits.append((rel, number, form))
            if name.endswith(".py"):
                hits.extend((rel, number, form) for number, form in argv_forms(text))
    return hits


def files_with_calls(root: str) -> int:
    """How many files under root carry at least one gh call."""
    return len({path for path, _, _ in scan(root)})
