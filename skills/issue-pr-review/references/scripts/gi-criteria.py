#!/usr/bin/env python3
"""Hold a criterion `pass` to reproducible evidence (issue #555).

/issue-pr-review judges each acceptance criterion in an isolated agent,
the criteria judge, that sees the issue and the diff only. This
script is the single home of the rule applied to what that agent returns: a
`pass` stands only on evidence someone can re-run at the PR head. Anything else
is downgraded to `unverified`, which the *Merge floor* treats as unmet.

Reads one JSON object on stdin:

    {"head": "<40-hex PR head SHA>",
     "criteria": ["<criterion text from the issue>", ...],
     "deferred": [<1-based criterion number>, ...],
     "verdicts": <the judge's JSON, verbatim>}

`head`, `criteria` and `deferred` come from the orchestrator; `deferred` lists
the rows a valid `Refs #N` PR body defers (`[]` otherwise). All four keys are
required. A missing key, any other top-level key not starting with `_`, a
`head` that is not 40 lowercase hex, criteria that are not strings, or a
deferred number out of range is exit 3: the orchestrator built a bad record.

`verdicts` is agent output, so it is never trusted to be well formed. It is
`{"criteria": [row, ...]}` or a bare list of rows, each row
`{"n": <1-based>, "status": "pass" | "fail" | "unverified", "evidence": {...}}`.
A pass keeps its status only with one of:

    {"kind": "test", "name": "<test name>", "exit": 0, "sha": "<head>"}
    {"kind": "command", "command": "<cmd>", "output": "<observed output>",
     "sha": "<head>"}

Every other pass is downgraded to `unverified`: a description, a file path, a
test that did not exit 0, an empty output, or a SHA other than `head` (a
verdict for an older commit is stale). A `fail` or `unverified` row keeps its
status. A criterion with no row, a duplicated row, an unknown status or
unreadable `verdicts` is `unverified` — this script never stops on agent
output and never turns a row into `pass`.

Prints {"head", "rows": [{"n", "criterion", "status", "evidence",
"downgraded"}], "counts": {"pass", "fail", "unverified", "deferred"},
"downgraded": <int>, "problems": [...]}. Deferred rows report status
`deferred` and count only under `deferred`.

Exit codes
  0  answered — read `rows` and `counts`. This script never exits 1.
  2  usage error.
  3  invalid input — the orchestrator's part of the record is malformed. Fix
     it and re-run; never read this as a verdict.
  4  cannot complete — stdin unreadable.

Authored at src/shared/scripts/gi-criteria.py — do not edit installed copies;
edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import json
import re
import sys


class InvalidInput(ValueError):
    """The orchestrator's part of the record is malformed (exit 3)."""


REQUIRED_KEYS = ("head", "criteria", "deferred", "verdicts")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
STATUSES = ("pass", "fail", "unverified")


def _text(entry: dict, key: str) -> str:
    value = entry.get(key)
    return value.strip() if isinstance(value, str) else ""


def _int(value: object) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) else None


def evidence_gap(evidence: object, head: str) -> str | None:
    """None when the evidence can be re-run at head, else why it cannot."""
    if not isinstance(evidence, dict):
        return "no test or command evidence"
    kind = evidence.get("kind")
    if kind == "test":
        if not _text(evidence, "name"):
            return "test evidence names no test"
        if _int(evidence.get("exit")) != 0:
            return "test did not run green (exit is not 0)"
    elif kind == "command":
        if not _text(evidence, "command"):
            return "command evidence names no command"
        if not _text(evidence, "output"):
            return "command evidence has no observed output"
    else:
        return "evidence is not a test or a command"
    sha = _text(evidence, "sha")
    if sha != head:
        return f"evidence ran at {sha[:7] or 'no SHA'}, not head {head[:7]}"
    return None


def render(evidence: object) -> str:
    """One table-cell line for the evidence, whatever its kind."""
    if not isinstance(evidence, dict):
        return str(evidence).strip() if evidence else "none given"
    kind = evidence.get("kind")
    if kind == "test":
        return f"test `{_text(evidence, 'name')}` green @ {_text(evidence, 'sha')[:7]}"
    if kind == "command":
        lines = [ln.strip() for ln in _text(evidence, "output").splitlines() if ln.strip()]
        first = lines[0][:80] if lines else ""
        return f"`{_text(evidence, 'command')}` → {first}"
    return _text(evidence, "text") or "none given"


