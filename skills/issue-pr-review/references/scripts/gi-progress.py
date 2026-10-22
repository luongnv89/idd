#!/usr/bin/env python3
"""Keep a durable progress record so a killed resolver or reviewer run can resume (issue #542).

/issue-resolver and /issue-pr-review lose their place when a session is killed:
a fresh invocation has no conversation to read, so it starts again from the
first step and repeats research, planning, QA or review cycles that already
finished. This script keeps one small record per run that a new session can
read back. **A record is a hint, never an authority.** It saves repeated work;
it never satisfies or skips a safety gate, and every gate re-runs live on a
resume.

The store
  `<git common dir>/idd/progress/<skill>-<N>.json` — inside `.git`, so no
  branch can commit it and no PR body can reach it, and in the *common* dir, so
  every worktree of one clone (auto-pilot's parallel lanes) shares one store.
  The resolver keys its record by issue number, the reviewer by PR number.
  Directory mode 0700, files 0600, written atomically (temp file + rename)
  under an flock on `<store>/.lock`; the last writer wins. Every path the
  script compares is canonicalized with `os.path.realpath` on both sides.

Modes (exactly one)
  --start  --skill S --number N   patch JSON on stdin. Replaces any record for
           S/N with a fresh one and deletes expired records. `step` defaults to
           the skill's first step.
  --write  --skill S --number N   patch JSON on stdin. Merges into the record;
           no record is exit 4.
  --read   --skill S --number N   prints {"status", "path", "age_s", "record",
           "binding"}. Never fails on record content: `absent`, `corrupt` and
           `expired` are answers, and only `ok` carries a record and a binding.
  --clear  --skill S --number N   removes the record. Idempotent; prints
           {"cleared": bool, "path"}.
  --list                          prints {"records": [{"skill", "number",
           "status", "step", "current", "age_s", "executor_match",
           "caller_run_id"}]}. Read-only; an absent store is {"records": []}.
  --read and --list never create the store.

Patch keys (a closed set — anything else is exit 3, and nothing is written)
  common    step, effect {kind, state: intent|done, key {sha, branch, pr}},
            pr, outcome, caller_run_id, resume (--write only)
  resolver  base, issue_updated_at, profile, analysis_reuse, worktree,
            research (opaque JSON object, <= 64 KiB), plan {selected {number,
            name, summary, files_to_modify[], files_to_create[], test_strategy,
            complexity, risk}, rejected[] <= 5 of {number, name,
            rejection_reason}, overall_complexity, overall_risk, sensitive}
            (<= 32 KiB), qa {cycle, ceiling, breach_reason, premise_ledger[]
            <= 20 of {kind: failure, ...}, open_findings[] <= 50},
            repro {status, test}. The ledger holds failures only: a premise
            revision lifts a block, so it is earned again in the session that
            relies on it, its diagnostics rerun, and never recorded
  reviewer  linked_issue, profile, prepass_head, cycle, findings {open[] <= 50,
            noted[] <= 50}, history[] <= 2 lists of finding signatures
  Effect kinds: resolver issue_edit, issue_close, push, pr_create, run_log;
  reviewer push, body_edit, merge. Nested objects are closed key sets too;
  `research` alone is opaque data, kept only to seed a verify-first research
  pass, and never read for a gate. Strings are capped (a summary at 2,000
  characters, a finding's text at 500) and the whole record at 256 KiB.

Forbidden keys (FORBIDDEN_KEYS: exit 3, nothing written)
  A record can never carry a fact that satisfies a gate: tests_state, tests,
  qa_handoff, review, receipt, marker, qa_clean, verdict, ci_sha, ci_status,
  verified_head, soft_pass. Nor can a caller claim what the script measures:
  head, branch, toplevel, executor, lane, completed, current, schema, skill,
  number, created_at, updated_at, run_started_at, resumed, resumed_at,
  base_sha, research_pin.

Measured by the script on every --start/--write, never taken from the caller
  head (`git rev-parse --verify HEAD`, null on an unborn branch), branch (the
  checked-out branch, `HEAD` when detached; a name outside the branch grammar
  is exit 4), toplevel (realpath of `--show-toplevel`), executor {user, uid,
  host}, updated_at, base_sha (`refs/remotes/origin/<base>`) when `base` is
  sent, research_pin {base_sha, issue_updated_at} when `research` is sent, and
  lane {lane_id, event_id, base_sha, worktree_path} from IDD_LANE_ID,
  IDD_EVENT_ID, IDD_BASE_SHA and IDD_WORKTREE_PATH when IDD_CALLER_WORKTREE=1
  (the worktree path realpath'd, and it must be this checkout's toplevel).

Steps and transitions
  Resolver steps 0-5, reviewer steps 1-7, plus `closing`. The record keeps two:
  `step`, the high-water mark (the furthest step entered, never lowered), and
  `current`, the step entered by the last write. A patch's `step` is the step
  being entered now. A step at or below the mark is a re-walk and always legal
  (a resumed session re-runs the early steps, and the reviewer loops 6 -> 3).
  Above the mark, only the next step is legal, plus the reviewer's 1 -> 3 and
  3|4|5 -> 7; `closing` is legal from anywhere. `completed` grows on each
  forward edge. Monotone on every write, re-walks included: qa.cycle and the
  reviewer's cycle never decrease, qa.premise_ledger only grows (the stored
  list must stay its prefix), and profile only moves light -> full.

  `resume: true` marks a resumed session: `resumed` counts up, `resumed_at` is
  stamped, and caller_run_id is replaced by the patch's value (null when the
  patch omits it), because it names whoever holds the record now.

Binding (--read, measured live against git from the current directory)
  executor_match; workspace — `here` (this toplevel and branch are the
  record's), `elsewhere` (the branch is checked out in another registered
  worktree, reported as worktree_path), `branch_only` (the branch exists but
  is checked out nowhere; measured on its tip, with this checkout as host), or
  `missing`; head_live and head_relation equal | descendant | other; dirty
  (`status --porcelain=v1 --untracked-files=all`, ignoring untracked entries
  under the machine-local `.idd/` and legacy `.gitissue/` trees); lane_match
  (null outside a lane). `verdict` is `bound` or `stale` with `reasons[]`:
  another executor, a missing workspace, a head that is not equal or a
  descendant, a dirty `branch_only` host, a lane mismatch, or a moved head or
  dirty tree while the high-water mark `step` is not one that commits
  (resolver 3-5, reviewer 2 and 6) — `step`, never `current`, which a resumed
  session's re-walk lowers. Records not written for seven days read as
  `expired`.
  The GitHub half of the check is the skill's: this script never calls `gh`.

Exit codes
  0  answered — `--read` statuses and a `stale` verdict included. Read the
     JSON, never the exit status. This script never exits 1.
  2  usage error (a bad --skill or --number included)
  3  invalid patch — a forbidden or unknown key, a bad value, an illegal
     transition or a counter moving backwards. Nothing was written.
  4  cannot complete — not a git work tree, git missing, no record to --write,
     an unusable lane environment, no flock, an I/O error. Nothing was written.
     Degrade: the skill stops writing for this run and carries on.

Authored at src/shared/scripts/gi-progress.py — do not edit installed copies;
edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import getpass
import json
import os
import re
import socket
import stat
import subprocess
import sys
import tempfile

try:
    import fcntl
except ImportError:  # pragma: no cover - non-POSIX hosts degrade at runtime
    fcntl = None

SCHEMA = 1
SKILLS = ("issue-resolver", "issue-pr-review")
TTL_S = 7 * 24 * 3600
RECORD_MAX = 256 * 1024
RESEARCH_MAX = 64 * 1024
PLAN_MAX = 32 * 1024
LEDGER_ENTRY_MAX = 8 * 1024
SUMMARY_MAX = 2000
TEXT_MAX = 500
STRATEGY_MAX = 4000

# Every pattern ends in `\Z`, never `$`, which would accept a trailing newline.
# The screens are gi-state.py's, kept in step with it.
RUN_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}\Z")
BRANCH_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,200}\Z")
LANE_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}\Z")
SHA_RE = re.compile(r"^[0-9a-f]{40}\Z")
TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\Z")
WORD_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_-]{0,31}\Z")
NAME_RE = re.compile(r"^(issue-resolver|issue-pr-review)-([1-9][0-9]{0,9})\.json\Z")

CLOSING = "closing"
STEPS = {
    "issue-resolver": (0, 1, 2, 3, 4, 5),
    "issue-pr-review": (1, 2, 3, 4, 5, 6, 7),
}
# Forward edges of the high-water mark. Anything at or below the mark is a
# re-walk, and `closing` is reachable from every step.
FORWARD = {
    "issue-resolver": {0: {1}, 1: {2}, 2: {3}, 3: {4}, 4: {5}, 5: set()},
    "issue-pr-review": {1: {2, 3}, 2: {3}, 3: {4, 7}, 4: {5, 7}, 5: {6, 7},
                        6: {7}, 7: set()},
}
# Steps that commit: only there may a resume find a moved head or a dirty tree.
COMMIT_STEPS = {"issue-resolver": {3, 4, 5}, "issue-pr-review": {2, 6}}
EFFECT_KINDS = {
    "issue-resolver": {"issue_edit", "issue_close", "push", "pr_create", "run_log"},
    "issue-pr-review": {"push", "body_edit", "merge"},
}
PROFILES = ("light", "full")
COMMON_KEYS = frozenset({"step", "effect", "pr", "outcome", "caller_run_id", "resume"})
SKILL_KEYS = {
    "issue-resolver": frozenset({"base", "issue_updated_at", "profile", "analysis_reuse",
                                 "worktree", "research", "plan", "qa", "repro"}),
    "issue-pr-review": frozenset({"linked_issue", "profile", "prepass_head", "cycle",
                                  "findings", "history"}),
}
# A record can never carry a fact that satisfies a gate, and a caller can never
# claim a fact the script measures. Both are refused by name at exit 3.
FORBIDDEN_KEYS = frozenset({
    "tests_state", "tests", "qa_handoff", "review", "receipt", "marker",
    "qa_clean", "verdict", "ci_sha", "ci_status", "verified_head", "soft_pass",
    "head", "branch", "toplevel", "executor", "lane", "completed", "current",
    "schema", "skill", "number", "created_at", "updated_at", "run_started_at",
    "resumed", "resumed_at", "base_sha", "research_pin",
})
MEASURED_KEYS = ("schema", "skill", "number", "step", "current", "completed",
                 "head", "branch", "toplevel", "executor", "lane", "created_at",
                 "run_started_at", "updated_at", "resumed", "resumed_at",
                 "caller_run_id")
LEGACY_LOCAL = (".idd/", ".gitissue/")


class InvalidInput(Exception):
    """Exit 3."""


class CannotComplete(Exception):
    """Exit 4."""


# --- git and the store -------------------------------------------------------


def _git(*args: str, cwd: str | None = None, check: bool = True) -> subprocess.CompletedProcess:
    cmd = ["git"] + (["-C", cwd] if cwd else []) + list(args)
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    except OSError as exc:  # git not installed
        raise CannotComplete(f"git unavailable: {exc}") from exc
    if check and proc.returncode != 0:
        raise CannotComplete(
            f"git {' '.join(args)} failed: {proc.stderr.strip() or proc.returncode}"
        )
    return proc


def store_dir() -> str:
    """Physical `<git common dir>/idd/progress`, shared by every worktree."""
    raw = _git("rev-parse", "--git-common-dir").stdout.strip()
    if not raw:
        raise CannotComplete("no git common dir")
    return os.path.join(os.path.realpath(raw), "idd", "progress")


def toplevel() -> str:
    raw = _git("rev-parse", "--show-toplevel").stdout.strip()
    if not raw:
        raise CannotComplete("not inside a work tree")
    return os.path.realpath(raw)


def current_branch(cwd: str | None = None) -> str:
    proc = _git("symbolic-ref", "--quiet", "--short", "HEAD", cwd=cwd, check=False)
    name = proc.stdout.strip()
    return name if proc.returncode == 0 and name else "HEAD"


def rev(ref: str, cwd: str | None = None) -> str | None:
    proc = _git("rev-parse", "--verify", "--quiet", ref + "^{commit}", cwd=cwd, check=False)
    sha = proc.stdout.strip()
    return sha if proc.returncode == 0 and SHA_RE.match(sha) else None


def worktrees() -> list[tuple[str, str | None]]:
    """(realpath, branch or None) for every registered worktree."""
    out, path = [], None
    for line in _git("worktree", "list", "--porcelain").stdout.splitlines():
        if line.startswith("worktree "):
            path = os.path.realpath(line[len("worktree "):])
            out.append((path, None))
        elif line.startswith("branch refs/heads/") and out:
            out[-1] = (out[-1][0], line[len("branch refs/heads/"):])
    return out


def is_dirty(path: str) -> bool | None:
    """Commit-relevant changes, ignoring untracked machine-local IDD trees.

    None when the status cannot be read (a pruned worktree, say): unknown is
    never reported as clean.
    """
    proc = _git("status", "--porcelain=v1", "-z", "--untracked-files=all", cwd=path,
                check=False)
    if proc.returncode != 0:
        return None
    entries = proc.stdout.split("\0")
    i = 0
    while i < len(entries):
        entry = entries[i]
        i += 1
        if len(entry) < 4:
            continue
        code, name = entry[:2], entry[3:]
        if code[0] in "RC":
            i += 1  # a rename or copy carries its source path as the next entry
        if code == "??" and name.startswith(LEGACY_LOCAL):
            continue
        return True
    return False


def executor() -> dict:
    uid = os.getuid() if hasattr(os, "getuid") else None
    try:
        user = getpass.getuser()
    except Exception:  # noqa: BLE001 — no login name in this environment
        user = None
    return {"user": user, "uid": uid, "host": socket.gethostname()}


def _now() -> _dt.datetime:
    return _dt.datetime.now(_dt.timezone.utc).replace(microsecond=0)


def _stamp(when: _dt.datetime) -> str:
    return when.strftime("%Y-%m-%dT%H:%M:%SZ")


def _age_s(stamp: object) -> int | None:
    if not isinstance(stamp, str) or not TS_RE.match(stamp):
        return None
    try:
        then = _dt.datetime.strptime(stamp, "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=_dt.timezone.utc)
    except ValueError:
        return None
    return int((_now() - then).total_seconds())


class _StoreLock:
    """Exclusive flock on `<store>/.lock` for every read-modify-write."""

    def __init__(self, directory: str):
        self.directory = directory
        self.fd = None

    def __enter__(self):
        if fcntl is None:
            raise CannotComplete("advisory locking (fcntl) is unavailable on this host")
        try:
            os.makedirs(self.directory, mode=0o700, exist_ok=True)
            self.fd = os.open(os.path.join(self.directory, ".lock"),
                              os.O_RDWR | os.O_CREAT, 0o600)
            fcntl.flock(self.fd, fcntl.LOCK_EX)
        except OSError as exc:
            raise CannotComplete(f"could not lock the progress store: {exc}") from exc
        return self

    def __exit__(self, *exc):
        if self.fd is not None:
            try:
                fcntl.flock(self.fd, fcntl.LOCK_UN)
            finally:
                os.close(self.fd)
        return False


def _atomic_write(directory: str, target: str, record: dict) -> None:
    temp = None
    try:
        fd, temp = tempfile.mkstemp(prefix=".progress-", suffix=".tmp", dir=directory)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(record, fh, sort_keys=True, ensure_ascii=False)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(temp, target)
        temp = None
    except OSError as exc:
        raise CannotComplete(f"could not write the progress record: {exc}") from exc
    finally:
        if temp is not None and os.path.exists(temp):
            os.unlink(temp)


# --- patch validation --------------------------------------------------------


def _is_int(value, minimum: int = 0) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= minimum


def _text(value, limit: int, name: str, nullable: bool = False) -> None:
    if value is None and nullable:
        return
    if not isinstance(value, str) or len(value) > limit:
        raise InvalidInput(f"{name} must be a string of at most {limit} characters")


def _closed(value, keys, name: str) -> dict:
    if not isinstance(value, dict):
        raise InvalidInput(f"{name} must be a JSON object")
    for key in value:
        if key in FORBIDDEN_KEYS:
            raise InvalidInput(f"{name}.{key} is never recorded — a record cannot carry it")
        if key not in keys:
            raise InvalidInput(f"{name}.{key} is not a known key")
    return value


def _size(value, limit: int, name: str) -> None:
    if len(json.dumps(value, ensure_ascii=False).encode("utf-8")) > limit:
        raise InvalidInput(f"{name} is larger than {limit // 1024} KiB")


def _finding(item, name: str) -> None:
    if isinstance(item, str):
        _text(item, TEXT_MAX, name)
        return
    if not isinstance(item, dict) or len(item) > 12:
        raise InvalidInput(f"{name} must be a string or an object of at most 12 fields")
    for key, value in item.items():
        if not WORD_RE.match(str(key)):
            raise InvalidInput(f"{name} has a malformed field name")
        if key in FORBIDDEN_KEYS:
            raise InvalidInput(f"{name}.{key} is never recorded — a record cannot carry it")
        if isinstance(value, str):
            _text(value, TEXT_MAX, f"{name}.{key}")
        elif value is not None and not isinstance(value, (int, float, bool)):
            raise InvalidInput(f"{name}.{key} must be a scalar")


def _findings(items, limit: int, name: str) -> None:
    if not isinstance(items, list) or len(items) > limit:
        raise InvalidInput(f"{name} must be a list of at most {limit} findings")
    for n, item in enumerate(items):
        _finding(item, f"{name}[{n}]")


def _step(value, skill: str, name: str = "step") -> None:
    if value != CLOSING and (not _is_int(value) or value not in STEPS[skill]):
        raise InvalidInput(f"{name} must be one of {list(STEPS[skill])} or 'closing'")


def _branch(value, name: str) -> None:
    if not isinstance(value, str) or not BRANCH_RE.match(value):
        raise InvalidInput(f"{name} is not a branch name the naming convention allows")


def _sha(value, name: str) -> None:
    if not isinstance(value, str) or not SHA_RE.match(value):
        raise InvalidInput(f"{name} must be 40 lowercase hex characters")


def _effect(value, skill: str) -> None:
    _closed(value, {"kind", "state", "key"}, "effect")
    if value.get("kind") not in EFFECT_KINDS[skill]:
        raise InvalidInput(f"effect.kind must be one of {sorted(EFFECT_KINDS[skill])}")
    if value.get("state") not in ("intent", "done"):
        raise InvalidInput("effect.state must be 'intent' or 'done'")
    key = value.get("key", {})
    _closed(key, {"sha", "branch", "pr"}, "effect.key")
    if "sha" in key:
        _sha(key["sha"], "effect.key.sha")
    if "branch" in key:
        _branch(key["branch"], "effect.key.branch")
    if "pr" in key and not _is_int(key["pr"], 1):
        raise InvalidInput("effect.key.pr must be an integer >= 1")


def _plan(value) -> None:
    _closed(value, {"selected", "rejected", "overall_complexity", "overall_risk",
                    "sensitive"}, "plan")
    selected = value.get("selected")
    if selected is not None:
        _closed(selected, {"number", "name", "summary", "files_to_modify",
                           "files_to_create", "test_strategy", "complexity", "risk"},
                "plan.selected")
        if "number" in selected and not _is_int(selected["number"], 1):
            raise InvalidInput("plan.selected.number must be an integer >= 1")
        _text(selected.get("name", ""), 200, "plan.selected.name")
        _text(selected.get("summary", ""), SUMMARY_MAX, "plan.selected.summary")
        _text(selected.get("test_strategy", ""), STRATEGY_MAX, "plan.selected.test_strategy")
        for key in ("complexity", "risk"):
            _text(selected.get(key, ""), 32, f"plan.selected.{key}")
        for key in ("files_to_modify", "files_to_create"):
            paths = selected.get(key, [])
            if not isinstance(paths, list) or len(paths) > 200:
                raise InvalidInput(f"plan.selected.{key} must be a list of at most 200 paths")
            for path in paths:
                _text(path, TEXT_MAX, f"plan.selected.{key}[]")
    rejected = value.get("rejected", [])
    if not isinstance(rejected, list) or len(rejected) > 5:
        raise InvalidInput("plan.rejected must be a list of at most 5 options")
    for n, option in enumerate(rejected):
        _closed(option, {"number", "name", "rejection_reason"}, f"plan.rejected[{n}]")
        if "number" in option and not _is_int(option["number"], 1):
            raise InvalidInput(f"plan.rejected[{n}].number must be an integer >= 1")
        _text(option.get("name", ""), 200, f"plan.rejected[{n}].name")
        _text(option.get("rejection_reason", ""), TEXT_MAX, f"plan.rejected[{n}].rejection_reason")
    if value.get("overall_complexity", "M") not in ("XS", "S", "M", "L", "XL"):
        raise InvalidInput("plan.overall_complexity must be XS, S, M, L or XL")
    if value.get("overall_risk", "Low") not in ("Low", "Medium", "High"):
        raise InvalidInput("plan.overall_risk must be Low, Medium or High")
    if not isinstance(value.get("sensitive", False), bool):
        raise InvalidInput("plan.sensitive must be a boolean")
    _size(value, PLAN_MAX, "plan")


def _qa(value) -> None:
    _closed(value, {"cycle", "ceiling", "breach_reason", "premise_ledger",
                    "open_findings"}, "qa")
    if "cycle" in value and not _is_int(value["cycle"]):
        raise InvalidInput("qa.cycle must be an integer >= 0")
    if value.get("ceiling") is not None and not _is_int(value["ceiling"]):
        raise InvalidInput("qa.ceiling must be an integer >= 0 or null")
    _text(value.get("breach_reason"), TEXT_MAX, "qa.breach_reason", nullable=True)
    ledger = value.get("premise_ledger", [])
    if not isinstance(ledger, list) or len(ledger) > 20:
        raise InvalidInput("qa.premise_ledger must be a list of at most 20 entries")
    for n, entry in enumerate(ledger):
        if not isinstance(entry, dict) or entry.get("kind") != "failure":
            raise InvalidInput(f"qa.premise_ledger[{n}] must be an object with kind failure — "
                               "a revision is earned in its own session, never recorded")
        _size(entry, LEDGER_ENTRY_MAX, f"qa.premise_ledger[{n}]")
    _findings(value.get("open_findings", []), 50, "qa.open_findings")


def validate_patch(patch, skill: str, mode: str) -> dict:
    """Check a patch's shape before anything touches the disk."""
    if not isinstance(patch, dict):
        raise InvalidInput("the patch must be a JSON object")
    allowed = COMMON_KEYS | SKILL_KEYS[skill]
    for key in patch:
        if key in FORBIDDEN_KEYS:
            raise InvalidInput(f"{key} is never recorded — a record cannot carry it")
        if key not in allowed:
            raise InvalidInput(f"{key} is not a known {skill} key")
    if "resume" in patch:
        if mode != "write":
            raise InvalidInput("resume is a --write key")
        if not isinstance(patch["resume"], bool):
            raise InvalidInput("resume must be a boolean")
    if "step" in patch:
        _step(patch["step"], skill)
    if "effect" in patch:
        _effect(patch["effect"], skill)
    if patch.get("pr") is not None and not _is_int(patch["pr"], 1):
        raise InvalidInput("pr must be an integer >= 1 or null")
    if patch.get("outcome") is not None and not (
            isinstance(patch["outcome"], str) and WORD_RE.match(patch["outcome"])):
        raise InvalidInput("outcome must be a short identifier or null")
    if patch.get("caller_run_id") is not None and not (
            isinstance(patch["caller_run_id"], str) and RUN_ID_RE.match(patch["caller_run_id"])):
        raise InvalidInput("caller_run_id is not a run id")
    if "profile" in patch and patch["profile"] not in PROFILES:
        raise InvalidInput("profile must be 'light' or 'full'")
    if skill == "issue-resolver":
        if "base" in patch:
            _branch(patch["base"], "base")
        if "issue_updated_at" in patch and not (
                isinstance(patch["issue_updated_at"], str) and TS_RE.match(patch["issue_updated_at"])):
            raise InvalidInput("issue_updated_at must be YYYY-MM-DDTHH:MM:SSZ")
        if "analysis_reuse" in patch and patch["analysis_reuse"] not in ("fresh", "stale", "absent"):
            raise InvalidInput("analysis_reuse must be fresh, stale or absent")
        if "worktree" in patch and not isinstance(patch["worktree"], bool):
            raise InvalidInput("worktree must be a boolean")
        if "research" in patch:
            if not isinstance(patch["research"], dict):
                raise InvalidInput("research must be a JSON object")
            _size(patch["research"], RESEARCH_MAX, "research")
        if "plan" in patch:
            _plan(patch["plan"])
        if "qa" in patch:
            _qa(patch["qa"])
        if "repro" in patch:
            _closed(patch["repro"], {"status", "test"}, "repro")
            status = patch["repro"].get("status")
            if status is not None and not (isinstance(status, str) and WORD_RE.match(status)):
                raise InvalidInput("repro.status must be a short identifier")
            _text(patch["repro"].get("test"), TEXT_MAX, "repro.test", nullable=True)
    else:
        if patch.get("linked_issue") is not None and not _is_int(patch["linked_issue"], 1):
            raise InvalidInput("linked_issue must be an integer >= 1 or null")
        if patch.get("prepass_head") is not None:
            _sha(patch["prepass_head"], "prepass_head")
        if "cycle" in patch and not _is_int(patch["cycle"]):
            raise InvalidInput("cycle must be an integer >= 0")
        if "findings" in patch:
            _closed(patch["findings"], {"open", "noted"}, "findings")
            for key in ("open", "noted"):
                _findings(patch["findings"].get(key, []), 50, f"findings.{key}")
        if "history" in patch:
            history = patch["history"]
            if not isinstance(history, list) or len(history) > 2:
                raise InvalidInput("history must be a list of at most 2 cycles")
            for n, cycle in enumerate(history):
                if not isinstance(cycle, list) or len(cycle) > 50:
                    raise InvalidInput(f"history[{n}] must be a list of at most 50 signatures")
                for sig in cycle:
                    _text(sig, TEXT_MAX, f"history[{n}][]")
    return patch


