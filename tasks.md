# Tasks — gitissue / IDD

Generated from PRD v1.1 and review decisions on 2026-03-20.

## Sprint 1: Foundation (v0.1.0) — Target: 2026-04-02

### Task 1.1: Project scaffolding
- **Status**: DONE
- **Priority**: P0 (blocker)
- **Description**: Initialize the repo with the correct structure, config files, and documentation.
- **Deliverables**:
  - [x] `CLAUDE.md` — project conventions for AI agents (reference DESIGN.md for output style)
  - [x] `README.md` — quick-start guide, installation, usage
  - [x] `LICENSE` — MIT
  - [x] `.gitissue.yml` schema documentation
  - [x] Skill folder structure: `skills/create-issue/`, `skills/resolve-issue/`, `skills/triage-issues/`, `skills/init-gitissue/`
- **Notes**: Each skill is a self-contained, isolated component in its own folder. Use `/skill-creator` for building each skill.
- **Depends on**: —

### Task 1.2: Issue templates (F3)
- **Status**: DONE
- **Priority**: P0 (blocker for F1, F2)
- **Description**: Create the 3 default issue templates: bug, feature, improvement. Templates must render cleanly in GitHub's web UI.
- **Deliverables**:
  - [x] `skills/create-issue/templates/bug.md`
  - [x] `skills/create-issue/templates/feature.md`
  - [x] `skills/create-issue/templates/improvement.md`
  - [x] Normalization marker: `<!-- gitissue:normalized v1 -->`
  - [x] Template sections: Type, Context (affected files, current behavior, related issues), Description, Acceptance Criteria, Technical Notes, Metadata
  - [x] Reporter Context blockquote for preserved original text
  - [x] Confidence markers in parentheses: `(high confidence)`, `(needs review)`
- **Notes**: See DESIGN.md "GitHub Markdown Rendering" section for rendering specs.
- **Depends on**: —

### Task 1.3: `.gitissue.yml` config (F5)
- **Status**: DONE
- **Priority**: P0 (blocker)
- **Description**: Define the config schema with sensible defaults. Config must work as zero-config (all defaults applied when no file exists).
- **Deliverables**:
  - [x] Config schema with all fields documented
  - [x] Default values for all settings
  - [x] Include `resolve.test_timeout: 300` in schema
  - [x] Config validation with line-number error reporting
  - [x] First-run hint: `○ First run — using default config. Run /init-gitissue to customize.`
- **Notes**: Config is loaded ONCE at the start of every skill, not re-read at each step.
- **Depends on**: —

### Task 1.4: `/create-issue` skill (F1)
- **Status**: DONE
- **Priority**: P1
- **Description**: Build the `/create-issue` skill for creating new structured issues from text/screenshot/batch input. Use `/skill-creator`.
- **Deliverables**:
  - [x] `skills/create-issue/SKILL.md`
  - [x] `skills/create-issue/references/error-messages.md`
  - [x] Single issue creation from text description
  - [x] Codebase scanning for relevant files (keywords, component names, error messages)
  - [x] Auto-classification: bug/feature/improvement
  - [x] Template population with all sections
  - [x] Auto-label suggestion
  - [x] `gh issue create --json` for reliable API interaction
  - [x] Duplicate issue detection (title + description similarity warning)
  - [x] Terminal output per DESIGN.md mockups (symbol vocabulary, progress, sections)
  - [x] Rich error format (what went wrong + fix command + docs link)
  - [x] Empty state: `⚠ Could not identify affected files. Issue created with manual-review flag.`
- **Acceptance Criteria**: All F1 acceptance criteria from PRD met.
- **Depends on**: Task 1.2, Task 1.3

### Task 1.5: `/create-issue N` normalization skill (F2)
- **Status**: DONE
- **Priority**: P1
- **Description**: Add normalization mode to the create-issue skill. Enriches existing unstructured issues with codebase context.
- **Deliverables**:
  - [x] Normalization detection via `<!-- gitissue:normalized v1 -->` marker
  - [x] Security label check — skip for 'security', 'CVE', 'vulnerability' unless `--force`
  - [x] Normalization preview with confidence scores (high/medium/low)
  - [x] `--dry-run` flag support
  - [x] Backup comment with original body in `<details>` block — posted and verified BEFORE body edit
  - [x] Abort normalization if backup comment fails
  - [x] Issue body update via `gh issue edit`
  - [x] Normalization comment noting what was added
  - [x] Terminal output per DESIGN.md normalize mockup
  - [x] Already-normalized empty state: `✓ Issue #42 is already normalized (v1, date). No changes needed.`
