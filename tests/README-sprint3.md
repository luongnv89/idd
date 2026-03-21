# Integration Tests — gitissue Sprint 3

These are manual integration tests for `/issue-triage`, `/init-gitissue`, and the formalized confidence scoring system.

## Prerequisites

- A test GitHub repository with push access
- `gh` CLI authenticated (`gh auth status`)
- Claude Code with `/issue-triage`, `/init-gitissue`, and `/issue-creator` skills loaded
- Test files in the repo for codebase scanning (see Sprint 1 setup)

## Setup

If not already set up from Sprint 1:

1. Create a test repo:
   ```bash
   gh repo create test-gitissue --public --clone
   cd test-gitissue
   echo "# Test repo for gitissue" > README.md
   git add README.md && git commit -m "init"
   git push -u origin main
   ```

2. Create test files for codebase scanning:
   ```bash
   mkdir -p src/auth src/api src/db tests
   echo 'def login(user, password): pass' > src/auth/login.py
   echo 'def get_users(): pass' > src/api/users.py
   echo 'class AuthError(Exception): pass' > src/auth/errors.py
   echo 'def connect(): pass' > src/db/connection.py
   echo 'def test_login(): pass' > tests/test_auth.py
   git add . && git commit -m "add test files" && git push
   ```

3. Create 10+ open issues for triage tests (lean format — no affected files in body):
   ```bash
   # Issue 1: bug about auth (triage will find auth files via keyword scan)
   gh issue create --title "Fix login redirect loop" --body '<!-- gitissue:normalized v1 -->
   ## Type
   Bug
   ## Description
   Login page redirects infinitely. The redirect logic in the auth module loops.
   ## Acceptance Criteria
   - [ ] Login completes without redirect loop
   ## Metadata
   **Priority:** P1
   **Labels:** bug, auth'

   # Issue 2: feature about api
   gh issue create --title "Add pagination to users endpoint" --body '<!-- gitissue:normalized v1 -->
   ## Type
   Feature
   ## Description
   Users endpoint needs pagination support. The API users module needs page/limit params.
   ## Acceptance Criteria
   - [ ] GET /users supports page and limit params
   ## Metadata
   **Priority:** P2
   **Labels:** feature, api'

   # Issue 3: improvement about auth (triage should detect overlap with issue 1 via keyword scan)
   gh issue create --title "Refactor auth middleware for OAuth2" --body '<!-- gitissue:normalized v1 -->
   ## Type
   Improvement
   ## Description
   Auth middleware needs refactoring for OAuth2 support. The login and error handling modules need updates.
   ## Acceptance Criteria
   - [ ] Auth middleware supports OAuth2 flow
   ## Metadata
   **Priority:** P2
   **Labels:** improvement, auth'

   # Issue 4: bug about db
   gh issue create --title "Fix database connection leak" --body '<!-- gitissue:normalized v1 -->
   ## Type
   Bug
   ## Description
   Database connections are not being closed properly. The connection module leaks handles.
   ## Acceptance Criteria
   - [ ] All database connections are properly closed after use
   ## Metadata
   **Priority:** P1
   **Labels:** bug, db'

   # Issue 5: feature (independent)
   gh issue create --title "Add dark mode toggle" --body '<!-- gitissue:normalized v1 -->
   ## Type
   Feature
   ## Description
   Add a dark mode toggle to settings page.
   ## Acceptance Criteria
   - [ ] Dark mode can be toggled in settings
   ## Metadata
   **Priority:** P3
   **Labels:** feature, ui'

   # Issues 6-10: create more for backlog depth (unstructured — triage scans keywords)
   gh issue create --title "Improve error messages in API" --body "API errors are too generic"
   gh issue create --title "Add rate limiting to endpoints" --body "Endpoints need rate limiting"
   gh issue create --title "Update user profile schema" --body "Profile schema needs new fields"
   gh issue create --title "Fix mobile CSS layout" --body "Layout breaks on small screens"
   gh issue create --title "Add email notification service" --body "Users need email notifications"
   ```

---

## Test Cases: /issue-triage

### T21: Triage 10+ issues — dependency table and execution order

**Setup:** Ensure 10+ open issues exist (see setup above).