# --- measuring and merging ---------------------------------------------------


def lane_from_env(strict: bool) -> dict | None:
    """The caller-managed lane identity, or None outside a lane."""
    if os.environ.get("IDD_CALLER_WORKTREE") != "1":
        return None
    lane_id = os.environ.get("IDD_LANE_ID", "")
    event_id = os.environ.get("IDD_EVENT_ID", "")
    base_sha = os.environ.get("IDD_BASE_SHA", "")
    path = os.environ.get("IDD_WORKTREE_PATH", "")
    ok = (LANE_ID_RE.match(lane_id) and LANE_ID_RE.match(event_id)
          and SHA_RE.match(base_sha) and os.path.isabs(path))
    if not ok:
        if strict:
            raise CannotComplete("IDD_CALLER_WORKTREE=1 but the lane environment is incomplete or malformed")
        return {"invalid": True}
    return {"lane_id": lane_id, "event_id": event_id, "base_sha": base_sha,
            "worktree_path": os.path.realpath(path)}


def measure() -> dict:
    top = toplevel()
    branch = current_branch()
    if branch != "HEAD" and not BRANCH_RE.match(branch):
        raise CannotComplete("the checked-out branch name is outside the branch grammar")
    lane = lane_from_env(strict=True)
    if lane is not None and lane["worktree_path"] != top:
        raise CannotComplete("IDD_WORKTREE_PATH is not this checkout's toplevel")
    return {"head": rev("HEAD"), "branch": branch, "toplevel": top,
            "executor": executor(), "lane": lane}


