# Frontend and UX practices

- **F1 Forgiving forms.** Keep entered values on error, accept spacing and dash variants in formatted fields (phone, card, postcode; never secrets or case-sensitive IDs), and state the fix. *Check:* error paths keep form state; no raw error text.
- **F2 No hidden actions.** Say why a control is disabled; give every hover- or gesture-only action a visible control. *Check:* each new `disabled` has reason text nearby.
- **F3 Self-evident labels.** Name buttons and links by action or destination, never "Click here"; one primary action per view. *Check:* read each new label.
- **F4 Empty states.** Every list, table or search view says why nothing shows and offers the next step. *Check:* each new collection render has a zero-items branch.
- **F5 Native elements first.** Navigate with `<a href>` or the router link, act with `<button>`; ARIA only where no native element fits. *Check:* no `div`/`span` click handlers.
- **F6 Color plus a cue.** Pair every color-coded meaning with text, an icon or a pattern. *Check:* no new state differs from its siblings only in color.
- **F7 Reduced motion.** Non-essential animation stops under `prefers-reduced-motion: reduce`. *Check:* every new animation has a reduced-motion path.
- **F8 Stable first paint.** New media carry dimensions or `aspect-ratio`; lazy-load only below the fold; new scripts load `defer` or `async`. *Check:* media tags have dimensions.
- **F9 Page outline.** A new route sets title and meta description through the repo's mechanism and has one `<h1>` with no skipped levels. *Check:* one h1; no bold text posing as a heading.
- **F10 Finished, honest content.** No placeholder text, mock data, missing assets, pre-checked opt-ins or invented urgency. *Check:* no lorem ipsum or TODO text; every asset path resolves.