**Input:**
```
/issue-triage
```

**Expected:**
- [ ] Output shows `● Fetching {N} open issues...`
- [ ] Output shows `● Scanning codebase for issue dependencies...`
- [ ] Output shows `◆ Issue Triage` section header
- [ ] Dependency table uses box-drawing characters: `│ ─ ┼`
- [ ] Table has columns: `# │ Issue │ Pri │ Blocks │ Status`
- [ ] Issues with keyword overlap detected via codebase scan (e.g., issue 1 and 3 both mention "auth" → triage finds shared files in `src/auth/`)
- [ ] Status column shows `ready`, `blocked`, or `stale` as appropriate
- [ ] Output shows `⚡ Parallelizable:` line identifying independent issues
- [ ] Output shows `○ Suggested order:` with topological sort
- [ ] If any issues are stale, output shows `⚠ Stale: N issue(s) (>14 days inactive)`

**Verify:**
```bash
# Confirm issues 1 and 3 are detected as dependent
# (triage keyword scan finds both mention "auth" → shared files in src/auth/)
# The triage output should show one blocking the other
```

---

### T22: Triage with circular dependencies

**Setup:** Create an issue whose keywords overlap with both issue 1 (auth) and issue 2 (API users):

```bash
gh issue create --title "Refactor API auth integration" --body '<!-- gitissue:normalized v1 -->
## Type
Improvement
## Description
API needs to use new auth middleware. The users endpoint and login module need to be integrated.
## Acceptance Criteria
- [ ] API uses refactored auth
## Metadata
**Priority:** P2
**Labels:** improvement'
```

This issue mentions both "auth/login" and "API/users" keywords, so triage's keyword scan should find files overlapping with both issue 1 and issue 2, potentially creating a cycle.

**Input:**
```
/issue-triage
```

