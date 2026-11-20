#!/usr/bin/env python3
"""Render and read the plan and claim comments of the plan-and-claim protocol.

The protocol (when to post, who may approve, how a claim is written and
released) lives in the plan-and-claim runtime doc. This script owns the comment
formats and the verdicts read from them, so a plan's freshness, its approval and
a claim's owner are computed, never judged.

Body hash
  sha256 over the issue body with CRLF turned into LF, every line's trailing
  whitespace removed and the whole text stripped; the first 16 hex digits.
  A plan whose marker hash differs from the live body's is `stale`.

Plan comment (render-plan writes it; check reads it back)

  <!-- idd:plan v1 body=<hash16> -->
  ### Plan: <name>
  Summary: <summary>
  **Files**
  - modify `<path>` — <changes>
  - create `<path>` — <purpose>
  **Tasks**
  - [ ] <task> (criteria: AC1, AC3; files: `<path>`, `<path>`)
  **Acceptance criteria**
  - AC1: <criterion text>
  **Covers:** AC1, AC3
  **Tests:** <test strategy>
  **Risks:** <risk details>

  Blank lines between the parts are allowed; a closing note line is ignored.
  The marker is the comment's first line. Every rendered value is one line:
  newlines become spaces and every `<!--` and `-->` is removed, so no value
  can forge a marker or start a section. Criterion ids are `AC<n>`, the ids
  the readiness script numbers. Without `tasks`, each file becomes one task
  carrying the option's `criteria_covered`.

Claim comment (render-claim writes it) and release comment (render-release)

  <!-- idd:claim v1 run=<run> branch=<branch> -->
  <one line naming the run and the branch>

  <!-- idd:claim-released v1 run=<run> branch=<branch> -->
  <one line naming the run that let its claim go>

  A release comment closes every earlier claim marker by the same login for
  the same run, so a claim that ended stops counting the moment it is closed.

Subcommands
  render-plan   [--issue FILE] stdin {"body", "criteria": [{"id", "text"}], "option": {"name",
                "summary", "files_to_modify": [{"path", "changes"} | path],
                "files_to_create": [{"path", "purpose"} | path],
                "criteria_covered": [id], "test_strategy", "risk_details"},
                "tasks"?: [{"task", "criteria": [id], "files": [path]}]}
                → the plan comment on stdout. With --issue, the body is read from
                FILE (`gh issue view --json body` output or a gi-issue.py
                envelope) instead of stdin's `body`, so the hash is the live
                body's, never a retyped copy.
  render-claim  --run R --branch B → the claim comment on stdout.
  render-release --run R --branch B → the release comment on stdout.
  check         --login L [--run R] [--branch B] [--claim-label X]
                [--approved-label A] [--race-window S]; stdin the issue as
                `gh issue view --json body,labels,comments` prints it, or a
                gi-issue.py envelope {"issue": {...}} → one JSON line:
                  {"plan": "absent|current|stale", "superseded": bool, "approved": bool,
                   "plan_hash", "body_hash", "name", "summary",
                   "files_to_modify", "files_to_create", "tasks", "criteria",
                   "criteria_covered", "test_strategy", "risk_details",
                   "claim": "none|own|foreign", "claim_run", "claim_branch",
                   "claim_login", "claim_age_s"}
  conform       stdin {"files_to_modify", "files_to_create", "tasks",
                "changed": [path]} (check's output plus `changed`) → one JSON
                line {"out_of_plan": [path], "tasks_without_change": [task]}.

Check rules
  * Trust: a plan marker counts only in a comment whose author login is
    `--login`. Of those, the newest wins (by createdAt; list order when a
    timestamp is missing). `current` when its hash equals the live body's.
    A plan marker posted after it by another writer login (the claim rule's
    authorAssociation filter) supersedes it: `plan` reads `stale` and
    `superseded` true, because `plan-approved` is issue-wide and approves the
    newest plan, never an older one.
  * `approved` is true only when the `--approved-label` (default
    `plan-approved`) is on the issue and the plan is `current`.
  * Claim. No `--claim-label` value on the issue (or `--claim-label ""`) →
    `none`: a marker without the label claims nothing. With the label, `mine`
    is the newest live claim marker by `--login` whose run is `--run` (or
    whose branch is `--branch`, when given). No `mine` → `foreign`. Otherwise
    `own`, unless a live marker for another run, by any login, precedes
    `mine` within `--race-window` seconds (default 600) — the first writer
    wins — or follows it by more than that window (that later claim reads
    itself own), so two live claims never both read `own`. A marker by another
    login can make a claim `foreign`, never `own`. On a bound resume
    (`--branch`), an earlier marker by `--login` for that branch is this
    run's own earlier attempt, never a racer; and when no live marker is
    left and the newest closed one is `--login`'s for that branch, the claim
    reads `own` — a resume killed between its release comment and the label
    removal still owns the label. `claim_run`, `claim_branch` and
    `claim_age_s` (and `claim_login`, its author) describe the claim read: `mine` when own, else the marker
    it yields to (the earliest racer, or the newest live marker), null when
    none.
  * Live markers only. A claim marker never counts when its run or branch is
    outside its grammar, when a release comment closed it, or when its
    author is another login whose `authorAssociation` is present and is not
    OWNER, MEMBER or COLLABORATOR — an account that cannot add the label
    cannot hold the claim.
  * `--login ""` (the login could not be read): no comment is trusted, so
    every plan reads `absent` and the claim `foreign` when the label is on
    the issue, `none` otherwise.

Exit codes
  0  rendered or judged — read the JSON, never the exit status. This script
     never exits 1.
  2  usage error.
  3  invalid input — a malformed argument (run, branch, login or label
     outside its grammar), stdin JSON of the wrong shape, or a plan with no
     name, no files or a criterion id outside `AC<n>`.
  4  cannot complete — stdin empty or unreadable. Callers follow the manual
     procedure in the plan-and-claim doc.

Authored at src/shared/scripts/gi-plan.py — do not edit installed copies;
edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone

RUN_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")
BRANCH_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._/-]{0,99}")
LOGIN_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]{0,38}(?:\[bot\])?")
LABEL_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,49}")
ID_RE = re.compile(r"AC[1-9][0-9]{0,3}")
PLAN_MARKER_RE = re.compile(r"<!-- idd:plan v1 body=([0-9a-f]{16}) -->")
CLAIM_MARKER_RE = re.compile(r"<!-- idd:claim v1 run=(\S+) branch=(\S+) -->")
RELEASE_MARKER_RE = re.compile(r"<!-- idd:claim-released v1 run=(\S+) branch=(\S+) -->")
WRITERS = {"OWNER", "MEMBER", "COLLABORATOR"}
FILE_LINE_RE = re.compile(r"- (modify|create) `([^`]+)`(?: — (.*))?")
TASK_LINE_RE = re.compile(r"- \[[ xX]\] (.+) \(criteria: ([A-Za-z0-9, ]*); files: (.*)\)")
CRITERION_LINE_RE = re.compile(r"- (AC[1-9][0-9]{0,3}): (.*)")
SECTIONS = {"**Files**": "files", "**Tasks**": "tasks", "**Acceptance criteria**": "criteria"}
FIELDS = {"Summary: ": "summary", "**Covers:** ": "covers", "**Tests:** ": "test_strategy",
          "**Risks:** ": "risk_details"}
TEXT_MAX = 2000


class InvalidInput(ValueError):
    """An argument or stdin is not of the documented shape (exit 3)."""


class CannotComplete(OSError):
    """stdin is empty or unreadable (exit 4)."""


def body_hash(body: str) -> str:
    lines = (body or "").replace("\r\n", "\n").split("\n")
    text = "\n".join(line.rstrip() for line in lines).strip()
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def clean(value: object, where: str, limit: int = TEXT_MAX) -> str:
    """One rendered line: no newline, no comment delimiter, bounded."""
    if value is None:
        return ""
    if not isinstance(value, (str, int, float)) or isinstance(value, bool):
        raise InvalidInput(f"{where} must be text")
    text = str(value)
    while "<!--" in text or "-->" in text:
        text = text.replace("<!--", "").replace("-->", "")
    return re.sub(r"\s+", " ", text).strip()[:limit]


def clean_path(value: object, where: str) -> str:
    path = clean(value, where, 300).replace("`", "")
    if not path:
        raise InvalidInput(f"{where} is empty")
    return path


def ids(value: object, where: str) -> list[str]:
    if not isinstance(value, list) or not all(isinstance(i, str) for i in value):
        raise InvalidInput(f"{where} must be a list of criterion ids")
    out = [i.strip().upper() for i in value]
    bad = [i for i in out if not ID_RE.fullmatch(i)]
    if bad:
        raise InvalidInput(f"{where} has an id outside AC<n>: {', '.join(bad)}")
    return list(dict.fromkeys(out))


def _files(option: dict, key: str, note_key: str) -> list[tuple[str, str]]:
    raw = option.get(key, [])
    if not isinstance(raw, list):
        raise InvalidInput(f"option.{key} must be a list")
    out = []
    for item in raw:
        if isinstance(item, dict):
            out.append((clean_path(item.get("path"), f"option.{key}[].path"),
                        clean(item.get(note_key), f"option.{key}[].{note_key}", 500)))
        else:
            out.append((clean_path(item, f"option.{key}[]"), ""))
    return out


def render_plan(payload: object, issue_file: str | None = None) -> str:
    if not isinstance(payload, dict):
        raise InvalidInput("stdin must be a JSON object")
    body, option = payload.get("body"), payload.get("option")
    if issue_file is not None:
        try:
            with open(issue_file, encoding="utf-8") as fh:
                text = fh.read()
        except UnicodeDecodeError as exc:
            raise InvalidInput(f"--issue is not UTF-8: {exc}") from exc
        if not text.strip():
            raise CannotComplete("--issue file is empty")
        try:
            body = _issue(json.loads(text)).get("body") or ""
        except ValueError as exc:
            raise InvalidInput(f"--issue is not JSON: {exc}") from exc
    if not isinstance(body, str):
        raise InvalidInput("`body` must be the issue body as a string")
    if not isinstance(option, dict):
        raise InvalidInput("`option` must be an object")
    name = clean(option.get("name"), "option.name", 200)
    if not name:
        raise InvalidInput("option.name is empty")
    modify = _files(option, "files_to_modify", "changes")
    create = _files(option, "files_to_create", "purpose")
    if not modify and not create:
        raise InvalidInput("the option names no files")
    covered = ids(option.get("criteria_covered", []), "option.criteria_covered")
    raw_criteria = payload.get("criteria", [])
    if not isinstance(raw_criteria, list):
        raise InvalidInput("`criteria` must be a list")
    criteria = []
    for n, item in enumerate(raw_criteria, 1):
        if isinstance(item, dict):
            cid = ids([item.get("id") if isinstance(item.get("id"), str) else ""], "criteria[].id")[0]
            criteria.append((cid, clean(item.get("text"), "criteria[].text")))
        else:
            criteria.append((f"AC{n}", clean(item, "criteria[]")))
    tasks = payload.get("tasks")
    if tasks is None:
        tasks = [{"task": f"{'Modify' if i < len(modify) else 'Create'} `{path}`"
                         + (f": {note}" if note else ""),
                  "criteria": covered, "files": [path]}
                 for i, (path, note) in enumerate(modify + create)]
    if not isinstance(tasks, list):
        raise InvalidInput("`tasks` must be a list")
    lines = [f"<!-- idd:plan v1 body={body_hash(body)} -->", f"### Plan: {name}"]
    summary = clean(option.get("summary"), "option.summary")
    if summary:
        lines.append(f"Summary: {summary}")
    lines += ["", "**Files**", ""]
    lines += [f"- modify `{p}`" + (f" — {n}" if n else "") for p, n in modify]
    lines += [f"- create `{p}`" + (f" — {n}" if n else "") for p, n in create]
    lines += ["", "**Tasks**", ""]
    for task in tasks:
        if not isinstance(task, dict):
            raise InvalidInput("each task must be an object")
        text = clean(task.get("task"), "tasks[].task", 500).replace(" (criteria: ", " (")
        if not text:
            raise InvalidInput("a task has no text")
        crit = ids(task.get("criteria", []), "tasks[].criteria")
        files = task.get("files", [])
        if not isinstance(files, list):
            raise InvalidInput("tasks[].files must be a list")
        listed = ", ".join(f"`{clean_path(f, 'tasks[].files[]')}`" for f in files) or "none"
        lines.append(f"- [ ] {text} (criteria: {', '.join(crit)}; files: {listed})")
    if criteria:
        lines += ["", "**Acceptance criteria**", ""]
        lines += [f"- {cid}: {text}" for cid, text in criteria]
    lines += ["", f"**Covers:** {', '.join(covered) or 'none'}"]
    lines.append(f"**Tests:** {clean(option.get('test_strategy'), 'option.test_strategy') or 'none'}")
    lines.append(f"**Risks:** {clean(option.get('risk_details'), 'option.risk_details') or 'none'}")
    lines += ["", "_Approve with the `plan-approved` label. Editing the issue body makes this plan stale._"]
    return "\n".join(lines) + "\n"


def render_claim(run: str, branch: str) -> str:
    return (f"<!-- idd:claim v1 run={run} branch={branch} -->\n"
            f"Claimed by IDD Stack run `{run}` on branch `{branch}`. "
            "Removing the claim label releases it.\n")


def render_release(run: str, branch: str) -> str:
    return (f"<!-- idd:claim-released v1 run={run} branch={branch} -->\n"
            f"Released by IDD Stack run `{run}` on branch `{branch}`.\n")


def parse_plan(text: str) -> dict:
    plan: dict = {"name": None, "summary": None, "files_to_modify": [], "files_to_create": [],
                  "tasks": [], "criteria": [], "criteria_covered": [], "test_strategy": None,
                  "risk_details": None}
    section = None
    for line in text.replace("\r\n", "\n").split("\n")[1:]:
        line = line.rstrip()
        if line.startswith("### Plan: ") and plan["name"] is None:
            plan["name"] = line[len("### Plan: "):]
            continue
        if line in SECTIONS:
            section = SECTIONS[line]
            continue
        field = next((key for key in FIELDS if line.startswith(key)), None)
        if field:
            section = None
            value = line[len(field):]
            if FIELDS[field] == "covers":
                plan["criteria_covered"] = [i for i in re.split(r"[,\s]+", value) if ID_RE.fullmatch(i)]
            else:
                plan[FIELDS[field]] = value
            continue
        if section == "files" and (m := FILE_LINE_RE.fullmatch(line)):
            plan["files_to_modify" if m.group(1) == "modify" else "files_to_create"].append(m.group(2))
        elif section == "tasks" and (m := TASK_LINE_RE.fullmatch(line)):
            plan["tasks"].append({
                "task": m.group(1),
                "criteria": [i for i in re.split(r"[,\s]+", m.group(2)) if ID_RE.fullmatch(i)],
                "files": re.findall(r"`([^`]+)`", m.group(3)),
            })
        elif section == "criteria" and (m := CRITERION_LINE_RE.fullmatch(line)):
            plan["criteria"].append({"id": m.group(1), "text": m.group(2)})
    return plan


def _when(value: object) -> float | None:
    if not isinstance(value, str):
        return None
    try:
        stamp = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=timezone.utc)
    return stamp.timestamp()


def _issue(payload: object) -> dict:
    if isinstance(payload, dict) and isinstance(payload.get("issue"), dict):
        payload = payload["issue"]
    if not isinstance(payload, dict):
        raise InvalidInput("stdin must be an issue object")
    for key, kind in (("labels", list), ("comments", list)):
        if not isinstance(payload.get(key, []), kind):
            raise InvalidInput(f"`{key}` must be a list")
    if not isinstance(payload.get("body") or "", str):
        raise InvalidInput("`body` must be a string")
    return payload


def _markers(comments: list) -> list[dict]:
    """Every comment as {login, assoc, body, at, index}, oldest first."""
    rows = []
    for index, comment in enumerate(comments):
        if not isinstance(comment, dict) or not isinstance(comment.get("body"), str):
            continue
        author = comment.get("author")
        login = author.get("login") if isinstance(author, dict) else None
        assoc = comment.get("authorAssociation")
        rows.append({"login": login if isinstance(login, str) else None, "body": comment["body"],
                     "assoc": assoc if isinstance(assoc, str) else None,
                     "at": _when(comment.get("createdAt")), "index": index})
    if all(row["at"] is not None for row in rows):
        rows.sort(key=lambda row: (row["at"], row["index"]))
    return rows


def _first_line(body: str) -> str:
    return body.lstrip().split("\n", 1)[0].strip()


def check(payload: object, args: argparse.Namespace) -> dict:
    issue = _issue(payload)
    labels = {item.get("name") if isinstance(item, dict) else item for item in issue.get("labels", [])}
    rows = _markers(issue.get("comments", []))
    live = body_hash(issue.get("body") or "")
    def writer(row: dict) -> bool:
        return bool(args.login and row["login"] == args.login) or row["assoc"] is None or row["assoc"] in WRITERS

    plans = [row for row in rows if args.login and row["login"] == args.login
             and PLAN_MARKER_RE.fullmatch(_first_line(row["body"]))]
    result: dict = {"plan": "absent", "approved": False, "plan_hash": None, "body_hash": live,
                    "superseded": False}
    parsed = parse_plan("")
    if plans:
        newest = plans[-1]
        result["plan_hash"] = PLAN_MARKER_RE.fullmatch(_first_line(newest["body"])).group(1)
        result["plan"] = "current" if result["plan_hash"] == live else "stale"
        later = rows[rows.index(newest) + 1:]
        if any(row["login"] != args.login and writer(row)
               and PLAN_MARKER_RE.fullmatch(_first_line(row["body"])) for row in later):
            result["plan"], result["superseded"] = "stale", True
        parsed = parse_plan(newest["body"].lstrip())
        result["approved"] = args.approved_label in labels and result["plan"] == "current"
    result.update(parsed)
    result.update({"claim": "none", "claim_run": None, "claim_branch": None, "claim_login": None,
                   "claim_age_s": None})
    if not args.claim_label or args.claim_label not in labels:
        return result
    claims, closed = [], []
    for seq, row in enumerate(rows):
        first = _first_line(row["body"])
        released = RELEASE_MARKER_RE.fullmatch(first)
        if released and row["login"]:
            ended = [c for c in claims if c["login"] == row["login"] and c["run"] == released.group(1)]
            closed += ended
            claims = [c for c in claims if c not in ended]
            continue
        m = CLAIM_MARKER_RE.fullmatch(first)
        if m and writer(row) and RUN_RE.fullmatch(m.group(1)) and BRANCH_RE.fullmatch(m.group(2)):
            claims.append({**row, "run": m.group(1), "branch": m.group(2), "seq": seq})
    mine = None
    for pos, row in enumerate(claims):
        if args.login and row["login"] == args.login and (
            (args.branch is not None and row["branch"] == args.branch)
            or (args.run is not None and row["run"] == args.run)
        ):
            mine = (pos, row)
    def other(row: dict, own: dict) -> bool:
        return row["run"] != own["run"] and not (
            args.branch is not None and row["login"] == args.login and row["branch"] == args.branch)

    held = None
    last_closed = max(closed, key=lambda c: c["seq"]) if closed else None
    if mine is None and not claims and args.branch is not None and last_closed is not None \
            and last_closed["login"] == args.login and last_closed["branch"] == args.branch:
        # A bound resume killed between its release comment and the label
        # removal: no live marker is left, so the label is still its own.
        result["claim"] = "own"
        held = last_closed
    elif mine is None:
        result["claim"] = "foreign"
        held = claims[-1] if claims else None
    else:
        pos, own = mine
        racers = [row for row in claims[:pos] if other(row, own) and (
            row["at"] is None or own["at"] is None or own["at"] - row["at"] <= args.race_window)]
        # A live marker posted more than the window after mine reads itself
        # own, so mine yields to it: two live claims never both read own.
        racers += [row for row in claims[pos + 1:] if other(row, own) and row["at"] is not None
                   and own["at"] is not None and row["at"] - own["at"] > args.race_window]
        result["claim"] = "foreign" if racers else "own"
        held = racers[0] if racers else own
    if held is not None:
        result["claim_run"], result["claim_branch"] = held["run"], held["branch"]
        result["claim_login"] = held["login"]
        if held["at"] is not None:
            now = datetime.now(timezone.utc).timestamp()
            result["claim_age_s"] = max(0, int(now - held["at"]))
    return result


def conform(payload: object) -> dict:
    if not isinstance(payload, dict):
        raise InvalidInput("stdin must be a JSON object")
    lists = {key: payload.get(key, []) for key in ("files_to_modify", "files_to_create", "changed", "tasks")}
    for key, value in lists.items():
        if not isinstance(value, list):
            raise InvalidInput(f"`{key}` must be a list")
    planned = {p for p in lists["files_to_modify"] + lists["files_to_create"] if isinstance(p, str)}
    changed = [p for p in lists["changed"] if isinstance(p, str)]
    out_of_plan = [p for p in dict.fromkeys(changed) if p not in planned]
    missing = []
    for task in lists["tasks"]:
        if not isinstance(task, dict) or not isinstance(task.get("files"), list):
            raise InvalidInput("each task needs a `files` list")
        if task["files"] and not any(f in changed for f in task["files"]):
            missing.append(task.get("task"))
    return {"out_of_plan": out_of_plan, "tasks_without_change": missing}


def _stdin() -> object:
    buffer = getattr(sys.stdin, "buffer", None)
    raw = buffer.read() if buffer is not None else sys.stdin.read().encode()
    if not raw.strip():
        raise CannotComplete("stdin is empty")
    try:
        return json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as exc:
        raise InvalidInput(f"stdin is not UTF-8 JSON: {exc}") from exc


def _screen(value: str | None, pattern: re.Pattern, flag: str, empty_ok: bool = False) -> None:
    if value is None or (empty_ok and value == ""):
        return
    if not pattern.fullmatch(value):
        raise InvalidInput(f"{flag} is outside its grammar")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-plan.py",
        description="Render and read plan and claim comments. Formats and rules: this script's docstring.",
        epilog="Example: python3 gi-plan.py check --login octocat --run resolver-20261119T101500Z-1a2b "
               "--claim-label agent:working < .idd/cache/plan-issue-12.json",
    )
    sub = parser.add_subparsers(dest="command", required=True)
    plan = sub.add_parser("render-plan", help="render a plan comment from stdin JSON")
    plan.add_argument("--issue", metavar="FILE", help="read the issue body from this JSON file")
    for name, what in (("render-claim", "a claim"), ("render-release", "a release")):
        claim = sub.add_parser(name, help=f"render {what} comment")
        claim.add_argument("--run", required=True)
        claim.add_argument("--branch", required=True)
    chk = sub.add_parser("check", help="read the plan and claim state of an issue on stdin")
    chk.add_argument("--login", required=True, help='the authenticated GitHub login; "" when it cannot be read')
    chk.add_argument("--run", help="this run's id")
    chk.add_argument("--branch", help="this run's branch (a bound resume)")
    chk.add_argument("--claim-label", default="agent:working", help='claim label; "" turns the claim off')
    chk.add_argument("--approved-label", default="plan-approved")
    chk.add_argument("--race-window", type=int, default=600, help="seconds (default 600)")
    sub.add_parser("conform", help="compare a plan with a PR's changed files")
    args = parser.parse_args(argv)
    try:
        if args.command in ("render-claim", "render-release"):
            _screen(args.run, RUN_RE, "--run")
            _screen(args.branch, BRANCH_RE, "--branch")
            render = render_claim if args.command == "render-claim" else render_release
            sys.stdout.write(render(args.run, args.branch))
            return 0
        if args.command == "check":
            _screen(args.login, LOGIN_RE, "--login", empty_ok=True)
            _screen(args.run, RUN_RE, "--run")
            _screen(args.branch, BRANCH_RE, "--branch")
            _screen(args.claim_label, LABEL_RE, "--claim-label", empty_ok=True)
            _screen(args.approved_label, LABEL_RE, "--approved-label")
            if args.race_window < 0:
                raise InvalidInput("--race-window must be >= 0")
        payload = _stdin()
        if args.command == "render-plan":
            sys.stdout.write(render_plan(payload, args.issue))
            return 0
        result = check(payload, args) if args.command == "check" else conform(payload)
    except InvalidInput as exc:
        print(f"✗ gi-plan: {exc}", file=sys.stderr)
        return 3
    except OSError as exc:
        print(f"⚠ gi-plan: {exc}", file=sys.stderr)
        return 4
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
