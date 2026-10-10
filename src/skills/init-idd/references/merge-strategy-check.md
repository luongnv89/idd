# Merge strategy check — /init-idd

The optional post-write check SKILL.md *Step 3* points at. It reads two
repository settings and warns when either one defeats the IDD durable-memory
binding (B1). It never changes a setting and never changes the run's `Result`.

## When it runs

1. Run it only after the written config passed *Validate the written config*.
2. Run `which gh`. If it fails, print `○ Merge strategy check skipped — gh not installed` and continue.
3. Run `gh auth status`. If it fails, print `○ Merge strategy check skipped — gh not authenticated` and continue.

## The two reads

Run **both** squash-merge preflight reads from `docs/platform-github.md` — the
strategy allow-flags and the squash-commit message source. They answer
different questions, and neither substitutes for the other:

```bash
gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed
gh api repos/{owner}/{repo} --jq '{squash_merge_commit_title, squash_merge_commit_message}'
```

The second read uses the REST endpoint on purpose: `gh repo view --json
squashMergeCommitMessage` returns `Unknown JSON field` — that selector cannot
reach the sub-setting.

## Warnings

Check each condition independently. A repo can fail both, and reporting only the
strategy is the blind spot that hid the second condition for the whole life of
the project.

**Strategy.** If `squashMergeAllowed` is false, or `mergeCommitAllowed` or
`rebaseMergeAllowed` is true, print:

```
⚠ Merge strategy is not squash-only — squash-merge is required for IDD durable-memory (B1 binding). See docs/idd-methodology.md.
```

**Squash commit message.** If `squash_merge_commit_message` is any value other
than `PR_BODY`, print the warning below. The strategy can be squash-only and the
B1 binding still be defeated: the squash commit then carries the list of commit
subjects instead of the PR body, so the Decision Record never reaches git
history (issue #295). GitHub's default is `COMMIT_MESSAGES`, so this warning
fires on most fresh repos:

```
⚠ Squash commit message is {value}, not PR_BODY — the PR body will not reach git
  history, defeating the B1 durable-memory binding. See docs/idd-methodology.md.

To fix:  gh api -X PATCH repos/{owner}/{repo} -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY
```

The remedy sets both flags because GitHub accepts only four title/message
combinations, and `PR_BODY` pairs solely with `PR_TITLE`. Sending the message
alone against the common default `COMMIT_OR_PR_TITLE` fails with HTTP 422
`invalid_squash_commit_setting_combo`.

**Unread setting.** If the strategy read fails, print `○ Merge strategy check
skipped — {reason}` and continue. If the strategy read succeeds but the settings read does not
answer (404, insufficient permission, or the field is absent from the response),
print `○ Squash commit message check skipped — {reason}` and continue. Never
report the setting as satisfied: an unread setting is the assumption this check
exists to remove.

## Report row

Print one `Merge settings:` row in the *Step 4 — Report* block:

| Outcome | Row |
|---|---|
| Both reads ran; squash-only and `PR_BODY` | `✓ squash-only, PR_BODY` |
| A read ran and a warning fired | `⚠ warn ({not squash-only and/or message is {value}})` |
| Check skipped (no `gh`, not authenticated, unread setting) | `○ skip ({reason})` |

A warning or a skip leaves `Result` unchanged — the config was still written and
validated. Name each warning's `To fix:` command on the `Next action:` row; the
user runs it, this skill does not.
