# IDD Stack — Issue-Driven Development

IDD Stack makes GitHub issues the single source of truth for development work. This plugin bundles eight Claude Code skills that turn rough notes or a whole plan into structured issues, prioritize the backlog, investigate one issue, open a pull request that resolves it, review and merge that pull request, and run the whole loop unattended.

## Skills

| Command | What it does |
|---|---|
| `/idd:issue-creator` | Creates structured issues from text, screenshots, or lists, with acceptance criteria and a duplicate check; normalizes existing issues to the IDD template |
| `/idd:plan-to-issues` | Turns a phased plan file, or a conversation about what to build, into labelled issues under one tracking epic that maps each issue to its source task |
| `/idd:issue-triage` | Scans open issues for dependencies, priority, parallel work, and staleness, and proposes an order |
| `/idd:issue-analysis N` | Investigates issue N for root cause, complexity, and risk |
| `/idd:issue-resolver N` | Branches, implements, tests, commits, and opens one pull request that closes issue N |
| `/idd:issue-pr-review` | Reviews a pull request, checks CI and acceptance criteria, applies fixes, and optionally merges |
| `/idd:auto-pilot` | Repeats triage, resolve, review, and merge across the backlog without prompts |
| `/idd:init-gitissue` | Writes a `.gitissue.yml` tuned to the repository's stack |

## Requirements

- The GitHub CLI (`gh`), authenticated with `gh auth login`, for the repository you work in
- `git`
- `python3` is optional: the skills run small standard-library helper scripts when it is available and follow an equivalent written procedure when it is not

## What the plugin runs, sends, and stores

The plugin has no hooks, MCP servers, or background processes. Everything happens when you invoke a skill, through tools Claude already uses in your session:

- **GitHub, through your own `gh` login.** The skills read and write issues, labels, comments, pull requests, and CI status in the repository you point them at. `/idd:issue-resolver` and `/idd:auto-pilot` create branches, commit, and push with `git`. `/idd:issue-pr-review` and `/idd:auto-pilot` can merge pull requests: auto-pilot does so without asking, which is its purpose, and both respect the repository's own branch rules. The plugin never reads or forwards your token itself.
- **One optional public page.** `/idd:issue-creator` can refresh its model-suggestion table by fetching the public page `https://cursor.com/cursorbench`, only after you accept a refresh prompt or pass `--refresh-model-data`. Nothing about your repository is sent, and the bundled data works offline.
- **Local files only.** Run logs, triage and analysis results, and caches go to `.gitissue/` in your repository. The model-suggestion cache goes to `${XDG_CACHE_HOME:-~/.cache}/gitissue`. Before any commit, a scan checks staged changes for secrets and build artifacts.

No telemetry is collected, and no data leaves your machine except the GitHub calls above and that optional page fetch.

## Configuration

IDD Stack works with no configuration. To change labels, branch naming, test commands, review gates, or per-role agent models, run `/idd:init-gitissue` or edit `.gitissue.yml`. Full documentation, the methodology, and the configuration schema are at https://github.com/luongnv89/idd

## License

MIT
