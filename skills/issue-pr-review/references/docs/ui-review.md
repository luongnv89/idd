<!-- Generated from /docs/ui-review.md. Do not edit. Edit source and run ./scripts/build.sh. -->
# UI/UX Review Mechanics (shared)

Single authoritative home for the auto-detected UI/UX review shared by
`/issue-resolver` (Step 4 — QA) and `/issue-pr-review` (Step 3 — UI/UX Review).
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

## Detection

Detection runs **once**, before the review cycles.

1. Scan the work item's title + body (issue body for the resolver, PR title/body
   for the PR reviewer) for UI keywords: `UI`, `frontend`, `component`, `style`,
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
`references/agents/ui-reviewer.md`):

```python
Agent(
  description="ui-reviewer — UI/UX code review (…)",
  prompt=<ui-reviewer.md prompt with mode=code, {variables} replaced>,
  # do NOT set subagent_type — default general-purpose agent, not a custom "ui-reviewer" type
)
```

The consuming skill supplies the variable set (`{branch_name}`, `{base_branch}`,
`{issue_context}`, `{pr_context}`, `{diff_command}`, and any skill-specific
extras). Merge UI reviewer findings into that skill's own review findings — both
use the same `action: "fix" | "note"` semantics, so they flow into the existing
fix loop unchanged.

## Browser-based review (optional, gated)

Browser review runs only when it both *can* and *should*.

**First, detect the display environment (for the report only — capture is always
headless).** Classify the runtime as *no-GUI/server* or *graphical* up front,
before the gate and capability checks, so `ui_env` is always defined for every
code path below — including the early skip paths. This label never selects the
launch mode and never gates the review — Playwright always runs **headless** (the
only capture mode this review has ever used), so behavior on a graphical display
is unchanged:

```bash
# Label the environment for reporting. Capture stays headless either way —
# headless Chromium needs no display, so a no-GUI/server host is fully supported.
if [ "$(uname)" = "Darwin" ] || [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
  ui_env="graphical"        # a display is present (macOS, or Linux with X11/Wayland)
else
  ui_env="no-GUI server"    # no display ($DISPLAY/$WAYLAND_DISPLAY unset on a non-macOS host)
fi
```

This detection is **report-only**: it is never a fourth gate, and it never
switches Playwright to a headed launch. A no-GUI result does **not** skip the
browser review — headless Chromium needs no display, so capture proceeds headless
exactly as it does on a graphical host.

Then check `{ui_config_scope}.ui_review.browser_review`:

- **`"false"`** — skip; code review already ran.
- **`"ask"`** — prompt interactive users; skip silently in auto mode.
- **`"true"`** — proceed to the capability check.

Then verify the runtime can actually capture screenshots — **all** must hold:

1. A target app is running and reachable (e.g. `curl -sf {app_url}` succeeds).
2. A headless browser is available (Playwright/Chromium installed). A headless
   server with no physical display is fine — headless Chromium needs no display;
   what it needs is the browser binary and a reachable app.
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

## Integration with the fixer

UI `action: "fix"` findings join the consuming skill's fixable issues and are
handled by its fixer step. The fixer handles file/line findings normally;
browser-only findings without file/line are resolved by identifying the
responsible files from the diff and the issue/PR context.
