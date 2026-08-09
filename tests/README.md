# Integration Tests — gitissue Sprint 1 (Lean Issues)

These are manual integration tests for `/issue-creator` and `/issue-creator N` (normalization).

> This file covers Sprint 1 (`/issue-creator`) only. See [`README-sprint2.md`](README-sprint2.md) and [`README-sprint3.md`](README-sprint3.md) for later sprints' manual tests.
>
> **The automated suite is separate from all three READMEs.** The `.sh` scripts in this directory (build, autopilot, config, sync, security, …) need no setup and no GitHub repo — they read `src/`, `docs/`, and the built `skills/`. Every one of them runs in CI, and [`.github/workflows/dist-check.yml`](../.github/workflows/dist-check.yml) is the authoritative list: one named step per script, in the order CI runs them. Run one locally from the repo root with `bash tests/<name>.sh`; run them all with `git ls-files 'tests/*.sh' | xargs -n1 bash`. `tests/test-build-script.sh` (T9) fails if any script in this directory is missing from that workflow, so the list cannot silently fall behind.

Updated for the **lean issues architecture**: issues contain only human intent (type, description, acceptance criteria). No codebase scanning during issue creation or normalization.

## Prerequisites

- A test GitHub repository with push access
- `gh` CLI authenticated (`gh auth status`)
- Claude Code with the `/issue-creator` skill loaded

## Setup

1. Create a test repo (or use an existing one):
   ```bash
   gh repo create test-gitissue --public --clone
   cd test-gitissue
   echo "# Test repo for gitissue" > README.md
   git add README.md && git commit -m "init"
   git push -u origin main
   ```

2. Create some test files (used by triage and resolver tests, not creator):
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
   { "skills": ["./skills/issue-creator"] }
   ```

---

## Test Cases

### T1: Create lean issue from one-sentence description

**Input:**
```
/issue-creator The login page returns a 500 error when using SSO authentication
```

**Expected:**
- [ ] Output shows `◆ Issue Preview` section with Type, Title, Labels, Criteria
- [ ] Output does NOT show `● Scanning codebase...` (no codebase scan)
- [ ] Preview does NOT contain a `Files:` line
- [ ] Issue type is classified as `bug`
- [ ] Issue is created on GitHub with structured template
- [ ] Issue body contains `<!-- gitissue:normalized v1 -->` marker
- [ ] Issue body contains `## Type`, `## Description`, `## Acceptance Criteria`, `## Metadata` sections
- [ ] Issue body does NOT contain `## Context` or `## Technical Notes` sections
- [ ] Output shows `✓ Created issue #N` with GitHub URL on its own line

**Verify:**
```bash
gh issue view <N> --json body | jq -r '.body' | head -5
# Should start with: <!-- gitissue:normalized v1 -->

# Verify NO affected files section
gh issue view <N> --json body | jq -r '.body' | grep -c "Affected files"
# Should be: 0

# Verify NO technical notes section
gh issue view <N> --json body | jq -r '.body' | grep -c "Technical Notes"
# Should be: 0
```

---

### T2: Create issue from vague description (lean format)

**Input:**
```
/issue-creator Something is broken
```

**Expected:**
- [ ] Output does NOT show `⚠ Could not identify affected files` (that message is removed)
- [ ] Issue is created with type classified (likely `bug` with low confidence)
- [ ] Issue body has acceptance criteria (even if generic)
- [ ] Issue body has NO affected files section

---

### T3: Normalize a messy issue (structure-only)

**Setup:**
```bash
gh issue create --title "login broken on mobile" --body "the login doesn't work on phones. it just spins forever."
# Note the issue number
```

**Input:**
```
/issue-creator <N>
```

**Expected:**
- [ ] Output shows `● Fetching issue #N...`
- [ ] Output does NOT show `● Scanning codebase for context...` (no scan)
- [ ] Output shows `◆ Normalization Preview` with `+` prefixed added fields and `=` preserved fields
- [ ] Preview does NOT contain a `Files:` line
- [ ] Confidence scores shown for Type and Criteria
- [ ] Backup comment posted BEFORE body edit (verify in GitHub)
- [ ] Backup comment contains original body in `<details>` block
- [ ] Issue body updated with template structure
- [ ] Issue body does NOT contain `## Context` or `## Technical Notes`
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

# Verify NO affected files
gh issue view <N> --json body --jq '.body' | grep -c "Affected files"
# Should be: 0
```

---

### T4: Normalize already-normalized issue (skip)

**Setup:** Use the issue from T3 (already normalized).

**Input:**
```
/issue-creator <N>
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
/issue-creator <N>
```

**Expected:**
- [ ] Output shows `⚠ Issue #N has a security label (security). Skipping normalization.`
- [ ] Output shows `To override: /issue-creator N --force`
- [ ] No backup comment posted
- [ ] No body edits made

---

### T6: Force normalize security-labeled issue

**Input:**
```
/issue-creator <N> --force
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
/issue-creator <N> --dry-run
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
/issue-creator Test issue
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
/issue-creator 99999
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
/issue-creator <N>
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
/issue-creator The login redirect keeps looping
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
/issue-creator Add dark mode support
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
