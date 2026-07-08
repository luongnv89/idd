# IDD Specification

**Issue-Driven Development (IDD)** — a tool-neutral contract for turning an issue tracker and git history into executable project memory.

- **Spec version:** 1.0
- **Marker version:** `v1`
- **Status:** Stable

The key words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

This document defines the *contract* only. It requires no specific AI agent, editor, CLI, or hosting platform. Any tool — or a human with a text editor — can implement it. [gitissue](README.md) is a reference implementation of this spec for Claude Code + GitHub.

## Terminology

| Term | Meaning |
|------|---------|
| **Tracker** | Any issue system with markdown bodies and `#N` cross-references (GitHub, GitLab, Gitea, …) |
| **Issue** | A tracker work item capturing intent |
| **Resolver** | Whoever implements the change — human or agent |
| **Normalization** | Restructuring an existing issue body to conform to §1 |
| **Default branch** | The branch a merged change lands on (`main`, `master`, …) |

---

## 1. Issue Contract

### 1.1 Structure

A conforming issue body consists of, in order:

1. **Normalization marker** — first line: `<!-- gitissue:normalized v1 -->`. Invisible when rendered, detectable by tools. The marker string is retained verbatim from the reference implementation for compatibility with deployed issues; the trailing `v1` tracks this spec's major version.
2. **`## Type`** — one of `Bug`, `Feature`, `Improvement`. Implementations MAY define additional types.
3. **`## Description`** — the intent, with type-specific fields:
   - `Bug` MUST include `**Current behavior:**` and `**Expected behavior:**`
   - `Improvement` MUST include `**Current state:**` and `**Proposed change:**`
   - `Feature` has no required sub-fields
   - Any type MAY include `**Related issues:**` and `**Related components:**`
4. **Reporter Context** — inside the Description, a blockquote beginning `> **Reporter Context**` preserving the reporter's original text **verbatim**. Required when normalizing an existing issue. When an issue is authored in structured form from the start, the author's raw input SHOULD still be preserved here.
5. **`## Screenshots`** — optional; omit when empty.
6. **`## Acceptance Criteria`** — one or more markdown checkboxes (`- [ ] …`). Each criterion MUST be a testable condition, not an implementation step.
7. **`## Metadata`** — bold-label lines: `**Priority:**`, `**Effort:**`, `**Labels:**`. Value scales (e.g. `P0–P3`, `XS–XL`) are project-defined. Implementations MAY add advisory fields; consumers MUST ignore fields they do not recognize.

### 1.2 The intent–code boundary

An issue owns **intent**: problem, expected outcome, acceptance criteria, priority. It MUST NOT contain generated or guessed code-level claims — predicted affected files, inferred root cause, or assumed architecture constraints. Code changes; frozen guesses go stale and mislead the next resolver.

File paths or constraints **explicitly stated by the reporter** MAY appear (they are reporter testimony, not tool inference). All code-level analysis belongs in resolution-time artifacts (§4), produced by scanning the codebase **as it exists when work begins**.

### 1.3 Confidence vocabulary

Inferred fields (Type, individual acceptance criteria, Metadata values) MAY carry a trailing confidence marker:

| Marker | Meaning |
|--------|---------|
| `(high confidence)` | Explicit signal in the source text |
| `(medium confidence)` | Inferred from context or tone |
| `(needs review)` | Ambiguous; defaulted — a human should verify |

An unmarked field is asserted by its human author. Tools that infer a value MUST mark it.

### 1.4 Data safety

Normalization mutates a human's words. Before rewriting an existing issue body, an implementation MUST preserve the prior body (e.g. as an issue comment) and MUST carry the original text into the Reporter Context blockquote. Issues labeled as security-sensitive MUST NOT be rewritten without explicit operator confirmation.

## 2. Dependency Markers

A merge-order dependency between issues is recorded in plain prose in the issue body:

```
Depends on #N
Blocked by #N
```

- The two forms are synonymous. Matching is case-insensitive.
- Multiple references on one line are allowed: `Depends on #12, #15`.
- The marker may appear in any list or sentence shape (`- Depends on #12`, `Depends on: #12`, `This depends on #12`), anywhere in the body — typically under `## Metadata` or a `## Dependencies` section.
- Cross-repo references (`org/repo#N`) are out of scope for v1 and MUST be ignored.

Semantics: the referenced issue (or its PR) must be merged before the dependent issue's PR is merged. Tools that automate merging MUST check these markers and pause rather than merge a PR whose dependencies are open.

## 3. Naming Conventions

### 3.1 Branches

**Grammar:** `<type>/<issue-number>-<short-description>`

Lowercase; words separated by hyphens; total length SHOULD stay under 50 characters. The issue number is REQUIRED (exception: `release/` and `hotfix/` branches, which are workflow-driven). The short description derives from the issue title: lowercase, spaces → hyphens, non-alphanumerics removed, truncated.

| Issue type | Prefix | Example |
|------------|--------|---------|
| bug | `fix/` | `fix/42-mobile-auth-redirect` |
| feature | `feat/` | `feat/15-dark-mode-toggle` |
| improvement | `refactor/` | `refactor/8-cleanup-auth-module` |
| documentation | `docs/` | `docs/23-update-api-reference` |
| test | `test/` | `test/31-add-auth-unit-tests` |
| maintenance | `chore/` | `chore/50-update-dependencies` |

### 3.2 Commits

