#!/usr/bin/env python3
# gi-requires: references/scripts/gi-gh.py
"""Report run outcomes and the post-merge look-back from the local run log.

`/auto-pilot --stats` runs this from the repository root. It reads
`.idd/runs.jsonl` (plus the newest rotated `runs-*.jsonl` segments) and one
`git log` walk of the default branch, and prints:

  - run outcomes: rows, outcome counts, success rate, unexplained QA ceiling
    breaches, the slowest recorded phase;
  - the look-back after merge (VW19, issue #568), per release and in total:
    merged runs, unconfirmed merges, reverts, reopened issues, follow-up bugs,
    planned follow-ups, and the flagged count and rate.

It is read-only. It never opens a file for writing, creates a directory, takes
a lock, writes a cache, fetches, or switches a branch; every git call runs with
GIT_OPTIONAL_LOCKS=0, so not even git's opportunistic index refresh writes.

One source. The collectors are a verbatim mirror of `scripts/idd-lint.py`:
idd-lint stays a self-contained single file that users `curl` and run, and this
script carries the same function source byte for byte, so the two reports
cannot drift. `tests/test-stats-573.sh` compares every mirrored definition and
the two reports' `runs` and `lookback` objects on one fixture.

The walked ref. By default the walk is `origin/<default>` when that
remote-tracking ref exists, else the local default branch (`origin/HEAD`, else
`main`, else `master`). `--branch REF` walks REF instead. The report names the
ref, its tip sha and its commit date. When the local default branch and
`origin/<default>` differ, or a logged run's merge commit on GitHub is not in
the walk, it warns: the remote-tracking ref is only as fresh as the last
`git fetch`, which this script never runs.

GitHub. Unless `--no-github` is given, exactly two read-only gh calls fetch the
look-back pages, through gi-gh.py:

    gh pr list --state merged --limit <limit> --json number,body,mergedAt,mergeCommit
    gh issue list --state all --limit <max(limit, 500)> --json <ISSUE_PAGE_FIELDS>

idd-lint reaches the same two pages only behind its normalization sections;
this script fetches them directly, deliberately, because those sections are not
part of this report. When gh is missing, unauthenticated or offline, the report
says why under `github_skipped`, and the GitHub-only counts are null, never 0.

Output. A compact text report by default. `--json` prints one object, keys
sorted:

    {"github_skipped": null | "<reason>", "lookback": {...} | null,
     "runs": {...} | null, "walked": {"ref", "sha", "date"} | null,
     "warnings": [...]}

`runs` and `lookback` have exactly the shape of `idd-lint stats --json`.

Exit codes
  0  a report was printed — also for an empty or missing run log, and for
     QA ceiling breaches, which are data here, not a verdict
  2  usage error, including a --branch that does not resolve
  4  cannot complete — not inside a git repository, or no git on PATH
     (stderr: `⚠ gi-stats: <reason>`). Callers count the run log by hand.

Authored at src/shared/scripts/gi-stats.py — do not edit installed copies;
edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import runpy
import statistics
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import NamedTuple

_RUN_GH = runpy.run_path(str(Path(__file__).with_name("gi-gh.py")))["run_gh"]


class Unavailable(Exception):
    """The report cannot be produced — exit 4."""


class UsageError(Exception):
    """A command-line value is unusable — exit 2."""


# --- Mirrored from scripts/idd-lint.py -----------------------------------------
# Byte-identical definitions; tests/test-stats-573.sh (T3) fails on any drift.
# Change them in scripts/idd-lint.py first, then copy the definition here.

SECTION_RE = re.compile(r"^## +(.+?)\s*$")
CONFIDENCE_RE = re.compile(r"\((?:high|medium) confidence\)|\(needs review\)")
SOFT_COMMAND_TIMEOUT_SECONDS = 60
MIN_ISSUE_FETCH_LIMIT = 500
DEFAULT_GITHUB_FETCH_LIMIT = 200
MAX_RUN_SEGMENTS = 10


def split_sections(text: str) -> dict[str, str]:
    """Split a markdown body into {heading: content} on `## ` headings.
    Content before the first heading is stored under ''. First heading wins
    on duplicates."""
    sections: dict[str, str] = {}
    current = ""
    buf: list[str] = []
    for line in text.splitlines():
        m = SECTION_RE.match(line)
        if m:
            if current not in sections:
                sections[current] = "\n".join(buf)
            current = m.group(1)
            buf = []
        else:
            buf.append(line)
    if current not in sections:
        sections[current] = "\n".join(buf)
    return sections


def strip_confidence(value: str) -> str:
    return CONFIDENCE_RE.sub("", value).strip()


def first_content_line(text: str) -> str:
    for line in text.splitlines():
        if line.strip():
            return line.strip()
    return ""


CLOSING_KEYWORD_RE = r"(?i)\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\s+#{n}\b"
SUCCESS_OUTCOMES = {"success", "merged"}
SKIP_OUTCOMES = {"skipped", "already_resolved", "revert_opened"}
ISSUE_PAGE_FIELDS = "number,body,state,stateReason,createdAt,labels,title"


def _run_soft(cmd: list[str], input_text: str | None = None) -> str | None:
    """Run a command, returning stdout or None on any failure (soft probe)."""
    try:
        proc = subprocess.run(
            cmd,
            input=input_text,
            capture_output=True,
            text=True,
            timeout=SOFT_COMMAND_TIMEOUT_SECONDS,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        return None
    return proc.stdout if proc.returncode == 0 else None


def _merged_at_epoch(value: object) -> int | None:
    """`2026-08-14T19:33:53Z` → Unix timestamp; None when unparsable."""
    if not isinstance(value, str):
        return None
    try:
        dt = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        return None
    return int(dt.replace(tzinfo=timezone.utc).timestamp())


def _pct(n: int, d: int) -> int | None:
    return round(100 * n / d) if d else None


def _median(values: list) -> float | None:
    return statistics.median(values) if values else None


def detect_default_branch() -> str:
    out = _run_soft(["git", "rev-parse", "--abbrev-ref", "origin/HEAD"])
    if out and "/" in out.strip():
        return out.strip().split("/", 1)[1]
    for cand in ("main", "master"):
        if _run_soft(["git", "rev-parse", "--verify", "--quiet", cand]) is not None:
            return cand
    return "HEAD"


DEFAULT_HIGH_CEILING = 5


def policy_ceiling(profile: object, complexity: object, *, high: int = DEFAULT_HIGH_CEILING) -> int:
    """light → 1; full+high → high (default 5); omitted profile/complexity → 2."""
    if profile == "light":
        return 1
    if complexity == "high":
        return high
    return 2


def row_ceiling(row: dict) -> int:
    recorded = row.get("ceiling")
    if isinstance(recorded, int) and not isinstance(recorded, bool) and recorded >= 1:
        return recorded
    return policy_ceiling(row.get("profile"), row.get("complexity"))


def _unexplained_ceiling_breach(row: dict) -> bool:
    qa = row.get("qa_cycles")
    if not isinstance(qa, int) or isinstance(qa, bool):
        return False
    if qa <= row_ceiling(row):
        return False
    reason = row.get("breach_reason")
    return not (isinstance(reason, str) and reason.strip())


def load_run_rows(path: Path) -> list[dict] | None:
    """Parse the run log exactly once — active file plus rotated segments.

    Rotation (F-PERF-006) splits one append-only file into timestamped
    `runs-*.jsonl` segments plus the fresh active log, so a reader that opens
    only the active path silently loses every record before the last rotation.
    This reads the same bounded tail gi-runlog scans — newest segments first,
    oldest to newest, then the active file — and skips malformed lines with the
    no-schema-migration tolerance every runs.jsonl reader shares. Returns None
    when nothing anywhere parsed to a row.
    """
    segments = sorted(
        candidate
        for candidate in path.parent.glob(f"{path.stem}-*.jsonl")
        if candidate.is_file()
    )
    rows: list[dict] = []
    for candidate in (*segments[-MAX_RUN_SEGMENTS:], path):
        if not candidate.is_file():
            continue
        try:
            text = candidate.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(row, dict):
                rows.append(row)
    return rows or None


def collect_phase_stats(rows: list[dict]) -> dict[str, dict]:
    """Per-phase seconds across rows carrying the optional `phases` map (#467).

    Tolerant like every runs.jsonl reader: the raw-append fallback bypasses
    gi-runlog's validation, so a non-object `phases` or an entry that is not a
    non-negative integer is skipped, never raised on.
    """
    seconds: dict[str, list[int]] = {}
    for r in rows:
        phases = r.get("phases")
        if not isinstance(phases, dict):
            continue
        for name, value in phases.items():
            if (
                isinstance(name, str)
                and isinstance(value, int)
                and not isinstance(value, bool)
                and value >= 0
            ):
                seconds.setdefault(name, []).append(value)
    return {
        name: {"runs": len(values), "median_s": _median(values), "total_s": sum(values)}
        for name, values in seconds.items()
    }


def slowest_phase(phases: dict[str, dict]) -> str | None:
    """The phase with the highest median; ties go to the larger total, then name."""
    if not phases:
        return None
    return min(
        phases,
        key=lambda name: (-phases[name]["median_s"], -phases[name]["total_s"], name),
    )


def collect_skill_costs(rows: list[dict]) -> dict[str, dict]:
    """Per writing skill: runs, token samples, and median tokens (issue #562).

    A release records one median per flow in the release-costs.md doc, and this
    is where it is read. Only a row that carries a host-reported `tokens`
    count is a sample; `median_tokens` is None when a skill has none — the
    report says "no data", never 0, because a zero would read as a measured
    cost. A malformed value (a raw-appended row bypasses gi-runlog) is skipped.
    """
    costs: dict[str, dict] = {}
    samples: dict[str, list[int]] = {}
    for row in rows:
        skill = row.get("skill")
        if not isinstance(skill, str) or not skill:
            continue
        costs.setdefault(skill, {"runs": 0})["runs"] += 1
        tokens = row.get("tokens")
        if isinstance(tokens, int) and not isinstance(tokens, bool) and tokens > 0:
            samples.setdefault(skill, []).append(tokens)
    for skill, entry in costs.items():
        values = samples.get(skill, [])
        entry["token_samples"] = len(values)
        entry["median_tokens"] = _median(values)
    return dict(sorted(costs.items()))


def collect_run_stats(rows: list[dict] | None) -> dict | None:
    """Outcome/QA/duration aggregates over run-log rows parsed by load_run_rows."""
    if not rows:
        return None
    outcomes: dict[str, int] = {}
    for r in rows:
        o = str(r.get("outcome", "unknown"))
        outcomes[o] = outcomes.get(o, 0) + 1
    attempted = [r for r in rows if r.get("outcome") not in SKIP_OUTCOMES]
    succeeded = [r for r in attempted if r.get("outcome") in SUCCESS_OUTCOMES]
    qa = [r["qa_cycles"] for r in rows if isinstance(r.get("qa_cycles"), int)]
    dur = [r["duration_s"] for r in rows if isinstance(r.get("duration_s"), (int, float))]
    by_complexity: dict[str, dict] = {}
    for level in ("low", "medium", "high"):
        sub = [r for r in rows if r.get("complexity") == level]
        if sub:
            sub_qa = [r["qa_cycles"] for r in sub if isinstance(r.get("qa_cycles"), int)]
            by_complexity[level] = {"runs": len(sub), "median_qa": _median(sub_qa)}
    unexplained = [r for r in rows if _unexplained_ceiling_breach(r)]
    phases = collect_phase_stats(rows)
    return {
        "runs": len(rows),
        "outcomes": dict(sorted(outcomes.items())),
        "attempted": len(attempted),
        "succeeded": len(succeeded),
        "success_pct": _pct(len(succeeded), len(attempted)),
        "median_qa_cycles": _median(qa),
        "median_duration_s": _median(dur),
        "by_complexity": by_complexity,
        "by_skill": collect_skill_costs(rows),
        "phases": phases,
        "slowest_phase": slowest_phase(phases),
        "issues": sorted({r["issue"] for r in rows if isinstance(r.get("issue"), int)}),
        "unexplained_ceiling_breaches": len(unexplained),
        "ceiling_breach_issues": sorted(
            {r["issue"] for r in unexplained if isinstance(r.get("issue"), int)}
        ),
    }


REVERT_FOOTER_RE = re.compile(r"^This reverts commit ([0-9a-fA-F]{40})\b", re.MULTILINE)
REVERT_PR_RE = re.compile(r"^Reverts [\w.-]+/[\w.-]+#(\d+)\s*$", re.MULTILINE)
SUBJECT_PR_RE = re.compile(r"\(#(\d+)\)\s*$")
RELEASE_TAG_RE = re.compile(r"^v?(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)$")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
PLANNED_FOLLOWUP_LABEL = "auto-pilot-followup"
UNRELEASED = "unreleased"
HISTORY_FIELDS = 4


def parse_merge_history(raw: str) -> list[dict] | None:
    """Parse the NUL-framed walk into commits, newest first. None when malformed."""
    fields = raw.split("\0")
    if fields and fields[-1] == "":
        fields.pop()
    if len(fields) % HISTORY_FIELDS:
        return None
    commits = []
    for sha, ct, decorations, message in zip(*[iter(fields)] * HISTORY_FIELDS):
        sha = sha.strip().lower()
        if not SHA_RE.match(sha):
            return None
        commits.append({
            "sha": sha,
            "ct": int(ct) if ct.strip().isdigit() else None,
            "tags": [
                ref.strip().removeprefix("tag: ")
                for ref in decorations.split(",")
                if ref.strip()
            ],
            "message": message,
        })
    return commits


def collect_merge_history(branch: str) -> list[dict] | None:
    """One offline `git log` walk of `branch`: messages, commit times, tags.

    Not windowed: a revert can land long after the run it undoes, and the
    release a commit shipped in is named by a tag above it.
    """
    out = _run_soft([
        "git", "log", "-z", "--decorate-refs=refs/tags",
        "--format=%H%x00%ct%x00%D%x00%B", branch,
    ])
    return None if out is None else parse_merge_history(out)


def _release_name(value: object) -> str | None:
    """`0.27.0` or `v0.27.0` → `v0.27.0`; anything that is not a version → None."""
    if not isinstance(value, str):
        return None
    m = RELEASE_TAG_RE.match(value.strip())
    return f"v{m.group(1)}" if m else None


def _release_sort_key(name: str) -> tuple:
    if name == UNRELEASED:
        return (0,)
    core = re.findall(r"\d+", name.split("-", 1)[0].split("+", 1)[0])
    return (1, *(-int(part) for part in core), name)


class _HistoryIndex(NamedTuple):
    commits_by_pr: dict[int, list[str]]  # newest first
    reverted_shas: set[str]
    reverted_prs: set[int]
    release_by_sha: dict[str, str]
    time_by_sha: dict[str, int | None]


def _index_history(history: list[dict]) -> _HistoryIndex:
    commits_by_pr: dict[int, list[str]] = {}
    reverted_shas: set[str] = set()
    reverted_prs: set[int] = set()
    release_by_sha: dict[str, str] = {}
    time_by_sha: dict[str, int | None] = {}
    release = UNRELEASED
    for commit in history:  # newest first
        sha, message = commit["sha"], commit.get("message") or ""
        tag = next(filter(None, map(_release_name, commit.get("tags") or [])), None)
        if tag:
            release = tag
        release_by_sha[sha] = release
        time_by_sha[sha] = commit.get("ct")
        reverted_shas.update(t.lower() for t in REVERT_FOOTER_RE.findall(message))
        reverted_prs.update(int(n) for n in REVERT_PR_RE.findall(message))
        subject = message.strip().split("\n", 1)[0].strip()
        if subject.startswith('Revert "'):
            continue  # a revert is never the commit that landed the PR it names
        m = SUBJECT_PR_RE.search(subject)
        if m:
            commits_by_pr.setdefault(int(m.group(1)), []).append(sha)
    return _HistoryIndex(commits_by_pr, reverted_shas, reverted_prs, release_by_sha, time_by_sha)


def _label_names(issue: dict) -> set[str]:
    names = set()
    for label in issue.get("labels") or []:
        name = label.get("name") if isinstance(label, dict) else label
        if isinstance(name, str):
            names.add(name.strip().lower())
    return names


def _is_bug_issue(issue: dict) -> bool:
    if "bug" in _label_names(issue):
        return True
    if str(issue.get("title") or "").strip().lower().startswith("bug:"):
        return True
    type_section = split_sections(issue.get("body") or "").get("Type", "")
    return strip_confidence(first_content_line(type_section)).lower() == "bug"


def _new_bucket(joined: bool) -> dict:
    gh_count = 0 if joined else None
    return {
        "merged_runs": 0,
        "unconfirmed": 0,
        "reverted": 0,
        "reopened": gh_count,
        "followed_up": gh_count,
        "planned_followups": gh_count,
        "flagged": gh_count,
        "flagged_pct": None,
        "keyed_by": {"skill_version": 0, "history": 0, "none": 0},
    }


def collect_lookback_stats(
    run_rows: list[dict] | None,
    merged_prs: list | None,
    issues: list | None,
    history: list[dict] | None,
    window: SinceWindow | None,
    *,
    limit: int | None = None,
) -> dict | None:
    """Join merged runs to what happened after the merge (VW19). No I/O.

    This docstring is the contract later work builds on (#571 links the trace
    into the run record, #573 ships it in a skill).

    Inputs: run-log rows; the merged-PR page (`number, body, mergedAt,
    mergeCommit`) and the issue page (`number, body, state, stateReason,
    createdAt, labels, title`), both None offline; the commits of one
    `collect_merge_history` walk, newest first, or None when git failed (then
    this returns None); and the already-resolved `--since` window.

    Denominator. A run is a row with an integer `pr`, deduplicated on `pr`: a
    resolver `success` row and an auto-pilot `merged` row for one PR are one
    run, and the outcome is not read, so an unknown outcome is tolerated,
    except that a `revert_opened` row (#571) is never a run: git alone detects
    the revert. The
    run counts as merged when the PR page lists it or the walk holds a commit
    for it; otherwise it is `unconfirmed`, never clean. A window keeps rows
    whose `ts` is at or after its cutoff; an unresolved window is lifetime.

    Commit for a PR: the page's `mergeCommit.oid` when given, plus every walk
    commit whose subject ENDS in `(#pr)` — only the last `(#N)` counts, so
    `feat: x (#567) (#598)` is PR 598, and a subject starting `Revert "` is
    never the commit that landed a PR.

    reverted: a commit's message has a line `This reverts commit <sha>` (git
    revert's footer, also inside a squash body) naming one of the run's
    commits, or a line `Reverts owner/repo#<pr>` (GitHub's Revert button). The
    word "revert" without one of those lines does not count. A revert that was
    itself reverted still counts.

    reopened: the run's issue is OPEN now, or its stateReason is REOPENED, and
    the PR body closed it (`Closes`, `Fixes` or `Resolves #<issue>`). A PR that
    is not on the page cannot be judged and does not count.

    followed_up: another issue, created after the merge (page `mergedAt`, else
    the commit time), whose body references `#<pr>` or `/pull/<pr>` and which
    is a bug: a `bug` label, a title starting `Bug:`, or a `## Type` of Bug.
    The run's own issue is skipped. An issue labelled `auto-pilot-followup` is
    planned work: it never counts as followed_up and counts as
    `planned_followups` instead, bug or not.

    reopened, followed_up, planned_followups and flagged are None, not 0, when
    either gh page is missing: a count nobody measured must not read as clean,
    and an offline flagged rate (reverts only) is not comparable with an online
    one. Every count is a number of runs; flagged is the union of the three
    signals and flagged_pct is flagged over merged runs.

    Release key: the row's `skill_version` (the IDD release that ran) as
    `vX.Y.Z`, else the version tag at or above the PR's commit in the walk (the
    project release it shipped in; exact on a linear squash history,
    approximate with merge commits), else `unreleased`. Tags that are not
    versions are not boundaries. `keyed_by` counts which source keyed each run.
    """
    if not run_rows or history is None:
        return None
    index = _index_history(history)
    joined = merged_prs is not None and issues is not None
    page = {
        pr["number"]: pr
        for pr in merged_prs or []
        if isinstance(pr, dict) and isinstance(pr.get("number"), int)
    }
    issue_list = [i for i in issues or [] if isinstance(i, dict)]
    issue_by_number = {i.get("number"): i for i in issue_list}
    cutoff = window.cutoff if window else None

    runs: dict[int, dict] = {}
    for row in run_rows:
        pr = row.get("pr")
        if not isinstance(pr, int) or isinstance(pr, bool):
            continue
        if row.get("outcome") == "revert_opened":
            continue
        if cutoff is not None and (_merged_at_epoch(row.get("ts")) or -1) < cutoff:
            continue
        run = runs.setdefault(pr, {"issue": None, "version": None})
        issue = row.get("issue")
        if run["issue"] is None and isinstance(issue, int) and not isinstance(issue, bool):
            run["issue"] = issue
        if run["version"] is None:
            run["version"] = _release_name(row.get("skill_version"))

    total = _new_bucket(joined)
    by_release: dict[str, dict] = {}
    prs: dict[str, list[int]] = {
        "reverted": [], "reopened": [], "followed_up": [], "unconfirmed": [],
    }
    for pr, run in sorted(runs.items()):
        listed = page.get(pr)
        oid = ""
        if listed is not None and isinstance(listed.get("mergeCommit"), dict):
            oid = str(listed["mergeCommit"].get("oid") or "").lower()
        walk = index.commits_by_pr.get(pr, [])
        shas = list(dict.fromkeys(([oid] if oid else []) + walk))
        placed = [s for s in ([oid] if oid else []) + walk[::-1] if s in index.release_by_sha]

        if run["version"]:
            release, source = run["version"], "skill_version"
        elif placed:
            release, source = index.release_by_sha[placed[0]], "history"
        else:
            release, source = UNRELEASED, "none"
        bucket = by_release.setdefault(release, _new_bucket(joined))
        for target in (total, bucket):
            target["keyed_by"][source] += 1

        if listed is None and not walk:
            prs["unconfirmed"].append(pr)
            for target in (total, bucket):
                target["unconfirmed"] += 1
            continue

        signals = {"reverted": any(s in index.reverted_shas for s in shas)
                   or pr in index.reverted_prs}
        planned = False
        if joined:
            issue = issue_by_number.get(run["issue"]) if run["issue"] is not None else None
            closes = bool(
                issue is not None and listed is not None
                and re.search(CLOSING_KEYWORD_RE.format(n=run["issue"]), listed.get("body") or "")
            )
            signals["reopened"] = closes and (
                str(issue.get("state") or "").upper() == "OPEN"
                or str(issue.get("stateReason") or "").upper() == "REOPENED"
            )
            merged_at = _merged_at_epoch(listed.get("mergedAt")) if listed else None
            if merged_at is None and placed:
                merged_at = index.time_by_sha.get(placed[0])
            reference = re.compile(rf"(?:#|/pull/){pr}\b")
            followed = False
            for other in issue_list:
                created = _merged_at_epoch(other.get("createdAt"))
                if (
                    other.get("number") == run["issue"]
                    or merged_at is None or created is None or created <= merged_at
                    or not reference.search(other.get("body") or "")
                ):
                    continue
                if PLANNED_FOLLOWUP_LABEL in _label_names(other):
                    planned = True
                elif _is_bug_issue(other):
                    followed = True
            signals["followed_up"] = followed

        for target in (total, bucket):
            target["merged_runs"] += 1
            for name, hit in signals.items():
                target[name] += hit
            if joined:
                target["planned_followups"] += planned
                target["flagged"] += any(signals.values())
        for name, hit in signals.items():
            if hit:
                prs[name].append(pr)

    for bucket in (total, *by_release.values()):
        if joined:
            bucket["flagged_pct"] = _pct(bucket["flagged"], bucket["merged_runs"])
    if not joined:
        prs["reopened"] = prs["followed_up"] = None
    truncated = bool(
        joined and limit is not None
        and (len(merged_prs) >= limit or len(issue_list) >= max(limit, MIN_ISSUE_FETCH_LIMIT))
    )
    return {
        "github": joined,
        "window": window.since if cutoff is not None else None,
        "truncated": truncated,
        "total": total,
        "by_release": dict(sorted(by_release.items(), key=lambda kv: _release_sort_key(kv[0]))),
        "prs": prs,
    }


# --- End of the mirror ---------------------------------------------------------

RUN_LOG = Path(".idd") / "runs.jsonl"
WARN_PR_LIST_MAX = 5


def _git(*args: str) -> str | None:
    """A read-only git call; stdout, or None on any failure."""
    return _run_soft(["git", *args])


def _ref_exists(ref: str) -> bool:
    return _git("rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}") is not None


def _tip(ref: str) -> dict | None:
    out = _git("log", "-1", "--format=%H%x00%cI", ref)
    if not out or "\0" not in out:
        return None
    sha, date = out.strip().split("\0", 1)
    return {"ref": ref, "sha": sha, "date": date}


def choose_ref(branch: str | None) -> tuple[str, list[str]]:
    """The ref to walk, plus any freshness warning. Never fetches."""
    if branch:
        if not _ref_exists(branch):
            raise UsageError(f"--branch {branch} does not resolve to a commit")
        return branch, []
    default = detect_default_branch()
    remote = f"origin/{default}"
    if default == "HEAD" or not _ref_exists(f"refs/remotes/{remote}"):
        return default, []
    warnings = []
    local = _git("rev-parse", "--verify", "--quiet", f"refs/heads/{default}^{{commit}}")
    upstream = _git("rev-parse", "--verify", "--quiet", f"refs/remotes/{remote}^{{commit}}")
    if local and upstream and local.strip() != upstream.strip():
        warnings.append(
            f"local {default} ({local.strip()[:7]}) and {remote} "
            f"({upstream.strip()[:7]}) differ; walked {remote}, which is as fresh "
            "as the last `git fetch`"
        )
    return remote, warnings


def _gh_page(args: list[str]) -> list:
    proc = _RUN_GH(args, Unavailable)
    if proc.returncode != 0:
        raise Unavailable("gh unavailable, unauthenticated, or offline")
    try:
        page = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise Unavailable("gh printed unparsable JSON") from exc
    if not isinstance(page, list):
        raise Unavailable("gh printed an unexpected JSON shape")
    return page


def fetch_pages(limit: int) -> tuple[list, list]:
    """The two look-back pages. Raises Unavailable; makes no other gh call."""
    prs = _gh_page([
        "pr", "list", "--state", "merged", "--limit", str(limit),
        "--json", "number,body,mergedAt,mergeCommit",
    ])
    issues = _gh_page([
        "issue", "list", "--state", "all",
        "--limit", str(max(limit, MIN_ISSUE_FETCH_LIMIT)),
        "--json", ISSUE_PAGE_FIELDS,
    ])
    return prs, issues


def behind_github(rows: list[dict] | None, prs: list | None, history: list[dict]) -> list[int]:
    """Logged runs whose GitHub merge commit is not in the walk, ascending."""
    logged = {
        row["pr"] for row in rows or []
        if isinstance(row.get("pr"), int) and not isinstance(row.get("pr"), bool)
    }
    walked = {commit["sha"] for commit in history}
    missing = []
    for pr in prs or []:
        if not isinstance(pr, dict) or pr.get("number") not in logged:
            continue
        merge = pr.get("mergeCommit")
        oid = str(merge.get("oid") or "").lower() if isinstance(merge, dict) else ""
        if oid and oid not in walked:
            missing.append(pr["number"])
    return sorted(missing)


def build_report(args: argparse.Namespace) -> dict:
    root_out = _git("rev-parse", "--show-toplevel")
    if not root_out:
        raise Unavailable("not inside a git repository (or git is not on PATH)")
    root = Path(root_out.strip())
    ref, warnings = choose_ref(args.branch)

    rows = load_run_rows(root / RUN_LOG)
    prs = issues = None
    skipped = None
    if args.no_github:
        skipped = "--no-github"
    else:
        try:
            prs, issues = fetch_pages(args.limit)
        except Unavailable as exc:
            skipped = str(exc)

    history = collect_merge_history(ref)
    lookback = None
    if history is None:
        warnings.append(f"could not walk {ref} — the look-back needs git history")
    else:
        late = behind_github(rows, prs, history)
        if late:
            shown = ", ".join(f"#{n}" for n in late[:WARN_PR_LIST_MAX])
            more = f" and {len(late) - WARN_PR_LIST_MAX} more" if len(late) > WARN_PR_LIST_MAX else ""
            warnings.append(
                f"merged PR {shown}{more} is not in {ref}; the walked ref is behind "
                "GitHub — `git fetch` refreshes it"
            )
    if rows:
        lookback = collect_lookback_stats(rows, prs, issues, history, None, limit=args.limit)
    if lookback and lookback["truncated"]:
        warnings.append(
            f"a GitHub page hit --limit {args.limit}; older items are not in this sample"
        )
    return {
        "github_skipped": skipped,
        "lookback": lookback,
        "runs": collect_run_stats(rows),
        "walked": _tip(ref),
        "warnings": warnings,
    }


# --- Text report (DESIGN.md symbols; two-space indent; at most 80 columns) -----

_COLUMNS = (
    ("merged", "merged_runs"), ("unconf", "unconfirmed"), ("revert", "reverted"),
    ("reopen", "reopened"), ("follow", "followed_up"), ("planned", "planned_followups"),
)


def _plural(n: int, word: str) -> str:
    return f"{n} {word}{'' if n == 1 else 's'}"


def _render_runs(runs: dict | None) -> list[str]:
    if runs is None:
        return ["  ○ Run outcomes — no rows in .idd/runs.jsonl"]
    lines = [f"  ● Run outcomes  {_plural(runs['runs'], 'row')} in .idd/runs.jsonl"]
    lines.append("    " + " · ".join(f"{k} {v}" for k, v in runs["outcomes"].items()))
    if runs["success_pct"] is None:
        lines.append("  ○ success       no attempted runs")
    else:
        lines.append(
            f"  ✓ success       {runs['succeeded']} of {runs['attempted']} attempted"
            f" ({runs['success_pct']}%)"
        )
    breaches = runs["unexplained_ceiling_breaches"]
    if breaches:
        issues = ", ".join(f"#{n}" for n in runs["ceiling_breach_issues"])
        lines.append(f"  ✗ unexplained QA ceiling breaches  {breaches}" + (f" ({issues})" if issues else ""))
    else:
        lines.append("  ✓ no unexplained QA ceiling breach")
    slowest = runs["slowest_phase"]
    if slowest:
        phase = runs["phases"][slowest]
        lines.append(
            f"  ● slowest phase {slowest} (median {round(phase['median_s'])}s"
            f" · {_plural(phase['runs'], 'run')})"
        )
    return lines


def _cell(value: object) -> str:
    return "—" if value is None else str(value)


def _flagged(bucket: dict) -> str:
    if bucket["flagged"] is None:
        return "○"
    pct = bucket["flagged_pct"]
    return f"{bucket['flagged']}" + (f" ({pct}%)" if pct is not None else "")


def _row(label: str, bucket: dict) -> str:
    cells = "".join(f"{_cell(bucket[key]):>8}" for _, key in _COLUMNS)
    return f"    {label:<12}{cells}  {_flagged(bucket)}"


def _render_lookback(lookback: dict | None, skipped: str | None) -> list[str]:
    if lookback is None:
        return ["  ○ Look back after merge — no merged runs to join"]
    total = lookback["total"]
    lines = [f"  ● Look back after merge  {_plural(total['merged_runs'], 'merged run')}"]
    header = "".join(f"{name:>8}" for name, _ in _COLUMNS)
    lines.append(f"    {'release':<12}{header}  flagged")
    for release, bucket in lookback["by_release"].items():
        lines.append(_row(release, bucket))
    lines.append(_row("total", total))
    for name in ("reverted", "reopened", "followed_up"):
        listed = lookback["prs"].get(name)
        if listed:
            lines.append(f"    {name.replace('_', ' ')}: " + ", ".join(f"#{n}" for n in listed))
    if not lookback["github"]:
        why = skipped or "gh unavailable, unauthenticated, or offline"
        lines.append(f"  ○ needs GitHub — reopen, follow, planned and flagged ({why})")
    return lines


def render_text(report: dict) -> str:
    walked = report["walked"]
    lines = ["◆ IDD stats — read-only"]
    if walked:
        lines.append(f"  walked {walked['ref']} @ {walked['sha'][:7]} ({walked['date']})")
    lines.append("┄" * 60)
    lines.extend(_render_runs(report["runs"]))
    lines.append("")
    lines.extend(_render_lookback(report["lookback"], report["github_skipped"]))
    for warning in report["warnings"]:
        lines.append(f"  ⚠ {warning}")
    return "\n".join(lines)


def _positive_int(raw: str) -> int:
    try:
        value = int(raw)
    except ValueError:
        raise argparse.ArgumentTypeError(f"not an integer: {raw}") from None
    if value < 1:
        raise argparse.ArgumentTypeError("must be at least 1")
    return value


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="gi-stats.py",
        description=(
            "Read-only report of run outcomes and the post-merge look-back "
            "from .idd/runs.jsonl. Run it from inside the repository."
        ),
    )
    parser.add_argument("--branch", metavar="REF",
                        help="ref to walk (default: origin/<default>, else the local default branch)")
    parser.add_argument("--limit", type=_positive_int, default=DEFAULT_GITHUB_FETCH_LIMIT,
                        metavar="N", help="merged-PR page size (default: %(default)s)")
    parser.add_argument("--no-github", action="store_true",
                        help="make no gh call; GitHub-only counts are reported as null")
    parser.add_argument("--json", action="store_true", help="print one JSON object")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    os.environ["GIT_OPTIONAL_LOCKS"] = "0"
    try:
        report = build_report(args)
    except UsageError as exc:
        print(f"✗ gi-stats: {exc}", file=sys.stderr)
        return 2
    except Unavailable as exc:
        print(f"⚠ gi-stats: {exc}", file=sys.stderr)
        return 4
    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(render_text(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
