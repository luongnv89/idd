#!/usr/bin/env python3
"""Run a project-local verification recipe against an owned app instance (issue #523).

A repository may commit `.idd-recipe.json` to describe how to verify it
end to end: how to **launch** the app, how to tell it is ready, which
**capabilities** to **drive** for which changed paths, and what extra
**cleanup** to run. This script executes that recipe deterministically and
prints one JSON verdict, so the skills never improvise a launch or a kill.

Trust boundary
  The recipe is read from `--ref` (the base branch), never from the working
  tree: a branch under review must not supply the recipe it is verified by.
  The recipe's commands run in the working tree — the code under test.
  In auto mode (`--auto`, or `IDD_AUTO_MODE=1`) nothing runs unless the
  base-ref recipe's `auto` list names `--consumer`.
  A base ref with no `.idd-recipe.json` is read for the pre-rename
  `.gitissue-recipe.json` instead (issue #537, ⚠ line on stderr). Only absence
  falls back: a present `.idd-recipe.json` that is invalid is exit 3, never a
  reason to run the older recipe.

Recipe (JSON, every key outside this list is invalid, `_`-prefixed keys are
comments):

    {"version": 1,
     "auto": ["resolve", "review"],                 (optional, default [])
     "app_url": "http://127.0.0.1:{port}",          (optional; loopback only)
     "launch": {"command": ["python3", "-I", "-m", "http.server", "{port}",
                            "--bind", "127.0.0.1"],
                "ready": {"url": "/", "timeout_s": 30}},
     "capabilities": [
       {"name": "landing", "paths": ["*.html", "assets/*"],   (paths optional:
        "drive": ["curl", "-sf", "-o", "{evidence_dir}/landing.html",
                  "{app_url}/landing.html"],                  omitted = always)
        "timeout_s": 60}],
     "cleanup": [["rm", "-f", "{instance_dir}/pid"]]}         (optional)

  Commands are argv arrays, never shell strings. Tokens substituted in every
  argument: `{port}` (a free loopback port this script picks), `{app_url}`,
  `{instance_dir}` (scratch removed at teardown) and `{evidence_dir}` (the run
  root for launch/cleanup, the capability's own directory for a drive). The
  same values are exported as IDD_PORT, IDD_APP_URL, IDD_INSTANCE_DIR and
  IDD_EVIDENCE_DIR. `paths` are fnmatch globs (`*` also crosses `/`) matched
  against the changed files read from `--changed` (a file, or `-` for stdin,
  one path per line); a capability is driven only when one of them matches.

Lifecycle
  launch in a new process group (the only group this script ever signals) →
  poll the ready URL → drive each mapped capability → teardown: SIGTERM, then
  SIGKILL, the owned group; run `cleanup`; remove `{instance_dir}`. Teardown
  runs on every path, including a readiness failure and SIGTERM/SIGINT.

Evidence
  `<git common dir>/idd/evidence/<head sha40>/<consumer>-<UTC>-<pid>/`, mode
  0700: `launch.log`, `<capability>/drive.log` plus whatever the drive wrote,
  `cleanup.log`, and `verdict.json`. It sits inside `.git`, outside the owned
  instance and outside the work tree, so it survives teardown, never dirties
  the tree, and its paths can be digested as revision-receipt artifacts.

Output: one JSON line on stdout —
    {"status": "absent" | "skipped" | "planned" | "ran" | "unavailable",
     "reason", "recipe", "ref", "consumer", "head", "capabilities":
     [{"name", "mapped", "driven", "exit", "timed_out"}],
     "result": "pass" | "fail" | "none", "app_url", "evidence_dir",
     "evidence": [<absolute paths>], "owned": {"pgid"} | null,
     "torn_down": true | false | null, "cleanup": [<exit> ...]}
  `result` is `fail` when any driven capability exited non-zero or timed out.
  `recipe` is the path actually loaded, or null when the ref carries none.

Exit codes
  0  answered — `absent` (no recipe at the ref), `skipped` (auto opt-in not
     set, or no capability mapped), `planned` (--plan), or `ran`. Read
     `status` and `result`, never the exit status. This script never exits 1.
  2  usage error
  3  invalid input — the base-ref recipe is not valid JSON of the shape above,
     or its app_url is not loopback. Nothing was launched. Stop and fix it.
  4  cannot complete — git missing, the ref does not resolve, no process
     groups on this platform, the launch failed or never became ready, or the
     run was interrupted. stdout still carries the verdict (`unavailable`)
     when a launch was attempted, with the owned group torn down. Degrade.

Authored at src/shared/scripts/gi-recipe.py — do not edit installed copies;
edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import fnmatch
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

RECIPE_PATH = ".idd-recipe.json"
LEGACY_RECIPE_PATH = ".gitissue-recipe.json"
CONSUMERS = ("resolve", "review")
DEFAULT_APP_URL = "http://127.0.0.1:{port}"
LOOPBACK_HOSTS = ("127.0.0.1", "localhost", "::1")
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,39}$")
MAX_TIMEOUT_S = 600
TERM_GRACE_S = 5
TOP_KEYS = {"version", "auto", "app_url", "launch", "capabilities", "cleanup"}
LAUNCH_KEYS = {"command", "ready"}
READY_KEYS = {"url", "timeout_s"}
CAPABILITY_KEYS = {"name", "paths", "drive", "timeout_s"}


class InvalidRecipe(Exception):
    """Exit 3."""


class CannotComplete(Exception):
    """Exit 4."""


class Interrupted(Exception):
    """A termination signal arrived; teardown still runs."""


def _git(*args: str) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(["git", *args], capture_output=True, text=True, check=False)
    except OSError as exc:
        raise CannotComplete(f"git unavailable: {exc}") from exc


def _git_out(*args: str) -> str:
    proc = _git(*args)
    if proc.returncode != 0:
        raise CannotComplete(f"git {' '.join(args)} failed: {proc.stderr.strip() or proc.returncode}")
    return proc.stdout.strip()


def _keys(obj: object, allowed: set[str], where: str) -> dict:
    if not isinstance(obj, dict):
        raise InvalidRecipe(f"{where} must be an object")
    extra = sorted(k for k in obj if k not in allowed and not k.startswith("_"))
    if extra:
        raise InvalidRecipe(f"{where} has unknown key(s): {', '.join(extra)}")
    return obj


def _argv(value: object, where: str) -> list[str]:
    if (
        not isinstance(value, list)
        or not value
        or not all(isinstance(a, str) for a in value)
        or not value[0]
    ):
        raise InvalidRecipe(f"{where} must be a non-empty array of strings (argv, not a shell string)")
    return list(value)


def _timeout(obj: dict, key: str, default: int, where: str) -> int:
    value = obj.get(key, default)
    if type(value) is not int or not 1 <= value <= MAX_TIMEOUT_S:
        raise InvalidRecipe(f"{where}.{key} must be an integer from 1 to {MAX_TIMEOUT_S}")
    return value


def _split(url: str, where: str) -> urllib.parse.SplitResult:
    # urlsplit raises ValueError on input such as an unclosed IPv6 bracket;
    # uncaught, that would be a traceback and exit 1 instead of exit 3.
    try:
        parts = urllib.parse.urlsplit(url)
        parts.port  # noqa: B018 - validates the port, raising ValueError
    except ValueError as exc:
        raise InvalidRecipe(f"{where} is not a valid URL: {exc}") from exc
    return parts


def validate(obj: object) -> dict:
    """Return the recipe with defaults applied, or raise InvalidRecipe."""
    top = _keys(obj, TOP_KEYS, "recipe")
    if top.get("version") != 1 or type(top.get("version")) is not int:
        raise InvalidRecipe("recipe.version must be 1")
    auto = top.get("auto", [])
    if not isinstance(auto, list) or not all(a in CONSUMERS for a in auto):
        raise InvalidRecipe(f"recipe.auto must be an array of {' / '.join(CONSUMERS)}")
    app_url = top.get("app_url", DEFAULT_APP_URL)
    if not isinstance(app_url, str):
        raise InvalidRecipe("recipe.app_url must be a string")
    probe = _split(app_url.replace("{port}", "1"), "recipe.app_url")
    if probe.scheme not in ("http", "https") or probe.hostname not in LOOPBACK_HOSTS:
        raise InvalidRecipe("recipe.app_url must be an http(s) URL on a loopback host")
    launch = _keys(top.get("launch"), LAUNCH_KEYS, "recipe.launch")
    command = _argv(launch.get("command"), "recipe.launch.command")
    ready = _keys(launch.get("ready"), READY_KEYS, "recipe.launch.ready")
    ready_url = ready.get("url")
    if not isinstance(ready_url, str) or not (ready_url.startswith("/") or ready_url.startswith("{app_url}")):
        raise InvalidRecipe("recipe.launch.ready.url must start with / or {app_url}")
    ready_probe = ready_url.replace("{app_url}", app_url.replace("{port}", "1"))
    ready_probe = app_url.replace("{port}", "1") + ready_probe if ready_probe.startswith("/") else ready_probe
    if _split(ready_probe, "recipe.launch.ready.url").hostname not in LOOPBACK_HOSTS:
        raise InvalidRecipe("recipe.launch.ready.url must stay on the app_url host")
    ready_timeout = _timeout(ready, "timeout_s", 30, "recipe.launch.ready")
    caps_in = top.get("capabilities")
    if not isinstance(caps_in, list) or not caps_in:
        raise InvalidRecipe("recipe.capabilities must be a non-empty array")
    caps, seen = [], set()
    for i, raw in enumerate(caps_in):
        where = f"recipe.capabilities[{i}]"
        cap = _keys(raw, CAPABILITY_KEYS, where)
        name = cap.get("name")
        if not isinstance(name, str) or not NAME_RE.match(name) or name in seen:
            raise InvalidRecipe(f"{where}.name must be a unique lowercase-hyphen name")
        seen.add(name)
        paths = cap.get("paths")
        if paths is not None and (
            not isinstance(paths, list) or not paths or not all(isinstance(p, str) and p for p in paths)
        ):
            raise InvalidRecipe(f"{where}.paths must be a non-empty array of globs, or omitted")
        caps.append({
            "name": name,
            "paths": paths,
            "drive": _argv(cap.get("drive"), f"{where}.drive"),
            "timeout_s": _timeout(cap, "timeout_s", 60, where),
        })
    cleanup = top.get("cleanup", [])
    if not isinstance(cleanup, list):
        raise InvalidRecipe("recipe.cleanup must be an array of argv arrays")
    return {
        "auto": auto,
        "app_url": app_url,
        "launch": command,
        "ready_url": ready_url,
        "ready_timeout": ready_timeout,
        "capabilities": caps,
        "cleanup": [_argv(c, f"recipe.cleanup[{i}]") for i, c in enumerate(cleanup)],
    }


def load_recipe(ref: str) -> tuple[dict, str] | None:
    """(validated recipe, path loaded) at `ref`, or None when it carries none."""
    if _git("rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}").returncode != 0:
        raise CannotComplete(f"ref does not resolve to a commit: {ref}")
    path = RECIPE_PATH
    if _git("cat-file", "-e", f"{ref}:{RECIPE_PATH}").returncode != 0:
        # Absence alone falls back to the legacy name; a present new recipe is
        # validated below and an invalid one stops at exit 3.
        if _git("cat-file", "-e", f"{ref}:{LEGACY_RECIPE_PATH}").returncode != 0:
            return None
        path = LEGACY_RECIPE_PATH
        print(
            f"⚠ legacy {LEGACY_RECIPE_PATH} found at {ref} — rename to {RECIPE_PATH}",
            file=sys.stderr,
        )
    text = _git_out("show", f"{ref}:{path}")
    try:
        obj = json.loads(text)
    except ValueError as exc:
        raise InvalidRecipe(f"{path} at {ref} is not JSON: {exc}") from exc
    return validate(obj), path


def mapped(cap: dict, changed: list[str]) -> bool:
    if cap["paths"] is None:
        return True
    return any(fnmatch.fnmatchcase(f, pat) for f in changed for pat in cap["paths"])


def _subst(argv: list[str], values: dict[str, str]) -> list[str]:
    out = []
    for arg in argv:
        for token, value in values.items():
            arg = arg.replace(token, value)
        out.append(arg)
    return out


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def _group_alive(pgid: int) -> bool:
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _signal_group(pgid: int, sig: int) -> None:
    if pgid == os.getpgrp():  # never this script's own group
        return
    try:
        os.killpg(pgid, sig)
    except (ProcessLookupError, PermissionError):
        pass


def _stop_group(proc: subprocess.Popen) -> bool:
    """Terminate the owned group led by `proc`; True once no member remains."""
    pgid = proc.pid
    if proc.poll() is None or _group_alive(pgid):
        _signal_group(pgid, signal.SIGTERM)
        try:
            proc.wait(timeout=TERM_GRACE_S)
        except subprocess.TimeoutExpired:
            pass
    if _group_alive(pgid):
        _signal_group(pgid, signal.SIGKILL)
    try:
        proc.wait(timeout=TERM_GRACE_S)
    except subprocess.TimeoutExpired:
        return False
    deadline = time.monotonic() + 3
    while _group_alive(pgid) and time.monotonic() < deadline:
        time.sleep(0.05)
    return not _group_alive(pgid)


def _run_owned(argv, cwd, env, log, timeout) -> tuple[int | None, bool]:
    """Run one drive/cleanup command in its own group; (exit, timed_out)."""
    try:
        proc = subprocess.Popen(
            argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=log,
            stderr=subprocess.STDOUT, start_new_session=True,
        )
    except OSError as exc:
        log.write(f"cannot start {argv[0]}: {exc}\n".encode())
        return None, False
    try:
        code = proc.wait(timeout=timeout)
        timed_out = False
    except subprocess.TimeoutExpired:
        code, timed_out = None, True
    finally:
        _stop_group(proc)  # also reaps background stragglers the command left
    return code, timed_out


def _wait_ready(proc: subprocess.Popen, url: str, timeout: int) -> None:
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            raise CannotComplete(f"launch exited with {proc.returncode} before it was ready")
        try:
            with opener.open(url, timeout=2) as resp:
                if resp.status < 400:
                    return
        except (urllib.error.URLError, OSError, ValueError):
            pass
        time.sleep(0.2)
    raise CannotComplete(f"not ready at {url} within {timeout}s")


def _on_signal(signum, _frame):
    raise Interrupted(f"interrupted by signal {signum}")


def _defer_signal(_signum, _frame):
    """During teardown a second signal must not abort the kill of the owned group.

    A Python-level handler (unlike SIG_IGN) resets on exec, so cleanup commands
    still receive SIGTERM normally.
    """


def _evidence_root(common_dir: str, head: str, consumer: str) -> str:
    stamp = _dt.datetime.now(_dt.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    path = os.path.join(common_dir, "idd", "evidence", head, f"{consumer}-{stamp}-{os.getpid()}")
    os.makedirs(path, mode=0o700, exist_ok=False)
    for part in (os.path.join(common_dir, "idd", "evidence"), os.path.dirname(path), path):
        os.chmod(part, 0o700)
    return path


def _list_evidence(root: str) -> list[str]:
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            path = os.path.join(dirpath, name)
            if os.path.isfile(path) and not os.path.islink(path):
                found.append(path)
    return found


def execute(recipe: dict, verdict: dict, repo_root: str, common_dir: str) -> int:
    """Launch, drive, tear down. Fills `verdict` in place; returns the exit code."""
    if not hasattr(os, "killpg"):
        raise CannotComplete("process groups are unsupported on this platform")
    evidence_dir = _evidence_root(common_dir, verdict["head"], verdict["consumer"])
    instance_dir = tempfile.mkdtemp(prefix="idd-recipe-")
    port = _free_port()
    app_url = recipe["app_url"].replace("{port}", str(port)).rstrip("/")
    values = {"{port}": str(port), "{app_url}": app_url, "{instance_dir}": instance_dir,
              "{evidence_dir}": evidence_dir}
    env = dict(os.environ, IDD_PORT=str(port), IDD_APP_URL=app_url,
               IDD_INSTANCE_DIR=instance_dir, IDD_EVIDENCE_DIR=evidence_dir)
    verdict.update(app_url=app_url, evidence_dir=evidence_dir, status="ran")
    ready_url = recipe["ready_url"].replace("{app_url}", app_url)
    if ready_url.startswith("/"):
        ready_url = app_url + ready_url
    code, proc = 0, None
    launch_log = open(os.path.join(evidence_dir, "launch.log"), "wb")
    signals = (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)
    previous = {s: signal.signal(s, _on_signal) for s in signals}
    try:
        try:
            proc = subprocess.Popen(
                _subst(recipe["launch"], values), cwd=repo_root, env=env,
                stdin=subprocess.DEVNULL, stdout=launch_log, stderr=subprocess.STDOUT,
                start_new_session=True,
            )
        except OSError as exc:
            raise CannotComplete(f"launch failed: {exc}") from exc
        verdict["owned"] = {"pgid": proc.pid}
        _wait_ready(proc, ready_url, recipe["ready_timeout"])
        for entry in verdict["capabilities"]:
            if not entry["mapped"]:
                continue
            cap = next(c for c in recipe["capabilities"] if c["name"] == entry["name"])
            cap_dir = os.path.join(evidence_dir, cap["name"])
            os.makedirs(cap_dir, mode=0o700)
            cap_env = dict(env, IDD_EVIDENCE_DIR=cap_dir)
            with open(os.path.join(cap_dir, "drive.log"), "wb") as log:
                exit_code, timed_out = _run_owned(
                    _subst(cap["drive"], dict(values, **{"{evidence_dir}": cap_dir})),
                    repo_root, cap_env, log, cap["timeout_s"],
                )
            entry.update(driven=True, exit=exit_code, timed_out=timed_out)
    except (CannotComplete, Interrupted) as exc:
        verdict.update(status="unavailable", reason=str(exc))
        code = 4
    finally:
        for sig in signals:
            signal.signal(sig, _defer_signal)
        if proc is not None:
            verdict["torn_down"] = _stop_group(proc)
        launch_log.close()
        with open(os.path.join(evidence_dir, "cleanup.log"), "wb") as log:
            for argv in recipe["cleanup"]:
                exit_code, _ = _run_owned(_subst(argv, values), repo_root, env, log, 60)
                verdict["cleanup"].append(exit_code)
        shutil.rmtree(instance_dir, ignore_errors=True)
        for sig, handler in previous.items():
            signal.signal(sig, handler)
    driven = [c for c in verdict["capabilities"] if c["driven"]]
    if verdict["status"] == "ran":
        verdict["result"] = "pass" if all(c["exit"] == 0 for c in driven) else "fail"
    with open(os.path.join(evidence_dir, "verdict.json"), "w", encoding="utf-8") as fh:
        json.dump(verdict, fh, sort_keys=True, indent=2)
    verdict["evidence"] = _list_evidence(evidence_dir)
    return code


def _read_changed(source: str) -> list[str]:
    if source == "-":
        text = sys.stdin.read()
    else:
        with open(source, encoding="utf-8") as fh:
            text = fh.read()
    return [line.strip() for line in text.splitlines() if line.strip()]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-recipe.py",
        description=(
            f"Run the {RECIPE_PATH} verification recipe read from a base ref: launch an "
            "owned app instance, drive the capabilities mapped to the changed files, keep "
            "evidence under the git common dir, tear down only the owned process group."
        ),
        epilog=(
            "Example: git diff --name-only \"origin/${base}\"...HEAD | python3 gi-recipe.py "
            "--ref \"origin/${base}\" --consumer resolve --changed -"
        ),
    )
    parser.add_argument("--ref", required=True, help="base ref the recipe is read from (never the branch under test)")
    parser.add_argument("--consumer", required=True, choices=CONSUMERS, help="calling skill scope")
    parser.add_argument("--changed", required=True, help="file of changed paths, one per line; - for stdin")
    parser.add_argument("--auto", action="store_true", help="auto mode (also implied by IDD_AUTO_MODE=1)")
    parser.add_argument("--plan", action="store_true", help="report mapped capabilities without launching")
    args = parser.parse_args(argv)
    auto = args.auto or os.environ.get("IDD_AUTO_MODE") == "1"
    verdict: dict = {
        "status": "absent", "reason": None, "recipe": None, "ref": args.ref,
        "consumer": args.consumer, "head": None, "capabilities": [], "result": "none",
        "app_url": None, "evidence_dir": None, "evidence": [], "owned": None,
        "torn_down": None, "cleanup": [],
    }
    code = 0
    try:
        changed = _read_changed(args.changed)
        loaded = load_recipe(args.ref)
        if loaded is not None:
            recipe, verdict["recipe"] = loaded
            verdict["capabilities"] = [
                {"name": c["name"], "mapped": mapped(c, changed), "driven": False,
                 "exit": None, "timed_out": False}
                for c in recipe["capabilities"]
            ]
            if auto and args.consumer not in recipe["auto"]:
                verdict.update(status="skipped", reason=f"auto opt-in not set for {args.consumer}")
            elif not any(c["mapped"] for c in verdict["capabilities"]):
                verdict.update(status="skipped", reason="no capability mapped to the changed files")
            elif args.plan:
                verdict["status"] = "planned"
            else:
                repo_root = _git_out("rev-parse", "--show-toplevel")
                verdict["head"] = _git_out("rev-parse", "HEAD")
                common_dir = os.path.abspath(_git_out("rev-parse", "--git-common-dir"))
                code = execute(recipe, verdict, repo_root, common_dir)
    except InvalidRecipe as exc:
        print(f"✗ gi-recipe: {exc}", file=sys.stderr)
        return 3
    except (CannotComplete, Interrupted, OSError) as exc:
        if verdict["evidence_dir"] is None:
            print(f"⚠ gi-recipe: {exc}", file=sys.stderr)
            return 4
        verdict.update(status="unavailable", reason=str(exc))
        code = 4
    if code == 4:
        print(f"⚠ gi-recipe: {verdict['reason']}", file=sys.stderr)
    print(json.dumps(verdict, sort_keys=True))
    return code


if __name__ == "__main__":
    sys.exit(main())
