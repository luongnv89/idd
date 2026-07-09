#!/usr/bin/env python3
"""Parse local issue numbers from SPEC §2 dependency markers in an issue body.

Cross-repo references (org/repo#N) MUST be ignored per SPEC §2.
Used by tests and referenced from auto-pilot phases.md Step 5.1b.
"""

from __future__ import annotations

import re

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


def main() -> None:
    import sys

    body = sys.stdin.read()
    for n in extract_dependency_issue_numbers(body):
        print(n)


if __name__ == "__main__":
    main()