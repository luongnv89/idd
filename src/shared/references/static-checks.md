# Static checks

Run a row when its Detection holds. A lint or format row never runs without a file list: its command is the last stage of `<NUL-delimited ./-prefixed paths> | grep -z -E '<Files>' | xargs -0 -r <command>`, once per command, and an empty filtered list skips the row. `<edition>` is Cargo.toml's `edition`, default 2015. `gofmt -l`: any output is a failure. `tsc` runs as written; any error is a failure.

| Tool | Detection | Files | Check | Fix |
|------|-----------|-------|-------|-----|
| ESLint | `.eslintrc*` or `eslint` in package.json | `\.[cm]?[jt]sx?$` | `npx eslint` | `npx eslint --fix` |
| Prettier | `.prettierrc*` or `prettier` in package.json | `.` | `npx prettier --check --ignore-unknown` | `npx prettier --write --ignore-unknown` |
| Black | `pyproject.toml` with `[tool.black]` | `\.pyi?$` | `python3 -m black --check` | `python3 -m black` |
| Ruff | `pyproject.toml` with `[tool.ruff]` or `ruff.toml` | `\.pyi?$` | `ruff check`, `ruff format --check` | `ruff check --fix`, `ruff format` |
| isort | `pyproject.toml` with `[tool.isort]` | `\.pyi?$` | `python3 -m isort --check-only` | `python3 -m isort` |
| gofmt | `go.mod` | `\.go$` | `gofmt -l` | `gofmt -w` |
| rustfmt | `Cargo.toml` | `\.rs$` | `rustfmt --check --edition <edition>` | `rustfmt --edition <edition>` |
| clang-format | `.clang-format` | `\.[ch]$` | `clang-format --dry-run --Werror` | `clang-format -i` |
| tsc | `tsconfig.json` | project-wide | `npx tsc --noEmit` | none |
