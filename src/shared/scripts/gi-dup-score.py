#!/usr/bin/env python3
"""Deterministically score proposed issues against the open backlog.

Proposed items and resolved ``duplicate_detection.*`` configuration arrive as
one JSON object on stdin. Existing issues are either fetched by this script via
``gh --json`` or read from ``--issues-from`` for tests/debugging. Issue text is
never accepted as a command-line argument.

The scorer's invariant is structural: every payment is computed from canonical
item tokens that no earlier signal consumed. Title phrases, title overlap, and
keyword evidence all use one Unicode-aware tokenizer and one stop-word/minimum-
length policy. Keywords are a token union, so grouping, order, overlap, and
duplication cannot alter a score.

Exit codes: 0 scored; 2 usage; 3 invalid input; 4 backlog unavailable.
"""

from __future__ import annotations

import argparse
import json
import runpy
import sys
import unicodedata
from pathlib import Path
from typing import Any

_RUN_GH = runpy.run_path(str(Path(__file__).with_name("gi-gh.py")))["run_gh"]

DEFAULTS: dict[str, Any] = {
    "weights.phrase": 2,
    "weights.title_overlap": 2,
    "weights.keyword": 1,
    "weights.same_type": 1,
    "high_threshold": 5,
    "medium_threshold": 3,
    "min_token_length": 1,
    "phrase_min_tokens": 3,
    "backlog_limit": 100,
    "max_items": 100,
    "extra_stop_words": "",
}
STOP_WORDS = frozenset(
    """a an the to for in on of and or is it be as at by with from that this not
    but are was all has its can will should when if add fix update issue bug
    feature improvement create make get set""".split()
)
TYPE_ALIASES = {
    "bug": "bug", "defect": "bug", "fix": "bug",
    "feature": "feature", "enhancement": "improvement",
    "improvement": "improvement", "refactor": "improvement",
}
CONFIG_PREFIX = "duplicate_detection."
MEDIUM_BODY_CHAR_LIMIT = 1000
MEDIUM_JUDGEMENT_BATCH_SIZE = 20
MEDIUM_JUDGEMENT_LIMIT = 200


class InvalidInput(Exception):
    """Request/configuration cannot be scored (exit 3)."""


class Unavailable(Exception):
    """Backlog cannot be read (exit 4)."""


def canonical_tokens(text: str) -> list[str]:
    """Return NFKC/case-folded alphanumeric tokens, preserving order."""
    normalized = unicodedata.normalize("NFKC", text).casefold()
    tokens: list[str] = []
    current: list[str] = []
    for char in normalized:
        if char.isalnum():
            current.append(char)
        elif current:
            tokens.append("".join(current))
            current = []
    if current:
        tokens.append("".join(current))
    return tokens


def _flatten_config(raw: object) -> dict[str, object]:
    """Accept gi-config's dotted mapping or a nested duplicate_detection map."""
    if raw is None:
        return {}
    if not isinstance(raw, dict):
        raise InvalidInput("config must be an object")
    if "duplicate_detection" in raw:
        section = raw["duplicate_detection"]
        if not isinstance(section, dict):
            raise InvalidInput("config.duplicate_detection must be an object")
        out: dict[str, object] = {}
        for key, value in section.items():
            if key == "weights":
                if not isinstance(value, dict):
                    raise InvalidInput("duplicate_detection.weights must be an object")
                for weight, weight_value in value.items():
                    out[f"weights.{weight}"] = weight_value
            else:
                out[str(key)] = value
        return out
    return {
        key[len(CONFIG_PREFIX):]: value
        for key, value in raw.items()
        if isinstance(key, str) and key.startswith(CONFIG_PREFIX)
    }


def resolve_config(raw: object, args: argparse.Namespace) -> dict[str, Any]:
    values = dict(DEFAULTS)
    overrides = _flatten_config(raw)
    unknown = sorted(set(overrides) - set(DEFAULTS))
    if unknown:
        raise InvalidInput("unknown duplicate_detection key(s): " + ", ".join(unknown))
    values.update(overrides)
    if args.limit is not None:
        values["backlog_limit"] = args.limit
    if args.high is not None:
        values["high_threshold"] = args.high
    if args.medium is not None:
        values["medium_threshold"] = args.medium

    integer_keys = [key for key in DEFAULTS if key != "extra_stop_words"]
    for key in integer_keys:
        value = values[key]
        if not isinstance(value, int) or isinstance(value, bool):
            raise InvalidInput(f"duplicate_detection.{key} must be an integer")
        minimum = 0 if key.startswith("weights.") else 1
        if value < minimum:
            raise InvalidInput(f"duplicate_detection.{key} must be >= {minimum}")
    if values["medium_threshold"] > values["high_threshold"]:
        raise InvalidInput(
            "duplicate_detection.medium_threshold must not exceed high_threshold"
        )
    if values["weights.phrase"] < values["weights.title_overlap"]:
        raise InvalidInput(
            "duplicate_detection.weights.phrase must be >= weights.title_overlap"
        )
    extra = values["extra_stop_words"]
    if isinstance(extra, str):
        extra = [part.strip() for part in extra.split(",") if part.strip()]
    if not isinstance(extra, list) or not all(isinstance(word, str) for word in extra):
        raise InvalidInput("duplicate_detection.extra_stop_words must be a list of strings")
    values["extra_stop_words"] = extra
    return values


