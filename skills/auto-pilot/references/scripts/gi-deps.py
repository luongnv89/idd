#!/usr/bin/env python3
"""Parse local issue numbers from SPEC §2 dependency markers in an issue body.

Reads the issue body on stdin and prints one local issue number per line, in
first-appearance order, deduplicated. Cross-repo references (`org/repo#N`) MUST
be ignored per SPEC §2 — only issues in the current repository can gate a merge.

Exit code is always 0: an issue body with no dependency markers is the normal
case, not an error, and prints nothing.

Authored at src/shared/scripts/gi-deps.py — do not edit installed copies; edit
the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import re
import sys

MARKER_RE = re.compile(r"(?i)\b(?:depends\s+on|blocked\s+by)\b")
CROSS_REPO_TOKEN_RE = re.compile(r"\S+/\S+#\d+")
BARE_ISSUE_RE = re.compile(r"(?<![\w/])#(\d+)")


def extract_dependency_issue_numbers(body: str) -> list[int]:
    """Return unique local issue numbers from Depends on / Blocked by lines."""
    found: list[int] = []
    seen: set[int] = set()
    for line in body.splitlines():
        if not MARKER_RE.search(line):
            continue
        local_segment = CROSS_REPO_TOKEN_RE.sub("", line)
        for match in BARE_ISSUE_RE.finditer(local_segment):
            number = int(match.group(1))
            if number not in seen:
                seen.add(number)
                found.append(number)
    return found


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-deps.py",
        description=(
            "Read an issue body on stdin; print each local dependency issue "
            "number on its own line. Cross-repo org/repo#N tokens are ignored."
        ),
        epilog="Example: printf '%s' \"$issue_body\" | python3 gi-deps.py",
    )
    parser.parse_args(argv)
    for n in extract_dependency_issue_numbers(sys.stdin.read()):
        print(n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
