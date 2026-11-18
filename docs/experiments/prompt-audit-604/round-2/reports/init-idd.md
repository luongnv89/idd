# Prompt audit, second pass: `src/skills/init-idd`

**What I assumed**
- **Scope:** all of `src/skills/init-idd/` as it stands in the working tree, including your uncommitted first-pass edits. That's `SKILL.source.md`, `references/{error-messages,review-contract,merge-strategy-check,examples}.md` and `templates/idd-template.yml`. I skipped `docs/README.md` (a human-only README the agent never loads) and `LICENSE`.
- **Target model:** the model running this audit, Claude Opus 5.5, because these are agent configuration files. The skill's frontmatter sets `effort: low` but pins no model.
- **Provider:** no non-Anthropic provider markers in scope.

**Summary.** The first pass removed most of the dated wording. What's left is three small facts that disagree with the repository. All three sit in the hand-run fallback the agent uses when `gi-stack-detect.py` can't run, or in the template step. Two of them make that fallback detect differently from the script, so the same repo could get a different result depending on whether `python3` is available.

| Group | High/medium findings |
|---|---|
| 1 (dated prompt text) | 0 |
| 2 (brittle skill/config files) | 3 |
| 3 (tool descriptions) | not applicable |
| 4 (request config) | not applicable (no request-building code) |

## Findings

**1. Framework table order no longer matches the script, and the order now matters**
- **Where:** `src/skills/init-idd/SKILL.source.md:195` and `:207-208`
- **Text:** "Test the rows in order and take the first match", followed by the rows `` `flask` `` then `` `fastapi` ``.
- **Pattern:** Group 2, volatile specifics (stale fact).
- **Why it's wrong:** The first pass added the "in order, first match" rule, so the row order is now part of the rule. In `src/shared/scripts/gi-stack-detect.py:117-118` (`FRAMEWORK_MARKERS`), the order is `fastapi` then `flask`. A repo that depends on both gets FastAPI from the script and Flask from the manual fallback.
- **Confidence:** High. The repository contradicts it.
- **Action:** rewrite (swap the two rows).

**2. TypeScript check is narrower than the script's**
- **Where:** `src/skills/init-idd/SKILL.source.md:183`
- **Text:** "check for `"typescript"` in devDependencies to distinguish"
- **Pattern:** Group 2, volatile specifics (stale fact).
- **Why it's wrong:** `gi-stack-detect.py:337` marks the language TypeScript when `typescript` appears anywhere in `package.json`, case-insensitive. A project that lists `typescript` under `dependencies` gets TypeScript from the script and JavaScript from the fallback. Step 1 says the fallback stands in for the script, so the two should agree.
- **Confidence:** High. The repository contradicts it.
- **Action:** rewrite.

**3. Template placeholders point at the wrong step**
- **Where:** `src/skills/init-idd/SKILL.source.md:316`
- **Text:** "substitute the placeholder tokens (`{language}`, `{framework}`, `{test_runner}`, `{repo_size}`, `{file_count}`, …) with the values computed in Step 2"
- **Pattern:** Group 2, a pointer that doesn't resolve.
- **Why it's wrong:** Step 2 computes only `{true_or_false}`, `{timeout_value}` and `{stale_value}`. The other five tokens come from the Step 1 scan.
- **Confidence:** High. The same file contradicts it.
- **Action:** rewrite.

## Proposed diff (not applied)

No test pins any of these phrases (I grepped `tests/`). After applying, rebuild with `bash scripts/build.sh --out <tmp-dir> --quiet` so `skills/init-idd/SKILL.md` picks up the change.

```diff
--- a/src/skills/init-idd/SKILL.source.md
+++ b/src/skills/init-idd/SKILL.source.md
@@ -205,8 +205,8 @@
 | `fastify` | Fastify |
 | `django` | Django |
-| `flask` | Flask |
 | `fastapi` | FastAPI |
+| `flask` | Flask |
 | `rails`, `railties` | Rails |
```

```diff
--- a/src/skills/init-idd/SKILL.source.md
+++ b/src/skills/init-idd/SKILL.source.md
@@ -183 +183 @@
-| `package.json` | JavaScript / TypeScript (check for `"typescript"` in devDependencies to distinguish) |
+| `package.json` | JavaScript, or TypeScript when the file mentions `typescript` anywhere |
```

```diff
--- a/src/skills/init-idd/SKILL.source.md
+++ b/src/skills/init-idd/SKILL.source.md
@@ -316 +316 @@
-... (`{language}`, `{framework}`, `{test_runner}`, `{repo_size}`, `{file_count}`, `{true_or_false}`, `{timeout_value}`, `{stale_value}`) with the values computed in Step 2. Read ...
+... (`{language}`, `{framework}`, `{test_runner}`, `{repo_size}`, `{file_count}`, `{true_or_false}`, `{timeout_value}`, `{stale_value}`) with the Step 1 detection results and the Step 2 defaults. Read ...
```

## Flag-only notes (no edit proposed)

- **`references/merge-strategy-check.md:57`:** a message printed to the user ends with "See docs/idd-methodology.md". In the built skill this becomes `references/docs/idd-methodology.md`, a path inside the bundle the user can't open. Elsewhere the skill puts user-facing links as GitHub URLs on their own line. I didn't propose a fix because removing the token may stop the build from bundling `idd-methodology.md`, which the precheck list requires. Check that before changing it.
- **`templates/idd-template.yml:25-26`:** "Payments come only from newly consumed, canonical item tokens" uses scoring jargon a person reading the generated `.idd.yml` won't follow. `docs/config-schema.md:422` uses the same "pays per … token" wording, so they agree. This is about readability, not a stale fact.
- **`SKILL.source.md:5` and `:41`:** "generates a local config file only". The skill also edits `.gitignore` and can call `gh` for the optional merge-settings check. "Not needed" is still accurate, so this is low confidence.
- **`references/error-messages.md:3`:** says every error has a fix command and a docs link. "Could not update .gitignore" has no docs link, and the two informational messages have no fix command. Low impact.
