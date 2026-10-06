#!/usr/bin/env python3
"""Blinded real-agent promotion lane for IDD Stack skills (issue #517).

The hermetic lane (run_eval.sh) runs deterministic skill stand-ins and never a
model. This driver is the other half: it runs a real agent CLI against two
revisions of `skills/` — a baseline and a candidate — on held-out tasks graded
by private rubrics, and decides whether the candidate may be promoted.

It is opt-in and local only. It needs the model provider's network, so it is
not sandboxed, and it is NEVER run in CI: `run` refuses when CI or
GITHUB_ACTIONS is set, unless IDD_EVAL_AGENT=1 is set, and when EVAL_RECORD=1.

Subcommands
  lock    --task-id ID
          Validate a task and its rubric and commit their digests to the lock
          file. Commit the lock before running: a run refuses a task whose task
          or rubric digest no longer matches it.
  run     --task-id ID --baseline REF --candidate REF --agent-config FILE
          [--runs N] [--seed INT] [--timeout SECONDS]
          Refusals, clean-tree + lock checks, pre-run leak checks, N shuffled
          runs per arm, post-run leak checks, objective checks (grade.py),
          blind packets, a sealed arm key and provenance.json.
  verdict --run-dir D --scores FILE
          Unseal the key against blind scores and record the verdict:
          invalid (any leak) | insufficient (runs < min_runs) | reject
          (candidate below baseline) | promote | hold.
  verify  --run-dir D
          Re-hash every artifact provenance.json lists.

Shared options: --repo (default: this file's repo), --store (default:
$IDD_PROMOTION_STORE, else <repo>/evals/promotion/private, gitignored),
--lock (default: <repo>/evals/promotion/lock.json). Each subcommand prints one
JSON object on stdout; human ✓/✗/⚠ lines go to stderr.

Exit codes: 0 ok (an agent exiting non-zero is data, not a failure) · 2 usage
error or refused (CI, no opt-in, EVAL_RECORD) · 3 invalid input (bad shapes,
unlocked or changed task/rubric, unknown ref, pre-run leak) · 4 cannot complete
(dirty tree, agent command cannot start, I/O). Never 1.

Store layout (private — never committed)
  <store>/tasks/<task-id>/task.json        {"version": 1, "id", "skill",
                                            "prompt", "min_runs": >=1 (3)}
  <store>/tasks/<task-id>/cassettes.json   optional gh replay cassettes
  <store>/tasks/<task-id>/fixture_repo/    optional agent workspace seed
  <store>/rubrics/<task-id>.json           {"version": 1, "task_id",
                                            "canary": str >= 16 chars,
                                            "criteria": [{"id", "text"}, ...],
                                            "checks": [grade.py assertions],
                                            "pass_threshold": 0..1 (1.0),
                                            "min_pass_rate": 0..1 (0.5)}
  <store>/runs/<run-id>/                   one `run`: raw/, checks/, blind/,
                                           sealed/, provenance.json

The agent itself works under a throwaway `idd-agent-*` staging root in the
system temp dir, outside the store and the repo, so the private rubrics are
not a few `..` above its cwd. Each run is copied into raw/ afterwards.

Agent config (JSON): {"command": [argv; placeholders {prompt_file}
{workspace} {skills_dir} {out_dir}], "model", "cli", "cli_version",
"tools": [...], "pass_env": [env var names], "notes"?}. The agent gets an
isolated HOME and gh config, a PATH-fronted gh_shim (cassette replay), and only
the pass_env variables from the caller's environment — never a GitHub token.
The command must emit the full session (tool calls included) on stdout or
stderr: leak detection and grading see nothing else.

Stdlib only.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import getpass
import hashlib
import json
import os
import random
import re
import secrets
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

TASK_ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
CRITERION_ID_RE = re.compile(r"^[a-z0-9-]+$")
ENV_NAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
PLACEHOLDER_RE = re.compile(r"\{([A-Za-z_][A-Za-z0-9_]*)\}")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
WORD_RE = re.compile(r"[a-z0-9]+")
SHINGLE = 8
PLACEHOLDERS = ("prompt_file", "workspace", "skills_dir", "out_dir")
FORBIDDEN_ENV = {
    "GH_TOKEN",
    "GITHUB_TOKEN",
    "GH_ENTERPRISE_TOKEN",
    "GITHUB_ENTERPRISE_TOKEN",
    "EVAL_RECORD",
}
FORBIDDEN_ENV_PREFIXES = ("EVAL_", "IDD_")
# Variables the driver sets itself; passing them through would bypass the
# isolated HOME, gh config or the PATH-fronted shim.
MANAGED_ENV = {"HOME", "PATH", "LANG", "GH_CONFIG_DIR", "GH_PROMPT_DISABLED"}
HARNESS_FILES = (
    "evals/harness/agent_eval.py",
    "evals/harness/gh_shim.py",
    "evals/harness/grade.py",
)
ARMS = ("baseline", "candidate")
EMPTY_CASSETTES = '{"version": 1, "calls": []}\n'


class Fail(Exception):
    """A stop with an exit code and an optional JSON report."""

    def __init__(self, code: int, message: str, report: dict | None = None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.report = report or {}


def _say(symbol: str, msg: str) -> None:
    print(f"{symbol} {msg}", file=sys.stderr)


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _now(fmt: str) -> str:
    return _dt.datetime.now(_dt.timezone.utc).strftime(fmt)


def _dump(obj: Any) -> str:
    return json.dumps(obj, sort_keys=True, indent=2, ensure_ascii=False) + "\n"


def _atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _load_json(path: Path, what: str) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise Fail(3, f"{what} not found: {path}") from exc
    except (OSError, UnicodeDecodeError, ValueError) as exc:
        raise Fail(3, f"{what} is not valid JSON: {path} ({exc})") from exc


def _git(repo: Path, *args: str) -> str:
    proc = subprocess.run(
        ["git", "-C", str(repo), *args], capture_output=True, text=True
    )
    if proc.returncode != 0:
        raise subprocess.CalledProcessError(
            proc.returncode, args, proc.stdout, proc.stderr
        )
    return proc.stdout.strip()


def _executor() -> dict:
    uid = os.getuid() if hasattr(os, "getuid") else None
    try:
        user = getpass.getuser()
    except Exception:  # noqa: BLE001 — no login name in this environment
        user = None
    return {"user": user, "uid": uid, "host": socket.gethostname()}


def _words(text: str) -> list[str]:
    return WORD_RE.findall(text.lower())


def _shingles(words: list[str]) -> set[tuple[str, ...]]:
    return {tuple(words[i : i + SHINGLE]) for i in range(len(words) - SHINGLE + 1)}


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _nonempty_str(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _regular_files(root: Path) -> list[Path]:
    """Regular files under root, never following symlinks, sorted."""
    found: list[Path] = []
    for dirpath, _dirnames, filenames in os.walk(root, followlinks=False):
        for name in filenames:
            path = Path(dirpath) / name
            if path.is_file() and not path.is_symlink():
                found.append(path)
    return sorted(found)


# ─── Store: tasks, rubrics, digests ────────────────────────────


def _task_dir(store: Path, task_id: str) -> Path:
    if not TASK_ID_RE.match(task_id or ""):
        raise Fail(3, f"invalid task id {task_id!r} (want lowercase-hyphen)")
    return store / "tasks" / task_id


def load_task(store: Path, task_id: str) -> tuple[dict, Path]:
    task_dir = _task_dir(store, task_id)
    if not task_dir.is_dir() or task_dir.is_symlink():
        raise Fail(3, f"task directory not found: {task_dir}")
    task = _load_json(task_dir / "task.json", "task.json")
    if not isinstance(task, dict) or task.get("version") != 1:
        raise Fail(3, "task.json must be an object with version 1")
    if task.get("id") != task_id:
        raise Fail(3, f"task.json id {task.get('id')!r} != directory {task_id!r}")
    if not _nonempty_str(task.get("skill")):
        raise Fail(3, "task.json skill must be a non-empty string")
    if not _nonempty_str(task.get("prompt")):
        raise Fail(3, "task.json prompt must be a non-empty string")
    min_runs = task.get("min_runs", 3)
    if type(min_runs) is not int or min_runs < 1:
        raise Fail(3, "task.json min_runs must be an integer >= 1")
    task["min_runs"] = min_runs
    return task, task_dir


def task_digest(task_dir: Path) -> str:
    """sha256 over (relpath, file sha256) of every file, sorted by relpath."""
    entries: list[tuple[str, str]] = []
    for dirpath, dirnames, filenames in os.walk(task_dir, followlinks=False):
        for name in dirnames + filenames:
            path = Path(dirpath) / name
            if path.is_symlink():
                raise Fail(3, f"symlink in task directory: {path}")
        for name in filenames:
            path = Path(dirpath) / name
            if not path.is_file():
                raise Fail(3, f"non-regular file in task directory: {path}")
            rel = path.relative_to(task_dir).as_posix()
            entries.append((rel, _sha256_file(path)))
    h = hashlib.sha256()
    for rel, digest in sorted(entries):
        h.update(f"{rel}\0{digest}\n".encode("utf-8"))
    return h.hexdigest()


def load_rubric(store: Path, task_id: str) -> tuple[dict, Path]:
    path = store / "rubrics" / f"{task_id}.json"
    rubric = _load_json(path, "rubric")
    if not isinstance(rubric, dict) or rubric.get("version") != 1:
        raise Fail(3, "rubric must be an object with version 1")
    if rubric.get("task_id") != task_id:
        raise Fail(3, f"rubric task_id {rubric.get('task_id')!r} != {task_id!r}")
    canary = rubric.get("canary")
    if not isinstance(canary, str) or len(canary) < 16:
        raise Fail(3, "rubric canary must be a string of at least 16 characters")
    criteria = rubric.get("criteria")
    if not isinstance(criteria, list) or not criteria:
        raise Fail(3, "rubric criteria must be a non-empty list")
    seen: set[str] = set()
    for item in criteria:
        if not isinstance(item, dict):
            raise Fail(3, "each rubric criterion must be an object")
        cid = item.get("id")
        if not isinstance(cid, str) or not CRITERION_ID_RE.match(cid):
            raise Fail(3, f"invalid criterion id {cid!r}")
        if cid in seen:
            raise Fail(3, f"duplicate criterion id {cid!r}")
        seen.add(cid)
        if not _nonempty_str(item.get("text")):
            raise Fail(3, f"criterion {cid!r} text must be non-empty")
    checks = rubric.get("checks", [])
    if not isinstance(checks, list) or not all(isinstance(c, dict) for c in checks):
        raise Fail(3, "rubric checks must be a list of grade.py assertion objects")
    rubric["checks"] = checks
    for key, default in (("pass_threshold", 1.0), ("min_pass_rate", 0.5)):
        value = rubric.get(key, default)
        if not _is_number(value) or not 0 <= value <= 1:
            raise Fail(3, f"rubric {key} must be a number in 0..1")
        rubric[key] = float(value)
    return rubric, path


# ─── lock ──────────────────────────────────────────────────────


def _read_lock(lock_path: Path, *, must_exist: bool) -> dict:
    if not lock_path.exists() and not must_exist:
        return {"version": 1, "tasks": {}}
    lock = _load_json(lock_path, "lock file")
    if (
        not isinstance(lock, dict)
        or lock.get("version") != 1
        or not isinstance(lock.get("tasks"), dict)
    ):
        raise Fail(3, f"lock file must be {{'version': 1, 'tasks': {{}}}}: {lock_path}")
    return lock


def cmd_lock(args: argparse.Namespace) -> dict:
    task, task_dir = load_task(args.store, args.task_id)
    _, rubric_path = load_rubric(args.store, args.task_id)
    entry = {
        "task_sha256": task_digest(task_dir),
        "rubric_sha256": _sha256_file(rubric_path),
    }
    lock = _read_lock(args.lock, must_exist=False)
    lock["tasks"][task["id"]] = entry
    _atomic_write(args.lock, _dump(lock))
    _say("✓", f"locked {task['id']} — commit {args.lock} before running")
    return {"locked": True, "task_id": task["id"], **entry, "lock": str(args.lock)}


# ─── run ───────────────────────────────────────────────────────


def _refuse_unsafe_env() -> None:
    ci = os.environ.get("CI")
    if (ci is not None and ci.strip().lower() not in ("", "0", "false")) or (
        os.environ.get("GITHUB_ACTIONS") == "true"
    ):
        raise Fail(2, "refused: never run real agents in CI (CI/GITHUB_ACTIONS set)")
    if os.environ.get("IDD_EVAL_AGENT") != "1":
        raise Fail(2, "refused: the promotion lane is opt-in — set IDD_EVAL_AGENT=1")
    if os.environ.get("EVAL_RECORD") == "1":
        raise Fail(2, "refused: EVAL_RECORD=1 must never be set for a promotion run")


def load_agent_config(path: Path) -> dict:
    cfg = _load_json(path, "agent config")
    if not isinstance(cfg, dict):
        raise Fail(3, "agent config must be a JSON object")
    command = cfg.get("command")
    if (
        not isinstance(command, list)
        or not command
        or not all(_nonempty_str(a) for a in command)
    ):
        raise Fail(3, "agent config command must be a non-empty list of strings")
    for arg in command:
        for name in PLACEHOLDER_RE.findall(arg):
            if name not in PLACEHOLDERS:
                raise Fail(3, f"unknown placeholder {{{name}}} in agent command")
    for key in ("model", "cli", "cli_version"):
        if not _nonempty_str(cfg.get(key)):
            raise Fail(3, f"agent config {key} must be a non-empty string")
    tools = cfg.get("tools")
    if not isinstance(tools, list) or not tools or not all(_nonempty_str(t) for t in tools):
        raise Fail(3, "agent config tools must be a non-empty list of strings")
    pass_env = cfg.get("pass_env", [])
    if not isinstance(pass_env, list):
        raise Fail(3, "agent config pass_env must be a list of variable names")
    for name in pass_env:
        if not isinstance(name, str) or not ENV_NAME_RE.match(name):
            raise Fail(3, f"invalid pass_env name {name!r}")
        if (
            name in FORBIDDEN_ENV
            or name.startswith(FORBIDDEN_ENV_PREFIXES)
            or name in MANAGED_ENV
        ):
            raise Fail(3, f"pass_env may not carry {name} (tokens, EVAL_*/IDD_*, managed env)")
    if "notes" in cfg and not isinstance(cfg["notes"], str):
        raise Fail(3, "agent config notes must be a string")
    cfg["pass_env"] = pass_env
    return cfg


def _require_clean_repo(repo: Path) -> str:
    try:
        _git(repo, "rev-parse", "--is-inside-work-tree")
        status = _git(repo, "status", "--porcelain=v1", "--untracked-files=all")
        sha = _git(repo, "rev-parse", "HEAD")
    except (OSError, subprocess.CalledProcessError) as exc:
        raise Fail(4, f"not a git work tree with a commit: {repo}") from exc
    if status:
        raise Fail(
            4, "dirty tree — commit or stash; provenance never records a dirty source"
        )
    return sha


def _resolve_arm(repo: Path, ref: str) -> dict:
    try:
        sha = _git(repo, "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}")
    except subprocess.CalledProcessError as exc:
        raise Fail(3, f"unknown ref {ref!r}") from exc
    if not SHA_RE.match(sha):
        raise Fail(3, f"ref {ref!r} did not resolve to a commit")
    try:
        tree = _git(repo, "rev-parse", f"{sha}:skills")
    except subprocess.CalledProcessError as exc:
        raise Fail(3, f"ref {ref!r} has no skills/ tree") from exc
    return {"ref": ref, "sha": sha, "skills_tree": tree}


def _check_lock(lock_path: Path, task_id: str, task_sha: str, rubric_sha: str) -> None:
    lock = _read_lock(lock_path, must_exist=True)
    entry = lock["tasks"].get(task_id)
    if not isinstance(entry, dict):
        raise Fail(3, f"task not locked: {task_id} — run `lock` and commit the lock")
    if entry.get("task_sha256") != task_sha:
        raise Fail(3, f"task changed since it was locked: {task_id}")
    if entry.get("rubric_sha256") != rubric_sha:
        raise Fail(3, f"rubric changed since it was locked: {task_id}")


def _materialize(repo: Path, sha: str, dest: Path) -> Path:
    dest.mkdir(parents=True)
    archive = subprocess.Popen(
        ["git", "-C", str(repo), "archive", "--format=tar", sha, "skills"],
        stdout=subprocess.PIPE,
    )
    untar = subprocess.run(["tar", "-x", "-C", str(dest)], stdin=archive.stdout)
    assert archive.stdout is not None
    archive.stdout.close()
    if archive.wait() != 0 or untar.returncode != 0:
        raise Fail(4, f"cannot materialize skills/ at {sha}")
    return dest / "skills"


def _scan_held_out(prompt: str, canary: bytes, arms: dict[str, Path]) -> list[dict]:
    """The held-out task must not already be in either arm's skills tree."""
    prompt_words = _words(prompt)
    prompt_shingles = _shingles(prompt_words)
    joined_prompt = " ".join(prompt_words)
    offenders: list[dict] = []
    for arm, skills in arms.items():
        for path in _regular_files(skills):
            data = path.read_bytes()
            rel = path.relative_to(skills.parent).as_posix()
            if canary in data:
                offenders.append({"arm": arm, "path": rel, "reason": "canary"})
            try:
                text = data.decode("utf-8")
            except UnicodeDecodeError:
                continue
            words = _words(text)
            if prompt_shingles:
                if prompt_shingles & _shingles(words):
                    offenders.append({"arm": arm, "path": rel, "reason": "prompt-shingle"})
            elif joined_prompt and joined_prompt in " ".join(words):
                offenders.append({"arm": arm, "path": rel, "reason": "prompt-text"})
    return offenders


