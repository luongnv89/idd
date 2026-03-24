# Issue Resolver

> Resolve a GitHub issue end-to-end — from open issue to atomic PR in 8 steps.

## Highlights

- **Full pipeline**: Fetch → Guards → Normalize → Branch → Research → Plan → Execute → Test → Verify → Ship
- **Dedicated test step**: Writes unit tests and e2e tests (when feasible) for all new features and changes
- **Build verification**: Compiles/builds the project before running tests to catch errors early
- **Auto-normalization**: Enriches unstructured issues with codebase context before resolving
- **Safety guards**: Warns on assigned issues, blocking labels, and prompt injection in issue bodies
- **Configurable gates**: Auto-proceed or pause for approval at the plan phase
- **Atomic PRs**: Creates a single PR with "Closes #N", summary, approach, files changed, and test results

## When to Use

| Say this... | Skill will... |
|---|---|
| `/issue-resolver 42` | Resolve issue #42 through the full 8-step pipeline |
| "fix issue #42" | Fetch, research, implement, test, and ship a PR for #42 |
| "work on #15" | Branch, implement changes, write tests, verify, create PR closing #15 |
| "implement the auth fix in issue 7" | Research the issue, plan the fix, execute, write tests, and ship |

## How It Works

```mermaid
graph TD
    A["[1/8] Fetch + Guards + Normalize"] --> B["[2/8] Branch"]
    B --> C["[3/8] Research"]
    C --> D["[4/8] Plan"]
    D --> E["[5/8] Execute"]
    E --> F["[6/8] Test"]
    F --> G["[7/8] Verify"]
    G --> H["[8/8] Ship PR"]
    style A fill:#4CAF50,color:#fff
    style H fill:#2196F3,color:#fff
```

## Installation

Install via [npx (Vercel)](https://www.npmjs.com/package/skills):

```bash
npx skills add https://github.com/luongnv89/idd --skill issue-resolver
```

Or via [agent-skill-manager (asm)](https://www.npmjs.com/package/agent-skill-manager):

```bash
asm install https://github.com/luongnv89/idd --skill issue-resolver
```

## Usage

```
/issue-resolver 42
```

## Resources

| Path | Description |
|---|---|
| `references/error-messages.md` | Complete error catalog with triggers and exact output for every failure scenario |

## Output

A pull request on GitHub linked to the resolved issue, containing:
- Issue summary and approach taken
- Table of files changed
- Test results
- Acceptance criteria checklist
- `Closes #N` for automatic issue closure on merge
