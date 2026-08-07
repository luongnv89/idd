#!/usr/bin/env python3
"""Score proposed issues against the open backlog for duplicates.

The scoring table `/issue-creator` uses is fixed arithmetic — +3 for a title
overlap, +2 per matched keyword, +1 for a shared type, +5 for a verbatim
phrase, then two thresholds. The three sightings are scored over disjoint
regions of the target so that one observation can never pay twice: the +3 and
the +5 split title from body, and a keyword whose every token a title signal
has **already counted** is that same sighting read again and does not pay. A
keyword contributing a term no paid signal counted still does. See `score_pair`.

Running it inside a language model means reading up to 100 issue bodies into a
context window (10-20k tokens on every create) to compute a sum that has one
correct answer. This script computes it, and leaves the model the only part
that genuinely needs judgement: the medium band, where a score is suggestive
rather than conclusive.

Untrusted input never travels on the command line. The proposed items arrive as
JSON **on stdin**, and the existing issues are fetched by this script calling
`gh` itself. Both are attacker-controlled — anyone can file an issue on a public
repository, and `/auto-pilot` creates issues unattended — so a title
interpolated into a shell word could close its quote and append a command.

Input on stdin, one JSON object:

    {"mode": "create" | "batch",
     "items": [{"index": 1, "title": "...", "keywords": ["..."],
                "type": "bug" | "feature" | "improvement"}]}

Output on stdout, one JSON object:

    {"duplicates": [...], "medium_band": [...], "batch_internal_duplicates": [...],
     "open_issue_count": 15, "scan_truncated": false, "items_checked": 1,
     "issue_source": "gh", "weights": {...}, "thresholds": {...}}

`duplicates` holds only matches at or above the high threshold — those are
decided, and no model needs to re-read them. `medium_band` holds the matches
between the two thresholds, which is the only list a model should judge.

Exit codes
  0  scored — including the normal case of an empty backlog, which is a real
     answer (no duplicates) and not an error
  2  usage error
  3  invalid input — unparsable stdin, an item without a title, or an
     out-of-range `duplicate_detection.*` value (stderr: `✗ gi-dup-score: …`).
     Stop: the caller handed this script something it cannot score.
  4  cannot complete — `gh` is missing, unauthenticated, or failed (stderr:
     `⚠ gi-dup-score: …`). Degrade to the prose procedure. A failed fetch is
     never reported as an empty backlog: "no issues" and "could not look" are
     different answers, and conflating them turns every duplicate into a pass.

Authored at src/shared/scripts/gi-dup-score.py — do not edit installed copies;
edit the source and run ./scripts/build.sh.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys

DEFAULT_LIMIT = 100

# The scoring table from the duplicate-detector prompt, unchanged.
DEFAULT_WEIGHTS = {
    "title_overlap": 3,
    "keyword": 2,
    "same_type": 1,
    "phrase": 5,
}
DEFAULT_HIGH = 8
DEFAULT_MEDIUM = 5

# Shared significant words needed before the title-overlap weight applies.
TITLE_OVERLAP_MIN = 3
# Significant words in a run before it counts as a verbatim phrase match.
PHRASE_MIN = 3

STOP_WORDS = frozenset(
    """a an the to for in on of and or is it be as at by with from that this not
    but are was all has its can will should when if add fix update issue bug
    feature improvement create make get set""".split()
)

# Issue-type synonyms, so a repository labelling things `enhancement` still
# scores a shared type against a proposed `improvement`.
TYPE_ALIASES = {
    "bug": "bug",
    "defect": "bug",
    "fix": "bug",
    "feature": "feature",
    "enhancement": "improvement",
    "improvement": "improvement",
    "refactor": "improvement",
}

CONFIG_NAME = ".gitissue.yml"
CONFIG_SECTION = "duplicate_detection"
CONFIG_KEYS = ("high_threshold", "medium_threshold", "extra_stop_words")

_SECTION_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):\s*$")
_ENTRY_RE = re.compile(r"^\s+([a-z_][a-z0-9_]*):[ \t]+(.*?)\s*$")
_WORD_RE = re.compile(r"[a-z0-9]+")


class InvalidInput(Exception):
    """Caller-supplied input is unusable — exit 3."""


class Unavailable(Exception):
    """The backlog could not be read; the caller degrades — exit 4."""


# --- configuration -----------------------------------------------------------


def _parse_scalar(raw: str, key: str) -> object:
    """Parse the restricted scalar syntax the config schema documents."""
    if raw.startswith('"'):
        try:
            return json.loads(raw)
        except json.JSONDecodeError as exc:
            raise InvalidInput(
                f"{CONFIG_SECTION}.{key} — invalid quoted string ({exc.msg})"
            ) from exc
    if raw.startswith("'") and raw.endswith("'") and len(raw) >= 2:
        return raw[1:-1].replace("''", "'")
    if re.fullmatch(r"-?[0-9]+", raw):
        return int(raw)
    return raw


def read_config(path: str) -> dict[str, object]:
    """Read the `duplicate_detection:` block of a config file, or {}."""
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        # No config file is the zero-config case, not an error.
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


def find_config(explicit: str | None) -> str | None:
    """The explicit path, else `.gitissue.yml` found upward from the cwd.

    An explicit path that is not a file returns None rather than itself, so the
    caller reports it instead of reading nothing and running on the defaults —
    a config the user named and the script quietly ignored is the same silent
    substitution the reader below exists to avoid.
    """
    if explicit:
        return explicit if os.path.isfile(explicit) else None
    here = os.path.abspath(os.getcwd())
    while True:
        candidate = os.path.join(here, CONFIG_NAME)
        if os.path.isfile(candidate):
            return candidate
        parent = os.path.dirname(here)
        if parent == here:
            return None
        here = parent


def resolve_thresholds(args: argparse.Namespace) -> tuple[int, int, frozenset[str]]:
    """Merge the documented defaults with `duplicate_detection:` and the flags."""
    values: dict[str, object] = {}
    if not args.no_config:
        path = find_config(args.config)
        if path is None and args.config:
            raise InvalidInput(f"config file not found: {args.config}")
        if path is not None:
            values = read_config(path)

    high = args.high if args.high is not None else values.get("high_threshold", DEFAULT_HIGH)
    medium = (
        args.medium
        if args.medium is not None
        else values.get("medium_threshold", DEFAULT_MEDIUM)
    )
    for label, value in (("high_threshold", high), ("medium_threshold", medium)):
        if not isinstance(value, int) or isinstance(value, bool):
            raise InvalidInput(f"{CONFIG_SECTION}.{label} must be an integer, got {value!r}")
        if value < 1:
            raise InvalidInput(f"{CONFIG_SECTION}.{label} must be >= 1, got {value}")
    if medium > high:
        raise InvalidInput(
            f"{CONFIG_SECTION}.medium_threshold ({medium}) must not exceed "
            f"high_threshold ({high})"
        )

    extra_raw = values.get("extra_stop_words", "")
    if args.extra_stop_words is not None:
        extra_raw = args.extra_stop_words
    if not isinstance(extra_raw, str):
        raise InvalidInput(
            f"{CONFIG_SECTION}.extra_stop_words must be a comma-separated string"
        )
    extra = {word.strip().lower() for word in extra_raw.split(",") if word.strip()}
    return high, medium, frozenset(STOP_WORDS | extra)


# --- scoring -----------------------------------------------------------------


def words(text: str) -> list[str]:
    """Lowercased alphanumeric tokens, in order."""
    return _WORD_RE.findall(text.lower())


def significant(text: str, stop_words: frozenset[str]) -> list[str]:
    """Tokens that carry meaning: not a stop-word, at least two characters."""
    return [w for w in words(text) if len(w) > 1 and w not in stop_words]


def issue_type(labels: list[str]) -> str | None:
    """The first label that names a known issue type, normalized."""
    for label in labels:
        key = label.strip().lower()
        if key in TYPE_ALIASES:
            return TYPE_ALIASES[key]
    return None


def phrase_hit(item_tokens: list[str], target_tokens: list[str]) -> list[str] | None:
    """The longest run of >= PHRASE_MIN item tokens appearing verbatim in target.

    Compared on the significant-token stream rather than raw characters, so a
    difference in punctuation or casing does not hide a phrase that a reader
    would call identical.

    The title and the body are searched as *separate* streams by the caller, so
    a run can never straddle the join between them — a "phrase" that exists
    only because a title's last word abuts a body's first word is an artifact of
    the concatenation, not something a reader would call a phrase.
    """
    if len(item_tokens) < PHRASE_MIN or len(target_tokens) < PHRASE_MIN:
        return None
    # Longest first, then left to right, so the answer is the same run every
    # time regardless of how many shorter runs also match.
    for size in range(len(item_tokens), PHRASE_MIN - 1, -1):
        for start in range(0, len(item_tokens) - size + 1):
            run = item_tokens[start : start + size]
            for pos in range(0, len(target_tokens) - size + 1):
                if target_tokens[pos : pos + size] == run:
                    return run
    return None


def score_pair(
    item: dict,
    target_title: str,
    target_body: str,
    target_type: str | None,
    weights: dict[str, int],
    stop_words: frozenset[str],
) -> tuple[int, list[str], list[str]]:
    """Score one proposed item against one existing issue.

    Returns (score, shared_keywords, reasons).
    """
    item_title_tokens = significant(item["title"], stop_words)
    target_title_tokens = significant(target_title, stop_words)
    target_body_tokens = significant(target_body, stop_words)
    target_word_set = set(words(f"{target_title}\n{target_body}"))

    score = 0
    reasons: list[str] = []

    # `title_overlap` and `phrase` are scored over *disjoint regions* of the
    # target, because they are not independent signals over the same region: a
    # run of >= PHRASE_MIN item-title tokens inside the target **title**
    # necessarily also produces >= TITLE_OVERLAP_MIN shared title words, so one
    # observation would fire both rules and sum to exactly the high threshold.
    # That is how `"Login crash on mobile Safari"` used to auto-decide against
    # `"Login crash on mobile Chrome"` with no model consulted.
    #
    # So: a run found in the title *replaces* the title-overlap weight (the
    # stronger reading of the one observation, never the sum of two), while a
    # run found in the **body** is a genuinely separate sighting and is added on
    # top of whatever the title overlap earned. Only two distinct observations
    # can reach the high threshold from these two rules.
    title_run = phrase_hit(item_title_tokens, target_title_tokens)
    body_run = phrase_hit(item_title_tokens, target_body_tokens)
    phrase_run = body_run or title_run
    # The overlap is paid unless the *only* phrase evidence came from the title.
    overlap_is_independent = body_run is not None or title_run is None

    # The words an already-paid signal has counted, **per region**. Everything
    # below is scored against these: a later signal whose whole evidence in a
    # region is words that region has already been paid for is re-reading one
    # sighting, not making a second one. The two sets stay separate because the
    # regions are the whole point — the body is precisely what the title
    # signals cannot see, so a sighting there is never a re-reading of one.
    counted_title: set[str] = set()
    counted_body: set[str] = set()

    shared_title = sorted(set(item_title_tokens) & set(target_title_tokens))
    if len(shared_title) >= TITLE_OVERLAP_MIN and overlap_is_independent:
        score += weights["title_overlap"]
        reasons.append(f"title overlap: {len(shared_title)} shared words")
        counted_title |= set(shared_title)
    if phrase_run:
        (counted_body if body_run else counted_title).update(phrase_run)

    # The same rule as above, applied to the third signal. A keyword the model
    # lifted out of the item's own title, sighted in the target *title*, is
    # literally one of the shared words `title_overlap` has already been paid
    # for — `"Slow query on dashboard load"` vs `"Slow dashboard query on first
    # load"` reached 10 and auto-decided on one observation counted three times.
    #
    # A keyword pays when **some region sights it that has not already been paid
    # for those words**. That keeps the rule disjoint without turning it off:
    # a term the item's title never contained is new wherever it appears, and a
    # term sighted in the *body* is new when only the title was paid — the body
    # being unreadable to the title signals is the whole reason the regions are
    # split. Suppression needs *every* token of the keyword already counted in
    # every region that sights it, so a multi-word keyword adding one new term
    # keeps its weight.
    target_title_words = set(words(target_title))
    target_body_words = set(words(target_body))

    shared_keywords: list[str] = []
    echoed = 0
    for keyword in item.get("keywords") or []:
        tokens = [w for w in words(str(keyword)) if w]
        if not tokens:
            continue
        if not all(token in target_word_set for token in tokens):
            continue
        regions = []
        if all(token in target_title_words for token in tokens):
            regions.append(counted_title)
        if all(token in target_body_words for token in tokens):
            regions.append(counted_body)
        if not regions:
            # The keyword's tokens are split across the two regions, so the
            # sighting belongs to neither alone; it is new unless both regions
            # together have already been paid for all of them.
            regions.append(counted_title | counted_body)
        if not any(
            any(token not in counted for token in tokens) for counted in regions
        ):
            echoed += 1
            continue
        shared_keywords.append(str(keyword))
    if shared_keywords:
        score += weights["keyword"] * len(shared_keywords)
        reasons.append(f"{len(shared_keywords)} keyword match(es)")
    if echoed:
        reasons.append(f"{echoed} keyword(s) already counted by a title signal")

    if item.get("type") and target_type and item["type"] == target_type:
        score += weights["same_type"]
        reasons.append(f"same type ({target_type})")

    if phrase_run:
        score += weights["phrase"]
        where = "body" if body_run else "title"
        reasons.append(f'verbatim phrase "{" ".join(phrase_run)}" in the {where}')

    return score, shared_keywords, reasons


# --- issue source ------------------------------------------------------------


def fetch_issues(limit: int, repo: str | None) -> tuple[list[dict], bool]:
    """Fetch open issues with `gh`, plus whether the list was truncated.

    A failed fetch raises rather than returning an empty list. An empty backlog
    and an unreadable backlog produce the same JSON otherwise, and the caller
    would report "no duplicates found" over an outage.
    """
    payload = _gh_issue_list(limit, repo)
    truncated = len(payload) >= limit
    if truncated:
        # `gh` caps at the requested limit, so ask for one more to learn whether
        # anything was left behind rather than assuming it was.
        probe = _gh_issue_list(limit + 1, repo, fields="number")
        truncated = len(probe) > limit
    return payload, truncated


def _gh_issue_list(limit: int, repo: str | None, fields: str = "number,title,body,labels") -> list[dict]:
    args = ["issue", "list", "--state", "open", "--json", fields, "--limit", str(limit)]
    if repo:
        args += ["--repo", repo]
    try:
        proc = subprocess.run(["gh", *args], capture_output=True, text=True, check=False)
    except FileNotFoundError as exc:
        raise Unavailable("gh is not installed or not on PATH") from exc
    except OSError as exc:
        raise Unavailable(f"cannot run gh — {exc}") from exc
    if proc.returncode != 0:
        detail = proc.stderr.strip().splitlines()
        raise Unavailable(
            "gh issue list failed: "
            + (detail[-1] if detail else f"exit {proc.returncode}")
        )
    try:
        loaded = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise Unavailable(f"gh printed unparsable JSON — {exc}") from exc
    if not isinstance(loaded, list):
        raise Unavailable("gh issue list did not return a JSON array")
    return [entry for entry in loaded if isinstance(entry, dict)]


def load_issue_file(path: str) -> list[dict]:
    """Read the issue array from a file the caller named explicitly.

    This is an *alternative* source, never a fallback: a run that asked for
    `gh` and could not reach it exits 4 rather than quietly reading a file that
    may describe a different repository at a different time.
    """
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError as exc:
        raise Unavailable(f"cannot read {path} — {exc}") from exc
    try:
        loaded = json.loads(text)
    except json.JSONDecodeError as exc:
        raise InvalidInput(f"{path} is not valid JSON — {exc}") from exc
    if not isinstance(loaded, list):
        raise InvalidInput(f"{path} must hold a JSON array of issues")
    return [entry for entry in loaded if isinstance(entry, dict)]


def read_stdin_object() -> dict:
    """Read the request object from stdin, tolerating non-UTF-8 bytes.

    A cp1252 quote in an issue title must not raise UnicodeDecodeError out of
    main() as exit 1 — a code this script does not use and a caller cannot read.
    """
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


def normalize_items(request: dict) -> list[dict]:
    """Validate and normalize the proposed items."""
    items = request.get("items")
    if not isinstance(items, list) or not items:
        raise InvalidInput("request must carry a non-empty 'items' array")
    out: list[dict] = []
    for position, entry in enumerate(items, start=1):
        if not isinstance(entry, dict):
            raise InvalidInput(f"items[{position - 1}] is not an object")
        title = entry.get("title")
        if not isinstance(title, str) or not title.strip():
            raise InvalidInput(f"items[{position - 1}] has no usable 'title'")
        keywords = entry.get("keywords") or []
        if not isinstance(keywords, list):
            raise InvalidInput(f"items[{position - 1}].keywords must be an array")
        kind = entry.get("type")
        if kind is not None and not isinstance(kind, str):
            raise InvalidInput(f"items[{position - 1}].type must be a string")
        index = entry.get("index")
        if not isinstance(index, int) or isinstance(index, bool):
            index = position
        out.append(
            {
                "index": index,
                "title": title,
                "keywords": [str(k) for k in keywords],
                "type": TYPE_ALIASES.get((kind or "").strip().lower()),
            }
        )
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-dup-score.py",
        description=(
            "Score proposed issues against the open backlog. Reads the request "
            "as JSON on stdin and fetches the backlog itself; prints one JSON "
            "object on stdout."
        ),
        epilog=(
            "Example: python3 gi-dup-score.py < request.json    "
            "(never pass an issue title as an argument)"
        ),
    )
    parser.add_argument("--repo", metavar="OWNER/NAME")
    parser.add_argument(
        "--limit",
        type=int,
        default=DEFAULT_LIMIT,
        metavar="N",
        help=f"open issues to score against (default {DEFAULT_LIMIT})",
    )
    parser.add_argument(
        "--issues-from",
        metavar="FILE",
        help=(
            "score against a JSON array of issues in FILE instead of calling "
            "gh. An explicit alternative source, never a fallback"
        ),
    )
    parser.add_argument("--config", metavar="PATH", help=f"{CONFIG_NAME} to read")
    parser.add_argument("--no-config", action="store_true", help="ignore any config file")
    parser.add_argument("--high", type=int, metavar="N", help="high-band threshold override")
    parser.add_argument("--medium", type=int, metavar="N", help="medium-band threshold override")
    parser.add_argument(
        "--extra-stop-words",
        metavar="LIST",
        help="comma-separated words to ignore, on top of the built-in list",
    )
    args = parser.parse_args(argv)

    try:
        if args.limit < 1:
            raise InvalidInput("--limit must be >= 1")
        high, medium, stop_words = resolve_thresholds(args)
        request = read_stdin_object()
        items = normalize_items(request)
        mode = request.get("mode") if request.get("mode") in ("create", "batch") else "create"

        if args.issues_from:
            issues = load_issue_file(args.issues_from)
            truncated = len(issues) > args.limit
            issues = issues[: args.limit]
            source = "file"
        else:
            issues, truncated = fetch_issues(args.limit, args.repo)
            source = "gh"
    except InvalidInput as exc:
        sys.stderr.write(f"✗ gi-dup-score: {exc}\n")
        return 3
    except Unavailable as exc:
        sys.stderr.write(f"⚠ gi-dup-score: {exc}\n")
        return 4

    weights = dict(DEFAULT_WEIGHTS)
    high_matches: list[dict] = []
    medium_matches: list[dict] = []

    for item in items:
        for issue in issues:
            number = issue.get("number")
            if not isinstance(number, int):
                continue
            labels = [
                str(label.get("name", ""))
                for label in issue.get("labels") or []
                if isinstance(label, dict)
            ]
            score, shared, reasons = score_pair(
                item,
                str(issue.get("title") or ""),
                str(issue.get("body") or ""),
                issue_type(labels),
                weights,
                stop_words,
            )
            if score < medium:
                continue
            record = {
                "item_index": item["index"],
                "match_type": "existing_issue",
                "match_number": number,
                "match_title": str(issue.get("title") or ""),
                "confidence": "high" if score >= high else "medium",
                "score": score,
                "shared_keywords": shared,
                "reason": "; ".join(reasons) or "score threshold reached",
            }
            (high_matches if score >= high else medium_matches).append(record)

    internal: list[dict] = []
    if mode == "batch":
        for left in range(len(items)):
            for right in range(left + 1, len(items)):
                other = items[right]
                score, shared, reasons = score_pair(
                    items[left],
                    other["title"],
                    "",
                    other["type"],
                    weights,
                    stop_words,
                )
                if score < medium:
                    continue
                internal.append(
                    {
                        "item_index": items[left]["index"],
                        "match_type": "batch_internal",
                        "match_index": other["index"],
                        "match_title": other["title"],
                        "confidence": "high" if score >= high else "medium",
                        "score": score,
                        "shared_keywords": shared,
                        "reason": "; ".join(reasons) or "score threshold reached",
                    }
                )

    def order(record: dict) -> tuple:
        return (
            record["item_index"],
            -record["score"],
            record.get("match_number", record.get("match_index", 0)),
        )

    print(
        json.dumps(
            {
                "duplicates": sorted(high_matches, key=order),
                "medium_band": sorted(medium_matches, key=order),
                "batch_internal_duplicates": sorted(internal, key=order),
                "open_issue_count": len(issues),
                "scan_truncated": truncated,
                "items_checked": len(items),
                "issue_source": source,
                "mode": mode,
                "weights": weights,
                "thresholds": {"high": high, "medium": medium},
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
