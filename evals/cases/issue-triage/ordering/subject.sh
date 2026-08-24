#!/usr/bin/env bash
# issue-triage stand-in: fetch the open backlog and the merged PRs under the
# PATH-shimmed gh, then compute the execution order exactly as
# references/detection.md (Steps 3-7) specifies — direct the dependency edges
# from `Depends on #N` body markers, topologically level the graph, sort each
# level by type then age then number, push maybe-fixed issues to the bottom,
# bucket P1/P2/P3, and flag staleness.
#
# Every rank is emitted as its own artifact named `rank-<r>-issue-<n>.txt`, so
# case.json can assert the ordering with `file-exists` alone: a subject that
# ranks differently simply does not create the file the case expects.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"
: "${EVAL_CASSETTES:?EVAL_CASSETTES is required}"

# Preflight the real skill runs before any tracker read.
gh auth status >/dev/null

gh issue list --state open --limit 100 \
  --json number,title,body,labels,assignees,state,createdAt,updatedAt \
  > "$EVAL_OUT/issue-list.json"

gh pr list --state merged --limit 20 --json number,title,body,state \
  > "$EVAL_OUT/pr-list.json"

# Fixture clock. The subject runs with `env -i`, so the reference instant is a
# constant here rather than an inherited variable; staleness and the "bug older
# than 2x the threshold" P1 rule both read it.
NOW="2026-08-24T12:00:00Z"
STALE_DAYS=14

EVAL_OUT="$EVAL_OUT" NOW="$NOW" STALE_DAYS="$STALE_DAYS" python3 - <<'PY'
import json
import os
import re
from datetime import datetime, timezone

out = os.environ["EVAL_OUT"]
now = datetime.strptime(os.environ["NOW"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
stale_days = int(os.environ["STALE_DAYS"])

# Type precedence inside one topological level: bugs first (detection.md Step 4).
TYPE_RANK = {"bug": 0, "feature": 1, "improvement": 2}
ESCALATING = {"critical", "urgent"}
DEP_MARKER = re.compile(r"(?im)\b(?:depends\s+on|blocked\s+by)\b")
CROSS_REPO = re.compile(r"\S+/\S+#\d+")
LOCAL_REF = re.compile(r"(?<![\w/])#(\d+)")


def ts(value):
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def dep_numbers(body):
    """Local issue numbers a `Depends on` / `Blocked by` line names.

    Cross-repo tokens (`owner/repo#15`) are stripped before local refs are
    captured, matching the gate grammar in docs/idd-methodology.md.
    """
    found = []
    for line in body.splitlines():
        if not DEP_MARKER.search(line):
            continue
        for ref in LOCAL_REF.findall(CROSS_REPO.sub("", line)):
            number = int(ref)
            if number not in found:
                found.append(number)
    return found


with open(os.path.join(out, "issue-list.json"), encoding="utf-8") as fh:
    raw_issues = json.load(fh)
with open(os.path.join(out, "pr-list.json"), encoding="utf-8") as fh:
    raw_prs = json.load(fh)

# A merged PR that closes an open issue is the "already fixed" signal.
fixed_by = {}
for pr in raw_prs:
    for ref in re.findall(r"(?im)\bcloses\s+#(\d+)", pr.get("body") or ""):
        fixed_by.setdefault(int(ref), f"PR #{pr['number']}")

issues = {}
for entry in raw_issues:
    number = entry["number"]
    labels = [label["name"] for label in entry.get("labels") or []]
    kind = next((label for label in labels if label in TYPE_RANK), None)
    issues[number] = {
        "number": number,
        "title": entry["title"],
        "type": kind,
        "labels": labels,
        "created": ts(entry["createdAt"]),
        "updated": ts(entry["updatedAt"]),
        "potentially_fixed_by": fixed_by.get(number),
    }

# Directed edges: blocker -> blocked. A marker naming an unknown issue is
# dropped rather than blocking the whole order.
edges = set()
for number, issue in issues.items():
    body = next(e["body"] for e in raw_issues if e["number"] == number)
    for blocker in dep_numbers(body):
        if blocker in issues and blocker != number:
            edges.add((blocker, number))

blocks = {n: [] for n in issues}
blocked_by = {n: [] for n in issues}
for src, dst in sorted(edges):
    blocks[src].append(dst)
    blocked_by[dst].append(src)


def sort_key(number):
    issue = issues[number]
    return (TYPE_RANK.get(issue["type"] or "", 99), issue["created"].timestamp(), number)


# Kahn levels; each level sorted by type, then age, then issue number.
remaining = set(issues)
incoming = {n: set() for n in issues}
for src, dst in edges:
    incoming[dst].add(src)
levels = []
while remaining:
    ready = sorted((n for n in remaining if not (incoming[n] & remaining)), key=sort_key)
    if not ready:  # defensive: the fixture graph is acyclic
        ready = sorted(remaining, key=sort_key)
    levels.append(ready)
    remaining -= set(ready)

order = [n for level in levels for n in level]
maybe_fixed = [n for n in order if issues[n]["potentially_fixed_by"]]
order = [n for n in order if n not in maybe_fixed] + maybe_fixed


def priority(number):
    issue = issues[number]
    if {label.lower() for label in issue["labels"]} & ESCALATING:
        return "P1"
    if issue["type"] == "bug":
        if blocks[number]:
            return "P1"
        if (now - issue["created"]).days > stale_days * 2:
            return "P1"
        return "P2"
    if issue["type"] == "feature" and blocks[number]:
        return "P2"
    if issue["type"] == "improvement" and len(blocks[number]) >= 2:
        return "P2"
    return "P3"


records = []
stale_count = 0
for number in order:
    issue = issues[number]
    age = (now - issue["updated"]).days
    is_stale = age > stale_days
    stale_count += 1 if is_stale else 0
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
            "priority": priority(number),
            "blocks": blocks[number],
            "blocked_by": blocked_by[number],
            "status": status,
            "stale_days": age if is_stale else None,
            "potentially_fixed_by": issue["potentially_fixed_by"],
        }
    )