def _rank(step) -> int:
    return 100 if step == CLOSING else int(step)


def _advance(record: dict, new, skill: str) -> None:
    mark = record["step"]
    record["current"] = new
    if _rank(new) <= _rank(mark):
        return  # a re-walk: legal, the mark never moves down
    if new != CLOSING and new not in FORWARD[skill].get(mark, set()):
        raise InvalidInput(f"illegal transition: step {mark} -> {new}")
    if mark not in record["completed"] and mark != CLOSING:
        record["completed"].append(mark)
    record["step"] = new


def _merge(record: dict, patch: dict, skill: str, measured: dict, now: str,
           mode: str) -> dict:
    out = json.loads(json.dumps(record))  # deep copy; the original stays intact
    if mode == "start":
        out["step"] = out["current"] = patch.get("step", STEPS[skill][0])
    elif "step" in patch:
        _advance(out, patch["step"], skill)
    for key, value in patch.items():
        if key in ("step", "resume", "caller_run_id"):
            continue
        if key == "qa":
            old = out.get("qa") or {}
            new = {**old, **value}
            if _is_int(old.get("cycle")) and new.get("cycle", 0) < old["cycle"]:
                raise InvalidInput(f"qa.cycle cannot decrease ({old['cycle']} -> {new.get('cycle')})")
            old_ledger = old.get("premise_ledger") or []
            new_ledger = new.get("premise_ledger") or []
            if new_ledger[:len(old_ledger)] != old_ledger:
                raise InvalidInput("qa.premise_ledger may only grow — the stored ledger must stay its prefix")
            out["qa"] = new
        elif key == "findings":
            out["findings"] = {**(out.get("findings") or {}), **value}
        elif key == "profile":
            if out.get("profile") == "full" and value == "light":
                raise InvalidInput("profile may only move light -> full")
            out["profile"] = value
        elif key == "cycle":
            if _is_int(out.get("cycle")) and value < out["cycle"]:
                raise InvalidInput(f"cycle cannot decrease ({out['cycle']} -> {value})")
            out["cycle"] = value
        else:
            out[key] = value
    if "base" in patch:
        out["base_sha"] = rev(f"refs/remotes/origin/{patch['base']}")
    if "research" in patch:
        out["research_pin"] = {"base_sha": out.get("base_sha"),
                               "issue_updated_at": out.get("issue_updated_at")}
    if mode == "start":
        out["caller_run_id"] = patch.get("caller_run_id")
    elif patch.get("resume") is True:
        out["caller_run_id"] = patch.get("caller_run_id")
        out["resumed"] = out.get("resumed", 0) + 1
        out["resumed_at"] = now
    elif "caller_run_id" in patch and patch["caller_run_id"] != out.get("caller_run_id"):
        raise InvalidInput("caller_run_id changes only on --start or a resume: true write")
    out.update(measured)
    out["updated_at"] = now
    if len(json.dumps(out, ensure_ascii=False).encode("utf-8")) > RECORD_MAX:
        raise InvalidInput(f"the record would exceed {RECORD_MAX // 1024} KiB")
    return out


