# Summary Report Templates

Templates for the Step 7 summary report and the expected inline pipeline output. SKILL.md keeps the contract short; this file holds the full templates.

## Summary — Clean PR

```
◆ PR Review: #{pr_number} (pass {N} — clean)
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Script pre-pass:   ✓ lint/format auto-fixed ({auto_fixed} files)
  Code review:       ✓ pass
  Tests:             ✓ pass ({count} passed)
  CI status:         ✓ pass ({checks_count} checks passed)
  Issues fixed:      ✓ {total_fixed} total across {cycles} cycles
  Issues noted:      ○ {note_count} (medium, not blocking)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            PASS

  {pr_url}
```

## Summary — PR With Remaining Issues

```
◆ PR Review: #{pr_number} (pass {max} — issues remain)
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  Code review:       ⚠ warn ({N} issues remain)
  Tests:             ✓ pass
  CI status:         ✓ pass
  Issues fixed:      ✓ {total_fixed} total across {max} cycles
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            WARN (manual review recommended)

  Remaining:
    ● [category] description (file:line)

  {pr_url}
```

## Auto-Merge (auto mode only)

If the PR is clean AND `--auto` is set:

```bash
gh pr merge {N} --squash --delete-branch
```

Append to the report on success:

```
  Merge:             ✓ pass (squash merged)
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            MERGED

  ✓ PR #{N} merged — branch {branch_name} deleted
```

On merge failure:

```
  Merge:             ✗ fail ({reason})
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Result:            BLOCKED (manual merge required)
```

In interactive mode: never auto-merge — just report status.

## Expected Inline Output

A clean review prints the 7-step tracker and a summary:

```
  [1/7] PR Info       ✓ #87 fix(auth): resolve redirect (#42)
  [2/7] Script Pre    ✓ 3 lint fixes applied
  [3/7] Review        ✓ 0 critical, 1 medium (note)
  [4/7] Tests         ✓ 12 passed
  [5/7] CI            ✓ all checks green
  [6/7] Fix           ○ skipped — nothing to fix
  [7/7] Summary       ✓ PR ready to merge

  ✓ PR #87 passed review (soft-pass: 1 medium note)
```
