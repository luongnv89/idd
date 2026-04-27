# /init-gitissue — Examples

Full example outputs for the three typical scenarios.

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
6. Report:

```
  ● Scanning repository...
    Language:    TypeScript (detected from package.json)
    Framework:   Next.js
    Test runner: Jest
    Templates:   .github/ISSUE_TEMPLATE/ found (3 templates)
    Repo size:   medium (342 files)

  ◆ Configuration
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    Generated .gitissue.yml with project-specific defaults

  ✓ Setup complete
    Config: .gitissue.yml
    Run /issue-creator to create your first issue
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
7. Report:

```
  ○ Could not detect test runner. Setting resolve.auto_test: false.
    Tip: configure your test command in .gitissue.yml after setup.

  ● Scanning repository...
    Language:    Python (detected from requirements.txt)
    Test runner: none
    Templates:   none found
    Repo size:   small (47 files)

  ◆ Configuration
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    Generated .gitissue.yml with project-specific defaults

  ✓ Setup complete
    Config: .gitissue.yml
    Run /issue-creator to create your first issue
```

## Example: Config already exists (merge)

**User says:** `/init-gitissue`

1. Prerequisites pass
2. `.gitissue.yml` already exists — show overwrite/merge/cancel prompt
3. User chooses **merge**
4. Read existing file, scan repo, add missing fields
5. Report:

```
  ● Scanning repository...
    Language:    Go (detected from go.mod)
    Framework:   Gin
    Test runner: Go test
    Templates:   none found
    Repo size:   large (1847 files)

  ◆ Configuration
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    Merged new fields into existing .gitissue.yml
    3 new fields added, 8 existing values preserved

  ✓ Setup complete
    Config: .gitissue.yml
    Run /issue-creator to create your first issue
```

---