- **Acceptance Criteria**: All F2 acceptance criteria from PRD met. Data safety: backup always before edit.
- **Depends on**: Task 1.4

### Task 1.6: Phase 1 integration testing
- **Status**: DONE
- **Priority**: P1
- **Description**: Create scripted smoke tests for create-issue and normalization flows.
- **Deliverables**:
  - [x] `tests/` directory with shell scripts
  - [x] Test: create issue from one-sentence description → verify structured issue created
  - [x] Test: normalize messy issue → verify backup comment exists, body enriched
  - [x] Test: normalize already-normalized issue → verify skip
  - [x] Test: normalize security-labeled issue → verify skip with warning
  - [x] Test: --dry-run → verify no edit made
  - [x] Test: gh auth failure → verify rich error message
  - [x] Test: issue not found → verify rich error message
  - [x] Test: normalization marker false positive (`<!-- gitissue:normalized v1 -->` in regular text)
- **Notes**: Mock inputs for screenshot testing. Reference test plan at `~/.gstack/projects/luongnv89-idd/montimage-main-test-plan-*.md`.
- **Depends on**: Task 1.4, Task 1.5

---

## Sprint 2: Resolution (v0.2.0) — Target: 2026-04-16

### Task 2.1: `/resolve-issue N` skill (F4)
- **Status**: TODO
- **Priority**: P1
- **Description**: Build the full resolution pipeline skill: fetch → guards → normalize → branch → research → plan → execute → verify → ship.
- **Deliverables**:
  - [ ] `skills/resolve-issue/SKILL.md`
  - [ ] `skills/resolve-issue/references/error-messages.md`
  - [ ] Guard checks: assignment + blocking labels → warn before proceeding
  - [ ] Auto-normalization when `auto_normalize: true`
  - [ ] Branch creation: `issue-N/short-description`
  - [ ] Research phase: read affected files, trace dependencies (using Agent tool for parallelism)
  - [ ] Plan phase: local only, approval gate support (auto / comment-and-wait)
  - [ ] Execute phase: write code, write tests, atomic commits (max_commits check)
  - [ ] Verify phase: run tests with timeout (`resolve.test_timeout`), check acceptance criteria
  - [ ] Ship phase: `gh pr create` with "Closes #N", summary, approach, files changed
  - [ ] Prompt injection boundary: issue body treated as untrusted data
  - [ ] Terminal output per DESIGN.md resolve mockup (step counter [1/7])
  - [ ] Static sequential progress (each step prints new line)
  - [ ] Error: tests fail → abort PR, show failure details
  - [ ] Error: tests timeout → abort, report timeout
  - [ ] Error: branch exists → prompt: continue or fresh
- **Acceptance Criteria**: All F4 acceptance criteria from PRD met.
- **Depends on**: Task 1.4, Task 1.5

### Task 2.2: Batch issue creation (F7)
- **Status**: TODO
- **Priority**: P2
- **Description**: Add batch mode to `/create-issue` — extract multiple issues from text, screenshots, or documents.
- **Deliverables**:
  - [ ] Multi-item extraction with boundary detection
  - [ ] Screenshot/image input support
  - [ ] Preview table before creating: `# | Type | Title | Effort`
  - [ ] User can approve all, edit individual items, or cancel
  - [ ] Partial failure handling: `✓ 3/5 created, ⚠ 2 failed [retry hint]`
  - [ ] Rate limit respect with backoff
- **Notes**: Leverage patterns from `github-issue-creator` skill.
- **Depends on**: Task 1.4

### Task 2.3: Phase 2 integration testing
- **Status**: TODO
- **Priority**: P1
- **Description**: Extend test suite for resolve pipeline and batch creation.
- **Deliverables**:
  - [ ] Test: resolve issue end-to-end → verify branch, code, tests, PR created with "Closes #N"
  - [ ] Test: resolve with assignment guard → verify warning
  - [ ] Test: resolve with blocking label → verify warning
  - [ ] Test: tests fail during verify → verify no PR created
  - [ ] Test: branch exists → verify prompt
  - [ ] Test: prompt injection in issue body → verify agent follows pipeline only
  - [ ] Test: approval gate pause (mocked)
  - [ ] Test: batch create from document → verify preview table + all issues created
