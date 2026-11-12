#!/usr/bin/env bash
# Deterministic issue-creator stand-in (issue #557): the reporter states three
# boundaries, and the body carries each one in `## Constraints` (after the
# Acceptance Criteria), labelled and confidence-marked. Nothing is added that
# the reporter did not say. Does not call real GitHub.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"
: "${EVAL_CASSETTES:?EVAL_CASSETTES is required}"

TITLE="Feature: Add CSV export to the reports page"
BODY_FILE="$EVAL_OUT/issue.md"

cat > "$BODY_FILE" <<'EOF'
<!-- idd:normalized v1 -->

## Type

feature (high confidence)

## Description

Users can download the reports table as a CSV file.

> **Reporter Context**
> Add CSV export to the reports page. Don't change the existing JSON API. An export of 10,000 rows must finish in under 5 seconds. PDF export is out of scope.

## Acceptance Criteria

- [ ] The reports page offers a CSV download of the visible table (high confidence)
- [ ] The CSV holds one header row and one row per report (medium confidence)

## Constraints

- **Invariant:** The existing JSON API does not change (high confidence)
- **Limit:** An export of 10,000 rows finishes in under 5 seconds (high confidence)
- **Non-goal:** PDF export (high confidence)

## Metadata

**Priority:** P2 (medium confidence)
**Effort:** S (medium confidence)
**Labels:** feature, reports (medium confidence)
EOF

gh auth status >/dev/null

URL="$(gh issue create --title "$TITLE" --body-file "$BODY_FILE")"
printf '%s\n' "$URL" > "$EVAL_OUT/issue-url.txt"
gh issue view 1 --json number,title,body,state > "$EVAL_OUT/verification.json"
python3 - "$EVAL_OUT" <<'PYREPORT'
import json
import re
import sys
from pathlib import Path
out = Path(sys.argv[1])
body = (out / "issue.md").read_text()
verified = json.loads((out / "verification.json").read_text())
assert verified["body"] == body
reporter = " ".join(l[2:] for l in body.splitlines() if l.startswith("> ")).lower()
section = body.split("## Constraints", 1)[1].split("\n## ", 1)[0]
items = [l for l in section.splitlines() if l.startswith("- ")]
assert len(items) == 3, items
item_re = re.compile(r"^- \*\*(Non-goal|Invariant|Limit):\*\* (.+?) \((high|medium) confidence\)$")
for item in items:
    m = item_re.match(item)
    assert m, f"unlabelled or unmarked constraint: {item}"
    # Reporter testimony only: the item's key words come from the reporter's text.
    words = [w for w in re.findall(r"[a-z0-9,]+", m.group(2).lower()) if len(w) > 3]
    missing = [w for w in words if w not in reporter and w not in {"does", "finishes", "change"}]
    assert not missing, f"constraint not from the reporter: {item} ({missing})"
(out / "report.txt").write_text(
    "DONE: Created issue #1 — Feature: Add CSV export to the reports page\n"
    "Evidence: uncached issue view matches the body; 3 constraints, each from the "
    "reporter's text with a confidence marker.\n"
)
PYREPORT