**Grammar:** `<type>(<scope>): <description> (#<issue-number>)` — [Conventional Commits](https://www.conventionalcommits.org/) plus a REQUIRED trailing issue reference.

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `style`, `perf`. Scope is optional but recommended (module, not filename). Description in imperative mood, lowercase, no trailing period; first line under 72 characters. One logical change per commit.

### 3.3 Pull request titles

Same grammar as commits: `<type>(<scope>): <description> (#<issue-number>)`. Use the dominant type when a PR spans several. `Closes #N` goes on the **first line of the PR body**, never in the title.

### 3.4 Issue titles

Imperative mood ("Fix login crash on mobile", not "Login is crashing"); concise and actionable; under 70 characters; optional `Bug:`/`Feature:` prefix.

## 4. Decision Record

The Decision Record is the durable analysis payload: the reasoning that would otherwise die in a chat log or a local cache file.

### 4.1 Fields

A `## Decision Record` section is a bold-label bullet list. Field labels are string-matched by conformance checkers and MUST NOT be renamed:

| Field | Content | Required |
|-------|---------|----------|
| **Root cause** | One-paragraph diagnosis against the code as analyzed | Always |
| **Options considered** | The implementation options that were on the table | Always |
| **Options rejected** | Which were rejected, each with a one-line reason | Always |
| **Selected option** | The chosen approach | Always |
| **Residual risk** | What remains uncertain or accepted, or `none identified` | Always |
| **Reproduction** | The command confirmed failing for the stated reason before the fix, and the regression test proving the red → green transition | Bug issues only |

A trailing line SHOULD record what the analysis ran against: `` Analyzed at: `<branch> @ <short-sha>` (<date>) ``. Implementations MAY add fields; consumers MUST ignore fields they do not recognize.

### 4.2 The dual-write rule

Any analysis signal worth preserving MUST be written to **both**:

1. the **PR body** — where reviewers see it, and
2. a **git-history artifact** on the default branch — so `git log` answers "why does this code exist?" with the tracker offline.

Intermediate analysis files (e.g. a local `analysis-N.json` cache) are disposable and MUST NOT be the sole home of the reasoning.

### 4.3 Durable-memory bindings

The git-history half of the dual write is satisfied by exactly one **declared binding**:

| Binding | Mechanism | Notes |
|---------|-----------|-------|
| **B1 — Squash-merge body** | The platform copies the PR body verbatim into the squash commit that lands on the default branch | Zero extra tooling; requires squash-merge as the repo's merge strategy |
| **B2 — Merge-commit body** | The Decision Record is appended to the merge commit message (body or trailer block) at merge time | Works with true merge commits; needs merge automation or discipline |
| **B3 — Git notes** | The Decision Record is attached to the landing commit under a documented notes ref (e.g. `refs/notes/idd`) | Merge-strategy-independent; notes must be explicitly pushed/fetched |

A repo claiming L3 conformance (§6) MUST declare which binding it uses. Tooling SHOULD warn when the repo's merge strategy silently defeats the declared binding (e.g. B1 declared, merge-commit strategy configured).

## 5. Traceability

### 5.1 The chain

Every change MUST leave an unbroken reference chain:

```
Issue #N → branch <type>/N-… → commits …(#N) → PR title …(#N) + body "Closes #N" → merge → issue closes
```

Concretely: the branch name carries the issue number (§3.1); every commit references it (§3.2); the PR title references it and the PR body's first line is `Closes #N` (§3.3), so the tracker links and auto-closes the issue on merge. From any point — a `git blame` line, a commit, a PR, an issue — the rest of the chain is reachable.

### 5.2 Acceptance criteria verification

The PR body MUST verify the issue's acceptance criteria in a table:

```markdown
## Acceptance Criteria Verification

| Criterion | Status | Evidence |
|-----------|--------|----------|
| <criterion text from the issue> | pass | <file/line, test name, or manual check> |
```

Status is `pass`, `fail`, or `unverified`; every row MUST cite evidence. For bug issues the evidence for the fixed symptom MUST cite the reproduction (§4.1), not just a checkmark. If the issue defines no criteria, the table is replaced by an explicit note recommending manual review.

## 6. Conformance Levels

Conformance is claimed per level, e.g. *"IDD L2 (spec v1.0)"*. Each level includes all lower levels. L1 is deliberately adoptable by a human-only team with zero tooling installed.

| Level | Name | Requires |
|-------|------|----------|
| **L1** | Structured Issues | §1 issue contract + §2 dependency markers |
| **L2** | Traceable Delivery | L1 + §3 naming conventions + §5 traceability chain and AC verification |
| **L3** | Durable Memory | L2 + §4 Decision Records dual-written via one declared binding |

## Versioning

This spec follows semantic versioning. Additive, backward-compatible clarifications bump the minor version; any change that invalidates a previously conforming artifact bumps the major version and the normalization marker (`v1` → `v2`). Issues normalized under an older major version remain valid instances of that version.

---

*Non-normative: the rationale behind this contract — the intent–code boundary, executable project memory, and the compounding value of structured history — is elaborated in [docs/idd-methodology.md](docs/idd-methodology.md). A rendered example of a conforming issue is at [docs/sample-normalized-issue.md](docs/sample-normalized-issue.md). A dependency-free conformance checker for §1–§5 ships as [scripts/idd-lint.py](scripts/idd-lint.py) — it validates issue bodies, PR bodies, commit messages, and branch names from plain data, mapped to the levels above.*
