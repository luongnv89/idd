#!/usr/bin/env python3
"""Adjudicate caller-first design sketches before a plan is selected (issue #520).

/issue-resolver's Step 2 design-sketch check (`rs-design-sketch`) makes the
synthesizer's options differ in *structure*, not only in scope, when a change
introduces or reshapes a domain type, state or transition. Each option carries
a sketch: its types plus caller code — callers making valid transitions, and
callers attempting invalid ones. The orchestrator runs the repository's own
static checker over every caller (check-only, never executing the sketch) and
records each exit status. This script holds the deterministic half: whether
the designs are structurally distinct, which of them reject every invalid
transition, and which option the plan should select.

Reads one JSON ledger on stdin:

    {"recommended": <option number>,
     "options": [{"number": <int>,
                  "shape": "<one-line structural label>",
                  "types": "<the sketch's type declarations>",
                  "callers": [{"id": "<id>",
                               "kind": "valid" | "invalid",
                               "transition": "<from -> to>",
                               "check": {"exit": <int> | null,
                                         "excerpt": "<checker diagnostic>"}},
                              ...]},
                 ...]}

Both `recommended` (an integer naming one option) and `options` (a list of
objects, each with a unique integer `number`) are required. A missing key, a
duplicate or missing option number, a `recommended` naming no option, or any
other top-level key not starting with `_` is exit 3: a misspelled `options`
must never read as "nothing to check".

Prints {"verdict": "proceed" | "switch" | "unproven", "selected": <number>,
"distinct": true | false, "indistinct": [[a, b], ...],
"options": [{"number", "status", "rejected", "accepted_invalid",
"failed_valid"}], "problems": [...]}:

  * An option's status is `fail` when its checker accepted an invalid
    transition (`exit` 0 on an `invalid` caller — the design lets the bad
    state through) or rejected a valid one (non-zero `exit` on a `valid`
    caller — the design cannot express the intended use). Otherwise it is
    `unchecked` when it has no `shape`, no `types`, no valid caller, no
    invalid caller, a caller of unknown `kind`, a caller whose check did not
    run (`exit` not an integer — a timeout records null), or an invalid
    caller rejected without a diagnostic `excerpt`. Otherwise `pass`: every
    valid caller type-checked and every invalid transition was rejected.
  * Two sketched options are indistinct when their `shape` labels match
    (case and whitespace folded) or their `types` match (whitespace folded):
    scope variants of one design are not a comparison. `distinct` needs at
    least two sketched options and no indistinct pair.
  * `selected` is the recommended option when it passes, else the
    lowest-numbered option that passes, else the recommended option.
  * `verdict` is `proceed` when the designs are distinct and the recommended
    option passes; `switch` when they are distinct and the recommended option
    did not pass but another did — select that one instead; `unproven`
    otherwise (still select `selected`, which differs from the
    recommendation only when another design passed, and mark the plan
    `(needs review)`). No verdict stops the run.

Exit codes
  0  answered — read `verdict`, never the exit status. This script never
     exits 1.
  2  usage error.
  3  invalid input — stdin is not a ledger of the documented shape. Fix the
     ledger and re-run; never read this as `proceed`.
  4  cannot complete — stdin unreadable.

Authored at src/shared/scripts/gi-sketch.py — do not edit installed copies;
edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import json
import sys


class InvalidInput(ValueError):
    """stdin is not a ledger of the documented shape (exit 3)."""


REQUIRED_KEYS = ("recommended", "options")


def _int(value: object) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) else None


def _text(entry: dict, key: str) -> str:
    value = entry.get(key)
    return value.strip() if isinstance(value, str) else ""


def _fold(text: str) -> str:
    return " ".join(text.split())


def judge(option: dict) -> dict:
    number = option["number"]
    callers = option.get("callers")
    gaps: list[str] = []
    rejected: list[str] = []
    accepted_invalid: list[str] = []
    failed_valid: list[str] = []
    if not _text(option, "shape") or not _text(option, "types"):
        gaps.append("no shape or types")
    if not isinstance(callers, list) or not all(isinstance(c, dict) for c in callers):
        gaps.append("callers must be a list of objects")
        callers = []
    kinds = {_text(c, "kind") for c in callers}
    if "valid" not in kinds or "invalid" not in kinds:
        gaps.append("needs at least one valid and one invalid caller")
    for caller in callers:
        label = _text(caller, "id") or _text(caller, "transition") or "(unnamed caller)"
        kind = _text(caller, "kind")
        check = caller.get("check")
        status = _int(check.get("exit")) if isinstance(check, dict) else None
        if kind not in ("valid", "invalid"):
            gaps.append(f"caller {label} has unknown kind `{kind}`")
        elif status is None:
            gaps.append(f"caller {label} was not checked")
        elif kind == "valid" and status != 0:
            failed_valid.append(label)
        elif kind == "invalid" and status == 0:
            accepted_invalid.append(label)
        elif kind == "invalid" and not _text(check, "excerpt"):
            gaps.append(f"caller {label} was rejected without a diagnostic excerpt")
        elif kind == "invalid":
            rejected.append(label)
    if accepted_invalid or failed_valid:
        status_word = "fail"
    elif gaps:
        status_word = "unchecked"
    else:
        status_word = "pass"
    problems = [f"option {number}: {gap}" for gap in gaps]
    problems += [f"option {number}: accepts invalid transition {c}" for c in accepted_invalid]
    problems += [f"option {number}: rejects valid caller {c}" for c in failed_valid]
    return {
        "number": number,
        "status": status_word,
        "rejected": rejected,
        "accepted_invalid": accepted_invalid,
        "failed_valid": failed_valid,
        "_problems": problems,
    }


def decide(ledger: object) -> dict:
    if not isinstance(ledger, dict):
        raise InvalidInput("stdin must be a JSON object")
    missing = [k for k in REQUIRED_KEYS if k not in ledger]
    if missing:
        raise InvalidInput(f"missing required key(s): {', '.join(missing)}")
    unknown = sorted(k for k in ledger if k not in REQUIRED_KEYS and not str(k).startswith("_"))
    if unknown:
        raise InvalidInput(f"unknown key(s): {', '.join(unknown)}")
    options = ledger["options"]
    if not isinstance(options, list) or not options or not all(isinstance(o, dict) for o in options):
        raise InvalidInput("`options` must be a non-empty list of objects")
    numbers = [_int(o.get("number")) for o in options]
    if any(n is None for n in numbers) or len(set(numbers)) != len(numbers):
        raise InvalidInput("every option needs a unique integer `number`")
    recommended = _int(ledger["recommended"])
    if recommended not in numbers:
        raise InvalidInput("`recommended` must name one of the options")

    judged = sorted((judge(o) for o in options), key=lambda j: j["number"])
    problems = [p for j in judged for p in j.pop("_problems")]

    sketched = sorted(
        (o for o in options if _text(o, "shape") and _text(o, "types")),
        key=lambda o: o["number"],
    )
    indistinct = []
    for i, left in enumerate(sketched):
        for right in sketched[i + 1:]:
            same_shape = _fold(_text(left, "shape")).casefold() == _fold(_text(right, "shape")).casefold()
            same_types = _fold(_text(left, "types")) == _fold(_text(right, "types"))
            if same_shape or same_types:
                indistinct.append([left["number"], right["number"]])
    distinct = len(sketched) >= 2 and not indistinct
    if len(sketched) < 2:
        problems.append("fewer than two sketched designs — nothing was compared")
    for a, b in indistinct:
        problems.append(f"options {a} and {b} share one design (same shape or types)")

    passing = [j["number"] for j in judged if j["status"] == "pass"]
    if recommended in passing:
        selected = recommended
    elif passing:
        selected = passing[0]
    else:
        selected = recommended
        problems.append("no design rejects every invalid transition")

    if distinct and selected in passing:
        verdict = "proceed" if selected == recommended else "switch"
    else:
        verdict = "unproven"
    return {
        "verdict": verdict,
        "selected": selected,
        "distinct": distinct,
        "indistinct": indistinct,
        "options": judged,
        "problems": problems,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-sketch.py",
        description=(
            "Read the design-sketch ledger on stdin; print whether the options' "
            "designs are structurally distinct, which reject every invalid "
            "transition under the repo's static checker, and which to select."
        ),
        epilog="Example: printf '%s' \"$sketch_ledger\" | python3 gi-sketch.py",
    )
    parser.parse_args(argv)
    try:
        buffer = getattr(sys.stdin, "buffer", None)
        raw = buffer.read() if buffer is not None else sys.stdin.read().encode()
        try:
            ledger = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, ValueError) as exc:
            raise InvalidInput(f"stdin is not UTF-8 JSON: {exc}") from exc
        result = decide(ledger)
    except InvalidInput as exc:
        print(f"✗ gi-sketch: {exc}", file=sys.stderr)
        return 3
    except OSError as exc:
        print(f"⚠ gi-sketch: {exc}", file=sys.stderr)
        return 4
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
