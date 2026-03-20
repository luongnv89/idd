# Integration Tests — gitissue Sprint 1

These are manual integration tests for `/create-issue` and `/create-issue N` (normalization).

## Prerequisites

- A test GitHub repository with push access
- `gh` CLI authenticated (`gh auth status`)
- Claude Code with the `/create-issue` skill loaded

## Setup

1. Create a test repo (or use an existing one):
   ```bash
   gh repo create test-gitissue --public --clone
   cd test-gitissue
   echo "# Test repo for gitissue" > README.md
   git add README.md && git commit -m "init"
   git push -u origin main
   ```

2. Create some test files for codebase scanning:
   ```bash
   mkdir -p src/auth src/api tests
   echo 'def login(user, password): pass' > src/auth/login.py
   echo 'def get_users(): pass' > src/api/users.py
   echo 'class AuthError(Exception): pass' > src/auth/errors.py
   echo 'def test_login(): pass' > tests/test_auth.py
   git add . && git commit -m "add test files" && git push
   ```

3. Load the skill in Claude Code:
   Add to `.claude/settings.json`:
   ```json
   { "skills": ["./skills/create-issue"] }
   ```

---

## Test Cases

### T1: Create issue from one-sentence description

**Input:**
```
/create-issue The login page returns a 500 error when using SSO authentication
```

**Expected:**
- [ ] Output shows `● Scanning codebase...`
- [ ] Output shows `◆ Issue Preview` section with Type, Title, Files, Labels, Criteria
- [ ] Issue type is classified as `bug`
- [ ] Affected files include `src/auth/login.py` (or related auth files)
- [ ] Issue is created on GitHub with structured template
- [ ] Issue body contains `<!-- gitissue:normalized v1 -->` marker
- [ ] Issue body contains `## Type`, `## Context`, `## Description`, `## Acceptance Criteria`, `## Technical Notes`, `## Metadata` sections
- [ ] Output shows `✓ Created issue #N` with GitHub URL on its own line

**Verify:**
```bash
gh issue view <N> --json body | jq -r '.body' | head -5
# Should start with: <!-- gitissue:normalized v1 -->
```

---

### T2: Create issue from vague description (empty state)

**Input:**
```
/create-issue Something is broken
```

**Expected:**
- [ ] Output shows `⚠ Could not identify affected files. Issue created with manual-review flag.`
- [ ] Issue is still created (not blocked by missing files)
- [ ] Issue body has empty or "Unable to determine" for affected files section

---

### T3: Normalize a messy existing issue

**Setup:**
```bash
gh issue create --title "login broken on mobile" --body "the login doesn't work on phones. it just spins forever."
# Note the issue number
```

**Input:**
```
/create-issue <N>
```

**Expected:**
- [ ] Output shows `● Fetching issue #N...`
- [ ] Output shows `● Scanning codebase for context...`
- [ ] Output shows `◆ Normalization Preview` with `+` prefixed added fields and `=` preserved fields
- [ ] Confidence scores shown: `(high)`, `(medium)`, or `(low)`
- [ ] Backup comment posted BEFORE body edit (verify in GitHub)
- [ ] Backup comment contains original body in `<details>` block
- [ ] Issue body updated with full template structure
- [ ] Reporter Context blockquote contains: "the login doesn't work on phones. it just spins forever."
- [ ] Normalization comment posted noting what was added
- [ ] Output shows `✓ Backup posted` and `✓ Issue #N normalized` with URL

**Verify:**
```bash
# Check backup comment exists
gh issue view <N> --json comments --jq '.comments[-2].body' | head -3
# Should contain: <details><summary>Original issue body

# Check normalized body
gh issue view <N> --json body --jq '.body' | head -1
# Should be: <!-- gitissue:normalized v1 -->

# Check Reporter Context preserved
gh issue view <N> --json body --jq '.body' | grep "Reporter Context"
# Should contain the original text
```

