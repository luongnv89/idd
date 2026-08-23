#!/usr/bin/env python3
"""Turn a scanned issue graph into the triage payload: order, status, priority.

Everything `/issue-triage` does between the scanner returning and the report
being rendered is arithmetic over structured data — direct the undirected edges,
find the cycles, break them, topologically sort, group the independent sets,
subtract two dates, bucket into P1/P2/P3. There is one correct answer for each,
and a language model recomputing them from prose gets a *plausible* one. The
judgement that genuinely needs a model — extracting keywords from a body,
deciding which files an issue touches — happens before this script and is
handed to it as input.

Untrusted input never travels on the command line: issue titles and bodies
arrive as JSON on stdin. Anyone can file an issue on a public repository, and
`/auto-pilot` triages unattended.

Input on stdin, one JSON object:

    {"issues": [{"number": 12, "title": "...", "type": "bug",
                 "labels": ["bug"], "createdAt": "...", "updatedAt": "...",
                 "affected_files": ["auth.py"], "potentially_fixed_by": null}],
     "edges": [{"from": 12, "to": 15}, {"a": 8, "b": 9}]}

An edge with `from`/`to` is already directed. An edge with `a`/`b` (or a
two-element array) is undirected and is directed here by the three heuristics
`references/detection.md` states, in its order: earlier `createdAt` first, then
the higher **blocking** count, then bug before feature before improvement. Two
issues that tie on all three are reported in `co_dependent` and get no edge —
there is deliberately no fourth tie-break on the issue number, because an order
invented from an issue number reads as a real dependency to whoever acts on it,
and `co_dependent` is the honest answer. Determinism does not depend on that
tie-break: duplicate edges are canonicalized away before anything counts them,
and every emitted list is sorted.

`summary.circular_deps` reports one closed chain per **broken** edge — the set
of edges to remove to make the graph acyclic, which is the actionable answer.
It is not an enumeration of every simple cycle: when two cycles share a broken
edge, only the chain found first is listed, and a node reachable only through
an already-broken edge may not appear in any chain. The execution order is
unaffected (`acyclic` is always genuinely acyclic), and removing the reported
edge still resolves the cycles that share it. A self-dependency (`{"from": 7,
"to": 7}`) carries no ordering information and is dropped rather than reported.

Output on stdout (or `--out FILE`) is the `.gitissue/triage.json` payload:
`version`, `updated`, `source`, `analyzed_count`, `issues[]`, `summary`, and
`history[]`, exactly as documented in the triage output reference.

Exit codes
  0  computed
  2  usage error
  3  invalid input — unparsable stdin, an issue without a number, an edge
     naming an unknown issue, an unparsable timestamp, or an out-of-range
     `triage.*` value (stderr: `✗ gi-triage-graph: …`). Stop.
  4  cannot complete — `--out` could not be written (stderr:
     `⚠ gi-triage-graph: …`). The computed payload is still printed on stdout,
     so the caller can persist it another way; degrade to the prose procedure.

Authored at src/shared/scripts/gi-triage-graph.py — do not edit installed
copies; edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys

DEFAULT_STALE_DAYS = 14
# Type precedence inside one topological level: bugs first.
TYPE_RANK = {"bug": 0, "feature": 1, "improvement": 2}
ESCALATING_LABELS = frozenset({"critical", "urgent"})
KNOWN_SOURCES = ("/issue-triage", "/auto-pilot")

CONFIG_NAME = ".gitissue.yml"
CONFIG_SECTION = "triage"
CONFIG_KEYS = ("stale_threshold_days", "auto_priority")

# `git rev-parse --show-cdup` is empty at the working-tree root and otherwise
# consists only of `../` segments. Refuse to resolve any other output as a path.
_CDUP_RE = re.compile(r"^(\.\./)*$")

_SECTION_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):\s*$")
_ENTRY_RE = re.compile(r"^\s+([a-z_][a-z0-9_]*):[ \t]+(.*?)\s*$")


class InvalidInput(Exception):
    """Caller-supplied input is unusable — exit 3."""


class Unavailable(Exception):
    """The result could not be delivered where asked — exit 4."""


# --- configuration -----------------------------------------------------------


def _parse_scalar(raw: str, key: str) -> object:
    if raw.startswith('"'):
        try:
            return json.loads(raw)
        except json.JSONDecodeError as exc:
            raise InvalidInput(
                f"{CONFIG_SECTION}.{key} — invalid quoted string ({exc.msg})"
            ) from exc
    if raw.startswith("'") and raw.endswith("'") and len(raw) >= 2:
        return raw[1:-1].replace("''", "'")
    if raw == "true":
        return True
    if raw == "false":
        return False
    if re.fullmatch(r"-?[0-9]+", raw):
        return int(raw)
    return raw


def read_config(path: str) -> dict[str, object]:
    """Read the `triage:` block of a config file, or {} when it has none."""
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return {}
    values: dict[str, object] = {}
    inside = False
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        section = _SECTION_RE.match(line)
        if section:
            inside = section.group(1) == CONFIG_SECTION
            continue
        if not inside:
            continue
        entry = _ENTRY_RE.match(line)
        if entry and entry.group(1) in CONFIG_KEYS:
            values[entry.group(1)] = _parse_scalar(entry.group(2), entry.group(1))
    return values


def config_search_ceiling() -> str:
    """Return the working-tree root, or cwd when git cannot identify one."""
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "--show-cdup"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return os.path.abspath(os.getcwd())
    cdup = proc.stdout.rstrip("\n")
    if proc.returncode != 0 or not _CDUP_RE.match(cdup):
        return os.path.abspath(os.getcwd())
    return (
        os.path.normpath(os.path.join(os.getcwd(), cdup))
        if cdup
        else os.path.abspath(os.getcwd())
    )


def find_config(explicit: str | None) -> str | None:
    """The explicit file, else search upward to the working-tree root."""
    if explicit:
        return explicit if os.path.isfile(explicit) else None
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


def resolve_settings(args: argparse.Namespace) -> tuple[int, bool]:
    values: dict[str, object] = {}
    if not args.no_config:
        path = find_config(args.config)
        if path is None and args.config:
            raise InvalidInput(f"config file not found: {args.config}")
        if path is not None:
            values = read_config(path)
    stale = (
        args.stale_days
        if args.stale_days is not None
        else values.get("stale_threshold_days", DEFAULT_STALE_DAYS)
    )
    if not isinstance(stale, int) or isinstance(stale, bool) or stale < 1:
        raise InvalidInput(
            f"{CONFIG_SECTION}.stale_threshold_days must be an integer >= 1, got {stale!r}"
        )
    auto_priority = values.get("auto_priority", True)
    if args.no_priority:
        auto_priority = False
    if not isinstance(auto_priority, bool):
        raise InvalidInput(
            f"{CONFIG_SECTION}.auto_priority must be true or false, got {auto_priority!r}"
        )
    return stale, auto_priority


# --- input -------------------------------------------------------------------


def parse_time(value: object, label: str) -> dt.datetime | None:
    """Parse an ISO-8601 timestamp, or None when the field is absent.

    An absent timestamp is a real state (an issue payload that did not ask for
    the field); a *present but unparsable* one is invalid input, because
    silently treating it as absent would report a stale issue as fresh.
    """
    if value is None or value == "":
        return None
    if not isinstance(value, str):
        raise InvalidInput(f"{label} must be an ISO-8601 string, got {value!r}")
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = dt.datetime.fromisoformat(text)
    except ValueError as exc:
        raise InvalidInput(f"{label} is not an ISO-8601 timestamp: {value!r} ({exc})") from exc
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=dt.timezone.utc)


def read_stdin_object() -> dict:
    buffer = getattr(sys.stdin, "buffer", None)
    raw = buffer.read().decode("utf-8", errors="replace") if buffer else sys.stdin.read()
    if not raw.strip():
        raise InvalidInput("no request object on stdin")
    try:
        loaded = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise InvalidInput(f"stdin is not valid JSON — {exc}") from exc
    if not isinstance(loaded, dict):
        raise InvalidInput("stdin must hold a JSON object")
    return loaded


def normalize_issues(request: dict) -> list[dict]:
    raw = request.get("issues")
    if not isinstance(raw, list):
        raise InvalidInput("request must carry an 'issues' array")
    issues: list[dict] = []
    seen: set[int] = set()
    for position, entry in enumerate(raw):
        if not isinstance(entry, dict):
            raise InvalidInput(f"issues[{position}] is not an object")
        number = entry.get("number")
        if not isinstance(number, int) or isinstance(number, bool):
            raise InvalidInput(f"issues[{position}] has no integer 'number'")
        if number in seen:
            raise InvalidInput(f"issue #{number} appears twice in 'issues'")
        seen.add(number)
        labels = [str(label) for label in entry.get("labels") or []]
        kind = str(entry.get("type") or "").strip().lower()
        if kind not in TYPE_RANK:
            # Fall back to the labels before giving up: a repository that types
            # its issues only by label still gets the documented tie-breaks.
            kind = next((label.lower() for label in labels if label.lower() in TYPE_RANK), "")
        files = entry.get("affected_files") or []
        if not isinstance(files, list):
            raise InvalidInput(f"issues[{position}].affected_files must be an array")
        issues.append(
            {
                "number": number,
                "title": str(entry.get("title") or ""),
                "type": kind or None,
                "labels": labels,
                "created": parse_time(entry.get("createdAt"), f"issues[{position}].createdAt"),
                "updated": parse_time(entry.get("updatedAt"), f"issues[{position}].updatedAt"),
                "affected_files": [str(f) for f in files],
                "potentially_fixed_by": entry.get("potentially_fixed_by") or None,
            }
        )
    return issues


# --- graph -------------------------------------------------------------------


def blocking_degree(edges: list[dict], number: int) -> int:
    """How many edges could make `number` a **blocker** of something else.

    `references/detection.md` states the rule as "more *blocking* relationships
    take precedence". An edge that already points *at* this issue makes it
    blocked, not blocking, so counting the `to` end inverted the rule: an issue
    blocked by three others outranked a peer that blocked nobody and was
    ordered ahead of it. An undirected end counts, because which way it will be
    directed is exactly what this number is being used to decide.
    """
    total = 0
    for edge in edges:
        if number in (edge.get("a"), edge.get("b"), edge.get("from")):
            total += 1
    return total


def _edge_key(edge: dict) -> tuple:
    """A canonical, hashable identity for one edge.

    `repr` rather than the value itself, because an edge may name anything JSON
    can hold and an unhashable value must produce this script's exit 3 rather
    than a `TypeError` out of a `in index` test — exit 1 is a code no call site
    classifies. An undirected pair is unordered: `{a: 1, b: 2}` and
    `{a: 2, b: 1}` are one edge.
    """
    if "from" in edge or "to" in edge:
        return ("directed", repr(edge.get("from")), repr(edge.get("to")))
    return ("undirected", tuple(sorted((repr(edge.get("a")), repr(edge.get("b"))))))


def direct_edges(
    raw_edges: list, index: dict[int, dict]
) -> tuple[list[tuple[int, int]], list[list[int]]]:
    """Split the input edges into directed pairs and co-dependent pairs."""
    normalized: list[dict] = []
    seen_edges: set[tuple] = set()
    for position, edge in enumerate(raw_edges):
        if isinstance(edge, list) and len(edge) == 2:
            edge = {"a": edge[0], "b": edge[1]}
        if not isinstance(edge, dict):
            raise InvalidInput(f"edges[{position}] is not an object or a two-element array")
        # Canonicalize *before* anything counts it. `blocking_degree` runs over
        # this list, so a repeated edge used to vote twice on precedence — and
        # deduplicating `directed` afterwards preserved the flipped direction
        # rather than undoing it. The same logical graph then produced a
        # different execution order depending on whether an edge was listed
        # twice, which the scanner has no reason to guarantee it never is.
        key = _edge_key(edge)
        if key in seen_edges:
            continue
        seen_edges.add(key)
        normalized.append(edge)

    def known(value: object, position: int) -> int:
        if not isinstance(value, int) or isinstance(value, bool) or value not in index:
            raise InvalidInput(f"edges[{position}] names unknown issue {value!r}")
        return value

    directed: list[tuple[int, int]] = []
    co_dependent: list[list[int]] = []
    for position, edge in enumerate(normalized):
        if "from" in edge or "to" in edge:
            src = known(edge.get("from"), position)
            dst = known(edge.get("to"), position)
            if src != dst:
                directed.append((src, dst))
            continue
        left = known(edge.get("a"), position)
        right = known(edge.get("b"), position)
        if left == right:
            continue
        winner = precedence(index[left], index[right], normalized)
        if winner is None:
            pair = sorted([left, right])
            if pair not in co_dependent:
                co_dependent.append(pair)
            continue
        loser = right if winner == left else left
        directed.append((winner, loser))
    # Deduplicate while keeping first-appearance order.
    unique: list[tuple[int, int]] = []
    for pair in directed:
        if pair not in unique:
            unique.append(pair)
    # Sorted, not input-ordered: `co_dependent` was the one emitted list whose
    # value depended on the order the scanner happened to list its edges in.
    return unique, sorted(co_dependent)


def precedence(left: dict, right: dict, edges: list[dict]) -> int | None:
    """Which of two issues should be resolved first, or None when neither does.

    The order of the tests is the order the detection reference states them:
    creation date, then blocking count, then type. There is no fourth test on
    the issue number — a pair that ties on all three is reported as
    `co_dependent`, which is a real answer, where an order derived from an
    issue number would read as a dependency that nobody observed.
    """
    if left["created"] and right["created"] and left["created"] != right["created"]:
        return left["number"] if left["created"] < right["created"] else right["number"]
    left_degree = blocking_degree(edges, left["number"])
    right_degree = blocking_degree(edges, right["number"])
    if left_degree != right_degree:
        return left["number"] if left_degree > right_degree else right["number"]
    left_rank = TYPE_RANK.get(left["type"] or "", 99)
    right_rank = TYPE_RANK.get(right["type"] or "", 99)
    if left_rank != right_rank:
        return left["number"] if left_rank < right_rank else right["number"]
    return None


def find_cycles(nodes: list[int], edges: list[tuple[int, int]]) -> tuple[list[list[int]], set[tuple[int, int]]]:
    """Depth-first cycle detection; returns (cycles, back edges to remove).

    Nodes are visited in ascending issue order and each node's successors in
    ascending order, so the same graph always yields the same cycle list and the
    same broken edges — a triage that reorders itself between identical runs is
    not a triage anyone can act on.
    """
    successors: dict[int, list[int]] = {node: [] for node in nodes}
    for src, dst in edges:
        successors[src].append(dst)
    for node in successors:
        successors[node].sort()

    color: dict[int, int] = {node: 0 for node in nodes}  # 0 white, 1 grey, 2 black
    stack: list[int] = []
    cycles: list[list[int]] = []
    back: set[tuple[int, int]] = set()

    def visit(node: int) -> None:
        color[node] = 1
        stack.append(node)
        for nxt in successors[node]:
            if (node, nxt) in back:
                continue
            if color[nxt] == 0:
                visit(nxt)
            elif color[nxt] == 1:
                cycle = stack[stack.index(nxt) :] + [nxt]
                if cycle not in cycles:
                    cycles.append(cycle)
                back.add((node, nxt))
        stack.pop()
        color[node] = 2

    sys.setrecursionlimit(max(sys.getrecursionlimit(), len(nodes) * 4 + 100))
    for node in sorted(nodes):
        if color[node] == 0:
            visit(node)
    return cycles, back


def topological_levels(
    nodes: list[int], edges: list[tuple[int, int]], index: dict[int, dict]
) -> list[list[int]]:
    """Kahn levels, each level sorted by type then age then issue number."""
    incoming: dict[int, set[int]] = {node: set() for node in nodes}
    outgoing: dict[int, set[int]] = {node: set() for node in nodes}
    for src, dst in edges:
        outgoing[src].add(dst)
        incoming[dst].add(src)

    def sort_key(number: int) -> tuple:
        issue = index[number]
        created = issue["created"]
        return (
            TYPE_RANK.get(issue["type"] or "", 99),
            created.timestamp() if created else float("inf"),
            number,
        )

    remaining = set(nodes)
    levels: list[list[int]] = []
    while remaining:
        ready = sorted(
            (n for n in remaining if not (incoming[n] & remaining)), key=sort_key
        )
        if not ready:  # defensive: cycles were broken before this runs
            ready = sorted(remaining, key=sort_key)
        levels.append(ready)
        remaining -= set(ready)
    return levels


def parallel_groups(
    levels: list[list[int]], edges: list[tuple[int, int]], index: dict[int, dict]
) -> list[list[int]]:
    """Independent sets inside each level: no edge and no shared file.

    Audited in issue #278. Two properties, one of them a deliberate bound:

    * **Sound.** Every reported group is genuinely independent — no pair in it
      shares an edge or a file. That holds against the *original* graph too, not
      just `acyclic`: a broken back edge `(u, v)` exists only because `v` is an
      ancestor of `u` in the DFS, so a `v → … → u` path always survives the
      break and separates their levels. Two issues in a cycle can therefore
      never be reported as parallelizable. Verified over 1200 randomly
      generated cyclic graphs and 3000 random levels: zero violations.
    * **Not maximal, on purpose.** The bucketing is greedy first fit, so on
      about one level in ten it reports a smaller group than the largest that
      exists. Maximum independent set is NP-hard, this output is a *suggestion*
      about what could be worked in parallel, and under-reporting is the safe
      direction: it costs some parallelism, where over-reporting would tell two
      developers that conflicting issues are independent. The level is already
      sorted by `sort_key`, so which group greedy finds is deterministic.
    """
    linked = {(src, dst) for src, dst in edges} | {(dst, src) for src, dst in edges}
    groups: list[list[int]] = []
    for level in levels:
        buckets: list[list[int]] = []
        for number in level:
            files = set(index[number]["affected_files"])
            for bucket in buckets:
                if all(
                    (number, other) not in linked
                    and not (files & set(index[other]["affected_files"]))
                    for other in bucket
                ):
                    bucket.append(number)
                    break
            else:
                buckets.append([number])
        groups.extend(bucket for bucket in buckets if len(bucket) > 1)
    return groups


def assign_priority(issue: dict, blocks: list[int], stale_days: int, now: dt.datetime) -> str:
    """P1/P2/P3 from the documented heuristics.

    Audited in issue #278 against every row of the table in
    `references/detection.md`; all thirteen agree, including the escalating
    labels, the 2x-stale-threshold bug rule, and the untyped fallthrough.

    One row of that table contradicts itself and is resolved here rather than
    silently: a **stale bug that blocks nothing** matches both "bugs that do not
    block other issues" (P2) and "stale issues with no dependencies" (P3). This
    returns **P2** — staleness is a property of the report, not of the bug, and
    a bug nobody has touched in three months is not thereby less of a bug.
    Changing it is a decision about the documented table, not about this
    function; move `detection.md` first if you disagree.
    """
    labels = {label.strip().lower() for label in issue["labels"]}
    kind = issue["type"]
    if labels & ESCALATING_LABELS:
        return "P1"
    if kind == "bug":
        if blocks:
            return "P1"
        created = issue["created"]
        if created and (now - created).days > stale_days * 2:
            return "P1"
        return "P2"
    if kind == "feature" and blocks:
        return "P2"
    if kind == "improvement" and len(blocks) >= 2:
        return "P2"
    return "P3"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-triage-graph.py",
        description=(
            "Compute the triage execution order, status, staleness, and "
            "priority from a scanned issue graph on stdin."
        ),
        epilog="Example: python3 gi-triage-graph.py --source /issue-triage < scan.json",
    )
    parser.add_argument(
        "--source",
        default=KNOWN_SOURCES[0],
        choices=KNOWN_SOURCES,
        help="value written to the payload's `source` field",
    )
    parser.add_argument("--out", metavar="FILE", help="also write the payload to FILE")
    parser.add_argument("--now", metavar="ISO", help="treat this instant as now (tests)")
    parser.add_argument("--config", metavar="PATH", help=f"{CONFIG_NAME} to read triage.* from")
    parser.add_argument("--no-config", action="store_true", help="ignore any config file")
    parser.add_argument(
        "--stale-days", type=int, metavar="N", help="triage.stale_threshold_days override"
    )
    parser.add_argument(
        "--no-priority", action="store_true", help="behave as triage.auto_priority: false"
    )
    args = parser.parse_args(argv)

    try:
        stale_days, auto_priority = resolve_settings(args)
        now = parse_time(args.now, "--now") or dt.datetime.now(dt.timezone.utc)
        request = read_stdin_object()
        issues = normalize_issues(request)
        index = {issue["number"]: issue for issue in issues}
        raw_edges = request.get("edges") or []
        if not isinstance(raw_edges, list):
            raise InvalidInput("'edges' must be an array")
        directed, co_dependent = direct_edges(raw_edges, index)
    except InvalidInput as exc:
        sys.stderr.write(f"✗ gi-triage-graph: {exc}\n")
        return 3

    nodes = [issue["number"] for issue in issues]
    cycles, back_edges = find_cycles(nodes, directed)
    acyclic = [pair for pair in directed if pair not in back_edges]
    levels = topological_levels(nodes, acyclic, index)

    blocks: dict[int, list[int]] = {n: [] for n in nodes}
    blocked_by: dict[int, list[int]] = {n: [] for n in nodes}
    for src, dst in acyclic:
        blocks[src].append(dst)
        blocked_by[dst].append(src)
    for number in nodes:
        blocks[number].sort()
        blocked_by[number].sort()

    order: list[int] = [n for level in levels for n in level]
    maybe_fixed = [n for n in order if index[n]["potentially_fixed_by"]]
    order = [n for n in order if n not in maybe_fixed] + maybe_fixed

    records: list[dict] = []
    stale_count = 0
    for number in order:
        issue = index[number]
        updated = issue["updated"]
        age_days = (now - updated).days if updated else None
        is_stale = age_days is not None and age_days > stale_days
        if is_stale:
            stale_count += 1
        if issue["potentially_fixed_by"]:
            status = "maybe-fixed"
        elif blocked_by[number]:
            status = "blocked"
        elif is_stale:
            status = "stale"
        else:
            status = "ready"
        records.append(
            {
                "number": number,
                "title": issue["title"],
                "type": issue["type"],
                "priority": (
                    assign_priority(issue, blocks[number], stale_days, now)
                    if auto_priority
                    else None
                ),
                "blocks": blocks[number],
                "blocked_by": blocked_by[number],
                "status": status,
                "stale_days": age_days if is_stale else None,
                "labels": issue["labels"],
                "affected_files": issue["affected_files"],
                "updated_at": (
                    updated.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                    if updated
                    else None
                ),
                "potentially_fixed_by": issue["potentially_fixed_by"],
            }
        )

    stamp = now.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    payload = {
        "version": 1,
        "updated": stamp,
        "source": args.source,
        "analyzed_count": len(records),
        "issues": records,
        "summary": {
            "parallel_groups": parallel_groups(levels, acyclic, index),
            "stale_count": stale_count,
            "stale_threshold_days": stale_days,
            "potentially_fixed_count": len(maybe_fixed),
            "suggested_order": order,
            "circular_deps": cycles,
            "co_dependent": co_dependent,
        },
        "history": [
            {
                "time": stamp,
                "source": args.source,
                "changes": f"Full re-triage ({len(records)} issues)",
            }
        ],
    }

    text = json.dumps(payload, indent=2)
    print(text)
    if args.out:
        try:
            directory = os.path.dirname(os.path.abspath(args.out))
            if directory:
                os.makedirs(directory, exist_ok=True)
            with open(args.out, "w", encoding="utf-8") as handle:
                handle.write(text + "\n")
        except OSError as exc:
            sys.stderr.write(f"⚠ gi-triage-graph: cannot write {args.out} — {exc}\n")
            return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
