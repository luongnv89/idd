#!/usr/bin/env bash
# Deterministic issue-creator stand-in: build a lint-clean bug body and
# create it via PATH-shimmed gh. Does not call real GitHub.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"
: "${EVAL_CASSETTES:?EVAL_CASSETTES is required}"

TITLE="Bug: Fix mobile login redirect loop"
BODY_FILE="$EVAL_OUT/issue.md"

cat > "$BODY_FILE" <<'EOF'
<!-- gitissue:normalized v1 -->

## Type

Bug

## Description

**Current behavior:**
Mobile users hit a redirect loop after login.

**Expected behavior:**
Login completes and lands on the home screen.

> **Reporter Context**
> Create a bug issue for mobile login redirect loop

## Acceptance Criteria

- [ ] Mobile login completes without a redirect loop
- [ ] Desktop login continues to work

## Metadata

**Priority:** P1
**Effort:** S
**Labels:** bug, auth
EOF

# Optional preflight the real skill would run
gh auth status >/dev/null

URL="$(gh issue create --title "$TITLE" --body-file "$BODY_FILE")"
printf '%s\n' "$URL" > "$EVAL_OUT/issue-url.txt"
# The cassette read is uncached; compare the entire body before claiming success.
gh issue view 1 --json number,title,body,state > "$EVAL_OUT/verification.json"
python3 - "$EVAL_OUT" <<'PYREPORT'
import json
import sys
from pathlib import Path
out = Path(sys.argv[1])
verified = json.loads((out / "verification.json").read_text())
assert verified["number"] == 1
assert verified["title"] == "Bug: Fix mobile login redirect loop"
assert verified["body"] == (out / "issue.md").read_text()
url = (out / "issue-url.txt").read_text().strip()
report = (
    "DONE: Created issue #1 — Bug: Fix mobile login redirect loop\n"
    "Evidence: uncached issue view confirmed number, title, and complete body; "
    "saved in verification.json.\n"
    f"{url}\n"
    "Uncertainty: classification inferred from reporter text; bug reproduction "
    "untested; duplicate scan not performed by this stand-in.\n"
    "No approval needed. Remaining action: review the issue before implementation.\n"
)
(out / "report.txt").write_text(report)
print(report, end="")
PYREPORT

# Branch name artifact (creator may suggest one; used by grade)
printf '%s\n' "fix/1-mobile-login-redirect" > "$EVAL_OUT/branch.txt"
