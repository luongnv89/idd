# UI/UX Review Mechanics

Operational detail for the auto-detected UI/UX review in *Step 3 — UI/UX Review*. SKILL.md keeps the contract (auto-detect → always run code review; browser review is an additive bonus); this file holds the detection commands, the display-environment label, the gate/capability checks, and the capture call.

## Detection phase (runs once, after Step 2, before the review cycles)

1. **Check PR context** for UI indicators:
   ```bash
   pr_body=$(gh pr view {N} --json body --jq .body)
   ```
   Scan title + body for UI keywords: `UI`, `frontend`, `component`, `style`, `css`, `html`, `design`, `layout`, `responsive`, `mobile`, `theme`, `dark mode`, `button`, `form`, `page`, `screen`, `visual`, `accessibility`, `a11y`, `icon`, `image`, `screenshot`, `dashboard`, `navigation`, `modal`, `dialog`, `card`, `table`, `chart`, `graph`.

2. **Check PR diff** for UI file changes:
   ```bash
   ui_files=$(gh pr diff {N} --name-only | grep -E '\.(html|htm|css|scss|sass|less|styl|tsx|jsx|vue|svelte|astro)$|^(components|pages|views|layouts|app|src/app|screens|routes|templates)/|tailwind\.config\.|theme\.|tokens\.')
   ```

3. **Classify**:
   - **`ui: detected`** — UI keywords in PR context OR UI files in diff → run the code UI review.
   - **`ui: not detected`** — no UI indicators → skip UI review entirely (no agent spawned).

4. **Propose review mix** (interactive mode only):
   ```
   ◆ UI Review Detected
   ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

     PR mentions:    responsive, mobile, button
     Files changed:  src/components/Button.tsx, src/styles/main.css

     Proposed review:
       ✓ Code review (a11y, responsive, interaction patterns) — runs now
       ○ Browser review (screenshot capture) — needs a running app

     Enable browser review? [Y/n] (requires a reachable app + Playwright)
   ```
   In auto mode (`IDD_AUTO_MODE=1`): log the detection result and proceed with **code review only** — browser review requires user confirmation per `review.ui_review.browser_review`.

## Code-based review

When detection returns `ui: detected`, spawn the `ui-reviewer` subagent in **code** mode (see `references/agents/ui-reviewer.md`):

```python
Agent(
  description="Dieter Rams — UI/UX code review for PR #{N}",
  prompt=<ui-reviewer.md prompt with mode=code, {variables} replaced>,
  subagent_type="general-purpose"
)
```

Pass `{branch_name}`, `{base_branch}`, `{pr_context}` (PR title + body), `{issue_context}` (the linked issue title/body + acceptance criteria, or empty if none), and `{diff_command}` (`gh pr diff {N}`). Merge UI reviewer findings into the code reviewer findings — both use the same `action: "fix" | "note"` semantics, so they flow into Step 6 unchanged.

For cycle reuse, cycles 2+ re-message the existing UI reviewer via `SendMessage`:
```
The fixer applied changes. Re-review the PR diff for UI/UX issues.

Run: gh pr diff {N}

Return the same JSON format as before.
```
For the confirmation pass, spawn one **fresh** UI reviewer for an unbiased final check.

## Browser-based review (optional, gated)

Browser review runs only when it both *can* and *should*.

**First, detect the display environment (for the report only — capture is always headless).** Classify the runtime as *no-GUI/server* or *graphical* up front, before the gate and capability checks, so `ui_env` is always defined for every code path below — including the early skip paths. This label never selects the launch mode and never gates the review — Playwright always runs **headless** (the only capture mode this review has ever used), so behavior on a graphical display is unchanged:

```bash
# Label the environment for reporting. Capture stays headless either way —
# headless Chromium needs no display, so a no-GUI/server host is fully supported.
if [ "$(uname)" = "Darwin" ] || [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
  ui_env="graphical"        # a display is present (macOS, or Linux with X11/Wayland)
else
  ui_env="no-GUI server"    # no display ($DISPLAY/$WAYLAND_DISPLAY unset on a non-macOS host)
fi
```

This detection is **report-only**: it is never a fourth gate, and it never switches Playwright to a headed launch. A no-GUI result does **not** skip the browser review — headless Chromium needs no display, so capture proceeds headless exactly as it does on a graphical host.

Then check `review.ui_review.browser_review`:

- **`"false"`** — skip; code review already ran.
- **`"ask"`** — prompt interactive users; skip silently in auto mode.
- **`"true"`** — proceed to the capability check below.

Then verify the runtime can actually capture screenshots — **all** must hold:
1. A target app is running and reachable (e.g. `curl -sf {app_url}` succeeds).
2. A headless browser is available (Playwright/Chromium installed). A headless server with no physical display is fine — headless Chromium needs no display; what it needs is the browser binary and a reachable app.
3. Capture is safe (not a production URL, no auth wall that would log real traffic).

If the gate or any capability check fails, print a warning and skip — **without** affecting the code UI review that already ran. Name the environment so a no-GUI host is never mistaken for a silent skip:
```
⚠ Browser review skipped — {reason} (environment: {ui_env})
  Code UI review still ran. Enable browser review with:
  review.ui_review.browser_review: "true"  (and ensure the app is running and reachable)
```

When all hold, capture screenshots at mobile/tablet/desktop viewports with Playwright launched **headless**, then spawn the UI reviewer in **browser** mode with the screenshot paths and `{app_url}`. **Report the mode and environment** on success so the review output always states that the headless path ran and where:
```
✓ Browser review — captured 3 viewports (Playwright: headless; environment: {ui_env})
```

## Integration with the fixer

`action: "fix"` findings from the UI reviewer join the fixable issues in Step 6. The fixer handles file/line findings normally; browser-only findings without file/line are resolved by identifying the responsible files from the PR diff and issue context.
