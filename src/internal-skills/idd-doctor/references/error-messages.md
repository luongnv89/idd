# Error Messages — /idd-doctor

All errors follow the rich error format: what went wrong + fix command (+ docs link when useful).

## Setup

### Not a git repository
```
✗ Not a git repository

  To fix:  cd into a git repository, or run `git init` first
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/platform-github.md
```
**Trigger:** `git rev-parse --git-dir` exits non-zero.

### Could not read repo root
```
✗ Could not read repo root

  To fix:  ensure the working directory is the repo root and is readable
  Check:   ls -la .
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/platform-github.md
```
**Trigger:** The repo root is unreadable (rare — typically a permission misconfiguration on a shared mount).

---

## Check 1 — Stale skill claims

### Pass
```
  ✓ [1/4] Stale skill claims    no stale language in /issue-creator
```
**Trigger:** `src/skills/issue-creator/docs/README.md` and `src/skills/issue-creator/SKILL.source.md` are both clean.

### Fail
```
  ✗ [1/4] Stale skill claims    {K} drifted line(s) in {J} file(s)
        {path}:{line_number}
        pattern: {matched_pattern}
        line:    {trimmed_line_text}
        ...
```
**Trigger:** At least one line in `src/skills/issue-creator/docs/README.md` or `src/skills/issue-creator/SKILL.source.md` matches a forbidden pattern without a negation marker on the same line.

**Fix hint** (printed once after the per-finding block):
```
        Fix: rewrite the offending lines to remove claims that /issue-creator
             scans the codebase, predicts affected files, or generates
             implementation notes. See docs §1a or
             /Users/.../src/skills/issue-creator/docs/README.md for the intent-only contract.
```

---

## Check 2 — Issue-template fields

### Pass
```
  ✓ [2/4] Issue-template fields no forbidden fields in {N} template(s)
```
**Trigger:** All scanned template files are clean.

### Pass (no templates)
```
  ✓ [2/4] Issue-template fields no template files found — nothing to check
```
**Trigger:** Neither `src/skills/issue-creator/templates/` nor `.github/ISSUE_TEMPLATE/` contain any files.

### Fail
```
  ✗ [2/4] Issue-template fields {K} forbidden field(s) in {J} template(s)
        {path}:{line_number}
        pattern: {matched_pattern}
        line:    {trimmed_line_text}
        ...
```
**Trigger:** At least one line in a scanned template file matches a forbidden pattern.

**Fix hint:**
```
        Fix: remove fields like "Affected Files", "Technical Notes",
             "Root Cause", or "Implementation Hints" from the template.
             These belong to /issue-resolver, not the issue body.
```

---

## Check 3 — Autopilot mode

### Skip (no config)
```
  ○ [3/4] Autopilot mode        skipped — no .gitissue.yml
```
**Trigger:** `.gitissue.yml` does not exist in the repo root.

### Pass
```
  ✓ [3/4] Autopilot mode        autopilot.mode = {value}
```
**Trigger:** `.gitissue.yml` exists and contains an `autopilot.mode` line with a non-empty value.

### Fail
```
  ✗ [3/4] Autopilot mode        .gitissue.yml has no autopilot.mode
        Fix: add to .gitissue.yml under `autopilot:`
          mode: conservative
```
**Trigger:** `.gitissue.yml` exists but does not contain a recognizable `autopilot.mode` line.

---

## Check 4 — Squash-merge default

### Skip (no gh)
```
  ○ [4/4] Squash-merge default  skipped — gh not installed
```
**Trigger:** `which gh` returns empty.

### Skip (gh unauthenticated)
```
  ○ [4/4] Squash-merge default  skipped — gh not authenticated
```
**Trigger:** `gh auth status` exits non-zero.

