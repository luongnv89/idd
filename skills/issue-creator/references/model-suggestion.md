# Model Suggestion — Reference

How `/issue-creator` suggests a cost-effective model + thinking level for each
issue, and how it manages the local CursorBench data cache. This procedure
runs when `model_suggestion.enabled` is `true` in `.gitissue.yml`
(default: `true`). When disabled, every step here is skipped
silently — issue creation behaves exactly as before.

The suggestion is **advisory metadata**, like priority and effort. It never
blocks issue creation: any fetch, cache, or parse failure degrades to a warning
and the skill continues (mirroring the image-upload degradation pattern).

## Data source and cache file

| Item | Value |
|------|-------|
| Source | CursorBench 3.1 — `https://cursor.com/cursorbench` |
| Cache file | `.gitissue/model-data.json` (committed with other `.gitissue/` state) |
| Bundled seed | `templates/model-data.json` (ships inside the skill) |
| Staleness threshold | 7 days (compared against the cache's `last_fetched`) |

The cache file mirrors the `.gitissue/triage.json` / `analysis-<N>.json`
conventions: a top-level ISO-8601 (`Z`) timestamp, JSON formatted for readable
git diffs, and a full overwrite on refresh (never append).

### Cache file schema

```json
{
  "schema_version": 1,
  "source": "CursorBench 3.1",
  "source_url": "https://cursor.com/cursorbench",
  "last_fetched": "2026-06-12T00:00:00Z",
  "providers": {
    "openai":    { "family": "GPT-5.5", "models": [ { "name": "...", "thinking": "...", "score": 0.0, "cost_per_task_usd": 0.0, "tokens_per_task": 0 } ] },
    "anthropic": { "families": ["Fable 5", "Opus 4.7", "Opus 4.8"], "models": [ { "name": "...", "family": "...", "thinking": "...", "score": 0.0, "cost_per_task_usd": 0.0, "tokens_per_task": 0 } ] }
  },
  "complexity_mapping": {
    "XS": { "label": "trivial", "openai": "GPT-5.5 Low", "anthropic": "Opus 4.7 Low", "est_cost_per_task_usd": 3.06 }
  }
}
```

## Cache lifecycle (runs once at skill start, after config load)

Only when `model_suggestion.enabled` is `true`:

1. **Cache present and fresh** (`last_fetched` ≤ 7 days old) → use it silently:
   ```
   ○ Using cached model data (CursorBench 3.1, fetched {age}).
   ```

2. **Cache present but stale** (`last_fetched` > 7 days old) → warn and offer a
   refresh. Use the stale data if the user declines or the refresh fails:
   ```
   ⚠ Model data is {age} old (CursorBench 3.1).
     Refresh now? [y/N]
   ```

3. **Cache missing** → seed it from the bundled `templates/model-data.json`,
   then offer a fresh fetch:
   ```bash
   mkdir -p .gitissue
   cp "{skill_dir}/templates/model-data.json" .gitissue/model-data.json
   ```
   ```
   ○ Seeded model data from bundled CursorBench 3.1 snapshot.
     Fetch the latest now? [y/N]
   ```

4. **Bundled seed also missing** → emit the rich error
   `Model data unavailable` from `references/error-messages.md`, disable
   suggestions for this run, and continue creating the issue without them.

In auto-pilot contexts (`IDD_AUTO_MODE=1`), never prompt: use cached or seeded
data as-is, log staleness as a warning, and skip the fetch.

### Refresh procedure

When the user accepts a refresh (or chooses to fetch fresh seed data), fetch the
source URL with the **WebFetch** tool and ask it to extract the model scoring
tables. On success, overwrite `.gitissue/model-data.json` with the parsed data
and a new `last_fetched` set to the current time. On any failure (network,
parse, empty result), warn with `Model data refresh failed` from
`references/error-messages.md` and keep the existing cached/seeded data.

> WebFetch is the only network call this skill makes, and only on explicit
> opt-in. The bundled seed guarantees the feature works offline and on first run.

## Complexity classification (AC #4)

The suggestion is keyed off the **effort** estimate the skill already produces
for the `## Metadata` section — the existing **XS / S / M / L / XL** scale. Do
**not** introduce a parallel classifier or reuse the analysis-pipeline
`trivial…complex` scale.

When effort has not yet been decided, estimate it from the issue using these
signals, then pick the highest band any signal reaches:

| Effort | Description length | Acceptance criteria | Scope signals |
|--------|--------------------|--------------------|----------------|
| XS | one line | 0–1 | typo, config, single value |
| S  | a short paragraph | 2–3 | one component, no new surface |
| M  | a few paragraphs | 3–5 | a few files / one subsystem |
| L  | detailed, multi-part | 5–8 | new capability, several subsystems |
| XL | very large / multi-feature | 8+ | new subsystem, cross-cutting, migration |

## Complexity → model mapping (AC #5)

Map the effort band to exactly **one** OpenAI model and **one** Anthropic
model, using the cache's `complexity_mapping` (seed values shown):

| Effort | OpenAI | Anthropic | Est. cost/task |
|--------|--------|-----------|----------------|
| XS | GPT-5.5 Low | Opus 4.7 Low | $3.06 |
| S  | GPT-5.5 Medium | Opus 4.8 Low | $5.15 |
| M  | GPT-5.5 High | Opus 4.8 Medium | $7.42 |
| L  | GPT-5.5 Extra High | Opus 4.7 Extra High | $11.48 |
| XL | GPT-5.5 Extra High | Fable 5 Max | $22.39 |

Always read the mapping from the cache file, not from this table — the table is
the seed snapshot and may be refreshed. If the cache omits a band, fall back to
the nearest lower band and note `(needs review)`.

## Rendering the suggestion (AC #6)

The suggestion appears in **two** places.

### Step 5 preview (ephemeral)

Add a `⚡ Model:` line to the `◆ Issue Preview` block:

```
◆ Issue Preview
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Type:     feature (high)
  Title:    Add dark mode toggle to settings
  Effort:   M
  ⚡ Model:  GPT-5.5 High · Opus 4.8 Medium  (~$7.42/task)
  Labels:   feature, settings
  Criteria: 4 acceptance criteria generated (medium)
```

### Issue body `## Metadata` (durable, advisory + dated)

Add a `**Suggested model:**` line after `**Effort:**` in the body. It is
**dated and labelled advisory** so its staleness is self-documenting:

```markdown
**Suggested model:** GPT-5.5 High · Opus 4.8 Medium _(CursorBench 3.1, 2026-06-12 — advisory)_
```

The date is the cache's `last_fetched` (date portion). This is the one piece of
externally-derived data the Output Contract admits into the body — see the
**Output Contract** note in `SKILL.source.md`, which records why it is permitted
(advisory metadata, like effort) and how the date label mitigates staleness.

When the feature is disabled, omit the `**Suggested model:**` line entirely and
do not render the preview `⚡ Model:` line — neither the body nor the preview
changes from the pre-feature behaviour.

## Configuration (AC #7)

```yaml
# Suggest a cost-effective model + thinking level per issue (CursorBench data)
model_suggestion:
  # Master switch. When false, all model-suggestion behaviour is skipped.
  enabled: true
  # Source URL refreshed into .gitissue/model-data.json
  data_url: "https://cursor.com/cursorbench"
  # Days before the cache is considered stale
  cache_ttl_days: 7
```

See `references/docs/config-schema.md` for the full schema, the Config Section Map, and the
Defaults Table entries.
