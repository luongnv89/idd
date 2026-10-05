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

#### Task 0.2: Add the CI workflow

**Description**: Nothing runs the tests on push.
**Closes**: F-CI-001
**Dependencies**: 0.1
**Effort**: S
**Acceptance Criteria**:
- [ ] A workflow runs `npm test` on every pull request

## Phase P1 — Harden

**Goal:** a pinned toolchain · **Milestone M1:** the runtime version is explicit

### Sprint 1 — Toolchain

#### Task 1.1: Pin the Node runtime

**Description**: The runtime version is implicit.
**Closes**: F-DEP-002
**Dependencies**: 0.2
**Effort**: XS
**Acceptance Criteria**:
- [ ] `.nvmrc` pins the Node major version

**Critical path:** 0.1 → 0.2 → 1.1
