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
     "scanned": <int>, "skipped": <int>, "branch": <str or null>,
     "mode": "auto" | "interactive", "confirm_required": <bool>}

Human-readable `✗` / `⚠` / `○` lines go to stderr, so a caller may show them
verbatim and still parse stdout.

`--staged` scans the bytes in the **index** — the blob `git commit` will write —
not the file on disk. The two diverge the moment a path is staged and then
edited, and scanning the working-tree copy of a staged path is a silent false
negative: `git add secrets.txt` followed by an edit that strips the key leaves a
clean file over a blob that still carries it. Every other input source (paths,
`--files-from`, `--working-tree`, `--range`) reads the working tree, which is
what those sources mean.

Rule extensions come from the `security:` block of `.gitissue.yml`, which this
script reads itself. That is a security decision: `.gitissue.yml` is
repository-controlled, so a design where the caller passes config *values* on
the command line lets a crafted value break out of its shell quoting and run a
command — during a pull-request review, on the reviewer's machine, at the moment
the gate runs. `--config-json` remains for programmatic callers that already
hold the parsed config and can pass it without a shell.

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
  4  cannot complete — no file list could be determined, or `git` was needed and
     is unavailable (stderr: `⚠ gi-secscan: <reason>`). Callers fall back to the
     Primary Pattern in the pre-commit security conventions document.

Authored at src/shared/scripts/gi-secscan.py — do not edit installed copies;
edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys

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


# --- Inputs ------------------------------------------------------------------


def _git(args: list[str]) -> str:
    """Run a read-only git command, or raise Unavailable."""
    try:
        proc = subprocess.run(
            ["git", *args],
            capture_output=True,
            text=True,
            check=False,
        )
    except (OSError, ValueError) as exc:  # git missing, or a bad argv
        raise Unavailable(f"cannot run git — {exc}") from exc
    if proc.returncode != 0:
        detail = proc.stderr.strip().splitlines()
        raise Unavailable(
            "git " + " ".join(args) + " failed: " + (detail[-1] if detail else "unknown")
        )
    return proc.stdout


def _dedupe(entries: list[str]) -> list[str]:
    """Drop blanks and repeats, preserving first-appearance order.

    Only `\\r` and the trailing newline are stripped — never leading or trailing
    spaces. A space is a legal filename character on every platform this runs
    on, and filenames are attacker-controlled in the flows that call this gate:
    stripping ` secrets.env` to `secrets.env` renames the path to a *different*
    file, so the index blob and the file on disk that get scanned are not the
    ones being committed. Where a sibling exists, its clean contents are scanned
    in place of the real one; where it does not, the path resolves to nothing
    and is skipped as a deletion. Both report clean over a live key.
    """
    seen: set[str] = set()
    out: list[str] = []
    for entry in entries:
        path = entry.rstrip("\r\n")
        if not path.strip() or path in seen:
            continue
        seen.add(path)
        out.append(path)
    return out


def _split_paths(text: str) -> list[str]:
    """Split a newline- or NUL-separated path list."""
    return _dedupe(text.split("\0") if "\0" in text else text.splitlines())


def _porcelain_paths(text: str) -> list[str]:
    """Extract paths from `git status --porcelain -z` output.

    NUL-separated records, so no path is ever quoted or escaped — a filename
    with a space, a quote, or a non-ASCII character arrives verbatim. In this
    format a rename or copy is `XY <new>\\0<old>\\0`: the *new* path is the one
    about to be committed, and the extra origin field must be consumed rather
    than parsed as its own record.
    """
    fields = text.split("\0")
    out: list[str] = []
    index = 0
    while index < len(fields):
        record = fields[index]
        index += 1
        if len(record) < 4:
            continue
        status, path = record[:2], record[3:]
        if status[0] in ("R", "C") or status[1] in ("R", "C"):
            index += 1  # consume the origin path that follows a rename/copy
        if path:
            out.append(path)
    return _dedupe(out)


def repo_root() -> str:
    """The working tree's top level, or "" when git cannot say."""
    try:
        return _git(["rev-parse", "--show-toplevel"]).strip()
    except Unavailable:
        return ""


