#!/usr/bin/env bash
# Negative trigger: empty/unstructured body — idd-lint must fail.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"

# Deliberately non-conforming: no normalization marker, no sections, no AC.
printf '%s\n' "login broken pls fix" > "$EVAL_OUT/issue.md"

gh auth status >/dev/null || true
# Still "create" so the subject exercises gh under the shim.
gh issue create --title "login broken" --body-file "$EVAL_OUT/issue.md" \
  > "$EVAL_OUT/issue-url.txt" || true
