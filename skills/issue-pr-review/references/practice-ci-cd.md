# CI/CD and build config practices

- **D1 Untrusted input via `env:`.** Pass event text (titles, bodies, comments, `head_ref`) to `run:` only through a quoted `env:` variable. *Check:* no title, body, comment, `head_ref` or `inputs.*` expression in `run:`.
- **D2 Privileged jobs on trusted events.** Deploy, publish and secret-bearing jobs run only on default-branch push, tags or manual dispatch; no `pull_request_target` job runs PR code. *Check:* read each such job's triggers.
- **D3 Least-privilege token.** Each new job declares `permissions:` naming only the scopes its steps use. *Check:* every write scope maps to a step.
- **D4 Pin external refs.** Pin new `uses:` as the repo does (never `@main`) and images to an exact tag or digest (never `:latest`). *Check:* grep new `uses:`, `FROM`, `image:`.
- **D5 Locked installs.** Use the lockfile's frozen mode (`npm ci`, `--frozen-lockfile`, `--locked`); no `curl | sh` and no undeclared `npx` package. *Check:* grep new install, `curl`, `npx` lines.
- **D6 Never weaken a gate.** No `continue-on-error`, `|| true`, skipped hook or lowered threshold on a gating step unless the issue asks for it. *Check:* grep the diff.
- **D7 Required checks keep reporting.** Never path-filter a workflow running a required check (skip jobs with `if:`); name renamed checks in the commit body. *Check:* read changed `on:` and job names.
- **D8 No `needs:` on skippable jobs.** A job that needs a job skipped on its event is skipped too. *Check:* compare each new `needs:` target's `if:` and events.
- **D9 Bounded runs.** New jobs get `timeout-minutes`; new PR workflows get a `concurrency` group with `cancel-in-progress: true`, never on deploys. *Check:* read each added job.
- **D10 Honest caches and history.** Key caches on OS, toolchain and lockfile hash; use `fetch-depth: 0` where a job diffs refs. *Check:* read each new `key:` and checkout.
