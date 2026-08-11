#!/usr/bin/env bash
# Negative pr-review: artifact PR body without Closes #N.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"

# Fetch under shim (exercises cassette) then write non-conforming body.
gh auth status >/dev/null
BODY="$(gh pr view 7 --json number,title,body,state)"
printf '%s\n' "$BODY" > "$EVAL_OUT/pr-view.json"

cat > "$EVAL_OUT/pr-body.md" <<'EOF'
This PR fixes things.

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
