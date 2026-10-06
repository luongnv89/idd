#!/usr/bin/env python3
"""Write or verify a revision receipt for a QA-handed-off commit (issue #515).

/issue-resolver ends a clean QA loop by writing a `<!-- gitissue:qa v1 … -->`
marker into its PR body, and /issue-pr-review uses that marker to skip work the
resolver already did. A PR body is written by whoever opened the PR, and the
head SHA it binds to is public, so the marker alone authenticates nothing: a
forged marker plus any unrelated green CI check would skip QA on a commit no
suite ever ran on.

A revision receipt is the evidence the marker cannot carry. The resolver writes
one, with this script, for the exact commit it is about to push; the reviewer
trusts the marker only when a receipt for the PR's live head verifies here.

The store
  `<git common dir>/idd/receipts/<sha40>.json` — inside `.git`, so no branch can
  commit into it and no PR body can reach it, and in the *common* dir, so every
  worktree of one clone (auto-pilot's parallel lanes) shares one store.
  Directory mode 0700, files 0600, written atomically (temp file + rename).

  This is bookkeeping against the PR author's write surface (the PR body, the
  branch's contents, its CI checks), not cryptographic authentication: any code
  already executing on this host as this user can write the store too. A review
  on a different machine finds no receipt and runs its full pipeline.

--write (resolver)
  Reads one JSON record on stdin:

      {"tool": "issue-resolver", "profile": "light" | "full",
       "cycles": <int >= 0>, "review": "clean",
       "tests": {"count": <int >= 0>, "sha": "<sha40>", "command": "<str>"}
                | null,                                  (optional)
       "ui": "<the marker's ui= value>" | null,          (optional)
       "artifacts": ["<path>", ...]}                     (optional)

  and adds what it measures itself, never what the caller claims:
    sha         `git rev-parse HEAD` — the receipt is for the current commit
    clean_tree  `git status --porcelain=v1 --untracked-files=all` must be empty;
                a dirty tree is refused (exit 4), never recorded as dirty
    executor    {"user", "uid", "host"} of the process writing it
    artifacts   [{"path", "sha256", "bytes"}] digested from each named file
    written_at  UTC timestamp
  `tests.sha` must be HEAD or an ancestor of it: evidence from another history
  is not evidence about this commit. Prints {"written": true, "sha", "path"}.

--verify SHA40 (reviewer)
  Prints {"verified": true | false, "reason", "sha", "path", "profile",
  "tests", "ui", "receipt"}. `tests` is the receipt's "<count>@<sha40>" (null
  when the resolver recorded no suite); `profile` and `ui` are the recorded
  values. A caller compares each with the marker's `profile=`, `tests=` and
  `ui=` as strings, so a real receipt never backs a field it did not record. `verified` is true only when the file is a regular
  file (not a symlink) that parses, carries schema 1, names this SHA, records
  a clean tree and `review: clean`, was written by this user on this host, and
  every artifact that still exists still has its recorded digest. Anything
  else is `verified: false` with a reason, and a caller reads that as "no
  receipt".

Exit codes
  0  answered — including `verified: false`, which is an answer, not an error.
     Read `verified`, never the exit status. This script never exits 1.
  2  usage error
  3  invalid input — a SHA that is not 40 lowercase hex, or (--write) a record
     that is not the shape above. Nothing was written. Stop and fix the input.
  4  cannot complete — not a git work tree, git missing, a dirty tree, an I/O
     failure. Nothing was written. Degrade: the resolver ships without a
     receipt and the reviewer treats the marker as `stale`.

Authored at src/shared/scripts/gi-receipt.py — do not edit installed copies; edit
the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import getpass
import hashlib
import json
import os
import re
import socket
import stat
import subprocess
import sys
import tempfile

SCHEMA = 1
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
PROFILES = ("light", "full")


class InvalidInput(Exception):
    """Exit 3."""


class CannotComplete(Exception):
    """Exit 4."""


def _git(*args: str) -> str:
    try:
        proc = subprocess.run(
            ["git", *args], capture_output=True, text=True, check=False
        )
    except OSError as exc:  # git not installed
        raise CannotComplete(f"git unavailable: {exc}") from exc
    if proc.returncode != 0:
        raise CannotComplete(
            f"git {' '.join(args)} failed: {proc.stderr.strip() or proc.returncode}"
        )
    return proc.stdout


def store_dir() -> str:
    """Absolute `<git common dir>/idd/receipts`, shared by every worktree."""
    raw = _git("rev-parse", "--git-common-dir").strip()
    if not raw:
        raise CannotComplete("no git common dir")
    return os.path.join(os.path.abspath(raw), "idd", "receipts")


def executor() -> dict:
    uid = os.getuid() if hasattr(os, "getuid") else None
    try:
        user = getpass.getuser()
    except Exception:  # noqa: BLE001 — no login name in this environment
        user = None
    return {"user": user, "uid": uid, "host": socket.gethostname()}


def _digest(path: str) -> dict:
    h = hashlib.sha256()
    size = 0
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
            size += len(chunk)
    return {"path": os.path.abspath(path), "sha256": h.hexdigest(), "bytes": size}


def _is_count(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def validate_record(record) -> dict:
    """Check the caller's stdin record; return the fields the receipt keeps."""
    if not isinstance(record, dict):
        raise InvalidInput("record must be a JSON object")
    tool = record.get("tool")
    if not isinstance(tool, str) or not tool.strip():
        raise InvalidInput("tool must be a non-empty string")
    if record.get("profile") not in PROFILES:
        raise InvalidInput("profile must be 'light' or 'full'")
    if not _is_count(record.get("cycles")):
        raise InvalidInput("cycles must be an integer >= 0")
    if record.get("review") != "clean":
        raise InvalidInput("review must be 'clean' — a receipt records a clean QA exit only")
    tests = record.get("tests")
    if tests is not None:
        if not isinstance(tests, dict):
            raise InvalidInput("tests must be an object or null")
        if not _is_count(tests.get("count")):
            raise InvalidInput("tests.count must be an integer >= 0")
        if not isinstance(tests.get("sha"), str) or not SHA_RE.match(tests["sha"]):
            raise InvalidInput("tests.sha must be 40 lowercase hex characters")
        command = tests.get("command")
        if not isinstance(command, str) or not command.strip():
            raise InvalidInput("tests.command must be a non-empty string")
        tests = {"count": tests["count"], "sha": tests["sha"], "command": command}
    ui = record.get("ui")
    if ui is not None and (not isinstance(ui, str) or not ui.strip() or any(c.isspace() for c in ui)):
        raise InvalidInput("ui must be the marker's ui= value (no spaces) or null")
    artifacts = record.get("artifacts", [])
    if not isinstance(artifacts, list) or not all(
        isinstance(a, str) and a for a in artifacts
    ):
        raise InvalidInput("artifacts must be a list of file paths")
    for path in artifacts:
        if not os.path.isfile(path):
            raise InvalidInput(f"artifact is not a readable file: {path}")
    return {
        "tool": tool,
        "profile": record["profile"],
        "cycles": record["cycles"],
        "review": "clean",
        "tests": tests,
        "ui": ui,
        "artifacts": artifacts,
    }