- **Depends on**: Task 2.1, Task 2.2

---

## Sprint 3: Triage & Polish (v0.3.0) — Target: 2026-04-30

### Task 3.1: `/triage-issues` skill (F6)
- **Status**: TODO
- **Priority**: P2
- **Description**: Build the triage skill: dependency analysis, priority suggestions, stale detection, execution order.
- **Deliverables**:
  - [ ] `skills/triage-issues/SKILL.md`
  - [ ] `skills/triage-issues/references/error-messages.md`
  - [ ] Fetch all open issues via `gh issue list --json` (bodies included, avoid N+1)
  - [ ] Dependency detection via shared affected files and module dependencies
  - [ ] Dependency table: `# | Issue | Pri | Blocks | Status`
  - [ ] Topological sort for execution order
  - [ ] Parallelizable issue identification
  - [ ] Stale issue detection (> configured threshold)
  - [ ] Circular dependency warning
  - [ ] `--limit N` flag for large backlogs
  - [ ] Terminal output per DESIGN.md triage mockup (table + recommendations)
  - [ ] Empty state: `○ No open issues found. Nothing to triage!`
- **Acceptance Criteria**: All F6 acceptance criteria from PRD met.
- **Depends on**: Task 1.3

### Task 3.2: `/init-gitissue` skill (F9)
- **Status**: TODO
- **Priority**: P2
- **Description**: Build the config generator skill: scan repo, suggest defaults, write `.gitissue.yml`.
- **Deliverables**:
  - [ ] `skills/init-gitissue/SKILL.md`
  - [ ] Detect project language, framework, test runner
  - [ ] Detect existing `.github/ISSUE_TEMPLATE/` templates
  - [ ] Suggest defaults based on repo size and conventions
  - [ ] Write `.gitissue.yml` with inline comments explaining each setting
  - [ ] Report setup summary
- **Depends on**: Task 1.3

### Task 3.3: Confidence scoring (F8)
- **Status**: TODO
- **Priority**: P2
- **Description**: Add confidence indicators to all auto-enriched fields during normalization.
- **Deliverables**:
  - [ ] Confidence levels: high (direct match), medium (keyword inference), low (best guess)
  - [ ] Display in normalization preview: `+ Files: auth.py (high), config.py (medium)`
  - [ ] Low-confidence fields marked `(needs review)` in the issue body
  - [ ] Confidence displayed before applying (preview step)
- **Notes**: This is already partially specified in Task 1.5. This task formalizes and completes it.
- **Depends on**: Task 1.5

### Task 3.4: IDD documentation
- **Status**: TODO
- **Priority**: P2
- **Description**: Write the IDD methodology documentation and complete the README.
- **Deliverables**:
  - [ ] IDD methodology overview (what it is, why, how)
  - [ ] Comparison with TDD, BDD, spec-driven development
  - [ ] Quick-start guide in README
  - [ ] Full command reference
  - [ ] Configuration reference
  - [ ] Agent compatibility documentation (demonstrate with 3+ agents)
- **Depends on**: Task 2.1 (needs working resolve pipeline for demos)

### Task 3.5: Phase 3 integration testing
- **Status**: TODO
- **Priority**: P2
- **Description**: Extend test suite for triage, init, and confidence scoring.
- **Deliverables**:
  - [ ] Test: triage 10+ issues → verify dependency table and execution order
  - [ ] Test: triage with circular dependencies → verify warning
  - [ ] Test: triage with no open issues → verify empty state
  - [ ] Test: init on fresh repo → verify .gitissue.yml created
  - [ ] Test: confidence scoring → verify high/medium/low displayed correctly
- **Depends on**: Task 3.1, Task 3.2, Task 3.3

---

## Key Implementation Conventions

These apply to ALL tasks above:

1. **Use `/skill-creator`** to build each skill for consistent prompt structure
2. **Use `gh --json`** with explicit field selection for ALL GitHub CLI calls
3. **Follow DESIGN.md** for all terminal output (symbols, colors, spacing, errors, progress)
4. **Each skill is isolated** in its own folder with its own `references/error-messages.md`
5. **Config loaded once** at skill start, not re-read at each step
6. **Rich error format** for all failures: what went wrong + fix command + docs link
7. **Warm empty states** with context and next action for every "nothing found" scenario
8. **Static sequential output** — each step prints a new line, no terminal animation