def active_tokens(text: str, stop_words: frozenset[str], minimum: int) -> list[str]:
    return [
        token for token in canonical_tokens(text)
        if len(token) >= minimum and token not in stop_words
    ]


def evidence_sequence(
    text: str, stop_words: frozenset[str], minimum: int
) -> list[str | None]:
    """Canonical sequence with ignored tokens retained as phrase barriers.

    Dropping ignored tokens before phrase matching would join their neighbours.
    Adding a stop word could then create a new phrase and *raise* a score, the
    inverse of the option's contract. ``None`` prevents that silent adjacency.
    """
    return [
        token if len(token) >= minimum and token not in stop_words else None
        for token in canonical_tokens(text)
    ]


def phrase_hit(
    item_tokens: list[str | None], target_tokens: list[str | None], minimum: int
) -> list[str]:
    """Longest contiguous active phrase; ignored tokens are hard barriers."""
    if len(item_tokens) < minimum or len(target_tokens) < minimum:
        return []
    for size in range(min(len(item_tokens), len(target_tokens)), minimum - 1, -1):
        target_runs = {
            tuple(target_tokens[start:start + size])
            for start in range(len(target_tokens) - size + 1)
            if None not in target_tokens[start:start + size]
        }
        for start in range(len(item_tokens) - size + 1):
            run = item_tokens[start:start + size]
            if None not in run and tuple(run) in target_runs:
                return [str(token) for token in run]
    return []


def normalize_type(value: object) -> str | None:
    return TYPE_ALIASES.get(str(value or "").strip().casefold())


def issue_type(labels: object) -> str | None:
    if not isinstance(labels, list):
        return None
    for label in labels:
        name = label.get("name") if isinstance(label, dict) else label
        normalized = normalize_type(name)
        if normalized:
            return normalized
    return None


def score_pair(item: dict[str, Any], target: dict[str, Any], config: dict[str, Any]) -> dict[str, Any]:
    """Score one direction and return token-level payment provenance."""
    minimum = config["min_token_length"]
    extra_tokens = {
        token
        for word in config["extra_stop_words"]
        for token in canonical_tokens(word)
    }
    stop_words = frozenset(STOP_WORDS | extra_tokens)
    item_title = active_tokens(item["title"], stop_words, minimum)
    target_title = active_tokens(str(target.get("title") or ""), stop_words, minimum)
    item_title_sequence = evidence_sequence(item["title"], stop_words, minimum)
    target_title_sequence = evidence_sequence(
        str(target.get("title") or ""), stop_words, minimum
    )
    target_body = active_tokens(str(target.get("body") or ""), stop_words, minimum)
    target_all = set(target_title) | set(target_body)
    keyword_tokens = {
        token
        for keyword in item.get("keywords", [])
        for token in active_tokens(str(keyword), stop_words, minimum)
    }

    consumed: set[str] = set()
    payments: list[dict[str, Any]] = []
    score = 0

    phrase = phrase_hit(
        item_title_sequence, target_title_sequence, config["phrase_min_tokens"]
    )
    if phrase:
        novel = sorted(set(phrase) - consumed)
        amount = len(novel) * config["weights.phrase"]
        if amount:
            score += amount
            consumed.update(novel)
            payments.append({"signal": "phrase", "tokens": novel, "amount": amount})

    shared_title = sorted((set(item_title) & set(target_title)) - consumed)
    if shared_title:
        amount = len(shared_title) * config["weights.title_overlap"]
        if amount:
            score += amount
            consumed.update(shared_title)
            payments.append(
                {"signal": "title_overlap", "tokens": shared_title, "amount": amount}
            )

    shared_keywords = sorted((keyword_tokens & target_all) - consumed)
    if shared_keywords:
        amount = len(shared_keywords) * config["weights.keyword"]
        if amount:
            score += amount
            consumed.update(shared_keywords)
            payments.append(
                {"signal": "keyword", "tokens": shared_keywords, "amount": amount}
            )

    item_type = normalize_type(item.get("type"))
    target_type = normalize_type(target.get("type")) or issue_type(target.get("labels"))
    if item_type and item_type == target_type and config["weights.same_type"]:
        amount = config["weights.same_type"]
        score += amount
        payments.append({"signal": "same_type", "tokens": [], "amount": amount})

    return {
        "score": score,
        "shared_keywords": shared_keywords,
        "consumed_tokens": sorted(consumed),
        "payments": payments,
    }


