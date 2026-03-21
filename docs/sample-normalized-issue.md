# Sample Normalized Issue

This shows how a gitissue-normalized bug report renders in GitHub's web UI.

---

<!-- gitissue:normalized v1 -->

## Type

Bug

## Description

**Current behavior:**
Mobile users hitting `/login?sso=true` enter an infinite redirect loop between the SSO provider and the app callback endpoint. The browser shows "too many redirects" after ~30 cycles.

**Expected behavior:**
SSO login completes in a single redirect cycle and lands on the dashboard.

**Related issues:**
- #38 — SSO integration (original implementation)

> **Reporter Context**
> the login is broken on mobile. it just keeps spinning and then says too many redirects. works fine on desktop. started happening after last week's deploy.

## Acceptance Criteria

- [ ] Mobile SSO login completes without redirect loops
- [ ] Session cookie sets `SameSite=None; Secure` for cross-origin SSO flows
- [ ] Existing desktop SSO flow continues to work unchanged
- [ ] Redirect loop detection added (max 3 redirects before error page)

## Metadata

**Priority:** P1
**Effort:** S
**Labels:** bug, auth, mobile
