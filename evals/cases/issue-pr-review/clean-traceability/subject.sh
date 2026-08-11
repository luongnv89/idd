#!/usr/bin/env bash
# Positive pr-review: conforming PR body with Closes + Decision Record.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"

gh auth status >/dev/null
gh pr view 8 --json number,title,body,state > "$EVAL_OUT/pr-view.json"

cat > "$EVAL_OUT/pr-body.md" <<'EOF'
Closes #42

## Summary

Fix the mobile redirect loop.

## Decision Record

- **Root cause:** session cookie rejected on cross-origin SSO redirects.
- **Options considered:** Option 1 — proxy; Option 2 — SameSite=None
- **Options rejected:** Option 1 — heavier infra change
- **Selected option:** Option 2 — SameSite=None
- **Residual risk:** none identified
- **Reproduction:** `npm test` confirmed red → regression test `tests/redirect.spec.ts`

Analyzed at: `fix/42-mobile-auth @ abc1234` (2026-07-08)

## Acceptance Criteria Verification

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Mobile login completes | pass | tests/redirect.spec.ts |
| Desktop login unchanged | unverified | manual review needed |
EOF

printf '%s\n' "fix/42-mobile-auth-redirect" > "$EVAL_OUT/branch.txt"
