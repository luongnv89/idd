---
name: init-gitissue
description: "Generate a project-specific .gitissue.yml by auto-detecting language, framework, test runner, and repo size. Use when asked to init gitissue, setup gitissue, configure gitissue, first time setup, /init-gitissue, or to set up IDD on a new repo. Don't use for editing an existing .gitissue.yml (edit directly), creating GitHub issues (use /issue-creator), or general git/repo initialization like git init or npm init."
license: MIT
compatibility: Requires git. No GitHub CLI or authentication needed — generates a local config file only.
effort: low
metadata:
  version: 0.3.1
  creator: Luong NGUYEN <luongnv89@gmail.com>
---

# /init-gitissue

Generate a project-specific `.gitissue.yml` by auto-detecting the repo’s stack and test runner.

## Prerequisites

Before any operation, verify the environment. On failure, output the exact error from `references/error-messages.md` and stop.

1. Confirm git repository: `git rev-parse --git-dir`
2. Confirm the working directory is the repo root or a subdirectory with write access
3. Confirm the target `.gitissue.yml` does not already contain custom values you need to preserve

## Workflow

- Detect the language, framework, and test runner.
- Inspect the repository size and structure.
- Write a repo-specific `.gitissue.yml` with sensible defaults.
- See `references/init-runbook.md` for the detection rules and the config fields that matter most.

## When to Use

- Use this skill on a new repo or whenever the gitissue config needs a first pass.

## Instructions

1. Detect manifests, language, framework, and test tooling.
2. Preserve any existing custom values that should not be overwritten.
3. Write a compact `.gitissue.yml` tailored to the repository.

## Acceptance Criteria

- [ ] A valid `.gitissue.yml` is written in the repo root.
- [ ] The config reflects the detected stack and test runner.
- [ ] The file stays small and repository-specific.

## Edge Cases

- Existing customized `.gitissue.yml` should be preserved or updated carefully.
- Ambiguous stacks should fall back to conservative defaults.

## Example

```text
/init-gitissue
```

Expected output: a generated `.gitissue.yml` tailored to the repo.
