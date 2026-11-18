# Model Suggestion — Reference

How `/issue-creator` suggests a cost-effective model + thinking level for each
issue, and how it manages the local CursorBench data cache. This procedure
runs when `model_suggestion.enabled` is `true` in `.idd.yml`
(default: `true`). When disabled, every step here is skipped
silently — create the issue without a model suggestion.

The suggestion is **advisory metadata**, like priority and effort. It never
blocks issue creation: any fetch, cache, or parse failure degrades to a warning
and the skill continues (mirroring the image-upload degradation pattern).

## Data source and cache file

| Item | Value |
|------|-------|
| Source | CursorBench — `https://cursor.com/cursorbench` (the version is the data's `source` field) |
| Cache file | `{cache_dir}/model-data-{YYYY-MM-DD}.json` — **user-level, dated, one per machine** |
| Cache dir | `{cache_dir}` = `$IDD_CACHE_DIR`, else `${XDG_CACHE_HOME:-$HOME/.cache}/idd` |
| Bundled seed | `{skill_dir}/templates/model-data.json` — undated, ships inside the skill, read-only |
| Staleness threshold | 7 days (compared against the cache's `last_fetched`) |

The model-suggestion cache is **user-level data — it does not vary by
repository.** One cache in the user's cache directory serves every repo on the
machine, so users never re-seed or maintain duplicate caches across projects.
`{skill_dir}` is the directory of the installed `issue-creator` skill (the
dirname of its `SKILL.md`); it is only ever **read**, for the bundled seed.
`{cache_dir}` is where the cache is written (`gi-model-cache.py --cache-dir`
overrides it; a `{cache_dir}` that is itself a symlink is refused).

**The cache filename carries the date it was last updated**
(`model-data-{YYYY-MM-DD}.json`, e.g. `model-data-2026-11-17.json`). That date is
the date portion of the cache's own `last_fetched`, so the two can never
disagree, and a glance at the filename tells you whether a refresh is likely
needed without opening the file.

The cache is **never per-repo** — not under `.idd/` — and is **never
committed**: it is regenerable runtime state, not project state. It is also
**never inside the skill folder**: a plugin update replaces the versioned plugin
directory, an `asm install` replaces the copy, and `claude --plugin-dir .` points
the skill folder at a git checkout, where a written cache would be an untracked
file. `{cache_dir}` sits outside all of them.

Because the cache lives outside the skill folder, it survives plugin updates
and reinstalls, and a reinstall can ship a newer bundled seed. The lifecycle
compares the two by `last_fetched`: when the seed's date is **newer** than the
cache's, the seed wins and is written to `{cache_dir}` (pruning the older copy);
otherwise — including a tie — the cache is kept, so a refreshed cache is never
overwritten by an older seed.

The cache file mirrors the `triage.json` / `analysis-<N>.json` JSON conventions:
a top-level ISO-8601 (`Z`) `last_fetched` timestamp, JSON formatted for readable
diffs, and a full overwrite on refresh (never append).

### Cache file schema

```json
{
  "schema_version": 1,
  "source": "CursorBench 4.0",
  "source_url": "https://cursor.com/cursorbench",
  "last_fetched": "2026-11-17T08:17:15Z",
  "providers": {
    "openai":    { "families": ["GPT-5.6 Sol", "GPT-5.6 Terra", "GPT-5.6 Luna"], "models": [ { "name": "...", "family": "...", "thinking": "...", "score": 0.0, "cost_per_task_usd": 0.0, "tokens_per_task": 0 } ] },
    "anthropic": { "families": ["Fable 5.2", "Opus 5.5", "Sonnet 5.5", "Fable 5.1", "Haiku 5.5", "Opus 5", "Sonnet 5"], "models": [ { "name": "...", "family": "...", "thinking": "...", "score": 0.0, "cost_per_task_usd": 0.0, "tokens_per_task": 0 } ] }
  },
  "complexity_mapping": {
    "XS": { "label": "trivial", "openai": "...", "anthropic": "..." }
  }
}
```

**Per-task cost semantics.** A `complexity_mapping` band names two *alternative*
picks (one OpenAI, one Anthropic) — you pick one, not both. It therefore carries
**no** cost field of its own: a single summed figure would misrepresent the cost
of either pick (roughly doubling it). Per-task cost is instead rendered
**per-model**, sourced from each named model's own `cost_per_task_usd` in the
`providers` block, so a band shows two independent figures — one per pick,
never their sum.

## Cache lifecycle (runs once at skill start, after config load)

Only when `model_suggestion.enabled` is `true`.

> **This section is refresh- and debug-only reading.** The default run does not
> execute it: SKILL.md's *Configuration* step runs
> `references/scripts/gi-model-cache.py`, which performs the whole lifecycle —
> locate, seed, prune, age against the TTL — and returns `persisted`, `state`, `stale`,
> `age_days`, `data_version`, `data_date`, and the resolved `bands` mapping.
> What follows is the authoritative description of what that script does, the
> procedure to run by hand when it degrades, and the refresh path (which still
> needs WebFetch and therefore still needs an agent).

### Locating the cache (user-level, dated)

The cache lives in `{cache_dir}`, not in the skill folder and not per-repo. The
script lists `{cache_dir}` for `model-data-*.json` and selects the newest by its
filename date; by hand, that is:

```bash
cache_dir="${IDD_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/idd}"
# Newest user-level cache, or empty if none exists yet.
cache="$(ls -1 "$cache_dir"/model-data-*.json 2>/dev/null | sort | tail -n1)"
```

The filename date (`model-data-{YYYY-MM-DD}.json`) is the human-glance signal;
the authoritative staleness check is always the cache's internal `last_fetched`.
If several dated files are somehow present, the newest wins and the lifecycle
prunes the rest on the next write (see *Refresh procedure*).

A cache file that does not parse or fails validation is treated as a **miss**,
never used — it is stored fetched content. The script prints a `⚠` line naming
it, so the substitution is never silent, and reseeds from the bundled seed,
which prunes the bad copy. Exit 4 is reserved for state 4 below: no valid cache
**and** no readable seed.

When `{cache_dir}` is unusable (unwritable, a symlink, not a directory, or no
absolute `$HOME`), nothing is written: the seed is served from memory for this
run, the script exits 0 with `persisted: false` and `cache_file: null`, and
prints a `⚠` line. Suggestions keep working; only the cache is skipped.

### States

1. **Cache present and fresh** (`last_fetched` ≤ `cache_ttl_days`, default 7) →
   use it silently:
   ```
   ○ Using cached model data (CursorBench {data_version}, fetched {age}).
   ```

2. **Cache present but stale** (`last_fetched` older than the threshold) → warn
   and offer a refresh. Use the stale data if the user declines or the refresh
   fails:
   ```
   ⚠ Model data is {age} old (CursorBench {data_version}).
     Refresh now? [y/N]
   ```
   <!-- auto:no -->

3. **Cache missing, invalid, or older than the seed** (script
   `state: "seeded"`) → seed it from the bundled `templates/model-data.json`
   into `{cache_dir}` under a dated name, then offer a fresh fetch. By hand:
   ```bash
   # Date portion of the seed's own last_fetched — NOT today's date — so the
   # filename date and the cache's last_fetched can never disagree.
   seed_date="$(grep -o '"last_fetched": *"[0-9-]\{10\}' \
     "$skill_dir/templates/model-data.json" | grep -o '[0-9-]\{10\}$')"
   mkdir -p "$cache_dir"
   cp "$skill_dir/templates/model-data.json" \
      "$cache_dir/model-data-${seed_date}.json"
   ```
   ```
   ○ Seeded model data from bundled CursorBench {data_version} snapshot.
     Fetch the latest now? [y/N]
   ```
   <!-- auto:no -->

4. **No valid cache and bundled seed also missing** (script exit 4) → emit the rich error
   `Model data unavailable` from `references/error-messages.md`, disable
   suggestions for this run, and continue creating the issue without them.

In auto mode (`references/docs/auto-mode.md` — `--auto` or `IDD_AUTO_MODE=1`), never prompt: use cached or seeded
data as-is, log staleness as a warning, and skip the fetch.

### Forcing a refresh

`/issue-creator … --refresh-model-data` refreshes the cache **unconditionally**,
regardless of staleness, so users can pull the latest CursorBench data on
demand. It runs the *Refresh procedure* below before issue creation, then
proceeds normally. The flag is honored even under `IDD_AUTO_MODE=1` (an explicit
request overrides the no-prompt-no-fetch default); a failed forced refresh
degrades to a warning and the existing cache, like any other refresh.

The bundled seed changes only when the skill is reinstalled, so the procedure
below is how a run gets fresher data.

### Refresh procedure

When a refresh runs (accepted prompt, fresh-seed fetch, or `--refresh-model-data`),
fetch the source URL with the **WebFetch** tool and ask it to extract the model
scoring tables. On success:

1. Build the parsed data with a new `last_fetched` set to the current time.
2. Write it to a scratch file with the Write tool — **never** paste fetched web
   content into a command line — and install it:

   ```bash
   python3 references/scripts/gi-model-cache.py --skill-dir "$skill_dir" --install .idd/cache/model-data-new.json
   ```

   The script names the file from the date portion of the payload's own
   `last_fetched` and **deletes every other `model-data-*.json` in
   `{cache_dir}`**, so exactly one dated cache remains and the filename can never
   disagree with the timestamp inside it. Exit 3 means the payload is not a
   model-data document — stop and warn; the old cache is untouched.
   `persisted: false` means `{cache_dir}` was unusable: the refreshed data is
   used for this run only. Delete the scratch file afterwards.

By hand, when the script is unavailable: write the parsed data to
`$cache_dir/model-data-{YYYY-MM-DD}.json` using the date portion of the new
`last_fetched`, then delete every other `model-data-*.json` in `$cache_dir`.

On any failure (network, parse, empty result), warn with
`Model data refresh failed` from `references/error-messages.md` and keep the
existing cached/seeded data and its dated file.

> WebFetch is the only call this skill makes outside GitHub, and only on
> explicit opt-in or `--refresh-model-data`. The bundled seed guarantees the feature
> works offline and on first run.

## Complexity classification

The suggestion is keyed off the **effort** estimate the skill already produces
for the `## Metadata` section — the existing **XS / S / M / L / XL** scale. Do
**not** introduce a parallel classifier or reuse the analysis-pipeline
`trivial…complex` scale.

When effort has not yet been decided, estimate it from the issue using these
signals, then pick the highest band any signal reaches. Count only the
requirements the reporter stated, not the 3–5 criteria Step 4 generates —
those would put every issue at M or above:

| Effort | Description length | Stated requirements | Scope signals |
|--------|--------------------|--------------------|----------------|
| XS | one line | 0–1 | typo, config, single value |
| S  | a short paragraph | 2–3 | one component, no new surface |
| M  | a few paragraphs | 3–5 | a few files / one subsystem |
| L  | detailed, multi-part | 5–8 | new capability, several subsystems |
| XL | very large / multi-feature | 8+ | new subsystem, cross-cutting, migration |

## Complexity → model mapping

The picks are the effort band's `openai` and `anthropic` entries in the cache's
`complexity_mapping`; render both per *the two-model rendering rule* under
**Rendering** below. Each pick's per-task cost is that model's own
`cost_per_task_usd` in `providers` — the two are alternatives, never summed.
The bundled seed `templates/model-data.json` holds the current picks; they are
not copied here because a refresh replaces them, so always read them from the
cache file. If the cache omits a band, fall back to the nearest lower band and
note `(needs review)`.

## Rendering the suggestion

**The two-model rendering rule (single home).** The suggestion appears in **two**
places — the Step 5 ephemeral preview and the durable issue-body `## Metadata`
line. In both, it **always names exactly two models — one OpenAI model and one
Anthropic model — joined by ` · ` (OpenAI first)** — `{openai_model} · {anthropic_model}`.
The two names are read from the effort band's `openai` and
`anthropic` entries in the cache. Both providers are always present; **never**
collapse it to a single model or a single provider. Every mention of this rule
elsewhere points here.

In the **ephemeral preview** (Step 5), append each model's own per-task cost in
parentheses immediately after it, read from that model's `cost_per_task_usd` in
the `providers` block — `{openai_model} (~${openai_cost}/task) · {anthropic_model}
(~${anthropic_cost}/task)`. The two costs are independent (the picks are alternatives) and
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
  ⚡ Model:  {openai_model} (~${openai_cost}/task) · {anthropic_model} (~${anthropic_cost}/task)
  Labels:   feature, settings
  Criteria: 4 acceptance criteria generated (medium)
```

### Issue body `## Metadata` (durable, advisory + dated)

Add a `**Suggested model:**` line after `**Effort:**` in the body. It is
**dated and labelled advisory** so its staleness is self-documenting:

```markdown
**Suggested model:** {openai_model} · {anthropic_model} _(CursorBench {data_version}, {data_date} — advisory)_
```

The template placeholders fill from the cache: `{openai_model}` and
`{anthropic_model}` are the effort band's `openai` / `anthropic` entries,
`{data_version}` is the version portion of `source` (e.g. `4.0` from
`CursorBench 4.0` — do not repeat the `CursorBench` prefix), and `{data_date}` is
the date portion of `last_fetched`.
This is the one piece of externally-derived data the Output Contract admits
into the body (**Output Contract** in `SKILL.md`): it is advisory metadata, like
effort, and its date label shows how stale it is.

When the feature is disabled, omit the `**Suggested model:**` line entirely and
do not render the preview `⚡ Model:` line.

## Configuration

```yaml
# Suggest a cost-effective model + thinking level per issue (CursorBench data)
model_suggestion:
  # Master switch. When false, all model-suggestion behaviour is skipped.
  enabled: true
  # Source URL refreshed into the user-level model-data-<date>.json cache
  data_url: "https://cursor.com/cursorbench"
  # Days before the cache is considered stale
  cache_ttl_days: 7
```

Force a refresh at any time, independent of `cache_ttl_days`, with
`/issue-creator … --refresh-model-data`.

See `references/docs/config-schema.md` for the `model_suggestion` schema and its Defaults
Table entries; the whole-schema Config Section Map is in the full document at
[config-schema.md](https://github.com/luongnv89/idd/blob/main/docs/config-schema.md).
