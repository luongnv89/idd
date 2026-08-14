#!/usr/bin/env python3
"""Scan a set of paths for secrets and risky artifacts before a commit or push.

Every IDD skill that runs `git add` / `git commit` / `git push` must apply the
same gate. Expressed as prose that gate is ~90 lines of bash an agent re-derives
at every commit site, which is both expensive and the exact place where a
transcription slip turns a blocking check into a passing one. This script is
that gate as one deterministic tool: the same five rules, the same block/warn
split, decided by code instead of by re-reading a document.

The rules, in the order they are reported:

  1. block  secret-bearing filenames (`.env`, `*.key`, `*.pem`, `id_rsa`, ...)
  2. block  real API-key values inside text files, matched on known prefix plus
            length so placeholders (`your-key`, `xxx`, `<key>`, `${VAR}`) do not
            fire
  3. warn   files larger than `--max-file-size-mb` without Git LFS
  4. warn   build artifacts and temp files (gitignore hygiene)
  5. warn   the current branch is a protected one (main/master/production/...)

Output on success is exactly one line of JSON on stdout:

    {"verdict": "clean" | "warn" | "block",
     "blocking": [{"rule": ..., "path": ..., "detail": ...}, ...],
     "warnings": [{"rule": ..., "path": ..., "detail": ...}, ...],
     "scanned": <int>, "skipped": <int>, "policy_source": <str>,
     "branch": <str or null>,
     "mode": "auto" | "interactive", "confirm_required": <bool>}

Human-readable `✗` / `⚠` / `○` lines go to stderr, so a caller may show them
verbatim and still parse stdout.

The policy-provenance contract
------------------------------

`security.allow_pattern` suppresses **scanning**, not findings: a path it
matches is skipped before any rule runs. That is correct for the pre-commit
caller, where the repository is the operator's own. It is wrong for a caller
reviewing a branch it does not control, because `.gitissue.yml` is repository
data: a pull request committing `allow_pattern: "."` skips every path, and the
gate reports `verdict: clean` with `scanned: 0` having examined nothing. A
*narrow* pattern naming only the file that carries the key is the same hole with
a healthy-looking `scanned`, so a threshold on `scanned` does not close it.

`--policy-ref REF` closes it by provenance: `security.*` is read from
`REF:.gitissue.yml`, a ref the reviewed branch cannot write, and the work tree's
own file is not consulted at all. `policy_source` reports what was actually
used — `ref:<REF>`, `file:<path>`, or `defaults` — so a caller can assert it got
the policy it asked for. The flag is opt-in and changes nothing when absent: the
default remains the documented upward search from the working directory.

Callers reviewing code they do not control should treat exit 0 as a pass only
when `policy_source` is the ref they named, `verdict` is not `block`, and
`scanned` is not 0 while `skipped` is above 0.

The byte-source contract
------------------------

Seven separate silent passes were found in this gate before it was written this
way, and every one of them was the same bug: the scan read bytes that were not
the bytes being shipped, and then reported the path as scanned and clean. The
inputs differed — a path with a leading space, a path ending in `\\r`, a path
carrying an undecodable byte, a path literally named `0:x.txt`, a repository
directory whose name ended in a space — but the mechanism never did. Patching
inputs one at a time cannot close that class, because the class is "some path
shape steers the read"; it is closed only by making the read not depend on the
path at all.

So each mode declares, per entry, exactly one **byte source**, and the scan
reads that source and nothing else:

  --staged        the blob object id in the index, from `git diff --cached
                  --raw`. The object id *is* the content `git commit` will
                  write. No filename is used to find those bytes, so no
                  filename shape can redirect them.
  --range         the blob object id of every entry of every commit in
                  `BASE..HEAD`, from `git rev-list` plus `git diff-tree --raw`.
                  Commit by commit, not a net diff: a secret added in one commit
                  and removed in the next is absent from `BASE...HEAD` yet is
                  still in the history `git push` sends, so a net diff is a
                  pre-push hole.
  --working-tree  the file on disk, because that is what this mode is asking
                  about. The path comes from `git status --porcelain -z -uall`
                  byte for byte, and is joined against the working tree root
                  derived from `git rev-parse --show-cdup` — a string that can
                  only ever be a run of `../`, so no byte of the repository's
                  own directory name takes part in resolving it.
  paths /         the file on disk, relative to the working directory, exactly
  --files-from    as the caller named it.

Three invariants follow, and the mode x path-shape matrix test enforces each
of them for every combination:

  1. The bytes scanned for an entry are exactly the bytes that mode ships.
  2. The path reported for an entry is exactly the path git reported, byte for
     byte — no strip, no case fold, no re-encode.
  3. A declared byte source that cannot be read **fails closed** with exit 4.
     It is never skipped, never counted as scanned, and never reaches a clean
     verdict. The one exception is a caller-supplied list (`paths`,
     `--files-from`), where git makes no claim that the path exists: there a
     missing entry is reported as an `unreadable-path` warning, so it is
     visible rather than silently counted as clean.

Rule extensions come from the `security:` block of `.gitissue.yml`, which this
script reads itself. That is a security decision: `.gitissue.yml` is
repository-controlled, so a design where the caller passes config *values* on
the command line lets a crafted value break out of its shell quoting and run a
command — during a pull-request review, on the reviewer's machine, at the moment
the gate runs. `--config-json` remains for programmatic callers that already
hold the parsed config and can pass it without a shell. The search for that file
stops at the top of the working tree: a `.gitissue.yml` in `$HOME` must not be
able to set `security.allow_pattern` for every repository underneath it.

`confirm_required` is the mode contract, pre-computed: it is true only when
warnings fired *and* the run is interactive (`IDD_AUTO_MODE` is not `1`). This
script never prompts — it does not own the terminal, and the file list may
already be arriving on stdin. The caller prompts, or logs and proceeds in auto
mode. A block is never subject to either: it stops the commit in both modes.

Exit codes
  0  scan completed, nothing blocking (verdict `clean` or `warn`)
  1  scan completed, something blocking (verdict `block`) — this is a *verdict*,
     not a runtime failure. Callers MUST stop; they MUST NOT treat it as the
     degrade-to-prose path, because degrading past a real secret is the one
     outcome this gate exists to prevent.
  2  usage error
  3  invalid input — an unusable `--config-json`, a `security.*` value in
     `.gitissue.yml` that is the wrong type, or a regex that does not compile
     (stderr: `✗ gi-secscan: <why>`). Stop; a scan configured wrongly has not
     run, so its silence means nothing.
  4  cannot complete — no file list could be determined, a declared byte source
     could not be read, or `git` was needed and is unavailable (stderr:
     `⚠ gi-secscan: <reason>`). Callers fall back to the Primary Pattern in the
     pre-commit security conventions document. This is the fail-closed exit: it
     is *always* preferred to a clean verdict over bytes that were never read.

Authored at src/shared/scripts/gi-secscan.py — do not edit installed copies;
edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import re
import stat as statmod
import subprocess
import sys
from typing import NamedTuple

# --- Rule patterns -----------------------------------------------------------
#
# These are the canonical patterns from the pre-commit security conventions
# document, transcribed once. Extending them is a documentation change there
# plus an edit here; a repository extends them for itself through the
# `security.*` config keys rather than by editing this file.

SECRET_FILE_PATTERN = (
    r"(^|/)\.env($|\..+$)|\.key$|\.pem$|(^|/)credentials\.json$"
    r"|(^|/)secrets\.ya?ml$|(^|/)id_rsa($|\.pub$)|\.p12$|\.pfx$|\.cer$"
)

# Prefix + length, never identifier + value: the latter false-positives on
# docstrings and tests, which is how a scan gets disabled in practice.
SECRET_VALUE_PATTERN = (
    r"(sk-(proj-)?[A-Za-z0-9_-]{20,}|sk_live_[A-Za-z0-9]{20,}"
    r"|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}"
    r"|ghp_[A-Za-z0-9]{30,}|gho_[A-Za-z0-9]{30,}|ghs_[A-Za-z0-9]{30,}"
    r"|ghu_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}"
    r"|xox[abprs]-[A-Za-z0-9-]{10,}|glpat-[A-Za-z0-9_-]{20,}"
    r"|AIza[0-9A-Za-z_-]{30,})"
)

JUNK_FILE_PATTERN = (
    r"(^|/)(node_modules|dist|build|__pycache__|\.venv)(/|$)"
    r"|\.pyc$|(^|/)(\.DS_Store|thumbs\.db)$|\.swp$|\.tmp$"
)

PROTECTED_BRANCHES = ("main", "master", "production", "release")

DEFAULT_MAX_FILE_SIZE_MB = 10

# Read in 1 MiB chunks: a scanned file is usually source, but a caller can pass
# a checked-in tarball, and slurping it whole would spend memory to find nothing.
_CHUNK = 1 << 20

# A NUL in the first block is the same binary signal `file --mime` reports, with
# no dependency on `file` being installed (the prose fallback documents its
# absence as a known degradation; here there is nothing to degrade to).
_BINARY_SNIFF = 8192

# Bytes of a too-long line carried across a chunk boundary. A minified bundle or
# a serialized config can be one line of many megabytes; the buffer is scanned
# and then trimmed to this overlap, so a key whose prefix straddles the cut is
# still matched while memory stays bounded. Any real key prefix is far shorter.
_LINE_OVERLAP = 4096


class UsageError(Exception):
    """Bad invocation — exit 2."""


class InvalidInput(Exception):
    """Caller-supplied configuration is unusable — exit 3."""


class Unavailable(Exception):
    """The scan could not run; the caller falls back to prose — exit 4."""


class Target(NamedTuple):
    """One path plus the single source of the bytes that path ships.

    `kind` is the whole contract:

      "blob"      `oid` names a git object; its bytes are the shipped bytes.
                  The path is never used to find them.
      "worktree"  the file on disk under the scan's base directory.
      "absent"    this entry ships no bytes at all — a deletion, or a submodule
                  gitlink. `reason` says which. The filename rules still run;
                  there is simply no content or size to read.

    There is no fourth kind and no fallback between kinds. A "blob" whose object
    cannot be read is exit 4, not a quiet retry against the working tree: that
    retry is precisely how a tidied working copy came to be scanned in place of
    the blob a commit was about to write.
    """

    path: str
    kind: str
    oid: str = ""
    reason: str = ""


# --- Inputs ------------------------------------------------------------------


def _git(args: list[str]) -> str:
    """Run a read-only git command, or raise Unavailable.

    Decoding is `os.fsdecode`, not `text=True` and not a plain `.decode()`.
    `text=True` turns on universal newlines, which rewrites a lone `\r` inside a
    *filename* to `\n`; `errors="replace"` turns an undecodable byte into U+FFFD.
    Either one names a different file — or no file — while the path is still
    counted as scanned, which is a clean verdict over a secret. `os.fsdecode`
    uses surrogateescape, the same round-tripping the `os` module applies to
    every path it hands out, so `b"notes\xff.txt"` decodes to something that
    reopens the very same file. `-z` output exists precisely so that no byte of
    a filename is reinterpreted; anything else here undoes that.

    `--no-replace-objects` is a **top-level** git option and is passed here, not
    on the subcommand: `git cat-file --no-replace-objects …` is rejected with
    `error: unknown option`, which this helper would raise as Unavailable and
    every caller would read as exit 4 — a gate that degrades to prose on every
    run. A `refs/replace` entry otherwise rewrites what git reports: it can
    remap a *commit*, so `rev-list` and `diff-tree` enumerate a tree that never
    shipped, and the entry the secret lives in is never listed to begin with.
    Setting it once here covers every enumeration this scan performs.
    """
    try:
        proc = subprocess.run(
            ["git", "--no-replace-objects", *args],
            capture_output=True,
            check=False,
        )
    except (OSError, ValueError) as exc:  # git missing, or a bad argv
        raise Unavailable(f"cannot run git — {exc}") from exc
    if proc.returncode != 0:
        detail = proc.stderr.decode("utf-8", errors="replace").strip().splitlines()
        raise Unavailable(
            "git " + " ".join(args) + " failed: " + (detail[-1] if detail else "unknown")
        )
    return os.fsdecode(proc.stdout)


def _dedupe(entries: list[str]) -> list[str]:
    """Drop blank and repeated entries, preserving first-appearance order.

    Nothing is normalised here. Every byte that was not used as a separator is
    part of the filename — spaces, tabs and `\r` are all legal on the platforms
    this runs on — and filenames are attacker-controlled in the flows that call
    this gate. Rewriting ` secrets.env` to `secrets.env`, or `x.txt\r` to
    `x.txt`, names a *different* file: where a sibling exists its clean bytes
    are scanned in place of the real one, and where none exists the path
    resolves to nothing and is skipped as a deletion. Both report clean over a
    live key. Only the newline-separated caller list needs line-ending repair,
    and `_split_lines` does that where the format makes it unambiguous.
    """
    seen: set[str] = set()
    out: list[str] = []
    for entry in entries:
        # `not entry` alone is the separator artefact: a trailing NUL or a
        # final newline yields an empty field. A name that is only spaces is a
        # legal file, and dropping it would be the normalisation this docstring
        # says does not happen here.
        if not entry or entry in seen:
            continue
        seen.add(entry)
        out.append(entry)
    return out


def _split_lines(text: str) -> list[str]:
    """Split a newline-separated path list written by a human or a shell.

    Only this form gets its `\r` repaired, and only at the end of a line, where
    CRLF is a line ending rather than a name. `str.splitlines()` is deliberately
    not used: it also splits on `\v`, `\f`, `\x85` and ` `, every one of
    which is a legal filename byte. Git-sourced lists never come through here —
    they are NUL-separated, and `_fields` passes them through byte for byte.
    """
    # One `\r`, not a run of them: `x.txt\r\r\n` names a file ending in `\r`,
    # and stripping both would point at a different file with no warning.
    return _dedupe(
        [line[:-1] if line.endswith("\r") else line for line in text.split("\n")]
    )


def _fields(text: str) -> list[str]:
    """Split `-z` git output into its NUL-separated fields, verbatim.

    Not a heuristic on the *presence* of a NUL: every caller of this function
    passes `-z` to git, so the separator is known from the invocation rather
    than sniffed from the payload. The trailing empty field left by git's final
    NUL is dropped; nothing else is touched.
    """
    fields = text.split("\0")
    if fields and fields[-1] == "":
        fields.pop()
    return fields


# `:<src-mode> <dst-mode> <src-oid> <dst-oid> <status>[<score>]`, the header of
# one `--raw -z` record. Anchored and fully specified: a header that does not
# match is a format this parser does not model, and guessing which bytes ship is
# the exact move this contract forbids. Combined-diff headers (`::`) do not match
# either — none of the invocations here ask for one.
_RAW_HEADER_RE = re.compile(
    r"^:([0-7]{6}) ([0-7]{6}) ([0-9a-f]+) ([0-9a-f]+) ([A-Z])([0-9]*)$"
)

_ZERO_OID_RE = re.compile(r"^0+$")
_OID_RE = re.compile(r"^[0-9a-f]{7,64}$")

# `git rev-parse --show-cdup` can only ever be empty or a run of `../`. Asserting
# that is what keeps the repository's own directory name — which may end in a
# space, a tab or a `\r` — out of every path this scan resolves.
_CDUP_RE = re.compile(r"^(\.\./)*$")

# A gitlink: a submodule pointer, whose "content" is a commit id in another
# repository. No file bytes ship with it.
_GITLINK_MODE = "160000"


def _target_from_raw(
    path: str, dst_mode: str, dst_oid: str, status: str, what: str
) -> Target:
    """Turn one parsed `--raw` record into its declared byte source."""
    if status == "D":
        return Target(path, "absent", reason="deleted — no bytes are shipped")
    if status not in ("A", "C", "M", "R", "T"):
        # `U` (unmerged) and `X` (unknown) both mean git cannot tell us what
        # content this entry carries. Exit 4, so the caller falls back to the
        # prose gate rather than committing on a scan that skipped an entry.
        raise Unavailable(
            f"{what}: {path!r} has status {status!r}, whose shipped content git "
            "does not report — resolve it and rerun"
        )
    if dst_mode == _GITLINK_MODE:
        return Target(path, "absent", reason="submodule gitlink — no file bytes")
    if _ZERO_OID_RE.match(dst_oid) or not _OID_RE.match(dst_oid):
        raise Unavailable(
            f"{what}: {path!r} reports no destination object id — the bytes it "
            "ships cannot be read"
        )
    return Target(path, "blob", oid=dst_oid)


def _raw_targets(text: str, what: str) -> list[Target]:
    """Parse `git diff/diff-tree --raw -z` into byte-source targets.

    The record shape is a header field followed by one path field — two for a
    rename or a copy, where the *second* is the destination, the path that is
    actually being shipped. Path fields are consumed positionally by count, so
    a filename that happens to look like a header is data, not a record: the
    parser never has to decide what a field means.
    """
    fields = _fields(text)
    out: list[Target] = []
    index = 0
    while index < len(fields):
        header = fields[index]
        index += 1
        if not header:
            continue
        match = _RAW_HEADER_RE.match(header)
        if match is None:
            raise Unavailable(
                f"{what}: unparsable raw record {header!r} — refusing to guess "
                "which bytes are being shipped"
            )
        _, dst_mode, _, dst_oid, status, _ = match.groups()
        wanted = 2 if status in ("R", "C") else 1
        if index + wanted > len(fields):
            raise Unavailable(f"{what}: truncated {status} record for {header!r}")
        path = fields[index + wanted - 1]
        index += wanted
        if not path:
            raise Unavailable(f"{what}: a raw record named an empty path")
        out.append(_target_from_raw(path, dst_mode, dst_oid, status, what))
    return out


def _porcelain_targets(text: str) -> list[Target]:
    """Parse `git status --porcelain -z -uall` into byte-source targets.

    NUL-separated records, so no path is ever quoted or escaped — a filename
    with a space, a quote, or a non-ASCII character arrives verbatim. In this
    format a rename or copy is `XY <new>\\0<old>\\0`: the *new* path is the one
    about to be committed, and the extra origin field must be consumed rather
    than parsed as its own record. `-uall` is not optional: without it git
    collapses a new subtree to `?? a/`, which is not a file, so every path
    beneath it would be skipped while still being counted — a whole directory of
    secrets passing as one clean entry.
    """
    fields = _fields(text)
    out: list[Target] = []
    index = 0
    while index < len(fields):
        record = fields[index]
        index += 1
        if not record:
            continue
        if len(record) < 4 or record[2] != " ":
            raise Unavailable(
                f"--working-tree: unparsable status record {record!r} — refusing "
                "to guess which paths are being shipped"
            )
        state, path = record[:2], record[3:]
        if state[0] in ("R", "C") or state[1] in ("R", "C"):
            if index >= len(fields):
                raise Unavailable("--working-tree: truncated rename record")
            index += 1  # consume the origin path that follows a rename/copy
        if state[0] == "U" or state[1] == "U":
            raise Unavailable(
                f"--working-tree: {path!r} is unmerged — resolve the conflict "
                "and rerun"
            )
        if state[1] == "D" or (state[0] == "D" and state[1] == " "):
            out.append(
                Target(path, "absent", reason="deleted from the working tree")
            )
        else:
            out.append(Target(path, "worktree"))
    return out


def _dedupe_targets(targets: list[Target]) -> list[Target]:
    """Drop exact repeats, preserving first-appearance order.

    A range covering many commits re-lists a path once per commit that touched
    it; each *distinct* (path, source) pair is still scanned, because two
    commits shipping two different blobs at one path are two different sets of
    bytes to check.
    """
    seen: set[tuple[str, str, str]] = set()
    out: list[Target] = []
    for target in targets:
        key = (target.path, target.kind, target.oid)
        if key in seen:
            continue
        seen.add(key)
        out.append(target)
    return out


def worktree_base() -> str:
    """The absolute working-tree root, derived without reading its name.

    `rev-parse --show-cdup` answers "how far up is the top level" as a run of
    `../` — never as the repository's own path. That matters: `--show-toplevel`
    hands back a directory name whose trailing bytes are as attacker-controlled
    as any filename, and one `.strip()` on it points every subsequent
    `os.path.isfile` at a directory that does not exist. Every content and size
    rule then misses on a git-sourced list, which raises no unreadable-path
    warning either — the same silent pass as a mangled filename, one level up.
    Joining `../` against `os.getcwd()` cannot have that failure mode, because
    the bytes of the repository's name never enter the computation.
    """
    cdup = _git(["rev-parse", "--show-cdup"])
    if cdup.endswith("\n"):
        cdup = cdup[:-1]
    if not _CDUP_RE.match(cdup):
        raise Unavailable(
            f"git rev-parse --show-cdup returned {cdup!r}, which is not a run "
            "of '../' — refusing to resolve paths against it"
        )
    here = os.getcwd()
    return os.path.normpath(os.path.join(here, cdup)) if cdup else here


def _range_targets(base: str) -> list[Target]:
    """Every blob shipped by `base..HEAD`, commit by commit.

    Not `base...HEAD`. A net diff answers "how does the tip differ from the
    merge base", and a secret added in one commit and removed in the next does
    not differ — yet `git push` still sends the commit that added it, and the
    blob stays fetchable from the remote forever. The push is a set of commits,
    so the gate walks that set.
    """
    if base.startswith("-"):
        # `f"{base}..HEAD"` would otherwise hand git an option instead of a
        # revision. No shell is involved, but argv injection is still injection.
        raise UsageError(f"--range value must be a revision, not an option: {base!r}")
    commits = _split_lines(_git(["rev-list", f"{base}..HEAD", "--"]))
    targets: list[Target] = []
    for commit in commits:
        if not _OID_RE.match(commit):
            raise Unavailable(f"--range: git rev-list printed {commit!r}, not a commit id")
        targets += _raw_targets(
            _git(
                [
                    "diff-tree",
                    "-r",
                    "-m",
                    "--root",
                    "--raw",
                    "-z",
                    "--no-abbrev",
                    "--no-commit-id",
                    commit,
                ]
            ),
            f"--range (commit {commit[:8]})",
        )
    return _dedupe_targets(targets)


def collect_targets(args: argparse.Namespace) -> tuple[list[Target], str, bool]:
    """Resolve the requested source into (targets, base, strict).

    `base` is the directory `worktree` targets are relative to. Git reports
    paths relative to the *repo root* regardless of where it was invoked, so a
    scan started from a subdirectory must join them against the top level —
    without that, every `os.path.isfile` misses and the content and size rules
    silently do not run, which reads as a clean scan. Caller-supplied paths are
    relative to the working directory and get an empty base.

    `strict` is the fail-closed switch. It is true for every git-sourced mode,
    where git has told us the entry exists and an unreadable byte source is
    therefore a scan that did not happen. It is false for caller-supplied lists,
    where a path that resolves to nothing is the caller's typo and is reported
    as a warning instead.
    """
    if args.paths:
        return (
            [Target(path, "worktree") for path in _split_lines("\n".join(args.paths))],
            "",
            False,
        )
    if args.files_from:
        if args.files_from == "-":
            buffer = getattr(sys.stdin, "buffer", None)
            # os.fsdecode, as in _git: a listed path with an undecodable byte
            # must round-trip to the same file, not to U+FFFD.
            text = (
                os.fsdecode(buffer.read())
                if buffer is not None
                else sys.stdin.read()
            )
        else:
            try:
                with open(args.files_from, "rb") as handle:
                    text = os.fsdecode(handle.read())
            except OSError as exc:
                raise Unavailable(f"cannot read {args.files_from} — {exc}") from exc
        return [Target(path, "worktree") for path in _split_lines(text)], "", False
    # `-z` on every git read: without it git applies core.quotePath and emits
    # `"conf\303\257gs/keys.txt"` for any path with a non-ASCII, quoted, or
    # escaped character. That string names no file on disk, so the file would
    # be counted as scanned while its contents were never read.
    if args.staged:
        return (
            _dedupe_targets(
                _raw_targets(
                    _git(
                        ["diff", "--cached", "-M", "--raw", "-z", "--no-abbrev"]
                    ),
                    "--staged",
                )
            ),
            worktree_base(),
            True,
        )
    if args.working_tree:
        return (
            _dedupe_targets(
                _porcelain_targets(_git(["status", "--porcelain", "-z", "-uall"]))
            ),
            worktree_base(),
            True,
        )
    if args.range:
        return _range_targets(args.range), worktree_base(), True
    raise UsageError(
        "no input selected — pass paths, or one of "
        "--staged / --working-tree / --range / --files-from"
    )


def current_branch() -> str | None:
    """The checked-out branch name, or None when git cannot tell us."""
    try:
        # `--show-current` over `rev-parse --abbrev-ref HEAD`: it is empty
        # rather than failing on a detached HEAD, and it works in a repository
        # that has no commits yet, where rev-parse errors on an unborn HEAD.
        return _git(["branch", "--show-current"]).strip() or None
    except Unavailable:
        # A detached HEAD or a missing git is not a scan failure: the
        # protected-branch rule is the only thing that needs the name, and it
        # is a warning. Every blocking rule still runs.
        return None


# --- Configuration -----------------------------------------------------------


def _compile(pattern: str, label: str) -> re.Pattern[str]:
    try:
        return re.compile(pattern)
    except re.error as exc:
        raise InvalidInput(f"{label} is not a valid regex — {exc}") from exc


SECURITY_KEYS = (
    "extra_secret_file_pattern",
    "extra_secret_value_pattern",
    "allow_pattern",
    "max_file_size_mb",
)

CONFIG_NAME = ".gitissue.yml"

# Only the `security:` block, only its four documented scalars. This is not a
# general YAML parser and must not become one — it exists so a config value
# never has to travel on a command line (see `load_overrides`).
_SECTION_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):\s*$")
_ENTRY_RE = re.compile(r"^\s+([a-z_][a-z0-9_]*):[ \t]+(.*?)\s*$")


def _parse_scalar(raw: str, key: str) -> object:
    """Parse the restricted scalar syntax the config schema documents."""
    if raw.startswith('"'):
        try:
            return json.loads(raw)
        except json.JSONDecodeError as exc:
            raise InvalidInput(f"security.{key} — invalid quoted string ({exc.msg})")
    if raw.startswith("'") and raw.endswith("'") and len(raw) >= 2:
        return raw[1:-1].replace("''", "'")
    if re.fullmatch(r"-?[0-9]+", raw):
        return int(raw)
    return raw


def read_security_config(path: str) -> dict[str, object]:
    """Read the `security:` block of a `.gitissue.yml`, or {} when absent."""
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        # No config file is the normal zero-config case, not an error.
        return {}
    return parse_security_config(text)


def parse_security_config(text: str) -> dict[str, object]:
    """Parse the `security:` block out of `.gitissue.yml` text.

    Split from `read_security_config` so the same restricted parser serves both
    byte sources — the file on disk, and the blob `--policy-ref` reads out of a
    git ref. One parser, so the two sources can never disagree about what a
    value means.
    """
    values: dict[str, object] = {}
    inside = False
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        section = _SECTION_RE.match(line)
        if section:
            inside = section.group(1) == "security"
            continue
        if not inside:
            continue
        entry = _ENTRY_RE.match(line)
        if entry and entry.group(1) in SECURITY_KEYS:
            values[entry.group(1)] = _parse_scalar(entry.group(2), entry.group(1))
    return values


def config_search_ceiling() -> str:
    """The highest directory the config search may look in.

    The top of the working tree, or the working directory itself when there is
    no working tree to speak of. Without a ceiling the search walks to `/`, so a
    `.gitissue.yml` in `$HOME` — or in `/tmp`, or anywhere else a repository
    happens to be checked out under — governs `security.allow_pattern` for every
    repository beneath it, and `allow_pattern: .` turns this gate off entirely.
    A file outside the repository under review is not that repository's
    configuration, so the walk stops at its root. When git cannot say where that
    root is, the search covers the working directory only: reading nothing above
    it is the fail-closed answer.
    """
    try:
        return worktree_base()
    except Unavailable:
        return os.path.abspath(os.getcwd())


def find_config(explicit: str | None) -> str | None:
    """Locate the config file: the explicit path, else `.gitissue.yml` at or
    above the working directory but never above the working-tree root."""
    if explicit:
        return explicit
    here = os.path.abspath(os.getcwd())
    ceiling = os.path.abspath(config_search_ceiling())
    while True:
        candidate = os.path.join(here, CONFIG_NAME)
        if os.path.isfile(candidate):
            return candidate
        parent = os.path.dirname(here)
        if here == ceiling or parent == here:
            return None
        here = parent


# The gitrevisions lookup order for a non-fully-qualified `<refname>`, minus
# rule 1 (`$GIT_DIR/<refname>`): git only honours that form for a handful of
# all-caps root refs (`HEAD`, `FETCH_HEAD`, `ORIG_HEAD`, ...), which
# `_reject_ambiguous_ref` returns early on, and `for-each-ref` does not list
# them anyway. The remaining five are the forms two different refs can both
# claim — and the order matters: `refs/heads/<ref>` is consulted *before*
# `refs/remotes/<ref>`, which is the whole of the defect below.
_REF_LOOKUP_RULES = (
    "refs/{ref}",
    "refs/tags/{ref}",
    "refs/heads/{ref}",
    "refs/remotes/{ref}",
    "refs/remotes/{ref}/HEAD",
)


def _reject_ambiguous_ref(ref: str) -> None:
    """Fail closed when `ref` could name more than one ref — exit 4.

    A short `<refname>` is not a name, it is a *search*: git tries the five
    forms above in order and takes the first hit. So `refs/heads/origin/main`
    shadows `refs/remotes/origin/main`, and every caller of this script binds
    the short `origin/<default-branch>` form. `/issue-pr-review` Step 1 runs
    `gh pr checkout`, which materialises the pull request's own — attacker
    chosen — `headRefName` as a *local branch*: a branch literally named
    `origin/main` therefore wins the lookup and re-supplies the reviewed
    branch's `.gitissue.yml` as the "trusted" policy, while `policy_source`
    still reports `ref:origin/main`, exactly the ref the caller asked for.

    Detected mechanically rather than by reading git's `warning: refname ... is
    ambiguous` line: that text is localizable, version-dependent, and lands on
    a stderr this script discards. A ref that resolves to anything other than
    exactly one ref was never read from the reviewing side, so it raises
    Unavailable rather than being scanned under.

    A fully-qualified `refs/...` name and `HEAD` both resolve unambiguously and
    are returned early; zero matches fall through to the caller's existing
    absent-versus-unreadable split, which is unchanged.
    """
    if ref.startswith("refs/") or ref == "HEAD":
        return
    candidates = [rule.format(ref=ref) for rule in _REF_LOOKUP_RULES]
    # `_git`, not a raw `subprocess.run`: it places `--no-replace-objects` as
    # the top-level option it has to be, and turns a git failure into
    # Unavailable — which is the fail-closed direction this check wants anyway.
    listed = _git(["for-each-ref", "--format=%(refname)", *candidates])
    # Exact membership, because a `for-each-ref` pattern matches "completely or
    # from the beginning up to a slash": a bare prefix hit is not a ref this
    # lookup would ever reach, and counting it would degrade a healthy repo.
    wanted = set(candidates)
    found = {line for line in listed.split("\n") if line in wanted}
    if len(found) > 1:
        raise Unavailable(
            f"--policy-ref {ref} is ambiguous — it names "
            + ", ".join(sorted(found))
            + ". The reviewing side's policy could not be identified, so "
            "nothing was scanned under it; pass the fully-qualified name of "
            "the one you mean"
        )


def read_policy_ref(ref: str) -> tuple[dict[str, object], str]:
    """Read `security.*` from `<ref>:.gitissue.yml`, never from the work tree.

    The trust boundary this closes. `.gitissue.yml` is repository-controlled and
    `/issue-pr-review` runs with the pull request's branch checked out, so the
    file the ordinary upward walk finds is written by the author of the artifact
    under review. A branch that commits `allow_pattern: "."` — or a narrow
    pattern naming just the file carrying the key — governs its own review, and
    the gate reports `clean` having examined nothing that matters. Pointing the
    policy at a ref the reviewed branch cannot write makes the reviewing side
    supply the policy.

    Fail-closed in three directions. A ref that resolves but carries no
    `.gitissue.yml` yields the built-in defaults (no allow pattern at all) —
    never a silent fall back to the branch's file, which would hand the decision
    straight back to the artifact. A ref that does not resolve is `Unavailable`
    (exit 4, the documented degrade), because a policy that could not be read is
    not a policy that permitted anything. And a ref that resolves to *more than
    one* ref is `Unavailable` too: the short `origin/<branch>` form every call
    site binds is resolved by git as `refs/heads/` before `refs/remotes/`, and
    `gh pr checkout` materialises the pull request's attacker-chosen head-ref
    name as a local branch — so a branch named `origin/main` re-supplies its own
    policy while `policy_source` still names the ref the caller asked for. See
    `_reject_ambiguous_ref`.
    """
    if not ref:
        # An empty value is a malformed invocation, not an opt-out. Treating it
        # as "no policy ref" would send the scan back to the work tree — the
        # branch's own file — which is the entire defect this flag exists to
        # close, reached by supplying nothing rather than by supplying a ref.
        raise UsageError("--policy-ref value must not be empty")
    if ref.startswith("-"):
        # `f"{ref}:{CONFIG_NAME}"` would otherwise hand git an option instead of
        # a revision. Same rule as `--range` — no shell is involved, but argv
        # injection is still injection.
        raise UsageError(f"--policy-ref value must be a revision, not an option: {ref!r}")
    # After both usage guards and before `spec`: an empty or option-shaped value
    # is a malformed invocation (exit 2), while an ambiguous one is a policy that
    # could not be identified (exit 4). Reordering these flips a pinned contract.
    _reject_ambiguous_ref(ref)
    spec = f"{ref}:{CONFIG_NAME}"
    # Ask whether a blob exists at that path *before* reading it, so the two
    # non-zero outcomes below stay distinguishable. Without this probe every
    # failure to read collapses into "the ref has no config": a `.gitissue.yml`
    # that is a tree, a blobless or shallow clone that has the commit but not
    # the blob, and a corrupt object would each silently drop the trusted ref's
    # real `security.*` — including its extra secret patterns — while the
    # verdict still claimed `policy_source: ref:<REF>`.
    try:
        present = subprocess.run(
            ["git", "--no-replace-objects", "rev-parse", "--verify", "--quiet", spec],
            capture_output=True,
            check=False,
        ).returncode == 0
    except OSError as exc:
        raise Unavailable(f"cannot read {spec} — {exc}") from exc
    if not present:
        # Either the ref itself is absent — exit 4, because a policy that could
        # not be read permitted nothing — or it resolves and simply ships no
        # config, which is the built-in defaults and never the work-tree file.
        try:
            _git(["rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"])
        except Unavailable as exc:
            raise Unavailable(
                f"--policy-ref {ref} does not resolve — the reviewing side's "
                "policy could not be read, so nothing was scanned under it"
            ) from exc
        return {}, f"ref:{ref}"
    try:
        proc = subprocess.run(
            ["git", "--no-replace-objects", "cat-file", "blob", spec],
            capture_output=True,
            check=False,
        )
    except OSError as exc:
        raise Unavailable(f"cannot read {spec} — {exc}") from exc
    if proc.returncode != 0:
        # The path names a blob that cannot be read. Every other byte source in
        # this script fails closed here rather than substituting something else.
        raise Unavailable(
            f"{spec} exists but could not be read — the reviewing side's policy "
            "was never applied"
        )
    text = proc.stdout.decode("utf-8", errors="replace")
    return parse_security_config(text), f"ref:{ref}"


def load_overrides(args: argparse.Namespace) -> tuple[dict[str, object], str]:
    """Resolve the rule extensions: config file, then `--config-json`, then flags.

    This script reads `.gitissue.yml` itself rather than taking the resolved
    config as an argument, and that is a security decision, not a convenience.
    `.gitissue.yml` is repository-controlled, and `/issue-pr-review` runs with a
    pull request's branch checked out. Any design where a caller interpolates a
    config *value* into the command line — `--allow-pattern '<value>'`, or the
    whole JSON envelope inside a quoted word — lets a crafted value close the
    quote and append a command, executing it on the reviewer's machine at the
    exact moment the security gate runs. Reading the file directly means no
    config value ever touches a shell.

    Only the four documented `security.*` scalars are read, so this is not a
    second copy of the configuration resolver; every other key stays the config
    resolver's business.

    Returns the values and the `policy_source` string naming where they came
    from, so a caller reviewing code it does not control can assert that the
    policy it got is the one it asked for rather than the branch's own.
    """
    values: dict[str, object] = {}
    # Presence, never truthiness: `--policy-ref ""` must not fall through to the
    # filesystem search. `read_policy_ref` rejects the empty value as a usage
    # error, so an orchestrator that renders an unset spawn variable into the
    # flag gets exit 2 instead of a scan governed by the branch's own config.
    if args.policy_ref is not None:
        # `--policy-ref` replaces the filesystem search outright. Consulting the
        # work tree as well would re-admit the branch's own file through the
        # merge, which is the whole hole this flag exists to close.
        values, source = read_policy_ref(args.policy_ref)
    elif not args.no_config:
        path = find_config(args.config)
        if path is not None:
            values.update(read_security_config(path))
            source = f"file:{path}"
        elif args.config:
            raise InvalidInput(f"config file not found: {args.config}")
        else:
            source = "defaults"
    else:
        source = "defaults"

    if args.config_json:
        try:
            text = args.config_json
            if text == "-":
                # Read bytes, not text: a UnicodeDecodeError from sys.stdin is a
                # ValueError that would escape main() and exit 1 — the code
                # reserved for "a real secret was found".
                buffer = getattr(sys.stdin, "buffer", None)
                text = (
                    buffer.read().decode("utf-8", errors="replace")
                    if buffer is not None
                    else sys.stdin.read()
                )
            loaded = json.loads(text)
        except (json.JSONDecodeError, UnicodeDecodeError, OSError) as exc:
            raise InvalidInput(f"--config-json is not valid JSON — {exc}") from exc
        if not isinstance(loaded, dict):
            raise InvalidInput("--config-json must be a JSON object")
        # Accept gi-config's full envelope or a bare dotted-key mapping.
        config = loaded.get("config", loaded)
        if not isinstance(config, dict):
            raise InvalidInput("--config-json 'config' must be a JSON object")
        for key in SECURITY_KEYS:
            if config.get(f"security.{key}") not in (None, ""):
                values[key] = config[f"security.{key}"]

    if args.extra_secret_file_pattern is not None:
        values["extra_secret_file_pattern"] = args.extra_secret_file_pattern
    if args.extra_secret_value_pattern is not None:
        values["extra_secret_value_pattern"] = args.extra_secret_value_pattern
    if args.allow_pattern is not None:
        values["allow_pattern"] = args.allow_pattern
    if args.max_file_size_mb is not None:
        values["max_file_size_mb"] = args.max_file_size_mb
    return values, source


def build_rules(overrides: dict[str, object]) -> dict[str, object]:
    """Compile the effective rule set: built-ins plus this repo's extensions."""

    def _alternate(base: str, key: str, label: str) -> re.Pattern[str]:
        extra = overrides.get(key)
        if extra in (None, ""):
            return _compile(base, label)
        if not isinstance(extra, str):
            raise InvalidInput(f"security.{key} must be a string")
        # Validate the extension on its own first, so the error names the
        # user's regex rather than the 300-character combined one.
        _compile(extra, f"security.{key}")
        return _compile(f"{base}|{extra}", label)

    size = overrides.get("max_file_size_mb", DEFAULT_MAX_FILE_SIZE_MB)
    if isinstance(size, bool) or not isinstance(size, int) or size < 1:
        raise InvalidInput("security.max_file_size_mb must be an integer >= 1")

    allow = overrides.get("allow_pattern")
    if allow in (None, ""):
        allow_re = None
    elif isinstance(allow, str):
        allow_re = _compile(allow, "security.allow_pattern")
    else:
        raise InvalidInput("security.allow_pattern must be a string")

    return {
        "secret_file": _alternate(
            SECRET_FILE_PATTERN, "extra_secret_file_pattern", "secret-file pattern"
        ),
        "secret_value": _alternate(
            SECRET_VALUE_PATTERN, "extra_secret_value_pattern", "secret-value pattern"
        ),
        "junk_file": _compile(JUNK_FILE_PATTERN, "junk-file pattern"),
        "allow": allow_re,
        "max_bytes": size * 1024 * 1024,
        "max_mb": size,
    }


# --- Scanning ----------------------------------------------------------------


def _looks_binary(head: bytes) -> bool:
    return b"\0" in head


class _Tap:
    """A read-through wrapper that records exactly which bytes were scanned.

    This is the observability half of the byte-source contract: without it a
    test can only assert "the scan blocked", which is satisfied just as well by
    a scan that read the wrong file and got lucky. With it, the matrix test
    compares a digest of the bytes this scan actually consumed against a digest
    of the bytes the mode ships, computed independently. It is off unless
    `--emit-sources` is passed, and it never changes what is read.
    """

    def __init__(self, handle) -> None:
        self._handle = handle
        self._digest = hashlib.sha256()
        self.count = 0

    def read(self, size: int = -1) -> bytes:
        data = self._handle.read(size)
        self._digest.update(data)
        self.count += len(data)
        return data

    def hexdigest(self) -> str:
        return self._digest.hexdigest()


def _scan_stream(handle, pattern: re.Pattern[str]) -> tuple[bool, str | None]:
    """Return `(decided, detail)` for one byte stream.

    `detail` is the matched secret's rule detail, or None. Only the *shape* of
    the match is reported — the prefix and the line number. Echoing the value
    would copy the secret into a transcript, a log, and quite possibly a PR
    comment, which is a second leak on top of the first.

    `decided` is True when the answer was reached without consuming the whole
    stream — a match, or a binary sniff. A caller reading from a pipe needs it
    to tell "I stopped early on purpose" from "the producer failed".
    """
    head = handle.read(_BINARY_SNIFF)
    if _looks_binary(head):
        return True, None
    line_number = 0
    carry = b""
    chunk = head
    while chunk:
        carry += chunk
        *lines, carry = carry.split(b"\n")
        for raw in lines:
            line_number += 1
            match = pattern.search(raw.decode("utf-8", errors="replace"))
            if match:
                return True, f"line {line_number}: {match.group(0)[:8]}… (redacted)"
        if len(carry) > _CHUNK:
            # A single line longer than the buffer. Scan it *before*
            # trimming — dropping the head unscanned would hide a
            # secret anywhere but the final megabyte of a minified
            # bundle — then keep an overlap so a prefix straddling the
            # cut is still matched on the next pass.
            match = pattern.search(carry.decode("utf-8", errors="replace"))
            if match:
                return True, (
                    f"line {line_number + 1}: "
                    f"{match.group(0)[:8]}… (redacted)"
                )
            carry = carry[-_LINE_OVERLAP:]
        chunk = handle.read(_CHUNK)
    if carry:
        line_number += 1
        match = pattern.search(carry.decode("utf-8", errors="replace"))
        if match:
            return True, f"line {line_number}: {match.group(0)[:8]}… (redacted)"
    return False, None


class Reading(NamedTuple):
    """The outcome of reading one target's declared byte source.

    `state` is "read" when bytes were actually consumed and "no-bytes" when the
    source exists but ships no file content — a submodule checkout, a device
    node. A source that *should* have bytes and could not be read is never a
    Reading: it raises Unavailable, which is exit 4.
    """

    state: str
    detail: str | None
    size: int | None
    bytes_read: int
    digest: str | None
    decided_early: bool


NO_BYTES = Reading("no-bytes", None, None, 0, None, False)


def _read_blob(
    oid: str, pattern: re.Pattern[str], tap: bool, sizes: dict[str, int]
) -> Reading:
    """Scan a git object by id. The path is not involved and cannot redirect it.

    A failure here is exit 4, never a fallback: `git show`ing a blob and quietly
    scanning the working-tree file instead when it fails is how a tidied copy
    came to be scanned in place of the bytes a commit was about to write.
    Stopping early *by decision* — a match, or a binary sniff — still counts as
    a successful read even though closing the pipe leaves git a non-zero status.

    `--no-replace-objects` goes before `cat-file`, never after it: it is a git
    top-level option, and as a `cat-file` option git rejects it outright. Without
    it a `refs/replace` entry pointing the secret-bearing blob at a clean one
    makes this read return the clean bytes, and the scan reports on a blob the
    commit does not ship.
    """
    try:
        proc = subprocess.Popen(
            ["git", "--no-replace-objects", "cat-file", "blob", oid],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
    except OSError as exc:
        raise Unavailable(f"cannot read blob {oid} — {exc}") from exc
    assert proc.stdout is not None
    meter = _Tap(proc.stdout) if tap else None
    try:
        decided, detail = _scan_stream(meter or proc.stdout, pattern)
    except (OSError, MemoryError) as exc:
        proc.kill()
        proc.wait()
        raise Unavailable(f"cannot read blob {oid} — {exc}") from exc
    finally:
        # Close rather than drain: draining a multi-gigabyte blob to be polite
        # to the pipe would spend the memory the chunked read was written to
        # avoid. git takes EPIPE and exits non-zero.
        proc.stdout.close()
    status = proc.wait()
    if not decided and status != 0:
        raise Unavailable(
            f"git cat-file blob {oid} failed — the bytes this entry ships were "
            "never read"
        )
    return Reading(
        "read",
        detail,
        sizes.get(oid),
        meter.count if meter else 0,
        meter.hexdigest() if meter else None,
        decided,
    )


def _blob_sizes(oids: list[str]) -> dict[str, int]:
    """Size every object in one `git cat-file --batch-check`, or exit 4.

    One process for the whole scan rather than one per entry: a range covering a
    few dozen commits would otherwise spend more time forking `cat-file -s` than
    reading. A `missing` answer is fail-closed — an entry git listed but cannot
    size is an entry this scan cannot report on.

    `--no-replace-objects` is passed as a top-level option for the reason given
    in `_read_blob`: a replaced blob would otherwise be sized as its stand-in,
    and an oversized artifact would pass the size rule on a smaller substitute.
    """
    wanted = sorted(set(oids))
    if not wanted:
        return {}
    try:
        proc = subprocess.run(
            ["git", "--no-replace-objects", "cat-file", "--batch-check"],
            input="\n".join(wanted) + "\n",
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as exc:
        raise Unavailable(f"cannot size the scanned blobs — {exc}") from exc
    if proc.returncode != 0:
        raise Unavailable("git cat-file --batch-check failed — no entry was sized")
    sizes: dict[str, int] = {}
    for line in proc.stdout.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[1] == "blob":
            try:
                sizes[parts[0]] = int(parts[2])
            except ValueError:
                pass
    for oid in wanted:
        if oid not in sizes:
            raise Unavailable(
                f"git cannot size object {oid} — an entry this scan was asked "
                "to check is unreadable"
            )
    return sizes


def _read_worktree(
    resolved: str, pattern: re.Pattern[str], tap: bool, strict: bool
) -> Reading | None:
    """Scan the file on disk, or return None when there is nothing there.

    None means "no bytes at this path". Under `strict` — every git-sourced mode,
    where git has just told us the entry exists — the caller turns that into
    exit 4 rather than a skip. A symlink is read as the link target, because
    that string is exactly what git stores for it; a directory or a device node
    ships no file bytes at all. Anything else that cannot be opened, including a
    file whose permissions deny the read, is a source that was declared and not
    read: exit 4 under strict, an `unreadable-path` warning for a caller list.
    """
    try:
        info = os.lstat(resolved)
    except OSError:
        # Nothing at this path at all. The caller decides what that means: exit
        # 4 for a git-sourced entry, a visible warning for a caller's own list.
        return None
    if statmod.S_ISLNK(info.st_mode):
        try:
            payload = os.fsencode(os.readlink(resolved))
        except OSError as exc:
            if strict:
                raise Unavailable(f"cannot read the symlink {resolved!r} — {exc}")
            return None
        handle: object = io.BytesIO(payload)
        meter = _Tap(handle) if tap else None
        decided, detail = _scan_stream(meter or handle, pattern)
        return Reading(
            "read",
            detail,
            len(payload),
            meter.count if meter else 0,
            meter.hexdigest() if meter else None,
            decided,
        )
    if not statmod.S_ISREG(info.st_mode):
        # A directory (a submodule checkout) or a device node. Git lists it, and
        # it genuinely ships no file bytes — that is an answer, not a failure.
        return NO_BYTES
    try:
        with open(resolved, "rb") as raw:
            meter = _Tap(raw) if tap else None
            decided, detail = _scan_stream(meter or raw, pattern)
            return Reading(
                "read",
                detail,
                info.st_size,
                meter.count if meter else 0,
                meter.hexdigest() if meter else None,
                decided,
            )
    except OSError as exc:
        if strict:
            # The file is there and git says it ships; we simply could not read
            # it. Counting that as clean is the silent pass this gate exists to
            # prevent.
            raise Unavailable(
                f"cannot read {resolved!r} — {exc}. Its contents were never "
                "checked, so this scan has no verdict to give"
            )
        return None


def scan(
    targets: list[Target],
    rules: dict[str, object],
    base: str = "",
    strict: bool = False,
    emit_sources: bool = False,
    policy_source: str = "defaults",
) -> dict[str, object]:
    """Apply every rule to every target and return the structured verdict.

    `base` is the directory `worktree` targets are relative to (see
    `collect_targets`). The reported path stays exactly as git gave it —
    repo-relative reads better in a commit message than an absolute one, and any
    rewrite of it is a rename — while every filesystem access is resolved
    against `base`.

    Which bytes get read is decided entirely by `target.kind`. There is no
    fallback from one kind to another, and under `strict` a declared source that
    cannot be read raises Unavailable, which `main` turns into exit 4.
    """
    blocking: list[dict[str, str]] = []
    warnings: list[dict[str, str]] = []
    sources: list[dict[str, object]] = []
    scanned = 0
    skipped = 0

    # One batch-check for every blob the scan will read, up front: sizing each
    # one with its own process is the difference between a fast gate and one a
    # caller is tempted to skip.
    sizes = _blob_sizes([t.oid for t in targets if t.kind == "blob"])

    allow: re.Pattern[str] | None = rules["allow"]  # type: ignore[assignment]
    secret_file: re.Pattern[str] = rules["secret_file"]  # type: ignore[assignment]
    secret_value: re.Pattern[str] = rules["secret_value"]  # type: ignore[assignment]
    junk_file: re.Pattern[str] = rules["junk_file"]  # type: ignore[assignment]

    for target in targets:
        path = target.path
        if allow is not None and allow.search(path):
            skipped += 1
            continue
        scanned += 1

        if secret_file.search(path):
            blocking.append(
                {
                    "rule": "secret-file",
                    "path": path,
                    "detail": "filename matches a secret-bearing pattern",
                }
            )

        if junk_file.search(path):
            warnings.append(
                {
                    "rule": "build-artifact",
                    "path": path,
                    "detail": "build artifact or temp file — add it to .gitignore",
                }
            )

        resolved = os.path.join(base, path) if base else path
        reading: Reading | None = None
        if target.kind == "blob":
            reading = _read_blob(target.oid, secret_value, emit_sources, sizes)
        elif target.kind == "worktree":
            reading = _read_worktree(resolved, secret_value, emit_sources, strict)
            if reading is None and strict:
                raise Unavailable(
                    f"{path!r} is listed by git but no bytes could be read for "
                    "it — the scan cannot report on a file it never opened"
                )
            if reading is None or (not strict and reading.state == "no-bytes"):
                # A caller-supplied list has no git guarantee behind it: a typo,
                # a stray space, or a directory where a file was meant resolves
                # to no bytes at all, and reporting that as clean is a scan of
                # zero bytes dressed as a pass. (Under `strict` a "no-bytes"
                # entry is a submodule gitlink git itself listed, which really
                # does ship no file content.)
                warnings.append(
                    {
                        "rule": "unreadable-path",
                        "path": path,
                        "detail": "listed for scanning but not readable — "
                        "its contents were never checked",
                    }
                )

        if emit_sources:
            sources.append(
                {
                    "path": path,
                    "kind": (
                        target.kind
                        if target.kind == "absent"
                        else "unread"
                        if reading is None
                        else (target.kind if reading.state == "read" else "no-bytes")
                    ),
                    "id": target.oid
                    if target.kind == "blob"
                    else (os.path.abspath(resolved) if target.kind == "worktree" else ""),
                    "reason": target.reason,
                    "bytes_read": reading.bytes_read if reading else 0,
                    "sha256": reading.digest if reading else None,
                    "decided_early": bool(reading and reading.decided_early),
                }
            )

        if reading is None:
            continue
        if reading.detail is not None:
            blocking.append(
                {"rule": "secret-value", "path": path, "detail": reading.detail}
            )
        if reading.size is not None and reading.size > rules["max_bytes"]:  # type: ignore[operator]
            warnings.append(
                {
                    "rule": "large-file",
                    "path": path,
                    "detail": f"{reading.size // (1024 * 1024)} MB exceeds "
                    f"{rules['max_mb']} MB without Git LFS",
                }
            )

    branch = current_branch()
    if branch in PROTECTED_BRANCHES:
        warnings.append(
            {
                "rule": "protected-branch",
                "path": "",
                "detail": f"on protected branch {branch} — confirm this is intentional",
            }
        )

    auto = os.environ.get("IDD_AUTO_MODE", "0") == "1"
    verdict = "block" if blocking else ("warn" if warnings else "clean")
    result: dict[str, object] = {
        "verdict": verdict,
        "blocking": blocking,
        "warnings": warnings,
        "scanned": scanned,
        "skipped": skipped,
        # Where `security.*` came from: `ref:<REF>`, `file:<path>`, or
        # `defaults`. A caller reviewing code it does not control asserts this
        # is the ref it named — `scanned`/`skipped` say what was examined, and
        # this says who decided. An allow pattern suppresses *scanning*, not
        # findings, so a verdict is only as trustworthy as its policy's source.
        "policy_source": policy_source,
        "branch": branch,
        "mode": "auto" if auto else "interactive",
        "confirm_required": bool(warnings) and not auto and not blocking,
    }
    if emit_sources:
        result["sources"] = sources
    return result


def report(result: dict[str, object]) -> None:
    """Write the human-readable half of the verdict to stderr."""
    for item in result["blocking"]:  # type: ignore[union-attr]
        where = f" {item['path']}" if item["path"] else ""
        sys.stderr.write(f"✗ {item['rule']}:{where} — {item['detail']}\n")
    for item in result["warnings"]:  # type: ignore[union-attr]
        where = f" {item['path']}" if item["path"] else ""
        sys.stderr.write(f"⚠ {item['rule']}:{where} — {item['detail']}\n")
    if result["verdict"] == "block":
        sys.stderr.write(
            "\n✗ Pre-commit security scan blocked the commit — secrets detected.\n"
            "\n  To fix:  remove or rotate the offending value, then re-stage the\n"
            "           file. If the match was a false positive, replace the\n"
            "           literal with a placeholder (your-key, xxx, <your-key>,\n"
            "           ${YOUR_KEY}) and rerun.\n"
            "  Docs:    pre-commit-security conventions reference\n\n"
        )
    elif result["verdict"] == "warn" and not result["confirm_required"]:
        sys.stderr.write("○ Warnings logged — proceeding (auto mode).\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-secscan.py",
        description=(
            "Scan paths for secrets and risky artifacts before a commit or "
            "push. Prints one JSON verdict on stdout; exits 1 when something "
            "blocking is found."
        ),
        epilog=(
            "Example: python3 gi-secscan.py --staged   (scans the blobs the "
            "commit will write, not the working tree)"
        ),
    )
    source = parser.add_argument_group("input (choose exactly one)")
    source.add_argument("paths", nargs="*", help="paths to scan")
    source.add_argument("--files-from", metavar="FILE", help="path list ('-' = stdin)")
    source.add_argument("--staged", action="store_true", help="the index's blobs")
    source.add_argument("--working-tree", action="store_true", help="git status")
    source.add_argument(
        "--range", metavar="BASE", help="every blob in BASE..HEAD, commit by commit"
    )

    tuning = parser.add_argument_group("rule configuration")
    tuning.add_argument(
        "--config",
        metavar="PATH",
        help=f"{CONFIG_NAME} to read security.* from (default: found upward from "
        "cwd, stopping at the working-tree root)",
    )
    tuning.add_argument(
        "--no-config", action="store_true", help="ignore any config file"
    )
    tuning.add_argument(
        "--policy-ref",
        metavar="REF",
        help=(
            f"read security.* from REF:{CONFIG_NAME} instead of the work tree. "
            "For callers reviewing code they do not control: the checked-out "
            "config is written by the branch under review and can allow-list "
            "its own secrets. Reported as policy_source"
        ),
    )
    tuning.add_argument(
        "--config-json",
        metavar="JSON",
        help=(
            "gi-config output, or a dotted-key mapping ('-' = stdin). Prefer "
            "the config file: a value interpolated into a command line can "
            "escape its quoting"
        ),
    )
    tuning.add_argument("--extra-secret-file-pattern", metavar="RE")
    tuning.add_argument("--extra-secret-value-pattern", metavar="RE")
    tuning.add_argument("--allow-pattern", metavar="RE", help="paths to skip entirely")
    tuning.add_argument("--max-file-size-mb", type=int, metavar="N")
    parser.add_argument(
        "--quiet", action="store_true", help="suppress the stderr report"
    )
    parser.add_argument(
        "--emit-sources",
        action="store_true",
        help=(
            "add a 'sources' array recording, per path, the byte source that "
            "was scanned and a sha256 of the bytes read. Diagnostic only — it "
            "changes nothing about what is scanned"
        ),
    )
    args = parser.parse_args(argv)

    chosen = [
        bool(args.paths),
        bool(args.files_from),
        args.staged,
        args.working_tree,
        bool(args.range),
    ]
    if sum(1 for flag in chosen if flag) > 1:
        sys.stderr.write("✗ gi-secscan: choose exactly one input source\n")
        return 2

    # `--policy-ref` names *the* policy source. Silently merging a second one
    # would let the branch's own file back in through the side door, and would
    # make `policy_source` a claim the verdict does not support.
    if args.policy_ref is not None and (
        args.config or args.no_config or args.config_json
    ):
        sys.stderr.write(
            "✗ gi-secscan: --policy-ref conflicts with --config/--no-config/"
            "--config-json — choose one policy source\n"
        )
        return 2

    try:
        overrides, policy_source = load_overrides(args)
        rules = build_rules(overrides)
        targets, base, strict = collect_targets(args)
        result = scan(
            targets,
            rules,
            base,
            strict=strict,
            emit_sources=args.emit_sources,
            policy_source=policy_source,
        )
    except UsageError as exc:
        sys.stderr.write(f"✗ gi-secscan: {exc}\n")
        return 2
    except InvalidInput as exc:
        sys.stderr.write(f"✗ gi-secscan: {exc}\n")
        return 3
    except Unavailable as exc:
        sys.stderr.write(f"⚠ gi-secscan: {exc}\n")
        return 4

    print(json.dumps(result))
    if not args.quiet:
        report(result)
    return 1 if result["verdict"] == "block" else 0


if __name__ == "__main__":
    sys.exit(main())