def collect_paths(args: argparse.Namespace) -> tuple[list[str], str]:
    """Resolve the requested source into (paths, base).

    `base` is the directory the returned paths are relative to. Git reports
    paths relative to the *repo root* regardless of where it was invoked, so a
    scan started from a subdirectory must join them against the top level —
    without that, every `os.path.isfile` misses and the content and size rules
    silently do not run, which reads as a clean scan. Caller-supplied paths are
    relative to the working directory and get an empty base.
    """
    if args.paths:
        return _split_paths("\n".join(args.paths)), ""
    if args.files_from:
        if args.files_from == "-":
            buffer = getattr(sys.stdin, "buffer", None)
            text = (
                buffer.read().decode("utf-8", errors="replace")
                if buffer is not None
                else sys.stdin.read()
            )
        else:
            try:
                with open(args.files_from, "rb") as handle:
                    text = handle.read().decode("utf-8", errors="replace")
            except OSError as exc:
                raise Unavailable(f"cannot read {args.files_from} — {exc}") from exc
        return _split_paths(text), ""
    # `-z` on every git read: without it git applies core.quotePath and emits
    # `"conf\303\257gs/keys.txt"` for any path with a non-ASCII, quoted, or
    # escaped character. That string names no file on disk, so the file would
    # be counted as scanned while its contents were never read.
    if args.staged:
        return _split_paths(_git(["diff", "--cached", "-z", "--name-only"])), repo_root()
    if args.working_tree:
        return _porcelain_paths(_git(["status", "--porcelain", "-z"])), repo_root()
    if args.range:
        return (
            _split_paths(_git(["diff", "-z", "--name-only", f"{args.range}...HEAD"])),
            repo_root(),
        )
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


def find_config(explicit: str | None) -> str | None:
    """Locate the config file: the explicit path, else `.gitissue.yml` at or
    above the working directory."""
    if explicit:
        return explicit
    here = os.path.abspath(os.getcwd())
    while True:
        candidate = os.path.join(here, CONFIG_NAME)
        if os.path.isfile(candidate):
            return candidate
        parent = os.path.dirname(here)
        if parent == here:
            return None
        here = parent


