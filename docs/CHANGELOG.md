# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `/issue-triage` persistence — triage results saved to `.gitissue/triage.json` for cross-session access
- `/issue-triage view` mode — render cached triage report without GitHub API calls, with report age indicator
- `/issue-triage update` mode — explicit full re-triage with persistence
- `.gitissue/` directory convention for persistent skill state
- CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md
- GitHub issue and PR templates
- .gitignore
- Architecture and development documentation

## [0.1.0] - 2026-03-20

### Added
- `/issue-creator` skill — create and normalize GitHub issues with codebase context
  - Single issue creation from text descriptions
  - Issue normalization (enrich existing issues)
  - Batch creation from multi-item input
  - Image upload and embedding in issue descriptions
  - Security issue detection (skip normalization for CVE/vulnerability labels)
- `/issue-resolver` skill — resolve issues through a 7-step pipeline (Fetch → Branch → Research → Plan → Execute → Verify → Ship)
- `/issue-triage` skill — backlog analysis with dependency detection, priority suggestions, stale issue flagging
- `/init-gitissue` skill — auto-detect project language/framework and generate `.gitissue.yml`
- IDD methodology documentation
- Terminal output style guide (DESIGN.md)
- Configuration schema documentation
- Integration test framework