def _blank(skill: str, number: int, now: str) -> dict:
    return {"schema": SCHEMA, "skill": skill, "number": number,
            "step": STEPS[skill][0], "current": STEPS[skill][0], "completed": [],
            "created_at": now, "run_started_at": now, "resumed": 0,
            "resumed_at": None, "caller_run_id": None}


# --- reading -----------------------------------------------------------------


def screen(record, skill: str, number: int) -> str | None:
    """None when the record is usable, else why it is corrupt."""
    if not isinstance(record, dict):
        return "not a JSON object"
    if record.get("schema") != SCHEMA:
        return "unknown schema"
    if record.get("skill") != skill or record.get("number") != number:
        return "names a different skill or number"
    content = {k: v for k, v in record.items()
               if k not in MEASURED_KEYS and k not in ("base_sha", "research_pin")}
    try:
        validate_patch(content, skill, "start")
        _step(record.get("step"), skill, "step")
        _step(record.get("current"), skill, "current")
        if record.get("base_sha") is not None:
            _sha(record["base_sha"], "base_sha")
        pin = record.get("research_pin")
        if pin is not None:
            # Read back into git commands by step 0j: null or exactly the shape
            # the script measures, each field screened, or the record is corrupt.
            if not isinstance(pin, dict) or set(pin) != {"base_sha", "issue_updated_at"}:
                raise InvalidInput("research_pin must be null or {base_sha, issue_updated_at}")
            if pin["base_sha"] is not None:
                _sha(pin["base_sha"], "research_pin.base_sha")
            if pin["issue_updated_at"] is not None and not (
                    isinstance(pin["issue_updated_at"], str) and TS_RE.match(pin["issue_updated_at"])):
                raise InvalidInput("research_pin.issue_updated_at must be YYYY-MM-DDTHH:MM:SSZ")
        if record.get("caller_run_id") is not None and not (
                isinstance(record["caller_run_id"], str) and RUN_ID_RE.match(record["caller_run_id"])):
            raise InvalidInput("caller_run_id")
    except InvalidInput as exc:
        return f"failed a screen: {exc}"
    branch = record.get("branch")
    if not isinstance(branch, str) or not (branch == "HEAD" or BRANCH_RE.match(branch)):
        return "branch failed its screen"
    if record.get("head") is not None and not (isinstance(record["head"], str) and SHA_RE.match(record["head"])):
        return "head is not a full SHA"
    if not isinstance(record.get("toplevel"), str) or not os.path.isabs(record["toplevel"]):
        return "toplevel is not an absolute path"
    if not isinstance(record.get("executor"), dict):
        return "no executor identity"
    if not isinstance(record.get("completed"), list):
        return "completed is not a list"
    lane = record.get("lane")
    if lane is not None and not (
            isinstance(lane, dict) and set(lane) == {"lane_id", "event_id", "base_sha", "worktree_path"}):
        return "malformed lane identity"
    if _age_s(record.get("updated_at")) is None:
        return "updated_at is not a timestamp"
    return None