**Expected:**
- [ ] If circular dependencies are detected, output shows `⚠ Circular dependency detected: #{a} → #{b} → #{a}`
- [ ] Warning includes suggestion for which to resolve first
- [ ] Triage continues despite circular dependency (it's a warning, not a blocker)
- [ ] Remaining issues still appear in the dependency table

---

### T23: Triage with no open issues

**Setup:** Close all open issues:
```bash
gh issue list --state open --json number --jq '.[].number' | while read n; do
  gh issue close "$n" --reason "not planned"
done
```

**Input:**
```
/issue-triage
```

**Expected:**
- [ ] Output shows `○ No open issues found. Nothing to triage!`
- [ ] Output shows `Create issues with /issue-creator to get started.`
- [ ] No table displayed
- [ ] No errors

**Cleanup:** Reopen issues for other tests:
```bash
gh issue list --state closed --json number --jq '.[].number' | while read n; do
  gh issue reopen "$n"
done
```

---

### T24: Triage stale detection

**Setup:** Ensure at least one issue has `updatedAt` older than 14 days. If all test issues were just created, this test requires waiting or using an issue known to be old. Alternatively, set `triage.stale_threshold_days: 0` in `.gitissue.yml`:

```bash
cat > .gitissue.yml << 'EOF'
triage:
  stale_threshold_days: 0
EOF
git add .gitissue.yml && git commit -m "temp: zero stale threshold" && git push
```

**Input:**
```
/issue-triage
```

**Expected:**
- [ ] Output shows `⚠ Stale: N issue(s)` line
- [ ] Stale issues marked in the Status column with `stale (Nd)` where N is days since last activity

**Cleanup:**
```bash
git rm .gitissue.yml && git commit -m "remove temp config" && git push
```

---

### T25: Triage with --limit flag

**Setup:** Ensure 10+ open issues exist.

**Input:**
```
/issue-triage --limit 3
```

**Expected:**
- [ ] Only 3 issues are analyzed
- [ ] Output shows `● Fetching 3 open issues...` (or similar limited count)
- [ ] Dependency table shows at most 3 rows
- [ ] No errors about truncated results

---

## Test Cases: /init-gitissue

### T26: Init on fresh repo (no .gitissue.yml)

**Setup:** Ensure no `.gitissue.yml` exists in the repo root.

**Input:**
```
/init-gitissue
```

**Expected:**
- [ ] Output shows `● Scanning repository...`
- [ ] Output shows detected language (e.g., `Language: Python`)
- [ ] Output shows detected test runner or `Could not detect test runner`
- [ ] Output shows repo size estimate
- [ ] Output shows `◆ Configuration` section
- [ ] `.gitissue.yml` file created in repo root
- [ ] File contains all config sections: `platform`, `issue`, `resolve`, `triage`
- [ ] File contains inline `#` comments explaining each setting
- [ ] Output shows `✓ Setup complete`
- [ ] Output shows `Run /issue-creator to create your first issue`

**Verify:**
```bash
# Check file exists
cat .gitissue.yml

# Check it has the expected sections
grep "platform:" .gitissue.yml
grep "issue:" .gitissue.yml
grep "resolve:" .gitissue.yml
grep "triage:" .gitissue.yml

# Check inline comments exist
grep "#" .gitissue.yml | head -5
```

**Cleanup:**
```bash
rm .gitissue.yml
```

---

### T27: Init with existing .gitissue.yml

**Setup:**
```bash
echo "platform: github" > .gitissue.yml
```

**Input:**
```
/init-gitissue
```

**Expected:**
- [ ] Output shows `⚠ .gitissue.yml already exists`
- [ ] Output shows three options: `overwrite`, `merge`, `cancel`
- [ ] Selecting `overwrite` replaces the file with a new auto-detected config
- [ ] Selecting `merge` keeps existing values and adds new fields
- [ ] Selecting `cancel` makes no changes

**Cleanup:**
```bash
rm .gitissue.yml
```

---

### T28: Init language detection — Python project

**Setup:** Ensure the test repo has Python files and a `requirements.txt`:
```bash
echo "flask==3.0.0" > requirements.txt
git add requirements.txt && git commit -m "add requirements" && git push
```

**Input:**
```
/init-gitissue
```

**Expected:**
- [ ] Output shows `Language: Python (detected from requirements.txt)`
- [ ] If Flask is detected: `Framework: Flask`
- [ ] Generated config has appropriate Python defaults
- [ ] If pytest is detected, `resolve.auto_test: true`

**Cleanup:**
```bash
git rm requirements.txt && git commit -m "remove requirements" && git push
rm .gitissue.yml
```

---

### T29: Init on empty repo — no language detected

**Setup:** Create a new empty repo:
```bash
mkdir /tmp/test-empty-repo && cd /tmp/test-empty-repo
git init && git commit --allow-empty -m "init"
```

**Input:**
```
/init-gitissue
```

**Expected:**
- [ ] Output shows `○ Could not detect project language. Using generic defaults.`
- [ ] Output shows `○ Could not detect test runner. Setting resolve.auto_test: false.`
- [ ] `.gitissue.yml` still created with generic defaults
- [ ] `resolve.auto_test` is set to `false` in the generated config

**Cleanup:**
```bash
cd - && rm -rf /tmp/test-empty-repo
```

---

## Test Cases: Confidence Scoring (Lean Issues)

Confidence scoring now applies only to **type classification** and **acceptance criteria**. File-level confidence is removed (issues no longer contain affected files).

### T30: High confidence — explicit bug keywords

**Input:**
```
/issue-creator The login page crashes with a 500 Internal Server Error when using SSO
```

**Expected:**
- [ ] Preview shows `Type: bug (high)` — crash/500/error keywords trigger high confidence
- [ ] Preview does NOT show a `Files:` line
- [ ] Created issue body shows type with `(high confidence)`
- [ ] Acceptance criteria are generated with confidence levels

**Verify:**
```bash
gh issue view <N> --json body --jq '.body' | grep "high confidence"
# Should match on the Type line
gh issue view <N> --json body --jq '.body' | grep -c "Affected files"
# Should be: 0
```

---

### T31: Medium confidence — inferred type

**Input:**
```
/issue-creator The authentication system sometimes fails for new users
```

**Expected:**
- [ ] Preview shows `Type: bug (medium)` — "fails" suggests bug but isn't explicit crash/error
- [ ] Issue body shows type with `(medium confidence)`
- [ ] Issue body does NOT contain affected files

**Verify:**
```bash
gh issue view <N> --json body --jq '.body' | grep "medium confidence"
```

---

### T32: Low confidence — vague description

**Input:**
```
/issue-creator Something is broken when users try to do things
```

**Expected:**
- [ ] Preview shows `Type: bug (needs review)` — ambiguous, defaulted
- [ ] Issue body marks type with `(needs review)`
- [ ] Acceptance criteria likely marked `(needs review)` too
- [ ] Issue body does NOT contain affected files

**Verify:**
```bash
gh issue view <N> --json body --jq '.body' | grep "needs review"
```

---

### T33: Confidence in normalization preview (structure-only)

**Setup:**
```bash
gh issue create --title "Auth login is slow" --body "The login function takes forever to return"
```

**Input:**
```
/issue-creator <N>
```

**Expected:**
- [ ] Normalization preview shows confidence on Type and Criteria only:
  - `+ Type:` with confidence (e.g., `improvement (medium)`)
  - `+ Criteria:` with confidence (e.g., `3 acceptance criteria (medium)`)
- [ ] Preview does NOT show `+ Files:` line
- [ ] `= Original:` line shows preserved text
- [ ] Low-confidence items show `(needs review)` in the preview

---

## Test Cases: Triage Keyword Scan (Lean Issues)

### T34: Triage builds dependency graph from keyword scan (not issue body)

**Setup:** Use issues from setup above (lean format — no affected files in body).

**Input:**
```
/issue-triage
```

**Expected:**
- [ ] Output shows `● Scanning codebase for issue dependencies...`
- [ ] Triage scans codebase for each issue's keywords (not reading affected files from body)
- [ ] Issues 1 and 3 both mention "auth" keywords → triage finds files in `src/auth/` for both → dependency detected
- [ ] Issue 4 mentions "database/connection" → triage finds `src/db/connection.py` → independent from auth issues
- [ ] Dependency graph is built from scan results, not from issue body content

**Verify:**
```bash
# Check triage.json was created
cat .gitissue/triage.json | jq '.issues[0].affected_files'
# Should contain files found by keyword scan (e.g., ["src/auth/login.py"])
# NOT files read from the issue body
```

---

### T35: Triage handles issues with no affected files section

**Setup:** Ensure some issues have no `## Context` or `**Affected files:**` section (issues 6-10 from setup are unstructured).

**Input:**
```
/issue-triage
```

**Expected:**
- [ ] No errors about missing affected files
- [ ] Unstructured issues still appear in the triage table
- [ ] Triage extracts keywords from raw title/body text for unstructured issues
- [ ] If keyword scan finds files, dependencies are detected normally

---

### T36: Triage scan timeout

**Setup:** Create a `.gitissue.yml` with a very short timeout to force timeout behavior:
```bash
cat > .gitissue.yml << 'EOF'
triage:
  scan_timeout_per_issue: 1
EOF
git add .gitissue.yml && git commit -m "temp: 1s scan timeout" && git push
```

**Input:**
```
/issue-triage
```

**Expected:**
- [ ] If any issue scan exceeds 1 second, output shows `⚠ Scan timeout for #N — skipping file analysis`
- [ ] Timed-out issues appear in the table with `no-deps (timeout)` status
- [ ] Triage completes successfully (timeout is non-fatal)
- [ ] Non-timed-out issues still have their dependencies analyzed

**Cleanup:**
```bash
git rm .gitissue.yml && git commit -m "remove temp config" && git push
```

---

### T37: Triage persists keyword-scan results to triage.json

**Input:**
```
/issue-triage
```

**Expected:**
- [ ] `.gitissue/triage.json` is created/updated
- [ ] Each issue entry has `affected_files` populated from keyword scan (not from issue body)
- [ ] `affected_files` reflect current codebase state

**Verify:**
```bash
cat .gitissue/triage.json | jq '.issues[] | {number, affected_files}'
# Each issue should have affected_files from scan results
```

---

## Cleanup

After testing, clean up test issues, config files, and branches:

```bash
# Close all test issues
gh issue list --state open --json number --jq '.[].number' | while read n; do
  gh issue close "$n" --reason "not planned"
done

# Remove config file
rm -f .gitissue.yml

# Remove test branches
git branch | grep "issue-" | xargs -I {} git branch -D {}
```
