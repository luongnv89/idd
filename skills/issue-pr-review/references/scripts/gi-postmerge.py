#!/usr/bin/env python3
# gi-requires: references/scripts/gi-gh.py
"""Clean up the local checkout after a PR merged.

A squash merge leaves three things behind locally: the head branch (whose tip
is never an ancestor of the base, so `git branch -d` always refuses it), any
worktree that still has that branch checked out, and a main checkout parked on
a branch that no longer exists upstream. `gh pr merge --delete-branch` handles
some of this, but only in some gh versions, only for the PR it just merged,
and it can exit non-zero after the merge already landed. This script is the
idempotent cleanup every merge site runs afterwards, whoever did the merge.

Usage:  gi-postmerge.py --pr N [--dry-run] [--delete-remote]
                        [--remove-worktree PATH ...]

Run it from anywhere inside the repository, in any of its worktrees. It reads
`gh pr view N --json state,headRefName,headRefOid,baseRefName,isCrossRepository`
and does nothing unless `state` is `MERGED`. Then, all from the MAIN worktree
(the first entry of `git worktree list --porcelain`):

  1. `git fetch --prune origin`, so `origin/<base>` is current and the deleted
     head's remote-tracking ref disappears.
  2. Every linked worktree with the head branch checked out is removed with a
     plain `git worktree remove` — never `--force` on its own. A worktree with
     tracked changes (`dirty`), untracked files (`untracked_files`), ignored
     files (`ignored_files`; a remove deletes them too), an in-progress
     merge/rebase/cherry-pick/bisect, or a lock is kept and reported; the
     status probes pass `--untracked-files=all`, so `status.showUntrackedFiles=no`
     cannot hide a file. A kept untracked/ignored worktree lists its `files`
     (first 20) and `file_count`. A stale entry whose directory is gone is
     pruned.
  3. The main worktree switches to the base branch and fast-forwards it to
     `origin/<base>`, but only when it is on the head branch or already on the
     base, and no operation is in progress there. A dirty tree is stashed
     first (`git stash push -u`), and that exact stash is popped after, the
     sync conventions' stash-first pattern. On any other branch, or detached,
     it stays put: only the local base ref is fast-forwarded, and only when
     that is a fast-forward.
  4. The local head branch is deleted (`git branch -D`) only when nothing has
     it checked out and its tip is the merged head SHA, an ancestor of it, or
     already reachable from `origin/<base>`. A branch with commits the PR
     never had is kept.
  5. With `--delete-remote`, a remote head branch that still points at the
     merged head is deleted. Use it only where the caller's own `gh pr merge
     --delete-branch` merged and gh stopped before deleting it. Never for a
     fork PR.

`--remove-worktree PATH` (repeatable) is the user's confirmation, and the only
way this script deletes untracked or ignored files: that one worktree is
removed with `git worktree remove --force`, after the probes are re-run at
removal time. It is refused (kept, reported) when the worktree now has
tracked changes, a lock, or an operation in progress, or is not a linked
worktree on the merged branch. The rest of the cleanup runs as usual, so the
branch can be deleted in the same run. Never pass it without asking the user.

The head branch is matched by name, except for a fork PR (isCrossRepository):
its name can be an unrelated local branch, so only a local branch at exactly
headRefOid counts, and a same-named branch elsewhere is reported, not touched.
A same-repo head named like the base is never touched.

`--dry-run` runs nothing that changes state (no fetch either) and reports
each step as `planned`, judged against the refs as they are now.

Prints one JSON object:

  {"pr": N, "merged": bool, "dry_run": bool, "branch": str, "base": str,
   "main_worktree": str, "fetch": "ok|failed|skipped|planned",
   "worktrees": [{"path": str, "action": "removed|pruned|kept|planned",
                  "reason": str, "files": [str], "file_count": int}],
   "checkout": {"action": "switched|already|kept|failed|planned",
                "from": str, "reason": str},
   "fast_forward": "updated|up_to_date|diverged|failed|skipped|planned",
   "stash": "none|restored|pop_failed|planned",
   "local_branch": {"action": "deleted|absent|kept|planned", "reason": str},
   "remote_branch": "deleted|absent|kept|skipped|planned",
   "cwd_removed": bool, "ok": bool, "problems": [str, ...]}

`files`/`file_count` appear only on a worktree kept (or force-removed) for
`untracked_files` or `ignored_files`. `ok` is true when every step reached its
goal. Each kept item, failed step, or stash that would not pop adds one line
to `problems`, and that line says how to finish by hand. A stash pop that
conflicts names the unmerged paths and the kept stash.

Exit codes
  0  answered: read `merged` and `ok`, never the exit status. A PR that is
     not merged is an answer (`merged: false`, `ok: false`, nothing touched).
     This script never exits 1.
  2  usage error.
  3  invalid input: `--pr` is not a positive integer.
  4  cannot complete: not inside a git repository (or the current directory
     is gone), gh unavailable or failing, or a PR record that is malformed.
     Raised before any change, except a git failure mid-run, which may leave
     a step done; degrade to the manual procedure in the post-merge cleanup
     doc, which is idempotent.

Authored at src/shared/scripts/gi-postmerge.py. Do not edit installed copies;
edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import runpy
import subprocess
import sys
import time
from pathlib import Path

_RUN_GH = runpy.run_path(str(Path(__file__).with_name("gi-gh.py")))["run_gh"]

REMOTE = "origin"
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
PR_FIELDS = "state,headRefName,headRefOid,baseRefName,isCrossRepository"
FILE_CAP = 20
IN_PROGRESS = (
    "MERGE_HEAD",
    "CHERRY_PICK_HEAD",
    "REVERT_HEAD",
    "BISECT_LOG",
    "rebase-merge",
    "rebase-apply",
)


class InvalidInput(ValueError):
    """The caller's arguments are invalid (exit 3)."""


