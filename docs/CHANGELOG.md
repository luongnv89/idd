# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-03-21

### Added
- `/issue-creator` skill — create and normalize GitHub issues
  - Single issue creation from text descriptions
  - Issue normalization (restructure existing issues into standard template)
  - Batch creation from multi-item input
  - Image upload and embedding in issue descriptions
  - Security issue detection (skip normalization for CVE/vulnerability labels)
  - Confidence scoring for type classification and acceptance criteria
- `/issue-resolver` skill — resolve issues through a 7-step pipeline (Fetch → Branch → Research → Plan → Execute → Verify → Ship)
  - Structure-only auto-normalize before resolution
  - Single authoritative codebase scan in Research step
- `/issue-triage` skill — backlog analysis with keyword-based codebase scanning for dependency detection, priority suggestions, stale issue flagging
  - Triage results persisted to `.gitissue/triage.json` for cross-session access
  - View mode renders cached report without GitHub API calls
  - Per-issue scan timeout (`triage.scan_timeout_per_issue`, default 30s)
- `/init-gitissue` skill — auto-detect project language/framework and generate `.gitissue.yml`
- Lean issues architecture — issues contain only human intent (type, description, acceptance criteria); codebase analysis performed by consumer skills at execution time
- IDD methodology documentation
- Terminal output style guide (DESIGN.md)
- Configuration schema documentation with Mermaid diagrams
- Integration test framework (Sprint 1-3 test suites)
- SVG terminal screenshots in README
- CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md
- GitHub issue and PR templates
- `.gitissue/` directory convention for persistent skill state
