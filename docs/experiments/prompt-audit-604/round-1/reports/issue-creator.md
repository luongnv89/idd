# Prompt audit: `src/skills/issue-creator`

**Assumptions**
- **Scope:** the skill's runtime prose, meaning `SKILL.source.md`, `references/*.md` and `templates/{bug,feature,improvement}.md`. I left out three files: `LICENSE`; `docs/README.md`, which is for humans and never loaded; and `templates/model-data.json`, which is data, so I only read its `M` band to check the examples. Shared files the skill bundles (`src/shared/*`, `docs/*`) are out of scope except where a finding points at them.
- **Target model:** Claude Opus 5.5, the model running this audit. The skill sets only `metadata.effort: medium` and doesn't pin a model.
- **Not run:** I couldn't run `scripts/build.sh` here because permission was declined. So the pointer checks use the sources, not a built bundle.

**Summary.** Most of what this audit found is not dated wording. It's facts in the skill that disagree with each other or with the repo:
- The Normalize preview uses confidence markers that differ from the confidence-scoring table it's supposed to follow.
- The rate-limit retry rule in `error-messages.md` is narrower than the driver rule it cites.
- The model-suggestion reference still has acceptance-criterion numbers in its headings, makes a false "only network call" claim, describes the CI pipeline, and uses "pre-feature" wording. `CLAUDE.md` forbids all of these in bundled text.

There's very little pressure language: nearly every `MUST`/`mandatory` comes with its reason, so I left those alone.

**Counts:** Group 1: 2 · Group 2: 10 (3 of them are flag-only) · Group 3: not applicable (no tool definitions; the frontmatter `description` is routing text and fine) · Group 4: not applicable (no request-building code).

## Findings

### High confidence

| # | Location | Evidence | Pattern | Why it's wrong | Action |
|---|---|---|---|---|---|
| 1 | `references/modes.md:82,90` | `+ Type: bug (high confidence)` / "Use `(high confidence)` for Type, abbreviated … `(low)` for criteria" | G2 · files contradict each other | `references/confidence-scoring.md:9-11` (blame 2026-06-30, the newer one; modes.md is 2026-04-20) says the preview shows `(high)`, and a low-confidence field shows `(needs review)`, never `(low)`. Create's preview at `SKILL.source.md:276` already follows the table. | rewrite modes.md to point at the table |
| 2 | `references/error-messages.md:125` | "a *secondary* limit carrying `Retry-After`" | G2 · files contradict each other | `docs/platform-github.md:11` (rule 5) and `modes.md:329` treat any secondary rate-limit 403 as retryable. This line adds a `Retry-After` condition that neither of them has. | rewrite to match rule 5 |
| 3 | `references/model-suggestion.md:217,235,246,301` | `## Complexity classification (AC #4)` … `(AC #7)` | G2 · history narratives | Acceptance-criterion numbers mean nothing at run time. `CLAUDE.md` › Writing skill text forbids them in bundled text. No test pins these headings. | rewrite (drop the suffix) |
| 4 | `references/model-suggestion.md:213` | "WebFetch is the only network call this skill makes" | G2 · volatile specifics | False: the skill calls `gh issue create`, `gh api …/contents` (`image-upload.md:26`), `gh issue list`, and so on. | rewrite |
| 5 | `references/model-suggestion.md:179-181` | "A weekly CI job opens or updates a pull request when the bundled seed is stale…" | G2 · maintainer material in the bundle | `CLAUDE.md` says CI workflow descriptions belong outside the bundle. The agent can't act on this. All it needs is that the seed changes only on reinstall. | rewrite |

### Medium confidence

| # | Location | Evidence | Pattern | Why it's wrong | Action |
|---|---|---|---|---|---|
| 6 | `references/model-suggestion.md:297-299` | "neither the body nor the preview changes from the pre-feature behaviour" | G1d · wording that compares against an older version | It compares against a version the agent never saw. | rewrite |
| 7 | `SKILL.source.md:279`, `references/model-suggestion.md:78-80, 251-252, 259-260, 274` | `GPT-5.6 Luna Max (~$1.03/task) · Sonnet 5.5 Extra High (~$2.81/task)` | G1c · examples the model copies + G2 · volatile specifics | `model-suggestion.md:241-243` says the picks "are not copied here because a refresh replaces them", yet five passages copy the current `M` picks and prices. They match the seed today, but no refresh job updates the prose, so after the next refresh the example contradicts the cache and the agent may print the example instead. Only `test-scripts-253.sh:465` pins these names, and it checks the seed, not the prose. Line 285 (the dated body line) is labelled and dated, so I left it. | rewrite to placeholders |
| 8 | `references/model-suggestion.md:227-233` | Effort table column "Acceptance criteria": S `2–3`, M `3–5`, plus "pick the highest band any signal reaches" | G2 · conflict inside the skill | Create Step 4 (`SKILL.source.md:265`) always generates 3–5 criteria. If the generated criteria are counted, every issue reaches at least M, so effort and the model pick drift upward. | rewrite the column to count only requirements the reporter stated |
| 9 | `SKILL.source.md:371` | "GitHub API rate limit — creation stops at the last successful issue" | G2 · a restated rule that has drifted | `modes.md:329` retries a secondary limit, then skips the item and continues. Only primary exhaustion stops. | rewrite as a pointer |
| 10 | `references/modes.md:17,148,176,366` | `python3 references/scripts/gi-issue[.]py {N} --invalidate` | G2 · conflicts with `CLAUDE.md` › "cite scripts as `shared/scripts/NAME[.]py`" | It works today only because `modes.md:11` carries the build token. If that line moves, the closure loses the script. | rewrite to the token |

