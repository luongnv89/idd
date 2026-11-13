# Merge strategy check — /init-idd

The optional post-write check SKILL.md *Step 3* points at. It reads two
repository settings and judges them against `review.merge_method` in the file
just written. It never changes a repository setting and never changes the run's
`Result`.

## When it runs

1. Run it only after the written config passed *Validate the written config*.
2. Run `which gh`. If it fails, print `○ Merge strategy check skipped — gh not installed` and continue.
3. Run `gh auth status`. If it fails, print `○ Merge strategy check skipped — gh not authenticated` and continue.

## The two reads

Run **both** merge preflight reads from `references/docs/platform-github.md` — the
strategy allow-flags and the hand-merge message source. They answer different
questions, and neither substitutes for the other:

```bash
gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed
gh api repos/{owner}/{repo} --jq '{squash_merge_commit_message, merge_commit_message}'
```

The second read uses the REST endpoint on purpose: `gh repo view --json` has no
such field.

## The method

`{method}` is `review.merge_method` in the written file: `squash`, `merge` or
`rebase`.

**One allowed method.** When the strategy read shows exactly one allowed
method, it differs from `{method}`, and this run generated the value (a create
or an overwrite, not a value a merge preserved), rewrite that one line of
`.idd.yml` to the allowed method, re-run *Validate the written config*, and
print:

```
○ review.merge_method set to {allowed} — the only method this repo allows
```

Otherwise leave the value alone.

## Findings

Check each condition independently.

**Method not allowed.** If the repo does not allow `{method}`, print:

```
⚠ review.merge_method is {method}, but this repo allows only: {allowed}

To fix:  set review.merge_method in .idd.yml to one of: {allowed}
```

**Rebase.** If `{method}` is `rebase`, print:

```
⚠ review.merge_method is rebase — tracker-only: no commit carries the PR body. See references/docs/idd-methodology.md.

To fix:  set review.merge_method in .idd.yml to squash or merge
```

**Hand merge.** If `{method}` is `squash` or `merge` and that method's message
source (`squash_merge_commit_message` / `merge_commit_message`) is any value
other than `PR_BODY`, print the note below. It is a note, not a warning: IDD's
own merge passes the PR body as the commit body, so the durable record lands
whatever this setting says. Only a merge made by hand in the GitHub UI loses
it. GitHub's default is not `PR_BODY`, so this note fires on most fresh repos:

```
○ A merge made by hand in the GitHub UI will not carry the PR body ({field} is {value}). IDD's own merge passes it.
```

**Unread setting.** If the strategy read fails, print `○ Merge strategy check
skipped — {reason}` and continue. If the strategy read succeeds but the message
read does not answer (404, insufficient permission, or the field is absent from
the response), print `○ Hand-merge message source unread — {reason}` and
continue. Never report an unread setting as satisfied.

## Report row

Print one `Merge settings:` row in the *Step 4 — Report* block:

| Outcome | Row |
|---|---|
| The strategy read ran; `{method}` is `squash` or `merge` and the repo allows it | `✓ {method} allowed`, plus `; hand merge drops the PR body` when the note fired |
| A warning fired | `⚠ warn ({method} not allowed)` or `⚠ warn (rebase is tracker-only)` |
| Check skipped (no `gh`, not authenticated, unread strategy) | `○ skip ({reason})` |

A warning or a skip leaves `Result` unchanged — the config was still written and
validated. Name each warning's `To fix:` line on the `Next action:` row; the
user edits `.idd.yml`, this skill does not change a repository setting.
