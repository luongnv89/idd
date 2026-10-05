# Modernization plan — acme-cli

**Baseline:** GREEN — builds; 12/12 tests pass
**Test command:** `npm test`

## Phase P0 — Stabilize

**Goal:** reproducible build · **Milestone M0:** build green in CI

### Sprint 0 — Baseline

#### Task 0.1: Commit the lockfile

**Description**: No lockfile is committed, so installs drift between machines.
**Closes**: F-DEP-001
**Dependencies**: None
**Effort**: S
**Acceptance Criteria**:
- [ ] `package-lock.json` is committed at the repo root
- [ ] `npm ci` succeeds from a clean checkout

#### Task 0.2: Document issue #999 — 9.9 phantom reference

**Description**: The plan title cites another issue; that citation is text, not a child.
**Closes**: F-DOCS-001
**Dependencies**: 0.1
**Effort**: XS
**Acceptance Criteria**:
- [ ] The README explains the reference

## Phase P1 — Harden

**Goal:** automated checks on every push · **Milestone M1:** CI gates every pull request

### Sprint 1 — Automation

#### Task 1.1: Add the CI workflow

**Description**: Nothing runs the tests on push.
**Closes**: F-CI-001
**Dependencies**: 0.1
**Effort**: S
**Acceptance Criteria**:
- [ ] A workflow runs `npm test` on every pull request

#### Task 1.2: Pin the Node runtime

**Description**: The runtime version is implicit.
**Closes**: F-DEP-002
**Dependencies**: 1.1
**Effort**: XS
**Acceptance Criteria**:
- [ ] `.nvmrc` pins the Node major version

**Critical path:** 0.1 → 1.1 → 1.2