def _scan_staging(
    prompt: str, task_dir: Path, rubric: dict, rubric_sha: str
) -> list[dict]:
    """Nothing staged for the agent may carry rubric material."""
    canary = rubric["canary"].encode("utf-8")
    criteria_shingles: set[tuple[str, ...]] = set()
    for item in rubric["criteria"]:
        criteria_shingles |= _shingles(_words(item["text"]))
    staged: list[tuple[str, bytes]] = [("prompt", prompt.encode("utf-8"))]
    fixture = task_dir / "fixture_repo"
    if fixture.is_dir():
        for path in _regular_files(fixture):
            staged.append((path.relative_to(task_dir).as_posix(), path.read_bytes()))
    cassettes = task_dir / "cassettes.json"
    if cassettes.is_file():
        staged.append(("cassettes.json", cassettes.read_bytes()))
    offenders: list[dict] = []
    for name, data in staged:
        if canary in data:
            offenders.append({"path": name, "reason": "canary"})
        if _sha256_bytes(data) == rubric_sha:
            offenders.append({"path": name, "reason": "rubric-copy"})
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            continue
        if criteria_shingles & _shingles(_words(text)):
            offenders.append({"path": name, "reason": "criteria-shingle"})
    return offenders


def _fill(arg: str, values: dict[str, str]) -> str:
    return PLACEHOLDER_RE.sub(lambda m: values[m.group(1)], arg)


