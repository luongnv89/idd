# Documentation practices

- **W1 Match the code.** Take every value a doc edit states (default, path, flag, env var, exit code, output) from the branch's code, never from memory, the plan or the issue. *Check:* each changed claim matches a `path:line` in the tree.
- **W2 Only what ships.** Document only behavior the branch implements; omit what the code cannot confirm. *Check:* no added `TODO`, `TBD` or future-tense feature in doc hunks.
- **W3 Real examples.** Copy each new command or example from code, tests or real `--help` output, and run it once when it has no side effects. *Check:* one changed example, run verbatim, gives the documented result.
- **W4 Surgical edits.** Edit only passages this change makes wrong, in the doc's own language, headings and terms; never reword or reorder unrelated prose. *Check:* each doc hunk traces to the code diff or the issue.
- **W5 Links resolve.** Every link or anchor the diff adds resolves, links to anything renamed or deleted are repointed, and a new doc is linked from an existing one. *Check:* `test -e` each target; grep finds no old name.
- **W6 Changelog placement.** When the changelog keeps an unreleased section, add the entry there in its neighbours' format. *Check:* the changelog diff adds lines only inside that section.
- **W7 Cites follow the code.** When the diff moves lines docs cite as `path:line`, repoint each cite. *Check:* grep docs for the changed file's cites; each lands on its fact.
