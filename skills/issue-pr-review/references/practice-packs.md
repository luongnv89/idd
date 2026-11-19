# Practice packs — selection

The files `references/practice-*.md` hold engineering rules, each with a
*Check* a reviewer can apply to a diff. Select packs from the change: its files
and what they do, plus the issue text. When unsure, include the pack.

| Pack | Select when the change… |
|------|-------------------------|
| `practice-tests.md`, `practice-code.md` | touches a source or test file (code in a programming language; not prose, prompt or data files) |
| `practice-security.md` | handles external input, auth or sessions, secrets or crypto, file paths, subprocesses, queries, HTTP handlers or outbound requests, or deserialization; edits a dependency manifest or lockfile; or was classified sensitive |
| `practice-performance.md` | touches data access or queries, request handlers, loops over input of unbounded size, file or network I/O, caching or long lists; or the issue states a latency, memory or throughput need |
| `practice-frontend.md` | touches a UI file (the file pattern in `references/docs/ui-review.md` → *Detection*) |
| `practice-ci-cd.md` | touches CI config, `.pre-commit-config.yaml`, `Dockerfile*`, compose files, or build files CI runs |
| `practice-cli.md` | adds or changes a command, flag, CLI entry point or install script |
| `practice-docs.md` | touches `README*`, a docs directory, `CHANGELOG*` or usage text |

Bind the selected files' **absolute** paths, newline-separated, as
`practice_packs`, and an empty value when nothing matches: a subagent's working
directory is the target repo, so a skill-relative path resolves to nothing.
Print `○ Practice packs: {names}` or `○ Practice packs: none`.

A pack shapes only the lines the change writes; it never widens the change.
