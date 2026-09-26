#!/usr/bin/env python3
"""Deterministic cost counters for skill runs — lab side only (issue #465).

Two jobs, one per subcommand:

  calls LOG
      Summarize a gh call log written by the eval shim
      (evals/harness/gh_shim.py with EVAL_GH_CALL_LOG set): the total number of
      gh invocations and a per-command tally, where a command is the first two
      argv tokens (`issue view`, `pr checks`, …). The shim records the
      normalized argv and nothing else, so the same scripted flow always yields
      the same log and this summary is byte-stable. This is the provisionally
      adopted counter: gh calls per scripted flow. It is kept as a
      deterministic regression count, not a validated cost counter. It counts
      script-issued calls; the evidence below counts agent-issued ones, so its
      link to cost is inferred, not measured (see the doc's §6).

  evidence DIR
      Mine local Claude Code session transcripts for the evidence that decides
      whether a proposed counter tracks what a run actually cost. Offline and
      read-only; DIR is required (there is no default) and is never echoed.
      Output is aggregates plus per-run numbers only — the subagent's
      description, an 8-character session prefix and counts. Transcript text
      is never printed.

Why this is not in a skill
  The run-stats footer contract (docs/decisions/run-stats-field-set.md, #414)
  forbids tallies and extra subprocesses at run time, and the token-reporting
  decision forbids a skill reading transcripts. Counting therefore happens in
  the eval lab and in this repo tool, never inside a skill run. The method and
  the recorded evidence are in docs/experiments/cost-counters-465.md.

Evidence method (mirrors the #465 analysis exactly)
  Runs     every `<DIR>/*/subagents/*.meta.json` with `spawnDepth == 1`
           whose description matches the flow's selector, minus any matching
           an --exclude regex. Its transcript is the sibling `.jsonl`.
  Nesting  a run's totals include every descendant transcript, linked by a
           child meta's `toolUseId` == a parent Agent/Task tool_use id.
  gh       regex matches of a gh subcommand in Bash tool_use commands.
  gh_bytes tool_result size of the Bash calls that contain a gh match.
  result_bytes  every tool_result: a string counts its UTF-8 bytes, anything
           else the length of its JSON serialization (ensure_ascii off).
  spawns   Agent/Task tool_uses.   tools  all tool_uses.
  tokens   per distinct assistant message id, the MAX of each of
           input_tokens, cache_creation_input_tokens, cache_read_input_tokens
           and output_tokens across that id's rows (streamed rows repeat
           usage), then the four summed over ids. Processed tokens, not bill.
  wall_s   max - min row timestamp of the run's OWN transcript.
  Stats    Spearman rho (average ranks for ties); a two-sided permutation p on
           |rho| from a seeded shuffle (default seed 465, 20000 iterations);
           partial Spearman controlling for `tools`. Runs are sorted by
           description, then session, then transcript name before any
           statistic, so p is reproducible for a given snapshot and seed.
  Join     --runs-log adds rho of each counter against runs.jsonl
           `duration_s`, keyed by the first three-digit number in the run's
           description; an issue that appears in more than one run, or that
           has other than exactly one `duration_s` record, is dropped.

Exit codes
  0  summary printed
  2  usage error
  3  invalid input — a log, transcripts dir or runs log that does not exist or
     cannot be parsed, or an --exclude regex that does not compile
  4  cannot complete — a file that exists but cannot be read or is not UTF-8
     (the call log, a transcript or the runs log). The message gives the
     reason only (the OS error text, or the offending byte offset), never the
     path the OS error carries, so the transcripts DIR stays unechoed.

Authored at scripts/idd-cost-counters.py — repo tooling; not bundled into
skills.
"""

from __future__ import annotations

import argparse
import datetime
import glob
import json
import os
import random
import re
import sys
from collections import Counter
from typing import Any

SEP = "┄" * 56
DEFAULT_SEED = 465
DEFAULT_ITERATIONS = 20000

