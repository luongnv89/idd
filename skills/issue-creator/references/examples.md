# /issue-creator — Examples

Full example runs for batch creation and vague-description scenarios.

## Example: Batch from a planning document

**User says:** `/issue-creator` followed by:
```
Here are the items from our sprint planning:
1. Fix the Safari checkout redirect bug — payments fail on iOS Safari
2. Add dark mode toggle to the settings page
3. Refactor auth middleware to support OAuth2
```

1. Detect → 3 items from numbered list
2. Preview table → 3 rows with types and effort estimates
3. Duplicates → none found
4. Approval:
   ```
   ● Parsing input...
     Found 3 items in input

   ◆ Batch Preview
   ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
     #  │ Type        │ Title                              │ Effort
     ───┼─────────────┼────────────────────────────────────┼───────
     1  │ bug         │ Fix Safari checkout redirect        │ S
     2  │ feature     │ Add dark mode toggle                │ M
     3  │ improvement │ Refactor auth middleware for OAuth2  │ L

   Create 3 issues? [A]ll / [e]dit / [c]ancel
   ```
5. On "All" → create each → `✓ 3/3 issues created`

---

## Example: Create from a vague description

**User says:** `/issue-creator the checkout page is broken on Safari`

1. Parse → keywords: "checkout", "broken", "Safari"; type: bug
2. Classify → bug (high confidence)
3. Duplicates → none found
4. Generate → populates bug.md template with Safari-specific acceptance criteria
5. Preview:
   ```
   ◆ Issue Preview
   ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
     Type:     bug (high)
     Title:    Fix checkout page broken on Safari
     Labels:   bug, checkout
     Criteria: 3 acceptance criteria generated (medium)

   Create issue? [Y/n]
   ```
6. On confirmation → `gh issue create` → `✓ Created issue #15`