def load_overrides(args: argparse.Namespace) -> dict[str, object]:
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
    """
    values: dict[str, object] = {}
    if not args.no_config:
        path = find_config(args.config)
        if path is not None:
            values.update(read_security_config(path))
        elif args.config:
            raise InvalidInput(f"config file not found: {args.config}")

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
    return values


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


def _scan_file_contents(path: str, pattern: re.Pattern[str]) -> str | None:
    """Scan a working-tree file. See `_scan_stream` for the reporting contract."""
    try:
        with open(path, "rb") as handle:
            return _scan_stream(handle, pattern)[1]
    except OSError:
        # Unreadable or vanished between listing and scanning. Not a block: the
        # file cannot reach the commit either.
        return None


def _index_rev(path: str) -> str:
    """The index revision for `path`, stage-qualified.

    `:<path>` is ambiguous: git reads `:<n>:<path>` when the character after the
    colon is a digit, so a staged file literally named `0:x.txt` resolves to
    stage 0 of `x.txt` — a different file, whose clean contents would be scanned
    in its place. Naming stage 0 explicitly removes the ambiguity for every
    path, and filenames are attacker-controlled in the flows that run this gate.
    """
    return f":0:{path}"


def _scan_index_blob(
    path: str, root: str, pattern: re.Pattern[str]
) -> tuple[bool, str | None]:
    """Scan the *staged* content of `path`, i.e. the blob in the index.

    Returns `(scanned, detail)`. A staged scan must read what `git commit` will
    write, not what happens to be on disk: `git add secrets.txt` followed by an
    edit that removes the key leaves a clean working tree over a blob that still
    carries it, and scanning the file would report clean while the commit takes
    the secret. `scanned` is False only when the blob could not be read at all (a
    staged deletion, a gitlink, a git that failed), so the caller can fall back
    to the working-tree file rather than silently skipping content scanning.
    Stopping early *by decision* — a match, or a binary sniff — still counts as
    read, even though closing the pipe leaves git a non-zero status: reporting
    those as unread drops the size rule for every binary blob over the pipe
    buffer.
    """
    try:
        proc = subprocess.Popen(
            ["git", "-C", root or ".", "show", _index_rev(path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        return False, None
    try:
        assert proc.stdout is not None
        decided, detail = _scan_stream(proc.stdout, pattern)
    except (OSError, MemoryError):
        proc.kill()
        proc.wait()
        return False, None
    finally:
        if proc.stdout is not None:
            # Close rather than drain: draining a multi-gigabyte blob to be
            # polite to the pipe would spend the memory the chunked read was
            # written to avoid. git takes EPIPE and exits non-zero.
            proc.stdout.close()
    status = proc.wait()
    # `decided` means the scan reached its answer without needing the rest of
    # the stream — a match, or a binary sniff. Both leave git to die of EPIPE,
    # so its non-zero status says nothing about whether the blob was readable,
    # and reading it as "no blob" would drop the size rule for every binary
    # file larger than the pipe buffer.
    return (decided or status == 0), detail


def _index_blob_size(path: str, root: str) -> int | None:
    """Byte size of the staged blob, or None when git cannot report it."""
    try:
        proc = subprocess.run(
            ["git", "-C", root or ".", "cat-file", "-s", _index_rev(path)],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return None
    if proc.returncode != 0:
        return None
    try:
        return int(proc.stdout.strip())
    except ValueError:
        return None


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


def _file_size(path: str) -> int | None:
    try:
        return os.path.getsize(path)
    except OSError:
        return None


def scan(
    paths: list[str],
    rules: dict[str, object],
    base: str = "",
    from_index: bool = False,
) -> dict[str, object]:
    """Apply every rule to every path and return the structured verdict.

    `base` is the directory `paths` are relative to (see `collect_paths`). The
    reported path stays as given — repo-relative reads better in a commit
    message than an absolute one — while every filesystem access is resolved
    against `base`.

    `from_index` selects the *staged* bytes (the blob `git commit` will write)
    over the working-tree file. They diverge whenever a path is staged and then
    edited, and only the index copy is the one about to be committed.
    """
    blocking: list[dict[str, str]] = []
    warnings: list[dict[str, str]] = []
    scanned = 0
    skipped = 0

    allow: re.Pattern[str] | None = rules["allow"]  # type: ignore[assignment]
    secret_file: re.Pattern[str] = rules["secret_file"]  # type: ignore[assignment]
    secret_value: re.Pattern[str] = rules["secret_value"]  # type: ignore[assignment]
    junk_file: re.Pattern[str] = rules["junk_file"]  # type: ignore[assignment]

    for path in paths:
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

        indexed = False
        if from_index:
            indexed, detail = _scan_index_blob(path, base, secret_value)
            if indexed and detail is not None:
                blocking.append(
                    {"rule": "secret-value", "path": path, "detail": detail}
                )

        if not indexed:
            # No staged blob (a staged deletion, a gitlink, or a git that could
            # not answer), or a non-staged mode: fall back to the file on disk.
            if not os.path.isfile(resolved):
                # A deletion, or a path outside the working tree. The filename
                # rules above still applied; there is no content or size here.
                continue

            detail = _scan_file_contents(resolved, secret_value)
            if detail is not None:
                blocking.append(
                    {"rule": "secret-value", "path": path, "detail": detail}
                )

        size = _index_blob_size(path, base) if indexed else None
        if size is None:
            size = _file_size(resolved)
        if size is not None and size > rules["max_bytes"]:  # type: ignore[operator]
            warnings.append(
                {
                    "rule": "large-file",
                    "path": path,
                    "detail": f"{size // (1024 * 1024)} MB exceeds "
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
    return {
        "verdict": verdict,
        "blocking": blocking,
        "warnings": warnings,
        "scanned": scanned,
        "skipped": skipped,
        "branch": branch,
        "mode": "auto" if auto else "interactive",
        "confirm_required": bool(warnings) and not auto and not blocking,
    }


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
            "Example: git diff --cached --name-only | "
            "python3 gi-secscan.py --files-from -"
        ),
    )
    source = parser.add_argument_group("input (choose exactly one)")
    source.add_argument("paths", nargs="*", help="paths to scan")
    source.add_argument("--files-from", metavar="FILE", help="path list ('-' = stdin)")
    source.add_argument("--staged", action="store_true", help="git diff --cached")
    source.add_argument("--working-tree", action="store_true", help="git status")
    source.add_argument("--range", metavar="BASE", help="git diff BASE...HEAD")

    tuning = parser.add_argument_group("rule configuration")
    tuning.add_argument(
        "--config",
        metavar="PATH",
        help=f"{CONFIG_NAME} to read security.* from (default: found upward from cwd)",
    )
    tuning.add_argument(
        "--no-config", action="store_true", help="ignore any config file"
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

    try:
        rules = build_rules(load_overrides(args))
        paths, base = collect_paths(args)
    except UsageError as exc:
        sys.stderr.write(f"✗ gi-secscan: {exc}\n")
        return 2
    except InvalidInput as exc:
        sys.stderr.write(f"✗ gi-secscan: {exc}\n")
        return 3
    except Unavailable as exc:
        sys.stderr.write(f"⚠ gi-secscan: {exc}\n")
        return 4

    result = scan(paths, rules, base, from_index=bool(args.staged))
    print(json.dumps(result))
    if not args.quiet:
        report(result)
    return 1 if result["verdict"] == "block" else 0


if __name__ == "__main__":
    sys.exit(main())