def read_request() -> dict[str, Any]:
    buffer = getattr(sys.stdin, "buffer", None)
    raw = buffer.read().decode("utf-8", errors="replace") if buffer else sys.stdin.read()
    if not raw.strip():
        raise InvalidInput("no request object on stdin")
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise InvalidInput(f"stdin is not valid JSON — {exc.msg}") from exc
    if not isinstance(value, dict):
        raise InvalidInput("stdin must hold a JSON object")
    return value


def normalize_items(request: dict[str, Any], maximum: int) -> list[dict[str, Any]]:
    items = request.get("items")
    if not isinstance(items, list) or not items:
        raise InvalidInput("request must carry a non-empty 'items' array")
    if len(items) > maximum:
        raise InvalidInput(f"request carries {len(items)} items; maximum is {maximum}")
    normalized: list[dict[str, Any]] = []
    seen: set[int] = set()
    for position, raw in enumerate(items, start=1):
        if not isinstance(raw, dict):
            raise InvalidInput(f"items[{position - 1}] must be an object")
        title = raw.get("title")
        if not isinstance(title, str) or not title.strip():
            raise InvalidInput(f"items[{position - 1}].title must be a non-empty string")
        keywords = raw.get("keywords", [])
        if not isinstance(keywords, list) or not all(isinstance(k, str) for k in keywords):
            raise InvalidInput(f"items[{position - 1}].keywords must be an array of strings")
        index = raw.get("index", position)
        if not isinstance(index, int) or isinstance(index, bool) or index in seen:
            raise InvalidInput(f"items[{position - 1}].index must be a unique integer")
        seen.add(index)
        normalized.append({
            "index": index,
            "title": title,
            "keywords": keywords,
            "type": normalize_type(raw.get("type")),
        })
    return normalized


def load_issue_file(path: str, limit: int) -> tuple[list[dict[str, Any]], bool]:
    try:
        value = json.loads(Path(path).read_text(encoding="utf-8"))
    except OSError as exc:
        raise Unavailable(f"cannot read {path} — {exc}") from exc
    except json.JSONDecodeError as exc:
        raise InvalidInput(f"{path} is not valid JSON — {exc.msg}") from exc
    if not isinstance(value, list):
        raise InvalidInput(f"{path} must hold a JSON array")
    issues = [entry for entry in value if isinstance(entry, dict)]
    return issues[:limit], len(issues) > limit


def _gh_issue_list(limit: int, repo: str | None, fields: str) -> list[dict[str, Any]]:
    command = ["issue", "list", "--state", "open", "--json", fields, "--limit", str(limit)]
    if repo:
        command.extend(["--repo", repo])
    result = _RUN_GH(command, Unavailable)
    if result.returncode:
        detail = result.stderr.strip().splitlines()
        raise Unavailable("gh issue list failed: " + (detail[-1] if detail else f"exit {result.returncode}"))
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise Unavailable(f"gh printed unparsable JSON — {exc.msg}") from exc
    if not isinstance(value, list):
        raise Unavailable("gh issue list did not return a JSON array")
    return [entry for entry in value if isinstance(entry, dict)]


def fetch_issues(limit: int, repo: str | None) -> tuple[list[dict[str, Any]], bool]:
    issues = _gh_issue_list(limit, repo, "number,title,body,labels")
    truncated = False
    if len(issues) == limit:
        truncated = len(_gh_issue_list(limit + 1, repo, "number")) > limit
    return issues, truncated


def band(score: int, config: dict[str, Any]) -> str:
    if score >= config["high_threshold"]:
        return "high"
    if score >= config["medium_threshold"]:
        return "medium"
    return "low"