def _hermetic_git(cwd: Path, home: Path, *args: str) -> None:
    env = {
        "HOME": str(home),
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "GIT_CONFIG_NOSYSTEM": "1",
    }
    subprocess.run(
        ["git", "-c", "commit.gpgsign=false", *args],
        cwd=str(cwd),
        env=env,
        check=True,
        capture_output=True,
    )


def _stage_run(raw: Path, task_dir: Path, prompt: str, harness_shim: Path) -> dict:
    workspace, out, home = raw / "workspace", raw / "out", raw / "home"
    gh_config, state, bindir = raw / "gh-config", raw / "state", raw / "bin"
    fixture = task_dir / "fixture_repo"
    raw.mkdir(parents=True)
    if fixture.is_dir():
        shutil.copytree(fixture, workspace, symlinks=True)
    else:
        workspace.mkdir()
    for d in (out, home, gh_config, state, bindir):
        d.mkdir()
    _hermetic_git(workspace, home, "init", "-q")
    _hermetic_git(workspace, home, "config", "user.name", "idd-eval")
    _hermetic_git(workspace, home, "config", "user.email", "idd-eval@example.invalid")
    _hermetic_git(workspace, home, "add", "-A")
    _hermetic_git(workspace, home, "commit", "-q", "--allow-empty", "-m", "fixture")
    gh = bindir / "gh"
    gh.write_text(
        "#!/usr/bin/env bash\n"
        f"exec {shlex.quote(sys.executable)} -B {shlex.quote(str(harness_shim))} \"$@\"\n",
        encoding="utf-8",
    )
    gh.chmod(0o755)
    prompt_file = raw / "prompt.txt"
    prompt_file.write_text(prompt, encoding="utf-8")
    cassettes = raw / "cassettes.json"
    if (task_dir / "cassettes.json").is_file():
        shutil.copyfile(task_dir / "cassettes.json", cassettes)
    else:
        cassettes.write_text(EMPTY_CASSETTES, encoding="utf-8")
    call_log = raw / "gh-calls.jsonl"
    call_log.write_text("", encoding="utf-8")
    return {
        "workspace": workspace,
        "out": out,
        "home": home,
        "gh_config": gh_config,
        "state": state,
        "bin": bindir,
        "prompt_file": prompt_file,
        "cassettes": cassettes,
        "call_log": call_log,
    }