### Pass
```
  ✓ [4/4] Squash-merge default  squash-only · squash message source PR_BODY
```
**Trigger:** `squashMergeAllowed=true`, `mergeCommitAllowed=false`, `rebaseMergeAllowed=false`, **and** `squash_merge_commit_message=PR_BODY`.

All four conditions are required. SPEC §4.3 forbids reporting the B1 binding satisfied on the strength of the merge strategy alone: a squash-only repo whose message source is GitHub's default `COMMIT_MESSAGES` writes the list of commit subjects into the squash commit and the Decision Record never reaches git history.

### Warn
```
  ⚠ [4/4] Squash-merge default  {summary} — recommend squash-only
        Fix: in repo Settings → General → Pull Requests, allow only "Squash merging",
             and set the squash commit message to "Pull request title and description"
        Or:  gh api -X PATCH repos/:owner/:repo \
               -f allow_squash_merge=true \
               -f allow_merge_commit=false \
               -f allow_rebase_merge=false \
               -f squash_merge_commit_title=PR_TITLE \
               -f squash_merge_commit_message=PR_BODY
```
**Trigger:** Any of `mergeCommitAllowed`, `rebaseMergeAllowed` is `true`, or `squashMergeAllowed` is `false`, or `squash_merge_commit_message` is not `PR_BODY`.

Both `squash_merge_commit_*` fields go in one call: GitHub pairs `PR_BODY` only with `PR_TITLE` and rejects the message on its own with HTTP 422.

### Warn — message source unreadable
```
  ⚠ [4/4] Squash-merge default  {summary}; squash message source unreadable — binding unverified
```
**Trigger:** `gh repo view` succeeded but `gh api repos/{owner}/{repo}` did not — a 404, a token without the permission, or the `squash_merge_commit_message` field absent from the response.

This is a **warn, never a pass**, even when the strategy half is perfect (`squash-only; squash message source unreadable — binding unverified`). SPEC §4.3: tooling MUST NOT report the binding satisfied when the configuration cannot be read. It is also not a *skip* — a skip belongs to a missing or unauthenticated `gh`, where nothing at all was read; here the strategy was read and the answer is genuinely unknown.

### `{summary}` enumeration

`{summary}` belongs to the **warn** lines only. The pass line has its own fixed wording — `squash-only · squash message source PR_BODY`, joined with `·` — because a pass has exactly one shape and needs no enumeration. Everything below describes the warn lines, which join their clauses with `;`.

`{summary}` is the strategy clause, then — when the message source was read — a `; squash message source {value}` clause appended.

| Strategy state | Strategy clause |
|-------|---------|
| All three allowed | `squash + merge-commit + rebase enabled` |
| Squash + merge-commit | `squash + merge-commit enabled` |
| Squash + rebase | `squash + rebase enabled` |
| Squash only | `squash-only` |
| Only merge-commit | `merge-commit enabled (no squash)` |
| Only rebase | `rebase enabled (no squash)` |
| Nothing allowed | `no merge strategies enabled` |

| Message source | Clause |
|-------|---------|
| `PR_BODY` | `; squash message source PR_BODY` |
| `COMMIT_MESSAGES` (GitHub default) | `; squash message source COMMIT_MESSAGES` |
| `BLANK` | `; squash message source BLANK` |
| Unreadable | `; squash message source unreadable — binding unverified` |

This repo today reads `squash + merge-commit + rebase enabled; squash message source PR_BODY` — the message source was repaired under #295, but a one-click merge-commit or rebase still bypasses B1. See `docs/decisions/b1-binding-declaration.md`.

---

## Summary footer

After all four checks, print one of:

```
    Result: PASS  ({total} checks, 0 failed, 0 warned)
    Result: WARN  ({total} checks, 0 failed, {W} warned)
    Result: FAIL  ({total} checks, {F} failed, {W} warned)
        Run /idd-doctor after applying fixes to verify.
```

Where `{total}` is always 4. The "Run /idd-doctor after applying fixes…" hint is appended only when `{F} > 0`.