def load(path: str, skill: str, number: int) -> tuple[str, dict | None, str | None]:
    """(status, record, reason) — status is ok | absent | corrupt | expired."""
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        return "absent", None, None
    except OSError as exc:
        raise CannotComplete(f"could not stat the record: {exc}") from exc
    if not stat.S_ISREG(st.st_mode):
        return "corrupt", None, "not a regular file"
    try:
        with open(path, encoding="utf-8") as fh:
            record = json.load(fh)
    except (OSError, ValueError):
        return "corrupt", None, "unreadable or not JSON"
    reason = screen(record, skill, number)
    if reason:
        return "corrupt", None, reason
    if _age_s(record["updated_at"]) > TTL_S:
        return "expired", None, "not written for seven days"
    return "ok", record, None


def binding(record: dict, skill: str) -> dict:
    here = executor()
    who = record["executor"]
    executor_match = all(who.get(k) == here[k] for k in ("user", "uid", "host"))
    top = toplevel()
    branch = record["branch"]
    holders = [p for p, b in worktrees() if branch != "HEAD" and b == branch]
    if record["toplevel"] == top and current_branch() == branch:
        workspace, path, head_live, host = "here", top, rev("HEAD"), top
    elif holders:
        path = top if top in holders else holders[0]
        workspace, head_live, host = "elsewhere", rev("HEAD", cwd=path), path
    elif branch != "HEAD" and rev(f"refs/heads/{branch}"):
        workspace, path, head_live, host = "branch_only", None, rev(f"refs/heads/{branch}"), top
    else:
        workspace, path, head_live, host = "missing", None, None, None

    relation = None
    if record.get("head") and head_live:
        if record["head"] == head_live:
            relation = "equal"
        elif _git("merge-base", "--is-ancestor", record["head"], head_live,
                  check=False).returncode == 0:
            relation = "descendant"
        else:
            relation = "other"
    dirty = is_dirty(host) if host else None

    env_lane = lane_from_env(strict=False)
    rec_lane = record.get("lane")
    if env_lane is None and rec_lane is None:
        lane_match = None
    else:
        lane_match = bool(env_lane and rec_lane and not env_lane.get("invalid")
                          and env_lane == rec_lane)

    reasons = []
    if not executor_match:
        reasons.append("executor")
    if workspace == "missing" or dirty is None:
        reasons.append("workspace")
    elif relation not in ("equal", "descendant"):
        reasons.append("head")
    if workspace == "branch_only" and dirty:
        reasons.append("dirty")
    if lane_match is False or (env_lane is not None and workspace != "here"):
        reasons.append("lane")
    moved = relation == "descendant" or (dirty and workspace != "branch_only")
    # The high-water mark, never `current`: a resumed session's re-walk writes
    # lower `current`, and a second kill must not turn a valid resume stale.
    if moved and record["step"] not in COMMIT_STEPS[skill]:
        reasons.append("moved")
    return {"verdict": "stale" if reasons else "bound", "reasons": reasons,
            "executor_match": executor_match, "workspace": workspace,
            "worktree_path": path, "branch_live": branch if workspace != "missing" else None,
            "head_live": head_live, "head_relation": relation, "dirty": dirty,
            "lane_match": lane_match}


