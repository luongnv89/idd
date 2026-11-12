#!/usr/bin/env python3
"""Judge whether an issue is ready for an unattended resolve (issue #553).

The rule's prose home is *Issue Readiness* in the IDD methodology document;
this script is its deterministic form. An issue is **ready** when its body has an
`Acceptance Criteria` heading (any level, any case, an optional trailing colon)
with at least one list item under it — a sub-heading deeper than it stays inside
it — and neither the value under the `Type` heading nor any of those criteria
ends with the `(needs review)` marker. A marker ending any line of a criterion,
its wrapped continuation lines included, counts.

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

Plan coverage (issue #554) reuses the same parser. `--criteria` takes one issue
(an envelope or a bare object) and numbers its criteria in body order:

    {"number": 12, "criteria": [{"id": "AC1", "text": "..."}, ...]}

Only top-level items are numbered; an item indented to the content column of
the last top-level item is detail, not a criterion (readiness still reads every
item's marker).

`--coverage` takes `{"issue": {...}, "options": [{"number": 1,
"criteria_covered": ["AC1", ...]}, ...], "selected": 1, "criteria": [...]}` and
checks the selected option against those IDs (case-insensitive). An ID no
criterion carries is listed in `unknown` and never counts as covered. The
optional `criteria` is the `[{id, text}]` list the options' IDs were numbered
against; when it differs from this body's numbering (text compared ignoring
case, backticks, spacing and a trailing confidence marker) the verdict is
`renumbered`, because the IDs no longer name the same criteria:

    {"number": 12, "verdict": "gap", "selected": 1, "criteria": [...],
     "missing": [{"id": "AC2", "text": "..."}], "unknown": []}

`verdict` is `covered`, `gap` (some criterion is uncovered), `no_criteria`
(the body has none, so nothing can be mapped) or `renumbered`.

Exit codes
  0  judged (a `gap` is a verdict, not an error)
  2  usage error
  3  invalid plan (`--coverage` only) — `options` is not a non-empty list, an
     option lacks a `criteria_covered` list of strings or a unique integer
     `number`, or `selected` is not an integer naming an option. Fix the plan and re-run.
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

HEADING_RE = re.compile(r"^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$")
FENCE_RE = re.compile(r"^\s{0,3}(```|~~~)")
ITEM_RE = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s*)?(.*)$")
MARKER_COL_RE = re.compile(r"^(\s*)(?:[-*+]|\d+[.)])\s+")
CODE_SPAN_RE = re.compile(r"`+[^`]*`+")
MARKER_RE = re.compile(r"\(needs review\)\s*$", re.IGNORECASE)
CONFIDENCE_RE = re.compile(r"\((?:high confidence|needs review)\)\s*$", re.IGNORECASE)


class CannotComplete(ValueError):
    """The input cannot be judged; the caller degrades to the prose rule."""


class InvalidPlan(ValueError):
    """The plan handed to --coverage is malformed (exit 3)."""


def _sections(body: str) -> list[tuple[str, int, list[str]]]:
    """Split a body into (heading, level, lines), skipping fences and quotes."""
    sections: list[tuple[str, int, list[str]]] = [("", 0, [])]
    fenced = False
    for line in body.splitlines():
        if FENCE_RE.match(line):
            fenced = not fenced
            continue
        if fenced or line.lstrip().startswith(">"):
            continue
        heading = HEADING_RE.match(line)
        if heading:
            title = heading.group(2).strip().rstrip(":").strip().lower()
            sections.append((title, len(heading.group(1)), []))
        else:
            sections[-1][2].append(line)
    return sections


def _items(body: str) -> list[tuple[str, str, bool]]:
    """Each list item under an Acceptance Criteria heading, in body order, as
    (text with code spans dropped, display text, top level?). An item is found
    on the code-span-stripped line, as readiness always has. As in CommonMark,
    an item is nested only when it is indented to the content column of the
    last top-level item, so a nested detail is never its own criterion while a
    sibling indented 1-3 spaces (or a right-aligned number) still is, and an
    unindented paragraph after a blank line ends the list.

    A sub-heading strictly deeper than the Acceptance Criteria heading stays
    inside it, so its items are criteria too. A line that continues an item (a
    wrapped line, or a paragraph indented to its content column) joins that
    item's marker text as a line of its own: readiness reads a marker ending
    any of them, while the display text, and so the numbering, stays the
    first line."""
    found: list[tuple[str, str, bool]] = []
    level = 0  # the open Acceptance Criteria heading's level; 0 when none is open
    for heading, depth, lines in _sections(body or ""):
        if heading == "acceptance criteria":
            level = depth
        elif not (level and depth > level):
            level = 0
        if not level:
            continue
        content_col = None
        after_blank = False
        last = None  # index in `found` of the item a continuation line extends
        for line in lines:
            bare_line = CODE_SPAN_RE.sub("", line)
            item = ITEM_RE.match(bare_line)
            if not (item and item.group(1).strip()):
                indent = len(line.expandtabs(4)) - len(line.expandtabs(4).lstrip())
                if line.strip() and after_blank and not item and (
                        content_col is None or indent < content_col):
                    content_col = None  # a paragraph ends the list
                    last = None
                elif line.strip() and not item and last is not None:
                    bare, text, top = found[last]
                    found[last] = (f"{bare}\n{bare_line.strip()}", text, top)
                after_blank = not line.strip()
                continue
            after_blank = False
            raw = ITEM_RE.match(line)
            text = (raw.group(1) if raw else item.group(1)).strip()
            # The column is measured on the raw line: a stripped code span
            # would leave its spaces behind and push the column right.
            marker = (MARKER_COL_RE.match(line.expandtabs(4))
                      or MARKER_COL_RE.match(bare_line.expandtabs(4)))
            top = content_col is None or len(marker.group(1)) < content_col
            if top:
                content_col = marker.end()
            found.append((item.group(1), text, top))
            last = len(found) - 1
    return found


def criteria(body: str) -> list[str]:
    """The top-level criteria texts, in body order."""
    return [text for _, text, top in _items(body) if top]


def readiness(body: str) -> list[str]:
    """Return the reasons the body is not ready; an empty list means ready."""
    texts = [bare for bare, _, _ in _items(body)]
    type_values: list[str] = []
    for heading, _, lines in _sections(body or ""):
        if heading == "type":
            stripped = (CODE_SPAN_RE.sub("", line) for line in lines)
            type_values.append(next((line for line in stripped if line.strip()), ""))
    reasons = []
    if not texts:
        reasons.append("no_criteria")
    if any(MARKER_RE.search(value) for value in type_values):
        reasons.append("type_needs_review")
    if any(MARKER_RE.search(part) for text in texts for part in text.splitlines()):
        reasons.append("criteria_need_review")
    return reasons


def _body(issue: object) -> str:
    if not isinstance(issue, dict) or "body" not in issue:
        raise CannotComplete("an issue has no 'body' field")
    body = issue["body"]
    if body is not None and not isinstance(body, str):
        raise CannotComplete("an issue 'body' is not a string")
    return body or ""


def judge(issue: object) -> dict[str, object]:
    reasons = readiness(_body(issue))
    return {"number": issue.get("number"), "ready": not reasons, "reasons": reasons}


def numbered(issue: object) -> list[dict[str, str]]:
    """The issue's criteria as `[{id: "AC<k>", text}]`, 1-based in body order."""
    return [{"id": f"AC{k}", "text": text}
            for k, text in enumerate(criteria(_body(issue)), 1)]