def _agent_env(paths: dict, skills: Path, pass_env: list[str]) -> dict[str, str]:
    env = {
        "HOME": str(paths["home"]),
        "PATH": f"{paths['bin']}:{os.environ.get('PATH', '/usr/bin:/bin')}",
        "LANG": "C.UTF-8",
        "GH_CONFIG_DIR": str(paths["gh_config"]),
        "GH_PROMPT_DISABLED": "1",
        "EVAL_CASSETTES": str(paths["cassettes"]),
        "EVAL_STATE_DIR": str(paths["state"]),
        "EVAL_GH_CALL_LOG": str(paths["call_log"]),
        "EVAL_OUT": str(paths["out"]),
        "EVAL_WORKSPACE": str(paths["workspace"]),
        "EVAL_SKILLS_DIR": str(skills),
        "EVAL_PROMPT_FILE": str(paths["prompt_file"]),
    }
    for name in pass_env:
        if name in os.environ:
            env[name] = os.environ[name]
    return env


def _execute(argv: list[str], cwd: Path, env: dict, raw: Path, timeout: int) -> tuple[Any, float]:
    start = time.monotonic()
    with open(raw / "transcript.txt", "wb") as so, open(
        raw / "transcript.stderr.txt", "wb"
    ) as se:
        try:
            proc = subprocess.Popen(
                argv,
                cwd=str(cwd),
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=so,
                stderr=se,
                start_new_session=True,
            )
        except OSError as exc:
            raise Fail(4, f"agent command cannot be started: {exc}") from exc
        try:
            code: Any = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            code = "timeout"
        # Reap the whole session: a timed-out agent, or stray background children.
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        proc.wait()
    return code, round(time.monotonic() - start, 3)