# --- modes -------------------------------------------------------------------


def _read_patch() -> dict:
    buffer = getattr(sys.stdin, "buffer", None)
    raw = buffer.read() if buffer is not None else sys.stdin.read().encode()
    try:
        return json.loads(raw.decode("utf-8"))
    except UnicodeDecodeError as exc:
        raise InvalidInput(f"stdin is not UTF-8: {exc}") from exc
    except ValueError as exc:
        raise InvalidInput(f"stdin is not JSON: {exc}") from exc


def _sweep(directory: str) -> None:
    for name in os.listdir(directory):
        match = NAME_RE.match(name)
        path = os.path.join(directory, name)
        if not match or not os.path.isfile(path) or os.path.islink(path):
            continue
        try:
            with open(path, encoding="utf-8") as fh:
                age = _age_s(json.load(fh).get("updated_at"))
        except (OSError, ValueError, AttributeError):
            continue
        if age is not None and age > TTL_S:
            try:
                os.unlink(path)
            except OSError:
                pass


def start_or_write(skill: str, number: int, mode: str) -> dict:
    patch = validate_patch(_read_patch(), skill, mode)
    measured = measure()
    directory = store_dir()
    target = os.path.join(directory, f"{skill}-{number}.json")
    now = _stamp(_now())
    with _StoreLock(directory):
        if mode == "start":
            _sweep(directory)
            record = _merge(_blank(skill, number, now), patch, skill, measured, now, mode)
            replaced = os.path.lexists(target)
        else:
            status, current, reason = load(target, skill, number)
            if status == "absent":
                raise CannotComplete("no record to --write — run --start first")
            if status != "ok":
                raise CannotComplete(f"the record is {status} ({reason}) — run --start")
            record = _merge(current, patch, skill, measured, now, mode)
            replaced = True
        _atomic_write(directory, target, record)
    return {"written": True, "path": target, "replaced": replaced}