def write(stdin_text: str) -> dict:
    try:
        record = json.loads(stdin_text)
    except ValueError as exc:
        raise InvalidInput(f"stdin is not JSON: {exc}") from exc
    fields = validate_record(record)

    sha = _git("rev-parse", "HEAD").strip()
    if not SHA_RE.match(sha):
        raise CannotComplete(f"HEAD is not a full SHA: {sha!r}")
    if _git("status", "--porcelain=v1", "--untracked-files=all").strip():
        raise CannotComplete("working tree is not clean — no receipt for an uncommitted tree")
    tests = fields["tests"]
    if tests is not None and tests["sha"] != sha:
        try:
            _git("merge-base", "--is-ancestor", tests["sha"], sha)
        except CannotComplete as exc:
            raise InvalidInput(
                f"tests.sha {tests['sha']} is not HEAD or an ancestor of it"
            ) from exc

    try:
        digests = [_digest(p) for p in fields["artifacts"]]
    except OSError as exc:
        raise CannotComplete(f"could not read an artifact: {exc}") from exc

    receipt = {
        "schema": SCHEMA,
        "sha": sha,
        "clean_tree": True,
        "tool": fields["tool"],
        "profile": fields["profile"],
        "cycles": fields["cycles"],
        "review": "clean",
        "tests": tests,
        "ui": fields["ui"],
        "executor": executor(),
        "artifacts": digests,
        "written_at": _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }

    directory = store_dir()
    try:
        os.makedirs(directory, mode=0o700, exist_ok=True)
        fd, temp = tempfile.mkstemp(prefix=".receipt-", suffix=".tmp", dir=directory)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump(receipt, fh, sort_keys=True)
                fh.write("\n")
                fh.flush()
                os.fsync(fh.fileno())
            target = os.path.join(directory, f"{sha}.json")
            os.replace(temp, target)
        except BaseException:
            if os.path.exists(temp):
                os.unlink(temp)
            raise
    except OSError as exc:
        raise CannotComplete(f"could not write receipt: {exc}") from exc
    return {"written": True, "sha": sha, "path": target}