# A gh subcommand at a command boundary: start, whitespace, ; & | ( ` $.
GH_RE = re.compile(
    r"(?:^|[\s;&|(`$])gh\s+"
    r"(?:issue|pr|api|repo|run|label|project|search|release|workflow|auth)\b"
)
FLOWS: dict[str, dict[str, Any]] = {
    "resolver": {"selector": r"^Resolve", "join": True},
    "review": {"selector": r"^(Review PR|reviewer|Code review)", "join": False},
}
COUNTERS = ("gh", "gh_bytes", "result_bytes", "spawns")
USAGE_KEYS = (
    "input_tokens",
    "cache_creation_input_tokens",
    "cache_read_input_tokens",
    "output_tokens",
)
ISSUE_RE = re.compile(r"(\d{3})")


class InputError(Exception):
    """Unusable input — exit 3."""


class Unavailable(Exception):
    """A file could not be read or decoded — exit 4."""


def _why(exc: Exception) -> str:
    """The reason an existing file could not be read, without its path.

    str(OSError) embeds the filename, which may sit under the transcripts DIR
    this tool promises never to echo, so only strerror is used.
    """
    if isinstance(exc, UnicodeDecodeError):
        return f"not UTF-8 at byte {exc.start}"
    if isinstance(exc, OSError):
        return exc.strerror or type(exc).__name__
    return type(exc).__name__


# ─── calls ────────────────────────────────────────────────


def summarize_calls(path: str) -> dict[str, Any]:
    """Total and per-command tally of one shim call log."""
    if not os.path.isfile(path):
        raise InputError(f"no gh call log at {path}")
    by_command: Counter[str] = Counter()
    total = 0
    try:
        with open(path, encoding="utf-8") as fh:
            for lineno, line in enumerate(fh, 1):
                if not line.strip():
                    continue
                try:
                    record = json.loads(line)
                except ValueError as exc:
                    raise InputError(f"log line {lineno} is not JSON — {exc}") from exc
                argv = record.get("argv") if isinstance(record, dict) else None
                if not isinstance(argv, list) or not all(isinstance(a, str) for a in argv):
                    raise InputError(f"log line {lineno} has no argv string list")
                total += 1
                by_command[" ".join(argv[:2])] += 1
    except (OSError, UnicodeError) as exc:
        raise Unavailable(f"cannot read the gh call log — {_why(exc)}") from exc
    return {"total": total, "by_command": dict(sorted(by_command.items()))}


def render_calls(summary: dict[str, Any]) -> str:
    lines = ["◆ gh call counter", SEP, f"  total │ {summary['total']}"]
    for command, n in summary["by_command"].items():
        lines.append(f"  {command or '(bare)'} │ {n}")
    lines.append(SEP)
    return "\n".join(lines)


# ─── evidence: mining ─────────────────────────────────────