def read(skill: str, number: int) -> dict:
    path = os.path.join(store_dir(), f"{skill}-{number}.json")
    status, record, reason = load(path, skill, number)
    out = {"status": status, "path": path, "reason": reason, "age_s": None,
           "record": None, "binding": None}
    if status == "ok":
        out.update(age_s=_age_s(record["updated_at"]), record=record,
                   binding=binding(record, skill))
    return out


def clear(skill: str, number: int) -> dict:
    directory = store_dir()
    target = os.path.join(directory, f"{skill}-{number}.json")
    if not os.path.isdir(directory):
        return {"cleared": False, "path": target}
    with _StoreLock(directory):
        try:
            st = os.lstat(target)
        except FileNotFoundError:
            return {"cleared": False, "path": target}
        except OSError as exc:
            raise CannotComplete(f"could not stat the record: {exc}") from exc
        if stat.S_ISDIR(st.st_mode):
            raise CannotComplete("the record path is a directory")
        try:
            os.unlink(target)  # a symlink is removed itself, never followed
        except OSError as exc:
            raise CannotComplete(f"could not remove the record: {exc}") from exc
    return {"cleared": True, "path": target}


def list_records() -> dict:
    directory = store_dir()
    rows = []
    if os.path.isdir(directory):
        here = executor()
        for name in sorted(os.listdir(directory)):
            match = NAME_RE.match(name)
            if not match:
                continue
            skill, number = match.group(1), int(match.group(2))
            status, record, _ = load(os.path.join(directory, name), skill, number)
            row = {"skill": skill, "number": number, "status": status, "step": None,
                   "current": None, "age_s": None, "executor_match": None,
                   "caller_run_id": None}
            if record is not None:
                who = record["executor"]
                row.update(step=record["step"], current=record["current"],
                           age_s=_age_s(record["updated_at"]),
                           executor_match=all(who.get(k) == here[k] for k in ("user", "uid", "host")),
                           caller_run_id=record.get("caller_run_id"))
            rows.append(row)
    return {"records": rows}


