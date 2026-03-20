# Sample Normalized Issue

This shows how a gitissue-normalized bug report renders in GitHub's web UI.

---

<!-- gitissue:normalized v1 -->

## Type

Bug

## Context

**Affected files:**
- `src/auth/middleware.py` (high confidence)
- `src/auth/redirect.py` (high confidence)
- `src/config/auth_settings.py` (medium confidence)

**Current behavior:**
Mobile users hitting `/login?sso=true` enter an infinite redirect loop between the SSO provider and the app callback endpoint. The browser shows "too many redirects" after ~30 cycles.

**Expected behavior:**
SSO login completes in a single redirect cycle and lands on the dashboard.

**Related issues:**
- #38 — SSO integration (original implementation)

## Description

The SSO callback handler in `middleware.py` doesn't check whether the current request is already authenticated before initiating a new SSO flow. On mobile browsers, the session cookie isn't set correctly due to SameSite restrictions, causing each callback to look like a fresh unauthenticated request.

> **Reporter Context**
> the login is broken on mobile. it just keeps spinning and then says too many redirects. works fine on desktop. started happening after last week's deploy.

## Acceptance Criteria

- [ ] Mobile SSO login completes without redirect loops
- [ ] Session cookie sets `SameSite=None; Secure` for cross-origin SSO flows
- [ ] Existing desktop SSO flow continues to work unchanged
- [ ] Redirect loop detection added (max 3 redirects before error page)

## Technical Notes

**Architecture constraints:**
The auth middleware is shared across all route handlers. Changes must not break the standard username/password flow or API token authentication.

**Test coverage:**
`tests/auth/test_sso.py` covers desktop SSO flow but has no mobile user-agent tests. Add mobile-specific test cases.

**Breaking change risk:** Low — cookie attribute change is additive.

## Metadata

**Priority:** P1
**Effort:** S
**Labels:** bug, auth, mobile