def _rows(verdicts: object) -> list | None:
    if isinstance(verdicts, dict):
        verdicts = verdicts.get("criteria")
    return verdicts if isinstance(verdicts, list) else None


def decide(record: object) -> dict:
    if not isinstance(record, dict):
        raise InvalidInput("stdin must be a JSON object")
    missing = [k for k in REQUIRED_KEYS if k not in record]
    if missing:
        raise InvalidInput(f"missing required key(s): {', '.join(missing)}")
    unknown = sorted(k for k in record if k not in REQUIRED_KEYS and not str(k).startswith("_"))
    if unknown:
        raise InvalidInput(f"unknown key(s): {', '.join(unknown)}")
    head = record["head"]
    if not isinstance(head, str) or not SHA_RE.match(head):
        raise InvalidInput("`head` must be a 40-character lowercase hex SHA")
    criteria = record["criteria"]
    if not isinstance(criteria, list) or not all(isinstance(c, str) for c in criteria):
        raise InvalidInput("`criteria` must be a list of strings")
    deferred = record["deferred"]
    if not isinstance(deferred, list) or not all(
        _int(n) is not None and 1 <= n <= len(criteria) for n in deferred
    ):
        raise InvalidInput("`deferred` must list criterion numbers from 1 to len(criteria)")

    problems: list[str] = []
    by_n: dict[int, list[dict]] = {}
    raw = _rows(record["verdicts"])
    if raw is None:
        problems.append("judge output unreadable — every criterion is unverified")
        raw = []
    for row in raw:
        n = _int(row.get("n")) if isinstance(row, dict) else None
        if n is None or not 1 <= n <= len(criteria):
            problems.append(f"ignored a row with no valid criterion number: {json.dumps(row)[:80]}")
            continue
        by_n.setdefault(n, []).append(row)

    rows: list[dict] = []
    counts = {"pass": 0, "fail": 0, "unverified": 0, "deferred": 0}
    downgraded = 0
    for n, criterion in enumerate(criteria, start=1):
        found = by_n.get(n, [])
        out = {"n": n, "criterion": criterion, "downgraded": False}
        if n in deferred:
            out.update(status="deferred", evidence="deferred")
        elif len(found) != 1:
            why = "no verdict from the judge" if not found else "conflicting verdicts from the judge"
            problems.append(f"criterion {n}: {why}")
            out.update(status="unverified", evidence=why)
        else:
            row = found[0]
            status = row.get("status")
            evidence = row.get("evidence")
            if status not in STATUSES:
                problems.append(f"criterion {n}: unknown status {status!r}")
                out.update(status="unverified", evidence=f"unknown status {status!r}")
            elif status == "pass" and (gap := evidence_gap(evidence, head)):
                downgraded += 1
                out.update(status="unverified", evidence=f"downgraded from pass: {gap}",
                           downgraded=True)
            else:
                out.update(status=status, evidence=render(evidence))
        counts[out["status"]] += 1
        rows.append(out)
    return {"head": head, "rows": rows, "counts": counts,
            "downgraded": downgraded, "problems": problems}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-criteria.py",
        description=(
            "Read the criteria judge's verdicts on stdin; keep a pass only when "
            "a named test exited 0 at head or a command's observed output is "
            "recorded at head, else downgrade it to unverified."
        ),
        epilog="Example: printf '%s' \"$criteria_json\" | python3 gi-criteria.py",
    )
    parser.parse_args(argv)
    try:
        buffer = getattr(sys.stdin, "buffer", None)
        raw = buffer.read() if buffer is not None else sys.stdin.read().encode()
        try:
            record = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, ValueError) as exc:
            raise InvalidInput(f"stdin is not UTF-8 JSON: {exc}") from exc
        result = decide(record)
    except InvalidInput as exc:
        print(f"✗ gi-criteria: {exc}", file=sys.stderr)
        return 3
    except OSError as exc:
        print(f"⚠ gi-criteria: {exc}", file=sys.stderr)
        return 4
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
