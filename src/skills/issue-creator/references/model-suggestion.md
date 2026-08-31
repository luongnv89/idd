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
| Source | CursorBench 3.2 — `https://cursor.com/cursorbench` |
| Cache file | `{skill_dir}/model-data-{YYYY-MM-DD}.json` — **skill-level, dated, one per machine** |
| Bundled seed | `{skill_dir}/templates/model-data.json` — undated, ships inside the skill |
| Staleness threshold | 7 days (compared against the cache's `last_fetched`) |

The model-suggestion cache is **skill-level data — it does not vary by
repository.** One cache under the installed skill folder serves every repo on the
machine, so users never re-seed or maintain duplicate caches across projects.
`{skill_dir}` is the directory of the installed `issue-creator` skill (the
dirname of its `SKILL.md`).

**The cache filename carries the date it was last updated**
(`model-data-{YYYY-MM-DD}.json`, e.g. `model-data-2026-08-31.json`). That date is
the date portion of the cache's own `last_fetched`, so the two can never
disagree, and a glance at the filename tells you whether a refresh is likely
needed without opening the file.

The cache is **not** stored per-repo under `.gitissue/` and is **never
committed**: it is regenerable runtime state, not project state. It lives at the
**skill root**, never inside `templates/` — `templates/` ships only the undated
seed, and the build copies that directory wholesale, so runtime state must stay
out of it.

> **Upgrade note.** Reinstalling the skill (`asm install`, or a manual copy)
> replaces the skill folder, so the dated cache is cleared on upgrade. This is
> self-healing, not data loss: the freshly-installed seed reseeds the lifecycle
> below (and is usually newer than the cache it replaced), and a refresh is
> offered on the next run.

The cache file mirrors the `triage.json` / `analysis-<N>.json` JSON conventions:
a top-level ISO-8601 (`Z`) `last_fetched` timestamp, JSON formatted for readable
diffs, and a full overwrite on refresh (never append).

### Cache file schema

```json
{
  "schema_version": 1,
  "source": "CursorBench 3.2",
  "source_url": "https://cursor.com/cursorbench",
  "last_fetched": "2026-08-31T00:00:00Z",
  "providers": {
    "openai":    { "families": ["GPT-5.6 Sol", "GPT-5.6 Terra", "GPT-5.6 Luna", "GPT-5.5"], "models": [ { "name": "...", "family": "...", "thinking": "...", "score": 0.0, "cost_per_task_usd": 0.0, "tokens_per_task": 0 } ] },
    "anthropic": { "families": ["Fable 5", "Opus 5", "Opus 4.8", "Sonnet 5"], "models": [ { "name": "...", "family": "...", "thinking": "...", "score": 0.0, "cost_per_task_usd": 0.0, "tokens_per_task": 0 } ] }
  },
  "complexity_mapping": {
    "XS": { "label": "trivial", "openai": "GPT-5.6 Sol Low", "anthropic": "Opus 5 Low" }
  }
}
```

**Per-task cost semantics.** A `complexity_mapping` band names two *alternative*
picks (one OpenAI, one Anthropic) — you pick one, not both. It therefore carries
**no** cost field of its own: a single summed figure would misrepresent the cost
of either pick (roughly doubling it). Per-task cost is instead rendered
**per-model**, sourced from each named model's own `cost_per_task_usd` in the
`providers` block. So the M band's cost is `GPT-5.6 Sol High` → `$2.79` and
`Opus 5 Medium` → `$3.29`, shown as two independent figures — never their sum.

## Cache lifecycle (runs once at skill start, after config load)

Only when `model_suggestion.enabled` is `true`.

> **This section is refresh- and debug-only reading.** The default run does not
> execute it: SKILL.md's *Configuration* step runs
> `shared/scripts/gi-model-cache.py`, which performs the whole lifecycle —
> locate, seed, prune, age against the TTL — and returns `state`, `stale`,
> `age_days`, `data_version`, `data_date`, and the resolved `bands` mapping.
> What follows is the authoritative description of what that script does, the
> procedure to run by hand when it degrades, and the refresh path (which still
> needs WebFetch and therefore still needs an agent).

### Locating the cache (skill-level, dated)

The cache lives in the installed skill folder, not per-repo. The script lists
the skill root for `model-data-*.json` and selects the newest by its filename
date; by hand, that is:

```bash
# Newest skill-level cache, or empty if none exists yet.
cache="$(ls -1 "$skill_dir"/model-data-*.json 2>/dev/null | sort | tail -n1)"
```

The filename date (`model-data-{YYYY-MM-DD}.json`) is the human-glance signal;
the authoritative staleness check is always the cache's internal `last_fetched`.
If several dated files are somehow present, the newest wins and the lifecycle
prunes the rest on the next write (see *Refresh procedure*).

A cache file that exists but does not parse is **not** treated as missing: the
script exits 4 and says so rather than seeding over it, because reseeding there
would silently replace the user's refreshed data with the bundled snapshot and
report success. On exit 4 the skill disables model suggestions for the run and
creates the issue without them — the same outcome as state 4 below.

> **Per-repo legacy cache (AC7).** A pre-existing `.gitissue/model-data.json`
> from an older skill version is **ignored** — the skill neither reads nor
> writes it, so model suggestions keep working unchanged. It is stale project
> state, safe to delete; the skill does not touch or migrate it.

### States

1. **Cache present and fresh** (`last_fetched` ≤ `cache_ttl_days`, default 7) →
   use it silently:
   ```
   ○ Using cached model data (CursorBench 3.2, fetched {age}).
   ```

2. **Cache present but stale** (`last_fetched` older than the threshold) → warn
   and offer a refresh. Use the stale data if the user declines or the refresh
   fails:
   ```
   ⚠ Model data is {age} old (CursorBench 3.2).
     Refresh now? [y/N]
   ```

3. **Cache missing** (script `state: "seeded"`) → seed it from the bundled
   `templates/model-data.json` into the skill folder under a dated name, then
   offer a fresh fetch. By hand:
   ```bash
   # Date portion of the seed's own last_fetched — NOT today's date — so the
   # filename date and the cache's last_fetched can never disagree (AC5).
   seed_date="$(grep -o '"last_fetched": *"[0-9-]\{10\}' \
     "$skill_dir/templates/model-data.json" | grep -o '[0-9-]\{10\}$')"
   cp "$skill_dir/templates/model-data.json" \
      "$skill_dir/model-data-${seed_date}.json"
   ```
   ```
   ○ Seeded model data from bundled CursorBench 3.2 snapshot.
     Fetch the latest now? [y/N]
   ```

4. **Bundled seed also missing** (script exit 4) → emit the rich error
   `Model data unavailable` from `references/error-messages.md`, disable
   suggestions for this run, and continue creating the issue without them.

In auto mode (`docs/auto-mode.md` — `--auto` or `IDD_AUTO_MODE=1`), never prompt: use cached or seeded
data as-is, log staleness as a warning, and skip the fetch.

### Forcing a refresh (AC6)

`/issue-creator … --refresh-model-data` refreshes the cache **unconditionally**,
regardless of staleness, so users can pull the latest CursorBench data on
demand. It runs the *Refresh procedure* below before issue creation, then
proceeds normally. The flag is honored even under `IDD_AUTO_MODE=1` (an explicit
request overrides the no-prompt-no-fetch default); a failed forced refresh
degrades to a warning and the existing cache, like any other refresh.

> **Automated seed refresh (CI).** The bundled `templates/model-data.json`
> snapshot itself is refreshed weekly by this repository's
> `.github/workflows/model-data-refresh.yml`, which skips while the seed is
> younger than `cache_ttl_days` and pushes a new snapshot only when it is
> stale. That automation updates installed skill copies only via skill
> reinstalls — the manual procedure below remains the runtime fallback.

### Refresh procedure

When a refresh runs (accepted prompt, fresh-seed fetch, or `--refresh-model-data`),
fetch the source URL with the **WebFetch** tool and ask it to extract the model
scoring tables. On success:

1. Build the parsed data with a new `last_fetched` set to the current time.
2. Write it to a scratch file with the Write tool — **never** paste fetched web
   content into a command line — and install it:

   ```bash
   python3 shared/scripts/gi-model-cache.py --skill-dir "$skill_dir" --install .gitissue/cache/model-data-new.json
   ```

   The script names the file from the date portion of the payload's own
   `last_fetched` and **deletes every other `model-data-*.json` in the skill
   folder**, so exactly one dated cache remains and the filename can never
   disagree with the timestamp inside it. Exit 3 means the payload is not a
   model-data document — stop and warn; the old cache is untouched. Delete the
   scratch file afterwards.

By hand, when the script is unavailable: write the parsed data to
`$skill_dir/model-data-{YYYY-MM-DD}.json` using the date portion of the new
`last_fetched`, then delete every other `model-data-*.json` in the skill folder.

On any failure (network, parse, empty result), warn with
`Model data refresh failed` from `references/error-messages.md` and keep the
existing cached/seeded data and its dated file.

> WebFetch is the only network call this skill makes, and only on explicit
> opt-in or `--refresh-model-data`. The bundled seed guarantees the feature
> works offline and on first run.

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

Map the effort band to its `openai` and `anthropic` entries in the cache's
`complexity_mapping` (seed values shown), then render both per *the two-model
rendering rule* under **Rendering** below:

Each cell shows the pick's own per-task cost — the two are alternatives, so the
costs are independent, never summed:

| Effort | OpenAI (cost/task) | Anthropic (cost/task) |
|--------|--------------------|-----------------------|
| XS | GPT-5.6 Sol Low ($1.01) | Opus 5 Low ($2.55) |
| S  | GPT-5.6 Sol Medium ($1.95) | Opus 5 Low ($2.55) |
| M  | GPT-5.6 Sol High ($2.79) | Opus 5 Medium ($3.29) |
| L  | GPT-5.6 Sol Extra High ($3.88) | Opus 5 Extra High ($7.35) |
| XL | GPT-5.6 Sol Max ($5.69) | Fable 5 Max ($17.32) |

Always read the mapping from the cache file, not from this table — the table is
the seed snapshot and may be refreshed. If the cache omits a band, fall back to
the nearest lower band and note `(needs review)`.

## Rendering the suggestion (AC #6)

**The two-model rendering rule (single home).** The suggestion appears in **two**
places — the Step 5 ephemeral preview and the durable issue-body `## Metadata`
line. In both, it **always names exactly two models — one OpenAI model and one
Anthropic model — joined by ` · ` (OpenAI first)** — e.g. `GPT-5.6 Sol High · Opus
5 Medium`. The two names are read from the effort band's `openai` and
`anthropic` entries in the cache. Both providers are always present; **never**
collapse it to a single model or a single provider. Every mention of this rule
elsewhere points here.

In the **ephemeral preview** (Step 5), append each model's own per-task cost in
parentheses immediately after it, read from that model's `cost_per_task_usd` in
the `providers` block — e.g. `GPT-5.6 Sol High (~$2.79/task) · Opus 5 Medium
(~$3.29/task)`. The two costs are independent (the picks are alternatives) and
are **never** added together. The durable `**Suggested model:**` body line omits
costs (it stays a lean, dated advisory of the two names).

### Step 5 preview (ephemeral)

Add a `⚡ Model:` line to the `◆ Issue Preview` block:

```
◆ Issue Preview
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  Type:     feature (high)
  Title:    Add dark mode toggle to settings
  Effort:   M
  ⚡ Model:  GPT-5.6 Sol High (~$2.79/task) · Opus 5 Medium (~$3.29/task)
  Labels:   feature, settings
  Criteria: 4 acceptance criteria generated (medium)
```

### Issue body `## Metadata` (durable, advisory + dated)

Add a `**Suggested model:**` line after `**Effort:**` in the body. It is
**dated and labelled advisory** so its staleness is self-documenting:

```markdown
**Suggested model:** GPT-5.6 Sol High · Opus 5 Medium _(CursorBench 3.2, 2026-08-31 — advisory)_
```

The template placeholders fill from the cache: `{openai_model}` and
`{anthropic_model}` are the effort band's `openai` / `anthropic` entries,
`{data_version}` is the version portion of `source` (e.g. `3.2` from
`CursorBench 3.2` — do not repeat the `CursorBench` prefix), and `{data_date}` is
the date portion of `last_fetched`.
This is the one piece of externally-derived data the Output Contract admits
into the body — see the
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
  # Source URL refreshed into the skill-level model-data-<date>.json cache
  data_url: "https://cursor.com/cursorbench"
  # Days before the cache is considered stale
  cache_ttl_days: 7
```

Force a refresh at any time, independent of `cache_ttl_days`, with
`/issue-creator … --refresh-model-data`.

See `docs/config-schema.md` for the `model_suggestion` schema and its Defaults
Table entries; the whole-schema Config Section Map is in the full document at
[config-schema.md](https://github.com/luongnv89/idd/blob/main/docs/config-schema.md).
