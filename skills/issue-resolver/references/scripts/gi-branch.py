#!/usr/bin/env python3
"""Derive a branch name from an issue number, title, and type.

The rules are small — lowercase, hyphens, issue number, type prefix, under 50
characters — which is exactly why they should not be re-applied by hand once per
resolve. Small rules applied from memory drift: a stray uppercase letter, a
trailing hyphen, a name two characters over the limit. The grammar already
exists as a regex in this repository's linter, so the derivation and the
validation can agree by construction instead of by review.

Output on success is exactly one line of JSON on stdout:

    {"branch": "feat/42-dark-mode-toggle", "prefix": "feat/", "issue": 42,
     "slug": "dark-mode-toggle", "type": "feature", "truncated": false,
     "length": 23, "valid": true, "slug_source": "title"}

`valid` is this script checking its own output against the same branch grammar
the repository lint enforces, so a caller never has to.

Two prefix modes, matching `resolve.branch_prefix`:

  "auto"  (default)  type-based — `feat/42-...`, `fix/42-...`
  anything else      the configured prefix verbatim, then the number:
                     `issue-` gives `issue-42-dark-mode-toggle`

The second form is a flat name with no `/` component. A configured prefix is a
literal, and inserting a separator the user did not write would produce a
different branch than the one they configured.

Untrusted input never travels on the command line. Pass `--from-issue` and the
script reads the title (and, absent `--type`, the type from the labels) straight
from GitHub, and `resolve.branch_prefix` from `.gitissue.yml`. Both are
attacker-controlled — anyone can file an issue on a public repository, and
`.gitissue.yml` arrives with a pull request's branch — so a value interpolated
into a shell word could close its quote and append a command, which
`/auto-pilot` would then run unattended. `--title` and `--prefix` remain for
tests and programmatic callers that can pass arguments without a shell.

Exit codes
  0  a branch name was derived and printed
  2  usage error
  3  invalid input — a non-numeric issue number, an unknown issue type with no
     mapping, or a `--max-length` too small to hold the prefix and number
     (stderr: `✗ gi-branch: <why>`). Stop.
  4  cannot complete — `--from-issue` was given and `gh` is missing or the issue
     cannot be read (stderr: `⚠ gi-branch: <reason>`). Degrade to the six
     derivation steps in the naming conventions document.

Authored at src/shared/scripts/gi-branch.py — do not edit installed copies; edit
the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys

# The inclusive maximum total length. The naming conventions say the branch
# name must stay *under* 50 characters, so the default is 49, not 50 — a name
# of exactly 50 violates the rule it is meant to satisfy.
DEFAULT_MAX_LENGTH = 49

# Issue type → branch prefix. The authority is the naming conventions document;
# a repository overrides it with --type-map rather than by editing this file.
DEFAULT_TYPE_MAP = {
    "bug": "fix",
    "feature": "feat",
    "improvement": "refactor",
    "enhancement": "refactor",
    "documentation": "docs",
    "docs": "docs",
    "test": "test",
    "maintenance": "chore",
    "chore": "chore",
}

# Kept identical to BRANCH_RE / BRANCH_EXEMPT_RE in this repository's lint tool.
# The lint tool is not importable from an installed skill, so the grammar is
# restated here and a test asserts the two stay in step.
BRANCH_RE = re.compile(r"^(fix|feat|refactor|docs|test|chore)/(\d+)((?:-[a-z0-9]+)+)$")
BRANCH_EXEMPT_RE = re.compile(r"^(hotfix|release)/[a-z0-9][a-z0-9.-]*$")

# Issue titles often carry a redundant type label. `Bug: login crashes` should
# become `fix/42-login-crashes`, not `fix/42-bug-login-crashes`.
TITLE_LABEL_RE = re.compile(
    r"^\s*(bug|fix|feature|feat|enhancement|improvement|refactor|docs?|"
    r"documentation|test|chore|task|maintenance)\s*[:\-–]\s+",
    re.IGNORECASE,
)

# A separator-less restatement of the prefix — `Fix mobile auth redirect loop`
# under a `fix/` prefix. Only the *first word* is considered and only when it
# equals the chosen prefix, so `Fixture loading fails` keeps its first word and
# `Test harness is flaky` filed as a bug keeps "test" (it is information, not a
# duplicate). Matching the naming conventions' own worked example.
_LEADING_WORD_RE = re.compile(r"^([a-z0-9]+)-(?=.)")

# Used when a title slugs to nothing at all (an emoji-only or CJK-only title).
# Failing there would be worse than a generic name: the branch is a label, and
# the issue number in it is what carries the traceability.
FALLBACK_SLUG = "update"


CONFIG_NAME = ".gitissue.yml"

# Only `resolve.branch_prefix`. Deliberately not a general YAML parser: it
# exists so a config value never has to travel on a command line.
_SECTION_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):\s*$")
_PREFIX_RE = re.compile(r"^\s+branch_prefix:[ \t]+(.*?)\s*$")


class InvalidInput(Exception):
    """Caller-supplied arguments are unusable — exit 3."""


class Unavailable(Exception):
    """A needed external command could not run — exit 4, caller degrades."""


def _unquote(raw: str) -> str:
    if raw.startswith('"'):
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return raw.strip('"')
    if raw.startswith("'") and raw.endswith("'") and len(raw) >= 2:
        return raw[1:-1].replace("''", "'")
    return raw


def find_config(explicit: str | None) -> str | None:
    """Locate `.gitissue.yml`: the explicit path, else upward from the cwd."""
    if explicit:
        return explicit
    here = os.path.abspath(os.getcwd())
    while True:
        candidate = os.path.join(here, CONFIG_NAME)
        if os.path.isfile(candidate):
            return candidate
        parent = os.path.dirname(here)
        if parent == here:
            return None
        here = parent


def read_branch_prefix(path: str) -> str | None:
    """Read `resolve.branch_prefix` from a config file, or None."""
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return None
    inside = False
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        section = _SECTION_RE.match(line)
        if section:
            inside = section.group(1) == "resolve"
            continue
        if inside:
            found = _PREFIX_RE.match(line)
            if found:
                return _unquote(found.group(1))
    return None


def fetch_issue(number: int, repo: str | None) -> tuple[str, list[str]]:
    """Return (title, label names) straight from GitHub.

    Reading the title here rather than accepting it as an argument is a
    security decision, not a convenience. An issue title is written by whoever
    filed the issue — on a public repository, anyone at all — and `/auto-pilot`
    derives branch names unattended. A title interpolated into a shell word can
    close the quote and append a command, so the untrusted text must never
    reach a command line at all.
    """
    args = ["issue", "view", str(number), "--json", "title,labels"]
    if repo:
        args += ["--repo", repo]
    try:
        proc = subprocess.run(
            ["gh", *args], capture_output=True, text=True, check=False
        )
    except FileNotFoundError as exc:
        raise Unavailable("gh is not installed or not on PATH") from exc
    except OSError as exc:
        raise Unavailable(f"cannot run gh — {exc}") from exc
    if proc.returncode != 0:
        detail = proc.stderr.strip().splitlines()
        raise Unavailable(
            f"gh issue view {number} failed: "
            + (detail[-1] if detail else f"exit {proc.returncode}")
        )
    try:
        loaded = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise Unavailable(f"gh printed unparsable JSON — {exc}") from exc
    if not isinstance(loaded, dict):
        raise Unavailable("gh issue view did not return a JSON object")
    labels = [
        str(item.get("name", ""))
        for item in loaded.get("labels") or []
        if isinstance(item, dict)
    ]
    return str(loaded.get("title") or ""), labels


def type_from_labels(labels: list[str], type_map: dict[str, str]) -> str | None:
    """First label that names a known issue type, or None."""
    for label in labels:
        if label.strip().lower() in type_map:
            return label.strip().lower()
    return None


def slugify(title: str) -> str:
    """Lowercase, hyphenate, and strip a title down to `[a-z0-9-]`."""
    text = TITLE_LABEL_RE.sub("", title)
    text = text.lower()
    # Every run of non-alphanumerics becomes one hyphen: this covers "spaces to
    # hyphens" and "remove non-alphanumerics" in one pass, and never leaves the
    # doubled hyphens that a two-step replacement produces from `foo - bar`.
    text = re.sub(r"[^a-z0-9]+", "-", text)
    return text.strip("-")


def truncate(slug: str, budget: int) -> tuple[str, bool]:
    """Trim `slug` to `budget` characters on a word boundary where possible."""
    if budget <= 0:
        return "", bool(slug)
    if len(slug) <= budget:
        return slug, False
    cut = slug[:budget]
    # Prefer a whole-word cut; fall back to a hard cut when the first word is
    # itself longer than the budget.
    if "-" in cut:
        head = cut.rsplit("-", 1)[0].strip("-")
        if head:
            return head, True
    return cut.strip("-"), True


def parse_type_map(raw: str | None) -> dict[str, str]:
    """Parse `--type-map "bug=fix,feature=feat"` over the built-in defaults."""
    mapping = dict(DEFAULT_TYPE_MAP)
    if not raw:
        return mapping
    for pair in raw.split(","):
        pair = pair.strip()
        if not pair:
            continue
        if "=" not in pair:
            raise InvalidInput(f"--type-map entry must be key=value, got {pair!r}")
        key, value = pair.split("=", 1)
        key, value = key.strip().lower(), value.strip().lower()
        if not key or not value:
            raise InvalidInput(f"--type-map entry must be key=value, got {pair!r}")
        mapping[key] = value
    return mapping


def derive(
    number: int,
    title: str,
    issue_type: str | None,
    branch_prefix: str,
    type_map: dict[str, str],
    max_length: int,
) -> dict[str, object]:
    """Build the branch name and report how it was built."""
    if branch_prefix == "auto":
        key = (issue_type or "").strip().lower()
        if not key:
            raise InvalidInput(
                "--type is required when the branch prefix is 'auto' "
                "(pass --prefix to use a fixed prefix instead)"
            )
        if key not in type_map:
            raise InvalidInput(
                f"unknown issue type {issue_type!r} — extend it with "
                "--type-map, e.g. --type-map 'spike=chore'"
            )
        prefix = f"{type_map[key]}/"
    else:
        prefix = branch_prefix

    head = f"{prefix}{number}-"
    if len(head) + 1 > max_length:
        raise InvalidInput(
            f"--max-length {max_length} leaves no room for {head!r} plus a slug"
        )

    slug = slugify(title)
    if branch_prefix == "auto":
        leading = _LEADING_WORD_RE.match(slug)
        if leading and leading.group(1) == prefix.rstrip("/"):
            slug = slug[leading.end():]
    slug_source = "title"
    if not slug:
        slug = FALLBACK_SLUG
        slug_source = "fallback"

    slug, truncated = truncate(slug, max_length - len(head))
    if not slug:  # every word was longer than the remaining budget
        slug = FALLBACK_SLUG[: max_length - len(head)] or FALLBACK_SLUG
        slug_source = "fallback"

    branch = f"{head}{slug}"
    return {
        "branch": branch,
        "prefix": prefix,
        "issue": number,
        "slug": slug,
        "type": (issue_type or "").strip().lower() or None,
        "truncated": truncated,
        "length": len(branch),
        "valid": bool(BRANCH_RE.match(branch) or BRANCH_EXEMPT_RE.match(branch)),
        "slug_source": slug_source,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-branch.py",
        description=(
            "Derive a convention-conformant branch name from an issue number, "
            "title, and type. Prints one JSON object on stdout."
        ),
        epilog="Example: python3 gi-branch.py 42 --from-issue --type feature",
    )
    parser.add_argument("number", help="issue number")
    parser.add_argument(
        "--from-issue",
        action="store_true",
        help=(
            "read the title (and, failing --type, the type) from GitHub rather "
            "than the command line — REQUIRED for untrusted issues"
        ),
    )
    parser.add_argument("--repo", metavar="OWNER/NAME")
    parser.add_argument(
        "--title",
        default="",
        help=(
            "issue title. Never pass untrusted text here: a title is written "
            "by whoever filed the issue, and interpolating it into a shell "
            "word is a command injection. Use --from-issue"
        ),
    )
    parser.add_argument("--type", dest="issue_type", help="bug | feature | ...")
    parser.add_argument(
        "--prefix",
        help=(
            "resolve.branch_prefix override: 'auto' for type-based, else a "
            "literal prefix. Default: read from .gitissue.yml, then 'auto'"
        ),
    )
    parser.add_argument(
        "--config", metavar="PATH", help=f"{CONFIG_NAME} to read resolve.branch_prefix from"
    )
    parser.add_argument(
        "--no-config", action="store_true", help="ignore any config file"
    )
    parser.add_argument(
        "--type-map", help="override the type→prefix map, e.g. 'spike=chore'"
    )
    parser.add_argument(
        "--max-length",
        type=int,
        default=DEFAULT_MAX_LENGTH,
        metavar="N",
        help=(
            f"inclusive maximum total branch length (default "
            f"{DEFAULT_MAX_LENGTH}, which keeps the name *under* the 50 "
            "characters the naming conventions require)"
        ),
    )
    args = parser.parse_args(argv)

    try:
        if not args.number.isdecimal():
            # isdigit() accepts superscripts and other Unicode digits that int()
            # then rejects, raising out of main() as exit 1 with a traceback.
            raise InvalidInput(f"issue must be a number, got {args.number!r}")
        if args.max_length < 1:
            raise InvalidInput("--max-length must be >= 1")
        number = int(args.number)
        type_map = parse_type_map(args.type_map)

        title = args.title
        issue_type = args.issue_type
        if args.from_issue:
            title, labels = fetch_issue(number, args.repo)
            if not issue_type:
                issue_type = type_from_labels(labels, type_map)

        prefix = args.prefix
        if prefix is None:
            prefix = "auto"
            if not args.no_config:
                path = find_config(args.config)
                if path is not None:
                    prefix = read_branch_prefix(path) or "auto"
                elif args.config:
                    raise InvalidInput(f"config file not found: {args.config}")

        result = derive(
            number, title, issue_type, prefix, type_map, args.max_length
        )
    except InvalidInput as exc:
        sys.stderr.write(f"✗ gi-branch: {exc}\n")
        return 3
    except Unavailable as exc:
        sys.stderr.write(f"⚠ gi-branch: {exc}\n")
        return 4

    print(json.dumps(result))
    if not result["valid"]:
        # Only reachable with a custom --prefix: the repository grammar covers
        # the six type prefixes, and a configured prefix is outside it by
        # definition. Surfaced so a caller can see why lint may object.
        sys.stderr.write(
            f"⚠ gi-branch: {result['branch']} is outside the default branch "
            "grammar (custom prefix)\n"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
