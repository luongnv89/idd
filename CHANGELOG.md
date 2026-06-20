# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!-- gitissue:normalized v1 -->

## [v0.15.0] — 2026-06-20

### Features
- **issue-resolver:** offer interactive worktree resolution (#128) @luongnv89
- **issue-creator:** cache model data at skill level with dated filename (#127) @luongnv89
- **issue-creator:** always suggest one OpenAI + one Anthropic model (#122) @luongnv89

### Bug Fixes
- **issue-creator:** stream image base64 via stdin to avoid ARG_MAX (#126) @luongnv89

### Other Changes
- **landing:** highlight model and thinking level on issue create @luongnv89

**Full Changelog:** https://github.com/luongnv89/idd/compare/v0.14.0...v0.15.0

## [v0.14.0] — 2026-06-15

### Features
- **issue-creator:** add model suggestion with cache management (#119) @luongnv89

### Bug Fixes
- **nav:** repair broken landing-page nav links and deploy changelog (#120) @luongnv89
- **nav:** unify navigation bar across all pages (#115) @luongnv89

### Other Changes
- **issue-creator:** enable model_suggestion by default (#121) @luongnv89
- **config:** add .gitissue.yml with balanced merge default @luongnv89
- **docs:** format CSS, unify footer structure (#116) @luongnv89

**Full Changelog:** https://github.com/luongnv89/idd/compare/v0.13.0...v0.14.0