class Unavailable(RuntimeError):
    """The environment cannot answer (exit 4)."""


def git(args: list[str], cwd: str) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            ["git", "-C", cwd, *args], capture_output=True, text=True, check=False
        )
    except OSError as exc:
        raise Unavailable(f"cannot run git: {exc}") from exc


def ok(args: list[str], cwd: str) -> bool:
    return git(args, cwd).returncode == 0


def out(args: list[str], cwd: str) -> str:
    proc = git(args, cwd)
    return proc.stdout.strip() if proc.returncode == 0 else ""


def first_line(text: str) -> str:
    for line in text.splitlines():
        if line.strip():
            return line.strip()
    return "no output"


def fetch_pr(number: int) -> dict:
    proc = _RUN_GH(["pr", "view", str(number), "--json", PR_FIELDS], Unavailable)
    if proc.returncode != 0:
        raise Unavailable(f"gh pr view {number} failed: {first_line(proc.stderr)}")
    try:
        pr = json.loads(proc.stdout)
    except ValueError as exc:
        raise Unavailable(f"gh pr view {number} returned non-JSON output") from exc
    if not isinstance(pr, dict):
        raise Unavailable(f"gh pr view {number} returned a non-object")
    for key in ("state", "headRefName", "headRefOid", "baseRefName"):
        if not isinstance(pr.get(key), str) or not pr[key]:
            raise Unavailable(f"PR record is missing {key}")
    if not SHA_RE.match(pr["headRefOid"]):
        raise Unavailable("PR headRefOid is not a 40-hex SHA")
    return pr


def valid_branch(name: str, cwd: str) -> bool:
    return not name.startswith("-") and ok(
        ["check-ref-format", "--branch", name], cwd
    )


