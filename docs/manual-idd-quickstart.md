# Manual IDD Quickstart — no AI required

Issue-Driven Development is a methodology, not a tool. This page gets a team to **L1 conformance** ([SPEC.md](https://github.com/luongnv89/idd/blob/main/SPEC.md) §6) with nothing installed — no gitissue skills, no AI agent, no build. A text editor and your existing tracker are enough. L2 and L3 are each one habit away.

## 1. Structure your issues (L1)

Paste this skeleton into a new issue and fill it in. It is the spec's issue contract (§1) in its bug form:

```markdown
<!-- gitissue:normalized v1 -->

## Type

Bug

## Description

**Current behavior:**
What happens today.

**Expected behavior:**
What should happen instead.

> **Reporter Context**
> The reporter's original words, verbatim — even if messy.

## Acceptance Criteria

- [ ] A testable condition for "done"
- [ ] Another one

## Metadata

**Priority:** P2
**Effort:** M
**Labels:** bug
```

For a **Feature**, drop the Current/Expected pair (free-form description). For an **Improvement**, use `**Current state:**` / `**Proposed change:**` instead. Two rules carry most of the value:

- **Intent only.** Never write guessed file lists, root causes, or architecture notes into the issue — they go stale after one merge and mislead the next resolver. (Paths the *reporter* explicitly stated are fine — that's testimony, not inference.)
- **Preserve the reporter's words.** Rewrite for structure, but keep the original text in the Reporter Context blockquote.

Relationships are plain prose, greppable by anything:

```
Depends on #12        ← merge order: #12 must merge before this
Part of #7            ← scope: this issue is a child of epic #7
```

**That's L1.** Your issues are now structured work orders any human — or any future agent — can execute against.

## 2. Link every artifact (L2)

Follow the naming grammar (spec §3) so the chain issue → branch → commit → PR never breaks:

| Artifact | Format | Example |
|----------|--------|---------|
| Branch | `<type>/<issue>-<short-desc>` | `fix/42-mobile-auth-redirect` |
| Commit | `<type>(<scope>): <desc> (#N)` | `fix(auth): resolve redirect loop (#42)` |
| PR title | same as commit | `fix(auth): resolve redirect loop (#42)` |
| PR body | first line | `Closes #42` |

Types: `fix` `feat` `refactor` `docs` `test` `chore`. Descriptions imperative, lowercase, no trailing period. End the PR body with a table verifying each acceptance criterion (`pass` / `fail` / `unverified`, with evidence).

**That's L2.** From any line of code, `git blame` → commit → `(#42)` → the issue that motivated it.

## 3. Remember the reasoning (L3)

Before merging, add a `## Decision Record` to the PR body — five bullet lines: **Root cause**, **Options considered**, **Options rejected**, **Selected option**, **Residual risk** (plus **Reproduction** for bugs). Then **squash-merge**: GitHub copies the PR body into the commit that lands on the default branch, so the reasoning survives in `git log -p` even if the tracker disappears.

**That's L3.** Six months from now, "why does this code exist?" is answered offline:

```bash
git log --oneline --grep "(#42)"      # every commit for issue 42
git log -p --grep "Closes #42"        # the full story, Decision Record included
```

More retrieval recipes: [idd-methodology.md → Reading the memory back](https://github.com/luongnv89/idd/blob/main/docs/idd-methodology.md#reading-the-memory-back).

## Optional: enforce it in CI

[`scripts/idd-lint.py`](https://github.com/luongnv89/idd/blob/main/scripts/idd-lint.py) checks all of the above from plain data — no LLM, no dependencies (Python stdlib):

```bash
python3 idd-lint.py repo --base origin/main   # branch name + commits
python3 idd-lint.py issue - < issue-body.md   # the §1 contract
python3 idd-lint.py stats                     # is it paying off?
```

When you later want the automated version of each phase — elicitation, triage, analysis, resolution — the [gitissue skills](https://github.com/luongnv89/idd#get-started) are the reference implementation of this same spec. Nothing about your issues has to change; that is the point.
