# Error Messages — /idd-doctor

All errors follow the rich error format: what went wrong + fix command (+ docs link when useful).

**A block here that stops the run is followed by the run-stats footer** — see `references/run-stats.md`. A stop is a terminal outcome like any other, and printing the error block and exiting without the footer is the gap that contract exists to close. A stop that happens before the run clock was captured prints `elapsed n/a`, which is the contract working, not a hole in it. A `⚠` block that warns and continues is not a terminal outcome and prints no footer of its own.

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
             implementation notes. See SPEC.md §1.2 (intent–code boundary)
             for the intent-only contract.
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
  ○ [3/4] Autopilot mode        skipped — no .idd.yml
```
**Trigger:** `.idd.yml` does not exist in the repo root.

### Pass
```
  ✓ [3/4] Autopilot mode        autopilot.mode = {value}
```
**Trigger:** `.idd.yml` exists and contains an `autopilot.mode` line with a non-empty value.

### Fail
```
  ✗ [3/4] Autopilot mode        .idd.yml has no autopilot.mode
        Fix: add to .idd.yml under `autopilot:`
          mode: conservative
```
**Trigger:** `.idd.yml` exists but does not contain a recognizable `autopilot.mode` line.

### Fail (unreadable)
```
  ✗ [3/4] Autopilot mode        .idd.yml unreadable
        Fix: check the file's permissions:  ls -l .idd.yml
```
**Trigger:** `.idd.yml` exists but cannot be read. The check fails rather than stopping the run; Check 4 still runs.

---

## Check 4 — Merge method

`{method}` is `review.merge_method` from `.idd.yml`, or `squash` when the key is absent.

### Skip (no gh)
```
  ○ [4/4] Merge method           skipped — gh not installed
```
**Trigger:** `which gh` returns empty.

### Skip (gh unauthenticated)
```
  ○ [4/4] Merge method           skipped — gh not authenticated
```
**Trigger:** `gh auth status` exits non-zero.

### Skip (repo settings unreadable)
```
  ○ [4/4] Merge method           skipped — repo settings unreadable
```
**Trigger:** `gh` is authenticated but `gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed` fails — for example, the repo has no GitHub remote. Nothing was read, so the binding is neither passed nor warned.

### Pass
```
  ✓ [4/4] Merge method           {method} allowed · IDD's merge carries the PR body
```
**Trigger:** `{method}` is `squash` and `squashMergeAllowed=true`, or `{method}` is `merge` and `mergeCommitAllowed=true`. Other allowed methods do not matter: IDD's merge passes the PR body as the commit body, so no repository setting is needed.

### Hand-merge note (under a pass)
```
        ○ a hand merge in the GitHub UI will not carry the PR body ({field}: {value})
```
**Trigger:** the check passed and `{field}` — `squash_merge_commit_message` for `squash`, `merge_commit_message` for `merge` — is not `PR_BODY`. When `gh api repos/{owner}/{repo}` did not answer, `{value}` is `unread`. The note never changes the result.

### Warn — method not allowed
```
  ⚠ [4/4] Merge method           {method} is not allowed by this repo ({summary})
        Fix: set review.merge_method in .idd.yml to one of: {allowed}
```
**Trigger:** `{method}` is `squash` or `merge` and the repo does not allow it. The fix is a config edit. The doctor never prints a repository-settings command.

### Warn — rebase
```
  ⚠ [4/4] Merge method           rebase is tracker-only — no commit carries the PR body
        Fix: set review.merge_method in .idd.yml to squash or merge
```
**Trigger:** `{method}` is `rebase`, whatever the repo allows. A rebase lands the PR's own commits, so neither B1 nor B2 holds.

### Warn — invalid method
```
  ⚠ [4/4] Merge method           review.merge_method: {value} is not squash, merge or rebase
        Fix: set review.merge_method in .idd.yml to squash, merge or rebase
```
**Trigger:** the `merge_method:` line carries any other value. Nothing else is read.

### `{summary}` enumeration

`{summary}` names what the strategy read returned; `{allowed}` lists the same methods as config values (`squash`, `merge`, `rebase`).

| Strategy state | `{summary}` |
|-------|---------|
| All three allowed | `squash + merge-commit + rebase enabled` |
| Squash + merge-commit | `squash + merge-commit enabled` |
| Squash + rebase | `squash + rebase enabled` |
| Merge-commit + rebase | `merge-commit + rebase enabled` |
| Squash only | `squash-only` |
| Only merge-commit | `merge-commit only` |
| Only rebase | `rebase only` |
| Nothing allowed | `no merge strategies enabled` |

This repo today sets no `review.merge_method` and allows squash only, so it reads `squash allowed · IDD's merge carries the PR body`. See `docs/decisions/b1-binding-declaration.md`.

---

## Summary footer

After all four checks, print the separator, one `Result:` line, then the three contract rows defined in `references/review-contract.md`:

```
    ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    Result: PASS  ({total} checks, 0 failed, 0 warned)
    Result: WARN  ({total} checks, 0 failed, {W} warned)
    Result: FAIL  ({total} checks, {F} failed, {W} warned)
    Evidence:    ran {checks} · skipped {N} ({reason}) · scanned {a} skill files, {b} templates
    Uncertainty: {items, separated by "; "}
    Decision:    No approval needed — report-only, nothing changed. Next: {fix hints to apply, then re-run /idd-doctor | none}
```

Print exactly one of the three `Result:` lines. `{total}` is always 4. Omit the `skipped …` clause when no check skipped.