def _number(text: str) -> int:
    if not re.fullmatch(r"[1-9][0-9]{0,9}", text or ""):
        raise argparse.ArgumentTypeError("must be a positive integer")
    return int(text)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-progress.py",
        description=(
            "Durable progress record for /issue-resolver and /issue-pr-review, so a "
            "killed run can resume. A record is a hint, never an authority."
        ),
        epilog=(
            "Examples: python3 gi-progress.py --write --skill issue-resolver --number 42 "
            "< .idd/cache/progress-patch.json ; python3 gi-progress.py --read "
            "--skill issue-pr-review --number 87 ; python3 gi-progress.py --list"
        ),
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--start", action="store_true", help="replace the record (patch on stdin)")
    mode.add_argument("--write", action="store_true", help="merge a patch into the record (stdin)")
    mode.add_argument("--read", action="store_true", help="print the record and its live binding")
    mode.add_argument("--clear", action="store_true", help="remove the record (idempotent)")
    mode.add_argument("--list", action="store_true", help="list every record in the store")
    parser.add_argument("--skill", choices=SKILLS, help="issue-resolver or issue-pr-review")
    parser.add_argument("--number", type=_number, help="issue number (resolver) or PR number (reviewer)")
    args = parser.parse_args(argv)
    if args.list and (args.skill or args.number):
        parser.error("--list takes no --skill or --number")
    if not args.list and (args.skill is None or args.number is None):
        parser.error("--skill and --number are required")

    try:
        if args.start or args.write:
            result = start_or_write(args.skill, args.number, "start" if args.start else "write")
        elif args.read:
            result = read(args.skill, args.number)
        elif args.clear:
            result = clear(args.skill, args.number)
        else:
            result = list_records()
    except InvalidInput as exc:
        print(f"✗ gi-progress: {exc}", file=sys.stderr)
        return 3
    except CannotComplete as exc:
        print(f"⚠ gi-progress: {exc}", file=sys.stderr)
        return 4
    except Exception as exc:  # noqa: BLE001 — an unexpected failure degrades, never exits 1
        print(f"⚠ gi-progress: unexpected failure: {exc}", file=sys.stderr)
        return 4
    try:
        print(json.dumps(result, sort_keys=True))
    except OSError:
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
