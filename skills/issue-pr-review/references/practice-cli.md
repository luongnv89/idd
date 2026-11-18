# Command-line interface practices

- **L1 Exit status.** Exit 0 only on success and non-zero on every failure path, using the repo's per-class codes where it has them. *Check:* trigger each new failure path and read `$?`.
- **L2 Output streams.** Results go to stdout; errors, warnings and logs to stderr; progress only when stderr is a TTY. *Check:* `<cli> <bad-args> 2>/dev/null` prints no error text.
- **L3 Machine output.** A machine format (`--json`, `--format json`) stays parseable: no escape codes, banners or log lines. *Check:* the output parses, and holds no ESC byte even with `FORCE_COLOR=1`.
- **L4 Actionable errors.** Each new error says what failed and how to fix it: a valid value, flag or command. *Check:* trigger one; the message alone tells the user what to change.
- **L5 Help text.** Every new command, flag and argument has a help description, and `--help` exits 0 at every level. *Check:* `<cli> <cmd> --help` lists the new item.
- **L6 Color gating.** Style output only on a TTY or under `FORCE_COLOR`; `NO_COLOR` or `--no-color` drops every escape code. *Check:* piped output holds no ESC byte, also with `FORCE_COLOR=1 NO_COLOR=1`.
- **L7 Config precedence.** Resolve a new setting as flag > env var > config file > default, unless the repo's settings use another order. *Check:* a test sets two sources and asserts the higher one wins.
- **L8 Install scripts.** Use `set -euo pipefail`, stop naming any unsupported platform, skip dependencies `command -v` finds, pass non-interactive flags, and use `sudo` only when not root. *Check:* `bash -n` passes; never run the script on the host.
