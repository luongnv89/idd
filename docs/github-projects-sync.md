# GitHub Projects Status Sync

Shared reference for synchronizing issue status on GitHub Project boards. This is an infrastructure component — a reusable procedure that each skill includes, not a standalone skill.

## Overview

When skills perform actions (create issues, start/complete work, reprioritize), this utility syncs the corresponding status field on the repo's GitHub Project board via the GitHub Projects v2 GraphQL API (`gh api graphql`).

**Integration points:**

| Skill | Trigger | Status transition |
|-------|---------|-------------------|
| `/issue-creator` | Issue created | Add to board, set "Todo" |
| `/issue-resolver` | Branch created (Step 2) | Set "In Progress" |
| `/issue-resolver` | PR created (Step 8) | Set "Done" |
| `/issue-triage` | Priority changed | (read-only, no status change) |
| `/issue-analysis` | Analysis complete | (read-only, no status change) |

## Configuration

The `projects` section in `.gitissue.yml` controls this utility:

```yaml
projects:
  sync_enabled: true       # Enable project board sync (default: false)
  project_number: null      # Explicit project number (null = auto-detect)
  status_field: "Status"    # Name of the Status field on the board
  status_map:
    todo: "Todo"            # Status value for new issues
    in_progress: "In Progress"  # Status value when work starts
    done: "Done"            # Status value when PR is created
```

When `projects.sync_enabled` is `false` (default), all sync operations are silently skipped. Skills never block on project sync failures.

## Procedures

### 1. Discover Project

Find the GitHub Project linked to the current repository.

**If `projects.project_number` is set:**

```bash
gh api graphql -f query='
  query($owner: String!, $number: Int!) {
    organization(login: $owner) {
      projectV2(number: $number) {
        id
        title
      }
    }
  }
' -f owner="{owner}" -F number={project_number}
```

If the repo owner is a user (not an org), replace `organization` with `user`.

**If `projects.project_number` is null (auto-detect):**

```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!) {
    repository(owner: $owner, name: $repo) {
      projectsV2(first: 1) {
        nodes {
          id
          title
          number
        }
      }
    }
  }
' -f owner="{owner}" -f repo="{repo}"
```

Takes the first linked project. If no projects are found, output a note and skip:

```
○ No GitHub Project linked to this repo — skipping board sync.
  To link: create a project at https://github.com/{owner}/{repo}/projects
```

**Cache the project ID** for the duration of the skill invocation. Do not re-discover on each sync call.

### 2. Get Status Field

Retrieve the Status field ID and its option values from the project:

```bash
gh api graphql -f query='
  query($projectId: ID!) {
    node(id: $projectId) {
      ... on ProjectV2 {
        field(name: "Status") {
          ... on ProjectV2SingleSelectField {
            id
            options {
              id
              name
            }
          }
        }
      }
    }
  }
' -f projectId="{project_id}"
```

Replace `"Status"` with the value of `projects.status_field` from config.

**Cache the field ID and option IDs** for the duration of the skill invocation.

If the Status field is not found:

```
⚠ Status field "{field_name}" not found on project "{project_title}"

  To fix:  add a single-select field named "{field_name}" to the project
  Check:   https://github.com/orgs/{owner}/projects/{number}/settings
```

Skip sync for this invocation. Non-fatal.

### 3. Add Issue to Project

Add an issue to the project board (idempotent — safe to call if already added):

```bash
gh api graphql -f query='
  mutation($projectId: ID!, $contentId: ID!) {
    addProjectV2ItemById(input: {
      projectId: $projectId
      contentId: $contentId
    }) {
      item {
        id
      }
    }
  }
' -f projectId="{project_id}" -f contentId="{issue_node_id}"
```

The `issue_node_id` is the GraphQL node ID of the issue. Retrieve it via:

```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!, $number: Int!) {
    repository(owner: $owner, name: $repo) {
      issue(number: $number) {
        id
      }
    }
  }
' -f owner="{owner}" -f repo="{repo}" -F number={issue_number}
```

Returns the project item ID, needed for status updates.

### 4. Update Status

Set the status field value on a project item:

```bash
gh api graphql -f query='
  mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
    updateProjectV2ItemFieldValue(input: {
      projectId: $projectId
      itemId: $itemId
      fieldId: $fieldId
      value: { singleSelectOptionId: $optionId }
    }) {
      projectV2Item {
        id
      }
    }
  }
' -f projectId="{project_id}" -f itemId="{item_id}" -f fieldId="{status_field_id}" -f optionId="{option_id}"
```

The `option_id` is looked up from the cached status field options using the `projects.status_map` values.

If the target status value does not match any option:

```
⚠ Status value "{value}" not found in project field options

  Available options: {comma-separated list of option names}
  To fix:  update projects.status_map in .gitissue.yml to match your board
```

Skip this status update. Non-fatal.

## Graceful Degradation

Project sync is **non-blocking** for all skills. If any step fails:

1. Print a `⚠` warning with the specific error
2. Continue the skill's main pipeline without interruption
3. Never abort a skill due to project sync failure

Common failure modes and their handling:

| Failure | Output | Behavior |
|---------|--------|----------|
| `projects.sync_enabled: false` | (silent) | Skip all sync |
| No project linked to repo | `○ No GitHub Project linked...` | Skip all sync |
| Status field not found | `⚠ Status field not found...` | Skip status update |
| Status option not found | `⚠ Status value not found...` | Skip status update |
| GraphQL API error | `⚠ Project sync failed: {error}` | Skip and continue |
| Rate limit | `⚠ Project sync rate limited` | Skip and continue |
| Insufficient permissions | `⚠ Project sync requires write access` | Skip and continue |

## Skill Integration Reference

### In `/issue-creator`

After successful issue creation (Step 6 in single mode, Step 5 in batch mode):

```
● Syncing project board...
```

1. Discover project (or use cached)
2. Add issue to project
3. Update status to `projects.status_map.todo`

```
✓ Added to project "{project_title}" — Status: Todo
```

### In `/issue-resolver`

**After branch creation (Step 2):**

```
● Syncing project board...
```

1. Discover project (or use cached)
2. Add issue to project (if not already present)
3. Update status to `projects.status_map.in_progress`

```
✓ Project status: In Progress
```

**After PR creation (Step 8):**

1. Update status to `projects.status_map.done`

```
✓ Project status: Done
```

### In `/issue-triage`

No status changes. Triage is read-only with respect to the project board. Future versions may reorder project board items based on triage priority.

## Terminal Output

Follow DESIGN.md conventions for all sync output:

- `●` when sync is in progress
- `✓` on success
- `⚠` on non-fatal failure
- `○` for informational notes (no project found, sync disabled)
- Two-space indent for details
- Static sequential output — no animation

## Error Messages

### No project linked
```
○ No GitHub Project linked to this repo — skipping board sync.
  To link: create a project at https://github.com/{owner}/{repo}/projects
```

### Status field not found
```
⚠ Status field "{field_name}" not found on project "{project_title}"

  To fix:  add a single-select field named "{field_name}" to the project
  Check:   https://github.com/orgs/{owner}/projects/{number}/settings
```

### Status option not matched
```
⚠ Status value "{value}" not found in project field options

  Available options: {option1}, {option2}, {option3}
  To fix:  update projects.status_map in .gitissue.yml to match your board
```

### Generic API failure
```
⚠ Project sync failed: {error_message}

  To fix:  check project permissions and try: gh api graphql -f query='...'
```

### Insufficient permissions
```
⚠ Project sync requires write access to the project board

  To fix:  ensure your token has the project scope
  Check:   gh auth status
```
