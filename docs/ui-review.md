# UI/UX Review Mechanics (shared)

Single authoritative home for the auto-detected UI/UX review shared by
`/issue-resolver` (Step 4 — QA) and `/issue-pr-review` (Step 3 — Analyze & Review).
Each consuming skill keeps only its own *deltas* (where the diff comes from,
which config scope gates the browser pass, which variables it passes, and where
findings flow) and points here for everything below.

Throughout, `{ui_config_scope}` is the consuming skill's config namespace:
`resolve` for `/issue-resolver`, `review` for `/issue-pr-review`.

## Contract

UI review is **auto-detected per work item** — no config flag enables it. Before
the review cycles, examine the issue/PR context and the diff to decide whether UI
work is involved, then run only the review that *can* and *should* run:

- **Code UI review** is environment-independent — it reads the diff and the
  changed files. It runs whenever UI work is detected, on any machine,
  **including a headless server with no display**. It is never gated on a GUI, a
  running app, or a browser.
- **Browser UI review** is optional and captures screenshots from a running app,
  so it only runs when there is a reachable running app *and* the user opted in.
  When it can't run, it **skips with a warning and the code UI review still
  runs** — fail-soft to code-only, never block.
- **Verification recipe** is opt-in: a base-ref `.idd-recipe.json` (or legacy
  `.gitissue-recipe.json`)
  launches, drives and tears down an owned instance (*Verification recipe*).

## Detection

Detection runs **once**, before the review cycles.

1. Scan the work item's title + body (the issue title/body for the resolver, the
   PR title/body for the PR reviewer) for UI keywords: `UI`, `frontend`, `component`, `style`,
   `css`, `html`, `design`, `layout`, `responsive`, `mobile`, `theme`,
   `dark mode`, `button`, `form`, `page`, `screen`, `visual`, `accessibility`,
   `a11y`, `icon`, `image`, `screenshot`, `dashboard`, `navigation`, `modal`,
   `dialog`, `card`, `table`, `chart`, `graph`.
2. Scan the diff for UI files, using the consuming skill's own diff command:
   ```bash
   <skill diff command> --name-only | grep -E '\.(html|htm|css|scss|sass|less|styl|tsx|jsx|vue|svelte|astro)$|^(components|pages|views|layouts|app|src/app|screens|routes|templates)/|tailwind\.config\.|theme\.|tokens\.'
   ```
3. Classify:
   - **`ui: detected`** — UI keywords **OR** UI files in the diff → run the code
     UI review.
   - **`ui: not detected`** — no UI indicators → skip UI review entirely (no
     agent spawned).

## Code-based review

When `ui: detected`, spawn the `ui-reviewer` subagent in **code** mode (see
`shared/agents/ui-reviewer.md`):

```python
Agent(
  description="ui-reviewer — UI/UX code review (…)",
  prompt=<ui-reviewer.md prompt with mode=code, {variables} replaced>,
  # do NOT set subagent_type — default general-purpose agent, not a custom "ui-reviewer" type
)
```

Role `ui-reviewer`: the consuming skill applies its agent-override rule with
`agents.model.ui-reviewer` / `agents.effort.ui-reviewer`; `null` passes nothing.

The consuming skill supplies the variables (`{branch_name}`, `{base_branch}`,
`{issue_context}`, `{pr_context}`, `{diff_command}`, plus its own extras). Merge
UI reviewer findings into its review findings — same `action: "fix" | "note"`
semantics, so they flow into the fix loop unchanged.

## Browser-based review (optional, gated)

Browser review runs only when it both *can* and *should*.

**First, label the display environment — for the report only.** Set `ui_env`
before the gate, so every path below (skips included) can name it. The label
never gates the review and never switches Playwright to a headed launch:
capture is always **headless**, which needs no display:

```bash
if [ "$(uname)" = "Darwin" ] || [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
  ui_env="graphical"        # macOS, or Linux with X11/Wayland
else
  ui_env="no-GUI server"    # no display ($DISPLAY/$WAYLAND_DISPLAY unset on a non-macOS host)
fi
```

Then check `{ui_config_scope}.ui_review.browser_review`:

- **`"false"`** — skip; code review already ran.
- **`"ask"`** — prompt interactive users; skip silently in auto mode.
- **`"true"`** — proceed to the capability check.

Then verify the runtime can actually capture screenshots — **all** must hold:

1. A target app is running and reachable (e.g. `curl -sf {app_url}` succeeds).
2. A headless browser is available (Playwright/Chromium installed); no display
   is needed.
3. Capture is safe (not a production URL, no auth wall that would log real
   traffic).

If the gate or any capability check fails, print a warning and skip — **without**
affecting the code UI review that already ran. Name the environment so a no-GUI
host is never mistaken for a silent skip:

```
⚠ Browser review skipped — {reason} (environment: {ui_env})
  Code UI review still ran. Enable browser review with:
  {ui_config_scope}.ui_review.browser_review: "true"  (and ensure the app is running and reachable)
```

When all hold, capture screenshots at mobile/tablet/desktop viewports with
Playwright launched **headless**, then spawn the UI reviewer in **browser** mode
with the screenshot paths and `{app_url}`. **Report the mode and environment** on
success so the review output always states that the headless path ran and where:

```
✓ Browser review — captured 3 viewports (Playwright: headless; environment: {ui_env})
```

## Verification recipe (optional, opt-in) <!-- a:ui-verification-recipe -->

Project-wide, independent of UI detection: `.idd-recipe.json` (legacy
`.gitissue-recipe.json`, read only when the new name is absent) maps
**capabilities** to changed paths. The consuming skill runs it through its
bundled recipe helper (schema in the helper's docstring), which prints one JSON
verdict.

- **Source:** read **only from the base ref**, never the working tree — a branch
  must not supply the recipe it is verified by. Its commands run in the working
  tree, against the code under test.
- **Opt-in:** no file (`status: absent`) changes nothing. Interactive: run with
  `--plan`, list the mapped capabilities, ask `Run verification recipe? [Y/n]`.
  Auto: runs only when the base-ref recipe's `auto` list names `{ui_config_scope}`;
  `.idd.yml` cannot enable it, as a branch can edit it.
- **Lifecycle:** launch in a new process group — the only group the helper
  signals — wait for the ready URL, drive each mapped capability, then SIGTERM
  and SIGKILL that group, run `cleanup`, remove `{instance_dir}`. Teardown runs
  on every path, readiness failure and interruption included.
- **Evidence:** `<git common dir>/idd/evidence/<head sha40>/<run>/` holds
  `launch.log`, each `drive.log` and drive output, and `verdict.json`. Inside
  `.git` and outside the instance, it survives teardown, never dirties the
  tree, and is never overwritten.
- **Verdict:** `result: fail` (a drive exited non-zero or timed out) is an
  `action: "fix"` finding citing that capability's `drive.log`. Exit 3 (invalid
  base-ref recipe, nothing launched) stops with `✗ Invalid verification recipe:
  {recipe file} at {ref}`, the helper's reason, and `To fix: correct or
  remove it on the base branch`. Any other exit or no `python3`: print
  `⚠ Verification recipe skipped — {reason}` and continue. Never hand-run
  recipe commands: owned-only teardown is what the helper guarantees.

## Integration with the fixer

UI `action: "fix"` findings join the consuming skill's fixable issues and are
handled by its fixer step. The fixer handles file/line findings normally;
browser-only findings without file/line are resolved by identifying the
responsible files from the diff and the issue/PR context.