def record_for(
    item: dict[str, Any], target: dict[str, Any], scored: dict[str, Any], match_type: str
) -> dict[str, Any]:
    record: dict[str, Any] = {
        "item_index": item["index"],
        "match_type": match_type,
        "match_title": str(target.get("title") or ""),
        "score": scored["score"],
        "shared_keywords": scored["shared_keywords"],
        "payments": scored["payments"],
        "reason": "; ".join(
            f"{payment['signal']} +{payment['amount']}"
            for payment in scored["payments"]
        ) or "no paid evidence",
    }
    if match_type == "existing_issue":
        record.update({
            "match_number": target["number"],
            "match_labels": target.get("labels") or [],
        })
    else:
        record["match_index"] = target["index"]
    return record


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-dup-score.py",
        description="Score stdin issue items; issue text is never a command-line argument.",
    )
    parser.add_argument("--repo", metavar="OWNER/NAME")
    parser.add_argument("--issues-from", metavar="FILE")
    parser.add_argument("--limit", type=int, metavar="N")
    parser.add_argument("--high", type=int, metavar="N")
    parser.add_argument("--medium", type=int, metavar="N")
    args = parser.parse_args(argv)

    try:
        request = read_request()
        config = resolve_config(request.get("config"), args)
        items = normalize_items(request, config["max_items"])
        mode = request.get("mode", "create")
        if mode not in ("create", "batch"):
            raise InvalidInput("mode must be 'create' or 'batch'")
        if args.issues_from:
            issues, truncated = load_issue_file(args.issues_from, config["backlog_limit"])
            source = "file"
        else:
            issues, truncated = fetch_issues(config["backlog_limit"], args.repo)
            source = "gh"
    except InvalidInput as exc:
        sys.stderr.write(f"✗ gi-dup-score: {exc}\n")
        return 3
    except Unavailable as exc:
        sys.stderr.write(f"⚠ gi-dup-score: {exc}\n")
        return 4

    high_matches: list[dict[str, Any]] = []
    medium_matches: list[dict[str, Any]] = []
    internal_high: list[dict[str, Any]] = []

    for item in items:
        for issue in issues:
            if not isinstance(issue.get("number"), int):
                continue
            scored = score_pair(item, issue, config)
            level = band(scored["score"], config)
            if level == "low":
                continue
            record = record_for(item, issue, scored, "existing_issue")
            record["confidence"] = level
            if level == "high":
                record["match_labels"] = issue.get("labels") or []
                high_matches.append(record)
            else:
                # Medium candidates reference the deduplicated context table.
                # Repeating title/body/labels for every item × issue pair makes
                # the supported 100 × 100 request unusably large.
                record.pop("match_title", None)
                medium_matches.append(record)

    if mode == "batch":
        for left_pos, left in enumerate(items):
            for right in items[left_pos + 1:]:
                forward = score_pair(left, right, config)
                backward = score_pair(right, left, config)
                reverse_wins = backward["score"] > forward["score"] or (
                    backward["score"] == forward["score"]
                    and right["index"] < left["index"]
                )
                if reverse_wins:
                    source_item, target, strongest, direction = right, left, backward, "reverse"
                else:
                    source_item, target, strongest, direction = left, right, forward, "forward"
                level = band(strongest["score"], config)
                if level == "low":
                    continue
                record = record_for(source_item, target, strongest, "batch_internal")
                record.update({
                    "confidence": level,
                    "pair": sorted([left["index"], right["index"]]),
                    "direction": direction,
                    "directional_scores": {
                        str(left["index"]): forward["score"],
                        str(right["index"]): backward["score"],
                    },
                })
                (internal_high if level == "high" else medium_matches).append(record)

    def order(record: dict[str, Any]) -> tuple[Any, ...]:
        return (
            tuple(record.get("pair", [record["item_index"]])),
            -record["score"],
            record.get("match_number", record.get("match_index", 0)),
        )

    ordered_medium = sorted(medium_matches, key=order)
    medium_issue_numbers = {
        record["match_number"]
        for record in ordered_medium
        if record["match_type"] == "existing_issue"
    }
    medium_issue_context = []
    for issue in issues:
        if issue.get("number") not in medium_issue_numbers:
            continue
        body = str(issue.get("body") or "")
        medium_issue_context.append({
            "number": issue["number"],
            "title": str(issue.get("title") or ""),
            "body": body[:MEDIUM_BODY_CHAR_LIMIT],
            "body_truncated": len(body) > MEDIUM_BODY_CHAR_LIMIT,
            "labels": issue.get("labels") or [],
        })
    medium_issue_context.sort(key=lambda issue: issue["number"])
    selected_count = min(len(ordered_medium), MEDIUM_JUDGEMENT_LIMIT)

    output = {
        "duplicates": sorted(high_matches, key=order),
        "medium_band": ordered_medium,
        "medium_issue_context": medium_issue_context,
        "medium_judgement": {
            "selected_count": selected_count,
            "deferred_count": len(ordered_medium) - selected_count,
            "batch_size": MEDIUM_JUDGEMENT_BATCH_SIZE,
            "body_char_limit": MEDIUM_BODY_CHAR_LIMIT,
        },
        "batch_internal_duplicates": sorted(internal_high, key=order),
        "open_issue_count": len(issues),
        "scan_truncated": truncated,
        "items_checked": len(items),
        "issue_source": source,
        "mode": mode,
        "weights": {
            key.removeprefix("weights."): config[key]
            for key in config if key.startswith("weights.")
        },
        "thresholds": {
            "high": config["high_threshold"],
            "medium": config["medium_threshold"],
        },
        "token_policy": {
            "normalization": "NFKC+casefold",
            "min_length": config["min_token_length"],
            "phrase_min_tokens": config["phrase_min_tokens"],
        },
    }
    print(json.dumps(output, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
