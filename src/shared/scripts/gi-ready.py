#!/usr/bin/env python3
"""Judge whether an issue is ready for an unattended resolve (issue #553).

The rule's prose home is *Issue Readiness* in the IDD methodology document;
this script is its deterministic form. An issue is **ready** when its body has an
`Acceptance Criteria` heading (any level, any case, an optional trailing colon)
with at least one list item under it, and neither the value under the `Type`
heading nor any of those criteria ends with the `(needs review)` marker.

Only a *trailing* marker counts, so an issue that merely discusses the marker is
not flagged: inline code spans are dropped first, and blockquote lines (the
preserved `> Reporter Context`) and fenced code are never read.

Input on stdin, one JSON value: a `gi-issue.py` envelope (`{"issue": {...}}`),
a `gi-backlog.py` envelope (`{"issues": [...]}`), a bare issue object, or an
array of them. Each issue needs a `body` key (`null` reads as empty). Issue
bodies are untrusted text; they arrive on stdin, never on the command line.

Output, one JSON line on stdout. A single issue:

    {"number": 12, "ready": false, "reasons": ["no_criteria"]}

A list:

    {"issues": [{"number": 12, "ready": false, "reasons": [...]}, ...],
     "not_ready": [12]}

`reasons` is a subset of `no_criteria`, `type_needs_review`,
`criteria_need_review`, in that order; empty when ready.

Exit codes
  0  judged
  2  usage error
  4  cannot complete — empty or unparsable stdin, or an issue without a `body`
     key (stderr: `⚠ gi-ready: <reason>`). Callers apply the prose rule.

Authored at src/shared/scripts/gi-ready.py — do not edit installed copies; edit
the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import json
import re
import sys

HEADING_RE = re.compile(r"^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$")
FENCE_RE = re.compile(r"^\s{0,3}(```|~~~)")
ITEM_RE = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s*)?(.*)$")
CODE_SPAN_RE = re.compile(r"`+[^`]*`+")
MARKER_RE = re.compile(r"\(needs review\)\s*$", re.IGNORECASE)


class CannotComplete(ValueError):
    """The input cannot be judged; the caller degrades to the prose rule."""


def _sections(body: str) -> list[tuple[str, list[str]]]:
    """Split a body into (heading, lines) pairs, skipping fences and quotes."""
    sections: list[tuple[str, list[str]]] = [("", [])]
    fenced = False
    for line in body.splitlines():
        if FENCE_RE.match(line):
            fenced = not fenced
            continue
        if fenced or line.lstrip().startswith(">"):
            continue
        heading = HEADING_RE.match(line)
        if heading:
            sections.append((heading.group(1).strip().rstrip(":").strip().lower(), []))
        else:
            sections[-1][1].append(CODE_SPAN_RE.sub("", line))
    return sections


def readiness(body: str) -> list[str]:
    """Return the reasons the body is not ready; an empty list means ready."""
    criteria: list[str] = []
    type_values: list[str] = []
    for heading, lines in _sections(body or ""):
        if heading == "acceptance criteria":
            for line in lines:
                item = ITEM_RE.match(line)
                if item and item.group(1).strip():
                    criteria.append(item.group(1))
        elif heading == "type":
            value = next((line for line in lines if line.strip()), "")
            type_values.append(value)
    reasons = []
    if not criteria:
        reasons.append("no_criteria")
    if any(MARKER_RE.search(value) for value in type_values):
        reasons.append("type_needs_review")
    if any(MARKER_RE.search(text) for text in criteria):
        reasons.append("criteria_need_review")
    return reasons


def judge(issue: object) -> dict[str, object]:
    if not isinstance(issue, dict) or "body" not in issue:
        raise CannotComplete("an issue has no 'body' field")
    body = issue["body"]
    if body is not None and not isinstance(body, str):
        raise CannotComplete("an issue 'body' is not a string")
    reasons = readiness(body or "")
    return {"number": issue.get("number"), "ready": not reasons, "reasons": reasons}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Judge issue readiness from JSON on stdin: Acceptance Criteria "
            "present, and no trailing (needs review) on Type or a criterion."
        )
    )
    parser.parse_args(argv)
    try:
        raw = sys.stdin.read()
        if not raw.strip():
            raise CannotComplete("stdin is empty")
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise CannotComplete(f"stdin is not JSON ({exc.msg})") from exc
        if isinstance(data, dict) and "issue" in data:
            result: dict[str, object] = judge(data["issue"])
        elif isinstance(data, dict) and isinstance(data.get("issues"), list):
            result = _judge_all(data["issues"])
        elif isinstance(data, list):
            result = _judge_all(data)
        else:
            result = judge(data)
    except CannotComplete as exc:
        sys.stderr.write(f"⚠ gi-ready: {exc}\n")
        return 4
    print(json.dumps(result, separators=(",", ":")))
    return 0


def _judge_all(issues: list[object]) -> dict[str, object]:
    judged = [judge(issue) for issue in issues]
    return {
        "issues": judged,
        "not_ready": [entry["number"] for entry in judged if not entry["ready"]],
    }


if __name__ == "__main__":
    sys.exit(main())