def worktrees(cwd: str) -> list[dict]:
    """Parse `git worktree list --porcelain`; the first entry is the main one."""
    proc = git(["worktree", "list", "--porcelain"], cwd)
    if proc.returncode != 0:
        raise Unavailable(f"git worktree list failed: {first_line(proc.stderr)}")
    entries: list[dict] = []
    for line in proc.stdout.splitlines():
        if line.startswith("worktree "):
            entries.append({"path": line[len("worktree "):], "branch": None, "head": ""})
        elif not entries:
            continue
        elif line.startswith("HEAD "):
            entries[-1]["head"] = line[len("HEAD "):]
        elif line.startswith("branch refs/heads/"):
            entries[-1]["branch"] = line[len("branch refs/heads/"):]
        elif line == "locked" or line.startswith("locked "):
            entries[-1]["locked"] = True
        elif line == "prunable" or line.startswith("prunable "):
            entries[-1]["prunable"] = True
    if not entries:
        raise Unavailable("git worktree list returned no worktrees")
    return entries


def busy_reason(path: str, ignored: bool = False) -> tuple[str, list[str]]:
    """Why this worktree must not be removed or switched ('' when clean), and
    the untracked/ignored files a forced removal would delete.

    An in-progress operation is checked first: stashing and switching in the
    middle of a staged merge would carry MERGE_HEAD onto the base. The probe
    passes `--untracked-files=all`, so `status.showUntrackedFiles=no` cannot
    hide an untracked file. `ignored` also counts ignored files, which
    `git worktree remove` deletes silently. Tracked changes win (`dirty`),
    then untracked files, then ignored-only.
    """
    git_dir = out(["rev-parse", "--absolute-git-dir"], path)
    if not git_dir:
        return "unreadable", []
    if any(os.path.exists(os.path.join(git_dir, m)) for m in IN_PROGRESS):
        return "operation_in_progress", []
    args = ["status", "--porcelain", "-z", "--untracked-files=all"]
    status = git(args + (["--ignored"] if ignored else []), path)
    if status.returncode != 0:
        return "unreadable", []
    untracked: list[str] = []
    ignored_files: list[str] = []
    for record in status.stdout.split("\0"):
        if not record:
            continue
        code, name = record[:2], record[3:]
        if code == "??":
            untracked.append(name)
        elif code == "!!":
            ignored_files.append(name)
        else:
            # Any tracked change; returning here also skips a rename's
            # second NUL-separated field.
            return "dirty", []
    if untracked:
        return "untracked_files", untracked + ignored_files
    if ignored_files:
        return "ignored_files", ignored_files
    return "", []


def is_inside(child: str, parent: str) -> bool:
    try:
        child_p, parent_p = Path(child).resolve(), Path(parent).resolve()
    except OSError:
        return False
    return child_p == parent_p or parent_p in child_p.parents


def canon(path: str) -> str:
    try:
        return str(Path(path).resolve())
    except OSError:
        return os.path.abspath(path)


def kept_entry(path: str, reason: str, files: list[str]) -> dict:
    entry = {"path": path, "action": "kept", "reason": reason}
    if reason in ("untracked_files", "ignored_files"):
        entry.update(files=files[:FILE_CAP], file_count=len(files))
    return entry


