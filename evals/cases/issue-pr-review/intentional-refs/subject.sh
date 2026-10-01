#!/usr/bin/env bash
# Intentional partial delivery (#493): a `Refs #N` PR body that declares its
# deferred acceptance criteria passes; one that defers every criterion fails.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"

gh auth status >/dev/null
gh pr view 9 --json number,title,body,state > "$EVAL_OUT/pr-view.json"

write_body() {
  cat <<EOF
Refs #42

## Summary

Ship the Claude Code plugin; the Codex plugin is deferred, so #42 stays open.

## Decision Record

- **Root cause:** no plugin distribution path.
- **Options considered:** Option 1 — both plugins; Option 2 — Claude Code first
- **Options rejected:** Option 1 — Codex mechanism not yet documented
- **Selected option:** Option 2 — Claude Code first
- **Residual risk:** none identified

Analyzed at: \`feat/42-plugin @ abc1234\` (2026-09-30)

## Acceptance Criteria Verification

| Criterion | Status | Evidence |
|-----------|--------|----------|
$1
| Codex plugin installs | unverified | Deferred to a later PR; #42 stays open for it |
EOF
}

write_body "| Claude Code plugin installs | pass | tests/test-plugin.sh |" > "$EVAL_OUT/pr-body.md"
write_body "| Claude Code plugin installs | unverified | deferred as well |" > "$EVAL_OUT/pr-body-all-deferred.md"
