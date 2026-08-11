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
echo "  ○ created issue → $URL"

# Branch name artifact (creator may suggest one; used by grade)
printf '%s\n' "fix/1-mobile-login-redirect" > "$EVAL_OUT/branch.txt"
