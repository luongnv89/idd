# Step 3.5 — Clarify Ambiguous Intent

This step makes intent capture **active** rather than passive: before drafting, the skill resolves genuine ambiguity by asking — but only when confidence is genuinely low, and only in interactive Create mode. When confidence is high, this step is a silent no-op and the one-shot path (Step 3 → Step 4) is unchanged.

## When this step runs

Run this step only if **all** of these hold:

- Interactive Create mode (not Batch, not Normalize). Batch and any non-interactive/auto context **never** ask — see *Non-interactive contexts* below.
- The predicted confidence of **type classification** (from Step 2) or **acceptance criteria** is `low`. Predict acceptance-criteria confidence from the same signals the Confidence Scoring System uses: `low` when the input states no explicit requirements and criteria would be generic template defaults.
- The ambiguity is about **intent** (what the reporter wants), not implementation. In practice type and acceptance criteria are always intent, so a genuinely low-confidence field always qualifies — this clause only forbids drifting into "how should we build it?" questions, which belong to the resolver, never to issue creation.

If type and criteria are both `high` or `medium`, skip this step entirely and proceed to Step 4. No question is asked; no friction is added.

## Resolve from the repo before asking

A question is only worth the user's attention if the repo cannot answer it. Before asking anything, check whether repo inspection resolves the ambiguity — for example, "is dark mode a new capability or a broken existing one?" is answered by checking whether a dark-mode toggle already exists (→ `improvement`/`bug` vs `feature`). If repo inspection settles the field, **do not ask**: raise its confidence to `high` when the inspection is conclusive, or `medium` when it is suggestive but not definitive.

> **Output Contract boundary (critical):** Repo inspection here serves *only* to disambiguate intent and set confidence. Its findings MUST NOT leak into the issue body. The Output Contract still holds in full — no predicted affected files, no generated technical notes, no root cause, no implementation hints. Knowing "a `ThemeToggle` component exists" may flip the type from feature to bug, but neither that component name nor any path appears in the draft. This step changes *classification*, never *body content*.

## How to ask

For each remaining low-confidence field (at most one or two — do not interrogate):

1. Ask **one question at a time**, each phrased to capture intent, never implementation.
2. Offer a **recommended default** — and make that default exactly the assumption the one-shot path would have made today (the `(needs review)` guess). This is the unifying rule: high confidence skips the question; low-confidence interactive asks with today's guess as the default; non-interactive takes that same default silently.
3. Use the project's plain `[Y/n]`-style prompt idiom with the default shown in the line — never a special UI widget (the skill must also run on Claude.ai). Wait for the answer before asking the next question.

```
◆ One quick question before I draft this
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

  This reads as ambiguous: is "export broken" a bug in existing
  export, or a request for a new export format?

  ⚡ Recommended: bug (something that used to work now fails)

  Type — [bug] / feature / improvement:
```

If the user accepts the default (empty answer or confirmation), record the field at its defaulted value but **raise its confidence to `medium`** — the human confirmed it. If the user overrides, use their answer at `high` confidence. Either way, fold the answer into the Step 4 draft; do not re-ask in the preview.

After at most two questions, proceed to Step 4 regardless — this is targeted disambiguation, not an open-ended interview.

## Non-interactive contexts (never block)

In Batch mode and any auto/non-interactive context, **skip this step entirely**. Proceed straight to Step 4, draft with the defaulted assumptions, and mark those fields `(needs review)` in the body exactly as today. The skill never pauses for input outside interactive Create mode.