def _post_leaks(raw: Path, out: Path, canary: bytes, criteria_shingles: set) -> list[str]:
    reasons: list[str] = []
    scanned = [raw / "transcript.txt", raw / "transcript.stderr.txt", raw / "gh-calls.jsonl"]
    scanned += _regular_files(out)
    for path in scanned:
        if path.is_file() and canary in path.read_bytes():
            reasons.append(f"canary in {path.relative_to(raw).as_posix()}")
    for name in ("transcript.txt", "transcript.stderr.txt"):
        text = (raw / name).read_bytes().decode("utf-8", errors="replace")
        if criteria_shingles & _shingles(_words(text)):
            reasons.append(f"rubric criteria text in {name}")
    return reasons


def _run_checks(
    repo: Path, run_dir: Path, bid: str, task_id: str, checks: list, raw: Path
) -> bool:
    if not checks:
        return True
    case_dir = run_dir / "checks" / bid
    case_dir.mkdir(parents=True)
    (case_dir / "case.json").write_text(
        _dump({"name": f"promotion/{task_id}", "grade": checks}), encoding="utf-8"
    )
    env = dict(os.environ, REPO_ROOT=str(repo), PYTHONDONTWRITEBYTECODE="1")
    proc = subprocess.run(
        [
            sys.executable,
            "-B",
            str(repo / "evals" / "harness" / "grade.py"),
            "--case",
            str(case_dir),
            "--out",
            str(raw / "out"),
        ],
        cwd=str(repo),
        env=env,
        capture_output=True,
        text=True,
    )
    (raw / "checks.txt").write_text(proc.stdout + proc.stderr, encoding="utf-8")
    return proc.returncode == 0


def _scrubber(tokens: set[str]):
    literal = sorted((t for t in tokens if t), key=len, reverse=True)
    lit_re = re.compile("|".join(re.escape(t) for t in literal)) if literal else None
    arm_re = re.compile(r"\b(?:baseline|candidate)\b", re.IGNORECASE)

    def scrub(text: str) -> str:
        if lit_re is not None:
            text = lit_re.sub("[redacted]", text)
        return arm_re.sub("[redacted]", text)

    return scrub


def _path_forms(path: Path) -> set[str]:
    return {str(path), os.path.abspath(str(path)), str(path.resolve())}


def _build_packets(
    run_dir: Path,
    records: dict[str, dict],
    rubric: dict,
    scrub,
) -> None:
    blind = run_dir / "blind"
    criteria = [{"id": c["id"], "text": c["text"]} for c in rubric["criteria"]]
    for bid, rec in records.items():
        raw = run_dir / rec["raw"]
        packet = blind / bid
        packet.mkdir(parents=True)
        for name in ("transcript.txt", "transcript.stderr.txt", "gh-calls.jsonl"):
            text = (raw / name).read_bytes().decode("utf-8", errors="replace")
            (packet / name).write_text(scrub(text), encoding="utf-8")
        out = raw / "out"
        for path in _regular_files(out):
            rel = path.relative_to(out).as_posix()
            if rel in ("transcript.txt", "gh-calls.jsonl"):
                continue  # duplicates of the files already copied above
            try:
                text = path.read_bytes().decode("utf-8")
            except UnicodeDecodeError:
                continue
            dest = packet / "out" / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(scrub(text), encoding="utf-8")
        (packet / "criteria.json").write_text(_dump(criteria), encoding="utf-8")
    template = {bid: {c["id"]: None for c in criteria} for bid in sorted(records)}
    (blind / "scores.template.json").write_text(_dump(template), encoding="utf-8")


def _artifact(run_dir: Path, path: Path) -> dict:
    return {
        "path": path.relative_to(run_dir).as_posix(),
        "sha256": _sha256_file(path),
        "bytes": path.stat().st_size,
    }