def cleanup(
    number: int, dry_run: bool, delete_remote: bool, remove_worktrees: list[str] | None = None
) -> dict:
    try:
        here = os.getcwd()
    except OSError as exc:
        raise Unavailable("the current directory no longer exists; cd to the main worktree") from exc
    if not ok(["rev-parse", "--git-dir"], here):
        raise Unavailable("not inside a git repository")
    pr = fetch_pr(number)
    branch, base, head_sha = pr["headRefName"], pr["baseRefName"], pr["headRefOid"]
    main = worktrees(here)[0]["path"]
    result: dict = {
        "pr": number,
        "merged": pr["state"] == "MERGED",
        "dry_run": dry_run,
        "branch": branch,
        "base": base,
        "main_worktree": main,
        "fetch": "skipped",
        "worktrees": [],
        "checkout": {"action": "kept", "from": "", "reason": "not_merged"},
        "fast_forward": "skipped",
        "stash": "none",
        "local_branch": {"action": "kept", "reason": "not_merged"},
        "remote_branch": "skipped",
        "cwd_removed": False,
        "ok": True,
        "problems": [],
    }
    problems: list[str] = result["problems"]
    if not result["merged"]:
        result["ok"] = False
        problems.append(f"PR #{number} is {pr['state']}, not MERGED; nothing was touched")
        return result
    if not valid_branch(branch, main) or not valid_branch(base, main):
        raise Unavailable("PR branch names are not valid local branch names")
    fork = bool(pr.get("isCrossRepository"))
    remote_base = f"refs/remotes/{REMOTE}/{base}"
    current = out(["symbolic-ref", "--quiet", "--short", "HEAD"], main)

    def tip(name: str) -> str:
        return out(["rev-parse", "--verify", "--quiet", f"refs/heads/{name}"], main)

    # The local branch that holds the PR head. A fork's head name can be an
    # unrelated local branch (or the base itself, which `gh pr checkout` then
    # renames), so for a fork only a branch at exactly headRefOid counts.
    if fork:
        found = [b for b in (branch, current) if b and b != base and tip(b) == head_sha]
        head_local = found[0] if found else ""
        if not head_local and branch != base and tip(branch):
            problems.append(
                f"local {branch} is not at PR #{number}'s head {head_sha[:7]} (fork PR); "
                f"left alone. Delete it by hand only if it is that PR: git branch -D {branch}"
            )
    else:
        head_local = branch if branch != base else ""

    # 1. Fetch with prune.
    if dry_run:
        result["fetch"] = "planned"
    else:
        proc = git(["fetch", "--prune", REMOTE], main)
        result["fetch"] = "ok" if proc.returncode == 0 else "failed"
        if proc.returncode != 0:
            problems.append(
                f"fetch failed ({first_line(proc.stderr)}); "
                f"retry: git fetch --prune {REMOTE}"
            )
    have_remote_base = ok(["show-ref", "--verify", "--quiet", remote_base], main)

    # 2. Linked worktrees that still hold the head branch. A path in
    #    `confirmed` is the user's yes to deleting its untracked/ignored files.
    confirmed = {canon(p) for p in remove_worktrees or []}
    matched: set[str] = set()
    for entry in worktrees(main)[1:]:
        if not head_local or entry["branch"] != head_local:
            continue
        path = entry["path"]
        if entry.get("prunable"):
            matched.add(canon(path))
            if dry_run:
                result["worktrees"].append({"path": path, "action": "planned", "reason": "prune"})
            elif ok(["worktree", "prune"], main):
                result["worktrees"].append({"path": path, "action": "pruned", "reason": "missing"})
            else:
                result["worktrees"].append({"path": path, "action": "kept", "reason": "prune_failed"})
                problems.append(f"stale worktree entry {path}; run: git worktree prune")
            continue
        if canon(path) in confirmed:
            matched.add(canon(path))
            _remove_confirmed(result, main, here, entry, dry_run)
            continue
        reason, files = ("locked", []) if entry.get("locked") else busy_reason(path, ignored=True)
        if reason in ("untracked_files", "ignored_files"):
            result["worktrees"].append(kept_entry(path, reason, files))
            problems.append(
                f"worktree {path} kept ({reason}: {len(files)} file(s) a removal would delete); "
                f"list them with git -C {path} status --porcelain --untracked-files=all --ignored, "
                f"and remove it only after the user confirms (never in auto mode)"
            )
            continue
        if reason:
            result["worktrees"].append(kept_entry(path, reason, files))
            problems.append(
                f"worktree {path} kept ({reason}); inspect with git -C {path} status, "
                f"then: git worktree remove {path}"
            )
            continue
        if dry_run:
            result["worktrees"].append({"path": path, "action": "planned", "reason": "remove"})
            continue
        proc = git(["worktree", "remove", "--", path], main)
        if proc.returncode == 0:
            result["worktrees"].append({"path": path, "action": "removed", "reason": ""})
            if is_inside(here, path):
                result["cwd_removed"] = True
        else:
            result["worktrees"].append({"path": path, "action": "kept", "reason": "remove_failed"})
            problems.append(
                f"worktree {path} kept ({first_line(proc.stderr)}); "
                f"then: git worktree remove {path}"
            )

    for path in sorted(confirmed - matched):
        result["worktrees"].append({"path": path, "action": "kept", "reason": "not_merged_branch_worktree"})
        problems.append(
            f"--remove-worktree {path}: not a linked worktree on {head_local or branch}; left alone"
        )

    # 3. The main worktree: switch to the base and fast-forward it.
    result["checkout"]["from"] = current or "(detached)"
    holders = {e["branch"]: e["path"] for e in worktrees(main)[1:] if e["branch"]}
    if current and current in (head_local, base):
        switch_needed = current != base
        main_busy = busy_reason(main)[0]
        if main_busy in ("operation_in_progress", "unreadable"):
            result["checkout"].update(action="kept", reason=main_busy)
            problems.append(
                f"{main} has an operation in progress or unreadable state; "
                f"finish or abort it (git -C {main} status), then rerun this cleanup"
            )
        elif switch_needed and base in holders:
            result["checkout"].update(action="kept", reason="base_checked_out_elsewhere")
            problems.append(
                f"{base} is checked out in {holders[base]}; switch that worktree "
                f"off {base}, then: git -C {main} checkout {base}"
            )
        elif dry_run:
            result["checkout"].update(
                action="planned" if switch_needed else "already",
                reason=f"switch to {base}" if switch_needed else "",
            )
            result["fast_forward"] = "planned" if have_remote_base else "skipped"
            if main_busy in ("dirty", "untracked_files"):
                result["stash"] = "planned"
        else:
            _switch_and_update(result, main, base, remote_base, have_remote_base, current)
    else:
        result["checkout"].update(
            action="kept", reason="on_other_branch" if current else "detached"
        )
        if base in holders or not have_remote_base:
            result["fast_forward"] = "skipped"
        elif not ok(["show-ref", "--verify", "--quiet", f"refs/heads/{base}"], main):
            result["fast_forward"] = "skipped"
        elif dry_run:
            result["fast_forward"] = "planned"
        else:
            before = out(["rev-parse", f"refs/heads/{base}"], main)
            proc = git(["fetch", ".", f"{remote_base}:refs/heads/{base}"], main)
            if proc.returncode == 0:
                after = out(["rev-parse", f"refs/heads/{base}"], main)
                result["fast_forward"] = "updated" if after != before else "up_to_date"
            else:
                result["fast_forward"] = "diverged"
                problems.append(
                    f"local {base} has commits not on {REMOTE}/{base}; it was not updated"
                )

    # 4. The local head branch.
    holder = {e["branch"]: e["path"] for e in worktrees(main) if e["branch"]}.get(head_local)
    # A dry run changed nothing, so discount the holders the real run would free.
    freed = {w["path"] for w in result["worktrees"] if w["action"] == "planned"}
    if result["checkout"]["action"] == "planned":
        freed.add(main)
    local_tip = tip(head_local) if head_local else ""
    if not head_local:
        reason = "same_as_base" if branch == base else "not_pr_head"
        result["local_branch"] = {"action": "kept", "reason": reason}
    elif not local_tip:
        result["local_branch"] = {"action": "absent", "reason": ""}
    elif holder and holder not in freed:
        result["local_branch"] = {"action": "kept", "reason": "checked_out"}
        problems.append(
            f"branch {head_local} is still checked out in {holder}; "
            f"switch it off {head_local}, then: git branch -D {head_local}"
        )
    else:
        # A tip behind the merged head, or already in the base, holds nothing
        # the PR did not. A fork branch must match exactly (see head_local).
        merged = local_tip == head_sha or (
            not fork
            and (
                ok(["merge-base", "--is-ancestor", local_tip, head_sha], main)
                or (have_remote_base and ok(["merge-base", "--is-ancestor", local_tip, remote_base], main))
            )
        )
        if not merged:
            result["local_branch"] = {"action": "kept", "reason": "unmerged_commits"}
            problems.append(
                f"branch {head_local} has commits PR #{number} never had "
                f"(tip {local_tip[:7]}, merged head {head_sha[:7]}); review them, then: "
                f"git branch -D {head_local}"
            )
        elif dry_run:
            result["local_branch"] = {"action": "planned", "reason": "delete"}
        elif ok(["branch", "-D", "--", head_local], main):
            result["local_branch"] = {"action": "deleted", "reason": ""}
        else:
            result["local_branch"] = {"action": "kept", "reason": "delete_failed"}
            problems.append(f"could not delete branch {head_local}; run: git branch -D {head_local}")

    # 5. The remote head branch, only on request, and only while it still
    #    points at the merged head: anything pushed after the merge is kept.
    if delete_remote and branch != base and not fork:
        probe = git(["ls-remote", "--exit-code", "--heads", REMOTE, f"refs/heads/{branch}"], main)
        remote_tip = probe.stdout.split()[0] if probe.returncode == 0 and probe.stdout.split() else ""
        if probe.returncode == 2:
            result["remote_branch"] = "absent"
        elif probe.returncode != 0:
            result["remote_branch"] = "kept"
            problems.append(f"could not read {REMOTE}; delete by hand: git push {REMOTE} --delete {branch}")
        elif remote_tip != head_sha:
            result["remote_branch"] = "kept"
            problems.append(
                f"{REMOTE}/{branch} moved past the merged head {head_sha[:7]}; review it, "
                f"then: git push {REMOTE} --delete {branch}"
            )
        elif dry_run:
            result["remote_branch"] = "planned"
        elif ok(["push", REMOTE, "--delete", branch], main):
            result["remote_branch"] = "deleted"
            git(["fetch", "--prune", REMOTE], main)
        else:
            result["remote_branch"] = "kept"
            problems.append(f"could not delete {REMOTE}/{branch}; run: git push {REMOTE} --delete {branch}")

    result["ok"] = not problems
    return result