### Flag (no edit proposed)

| # | Location | Evidence | Why | Confidence |
|---|---|---|---|---|
| 11 | `references/modes.md:57-58` vs `:73` | Security skip reason: "Codebase context could reveal exploit details." / "Normalization is structure-only … without scanning the codebase" | Both come from one commit (8ddf344a) and contradict each other, so the stated reason doesn't hold. It's a safety gate, so it's flag-only: you decide whether the skip stays and what its real reason is. | High (repo contradicts) |
| 12 | `references/model-suggestion.md:123-126` | "Per-repo legacy cache … is ignored" | It describes a path that doesn't run, which `CLAUDE.md` says can send the agent looking for something that doesn't exist. It may still help on repos that have the old file, so this is your call. | Low |
| 13 | `references/confidence-scoring.md:3`, `modes.md:309,325,348,354,374`, `SKILL.source.md:46` | `Per SPEC §1.3`, `SPEC §2.1` | `SPEC.md` isn't bundled. `docs/idd-methodology.md` only links to it by URL, and the rules are already written out in full where they're cited. The citations are harmless but don't resolve at run time. | Low |

## Proposed diff

These are proposed only, not applied. There's one finding per hunk. No test pins any removed phrase. One related copy is out of scope: the docstring in `src/shared/scripts/gi-model-cache.py:37` has the same example picks, so leave it or change it with #7.

```diff
--- a/src/skills/issue-creator/references/modes.md   (#1)
@@ -80,13 +80,13 @@
 ◆ Normalization Preview
 ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
-  + Type:        bug (high confidence)
+  + Type:        bug (high)
   + Criteria:    3 acceptance criteria (medium)
@@
-`+` = added field, `=` = preserved field. Use `(high confidence)` for Type, abbreviated `(high)`, `(medium)`, `(low)` for criteria. Low-confidence fields get `(needs review)` in the issue body.
+`+` = added field, `=` = preserved field. Confidence markers follow the preview and issue-body columns of `references/confidence-scoring.md`.
```

```diff
--- a/src/skills/issue-creator/references/error-messages.md   (#2)
@@ -125 +125 @@
-**Trigger:** `gh issue create` returns HTTP 403 with rate limit headers during batch creation. Retries only when driver rule 5 in `docs/platform-github.md` classifies it as recoverable — a *secondary* limit carrying `Retry-After` — on the shared bounded schedule of 2s, 4s, 8s, 16s (four attempts), or the longer `Retry-After` when one is given. *Primary* exhaustion is not retryable and stops with the *Rate limited* block above.
+**Trigger:** `gh issue create` returns HTTP 403 with rate limit headers during batch creation. Retries only when driver rule 5 in `docs/platform-github.md` classifies it as recoverable — a *secondary* rate-limit 403 — on the shared bounded schedule of 2s, 4s, 8s, 16s (four attempts), or the longer `Retry-After` when one is given. *Primary* exhaustion is not retryable and stops with the *Rate limited* block above.
```

```diff
--- a/src/skills/issue-creator/references/model-suggestion.md   (#3)
@@ -217 +217 @@
-## Complexity classification (AC #4)
+## Complexity classification
@@ -235 +235 @@
-## Complexity → model mapping (AC #5)
+## Complexity → model mapping
@@ -246 +246 @@
-## Rendering the suggestion (AC #6)
+## Rendering the suggestion
@@ -301 +301 @@
-## Configuration (AC #7)
+## Configuration
```

```diff
--- a/src/skills/issue-creator/references/model-suggestion.md   (#4)
@@ -213,2 +213,2 @@
-> WebFetch is the only network call this skill makes, and only on explicit
-> opt-in or `--refresh-model-data`. The bundled seed guarantees the feature
+> WebFetch is the only call this skill makes outside GitHub, and only on
+> explicit opt-in or `--refresh-model-data`. The bundled seed guarantees the feature
```