def _load_rows(path: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                try:
                    row = json.loads(line)
                except ValueError:
                    continue
                if isinstance(row, dict):
                    rows.append(row)
    except (OSError, UnicodeError) as exc:
        raise Unavailable(f"cannot read a transcript — {_why(exc)}") from exc
    return rows


def _timestamp(raw: Any) -> float | None:
    if not isinstance(raw, str):
        return None
    try:
        return datetime.datetime.fromisoformat(raw.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def _result_bytes(content: Any) -> int:
    if isinstance(content, str):
        return len(content.encode("utf-8"))
    return len(json.dumps(content, ensure_ascii=False))


def transcript_metrics(path: str) -> dict[str, Any]:
    """Counters for ONE transcript, excluding its children."""
    m: dict[str, Any] = {
        "gh": 0, "gh_bytes": 0, "result_bytes": 0, "spawns": 0, "tools": 0,
        "tokens": 0, "wall_s": 0, "spawn_ids": [],
    }
    usage: dict[str, dict[str, int]] = {}
    gh_ids: set[str] = set()
    stamps: list[float] = []
    for row in _load_rows(path):
        if "timestamp" in row:
            ts = _timestamp(row["timestamp"])
            if ts is not None:
                stamps.append(ts)
        msg = row.get("message")
        if not isinstance(msg, dict):
            continue
        content = msg.get("content")
        if row.get("type") == "assistant":
            mid, u = msg.get("id"), msg.get("usage")
            if mid and isinstance(u, dict) and u:
                cur = usage.setdefault(mid, {})
                for key in USAGE_KEYS:
                    value = u.get(key) or 0
                    if value > cur.get(key, 0):
                        cur[key] = value
            for item in content if isinstance(content, list) else []:
                if not isinstance(item, dict) or item.get("type") != "tool_use":
                    continue
                m["tools"] += 1
                name = item.get("name")
                if name == "Bash":
                    tool_input = item.get("input")
                    command = tool_input.get("command", "") if isinstance(tool_input, dict) else ""
                    hits = len(GH_RE.findall(command if isinstance(command, str) else ""))
                    m["gh"] += hits
                    if hits:
                        gh_ids.add(item.get("id"))
                elif name in ("Agent", "Task"):
                    m["spawns"] += 1
                    m["spawn_ids"].append(item.get("id"))
        elif row.get("type") == "user":
            for item in content if isinstance(content, list) else []:
                if isinstance(item, dict) and item.get("type") == "tool_result":
                    size = _result_bytes(item.get("content"))
                    m["result_bytes"] += size
                    if item.get("tool_use_id") in gh_ids:
                        m["gh_bytes"] += size
    m["tokens"] = sum(sum(cur.values()) for cur in usage.values())
    m["wall_s"] = round(max(stamps) - min(stamps)) if stamps else 0
    return m


def discover(transcripts_dir: str) -> dict[str, dict[str, Any]]:
    """Map each subagent transcript with a readable meta to that meta."""
    metas: dict[str, dict[str, Any]] = {}
    pattern = os.path.join(glob.escape(transcripts_dir), "*", "subagents", "*.meta.json")
    for meta_path in sorted(glob.glob(pattern)):
        transcript = meta_path[: -len(".meta.json")] + ".jsonl"
        if not os.path.isfile(transcript):
            continue
        try:
            with open(meta_path, encoding="utf-8") as fh:
                meta = json.load(fh)
        except (OSError, ValueError, UnicodeError):
            continue
        if isinstance(meta, dict):
            metas[transcript] = meta
    return metas


class Miner:
    """Aggregate each run with its descendants, memoized per transcript."""

    def __init__(self, metas: dict[str, dict[str, Any]]) -> None:
        self.metas = metas
        self.by_tool_use = {
            meta.get("toolUseId"): path
            for path, meta in metas.items()
            if meta.get("toolUseId")
        }
        self._own: dict[str, dict[str, Any]] = {}
        self._total: dict[str, dict[str, Any]] = {}

    def own(self, path: str) -> dict[str, Any]:
        if path not in self._own:
            self._own[path] = transcript_metrics(path)
        return self._own[path]

    def total(self, path: str, _seen: frozenset[str] = frozenset()) -> dict[str, Any]:
        if path in self._total:
            return self._total[path]
        own = self.own(path)
        tot = {k: own[k] for k in ("gh", "gh_bytes", "result_bytes", "spawns", "tools", "tokens")}
        tot["wall_s"] = own["wall_s"]
        tot["children"] = 0
        seen = _seen | {path}
        for spawn_id in own["spawn_ids"]:
            child = self.by_tool_use.get(spawn_id)
            if child is None or child in seen:
                continue
            sub = self.total(child, seen)
            tot["children"] += 1 + sub["children"]
            for key in ("gh", "gh_bytes", "result_bytes", "spawns", "tools", "tokens"):
                tot[key] += sub[key]
        self._total[path] = tot
        return tot


def select_runs(
    miner: Miner, selector: str, excludes: list[re.Pattern[str]]
) -> list[dict[str, Any]]:
    """Top-level runs of one flow, as numeric rows in a total order."""
    select = re.compile(selector)
    picked = []
    for path, meta in miner.metas.items():
        description = meta.get("description")
        if meta.get("spawnDepth") != 1 or not isinstance(description, str):
            continue
        if not select.search(description) or any(x.search(description) for x in excludes):
            continue
        session = os.path.basename(os.path.dirname(os.path.dirname(path)))
        picked.append((description, session, os.path.basename(path), path))
    picked.sort()
    rows = []
    for description, session, _name, path in picked:
        row = {"description": description, "session": session[:8]}
        row.update(miner.total(path))
        rows.append(row)
    return rows


# ─── evidence: statistics ─────────────────────────────────


def rank(values: list[float]) -> list[float]:
    """1-based ranks, ties sharing their average rank."""
    order = sorted(range(len(values)), key=lambda i: values[i])
    ranks = [0.0] * len(values)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and values[order[j + 1]] == values[order[i]]:
            j += 1
        for k in range(i, j + 1):
            ranks[order[k]] = (i + j) / 2 + 1
        i = j + 1
    return ranks


def pearson(x: list[float], y: list[float]) -> float | None:
    n = len(x)
    mx, my = sum(x) / n, sum(y) / n
    sx = sum((a - mx) ** 2 for a in x) ** 0.5
    sy = sum((b - my) ** 2 for b in y) ** 0.5
    if sx == 0 or sy == 0:
        return None
    return sum((a - mx) * (b - my) for a, b in zip(x, y)) / (sx * sy)


def spearman(x: list[float], y: list[float]) -> float | None:
    return pearson(rank(x), rank(y))


def permutation_p(x: list[float], y: list[float], seed: int, iterations: int) -> float | None:
    """Share of seeded shuffles of y whose |rho| reaches the observed |rho|.

    Ranking commutes with shuffling, so y's ranks are shuffled in place — one
    list, shuffled cumulatively, one generator per test — which is the same
    random stream and the same statistic as re-ranking a shuffled y each time.
    """
    rx, ry = rank(x), rank(y)
    observed = pearson(rx, ry)
    if observed is None:
        return None
    r0 = abs(observed)
    rng = random.Random(seed)
    hits = 0
    for _ in range(iterations):
        rng.shuffle(ry)
        r = pearson(rx, ry)
        if r is not None and abs(r) >= r0:
            hits += 1
    return hits / iterations


def partial_spearman(x: list[float], y: list[float], z: list[float]) -> float | None:
    rx, ry, rz = rank(x), rank(y), rank(z)
    rxy, rxz, ryz = pearson(rx, ry), pearson(rx, rz), pearson(ry, rz)
    if rxy is None or rxz is None or ryz is None:
        return None
    # With z perfectly rank-collinear to x or y the partial is undefined; the
    # guard also keeps float error (|r| a hair above 1) out of the square root.
    rest_x, rest_y = 1 - rxz**2, 1 - ryz**2
    if rest_x <= 1e-12 or rest_y <= 1e-12:
        return None
    denominator = (rest_x * rest_y) ** 0.5
    return (rxy - rxz * ryz) / denominator


def _r6(value: float | None) -> float | None:
    return None if value is None else round(value, 6)


def correlate(
    x: list[float], y: list[float], seed: int, iterations: int
) -> dict[str, Any]:
    if len(x) < 3:
        return {"rho": None, "p": None}
    return {
        "rho": _r6(spearman(x, y)),
        "p": permutation_p(x, y, seed, iterations),
    }


def counter_stats(rows: list[dict[str, Any]], seed: int, iterations: int) -> dict[str, Any]:
    tokens = [r["tokens"] for r in rows]
    wall = [r["wall_s"] for r in rows]
    tools = [r["tools"] for r in rows]
    stats: dict[str, Any] = {}
    for counter in COUNTERS:
        x = [r[counter] for r in rows]
        vs_tokens = correlate(x, tokens, seed, iterations)
        vs_wall = correlate(x, wall, seed, iterations)
        stats[counter] = {
            "rho_tokens": vs_tokens["rho"],
            "p_tokens": vs_tokens["p"],
            "partial_tools": _r6(partial_spearman(x, tokens, tools)) if len(x) >= 3 else None,
            "rho_wall": vs_wall["rho"],
            "p_wall": vs_wall["p"],
        }
    return stats


def load_durations(path: str) -> dict[int, list[Any]]:
    if not os.path.isfile(path):
        raise InputError(f"no runs log at {path}")
    durations: dict[int, list[Any]] = {}
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                try:
                    record = json.loads(line)
                except ValueError:
                    continue
                if isinstance(record, dict) and "duration_s" in record:
                    issue = record.get("issue")
                    if type(issue) is int:
                        durations.setdefault(issue, []).append(record["duration_s"])
    except (OSError, UnicodeError) as exc:
        raise Unavailable(f"cannot read the runs log — {_why(exc)}") from exc
    return durations


def duration_join(
    rows: list[dict[str, Any]], durations: dict[int, list[Any]], seed: int, iterations: int
) -> dict[str, Any]:
    issues = []
    for row in rows:
        m = ISSUE_RE.search(row["description"])
        issues.append(int(m.group(1)) if m else None)
    seen = Counter(n for n in issues if n is not None)
    pairs = []
    for row, n in zip(rows, issues):
        ds = durations.get(n) if n is not None else None
        if n is not None and seen[n] == 1 and ds and len(ds) == 1 and isinstance(ds[0], (int, float)):
            pairs.append((row, ds[0]))
    y = [d for _row, d in pairs]
    out: dict[str, Any] = {"n": len(pairs)}
    for key in ("gh", "tokens"):
        out[key] = correlate([row[key] for row, _d in pairs], y, seed, iterations)
    return out


def mine(
    transcripts_dir: str,
    flows: list[str],
    excludes: list[str],
    runs_log: str | None,
    seed: int,
    iterations: int,
) -> dict[str, Any]:
    if not os.path.isdir(transcripts_dir):
        raise InputError("transcripts dir does not exist or is not a directory")
    try:
        exclude_res = [re.compile(x) for x in excludes]
    except re.error as exc:
        raise InputError(f"--exclude does not compile — {exc}") from exc
    durations = load_durations(runs_log) if runs_log else None
    miner = Miner(discover(transcripts_dir))
    result: dict[str, Any] = {
        "seed": seed,
        "iterations": iterations,
        "excludes": list(excludes),
        "flows": {},
    }
    for flow in flows:
        spec = FLOWS[flow]
        rows = select_runs(miner, spec["selector"], exclude_res)
        entry: dict[str, Any] = {
            "selector": spec["selector"],
            "n": len(rows),
            "runs": rows,
            "counters": counter_stats(rows, seed, iterations),
        }
        if durations is not None and spec["join"]:
            entry["duration_join"] = duration_join(rows, durations, seed, iterations)
        result["flows"][flow] = entry
    return result


def _fmt(value: float | None) -> str:
    return "—" if value is None else f"{value:.2f}"


def _fmt_p(value: float | None, iterations: int) -> str:
    """A permutation p; zero hits is reported as a bound, never as p = 0."""
    if value is None:
        return "—"
    return f"<{1 / iterations:g}" if value == 0 else f"{value:g}"


def render_evidence(result: dict[str, Any]) -> str:
    its = result["iterations"]
    lines = [
        "◆ cost-counter evidence",
        SEP,
        f"  seed {result['seed']} · {result['iterations']} permutations"
        + (f" · excluded {', '.join(result['excludes'])}" if result["excludes"] else ""),
    ]
    for flow, entry in result["flows"].items():
        lines += ["", f"  ● {flow}  ({entry['selector']})  n={entry['n']}", ""]
        lines.append(
            "  run │ session │ gh │ gh_bytes │ result_bytes │ spawns │ tools │ tokens │ wall_s │ children"
        )
        for r in entry["runs"]:
            lines.append(
                f"  {r['description'][:40]} │ {r['session']} │ {r['gh']} │ {r['gh_bytes']} │ "
                f"{r['result_bytes']} │ {r['spawns']} │ {r['tools']} │ {r['tokens']} │ "
                f"{r['wall_s']} │ {r['children']}"
            )
        lines += ["", "  counter │ ρ tokens │ p │ partial ρ | tools │ ρ wall │ p"]
        for counter, s in entry["counters"].items():
            lines.append(
                f"  {counter} │ {_fmt(s['rho_tokens'])} │ {_fmt_p(s['p_tokens'], its)} │ "
                f"{_fmt(s['partial_tools'])} │ {_fmt(s['rho_wall'])} │ {_fmt_p(s['p_wall'], its)}"
            )
        join = entry.get("duration_join")
        if join is not None:
            lines.append(
                f"  duration_s join n={join['n']} │ gh ρ {_fmt(join['gh']['rho'])} "
                f"p {_fmt_p(join['gh']['p'], its)} │ tokens ρ {_fmt(join['tokens']['rho'])} "
                f"p {_fmt_p(join['tokens']['p'], its)}"
            )
    lines.append(SEP)
    return "\n".join(lines)


# ─── CLI ──────────────────────────────────────────────────


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="idd-cost-counters.py",
        description=(
            "Deterministic cost counters for skill runs (issue #465): summarize "
            "an eval gh call log, or mine local transcripts for the evidence "
            "that a counter tracks run cost. Lab-side only — never run by a skill."
        ),
        epilog="Exit codes: 0 ok · 2 usage · 3 invalid input · 4 cannot complete.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    calls = sub.add_parser("calls", help="summarize an EVAL_GH_CALL_LOG file")
    calls.add_argument("log", help="gh call log (one {\"argv\": [...]} per line)")
    calls.add_argument("--json", action="store_true", help="print one JSON object")

    evidence = sub.add_parser(
        "evidence", help="mine transcripts for counter-vs-cost correlations"
    )
    evidence.add_argument(
        "transcripts_dir",
        help="a Claude Code project transcripts dir (required; never defaulted)",
    )
    evidence.add_argument(
        "--flow",
        action="append",
        choices=sorted(FLOWS),
        help="flow to mine (repeatable; default: all)",
    )
    evidence.add_argument(
        "--exclude",
        action="append",
        default=[],
        metavar="REGEX",
        help="drop runs whose description matches (repeatable), e.g. an in-progress run",
    )
    evidence.add_argument("--runs-log", metavar="PATH", help="runs.jsonl to join duration_s from")
    evidence.add_argument("--seed", type=int, default=DEFAULT_SEED)
    evidence.add_argument("--iterations", type=int, default=DEFAULT_ITERATIONS)
    evidence.add_argument("--json", action="store_true", help="print one JSON object")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == "calls":
            result = summarize_calls(args.log)
            text = render_calls(result)
        else:
            if args.iterations < 1:
                parser.error("--iterations must be >= 1")
            flows = sorted(set(args.flow)) if args.flow else sorted(FLOWS)
            result = mine(
                args.transcripts_dir, flows, args.exclude, args.runs_log,
                args.seed, args.iterations,
            )
            text = render_evidence(result)
    except InputError as exc:
        print(f"✗ idd-cost-counters: {exc}", file=sys.stderr)
        return 3
    except Unavailable as exc:
        print(f"⚠ idd-cost-counters: {exc}", file=sys.stderr)
        return 4
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True, ensure_ascii=False))
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
