#!/usr/bin/env bash
# test-secscan-contract-272.sh — gi-secscan's byte-source contract (issue #272)
#
# Seven consecutive review rounds each found a *different* way to make
# gi-secscan return exit 0 with an empty blocking[] over a live key, and three
# of those seven were introduced by the previous round's own fix. Every one was
# the same bug wearing a new input: the scan read bytes that were not the bytes
# being shipped, then reported the path as scanned and clean.
#
# So this suite does not test inputs. It tests the contract:
#
#   for every mode x every path shape,
#     the bytes scanned are exactly the bytes that mode ships,
#     the path reported is exactly the path git reported, byte for byte,
#     and a byte source that cannot be read fails closed with exit 4.
#
# "Scanned bytes" is not inferred from the verdict — `--emit-sources` makes the
# scan report a sha256 of every byte it actually consumed and from which source,
# and each cell compares that against a digest of the shipped bytes computed
# here. "Did not crash" is not an assertion anywhere in this file.
#
# Phase C is the part that makes the rest worth anything: it reverse-applies
# each of the seven historical fixes to a scratch copy of the script and
# requires the matching cell to FAIL. A matrix that passes against the broken
# code proves nothing, and that is the exact failure this issue exists to
# prevent.
#
# Usage: bash tests/test-secscan-contract-272.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export IDD_REPO_ROOT="$REPO_ROOT"

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ gi-secscan byte-source contract (issue #272)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

RESULTS="$(mktemp)"
trap 'rm -f "$RESULTS"' EXIT

python3 - > "$RESULTS" <<'PY'
"""The mode x path-shape matrix, its fail-closed cells, and its non-vacuity proof."""

import errno
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.environ["IDD_REPO_ROOT"]
SCRIPT = os.path.join(ROOT, "src", "shared", "scripts", "gi-secscan.py")
GI_CONFIG = os.path.join(ROOT, "src", "shared", "scripts", "gi-config.py")

# The repositories built here are throwaway, but git would still read the
# invoking user's global config — a `diff.renames = false`, a `core.quotePath`,
# an `init.defaultBranch`, a hook path — and a matrix that only holds under one
# developer's git config is not a contract. Both the fixtures and gi-secscan's
# own git calls inherit this environment.
os.environ["GIT_CONFIG_GLOBAL"] = os.devnull
os.environ["GIT_CONFIG_SYSTEM"] = os.devnull
os.environ["GIT_TERMINAL_PROMPT"] = "0"
os.environ.pop("IDD_AUTO_MODE", None)

# AWS's own documentation example key, assembled from two halves so the literal
# never appears in this file — gi-secscan scans contents, and a checked-in key
# would block every commit of this suite.
KEY = "AKIA" + "IOSFODNN7EXAMPLE"

SECRET = ("aws_access_key_id = " + KEY + "\nharmless second line\n").encode()
# Same length class, no key. If a cell's scan reads a decoy instead of the
# shipped bytes, the digest comparison says so even when the verdict does not.
DECOY = b"aws_access_key_id = <your-key-here>\nharmless second line\n"
TIDIED = b"aws_access_key_id = os.environ['AWS_KEY']\ntidied, not shipped\n"

RESULTS = []


def emit(ok, label):
    RESULTS.append(("PASS" if ok else "FAIL") + "|" + label)


def pb(text):
    """The path bytes behind a JSON string, surrogate escapes and all."""
    return text.encode("utf-8", "surrogateescape")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(args, cwd, check=True):
    proc = subprocess.run(
        ["git", *args], cwd=cwd, capture_output=True, check=False
    )
    if check and proc.returncode != 0:
        raise RuntimeError(
            "git " + " ".join(str(a) for a in args) + " failed: "
            + proc.stderr.decode("utf-8", "replace")
        )
    return proc


def write(repo, rel, data):
    full = os.path.join(repo, rel)
    parent = os.path.dirname(full)
    if parent and not os.path.isdir(parent):
        os.makedirs(parent)
    with open(full, "wb") as handle:
        handle.write(data)


def init_repo(repo):
    os.makedirs(repo)
    git(["init", "-q", "-b", "work", "."], repo)
    git(["config", "user.email", "t@example.com"], repo)
    git(["config", "user.name", "t"], repo)
    # core.quotePath on purpose: `-z` is what must defeat it. Without `-z` git
    # would emit "conf\303\257gs/keys.txt", a string that names no file.
    git(["config", "core.quotePath", "true"], repo)
    git(["config", "core.autocrlf", "false"], repo)
    git(["commit", "-q", "--allow-empty", "-m", "init"], repo)


# ── The path shapes ──────────────────────────────────────────────────────────
def supports_non_utf8_filenames():
    """Probe the exact raw-byte filename capability used by one matrix shape."""
    workdir = tempfile.mkdtemp()
    probe = os.path.join(os.fsencode(workdir), b"probe\xff")
    created = False
    try:
        with open(os.fsdecode(probe), "x"):
            pass
        created = True
    except OSError as exc:
        if exc.errno in {
            errno.EILSEQ,
            errno.EINVAL,
            errno.ENOTSUP,
            errno.EOPNOTSUPP,
        }:
            return False
        raise
    finally:
        if created:
            os.unlink(os.fsdecode(probe))
        shutil.rmtree(workdir, ignore_errors=True)
    return True


NON_UTF8_FILENAMES = supports_non_utf8_filenames()

# Every shape below is a legal filename on the platforms this gate runs on, and
# every one is attacker-controlled on a branch under review. `decoys` are clean
# siblings that a normalising scan would read *instead* — the shape's entire
# point is that the two must never be confused. The raw non-UTF-8 shape is added
# only when this filesystem supports the bytes it exercises.
SHAPES = [
    ("leading-space", b" lead.txt", [b"lead.txt"]),
    ("trailing-space", b"trail.txt ", [b"trail.txt"]),
    ("embedded-newline", b"two\nlines.txt", [b"two", b"lines.txt"]),
    ("carriage-return", b"cr.txt\r", [b"cr.txt"]),
    ("colon-prefixed", b":colon.txt", [b"colon.txt"]),
    ("stage-alias", b"0:x.txt", [b"x.txt"]),
    ("quoted-octal", "confïgs/kéys.txt".encode("utf-8"), [b"configs/keys.txt"]),
    ("whitespace-only", b"   ", [b"space.txt"]),
    ("quote-backslash", b'q"uo\\te.txt', [b"quote.txt"]),
    ("nested-dir", b"a/b/c/deep.txt", [b"a/b/c/shallow.txt"]),
    ("subdir-cwd", b"sub/from-below.txt", [b"sub/sibling.txt"]),
    ("root-trailing-space", b"secret.txt", [b"other.txt"]),
    ("rename-origin", b" renamed.txt", []),
    ("untracked-dir", b"u/v/w/hidden.txt", []),
]
if NON_UTF8_FILENAMES:
    SHAPES.insert(4, ("non-utf8-byte", b"notes\xff.txt", [b"notes.txt"]))
    RESULTS.append("PASS|capability: raw non-UTF-8 filename shape is included")
else:
    RESULTS.append(
        "SKIP|capability: raw non-UTF-8 filename shape skipped "
        "(filesystem rejects raw non-UTF-8 names)"
    )

MODES = ["--staged", "--working-tree", "--range"]


def build(mode, shape, path, decoys, workdir):
    """Build one fixture and return (repo, cwd, shipped_bytes, scan_args).

    `shipped_bytes` is the ground truth: the bytes this mode is about to ship
    for `path`. It is what the test wrote, never something read back through
    the code under test.
    """
    name = b"repo " if shape == "root-trailing-space" else b"repo"
    repo = os.path.join(workdir, name)
    init_repo(repo)
    args = [mode]

    if mode == "--staged":
        if shape == "rename-origin":
            write(repo, b"orig.txt", SECRET)
            git(["add", "-A"], repo)
            git(["commit", "-qm", "seed"], repo)
            git(["mv", b"orig.txt", path], repo)
            git(["add", "-A"], repo)
        else:
            for decoy in decoys:
                write(repo, decoy, DECOY)
            write(repo, path, SECRET)
            git(["add", "-A"], repo)
        # The working tree is tidied *after* staging. Every byte on disk is now
        # clean; only the index still carries the key. A scan that reads the
        # file instead of the blob reports a clean commit over a live secret —
        # historical mechanism #1.
        write(repo, path, TIDIED)
        for decoy in decoys:
            write(repo, decoy, TIDIED)

    elif mode == "--working-tree":
        if shape == "rename-origin":
            write(repo, b"orig.txt", DECOY)
            git(["add", "-A"], repo)
            git(["commit", "-qm", "seed"], repo)
            git(["mv", b"orig.txt", path], repo)
            write(repo, path, SECRET)
        elif shape == "untracked-dir":
            # Never added: `git status` without -uall collapses the whole new
            # subtree to `?? u/`, which is not a file — historical mechanism #7.
            write(repo, path, SECRET)
        else:
            for decoy in decoys:
                write(repo, decoy, DECOY)
            write(repo, path, DECOY)
            git(["add", "-A"], repo)
            git(["commit", "-qm", "seed"], repo)
            # Committed clean, edited dirty: HEAD and the index both hold the
            # decoy, so reading either instead of the file reports clean.
            write(repo, path, SECRET)

    else:  # --range
        write(repo, b"b.txt", b"base\n")
        git(["add", "-A"], repo)
        git(["commit", "-qm", "base"], repo)
        git(["branch", "pushbase"], repo)
        if shape == "rename-origin":
            write(repo, b"orig.txt", SECRET)
            git(["add", "-A"], repo)
            git(["commit", "-qm", "add"], repo)
            git(["mv", b"orig.txt", path], repo)
            git(["add", "-A"], repo)
            git(["commit", "-qm", "rename"], repo)
        else:
            for decoy in decoys:
                write(repo, decoy, DECOY)
            write(repo, path, SECRET)
            git(["add", "-A"], repo)
            git(["commit", "-qm", "add"], repo)
            # Added and then removed *within* the branch. `pushbase...HEAD` — a
            # net diff — no longer mentions this path at all, yet `git push`
            # still sends the commit that added it and the blob stays fetchable
            # from the remote forever. Every --range cell is also this
            # regression test.
            os.remove(os.path.join(repo, path))
            git(["add", "-A"], repo)
            git(["commit", "-qm", "remove"], repo)
        args = ["--range", "pushbase"]

    cwd = repo
    if shape == "subdir-cwd":
        cwd = os.path.join(repo, b"sub")
        if not os.path.isdir(cwd):
            os.makedirs(cwd)
    return repo, cwd, SECRET, args


def run_scan(script, cwd, args):
    proc = subprocess.run(
        [sys.executable, script, *args, "--quiet", "--emit-sources", "--no-config"],
        cwd=cwd,
        capture_output=True,
        check=False,
    )
    return proc.returncode, proc.stdout.decode("utf-8", "replace"), proc.stderr.decode(
        "utf-8", "replace"
    )


def check_cell(code, out, path, shipped):
    """Return the list of contract violations for one cell. Empty means clean."""
    bad = []
    if not out.strip():
        return [f"no JSON verdict (exit {code})"]
    try:
        data = json.loads(out)
    except json.JSONDecodeError as exc:
        return [f"unparsable verdict — {exc.msg}"]
    blocking = data.get("blocking", [])
    if code == 0 and not blocking:
        bad.append("exit 0 with an empty blocking[] over a live secret")
    if code != 1:
        bad.append(f"exit {code}, expected 1 (block)")
    if not any(
        item.get("rule") == "secret-value" and pb(item.get("path", "")) == path
        for item in blocking
    ):
        bad.append("no secret-value block reported against the exact path bytes")
    want = digest(shipped)
    mine = [s for s in data.get("sources", []) if pb(s.get("path", "")) == path]
    if not mine:
        bad.append("no byte source recorded for the exact path bytes")
    elif not any(
        s.get("sha256") == want and s.get("bytes_read") == len(shipped) for s in mine
    ):
        got = ", ".join(f"{s.get('kind')}:{str(s.get('sha256'))[:12]}" for s in mine)
        bad.append(f"scanned bytes != shipped bytes (want {want[:12]}, got {got})")
    return bad


def run_cell(script, mode, shape, path, decoys):
    workdir = tempfile.mkdtemp()
    try:
        _, cwd, shipped, args = build(mode, shape, path, decoys, os.fsencode(workdir))
        code, out, _ = run_scan(script, cwd, args)
        return check_cell(code, out, path, shipped)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


# ── Phase A: the matrix ──────────────────────────────────────────────────────
cells = 0
for mode in MODES:
    for shape, path, decoys in SHAPES:
        cells += 1
        problems = run_cell(SCRIPT, mode, shape, path, decoys)
        emit(
            not problems,
            f"matrix {mode} x {shape}: scanned bytes == shipped bytes"
            + ("" if not problems else " — " + "; ".join(problems)),
        )
emit(cells == len(MODES) * len(SHAPES), f"matrix covers {cells} mode x path-shape cells")


# ── Phase B: fail closed ─────────────────────────────────────────────────────
# Every one of these is a byte source that was declared and cannot be read. The
# only acceptable answer is exit 4 — never exit 0, and never a verdict at all.
def fail_closed(label, setup, args, allow=(4,)):
    workdir = tempfile.mkdtemp()
    try:
        repo = os.path.join(os.fsencode(workdir), b"repo")
        init_repo(repo)
        cwd = setup(repo) or repo
        code, out, _ = run_scan(SCRIPT, cwd, args)
        clean_pass = code == 0 and not json.loads(out or "{}").get("blocking", [])
        emit(
            code in allow and not clean_pass,
            f"fail-closed: {label} exits {'/'.join(map(str, allow))} (got {code})",
        )
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def setup_unmerged(repo):
    write(repo, b"conflict.txt", b"base\n")
    git(["add", "-A"], repo)
    git(["commit", "-qm", "base"], repo)
    git(["checkout", "-q", "-b", "other"], repo)
    write(repo, b"conflict.txt", SECRET)
    git(["add", "-A"], repo)
    git(["commit", "-qm", "other"], repo)
    git(["checkout", "-q", "work"], repo)
    write(repo, b"conflict.txt", b"mine\n")
    git(["add", "-A"], repo)
    git(["commit", "-qm", "mine"], repo)
    git(["merge", "other"], repo, check=False)  # leaves an unmerged index


def setup_missing_blob(repo):
    write(repo, b"gone.txt", SECRET)
    git(["add", "-A"], repo)
    oid = (
        git(["rev-parse", ":0:gone.txt"], repo).stdout.decode().strip()
    )
    loose = os.path.join(repo, os.fsencode(f".git/objects/{oid[:2]}/{oid[2:]}"))
    if os.path.exists(loose):
        os.chmod(os.path.dirname(loose), 0o755)
        os.remove(loose)


def setup_unreadable_file(repo):
    write(repo, b"locked.txt", SECRET)
    os.chmod(os.path.join(repo, b"locked.txt"), 0o000)


fail_closed("an unmerged index entry (--staged)", setup_unmerged, ["--staged"])
fail_closed("a staged blob whose object is gone", setup_missing_blob, ["--staged"])
if os.geteuid() != 0:
    fail_closed(
        "a listed file whose permissions deny the read (--working-tree)",
        setup_unreadable_file,
        ["--working-tree"],
    )
else:  # pragma: no cover - CI runs unprivileged
    emit(True, "fail-closed: unreadable-file cell skipped (running as root)")
fail_closed(
    "a --range base that does not resolve", lambda repo: None, ["--range", "nope"]
)
fail_closed(
    "a --range value that is an option, not a revision",
    lambda repo: None,
    ["--range", "--upload-pack=x"],
    allow=(2,),
)


# ── Phase B2: the parser refuses to guess ────────────────────────────────────
# Unit-level, because git will not produce these on demand — and "refuse to
# guess" is precisely what has to hold when it does.
sys.path.insert(0, os.path.dirname(SCRIPT))
import importlib.util

spec = importlib.util.spec_from_file_location("gi_secscan", SCRIPT)
secscan = importlib.util.module_from_spec(spec)
spec.loader.exec_module(secscan)

for label, payload, parser in (
    ("a raw record with an unmodelled header", "not-a-header\0path\0", "raw"),
    ("a combined-diff (::) header", "::100644 100644 100644 aa bb cc MM\0p\0", "raw"),
    (
        "a raw record with a zero destination object id",
        ":100644 100644 " + "0" * 40 + " " + "0" * 40 + " M\0p\0",
        "raw",
    ),
    ("an unmerged raw status", ":100644 100644 " + "a" * 40 + " " + "b" * 40 + " U\0p\0", "raw"),
    ("a truncated rename record", ":100644 100644 " + "a" * 40 + " " + "b" * 40 + " R100\0only\0", "raw"),
    ("an unparsable porcelain record", "XY\0", "porcelain"),
    ("an unmerged porcelain record", "UU conflict.txt\0", "porcelain"),
):
    try:
        if parser == "raw":
            secscan._raw_targets(payload, "test")
        else:
            secscan._porcelain_targets(payload)
    except secscan.Unavailable:
        emit(True, f"fail-closed: {label} raises Unavailable (exit 4)")
    except Exception as exc:  # noqa: BLE001
        emit(False, f"fail-closed: {label} raised {type(exc).__name__}, not Unavailable")
    else:
        emit(False, f"fail-closed: {label} was silently accepted")

# A worktree target git listed but that is not on disk must never be a skip.
try:
    secscan.scan(
        [secscan.Target("vanished.txt", "worktree")],
        secscan.build_rules({}),
        base="",
        strict=True,
    )
except secscan.Unavailable:
    emit(True, "fail-closed: a git-listed path that vanished raises Unavailable")
else:
    emit(False, "fail-closed: a git-listed path that vanished was scanned as clean")

# The same target from a caller's own list stays a visible warning: git made no
# claim it exists, so exit 4 there would degrade every pre-commit call.
result = secscan.scan(
    [secscan.Target("vanished.txt", "worktree")],
    secscan.build_rules({}),
    base="",
    strict=False,
)
emit(
    any(w["rule"] == "unreadable-path" for w in result["warnings"]),
    "fail-closed: a caller-listed path that does not resolve is warned, not hidden",
)


# ── Phase B3: the config search stops at the working-tree root ───────────────
def config_boundary():
    workdir = os.fsencode(tempfile.mkdtemp())
    try:
        ancestor = os.path.join(workdir, b"ancestor")
        os.makedirs(ancestor)
        # allow_pattern: ".*" skips every path. In an ancestor directory it must
        # have no effect at all; inside the repo it must work exactly as
        # documented. Both halves matter — a boundary that also breaks the
        # feature is not a fix.
        with open(os.path.join(ancestor, b".gitissue.yml"), "wb") as handle:
            handle.write(b'security:\n  allow_pattern: ".*"\n')
        repo = os.path.join(ancestor, b"repo")
        init_repo(repo)
        write(repo, b"secret.txt", SECRET)
        git(["add", "-A"], repo)
        proc = subprocess.run(
            [sys.executable, SCRIPT, "--staged", "--quiet"],
            cwd=repo,
            capture_output=True,
            check=False,
        )
        emit(
            proc.returncode == 1,
            "boundary: a .gitissue.yml above the repo root cannot disable the gate "
            f"(exit {proc.returncode}, expected 1)",
        )
        shutil.copyfile(
            os.path.join(ancestor, b".gitissue.yml"),
            os.path.join(repo, b".gitissue.yml"),
        )
        proc = subprocess.run(
            [sys.executable, SCRIPT, "--staged", "--quiet"],
            cwd=repo,
            capture_output=True,
            check=False,
        )
        emit(
            proc.returncode == 0,
            "boundary: the repo's own .gitissue.yml still governs allow_pattern "
            f"(exit {proc.returncode}, expected 0)",
        )
        # And from a subdirectory, the repo-root config is still in scope.
        sub = os.path.join(repo, b"sub")
        os.makedirs(sub)
        proc = subprocess.run(
            [sys.executable, SCRIPT, "--staged", "--quiet"],
            cwd=sub,
            capture_output=True,
            check=False,
        )
        emit(
            proc.returncode == 0,
            "boundary: the search still reaches the repo root from a subdirectory "
            f"(exit {proc.returncode}, expected 0)",
        )
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


config_boundary()


def schema_boundary():
    """gi-config's upward walk is bounded at the same place, or the two diverge."""
    workdir = os.fsencode(tempfile.mkdtemp())
    try:
        ancestor = os.path.join(workdir, b"ancestor")
        os.makedirs(os.path.join(ancestor, b"docs"))
        shutil.copyfile(
            os.path.join(ROOT, "docs", "config-schema.md"),
            os.path.join(ancestor, b"docs", b"config-schema.md"),
        )
        repo = os.path.join(ancestor, b"repo")
        init_repo(repo)
        proc = subprocess.run(
            [sys.executable, GI_CONFIG],
            cwd=repo,
            capture_output=True,
            check=False,
        )
        emit(
            proc.returncode == 4,
            "boundary: gi-config will not read a schema above the repo root "
            f"(exit {proc.returncode}, expected 4)",
        )
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


schema_boundary()


# ── Phase C: non-vacuity ─────────────────────────────────────────────────────
# Reverse-apply each historical fix and require the matching cell to fail. Every
# `old` string below must still be present in the script: if a refactor moves it,
# this phase fails loudly rather than quietly testing nothing.

LEGACY_SHOW = '''

def _legacy_show(path, pattern, tap, sizes):
    """The pre-fix path-addressed read: `git show :<path>`, ambiguous by design."""
    proc = subprocess.Popen(
        ["git", "show", ":" + path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
    )
    meter = _Tap(proc.stdout) if tap else None
    decided, detail = _scan_stream(meter or proc.stdout, pattern)
    proc.stdout.close()
    proc.wait()
    return Reading(
        "read",
        detail,
        None,
        meter.count if meter else 0,
        meter.hexdigest() if meter else None,
        decided,
    )
'''

BLOB_CALL = "reading = _read_blob(target.oid, secret_value, emit_sources, sizes)"
GIT_RUN = """        proc = subprocess.run(
            ["git", *args],
            capture_output=True,
            check=False,
        )"""
FSDECODE = "    return os.fsdecode(proc.stdout)"
CDUP_CALL = '    cdup = _git(["rev-parse", "--show-cdup"])'

MECHANISMS = [
    (
        "1. --staged scanned the working tree, not the index blob",
        [(BLOB_CALL, "reading = _read_worktree(resolved, secret_value, emit_sources, False)")],
        "",
        ("--staged", "leading-space"),
    ),
    (
        "2. the `:{path}` alias — `0:x.txt` resolved to stage 0 of `x.txt`",
        [(BLOB_CALL, "reading = _legacy_show(target.path, secret_value, emit_sources, sizes)")],
        LEGACY_SHOW,
        ("--staged", "stage-alias"),
    ),
    (
        "3. the path list was normalised — ` solo.txt` renamed",
        [('    fields = text.split("\\0")', '    fields = [f.strip() for f in text.split("\\0")]')],
        "",
        ("--staged", "leading-space"),
    ),
    (
        "4. text=True universal newlines — `keys.txt\\r` renamed",
        [
            (GIT_RUN, GIT_RUN.replace("check=False,", "check=False,\n            text=True,")),
            (FSDECODE, "    return proc.stdout"),
        ],
        "",
        ("--staged", "carriage-return"),
    ),
    (
        '5. errors="replace" — `notes\\xff.txt` became U+FFFD',
        [(FSDECODE, '    return proc.stdout.decode("utf-8", errors="replace")')],
        "",
        ("--staged", "non-utf8-byte"),
    ),
    (
        "6. the repo root was stripped — a repo directory ending in a space",
        [(CDUP_CALL, '    return _git(["rev-parse", "--show-toplevel"]).strip()\n' + CDUP_CALL)],
        "",
        ("--working-tree", "root-trailing-space"),
    ),
    (
        "7a. --range read the disk, not the committed blob (the pre-push gate)",
        [(BLOB_CALL, "reading = _read_worktree(resolved, secret_value, emit_sources, False)")],
        "",
        ("--range", "nested-dir"),
    ),
    (
        "7b. --working-tree collapsed an untracked subtree to `?? a/`",
        [('_git(["status", "--porcelain", "-z", "-uall"])', '_git(["status", "--porcelain", "-z"])')],
        "",
        ("--working-tree", "untracked-dir"),
    ),
]

SHAPE_BY_NAME = {name: (name, path, decoys) for name, path, decoys in SHAPES}
original = open(SCRIPT, encoding="utf-8").read()
scratch_dir = tempfile.mkdtemp()
try:
    for label, edits, addendum, (mode, shape_name) in MECHANISMS:
        if shape_name == "non-utf8-byte" and not NON_UTF8_FILENAMES:
            RESULTS.append(
                "SKIP|non-vacuity: " + label + " skipped "
                "(filesystem rejects raw non-UTF-8 names)"
            )
            continue
        broken = original
        missing = [old for old, _ in edits if old not in broken]
        if missing:
            emit(False, f"non-vacuity: {label} — the fix's code no longer matches; "
                        "this phase would test nothing")
            continue
        for old, new in edits:
            broken = broken.replace(old, new, 1)
        broken += addendum
        scratch = os.path.join(scratch_dir, "gi-secscan-broken.py")
        with open(scratch, "w", encoding="utf-8") as handle:
            handle.write(broken)
        _, path, decoys = SHAPE_BY_NAME[shape_name]
        problems = run_cell(scratch, mode, shape_name, path, decoys)
        emit(
            bool(problems),
            f"non-vacuity: reverse-applying {label} makes {mode} x {shape_name} fail"
            + ("" if problems else " — IT STILL PASSED, the cell asserts nothing"),
        )
finally:
    shutil.rmtree(scratch_dir, ignore_errors=True)

print("\n".join(RESULTS))
PY

while IFS='|' read -r verdict label; do
  [ -n "${verdict:-}" ] || continue
  if [ "$verdict" = "PASS" ]; then
    pass "$label"
  elif [ "$verdict" = "SKIP" ]; then
    echo "  ○ $label"
  else
    fail "$label"
  fi
done < "$RESULTS"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ The byte-source contract does not hold"
  exit 1
fi
echo "  ✓ Byte-source contract holds across every mode x path shape"