def _ids(option: dict, where: str) -> list[str]:
    covered = option.get("criteria_covered")
    if not isinstance(covered, list) or not all(isinstance(i, str) for i in covered):
        raise InvalidPlan(f"{where} has no criteria_covered list of strings")
    return [i.strip().upper() for i in covered]


def _norm(text: object) -> str:
    """Compare criterion text loosely: case, backticks, spacing, confidence marker."""
    text = CONFIDENCE_RE.sub("", str(text).replace("`", ""))
    return " ".join(text.lower().split())


def _basis(entries: object) -> list[tuple[str, str]] | None:
    if not isinstance(entries, list) or not all(isinstance(e, dict) for e in entries):
        return None
    return [(str(e.get("id", "")).strip().upper(), _norm(e.get("text", ""))) for e in entries]


def coverage(data: object) -> dict[str, object]:
    """Check the selected option's criteria_covered against the issue's criteria."""
    if not isinstance(data, dict) or "issue" not in data:
        raise CannotComplete("--coverage needs {issue, options, selected}")
    listed = numbered(data["issue"])
    options = data.get("options")
    if not isinstance(options, list) or not options:
        raise InvalidPlan("options must be a non-empty list")
    by_number: dict[int, list[str]] = {}
    for k, option in enumerate(options):
        number = option.get("number") if isinstance(option, dict) else None
        if not isinstance(number, int) or isinstance(number, bool) or number in by_number:
            raise InvalidPlan(f"options[{k}] needs a unique integer number")
        by_number[number] = _ids(option, f"option {number}")
    selected = data.get("selected")
    if not isinstance(selected, int) or isinstance(selected, bool) or selected not in by_number:
        raise InvalidPlan("selected names no option")
    claimed = by_number[selected]
    known = {entry["id"] for entry in listed}
    missing = [entry for entry in listed if entry["id"] not in claimed]
    unknown = sorted({i for i in claimed if i not in known})
    verdict = "no_criteria" if not listed else ("gap" if missing else "covered")
    if "criteria" in data and _basis(data["criteria"]) != _basis(listed):
        verdict = "renumbered"
    return {"number": data["issue"].get("number"), "verdict": verdict,
            "selected": selected, "criteria": listed, "missing": missing,
            "unknown": unknown}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Judge issue readiness from JSON on stdin: Acceptance Criteria "
            "present, and no trailing (needs review) on Type or a criterion."
        )
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--criteria", action="store_true",
                      help="number one issue's criteria AC1..ACn")
    mode.add_argument("--coverage", action="store_true",
                      help="check a selected plan option's criteria_covered")
    args = parser.parse_args(argv)
    try:
        raw = sys.stdin.read()
        if not raw.strip():
            raise CannotComplete("stdin is empty")
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise CannotComplete(f"stdin is not JSON ({exc.msg})") from exc
        result: dict[str, object]
        if args.coverage:
            result = coverage(data)
        elif args.criteria:
            issue = data["issue"] if isinstance(data, dict) and "issue" in data else data
            result = {"number": issue.get("number") if isinstance(issue, dict) else None,
                      "criteria": numbered(issue)}
        elif isinstance(data, dict) and "issue" in data:
            result = judge(data["issue"])
        elif isinstance(data, dict) and isinstance(data.get("issues"), list):
            result = _judge_all(data["issues"])
        elif isinstance(data, list):
            result = _judge_all(data)
        else:
            result = judge(data)
    except InvalidPlan as exc:
        sys.stderr.write(f"✗ gi-ready: {exc}\n")
        return 3
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
