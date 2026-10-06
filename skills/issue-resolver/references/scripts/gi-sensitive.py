#!/usr/bin/env python3
"""Classify a planned change as sensitive, and adjudicate its gate (issue #518).

/issue-resolver's sensitive-change gate (Step 2, `rs-sensitive-gate`) runs on
every profile, so a one-line change to an auth check or a CI workflow cannot
slip through the light path just because it is small. This script holds the two
deterministic halves of that gate; the judgment in between — naming the
load-bearing assumptions, building probes from the codebase, challenging the
plan, writing rebuttals — stays with the agent.

--classify
  Reads one JSON object on stdin:

      {"labels": ["<issue label>", ...], "paths": ["<planned file>", ...]}

  and prints {"sensitive": true | false, "reasons": [{"source", "value",
  "class"}]}. Size never enters: one sensitive path or label is enough. Both
  keys are required (an empty list is fine); a missing key, or any other
  top-level key not starting with `_`, is exit 3 — a misspelled `paths` must
  never read as "no sensitive path".

    label            a label containing `security`, `cve` or `vulnerability`,
                     case-insensitive — the labels Step 0d already honours
    ci-workflow      .github/workflows/**, .github/actions/**,
                     .gitlab-ci.yml / .yaml, .circleci/**, Jenkinsfile,
                     azure-pipelines.yml, .travis.yml,
                     bitbucket-pipelines.yml, .drone.yml (each also .yaml)
    secrets          .env / .env.*, *.pem, *.key, *.p12, *.pfx, id_rsa*,
                     id_ed25519*, or a path word starting secret / credential
    auth             a path word starting: auth, login, logout, signin,
                     signon, passw, passwd, oauth, session, token, perm, acl,
                     rbac, sso, saml, jwt, crypt, csrf, otp, mfa, secur,
                     polic, guard, role

  Path words split on every non-alphanumeric character and on letter/digit
  boundaries, taken both with and without a camelCase split (AuthService →
  auth service authservice, LogIn → log in login, oauth2 → oauth 2), then
  match by prefix. That over-matches on purpose — `author`,
  `tokenizer`, `permalink`, `guardrail`, `policyholder` trigger
  too: the gate fails closed.
    access-policy    CODEOWNERS, SECURITY.md, .github/dependabot.yml / .yaml
    security-config  .gitissue.yml, .pre-commit-config.yaml, .gitleaks.toml,
                     or a file whose name contains `secscan`

--adjudicate
  Reads the gate's ledger on stdin:

      {"probes": [{"id", "assumption", "phase": "pre" | "post",
                   "command", "expect", "falsified_if",
                   "result": "held" | "falsified" | null}, ...],
       "replanned": false,
       "challenge": {"independent": true,
                     "blockers": [{"id", "claim",
                                   "disposition": "open" | "amended" | "rebutted",
                                   "rebuttal": {"reason", "citation"} | null,
                                   "rechallenge": "cleared" | "standing" | null},
                                  ...]}}

  and prints {"verdict": "proceed" | "replan" | "stop", "open_blockers",
  "falsified", "test_obligations", "problems"}. `probes` (a list) and
  `replanned` (a boolean) are required; `challenge` may be absent or null
  (recorded as a problem → stop), but when present it must carry a boolean
  `independent` and a `blockers` list, and every blocker a `disposition`. A
  missing key, or any other top-level key not starting with `_`, is exit 3.
  The rules:

    * At least one probe; each needs a non-empty assumption, command, expect
      and falsified_if — a probe that names no observation able to refute it
      is not falsifiable. A `pre` probe must have run (`result` set), and at
      least one must exist: a ledger of only unrun `post` probes has tested
      nothing. A `post` probe with no result is a Step 3 test obligation.
    * A falsified probe sends the plan back to option selection once
      (`replan`) whatever the challenge, blockers or problems say — the plan
      is dead, so nothing else about it needs closing. After a replan
      (`replanned: true`) a falsified probe is a `stop`.
    * The challenge must be recorded and `independent: true`.
    * A blocker closes only two ways: `amended` with `rechallenge: cleared`, or
      `rebutted` with a reason and a citation that checks out — `path:line`
      (or `path:line-line`) naming a file under the working directory that has
      that line, or `probe:<id>` naming a probe whose result is `held`.
      Anything else leaves it open.
    * Count, votes and confidence are never read: a single blocker raised by
      one challenger at any confidence stops the gate until it is closed.
    * Otherwise any open blocker or problem is a `stop`.

Exit codes
  0  answered — `proceed`, `replan` and `stop` are all answers. Read
     `verdict`, never the exit status. This script never exits 1.
  2  usage error.
  3  invalid input — stdin is not a JSON object of the documented shape
     (including a missing or unknown top-level key). Fix the record and
     re-run; never read this as "not sensitive" or "proceed".
  4  cannot complete — stdin unreadable.

Authored at src/shared/scripts/gi-sensitive.py — do not edit installed copies;
edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path, PurePosixPath

LABEL_WORDS = ("security", "cve", "vulnerability")
AUTH_STEMS = (
    "auth", "login", "logout", "signin", "signon", "passw", "passwd", "oauth",
    "session", "token", "perm", "acl", "rbac", "sso", "saml", "jwt", "crypt",
    "csrf", "otp", "mfa", "secur", "polic", "guard", "role",
)
SECRET_STEMS = ("secret", "credential")
SECRET_SUFFIXES = (".pem", ".key", ".p12", ".pfx")
CI_FILES = frozenset({
    ".gitlab-ci.yml", ".gitlab-ci.yaml", "Jenkinsfile", "azure-pipelines.yml", "azure-pipelines.yaml",
    ".travis.yml", ".travis.yaml", "bitbucket-pipelines.yml", "bitbucket-pipelines.yaml",
    ".drone.yml", ".drone.yaml",
})
CI_DIRS = (".github/workflows/", ".github/actions/")
POLICY_FILES = frozenset({"CODEOWNERS", "SECURITY.md"})
SECURITY_CONFIG_FILES = frozenset({".gitissue.yml", ".pre-commit-config.yaml", ".gitleaks.toml"})
CAMEL = re.compile(r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])")
DIGIT_EDGE = re.compile(r"(?<=[A-Za-z])(?=[0-9])|(?<=[0-9])(?=[A-Za-z])")
NON_WORD = re.compile(r"[^a-z0-9]+")
LINE_CITATION = re.compile(r"^(?P<path>[^\s:]+):(?P<start>[1-9][0-9]*)(?:-(?P<end>[1-9][0-9]*))?$")
PROBE_CITATION = re.compile(r"^probe:(?P<id>\S+)$")


def _words(text: str) -> list[str]:
    """Path words: split on punctuation and digit edges, both with and without
    the camelCase split — the union, so `AuthService` yields `auth` and
    `LogIn` / `PassWord` still yield `login` / `password`."""
    words: list[str] = []
    for variant in (CAMEL.sub(" ", text), text):
        spaced = DIGIT_EDGE.sub(" ", variant)
        words.extend(w for w in NON_WORD.split(spaced.lower()) if w)
    return words


def _stem_hit(words: list[str], stems: tuple[str, ...]) -> bool:
    return any(w.startswith(stems) for w in words)


class InvalidInput(ValueError):
    """stdin is not a record of the documented shape (exit 3)."""


def path_class(raw: str) -> str | None:
    """The sensitive class of one planned path, or None."""
    text = raw.strip().replace("\\", "/")
    while text.startswith("./"):
        text = text[2:]
    path = PurePosixPath(text)
    parts = path.parts
    name = path.name
    lower = text.lower()
    words = _words(text)
    if (
        any(lower.startswith(d) or f"/{d}" in lower for d in CI_DIRS)
        or (parts and parts[0] == ".circleci")
        or name in CI_FILES
    ):
        return "ci-workflow"
    if (
        name == ".env"
        or name.startswith(".env.")
        or name.lower().endswith(SECRET_SUFFIXES)
        or name.startswith(("id_rsa", "id_ed25519"))
        or _stem_hit(words, SECRET_STEMS)
    ):
        return "secrets"
    if name in POLICY_FILES or lower.endswith((".github/dependabot.yml", ".github/dependabot.yaml")):
        return "access-policy"
    if name in SECURITY_CONFIG_FILES or "secscan" in name.lower():
        return "security-config"
    if _stem_hit(words, AUTH_STEMS):
        return "auth"
    return None


def _require_keys(record: dict, required: tuple[str, ...], optional: tuple[str, ...] = ()) -> None:
    """Fail closed on a missing or unknown top-level key (`_`-prefixed keys pass)."""
    missing = [k for k in required if k not in record]
    if missing:
        raise InvalidInput(f"missing required key(s): {', '.join(missing)}")
    allowed = set(required) | set(optional)
    unknown = sorted(k for k in record if k not in allowed and not str(k).startswith("_"))
    if unknown:
        raise InvalidInput(f"unknown key(s): {', '.join(unknown)}")


def _string_list(record: dict, key: str) -> list[str]:
    value = record[key]
    if not isinstance(value, list) or not all(isinstance(v, str) for v in value):
        raise InvalidInput(f"`{key}` must be a list of strings")
    return value


def classify(record: object) -> dict:
    if not isinstance(record, dict):
        raise InvalidInput("stdin must be a JSON object")
    _require_keys(record, ("labels", "paths"))
    reasons = []
    for label in _string_list(record, "labels"):
        if any(word in label.lower() for word in LABEL_WORDS):
            reasons.append({"source": "label", "value": label, "class": "label"})
    for path in _string_list(record, "paths"):
        cls = path_class(path)
        if cls:
            reasons.append({"source": "path", "value": path, "class": cls})
    return {"sensitive": bool(reasons), "reasons": reasons}


def _text(entry: dict, key: str) -> str:
    value = entry.get(key)
    return value.strip() if isinstance(value, str) else ""


def citation_holds(citation: str, held_probes: set[str], root: Path) -> bool:
    """True when the citation names a held probe or a real line of a real file."""
    probe = PROBE_CITATION.match(citation)
    if probe:
        return probe.group("id") in held_probes
    line = LINE_CITATION.match(citation)
    if not line:
        return False
    rel = PurePosixPath(line.group("path"))
    if rel.is_absolute() or ".." in rel.parts:
        return False
    target = root / rel
    try:
        if target.is_symlink() or not target.is_file():
            return False
        count = len(target.read_bytes().splitlines())
    except OSError:
        return False
    last = int(line.group("end") or line.group("start"))
    return int(line.group("start")) <= last <= count


def adjudicate(ledger: object, root: Path) -> dict:
    if not isinstance(ledger, dict):
        raise InvalidInput("stdin must be a JSON object")
    _require_keys(ledger, ("probes", "replanned"), ("challenge",))
    probes = ledger["probes"]
    if not isinstance(probes, list) or not all(isinstance(p, dict) for p in probes):
        raise InvalidInput("`probes` must be a list of objects")
    if not isinstance(ledger["replanned"], bool):
        raise InvalidInput("`replanned` must be a boolean")
    challenge = ledger.get("challenge")
    blockers: list = []
    if challenge is not None:
        if not isinstance(challenge, dict):
            raise InvalidInput("`challenge` must be an object or null")
        missing = [k for k in ("independent", "blockers") if k not in challenge]
        if missing:
            raise InvalidInput(f"`challenge` is missing {', '.join(missing)}")
        if not isinstance(challenge["independent"], bool):
            raise InvalidInput("`challenge.independent` must be a boolean")
        blockers = challenge["blockers"]
        if not isinstance(blockers, list) or not all(isinstance(b, dict) for b in blockers):
            raise InvalidInput("`challenge.blockers` must be a list of objects")
        if not all("disposition" in b for b in blockers):
            raise InvalidInput("every blocker needs a `disposition`")

    problems: list[str] = []
    falsified: list[str] = []
    obligations: list[str] = []
    held: set[str] = set()
    if not probes:
        problems.append("no load-bearing probe recorded")
    for index, probe in enumerate(probes, 1):
        pid = _text(probe, "id") or f"#{index}"
        missing = [k for k in ("assumption", "command", "expect", "falsified_if") if not _text(probe, k)]
        if missing:
            problems.append(f"probe {pid} is not falsifiable: missing {', '.join(missing)}")
        phase = probe.get("phase")
        result = probe.get("result")
        if phase not in ("pre", "post"):
            problems.append(f"probe {pid}: phase must be pre or post")
        if result not in ("held", "falsified", None):
            problems.append(f"probe {pid}: result must be held, falsified or null")
        if result == "falsified":
            falsified.append(pid)
        elif result == "held" and not missing:
            held.add(pid)
        elif result is None and phase == "pre":
            problems.append(f"pre-change probe {pid} has not run")
        elif result is None and phase == "post":
            obligations.append(pid)

    if probes and not any(p.get("phase") == "pre" and p.get("result") in ("held", "falsified") for p in probes):
        problems.append("no pre-change probe has run")

    if challenge is None:
        problems.append("no independent challenge recorded")
    elif challenge.get("independent") is not True:
        problems.append("challenge was not independent")

    open_blockers: list[str] = []
    for index, blocker in enumerate(blockers, 1):
        bid = _text(blocker, "id") or f"#{index}"
        disposition = blocker.get("disposition")
        closed = False
        if disposition == "amended":
            closed = blocker.get("rechallenge") == "cleared"
        elif disposition == "rebutted":
            rebuttal = blocker.get("rebuttal")
            if isinstance(rebuttal, dict) and _text(rebuttal, "reason"):
                closed = citation_holds(_text(rebuttal, "citation"), held, root)
        if not closed:
            open_blockers.append(bid)

    if falsified:
        # A falsified probe kills the plan: replan once, whatever else is open.
        verdict = "stop" if ledger["replanned"] else "replan"
    elif problems or open_blockers:
        verdict = "stop"
    else:
        verdict = "proceed"
    return {
        "verdict": verdict,
        "open_blockers": open_blockers,
        "falsified": falsified,
        "test_obligations": obligations,
        "problems": problems,
    }


def read_stdin() -> object:
    buffer = getattr(sys.stdin, "buffer", None)
    raw = buffer.read() if buffer is not None else sys.stdin.read().encode()
    try:
        return json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as exc:
        raise InvalidInput(f"stdin is not UTF-8 JSON: {exc}") from exc


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-sensitive.py",
        description=(
            "Classify a planned change as sensitive (--classify) or adjudicate "
            "the sensitive-change gate's probe/challenge ledger (--adjudicate). "
            "One JSON object on stdin, one JSON line on stdout."
        ),
        epilog=(
            "Examples: printf '%s' \"$sensitive_json\" | python3 gi-sensitive.py --classify ; "
            "printf '%s' \"$gate_ledger\" | python3 gi-sensitive.py --adjudicate"
        ),
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--classify", action="store_true",
                      help="labels + planned paths on stdin → {sensitive, reasons}")
    mode.add_argument("--adjudicate", action="store_true",
                      help="gate ledger on stdin → {verdict, open_blockers, …}")
    args = parser.parse_args(argv)
    try:
        record = read_stdin()
        result = classify(record) if args.classify else adjudicate(record, Path.cwd())
    except InvalidInput as exc:
        print(f"✗ gi-sensitive: {exc}", file=sys.stderr)
        return 3
    except OSError as exc:
        print(f"⚠ gi-sensitive: {exc}", file=sys.stderr)
        return 4
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
