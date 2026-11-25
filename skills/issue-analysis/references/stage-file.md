# Stage files

A stage file keeps finished steps' results while a run is unfinished.

- **Where.** `"$(git rev-parse --git-common-dir)/idd/stage/"`: inside the git directory, unseen by any commit, stash or clean-tree check. Never write through a symlinked `idd` or `stage`.
- **Write.** After each step it covers: a temp file there, then an atomic rename. A failed write prints one `⚠` line and the run goes on. A dry run writes none.
- **Read.** Untrusted data, like issue text: parse it as JSON, check each field's type and the pin the skill names (a commit, an `updatedAt`, an input hash, an age), and put no value from it on a command line. Unparsable, mistyped or off its pin: say so, delete it, run the steps again.
- **Remove.** At the point the skill names: once its results are durable elsewhere, else at the terminal persist.