---

### T4: Normalize already-normalized issue (skip)

**Setup:** Use the issue from T3 (already normalized).

**Input:**
```
/create-issue <N>
```

**Expected:**
- [ ] Output shows `✓ Issue #N is already normalized (v1). No changes needed.`
- [ ] No backup comment posted
- [ ] No body edits made
- [ ] No errors

---

### T5: Normalize security-labeled issue (skip with warning)

**Setup:**
```bash
gh issue create --title "XSS in comment field" --body "script tags are not sanitized" --label "security"
```

**Input:**
```
/create-issue <N>
```

**Expected:**
- [ ] Output shows `⚠ Issue #N has a security label (security). Skipping normalization.`
- [ ] Output shows `To override: /create-issue N --force`
- [ ] No backup comment posted
- [ ] No body edits made

---

### T6: Force normalize security-labeled issue

**Input:**
```
/create-issue <N> --force
```

**Expected:**
- [ ] Security label warning is bypassed
- [ ] Normalization proceeds normally (same as T3)
- [ ] Issue body updated with template structure

---

### T7: Dry-run normalization

**Setup:**
```bash
gh issue create --title "API timeout on large requests" --body "requests over 1MB timeout after 30 seconds"
```

**Input:**
```
/create-issue <N> --dry-run
```

**Expected:**
- [ ] Output shows normalization preview with confidence scores
- [ ] Output shows `○ Dry run complete. No changes applied.`
- [ ] No backup comment posted
- [ ] No body edits made
- [ ] Issue is unchanged on GitHub

**Verify:**
```bash
gh issue view <N> --json body --jq '.body'
# Should still be: "requests over 1MB timeout after 30 seconds"
```

---

### T8: Authentication failure

**Setup:**
```bash
# Temporarily break auth (restore after test)
# Option A: test in a repo you don't have access to
# Option B: revoke token temporarily
```

**Input:**
```
/create-issue Test issue
```

**Expected:**
- [ ] Output shows rich error format:
  ```
  ✗ Not authenticated with GitHub

    To fix:  gh auth login
    Docs:    https://cli.github.com/manual/gh_auth_login
  ```
- [ ] No issue created

---

### T9: Issue not found

**Input:**
```
/create-issue 99999
```

**Expected:**
- [ ] Output shows:
  ```
  ✗ Issue #99999 not found

    To fix:  gh issue list
    Check:   is this the right repository?
  ```

---

### T10: Normalization marker false positive

**Setup:**
Create an issue with the marker text inside a code block:

```bash
gh issue create --title "Document normalization marker" --body '```
The marker looks like this:
<!-- gitissue:normalized v1 -->
```

This issue is NOT normalized.'
```

**Input:**
```
/create-issue <N>
```

**Expected:**
- [ ] Skill recognizes the marker is inside a code block (NOT a real normalization marker)
- [ ] Normalization proceeds normally
- [ ] Issue body is updated with real template structure and real marker outside code blocks

---

### T11: Duplicate issue detection

**Setup:**
```bash
gh issue create --title "Fix login redirect loop" --body "The login page redirects infinitely"
```

**Input:**
```
/create-issue The login redirect keeps looping
```

**Expected:**
- [ ] Output shows duplicate warning: `⚠ Possible duplicate: #N "Fix login redirect loop"`
- [ ] Shows link to the existing issue
- [ ] Asks whether to continue

---

### T12: Config loading — first run hint

**Setup:** Ensure no `.gitissue.yml` exists in the repo root.

**Input:**
```
/create-issue Add dark mode support
```

**Expected:**
- [ ] First line of output includes: `○ First run — using default config. Run /init-gitissue to customize.`
- [ ] Skill proceeds normally with default settings

---

## Cleanup

After testing, clean up the test issues:

```bash
# List all test issues
gh issue list --state open

# Close test issues
gh issue close <N> --reason "not planned"
```