payload = {
    "version": 1,
    "updated": os.environ["NOW"],
    "source": "/issue-triage",
    "analyzed_count": len(records),
    "issues": records,
    "summary": {
        "stale_count": stale_count,
        "stale_threshold_days": stale_days,
        "potentially_fixed_count": len(maybe_fixed),
        "suggested_order": order,
    },
}
with open(os.path.join(out, "triage.json"), "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2)
    fh.write("\n")

# One artifact per rank — case.json asserts the ordering by file name.
for rank, number in enumerate(order, start=1):
    record = next(r for r in records if r["number"] == number)
    with open(os.path.join(out, f"rank-{rank}-issue-{number}.txt"), "w", encoding="utf-8") as fh:
        fh.write(f"{record['priority']} {record['status']} {record['title']}\n")

with open(os.path.join(out, "suggested-order.txt"), "w", encoding="utf-8") as fh:
    fh.write(" ".join(str(n) for n in order) + "\n")

# What /auto-pilot would pick next: the first entry of the order that is not
# blocked and not maybe-fixed. The artifact name carries both the issue and its
# priority bucket, so case.json pins the pick and the bucket together.
pick = next(r for r in records if r["status"] not in ("blocked", "maybe-fixed"))
with open(os.path.join(out, f"pick-{pick['number']}-{pick['priority']}.txt"), "w", encoding="utf-8") as fh:
    fh.write(f"{pick['number']} {pick['priority']} {pick['title']}\n")

print("  ○ suggested order: " + " → ".join(f"#{n}" for n in order))
print(f"  ○ pick: #{pick['number']} ({pick['priority']})")
PY

# The picked issue's body, rendered in normalized form: what triage hands to
# /issue-resolver must be spec-conformant, so idd-lint grades it. The pick
# itself is graded separately, by the pick-<n>-<priority> artifact above.
cat > "$EVAL_OUT/issue-top.md" <<'EOF'
<!-- gitissue:normalized v1 -->

## Type

Bug

## Description

**Current behavior:**
The auth token refresh spins forever once the token expires.

**Expected behavior:**
Refresh exchanges the expired token once and resumes the session.

> **Reporter Context**
> Fix auth token refresh loop

## Acceptance Criteria

- [ ] Refresh completes once for an expired token
- [ ] A refresh failure surfaces an error instead of looping

## Metadata

**Priority:** P1
**Effort:** M
**Labels:** bug, auth
EOF

# Negative control: the raw body as filed, before /issue-creator normalizes it.
# Triage must not report an un-normalized body as spec-conformant.
cat > "$EVAL_OUT/issue-unstructured.md" <<'EOF'
Refresh spins forever once the token expires.
EOF

echo "  ○ triage artifacts written to $EVAL_OUT"