def _repo_rel(repo: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(repo.resolve()).as_posix()
    except ValueError:
        return str(path.resolve())


def cmd_run(args: argparse.Namespace) -> dict:
    _refuse_unsafe_env()
    if args.runs is not None and args.runs < 1:
        raise Fail(2, "--runs must be >= 1")
    if args.timeout < 1:
        raise Fail(2, "--timeout must be >= 1")
    repo = args.repo.resolve()
    agent = load_agent_config(args.agent_config)
    head = _require_clean_repo(repo)
    arms = {"baseline": _resolve_arm(repo, args.baseline),
            "candidate": _resolve_arm(repo, args.candidate)}
    harness = []
    for rel in HARNESS_FILES:
        path = repo / rel
        if not path.is_file():
            raise Fail(4, f"harness file missing at HEAD: {rel}")
        harness.append({"path": rel, "sha256": _sha256_file(path)})

    store = args.store.resolve()
    task, task_dir = load_task(store, args.task_id)
    rubric, rubric_path = load_rubric(store, args.task_id)
    task_sha, rubric_sha = task_digest(task_dir), _sha256_file(rubric_path)
    _check_lock(args.lock, task["id"], task_sha, rubric_sha)
    lock_sha = _sha256_file(args.lock)
    if store == repo / "skills" or (repo / "skills") in store.parents:
        raise Fail(3, "the store may not live inside skills/")

    per_arm = args.runs if args.runs is not None else task["min_runs"]
    seed = args.seed if args.seed is not None else secrets.randbelow(2**32)

    # The agent works under a throwaway staging root outside the store and the
    # repo, so the private rubrics are never a few `..` above its cwd. Each run
    # is copied into the store's raw/ afterwards, and the root is removed.
    staging_root = Path(tempfile.mkdtemp(prefix="idd-agent-")).resolve()
    try:
        for inside in (store, repo):
            if staging_root == inside or inside in staging_root.parents:
                raise Fail(4, f"staging root {staging_root} is inside {inside} — set TMPDIR elsewhere")
        return _run_staged(
            args, agent, repo, head, arms, harness, store, task, task_dir, rubric,
            task_sha, rubric_sha, lock_sha, per_arm, seed, staging_root,
        )
    finally:
        shutil.rmtree(staging_root, ignore_errors=True)


def _run_staged(
    args: argparse.Namespace,
    agent: dict,
    repo: Path,
    head: str,
    arms: dict,
    harness: list,
    store: Path,
    task: dict,
    task_dir: Path,
    rubric: dict,
    task_sha: str,
    rubric_sha: str,
    lock_sha: str,
    per_arm: int,
    seed: int,
    staging_root: Path,
) -> dict:
    # Opaque directory names: every path the agent can see (cwd, skills dir,
    # out dir) must be free of the arm label.
    skills_dirs: dict[str, Path] = {}
    arm_tokens: list[str] = []
    for arm in ARMS:
        token = secrets.token_hex(4)
        arm_tokens.append(token)
        skills_dirs[arm] = _materialize(repo, arms[arm]["sha"], staging_root / token)

    canary = rubric["canary"].encode("utf-8")
    held_out = _scan_held_out(task["prompt"], canary, skills_dirs)
    staging = _scan_staging(task["prompt"], task_dir, rubric, rubric_sha)
    if held_out or staging:
        raise Fail(
            3,
            "pre-run leak check failed — no agent ran",
            {"leak": True, "stage": "pre", "held_out": held_out, "staging": staging},
        )
    _say("✓", "pre-run leak checks: held-out and staging clean")

    run_id = f"{_now('%Y%m%dT%H%M%SZ')}-{task['id']}-{secrets.token_hex(3)}"
    run_dir = store / "runs" / run_id
    run_dir.mkdir(parents=True)
    _say("●", f"run {run_id}")

    shim = staging_root / "harness" / "gh_shim.py"
    shim.parent.mkdir()
    shutil.copyfile(repo / "evals" / "harness" / "gh_shim.py", shim)

    order = [(arm, i) for arm in ARMS for i in range(1, per_arm + 1)]
    random.Random(seed).shuffle(order)
    bids: set[str] = set()
    plan: list[tuple[str, str, int]] = []
    for arm, index in order:
        bid = secrets.token_hex(4)
        while bid in bids:
            bid = secrets.token_hex(4)
        bids.add(bid)
        plan.append((bid, arm, index))

    criteria_shingles: set[tuple[str, ...]] = set()
    for item in rubric["criteria"]:
        criteria_shingles |= _shingles(_words(item["text"]))

    records: dict[str, dict] = {}
    for n, (bid, arm, index) in enumerate(plan, 1):
        stage = staging_root / bid
        paths = _stage_run(stage, task_dir, task["prompt"], shim)
        values = {
            "prompt_file": str(paths["prompt_file"]),
            "workspace": str(paths["workspace"]),
            "skills_dir": str(skills_dirs[arm]),
            "out_dir": str(paths["out"]),
        }
        argv = [_fill(a, values) for a in agent["command"]]
        env = _agent_env(paths, skills_dirs[arm], agent["pass_env"])
        code, duration = _execute(argv, paths["workspace"], env, stage, args.timeout)
        shutil.copyfile(paths["call_log"], paths["out"] / "gh-calls.jsonl")
        shutil.copyfile(stage / "transcript.txt", paths["out"] / "transcript.txt")
        raw = run_dir / "raw" / bid
        shutil.copytree(stage, raw, symlinks=True)
        leak_reasons = _post_leaks(raw, raw / "out", canary, criteria_shingles)
        checks_passed = _run_checks(repo, run_dir, bid, task["id"], rubric["checks"], raw)
        records[bid] = {
            "arm": arm,
            "index": index,
            "raw": f"raw/{bid}",
            "exit": code,
            "duration_s": duration,
            "checks_passed": checks_passed,
            "leak": bool(leak_reasons),
            "leak_reasons": leak_reasons,
        }
        mark = "⚠" if leak_reasons else "✓"
        _say(mark, f"run {n}/{len(plan)} {bid}: exit {code}, {duration}s")

    # The agent is not sandboxed: confirm the source it was measured against
    # is still the commit provenance names.
    if _require_clean_repo(repo) != head:
        raise Fail(4, "repo HEAD moved during the run — provenance would not describe it")

    tokens: set[str] = set(arm_tokens)
    for arm in ARMS:
        for key in ("sha", "skills_tree"):
            value = arms[arm][key]
            tokens.add(value)
            tokens.update(value[:k] for k in range(7, 13))
        if len(arms[arm]["ref"]) >= 3:
            tokens.add(arms[arm]["ref"])
    for path in [staging_root, run_dir, store]:
        tokens |= _path_forms(path)
    _build_packets(run_dir, records, rubric, _scrubber(tokens))

    key_path = run_dir / "sealed" / "key.json"
    _atomic_write(key_path, _dump(records))
    key_sha = _sha256_file(key_path)

    artifacts = [_artifact(run_dir, key_path)]
    for bid in records:
        for name in ("transcript.txt", "transcript.stderr.txt", "gh-calls.jsonl"):
            artifacts.append(_artifact(run_dir, run_dir / "raw" / bid / name))
    artifacts += [_artifact(run_dir, p) for p in _regular_files(run_dir / "blind")]
    artifacts.sort(key=lambda a: a["path"])

    leaks = sum(1 for r in records.values() if r["leak"])
    provenance = {
        "schema": 1,
        "kind": "idd-promotion-provenance",
        "tool": "agent_eval",
        "sha": head,
        "clean_tree": True,
        "harness": harness,
        "task": {
            "id": task["id"],
            "skill": task["skill"],
            "task_sha256": task_sha,
            "rubric_sha256": rubric_sha,
            "lock_path": _repo_rel(repo, args.lock),
            "lock_sha256": lock_sha,
        },
        "arms": arms,
        "agent": {
            "declared": {k: agent[k] for k in ("model", "cli", "cli_version", "tools")},
            "command": agent["command"],
            "pass_env": agent["pass_env"],
        },
        "posture": {
            "github": "gh_shim cassette replay; GH tokens stripped",
            "network": "unrestricted (model API); not sandboxed",
        },
        "runs": {
            "per_arm": per_arm,
            "seed": seed,
            "timeout_s": args.timeout,
            "min_runs": task["min_runs"],
        },
        "leakcheck": {"pre": {"held_out": "pass", "staging": "pass"}, "post_leaks": leaks},
        "key_sha256": key_sha,
        "executor": _executor(),
        "written_at": _now("%Y-%m-%dT%H:%M:%SZ"),
        "artifacts": artifacts,
        "verdict": None,
    }
    _atomic_write(run_dir / "provenance.json", _dump(provenance))
    if leaks:
        _say("⚠", f"{leaks} run(s) leaked rubric material — the verdict will be invalid")
    _say("✓", f"blind packets ready: {run_dir / 'blind'}")
    return {
        "run_id": run_id,
        "run_dir": str(run_dir),
        "blind_dir": str(run_dir / "blind"),
        "scores_template": str(run_dir / "blind" / "scores.template.json"),
        "runs": len(records),
        "leaks": leaks,
    }


# ─── verdict / verify ──────────────────────────────────────────


def _load_provenance(run_dir: Path) -> dict:
    prov = _load_json(run_dir / "provenance.json", "provenance.json")
    if not isinstance(prov, dict) or prov.get("kind") != "idd-promotion-provenance":
        raise Fail(3, "provenance.json is not an idd-promotion-provenance record")
    for key, kind in (("task", dict), ("runs", dict), ("leakcheck", dict), ("artifacts", list)):
        if not isinstance(prov.get(key), kind):
            raise Fail(3, f"provenance.json {key} is malformed")
    if prov.get("verdict") is not None and not isinstance(prov["verdict"], dict):
        raise Fail(3, "provenance.json verdict is malformed")
    return prov


def cmd_verdict(args: argparse.Namespace) -> dict:
    run_dir = args.run_dir.resolve()
    prov = _load_provenance(run_dir)
    # One verdict per run: re-scoring after the key is unsealed would let a
    # grader learn each blind id's arm by watching the per-arm counts move.
    if prov.get("verdict") is not None:
        raise Fail(3, "verdict already recorded for this run — it is final")
    key_path = run_dir / "sealed" / "key.json"
    if not key_path.is_file() or _sha256_file(key_path) != prov.get("key_sha256"):
        raise Fail(3, "sealed key does not match provenance key_sha256")
    key = _load_json(key_path, "sealed key")
    task_id = prov["task"]["id"]
    rubric, rubric_path = load_rubric(args.store.resolve(), task_id)
    if _sha256_file(rubric_path) != prov["task"]["rubric_sha256"]:
        raise Fail(3, "rubric changed since the run — it no longer matches provenance")
    criterion_ids = {c["id"] for c in rubric["criteria"]}

    scores = _load_json(args.scores, "scores")
    if not isinstance(scores, dict) or set(scores) != set(key):
        raise Fail(3, "scores must cover exactly every blind id in the sealed key")
    for bid, marks in scores.items():
        if not isinstance(marks, dict) or set(marks) != criterion_ids:
            raise Fail(3, f"scores for {bid} must cover exactly every criterion id")
        if not all(isinstance(v, bool) for v in marks.values()):
            raise Fail(3, f"scores for {bid} must be true/false")

    tally = {arm: {"passed": 0, "n": 0} for arm in ARMS}
    for bid, rec in key.items():
        marks = scores[bid]
        frac = sum(1 for v in marks.values() if v) / len(marks)
        passed = (
            rec.get("exit") == 0
            and rec.get("checks_passed") is True
            and not rec.get("leak")
            and frac >= rubric["pass_threshold"]
        )
        tally[rec["arm"]]["n"] += 1
        tally[rec["arm"]]["passed"] += int(passed)
    for arm in ARMS:
        n = tally[arm]["n"]
        tally[arm]["pass_rate"] = tally[arm]["passed"] / n if n else 0.0

    base, cand = tally["baseline"]["pass_rate"], tally["candidate"]["pass_rate"]
    if prov["leakcheck"]["post_leaks"] or any(r.get("leak") for r in key.values()):
        result = "invalid"
    elif prov["runs"]["per_arm"] < prov["runs"]["min_runs"]:
        result = "insufficient"
    elif cand < base:
        result = "reject"
    elif cand >= rubric["min_pass_rate"]:
        result = "promote"
    else:
        result = "hold"

    scores_path = run_dir / "scores.json"
    shutil.copyfile(args.scores, scores_path)
    verdict = {
        "result": result,
        "baseline": tally["baseline"],
        "candidate": tally["candidate"],
        "pass_threshold": rubric["pass_threshold"],
        "min_pass_rate": rubric["min_pass_rate"],
        "scores_sha256": _sha256_file(scores_path),
        "decided_at": _now("%Y-%m-%dT%H:%M:%SZ"),
    }
    artifacts = [a for a in prov.get("artifacts", []) if a.get("path") != "scores.json"]
    artifacts.append(_artifact(run_dir, scores_path))
    prov["artifacts"] = sorted(artifacts, key=lambda a: a["path"])
    prov["verdict"] = verdict
    _atomic_write(run_dir / "provenance.json", _dump(prov))
    _say("✓" if result == "promote" else "●", f"verdict: {result}")
    return verdict


def cmd_verify(args: argparse.Namespace) -> dict:
    run_dir = args.run_dir.resolve()
    prov = _load_provenance(run_dir)

    def answer(ok: bool, reason: str) -> dict:
        _say("✓" if ok else "✗", f"verify: {reason}")
        return {"verified": ok, "reason": reason, "run_dir": str(run_dir)}

    artifacts = prov.get("artifacts")
    if not isinstance(artifacts, list) or not artifacts:
        return answer(False, "provenance lists no artifacts")
    for item in artifacts:
        rel = item.get("path") if isinstance(item, dict) else None
        if not isinstance(rel, str) or rel.startswith("/") or ".." in Path(rel).parts:
            return answer(False, f"unsafe artifact path {rel!r}")
        path = run_dir / rel
        if not path.is_file() or path.is_symlink():
            return answer(False, f"missing artifact {rel}")
        if _sha256_file(path) != item.get("sha256") or path.stat().st_size != item.get("bytes"):
            return answer(False, f"artifact changed: {rel}")
    key_path = run_dir / "sealed" / "key.json"
    if not key_path.is_file() or _sha256_file(key_path) != prov.get("key_sha256"):
        return answer(False, "sealed key does not match key_sha256")
    verdict = prov.get("verdict")
    if verdict is not None:
        scores = run_dir / "scores.json"
        if not scores.is_file() or _sha256_file(scores) != verdict.get("scores_sha256"):
            return answer(False, "scores.json does not match the recorded verdict")
    return answer(True, f"{len(artifacts)} artifacts match")


# ─── CLI ───────────────────────────────────────────────────────


def _parser() -> argparse.ArgumentParser:
    repo_default = Path(__file__).resolve().parents[2]
    shared = argparse.ArgumentParser(add_help=False)
    shared.add_argument("--repo", type=Path, default=repo_default,
                        help="repository root (default: this file's repo)")
    shared.add_argument("--store", type=Path, default=None,
                        help="private store (default: $IDD_PROMOTION_STORE, else "
                        "<repo>/evals/promotion/private)")
    shared.add_argument("--lock", type=Path, default=None,
                        help="lock file (default: <repo>/evals/promotion/lock.json)")

    parser = argparse.ArgumentParser(
        prog="agent_eval.py",
        description="Blinded real-agent promotion lane (opt-in, never in CI).",
        epilog="Exit codes: 0 ok · 2 usage/refused · 3 invalid input · 4 cannot complete.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("lock", parents=[shared], help="commit task + rubric digests")
    p.add_argument("--task-id", required=True)
    p.set_defaults(func=cmd_lock)

    p = sub.add_parser("run", parents=[shared], help="run both arms blind")
    p.add_argument("--task-id", required=True)
    p.add_argument("--baseline", required=True, help="git ref for the baseline skills/")
    p.add_argument("--candidate", required=True, help="git ref for the candidate skills/")
    p.add_argument("--agent-config", required=True, type=Path)
    p.add_argument("--runs", type=int, default=None, help="runs per arm (default: task min_runs)")
    p.add_argument("--seed", type=int, default=None, help="run-order seed (default: random)")
    p.add_argument("--timeout", type=int, default=1800, help="seconds per run (default 1800)")
    p.set_defaults(func=cmd_run)

    p = sub.add_parser("verdict", parents=[shared], help="unseal the key against scores")
    p.add_argument("--run-dir", required=True, type=Path)
    p.add_argument("--scores", required=True, type=Path)
    p.set_defaults(func=cmd_verdict)

    p = sub.add_parser("verify", parents=[shared], help="re-hash a run's artifacts")
    p.add_argument("--run-dir", required=True, type=Path)
    p.set_defaults(func=cmd_verify)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    if args.store is None:
        env_store = os.environ.get("IDD_PROMOTION_STORE")
        args.store = Path(env_store) if env_store else args.repo / "evals" / "promotion" / "private"
    if args.lock is None:
        args.lock = args.repo / "evals" / "promotion" / "lock.json"
    try:
        result = args.func(args)
    except Fail as exc:
        _say("✗", exc.message)
        print(json.dumps({"error": exc.message, "exit": exc.code, **exc.report},
                         sort_keys=True))
        return exc.code
    except (KeyError, TypeError, AttributeError, ValueError) as exc:
        _say("✗", f"malformed record: {exc!r}")
        print(json.dumps({"error": f"malformed record: {exc!r}", "exit": 3}, sort_keys=True))
        return 3
    except Exception as exc:  # noqa: BLE001 — OSError, git failures: never exit 1
        _say("✗", f"cannot complete: {exc}")
        print(json.dumps({"error": str(exc), "exit": 4}, sort_keys=True))
        return 4
    print(json.dumps(result, sort_keys=True, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
