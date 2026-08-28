# Step 3 — Inline duplicate scoring (fallback)

**Read this file only when `gi-dup-score.py` cannot run** — no `python3`, exit 2,
exit 4, or unparsable stdout. When the script exits 0 its output is the whole
answer and nothing here applies. Exit 3 is an invalid request/config and exit 4
means the backlog was unreadable, never empty; both are handled at the call site
in `SKILL.md`, not here.

## Scoring the fetched backlog

`SKILL.md` has already validated `duplicate_detection.backlog_limit` and fetched
`fallback_issues` with a `backlog_limit + 1` truncation probe. From there:

Parse `fallback_issues` as JSON, score only its first `backlog_limit` records,
and report the scan as truncated when the extra record exists. Quoting the
validated digits-only value is mandatory; never use `eval`, shell re-parsing, or
an issue-derived value on that command line.

## The canonical rules

Apply the same rules `gi-dup-score.py` implements, so a degraded run and a
scripted run reach the same verdict:

- NFKC/case-fold tokens.
- One minimum-length policy and one additive stop-word policy.
- Fixed precedence: phrase → title-overlap → keyword.
- Each payment derived only from newly consumed item tokens.
- One same-type payment.
- The configured weights and thresholds, with the phrase per-token weight
  greater than or equal to the title-overlap weight — otherwise removing
  evidence with an extra stop word could move a token into a higher-paying
  lower-precedence signal.
- Internal batch pairs applied in both directions, keeping the stronger.

## Medium-band judgement is unchanged

The fallback uses the same bounded medium-judgement protocol `SKILL.md` states
for the scripted path: the tri-state `decision`, identity matching, fail-safe
ambiguity on any missing, duplicate, malformed, incomplete, unknown-decision,
wrong-identity, or failed-agent verdict. A candidate outside the bounded LLM
slice remains a possible-duplicate warning — never silently cleared.
