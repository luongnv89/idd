#!/usr/bin/env python3
"""Decide whether a premise reset blocks the next QA fix (issue #519).

/issue-resolver's Step 4 stagnation stop compares literal findings across two
consecutive cycles, so a fixer that keeps acting on the same wrong hypothesis —
rewording the symptom each time — never trips it. The premise-reset gate
(`rs-premise-reset`) compares *premises* instead: the one-line root-cause
hypothesis each fix acted on. This script holds the deterministic half. The
judgment — whether two premises are the same hypothesis, however worded — is
the orchestrator's, and it arrives here as a `premise_id`: the same id means
the same premise. Premise text is never compared, because comparing wording is
exactly the weakness this gate exists to close.

Reads one JSON ledger on stdin:

    {"failures": [{"cycle": <int>, "premise_id": "<id>", "premise": "<text>"},
                  ...],
     "revisions": [{"resets": "<premise_id>", "after_cycle": <int>,
                    "premise_id": "<new id>", "premise": "<text>",
                    "supports": "<why the diagnostics support it>",
                    "diagnostics": [{"command": "<str>",
                                     "recorded": {"exit": <int>,
                                                  "excerpt": "<str>"},
                                     "rerun": {"exit": <int>,
                                               "output": "<str>"}}, ...]},
                   ...]}

A failure is a cycle whose fix was applied and whose next review or test still
failed on a finding that fix targeted. Failures need not be consecutive.

Both `failures` and `revisions` are required lists — `[]` when there are none.
A missing key, or any other top-level key not starting with `_`, is exit 3: a
misspelled `failures` must never read as "nothing failed".

Prints {"blocked": true | false, "blocking_premises": [...],
"accepted_revisions": [...], "problems": [...]}:

  * A premise_id carried by two or more failures is a shared premise. It
    blocks the next fix until an accepted revision resets it.
  * A revision is accepted only when it names that shared premise in `resets`,
    is recorded at or after the premise's latest failure (`after_cycle`),
    carries a premise_id no failure up to that cycle used, a non-empty premise and
    `supports`, and at least one diagnostic — and every diagnostic reran
    clean: the same exit status, and the recorded excerpt found in the rerun
    output (whitespace-normalised). One mismatched rerun rejects it.
  * A later failure under a reset premise blocks again: the revision covered
    only the failures before it.

Exit codes
  0  answered — `blocked` true or false. Read `blocked`, never the exit
     status. This script never exits 1.
  2  usage error.
  3  invalid input — stdin is not a ledger of the documented shape
     (including a missing or unknown top-level key). Fix the ledger and
     re-run; never read this as "not blocked".
  4  cannot complete — stdin unreadable.

Authored at src/shared/scripts/gi-premise.py — do not edit installed copies;
edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import json
import sys


class InvalidInput(ValueError):
    """stdin is not a ledger of the documented shape (exit 3)."""


REQUIRED_KEYS = ("failures", "revisions")


def _objects(ledger: dict, key: str) -> list[dict]:
    value = ledger[key]
    if not isinstance(value, list) or not all(isinstance(v, dict) for v in value):
        raise InvalidInput(f"`{key}` must be a list of objects")
    return value


def _text(entry: dict, key: str) -> str:
    value = entry.get(key)
    return value.strip() if isinstance(value, str) else ""


def _int(entry: dict, key: str) -> int | None:
    value = entry.get(key)
    return value if isinstance(value, int) and not isinstance(value, bool) else None


def _squash(text: str) -> str:
    return " ".join(text.split())


def rerun_matches(diagnostic: dict) -> bool:
    recorded = diagnostic.get("recorded")
    rerun = diagnostic.get("rerun")
    if not _text(diagnostic, "command") or not isinstance(recorded, dict) or not isinstance(rerun, dict):
        return False
    excerpt = _squash(_text(recorded, "excerpt"))
    output = rerun.get("output")
    if _int(recorded, "exit") is None or _int(rerun, "exit") is None or not excerpt:
        return False
    if not isinstance(output, str):
        return False
    return recorded["exit"] == rerun["exit"] and excerpt in _squash(output)


def decide(ledger: object) -> dict:
    if not isinstance(ledger, dict):
        raise InvalidInput("stdin must be a JSON object")
    missing = [k for k in REQUIRED_KEYS if k not in ledger]
    if missing:
        raise InvalidInput(f"missing required key(s): {', '.join(missing)}")
    unknown = sorted(k for k in ledger if k not in REQUIRED_KEYS and not str(k).startswith("_"))
    if unknown:
        raise InvalidInput(f"unknown key(s): {', '.join(unknown)}")
    failures = _objects(ledger, "failures")
    revisions = _objects(ledger, "revisions")

    latest: dict[str, int] = {}
    counts: dict[str, int] = {}
    seen: list[tuple[int, str]] = []
    for failure in failures:
        pid = _text(failure, "premise_id")
        cycle = _int(failure, "cycle")
        if not pid or cycle is None:
            raise InvalidInput("each failure needs a premise_id and an integer cycle")
        counts[pid] = counts.get(pid, 0) + 1
        latest[pid] = max(latest.get(pid, cycle), cycle)
        seen.append((cycle, pid))
    shared = sorted(pid for pid, n in counts.items() if n >= 2)

    problems: list[str] = []
    accepted: list[str] = []
    reset: set[str] = set()
    for revision in revisions:
        target = _text(revision, "resets")
        new_id = _text(revision, "premise_id")
        label = new_id or "(unnamed revision)"
        after = _int(revision, "after_cycle")
        diagnostics = revision.get("diagnostics")
        why = []
        if target not in shared:
            why.append(f"resets `{target}`, which is not a shared premise")
        elif after is None or after < latest[target]:
            why.append(f"predates the latest failure under `{target}`")
        failed_before = {pid for cycle, pid in seen if after is None or cycle <= after}
        if not new_id or new_id in failed_before:
            why.append("its premise_id is not new — a revised premise must differ from every failed one")
        if not _text(revision, "premise") or not _text(revision, "supports"):
            why.append("missing premise or supports")
        if not isinstance(diagnostics, list) or not diagnostics:
            why.append("no rerunnable diagnostic")
        elif not all(isinstance(d, dict) and rerun_matches(d) for d in diagnostics):
            why.append("a diagnostic did not rerun to its recorded result")
        if why:
            problems.append(f"revision {label} rejected: {'; '.join(why)}")
        else:
            accepted.append(new_id)
            reset.add(target)

    still_blocked = [pid for pid in shared if pid not in reset]
    return {
        "blocked": bool(still_blocked),
        "blocking_premises": still_blocked,
        "accepted_revisions": accepted,
        "problems": problems,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-premise.py",
        description=(
            "Read the QA premise ledger on stdin; print whether a premise reset "
            "blocks the next fix (two failures sharing a premise_id, not yet "
            "reset by a revision whose diagnostics reran to their recorded result)."
        ),
        epilog="Example: printf '%s' \"$premise_ledger\" | python3 gi-premise.py",
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
        print(f"✗ gi-premise: {exc}", file=sys.stderr)
        return 3
    except OSError as exc:
        print(f"⚠ gi-premise: {exc}", file=sys.stderr)
        return 4
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