def _refuse(sha: str, path: str | None, reason: str) -> dict:
    return {"verified": False, "reason": reason, "sha": sha, "path": path,
            "profile": None, "tests": None, "ui": None, "receipt": None}


def verify(sha: str) -> dict:
    if not SHA_RE.match(sha):
        raise InvalidInput("SHA must be 40 lowercase hex characters")
    path = os.path.join(store_dir(), f"{sha}.json")
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        return _refuse(sha, path, "absent")
    except OSError as exc:
        raise CannotComplete(f"could not stat receipt: {exc}") from exc
    if not stat.S_ISREG(st.st_mode):
        return _refuse(sha, path, "not a regular file")
    try:
        with open(path, encoding="utf-8") as fh:
            receipt = json.load(fh)
    except (OSError, ValueError):
        return _refuse(sha, path, "unreadable or not JSON")
    if not isinstance(receipt, dict):
        return _refuse(sha, path, "not a JSON object")

    checks = (
        (receipt.get("schema") == SCHEMA, "unknown schema"),
        (receipt.get("sha") == sha, "names a different commit"),
        (receipt.get("clean_tree") is True, "tree was not clean"),
        (receipt.get("review") == "clean", "review is not clean"),
        (receipt.get("profile") in PROFILES, "profile is not light or full"),
        (_is_count(receipt.get("cycles")), "cycles is not a count"),
    )
    for ok, reason in checks:
        if not ok:
            return _refuse(sha, path, reason)

    who = receipt.get("executor")
    here = executor()
    if not isinstance(who, dict):
        return _refuse(sha, path, "no executor identity")
    if who.get("host") != here["host"] or who.get("uid") != here["uid"] or who.get("user") != here["user"]:
        return _refuse(sha, path, "written by another user or host")

    tests = receipt.get("tests")
    tests_text = None
    if tests is not None:
        if not (
            isinstance(tests, dict)
            and _is_count(tests.get("count"))
            and isinstance(tests.get("sha"), str)
            and SHA_RE.match(tests["sha"])
            and isinstance(tests.get("command"), str)
            and tests["command"].strip()
        ):
            return _refuse(sha, path, "malformed tests record")
        tests_text = f"{tests['count']}@{tests['sha']}"

    ui = receipt.get("ui")
    if ui is not None and not isinstance(ui, str):
        return _refuse(sha, path, "malformed ui record")

    artifacts = receipt.get("artifacts")
    if not isinstance(artifacts, list):
        return _refuse(sha, path, "malformed artifacts")
    for art in artifacts:
        if not (isinstance(art, dict) and isinstance(art.get("path"), str)
                and isinstance(art.get("sha256"), str)):
            return _refuse(sha, path, "malformed artifacts")
        if os.path.isfile(art["path"]):
            try:
                now = _digest(art["path"])["sha256"]
            except OSError:
                return _refuse(sha, path, f"artifact unreadable: {art['path']}")
            if now != art["sha256"]:
                return _refuse(sha, path, f"artifact changed since the receipt: {art['path']}")

    return {"verified": True, "reason": "ok", "sha": sha, "path": path,
            "profile": receipt["profile"], "tests": tests_text, "ui": ui,
            "receipt": receipt}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-receipt.py",
        description=(
            "Write (--write, record JSON on stdin) or verify (--verify SHA40) the "
            "revision receipt that backs a QA handoff marker."
        ),
        epilog=(
            "Examples: printf '%s' \"$receipt_json\" | python3 gi-receipt.py --write ; "
            "python3 gi-receipt.py --verify \"$head_oid\""
        ),
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true",
                      help="record a receipt for the current HEAD (record on stdin)")
    mode.add_argument("--verify", metavar="SHA40",
                      help="verify the receipt for this commit")
    args = parser.parse_args(argv)

    try:
        if args.write:
            buffer = getattr(sys.stdin, "buffer", None)
            raw = buffer.read() if buffer is not None else sys.stdin.read().encode()
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError as exc:
                raise InvalidInput(f"stdin is not UTF-8: {exc}") from exc
            result = write(text)
        else:
            result = verify(args.verify)
    except InvalidInput as exc:
        print(f"✗ gi-receipt: {exc}", file=sys.stderr)
        return 3
    except CannotComplete as exc:
        print(f"⚠ gi-receipt: {exc}", file=sys.stderr)
        return 4
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
