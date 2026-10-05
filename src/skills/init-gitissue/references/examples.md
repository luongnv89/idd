# /init-gitissue — Examples

Full example outputs for four scenarios. Every report follows `references/review-contract.md`: `Result` first, then the `Evidence`, `Uncertainty`, and `Decision` rows.

## Example: TypeScript + Next.js project

**User says:** `/init-gitissue`

1. Prerequisites pass — git repo confirmed
2. No existing `.gitissue.yml` found
3. Scan:
   - `package.json` found → TypeScript (typescript in devDependencies)
   - `next` in dependencies → Next.js
   - `jest.config.ts` found → Jest
   - `.github/ISSUE_TEMPLATE/` found with 3 files
   - `git ls-files` returns 342 files → medium
4. Defaults: `test_timeout: 300`, `auto_test: true`, `stale_threshold_days: 14`, `scan_timeout_per_issue: 30`
5. Write `.gitissue.yml` with Next.js-specific comments
6. Validate the written file — parses as YAML, no placeholder tokens left, `platform` present
7. Merge-settings reads: squash-only, but `squash_merge_commit_message` is `COMMIT_MESSAGES`
8. Report:

```
◆ Init Gitissue — setup complete
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Result:            DONE — .gitissue.yml generated and validated
  Git repo:          ✓ pass
  Language:          ✓ TypeScript (from package.json)
  Framework:         ✓ Next.js (from package.json)
  Test runner:       ✓ Jest (from jest.config.ts)
  Templates:         ✓ .github/ISSUE_TEMPLATE/ (3 templates)
  Repo size:         ✓ medium (342 files, via git ls-files)
  Config:            ✓ generated .gitissue.yml
  Validation:        ✓ parses as YAML, no placeholders left, platform set
  Merge settings:    ⚠ warn (message is COMMIT_MESSAGES)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Evidence:          gi-stack-detect exit 0; re-read with PyYAML
  Uncertainty:       values from marker files; Jest not run
  Decision:          No approval needed.

  Config: .gitissue.yml
  Next action: review and commit .gitissue.yml; run the squash-message
               To fix: command above; then /issue-creator
```

## Example: Minimal Python project

**User says:** `/init-gitissue`

1. Prerequisites pass
2. No existing `.gitissue.yml`
3. Scan:
   - `requirements.txt` found → Python
   - No known framework in requirements
   - No test runner markers found
   - No `.github/ISSUE_TEMPLATE/` directory
   - 47 tracked files → small
4. Print: `○ Could not detect test runner. Setting resolve.auto_test: false.`
5. Defaults: `test_timeout: 60`, `auto_test: false`, `stale_threshold_days: 7`, `scan_timeout_per_issue: 30`
6. Write `.gitissue.yml`
7. Validate the written file — parses as YAML, no placeholder tokens left, `platform` present
8. `gh` is not installed — merge-settings check skipped
9. Report:

```
  ○ Could not detect test runner. Setting resolve.auto_test: false.
    Tip: configure your test command in .gitissue.yml after setup.

◆ Init Gitissue — setup complete
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Result:            DONE — .gitissue.yml generated and validated
  Git repo:          ✓ pass
  Language:          ✓ Python (from requirements.txt)
  Framework:         ○ skip (not detected)
  Test runner:       ⚠ warn (none — auto_test disabled)
  Templates:         ○ skip (none found)
  Repo size:         ✓ small (47 files, via git ls-files)
  Config:            ✓ generated .gitissue.yml
  Validation:        ✓ parses as YAML, no placeholders left, platform set
  Merge settings:    ○ skip (gh not installed)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Evidence:          gi-stack-detect exit 0; re-read with PyYAML
  Uncertainty:       merge settings unread; values from marker files
  Decision:          No approval needed.

  Config: .gitissue.yml
  Next action: review and commit .gitissue.yml, then /issue-creator
```

## Example: Config already exists (merge)

**User says:** `/init-gitissue`

1. Prerequisites pass
2. `.gitissue.yml` already exists — show overwrite/merge/cancel prompt
3. User chooses **merge**
4. Read existing file, scan repo, add missing fields
5. Validate the merged file — parses as YAML, no placeholder tokens left, `platform` present
6. Merge-settings reads: squash-only, `PR_BODY`
7. Report:

```
◆ Init Gitissue — setup complete
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Result:            DONE — merged into .gitissue.yml and validated
  Git repo:          ✓ pass
  Language:          ✓ Go (from go.mod)
  Framework:         ✓ Gin (from go.mod)
  Test runner:       ✓ Go test (from *_test.go)
  Templates:         ○ skip (none found)
  Repo size:         ✓ large (1847 files, via git ls-files)
  Config:            ✓ merged into existing .gitissue.yml (3 new, 8 preserved)
  Validation:        ✓ parses as YAML, no placeholders left, platform set
  Merge settings:    ✓ squash-only, PR_BODY
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Evidence:          gi-stack-detect exit 0; re-read with PyYAML
  Uncertainty:       8 preserved values not re-checked against the scan
  Decision:          No approval needed.

  Config: .gitissue.yml
  Next action: review and commit .gitissue.yml, then /issue-creator
```

## Example: Config already exists (auto mode)

**Invoked by:** an orchestrator with `IDD_AUTO_MODE=1`

1. Prerequisites pass
2. `.gitissue.yml` already exists — auto mode takes the safe default (cancel)
3. No scan, no write
4. Report:

```
⚠ .gitissue.yml exists — auto mode keeps it (cancel)

◆ Init Gitissue — cancelled
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Result:            CANCELLED — existing .gitissue.yml kept unchanged
  Evidence:          .gitissue.yml present; IDD_AUTO_MODE=1
  Uncertainty:       existing file not scanned or validated
  Decision:          No approval needed.

  Next action: re-run /init-gitissue interactively to merge or overwrite
```

---

