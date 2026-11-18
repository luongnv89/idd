# Ledger (pass 2): src/skills/init-idd

| # | Location | Finding (short) | Confidence | Outcome | Detail |
|---|---|---|---|---|---|
| 1 | `SKILL.source.md:207-208` | Framework rows `flask` before `fastapi`; script order is fastapi then flask, and order is now first-match | High | fixed | Verified `gi-stack-detect.py` FRAMEWORK_MARKERS (`fastapi` precedes `flask`). Swapped the two rows in the Framework Detection table. |
| 2 | `SKILL.source.md:183` | TypeScript check limited to devDependencies; script matches `typescript` anywhere in package.json (case-insensitive) | High | fixed | Verified `detect_language` (`"typescript" in index.read(source).lower()`). Row now: "JavaScript, or TypeScript when the file mentions `typescript` anywhere". |
| 3 | `SKILL.source.md:316` | Placeholders said to come from Step 2; five come from Step 1 | High | fixed | "with the values computed in Step 2" → "with the Step 1 detection results and the Step 2 defaults". |
| F1 | `references/merge-strategy-check.md:57` | User-facing "See docs/idd-methodology.md" renders as a bundle path | Flag-only | kept | Flag-only per plan; removing the token may drop `idd-methodology.md` from the bundle, which the precheck list requires; needs a build-closure check first. |
| F2 | `templates/idd-template.yml:25-26` | "canonical item tokens" jargon in generated config | Flag-only | kept | Flag-only; matches `docs/config-schema.md` wording, readability only, no stale fact. |
| F3 | `SKILL.source.md:5,41` | "generates a local config file only" omits .gitignore edit / optional gh call | Low | kept | Low/flag-only; "not needed" statement still accurate. |
| F4 | `references/error-messages.md:3` | "Every error has a fix command and docs link" not true for all entries | Low | kept | Low/flag-only; low impact, no behaviour change. |