def _switch_and_update(
    result: dict, main: str, base: str, remote_base: str, have_remote_base: bool, branch: str
) -> None:
    problems: list[str] = result["problems"]
    stashed = ""
    if busy_reason(main)[0] in ("dirty", "untracked_files"):
        stamp = time.strftime("%Y-%m-%dT%H:%M:%S")
        before = out(["rev-parse", "--verify", "--quiet", "refs/stash"], main)
        proc = git(["stash", "push", "-u", "-m", f"post-merge: {branch} {stamp}"], main)
        if proc.returncode != 0:
            result["checkout"].update(action="failed", reason="stash_failed")
            problems.append(f"could not stash local changes ({first_line(proc.stderr)}); stayed on {branch}")
            return
        # `stash push` exits 0 having saved nothing (e.g. only a submodule
        # changed); popping then would apply someone's older stash.
        after = out(["rev-parse", "--verify", "--quiet", "refs/stash"], main)
        if after and after != before:
            stashed = after
    current = out(["symbolic-ref", "--quiet", "--short", "HEAD"], main)
    if current == base:
        result["checkout"].update(action="already", reason="")
    else:
        if ok(["show-ref", "--verify", "--quiet", f"refs/heads/{base}"], main):
            proc = git(["checkout", base], main)
        elif have_remote_base:
            proc = git(["checkout", "-b", base, "--track", f"{REMOTE}/{base}"], main)
        else:
            proc = None
        if proc is None or proc.returncode != 0:
            reason = "no_base_branch" if proc is None else first_line(proc.stderr)
            result["checkout"].update(action="failed", reason=reason)
            problems.append(f"could not switch to {base} ({reason}); run: git checkout {base}")
            _pop(result, main, stashed)
            return
        result["checkout"].update(action="switched", reason="")
    if have_remote_base:
        before = out(["rev-parse", "HEAD"], main)
        proc = git(["merge", "--ff-only", f"{REMOTE}/{base}"], main)
        if proc.returncode == 0:
            after = out(["rev-parse", "HEAD"], main)
            result["fast_forward"] = "updated" if after != before else "up_to_date"
        else:
            result["fast_forward"] = "diverged"
            problems.append(
                f"local {base} has commits not on {REMOTE}/{base}; "
                f"inspect with git log {REMOTE}/{base}..{base}"
            )
    else:
        result["fast_forward"] = "failed"
        problems.append(f"{REMOTE}/{base} is unknown; run: git fetch {REMOTE} && git merge --ff-only {REMOTE}/{base}")
    _pop(result, main, stashed)


