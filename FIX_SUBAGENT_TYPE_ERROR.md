# Fix: Subagent Type Error in IDD Skills

## Problem

When using `/issue-resolver` to resolve issues, the QA step (Step 4) was failing with:

```
Error: Agent type 'code-reviewer' not found. Available agents: claude, claude-code-guide, Explore, general-purpose, Plan, statusline-setup
```

This error occurred because the skill was trying to spawn an Agent with `subagent_type: "code-reviewer"`, but `code-reviewer` is **not a registered agent type** — it's a **shared agent file** that contains prompt instructions.

## Root Cause

Per the IDD architecture:
- All subagents are defined as **shared agent files** in `src/shared/agents/`
- Each shared agent explicitly states: **"Do NOT set `subagent_type` — use the default general-purpose agent"**
- The skill SKILL.md files were describing the architecture but not showing the correct Agent() invocation syntax

## Solution

Updated three SKILL.md files to document the correct Agent invocation pattern:

### 1. `/issue-resolver` (src/skills/issue-resolver/SKILL.md)

Added proper Agent() call signatures for all four subagent spawns:

**Step 1 — Research:**
```python
Agent(
  description="Research issue #N",
  prompt=<codebase-researcher.md prompt with {variables} replaced>,
  subagent_type="general-purpose"  # NOT "codebase-researcher"
)
```

**Step 2 — Plan:**
```python
Agent(
  description="Plan for issue #N",
  prompt=<synthesizer.md prompt with {variables} replaced>,
  subagent_type="general-purpose"  # NOT "synthesizer"
)
```

**Step 3 — Implement:**
```python
Agent(
  description="Implement issue #N",
  prompt=<implementer.md prompt with {variables} replaced>,
  subagent_type="general-purpose"  # NOT "implementer"
)
```

**Step 4 — QA:**
```python
Agent(
  description="Review cycle N",
  prompt=<code-reviewer.md prompt with {variables} replaced>,
  subagent_type="general-purpose"  # NOT "code-reviewer"
)
```

### 2. `/issue-pr-review` (src/skills/issue-pr-review/SKILL.md)

Added proper Agent() call signatures for code-reviewer spawns:

**Cycle 1 — Initial review:**
```python
Agent(
  description="Review PR #N",
  prompt=<code-reviewer.md prompt with {variables} replaced>,
  subagent_type="general-purpose"  # NOT "code-reviewer"
)
```

**Confirmation pass:**
```python
Agent(
  description="Confirmation review for PR #N",
  prompt=<code-reviewer.md prompt with {variables} replaced>,
  subagent_type="general-purpose"  # NOT "code-reviewer"
)
```

## Key Pattern

**NEVER do this:**
```python
Agent(subagent_type: "code-reviewer")  # ✗ WRONG — not a registered type
Agent(subagent_type: "synthesizer")    # ✗ WRONG — not a registered type
Agent(subagent_type: "implementer")    # ✗ WRONG — not a registered type
```

**ALWAYS do this:**
```python
Agent(
  description: "...",
  prompt: <shared agent file contents>,
  subagent_type: "general-purpose"  # ✓ CORRECT — built-in type
)
```

## Verification

All shared agents in `src/shared/agents/` include explicit guidance:

```markdown
## Agent Tool Parameters

Agent tool parameters:
  description: "..."
  prompt: <contents of the Prompt section below, with {variables} replaced>

Do **NOT** set `subagent_type` — use the default general-purpose agent.
```

This applies to:
- ✓ codebase-researcher.md
- ✓ synthesizer.md
- ✓ implementer.md
- ✓ code-reviewer.md

## Files Modified

- `src/skills/issue-resolver/SKILL.md` — Added Agent() invocation patterns for Steps 1-4
- `src/skills/issue-pr-review/SKILL.md` — Added Agent() invocation patterns for Cycle 1 and Confirmation pass

## Next Steps

1. **Rebuild the skills** (if using build.py):
   ```bash
   python scripts/build.py
   ```

2. **Test the fix** by resolving an issue:
   ```bash
   /issue-resolver 42
   ```

3. **Auto-pilot mode:**
   ```bash
   /auto-pilot --limit 3
   ```

The error should no longer occur. QA cycles will now spawn code-reviewer agents using the correct `general-purpose` type with the code-reviewer prompt embedded.