```diff
--- a/src/skills/issue-creator/references/model-suggestion.md   (#5)
@@ -179,3 +179,2 @@
-A weekly CI job opens or updates a pull request when the bundled seed is stale;
-a run sees it only after a release and a skill reinstall, so the procedure below
-is how a run gets fresher data.
+The bundled seed changes only when the skill is reinstalled, so the procedure
+below is how a run gets fresher data.
```

```diff
--- a/src/skills/issue-creator/references/model-suggestion.md   (#6)
@@ -297,3 +297,2 @@
 When the feature is disabled, omit the `**Suggested model:**` line entirely and
-do not render the preview `⚡ Model:` line — neither the body nor the preview
-changes from the pre-feature behaviour.
+do not render the preview `⚡ Model:` line.
```

```diff
--- a/src/skills/issue-creator/SKILL.source.md   (#7)
@@ -279 +279 @@
-  ⚡ Model:  GPT-5.6 Luna Max (~$1.03/task) · Sonnet 5.5 Extra High (~$2.81/task)
+  ⚡ Model:  {openai_model} (~${openai_cost}/task) · {anthropic_model} (~${anthropic_cost}/task)
--- a/src/skills/issue-creator/references/model-suggestion.md   (#7)
@@ -78,3 +78,3 @@
 **per-model**, sourced from each named model's own `cost_per_task_usd` in the
-`providers` block. So the M band's cost is `GPT-5.6 Luna Max` → `$1.03` and
-`Sonnet 5.5 Extra High` → `$2.81`, shown as two independent figures — never their sum.
+`providers` block, so a band shows two independent figures — one per pick,
+never their sum.
@@ -251,2 +251,2 @@
-Anthropic model — joined by ` · ` (OpenAI first)** — e.g. `GPT-5.6 Luna Max · Sonnet
-5.5 Extra High`. The two names are read from the effort band's `openai` and
+Anthropic model — joined by ` · ` (OpenAI first)** — `{openai_model} · {anthropic_model}`.
+The two names are read from the effort band's `openai` and
@@ -259,2 +259,2 @@
-the `providers` block — e.g. `GPT-5.6 Luna Max (~$1.03/task) · Sonnet 5.5 Extra
-High (~$2.81/task)`. The two costs are independent (the picks are alternatives) and
+the `providers` block — `{openai_model} (~${openai_cost}/task) · {anthropic_model}
+(~${anthropic_cost}/task)`. The two costs are independent (the picks are alternatives) and
@@ -274 +274 @@
-  ⚡ Model:  GPT-5.6 Luna Max (~$1.03/task) · Sonnet 5.5 Extra High (~$2.81/task)
+  ⚡ Model:  {openai_model} (~${openai_cost}/task) · {anthropic_model} (~${anthropic_cost}/task)
```

```diff
--- a/src/skills/issue-creator/references/model-suggestion.md   (#8)
@@ -224,4 +224,6 @@
 When effort has not yet been decided, estimate it from the issue using these
-signals, then pick the highest band any signal reaches:
+signals, then pick the highest band any signal reaches. Count only the
+requirements the reporter stated, not the 3–5 criteria Step 4 generates —
+those would put every issue at M or above:
 
-| Effort | Description length | Acceptance criteria | Scope signals |
+| Effort | Description length | Stated requirements | Scope signals |
```

```diff
--- a/src/skills/issue-creator/SKILL.source.md   (#9)
@@ -371 +371 @@
-- **GitHub API rate limit** — creation stops at the last successful issue, reporting the partial result with a resume hint.
+- **GitHub API rate limit** — a secondary limit is retried, then the item is skipped; primary exhaustion stops with a resume hint (`references/modes.md`, Batch Step 5).
```

```diff
--- a/src/skills/issue-creator/references/modes.md   (#10)
@@ -17 +17 @@
-… Every `gh issue edit` below is therefore followed by a **mandatory** `python3 references/scripts/gi-issue[.]py {N} --invalidate`, …
+… Every `gh issue edit` below is therefore followed by a **mandatory** `python3 shared/scripts/gi-issue[.]py {N} --invalidate`, …
@@ -148 +148 @@
-python3 references/scripts/gi-issue[.]py {N} --invalidate
+python3 shared/scripts/gi-issue[.]py {N} --invalidate
@@ -176 +176 @@
-python3 references/scripts/gi-issue[.]py {N} --invalidate   # mandatory: labels just changed
+python3 shared/scripts/gi-issue[.]py {N} --invalidate   # mandatory: labels just changed
@@ -366 +366 @@
-   python3 references/scripts/gi-issue[.]py {parent} --invalidate   # mandatory: body just changed
+   python3 shared/scripts/gi-issue[.]py {parent} --invalidate   # mandatory: body just changed
```

To check the diff after applying it, rebuild (`bash scripts/build.sh --out <tmp> --quiet`) and run the suite (`git ls-files 'tests/*.sh' | xargs -n1 bash`). Hunk #10 should leave the built `references/` output byte-identical.
