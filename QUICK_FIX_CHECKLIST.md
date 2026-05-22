# Quick Fix Checklist: Subagent Type Error

## ✓ What was fixed

The `/issue-resolver` skill now documents the **correct Agent invocation** for all subagents in Steps 1-4 (Research, Plan, Implement, QA).

**The error:** `Agent type 'code-reviewer' not found`
**The cause:** Skills were using `subagent_type: "code-reviewer"` (not a registered type)
**The solution:** Use `subagent_type: "general-purpose"` and pass the shared agent prompt

---

## ✓ Files modified

```
src/skills/issue-resolver/SKILL.md
  ├─ Step 1: Research — added Agent() invocation
  ├─ Step 2: Plan — added Agent() invocation
  ├─ Step 3: Implement — added Agent() invocation
  └─ Step 4: QA — added Agent() invocation + clarification

src/skills/issue-pr-review/SKILL.md
  ├─ Cycle 1: Initial review — added Agent() invocation
  └─ Confirmation pass — added Agent() invocation
```

---

## How to deploy

### Option 1: Rebuild (if using build.py)

```bash
cd /Users/montimage/buildspace/luongnv89/idd
python scripts/build.py
```

This regenerates:
- `dist/plugin/skills/issue-resolver/SKILL.md`
- `dist/plugin/skills/issue-pr-review/SKILL.md`
- `dist/skills/issue-resolver/SKILL.md`
- `dist/skills/issue-pr-review/SKILL.md`

### Option 2: Direct use (if importing from src/)

If your pi agent loads skills directly from `src/`, no rebuild needed — the fixes are already active.

---

## How to verify the fix

**Test resolve:**
```bash
/issue-resolver 42
```

Expected: Should pass Step 4 (QA) without the agent type error.

**Test PR review:**
```bash
/issue-pr-review 87
```

Expected: Should complete review cycles without the agent type error.

**Auto-pilot test:**
```bash
/auto-pilot --limit 2
```

Expected: Should triage, resolve, and review issues without agent type errors.

---

## Reference

- `FIX_SUBAGENT_TYPE_ERROR.md` — Detailed explanation of the problem, solution, and pattern
- `src/shared/agents/*.md` — Each shared agent documents the correct Agent() parameters (see "Agent Tool Parameters" section)

---

## Key takeaway

When spawning a subagent from a shared agent file:

```python
# ✗ DON'T
Agent(subagent_type: "code-reviewer")

# ✓ DO
Agent(
  description: "Review PR #N",
  prompt: <code-reviewer.md prompt>,
  subagent_type: "general-purpose"
)
```

The shared agent **file name** (`code-reviewer.md`) is NOT a registered agent type. Always use `general-purpose` and embed the prompt.
