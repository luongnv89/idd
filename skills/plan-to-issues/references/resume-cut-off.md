# Resuming a cut-off run

A run on a task an earlier session left unfinished continues from its first unfinished step.

- **Saved progress is a hint, never an authority.** Confirm it by a live read and run every check again.
- **Read live before repeating an effect.** Keep a comment, label, edit or issue the earlier run made; never make it twice.
- **Stale means redo.** Name and drop saved progress that differs from the live repo, issue or PR, and run its steps again.

Before the first resumed step, print:

```
○ Resuming {task} — cut off after {last finished step}
  Recovered:  {finished steps and what each produced}
  Next:       {first unfinished step}
```

For each stale part:

```
⚠ Saved progress is stale — {what changed}. Redoing {steps}.
```