def _pop(result: dict, main: str, stashed: str) -> None:
    """Pop the stash this run made, and only while it is still the top entry."""
    if not stashed:
        return
    if out(["rev-parse", "--verify", "--quiet", "refs/stash"], main) != stashed:
        result["stash"] = "pop_failed"
        result["problems"].append(
            f"the stash moved; your changes are in stash entry {stashed[:7]}: "
            "git stash list, then git stash pop <that entry>"
        )
        return
    if ok(["stash", "pop"], main):
        result["stash"] = "restored"
        return
    result["stash"] = "pop_failed"
    conflicted = out(["diff", "--name-only", "--diff-filter=U"], main).splitlines()
    if conflicted:
        result["problems"].append(
            f"stash pop conflicted in {', '.join(conflicted)}; your changes are still in "
            f"stash {stashed[:7]} (git stash list). Restore the clean base with "
            f"git -C {main} reset --merge, then resolve and apply that stash by hand"
        )
    else:
        result["problems"].append(
            f"stash pop failed; your changes are still in stash {stashed[:7]}: "
            "git stash list && git stash show -p stash@{0}"
        )


def _remove_confirmed(result: dict, main: str, here: str, entry: dict, dry_run: bool) -> None:
    """Force-remove one confirmed worktree, re-probing it at removal time.

    Only untracked/ignored files (or nothing) may be lost: tracked changes, a
    lock, or an operation in progress keep it, whatever the user confirmed.
    """
    path = entry["path"]
    reason, files = ("locked", []) if entry.get("locked") else busy_reason(path, ignored=True)
    if reason not in ("", "untracked_files", "ignored_files"):
        result["worktrees"].append(kept_entry(path, reason, files))
        result["problems"].append(
            f"--remove-worktree {path} refused ({reason}); inspect with git -C {path} status"
        )
        return
    record = kept_entry(path, reason, files)
    if dry_run:
        record.update(action="planned", reason=reason or "remove")
        result["worktrees"].append(record)
        return
    proc = git(["worktree", "remove", "--force", "--", path], main)
    if proc.returncode != 0:
        record["reason"] = "remove_failed"
        result["worktrees"].append(record)
        result["problems"].append(
            f"worktree {path} kept ({first_line(proc.stderr)}); inspect with git -C {path} status"
        )
        return
    record.update(action="removed", reason=reason)
    result["worktrees"].append(record)
    if is_inside(here, path):
        result["cwd_removed"] = True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-postmerge.py",
        description=(
            "After a PR merged: prune, remove clean worktrees on its branch, "
            "switch the main checkout to the updated base, and delete the "
            "local branch when it holds nothing the PR did not."
        ),
        epilog="Example: python3 gi-postmerge.py --pr 87",
    )
    parser.add_argument("--pr", required=True, help="the merged PR number")
    parser.add_argument("--dry-run", action="store_true", help="report the plan; change nothing")
    parser.add_argument(
        "--delete-remote",
        action="store_true",
        help="also delete the remote head branch if it still exists",
    )
    parser.add_argument(
        "--remove-worktree",
        action="append",
        default=[],
        metavar="PATH",
        help=(
            "the user confirmed deleting this worktree's untracked/ignored files: "
            "remove it with --force after re-probing; refused on tracked changes, "
            "a lock, an operation in progress, or a path not on the merged branch "
            "(repeatable; never pass it without asking)"
        ),
    )
    args = parser.parse_args(argv)
    try:
        if not re.fullmatch(r"[1-9][0-9]*", args.pr):
            raise InvalidInput(f"--pr must be a positive integer, got {args.pr!r}")
        result = cleanup(int(args.pr), args.dry_run, args.delete_remote, args.remove_worktree)
    except InvalidInput as exc:
        print(f"✗ gi-postmerge: {exc}", file=sys.stderr)
        return 3
    except Unavailable as exc:
        print(f"⚠ gi-postmerge: {exc}", file=sys.stderr)
        return 4
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
